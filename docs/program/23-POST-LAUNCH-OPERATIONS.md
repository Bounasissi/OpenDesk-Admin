# Plan 23 — Post-Launch Operations

> Binding instruction document. Read `/AGENTS.md` first. This plan begins at v1.0 LIVE and never "completes."

- **Plan ID:** 23
- **Prerequisites:** 22
- **Blocks:** Nothing; ongoing

---

## 1. Goal

Prevent v1 launch from becoming the end of engineering discipline.

---

## 2. Immediate Post-Release Checks

Automatically monitor:

```text
download availability
update feed validity
release checksums
documentation links
CI
security advisories
incoming crash reports
issues
```

---

## 3. Defect Severity

```text
P0 — security compromise, destructive behavior, credential exposure
P1 — major function unavailable/crash loop
P2 — material degraded behavior
P3 — ordinary defect
```

---

## 4. Hotfix Flow

```text
reproduce
→ regression test
→ fix
→ full relevant suite
→ version bump
→ signing
→ notarization
→ staged update
→ stable update
```

Runbook: `docs/runbooks/HOTFIX.md`.

---

## 5. Release Cadence

Do not commit to calendar releases unnecessarily. Release when a coherent, tested increment is ready. Security hotfixes bypass normal feature cadence.

---

## 6. Dependency Maintenance

Automation checks:

```text
Apple SDK changes
LibVNC changes
Sparkle changes
security advisories
package vulnerabilities
license changes
macOS compatibility regressions
```

---

## 7. Compatibility Monitoring

Pay special attention to macOS releases affecting:

```text
ScreenCaptureKit
TCC permissions
Accessibility
Remote Management
background items
SMAppService
network permissions
code signing
notarization
```

---

## 8. Standing Agent Sequence

1. Stand up automated monitoring for §2 items (CI job/check script).
2. Triage incoming issues/crash reports with §3 severity.
3. Execute §4 hotfix flow for P0/P1; follow cadence rule for everything else.
4. Maintain dependency/compatibility watch list; open remediation issues on upstream changes.

---

## 9. Recurring Gate

Every release (hotfix or feature) must pass `make verify` + relevant suites + signing/notarization pipeline (Plan 20) before publication.
