#!/bin/bash
# scripts/render-demo-migration.sh
# Renderiza el template SQL con un prefix concreto. Imprime el SQL a stdout.
# Determinístico, no requiere credenciales. Para aplicar el resultado, ver
# scripts/apply-demo-migration.sh (curl + Management API) o pasalo al
# Supabase MCP vía Copilot.
#
# Uso:
#   ./scripts/render-demo-migration.sh demo_a3f9b2c1_
#   ./scripts/render-demo-migration.sh demo_test_xyz_ > /tmp/demo.sql

set -uo pipefail

PREFIX="${1:-}"
if [[ -z "$PREFIX" ]]; then
  echo "Usage: $0 <prefix>" >&2
  echo "Example: $0 demo_a3f9b2c1_" >&2
  exit 1
fi

# Sanity: el prefix debe terminar en _ y solo contener [a-z0-9_]
if ! [[ "$PREFIX" =~ ^[a-z0-9_]+_$ ]]; then
  echo "✗ Prefix inválido: '$PREFIX'" >&2
  echo "  Debe match [a-z0-9_]+_ (lowercase alphanumeric + underscore, termina en _)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/supabase/templates/demo-migration.sql.template"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "✗ Template no encontrado: $TEMPLATE" >&2
  exit 1
fi

# Substituir {{PREFIX}} preservando todo lo demás
sed "s/{{PREFIX}}/${PREFIX}/g" "$TEMPLATE"
