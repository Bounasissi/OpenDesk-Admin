# Plan 20 — CI/CD, Signing, Notarization and Updates

> Binding instruction document. Read `/AGENTS.md`, `docs/release/RELEASE_CHECKLIST.md`, and `docs/release/APPCAST.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 20
- **Prerequisites:** 01–19
- **Blocks:** 21, 22

---

## 1. Goal

Convert a tagged commit into a trustworthy public release artifact automatically.

---

## 2. Release Strategy

Default v1:

```text
Developer ID distribution
+ notarization
+ signed update feed
+ GitHub Releases (or existing repository release host)
```

Mac App Store becomes a separate distribution track, not a v1 blocker.

Apple requires Developer ID signing, Hardened Runtime, secure timestamps, and notarization for Developer ID-distributed software; sandboxing outside the App Store is recommended rather than mandatory.

---

## 3. CI Stages

```text
source verification
→ build
→ unit tests
→ integration tests
→ security/license scan
→ archive
→ codesign
→ verify signature
→ notarize
→ staple
→ Gatekeeper assessment
→ package
→ checksum
→ SBOM
→ update-feed generation
→ release publication
```

---

## 4. Signing Verification

Release pipeline must verify the app and every nested executable/helper:

```bash
codesign --verify --deep --strict --verbose=2 OpenDesk.app
spctl --assess --type execute --verbose=4 OpenDesk.app
xcrun stapler validate OpenDesk.app
```

---

## 5. Notarization

Use current Apple `notarytool` or Notary API. Credentials live in CI secret storage. Never put signing credentials into repository files.

---

## 6. Hardened Runtime

Enabled for shipped executables unless a documented platform constraint requires otherwise. Entitlements must be minimal and reviewed.

---

## 7. Updates

Default: **Sparkle 2** unless the repository already has an equivalent mechanism.

Requirements:

```text
HTTPS
Ed25519 update signature
Developer ID signing
notarization
monotonic bundle versions
release notes
rollback procedure
```

Update-signing private keys are not stored on public web infrastructure.

---

## 8. Release Artifact

Publish:

```text
OpenDesk-<version>.dmg or .zip
checksums
SBOM
release notes
source tag
source archive
```

---

## 9. External Credential Gate

If Apple signing credentials are absent, the coding agent must still finish:

```text
release scripts
CI workflow
secret names
validation
unsigned dry run
documentation
artifact assembly
failure messages
```

and mark only the actual signing/notarization step as externally gated (`PROGRAM_STATUS.md` → External Gates).

---

## 10. Exit Gate

A release tag can create a signed, notarized, stapled, updateable artifact without modifying source code manually.

---

## 11. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `21-BETA-RELEASE-CANDIDATE`).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §26)

The conversation-derived `.app` bundle + ad-hoc signing is a development milestone only. Production requires the full chain — add explicit items to §2–§8:

```text
Developer ID Application signing
Hardened Runtime (already §6)
reviewed entitlements (minimum necessary set)
secure timestamp (-timestamp flag, verified in notarization log)
notarization + stapling (already §5)
Gatekeeper assessment (spctl check on the public artifact)
DMG/ZIP release artifact + checksums + SBOM (already §8)
release notes + source tag (already §8)
stable update feed (Sparkle 2 §7, Ed25519, monotonic versions, rollback)
signing/notarization credentials only in CI secret storage — never in repo
```

Ad-hoc signed artifacts must never be published as releases.
