#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import sys
import traceback
import atexit
import signal
import time
from contextlib import contextmanager
from datetime import datetime
from math import inf, log10
import wave


def default_dictionary_path():
    return os.path.expanduser("~/Library/Application Support/koto-type/user_dictionary.json")


def setup_logging():
    log_dir = os.path.expanduser("~/Library/Application Support/koto-type")
    os.makedirs(log_dir, exist_ok=True)

    log_file = os.path.join(log_dir, "server.log")

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
    if ffmpeg_module is None:
        try:
            import ffmpeg as imported_ffmpeg

            ffmpeg_module = imported_ffmpeg
        except ImportError:
            log("ffmpeg-python not available, skipping preprocessing")
            return input_path

    if peak_analyzer is None:
        peak_analyzer = analyze_wav_peak_dbfs

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
                        os.replace(boosted_output_path, output_path)
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

        log("All preprocessing filter chains failed, using original audio")
        return input_path

    except Exception as e:
        log(f"Audio preprocessing failed: {str(e)}")
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
        text = re.sub(r"([、。！？])\1+", r"\1", text)
        text = re.sub(
            r"(?<!^)(そして|しかし|ただし|また|さらに|なので|だから)",
            r"、\1",
            text,
        )
        text = text.replace("、。", "。")

        if text and not text.endswith(("。", "！", "？", "!", "?")):
            text += "。"
    else:
        text = re.sub(r"\s*([,.!?])\s*", r"\1 ", text).strip()
        text = re.sub(r"\s{2,}", " ", text)
        if text and not text.endswith((".", "!", "?")):
            text += "."

    return text


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


def generate_initial_prompt(language, use_context=True, user_words=None):
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

    return prompt if prompt else None


