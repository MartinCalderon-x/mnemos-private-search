#!/bin/bash
# scripts/apply-demo-migration.sh
# Aplica una migración de demo con prefix usando la Supabase Management API.
#
# Requiere en environment (o en .env):
#   SUPABASE_ACCESS_TOKEN  - personal access token (sbp_...)
#   SUPABASE_PROJECT_REF   - subdominio del proyecto Supabase
#
# Uso:
#   ./scripts/apply-demo-migration.sh demo_a3f9b2c1_
#
# Idempotente: el template usa CREATE TABLE/INDEX/FUNCTION IF NOT EXISTS / OR REPLACE,
# así que re-aplicarlo con el mismo prefix no falla ni destruye datos.

set -uo pipefail

PREFIX="${1:-}"
if [[ -z "$PREFIX" ]]; then
  echo "Usage: $0 <prefix>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env si existe y las vars no están en ambiente
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" || -z "${SUPABASE_PROJECT_REF:-}" ]]; then
  if [[ -f "$ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
  fi
fi

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
REF="${SUPABASE_PROJECT_REF:-}"

if [[ -z "$TOKEN" ]]; then
  echo "✗ Falta SUPABASE_ACCESS_TOKEN en entorno o .env" >&2
  echo "  Generalo en: https://supabase.com/dashboard/account/tokens" >&2
  exit 2
fi
if [[ -z "$REF" ]]; then
  echo "✗ Falta SUPABASE_PROJECT_REF en entorno o .env" >&2
  echo "  Es el subdominio del proyecto (ej: <your-supabase-project-ref>)" >&2
  exit 2
fi

# Render SQL
SQL=$("$ROOT/scripts/render-demo-migration.sh" "$PREFIX")
if [[ -z "$SQL" ]]; then
  echo "✗ Render falló — SQL vacío" >&2
  exit 3
fi

echo "▸ Aplicando migración con prefix '$PREFIX' al proyecto '$REF'..."

# Construir body JSON con jq para escapar el SQL correctamente
BODY=$(jq -nR --arg q "$SQL" '{query: $q}' <<<"")

RESPONSE=$(curl -sS -w "\n%{http_code}" -X POST \
  "https://api.supabase.com/v1/projects/${REF}/database/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY_RESP=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "✗ Management API respondió HTTP $HTTP_CODE:" >&2
  echo "$BODY_RESP" >&2
  exit 4
fi

echo "✓ Migración aplicada. Recursos creados:"
echo "  · public.${PREFIX}knowledge_base (tabla)"
echo "  · public.${PREFIX}match_knowledge (función)"
echo "  · ${PREFIX}knowledge_base_embedding_idx (HNSW)"
echo ""
echo "Para usar desde el backend: TABLE_PREFIX=${PREFIX} npm start"
