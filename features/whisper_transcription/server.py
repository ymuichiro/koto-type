#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from faster_whisper import WhisperModel
import os
from datetime import datetime
import traceback


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


def main():
    log_file, log = setup_logging()
    log("=== Server started ===")

    log("Loading Whisper model...")
    model = WhisperModel("large-v3-turbo", device="cpu", compute_type="int8")
    log("Model loaded")

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

            log(
                f"Received: audio={audio_path}, language={language}, temp={temperature}, beam={beam_size}"
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

            import time

            initial_prompt = None
            if language == "ja":
                initial_prompt = (
                    "これは会話の文字起こしです。正確な日本語で出力してください。"
                )
            elif language == "en":
                initial_prompt = (
                    "This is a speech transcription. Please output accurate English."
                )

            start_time = time.time()

            log("Starting transcription with Whisper...")

            segments, info = model.transcribe(
                audio_path,
                language=language,
                task="transcribe",
                temperature=temperature,
                beam_size=beam_size,
                best_of=5,
                vad_filter=True,
                word_timestamps=False,
                initial_prompt=initial_prompt,
            )

            elapsed_time = time.time() - start_time
            log(f"Transcription completed in {elapsed_time:.2f} seconds")

            transcription = " ".join([segment.text for segment in segments]).strip()
            log(f"Transcription result: '{transcription}'")
            log(f"Transcription length: {len(transcription)} characters")

            print(transcription, file=sys.stdout)
            sys.stdout.flush()
            log("Output flushed")

        except Exception as e:
            log(f"Error: {str(e)}")
            log(f"Traceback: {traceback.format_exc()}")
            print("", file=sys.stdout)
            sys.stdout.flush()


if __name__ == "__main__":
    main()
