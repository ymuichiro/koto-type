# KotoType - Design Document

## Overview

A Mac-native voice-to-text application using OpenAI Whisper. The app recognizes speech via a global push-to-talk hotkey (default: Command+Option) and types the transcribed text at the cursor position.

## Architecture

### Technology Stack Selection

**Swift + SwiftUI + Python (Hybrid Approach)**

- **Swift + SwiftUI**: Mac-native UI, global hotkeys, and keyboard input simulation
- **Python**: OpenAI Whisper for speech recognition

### System Architecture

```
┌─────────────────────────────────────┐
│  Swift App (Frontend)               │
│  - Menu bar resident                │
│  - Global hotkey detection          │
│  - Audio recording                  │
│  - Keyboard input simulation        │
└────────────┬────────────────────────┘
             │ Stdio communication
             │ (audio file path / text)
┌────────────┴────────────────────────┐
│  Python Script (Backend)             │
│  - Whisper transcription            │
└─────────────────────────────────────┘
```

## Core Components

### 1. Swift Application

**Libraries**:
- SwiftUI (UI)
- AppKit (Global hotkeys, CGEvent)

**Features**:
- Menu bar resident (icon + menu)
- Global event monitoring for a configurable hotkey (default: `⌘+⌥`)
- Recording start/stop (AVFoundation)
- Python process launch and communication (Process)
- Text input to other applications (CGEvent)
- Audio file import (`wav` / `mp3`) for transcription
- History management (save/view past transcriptions)
- Auto-start at login (toggle on/off)
- First-time setup wizard (permissions & FFmpeg check)

### 2. Python Script

**Libraries**:
- `faster-whisper` (speech recognition)
- `sys` (standard I/O)
- `ffmpeg` (uses user-installed executable)

**Features**:
- Receive audio file path from stdin
- Transcribe with Whisper (accuracy-optimized settings)
- Output result to stdout

#### Whisper Model Configuration (Accuracy-Optimized)

**Model**: `large-v3-turbo` (latest Large Turbo model)

**Parameters for Improved Accuracy**:

```python
from faster_whisper import WhisperModel

model = WhisperModel(
    "large-v3-turbo",
    device="cpu",
    compute_type="int8"
)

segments, info = model.transcribe(
    audio_file,
    
    # Language settings
    language="ja",              # Fixed Japanese (more accurate than auto-detection)
    task="transcribe",          # Transcription (not translation)
    
    # Decoding accuracy settings
    temperature=0.0,            # Most deterministic output (accuracy-focused)
    beam_size=5,                # Beam search exploration (increased from default 1)
    best_of=5,                  # Select best from multiple samples
    
    # Quality filter settings
    vad_filter=True,             # Use VAD (Voice Activity Detection)
    vad_parameters={"threshold": 0.5},  # VAD threshold
    no_speech_threshold=0.6,    # Silence detection threshold
    compression_ratio_threshold=2.4,  # Quality judgment by compression ratio
    
    # Other
    initial_prompt="これは会話の文字起こしです。正確な日本語で出力してください。"  # Initial prompt
)

# Combine results
text = " ".join([segment.text for segment in segments])
```

**Parameter Explanations**:
- **temperature=0.0**: Generates most deterministic output, improving consistency
- **beam_size=5 & best_of=5**: Beam search selects optimal from multiple candidates
- **compute_type="int8"**: 8-bit quantization reduces memory usage and increases speed
- **language="ja"**: Fixed Japanese avoids auto-detection errors
- **initial_prompt**: Provides context to guide expected output format

**Processing Time Impact**:
- Model size (large-v3-turbo) and int8 quantization result in 5-10 second processing time for medium audio
- faster-whisper optimizations enable fast CPU processing

## Implementation Flow

1. **Initialization**:
   - Launch Swift app
   - First-time setup wizard checks:
     - Accessibility permissions
     - Microphone permissions
     - `ffmpeg` command availability
   - Python backend is auto-resolved:
     - Release: Use bundled `whisper_server` (no Python/uv needed for users)
     - Development: `uv run` auto-prepares dependencies and launches
   - Transition to menu bar resident mode when conditions are met
   - Launch Python process in background

2. **Idle State**:
   - Start global hotkey monitoring

3. **Recording Start** (configured hotkey press and hold):
   - Start recording
   - Provide visual feedback (menu bar icon color change, etc.)

4. **Recording Stop** (configured hotkey release):
   - Stop recording
   - Save audio file temporarily
   - Send file path to Python

5. **Transcription**:
   - Process with Whisper
   - Return result to Swift

6. **Input**:
   - Swift receives result
   - Type text at current cursor position using CGEvent

7. **History Management**:
   - Save recording/import results to JSON in Application Support
   - View/copy from history window via menu

8. **Launch Settings**:
   - Toggle auto-start at login from Settings
   - Reflect registration status with `ServiceManagement`

## Release Design

- Manage distribution version with `VERSION` file
- Pushing to `main` automatically creates tag in format `v<VERSION>.<run_number>`
- Tag push triggers GitHub Actions to build `.app/.dmg`
- Attach `.dmg` to tag Release as distribution installer
- Avoid GPL risk by not bundling FFmpeg, validate system `ffmpeg` in initial setup

## Design Principles for Simplicity

1. **Minimal UI**: Menu bar resident only, no complex settings screens
2. **Simple Default**: Hotkey defaults to Command+Option and can be customized in Settings
3. **Temporary Files**: Save recording files temporarily, delete after use
4. **Synchronous Communication**: Communicate with Python synchronously to simplify processing
5. **Minimal Error Handling**: Handle only essential errors

## Directory Structure

```
koto-type/
├── KotoType/                    # Swift app
│   ├── Sources/KotoType/
│   │   ├── App/
│   │   ├── Audio/
│   │   ├── Input/
│   │   ├── Transcription/
│   │   ├── UI/
│   │   └── Support/
│   └── Tests/
├── python/
│   └── whisper_server.py     # Python script
├── tests/
│   └── python/               # Python tests
├── pyproject.toml           # Python dependencies
└── README.md
```

## Implementation Ease

- **Global Hotkey**: Implementable in few lines with Swift's NSEvent.monitor
- **Audio Recording**: Standard recording code using AVFoundation
- **Whisper**: Just two lines in Python: `whisper.load_model()` and `model.transcribe()`
- **Keyboard Input**: Simple implementation with CGEventCreateKeyboardEvent

## Performance Goals

- **Startup Time**: Under 3 seconds
- **Recording Start**: Within 100ms of hotkey press
- **Transcription**: 5-15 seconds (depends on audio length)
- **Text Input**: Within 500ms of receiving result
