# Copilot MCP Orchestration — Spec ejecutable

> Este documento describe **cómo Copilot Agent Mode orquesta los 3 MCPs** durante la construcción de mnemos.  
> Es la pieza central del demo: la audiencia ve a Copilot trabajar en paralelo con Supabase, GCP y mnemos MCP.

---

## Los 3 MCPs en el ecosistema del demo

```
┌──────────────────────────────────────────────────────────────────┐
│                  GitHub Copilot Agent Mode                        │
│                                                                   │
│   Recibe: prompt humano + contexto del workspace                  │
│   Decide: qué MCP usar para cada subtarea                         │
└──────────────────────────────────────────────────────────────────┘
              │                    │                    │
              ▼                    ▼                    ▼
    ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
    │  Supabase MCP    │  │     GCP MCP      │  │   mnemos MCP     │
    │  (oficial)       │  │   (community)    │  │  (este proyecto) │
    │                  │  │                  │  │                  │
    │ • Migraciones    │  │ • Cloud Run      │  │ • semantic_search│
    │ • Queries SQL    │  │ • Secret Manager │  │ • anonymous_search│
    │ • RLS policies   │  │ • Artifact Reg.  │  │ • save_to_kb     │
    │ • Edge Functions │  │ • IAM            │  │                  │
    └──────────────────┘  └──────────────────┘  └──────────────────┘
              │                    │                    │
              ▼                    ▼                    ▼
       Supabase Cloud         GCP Project          DB + SearxNG
```

---

## Cuándo Copilot usa cuál

### Supabase MCP — operaciones DB

| Acción humana | Copilot ejecuta |
|---------------|-----------------|
| "Aplicá las migraciones" | `supabase.apply_migration(name, sql)` |
| "Mostrame los datos guardados" | `supabase.execute_sql("SELECT * FROM knowledge_base LIMIT 10")` |
| "Creá la función match_knowledge" | `supabase.apply_migration("match_knowledge", sql)` |
| "¿Hay RLS habilitado?" | `supabase.list_policies("knowledge_base")` |
| "Deployá la edge function semantic-search" | `supabase.deploy_edge_function("semantic-search", code)` |

### GCP MCP — infraestructura

| Acción humana | Copilot ejecuta |
|---------------|-----------------|
| "Habilitá las APIs necesarias" | `gcp.enable_apis(["run", "artifactregistry", "secretmanager"])` |
| "Subí los secrets del .env" | `gcp.create_secrets_from_env(".env")` |
| "Buildea y deployá el backend" | `gcp.deploy_cloud_run(service, image, env)` |
| "Mostrame los logs del servicio" | `gcp.tail_logs("mnemos-backend", limit=50)` |
| "¿Cuánto está costando esto?" | `gcp.billing_summary(month)` |

### mnemos MCP — agente de investigación

| Acción humana | Copilot ejecuta |
|---------------|-----------------|
| "¿Qué sabés sobre HNSW?" | `mnemos.semantic_search("HNSW")` |
| "Buscá info de pgvector y guardala" | `mnemos.anonymous_search()` → `mnemos.save_to_knowledge()` |
| "Sintetizá lo que tengo guardado sobre X" | `mnemos.semantic_search()` → síntesis local de Copilot |

---

## Flujo del demo en vivo

### Fase 1 — Setup inicial (Copilot orquesta sin código aún)

```
Humano:  "Configurá los servicios externos del proyecto"

Copilot:
  1. Lee docs/adr/ADR-003 → entiende los 3 MCPs
  2. Usa GCP MCP:
     - Habilita Cloud Run, Artifact Registry, Secret Manager
     - Crea service account mnemos-deploy
     - Configura Workload Identity Federation
  3. Usa Supabase MCP:
     - Aplica migración pgvector
     - Aplica migración knowledge_base
     - Crea función RPC match_knowledge
  4. Reporta al humano: "Servicios listos, próximo paso: Issue #1"
```

### Fase 2 — Construcción del MCP server (mnemos MCP aún no existe)

