#!/usr/bin/env bash
# Prints every shell source in the repository, NUL-delimited.
set -euo pipefail
cd "$(dirname "$0")/.."
git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    case "$f" in
    *.sh | *.bash | *.bats) printf '%s\0' "$f" ;;
    *)
      if head -n1 "$f" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b'; then
        printf '%s\0' "$f"
      fi
      ;;
    esac
  done
