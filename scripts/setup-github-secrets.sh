#!/bin/bash
# scripts/setup-github-secrets.sh
# Sube los secrets del .env local al repo de GitHub vía gh CLI.
# Idempotente: re-ejecutable sin riesgo (gh secret set sobreescribe).
#
# Vars que se mandan como SECRET (encriptados):
#   SUPABASE_URL, SUPABASE_SECRET_KEY, SUPABASE_ACCESS_TOKEN,
#   SUPABASE_PROJECT_REF, OPENROUTER_API_KEY, SEARXNG_SECRET,
#   VITE_SUPABASE_URL, VITE_SUPABASE_PUBLISHABLE_KEY,
#   GCP_SA_KEY (opcional, JSON completo del service account)
#
# Vars que se mandan como VARIABLE (no encriptadas):
#   GCP_PROJECT_ID
#
# Para WIF (preferido en lugar de GCP_SA_KEY):
#   GCP_WIF_PROVIDER, GCP_WIF_SERVICE_ACCOUNT
#
# Si el repo es público, los Secrets siguen siendo seguros (encryption-at-rest,
# redactados en logs, no se heredan a forks). Las Variables son visibles.
#
# Uso:
#   ./scripts/setup-github-secrets.sh                # mismo repo (origin)
#   ./scripts/setup-github-secrets.sh --dry-run      # solo lista qué se subiría
#   REPO=user/repo ./scripts/setup-github-secrets.sh # otro repo

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
else
  fail "No se encontró .env en $ROOT"; exit 1
fi

# Detectar repo destino
if [[ -n "${REPO:-}" ]]; then
  REPO_ARG="--repo $REPO"
else
  REPO_ARG=""
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || { fail "No estás en un repo git con remote GitHub. Usa REPO=user/repo"; exit 2; }
fi

echo "Repo destino: $REPO"
[[ $DRY_RUN -eq 1 ]] && warn "DRY RUN — solo lista, no sube"
echo ""

# Lista de SECRETS (encriptados)
SECRETS=(
  SUPABASE_URL
  SUPABASE_SECRET_KEY
  SUPABASE_ACCESS_TOKEN
  SUPABASE_PROJECT_REF
  OPENROUTER_API_KEY
  SEARXNG_SECRET
  VITE_SUPABASE_URL
  VITE_SUPABASE_PUBLISHABLE_KEY
  GCP_SA_KEY
  GCP_WIF_PROVIDER
  GCP_WIF_SERVICE_ACCOUNT
)

# Lista de VARIABLES (visibles, no encriptadas)
VARIABLES=(
  GCP_PROJECT_ID
)

MISSING=()
PUSHED=0

for name in "${SECRETS[@]}"; do
  value="${!name:-}"
  if [[ -z "$value" ]]; then
    MISSING+=("$name (secret)")
    continue
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    ok "would set secret $name (${#value} chars)"
  else
    # IMPORTANT: usar --body "$value" directo, NO pipe a --body -
    # gh secret set con stdin trunca el valor a 1 char en algunos casos.
    # shellcheck disable=SC2086
    gh secret set "$name" $REPO_ARG --body "$value" >/dev/null 2>&1 \
      && { ok "secret $name (${#value} chars)"; ((PUSHED++)); } \
      || fail "secret $name"
  fi
done

for name in "${VARIABLES[@]}"; do
  value="${!name:-}"
  if [[ -z "$value" ]]; then
    MISSING+=("$name (variable)")
    continue
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    ok "would set variable $name=$value"
  else
    # shellcheck disable=SC2086
    gh variable set "$name" $REPO_ARG --body "$value" >/dev/null 2>&1 \
      && { ok "variable $name"; ((PUSHED++)); } \
      || fail "variable $name"
  fi
done

echo ""
[[ $DRY_RUN -eq 0 ]] && ok "$PUSHED secret(s)/variable(s) subido(s) a $REPO"

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  warn "Vars NO presentes en .env (se omitieron):"
  for m in "${MISSING[@]}"; do echo "    · $m"; done
  echo ""
  echo "Para incluirlas:"
  echo "  1. Agregalas a .env"
  echo "  2. Re-corré este script"
  echo ""
  echo "Cómo conseguir las que faltan:"
  echo "  SUPABASE_ACCESS_TOKEN  → https://supabase.com/dashboard/account/tokens"
  echo "  SUPABASE_PROJECT_REF   → <your-supabase-project-ref>  (subdominio de SUPABASE_URL)"
  echo "  GCP_PROJECT_ID         → gcloud config get-value project"
  echo "  GCP_SA_KEY             → gcloud iam service-accounts keys create ..."
  echo "  GCP_WIF_PROVIDER       → setup WIF (preferido vs SA_KEY)"
fi
