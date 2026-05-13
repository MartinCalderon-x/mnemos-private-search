#!/bin/bash
# scripts/generate-blueprint.sh
# Genera el blueprint público OSS de mnemos en un directorio destino.
#
# Incluye: specs (docs/adr, flows, plans), smoke tests, validators, scripts
# demo (render/apply/cleanup migrations, setup-wif, setup-secrets), templates
# de Dockerfiles, configs (docker-compose, supabase migrations).
#
# Excluye: código de implementación (backend/src, frontend/src), dist/,
# node_modules/, .env, .git, docs locales (linkedin, presentation, sessions),
# materiales privados (.github/copilot, .claude, backups).
#
# Decisión arquitectónica: ADR-013 — el reference (este repo) es privado;
# el blueprint público es un snapshot deliberado, sincronizado manualmente.
#
# Lo que SÍ se incluye de .github/: workflows (deploy.yml), copilot-instructions.md,
# copilot/mcp-config.json. Son configuración pública por diseño. Si en el futuro
# se agregan secrets reales dentro de .github/, hay que excluirlos puntualmente.
#
# Uso:
#   ./scripts/generate-blueprint.sh ../mnemos-private-search
#   ./scripts/generate-blueprint.sh /tmp/test --force
#
# Flags:
#   --force        Permite escribir en directorios no vacíos (con rsync --delete)

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

DEST=""
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) fail "Flag desconocido: $arg"; exit 2 ;;
    *) DEST="$arg" ;;
  esac
done

if [[ -z "$DEST" ]]; then
  echo "Usage: $0 <destination_dir> [--force]" >&2
  echo "Example: $0 ../mnemos-private-search" >&2
  exit 1
fi

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SHA=$(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo "no-git")

# Resolve destino a absoluto (mkdir lo crea si no existe)
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

if [[ "$DEST" == "$SRC" ]]; then
  fail "El destino no puede ser igual al repo source"
  exit 2
fi

# Si el destino tiene contenido, exigir --force
if [[ -n "$(ls -A "$DEST" 2>/dev/null)" ]] && [[ $FORCE -eq 0 ]]; then
  fail "$DEST no está vacío. Usá --force para sobreescribir (con rsync --delete)"
  exit 2
fi

echo "▸ Generating blueprint"
echo "  source: $SRC  (sha: $SRC_SHA)"
echo "  dest:   $DEST"
[[ $FORCE -eq 1 ]] && warn "FORCE mode — usando rsync --delete"

# ─── 1. Rsync con excludes ──────────────────────────────────────────────
DELETE_FLAG=""
# --delete-excluded también borra archivos del destino que matchean los excludes
# (sin esto, archivos previamente sincronizados quedan huérfanos al agregar excludes nuevos)
[[ $FORCE -eq 1 ]] && DELETE_FLAG="--delete --delete-excluded"

rsync -a $DELETE_FLAG \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='.env.local' \
  --exclude='.env.*.local' \
  --exclude='node_modules/' \
  --exclude='dist/' \
  --exclude='build/' \
  --exclude='backend/src/' \
  --exclude='frontend/src/' \
  --exclude='backend/Dockerfile' \
  --exclude='frontend/Dockerfile' \
  --exclude='frontend/nginx.conf' \
  --exclude='searxng/Dockerfile' \
  --exclude='/CLAUDE.md' \
  --exclude='docs/linkedin/' \
  --exclude='docs/presentation/' \
  --exclude='docs/sessions/' \
  --exclude='docs/paper/' \
  --exclude='docs/flows/live-demo-script.md' \
  --exclude='.claude/' \
  --exclude='.cache/' \
  --exclude='.DS_Store' \
  --exclude='.temp/' \
  --exclude='supabase/.temp/' \
  --exclude='*.log' \
  --exclude='*.disabled' \
  --exclude='/lib/' \
  "$SRC/" "$DEST/"

