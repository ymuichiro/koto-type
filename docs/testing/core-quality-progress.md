# Issue #131 中間検証（未完了）

2026-09-22。基準は `6fa3a04b47089be1a645b47caeca081b92377a00`。
検証対象はこの基準上の未コミット作業差分であり、配布済み版ではない。
要求ID・失敗処理は変更中だが、ASRプロンプトの変更候補は未採用。

## 英語の実発話・対照基準

- 固定済みの30発話、3話者ID（1272・1462・1673）。ローカルの `english-manifest.json` に発話ID・参照文・音声SHA-256を保持。
- `verify_holdout_pipeline.py --backend cpu --corpus english` と `--backend mlx --corpus english`。各1反復。言語auto、medium、辞書なし。実際のPython stdin要求→前処理→モデル→後処理→要求ID付き応答を使用。
- CPU/MLXとも30応答、空結果0、エラー0、全入力のSHA-256不変。発話ごとのWERの平均はともに0.0275858399。英字を小文字化し、英数字・空白以外を除いて空白分割した単語列の編集距離で計算。コーパス全体を重み付けしたWERとは異なる。
- 完了ログは各30件すべて指定backend、検出言語en。MLX試行のstatus配列は収集側の形式判定不備で空だったため、backend確認は実行ログを根拠とする。後続CPU試行では収集処理を修正済み。
- 成果物: `/tmp/kototype-goals-XdWea0/english-{cpu,mlx}-current-30-pipeline.json`。ローカル調査用であり、これらの一時ファイルだけをPRの再現手順にしない。最終提出時に再現手順と集計を固定する。

これは修正前後の改善証明ではない。各3反復、重要な日本語の疑問・否定・数値・固有名詞、遅延許容差を固定した比較は別途必要。

## 誤った証拠の除外

### 小音量の切り分け（2026-09-22、探索のみ・未採用）

#### 低活動量を空の成功にしない修正

- 低活動量skipは従来text=""を成功として返し、推論用finallyの外でcontinueするため前処理コピーも残していた。実stdinの回帰テストで、無音/極小の非ゼロPCMの両方に空成功とコピー残留を再現。
- skip時はinsufficient_audioを返し、既存の音声回復経路へ渡す。元音声は削除せず、前処理コピーだけを削除する。完全な無音も「認識に十分な音声がない」という明示的失敗になり、成功扱いしない。
- 修正後はquality Python135件・cleanup129件、ruff/tyが合格。さらに本物のCV 10→FLEURS 00→CV 14を同じ実stdinプロセスへ送り、前後はinsufficient_audio、中央はMLXで46文字成功、全元音声SHA-256不変、前処理コピー残留0を確認した。`/tmp/kototype-goals-XdWea0/verify_low_activity_live.py`と`low-activity-recovery-live.json`に記録。
- 信頼できない録音を無言で成功・破棄へ進めないための修正であり、極小音量のASR精度を改善したとはしない。以下の音量補正自体は引き続き未採用。先に作成したローカル.appにはこの後続修正は未反映で、再ビルド・再検証が必要。

- Common Voice 10/14のpeakは前処理前から-61.68/-59.94 dBFS、前処理後は-68.03/-63.07 dBFS。active duration/ratioは前後とも0であり、モデルへ渡る前に低活動量判定で除外される。前処理が原因のすべてとはいえない。
- 固定FLEURS 00をPCM16へ変換した対照、それを40 dB減衰した対照、CV 10/14、無音、固定seedの低音量white noiseについて、現状とpeak -6 dBFSへの補正を比較。6入力×2条件×CPU/MLX各1回、実stdin→前処理→モデル→応答を実行。元のダウンロード音声のSHA-256は不変。
- 減衰したFLEURSは両backendで空結果になったが、補正後はCPU46文字/MLX47文字を返した。既知の発話でも絶対音量の閾値だけで全体が失われる再現である。ただし通常音量でも用語の誤認識があり、文字数や空でないことは精度合格ではない。
- CV 10/14は補正しても回復しない。MLXはcompression ratioによるunreliable_transcription、CPUは空結果。無音/white noiseに今回の偽挿入はなかったが、環境雑音全体への安全性は未証明。補正のみで極小音量音声の品質問題を解消できるとは判断しない。
- 製品のfilter/gateはこの実験では変更しない。一律正規化は未採用。録音由来の小音量・実環境雑音・3話者以上の対照で、欠落減少と偽挿入/語尾/数値/遅延の悪化がないことを確認する必要がある。
- ローカル資材: `/tmp/kototype-goals-XdWea0/probe_quiet_gain.py`、`quiet-gain-{cpu,mlx}-pilot.json`。振幅加工を含む補助実験であり、Issueの固定重要ケース・30発話×3反復の代替ではない。個人の音声や参照文を公開Issueへ転載しない。

