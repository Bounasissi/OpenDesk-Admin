# APPCAST — OpenDesk Update Feed (Sparkle 2)

**Owner:** Plan 20. Default updater: Sparkle 2 unless the repository already has an equivalent mechanism.

---

## 1. Requirements

```text
HTTPS distribution
Ed25519 update signature
Developer ID signing
notarization
monotonic bundle versions
release notes
rollback procedure
```

Update-signing private keys are **not stored on public web infrastructure** (CI secret storage only).

---

## 2. Feed Contract

- `appcast.xml` served over HTTPS.
- Each entry: version, build, enclosure URL, Ed25519 signature, release-notes link, critical-update flag when warranted.
- Versions strictly monotonic per channel (`stable`, `beta`, `rc` channels supported).
- Per-release appcast snapshots archived in this directory for rollback rebuilds (`docs/runbooks/ROLLBACK.md` §4).

---

## 3. Generation (per release, from Plan 20 pipeline)

1. CI generates the entry from the signed/notarized artifact.
2. Signature produced with Ed25519 private key from secure storage (external gate if absent).
3. Validation step confirms: HTTPS URL, signature verify against published public key, monotonic version.

---

## 4. Rollout Modes

- **stable:** all clients.
- **staged (hotfix):** phased enclosure exposure per `docs/runbooks/HOTFIX.md`.
- **halt:** remove/supersede entry to stop offers (rollback runbook §2).

---

## 5. Key Management Rules

- Public Ed25519 key is embedded in the app and published in docs.
- Private key lives only in CI secret storage or a secure operator keychain; never in the repo, never on the web host.
