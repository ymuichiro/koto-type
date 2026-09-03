import json
import unittest
import wave
from dataclasses import asdict
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from scripts import benchmark_asr_models


class BenchmarkLanguageOptionTests(unittest.TestCase):
    def test_auto_language_uses_whisper_language_detection(self):
        options = benchmark_asr_models.transcribe_kwargs("auto")

        self.assertIsNone(options["language"])
        self.assertEqual(options["task"], "transcribe")

    def test_explicit_language_is_preserved_for_comparison(self):
        options = benchmark_asr_models.faster_whisper_transcribe_kwargs("ja")

        self.assertEqual(options["language"], "ja")
        self.assertEqual(options["beam_size"], 1)
        self.assertEqual(options["best_of"], 1)

    def test_auto_and_explicit_options_only_differ_in_language_hint(self):
        auto_options = benchmark_asr_models.faster_whisper_transcribe_kwargs("auto")
        explicit_options = benchmark_asr_models.faster_whisper_transcribe_kwargs("ja")

        self.assertEqual(
            {key: value for key, value in auto_options.items() if key != "language"},
            {
                key: value
                for key, value in explicit_options.items()
                if key != "language"
            },
        )


class BenchmarkArtifactPrivacyTests(unittest.TestCase):
    def test_worker_result_does_not_serialize_audio_path(self):
        result = benchmark_asr_models.WorkerResult(
            label="test",
            backend="test",
            model_id="test-model",
            audio_seconds=1.0,
            load_seconds=0.1,
            cold_total_seconds=0.2,
            warm_run_seconds=[0.1],
            transcript_chars=1,
            transcript_preview="x",
            requested_language="ja",
        )

        self.assertNotIn("audio_path", json.loads(json.dumps(asdict(result))))

    def test_failure_artifact_does_not_store_local_audio_path(self):
        with TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            audio_path = temp_path / "input.wav"
            output_path = temp_path / "result.json"
            with wave.open(str(audio_path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(16_000)
                wav_file.writeframes(b"\x00\x00" * 16_000)

            with (
                patch.object(
                    benchmark_asr_models,
                    "MODEL_CONFIGS",
                    [{"label": "test", "backend": "test", "model_id": "test-model"}],
                ),
                patch.object(
                    benchmark_asr_models,
                    "run_subprocess",
                    side_effect=RuntimeError(f"traceback includes {audio_path}"),
                ),
            ):
                benchmark_asr_models.benchmark(
                    audio_path,
                    audio_path,
                    warm_runs=1,
                    output_path=output_path,
                    language="ja",
                )

            artifact_text = output_path.read_text(encoding="utf-8")
            artifact = json.loads(artifact_text)
            row = artifact["cases"][0]["rows"][0]
            self.assertNotIn("cwd", artifact["host"])
            self.assertNotIn("audio_path", row)
            self.assertNotIn(str(audio_path), artifact_text)
            self.assertEqual(row["error"], "RuntimeError")


if __name__ == "__main__":
    unittest.main()
