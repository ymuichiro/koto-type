import unittest

from tools import evaluate_noise_strategies


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
        self.assertAlmostEqual(
            evaluate_noise_strategies.character_error_rate("確認します", "確認した"),
            0.4,
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


if __name__ == "__main__":
    unittest.main()
