#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import unittest
import tempfile
from python import whisper_server


class DecodeProfileTests(unittest.TestCase):
    def test_build_cpu_decode_profile_matches_presets(self):
        low = whisper_server.build_cpu_decode_profile("low")
        medium = whisper_server.build_cpu_decode_profile("medium")
        high = whisper_server.build_cpu_decode_profile("high")

        self.assertEqual(low.temperature, 0.0)
        self.assertEqual(low.beam_size, 1)
        self.assertEqual(low.best_of, 1)
        self.assertEqual(low.vad_threshold, 0.5)

        self.assertEqual(medium.beam_size, 5)
        self.assertEqual(medium.best_of, 5)
        self.assertEqual(medium.vad_threshold, 0.5)

        self.assertEqual(high.beam_size, 10)
        self.assertEqual(high.best_of, 10)
        self.assertEqual(high.vad_threshold, 0.5)

    def test_build_mlx_decode_profile_omits_non_compatible_controls(self):
        low = whisper_server.build_mlx_decode_profile("low")
        medium = whisper_server.build_mlx_decode_profile("medium")
        high = whisper_server.build_mlx_decode_profile("high")

        self.assertEqual(low.temperature, 0.0)
        self.assertIsNone(low.beam_size)
        self.assertIsNone(low.best_of)
        self.assertIsNone(low.vad_threshold)

        self.assertEqual(medium.temperature, (0.0, 0.2, 0.4))
        self.assertEqual(high.temperature, (0.0, 0.2, 0.4, 0.6, 0.8, 1.0))


class ParseRequestLineTests(unittest.TestCase):
    def test_parse_request_line_decodes_json_request(self):
        payload = whisper_server.parse_request_line(
            """
            {"type":"transcription_request","audio_path":"/tmp/test.wav","language":"ja","auto_punctuation":false,"quality_preset":"high","gpu_acceleration_enabled":true,"screenshot_context":"menu"}
            """
        )

        self.assertEqual(payload["kind"], "transcription")
        request = payload["request"]
        self.assertEqual(request.audio_path, "/tmp/test.wav")
        self.assertEqual(request.language, "ja")
        self.assertFalse(request.auto_punctuation)
        self.assertEqual(request.quality_preset, "high")
        self.assertTrue(request.gpu_acceleration_enabled)
        self.assertEqual(request.screenshot_context, "menu")

    def test_parse_request_line_treats_auto_language_as_none(self):
        payload = whisper_server.parse_request_line(
            '{"type":"transcription_request","audio_path":"/tmp/test.wav","language":"auto","quality_preset":"medium","gpu_acceleration_enabled":false}'
        )

        self.assertIsNone(payload["request"].language)

    def test_parse_request_line_decodes_backend_probe_request(self):
        payload = whisper_server.parse_request_line(
            '{"type":"backend_probe","gpu_acceleration_enabled":true,"preload_model":true}'
        )

        self.assertEqual(payload["kind"], "backend_probe")
        request = payload["request"]
        self.assertTrue(request.gpu_acceleration_enabled)
        self.assertTrue(request.preload_model)

    def test_parse_request_line_decodes_model_management_request(self):
        payload = whisper_server.parse_request_line(
            '{"type":"model_management","action":"download","model_kind":"mlx"}'
        )

        self.assertEqual(payload["kind"], "model_management")
        request = payload["request"]
        self.assertEqual(request.action, "download")
        self.assertEqual(request.model_kind, "mlx")


