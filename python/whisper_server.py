#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import atexit
import json
import os
import multiprocessing
import platform
import re
import signal
import time
import sys
import threading
import traceback
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from math import inf, log10
from typing import Protocol, cast
import wave

HEALTHCHECK_REQUEST_PREFIX = "__KOTOTYPE_HEALTHCHECK__:"
HEALTHCHECK_RESPONSE_PREFIX = "__KOTOTYPE_HEALTHCHECK_OK__:"
CONTROL_MESSAGE_PREFIX = "__KOTOTYPE_CONTROL__:"
DEFAULT_CPU_MODEL_ID = "large-v3-turbo"
DEFAULT_MLX_MODEL_ID = "mlx-community/whisper-large-v3-turbo"
DEFAULT_TASK = "transcribe"
DEFAULT_NO_SPEECH_THRESHOLD = 0.6
DEFAULT_COMPRESSION_RATIO_THRESHOLD = 2.4
DEFAULT_AUTO_GAIN_ENABLED = True
DEFAULT_AUTO_GAIN_WEAK_THRESHOLD_DBFS = -18.0
DEFAULT_AUTO_GAIN_TARGET_PEAK_DBFS = -10.0
DEFAULT_AUTO_GAIN_MAX_DB = 18.0


class MlxCoreModule(Protocol):
    float16: object


class MlxModelHolderProtocol(Protocol):
    def get_model(self, path_or_hf_repo: str, dtype: object) -> object: ...


class MlxTranscribeModule(Protocol):
    ModelHolder: MlxModelHolderProtocol


class MlxWhisperModule(Protocol):
    def transcribe(
        self,
        audio: str,
        *,
        path_or_hf_repo: str,
        verbose: bool | None = None,
        temperature: float | tuple[float, ...] = (0.0, 0.2, 0.4, 0.6, 0.8, 1.0),
        compression_ratio_threshold: float | None = 2.4,
        logprob_threshold: float | None = -1.0,
        no_speech_threshold: float | None = 0.6,
        condition_on_previous_text: bool = True,
        initial_prompt: str | None = None,
        word_timestamps: bool = False,
        language: str | None = None,
        task: str = "transcribe",
        **decode_options,
    ) -> dict[str, object]: ...


def default_dictionary_path():
    return os.path.expanduser("~/Library/Application Support/koto-type/user_dictionary.json")


def setup_logging():
    log_dir = os.path.expanduser("~/Library/Application Support/koto-type")
    os.makedirs(log_dir, mode=0o700, exist_ok=True)
    tighten_file_permissions(log_dir, mode=0o700)

    log_file = os.path.join(log_dir, "server.log")
    if not os.path.exists(log_file):
        with open(log_file, "a", encoding="utf-8"):
            pass
    tighten_file_permissions(log_file)

    def log(message):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{timestamp}] [pid={os.getpid()}] {message}\n"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(log_line)

    return log_file, log


def default_server_state_path():
    return os.path.expanduser("~/Library/Application Support/koto-type/server_state.json")


def default_server_state_lock_path():
    return os.path.expanduser("~/Library/Application Support/koto-type/server_state.lock")


def parse_int(value, default):
    if value is None:
        return default

    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def pid_exists(pid):
    if pid <= 0:
        return False

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False

    return True


def start_parent_watchdog(parent_pid, log, cleanup, interval_seconds=1.0):
    if parent_pid <= 0:
        return None

    def _watch():
        while True:
            time.sleep(interval_seconds)
            if pid_exists(parent_pid):
                continue

            log(f"Parent process {parent_pid} no longer exists, shutting down server")
            try:
                cleanup()
            finally:
                os._exit(0)

    thread = threading.Thread(
        target=_watch,
        name="parent-watchdog",
        daemon=True,
    )
    thread.start()
    return thread


def load_server_state(path):
    default_state = {"active_pids": [], "loading_pids": [], "updated_at": None}
    if not os.path.exists(path):
        return default_state

    try:
        import json

        with open(path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
    except Exception:
        return default_state

    if not isinstance(loaded, dict):
        return default_state

    active_pids = loaded.get("active_pids", [])
    loading_pids = loaded.get("loading_pids", [])

    if not isinstance(active_pids, list):
        active_pids = []
    if not isinstance(loading_pids, list):
        loading_pids = []

    return {
        "active_pids": [int(pid) for pid in active_pids if isinstance(pid, int)],
        "loading_pids": [int(pid) for pid in loading_pids if isinstance(pid, int)],
        "updated_at": loaded.get("updated_at"),
    }


def save_server_state(path, state):
    import json

    state["updated_at"] = datetime.now().isoformat()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)


@contextmanager
def server_state_lock(lock_path):
    import fcntl

    lock_dir = os.path.dirname(lock_path)
    os.makedirs(lock_dir, exist_ok=True)
    lock_file = open(lock_path, "a+", encoding="utf-8")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()


def mutate_server_state(state_path, lock_path, mutator):
    with server_state_lock(lock_path):
        state = load_server_state(state_path)
        state["active_pids"] = [pid for pid in state["active_pids"] if pid_exists(pid)]
        state["loading_pids"] = [pid for pid in state["loading_pids"] if pid_exists(pid)]
        result = mutator(state)
        save_server_state(state_path, state)
        return result


