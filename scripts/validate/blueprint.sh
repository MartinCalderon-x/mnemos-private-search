#!/bin/bash
# scripts/validate/blueprint.sh
# Closes issue #12 (scripts/generate-blueprint.sh).
# Corre el script en un directorio temporal y valida que el repo resultante
# tiene la estructura mínima esperada y archivos JSON parseables.

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$ROOT/scripts/generate-blueprint.sh"

echo "=== Validate: generate-blueprint.sh ==="

if [[ ! -x "$GEN" ]]; then
  fail "$GEN no existe o no es ejecutable — falta implementar issue #12"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "script existe y es ejecutable"

TMP=$(mktemp -d -t mnemos-blueprint-XXXXXX)
trap 'rm -rf "$TMP"' EXIT
echo "Output dir: $TMP"

# El script debe aceptar el directorio destino como argumento
if ! "$GEN" "$TMP/blueprint" >/dev/null 2>&1; then
  fail "generate-blueprint.sh falló al ejecutarse"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "script corrió sin error"

OUT="$TMP/blueprint"

REQUIRED_DIRS=(backend frontend docs scripts/smoke .vscode)
for D in "${REQUIRED_DIRS[@]}"; do
  if [[ -d "$OUT/$D" ]]; then
    ok "dir presente: $D"
  else
    fail "dir faltante: $D"
  fi
done

REQUIRED_FILES=(
  README.md
  docker-compose.yml
  .env.example
  backend/package.json
  frontend/package.json
  .vscode/mcp.json
)
for F in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$OUT/$F" ]]; then
    ok "archivo presente: $F"
  else
    fail "archivo faltante: $F"
  fi
done

# Validar JSONs parseables
if command -v jq >/dev/null 2>&1; then
  for J in backend/package.json frontend/package.json .vscode/mcp.json; do
    if [[ -f "$OUT/$J" ]] && jq empty "$OUT/$J" >/dev/null 2>&1; then
      ok "JSON válido: $J"
    elif [[ -f "$OUT/$J" ]]; then
      fail "JSON inválido: $J"
    fi
  done
fi

# El blueprint NO debe llevar código de implementación, solo specs/issues
if [[ -d "$OUT/backend/src" ]] && [[ -n "$(ls -A "$OUT/backend/src" 2>/dev/null)" ]]; then
  fail "blueprint contiene backend/src/ con código (debería estar vacío — Copilot lo regenera)"
else
  ok "blueprint no incluye código de implementación"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
