#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  echo "=== $(basename "$test_file") ==="
  bash "$test_file" || status=1
done

if (( status != 0 )); then
  echo "TESTES FALHARAM"
  exit 1
fi

echo "TODOS OS TESTES PASSARAM"
