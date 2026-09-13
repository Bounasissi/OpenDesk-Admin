# Definition of Done — OpenDesk Admin

## Project-level DoD (the clone test)

A fresh administrator installs OpenDesk and, **without Apple Remote Desktop**, can perform everything in [SRS-ROADMAP.md §6](../docs/SRS-ROADMAP.md#6-acceptance--clone-definition-of-done).

## Per-milestone DoD template

### Product
- [ ] User role is clear (macOS admin/IT operator).
- [ ] Use case tied to lifecycle: Build, Test, Deploy, Monitor, or Improve.
- [ ] Required product objects identified (Device, Task, Schedule, Result, Audit Event).
- [ ] Out-of-scope items explicitly excluded.

### Technical
- [ ] Files changed listed in PR.
- [ ] New dependencies justified (GPL compatibility checked).
- [ ] Existing behavior preserved unless intentionally changed.
- [ ] Tests added or updated (`swift test` green).
- [ ] Failure states handled (offline host, auth failure, timeout, partial failure).
- [ ] Logs/evidence available (task_events rows, audit_events rows).

### Governance / Clean-room
- [ ] Owner defined.
- [ ] Approval gate defined if risk warrants (power actions, package installs).
- [ ] Audit/evidence bundle requirements clear.
- [ ] Versioning impact understood.
- [ ] Rollback path documented.
- [ ] **Clean-room check: could this have been written from behavior specs + public docs alone?**

### Verification
- [ ] `swift build` passes.
- [ ] `swift test` passes.
- [ ] Manual QA path documented against test lab.
- [ ] Screenshots/logs/results attached if applicable.

## Milestone 3 (current) verification commands

```bash
swift build
swift test
swift run opendesk --help
bash -n scripts/analyze-ard-bundle.sh
bash -n scripts/capture-experiment.sh
sqlite3 packages/device-registry/Assets/schema.sql ".schema" # schema parses
```