# ── Sanitización de valores concretos del reference privado ──────────────
# Reemplaza identifiers reales (<your-gcp-project>, project number, supabase ref,
# email del autor) con placeholders. Aplica a .md, .yml, .json, .sh.
SED_SCRIPT='
s|<your-gcp-project>|<your-gcp-project>|g
s|<your-gcp-project-number>|<your-gcp-project-number>|g
s|<your-supabase-project-ref>|<your-supabase-project-ref>|g
s|<your-google-account>|<your-google-account>|g
s|api\.mnemos\.lat|api.<your-domain>|g
s|www\.mnemos\.lat|www.<your-domain>|g
s|mnemos\.lat|<your-domain>|g
s|mnemos-deploy@<your-gcp-project>\.iam\.gserviceaccount\.com|mnemos-deploy@<your-gcp-project>.iam.gserviceaccount.com|g
'
find "$DEST" \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.sh" \) \
  -type f -print0 2>/dev/null \
  | xargs -0 sed -i.bak "$SED_SCRIPT" 2>/dev/null
find "$DEST" -name "*.bak" -delete 2>/dev/null
ok "valores concretos sanitizados → placeholders"

ok "rsync terminado"

# ─── 2. src/ dirs NO se crean ─────────────────────────────────────────
# El validator scripts/validate/blueprint.sh exige que backend/src y
# frontend/src estén ausentes (sin código y sin .gitkeep). Copilot los
# crea cuando empieza a implementar los issues.
ok "backend/src y frontend/src omitidos (Copilot los crea)"

# ─── 3. Dockerfiles boilerplate (solo headers + referencias a ADRs) ─────
cat > "$DEST/backend/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7
# ─── mnemos backend — TEMPLATE (sin implementación) ──────────────────────
# Copilot debe implementar este Dockerfile siguiendo:
#   · ADR-002: HTTP server local (Hono) — entry dist/index.js
#   · ADR-010: dual entry points HTTP + MCP stdio
#   · docs/flows/agent-decision-flow.md
#
# Restricciones conocidas (no Alpine):
#   · @xenova/transformers usa onnxruntime-node que requiere glibc
#   · @supabase/supabase-js v2 requiere Node 22+ por WebSocket nativo
#   → base recomendada: node:22-slim (Debian)
#
# Estructura esperada:
#   · Stage 1 builder:  npm ci + tsc → dist/
#   · Stage 2 runtime:  npm ci --omit=dev + COPY dist/ + EXPOSE 3000
#   · CMD ["node", "dist/index.js"]
#
# Validador: scripts/smoke/03-http-api.sh debe pasar contra el container.
EOF

cat > "$DEST/frontend/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7
# ─── mnemos frontend — TEMPLATE (sin implementación) ─────────────────────
# Copilot debe implementar este Dockerfile siguiendo:
#   · React 18 + Vite + Tailwind
#   · Variables VITE_* se inlinea al bundle al hacer vite build → ARG/ENV
#   · Servido como static con Nginx (necesita SPA fallback + envsubst sobre PORT)
#
# Build args esperados:
#   · VITE_SUPABASE_URL
#   · VITE_SUPABASE_PUBLISHABLE_KEY
#   · VITE_BACKEND_URL
#
# Estructura esperada:
#   · Stage 1 builder:  npm ci + npm run build → dist/
#   · Stage 2 nginx:    COPY dist/ + nginx.conf con SPA try_files
#   · CMD ["nginx", "-g", "daemon off;"]
EOF

cat > "$DEST/frontend/nginx.conf" <<'EOF'
# TEMPLATE — Copilot debe implementar siguiendo:
#   · server.listen $PORT (Cloud Run inyecta PORT)
#   · root /usr/share/nginx/html con index.html
#   · SPA fallback: try_files $uri $uri/ /index.html
#   · gzip on para JS/CSS/SVG
#   · cache largo (1y immutable) en assets con hash
#   · no-cache en index.html
EOF

cat > "$DEST/searxng/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7
# ─── mnemos SearxNG — TEMPLATE (sin implementación) ──────────────────────
# Copilot debe implementar este Dockerfile siguiendo:
#   · ADR-006: settings.yml baked en la imagen (Cloud Run no monta volúmenes)
#   · Base: searxng/searxng:latest
#   · COPY settings.yml → /etc/searxng/settings.yml
#   · EXPOSE 8080
EOF

