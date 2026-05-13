#!/bin/bash
# scripts/cleanup-demo.sh
# Limpia todos los recursos creados por un demo run con un prefix dado.
#
# Borra:
#   · Supabase: tabla {prefix}knowledge_base + función {prefix}match_knowledge
#   · GCP Cloud Run: services con nombre mnemos-{backend,frontend,searxng}-{prefix-clean}
#   · GCP Secret Manager: secrets matching mnemos-{prefix-clean}-*
#
# Idempotente — re-ejecutable sin error si algo ya no existe.
#
# Requiere en entorno (o en .env):
#   SUPABASE_ACCESS_TOKEN  - para Supabase Management API
#   SUPABASE_PROJECT_REF   - subdominio del proyecto
#   GCP_PROJECT_ID         - proyecto destino en GCP
#   gcloud CLI autenticado (gcloud auth application-default login)
#
# Uso:
#   ./scripts/cleanup-demo.sh demo_a3f9b2c1_
#   ./scripts/cleanup-demo.sh demo_a3f9b2c1_ --dry-run   # solo lista
#   ./scripts/cleanup-demo.sh demo_a3f9b2c1_ --supabase-only

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

PREFIX="${1:-}"
DRY_RUN=0; SUPABASE_ONLY=0; GCP_ONLY=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --supabase-only) SUPABASE_ONLY=1 ;;
    --gcp-only) GCP_ONLY=1 ;;
    *) fail "Flag desconocido: $arg"; exit 2 ;;
  esac
done

if [[ -z "$PREFIX" ]]; then
  echo "Usage: $0 <prefix> [--dry-run|--supabase-only|--gcp-only]" >&2
  echo "Ejemplo: $0 demo_a3f9b2c1_" >&2
  exit 1
fi

if ! [[ "$PREFIX" =~ ^[a-z0-9_]+_$ ]]; then
  fail "Prefix inválido: '$PREFIX' (debe ser [a-z0-9_]+ y terminar en _)"
  exit 2
fi

# Strip trailing underscore para nombres GCP (Cloud Run no acepta _)
GCP_PREFIX="${PREFIX%_}"
GCP_PREFIX="${GCP_PREFIX//_/-}"  # snake → kebab para nombres de service

# Load .env
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" || -z "${SUPABASE_PROJECT_REF:-}" || -z "${GCP_PROJECT_ID:-}" ]]; then
  if [[ -f "$ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
  fi
fi

[[ $DRY_RUN -eq 1 ]] && warn "DRY RUN — solo lista, no borra"

# ─── Supabase ──────────────────────────────────────────────────────────────
cleanup_supabase() {
  local token="${SUPABASE_ACCESS_TOKEN:-}"
  local ref="${SUPABASE_PROJECT_REF:-}"

  if [[ -z "$token" || -z "$ref" ]]; then
    warn "Skip Supabase — falta SUPABASE_ACCESS_TOKEN o SUPABASE_PROJECT_REF"
    return
  fi

  local sql
  sql="DROP FUNCTION IF EXISTS public.${PREFIX}match_knowledge(extensions.vector, float, int, text);
DROP TABLE IF EXISTS public.${PREFIX}knowledge_base CASCADE;"

  echo ""
  echo "▸ Supabase ($ref):"
  echo "  · DROP FUNCTION public.${PREFIX}match_knowledge"
  echo "  · DROP TABLE    public.${PREFIX}knowledge_base"

  if [[ $DRY_RUN -eq 1 ]]; then return; fi

  local body resp http
  body=$(jq -nR --arg q "$sql" '{query: $q}' <<<"")
  resp=$(curl -sS -w "\n%{http_code}" -X POST \
    "https://api.supabase.com/v1/projects/${ref}/database/query" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$body")
  http=$(echo "$resp" | tail -n1)

  if [[ "$http" -ge 200 && "$http" -lt 300 ]]; then
    ok "Supabase limpiado"
  else
    fail "Supabase Management API HTTP $http"
    echo "$resp" | sed '$d' >&2
  fi
}

# ─── GCP ───────────────────────────────────────────────────────────────────
cleanup_gcp() {
  local project="${GCP_PROJECT_ID:-}"
  if [[ -z "$project" ]]; then
    warn "Skip GCP — falta GCP_PROJECT_ID"
    return
  fi
  if ! command -v gcloud >/dev/null 2>&1; then
    warn "Skip GCP — gcloud CLI no instalado"
    return
  fi

  echo ""
  echo "▸ GCP project '$project':"

  # Cloud Run services
  for role in backend frontend searxng; do
    local svc="mnemos-${role}-${GCP_PREFIX}"
    echo "  · Cloud Run service: $svc"
    if [[ $DRY_RUN -eq 1 ]]; then continue; fi
    gcloud run services delete "$svc" \
      --project="$project" --region="us-central1" \
      --quiet 2>/dev/null \
      && ok "  borrado: $svc" \
      || warn "  no existe o ya borrado: $svc"
  done

  # Secret Manager — secrets que matchean el prefijo
  echo "  · Secret Manager: buscando secrets mnemos-${GCP_PREFIX}-*"
  if [[ $DRY_RUN -eq 1 ]]; then
    gcloud secrets list --project="$project" \
      --filter="name:mnemos-${GCP_PREFIX}-" --format="value(name)" 2>/dev/null \
      | sed 's/^/      → /'
    return
  fi
  local secrets
  secrets=$(gcloud secrets list --project="$project" \
    --filter="name:mnemos-${GCP_PREFIX}-" --format="value(name)" 2>/dev/null)
  if [[ -z "$secrets" ]]; then
    warn "  ningún secret matchea"
  else
    while IFS= read -r s; do
      gcloud secrets delete "$s" --project="$project" --quiet 2>/dev/null \
        && ok "  borrado: $s" \
        || warn "  falló: $s"
    done <<< "$secrets"
  fi
}

# ─── Run ───────────────────────────────────────────────────────────────────
[[ $GCP_ONLY -eq 0 ]]      && cleanup_supabase
[[ $SUPABASE_ONLY -eq 0 ]] && cleanup_gcp

echo ""
ok "Cleanup terminado para prefix '$PREFIX'"
