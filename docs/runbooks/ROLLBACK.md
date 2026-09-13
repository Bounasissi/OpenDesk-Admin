# ROLLBACK_RUNBOOK — OpenDesk

**Owner:** Plan 22 (rollback readiness gate), Plan 23 (execution when needed).

---

## 1. Capabilities to Prove (before first publication)

```text
stop update rollout
remove/yank bad download link
restore previous stable appcast
publish hotfix
invalidate compromised release instructions
```

Rehearsal evidence is recorded in `docs/status/PROGRAM_STATUS.md` before launch.

---

## 2. Bad Update Published (artifact broken, not malicious)

1. Halt rollout: replace the newest appcast entry's enclosure URL with the previous good artifact or set its `sparkle:criticalUpdate` off / remove the entry (Sparkle 2 semantics: removal stops new offers).
2. Verify feed reverts for clients (cache/CDN TTLs documented in `docs/release/APPCAST.md`).
3. Publish hotfix per `docs/runbooks/HOTFIX.md` (P1 flow).
4. Record incident + timeline in `docs/status/PROGRAM_STATUS.md`.

---

## 3. Compromised Artifact / Signing Key Event (P0)

1. Immediately yank release asset + invalidate download link.
2. Rotate update-signing keys (Ed25519) and any leaked credentials.
3. Re-notarize and re-publish fixed artifact; version bump mandatory.
4. Communicate through SECURITY.md channel.
5. Full post-incident review appended to `docs/status/PROGRAM_STATUS.md`.

---

## 4. Appcast Restore Procedure

1. Rebuild appcast from last-good state (versioned appcast snapshots kept in `docs/release/` artifacts per release).
2. Sign with current Ed25519 key.
3. Validate HTTPS + signature + monotonic versions before re-publishing.

---

## 5. Rules

- Never ship an untested "rollback" — the rollback artifact must itself pass the release checklist.
- Terminal rule: an update that cannot pass Gatekeeper assessment must never be linked again.
