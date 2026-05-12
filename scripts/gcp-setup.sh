#!/bin/bash
set -euo pipefail

# mnemos — GCP Setup Script
# Usage: ./scripts/gcp-setup.sh <PROJECT_ID> [GITHUB_REPO]
# Example: ./scripts/gcp-setup.sh my-project MartinCalderon-x/mnemos

PROJECT_ID="${1:-}"
GITHUB_REPO="${2:-MartinCalderon-x/mnemos}"
REGION="us-central1"
SA_NAME="mnemos-deploy"
AR_REPO="mnemos"
WIF_POOL="github-pool"
WIF_PROVIDER="github-provider"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: ./scripts/gcp-setup.sh <PROJECT_ID> [GITHUB_REPO]"
  exit 1
fi

echo "🚀 mnemos GCP Setup"
echo "   Project: $PROJECT_ID"
echo "   GitHub:  $GITHUB_REPO"
echo "   Region:  $REGION"
echo ""

# 1. Set project
gcloud config set project "$PROJECT_ID"

# 2. Enable required APIs
echo "📡 Habilitando APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="$PROJECT_ID"

# 3. Create Artifact Registry repo
echo "📦 Creando Artifact Registry..."
gcloud artifacts repositories create "$AR_REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "   (ya existe)"

# 4. Create service account
echo "👤 Creando service account..."
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="mnemos deploy service account" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "   (ya existe)"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 5. Grant minimum permissions
echo "🔐 Asignando permisos mínimos..."
for ROLE in \
  "roles/run.developer" \
  "roles/artifactregistry.writer" \
  "roles/secretmanager.secretAccessor" \
  "roles/iam.serviceAccountUser"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --quiet 2>/dev/null
done

# 6. Workload Identity Federation (no service account keys)
echo "🔑 Configurando Workload Identity Federation..."
gcloud iam workload-identity-pools create "$WIF_POOL" \
  --location="global" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "   (pool ya existe)"

gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "   (provider ya existe)"

POOL_NAME=$(gcloud iam workload-identity-pools describe "$WIF_POOL" \
  --location="global" \
  --project="$PROJECT_ID" \
  --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" \
  --project="$PROJECT_ID" \
  --quiet

WIF_PROVIDER_FULL="${POOL_NAME/workloadIdentityPools/workloadIdentityPools}/${WIF_POOL}/providers/${WIF_PROVIDER}"
WIF_PROVIDER_RESOURCE="projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

# 7. Create secrets in Secret Manager from .env
echo "🔒 Creando secrets en Secret Manager..."
if [[ -f ".env" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" || -z "$value" ]] && continue
    [[ "$key" =~ ^VITE_ ]] && continue  # skip frontend vars
    secret_name=$(echo "$key" | tr '[:upper:]_' '[:lower:]-')
    echo "   Creating secret: $secret_name"
    echo -n "$value" | gcloud secrets create "$secret_name" \
      --data-file=- \
      --project="$PROJECT_ID" \
      --quiet 2>/dev/null || \
    echo -n "$value" | gcloud secrets versions add "$secret_name" \
      --data-file=- \
      --project="$PROJECT_ID" \
      --quiet
  done < ".env"
else
  echo "   ⚠️  No se encontró .env — crear secrets manualmente"
fi

# 8. Print GitHub Secrets to add
echo ""
echo "✅ Setup completado. Agregar estos GitHub Secrets:"
echo ""
echo "   GCP_PROJECT_ID=$PROJECT_ID"
echo "   GCP_SERVICE_ACCOUNT=$SA_EMAIL"
echo "   GCP_WORKLOAD_IDENTITY_PROVIDER=$WIF_PROVIDER_RESOURCE"
echo "   GCP_REGION=$REGION"
echo ""
echo "   Ir a: GitHub → Settings → Secrets and variables → Actions"
echo ""
echo "🚀 Hacer push a main para disparar el primer deploy."
