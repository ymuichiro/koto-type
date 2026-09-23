# 中核音声入力への簡素化（Issue #132、作業中）

関連: https://github.com/ymuichiro/koto-type/issues/132
品質の受入条件: https://github.com/ymuichiro/koto-type/issues/131
調査基準: main `6fa3a04b47089be1a645b47caeca081b92377a00`

## 機能の判断台帳

|機能|入口・設定・依存|利用者への価値／確認した問題|判断|
|---|---|---|---|
|通常の音声入力|HotkeyManager → AppDelegate → RealtimeRecorder → MultiProcessManager → PythonProcessManager → whisper_server|製品の中核。忠実性と録音・挿入の安定性が必須|維持。改善は#131と同じ実音声・状態遷移の受入条件で確認|
|翻訳|翻訳ホットキー、翻訳先設定、録音mode、Pythonプロンプト／task／ASCIIゲート|同梱turboモデルが翻訳用に訓練されていない。ASCII判定は翻訳品質や英語判定にならない|提供を撤回。UI・永続設定・プロトコル・推論分岐を通して削除する。旧翻訳要求を通常文字起こしとして処理しない|
|画面OCR|AppDelegate.stopRecording → ScreenContextExtractor、画面収録権限、screenshot_context|停止時に同期Vision処理が録音停止より先に走る。合成画面の計測では約0.44–0.79秒。関連語彙による品質改善は未確定|削除候補。ただし語彙による効果を未検証のまま「不要」と断定しない。無関係な固定ヒントだけの比較を効果全体の証明にしない|
|ユーザー辞書|SettingsDraft、UserDictionaryManager、Python initial_prompt|専門用語の認識支援という中核価値がある|維持。プロンプト簡素化後も実語彙で確認|
|Voice Shortcuts|SettingsView、VoiceShortcutManager、shortcuts.json|登録済みアクションに利用者データがある。未利用とは確認できていない|保留。勝手に削除しない|
|履歴・音声回復|TranscriptionHistoryManager、録音ファイル保護|認識失敗時の再試行とデータ喪失防止|維持。コード削減の対象にしない|
|GPU/CPU切替とフォールバック|BackendManager、TranscriptionBackendStatus|利用環境と推論失敗への回復|維持。品質や状態の分岐を検証し、不要な重複だけを削減|
|常駐・ヘルスチェック・再試行|MultiProcessManager、PythonProcessManager、バックグラウンド待機設定|初動速度と復帰の責務がある一方、複数の寿命管理が複雑|責務整理対象。推論後idle復帰・切断・再録音の検証なしに単純削除しない|
|旧Whisper API互換性matrix|`scripts/check_whisper_backend_compatibility.py`、11条件、直接ライブラリ呼び出し|CI/Make/テスト/製品から参照されず、3秒440Hz純音・廃止済み翻訳taskを含む歴史的なAPI調査|実行コードとraw JSONを削除。要約だけ保持し、依存変更で必要になった場合に製品経路テストとして再導入|
|更新・署名|AppUpdater、release.yml、appcast.xml|安全な配布・更新に不可欠|維持|

翻訳モデルの根拠: https://github.com/openai/whisper#command-line-usage

## 翻訳設定の移行

