#!/usr/bin/env bash
# ARD bundle analyzer — static decomposition harness (clean-room policy compliant).
# Inspects a lawfully owned copy of Remote Desktop.app for architecture understanding:
# linked frameworks, entitlements, XPC services, URL schemes, resource types.
# Records FACTS ABOUT INTERFACES — never reconstructed logic.
set -euo pipefail

APP="${1:-/Applications/Remote Desktop.app}"
OUT="${2:-./reverse-engineering/protocol-observations/bundle-analysis}"
mkdir -p "$OUT"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found. Pass the path to a lawfully owned copy of Remote Desktop.app" >&2
  exit 1
fi

echo "== bundle tree ==" | tee "$OUT/bundle-tree.txt"
find "$APP/Contents" -print | tee -a "$OUT/bundle-tree.txt"

echo "== Info.plist ==" | tee "$OUT/info-plist.txt"
plutil -p "$APP/Contents/Info.plist" | tee -a "$OUT/info-plist.txt"

echo "== code signature ==" | tee "$OUT/codesign.txt"
codesign -d --verbose=4 "$APP" 2>&1 | tee -a "$OUT/codesign.txt"
codesign -d --entitlements :- "$APP" 2>&1 | tee -a "$OUT/codesign.txt"

BINARIES=$(find "$APP/Contents" -type f \( -perm +111 -o -name "*.dylib" \) | grep -v -E '\.(nib|strings|plist|lproj)' || true)

for BIN in $BINARIES; do
  NAME=$(basename "$BIN")
  echo "== $NAME: otool -L ==" | tee -a "$OUT/linked-frameworks.txt"
  otool -L "$BIN" 2>/dev/null | tee -a "$OUT/linked-frameworks.txt" || true
  echo "== $NAME: architectures ==" | tee -a "$OUT/architectures.txt"
  otool -hv "$BIN" 2>/dev/null | tee -a "$OUT/architectures.txt" || true
  echo "== $NAME: strings ==" 
  strings -a "$BIN" > "$OUT/strings-${NAME}.txt" 2>/dev/null || true
done

echo "== resource inventory ==" | tee "$OUT/resources.txt"
find "$APP" \( \
  -name "*.plist" -o -name "*.strings" -o -name "*.sdef" \
  -o -name "*.storyboardc" -o -name "*.nib" -o -name "*.momd" \
  -o -name "*.sqlite" \) -print | tee -a "$OUT/resources.txt"

echo "Done. Output in $OUT"
echo "REMINDER (clean-room policy): findings are interface facts only."
echo "No decompiled logic, translated code, or Apple assets may enter packages/ or apps/."