def register_server_pid(state_path, lock_path, pid, max_active_servers):
    def mutator(state):
        if pid not in state["active_pids"]:
            state["active_pids"].append(pid)

        active_count = len(state["active_pids"])
        if active_count > max_active_servers:
            state["active_pids"] = [active_pid for active_pid in state["active_pids"] if active_pid != pid]
            state["loading_pids"] = [loading_pid for loading_pid in state["loading_pids"] if loading_pid != pid]
            return False, active_count - 1
        return True, active_count

    return mutate_server_state(state_path, lock_path, mutator)


def unregister_server_pid(state_path, lock_path, pid):
    def mutator(state):
        state["active_pids"] = [active_pid for active_pid in state["active_pids"] if active_pid != pid]
        state["loading_pids"] = [loading_pid for loading_pid in state["loading_pids"] if loading_pid != pid]
        return None

    mutate_server_state(state_path, lock_path, mutator)


def try_acquire_model_load_slot(state_path, lock_path, pid, max_parallel_model_loads):
    def mutator(state):
        loading = state["loading_pids"]
        if pid in loading:
            return True, len(loading)
        if len(loading) >= max_parallel_model_loads:
            return False, len(loading)
        loading.append(pid)
        return True, len(loading)

    return mutate_server_state(state_path, lock_path, mutator)


def release_model_load_slot(state_path, lock_path, pid):
    def mutator(state):
        state["loading_pids"] = [loading_pid for loading_pid in state["loading_pids"] if loading_pid != pid]
        return None

    mutate_server_state(state_path, lock_path, mutator)


def build_audio_filter_chain(enable_noise_reduction=True, use_nlm_denoise=False):
    filters = [
        "highpass=f=100",
        "lowpass=f=7800",
    ]

    if enable_noise_reduction:
        if use_nlm_denoise:
            # Non-local means denoise (stronger but not always available)
            filters.append("anlmdn=s=0.08:p=0.003")
        # Spectral denoise to suppress stationary noise (air conditioner, fan, etc.)
        filters.append("afftdn=nf=-26:tn=1")

    filters.extend(
        [
            "dynaudnorm=f=90:g=15:p=0.8",
            "acompressor=threshold=-21dB:ratio=2.8:attack=5:release=90",
        ]
    )
    return ",".join(filters)


def build_audio_filter_chain_candidates(enable_noise_reduction=True):
    if not enable_noise_reduction:
        return [build_audio_filter_chain(enable_noise_reduction=False)]

    return [
        build_audio_filter_chain(enable_noise_reduction=True, use_nlm_denoise=True),
        build_audio_filter_chain(enable_noise_reduction=True, use_nlm_denoise=False),
        build_audio_filter_chain(enable_noise_reduction=False),
    ]


def format_ffmpeg_error(error):
    stderr_output = getattr(error, "stderr", None)
    if isinstance(stderr_output, (bytes, bytearray)):
        return stderr_output.decode("utf-8", errors="ignore").strip()
    return str(error)


def run_preprocess_with_filter(ffmpeg_module, input_path, output_path, filter_chain):
    (
        ffmpeg_module.input(input_path)
        .output(
            output_path,
            acodec="pcm_s16le",
            ac=1,
            ar="16000",
            af=filter_chain,
        )
        .overwrite_output()
        .run(quiet=True)
    )


def apply_gain_to_wav(ffmpeg_module, input_path, output_path, gain_db):
    gain_filter_chain = f"volume={gain_db:.2f}dB,alimiter=limit=0.98"
    run_preprocess_with_filter(
        ffmpeg_module=ffmpeg_module,
        input_path=input_path,
        output_path=output_path,
        filter_chain=gain_filter_chain,
    )


def analyze_wav_peak_dbfs(wav_path):
    max_peak = 0

    with wave.open(wav_path, "rb") as wav_file:
        sample_width = wav_file.getsampwidth()
        channel_count = wav_file.getnchannels()

        if sample_width != 2:
            raise ValueError(
                f"Unsupported sample width for peak analysis: {sample_width * 8}-bit"
            )

        while True:
            frames = wav_file.readframes(4096)
            if not frames:
                break

            frame_count = len(frames) // (sample_width * channel_count)
            if frame_count <= 0:
                continue

            for frame_index in range(frame_count):
                offset = frame_index * sample_width * channel_count
                sample_bytes = frames[offset : offset + sample_width]
                sample_value = int.from_bytes(
                    sample_bytes,
                    byteorder="little",
                    signed=True,
                )
                abs_sample = abs(sample_value)
                if abs_sample > max_peak:
                    max_peak = abs_sample

    if max_peak <= 0:
        return -inf

    return 20.0 * log10(max_peak / 32767.0)


def determine_gain_for_weak_audio(
    peak_dbfs,
    weak_threshold_dbfs=-18.0,
    target_peak_dbfs=-10.0,
    max_gain_db=18.0,
):
    if peak_dbfs >= weak_threshold_dbfs:
        return 0.0

    required_gain = target_peak_dbfs - peak_dbfs
    if required_gain <= 0:
        return 0.0

    return min(required_gain, max_gain_db)


