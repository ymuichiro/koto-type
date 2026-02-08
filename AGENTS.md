# STT Simple - エージェント全体方針

## 概要

このプロジェクトはMacネイティブの音声文字起こしアプリケーションを開発します。Swift + SwiftUI + Pythonの混合アプローチを採用し、シンプルかつ高精度な実装を目指します。

## アーキテクチャの全体像

### システム構成

```
┌─────────────────────────────────────┐
│  Swift アプリ (フロントエンド)        │
│  - メニューバー常駐                   │
│  - グローバルホットキー検知            │
│  - 音声録音                          │
│  - キーボード入力シミュレーション       │
└────────────┬────────────────────────┘
             │ 標準入出力で通信
             │ (音声ファイルパス/テキスト)
┌────────────┴────────────────────────┐
│  Python スクリプト (バックエンド)     │
│  - Whisperによる文字起こし           │
└─────────────────────────────────────┘
```

### 技術スタック

- **フロントエンド**: Swift 6.2.3 + SwiftUI + AppKit
- **バックエンド**: Python 3.13.7 + faster-whisper (large-v3-turbo)
- **パッケージ管理**: UV (Python) + Xcode (Swift)
- **ビルドツール**: Xcode, Swift Package Manager, PyInstaller
- **依存管理**: pyproject.toml, Package.swift
- **配布形式**: .appバンドル, .dmgディスクイメージ

## 開発の全体方針

### 優先順位

1. **シンプルさ**: 最小限の機能で実装、複雑さを避ける
2. **精度**: Whisperの精度重視設定を優先
3. **安定性**: エラーハンドリングは必要最低限 but 重要なものは実装
4. **パフォーマンス**: 処理速度より精度を優先（5-15秒の処理時間は許容）

### 開発フェーズ

#### フェーズ1: Pythonバックエンド実装
1. Whisperサーバースクリプトの実装
2. 精度重視パラメータの適用
3. コマンドラインでの動作確認

#### フェーズ2: Swiftフロントエンド実装
1. Xcodeプロジェクトの作成
2. メニューバーアプリの基本構造
3. グローバルホットキーの実装
4. 音声録音の実装
5. Pythonプロセス通信の実装
6. キーボード入力シミュレーションの実装

#### フェーズ3: 統合とテスト
1. SwiftとPythonの連携テスト
2. 実際のアプリケーションでの動作確認
3. エッジケースの対応

## 使用するスキル

### 1. uv-add
**用途**: Pythonパッケージの管理

**使用タイミング**:
- 新しいPythonパッケージが必要な場合
- 依存関係を更新する場合

**コマンド例**:
```bash
uv pip install <package>
uv sync
```

**重要事項**:
- すべてのPythonパッケージ管理にUVを使用
- 仮想環境（.venv）で作業
- pyproject.tomlを常に最新に保つ

### 2. swift-dev (推奨追加)
**用途**: Swift/Xcodeプロジェクトの作成と管理

**使用タイミング**:
- Swiftアプリを作成する場合
- Xcodeプロジェクトを設定する場合

**重要事項**:
- SwiftUIを使用したUI実装
- AppKitによるグローバルホットキーとCGEvent
- メニューバー常駐アプリの実装パターン

### 3. whisper-transcribe (推奨追加)
**用途**: Whisper音声認識の実装とテスト

**使用タイミング**:
- Whisperモデルのロードと使用
- 音声認識パラメータの調整
- 文字起こし結果の検証

**重要事項**:
- large-v3-turboモデルを使用
- 精度重視パラメータ（temperature=0.0, beam_size=5など）
- 日本語固定設定
- CPUで高速に動作（int8量子化を使用）

## プロジェクト構成

```
stt-simple/
├── .cline/
│   └── skills/
│       ├── uv-add/              # Pythonパッケージ管理
│       ├── swift-dev/           # Swift開発 (推奨)
│       └── whisper-transcribe/  # Whisper実装 (推奨)
├── STTApp/                     # Swift アプリ
│   ├── Sources/STTApp/
│   │   ├── App/
│   │   ├── Audio/
│   │   ├── Input/
│   │   ├── Transcription/
│   │   ├── UI/
│   │   └── Support/
│   └── Tests/
├── python/
│   └── whisper_server.py        # Python スクリプト
├── tests/
│   └── python/                  # Pythonテスト
├── pyproject.toml            # Python依存
├── DESIGN.md                   # 設計方針
├── ENV_CHECK.md                # 環境調査結果
├── AGENTS.md                   # このファイル
└── README.md                   # ユーザードキュメント
```

## コミュニケーションプロトコル

### Swift ↔ Python 通信

**プロトコル**: 標準入出力（stdio）

