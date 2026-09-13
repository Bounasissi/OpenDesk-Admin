# Plan 22 — Production Launch

> Binding instruction document. Read `/AGENTS.md`, `docs/release/RELEASE_CHECKLIST.md`, and `docs/runbooks/ROLLBACK.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 22
- **Prerequisites:** 01–21
- **Blocks:** 23

---

## 1. Goal

Publish v1.0 and make OpenDesk usable by people who have never seen the repository.

---

## 2. Pre-Launch Freeze

Lock the release commit. Generate:

```text
version 1.0.0
signed tag
release notes
changelog
checksums
SBOM
license notices
notarized artifact
update feed entry
```

---

## 3. Final Verification

Test the **downloaded published artifact**, not merely the local build. On a clean supported Mac verify:

```text
Gatekeeper accepts
app launches
permissions explain themselves
database initializes
device can be added
remote session works
task works
diagnostics work
update check works
```

---

## 4. Public Release

When remote/provider permissions allow:

```text
push v1.0.0 tag
create public release
upload notarized artifact
publish checksums
publish SBOM
publish release notes
update stable appcast
publish documentation
publish website/landing page
```

If GitHub is the repository provider, GitHub Releases is the default binary host unless existing infrastructure is better.

---

## 5. Landing Page

Minimum:

```text
what OpenDesk does
download
system requirements
screenshots
quick start
security
GitHub link
documentation
known limitations
```

Use GitHub Pages by default if no existing product site exists.

---

## 6. Open-Source Discovery

Repository metadata:

```text
description
topics
social preview
releases
screenshots
installation badge/status
CI badge
license
```

---

## 7. Rollback Readiness

Before publication, prove the team can:

```text
stop update rollout
remove/yank bad download link
restore previous stable appcast
publish hotfix
invalidate compromised release instructions
```

Evidence: rehearsed `docs/runbooks/ROLLBACK.md` execution record.

---

## 8. Launch Declaration

Do not mark OpenDesk `LIVE` until:

```text
public URL accessible
release artifact downloadable
Gatekeeper verification passes
v1 source tag exists
documentation accessible
stable update feed accessible
critical smoke test passes
```

Then update:

```json
{
  "release": "1.0.0",
  "status": "LIVE"
}
```

(in `docs/status/program-state.json`).

---

## 9. Exit Gate

All §8 conditions hold with evidence committed to `docs/status/PROGRAM_STATUS.md`.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `23-POST-LAUNCH-OPERATIONS`).