def build_vad_parameters(vad_threshold):
    strict_mode = parse_bool(os.environ.get("KOTOTYPE_VAD_STRICT", "1"), default=True)
    threshold_delta = 0.07 if strict_mode else 0.0
    effective_threshold = max(0.0, min(1.0, vad_threshold + threshold_delta))

    if strict_mode:
        min_speech_duration_ms = 320
        min_silence_duration_ms = 700
        speech_pad_ms = 80
    else:
        min_speech_duration_ms = 250
        min_silence_duration_ms = 500
        speech_pad_ms = 30

    return {
        "threshold": effective_threshold,
        "min_speech_duration_ms": min_speech_duration_ms,
        "min_silence_duration_ms": min_silence_duration_ms,
        "speech_pad_ms": speech_pad_ms,
    }


def tighten_file_permissions(path, mode=0o600):
    try:
        os.chmod(path, mode)
    except OSError:
        return


def cleanup_temporary_audio_files(paths, log):
    for path in paths:
        if not path or not os.path.exists(path):
            continue
        try:
            os.remove(path)
            log(f"Removed temporary audio file: {path}")
        except OSError as error:
            log(f"Failed to remove temporary audio file {path}: {error}")


def cleanup_transcription_audio_path(audio_path, original_audio_path, log):
    if not audio_path or audio_path == original_audio_path:
        return
    cleanup_temporary_audio_files([audio_path], log)


def audio_preprocess(
    input_path,
    log,
    ffmpeg_module=None,
    peak_analyzer=None,
    auto_gain_enabled=None,
    auto_gain_weak_threshold_dbfs=None,
    auto_gain_target_peak_dbfs=None,
    auto_gain_max_db=None,
):
    if parse_bool(
        os.environ.get("KOTOTYPE_SKIP_AUDIO_PREPROCESSING", "0"),
        default=False,
    ):
        log("Audio preprocessing skipped via KOTOTYPE_SKIP_AUDIO_PREPROCESSING")
        return input_path

    if ffmpeg_module is None:
        try:
            import ffmpeg as imported_ffmpeg

            ffmpeg_module = imported_ffmpeg
        except ImportError:
            log("ffmpeg-python not available, skipping preprocessing")
            return input_path

    if peak_analyzer is None:
        peak_analyzer = analyze_wav_peak_dbfs

    output_path = None
    boosted_output_path = None
    try:
        base, _ = os.path.splitext(input_path)
        output_path = f"{base}_processed.wav"
        boosted_output_path = f"{base}_processed_gain.wav"
        enable_noise_reduction = parse_bool(
            os.environ.get("KOTOTYPE_ENABLE_NOISE_REDUCTION", "1"),
            default=True,
        )
        if auto_gain_enabled is None:
            auto_gain_enabled = parse_bool(
                os.environ.get("KOTOTYPE_AUTO_GAIN_ENABLED", "1"),
                default=True,
            )
        if auto_gain_weak_threshold_dbfs is None:
            auto_gain_weak_threshold_dbfs = parse_float(
                os.environ.get("KOTOTYPE_AUTO_GAIN_WEAK_THRESHOLD_DBFS"),
                default=-18.0,
            )
        if auto_gain_target_peak_dbfs is None:
            auto_gain_target_peak_dbfs = parse_float(
                os.environ.get("KOTOTYPE_AUTO_GAIN_TARGET_PEAK_DBFS"),
                default=-10.0,
            )
        if auto_gain_max_db is None:
            auto_gain_max_db = parse_float(
                os.environ.get("KOTOTYPE_AUTO_GAIN_MAX_DB"),
                default=18.0,
            )

        auto_gain_max_db = max(0.0, auto_gain_max_db)
        if auto_gain_target_peak_dbfs <= auto_gain_weak_threshold_dbfs:
            auto_gain_target_peak_dbfs = min(
                -1.0,
                auto_gain_weak_threshold_dbfs + 1.0,
            )

        log(f"Preprocessing audio: {input_path} -> {output_path}")
        filter_candidates = build_audio_filter_chain_candidates(
            enable_noise_reduction=enable_noise_reduction
        )

        for index, filter_chain in enumerate(filter_candidates):
            if index == 0:
                log(f"Audio preprocess filter chain: {filter_chain}")
            else:
                log(f"Retry preprocess with fallback filter chain #{index}: {filter_chain}")
            try:
                run_preprocess_with_filter(
                    ffmpeg_module=ffmpeg_module,
                    input_path=input_path,
                    output_path=output_path,
                    filter_chain=filter_chain,
                )
                tighten_file_permissions(output_path)

                if auto_gain_enabled:
                    peak_dbfs = peak_analyzer(output_path)
                    gain_db = determine_gain_for_weak_audio(
                        peak_dbfs=peak_dbfs,
                        weak_threshold_dbfs=auto_gain_weak_threshold_dbfs,
                        target_peak_dbfs=auto_gain_target_peak_dbfs,
                        max_gain_db=auto_gain_max_db,
                    )
                    log(
                        f"Auto gain analysis: peak={peak_dbfs:.2f} dBFS, gain={gain_db:.2f} dB"
                    )

                    if gain_db > 0.0:
                        apply_gain_to_wav(
                            ffmpeg_module=ffmpeg_module,
                            input_path=output_path,
                            output_path=boosted_output_path,
                            gain_db=gain_db,
                        )
                        tighten_file_permissions(boosted_output_path)
                        os.replace(boosted_output_path, output_path)
                        tighten_file_permissions(output_path)
                        log(
                            f"Applied automatic gain for weak input: +{gain_db:.2f} dB"
                        )
                    else:
                        log("Auto gain skipped: input level is sufficient")

                log(f"Audio preprocessing completed: {output_path}")
                return output_path
            except Exception as error:
                log(
                    "Noise reduction preprocessing failed, trying next filter chain: "
                    f"{format_ffmpeg_error(error)}"
                )
                cleanup_temporary_audio_files(
                    [output_path, boosted_output_path],
                    log,
                )

        log("All preprocessing filter chains failed, using original audio")
        cleanup_temporary_audio_files([output_path, boosted_output_path], log)
        return input_path

    except Exception as e:
        log(f"Audio preprocessing failed: {str(e)}")
        cleanup_temporary_audio_files([output_path, boosted_output_path], log)
        return input_path


