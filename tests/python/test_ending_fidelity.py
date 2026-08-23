import unittest
from pathlib import Path

from tools.evaluate_ending_fidelity import evaluate_rows, load_corpus


class EndingFidelityEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.corpus = load_corpus(Path("tests/data/ending_fidelity_corpus.json"))

    def test_metrics_report_retention_and_question_declarative_rate(self):
        rows = [
            {
                "case_id": case_id,
                "backend": "cpu",
                "prompt": "ending",
                "vad": "off",
                "post_process": "on",
                "text": case["reference"],
            }
            for case_id, case in self.corpus.items()
        ]
        metrics = evaluate_rows(self.corpus, rows)["cpu/ending/off/on"]

        self.assertEqual(metrics["ending_retention_rate"], 1.0)
        self.assertEqual(metrics["question_to_declarative_rate"], 0.0)
        self.assertEqual(metrics["question_samples_observed"], 3)

    def test_metrics_detect_question_changed_to_declarative(self):
        rows = [
            {
                "case_id": "question_kadoka",
                "backend": "mlx",
                "prompt": "baseline",
                "vad": "on",
                "post_process": "off",
                "text": "これは実現できます",
            },
            {
                "case_id": "question_deshouka",
                "backend": "mlx",
                "prompt": "baseline",
                "vad": "on",
                "post_process": "off",
                "text": "この方法で問題ないでしょうか",
            },
        ]
        metrics = evaluate_rows(self.corpus, rows)["mlx/baseline/on/off"]

        self.assertEqual(metrics["ending_retention_rate"], 0.5)
        self.assertEqual(metrics["question_to_declarative_rate"], 0.5)


if __name__ == "__main__":
    unittest.main()
