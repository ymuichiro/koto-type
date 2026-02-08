# Contributing to STT Simple

Thank you for your interest in contributing to STT Simple!

## 開発環境の設定

### 1. リポジトリをクローン

```bash
git clone https://github.com/yourusername/stt-simple.git
cd stt-simple
```

### 2. Python環境の設定

```bash
# UVがインストールされていることを確認
curl -LsSf https://astral.sh/uv/install.sh | sh

# 仮想環境の作成
uv venv
source .venv/bin/activate

# 依存パッケージのインストール
uv sync
```

### 3. Swiftアプリのビルド

```bash
cd STTApp
swift build
```

## 開発

### テスト

```bash
# Pythonテスト
source .venv/bin/activate
.venv/bin/python tests/python/test_transcription.py
.venv/bin/python tests/python/test_benchmark.py

# 型検査
.venv/bin/ty check python/

# リンティング
.venv/bin/ruff check python tests/python

# フォーマット
.venv/bin/ruff format python tests/python
```

### Swiftアプリの実行

```bash
cd STTApp
swift run
```

### アプリバンドルの作成

```bash
cd STTApp
./scripts/create_app.sh
```

### DMGの作成

```bash
cd STTApp
./scripts/create_dmg.sh
```

## コードスタイル

### Python

- **型検査**: tyを使用
- **リンティング**: ruffを使用
- **フォーマット**: ruff formatを使用
- **ドキュメント**: docstringを含める

### Swift

- **命名規則**: Swift API Design Guidelinesに従う
- **コメント**: 必要最小限
- **エラーハンドリング**: do-catchを使用

## プルリクエストの作成

1. フォークを作成
2. ブランチを作成: `git checkout -b feature/my-feature`
3. 変更をコミット: `git commit -m "Add some feature"`
4. ブランチをプッシュ: `git push origin feature/my-feature`
5. プルリクエストを作成

### プルリクエストのガイドライン

- 変更内容を明確に説明
- テストを追加または更新
- すべてのテストに合格
- コードスタイルガイドに従う

## バグ報告

バグを見つけた場合は、Issueを作成してください。以下の情報を含めてください：

- macOSのバージョン
- STT Simpleのバージョン
- 再現手順
- 期待される動作
- 実際の動作
- スクリーンショットまたはエラーログ（可能であれば）

## 機能リクエスト

新しい機能を提案する場合は、Issueを作成してください。以下の情報を含めてください：

- 機能の説明
- ユースケース
- 実装の提案（あれば）

## ライセンス

貢献はMIT Licenseの下でライセンスされます。

質問や提案があれば、お気軽にIssueを作成してください！
