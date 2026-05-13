# ADR-010: Backend con dos entry points — HTTP (Hono) + MCP stdio

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

El backend de mnemos tiene **dos consumidores con protocolos distintos**:

1. **Frontend web** (Vite + React) consume HTTP REST (`POST /api/*`).
2. **GitHub Copilot Agent Mode** consume MCP (JSON-RPC sobre stdio).

Hasta ADR-001/ADR-002 sólo existía el server HTTP. ADR-003 declaró que el
demo central es Copilot orquestando 3 MCPs (Supabase + GCP + mnemos), pero la
implementación de referencia inicial era únicamente Hono.

Durante la apertura de la sesión 2026-05-12 (issue #6) se detectó la
inconsistencia: `.vscode/mcp.json` apuntaba a `backend/dist/index.js`, que es
HTTP, y por lo tanto Copilot **fallaría el handshake MCP** aunque pudiera
lanzar el proceso.

## Decisión

El backend expone **dos entry points** que comparten toda la lógica de negocio:

```
backend/src/
├── http/                 ← Hono server (REST)
│   └── routes/
├── lib/                  ← Compartido (env, supabase, embeddings, searxng, openrouter)
├── tools/                ← Compartido (semanticSearch, anonymousSearch, saveToKnowledge)
├── index.ts              ← Entry HTTP   → dist/index.js  → puerto 3000
└── mcp.ts                ← Entry MCP    → dist/mcp.js    → stdio
```

| Entry | Build target | Protocolo | Consumidor | Transporte |
|-------|--------------|-----------|------------|------------|
| `index.ts` | `dist/index.js` | HTTP REST | Frontend Vite | TCP :3000 |
| `mcp.ts` | `dist/mcp.js` | MCP 2024-11-05 | Copilot Agent | stdio |

Las **3 tools** (`semantic_search`, `anonymous_search`, `save_to_knowledge`)
se exponen idénticas en ambos entry points, importando la misma implementación
desde `src/tools/`. No hay duplicación de lógica.

## Alternativas evaluadas

| Opción | Por qué se descartó |
|--------|---------------------|
| **Sólo MCP (eliminar HTTP)** | El frontend dejaría de funcionar; perdemos la UI de demo |
| **Sólo HTTP (eliminar MCP)** | Rompe ADR-003 — Copilot no puede consumir HTTP como MCP |
| **HTTP que envuelve MCP** | Doble transport overhead, latencia extra, no es idiomático |
| **MCP con transport HTTP** (Streamable HTTP) | Válido para producción remota, pero stdio es lo que Copilot detecta automáticamente desde `.vscode/mcp.json` |
| **Dos paquetes npm separados** | Sobreingeniería: comparten 100% de las tools |

## Implementación

### Scripts del package.json

```json
{
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "dev:mcp": "tsx src/mcp.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "start:mcp": "node dist/mcp.js"
  }
}
```

### Reglas críticas del entry MCP stdio

1. **Stdout reservado para JSON-RPC.** Cualquier `console.log` corrompe el
   handshake. Todos los logs van a `console.error` (stderr).
2. **dotenv carga `.env` desde la raíz del repo** vía `lib/env.ts`. Las vars
   inyectadas por `.vscode/mcp.json` toman precedencia, pero el `.env` actúa
   como fallback para `tsx src/mcp.ts` en desarrollo.
3. **El SDK serializa las inputSchemas zod a JSON Schema automáticamente** — lo
   que ve Copilot en `tools/list` se deriva del shape declarado en `mcp.ts`.

### Validación del handshake

```bash
# Smoke manual: initialize + tools/list por stdio
(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 1
) | node backend/dist/mcp.js
```

Salida esperada: `protocolVersion: 2024-11-05`, `serverInfo.name: mnemos`,
y `tools: [{ name: "semantic_search", ... }, { name: "anonymous_search", ... }, { name: "save_to_knowledge", ... }]`.

## Consecuencias

- **Build único, dos artefactos.** Un solo `tsc` produce ambos JS files.
- **No hay drift entre transports.** Si se agrega una tool, se registra una
  vez en `tools/` y se expone en ambos entry points editando 2 líneas.
- **Deploy a Cloud Run** sólo necesita el entry HTTP. El MCP stdio es
  irrelevante en producción (no hay agente corriendo allí).
- **El blueprint clonable** debe documentar ambos modos en BLUEPRINT.md.
- **Issue #14 (integration tests)** debe cubrir ambos transports — Vitest
  para el server Hono + un test de handshake stdio para el server MCP.

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| Un dev agrega un `console.log` y rompe stdio | Lint rule futura + comentario en `mcp.ts` |
| Drift entre HTTP y MCP (una tool actualizada en uno solo) | Las tools viven en `src/tools/`, los entry points las importan; no hay forma de divergir sin tocar la lógica común |
| MCP SDK cambia API y rompe el handshake | Pin de versión en `package.json` + smoke de handshake en CI |

## Referencias

- ADR-002 — HTTP server local vs Edge Functions (decisión Hono)
- ADR-003 — multi-MCP orchestration (consumidor del entry MCP)
- [MCP spec — Stdio transport](https://modelcontextprotocol.io/docs/concepts/transports)
- [@modelcontextprotocol/sdk — McpServer](https://github.com/modelcontextprotocol/typescript-sdk)
