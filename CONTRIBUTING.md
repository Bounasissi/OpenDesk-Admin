# Contributing to OpenDesk

Thank you for contributing. OpenDesk is a clean-room, open-source macOS fleet
administration tool — independent implementation of public protocols.

## Ground rules

1. **Read the binding instructions first:** `AGENTS.md`, `docs/program/PROGRAM_CHARTER.md`, and the active plan in `docs/program/`.
2. **Clean-room policy is non-negotiable:** no Apple proprietary code, binaries, decompiled material, or assets may enter this repository. See `docs/clean-room/POLICY.md`.
3. **Licensing:** MIT only. Do not import GPL-licensed code into the canonical tree (`docs/program/16A-LICENSE-DEPENDENCY-RECONCILIATION.md`).
4. **No plaintext secrets ever** — credentials live in macOS Keychain; SQLite stores references only.

## Development flow

```bash
make bootstrap   # prepare environment (zero external dependencies)
make build       # swift build --build-tests
make test        # swift test
make lint        # full compile, warnings as errors
make verify      # single pre-merge gate: build + lint + test + secret-scan + license-check
```

## Pull requests

1. Branch from `canonical-091326` (the canonical development branch).
2. One bounded change per PR; follow `AGENTS.md` §4 conventional commits (`feat: fix: test: docs: refactor: build: ci: chore:`).
3. `make verify` must pass; CI (build + lint + test + secret-scan + license-check) must be green.
4. Tests accompany every behavior change (TDD for deterministic logic: `AGENTS.md` §5).
5. Update the relevant plan/audit documents when behavior changes (`docs/status/CAPABILITY_AUDIT.md`).

## Code review

Every meaningful change receives a specification-compliance review and a
code-quality/security review. Findings are fixed before merge.
