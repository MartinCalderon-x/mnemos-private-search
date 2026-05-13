#!/bin/bash
# scripts/smoke/01-searxng.sh
# Closes issue #3 (Docker Compose local — SearxNG).
# Validates that SearxNG responds with parseable JSON for a known query.
#
# Env: SEARXNG_URL (default http://localhost:8080)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

SEARXNG_URL="${SEARXNG_URL:-http://localhost:8080}"

echo "=== Smoke 01: SearxNG ==="
echo "Target: $SEARXNG_URL"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq no está instalado (brew install jq)"
  echo "RESULTADO: FAIL"; exit 1
fi

RESPONSE=$(curl -s -w "\n%{http_code}" "$SEARXNG_URL/search?q=hello&format=json" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "/search respondió 200"
else
  fail "/search devolvió $HTTP_CODE (esperado 200) — ¿está corriendo 'docker compose up -d'?"
fi

if echo "$BODY" | jq -e '.results' >/dev/null 2>&1; then
  COUNT=$(echo "$BODY" | jq '.results | length')
  ok "respuesta JSON con .results ($COUNT items)"
else
  fail "respuesta no es JSON válido o no tiene .results"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
