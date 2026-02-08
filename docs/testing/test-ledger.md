# Test Ledger (Crash-Resilient)

Use this ledger for every production-like run.
Even if the session crashes, this file plus artifact bundles should preserve traceability.

## Entry Template
- DateTime:
- Operator:
- Branch/Commit:
- Scenario:
- Expected:
- Result:
- Artifact Bundle Paths:
- Key Log Evidence:
- Follow-up Actions:

## Entries
- DateTime: 2026-02-09 00:00 JST
- Operator: Codex
- Branch/Commit: `codex/release-and-recovery-guard` (working tree)
- Scenario: Investigation of repeated `whisper_server` starts during production-like usage
- Expected: identify direct causes and add hard limits
- Result: implemented Python shared-state limits and Swift restart circuit breaker improvements
- Artifact Bundle Paths: to be captured with `make capture-artifacts` in next run
- Key Log Evidence: repeated `Server started` bursts in `server.log` around `00:04` and `00:12`
- Follow-up Actions: run full production-like recording cycle and compare pre/post artifact bundles

- DateTime: 2026-02-09 07:49 JST
- Operator: Codex
- Branch/Commit: `codex/release-and-recovery-guard` (working tree)
- Scenario: Validate fatal termination containment (`status=9`) in `MultiProcessManager`
- Expected: no immediate retry storm after `status=9` during startup and active processing
- Result: added fatal-termination path + startup race fix; `MultiProcessManagerTests` passed (4/4)
- Artifact Bundle Paths: `/Users/you/github/ymuichiro/koto-type/artifacts/runtime/20260209_075150`
- Key Log Evidence: test logs include
  - `terminated with status 9 while idle; delaying recovery for 300s`
  - `terminated with status 9 while processing segment ...; completing with empty result and delaying recovery for 300s`
- Follow-up Actions: execute production-like app recording cycle and capture before/after artifacts

- DateTime: 2026-02-09 07:52 JST
- Operator: Codex
- Branch/Commit: `codex/release-and-recovery-guard` (working tree)
- Scenario: Lightweight regression suite for restart-storm controls
- Expected: guard logic and existing preprocessing/dictionary behavior stay green
- Result: passed
  - `swift test --filter "(MultiProcessManagerTests|PythonProcessManagerTests|RuntimeSafetyTests)"` (19 tests)
  - `python3 -m unittest tests/python/test_audio_preprocess.py tests/python/test_user_dictionary.py tests/python/test_server_state.py -v` (19 tests)
- Artifact Bundle Paths: `/Users/you/github/ymuichiro/koto-type/artifacts/runtime/20260209_075150`
- Key Log Evidence: `MultiProcessManager` tests emitted status 9 cooldown log lines and no immediate restart
- Follow-up Actions: run production-like recording start/stop cycle on patched DMG build
