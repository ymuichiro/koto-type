# Issue #101: Japanese ending-fidelity diagnostic

This diagnostic checks whether Japanese sentence-final wording survives the
CPU/MLX, prompt, VAD, and post-processing stages. The fixed case list is in
`tests/data/ending_fidelity_corpus.json`.

The corpus intentionally contains the endings most often reported as changed:
`か`, `でしょうか`, `ませんか`, `ね`, and `よ`. Record or copy local audio as
`<case-id>.wav` in a temporary directory; do not commit recordings or result
files because they may contain speech content.

Run the full local matrix with already-downloaded models:

```bash
mkdir -p /tmp/kototype-ending-fidelity
# Put question_kadoka.wav, question_deshouka.wav, ... in that directory.
.venv/bin/python tools/evaluate_ending_fidelity.py \
  --audio-dir /tmp/kototype-ending-fidelity
```

For an existing JSON/JSONL result set, evaluate without loading a model:

```bash
.venv/bin/python tools/evaluate_ending_fidelity.py \
  --results /path/to/ending-results.jsonl
```

Each matrix row records `backend`, `prompt` (`baseline` or `ending`), `vad`,
`post_process`, and the resulting text. `ending_retention_rate` requires the
reference ending to remain at the end of the output. For question cases,
`question_to_declarative_rate` counts outputs that no longer end in `か` or a
question mark. This separates content loss from punctuation-only changes.

The implementation change for #101 is deliberately narrow:

- the Japanese prompt explicitly preserves sentence-final particles;
- MLX full-audio retry keeps the initial prompt instead of dropping it;
- Japanese post-processing converts only an existing question ending into `？`
  or adds `？` when `か` is already present. It never reconstructs a missing
  particle.

## Local diagnostic result

On 2026-08-23, macOS 26.5.2 / Apple Silicon, six system-TTS Japanese utterances
were evaluated locally with the already-downloaded CPU and MLX models. The
recordings were temporary synthetic audio, so this is a directional diagnostic,
not a substitute for real-user recordings.

| backend / prompt | ending retention | question-to-declarative |
| --- | ---: | ---: |
| CPU / baseline | 100% (24/24 conditions) | 0% |
| CPU / ending | 100% (24/24 conditions) | 0% |
| MLX / baseline | 50% | 33.3% (1/3 questions) |
| MLX / ending | 100% | 0% |

The VAD and post-processing toggles did not change these content metrics on
this corpus. The result supports the prompt as the primary fix for the
observed MLX suffix loss; real-user recordings remain the next validation gate.
