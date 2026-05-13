#!/bin/bash
# scripts/smoke/03-http-api.sh
# Closes issue #1 (HTTP API server local — Hono).
# Validates /health + 4 endpoints documentados en docs/testing/strategy.md.
#
# Env: API_URL (default http://localhost:3000)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

# Cargar .env para el cleanup de filas creadas por este smoke
if [[ -f "$(dirname "$0")/../../.env" ]]; then
  set -a; source "$(dirname "$0")/../../.env"; set +a
fi

API_URL="${API_URL:-http://localhost:3000}"

echo "=== Smoke 03: HTTP API ==="
echo "Target: $API_URL"

probe() {
  local METHOD="$1" PATH_="$2" BODY="$3" EXPECTED="$4"
  local CODE
  if [[ "$METHOD" == "GET" ]]; then
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL$PATH_" 2>/dev/null)
  else
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X "$METHOD" -H "Content-Type: application/json" \
      -d "$BODY" "$API_URL$PATH_" 2>/dev/null)
  fi
  if [[ "$CODE" == "$EXPECTED" ]]; then
    ok "$METHOD $PATH_ → $CODE"
  else
    fail "$METHOD $PATH_ → $CODE (esperado $EXPECTED)"
  fi
}

probe GET  /health                ''                                    200
probe POST /api/search/semantic   '{"query":"hello"}'                   200
probe POST /api/search/web        '{"query":"hello"}'                   200
probe POST /api/synthesize        '{"query":"hello","sources":[]}'      200
# Marca con source="smoke-test" para poder limpiar al final
probe POST /api/knowledge/save    '{"title":"smoke-test","content":"smoke-test","source":"smoke-test"}'  200

# Cleanup: borrar las filas creadas por este smoke vía REST (requiere SUPABASE_SECRET_KEY)
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SECRET_KEY:-}" ]]; then
  curl -s -X DELETE \
    -H "apikey: $SUPABASE_SECRET_KEY" \
    -H "Authorization: Bearer $SUPABASE_SECRET_KEY" \
    "$SUPABASE_URL/rest/v1/knowledge_base?source=eq.smoke-test" >/dev/null
  ok "cleanup: filas smoke-test borradas"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
