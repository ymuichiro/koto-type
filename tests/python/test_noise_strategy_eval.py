import unittest
from types import SimpleNamespace
from unittest import mock

from tools import evaluate_noise_strategies
from tools import check_benchmark_regression


class NoiseStrategyEvalTests(unittest.TestCase):
    def test_normalize_text_removes_spacing_and_punctuation(self):
        self.assertEqual(
            evaluate_noise_strategies.normalize_text(" Azure Functions、確認します。 "),
            "azurefunctions確認します",
        )

    def test_character_error_rate(self):
        self.assertEqual(
            evaluate_noise_strategies.character_error_rate("確認します", "確認します"),
            0.0,
        )
        cer = evaluate_noise_strategies.character_error_rate("確認します", "確認した")
        if cer is None:
            raise AssertionError(
                "character_error_rate returned None for a non-empty reference"
            )
        self.assertAlmostEqual(cer, 0.4)

    def test_nonverbal_proxies_are_deterministic_and_nonempty(self):
        cough = evaluate_noise_strategies.synthetic_cough_proxy(1.0)
        laughter = evaluate_noise_strategies.synthetic_laughter_proxy(1.0)

        self.assertEqual(len(cough), 16_000)
        self.assertEqual(len(laughter), 16_000)
        self.assertGreater(float(abs(cough).max()), 0.0)
        self.assertGreater(float(abs(laughter).max()), 0.0)

    def test_cpu_result_payload_preserves_text_and_confidence_metrics(self):
        result = evaluate_noise_strategies.cpu_result_payload(
            [
                SimpleNamespace(
                    text=" はい ",
                    avg_logprob=-0.2,
                    compression_ratio=1.1,
                    no_speech_prob=0.03,
                )
            ]
        )

        self.assertEqual(result["text"], "はい")
        self.assertEqual(
            result["segments"],
            [
                {
                    "avg_logprob": -0.2,
                    "compression_ratio": 1.1,
                    "no_speech_prob": 0.03,
                }
            ],
        )

    def test_cpu_backend_uses_managed_model_default(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            self.assertEqual(
                evaluate_noise_strategies.default_model("cpu"),
                evaluate_noise_strategies.whisper_server.default_managed_cpu_model_path(),
            )

    def test_summary_orders_false_insertions_before_latency(self):
        activity = evaluate_noise_strategies.whisper_server.AudioActivityStats(
            duration_seconds=1.0,
            peak_dbfs=-12.0,
            active_duration_seconds=1.0,
            active_ratio=1.0,
            window_count=1,
        )
        results = [
            evaluate_noise_strategies.EvalResult(
                run_index=0,
                case_id="speech",
                noise_condition="clean",
                strategy="fast_but_false",
                reference_text="確認します",
                hypothesis_text="確認します",
                normalized_reference="確認します",
                normalized_hypothesis="確認します",
                cer=0.0,
                false_insertion=False,
                dropped_utterance=False,
                preprocess_seconds=0.0,
                transcribe_seconds=0.1,
                total_seconds=0.1,
                audio_duration_seconds=1.0,
                realtime_factor=0.1,
                processed_audio_path="speech.wav",
                gate_reason=None,
                segment_metrics=[],
                activity=activity,
            ),
            evaluate_noise_strategies.EvalResult(
                run_index=0,
                case_id="silent",
                noise_condition="clean",
                strategy="fast_but_false",
                reference_text="",
                hypothesis_text="誤挿入",
                normalized_reference="",
                normalized_hypothesis="誤挿入",
                cer=None,
                false_insertion=True,
                dropped_utterance=False,
                preprocess_seconds=0.0,
                transcribe_seconds=0.1,
                total_seconds=0.1,
                audio_duration_seconds=1.0,
                realtime_factor=0.1,
                processed_audio_path="silent.wav",
                gate_reason=None,
                segment_metrics=[],
                activity=activity,
            ),
            evaluate_noise_strategies.EvalResult(
                run_index=0,
                case_id="speech",
                noise_condition="clean",
                strategy="slow_clean",
                reference_text="確認します",
                hypothesis_text="確認します",
                normalized_reference="確認します",
                normalized_hypothesis="確認します",
                cer=0.0,
                false_insertion=False,
                dropped_utterance=False,
                preprocess_seconds=0.0,
                transcribe_seconds=1.0,
                total_seconds=1.0,
                audio_duration_seconds=1.0,
                realtime_factor=1.0,
                processed_audio_path="speech.wav",
                gate_reason=None,
                segment_metrics=[],
                activity=activity,
            ),
            evaluate_noise_strategies.EvalResult(
                run_index=0,
                case_id="silent",
                noise_condition="clean",
                strategy="slow_clean",
                reference_text="",
                hypothesis_text="",
                normalized_reference="",
                normalized_hypothesis="",
                cer=None,
                false_insertion=False,
                dropped_utterance=False,
                preprocess_seconds=0.0,
                transcribe_seconds=1.0,
                total_seconds=1.0,
                audio_duration_seconds=1.0,
                realtime_factor=1.0,
                processed_audio_path="silent.wav",
                gate_reason=None,
                segment_metrics=[],
                activity=activity,
            ),
        ]

        summary = evaluate_noise_strategies.summarize(results)

        self.assertEqual(summary[0]["strategy"], "slow_clean")
        self.assertEqual(summary[1]["strategy"], "fast_but_false")

    def test_benchmark_gate_rejects_accuracy_or_speed_regression(self):
        baseline = {
            "current": {
                "mean_cer": 0.1,
                "false_insertion_rate": 0.0,
                "dropped_utterance_rate": 0.0,
                "p95_latency_seconds": 1.0,
                "mean_realtime_factor": 0.5,
            }
        }
        candidate = {"current": dict(baseline["current"], p95_latency_seconds=1.01)}
        self.assertEqual(
            check_benchmark_regression.regressions(baseline, candidate),
            ["current.p95_latency_seconds: 1.000000 -> 1.010000"],
        )


if __name__ == "__main__":
    unittest.main()