```
Humano:  "Implementá el Issue #1"

Copilot:
  1. Lee Issue #1 (HTTP API server local)
  2. Lee docs/flows/agent-decision-flow.md (especificación)
  3. Lee ADR-002 (decisión de Hono)
  4. Genera código en backend/src/http/
  5. Corre smoke test scripts/smoke/03-http-api.sh
  6. Si pasa: marca issue como done con evidencia
```

### Fase 3 — Uso del MCP server recién construido

```
Humano:  "Llená el knowledge base con info sobre embeddings"

Copilot:
  1. Usa mnemos MCP (que acaba de construir):
     - mnemos.anonymous_search("OpenAI embeddings best practices")
     - Por cada resultado, mnemos.save_to_knowledge()
  2. Muestra al humano qué se guardó

Humano:  "Ahora preguntale: ¿cuándo conviene 1536 vs 3072 dimensiones?"

Copilot:
  1. mnemos.semantic_search("dimensiones embeddings 1536 3072")
  2. Sintetiza la respuesta con los chunks recuperados
  3. Cita las fuentes
```

### Fase 4 — Deploy a producción

```
Humano:  "Llevemos esto a Cloud Run"

Copilot (paralelo):
  - GCP MCP: build images en Artifact Registry
  - GCP MCP: deploy 3 servicios (backend, frontend, searxng)
  - Supabase MCP: deploy edge functions
  - GCP MCP: configura URLs públicas
  
Reporta: "URL pública: https://mnemos-frontend-xyz.run.app"
```

---

## Patrón de paralelización

Copilot Agent Mode ejecuta MCPs en paralelo cuando son independientes. Esto debe quedar visible en el demo.

Ejemplo de prompt que dispara paralelización visible:

```
"Setup completo de producción: APIs GCP, secrets, migraciones Supabase, 
 deploy Cloud Run para los 3 servicios, deploy edge functions"
```

Copilot orquesta:

```
Paralelo:
├── GCP MCP: enable_apis()
├── GCP MCP: create_secrets()
└── Supabase MCP: apply_migrations()
        ↓ (espera dependencias)
Paralelo:
├── GCP MCP: deploy mnemos-backend
├── GCP MCP: deploy mnemos-frontend
├── GCP MCP: deploy mnemos-searxng
└── Supabase MCP: deploy edge functions
```

---

## Configuración requerida en `.vscode/mcp.json`

Ver ADR-003 para configuración completa y ADR-010 para la decisión de dual entry points.
El server `mnemos` apunta a `backend/dist/mcp.js` (entry MCP stdio), **no** a `dist/index.js`
(que es el server HTTP del frontend). Para que Copilot pueda hablar con `mnemos`:

```bash
cd backend && npm install && npm run build   # genera dist/mcp.js
```

Variables necesarias en el entorno del usuario:

| Variable | Cómo conseguirla |
|----------|-----------------|
| `SUPABASE_ACCESS_TOKEN` | https://supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_REF` | URL del proyecto Supabase (subdominio) |
| `GCP_PROJECT_ID` | Console GCP → settings |
| `GOOGLE_APPLICATION_CREDENTIALS` | `gcloud auth application-default login` |
| `OPENROUTER_API_KEY` | https://openrouter.ai/keys |
| `SUPABASE_URL` / `SUPABASE_SECRET_KEY` | Proyecto Supabase → Settings → API |
| `SEARXNG_URL` | `http://localhost:8080` (docker compose lo levanta) |

---

## Mensaje narrativo del demo

> "Antes, conectar Copilot a 3 servicios externos era tres días de glue code. Hoy, son 3 entradas en un JSON. Todos hablan MCP — el USB-C de los agentes."

Este mensaje se entrega visualmente cuando:
1. Se muestra `.vscode/mcp.json` en pantalla (3 servidores)
2. Se ve a Copilot llamando a uno y luego a otro sin esfuerzo
3. Se demuestra el speed-up: lo que sería un workflow de 30 minutos se hace en 5

---

## Referencias

- ADR-003 — decisión de orquestación multi-MCP
- ADR-007 — reference vs blueprint
- `docs/flows/live-demo-script.md` — guion paso a paso del show
- `docs/flows/agent-decision-flow.md` — flujo interno del agente mnemos
