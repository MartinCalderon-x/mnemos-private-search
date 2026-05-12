# Mnemos — Copilot Coding Agent Instructions

Este repo es un **agente de investigación privado con RAG + búsqueda anónima**. Cuando alguien te asigne un issue, leé este archivo entero, después los ADRs relevantes, y recién después escribí código.

## Qué construis

Un sistema con:
- **Backend** Node 22 + TypeScript + Hono (HTTP REST en `:3000`) que también expone un **MCP server por stdio** (mismo backend, dos entry points — ver ADR-010).
- **Frontend** React 18 + Vite + Tailwind. Estilo chat tipo Perplexity con thinking steps visibles.
- **Knowledge base** Supabase + pgvector (extensión `extensions.vector`, embeddings 384D del modelo `multilingual-e5-small`).
- **Búsqueda anónima** SearxNG en Docker local (settings.yml baked para Cloud Run según ADR-006).
- **LLM gateway** OpenRouter (sin embeddings — los embeddings son locales con `@xenova/transformers`, ver ADR-008).

## Orden de implementación

Hay issues abiertos numerados. Los podés ver con `gh issue list`. El orden **mínimo viable** para que el demo funcione:

1. **Issue #10** — smoke tests (ya están, no los toques)
2. **Issue #3** — SearxNG corriendo via docker-compose
3. **Issue #2** — Supabase migrations aplicadas (función `match_knowledge`, tabla `knowledge_base`)
4. **Issue #1** — HTTP API Hono en `backend/src/`
5. **Issue #4** — frontend Vite en `frontend/src/`

Cada issue tiene "Criterios de aceptación" + "Testing". Tu definición de done = el smoke test correspondiente da `RESULTADO: PASS`.

## Reglas de oro

1. **Leé el ADR antes de implementar.** Los ADRs en `docs/adr/` son contratos. Si vas a tocar embeddings, leé ADR-008. Si vas a tocar el judge de síntesis, leé ADR-009. Si vas a deployar, leé ADR-004 + ADR-012.

2. **Smoke después de cada cambio sustancial.** Está en `scripts/smoke/0X-*.sh`. Si tu cambio rompe un smoke previamente verde, parar y arreglar antes de seguir.

3. **No commitees secrets.** Si necesitás una credencial, está en GitHub Secrets (prefijo `COPILOT_MCP_*` para tus MCPs, otras para los workflows). Nunca embebas valores hardcoded.

4. **TABLE_PREFIX existe.** Si te asignan un demo run, vas a recibir `TABLE_PREFIX=demo_xxxxxx_` como env var. Las tools deben usar `dbNames.knowledgeBaseTable` y `dbNames.matchKnowledgeFn` desde `backend/src/lib/env.ts` — nunca strings hardcoded. Ver ADR-011.

5. **No alpine para backend.** Node 22-slim (Debian). Razón: `@xenova/transformers` necesita glibc, y `@supabase/supabase-js` necesita Node 22+. Cualquier `Dockerfile FROM node:*-alpine` está mal.

## Estructura del repo

```
backend/
  src/
    lib/        ← clientes (env, supabase, embeddings, searxng, openrouter)
    tools/      ← lógica de negocio: semanticSearch, anonymousSearch, saveToKnowledge
    http/       ← server Hono + routes/
    index.ts    ← entry HTTP (compila a dist/index.js)
    mcp.ts      ← entry MCP stdio (compila a dist/mcp.js)
  Dockerfile    ← TEMPLATE (en blueprint público) o implementación (en mnemos privado)

frontend/
  src/
    components/  ← ChatMessage, ThinkingSteps, SourceCards
    hooks/       ← useChat orquesta el flow RAG → web → save
    App.tsx
  Dockerfile     ← Vite build → Nginx static
  nginx.conf     ← SPA fallback + envsubst sobre $PORT

supabase/
  migrations/    ← schema canónico
  templates/     ← demo-migration con {{PREFIX}} para multi-tenant (ADR-011)

scripts/
  smoke/        ← tests ejecutables: arrancan servicios y validan
  validate/     ← validators de contratos (mcp-config, blueprint, deploy-workflow)
  apply-demo-migration.sh, cleanup-demo.sh, etc.

docs/
  adr/          ← 13 decisiones arquitectónicas — léelas antes de implementar lo relacionado
  flows/        ← spec del agente, MCP orchestration, demo script
  plans/        ← deployment, blueprint replication
```

## Cómo deployar

**No deployes vos directamente.** Tirá el workflow:

```bash
gh workflow run deploy.yml \
  -f prefix=demo_$(date +%s | tail -c 9)_ \
  -f run_migration=true
```

El workflow corre con WIF (sin SA keys), buildea las 3 imágenes en Artifact Registry, deploya a Cloud Run, y reporta las URLs. Si te asignan un issue de deploy, esto es lo que tenés que ejecutar — no `gcloud run deploy` directo.

## MCPs disponibles para vos

Cuando trabajés en este repo, tenés acceso a estos MCPs (configurados en repo Settings):

| MCP | Para qué |
|-----|----------|
| **supabase** | Aplicar migraciones, queries SQL, listar tablas, ver schema. Usá esto en vez de tirar SQL via REST. |
| **github** | Issues, PRs, workflows (built-in del Coding Agent) |

Para GCP no usás MCP — disparás el workflow de deploy que ya tiene WIF configurado.

## Cuando termines un issue

1. Corré el smoke correspondiente → debe imprimir `RESULTADO: PASS`
2. Commiteá con mensaje siguiendo convención (`feat(scope): ...`, `fix(scope): ...`)
3. Comentá el issue con el output del smoke como evidencia (el último bloque del log, no entero)
4. Cerrá el issue (`Closes #N` en el commit message lo hace automático)
5. Pasá al siguiente del orden — no saltees, las dependencias son reales

## Estilo de código

- TypeScript strict, sin `any`
- Naming: tools camelCase (`semanticSearch`), tipos PascalCase (`SemanticHit`)
- Sin comentarios obvios. Solo si el "por qué" no se entiende del código.
- Errores explícitos: `throw new Error('contexto: detalle')` en vez de booleanos.

## Si algo no entendés

Antes de inventar:
1. Buscar en `docs/adr/` por palabra clave
2. Leer el issue completo (sección "Lectura previa obligatoria")
3. Mirar smoke tests del issue — describen el output esperado
4. Si después de eso seguís trabado, dejá un comentario en el issue describiendo el bloqueo y pará. No improvises arquitectura.
