#!/bin/bash
# scripts/smoke/05-end-to-end.sh
# Validación full del modo Local: corre 01-04 secuencialmente.
# RESULTADO: PASS solo si los 4 pasan.

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS=(01-searxng.sh 02-supabase.sh 03-http-api.sh 04-frontend.sh)
RESULTS=()
FAILED=0

echo "=== Smoke 05: End-to-end (modo Local) ==="
echo

for S in "${SCRIPTS[@]}"; do
  echo -e "${YELLOW}--- $S ---${NC}"
  if "$DIR/$S"; then
    RESULTS+=("✓ $S")
  else
    RESULTS+=("✗ $S")
    FAILED=1
  fi
  echo
done

echo "=== Resumen ==="
for R in "${RESULTS[@]}"; do
  if [[ "$R" == ✗* ]]; then
    echo -e "${RED}$R${NC}"
  else
    echo -e "${GREEN}$R${NC}"
  fi
done

echo
if [[ "$FAILED" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