class FakeBackendManager(whisper_server.BackendManager):
    def __init__(
        self,
        *,
        probe_result=(False, "mlx_runtime_import_failed"),
        cpu_result=("cpu text", "ja"),
        mlx_result=("mlx text", "ja"),
        mlx_error=None,
    ):
        temp_root = tempfile.mkdtemp(prefix="kototype-backend-models-")
        super().__init__(
            state_path="/tmp/server_state.json",
            lock_path="/tmp/server_state.lock",
            pid=1234,
            max_parallel_model_loads=1,
            model_load_wait_timeout=1,
            cpu_model_dir=f"{temp_root}/cpu",
            mlx_model_dir=f"{temp_root}/mlx",
            model_cache_dir=f"{temp_root}/cache",
            log=lambda _: None,
        )
        self.probe_result = probe_result
        self.cpu_result = cpu_result
        self.mlx_result = mlx_result
        self.mlx_error = mlx_error
        self.cpu_calls = 0
        self.mlx_calls = 0
        self.cpu_warmups = 0
        self.mlx_warmups = 0

    def _probe_mlx_runtime(self):
        if self.mlx_disabled_for_session:
            return False, "mlx_disabled_for_session"
        return self.probe_result

    def _transcribe_with_cpu(self, audio_path, language, quality_preset, initial_prompt):
        self.cpu_calls += 1
        return self.cpu_result

    def _transcribe_with_mlx(self, audio_path, language, quality_preset, initial_prompt):
        self.mlx_calls += 1
        if self.mlx_error is not None:
            raise self.mlx_error
        return self.mlx_result

    def _ensure_cpu_model(self):
        self.cpu_warmups += 1
        return object()

    def _ensure_mlx_model(self):
        self.mlx_warmups += 1
        if self.mlx_error is not None:
            raise self.mlx_error

    def _download_cpu_model(self):
        whisper_server.ensure_private_directory(self.cpu_model_dir)
        for file_name in ("config.json", "model.bin", "tokenizer.json"):
            with open(f"{self.cpu_model_dir}/{file_name}", "w", encoding="utf-8") as handle:
                handle.write("ok")

    def _download_mlx_model(self):
        whisper_server.ensure_private_directory(self.mlx_model_dir)
        for file_name in ("config.json", "weights.safetensors"):
            with open(f"{self.mlx_model_dir}/{file_name}", "w", encoding="utf-8") as handle:
                handle.write("ok")