**メッセージ形式**:
- Swift → Python: 音声ファイルパス（1行）
- Python → Swift: 文字起こし結果（1行）

**例**:
```
# Swift sends:
/tmp/recording_123456.wav

# Python responds:
こんにちは、今日はいい天気ですね。
```

## エラーハンドリングの方針

### 最小限のエラーハンドリング

**実装すべきエラー**:
1. Pythonプロセスの起動失敗
2. 音声ファイルの作成失敗
3. Whisperモデルのロード失敗
4. グローバルホットキーの監視失敗

**実装不要なエラー**:
1. ユーザー入力の検証（単純な入力のみ）
2. 複雑なリカバリー処理
3. 通知システム（ログで十分）

## テスト方針

### コード変更後の必須テスト

**重要**: コードの変更を加えた後は、必ず以下を実行すること：

1. **テストコードの作成**: 変更した機能に対応するテストコードを作成する
2. **動作確認**: 作成したテストコードを実行し、コードの動作確認を行う

このプロセスはすべてのコード変更に対して必須であり、例外はない。

### 手動テストを優先

1. **単体テスト**: Pythonスクリプトの単独動作確認
2. **統合テスト**: SwiftとPythonの連携確認
3. **実地テスト**: 実際のアプリケーションでの使用テスト

### テストシナリオ

1. **基本フロー**: 録音 → 文字起こし → 入力
2. **短い音声**: 1-2秒の短い発話
3. **長い音声**: 30秒程度の発話
4. **無音**: 無音状態での動作

## パフォーマンス目標

- **起動時間**: 3秒以内
- **録音開始**: ホットキー押下から100ms以内
- **文字起こし**: 5-15秒（音声長による）
- **テキスト入力**: 結果取得から500ms以内

## メンテナンス方針

### バージョン管理

- Swift: Xcodeの互換性に従う
- Python: 3.13系を使用
- Whisper: 最新のlarge-v3モデル
- 依存パッケージ: 定期的なアップデート

### ドキュメント更新

- 変更があればDESIGN.mdを更新
- 新しい機能や変更があればREADME.mdを更新
- バグ修正や改善があればCHANGELOGを追加

## 開発時の注意点

### Swift開発

1. **メニューバーアプリ**: AppDelegateでNSStatusItemを使用
2. **グローバルホットキー**: NSEvent.addGlobalMonitorForEventsを使用
3. **CGEvent**: CGEventCreateKeyboardEventでキーボード入力シミュレーション
4. **非同期処理**: DispatchQueueでメインスレッドをブロックしない

### Python開発

1. **Whisperモデル**: 初期化時にロード、再利用
2. **エンコーディング**: UTF-8を明示的に指定
3. **ファイルパス**: 絶対パスを使用
4. **一時ファイル**: 使用後に必ず削除

## ビルドと配布

### ビルド手順

アプリケーションをビルドして配布可能な形式にする手順：

```bash
# 1. 依存関係のインストール（開発依存含む）
make install-deps

# 2. Pythonサーバーバイナリのビルド（PyInstaller使用）
make build-server

# 3. Swiftアプリのビルド
make build-app

# または、上記すべてを一括実行
make build-all

# 4. .appバンドルの作成
cd STTApp
./scripts/create_app.sh

# 5. .dmgディスクイメージの作成（オプション）
./scripts/create_dmg.sh
```

### Pythonサーバーのパッケージ化

PythonスクリプトはPyInstallerを使用して単一の実行ファイルにパッケージ化されます：

- **実行コマンド**: `uv run pyinstaller --onefile --name whisper_server ...`
- **出力先**: `dist/whisper_server`
- **組み込み場所**: `.app/Contents/Resources/whisper_server`
- **注意点**: C拡張モジュール（faster-whisper, ctranslate2）の収集に注意

### 配布形式

#### .appバンドル (STTApp.app)
- macOSアプリケーションの標準形式
- Applicationsフォルダにドラッグ＆ドロップして使用
- 単独で配布可能

#### .dmgディスクイメージ (STTApp-1.0.0.dmg)
- macOSアプリの一般的な配布形式
- ダブルクリックでマウント
- アプリとApplicationsフォルダへのリンクを含む
- 推奨配布形式

### 注意点

- 両形式ともアドホック署名を使用
- 初回起動時にGatekeeperの警告が表示される可能性
- ユーザーは「右クリック → 開く」で警告をバイパス可能
- Whisperモデルはアプリに含まれず、初回実行時にダウンロード

## 次のステップ

1. 必要なスキルを作成する（swift-dev, whisper-transcribeなど）
2. Pythonバックエンド（python/whisper_server.py）を実装
3. Swiftフロントエンド（STTApp）を実装
4. 統合テストを実施
5. ユーザードキュメント（README.md）を作成
