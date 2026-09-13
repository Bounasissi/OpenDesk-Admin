# Plan 19 — Open-Source Release Readiness

> Binding instruction document. Read `/AGENTS.md` first. Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 19
- **Prerequisites:** 01–18
- **Blocks:** 20 (public artifacts need docs), 22 (public repo consumable)

---

## 1. Goal

Make the repository genuinely consumable as an open-source project.

---

## 2. Required Files

```text
README.md
LICENSE
CONTRIBUTING.md
SECURITY.md
CODE_OF_CONDUCT.md
CHANGELOG.md
SUPPORT.md
THIRD_PARTY_NOTICES.md
```

---

## 3. README Minimum

Include:

```text
what OpenDesk is
screenshots
current capabilities
supported macOS
installation
first-run permissions
build instructions
architecture overview
roadmap
security reporting
license
```

---

## 4. Licensing

If direct linkage to GPL-licensed components remains part of the shipped application, ensure the repository's license and distribution obligations are compatible.

Do not guess through an unresolved license conflict. Automate a license inventory (extends Plan 16 output).

---

## 5. Reproducibility

A new contributor must be able to:

```text
clone → bootstrap → build → test → run
```

using documented commands.

---

## 6. Architecture Docs

Document:

```text
process model
module graph
persistence
protocols
security boundaries
agent enrollment
task execution
release process
```

---

## 7. Agent Sequence

1. Write/verify all §2 files (README per §3 minimum, accurate and current).
2. Complete architecture documentation per §6 (the `docs/architecture/` set must be true of the code — reconcile any drift found).
3. Run reproducibility test: clean-clone walkthrough exactly as documented; fix gaps.
4. Automate third-party notice generation and license inventory.
5. Final branch-level review per AGENTS.md §6.

---

## 8. Tests Required

- Reproducibility check runs in CI (fresh clone bootstrap/build/test).
- Link check on docs (no dead internal links).
- `THIRD_PARTY_NOTICES.md` generation verified against dependency inventory.

---

## 9. Exit Gate

An external developer unfamiliar with the project can build OpenDesk from the public repository.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `20-CI-CD-SIGNING-NOTARIZATION-UPDATES`).
