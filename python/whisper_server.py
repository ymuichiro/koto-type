#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import traceback
from datetime import datetime


def setup_logging():
    log_dir = os.path.expanduser("~/Library/Application Support/stt-simple")
    os.makedirs(log_dir, exist_ok=True)

    log_file = os.path.join(log_dir, "server.log")

    def log(message):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{timestamp}] {message}\n"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(log_line)

    return log_file, log


def audio_preprocess(input_path, log):
    try:
        import ffmpeg

        base, ext = os.path.splitext(input_path)
        output_path = f"{base}_processed.wav"

        log(f"Preprocessing audio: {input_path} -> {output_path}")

        (
            ffmpeg.input(input_path)
            .output(
                output_path,
                acodec="pcm_s16le",
                ac=1,
                ar="16000",
                af=[
                    "highpass=f=200",
                    "lowpass=f=3000",
                    "dynaudnorm",
                    "acompressor=threshold=-20dB:ratio=4:attack=5:release=50",
                ],
            )
            .overwrite_output()
            .run(quiet=True)
        )

        log(f"Audio preprocessing completed: {output_path}")
        return output_path

    except ImportError:
        log("ffmpeg-python not available, skipping preprocessing")
        return input_path
    except Exception as e:
        log(f"Audio preprocessing failed: {str(e)}")
        return input_path


def post_process_text(text, language="ja"):
    if not text:
        return text

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

    if language == "ja":
        if text and not text.endswith(("。", "！", "？", "!", "?")):
            text += "。"

            text = text.replace("、 ", "、")

    return text


def load_user_dictionary():
    dict_path = os.path.expanduser(
        "~/Library/Application Support/stt-simple/user_dictionary.json"
    )
    try:
        if os.path.exists(dict_path):
            import json

            with open(dict_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("words", [])
    except Exception:
        pass
    return []


def generate_initial_prompt(language, use_context=True):
    base_prompts = {
        "ja": "これは会話の文字起こしです。正確な日本語で出力してください。",
        "en": "This is a speech transcription. Please output accurate English.",
    }

    prompt = base_prompts.get(language, "")

    if use_context:
        user_words = load_user_dictionary()
        if user_words:
            word_list = "、".join(user_words[:20])
            prompt += f" 以下の単語や専門用語を正確に認識してください: {word_list}。"

    return prompt if prompt else None


def main():
    log_file, log = setup_logging()
    log("=== Server started ===")

    log("Loading Whisper model...")

    # faster-whisperのみを使用
    from faster_whisper import WhisperModel

    model = WhisperModel(
        "large-v3-turbo",
        device="cpu",
        compute_type="int8",
    )

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

            actual_language = None if language == "auto" else language
            log(
                f"Received: audio={audio_path}, language={language}, actual_language={actual_language}, temp={temperature}, beam={beam_size}, "
                f"no_speech_threshold={no_speech_threshold}, compression_ratio_threshold={compression_ratio_threshold}, "
                f"task={task}, best_of={best_of}, vad_threshold={vad_threshold}"
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

            processed_audio_path = audio_preprocess(audio_path, log)

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

            import time

            initial_prompt = generate_initial_prompt(
                actual_language or language or "ja", use_context=True
            )

            start_time = time.time()

            log("Starting transcription with Whisper...")
            log(
                f"Transcription parameters: audio={transcription_audio_path}, language={actual_language}, task={task}, temperature={temperature}, beam_size={beam_size}, best_of={best_of}, vad_threshold={vad_threshold}, initial_prompt={initial_prompt[:50] if initial_prompt else None}..."
            )

            try:
                segments, info = model.transcribe(
                    transcription_audio_path,
                    language=actual_language,
                    task=task,
                    temperature=temperature,
                    beam_size=beam_size,
                    best_of=best_of,
                    vad_filter=True,
                    vad_parameters={
                        "threshold": vad_threshold,
                        "min_speech_duration_ms": 250,
                        "min_silence_duration_ms": 500,
                        "speech_pad_ms": 30,
                    },
                    word_timestamps=False,
                    initial_prompt=initial_prompt,
                    no_speech_threshold=no_speech_threshold,
                    compression_ratio_threshold=compression_ratio_threshold,
                )
            except Exception as transcribe_error:
                log(f"Transcription error: {str(transcribe_error)}")
                log(f"Transcription error traceback: {traceback.format_exc()}")
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

            transcription = post_process_text(transcription, detected_language)
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
