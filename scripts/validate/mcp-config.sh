#!/bin/bash
# scripts/validate/mcp-config.sh
# Closes issue #6 (.vscode/mcp.json con 3 MCPs).
# Valida que el archivo existe, es JSON válido, y declara los 3 servers
# requeridos por el demo: supabase, gcp, mnemos.

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="$ROOT/.vscode/mcp.json"

echo "=== Validate: .vscode/mcp.json ==="
echo "Target: $FILE"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq no está instalado"
  echo "RESULTADO: FAIL"; exit 1
fi

if [[ ! -f "$FILE" ]]; then
  fail "archivo no existe — falta implementar issue #6"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "archivo existe"

if ! jq empty "$FILE" >/dev/null 2>&1; then
  fail "JSON inválido"
  echo "RESULTADO: FAIL"; exit 1
fi
ok "JSON válido"

# Schema VSCode MCP usa "servers" (no "mcpServers" como Claude Desktop)
if ! jq -e '.servers' "$FILE" >/dev/null 2>&1; then
  fail 'falta clave "servers" (schema VSCode)'
fi

REQUIRED=(supabase gcp mnemos)
for SERVER in "${REQUIRED[@]}"; do
  if jq -e --arg s "$SERVER" '.servers[$s]' "$FILE" >/dev/null 2>&1; then
    ok "server '$SERVER' declarado"
  else
    # Aceptar variantes de nombre comunes
    if jq -e --arg s "$SERVER" '.servers | keys[] | select(contains($s))' "$FILE" >/dev/null 2>&1; then
      MATCH=$(jq -r --arg s "$SERVER" '.servers | keys[] | select(contains($s))' "$FILE" | head -1)
      ok "server '$SERVER' declarado (como '$MATCH')"
    else
      fail "server '$SERVER' no encontrado en .servers"
    fi
  fi
done

# Cada server debe tener command+args o url (transport stdio o http)
INVALID=$(jq -r '.servers | to_entries[] | select((.value.command == null) and (.value.url == null)) | .key' "$FILE" 2>/dev/null)
if [[ -n "$INVALID" ]]; then
  while IFS= read -r S; do
    fail "server '$S' no tiene .command ni .url (transport indefinido)"
  done <<< "$INVALID"
else
  ok "todos los servers tienen transport definido"
fi

if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
