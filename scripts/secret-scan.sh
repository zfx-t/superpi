#!/usr/bin/env bash
# Lightweight secret scan before push.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

patterns=(
  'api[_-]?key'
  'xai-[A-Za-z0-9]'
  'sk-[A-Za-z0-9]'
  'BEGIN (RSA |OPENSSH )?PRIVATE KEY'
  'password\s*=\s*["'\''][^"'\'']+["'\'']'
)

fail=0
while IFS= read -r -d '' file; do
  case "$file" in
    ./.git/*|./runs/*|./.pi/*) continue ;;
  esac
  for pat in "${patterns[@]}"; do
    if grep -nIiE "$pat" "$file" 2>/dev/null | head -n 5; then
      echo "Potential secret pattern in: $file (/$pat/)" >&2
      fail=1
    fi
  done
done < <(find . -type f \
  ! -path './.git/*' \
  ! -path './runs/*' \
  ! -name '*.png' ! -name '*.jpg' ! -name '*.pdf' \
  -print0)

if [[ $fail -ne 0 ]]; then
  echo "secret-scan: FAIL" >&2
  exit 1
fi
echo "secret-scan: OK"
