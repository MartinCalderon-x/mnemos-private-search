#!/bin/bash
# scripts/smoke/02-supabase.sh
# Closes issue #2 (Supabase link + migraciones).
# Validates that knowledge_base table exists and is reachable via REST.
#
# Env: SUPABASE_URL, SUPABASE_SECRET_KEY (sb_secret_...)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

# Cargar .env del repo si existe
if [[ -f "$(dirname "$0")/../../.env" ]]; then
  set -a; source "$(dirname "$0")/../../.env"; set +a
fi

echo "=== Smoke 02: Supabase ==="

if [[ -z "${SUPABASE_URL:-}" ]]; then
  fail "SUPABASE_URL no está definido"
  echo "RESULTADO: FAIL"; exit 1
fi
if [[ -z "${SUPABASE_SECRET_KEY:-}" ]]; then
  fail "SUPABASE_SECRET_KEY no está definido (debe empezar con sb_secret_)"
  echo "RESULTADO: FAIL"; exit 1
fi
if [[ "$SUPABASE_SECRET_KEY" != sb_secret_* ]]; then
  fail "SUPABASE_SECRET_KEY no parece una secret key 2025+ (esperado prefijo sb_secret_)"
fi

echo "Target: $SUPABASE_URL"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "apikey: $SUPABASE_SECRET_KEY" \
  -H "Authorization: Bearer $SUPABASE_SECRET_KEY" \
  "$SUPABASE_URL/rest/v1/knowledge_base?select=id&limit=1" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  200)
    ok "knowledge_base accesible vía REST"
    ;;
  401|403)
    fail "auth rechazada ($HTTP_CODE) — verificar SUPABASE_SECRET_KEY"
    ;;
  404)
    fail "knowledge_base no existe — falta correr migraciones"
    ;;
  *)
    fail "HTTP $HTTP_CODE — body: ${BODY:0:200}"
    ;;
esac

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
