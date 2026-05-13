#!/bin/bash
# scripts/smoke/06-production.sh
# Validación full contra Cloud Run.
# Corre 03-http-api y 04-frontend con URLs públicas.
# Espera además que SearxNG público responda (validado vía endpoint backend).
#
# Env: BACKEND_URL, FRONTEND_URL (URLs Cloud Run)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Smoke 06: Producción (Cloud Run) ==="

if [[ -z "${BACKEND_URL:-}" ]]; then
  echo -e "${RED}✗${NC} BACKEND_URL no está definido (export BACKEND_URL=https://mnemos-backend-...run.app)"
  echo "RESULTADO: FAIL"; exit 1
fi
if [[ -z "${FRONTEND_URL:-}" ]]; then
  echo -e "${RED}✗${NC} FRONTEND_URL no está definido (export FRONTEND_URL=https://mnemos-frontend-...run.app)"
  echo "RESULTADO: FAIL"; exit 1
fi

echo "Backend:  $BACKEND_URL"
echo "Frontend: $FRONTEND_URL"
echo

RESULTS=()
FAILED=0

echo -e "${YELLOW}--- API ---${NC}"
if API_URL="$BACKEND_URL" "$DIR/03-http-api.sh"; then
  RESULTS+=("✓ API")
else
  RESULTS+=("✗ API"); FAILED=1
fi
echo

echo -e "${YELLOW}--- Frontend ---${NC}"
# El frontend en Cloud Run sirve estáticos vía Nginx — root debe contener #root.
if FRONTEND_URL="$FRONTEND_URL" "$DIR/04-frontend.sh"; then
  RESULTS+=("✓ Frontend")
else
  RESULTS+=("✗ Frontend"); FAILED=1
fi
echo

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