`assets/audio/test_speech_ja.wav` は3秒・440Hzの純音。FFTの440Hz電力比は0.9999999322。
過去の「3秒日本語」のauto/ja比較を日本語認識精度の証拠に使わない。Issue #131本文も訂正済み。
純音をspeech smokeに使う既定値は撤去し、明示した音声入力を要求する変更を検証中。

## 未達条件

### 候補比較と採用判断の制約（2026-09-22〜23）

- 日本語短文prompt候補のCommon Voice悪化3例を再確認。19は主として「ほう/方」の表記差だが、1は語尾の時制/表現の書き換え、25は固有名の誤認識が残る。CER差をすべて意味変化とするのも、すべて無害な表記差とするのも不適切。平均CERが改善しただけで重要ケースの合格にはしない。
- FLEURS 21の単位誤り（参照50マイルに対する50m）はCPUの現行/無prompt/画面promptとMLX無promptに共通して残る。現行MLXの棄却を避けても、数値・単位保持は未達。後処理の置換で参照に合わせない。
- MLX候補 [`mlx-community/whisper-large-v3-mlx`](https://huggingface.co/mlx-community/whisper-large-v3-mlx/tree/49e6aa286ad60c14352c404340ded53710378a11) を一時取得し、revision `49e6aa286ad60c14352c404340ded53710378a11`、weights.npz 3,083,520,416 bytes、SHA-256 `05ff791ce3630fae47e7c51004e9666204d786246ec07cac6110af768099b40d` を確認。評価後、指示済みの一時モデルディレクトリだけを削除した。現行Turboは [`mlx-community/whisper-large-v3-turbo`](https://huggingface.co/mlx-community/whisper-large-v3-turbo)、ローカルHugging Face metadataのrevision `a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb`。
- 固定入力は[Common Voice Japanese](https://huggingface.co/datasets/FluidInference/cv-corpus-25.0-ja) 30件（公開manifest revision `365b7654cd582e20e8000921ef7b0e32caa1906a`、CC0-1.0、匿名speaker group 23組・1組あたり最大3件）と[LibriSpeech dev-clean](https://us.openslr.org/12/)英語30件（CC BY 4.0、3話者・各10件）。タグ付き日本語件数は疑問6、否定9、数値6、英語固有名詞6、15文字以下11。音声と参照文を含む選定manifestはローカル `/tmp/kototype-goals-XdWea0/{cv-balanced-v1/manifest.json,english-manifest.json}` にあり、リポジトリには未収録。このためPRだけでは同じ60件を再構成できず、再現可能なfixture化は未達。
- quality作業ツリーの実stdin→前処理→MLX→gate→後処理経路、language=auto、medium、既定prompt/VAD/gate/前処理、辞書なし。M4 Pro / 24 GiB。各60音声を3反復（同一音声の繰返しで独立標本180件ではない）、warmupを除外。結果はaggregateのみ保持し、個々の音声・認識文は保存しない。全入力のSHA-256は前後一致、backendは両モデル各180/180でMLX。
- Turbo→Large-v3の順で、日本語weighted CERは `0.6028 → 0.2605`、英語は `0.0128 → 0.0125`。日本語タグ別CER（Turbo→Large-v3）は固有名詞 `.5776→.3106`、否定 `.6897→.1839`、数値 `.5953→.2174`、疑問 `.6333→.2067`、短文 `.5755→.2547`。空/失敗応答は `36/180 → 6/180`（Turbo: unreliable 30 + insufficient_audio 6、Large-v3: insufficient_audio 6）。疑問符保持は `9/18 → 12/18`。自動言語の不一致は日本語で `9 → 6`、未判定は両方 `6`（いずれも3反復を含む）。
- backendログの推論時間（前処理・アプリ挿入を含まない）はp50/p95 `0.98/2.71秒 → 1.38/1.89秒`。単回パイロットでも同方向の差を確認。CERは各反復で同値だが、同一録音の反復は独立した利用者・話者サンプルではない。
- Large-v3はこの固定セットで改善する一方、疑問符・自動言語の誤りと低活動音声拒否が残り、ゼロの重要意味変更という受入条件を満たしたとはいえない。CPU版Large-v3は未取得・未評価。モデル既定値だけを変更すると、現行managed-modelsパスにあるTurbo重みを新モデルとして誤ロードするおそれがある。モデル識別・安全な保存先移行、CPU/MLX両方の比較、実機・配布アプリ検証、事前固定した速度許容差が済むまで製品モデルは切り替えない。

### 完了した待機負荷観測（backend単体、Issue全体は未完了）

- ハードウェア: Mac16,11 / Apple M4 Pro / 24 GiB。報告元のM4 MacBook Airそのものではない。
- `measure_backend_idle.py`で常駐MLX backendをpreloadし、60秒整定後、5分baseline→固定FLEURS実発話1件→前半5分→後半5分を3回。実マイク録音とSwiftアプリの停止処理は含めない。
- CPU/RSS集計は既存PR #127の`tools/measure_process_activity.py`（commit `e24da3581eee9e20ecac02a811fdfd6cae23dbff`）をローカルで再利用。新たな製品依存は追加していない。専用process group内の子プロセスも観測対象。
- 指標はmacOS `ps`のCPU率とRSS。GPU電力、システム電力、バッテリー、温度は測っていない。これだけで発熱問題の原因確定・解消としない。
- 短いpilotでは要求応答・観測・EOF終了・入力ファイル不変まで確認。初回pilotは計測側のtext bufferとselectの併用で応答待ちになり中断。非buffered pipeに直したpilotが完了してから長時間測定を開始した。
- 結果は`/tmp/kototype-goals-XdWea0/idle-mlx-three-runs.json`に各試行完了時点で追記される。開始しただけで合格とせず、全3試行と正常終了の記録を回収する。
- 1回目完了時点: baseline CPU p50/p95/maxはいずれも0%、推論後最後の5分もすべて0%。RSS中央値は1,751,232→1,813,984 KiB（約61.3 MiB増）、プロセス数は1→2。増えた子は実際の親子関係を確認したところPythonの`multiprocessing.resource_tracker`で、観測時CPU 0%、RSS 19,648 KiB。単に「残留worker」とは断定しない。2・3回目の増加傾向とbackend終了後の子の消滅を別途確認する。
- 全3回が完了し、各回の最後の5分はCPU p50/p95/maxすべて0%。RSS中央値の増分は順に62,752 / 1,168 / 352 KiB。初回以降の増分は小さいがゼロではなく、RSSが事前変動範囲に戻ったとは判定しない。
- 全区間でroot processが存在し、終了コード0、入力音声SHA-256不変。終了後のps確認で、観測したbackendとresource_trackerの両PIDは存在しなかった。
- 結論: この常駐MLX単体条件では10分続くCPU負荷を再現できなかった。電力・発熱の解消や、コード変更前後の改善を証明したものではない。同一プロセスでの3反復であり、独立した3起動の試験でもない。次は配布アプリの実行経路を対象にし、この未再現結果を理由にIssueを閉じない。

- 実発話品質を悪化させないASR改善方式の確定とCPU/MLX別の前後比較。
- 推論後10分待機×3と通常待機への負荷復帰、取得可能な電力指標。
- 配布アプリでの停止・再録音・入力切替・sleep・timeout・異常終了・保存操作。
- 同一commitのCI、署名済み配布物と更新、実マイク→目的アプリへの入力。
- #132の翻訳撤去との整合と別PRでの変更範囲確定。

## 実マイクの限定比較（2026-09-23）

- 利用者が起動した収録スクリプトで、同じ既知の日本語文を2回録音。18.10秒・18.17秒、16kHz mono WAV。各ファイルのSHA-256が処理前後で一致し、検証後にこの2つの一時ファイルを削除した。音声・全文・ハッシュはリポジトリやIssueへ保存しない。
- 同一音声を基準commit `6fa3a04b47089be1a645b47caeca081b92377a00` と quality作業ツリーのPython実stdin経路で処理。言語ja、medium、既定VAD/gate/prompt、辞書なし。CPU/MLXとも2録音を各1回ずつ比較した。
- 基準版と修正版、CPUとMLXで出力は一致。否定・数値・疑問の末尾は保持した一方、英語固有語の一部を誤認識した。修正差分がASR認識精度を改善した証拠ではなく、この2回だけでは対象症状の再現・解消を確定しない。
- 同一話者2回の直接backend試験であり、パッケージ、KotoType内蔵録音、目的アプリへの入力の証拠ではない。n=2かつ実装前に許容差を固定した計測でないため、CPU/MLX遅延の前後比較には使わない。

実マイクが利用できることは確認済み。ただし配布アプリでの実マイク→目的アプリ入力、他の状態遷移と負荷条件は未検証。公開音声3話者以上の候補比較は行ったが、選定manifestをリポジトリに固定して再実行可能にする条件は未達であり、Issue #131をOPENに保つ。
本Issueを自動closeするPRキーワードは使わない。

## 配布バイナリの限定検証（2026-09-23）

- quality/cleanup双方でPyInstaller backendを再構築し、バンドル内`Contents/Resources/whisper_server`を実行。healthcheckと公開日本語WAVを使ったCPU文字起こし要求に非空応答が返った。Smoke用入力のSHA-256はこの実行で前後測定していない。CPU結果には参照末尾との不一致があり、これは応答/実行経路の確認であって品質PASSではない。
- 両方の`.app`をrelease構成で作成し、必要resource/framework・bundle layout・deep/strict codesign検査が合格。署名はad-hocのみ。`KOTOTYPE_SPARKLE_PUBLIC_ED_KEY`未設定のためSparkle更新は無効。Developer ID、notarization、署名済み更新経路の検証ではない。
- quality側は録音/通信/worker関連Swift 71テスト、Python135テスト・ruff・ty、release buildが合格。quality側のSwift全件は実ユーザーApplication Support内のsettings.jsonを一時削除・復元する既存SettingsManagerTestsがあるため実行していない。cleanup側はこのテストを一時dirへ隔離した上でSwift全289、Python129テスト・ruff・ty、release buildが合格。テスト・backend smokeはGUI録音や目的アプリへの挿入を行っていない。

## Worker lifecycle isolation (2026-09-22)

Two executable regressions reproduced stale scheduled work crossing initialize:
an old audio retry reached the new worker, and an old recovery timer stopped
the new worker. MultiProcessManager now renews its lifecycle ID on initialize
and stop; delayed retries and recovery validate that ID before acting.
Both mocked reproductions pass after the change. A further test,
`MultiProcessManagerTests.testRealProcessRetryCannotCrossReinitialization`,
uses real PythonProcessManager pipes and OS child processes: the old request
exits with status 1, reinitialization occurs after retry scheduling, and only
the fresh request completes. The child-written attempt log contains exactly
old.wav then new.wav; all recorded child PIDs are absent after stop.
No ASR model or microphone is involved. Python is selected by
`KOTOTYPE_TEST_PYTHON` or /usr/bin/python3 (unavailable Python skips this test).
This Mac ran it, without a skip, with Python 3.9.6.
All 40 worker/import/response tests pass in each worktree. This is not packaged
microphone evidence; concurrent watchdog/reinitialize coverage and the Issue's
complete state-transition matrix remain required.
