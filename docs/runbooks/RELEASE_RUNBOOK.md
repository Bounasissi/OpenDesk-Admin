# RELEASE_RUNBOOK — OpenDesk

**Owner:** Plan 20/22. Executed per tagged release. Credentials are external-gated per `PROGRAM_CHARTER.md` §7.

---

## 1. Preconditions

```text
[x] make verify green on release branch
[x] CHANGELOG + release notes drafted
[x] version bumped; bundle version monotonic
[x] signing identity + notarytool profile available in CI secret storage (external gate if absent)
[x] Sparkle Ed25519 private key available in secure storage (external gate if absent)
```

---

## 2. Pipeline Stages (CI enforces)

```text
source verification → build → unit tests → integration tests → security/license scan
→ archive → codesign → verify signature → notarize → staple
→ Gatekeeper assessment → package → checksum → SBOM
→ update-feed generation → release publication
```

Verification commands:

```bash
codesign --verify --deep --strict --verbose=2 OpenDesk.app
spctl --assess --type execute --verbose=4 OpenDesk.app
xcrun stapler validate OpenDesk.app
```

---

## 3. Publication Steps

1. Tag: signed tag `<version>`.
2. CI run on tag → artifact assembly.
3. GitHub Release (default host) with: `.dmg`/`.zip`, checksums, SBOM, release notes, source archive.
4. Update appcast (HTTPS, Ed25519 signature, monotonic version) per `docs/release/APPCAST.md`.
5. Update docs/landing page (GitHub Pages default).

---

## 4. Post-Publication Verification

Execute `docs/release/RELEASE_CHECKLIST.md` against the **downloaded published artifact** on a clean supported Mac.

---

## 5. Rollback

Follow `docs/runbooks/ROLLBACK.md` (must be rehearsed before first publication — Plan 22 gate).
