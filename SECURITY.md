# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |
| < 1.0   | No        |

Older versions may contain unfixed bugs or security issues. Please upgrade to the latest 1.0.x release before reporting a vulnerability whenever possible.

## Reporting a Vulnerability

Do not open a public GitHub issue for a suspected security vulnerability.

Please report vulnerabilities privately by email:

- `ym.u.ichiro@icloud.com`

If GitHub private vulnerability reporting is enabled for this repository, you may use that channel instead of email.

Include the following in your report when possible:

- KotoType version
- macOS version
- clear reproduction steps
- expected behavior and actual behavior
- impact assessment
- logs, screenshots, or sample files with sensitive information removed

We will make a best effort to acknowledge new reports within 3 business days and will coordinate disclosure with the reporter before publishing details.

## Security Overview

### Permissions

KotoType currently requests the following macOS permissions:

1. **Microphone**: required for live audio recording.
2. **Accessibility**: required for global hotkey handling and simulated text insertion.
3. **Screen Recording**: currently required for screen-context capture used to improve transcription context.

At the moment, the initial setup flow treats all three permissions as required for normal use.

### Local Data Handling

KotoType is designed for local transcription. During normal operation, it stores data on the local Mac only.

The application may write the following local files:

- app settings in `~/Library/Application Support/koto-type/settings.json`
- transcription history in `~/Library/Application Support/koto-type/transcription_history.json`
- user dictionary terms in `~/Library/Application Support/koto-type/user_dictionary.json`
- Swift app logs in `~/Library/Application Support/koto-type/`
- Python backend log in `~/Library/Application Support/koto-type/server.log`
- temporary audio chunks in the system temporary directory during recording and preprocessing

Notes:

- Transcription history is stored locally until the user clears it.
- Logs are intended for troubleshooting and may contain operational metadata such as file paths, settings values, and stack traces.
- Persistent local files are written with owner-only POSIX permissions where supported.
- Automatic text insertion uses pasteboard-based paste simulation and restores the previous clipboard contents immediately after pasting. Transcribed text may still pass briefly through the macOS pasteboard and may be observable by clipboard managers.

### Network Access

KotoType does not intentionally upload recordings or transcriptions to external services during normal transcription.

Network access is currently used for:

- downloading Whisper model assets when they are not already present locally
- manual update checks via Sparkle appcast retrieval
- downloading signed update archives when the user chooses to update

Automatic background update checks and automatic installation are currently disabled by default.

### Update Security

KotoType uses Sparkle for application updates.

Current update model:

- the app embeds a Sparkle public verification key
- release automation signs update metadata and update ZIP archives with the matching private key
- the app verifies Sparkle signatures before applying updates
- the app uses a GitHub Releases-hosted `appcast.xml` feed
- update checks are user-initiated rather than automatic

Sparkle signing keys must never be committed to git. They should be provided through secure local key storage or CI secrets.

### Code Signing and Notarization

Current status:

- release bundles are ad-hoc signed for bundle integrity
- Apple Developer ID signing is not currently part of the release process
- notarization is not currently part of the release process

Because Developer ID signing and notarization are not yet in place, first launch may still require the user to explicitly approve the app in macOS security prompts.

## Developer Expectations

When contributing to KotoType:

1. validate inputs crossing the Swift-Python boundary
2. avoid logging transcript content or other sensitive user data unless strictly necessary for debugging
3. keep dependencies and release tooling up to date
4. preserve least-privilege behavior around permissions and local storage
5. keep signing keys and other secrets out of the repository

## Disclosure and Remediation

We classify reports roughly as:

- **Critical**: can be exploited with minimal user interaction and causes severe impact
- **High**: realistic exploitation with meaningful security or privacy impact
- **Medium**: limited impact or stronger preconditions
- **Low**: minor issues or defense-in-depth improvements

We aim to:

1. assess the report
2. confirm the scope and affected versions
3. develop and verify a fix
4. publish an update when needed
5. credit the reporter in release notes unless they prefer otherwise

## Security Notes for Users

- Download releases only from the official GitHub Releases page.
- Re-check macOS permissions after updating to a new app bundle.
- Review local logs before sharing them publicly, because they may contain environment-specific details.
- Keep FFmpeg, macOS, and KotoType up to date.

## Questions

For security questions that are not vulnerability reports, use the same private contact:

- `ym.u.ichiro@icloud.com`

---

**Last Updated**: 2026-03-22