def parse_bool(value, default=True):
    if value is None:
        return default

    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default


def parse_optional_bool(value):
    if value is None:
        return None

    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return None


def parse_float(value, default):
    if value is None:
        return default

    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


def parse_optional_float(value):
    if value is None:
        return None

    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def should_retry_without_vad(error):
    message = str(error)
    return "silero_vad_v6.onnx" in message and (
        "NO_SUCHFILE" in message or "File doesn't exist" in message
    )


def transcribe_once(model, transcribe_kwargs, vad_filter, vad_parameters=None):
    kwargs = {
        "language": transcribe_kwargs["language"],
        "task": transcribe_kwargs["task"],
        "temperature": transcribe_kwargs["temperature"],
        "beam_size": transcribe_kwargs["beam_size"],
        "best_of": transcribe_kwargs["best_of"],
        "vad_filter": vad_filter,
        "word_timestamps": transcribe_kwargs["word_timestamps"],
        "initial_prompt": transcribe_kwargs["initial_prompt"],
        "no_speech_threshold": transcribe_kwargs["no_speech_threshold"],
        "compression_ratio_threshold": transcribe_kwargs["compression_ratio_threshold"],
    }
    if vad_filter and vad_parameters is not None:
        kwargs["vad_parameters"] = vad_parameters

    return model.transcribe(
        transcribe_kwargs["audio"],
        **kwargs,
    )


def transcribe_with_vad_fallback(
    model,
    transcribe_kwargs,
    vad_parameters,
    log,
    fallback_on_empty_vad=None,
):
    def build_text(segments):
        return " ".join(getattr(segment, "text", "") for segment in segments).strip()

    class DummyInfo:
        language = transcribe_kwargs["language"] or "ja"

    if fallback_on_empty_vad is None:
        fallback_on_empty_vad = parse_bool(
            os.environ.get("KOTOTYPE_FALLBACK_ON_EMPTY_VAD", "0"),
            default=False,
        )

    try:
        segments_iter, info = transcribe_once(
            model=model,
            transcribe_kwargs=transcribe_kwargs,
            vad_filter=True,
            vad_parameters=vad_parameters,
        )
        segments = list(segments_iter)
    except Exception as transcribe_error:
        log(f"Transcription error: {str(transcribe_error)}")
        log(f"Transcription error traceback: {traceback.format_exc()}")

        if should_retry_without_vad(transcribe_error):
            log("Retrying transcription with vad_filter=False due to missing VAD asset")
            try:
                segments_iter, info = transcribe_once(
                    model=model,
                    transcribe_kwargs=transcribe_kwargs,
                    vad_filter=False,
                )
                return list(segments_iter), info
            except Exception as fallback_error:
                log(f"Fallback transcription error: {str(fallback_error)}")
                log(f"Fallback transcription traceback: {traceback.format_exc()}")

        return [], DummyInfo()

    raw_text = build_text(segments)
    if raw_text:
        return segments, info

    if fallback_on_empty_vad:
        log("VAD-enabled transcription returned empty text; retrying without VAD")
        try:
            fallback_segments_iter, fallback_info = transcribe_once(
                model=model,
                transcribe_kwargs=transcribe_kwargs,
                vad_filter=False,
            )
            fallback_segments = list(fallback_segments_iter)
        except Exception as fallback_error:
            log(f"Fallback transcription error: {str(fallback_error)}")
            log(f"Fallback transcription traceback: {traceback.format_exc()}")
            log("Non-VAD retry failed; keeping empty result")
            return segments, info

        fallback_text = build_text(fallback_segments)
        if fallback_text:
            return fallback_segments, fallback_info

        log("Non-VAD transcription also returned empty text; keeping empty result")
        return fallback_segments, fallback_info

    log("VAD-enabled transcription returned empty text; keeping empty result")
    return segments, info


