# Issue 72 ノイズ環境向け音声前処理 評価レポート

## 結論

今回の再現可能なローカル評価では、単独採用候補として最も有効だったのは `ffmpeg_office_gate` です。

`ffmpeg_office_gate` は、現行の `dynaudnorm` / auto gain 系を外した軽い FFmpeg office preset に、低活動・低信頼の結果を棄却する gate を組み合わせた条件です。speech ありのケースでは CER 0.000 / dropped utterance 0% を維持しつつ、speech なしケースの false insertion を 100% から 20% まで下げました。p95 latency は 0.59s でした。

一方で、`ffmpeg_office` 単体、`ffmpeg_current`、`ffmpeg_current_no_gain` は false insertion を下げませんでした。背景話者が近い `background_jp_near` は `ffmpeg_office_gate` でも誤挿入が残ったため、人声音ノイズへの根本対策としては Apple Voice Processing または WebRTC APM のライブ録音パス評価が必要です。2026-06-02 にまず Apple Voice Processing をライブ録音パスへ標準有効化しました。

## 実施内容

- issue #72 の指定に合わせ、評価専用 CLI `tools/evaluate_noise_strategies.py` を追加
- macOS `say` と合成ノイズで、再現可能な小規模データセットを生成
- MLX Whisper `mlx-community/whisper-large-v3-turbo` で同一音声を複数 strategy に通して比較
- CER / false insertion / dropped utterance / latency / activity / segment confidence を JSON と Markdown に出力
- 評価 CLI の純粋ロジックを `tests/python/test_noise_strategy_eval.py` でテスト

実行コマンド:

```bash
PYTHONPATH=. .venv/bin/python tools/evaluate_noise_strategies.py
PYTHONPATH=. .venv/bin/python -m unittest tests/python/test_noise_strategy_eval.py
.venv/bin/ruff check tools/evaluate_noise_strategies.py tests/python/test_noise_strategy_eval.py
```

出力:

- `artifacts/evaluations/noise_preprocess_issue_72/runs/20260609_012439/results.json`
- `artifacts/evaluations/noise_preprocess_issue_72/runs/20260609_012439/report.md`

## 評価条件

評価ケースは 11 件です。

| group | cases |
|---|---|
| clean | `clean_short`, `clean_long` |
| office noise | `office_mid` |
| target + competing speaker | `competing_jp_mid`, `competing_jp_high`, `competing_en_mid` |
| background speaker only | `background_jp_far`, `background_jp_near`, `background_en_far` |
| non-speech only | `keyboard_only`, `silence` |

比較した strategy:

| strategy | 内容 |
|---|---|
| `none` | 前処理なし |
| `ffmpeg_current` | 現行相当: highpass / lowpass / `dynaudnorm` + auto gain |
| `ffmpeg_current_gate` | 現行相当 + 低活動・低信頼 gate |
| `ffmpeg_current_no_gain` | 現行相当から auto gain のみ無効化 |
| `ffmpeg_office` | highpass / lowpass / `afftdn`、`dynaudnorm` と auto gain なし |
| `ffmpeg_office_gate` | `ffmpeg_office` + 低活動・低信頼 gate |

## 集計結果

| strategy | mean CER | false insertion | dropped utterance | p50 latency | p95 latency | mean RTF |
|---|---:|---:|---:|---:|---:|---:|
| `ffmpeg_office_gate` | 0.000 | 20% | 0% | 0.56s | 0.59s | 0.162 |
| `ffmpeg_current_gate` | 0.000 | 80% | 0% | 0.56s | 0.59s | 0.162 |
| `none` | 0.000 | 100% | 0% | 0.55s | 0.56s | 0.156 |
| `ffmpeg_office` | 0.000 | 100% | 0% | 0.56s | 0.59s | 0.162 |
| `ffmpeg_current` | 0.000 | 100% | 0% | 0.56s | 0.59s | 0.163 |
| `ffmpeg_current_no_gain` | 0.000 | 100% | 0% | 0.56s | 0.60s | 0.161 |

## 観察結果

1. FFmpeg filter 単体では false insertion が改善しませんでした。

`none` / `ffmpeg_current` / `ffmpeg_current_no_gain` / `ffmpeg_office` は、speech なしケースで全て false insertion 100% でした。MLX Whisper は silence や keyboard noise に対しても「ご視聴ありがとうございました」などを生成するため、前処理だけで hallucination を止めるのは難しいです。

