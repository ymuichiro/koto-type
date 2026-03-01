# KotoType

<div align="center">

![KotoType Logo](assets/logo/koto-tyoe_banner_transparent.png)

A Mac-native voice-to-text application with high-accuracy transcription powered by OpenAI Whisper.

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/yourusername/koto-type/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.13-blue.svg)](https://python.org)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)
[![Code of Conduct](https://img.shields.io/badge/code%20of%20conduct-enabled-brightgreen.svg)](CODE_OF_CONDUCT.md)

[![GitHub stars](https://img.shields.io/github/stars/yourusername/koto-type?style=social)](https://github.com/yourusername/koto-type/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/yourusername/koto-type?style=social)](https://github.com/yourusername/koto-type/network/members)
[![GitHub issues](https://img.shields.io/github/issues/yourusername/koto-type)](https://github.com/yourusername/koto-type/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/yourusername/koto-type)](https://github.com/yourusername/koto-type/pulls)

**[Documentation](#documentation) • [Installation](#installation) • [Usage](#usage) • [Contributing](#contributing) • [Support](#support)**

</div>

## Features

- **Menu Bar Application**: Resides in the menu bar for quick access
- **Push-to-Talk Hotkey**: Hold your configured hotkey to record, release to transcribe (default: `⌘+⌥`)
- **High-Accuracy Transcription**: Powered by OpenAI Whisper with optimized settings
- **Automatic Text Input**: Automatically types transcribed text at the cursor position
- **Audio Preprocessing**: Noise reduction with spectral subtraction and normalization
- **History Management**: Access past transcriptions from the history menu
- **Audio File Import**: Import `wav`/`mp3` files for transcription
- **Auto-Launch**: Toggle auto-start at login
- **First-Time Setup**: Comprehensive setup wizard for permissions and dependencies
- **Open Source**: Fully open-source under MIT License

## Installation

### Quick Start (3 Steps)

1. Install KotoType and FFmpeg (`brew install ffmpeg`)
2. Complete all checks in the Initial Setup window
3. Click a text field, hold hotkey to record, release to transcribe

### Install from DMG (Recommended)

1. Download the latest [KotoType.dmg](https://github.com/yourusername/koto-type/releases/latest)
2. Double-click the downloaded DMG file
3. Drag KotoType.app to your Applications folder
4. On first launch, click "Open" when prompted by the security warning

### Install FFmpeg (Required)

KotoType validates `ffmpeg` during the initial setup and cannot proceed without it.

```bash
# Homebrew (recommended)
brew install ffmpeg

# Confirm availability
ffmpeg -version
```

Alternative package manager:

```bash
# MacPorts
sudo port install ffmpeg
```

### Build from Source

#### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Python 3.13
- [uv](https://github.com/astral-sh/uv) package manager

#### Installation Steps

1. Clone the repository
```bash
git clone https://github.com/yourusername/koto-type.git
cd koto-type
```

2. Install dependencies (including dev dependencies)
```bash
make install-deps
```

3. Build the application (Python + Swift)
```bash
make build-all
```

4. Create the .app bundle
```bash
cd KotoType
./scripts/create_app.sh
```

5. (Optional) Create the .dmg disk image
```bash
./scripts/create_dmg.sh
```

## Usage

### Using Makefile (Recommended)

All operations can be executed through the Makefile. To see available commands:

```bash
make help
```

#### Application Commands

- `make run-app` - Launch the Swift application
- `make run-server` - Start the Python server (for testing)

#### Testing Commands

- `make test-transcription` - Run transcription tests
- `make test-benchmark` - Run performance benchmarks
- `make test-all` - Run all tests

#### Build Commands

- `make build-server` - Build Python server binary (PyInstaller)
- `make build-app` - Build Swift application
- `make build-all` - Build both Python and Swift
- `make install-deps` - Install Python dependencies (including dev)

#### Utility Commands

- `make clean` - Remove temporary files
- `make view-log` - View server logs
- `make capture-artifacts` - Collect crash-investigation artifacts into `artifacts/runtime/`

### Crash-Resilient Testing Workflow

When validating production-like behavior (especially recording start/stop), preserve evidence before and after each run:

```bash
# 1) Capture baseline
make capture-artifacts

# 2) Execute scenario (launch app, start recording, stop recording)

# 3) Capture post-run evidence
make capture-artifacts
```

If the machine crashes/reboots, run `make capture-artifacts` immediately after login.
Then append a summary entry to:

- `docs/testing/test-ledger.md`
- `docs/operations/restart-storm-runbook.md`

### Launching the Application

If installed from DMG:
1. Launch KotoType from Launchpad
2. Or run: `open /Applications/KotoType.app`

If built from source:
```bash
# Using Makefile (recommended)
make run-app

# Or run directly
cd KotoType
swift run
```

### First-Time Setup

On first launch, the "Initial Setup" screen will appear to verify the following:

1. **Accessibility Permissions** (for keyboard input simulation)
2. **Microphone Permissions** (for recording)
3. **Screen Recording Permissions** (for screen context support)
4. **FFmpeg Command Availability**

#### Step-by-step walkthrough (first launch)

1. Launch KotoType. The `Initial Setup` window opens automatically.
2. Click **Grant Accessibility**.
3. In `System Settings > Privacy & Security > Accessibility`, enable KotoType.
4. Return to KotoType and click **Re-check**.
5. If Accessibility does not switch to passed, wait a few seconds and click **Re-check** again. If still not reflected, click **Restart App** in the setup window and reopen.
6. Click **Grant Microphone**, then choose **Allow** when macOS asks for permission.
7. Click **Grant Screen Recording**, enable KotoType in `System Settings > Privacy & Security > Screen Recording`, then return to the app.
8. If FFmpeg is not detected, install it:

```bash
brew install ffmpeg
ffmpeg -version
```

9. Click **Re-check** until all required items become passed.
10. Click **Finish setup and start** to enter normal menu bar mode.

#### After setup: next 3 actions

1. Click the text field where you want output.
2. Hold your hotkey while speaking.
3. Release the hotkey and wait for automatic text insertion.

#### Fast fixes (first day)

- **App blocked and won’t open**: System Settings > Privacy & Security > `Open Anyway`
- **Hotkey does not start recording**: Re-enable KotoType in Accessibility
- **Recorded but text not inserted**: Confirm editable cursor focus + Accessibility permission
- **FFmpeg check failed**: `brew install ffmpeg` then `ffmpeg -version`, reopen app

If the FFmpeg check fails, install or reinstall FFmpeg and restart KotoType:

```bash
brew install ffmpeg
ffmpeg -version
```

> **Note**: Due to licensing considerations, FFmpeg is not bundled with the distribution.  
> You must have `ffmpeg` installed on your system (e.g., `brew install ffmpeg`).
>
> The distributed `.app`/`.dmg` includes the `whisper_server` binary, so Python and uv are not required for end users.
> During development only, if the bundled binary is not found, it falls back to `uv run`/`.venv` execution.

### Basic Operation

#### First dictation walkthrough

1. Confirm setup is complete and the KotoType icon is visible in the menu bar.
2. Open the app where you want text input (Notes, Slack, browser form, etc.).
3. Click the target text field so the cursor is active.
4. Hold the configured hotkey (default: **⌘+⌥**) to begin recording.
5. Keep holding the hotkey while speaking.
6. Release the hotkey to stop recording and trigger transcription.
7. Wait for processing to complete; KotoType types the recognized text at the current cursor position.
8. If no text is inserted, re-check Accessibility permission and confirm the cursor is focused in an editable field.

#### Other daily operations

1. (Optional) Change hotkey: "Settings... > Hotkey"
2. (Optional) Transcribe files: "Import Audio File..." (`wav`/`mp3`)
3. (Optional) Review past results: "History..."
4. Quit app: "Quit" or **Cmd+Q**

## Security Warning

This app is currently distributed without Apple Developer signing, so you may see a Gatekeeper warning on first launch.

### Unsigned App Launch Steps by macOS Version

Use the steps for your macOS version when KotoType is blocked.

| macOS version | What to do |
| --- | --- |
| 26 | 1) Try to open KotoType once from Finder. 2) Open `System Settings > Privacy & Security`. 3) In Security, click **Open Anyway** and confirm. |
| 15 / 14 | 1) Try to open KotoType once from Finder. 2) Open `System Settings > Privacy & Security`. 3) In Security, click **Open Anyway** and confirm. |

Apple references:
- [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)

> `Open Anyway` is a Gatekeeper setting in Privacy & Security. Firewall settings are not part of this launch flow in Apple’s documented steps.

### If You See a Warning

**Method 1: Right-click and "Open"**
1. Right-click or Ctrl+click on the app
2. Select "Open"

**Method 2: Allow in Privacy & Security**
1. Go to System Settings, then open Privacy & Security
2. Click "Open"

This is normal behavior for apps without Apple Developer Program signing. After this, the app will launch without warnings.

## Project Structure

```
koto-type/
├── python/
│   └── whisper_server.py       # Whisper server
├── tests/
│   └── python/                 # Python tests
│       ├── test_transcription.py
│       └── test_benchmark.py
├── KotoType/                     # Swift app
│   ├── Sources/KotoType/
│   │   ├── App/               # Entry point and path resolution
│   │   ├── Audio/             # Recording
│   │   ├── Input/             # Hotkey/input handling
│   │   ├── Transcription/     # Python process communication & batch control
│   │   ├── UI/                # Menu bar/settings UI
│   │   └── Support/           # Logger/settings/permissions
│   ├── Package.swift
│   └── scripts/
│       ├── create_app.sh        # App creation script
│       └── create_dmg.sh       # DMG creation script
├── pyproject.toml            # Python dependencies
├── LICENSE                    # MIT License
└── README.md                  # This file
```

## Testing

### Using Makefile (Recommended)

```bash
# Transcription tests
make test-transcription

# Performance benchmark tests
make test-benchmark

# Run all tests
make test-all
```

### Manual Testing

```bash
# Transcription tests
uv run python3 tests/python/test_transcription.py

# Performance benchmark tests
uv run python3 tests/python/test_benchmark.py
```

### Viewing Server Logs

```bash
# Using Makefile
make view-log

# Or directly
tail -100 ~/Library/Application\ Support/koto-type/server.log
```

### Noise Reduction Toggle

Noise reduction is enabled by default in audio preprocessing. To disable it for compatibility reasons:

```bash
export KOTOTYPE_ENABLE_NOISE_REDUCTION=0
```

### Auto Gain for Quiet Speech

Enabled by default. Automatically amplifies quiet audio before transcription.

```bash
export KOTOTYPE_AUTO_GAIN_ENABLED=1
```

Adjust threshold and amplification limits as needed:

```bash
export KOTOTYPE_AUTO_GAIN_WEAK_THRESHOLD_DBFS=-18
export KOTOTYPE_AUTO_GAIN_TARGET_PEAK_DBFS=-10
export KOTOTYPE_AUTO_GAIN_MAX_DB=18
```

### VAD Intensity for Noisy Environments

By default, VAD is set slightly stricter for noisy environments. To revert to traditional settings:

```bash
export KOTOTYPE_VAD_STRICT=0
```

### Type Checking and Linting

```bash
# Type checking (ty)
.venv/bin/ty check python/

# Linting (ruff)
.venv/bin/ruff check python tests/python

# Formatting
.venv/bin/ruff format python tests/python
```

## Development

### Building

```bash
# Using Makefile (recommended)
make build-all    # Build both Python and Swift
make build-server # Build Python server binary only
make build-app    # Build Swift app only

# Or run directly
cd KotoType
swift build
```

### Running

```bash
# Using Makefile (recommended)
make run-app

# Or run directly
cd KotoType
swift run
```

### Installing Dependencies

```bash
# Using Makefile (recommended)
make install-deps

# Or run directly
uv sync --extra dev
```

### Cleanup

```bash
# Using Makefile
make clean
```

### Distribution Build

```bash
# Complete build process
make install-deps  # Install dependencies
make build-all     # Build Python + Swift
cd KotoType
./scripts/create_app.sh    # Create .app bundle
./scripts/create_dmg.sh    # Create .dmg disk image (optional)
```

## Release Process

- Pushing to `main` branch triggers GitHub Actions to create a tag in format `v<VERSION>.<run_number>`
- Tag push triggers `.github/workflows/release.yml` to build `.dmg`
- Generated `.dmg` is automatically attached to the GitHub Release
- Release DMG does not include FFmpeg, so the initial setup requires system `ffmpeg`

Update the `VERSION` file to reflect in future tags and distribution versions.

### About PyInstaller

The Python server is packaged as a single executable using PyInstaller:

- **Command**: `uv run --extra dev pyinstaller --onefile --name whisper_server ...`
- **Output**: `dist/whisper_server`
- **Embedded at**: `.app/Contents/Resources/whisper_server`
- **C Extensions**: faster-whisper and ctranslate2 are automatically collected

## Troubleshooting

### Microphone Permissions
Allow microphone access on first launch when prompted.

### Whisper Model Download
The Whisper model (large-v3, ~3GB) is downloaded on first launch.

### Hotkey Not Working
Enable KotoType in System Settings > Privacy & Security > Accessibility, and confirm you are holding the configured hotkey (default: `⌘+⌥`).

### Python Server Binary Not Found
When creating distribution `.app`/`.dmg`, run `make build-server` to create `dist/whisper_server` before running `./scripts/create_app.sh`.

### PyInstaller Errors
Ensure dev dependencies are properly installed:
```bash
make install-deps
```

## Releases

Release binaries are available on the [Releases page](https://github.com/yourusername/koto-type/releases).

## Contributing

We welcome contributions from the community! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.

### Quick Start for Contributors

```bash
# Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/koto-type.git
cd koto-type

# Install dependencies
make install-deps

# Run tests
make test-all

# Start development
make run-app
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed information on:

- Development environment setup
- Code style guidelines
- Testing requirements
- Pull request process
- Reporting bugs and feature requests

## License

[MIT License](LICENSE) © 2025 KotoType Contributors

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)**: Version history and release notes
- **[DESIGN.md](DESIGN.md)**: Technical design documentation
- **[SECURITY.md](SECURITY.md)**: Security policy and reporting
- **[SUPPORT.md](SUPPORT.md)**: Getting help and troubleshooting

## Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) for the speech recognition model
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for the optimized Whisper implementation
- The open-source community for various tools and libraries

---

<div align="center">

Made with ❤️ by [KotoType Contributors](CONTRIBUTORS.md)

[⬆ Back to top](#kototype)

</div>

## Limitations

- **Microphone Permission**: Must be granted in System Settings
- **Accessibility Permission**: Required for hotkeys and keyboard simulation
- **Whisper Model**: ~3GB download on first launch

## Roadmap

- [ ] Multi-language support
- [ ] Customizable keyboard shortcuts
- [ ] Auto-update functionality
- [ ] Enhanced settings UI

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)**: Version history and release notes
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Guidelines for contributors
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)**: Community code of conduct
- **[DESIGN.md](DESIGN.md)**: Technical design documentation
- **[SECURITY.md](SECURITY.md)**: Security policy and reporting
- **[SUPPORT.md](SUPPORT.md)**: Getting help and troubleshooting

## Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) for the speech recognition model
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for the optimized Whisper implementation
- The open-source community for various tools and libraries

---

<div align="center">

Made with ❤️ by [KotoType Contributors](CONTRIBUTORS.md)

[⬆ Back to top](#kototype)

</div>
