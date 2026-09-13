# Plan 01 — Repository Baseline

> Binding instruction document. Read `/AGENTS.md` and `docs/program/00-MASTER-ORCHESTRATOR.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 01
- **Prerequisites:** None
- **Blocks:** 02–23

---

## 1. Goal

Turn the first-commit repository into a deterministic development environment.

---

## 2. Required Outputs

Establish or repair:

```text
build
unit-test command
integration-test command
lint/static-analysis command
format command
CI workflow
dependency lock/pinning
versioning
bundle identifiers
entitlements organization
test fixtures
configuration separation
debug/release schemes
```

---

## 3. Agent Sequence

### 3.1 Repository census

Record (commit the result as `docs/status/REPO_CENSUS.md` or equivalent):

```text
git remote
branches
current commit
project/workspace structure
targets
Swift packages
minimum macOS version
Xcode/Swift requirements
dependencies
tests
CI
licenses
build warnings
```

### 3.2 Establish canonical commands

At minimum provide:

```bash
make bootstrap
make build
make test
make lint
make verify
```

Equivalent scripts are acceptable if repository convention already exists. `make verify` must be the single local pre-merge gate.

### 3.3 Pin toolchain assumptions

Record compiler and Xcode requirements. Default v1 admin-app deployment target: **macOS 14+**, unless existing repository architecture already justifies another floor. Features requiring newer OS APIs use availability checks rather than silently raising the entire application's minimum OS.

### 3.4 Remove accidental nondeterminism

Fix:

- unpinned dependencies;
- generated files committed inconsistently;
- local absolute paths;
- developer-machine secrets;
- build scripts requiring private shell state.

### 3.5 CI

Required pull-request CI:

```text
build
unit tests
lint
dependency/license validation
secret scan
basic security/static analysis
```

---

## 4. Engineering Rules Specific to This Plan

- This plan may run on the default branch only if no source code exists yet to endanger; otherwise branch per §4 of AGENTS.md.
- Bundle identifiers, entitlements files, and schemes are created even if the app shell is still minimal.
- Create the `Tests/` target with a passing smoke test so `make test` is meaningful from day one.
- Choose the project's open-source license **now** (default: a permissive license such as Apache-2.0 or MIT unless an ADR records a different ruling; note that Plan 06's LibVNCClient licensing analysis depends on this choice). Record it in `LICENSE` and an ADR.

---

## 5. Tests Required

- `make verify` passes on a clean clone.
- CI workflow green on the plan branch.

---

## 6. Exit Gate

A clean clone can execute the documented bootstrap and verification path successfully.

---

## 7. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` (ledger + phase-gate report) and `docs/status/program-state.json` (set `currentPlan` to `02-CLEAN-ROOM-DECOMPOSITION`).
