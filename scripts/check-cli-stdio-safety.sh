#!/usr/bin/env bash
set -euo pipefail

file="${1:-CLI/cmux.swift}"

if [[ ! -f "$file" ]]; then
  echo "Missing file: $file" >&2
  exit 1
fi

patterns=(
  'FileHandle\.standardOutput\.write'
  'FileHandle\.standardError\.write'
  '\bprint\('
  '\bSwift\.print\('
  '\bFoundation\.print\('
  '\bputs\('
)

violations=0
for pattern in "${patterns[@]}"; do
  if rg -n "$pattern" "$file"; then
    violations=1
  fi
done

if [[ "$violations" -ne 0 ]]; then
  echo "Unsafe CLI stdio usage detected in $file" >&2
  exit 1
fi

echo "CLI stdio audit passed for $file"
echo "cliPrint callsites: $(rg -c '\bcliPrint\(' "$file")"
echo "cliWriteStdout callsites: $(rg -c '\bcliWriteStdout\(' "$file")"
echo "cliWriteStderr callsites: $(rg -c '\bcliWriteStderr\(' "$file")"
echo "cliWriteFatalStderr callsites: $(rg -c '\bcliWriteFatalStderr\(' "$file")"
