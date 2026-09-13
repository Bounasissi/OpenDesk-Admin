# RELEASE_CHECKLIST — OpenDesk

**Owner:** Plan 20/21/22. Final verification uses the **downloaded published artifact** — never the local build.

---

## 1. Pre-Publication

- [ ] `make verify` green on release branch
- [ ] Version bumped; monotonic bundle version
- [ ] CHANGELOG + release notes final
- [ ] License/dependency inventory + SBOM generated
- [ ] Checksums generated
- [ ] `codesign --verify --deep --strict` passes (app + every nested helper)
- [ ] Notarized + stapled; `xcrun stapler validate` passes
- [ ] `spctl --assess --type execute` passes
- [ ] Update feed entry generated; Ed25519-signed; HTTPS verified
- [ ] Rollback runbook rehearsed (`docs/runbooks/ROLLBACK.md`)

## 2. Published-Artifact Verification (clean supported Mac)

- [ ] Gatekeeper accepts download
- [ ] App launches
- [ ] Permissions explain themselves (onboarding detection)
- [ ] Database initializes
- [ ] Device can be added
- [ ] Remote session works (observe + control)
- [ ] Task works (dispatch → result)
- [ ] Diagnostics export works
- [ ] Update check works

## 3. Upgrade Path (per Plan 21)

- [ ] previous beta → RC
- [ ] RC → next RC
- [ ] database migration, Keychain retention, agent compatibility, scheduled tasks, update signature verified

## 4. Launch Declaration Gate (Plan 22 §8)

- [ ] public URL accessible
- [ ] release artifact downloadable
- [ ] Gatekeeper verification passes
- [ ] v1 source tag exists
- [ ] documentation accessible
- [ ] stable update feed accessible
- [ ] critical smoke test passes

## 5. Blocking Rule

Any unchecked item in §2 or an open P0/P1 blocks publication. Failures are repaired and the affected checks rerun — not waived.
