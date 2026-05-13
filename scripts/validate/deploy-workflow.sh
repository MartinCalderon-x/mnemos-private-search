#!/bin/bash
# scripts/validate/deploy-workflow.sh
# Closes issue #7 (deploy.yml con Workload Identity + 3 services).
# Valida YAML, permisos id-token, provider Workload Identity, y que se
# despliegan los 3 services Cloud Run: backend, frontend, searxng.

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="$ROOT/.github/workflows/deploy.yml"

echo "=== Validate: .github/workflows/deploy.yml ==="
echo "Target: $FILE"

if [[ ! -f "$FILE" ]]; then
  fail "archivo no existe — falta implementar issue #7"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "archivo existe"

# Validar YAML con python (pre-instalado en macOS)
if python3 -c "import yaml; yaml.safe_load(open('$FILE'))" 2>/dev/null; then
  ok "YAML válido"
else
  fail "YAML inválido"
  python3 -c "import yaml; yaml.safe_load(open('$FILE'))" 2>&1 | tail -3
  echo "RESULTADO: FAIL"; exit 1
fi

check_grep() {
  local PATTERN="$1" DESC="$2"
  if grep -qE "$PATTERN" "$FILE"; then
    ok "$DESC"
  else
    fail "$DESC (pattern: $PATTERN)"
  fi
}

# Permission requerido por Workload Identity Federation
check_grep 'id-token:[[:space:]]+write' 'permissions: id-token: write declarado'

# Action de auth de GCP
check_grep 'google-github-actions/auth' 'usa google-github-actions/auth'

# WIF provider
check_grep 'workload_identity_provider' 'workload_identity_provider configurado'

# Service account
check_grep 'service_account' 'service_account configurado'

# Los 3 services Cloud Run del demo
for SVC in backend frontend searxng; do
  if grep -qiE "(mnemos-)?$SVC" "$FILE"; then
    ok "service '$SVC' referenciado"
  else
    fail "service '$SVC' no aparece en el workflow"
  fi
done

# Cloud Run deploy action
check_grep 'google-github-actions/deploy-cloudrun' 'usa deploy-cloudrun action'

# No debe quedar referencias al template viejo (arx-codex)
if grep -qi 'arx-codex' "$FILE"; then
  fail 'aún hay referencias a arx-codex (template heredado)'
else
  ok 'sin referencias heredadas (arx-codex limpio)'
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
