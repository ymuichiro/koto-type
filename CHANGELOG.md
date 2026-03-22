# Changelog

All notable changes to KotoType will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Documentation updated to match the current repository URLs, test layout, release behavior, and security guidance

## [1.0.0] - 2025-02-08

### Added
- Initial release of KotoType
- Menu bar resident application
- Global hotkey (default: Command+Option) for recording
- OpenAI Whisper integration with large-v3-turbo model
- Automatic text input at cursor position
- Audio preprocessing with noise reduction
- History management for past transcriptions
- Audio file import (wav/mp3) support
- Auto-start at login toggle
- First-time setup wizard
- Accessibility, microphone, and screen recording permission checks
- FFmpeg dependency validation
- Multi-language documentation (Japanese)
- Comprehensive test suite

### Features
- Voice Activity Detection (VAD)
- Auto-gain for quiet speech
- Spectral noise reduction
- Audio file format conversion
- Transcription history with JSON storage
- Settings management

### Technical
- Swift 6.2.3 + SwiftUI frontend
- Python 3.13.7 + faster-whisper backend
- UV package management
- PyInstaller for Python binary packaging
- Standard I/O communication between Swift and Python
- CGEvent for keyboard input simulation
- AVFoundation for audio recording

### Planned
- Automatic update checks and installation
- Enhanced settings UI
- Additional language coverage and tuning improvements

---

[Unreleased]: https://github.com/ymuichiro/koto-type/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ymuichiro/koto-type/releases/tag/v1.0.0