- 旧`translationHotkeyConfig`と`translationTargetLanguage`は読み込み時に無視し、再保存しない。
- 通常ホットキー、言語、句読点、待機設定、タイムアウトを保持する。廃止フィールドの不正な型だけで設定全体を初期化しない。
- 設定以外の履歴・辞書・音声・Voice Shortcutsファイルを移行のために書き換えたり削除したりしない。
- `AppSettingsTests.testRetiredTranslationSettingsAreIgnoredWithoutLosingSettings`はメモリ上の旧JSON読み込みと再エンコードを検証する。実ユーザーファイルを変更しない。
- `SettingsManagerTests.testTranslationRemovalRoundTripsFileWithoutTouchingOtherData`で実ファイルのload→save→新しいmanagerでloadまで確認。不正型の廃止フィールドがあっても通常設定全体が一致し、load単体はファイルを書き換えず、save後に廃止2キーだけが落ちる。隣接する履歴・辞書・shortcuts・音声のテスト用sentinelは不変。
- 既存SettingsManagerTestsは実ユーザーのsettings.jsonを退避・削除・復元していたため、実行前にこの仕組みを撤去した。SettingsManagerに保存先URLを渡すinitializerを追加し、テストはUUID付き一時ディレクトリだけを使う。sharedの既定保存先と保護権限は変えない。新規抽象層・依存は追加しない。設定・draft・hotkeyの関連24テストが合格。これは配布アプリで設定画面を操作した証拠ではない。
- Swift側のtranslation target APIは録音セッション・キュー・再試行・Python送信を通して撤去済み。RecordingRequestMode型も削除済み。Python側も翻訳専用プロンプト、task選択、ASCII判定、mode/targetの内部伝播を削除し、CPU/MLXともtranscribeに固定した。
- パーサーは旧translate要求・不正なmodeをInvalidTranscriptionRequestで拒否し、request_id付きのinvalid_request応答を返す。#131の応答・回復処理をcleanup作業ツリーへ統合済み。翻訳要求を通常認識に変換したり空の成功を返したりしない。配布アプリのエラー表示・回復操作は別途確認が必要。

## 完了判定

### 状態所有者と終了・再試行の境界

|所有者|正本となる状態|終了通知・再試行の責務|
|---|---|---|
|AppDelegate / RecordingSessionContext|録音session、segment route、元音声ファイル、停止順のfinalization queue、hasFailedSegments|recorderからファイルを受けworkerへ渡す。成功/失敗でrouteを消費。未完了timeoutはworkerをcancelし、不完全な文を入力しない。音声の保存/破棄は明示的選択。ASR自体をここで再試行しない|
|RealtimeRecorder|録音機器・録音中の音声とファイル生成|録音開始/停止とファイル通知。推論workerの再起動や認識結果の確定を担当しない|
|BatchTranscriptionManager|session内の予定segmentと完了結果|全segment完了時のみ結合。失敗判定と挿入可否はsession側。独自の推論再試行はない|
|MultiProcessManager|worker、待ち行列、処理中segment、試行requestID、管理世代lifecycleID|送信失敗/通常終了は最大2回の再試行。推論timeoutは同じ重い推論を再送せず失敗通知。fatal終了は失敗通知＋復旧待機。健康監視・起動失敗の復旧はworker単位で、音声の成功通知とは別|
|PythonProcessManager|単一子プロセス・pipe・起動コマンド|起動/送信/停止とstdout・終了通知。音声の意味やsession確定は判断しない|
|Python BackendManager|CPU/MLXモデルのロード状態、backend選択|MLX失敗時のCPU fallbackは同じ要求内の回復。Swiftのプロセス再送とは別。要求ごとにtextかerrorを一度返す|
|ImportedAudioTranscriptionManager|単一importのpendingRequestIDとcompletion|一致する応答か終了で完了。録音session用の自動再送は使わない|

- 録音modeの状態は撤去したが、session・segment・workerの所有者は統合していない。異なる寿命の状態を一つに潰すことを削減としない。
- 遅延再試行/復旧の世代越境を発見。変更前の再現テストでは、再初期化後に古い音声が新workerへ送られ、古い復旧タイマーが新workerを停止した。initialize/stopでlifecycleIDを更新し、遅延処理の受付時に一致を確認することで両方を防止した。この安全性追加は#131へ帰属し、#132の削減には計上しない。
- この表は所有者の現状整理。watchdogと再初期化の並行実行、録音停止/即再録音、回復ダイアログを含む配布アプリの状態遷移検証は未完了。全競合を解消したという意味ではない。

### 確定差分（#133統合後のmainを基準）

