# Restart Storm Runbook

## Goal
Leave reproducible evidence even if the machine crashes during production-like testing.

## Problem Definition
- Symptom: many `whisper_server` processes start in a short interval.
- Impact: concurrent model loading causes memory pressure and can crash the OS session.
- Root risks:
  - Recovery loops in the app process manager.
  - Multiple backend processes loading model simultaneously.
  - Missing post-incident artifacts after reboot.

## Root-Cause Clarification
1. The direct restart-storm trigger was `status=9` (SIGKILL) handling in `MultiProcessManager`:
   - idle termination path previously auto-recovered immediately
   - active-segment termination path retried and recreated workers immediately
2. In distribution runtime, bundled `whisper_server` startup/model-load memory pressure made `status=9` more likely than development runtime.
3. Immediate recovery after `status=9` created a positive feedback loop (restart -> load -> kill -> restart).

## Current Defenses
1. Python shared state lock (`server_state.json` + `server_state.lock`) enforces:
   - max active servers (`KOTOTYPE_MAX_ACTIVE_SERVERS`, default: 1)
   - max parallel model loads (`KOTOTYPE_MAX_PARALLEL_MODEL_LOADS`, default: 1)
2. Swift `MultiProcessManager` has:
   - idle termination recovery suppression for status 9
   - active-segment status 9 handling that completes with empty result and delays recovery
   - start-failure circuit breaker with cooldown
   - startup registration ordering that avoids missing fatal-termination suppression
   - bounded queue attempts when no worker is available
   - explicit old-process stop on re-initialize
3. Python log lines include PID for causality tracking.

## Test Protocol (Production-like)
1. Before test, capture baseline artifacts:
   - `make capture-artifacts`
2. Start app and perform scenario:
   - launch app
   - start recording
   - stop recording
   - repeat for 2-3 cycles
3. Immediately after scenario, capture artifacts again:
   - `make capture-artifacts`
4. If system crashes/reboots, run capture immediately after login:
   - `make capture-artifacts`
5. Append one entry to test ledger:
   - `docs/testing/test-ledger.md`

## Evidence Checklist
- `~/Library/Application Support/koto-type/kototype_*.log`
- `~/Library/Application Support/koto-type/server.log`
- latest `KotoType*.ips` reports
- latest `ResetCounter*.diag`, `JetsamEvent*.ips`
- process snapshot (`ps`, `pgrep`)
- git commit/hash and local diff

## Fast Triage Queries
1. Restart storm density in server log:
   - `rg "Server started" ~/Library/Application\ Support/koto-type/server.log | tail -n 100`
2. Model-load overlap:
   - `rg "Loading Whisper model|Model loaded" ~/Library/Application\ Support/koto-type/server.log | tail -n 200`
3. Circuit breaker messages in app log:
   - `rg "opening circuit breaker|start suppressed|auto-recovery disabled|recovery suppressed" ~/Library/Application\ Support/koto-type/kototype_*.log`

## Exit Criteria
- No unbounded server start loop during recording start/stop flow.
- No overlapping model-load storm in logs.
- If backend fails, circuit breaker opens and remains bounded.
- Complete artifact bundle exists for each run.
