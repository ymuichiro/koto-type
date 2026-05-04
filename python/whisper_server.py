#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import atexit
import json
import multiprocessing
import os
import platform
import re
import signal
import shutil
import time
import sys
import threading
import traceback
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from math import inf, log10, sqrt
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
DEFAULT_ACTIVITY_WINDOW_MS = 30
DEFAULT_ACTIVITY_THRESHOLD_DBFS = -38.0
DEFAULT_MIN_ACTIVE_AUDIO_SECONDS = 0.18
DEFAULT_MIN_ACTIVE_AUDIO_RATIO = 0.12
DEFAULT_MIN_AUDIO_DURATION_FOR_SKIP_SECONDS = 0.8


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


def default_application_support_directory():
    return os.path.expanduser("~/Library/Application Support/koto-type")


def setup_logging():
    log_dir = default_application_support_directory()
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
    return os.path.join(default_application_support_directory(), "server_state.json")


def default_server_state_lock_path():
    return os.path.join(default_application_support_directory(), "server_state.lock")


def default_managed_models_root():
    return os.path.join(default_application_support_directory(), "managed-models")


def default_managed_cpu_model_path():
    return os.path.join(default_managed_models_root(), "cpu-large-v3-turbo")


def default_managed_mlx_model_path():
    return os.path.join(default_managed_models_root(), "mlx-whisper-large-v3-turbo")


def default_managed_model_cache_path():
    return os.path.join(default_application_support_directory(), "model-cache")


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


def analyze_wav_activity(
    wav_path,
    window_ms=DEFAULT_ACTIVITY_WINDOW_MS,
    activity_threshold_dbfs=DEFAULT_ACTIVITY_THRESHOLD_DBFS,
):
    max_peak = 0
    active_windows = 0
    total_windows = 0
    total_samples = 0

    with wave.open(wav_path, "rb") as wav_file:
        sample_width = wav_file.getsampwidth()
        channel_count = wav_file.getnchannels()
        sample_rate = wav_file.getframerate()

        if sample_width != 2:
            raise ValueError(
                f"Unsupported sample width for activity analysis: {sample_width * 8}-bit"
            )

        window_sample_count = max(1, int(sample_rate * max(window_ms, 5) / 1000))

        while True:
            frames = wav_file.readframes(window_sample_count)
            if not frames:
                break

            frame_count = len(frames) // (sample_width * channel_count)
            if frame_count <= 0:
                continue

            total_windows += 1
            total_samples += frame_count
            squared_sum = 0.0
            window_peak = 0

            for frame_index in range(frame_count):
                offset = frame_index * sample_width * channel_count
                sample_bytes = frames[offset : offset + sample_width]
                sample_value = int.from_bytes(
                    sample_bytes,
                    byteorder="little",
                    signed=True,
                )
                abs_sample = abs(sample_value)
                if abs_sample > window_peak:
                    window_peak = abs_sample
                squared_sum += float(sample_value * sample_value)

            if window_peak > max_peak:
                max_peak = window_peak

            rms = sqrt(squared_sum / frame_count) if frame_count > 0 else 0.0
            if rms > 0:
                rms_dbfs = 20.0 * log10(rms / 32767.0)
                if rms_dbfs >= activity_threshold_dbfs:
                    active_windows += 1

    if total_samples <= 0:
        return AudioActivityStats(
            duration_seconds=0.0,
            peak_dbfs=-inf,
            active_duration_seconds=0.0,
            active_ratio=0.0,
            window_count=0,
        )

    duration_seconds = total_samples / sample_rate
    peak_dbfs = -inf if max_peak <= 0 else 20.0 * log10(max_peak / 32767.0)
    active_ratio = active_windows / total_windows if total_windows > 0 else 0.0
    active_duration_seconds = active_windows * (window_sample_count / sample_rate)

    return AudioActivityStats(
        duration_seconds=duration_seconds,
        peak_dbfs=peak_dbfs,
        active_duration_seconds=active_duration_seconds,
        active_ratio=active_ratio,
        window_count=total_windows,
    )


