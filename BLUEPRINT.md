# Mnemos Blueprint — Setup para reconstruir con Copilot

> Este repo es un **blueprint clonable**. No contiene el código de implementación de mnemos
> (`backend/src/`, `frontend/src/` están vacíos a propósito). Tiene **specs auditables** y
> **smokes ejecutables** para que GitHub Copilot Agent Mode pueda reconstruir el sistema
> entero desde cero.
>
> Reference repo (privado) sincronizado al commit `9032048`.

---

## Setup en 5 pasos

### 1. Clonar y configurar `.env`

```bash
git clone <este-repo> mnemos
cd mnemos
cp .env.example .env       # llená con tus credenciales
```

Necesitás cuentas en:
- [Supabase](https://supabase.com) — proyecto + personal access token
- [OpenRouter](https://openrouter.ai) — API key para el LLM
- [Google Cloud](https://console.cloud.google.com) — project ID con billing habilitado

### 2. Levantar SearxNG local

```bash
docker compose up -d searxng
curl -s "http://localhost:8080/search?q=hello&format=json" | jq '.results | length'
# → ~10+ resultados
```

### 3. Aplicar migraciones Supabase

```bash
# Opción A: usás Supabase CLI directo
supabase link --project-ref $SUPABASE_PROJECT_REF
supabase db push

# Opción B: usás el script demo (con prefix si querés aislar tu run)
./scripts/apply-demo-migration.sh demo_xxxxxxxx_   # crea tabla prefijada
```

### 4. Configurar GitHub Copilot Agent Mode

Abrí el repo en VS Code. Copilot detecta automáticamente `.vscode/mcp.json` con los 3 MCPs:

- **supabase** — operaciones DB (migraciones, queries, RLS)
- **gcp** — Cloud Run, Secret Manager, Artifact Registry
- **mnemos** — (aún no existe; Copilot lo construye en el paso 5)

### 5. Decirle a Copilot que reconstruya el sistema

Abrir Copilot chat y pegar:

```
Implementá mnemos siguiendo los issues en orden:
#10 (smoke tests) → #3 (SearxNG) → #2 (Supabase migrations) → #1 (HTTP API) → #4 (Frontend UI)

Después de cada issue:
1. Ejecutá el smoke test correspondiente en scripts/smoke/
2. Solo avanzá al siguiente si el smoke da PASS
3. Comentá el issue con el output del smoke como evidencia
```

Copilot lee `docs/adr/`, `docs/flows/`, los issues con criterios de aceptación, y va escribiendo el código de `backend/src/` y `frontend/src/` mientras valida con los smokes.

---

## Validación final

```bash
./scripts/smoke/05-end-to-end.sh
# RESULTADO: PASS si todo funciona
```

---

## Para deploy a producción

```bash
# Setup WIF en tu GCP project (one-time, ~15s)
./scripts/setup-gcp-wif.sh --write-env

# Subir secrets a TU repo (one-time)
./scripts/setup-github-secrets.sh

# Trigger deploy desde GH Actions
gh workflow run deploy.yml -f prefix="" -f run_migration=false
```

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

1. Revisar smokes: `scripts/smoke/0X-*.sh`
2. Revisar el ADR relevante en `docs/adr/`
3. Comparar con la spec en `docs/flows/`

Generado el 2026-05-12 23:52 UTC desde `mnemos@9032048`.
