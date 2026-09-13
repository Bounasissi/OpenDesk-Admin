#!/bin/sh
# secret-scan.sh — Plan 01 quality gate: fail on committed secret material.
# Patterns cover the credential classes OpenDesk will ever handle locally.
set -eu

cd "$(dirname "$0")/.."

HITS=$(git ls-files -z -- . ':!:docs' ':!:*.md' | xargs -0 -I{} sh -c '
  grep -nEH "-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[bpars]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9]{20,}" "$1" 2>/dev/null || true
' _ {} || true)

if [ -n "$HITS" ]; then
  echo "secret-scan: FAILED — potential secrets committed:"
  printf '%s\n' "$HITS"
  exit 1
fi
echo "secret-scan: ok (no secret material in tracked sources)"
