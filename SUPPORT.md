# Support

Welcome to the KotoType support page. Here you'll find resources to help you get the most out of KotoType.

## Table of Contents

- [Documentation](#documentation)
- [Getting Started](#getting-started)
- [Troubleshooting](#troubleshooting)
- [Common Issues](#common-issues)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Community](#community)
- [Contributing](#contributing)

## Documentation

### Official Documentation

- **[README.md](README.md)**: Main documentation with installation, usage, and configuration instructions
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Guidelines for contributing to the project
- **[CHANGELOG.md](CHANGELOG.md)**: Version history and release notes
- **[DESIGN.md](DESIGN.md)**: Technical design document for developers

### Quick Links

- [Installation Guide](README.md#installation)
- [Usage Guide](README.md#usage)
- [Troubleshooting](README.md#troubleshooting)
- [Security Policy](SECURITY.md)

## Getting Started

### First Steps

1. **Install KotoType**: Follow the [Installation Guide](README.md#installation)
2. **Grant Permissions**: Run the first-time setup wizard to grant necessary permissions
3. **Test Recording**: Hold your hotkey to record and release to transcribe
4. **Check Transcription**: Verify that transcription works as expected

### Setup Requirements

Before using KotoType, ensure you have:

- macOS 13.0 or later
- FFmpeg installed (for audio file conversion, e.g., `brew install ffmpeg`)
- Microphone access granted
- Accessibility permissions granted (for hotkeys)
- Screen Recording permission granted (for screen context support)

## Troubleshooting

### General Troubleshooting Steps

1. **Check Requirements**: Verify all prerequisites are met
2. **Review Logs**: Check server logs for errors
3. **Restart the App**: Quit and relaunch KotoType
4. **Check Permissions**: Ensure all required permissions are granted
5. **Update KotoType**: Make sure you're using the latest version

## Common Issues

### Microphone Not Working

**Symptoms**: Recording fails or no audio is captured

**Solutions**:
1. Check System Settings > Privacy & Security > Microphone
2. Ensure KotoType is listed and enabled
3. Try restarting the app
4. Check if other apps are using the microphone

### Hotkey Not Responding

**Symptoms**: Holding and releasing the configured hotkey does not start/stop recording

**Solutions**:
1. Check System Settings > Privacy & Security > Accessibility
2. Ensure KotoType is listed and enabled
3. Verify no other apps are using the same hotkey
4. Try restarting the app

### Transcription Fails

**Symptoms**: Audio records but transcription doesn't work

**Solutions**:
1. Ensure the initial Whisper model download can complete
2. Verify FFmpeg is installed: `ffmpeg -version`
3. Review server logs: `make view-log`
4. Ensure sufficient disk space for the `large-v3-turbo` model download

### Gatekeeper Warning

**Symptoms**: Security warning on first launch

**Solutions**:
1. Right-click on KotoType.app
2. Select "Open"
3. Click "Open" in the security dialog

This is normal for apps that are not Developer ID signed and notarized. Current release bundles are ad-hoc signed, but macOS may still require manual approval on first launch.

### Slow Transcription

**Symptoms**: Transcription takes longer than expected

**Notes**:
- Expected time: 5-15 seconds depending on audio length
- Large-v3-turbo model requires more processing time
- CPU performance affects speed
- First run is slower (model download)

## Reporting Bugs

### How to Report a Bug

If you encounter an issue not covered above, please:

1. **Search Existing Issues**: Check if the bug has already been reported
2. **Use Bug Report Template**: Create a new issue using the bug report template
3. **Provide Details**: Include all relevant information:
   - macOS version
   - KotoType version
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots or logs

### Bug Report Checklist

- [ ] Searched existing issues
- [ ] Used bug report template
- [ ] Included environment details
- [ ] Provided steps to reproduce
- [ ] Attached relevant logs/screenshots

## Feature Requests

### Suggesting New Features

We welcome feature requests! To suggest a new feature:

1. **Search Existing Requests**: Check if the feature has already been requested
2. **Use Feature Request Template**: Create a new issue using the feature request template
3. **Provide Context**: Explain why the feature is needed
4. **Suggest Implementation**: If you have ideas on how it could work

### Feature Request Checklist

- [ ] Searched existing feature requests
- [ ] Used feature request template
- [ ] Described use case clearly
- [ ] Explained who would benefit
- [ ] Considered alternatives

## Community

### Getting Help

- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For questions and general discussion (if enabled)
- **Security reports**: Follow [SECURITY.md](SECURITY.md) for private vulnerability reporting

### Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Development setup
- Code style guidelines
- Pull request process
- Testing requirements

### Staying Updated

- **Watch Repository**: Get notified of new releases and issues
- **Star Repository**: Show your support for the project
- **Follow Maintainers**: Stay updated on project news

## Additional Resources

### Third-Party Resources

- [OpenAI Whisper Documentation](https://github.com/openai/whisper)
- [faster-whisper Documentation](https://github.com/SYSTRAN/faster-whisper)
- [Swift Documentation](https://swift.org/documentation/)
- [Python Documentation](https://docs.python.org/3/)

### Related Projects

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C++ implementation of Whisper
- [Whisper Web UI](https://github.com/jhj0517/Whisper-WebUI) - Web interface for Whisper

## Getting in Touch

For questions or suggestions that aren't covered by the above resources, please:

1. Check the [README.md](README.md) first
2. Search [GitHub Issues](https://github.com/ymuichiro/koto-type/issues)
3. Create a new issue if your question hasn't been answered

Thank you for using KotoType!
