#!/bin/bash
# scripts/smoke/04-frontend.sh
# Closes issue #4 (Frontend local dev).
# Validates Vite dev server responde con HTML que contiene #root y monta main.tsx.
#
# Env: FRONTEND_URL (default http://localhost:5173)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

FRONTEND_URL="${FRONTEND_URL:-http://localhost:5173}"

echo "=== Smoke 04: Frontend dev ==="
echo "Target: $FRONTEND_URL"

RESPONSE=$(curl -s -w "\n%{http_code}" "$FRONTEND_URL/" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "/ respondió 200"
else
  fail "/ devolvió $HTTP_CODE — ¿está corriendo 'npm run dev' en frontend/?"
  echo "RESULTADO: FAIL"; exit 1
fi

if echo "$BODY" | grep -q 'id="root"'; then
  ok 'HTML contiene <div id="root">'
else
  fail 'HTML no contiene <div id="root">'
fi

if echo "$BODY" | grep -qE '/(src/main\.tsx|@vite/client)'; then
  ok "Vite dev script presente"
else
  fail "no se detecta el script de Vite — ¿es la app correcta?"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
