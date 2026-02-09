#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "python"))

import whisper_server  # noqa: E402


class AudioPreprocessTests(unittest.TestCase):
    def test_build_audio_filter_chain_with_noise_reduction(self):
        chain = whisper_server.build_audio_filter_chain(enable_noise_reduction=True)
        self.assertIn("afftdn", chain)
        self.assertIn("highpass=f=100", chain)
        self.assertIn("lowpass=f=7800", chain)

    def test_build_audio_filter_chain_without_noise_reduction(self):
        chain = whisper_server.build_audio_filter_chain(enable_noise_reduction=False)
        self.assertNotIn("afftdn", chain)
        self.assertIn("dynaudnorm", chain)

    def test_build_audio_filter_chain_candidates(self):
        candidates = whisper_server.build_audio_filter_chain_candidates(
            enable_noise_reduction=True
        )
        self.assertEqual(len(candidates), 3)
        self.assertIn("anlmdn", candidates[0])
        self.assertIn("afftdn", candidates[1])
        self.assertNotIn("afftdn", candidates[2])

    def test_audio_preprocess_retries_without_denoise_filter(self):
        fake_ffmpeg = FakeFFmpegModule(fail_on_denoise=True)

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.wav"
            input_path.write_bytes(b"dummy")

            logs = []

            def capture_log(message):
                logs.append(message)

            original_env = os.environ.get("KOTOTYPE_ENABLE_NOISE_REDUCTION")
            original_auto_gain_env = os.environ.get("KOTOTYPE_AUTO_GAIN_ENABLED")
            os.environ["KOTOTYPE_ENABLE_NOISE_REDUCTION"] = "1"
            os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = "0"
            try:
                output_path = whisper_server.audio_preprocess(
                    str(input_path),
                    capture_log,
                    ffmpeg_module=fake_ffmpeg,
                    peak_analyzer=lambda _: -12.0,
                )
            finally:
                if original_env is None:
                    os.environ.pop("KOTOTYPE_ENABLE_NOISE_REDUCTION", None)
                else:
                    os.environ["KOTOTYPE_ENABLE_NOISE_REDUCTION"] = original_env
                if original_auto_gain_env is None:
                    os.environ.pop("KOTOTYPE_AUTO_GAIN_ENABLED", None)
                else:
                    os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = original_auto_gain_env

            self.assertTrue(output_path.endswith("_processed.wav"))
            self.assertEqual(fake_ffmpeg.run_call_count, 3)
            self.assertIn("afftdn", fake_ffmpeg.filter_history[0])
            self.assertIn("afftdn", fake_ffmpeg.filter_history[1])
            self.assertNotIn("afftdn", fake_ffmpeg.filter_history[2])
            self.assertTrue(
                any(
                    "trying next filter chain" in line
                    for line in logs
                ),
                "Expected fallback log when denoise filter fails",
            )

    def test_auto_gain_applies_boost_for_weak_input(self):
        fake_ffmpeg = FakeFFmpegModule(fail_on_denoise=False)

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.wav"
            input_path.write_bytes(b"dummy")

            logs = []

            def capture_log(message):
                logs.append(message)

            original_noise_env = os.environ.get("KOTOTYPE_ENABLE_NOISE_REDUCTION")
            original_auto_gain_env = os.environ.get("KOTOTYPE_AUTO_GAIN_ENABLED")
            os.environ["KOTOTYPE_ENABLE_NOISE_REDUCTION"] = "0"
            os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = "1"
            try:
                whisper_server.audio_preprocess(
                    str(input_path),
                    capture_log,
                    ffmpeg_module=fake_ffmpeg,
                    peak_analyzer=lambda _: -30.0,
                )
            finally:
                if original_noise_env is None:
                    os.environ.pop("KOTOTYPE_ENABLE_NOISE_REDUCTION", None)
                else:
                    os.environ["KOTOTYPE_ENABLE_NOISE_REDUCTION"] = original_noise_env
                if original_auto_gain_env is None:
                    os.environ.pop("KOTOTYPE_AUTO_GAIN_ENABLED", None)
                else:
                    os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = original_auto_gain_env

            self.assertEqual(fake_ffmpeg.run_call_count, 2)
            self.assertIn("volume=", fake_ffmpeg.filter_history[1])
            self.assertTrue(
                any("Applied automatic gain for weak input" in line for line in logs),
                "Expected auto gain log for weak input",
            )

    def test_auto_gain_request_overrides_environment_flag(self):
        fake_ffmpeg = FakeFFmpegModule(fail_on_denoise=False)

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "input.wav"
            input_path.write_bytes(b"dummy")

            original_auto_gain_env = os.environ.get("KOTOTYPE_AUTO_GAIN_ENABLED")
            os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = "0"
            try:
                whisper_server.audio_preprocess(
                    str(input_path),
                    lambda _: None,
                    ffmpeg_module=fake_ffmpeg,
                    peak_analyzer=lambda _: -40.0,
                    auto_gain_enabled=True,
                    auto_gain_weak_threshold_dbfs=-20.0,
                    auto_gain_target_peak_dbfs=-10.0,
                    auto_gain_max_db=9.0,
                )
            finally:
                if original_auto_gain_env is None:
                    os.environ.pop("KOTOTYPE_AUTO_GAIN_ENABLED", None)
                else:
                    os.environ["KOTOTYPE_AUTO_GAIN_ENABLED"] = original_auto_gain_env

            self.assertEqual(fake_ffmpeg.run_call_count, 2)
            self.assertIn("volume=9.00dB", fake_ffmpeg.filter_history[1])

    def test_determine_gain_for_weak_audio(self):
        gain = whisper_server.determine_gain_for_weak_audio(
            peak_dbfs=-30.0,
            weak_threshold_dbfs=-18.0,
            target_peak_dbfs=-10.0,
            max_gain_db=18.0,
        )
        self.assertEqual(gain, 18.0)

        no_gain = whisper_server.determine_gain_for_weak_audio(
            peak_dbfs=-12.0,
            weak_threshold_dbfs=-18.0,
            target_peak_dbfs=-10.0,
            max_gain_db=18.0,
        )
        self.assertEqual(no_gain, 0.0)

    def test_build_vad_parameters_strict_mode_default(self):
        original_env = os.environ.get("KOTOTYPE_VAD_STRICT")
        os.environ.pop("KOTOTYPE_VAD_STRICT", None)
        try:
            params = whisper_server.build_vad_parameters(0.5)
        finally:
            if original_env is not None:
                os.environ["KOTOTYPE_VAD_STRICT"] = original_env

        self.assertAlmostEqual(params["threshold"], 0.57, places=2)
        self.assertEqual(params["min_speech_duration_ms"], 320)
        self.assertEqual(params["min_silence_duration_ms"], 700)
        self.assertEqual(params["speech_pad_ms"], 80)

    def test_build_vad_parameters_non_strict_mode(self):
        original_env = os.environ.get("KOTOTYPE_VAD_STRICT")
        os.environ["KOTOTYPE_VAD_STRICT"] = "0"
        try:
            params = whisper_server.build_vad_parameters(0.5)
        finally:
            if original_env is None:
                os.environ.pop("KOTOTYPE_VAD_STRICT", None)
            else:
                os.environ["KOTOTYPE_VAD_STRICT"] = original_env

        self.assertAlmostEqual(params["threshold"], 0.5, places=2)
        self.assertEqual(params["min_speech_duration_ms"], 250)
        self.assertEqual(params["min_silence_duration_ms"], 500)
        self.assertEqual(params["speech_pad_ms"], 30)

    def test_parse_optional_values(self):
        self.assertIsNone(whisper_server.parse_optional_bool(None))
        self.assertTrue(whisper_server.parse_optional_bool("1"))
        self.assertFalse(whisper_server.parse_optional_bool("off"))
        self.assertIsNone(whisper_server.parse_optional_bool("maybe"))

        self.assertIsNone(whisper_server.parse_optional_float(None))
        self.assertEqual(whisper_server.parse_optional_float("1.5"), 1.5)
        self.assertIsNone(whisper_server.parse_optional_float("bad"))

    def test_should_retry_without_vad(self):
        err = Exception(
            "[ONNXRuntimeError] : 3 : NO_SUCHFILE : "
            "Load model from /tmp/faster_whisper/assets/silero_vad_v6.onnx failed"
        )
        self.assertTrue(whisper_server.should_retry_without_vad(err))

        unrelated = Exception("some other transcription error")
        self.assertFalse(whisper_server.should_retry_without_vad(unrelated))


