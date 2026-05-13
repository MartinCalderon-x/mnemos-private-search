#!/bin/bash
# scripts/setup-copilot-mcp-secrets.sh
# Sube los secrets necesarios para el Copilot Coding Agent.
# El agente solo ve secrets prefijados COPILOT_MCP_* (regla de GitHub).
# Por eso re-uploadeamos los valores existentes con el prefijo correcto.
#
# Idempotente. Lee desde .env. Requiere gh CLI autenticado.

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; source "$ROOT/.env"; set +a; }

# REPO env var permite targetear otros repos (ej blueprint público).
# Si no se setea, usa el repo del cwd.
if [[ -z "${REPO:-}" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi
echo "Target repo: $REPO"
echo ""

# Mapeo: source en .env  →  nombre que el Coding Agent verá
declare -a MAPPING=(
  "SUPABASE_ACCESS_TOKEN:COPILOT_MCP_SUPABASE_ACCESS_TOKEN"
  "SUPABASE_PROJECT_REF:COPILOT_MCP_SUPABASE_PROJECT_REF"
)

for pair in "${MAPPING[@]}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  val="${!src:-}"
  if [[ -z "$val" ]]; then
    warn "$src no está en .env — skipping $dst"
    continue
  fi
  # Usar --body directo (stdin truncaba a 1 char, ver setup-github-secrets.sh)
  gh secret set "$dst" --repo "$REPO" --body "$val" >/dev/null \
    && ok "$dst (${#val} chars)" \
    || warn "fallo en $dst"
done

echo ""
echo "Verificación:"
gh secret list --repo "$REPO" | grep "^COPILOT_MCP_" || warn "ningún COPILOT_MCP_* encontrado"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " Próximo paso MANUAL (no automatizable via API):"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. Abrir: https://github.com/${REPO}/settings/copilot/coding_agent"
echo "2. En 'MCP configuration', pegar el JSON de:"
echo "     .github/copilot/mcp-config.json"
echo "3. Save."
echo ""
echo "Después: asignar un issue a @copilot para probar."