def post_process_text(text, language="ja", auto_punctuation=True):
    if not text:
        return text

    auto_punctuation = parse_bool(auto_punctuation, default=True)

    ERROR_CORRECTION_DICT = {
        "ですい": "です",
        "ますい": "ます",
        "でしたい": "でした",
        "ましたい": "ました",
    }

    for wrong, correct in sorted(
        ERROR_CORRECTION_DICT.items(), key=lambda x: len(x[0]), reverse=True
    ):
        text = text.replace(wrong, correct)

    text = text.strip()

    text = " ".join(text.split())

    text = text.replace("\n\n", "\n").replace("\n ", "\n")

    if not auto_punctuation:
        return text

    if language == "ja":
        text = text.translate(str.maketrans({",": "、", ".": "。", "!": "！", "?": "？"}))
        text = re.sub(r"\s*([、。！？])\s*", r"\1", text)
        text = re.sub(r"、{2,}", "、", text)
        text = re.sub(r"。{2,}", "。", text)
        text = re.sub(r"！{2,}", "！", text)
        text = re.sub(r"？{2,}", "？", text)
        text = text.replace("、。", "。")

        if text and not text.endswith(("。", "！", "？", "!", "?")):
            text += "。"
    else:
        text = text.translate(str.maketrans({"、": ",", "。": ".", "！": "!", "？": "?"}))
        text = re.sub(r"\s+([,.!?])", r"\1", text)
        text = re.sub(r",{2,}", ",", text)
        text = re.sub(r"([!?])\1+", r"\1", text)
        text = re.sub(r"\s{2,}", " ", text)
        text = text.strip()
        if text and not text.endswith((".", "!", "?")):
            text += "."

    return text


def normalize_quality_preset(value):
    normalized = str(value or "").strip().lower()
    if normalized in {"low", "medium", "high"}:
        return normalized
    return "medium"


@dataclass(frozen=True)
class TranscriptionRequest:
    audio_path: str
    language: str | None
    auto_punctuation: bool
    quality_preset: str
    gpu_acceleration_enabled: bool
    screenshot_context: str | None = None


@dataclass(frozen=True)
class DecodeProfile:
    temperature: float | tuple[float, ...]
    beam_size: int | None = None
    best_of: int | None = None
    vad_threshold: float | None = None


@dataclass(frozen=True)
class BackendStatus:
    effective_backend: str
    gpu_requested: bool
    gpu_available: bool
    fallback_reason: str | None = None


def build_cpu_decode_profile(quality_preset):
    preset = normalize_quality_preset(quality_preset)
    profiles = {
        "low": DecodeProfile(temperature=0.0, beam_size=1, best_of=1, vad_threshold=0.5),
        "medium": DecodeProfile(temperature=0.0, beam_size=5, best_of=5, vad_threshold=0.5),
        "high": DecodeProfile(temperature=0.0, beam_size=10, best_of=10, vad_threshold=0.5),
    }
    return profiles[preset]


def build_mlx_decode_profile(quality_preset):
    preset = normalize_quality_preset(quality_preset)
    profiles = {
        "low": DecodeProfile(temperature=0.0),
        "medium": DecodeProfile(temperature=(0.0, 0.2, 0.4)),
        "high": DecodeProfile(temperature=(0.0, 0.2, 0.4, 0.6, 0.8, 1.0)),
    }
    return profiles[preset]


def emit_backend_status(status):
    payload = json.dumps(
        {
            "effectiveBackend": status.effective_backend,
            "gpuRequested": status.gpu_requested,
            "gpuAvailable": status.gpu_available,
            "fallbackReason": status.fallback_reason,
        },
        ensure_ascii=False,
    )
    print(f"{CONTROL_MESSAGE_PREFIX}{payload}", file=sys.stdout)
    sys.stdout.flush()


def parse_request_line(raw_line):
    stripped = raw_line.strip()
    if not stripped:
        return None
    if stripped.startswith(HEALTHCHECK_REQUEST_PREFIX):
        return {"kind": "healthcheck", "token": stripped[len(HEALTHCHECK_REQUEST_PREFIX) :]}

    payload = json.loads(stripped)
    if payload.get("type") != "transcription_request":
        raise ValueError(f"Unsupported request type: {payload.get('type')}")

    language = str(payload.get("language", "auto")).strip() or "auto"
    actual_language = None if language == "auto" else language
    screenshot_context = payload.get("screenshot_context")
    if screenshot_context is not None:
        screenshot_context = str(screenshot_context)

    return {
        "kind": "transcription",
        "request": TranscriptionRequest(
            audio_path=str(payload.get("audio_path", "")),
            language=actual_language,
            auto_punctuation=parse_bool(payload.get("auto_punctuation"), default=True),
            quality_preset=normalize_quality_preset(payload.get("quality_preset")),
            gpu_acceleration_enabled=parse_bool(
                payload.get("gpu_acceleration_enabled"), default=True
            ),
            screenshot_context=screenshot_context,
        ),
    }