class BackendSelectionTests(unittest.TestCase):
    def make_request(self, gpu_acceleration_enabled):
        return whisper_server.TranscriptionRequest(
            audio_path="/tmp/test.wav",
            language="ja",
            auto_punctuation=True,
            quality_preset="medium",
            gpu_acceleration_enabled=gpu_acceleration_enabled,
            screenshot_context=None,
        )

    def test_gpu_off_forces_cpu(self):
        manager = FakeBackendManager(probe_result=(True, None))

        text, language, status = manager.transcribe(
            request=self.make_request(False),
            audio_path="/tmp/test.wav",
            initial_prompt=None,
        )

        self.assertEqual(text, "cpu text")
        self.assertEqual(language, "ja")
        self.assertEqual(status.effective_backend, "cpu")
        self.assertFalse(status.gpu_requested)
        self.assertTrue(status.gpu_available)
        self.assertEqual(status.fallback_reason, "gpu_disabled_in_settings")
        self.assertEqual(manager.cpu_calls, 1)
        self.assertEqual(manager.mlx_calls, 0)

    def test_gpu_on_uses_mlx_when_available(self):
        manager = FakeBackendManager(probe_result=(True, None))

        text, language, status = manager.transcribe(
            request=self.make_request(True),
            audio_path="/tmp/test.wav",
            initial_prompt=None,
        )

        self.assertEqual(text, "mlx text")
        self.assertEqual(language, "ja")
        self.assertEqual(status.effective_backend, "mlx")
        self.assertTrue(status.gpu_requested)
        self.assertTrue(status.gpu_available)
        self.assertIsNone(status.fallback_reason)
        self.assertEqual(manager.cpu_calls, 0)
        self.assertEqual(manager.mlx_calls, 1)

    def test_gpu_on_falls_back_to_cpu_when_mlx_unavailable(self):
        manager = FakeBackendManager(probe_result=(False, "mlx_runtime_import_failed"))

        text, language, status = manager.transcribe(
            request=self.make_request(True),
            audio_path="/tmp/test.wav",
            initial_prompt=None,
        )

        self.assertEqual(text, "cpu text")
        self.assertEqual(status.effective_backend, "cpu")
        self.assertTrue(status.gpu_requested)
        self.assertFalse(status.gpu_available)
        self.assertEqual(status.fallback_reason, "mlx_runtime_import_failed")
        self.assertEqual(manager.cpu_calls, 1)
        self.assertEqual(manager.mlx_calls, 0)

    def test_mlx_failure_disables_gpu_for_session_and_falls_back_to_cpu(self):
        manager = FakeBackendManager(
            probe_result=(True, None),
            mlx_error=RuntimeError("mlx failed"),
        )

        text, language, status = manager.transcribe(
            request=self.make_request(True),
            audio_path="/tmp/test.wav",
            initial_prompt=None,
        )

        self.assertEqual(text, "cpu text")
        self.assertEqual(language, "ja")
        self.assertEqual(status.effective_backend, "cpu")
        self.assertFalse(status.gpu_available)
        self.assertEqual(status.fallback_reason, "mlx_model_load_failed")
        self.assertTrue(manager.mlx_disabled_for_session)
        self.assertEqual(manager.cpu_calls, 1)
        self.assertEqual(manager.mlx_calls, 1)

        second_text, _, second_status = manager.transcribe(
            request=self.make_request(True),
            audio_path="/tmp/test.wav",
            initial_prompt=None,
        )

        self.assertEqual(second_text, "cpu text")
        self.assertEqual(second_status.fallback_reason, "mlx_disabled_for_session")
        self.assertEqual(manager.cpu_calls, 2)
        self.assertEqual(manager.mlx_calls, 1)

    def test_probe_backend_status_reports_mlx_without_preload(self):
        manager = FakeBackendManager(probe_result=(True, None))

        status = manager.probe_backend_status(
            gpu_acceleration_enabled=True,
            preload_model=False,
        )

        self.assertEqual(status.effective_backend, "mlx")
        self.assertEqual(manager.mlx_warmups, 0)
        self.assertEqual(manager.cpu_warmups, 0)

    def test_probe_backend_status_preloads_cpu_when_gpu_is_unavailable(self):
        manager = FakeBackendManager(probe_result=(False, "mlx_runtime_import_failed"))

        status = manager.probe_backend_status(
            gpu_acceleration_enabled=True,
            preload_model=True,
        )

        self.assertEqual(status.effective_backend, "cpu")
        self.assertEqual(status.fallback_reason, "mlx_runtime_import_failed")
        self.assertEqual(manager.cpu_warmups, 1)
        self.assertEqual(manager.mlx_warmups, 0)

    def test_probe_backend_status_falls_back_to_cpu_when_mlx_preload_fails(self):
        manager = FakeBackendManager(
            probe_result=(True, None),
            mlx_error=RuntimeError("mlx preload failed"),
        )

        status = manager.probe_backend_status(
            gpu_acceleration_enabled=True,
            preload_model=True,
        )

        self.assertEqual(status.effective_backend, "cpu")
        self.assertEqual(status.fallback_reason, "mlx_model_load_failed")
        self.assertTrue(manager.mlx_disabled_for_session)
        self.assertEqual(manager.mlx_warmups, 1)
        self.assertEqual(manager.cpu_warmups, 1)

    def test_managed_model_statuses_start_as_not_downloaded(self):
        manager = FakeBackendManager()

        statuses = manager.managed_model_statuses()

        self.assertEqual([status.kind for status in statuses], ["cpu", "mlx"])
        self.assertFalse(statuses[0].is_downloaded)
        self.assertFalse(statuses[1].is_downloaded)

    def test_download_managed_model_marks_cpu_model_as_downloaded(self):
        manager = FakeBackendManager()

        status = manager.download_managed_model("cpu")

        self.assertEqual(status.kind, "cpu")
        self.assertTrue(status.is_downloaded)
        self.assertGreaterEqual(status.file_count, 3)
        self.assertGreater(status.byte_count, 0)

    def test_delete_managed_model_removes_downloaded_assets(self):
        manager = FakeBackendManager()
        manager.download_managed_model("mlx")

        status = manager.delete_managed_model("mlx")

        self.assertEqual(status.kind, "mlx")
        self.assertFalse(status.is_downloaded)
        self.assertEqual(status.file_count, 0)
        self.assertEqual(status.byte_count, 0)


if __name__ == "__main__":
    unittest.main()
