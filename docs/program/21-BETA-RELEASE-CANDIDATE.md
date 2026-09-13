# Plan 21 — Beta and Release Candidate

> Binding instruction document. Read `/AGENTS.md`, `docs/program/PROGRAM_CHARTER.md` §3, and `docs/release/RELEASE_CHECKLIST.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 21
- **Prerequisites:** 01–20
- **Blocks:** 22

---

## 1. Goal

Prove the release process and real-world product flow before v1.0.

---

## 2. Alpha Milestone

Expected feature baseline:

```text
device registry
remote control
commands
file transfer
package install
task engine
basic inventory
```

Tag: `0.x-alpha`

---

## 3. Beta Milestone

Must include:

```text
endpoint agent
groups
scheduler
reports
CLI
onboarding
security hardening
diagnostics
auto-update
```

Tag: `0.9.0-beta.*`

---

## 4. Release Candidate

Freeze feature additions. Only:

```text
defect fixes
security fixes
release/documentation fixes
```

Tag: `1.0.0-rc.*`

---

## 5. RC Acceptance Suite

Execute on the **exact public-distribution artifact**:

```text
clean installation
first launch
permission onboarding
add device
authenticate
observe
control
clipboard
push/pull file
execute command
install package
inventory
group task
schedule
offline/reconnect task
app restart
agent restart
auto-update
uninstall/reinstall
diagnostic export
```

---

## 6. Upgrade Testing

At minimum:

```text
previous beta → RC
RC → next RC
```

Verify:

```text
database migration
Keychain retention
agent compatibility
scheduled tasks
update signature
```

---

## 7. Bug Policy

Release blockers:

```text
P0 — data/security/destructive issue
P1 — core feature unavailable or repeated crash
```

No open P0/P1 enters v1.

---

## 8. Agent Sequence

1. Tag alpha once feature baseline passes CI; record smoke evidence.
2. Tag beta once §3 set passes CI + smoke; distribute via update feed.
3. Freeze features; drive RC cycles: defects → fixes → rerun §5 suite + §6 upgrades.
4. Gate v1 on zero open P0/P1.

---

## 9. Exit Gate

A release candidate passes the complete release suite using the exact public-distribution artifact.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `22-PRODUCTION-LAUNCH`).