class BackendManager:
    def __init__(
        self,
        state_path,
        lock_path,
        pid,
        max_parallel_model_loads,
        model_load_wait_timeout,
        log,
    ):
        self.state_path = state_path
        self.lock_path = lock_path
        self.pid = pid
        self.max_parallel_model_loads = max_parallel_model_loads
        self.model_load_wait_timeout = model_load_wait_timeout
        self.log = log
        self.cpu_model = None
        self.mlx_whisper: MlxWhisperModule | None = None
        self.mlx_transcribe_module: MlxTranscribeModule | None = None
        self.mlx_core: MlxCoreModule | None = None
        self.mlx_runtime_checked = False
        self.mlx_runtime_available = False
        self.mlx_runtime_reason = None
        self.mlx_disabled_for_session = False
        self.mlx_model_loaded = False

    def _is_apple_silicon(self):
        return sys.platform == "darwin" and platform.machine().lower() in {"arm64", "aarch64"}

    def _wait_for_model_load_slot(self):
        wait_started = time.time()
        while True:
            acquired, loading_count = try_acquire_model_load_slot(
                state_path=self.state_path,
                lock_path=self.lock_path,
                pid=self.pid,
                max_parallel_model_loads=self.max_parallel_model_loads,
            )
            if acquired:
                if loading_count > 1:
                    self.log(
                        "Model load slot acquired after waiting "
                        f"(parallel_loads={loading_count}, max={self.max_parallel_model_loads})"
                    )
                return

            elapsed = time.time() - wait_started
            if elapsed >= self.model_load_wait_timeout:
                raise TimeoutError(
                    "Timed out waiting for model-load slot "
                    f"(timeout={self.model_load_wait_timeout}s, max_parallel={self.max_parallel_model_loads})"
                )
            time.sleep(0.25)

    def _run_with_model_load_slot(self, loader):
        self._wait_for_model_load_slot()
        try:
            return loader()
        finally:
            release_model_load_slot(
                state_path=self.state_path,
                lock_path=self.lock_path,
                pid=self.pid,
            )

    def _probe_mlx_runtime(self):
        if self.mlx_disabled_for_session:
            return False, "mlx_disabled_for_session"
        if not self._is_apple_silicon():
            return False, "gpu_not_supported_on_host"
        if self.mlx_runtime_checked:
            return self.mlx_runtime_available, self.mlx_runtime_reason

        try:
            import importlib

            self.mlx_core = cast(MlxCoreModule, importlib.import_module("mlx.core"))
            self.mlx_whisper = cast(MlxWhisperModule, importlib.import_module("mlx_whisper"))
            self.mlx_transcribe_module = cast(
                MlxTranscribeModule, importlib.import_module("mlx_whisper.transcribe")
            )
            self.mlx_runtime_available = True
            self.mlx_runtime_reason = None
        except Exception as error:
            self.mlx_runtime_available = False
            self.mlx_runtime_reason = "mlx_runtime_import_failed"
            self.log(f"MLX runtime unavailable: {error}")
            self.log(traceback.format_exc())
        finally:
            self.mlx_runtime_checked = True

        return self.mlx_runtime_available, self.mlx_runtime_reason

    def _disable_mlx_for_session(self, reason, error=None):
        self.mlx_disabled_for_session = True
        self.mlx_runtime_available = False
        self.mlx_runtime_reason = "mlx_disabled_for_session"
        self.log(f"MLX disabled for app session (reason={reason})")
        if error is not None:
            self.log(f"MLX error: {error}")
            self.log(traceback.format_exc())

    def _ensure_cpu_model(self):
        if self.cpu_model is not None:
            return self.cpu_model

        def _load():
            from faster_whisper import WhisperModel

            self.log("Loading faster-whisper CPU model...")
            model = WhisperModel(
                DEFAULT_CPU_MODEL_ID,
                device="cpu",
                compute_type="int8",
            )
            self.log("CPU model loaded (backend=faster-whisper, device=cpu, compute_type=int8)")
            return model

        self.cpu_model = self._run_with_model_load_slot(_load)
        return self.cpu_model

    def _ensure_mlx_model(self):
        available, reason = self._probe_mlx_runtime()
        if not available:
            raise RuntimeError(reason or "mlx runtime unavailable")
        if self.mlx_model_loaded:
            return

        mlx_transcribe_module = self.mlx_transcribe_module
        mlx_core = self.mlx_core
        if mlx_transcribe_module is None or mlx_core is None:
            raise RuntimeError("mlx runtime unavailable")

        def _load():
            self.log("Loading MLX Whisper model...")
            mlx_transcribe_module.ModelHolder.get_model(
                DEFAULT_MLX_MODEL_ID,
                mlx_core.float16,
            )
            self.log(f"MLX model loaded (backend=mlx-whisper, model={DEFAULT_MLX_MODEL_ID})")

        self._run_with_model_load_slot(_load)
        self.mlx_model_loaded = True

    def _transcribe_with_cpu(self, audio_path, language, quality_preset, initial_prompt):
        model = self._ensure_cpu_model()
        profile = build_cpu_decode_profile(quality_preset)
        vad_parameters = build_vad_parameters(profile.vad_threshold or 0.5)
        transcribe_kwargs = {
            "audio": audio_path,
            "language": language,
            "task": DEFAULT_TASK,
            "temperature": profile.temperature,
            "beam_size": profile.beam_size,
            "best_of": profile.best_of,
            "word_timestamps": False,
            "initial_prompt": initial_prompt,
            "no_speech_threshold": DEFAULT_NO_SPEECH_THRESHOLD,
            "compression_ratio_threshold": DEFAULT_COMPRESSION_RATIO_THRESHOLD,
        }
        self.log(
            f"CPU transcription parameters: language={language}, preset={quality_preset}, beam_size={profile.beam_size}, best_of={profile.best_of}, vad_parameters={vad_parameters}, initial_prompt_present={initial_prompt is not None}"
        )
        segments, info = transcribe_with_vad_fallback(
            model=model,
            transcribe_kwargs=transcribe_kwargs,
            vad_parameters=vad_parameters,
            log=self.log,
        )
        text = " ".join(getattr(segment, "text", "") for segment in segments).strip()
        detected_language = info.language if language is None else language
        return text, detected_language

    def _transcribe_with_mlx(self, audio_path, language, quality_preset, initial_prompt):
        self._ensure_mlx_model()
        profile = build_mlx_decode_profile(quality_preset)
        mlx_whisper = self.mlx_whisper
        if mlx_whisper is None:
            raise RuntimeError("mlx runtime unavailable")
        self.log(
            f"MLX transcription parameters: language={language}, preset={quality_preset}, temperature={profile.temperature}, initial_prompt_present={initial_prompt is not None}"
        )
        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=DEFAULT_MLX_MODEL_ID,
            language=language,
            task=DEFAULT_TASK,
            temperature=profile.temperature,
            word_timestamps=False,
            initial_prompt=initial_prompt,
            no_speech_threshold=DEFAULT_NO_SPEECH_THRESHOLD,
            compression_ratio_threshold=DEFAULT_COMPRESSION_RATIO_THRESHOLD,
        )
        text = str(result.get("text", "")).strip()
        detected_language = result.get("language") if language is None else language
        return text, detected_language

    def transcribe(self, request, audio_path, initial_prompt):
        gpu_available, reason = self._probe_mlx_runtime()
        if not request.gpu_acceleration_enabled:
            text, detected_language = self._transcribe_with_cpu(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, BackendStatus(
                effective_backend="cpu",
                gpu_requested=False,
                gpu_available=gpu_available,
                fallback_reason="gpu_disabled_in_settings",
            )

        if not gpu_available:
            text, detected_language = self._transcribe_with_cpu(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, BackendStatus(
                effective_backend="cpu",
                gpu_requested=True,
                gpu_available=False,
                fallback_reason=reason,
            )

        try:
            text, detected_language = self._transcribe_with_mlx(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, BackendStatus(
                effective_backend="mlx",
                gpu_requested=True,
                gpu_available=True,
                fallback_reason=None,
            )
        except Exception as error:
            fallback_reason = "mlx_model_load_failed"
            if self.mlx_model_loaded:
                fallback_reason = "mlx_transcription_failed"
            self._disable_mlx_for_session(fallback_reason, error=error)
            text, detected_language = self._transcribe_with_cpu(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, BackendStatus(
                effective_backend="cpu",
                gpu_requested=True,
                gpu_available=False,
                fallback_reason=fallback_reason,
            )


def normalize_user_words(words):
    normalized = []
    seen = set()

    for word in words:
        if not isinstance(word, str):
            continue

        cleaned = " ".join(word.strip().split())
        if not cleaned:
            continue

        key = cleaned.casefold()
        if key in seen:
            continue

        seen.add(key)
        normalized.append(cleaned)

        if len(normalized) >= 200:
            break

    return normalized


def load_user_dictionary(path=None, log=None):
    dict_path = path or default_dictionary_path()
    try:
        if not os.path.exists(dict_path):
            return []

        import json

        with open(dict_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if isinstance(data, dict):
            raw_words = data.get("words", [])
        elif isinstance(data, list):
            raw_words = data
        else:
            raw_words = []

        words = normalize_user_words(raw_words)
        if log:
            log(f"Loaded user dictionary words: {len(words)}")
        return words
    except Exception as error:
        if log:
            log(f"Failed to load user dictionary: {error}")
        return []


def generate_initial_prompt(language, use_context=True, user_words=None, screenshot_context=None):
    base_prompts = {
        "ja": "これは会話の文字起こしです。正確な日本語で出力してください。",
        "en": "This is a speech transcription. Please output accurate English.",
    }

    prompt = base_prompts.get(language, "")

    if use_context:
        words_for_prompt = user_words if user_words is not None else load_user_dictionary()
        normalized_words = normalize_user_words(words_for_prompt)
        if normalized_words:
            if language == "ja":
                word_list = "、".join(normalized_words[:20])
                prompt += f" 以下の単語や専門用語を正確に認識してください: {word_list}。"
            else:
                word_list = ", ".join(normalized_words[:20])
                prompt += f" Please accurately recognize these terms: {word_list}."

    if screenshot_context:
        normalized_screenshot_context = " ".join(str(screenshot_context).split())
        if normalized_screenshot_context:
            clipped_screenshot_context = normalized_screenshot_context[:250]
            if language == "ja":
                prompt += f" 画面上の情報: {clipped_screenshot_context}。"
            else:
                prompt += f" On-screen context: {clipped_screenshot_context}."

    return prompt if prompt else None


def main():
    log_file, log = setup_logging()
    log("=== Server started ===")

    state_path = default_server_state_path()
    lock_path = default_server_state_lock_path()
    current_pid = os.getpid()
    parent_pid = parse_int(os.environ.get("KOTOTYPE_PARENT_PID"), 0)
    max_active_servers = max(1, parse_int(os.environ.get("KOTOTYPE_MAX_ACTIVE_SERVERS"), 1))
    max_parallel_model_loads = max(1, parse_int(os.environ.get("KOTOTYPE_MAX_PARALLEL_MODEL_LOADS"), 1))
    model_load_wait_timeout = max(1, parse_int(os.environ.get("KOTOTYPE_MODEL_LOAD_WAIT_TIMEOUT_SECONDS"), 120))

    registered, active_count = register_server_pid(
        state_path=state_path,
        lock_path=lock_path,
        pid=current_pid,
        max_active_servers=max_active_servers,
    )
    if not registered:
        log(
            "Server startup skipped: active server limit reached "
            f"(max={max_active_servers}, current={active_count})"
        )
        return

    def cleanup_server_state():
        release_model_load_slot(state_path=state_path, lock_path=lock_path, pid=current_pid)
        unregister_server_pid(state_path=state_path, lock_path=lock_path, pid=current_pid)

    atexit.register(cleanup_server_state)

    for signal_name in ("SIGTERM", "SIGINT"):
        if hasattr(signal, signal_name):
            sig = getattr(signal, signal_name)

            def _handler(signum, frame):
                cleanup_server_state()
                raise SystemExit(0)

            signal.signal(sig, _handler)

    start_parent_watchdog(
        parent_pid=parent_pid,
        log=log,
        cleanup=cleanup_server_state,
    )
    backend_manager = BackendManager(
        state_path=state_path,
        lock_path=lock_path,
        pid=current_pid,
        max_parallel_model_loads=max_parallel_model_loads,
        model_load_wait_timeout=model_load_wait_timeout,
        log=log,
    )

    log("Waiting for input from stdin...")
    sys.stdout.flush()

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                log("EOF reached, exiting")
                break

            request_payload = parse_request_line(line)
            if request_payload is None:
                continue
            if request_payload["kind"] == "healthcheck":
                token = request_payload["token"]
                print(f"{HEALTHCHECK_RESPONSE_PREFIX}{token}", file=sys.stdout)
                sys.stdout.flush()
                log(f"Health check acknowledged (token={token})")
                continue

            request = request_payload["request"]
            log(
                f"Received: audio_path_len={len(request.audio_path)}, language={request.language or 'auto'}, "
                f"quality_preset={request.quality_preset}, gpu_acceleration_enabled={request.gpu_acceleration_enabled}, "
                f"auto_punctuation={request.auto_punctuation}, screenshot_context_len={len(request.screenshot_context) if request.screenshot_context else 0}"
            )

            if not request.audio_path:
                log("Empty audio path, skipping")
                continue

            if not os.path.exists(request.audio_path):
                log("Error: input audio file not found")
                print("", file=sys.stdout)
                sys.stdout.flush()
                continue

            log(f"File exists, size: {os.path.getsize(request.audio_path)} bytes")
            transcription_audio_path = request.audio_path

            processed_audio_path = audio_preprocess(
                request.audio_path,
                log,
                auto_gain_enabled=DEFAULT_AUTO_GAIN_ENABLED,
                auto_gain_weak_threshold_dbfs=DEFAULT_AUTO_GAIN_WEAK_THRESHOLD_DBFS,
                auto_gain_target_peak_dbfs=DEFAULT_AUTO_GAIN_TARGET_PEAK_DBFS,
                auto_gain_max_db=DEFAULT_AUTO_GAIN_MAX_DB,
            )

            try:
                if (
                    os.path.exists(processed_audio_path)
                    and processed_audio_path != request.audio_path
                ):
                    log(
                        f"Processed file size: {os.path.getsize(processed_audio_path)} bytes"
                    )
                transcription_audio_path = processed_audio_path
            except Exception as e:
                log(f"Error checking processed file: {str(e)}, using original")
                transcription_audio_path = request.audio_path

            user_words = load_user_dictionary(log=log)
            initial_prompt = generate_initial_prompt(
                request.language or "auto",
                use_context=True,
                user_words=user_words,
                screenshot_context=request.screenshot_context,
            )

            start_time = time.time()
            log("Starting transcription with Whisper...")
            try:
                transcription, detected_language, backend_status = backend_manager.transcribe(
                    request=request,
                    audio_path=transcription_audio_path,
                    initial_prompt=initial_prompt,
                )
                elapsed_time = time.time() - start_time
                log(
                    f"Transcription completed in {elapsed_time:.2f} seconds (detected language: {detected_language}, backend={backend_status.effective_backend}, fallback_reason={backend_status.fallback_reason})"
                )
                log(f"Transcription length: {len(transcription)} characters")

                transcription = post_process_text(
                    transcription,
                    detected_language,
                    auto_punctuation=request.auto_punctuation,
                )
                log(f"Post-processed transcription length: {len(transcription)} characters")

                emit_backend_status(backend_status)
                print(transcription, file=sys.stdout)
                sys.stdout.flush()
                log("Output flushed")
            finally:
                cleanup_transcription_audio_path(
                    transcription_audio_path,
                    request.audio_path,
                    log,
                )

        except Exception as e:
            log(f"Error: {str(e)}")
            log(f"Traceback: {traceback.format_exc()}")
            print("", file=sys.stdout)
            sys.stdout.flush()


if __name__ == "__main__":
    # PyInstaller-frozen onefile binaries can re-execute for multiprocessing
    # helpers (for example, resource_tracker). freeze_support() prevents those
    # helper invocations from re-entering the full server main loop.
    multiprocessing.freeze_support()
    main()
