# Plan 16A — License and Dependency Reconciliation

> Binding instruction document. Executes before any public distribution (blocks Plan 19/20 exit).
> Source requirement: Addendum §4. Lineage conflict evidence: `docs/status/REPOSITORY_LINEAGE.md` §2.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 16A
- **Prerequisites:** 00A (lineage rulings), 06A (architecture decision)
- **Blocks:** 19 exit, 20 exit, any public release artifact

---

## 1. The Conflict

Conversation histories alternately claim:

```text
GPL-3.0-or-later   (scaffold history, OG-Output-Plan-0913 LICENSE)
MIT                (implementation history, initial-091396 LICENSE — canonical)
```

There may be exactly **one authoritative licensing story** for the repository and its release artifacts.

## 2. Required Work

### 2.1 Dependency/license inventory

Generate a complete inventory of everything that ships or is used at build time:

| Class | Check |
|---|---|
| SwiftPM dependencies | `Package.swift` + `Package.resolved` — canonical has none as of 2026-09-13 |
| System libraries linked | `libsqlite3` (via SQLite3 module — Apple-provided, permissive terms), system `ssh`/`sftp`/`installer` invoked as separate processes (not linked) |
| Vendored code | none as of 2026-09-13 |
| Scaffold-derived sources | excluded from canonical tree (ruling: `REPOSITORY_LINEAGE.md` §2) |

Classify every GPL-adjacent item as one of:

```text
linked
embedded
dynamically linked
separately executed
development-only
unused
```

### 2.2 License selection

**Default ruling:** repository license = **MIT**, matching the canonical implementation history, because:

1. The canonical code base is MIT with zero GPL-linked dependencies (verified: single-target `Package.swift`, no external packages).
2. System `libsqlite3` is not a distribution obligation trigger for MIT-licensed combined works in Apple's SDK-provided form; `THIRD_PARTY_NOTICES` still records it.
3. The GPL-3.0 `LICENSE` exists only in the unmerged scaffold branch; its Swift sources are excluded from canonical.
4. Same-author provenance: both histories were authored inside this repository; the owner may relicense scaffold-derived code, but until explicitly ruled, GPL text stays out of the MIT tree.

**External gate:** owner confirmation of the MIT ruling + explicit decision on whether scaffold-derived code (OG-Output-Plan-0913) may be relicensed into MIT. Until confirmed: scaffold sources remain reference-only, and any port of their behavior into canonical code must be re-authored (or ruled) in canonical license terms.

### 2.3 Consistency sweep

Update consistently (all or nothing):

```text
LICENSE
README (license section)
Package.swift (no license field needed; keep dependency-free)
source headers where applicable
THIRD_PARTY_NOTICES (NEW file: libsqlite3 notice + any future deps)
SBOM (Plan 20 artifact)
release artifacts
```

## 3. Tests / Verification

```text
grep-based license scan (no GPL headers/text in canonical sources)
scripts/build-app.sh artifact inspected: no GPL components bundled
CI job: license inventory + SBOM generated per release (Plan 20 wiring)
```

## 4. Exit Gate

- [ ] Dependency/license inventory committed (machine-readable, consumed by Plan 20 SBOM step).
- [ ] Exactly one license selected and swept across all artifacts listed in §2.3.
- [ ] Owner confirmation recorded or the item sits in `PROGRAM_STATUS.md` §2 External Gates with the exact remaining action.
- [ ] No open Critical/High license conflict.
- [ ] `THIRD_PARTY_NOTICES` exists and is accurate.