class TranscriptionFallbackTests(unittest.TestCase):
    def test_retry_without_vad_when_vad_result_is_empty(self):
        model = FakeTranscribeModel(
            responses=[
                ([], SimpleNamespace(language="ja")),
                ([SimpleNamespace(text="こんにちは")], SimpleNamespace(language="ja")),
            ]
        )
        logs = []
        segments, info = whisper_server.transcribe_with_vad_fallback(
            model=model,
            transcribe_kwargs={
                "audio": "dummy.wav",
                "language": "ja",
                "task": "transcribe",
                "temperature": 0.0,
                "beam_size": 5,
                "best_of": 5,
                "word_timestamps": False,
                "initial_prompt": None,
                "no_speech_threshold": 0.6,
                "compression_ratio_threshold": 2.4,
            },
            vad_parameters={"threshold": 0.57},
            log=logs.append,
            fallback_on_empty_vad=True,
        )

        self.assertEqual(info.language, "ja")
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].text, "こんにちは")
        self.assertEqual(model.vad_filter_history, [True, False])
        self.assertTrue(
            any(
                "vad-enabled transcription returned empty" in message.lower()
                for message in logs
            )
        )

    def test_retry_without_vad_when_vad_segments_have_empty_text(self):
        model = FakeTranscribeModel(
            responses=[
                ([SimpleNamespace(text="  ")], SimpleNamespace(language="ja")),
                ([SimpleNamespace(text="テスト成功")], SimpleNamespace(language="ja")),
            ]
        )
        segments, _ = whisper_server.transcribe_with_vad_fallback(
            model=model,
            transcribe_kwargs={
                "audio": "dummy.wav",
                "language": "ja",
                "task": "transcribe",
                "temperature": 0.0,
                "beam_size": 5,
                "best_of": 5,
                "word_timestamps": False,
                "initial_prompt": None,
                "no_speech_threshold": 0.6,
                "compression_ratio_threshold": 2.4,
            },
            vad_parameters={"threshold": 0.57},
            log=lambda _: None,
            fallback_on_empty_vad=True,
        )

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].text, "テスト成功")
        self.assertEqual(model.vad_filter_history, [True, False])

    def test_retry_without_vad_when_vad_asset_missing(self):
        missing_vad_error = Exception(
            "[ONNXRuntimeError] : 3 : NO_SUCHFILE : "
            "Load model from /tmp/faster_whisper/assets/silero_vad_v6.onnx failed"
        )
        model = FakeTranscribeModel(
            responses=[
                missing_vad_error,
                ([SimpleNamespace(text="fallback success")], SimpleNamespace(language="ja")),
            ]
        )
        logs = []
        segments, _ = whisper_server.transcribe_with_vad_fallback(
            model=model,
            transcribe_kwargs={
                "audio": "dummy.wav",
                "language": "ja",
                "task": "transcribe",
                "temperature": 0.0,
                "beam_size": 5,
                "best_of": 5,
                "word_timestamps": False,
                "initial_prompt": None,
                "no_speech_threshold": 0.6,
                "compression_ratio_threshold": 2.4,
            },
            vad_parameters={"threshold": 0.57},
            log=logs.append,
            fallback_on_empty_vad=True,
        )

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].text, "fallback success")
        self.assertEqual(model.vad_filter_history, [True, False])
        self.assertTrue(
            any("missing vad asset" in message.lower() for message in logs)
        )


