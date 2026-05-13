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
