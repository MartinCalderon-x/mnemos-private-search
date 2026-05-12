#!/bin/bash
# scripts/setup-gcp-wif.sh
# Configura Workload Identity Federation entre el proyecto GCP activo
# y el repo GitHub. Idempotente — re-ejecutable sin riesgo.
#
# Crea (o reusa si ya existen):
#   · Workload Identity Pool "mnemos-pool"
#   · OIDC Provider "github-provider" condicionado al repo
#   · Service Account "mnemos-deploy" con roles de deploy
#   · Binding WIF → SA (vía principalSet del repo)
#
# Al final imprime las 3 vars a guardar como GitHub Secret/Variable:
#   GCP_PROJECT_ID, GCP_WIF_PROVIDER, GCP_WIF_SERVICE_ACCOUNT
#
# Y opcionalmente las agrega a .env (--write-env).
#
# Uso:
#   ./scripts/setup-gcp-wif.sh                  # solo crea y muestra
#   ./scripts/setup-gcp-wif.sh --write-env      # crea + persiste en .env
#   GITHUB_REPO=user/repo ./scripts/setup-gcp-wif.sh   # otro repo

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

WRITE_ENV=0
[[ "${1:-}" == "--write-env" ]] && WRITE_ENV=1

# ─── Config ────────────────────────────────────────────────────────────────
# Soporta múltiples repos separados por coma para que el mismo SA pueda ser
# impersonado desde N repos hermanos (típico: reference privado + blueprint público)
GITHUB_REPOS="${GITHUB_REPOS:-${GITHUB_REPO:-MartinCalderon-x/mnemos}}"
POOL_ID="mnemos-pool"
PROVIDER_ID="github-provider"
SA_NAME="mnemos-deploy"

# Split comma-separated repos en array
IFS=',' read -r -a REPOS_ARRAY <<< "$GITHUB_REPOS"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "✗ No hay GCP project activo. Corré: gcloud config set project <id>" >&2
  exit 1
fi
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo "Project:      $PROJECT_ID (number: $PROJECT_NUMBER)"
echo "GitHub repos: ${REPOS_ARRAY[*]}"
echo "Pool:         $POOL_ID"
echo "Provider:     $PROVIDER_ID"
echo "SA:           $SA_EMAIL"
echo ""

# ─── 1. Enable required APIs ───────────────────────────────────────────────
echo "▸ Enabling APIs (idempotent)..."
gcloud services enable \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID" --quiet
ok "APIs habilitadas"

# ─── 2. Workload Identity Pool ─────────────────────────────────────────────
if gcloud iam workload-identity-pools describe "$POOL_ID" \
     --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "pool '$POOL_ID' ya existe — reusando"
else
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location=global \
    --display-name="Mnemos GitHub Actions" \
    --description="WIF pool for mnemos demo CI/CD" \
    --quiet
  ok "pool '$POOL_ID' creado"
fi

# ─── 3. OIDC Provider ──────────────────────────────────────────────────────
# Build CEL condition: assertion.repository in ['repo1', 'repo2', ...]
REPOS_CEL_LIST=$(printf "'%s'," "${REPOS_ARRAY[@]}")
REPOS_CEL_LIST="[${REPOS_CEL_LIST%,}]"
CONDITION="assertion.repository in $REPOS_CEL_LIST"

if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
     --workload-identity-pool="$POOL_ID" \
     --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "provider '$PROVIDER_ID' ya existe — actualizando condition"
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location=global --project="$PROJECT_ID" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor,attribute.ref=assertion.ref" \
    --attribute-condition="$CONDITION" \
    --quiet
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location=global --project="$PROJECT_ID" \
    --display-name="GitHub Actions" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor,attribute.ref=assertion.ref" \
    --attribute-condition="$CONDITION" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --quiet
fi
ok "provider '$PROVIDER_ID' restringido a repos: ${REPOS_ARRAY[*]}"

# ─── 4. Service Account ────────────────────────────────────────────────────
if gcloud iam service-accounts describe "$SA_EMAIL" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  warn "service account '$SA_NAME' ya existe — reusando"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="Mnemos Deploy" \
    --description="Used by GitHub Actions via WIF to deploy mnemos to Cloud Run" \
    --quiet
  ok "service account '$SA_NAME' creada"
fi

# ─── 5. Project roles ──────────────────────────────────────────────────────
echo "▸ Granting deploy roles to SA..."
ROLES=(
  roles/run.admin
  roles/iam.serviceAccountUser
  roles/secretmanager.admin
  roles/artifactregistry.writer
  roles/storage.admin
)
for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null
done
ok "roles asignados: ${ROLES[*]}"

# ─── 6. WIF → SA binding (uno por repo) ─────────────────────────────────────
for repo in "${REPOS_ARRAY[@]}"; do
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${repo}" \
    --quiet >/dev/null
done
ok "WIF principalSet bound a SA para: ${REPOS_ARRAY[*]}"

# ─── 7. Output ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " WIF setup completo. Valores para GitHub Secrets / Variables:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "GCP_PROJECT_ID=${PROJECT_ID}"
echo "GCP_WIF_PROVIDER=${WIF_PROVIDER}"
echo "GCP_WIF_SERVICE_ACCOUNT=${SA_EMAIL}"
echo ""

if [[ $WRITE_ENV -eq 1 ]]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  ENV_FILE="$ROOT/.env"
  for key in GCP_PROJECT_ID GCP_WIF_PROVIDER GCP_WIF_SERVICE_ACCOUNT; do
    grep -v "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  done
  {
    echo "GCP_PROJECT_ID=${PROJECT_ID}"
    echo "GCP_WIF_PROVIDER=${WIF_PROVIDER}"
    echo "GCP_WIF_SERVICE_ACCOUNT=${SA_EMAIL}"
  } >> "$ENV_FILE"
  ok "Persistidos en ${ENV_FILE}"
fi

echo ""
echo "Siguiente paso: ./scripts/setup-github-secrets.sh"
echo "para subir GCP_WIF_PROVIDER, GCP_WIF_SERVICE_ACCOUNT (secrets)"
echo "y GCP_PROJECT_ID (variable) al repo."
