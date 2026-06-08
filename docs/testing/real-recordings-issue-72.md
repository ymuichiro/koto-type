# Issue 72 実録データ評価メモ

## 対象データ

- `/Users/you/Desktop/静かな環境.m4a`
- `/Users/you/Desktop/後ろで BGM がうるさい.m4a`

どちらも iPad Voice Memos 由来の stereo AAC です。2 本は同一発話ではないため、片方をもう片方の reference には使いませんでした。

## 結論

今回の実録 2 本だけでは、「ノイズ環境でも正しく認識するようになった」と定量判断するには不足しています。

理由:

- `静かな環境.m4a` と `後ろで BGM がうるさい.m4a` は同一発話ではありません
- 正解文字起こしが提供されていないため、厳密な CER / WER を計算できません
- FFmpeg filter の追加調整では、BGM 録音の主要 transcript は改善しませんでした

## 実施した比較

探索出力:

- `artifacts/evaluations/real_recordings_issue_72/runs/20260602_092619/results.json`

比較した filter:

- no preprocessing
- legacy current 相当
- current office preset
- band limit variants
- stronger `afftdn`
- `dialoguenhance` variants

BGM 録音では、上記 filter を変えても主要 transcript はほぼ同じでした。

```text
ある程度静かな環境でしっかり話した場合の音声、これはテスト音声です。GitHubの一周を登録してください。こんにちは。
```

## 次に必要な評価データ

本来期待した成果を判断するには、以下のどちらかが必要です。

1. 同じ発話内容を静音環境と BGM / ノイズ環境で録音したペア
2. 各録音ファイルに対する正解文字起こし

この条件が揃えば、今回の `ffmpeg_office_gate` / Apple Voice Processing / 追加候補 filter を CER / WER で比較できます。