ok "Dockerfiles boilerplate creados (sin implementación — Copilot los completa)"

# ─── 4. BLUEPRINT.md (instrucciones de setup) ───────────────────────────
cat > "$DEST/BLUEPRINT.md" <<EOF
# Mnemos Blueprint — Setup para reconstruir con Copilot

> Este repo es un **blueprint clonable**. No contiene el código de implementación de mnemos
> (\`backend/src/\`, \`frontend/src/\` están vacíos a propósito). Tiene **specs auditables** y
> **smokes ejecutables** para que GitHub Copilot Agent Mode pueda reconstruir el sistema
> entero desde cero.
>
> Reference repo (privado) sincronizado al commit \`$SRC_SHA\`.

---

## Setup en 5 pasos

### 1. Clonar y configurar \`.env\`

\`\`\`bash
git clone <este-repo> mnemos
cd mnemos
cp .env.example .env       # llená con tus credenciales
\`\`\`

Necesitás cuentas en:
- [Supabase](https://supabase.com) — proyecto + personal access token
- [OpenRouter](https://openrouter.ai) — API key para el LLM
- [Google Cloud](https://console.cloud.google.com) — project ID con billing habilitado

### 2. Levantar SearxNG local

\`\`\`bash
docker compose up -d searxng
curl -s "http://localhost:8080/search?q=hello&format=json" | jq '.results | length'
# → ~10+ resultados
\`\`\`

### 3. Aplicar migraciones Supabase

\`\`\`bash
# Opción A: usás Supabase CLI directo
supabase link --project-ref \$SUPABASE_PROJECT_REF
supabase db push

# Opción B: usás el script demo (con prefix si querés aislar tu run)
./scripts/apply-demo-migration.sh demo_xxxxxxxx_   # crea tabla prefijada
\`\`\`

### 4. Configurar GitHub Copilot Agent Mode

Abrí el repo en VS Code. Copilot detecta automáticamente \`.vscode/mcp.json\` con los 3 MCPs:

- **supabase** — operaciones DB (migraciones, queries, RLS)
- **gcp** — Cloud Run, Secret Manager, Artifact Registry
- **mnemos** — (aún no existe; Copilot lo construye en el paso 5)

### 5. Decirle a Copilot que reconstruya el sistema

Abrir Copilot chat y pegar:

\`\`\`
Implementá mnemos siguiendo los issues en orden:
#10 (smoke tests) → #3 (SearxNG) → #2 (Supabase migrations) → #1 (HTTP API) → #4 (Frontend UI)

Después de cada issue:
1. Ejecutá el smoke test correspondiente en scripts/smoke/
2. Solo avanzá al siguiente si el smoke da PASS
3. Comentá el issue con el output del smoke como evidencia
\`\`\`

Copilot lee \`docs/adr/\`, \`docs/flows/\`, los issues con criterios de aceptación, y va escribiendo el código de \`backend/src/\` y \`frontend/src/\` mientras valida con los smokes.

---

## Validación final

\`\`\`bash
./scripts/smoke/05-end-to-end.sh
# RESULTADO: PASS si todo funciona
\`\`\`

---

## Para deploy a producción

\`\`\`bash
# Setup WIF en tu GCP project (one-time, ~15s)
./scripts/setup-gcp-wif.sh --write-env

# Subir secrets a TU repo (one-time)
./scripts/setup-github-secrets.sh

# Trigger deploy desde GH Actions
gh workflow run deploy.yml -f prefix="" -f run_migration=false
\`\`\`

Resultado: 3 URLs públicas de Cloud Run (backend, frontend, searxng).

---

## Decisiones técnicas (ADRs)

| ADR | Tema |
|-----|------|
| 001 | HNSW vs IVFFlat para pgvector |
| 002 | HTTP server local vs Edge Functions |
| 003 | Orquestación multi-MCP en Copilot |
| 004 | Modo local vs profesional |
| 005 | Testing strategy con smokes |
| 006 | SearxNG en Cloud Run con settings baked |
| 007 | Reference vs Blueprint (este split) |
| 008 | Embeddings: e5-small 384D local |
| 009 | LLM judge con fallback automático |
| 010 | Dual entry: HTTP + MCP stdio |
| 011 | Multi-tenant isolation via TABLE_PREFIX |
| 012 | Workload Identity Federation |
| 013 | Private reference + public blueprint |

Cada ADR es auto-contenido. Léelos en orden numérico.

---

## ¿Algo no funciona?

1. Revisar smokes: \`scripts/smoke/0X-*.sh\`
2. Revisar el ADR relevante en \`docs/adr/\`
3. Comparar con la spec en \`docs/flows/\`

Generado el $(date -u +"%Y-%m-%d %H:%M UTC") desde \`mnemos@$SRC_SHA\`.
EOF

ok "BLUEPRINT.md creado"

# ─── 5. README.blueprint — minimal, apunta a BLUEPRINT.md ────────────────
cat > "$DEST/README.md" <<'EOF'
# mnemos

> **Private RAG + Anonymous Research Agent** — OSS Blueprint

Agente de investigación privado que combina RAG sobre knowledge base propia,
búsqueda web anónima vía SearxNG, y un MCP server custom que se enchufa a
GitHub Copilot Agent Mode.

**Este repo es un blueprint** — `backend/src/` y `frontend/src/` están vacíos.
Copilot los reconstruye desde las specs en `docs/`.

→ Empezá por **[BLUEPRINT.md](./BLUEPRINT.md)**.

## Stack

- Node 22+ / TypeScript / Hono (backend)
- React 18 + Vite + Tailwind (frontend)
- Supabase + pgvector (knowledge base)
- SearxNG (búsqueda web anónima)
- Google Cloud Run + Workload Identity Federation (deploy)
- OpenRouter (LLM gateway)

## Documentación

| Path | Qué hay |
|------|---------|
| [`BLUEPRINT.md`](./BLUEPRINT.md) | Setup en 5 pasos |
| [`docs/adr/`](./docs/adr/) | 13 decisiones arquitectónicas auditables |
| [`docs/flows/`](./docs/flows/) | Spec del agente + orquestación MCP |
| [`docs/plans/`](./docs/plans/) | Planes de deployment |
| [`scripts/smoke/`](./scripts/smoke/) | Tests ejecutables |
| [`scripts/validate/`](./scripts/validate/) | Validadores de contratos |

## Licencia

Este blueprint es público. La versión de referencia con credenciales operacionales
del autor vive en un repo privado (ADR-013).
EOF

ok "README.md (versión blueprint) creado"

# ─── 6. Git init en el destino ──────────────────────────────────────────
cd "$DEST"
if [[ ! -d ".git" ]]; then
  git init -q -b main
  git add -A >/dev/null
  # Usa la identidad git global del usuario (no hardcoded). Si querés overridear,
  # exportá GIT_AUTHOR_NAME/EMAIL y GIT_COMMITTER_NAME/EMAIL antes de correr.
  git commit -q -m "sync: mnemos@${SRC_SHA} → blueprint snapshot"
  ok "git init + commit inicial"
else
  warn "git ya existe en destino — no se inicializa"
fi

# ─── 7. Resumen ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " ✓ Blueprint generado en: $DEST"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Stats:"
echo "  · Source SHA:     $SRC_SHA"
ADRS=$(find "$DEST/docs/adr" -name "ADR-*.md" 2>/dev/null | wc -l | xargs)
SMOKES=$(find "$DEST/scripts/smoke" -name "*.sh" 2>/dev/null | wc -l | xargs)
VALIDATORS=$(find "$DEST/scripts/validate" -name "*.sh" 2>/dev/null | wc -l | xargs)
SIZE=$(du -sh "$DEST" 2>/dev/null | cut -f1)
echo "  · ADRs:           $ADRS"
echo "  · Smoke tests:    $SMOKES"
echo "  · Validators:     $VALIDATORS"
echo "  · Total size:     $SIZE"
echo ""
echo "Next steps:"
echo "  cd $DEST"
echo "  cat BLUEPRINT.md   # leé las instrucciones"
echo "  ./scripts/validate/blueprint.sh   # valida que la estructura es correcta"