class FakeFFmpegModule:
    def __init__(self, fail_on_denoise=False):
        self.fail_on_denoise = fail_on_denoise
        self.filter_history = []
        self.run_call_count = 0

    def input(self, input_path):
        return FakeFFmpegPipeline(self)


class FakeFFmpegPipeline:
    def __init__(self, module):
        self.module = module
        self.filter_chain = ""
        self.output_path = None

    def output(self, output_path, acodec, ac, ar, af):
        self.filter_chain = af
        self.output_path = output_path
        self.module.filter_history.append(af)
        return self

    def overwrite_output(self):
        return self

    def run(self, quiet=True):
        self.module.run_call_count += 1
        if self.module.fail_on_denoise and "afftdn" in self.filter_chain:
            raise RuntimeError("No such filter: 'afftdn'")
        if self.output_path is not None:
            Path(self.output_path).write_bytes(b"processed")
        return None


class FakeTranscribeModel:
    def __init__(self, responses):
        self._responses = list(responses)
        self.vad_filter_history = []

    def transcribe(self, audio, **kwargs):
        self.vad_filter_history.append(kwargs.get("vad_filter"))
        if not self._responses:
            raise AssertionError("FakeTranscribeModel has no more responses")

        response = self._responses.pop(0)
        if isinstance(response, Exception):
            raise response

        return response


if __name__ == "__main__":
    unittest.main()