2. `ffmpeg_office_gate` は低活動ケースに効きました。

`background_jp_far`, `background_en_far`, `keyboard_only`, `silence` を棄却できました。speech ありケースは dropped 0% で、今回の合成 clean / office / competing-speaker mix では CER も悪化しませんでした。

3. 同じ gate でも `ffmpeg_current_gate` は効きにくいです。

実装前の現行相当 `dynaudnorm` / auto gain は、遠い背景話者や非人声音ノイズの activity を持ち上げます。そのため、同じ gate を足しても false insertion は 80% までしか下がりませんでした。実装前のコードも `build_audio_filter_chain_candidates()` の通常成功パスでは denoise より先に `highpass`, `lowpass`, `dynaudnorm` を通していました。

4. 近い背景話者はまだ残ります。

`background_jp_near` はどの strategy でも背景話者を転記しました。これは VAD / confidence gate では見分けにくい「十分に明瞭な人声」です。Apple Voice Processing や WebRTC APM がこの条件に効くかは、ライブ録音パスで raw / processed を保存して別途確認する必要があります。

5. 今回の CER は簡単すぎます。

合成 TTS で作った speech ありケースでは全 strategy が CER 0.000 でした。現実の採用判断には、issue #72 の要件どおり 100 文程度の実録または高品質合成データと、Mac 内蔵マイク / 口元マイクの両方が必要です。

## 現時点の採用判断

第一候補:

```text
ffmpeg_office_gate
```

製品仕様としては、ユーザー設定を増やさず、以下の単一標準処理に寄せるのが妥当です。

- live recording path では `dynaudnorm`, compressor, auto gain を標準から外す
- highpass / lowpass / stationary denoise は軽く残す
- audio activity と segment confidence による post-ASR gate を入れる
- gate は「背景話者が近い場合は防げない」前提で、過度に強めすぎない

不採用または保留:

| candidate | 判断 |
|---|---|
| `ffmpeg_current` | false insertion 100%。現行正規化が gate の効きも弱めるため、このまま強化する方向は弱い |
| `ffmpeg_current_no_gain` | auto gain だけ外しても false insertion は改善せず |
| `ffmpeg_office` | CER 悪化は見えないが、単体では false insertion 100% |
| Apple Voice Processing | 2026-06-02 に Swift 録音パスへ標準有効化。端末依存の問題に備え `KOTOTYPE_DISABLE_APPLE_VOICE_PROCESSING=1` で個別に退避可能 |
| WebRTC APM NS + AGC off | まだ未検証。依存追加と frame 処理実装が必要 |

## 次にやるべき検証

1. `ffmpeg_office_gate` を dev-only strategy としてライブ録音パスに接続する
2. Apple Voice Processing 有効時の実録データを raw 相当の既存評価ケースと比較する
3. WebRTC APM は AGC off / AEC off / NS low-high のみで、Apple Voice Processing の結果が不足した場合に比較する
4. 近い背景話者だけの実録データを必ず入れる
5. 30 分 dogfooding で latency / CPU / memory / false insertion を確認する

最終採用は、今回の `ffmpeg_office_gate` を暫定首位として、Apple Voice Processing と WebRTC APM のライブ録音データが揃ってから決めるべきです。

## 実装反映

2026-05-31 に `ffmpeg_office_gate` を標準処理として反映しました。

- runtime の標準 FFmpeg 前処理を `highpass=f=120,lowpass=f=6800,afftdn=nf=-28:tn=1` に変更
- `dynaudnorm`, compressor, auto gain の runtime 経路と環境変数を削除
- 既存の低活動スキップに加え、Whisper segment metrics による低信頼 gate を追加
- 評価 CLI だけは比較用に legacy current strategy を self-contained に保持

2026-06-02 に、追加の精度改善策として `RealtimeRecorder` の入力 tap 前に Apple Voice Processing を標準有効化しました。

- ユーザー設定は増やさず、ライブ録音では常に Apple Voice Processing を試行
- macOS / 入力デバイス都合で有効化できない場合は録音を止めず従来の raw input tap にフォールバック
- 互換性調査のみ `KOTOTYPE_DISABLE_APPLE_VOICE_PROCESSING=1` で capture-stage processing を無効化
- batch 音声作成ログに `appleVoiceProcessing=true/false` を出し、dogfooding 時に適用状況を確認可能にした