def main():
    log_file, log = setup_logging()
    log("=== Server started ===")

    state_path = default_server_state_path()
    lock_path = default_server_state_lock_path()
    current_pid = os.getpid()
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

    wait_started = time.time()
    while True:
        acquired, loading_count = try_acquire_model_load_slot(
            state_path=state_path,
            lock_path=lock_path,
            pid=current_pid,
            max_parallel_model_loads=max_parallel_model_loads,
        )
        if acquired:
            if loading_count > 1:
                log(
                    "Model load slot acquired after waiting "
                    f"(parallel_loads={loading_count}, max={max_parallel_model_loads})"
                )
            break

        elapsed = time.time() - wait_started
        if elapsed >= model_load_wait_timeout:
            log(
                "Server startup aborted: timed out waiting for model-load slot "
                f"(timeout={model_load_wait_timeout}s, max_parallel={max_parallel_model_loads})"
            )
            cleanup_server_state()
            return

        time.sleep(0.25)

    log("Loading Whisper model...")

    # faster-whisperのみを使用
    from faster_whisper import WhisperModel

    model = WhisperModel(
        "large-v3-turbo",
        device="cpu",
        compute_type="int8",
    )
    release_model_load_slot(state_path=state_path, lock_path=lock_path, pid=current_pid)

    log("Model loaded (device=cpu, compute_type=int8)")
    log("Using faster-whisper backend")

    log("Waiting for input from stdin...")
    sys.stdout.flush()

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                log("EOF reached, exiting")
                break

            parts = line.strip().split("|")
            audio_path = parts[0]
            language = parts[1] if len(parts) > 1 else "ja"
            temperature = float(parts[2]) if len(parts) > 2 else 0.0
            beam_size = int(parts[3]) if len(parts) > 3 else 5
            no_speech_threshold = float(parts[4]) if len(parts) > 4 else 0.6
            compression_ratio_threshold = float(parts[5]) if len(parts) > 5 else 2.4
            task = parts[6] if len(parts) > 6 else "transcribe"
            best_of = int(parts[7]) if len(parts) > 7 else 5
            vad_threshold = float(parts[8]) if len(parts) > 8 else 0.5
            auto_punctuation = parse_bool(parts[9], default=True) if len(parts) > 9 else True
            auto_gain_enabled = (
                parse_optional_bool(parts[10]) if len(parts) > 10 else None
            )
            auto_gain_weak_threshold_dbfs = (
                parse_optional_float(parts[11]) if len(parts) > 11 else None
            )
            auto_gain_target_peak_dbfs = (
                parse_optional_float(parts[12]) if len(parts) > 12 else None
            )
            auto_gain_max_db = (
                parse_optional_float(parts[13]) if len(parts) > 13 else None
            )

            actual_language = None if language == "auto" else language
            log(
                f"Received: audio={audio_path}, language={language}, actual_language={actual_language}, temp={temperature}, beam={beam_size}, "
                f"no_speech_threshold={no_speech_threshold}, compression_ratio_threshold={compression_ratio_threshold}, "
                f"task={task}, best_of={best_of}, vad_threshold={vad_threshold}, auto_punctuation={auto_punctuation}, "
                f"auto_gain_enabled={auto_gain_enabled}, auto_gain_weak_threshold_dbfs={auto_gain_weak_threshold_dbfs}, "
                f"auto_gain_target_peak_dbfs={auto_gain_target_peak_dbfs}, auto_gain_max_db={auto_gain_max_db}"
            )

            if not audio_path:
                log("Empty audio path, skipping")
                continue

            if not os.path.exists(audio_path):
                log(f"Error: File not found: {audio_path}")
                print("", file=sys.stdout)
                sys.stdout.flush()
                continue

            log(f"File exists, size: {os.path.getsize(audio_path)} bytes")

            processed_audio_path = audio_preprocess(
                audio_path,
                log,
                auto_gain_enabled=auto_gain_enabled,
                auto_gain_weak_threshold_dbfs=auto_gain_weak_threshold_dbfs,
                auto_gain_target_peak_dbfs=auto_gain_target_peak_dbfs,
                auto_gain_max_db=auto_gain_max_db,
            )

            try:
                if (
                    os.path.exists(processed_audio_path)
                    and processed_audio_path != audio_path
                ):
                    log(
                        f"Processed file size: {os.path.getsize(processed_audio_path)} bytes"
                    )
                transcription_audio_path = processed_audio_path
            except Exception as e:
                log(f"Error checking processed file: {str(e)}, using original")
                transcription_audio_path = audio_path

            user_words = load_user_dictionary(log=log)
            initial_prompt = generate_initial_prompt(
                actual_language or language or "ja",
                use_context=True,
                user_words=user_words,
            )

            start_time = time.time()
            vad_parameters = build_vad_parameters(vad_threshold)

            log("Starting transcription with Whisper...")
            log(
                f"Transcription parameters: audio={transcription_audio_path}, language={actual_language}, task={task}, temperature={temperature}, beam_size={beam_size}, best_of={best_of}, vad_parameters={vad_parameters}, auto_punctuation={auto_punctuation}, initial_prompt={initial_prompt[:50] if initial_prompt else None}..."
            )

            transcribe_kwargs = {
                "audio": transcription_audio_path,
                "language": actual_language,
                "task": task,
                "temperature": temperature,
                "beam_size": beam_size,
                "best_of": best_of,
                "word_timestamps": False,
                "initial_prompt": initial_prompt,
                "no_speech_threshold": no_speech_threshold,
                "compression_ratio_threshold": compression_ratio_threshold,
            }

            try:
                segments, info = model.transcribe(
                    transcribe_kwargs["audio"],
                    language=transcribe_kwargs["language"],
                    task=transcribe_kwargs["task"],
                    temperature=transcribe_kwargs["temperature"],
                    beam_size=transcribe_kwargs["beam_size"],
                    best_of=transcribe_kwargs["best_of"],
                    vad_filter=True,
                    vad_parameters=vad_parameters,
                    word_timestamps=transcribe_kwargs["word_timestamps"],
                    initial_prompt=transcribe_kwargs["initial_prompt"],
                    no_speech_threshold=transcribe_kwargs["no_speech_threshold"],
                    compression_ratio_threshold=transcribe_kwargs[
                        "compression_ratio_threshold"
                    ],
                )
            except Exception as transcribe_error:
                log(f"Transcription error: {str(transcribe_error)}")
                log(f"Transcription error traceback: {traceback.format_exc()}")

                fallback_succeeded = False
                if should_retry_without_vad(transcribe_error):
                    log(
                        "Retrying transcription with vad_filter=False due to missing VAD asset"
                    )
                    try:
                        segments, info = model.transcribe(
                            transcribe_kwargs["audio"],
                            language=transcribe_kwargs["language"],
                            task=transcribe_kwargs["task"],
                            temperature=transcribe_kwargs["temperature"],
                            beam_size=transcribe_kwargs["beam_size"],
                            best_of=transcribe_kwargs["best_of"],
                            vad_filter=False,
                            word_timestamps=transcribe_kwargs["word_timestamps"],
                            initial_prompt=transcribe_kwargs["initial_prompt"],
                            no_speech_threshold=transcribe_kwargs[
                                "no_speech_threshold"
                            ],
                            compression_ratio_threshold=transcribe_kwargs[
                                "compression_ratio_threshold"
                            ],
                        )
                        fallback_succeeded = True
                    except Exception as fallback_error:
                        log(f"Fallback transcription error: {str(fallback_error)}")
                        log(
                            f"Fallback transcription traceback: {traceback.format_exc()}"
                        )

                if not fallback_succeeded:
                    # エラーが発生した場合は空の結果を返す
                    segments = []

                    class DummyInfo:
                        language = actual_language or "ja"

                    info = DummyInfo()

            detected_language = (
                info.language if actual_language is None else actual_language
            )
            elapsed_time = time.time() - start_time
            log(
                f"Transcription completed in {elapsed_time:.2f} seconds (detected language: {detected_language})"
            )

            transcription = " ".join([segment.text for segment in segments]).strip()
            log(f"Transcription result (raw): '{transcription}'")
            log(f"Transcription length: {len(transcription)} characters")

            transcription = post_process_text(
                transcription,
                detected_language,
                auto_punctuation=auto_punctuation,
            )
            log(f"Transcription result (post-processed): '{transcription}'")

            print(transcription, file=sys.stdout)
            sys.stdout.flush()
            log("Output flushed")

            if transcription_audio_path != audio_path and os.path.exists(
                transcription_audio_path
            ):
                try:
                    os.remove(transcription_audio_path)
                    log(f"Cleaned up temporary file: {transcription_audio_path}")
                except Exception as e:
                    log(f"Error removing temporary file: {str(e)}")

        except Exception as e:
            log(f"Error: {str(e)}")
            log(f"Traceback: {traceback.format_exc()}")
            print("", file=sys.stdout)
            sys.stdout.flush()


if __name__ == "__main__":
    main()