def should_skip_transcription_for_low_activity(
    activity_stats,
    *,
    min_audio_duration_for_skip_seconds=DEFAULT_MIN_AUDIO_DURATION_FOR_SKIP_SECONDS,
    min_active_audio_seconds=DEFAULT_MIN_ACTIVE_AUDIO_SECONDS,
    min_active_audio_ratio=DEFAULT_MIN_ACTIVE_AUDIO_RATIO,
):
    if activity_stats.duration_seconds <= 0:
        return True
    if activity_stats.peak_dbfs == -inf:
        return True
    if activity_stats.duration_seconds < min_audio_duration_for_skip_seconds:
        return False
    if activity_stats.active_duration_seconds >= min_active_audio_seconds:
        return False
    if activity_stats.active_ratio >= min_active_audio_ratio:
        return False
    return True


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


def ensure_private_directory(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    tighten_file_permissions(path, mode=0o700)


def tighten_directory_tree_permissions(root_path):
    if not root_path or not os.path.exists(root_path):
        return

    for current_root, directory_names, file_names in os.walk(root_path):
        tighten_file_permissions(current_root, mode=0o700)
        for directory_name in directory_names:
            tighten_file_permissions(os.path.join(current_root, directory_name), mode=0o700)
        for file_name in file_names:
            tighten_file_permissions(os.path.join(current_root, file_name), mode=0o600)


def directory_file_stats(path):
    if not path or not os.path.exists(path):
        return 0, 0

    file_count = 0
    byte_count = 0
    for current_root, _, file_names in os.walk(path):
        for file_name in file_names:
            file_path = os.path.join(current_root, file_name)
            if not os.path.isfile(file_path):
                continue
            file_count += 1
            try:
                byte_count += os.path.getsize(file_path)
            except OSError:
                continue
    return file_count, byte_count


def remove_directory_tree(path):
    if not path or not os.path.exists(path):
        return
    shutil.rmtree(path)


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
        def normalize_japanese_punctuation_sequence(value):
            value = re.sub(r"、+([。！？])", r"\1", value)
            value = re.sub(r"。{2,}", "。", value)
            value = re.sub(r"！{2,}", "！", value)
            value = re.sub(r"？{2,}", "？", value)
            value = re.sub(r"、{2,}", "、", value)
            return value

        text = text.translate(str.maketrans({",": "、", ".": "。", "!": "！", "?": "？"}))
        text = re.sub(r"\s*([、。！？])\s*", r"\1", text)
        text = normalize_japanese_punctuation_sequence(text)

        if text and not text.endswith(("。", "！", "？", "!", "?")):
            if text.endswith("、"):
                text = text[:-1] + "。"
            else:
                text += "。"

        text = normalize_japanese_punctuation_sequence(text)
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
class BackendProbeRequest:
    gpu_acceleration_enabled: bool
    preload_model: bool = False


@dataclass(frozen=True)
class ModelManagementRequest:
    action: str
    model_kind: str | None = None


@dataclass(frozen=True)
class DecodeProfile:
    temperature: float | tuple[float, ...]
    beam_size: int | None = None
    best_of: int | None = None
    vad_threshold: float | None = None


@dataclass(frozen=True)
class AudioActivityStats:
    duration_seconds: float
    peak_dbfs: float
    active_duration_seconds: float
    active_ratio: float
    window_count: int


@dataclass(frozen=True)
class BackendStatus:
    effective_backend: str
    gpu_requested: bool
    gpu_available: bool
    fallback_reason: str | None = None


@dataclass(frozen=True)
class ManagedModelStatus:
    kind: str
    display_name: str
    model_id: str
    directory_path: str
    is_downloaded: bool
    file_count: int
    byte_count: int


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


def normalize_model_kind(value):
    normalized = str(value or "").strip().lower()
    if normalized in {"cpu", "mlx"}:
        return normalized
    raise ValueError(f"Unsupported model kind: {value}")


def normalize_model_management_action(value):
    normalized = str(value or "").strip().lower()
    if normalized in {"status_all", "download", "delete"}:
        return normalized
    raise ValueError(f"Unsupported model management action: {value}")


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


def emit_backend_preparation_progress(step, detail=None):
    payload = json.dumps(
        {
            "type": "backend_preparation_progress",
            "step": step,
            "detail": detail,
        },
        ensure_ascii=False,
    )
    print(f"{CONTROL_MESSAGE_PREFIX}{payload}", file=sys.stdout)
    sys.stdout.flush()


def serialize_managed_model_status(status):
    return {
        "kind": status.kind,
        "displayName": status.display_name,
        "modelID": status.model_id,
        "directoryPath": status.directory_path,
        "isDownloaded": status.is_downloaded,
        "fileCount": status.file_count,
        "byteCount": status.byte_count,
    }


def emit_managed_models(models):
    payload = json.dumps(
        {
            "type": "managed_models",
            "models": [serialize_managed_model_status(model) for model in models],
        },
        ensure_ascii=False,
    )
    print(f"{CONTROL_MESSAGE_PREFIX}{payload}", file=sys.stdout)
    sys.stdout.flush()


def emit_managed_model(model):
    payload = json.dumps(
        {
            "type": "managed_model",
            "model": serialize_managed_model_status(model),
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
    request_type = payload.get("type")
    if request_type == "backend_probe":
        return {
            "kind": "backend_probe",
            "request": BackendProbeRequest(
                gpu_acceleration_enabled=parse_bool(
                    payload.get("gpu_acceleration_enabled"), default=True
                ),
                preload_model=parse_bool(payload.get("preload_model"), default=False),
            ),
        }
    if request_type == "model_management":
        action = normalize_model_management_action(payload.get("action"))
        model_kind = payload.get("model_kind")
        return {
            "kind": "model_management",
            "request": ModelManagementRequest(
                action=action,
                model_kind=None if action == "status_all" else normalize_model_kind(model_kind),
            ),
        }
    if request_type != "transcription_request":
        raise ValueError(f"Unsupported request type: {request_type}")

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
        cpu_model_dir,
        mlx_model_dir,
        model_cache_dir,
        log,
    ):
        self.state_path = state_path
        self.lock_path = lock_path
        self.pid = pid
        self.max_parallel_model_loads = max_parallel_model_loads
        self.model_load_wait_timeout = model_load_wait_timeout
        self.cpu_model_dir = cpu_model_dir
        self.mlx_model_dir = mlx_model_dir
        self.model_cache_dir = model_cache_dir
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

    def _managed_model_status(self, model_kind):
        normalized_kind = normalize_model_kind(model_kind)
        if normalized_kind == "cpu":
            directory_path = self.cpu_model_dir
            is_downloaded = self._cpu_model_assets_exist()
            display_name = "CPU model"
            model_id = DEFAULT_CPU_MODEL_ID
        else:
            directory_path = self.mlx_model_dir
            is_downloaded = self._mlx_model_assets_exist()
            display_name = "MLX model"
            model_id = DEFAULT_MLX_MODEL_ID

        file_count, byte_count = directory_file_stats(directory_path)
        return ManagedModelStatus(
            kind=normalized_kind,
            display_name=display_name,
            model_id=model_id,
            directory_path=directory_path,
            is_downloaded=is_downloaded,
            file_count=file_count,
            byte_count=byte_count,
        )

    def managed_model_statuses(self):
        return [
            self._managed_model_status("cpu"),
            self._managed_model_status("mlx"),
        ]

    def download_managed_model(self, model_kind):
        normalized_kind = normalize_model_kind(model_kind)
        if normalized_kind == "cpu":
            self._download_cpu_model()
        else:
            self._download_mlx_model()
        return self._managed_model_status(normalized_kind)

    def delete_managed_model(self, model_kind):
        normalized_kind = normalize_model_kind(model_kind)
        if normalized_kind == "cpu":
            self.cpu_model = None
            remove_directory_tree(self.cpu_model_dir)
        else:
            self.mlx_model_loaded = False
            remove_directory_tree(self.mlx_model_dir)
        return self._managed_model_status(normalized_kind)

    def _cpu_model_assets_exist(self):
        config_path = os.path.join(self.cpu_model_dir, "config.json")
        model_bin_path = os.path.join(self.cpu_model_dir, "model.bin")
        tokenizer_path = os.path.join(self.cpu_model_dir, "tokenizer.json")
        return (
            os.path.isfile(config_path)
            and os.path.isfile(model_bin_path)
            and os.path.isfile(tokenizer_path)
        )

    def _mlx_model_assets_exist(self):
        config_path = os.path.join(self.mlx_model_dir, "config.json")
        safetensors_path = os.path.join(self.mlx_model_dir, "weights.safetensors")
        npz_path = os.path.join(self.mlx_model_dir, "weights.npz")
        return (
            os.path.isfile(config_path)
            and (os.path.isfile(safetensors_path) or os.path.isfile(npz_path))
        )

    def _download_cpu_model(self):
        from faster_whisper import utils as faster_whisper_utils

        ensure_private_directory(os.path.dirname(self.cpu_model_dir))
        ensure_private_directory(self.model_cache_dir)
        self.log(f"Downloading managed CPU model to {self.cpu_model_dir}")
        faster_whisper_utils.download_model(
            DEFAULT_CPU_MODEL_ID,
            output_dir=self.cpu_model_dir,
            cache_dir=self.model_cache_dir,
        )
        tighten_directory_tree_permissions(self.cpu_model_dir)

    def _download_mlx_model(self):
        from huggingface_hub import snapshot_download

        ensure_private_directory(os.path.dirname(self.mlx_model_dir))
        self.log(f"Downloading managed MLX model to {self.mlx_model_dir}")
        snapshot_download(
            repo_id=DEFAULT_MLX_MODEL_ID,
            local_dir=self.mlx_model_dir,
        )
        tighten_directory_tree_permissions(self.mlx_model_dir)

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

    def _probe_mlx_runtime(self, progress=None):
        if self.mlx_disabled_for_session:
            return False, "mlx_disabled_for_session"
        if not self._is_apple_silicon():
            return False, "gpu_not_supported_on_host"
        if self.mlx_runtime_checked:
            return self.mlx_runtime_available, self.mlx_runtime_reason

        try:
            if progress is not None:
                progress(
                    "importing_mlx_runtime",
                    "Loading the MLX runtime components needed for Apple GPU transcription.",
                )
            import_started_at = time.perf_counter()
            import importlib

            self.mlx_core = cast(MlxCoreModule, importlib.import_module("mlx.core"))
            self.mlx_whisper = cast(MlxWhisperModule, importlib.import_module("mlx_whisper"))
            self.mlx_transcribe_module = cast(
                MlxTranscribeModule, importlib.import_module("mlx_whisper.transcribe")
            )
            self.mlx_runtime_available = True
            self.mlx_runtime_reason = None
            elapsed = time.perf_counter() - import_started_at
            self.log(f"MLX runtime import completed in {elapsed:.2f} seconds")
        except Exception as error:
            elapsed = time.perf_counter() - import_started_at
            self.mlx_runtime_available = False
            self.mlx_runtime_reason = "mlx_runtime_import_failed"
            self.log(f"MLX runtime unavailable after {elapsed:.2f} seconds: {error}")
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

    def _status_for_gpu_request(self, gpu_acceleration_enabled, progress=None):
        if progress is not None:
            progress(
                "probing_gpu",
                "Detecting whether Apple GPU acceleration is available on this Mac.",
            )
        gpu_available, reason = self._probe_mlx_runtime(progress=progress)
        if not gpu_acceleration_enabled:
            return BackendStatus(
                effective_backend="cpu",
                gpu_requested=False,
                gpu_available=gpu_available,
                fallback_reason="gpu_disabled_in_settings",
            )
        if not gpu_available:
            return BackendStatus(
                effective_backend="cpu",
                gpu_requested=True,
                gpu_available=False,
                fallback_reason=reason,
            )
        return BackendStatus(
            effective_backend="mlx",
            gpu_requested=True,
            gpu_available=True,
            fallback_reason=None,
        )

    def probe_backend_status(self, gpu_acceleration_enabled, preload_model=False):
        emit_backend_preparation_progress(
            "starting",
            "Launching the transcription backend for first-time setup.",
        )
        status = self._status_for_gpu_request(
            gpu_acceleration_enabled,
            progress=emit_backend_preparation_progress,
        )
        if not preload_model:
            return status

        if status.effective_backend == "mlx":
            emit_backend_preparation_progress(
                "preparing_mlx_model",
                "Getting the Apple GPU transcription model ready.",
            )
            try:
                self._ensure_mlx_model(progress=emit_backend_preparation_progress)
                return status
            except Exception as error:
                fallback_reason = "mlx_model_load_failed"
                if self.mlx_model_loaded:
                    fallback_reason = "mlx_transcription_failed"
                emit_backend_preparation_progress(
                    "fallback_to_cpu",
                    "Apple GPU preparation failed, so KotoType is falling back to the CPU model.",
                )
                self._disable_mlx_for_session(fallback_reason, error=error)
                emit_backend_preparation_progress(
                    "preparing_cpu_model",
                    "Getting the CPU transcription model ready.",
                )
                self._ensure_cpu_model(progress=emit_backend_preparation_progress)
                return BackendStatus(
                    effective_backend="cpu",
                    gpu_requested=True,
                    gpu_available=False,
                    fallback_reason=fallback_reason,
                )

        emit_backend_preparation_progress(
            "preparing_cpu_model",
            "Getting the CPU transcription model ready.",
        )
        self._ensure_cpu_model(progress=emit_backend_preparation_progress)
        return status

    def _ensure_cpu_model(self, progress=None):
        if self.cpu_model is not None:
            if progress is not None:
                progress(
                    "loading_cpu_model",
                    "CPU model is already loaded and ready for transcription.",
                )
            return self.cpu_model

        if progress is not None:
            progress(
                "checking_cpu_model_assets",
                "Looking for the local CPU model so it does not need to be downloaded again.",
            )
        if not self._cpu_model_assets_exist():
            if progress is not None:
                progress(
                    "downloading_cpu_model",
                    "Downloading the CPU transcription model. This can take a while on first launch.",
                )
            self._download_cpu_model()

        if progress is not None:
            progress(
                "loading_cpu_model",
                "Loading the CPU model into memory.",
            )

        def _load():
            from faster_whisper import WhisperModel

            self.log("Loading faster-whisper CPU model...")
            model = WhisperModel(
                self.cpu_model_dir,
                device="cpu",
                compute_type="int8",
                local_files_only=True,
            )
            self.log("CPU model loaded (backend=faster-whisper, device=cpu, compute_type=int8)")
            return model

        self.cpu_model = self._run_with_model_load_slot(_load)
        return self.cpu_model

    def _ensure_mlx_model(self, progress=None):
        available, reason = self._probe_mlx_runtime(progress=progress)
        if not available:
            raise RuntimeError(reason or "mlx runtime unavailable")
        if self.mlx_model_loaded:
            if progress is not None:
                progress(
                    "loading_mlx_model",
                    "Apple GPU model is already loaded and ready for transcription.",
                )
            return

        mlx_transcribe_module = self.mlx_transcribe_module
        mlx_core = self.mlx_core
        if mlx_transcribe_module is None or mlx_core is None:
            raise RuntimeError("mlx runtime unavailable")
        if progress is not None:
            progress(
                "checking_mlx_model_assets",
                "Looking for the local Apple GPU model so it does not need to be downloaded again.",
            )
        if not self._mlx_model_assets_exist():
            if progress is not None:
                progress(
                    "downloading_mlx_model",
                    "Downloading the Apple GPU transcription model. This can take a while on first launch.",
                )
            self._download_mlx_model()

        if progress is not None:
            progress(
                "loading_mlx_model",
                "Loading the Apple GPU model into memory.",
            )

        def _load():
            self.log("Loading MLX Whisper model...")
            load_started_at = time.perf_counter()
            mlx_transcribe_module.ModelHolder.get_model(
                self.mlx_model_dir,
                mlx_core.float16,
            )
            elapsed = time.perf_counter() - load_started_at
            self.log(f"MLX model warmup completed in {elapsed:.2f} seconds")
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
            path_or_hf_repo=self.mlx_model_dir,
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
        status = self._status_for_gpu_request(request.gpu_acceleration_enabled)
        if status.effective_backend == "cpu" and status.fallback_reason == "gpu_disabled_in_settings":
            text, detected_language = self._transcribe_with_cpu(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, status

        if status.effective_backend == "cpu":
            text, detected_language = self._transcribe_with_cpu(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, status

        try:
            text, detected_language = self._transcribe_with_mlx(
                audio_path,
                request.language,
                request.quality_preset,
                initial_prompt,
            )
            return text, detected_language, status
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
    cpu_model_dir = os.environ.get("KOTOTYPE_CPU_MODEL_DIR", default_managed_cpu_model_path())
    mlx_model_dir = os.environ.get("KOTOTYPE_MLX_MODEL_DIR", default_managed_mlx_model_path())
    model_cache_dir = os.environ.get("KOTOTYPE_MODEL_CACHE_DIR", default_managed_model_cache_path())
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
        cpu_model_dir=cpu_model_dir,
        mlx_model_dir=mlx_model_dir,
        model_cache_dir=model_cache_dir,
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
            if request_payload["kind"] == "backend_probe":
                request = request_payload["request"]
                log(
                    "Received backend probe: "
                    f"gpu_acceleration_enabled={request.gpu_acceleration_enabled}, "
                    f"preload_model={request.preload_model}"
                )
                status = backend_manager.probe_backend_status(
                    gpu_acceleration_enabled=request.gpu_acceleration_enabled,
                    preload_model=request.preload_model,
                )
                emit_backend_status(status)
                continue
            if request_payload["kind"] == "model_management":
                request = request_payload["request"]
                log(
                    "Received model management request: "
                    f"action={request.action}, model_kind={request.model_kind or 'all'}"
                )
                if request.action == "status_all":
                    emit_managed_models(backend_manager.managed_model_statuses())
                elif request.action == "download":
                    emit_managed_model(
                        backend_manager.download_managed_model(request.model_kind)
                    )
                elif request.action == "delete":
                    emit_managed_model(
                        backend_manager.delete_managed_model(request.model_kind)
                    )
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

            try:
                activity_stats = analyze_wav_activity(transcription_audio_path)
                log(
                    "Audio activity analysis: "
                    f"duration={activity_stats.duration_seconds:.2f}s, "
                    f"peak={activity_stats.peak_dbfs:.2f} dBFS, "
                    f"active_duration={activity_stats.active_duration_seconds:.2f}s, "
                    f"active_ratio={activity_stats.active_ratio:.2f}, "
                    f"windows={activity_stats.window_count}"
                )
                if should_skip_transcription_for_low_activity(activity_stats):
                    backend_status = backend_manager._status_for_gpu_request(
                        request.gpu_acceleration_enabled
                    )
                    log(
                        "Skipping transcription because audio activity is too low "
                        "for a reliable result"
                    )
                    emit_backend_status(backend_status)
                    print("", file=sys.stdout)
                    sys.stdout.flush()
                    continue
            except Exception as activity_error:
                log(f"Audio activity analysis failed: {activity_error}")

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
