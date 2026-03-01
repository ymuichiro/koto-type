# AGENTS.md - Guidelines for AI Coding Agents

This document provides essential information for AI coding agents working on the KotoType codebase.

## Project Overview

KotoType is a macOS speech-to-text application with:
- **Swift frontend**: SwiftUI menu bar app (`KotoType/`)
- **Python backend**: Whisper-based transcription server (`python/whisper_server.py`)

## Build, Test, and Lint Commands

### Python

```bash
uv sync                                    # Install dependencies
make test-all                              # Run all Python tests
uv run python tests/python/test_user_dictionary.py  # Run single test
.venv/bin/ty check python/                 # Type checking
.venv/bin/ruff check python tests/python   # Linting
.venv/bin/ruff check --fix python tests/python  # Auto-fix lint
.venv/bin/ruff format python tests/python  # Format code
```

### Swift

```bash
cd KotoType && swift build                           # Build
cd KotoType && swift test                            # Run all tests
cd KotoType && swift test --filter LoggerTests       # Run single test class
cd KotoType && swift test --filter LoggerTests/testSharedLoggerInstance  # Single method
```

### Makefile Commands

```bash
make build-server    # Build Python server binary with PyInstaller
make build-app       # Build Swift application
make run-server      # Run Python server for testing
make run-app         # Run Swift application
```

## Code Style Guidelines

### Python Style

**Imports**: Group imports with blank lines: standard library → third-party → local modules

**Naming**: Follow PEP 8 (`snake_case` functions/variables, `PascalCase` classes, `UPPER_SNAKE_CASE` constants)

**Error Handling**: Use specific exception types with logging:

```python
try:
    result = perform_operation()
except FileNotFoundError as e:
    log(f"File not found: {e}")
    return default_value
except Exception as e:
    log(f"Error: {e}\n{traceback.format_exc()}")
    return default_value
```

**Logging**: Use the project's pattern with timestamp and pid:

```python
def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] [pid={os.getpid()}] {message}\n")
```

### Swift Style

**Imports**: Group framework imports first, then third-party

**Naming**: `camelCase` for properties/methods, `PascalCase` for types

**Access Control**: Use explicit modifiers (`private`, `final`, etc.)

**Error Handling**: Use do-catch with Logger:

```swift
do {
    try FileManager.default.removeItem(at: fileURL)
} catch {
    Logger.shared.log("Failed: \(error)", level: .warning)
}
```

**Logging**: Always use `Logger.shared.log("Message", level: .info)` (levels: `.debug`, `.info`, `.warning`, `.error`)

**MainActor**: Use `@MainActor` for UI-related classes

## Testing Guidelines

### After Making Code Changes

1. Write or update tests for changed functionality
2. Run tests to verify expected behavior
3. Run linters to ensure code quality

### Python Tests
- Use `unittest` framework in `tests/python/`
- File naming: `test_<module_name>.py`

### Swift Tests
- Use `XCTest` framework in `KotoType/Tests/`
- Use `@testable import KotoType` and `XCTestCase` subclass

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code refactoring
- `test:` - Test changes
- `chore:` - Build/tooling changes

## Project Structure

```
python/whisper_server.py              # Python transcription server
KotoType/Sources/KotoType/
├── App/                              # AppDelegate, entry point
├── Audio/                            # Audio recording
├── Input/                            # Hotkey and keystroke handling
├── Support/                          # Settings, logging, utilities
├── Transcription/                    # Python process management
└── UI/                               # SwiftUI views and windows
KotoType/Tests/                       # Swift tests
tests/python/                         # Python tests
```

## Key Dependencies

**Python**: `faster-whisper`, `ffmpeg-python`, `numpy`, `scipy`, `ruff`, `ty`
**Swift**: Pure SwiftUI/AppKit, macOS 13.0+, Swift 6.1
