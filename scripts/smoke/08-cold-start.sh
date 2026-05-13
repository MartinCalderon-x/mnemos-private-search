#!/bin/bash
# scripts/smoke/08-cold-start.sh
# Closes issue #11 (Anti cold-start).
# Mide TTFB del primer request al backend en Cloud Run y falla si excede umbral.
# Idea: tras un periodo idle, el primer request paga el cold start completo.
# El demo en vivo no puede pagar 10s de espera — por eso medimos.
#
# Env:
#   BACKEND_URL                     URL de Cloud Run (requerido)
#   COLD_START_THRESHOLD_MS         tope en ms (default 5000)
#   COLD_START_PATH                 endpoint a golpear (default /health)

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

echo "=== Smoke 08: Cold start ==="

if [[ -z "${BACKEND_URL:-}" ]]; then
  fail "BACKEND_URL no está definido"
  echo "RESULTADO: FAIL"; exit 1
fi

THRESHOLD_MS="${COLD_START_THRESHOLD_MS:-5000}"
PATH_="${COLD_START_PATH:-/health}"
URL="${BACKEND_URL%/}$PATH_"

echo "Target:    $URL"
echo "Threshold: ${THRESHOLD_MS}ms"

# curl -w devuelve segundos con decimales — convertir a ms enteros
TIMING=$(curl -s -o /dev/null -w "%{http_code} %{time_starttransfer}" "$URL" 2>/dev/null || echo "000 0")
HTTP_CODE=$(echo "$TIMING" | awk '{print $1}')
TTFB_S=$(echo "$TIMING" | awk '{print $2}')
TTFB_MS=$(awk "BEGIN { printf \"%.0f\", $TTFB_S * 1000 }")

if [[ "$HTTP_CODE" != "200" ]]; then
  fail "HTTP $HTTP_CODE — endpoint no respondió OK"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "HTTP 200"

echo -e "${YELLOW}TTFB:${NC} ${TTFB_MS}ms"

if [[ "$TTFB_MS" -le "$THRESHOLD_MS" ]]; then
  ok "TTFB ${TTFB_MS}ms ≤ umbral ${THRESHOLD_MS}ms"
else
  fail "TTFB ${TTFB_MS}ms > umbral ${THRESHOLD_MS}ms — implementar min-instances=1 o keepalive"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
