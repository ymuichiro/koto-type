.PHONY: help run-app run-server test-transcription test-benchmark test-user-dictionary test-all build-server build-app build-all install-deps clean view-log capture-artifacts

# デフォルトターゲット
.DEFAULT_GOAL := help

PYTHON := uv run python
SERVER_SCRIPT := python/whisper_server.py
PYTHON_TEST_DIR := tests/python

help:
	@echo "KotoType - 利用可能なコマンド:"
	@echo ""
	@echo "アプリケーション:"
	@echo "  make run-app       - Swiftアプリケーションを起動"
	@echo "  make run-server     - Pythonサーバーを起動（テスト用）"
	@echo ""
	@echo "テスト:"
	@echo "  make test-transcription - 音声文字起こしテスト"
	@echo "  make test-benchmark - 速度ベンチマークテスト"
	@echo "  make test-user-dictionary - 辞書機能ユニットテスト"
	@echo "  make test-all       - すべてのテストを実行"
	@echo ""
	@echo "ビルド:"
	@echo "  make build-server  - Pythonサーバーバイナリをビルド"
	@echo "  make build-app     - Swiftアプリケーションをビルド"
	@echo "  make build-all     - すべてのビルド（Python + Swift）"
	@echo "  make install-deps  - Python依存関係をインストール"
	@echo ""
	@echo "ユーティリティ:"
	@echo "  make clean          - 一時ファイルを削除"
	@echo "  make view-log       - サーバーログを表示"
	@echo "  make capture-artifacts - クラッシュ調査用アーティファクトを収集"

run-app:
	@echo "Swiftアプリケーションを起動中..."
	cd KotoType && swift run

run-server:
	@echo "Pythonサーバーを起動中..."
	$(PYTHON) $(SERVER_SCRIPT)

test-transcription:
	@echo "音声文字起こしテストを実行中..."
	$(PYTHON) $(PYTHON_TEST_DIR)/test_transcription.py

test-benchmark:
	@echo "Whisper速度ベンチマークを実行中..."
	$(PYTHON) $(PYTHON_TEST_DIR)/test_benchmark.py

test-user-dictionary:
	@echo "辞書機能ユニットテストを実行中..."
	$(PYTHON) $(PYTHON_TEST_DIR)/test_user_dictionary.py

test-all: test-transcription test-benchmark test-user-dictionary
	@echo ""
	@echo "✓ すべてのテスト完了"

build-server:
	@echo "Pythonサーバーバイナリをビルド中..."
	uv run --extra dev pyinstaller --onefile --name whisper_server \
	  --hidden-import=ctranslate2 \
	  --hidden-import=faster_whisper \
	  $(SERVER_SCRIPT)

build-app:
	@echo "Swiftアプリケーションをビルド中..."
	cd KotoType && swift build

build-all: build-server build-app
	@echo "✓ すべてのビルド完了"

install-deps:
	@echo "Python依存関係をインストール中..."
	uv sync --extra dev

clean:
	@echo "一時ファイルを削除中..."
	rm -rf /tmp/recording_*.wav
	rm -rf /tmp/*_processed.wav
	@echo "完了"

view-log:
	@echo "サーバーログを表示:"
	@cat ~/Library/Application\ Support/koto-type/server.log

capture-artifacts:
	@echo "実行時アーティファクトを収集中..."
	./scripts/capture_runtime_artifacts.sh
