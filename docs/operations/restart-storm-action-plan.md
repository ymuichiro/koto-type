# Restart Storm Action Plan

## Problem Statement
Production-like recording flow can trigger backend restart storms. The storm itself, not just one crash, is the core issue because repeated process starts amplify memory pressure and can destabilize the OS session.

## Scope
- In scope:
  - backend process lifecycle control
  - model-load concurrency control
  - failure recovery limits
  - evidence persistence for post-crash analysis
- Out of scope:
  - model quality tuning
  - UI redesign

## Technical Work Breakdown
1. Process start containment
- [x] enforce max active backend process count (Python shared state)
- [x] enforce max parallel model loading count (Python shared state)
- [x] add PID-correlated server logging

2. Recovery-loop containment
- [x] disable immediate auto-recovery on status 9 idle termination
- [x] disable immediate retry/recovery when status 9 happens during active segment processing
- [x] add start-failure circuit breaker + cooldown
- [x] remove startup race where a process could terminate before manager registration and escape suppression
- [x] prevent stale process leakage on `initialize` re-entry
- [x] bound no-idle retry queue attempts

3. Forensic persistence
- [x] add runbook for crash-resilient testing
- [x] add artifact capture script and Make target
- [x] add test ledger to preserve decisions/evidence

4. Remaining hardening tasks
- [x] add dedicated Swift tests for `MultiProcessManager` circuit-breaker behavior
- [ ] add integration test with a fake backend that exits immediately to validate bounded retries
- [ ] add telemetry counters in app logs (`start_attempts`, `breaker_opened`, `breaker_remaining_seconds`)
- [ ] run production-like recording validation and compare pre/post artifact bundles

## Definition of Done
- No unbounded restart loop under backend failure.
- No concurrent model-load storm under repeated failures.
- Recovery behavior is observable from logs and reproducible from artifact bundles.
- Test ledger entries exist for each production-like validation run.
