# STT Simple - 設計方針

## 概要

Macネイティブの音声文字起こしアプリケーション。OpenAI Whisperを使用し、グローバルホットキー（Ctrl+Alt長押し）で音声を認識し、カーソル位置にテキスト入力する。

## アーキテクチャ

### 言語・フレームワーク選定

**Swift + SwiftUI + Python（混合アプローチ）**

- **Swift + SwiftUI**: MacネイティブアプリのUI・グローバルホットキー・キーボード入力シミュレーション
- **Python**: OpenAI Whisperによる音声認識

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

## 主要コンポーネント

### 1. Swift アプリ

**ライブラリ**:
- SwiftUI (UI)
- AppKit (グローバルホットキー、CGEvent)

**機能**:
- メニューバーに常駐（アイコン + メニュー）
- `Ctrl+Alt` 長押しのグローバルイベント監視
- 録音の開始・停止（AVFoundation）
- Pythonプロセス起動・通信（Process）
- 他アプリへのテキスト入力（CGEvent）

### 2. Python スクリプト

**ライブラリ**:
- `faster-whisper` (音声認識)
- `sys` (標準入出力)

**機能**:
- 音声ファイルパスを受け取る
- Whisperで文字起こし（精度重視設定）
- 結果を標準出力

#### Whisperモデル設定（精度重視）

**使用モデル**: `large-v3-turbo`（最新のLarge Turboモデル）

**精度向上のためのパラメータ**:

```python
from faster_whisper import WhisperModel

model = WhisperModel(
    "large-v3-turbo",
    device="cpu",
    compute_type="int8"
)

segments, info = model.transcribe(
    audio_file,
    
    # 言語設定
    language="ja",              # 日本語固定（自動検出より精度向上）
    task="transcribe",          # 文字起こし（翻訳ではなく）
    
    # デコーディング精度設定
    temperature=0.0,            # 最も確定的な出力（精度重視）
    beam_size=5,                # ビームサーチで探索（デフォルト1から増加）
    best_of=5,                  # 複数サンプルから最良を選択
    
    # 品質フィルタ設定
    vad_filter=True,             # VAD（Voice Activity Detection）を使用
    vad_parameters={"threshold": 0.5},  # VADの閾値
    no_speech_threshold=0.6,    # 無音検出の閾値
    compression_ratio_threshold=2.4,  # 圧縮率による品質判定
    
    # その他
    initial_prompt="これは会話の文字起こしです。正確な日本語で出力してください。"  # 初期プロンプト
)

# 結果を結合
text = " ".join([segment.text for segment in segments])
```

**パラメータの説明**:
- **temperature=0.0**: 最も確定的な出力を生成し、一貫性を向上
- **beam_size=5 & best_of=5**: ビームサーチで複数候補から最適な選択
- **compute_type="int8"**: 8ビット量子化でメモリ使用量を削減し、高速化
- **language="ja"**: 日本語固定で自動検出の誤りを回避
- **initial_prompt**: 文脈を与えて期待する出力形式を誘導

**処理時間への影響**:
- モデルサイズ（large-v3-turbo）とint8量子化により、処理時間は中程度の音声で5-10秒程度
- faster-whisperの最適化により、CPUでも高速に処理可能

## 実装フロー

1. **初期化**:
   - Swiftアプリ起動
   - メニューバーにアイコン表示
   - Pythonプロセスをバックグラウンドで起動

2. **待機状態**:
   - グローバルホットキー監視開始

3. **録音開始** (`Ctrl+Alt` 長押し):
   - 録音開始
   - ユーザーに視覚的フィードバック（メニューバーアイコンの色変更など）

4. **録音停止** (`Ctrl+Alt` リリース):
   - 録音停止
   - 音声ファイルを一時保存
   - Pythonにファイルパスを送信

5. **文字起こし**:
   - Whisperで処理
   - 結果をSwiftに返却

6. **入力**:
   - Swiftが結果を受け取り
   - CGEventで現在のカーソル位置にテキスト入力

## シンプルさを維持するための設計方針

1. **最小限のUI**: メニューバー常駐のみ、複雑な設定画面なし
2. **単一設定**: ホットキーは固定（Ctrl+Alt）でユーザー設定不可
3. **一時ファイル**: 録音ファイルは一時的に保存し、使用後削除
4. **同期通信**: Pythonとの通信は同期的に行い、処理を単純化
5. **エラーハンドリング最小化**: 基本的なエラーのみ処理

## ディレクトリ構成

```
stt-simple/
├── STTApp/                    # Swift アプリ
│   ├── Sources/STTApp/
│   │   ├── App/
│   │   ├── Audio/
│   │   ├── Input/
│   │   ├── Transcription/
│   │   ├── UI/
│   │   └── Support/
│   └── Tests/
├── python/
│   └── whisper_server.py     # Python スクリプト
├── tests/
│   └── python/               # Pythonテスト
├── pyproject.toml           # Python依存
└── README.md
```

## 実装の容易さ

- **グローバルホットキー**: SwiftのNSEvent.monitorで数行で実装可能
- **音声録音**: AVFoundationを使用、標準的な録音コード
- **Whisper**: Pythonなら `whisper.load_model()` と `model.transcribe()` の2行
- **キーボード入力**: CGEventCreateKeyboardEvent でシンプルに実装
