# STT Simple

Macネイティブの音声文字起こしアプリケーション。

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Python](https://img.shields.io/badge/Python-3.13-blue.svg)

## 特徴

- メニューバー常駐アプリ
- グローバルホットキー（Ctrl+Option+Space）で録音開始/停止
- OpenAI Whisperによる高精度な文字起こし
- 自動でテキストをカーソル位置に入力
- 完全オープンソース（MIT License）

## インストール

### DMGからインストール（推奨）

1. [最新リリース](https://github.com/yourusername/stt-simple/releases/latest)からSTTApp.dmgをダウンロード
2. ダウンロードしたDMGをダブルクリック
3. STTApp.appをApplicationsフォルダにドラッグ
4. 初回起動時のセキュリティ警告で「開く」をクリック

### ソースからビルド

#### 前提条件

- macOS 13.0以降
- Xcode 15.0以降
- Python 3.13
- uv

#### インストール手順

1. レポジトリをクローン
```bash
git clone https://github.com/yourusername/stt-simple.git
cd stt-simple
```

2. 依存関係のインストール（開発依存含む）
```bash
make install-deps
```

3. アプリケーションのビルド（Python + Swift）
```bash
make build-all
```

4. .appバンドルの作成
```bash
cd STTApp
./scripts/create_app.sh
```

5. （オプション）.dmgディスクイメージの作成
```bash
./scripts/create_dmg.sh
```

## 使用方法

### Makefileを使用した操作（推奨）

すべての操作はMakefileから実行できます。利用可能なコマンドを確認するには：

```bash
make help
```

#### アプリケーション

- `make run-app` - Swiftアプリケーションを起動
- `make run-server` - Pythonサーバーを起動（テスト用）

#### テスト

- `make test-transcription` - 音声文字起こしテスト
- `make test-benchmark` - 速度ベンチマークテスト
- `make test-all` - すべてのテストを実行

#### ビルド

- `make build-server` - Pythonサーバーバイナリをビルド（PyInstaller）
- `make build-app` - Swiftアプリケーションをビルド
- `make build-all` - すべてのビルド（Python + Swift）
- `make install-deps` - Python依存関係をインストール（開発依存含む）

#### ユーティリティ

- `make clean` - 一時ファイルを削除
- `make view-log` - サーバーログを表示

### 起動

DMGからインストールした場合：
1. LaunchpadからSTTAppを起動
2. または `open /Applications/STTApp.app`

ソースからビルドした場合：
```bash
# Makefileを使用（推奨）
make run-app

# または直接実行
cd STTApp
swift run
```

### 初期設定

1. **マイク権限**: 初回起動時にマイクへのアクセス権限を許可してください
2. **アクセシビリティ権限**: グローバルホットキーを使用するには、
   システム環境設定 > セキュリティとプライバシー > アクセシビリティ でSTTAppを許可してください

### 操作

1. アプリを起動すると、メニューバーに「STT」が表示されます
2. **Ctrl+Option+Space**を押すと録音が開始されます
3. もう一度**Ctrl+Option+Space**を押すと録音が停止します
4. 録音が完了すると、自動的に文字起こしが行われ、カーソル位置にテキストが入力されます
5. メニューの「Quit」または**Cmd+Q**で終了します

## セキュリティ警告について

このアプリは無料のアドホック署名で配布されているため、初回起動時にGatekeeperの警告が表示されます。

### 警告が表示された場合

**方法1: ダブルクリックで「開く」**
1. 右クリックまたはCtrl+クリック
2. 「開く」を選択

**方法2: システム環境設定で許可**
1. システム環境設定 > セキュリティとプライバシー
2. 「開く」をクリック

これはAppleの署名がないための正常な動作です。以降は警告なしで起動できます。

## プロジェクト構成

```
stt-simple/
├── python/
│   └── whisper_server.py       # Whisperサーバー
├── tests/
│   └── python/                 # Pythonテスト
│       ├── test_transcription.py
│       └── test_benchmark.py
├── STTApp/                     # Swiftアプリ
│   ├── Sources/STTApp/
│   │   ├── App/               # エントリポイントとパス解決
│   │   ├── Audio/             # 録音
│   │   ├── Input/             # ホットキー/入力
│   │   ├── Transcription/     # Pythonプロセス通信・バッチ制御
│   │   ├── UI/                # メニューバー/設定UI
│   │   └── Support/           # ロガー・設定・権限
│   ├── Package.swift
│   └── scripts/
│       ├── create_app.sh        # アプリ作成スクリプト
│       └── create_dmg.sh       # DMG作成スクリプト
├── pyproject.toml            # Python依存
├── LICENSE                    # MIT License
└── README.md                  # このファイル
```

## テスト

### Makefileを使用したテスト（推奨）

```bash
# 音声文字起こしテスト
make test-transcription

# 速度ベンチマークテスト
make test-benchmark

# すべてのテストを実行
make test-all
```

### 手動でのテスト

```bash
# 音声文字起こしテスト
uv run python3 tests/python/test_transcription.py

# 速度ベンチマークテスト
uv run python3 tests/python/test_benchmark.py
```

### サーバーログの確認

```bash
# Makefileを使用
make view-log

# または直接実行
tail -100 ~/Library/Application\ Support/stt-simple/server.log
```

### 型検査とリンティング

```bash
# 型検査（ty）
.venv/bin/ty check python/

# リンティング（ruff）
.venv/bin/ruff check python tests/python

# フォーマット
.venv/bin/ruff format python tests/python
```

## 開発

### ビルド

```bash
# Makefileを使用（推奨）
make build-all    # Python + Swiftの両方をビルド
make build-server # Pythonサーバーバイナリのみ
make build-app    # Swiftアプリのみ

# または直接実行
cd STTApp
swift build
```

### 実行

```bash
# Makefileを使用（推奨）
make run-app

# または直接実行
cd STTApp
swift run
```

### 依存関係のインストール

```bash
# Makefileを使用（推奨）
make install-deps

# または直接実行
uv sync
```

### クリーンアップ

```bash
# Makefileを使用
make clean
```

### 配布用ビルド

```bash
# 完全なビルド手順
make install-deps  # 依存関係のインストール
make build-all     # Python + Swiftのビルド
cd STTApp
./scripts/create_app.sh    # .appバンドルの作成
./scripts/create_dmg.sh    # .dmgディスクイメージの作成（オプション）
```

### PyInstallerについて

PythonサーバーはPyInstallerを使用して単一の実行ファイルにパッケージ化されます：

- **実行コマンド**: `uv run pyinstaller --onefile --name whisper_server ...`
- **出力先**: `dist/whisper_server`
- **組み込み場所**: `.app/Contents/Resources/whisper_server`
- **C拡張モジュール**: faster-whisper, ctranslate2 が自動的に収集されます

## トラブルシューティング

### マイクの権限
初回起動時にマイクへのアクセス権限を許可する必要があります。

### Whisperモデルのダウンロード
初回起動時にWhisperモデル（large-v3、約3GB）がダウンロードされます。

### ホットキーが動作しない
システム環境設定 > セキュリティとプライバシー > アクセシビリティ でSTTAppを許可してください。

### Pythonサーバーバイナリが見つからない
`make build-server` を実行してwhisper_serverバイナリを作成してください。

### PyInstallerのエラー
開発依存が正しくインストールされているか確認してください：
```bash
make install-deps
```

## リリース

リリースバイナリは[Releases](https://github.com/yourusername/stt-simple/releases)からダウンロードできます。

## ライセンス

[MIT License](LICENSE)

## 貢献

プルリクエストを歓迎します。

## 制限事項

- **マイクの権限**: システム設定で許可が必要
- **アクセシビリティ権限**: ホットキーとキーボードシミュレーションに必要
- **Whisperモデル**: 初回起動時に約3GBダウンロード

## Roadmap

- [ ] 複数言語のサポート
- [ ] キーボードショートカットのカスタマイズ
- [ ] 自動更新機能
- [ ] 設定UIの実装
