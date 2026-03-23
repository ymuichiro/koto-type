# Contributing to KotoType

Thank you for your interest in contributing to KotoType! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Development Environment Setup](#development-environment-setup)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Code Style](#code-style)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Reporting Issues](#reporting-issues)
- [Feature Requests](#feature-requests)
- [License](#license)

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this standard. Please report unacceptable behavior to the project maintainers.

**Be respectful**: Treat everyone with respect and professionalism.

**Be constructive**: Provide feedback in a helpful and constructive manner.

**Be inclusive**: Welcome contributors from diverse backgrounds and experience levels.

## Development Environment Setup

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Python 3.13
- [uv](https://github.com/astral-sh/uv) package manager
- FFmpeg (required for setup validation, audio conversion, and end-to-end app runs)

### 1. Clone the Repository

```bash
git clone https://github.com/ymuichiro/koto-type.git
cd koto-type
```

### 2. Set Up Python Environment

```bash
# Ensure UV is installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
uv sync --extra dev
```

### 3. Build Swift Application

```bash
cd KotoType
swift build
```

### 4. Verify Installation

```bash
# Run Python tests
make test-all

# Run Swift app
make run-app
```

## Development Workflow

### Branching Strategy

- `main`: Production-ready code
- Feature branches: `feature/your-feature-name`
- Bugfix branches: `fix/bug-description`
- Documentation branches: `docs/your-docs`

### Making Changes

1. Create a new branch for your changes:
```bash
git checkout -b feature/your-feature-name
```

2. Make your changes following the [Code Style](#code-style) guidelines.

3. Test your changes thoroughly (see [Testing](#testing)).

4. Commit your changes with clear, descriptive messages:
```bash
git add .
git commit -m "feat: add new transcription option"
```

Follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting)
- `refactor:` Code refactoring
- `test:` Test changes
- `chore:` Build process or auxiliary tool changes

5. Push your branch and create a pull request:
```bash
git push origin feature/your-feature-name
```

## Testing

### Required Testing After Code Changes

**Important**: After making any code changes, you MUST:

1. **Write test code**: Create test code corresponding to the changed functionality
2. **Verify behavior**: Run the test code to confirm code behavior

This process is mandatory for all code changes, with no exceptions.

### Python Tests

```bash
# Run all tests
make test-all

# Run specific tests
uv run python tests/python/test_audio_preprocess.py
uv run python tests/python/test_user_dictionary.py
uv run python tests/python/smoke_whisper_server_binary.py dist/whisper_server
```

### Swift Tests

```bash
# From KotoType directory
swift test
```

### Manual Testing

1. **Basic Flow**: Recording → Transcription → Input
2. **Short Audio**: 1-2 second utterances
3. **Long Audio**: 30 second utterances
4. **Silence**: Behavior with no audio input

### Type Checking and Linting

```bash
# Type checking (ty)
.venv/bin/ty check python/

# Linting (ruff)
.venv/bin/ruff check python tests/python

# Formatting
.venv/bin/ruff format python tests/python
```

## Code Style

### Python

- **Type Checking**: Use `ty` for type checking
- **Linting**: Use `ruff` for linting
- **Formatting**: Use `ruff format` for formatting
- **Documentation**: Include docstrings for all public functions and classes
- **Naming**: Follow PEP 8 naming conventions
- **Imports**: Group imports (standard library, third-party, local) with blank lines between groups

Example:
```python
"""Module docstring."""

from typing import Optional

import faster_whisper

from local_module import local_function


def transcribe_audio(audio_path: str, language: str = "ja") -> Optional[str]:
    """Transcribe audio file using Whisper.
    
    Args:
        audio_path: Path to audio file
        language: Language code (default: "ja")
        
    Returns:
        Transcribed text or None if transcription fails
    """
    # Implementation
```

### Swift

- **Naming**: Follow Swift API Design Guidelines
- **Comments**: Keep to a minimum, let code be self-documenting
- **Error Handling**: Use `do-catch` for error handling
- **Access Control**: Use appropriate access modifiers
- **SwiftUI**: Follow SwiftUI best practices

Example:
```swift
/// Transcribe audio file using Whisper
func transcribe(audioPath: String, language: String = "ja") -> String? {
    // Implementation
}
```

## Pull Request Guidelines

### Before Submitting

1. **Check existing issues**: Search for existing PRs that address the same issue
2. **Write tests**: Add tests for new functionality or update existing tests
3. **Update documentation**: Update relevant documentation (README, DESIGN.md, etc.)
4. **Run all tests**: Ensure all tests pass
5. **Check code style**: Ensure code follows style guidelines
6. **Commit messages**: Use clear, descriptive commit messages

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] All tests pass
```

### Review Process

1. Required local checks must pass, and any configured CI/CD checks must pass before merge
2. At least one maintainer approval required
3. Address all review comments
4. Keep PR focused and small for easier review
5. Squash commits if needed before merging

## Reporting Issues

### Bug Reports

When reporting a bug, please include:

- **Title**: Clear, concise description of the issue
- **Description**: Detailed explanation of the bug
- **Steps to Reproduce**: Step-by-step instructions
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened
- **Environment**:
  - macOS version
  - KotoType version
  - FFmpeg version (if applicable)
- **Screenshots/Logs**: Include relevant screenshots or error logs

### Issue Template

```markdown
**Description**
Clear description of the issue

**Steps to Reproduce**
1. Step one
2. Step two
3. Step three

**Expected Behavior**
What should happen

**Actual Behavior**
What actually happens

**Environment**
- macOS: [e.g., 14.0]
- KotoType: [e.g., 1.0.0]
- FFmpeg: [e.g., 6.0]

**Screenshots/Logs**
[Attach relevant files]
```

## Feature Requests

When proposing a new feature:

1. **Search existing issues**: Check if the feature has already been requested
2. **Use the feature request template**: Provide clear information
3. **Consider the project goals**: Does it align with simplicity and accuracy focus?
4. **Be open to discussion**: Accept feedback and alternative approaches

### Feature Request Template

```markdown
**Feature Description**
Clear description of the feature

**Use Case**
Describe the problem this solves and who it helps

**Proposed Solution**
How do you envision this working?

**Alternatives Considered**
What other approaches did you consider?

**Additional Context**
Any other relevant information
```

## Documentation

### Updating Documentation

When adding features or making changes:
- Update README.md if user-facing
- Update DESIGN.md if architecture changes
- Update CONTRIBUTING.md if workflow changes
- Add inline code comments for complex logic

### Documentation Style

- **Be concise**: Keep explanations short and clear
- **Use examples**: Provide code examples where helpful
- **Keep it current**: Update documentation alongside code changes
- **Use consistent formatting**: Follow Markdown best practices

## License

By contributing to KotoType, you agree that your contributions will be licensed under the [MIT License](LICENSE).

## Getting Help

- **GitHub Issues**: For bug reports and feature requests
- **Discussions**: For questions and general discussion (if enabled)
- **Security reports**: Follow [SECURITY.md](SECURITY.md) for private vulnerability reporting

## Recognition

Contributors are recognized in the project's README and CONTRIBUTORS file. All contributions are valued and appreciated!

Thank you for contributing to KotoType!
