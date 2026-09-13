#!/bin/sh
# license-check.sh — Plan 01 quality gate: enforce the single licensing story.
# Canonical license: MIT (ADR-0006; reconciliation: docs/program/16A).
set -eu

cd "$(dirname "$0")/.."

fail() { echo "license-check: FAILED — $1" >&2; exit 1; }

[ -f LICENSE ] || fail "LICENSE missing"
grep -q "MIT License" LICENSE || fail "LICENSE is not MIT"
if grep -qi "GNU GENERAL PUBLIC" LICENSE; then fail "LICENSE contains GPL text"; fi

# No GPL license text in shipped sources or vendored code.
if grep -rn --include="*.swift" --include="*.sh" -i "GNU General Public License" Sources Tests scripts 2>/dev/null | grep -v "license-check.sh"; then
  fail "GPL license text found in shipped sources"
fi

# Package manifest must remain dependency-free or explicitly justified (ADR-0003).
if grep -E "^\s*\.package\(url:" Package.swift | grep -v "swift-argument-parser"; then
  echo "license-check: note — external dependency present; ensure it is covered by THIRD_PARTY_NOTICES + ADR"
fi

echo "license-check: ok (MIT single-story enforced)"