- #131統合前のmain比較: Swiftは追加67行／削除280行、純減213行。Pythonは追加26行／削除200行、純減174行。製品コード合計の純減387行で、テスト削除や資料は含めない。Pythonには先行したCPU重複分岐の削除も含む。
- #131統合後の簡素化差分は、#133のmerge commit `e2b6e4d` を親として確定。製品Sourcesと`python/whisper_server.py`は追加100行・削除491行、純減391行。#131の安全性追加を削減と混同しない。全差分は25ファイル、追加353行・削除864行（テスト・資料を含む）。
- 廃止した保存設定は翻訳先と翻訳ホットキーの2項目。翻訳UI・設定・プロトコル・推論分岐は撤去済み。配布アプリで旧設定移行とエラー表示を操作する確認は未達。依存の削減は0。
- AppDelegateの`pressedRecordingModes`は宣言・insert・removeの3参照のみで読み取りがなく、録音可否や停止判定に使われないため削除。sessionとworker contextのmode保存、およびimport・retry・sendInputのmode引数も撤去。Python送信時だけ固定の`transcribe`を明示する。ホットキーのモード辞書・列挙ループ・アクション配列・RecordingRequestMode型も削除し、ひとつのHotkeyStateに押下状態と直前の修飾キーを集約した。
- 設定移行・HotkeyConfiguration・import・workerの関連48テストが合格。その後の書き込み専用集合削除はSwift buildとdiff --checkが成功。実キー入力・マイク・配布物での証拠ではない。
- mode伝播撤去後はworker・import・backend準備・full flowの31テストとbuildが合格。旧「modeを保つ」テストは、同じ入力音声パスを全3試行で保つ確認へ変更。プロトコルの実プロセス検証と#131統合後の検証は別途必要。
- ホットキー簡素化は、候補の3イベント列テストを先に実行して合格後、製品処理へ接続。同じテストを製品HotkeyStateに対して実行し、設定・workerを含む40テストが合格。キーリピート・無関係キー・修飾キー解除・設定変更の解除を対象とする。OSのグローバル監視・実キー入力のE2E検証とは区別する。
- 検証中、mode引数撤去で`startRecording`から`beginRecordingSession`の呼び出しを誤って削除した回帰をビルド警告と差分調査で発見し復元した。状態単体テストはこの結線欠落を検出しなかった。配布アプリの録音開始E2Eは必須の未達条件として残す。
- CPUのGPU無効時専用分岐と一般CPU分岐の本体がAST比較で完全一致することを確認し、前者を削除。設定によるGPU無効・ランタイム非対応は同じCPU経路で元のstatusを返す。MLX推論失敗後のCPU fallbackは維持。削除前のbackend関連43テスト、削除後のPython全123テスト、ruff・tyが合格。これは実モデル精度改善の証拠ではなく、同じ実行処理を一箇所にした削減。
- Python翻訳撤去は一時ファイルの候補で先に検証。言語7種類×context有無×辞書2種類×画面context4種類の112通りで、通常文字起こし用プロンプトが変更前と文字列一致。旧translate・未知mode・不正型の計8種類の拒否テストは変更前に失敗し、反映後に合格。既存の翻訳提供を前提とするテストは削除し、CPU/MLXのtaskがtranscribe固定になる確認へ置換した。Python全116テスト、ruff、tyが合格。これは音声精度を改善した証拠ではない。
- 実モデル回帰確認: 固定FLEURS `fleurs-00.wav`をmain基準版とcleanupのstdin→前処理→推論→後処理へ入力。CPU/MLXそれぞれ1回ずつ、両版の46文字の出力が一致し、返されたeffectiveBackendが指定と一致、元音声SHA-256が不変だった。辞書は空、言語ja、通常transcribe。ローカル実行スクリプト`/tmp/kototype-goals-XdWea0/verify_cleanup_live.py`と`cleanup-{cpu,mlx}-live-comparison.json`に記録。1件の回帰スモークであり、30件×3回の品質評価・配布アプリ・実マイクの代替ではない。PR前に検証資材を再現可能な形で整理する。
- #131統合は共通のmain基準と両作業ツリーの3方向比較で実施。requestIDを維持しつつmode/translationTargetLanguageを復活させないよう競合を解消した。品質PR #133はmerge commit `e2b6e4d` としてmainへ統合済み。簡素化commit `f5589d7` はそのcommitを親とし、共有変更を重複計上しない。Issue #132はPR・CI・配布アプリ確認だけでは閉じず、全受入条件が終わるまでOPENを維持する。
- 統合後のPython全127テスト、要求解析と実stdin応答の重点20テスト、ruff/tyが合格。Swiftビルドと応答・音声保存・batch・worker・import・hotkeyの関連49テストも合格。実マイク・目的アプリへの挿入・配布物は未検証。
- 統合版の実モデル確認: CPU/MLX各1プロセスに「旧翻訳要求→固定FLEURS音声の通常認識→存在しない音声」を連続送信。各request_idに対して順にinvalid_request・46文字の成功・invalid_audioが返り、空行や旧形式の出力はなかった。拒否後も認識が継続し、選択backendと元音声SHA-256の不変を確認。`/tmp/kototype-goals-XdWea0/verify_integrated_protocol_live.py`、`integrated-{cpu,mlx}-protocol-live.json`に記録。精度全体の合格や回復ダイアログの動作証拠ではない。
- 2026-09-23の参照棚卸しで、`BackendPreparationService` は製品Sourcesに生成箇所がなく、初期セットアップは `AppDelegate → MultiProcessManager` のbackend probeを使うと確認。旧クラスは別の `PythonProcessManager`・`scriptPath`・completion lock・timeoutを持ち、その専用3テストも実行されない製品経路を検証していた。クラス90行と専用テスト140行を削除し、実際の `MultiProcessManager` probeテストへ進捗Storeの更新検証を移した。`BackendPreparationProgress` と `BackendPreparationProgressStore`、実workerのprobe/timeout/fallbackは維持。公開機能・設定・依存・有効な再試行箇所は不変で、孤立していた状態所有箇所を1つ削減。
- この削除後、`cd KotoType && swift test --filter MultiProcessManagerTests` は29件成功、`cd KotoType && swift test` は286件成功、`git diff --check` 成功。配布アプリの起動・設定画面・録音E2Eは未確認。
- 2026-09-23の開発ツール棚卸しで、旧互換性matrixは296行・11条件で、Whisperライブラリを製品のstdio/前処理/gate経路を通さず直接呼び出していた。tracked raw JSONは16KBで、非音声の純音入力に対する transcript preview とローカルパスを含む。Make/CI/テスト/製品の参照がないこと、翻訳条件が製品から削除済みであることを確認し、runnerとraw artifactを削除。歴史的なAPI制約だけは本資料に残した。製品機能・設定・依存は変更していない。
- 削除前後で `tests/python` は各129件成功。削除後の全repo参照検索でrunner名・artifact名の実行参照は残らず、Python lint/type checksと `git diff --check` も合格。旧依存matrixを再実行していない。実モデル品質や現行ライブラリのMLX互換性を証明する変更ではない。
- 次の必須作業は状態所有者・再試行責務の棚卸し、説明と配布物の整合、全受入条件の検証。応答プロトコル変更との依存関係をPRで明記する。

移動・分割だけを削減量に数えない。最終差分で製品LOC、公開機能、保存設定、依存、状態の所有者、再試行箇所を再集計する。元の6大ファイル合計は7,818行だが、別ファイルへ移した分を成果に含めない。

単体テストだけで成功としない。#131では利用者の実マイク音声2回を基準版・修正版のCPU/MLXで限定比較したが、出力は同一で固有語の誤りも残った。2026-09-23にユーザーから追加録音2件の保存先が提示されたが、示された一時パス上にファイルがなく、評価には使えていない。さらに公開日本語/英語音声60件×3反復のMLXモデル候補比較ではLarge-v3の日本語CERと失敗率が改善したものの、疑問符・自動言語判定の誤りが残り、CPU版は未検証のため採用していない（集計と制約は品質側 `core-quality-progress.md`）。両作業ツリーで配布bundle内backendのhealthcheck・実音声要求とad-hoc署名は確認済みだが、GUI録音→目的アプリ入力、Developer ID/notarization・署名済み更新、状態遷移・品質/idleの受入条件は残る。Issue #131/#132は両方OPENのままにする。
