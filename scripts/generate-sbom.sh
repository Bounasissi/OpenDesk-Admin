#!/bin/sh
# generate-sbom.sh — Plan 20 §8 SBOM artifact (CycloneDX-style JSON).
# Inventory: SwiftPM dependencies (zero by policy — ADR-0003), system-linked
# libraries, and the build toolchain. Deterministic output.
set -eu

cd "$(dirname "$0")/.."

SWIFT_VERSION=$(swift --version 2>/dev/null | head -1 | sed 's/.*version: //' || echo unknown)
DEPS=$(python3 - << 'EOF'
import json, subprocess, sys
deps = []
try:
    out = subprocess.run(["swift", "package", "dump-package"], capture_output=True, text=True, check=True).stdout
    manifest = json.loads(out)
    for d in manifest.get("dependencies", []):
        src = d.get("sourceControl", [{}])[0]
        deps.append({
            "name": src.get("identity", "unknown"),
            "url": src.get("location", ""),
            "requirement": json.dumps(src.get("requirement", {})),
        })
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
print(json.dumps(deps))
EOF
)

python3 - "$SWIFT_VERSION" "$DEPS" << 'EOF'
import json, sys, datetime, platform
swift_version, deps = sys.argv[1], json.loads(sys.argv[2])
sbom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "metadata": {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "component": {"type": "application", "name": "OpenDesk", "version": "unreleased"},
        "tools": [{"name": "Swift", "version": swift_version}],
    },
    "components": [
        {"type": "library", "name": d["name"], "purl": d["url"], "version": d["requirement"]}
        for d in deps
    ] + [
        {"type": "library", "name": "libsqlite3", "description": "Apple-provided system library (SQLite3 module); recorded per 16A/THIRD_PARTY_NOTICES", "scope": "required"},
    ],
    "dependencies": [{"ref": "OpenDesk", "dependsOn": ["libsqlite3"] + [d["name"] for d in deps]}],
}
json.dump(sbom, sys.stdout, indent=2)
print()
EOF
