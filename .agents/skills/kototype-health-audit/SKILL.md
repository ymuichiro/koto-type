---
name: kototype-health-audit
description: Audit the KotoType repository for bugs, security or privacy issues, performance regressions, release-readiness risks, and recurring maintenance gaps. Use this whenever the user asks to investigate app quality, find vulnerabilities, review performance bottlenecks, do a periodic health check, prepare a release audit, or turn repository inspection into a repeatable checklist for the macOS app or Whisper backend.
---

# KotoType Health Audit

Use this skill to perform a repeatable health review of KotoType. Favor high-signal findings over exhaustive paraphrase. The goal is to identify real defects, meaningful risk, missing coverage, and operational gaps.

## Repository shape

KotoType has two tightly coupled runtimes:

- SwiftUI/AppKit macOS app in `KotoType/`
- Python Whisper backend in `python/whisper_server.py`

The most failure-prone boundaries are:

- Swift-to-Python process startup, shutdown, retries, and health checks
- macOS permissions: microphone, accessibility, and screen capture
- local persistence: logs, settings, history, user dictionary, temporary audio files
- update and release flow: Sparkle feed, appcast signing, bundled backend binary, DMG and ZIP artifacts

## Default workflow

1. Read `AGENTS.md` and inspect the current worktree with `git status --short --untracked-files=all`.
2. Inventory the relevant code, tests, workflows, release scripts, and generated artifacts.
3. Run baseline checks when feasible:
   - `make test-all`
   - `.venv/bin/ruff check python tests/python`
   - `.venv/bin/ty check python/`
   - `cd KotoType && swift build`
   - `cd KotoType && swift test`
4. Treat command failures as findings only when they indicate a product or tooling gap. If a command is blocked by the local environment, say so explicitly.
5. Review the code paths most likely to hide bugs, privacy issues, restart loops, or performance regressions.
6. Report findings first, ordered by severity, with concrete file references and clear evidence.

## KotoType hotspots

Always inspect these areas first unless the user narrows the scope:

- `KotoType/Sources/KotoType/App/AppDelegate.swift`
- `KotoType/Sources/KotoType/Transcription/MultiProcessManager.swift`
- `KotoType/Sources/KotoType/Transcription/PythonProcessManager.swift`
- `KotoType/Sources/KotoType/Audio/RealtimeRecorder.swift`
- `KotoType/Sources/KotoType/Input/KeystrokeSimulator.swift`
- `KotoType/Sources/KotoType/Support/AppUpdater.swift`
- `KotoType/Sources/KotoType/Support/ScreenContextExtractor.swift`
- `KotoType/Sources/KotoType/Support/Logger.swift`
- `KotoType/Sources/KotoType/Support/SettingsManager.swift`
- `KotoType/Sources/KotoType/Support/TranscriptionHistoryManager.swift`
- `KotoType/Sources/KotoType/Support/UserDictionaryManager.swift`
- `python/whisper_server.py`
- `.github/workflows/release.yml`
- `.github/workflows/verify-release-assets.yml`
- `SECURITY.md`
- `.gitignore`

## Audit lenses

### 1. Bugs and regressions

Check for:

- startup and shutdown races between the app and backend
- worker restart storms, stuck queues, timeout handling, and retry loops
- recording start, stop, cancel, and imported-audio edge cases
- permission transitions after first launch, relaunch, or App Translocation
- persistence corruption in settings, history, or dictionary files
- stale temporary audio files or orphaned child processes
- release-time mismatches between bundled resources and runtime expectations

### 2. Security and privacy

Check for:

- overly broad or fragile permission usage
- transcript, OCR context, file paths, or user settings being logged in plain text
- clipboard side effects from keystroke simulation
- screenshot-derived text lingering longer than necessary
- unprotected local storage of sensitive or user-generated data
- secrets or signing material creeping into the repository or build outputs
- dependency and release-process gaps that could weaken update integrity
- missing or stale security process documentation

### 3. Performance and stability

Check for:

- Whisper model load time and model-load serialization
- memory pressure handling and adaptive worker-count reduction
- excessive CPU work in preprocessing, OCR, or repeated retries
- queue buildup when no workers are idle
- large recording or imported-file behavior
- cleanup behavior for temporary artifacts and long-running sessions
- missing smoke tests or benchmarks for expensive runtime paths

## Project-specific checks

Apply these KotoType-specific heuristics:

- Treat the Swift-Python boundary as a first-class review target. Validate launch command resolution, environment setup, pipe handling, and termination cleanup together.
- Treat local-only behavior as a privacy concern anyway. Logs, OCR context, clipboard writes, and history persistence are still audit targets.
- Treat Sparkle release integrity as part of the security surface. Verify key handling, feed configuration, signature checks, and generated release assets.
- Treat generated artifacts in the worktree as an operational smell. Check whether release ZIPs, app bundles, build products, or caches are correctly ignored.
- If `swift test` cannot run locally, call that out as a maintenance gap because it weakens recurring review quality.

## Output format

When the user asks for an audit or review, structure the response like this:

1. Findings first, ordered by severity.
2. For each finding include:
   - short title with severity
   - why it matters
   - evidence or reproduction notes
   - affected files
   - suggested fix or next step
3. After findings, include:
   - what was checked
   - what could not be verified
   - residual risks or follow-up ideas

If there are no findings, say so explicitly and still mention residual gaps such as unrun tests, environment blockers, or unverified release paths.

## Scope control

- For a quick pass, prioritize bugs that can lose data, break recording, or corrupt release/update behavior.
- For a security-focused pass, prioritize permissions, logging, local storage, update integrity, and dependency hygiene.
- For a performance-focused pass, prioritize model startup, worker management, memory pressure, temporary file churn, and smoke-test coverage.
- For recurring use, reuse the same command set and hotspot order so results are comparable across runs.
