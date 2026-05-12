#!/bin/bash
# scripts/smoke/07-frontend-docker.sh
# Closes issue #8 (Frontend Dockerfile + Nginx).
# Valida que el container del frontend (build estático vía Nginx) sirve la SPA.
# Asume que el container ya está corriendo: `docker run -p 8081:80 mnemos-frontend`.
#
# Env: FRONTEND_DOCKER_URL (default http://localhost:8081)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

FRONTEND_DOCKER_URL="${FRONTEND_DOCKER_URL:-http://localhost:8081}"

echo "=== Smoke 07: Frontend Docker ==="
echo "Target: $FRONTEND_DOCKER_URL"

RESPONSE=$(curl -s -w "\n%{http_code}" "$FRONTEND_DOCKER_URL/" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "/ respondió 200"
else
  fail "/ devolvió $HTTP_CODE — ¿el container está corriendo en ese puerto?"
  echo "RESULTADO: FAIL"; exit 1
fi

if echo "$BODY" | grep -q 'id="root"'; then
  ok 'HTML contiene <div id="root">'
else
  fail 'HTML no contiene <div id="root">'
fi

# Build estático no debe tener referencias al dev server de Vite
if echo "$BODY" | grep -q '@vite/client'; then
  fail 'detectado @vite/client — el container está sirviendo dev en lugar de build'
else
  ok "no hay rastros de Vite dev (build correcto)"
fi

# Probar SPA fallback: ruta inexistente debe devolver 200 con index.html (try_files de Nginx)
ROUTE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_DOCKER_URL/some/deep/route" 2>/dev/null)
if [[ "$ROUTE_CODE" == "200" ]]; then
  ok "SPA fallback funciona (try_files devuelve index.html)"
else
  fail "ruta SPA devolvió $ROUTE_CODE (esperado 200 — falta try_files en Nginx)"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
