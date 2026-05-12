# ADR-003: Orquestación multi-MCP en GitHub Copilot

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

El demo no es solamente "construir un MCP server" — es **mostrar cómo Copilot orquesta múltiples MCPs en simultáneo** para acelerar el desarrollo a niveles imposibles sin agentes.

Durante el demo en vivo, Copilot Agent Mode usa tres MCP servers:

| MCP | Provee | Quién lo construye |
|-----|--------|-------------------|
| **Supabase MCP** | Operaciones DB (queries, migraciones, RLS) | Externo (oficial) |
| **GCP MCP** | Cloud Run, Secret Manager, Artifact Registry | Externo (community) |
| **mnemos MCP** | RAG privado + búsqueda anónima | Construido en vivo |

## Decisión

Configurar los 3 MCPs en `.vscode/mcp.json` del proyecto, documentados con instrucciones precisas para que cualquier persona pueda replicar el setup.

## Configuración MCP del proyecto

```jsonc
// .vscode/mcp.json — versión real validada (ver archivo en el repo)
{
  "servers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y", "@supabase/mcp-server-supabase@latest",
        "--access-token", "${env:SUPABASE_ACCESS_TOKEN}",
        "--project-ref",  "${env:SUPABASE_PROJECT_REF}"
      ]
    },
    "gcp": {
      "command": "npx",
      "args": ["-y", "gcp-mcp"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "${userHome}/.config/gcloud/application_default_credentials.json",
        "GCP_PROJECT_ID": "${env:GCP_PROJECT_ID}"
      }
    },
    "mnemos": {
      "command": "node",
      "args": ["${workspaceFolder}/backend/dist/mcp.js"],
      "env": {
        "SUPABASE_URL":        "${env:SUPABASE_URL}",
        "SUPABASE_SECRET_KEY": "${env:SUPABASE_SECRET_KEY}",
        "OPENROUTER_API_KEY":  "${env:OPENROUTER_API_KEY}",
        "SEARXNG_URL":         "${env:SEARXNG_URL}"
      }
    }
  }
}
```

**Notas sobre el path de mnemos:**

- Apunta a `backend/dist/mcp.js` (entry point MCP stdio), **no** a `dist/index.js`
  (que es el server HTTP Hono usado por el frontend). Decisión documentada en ADR-010.
- VSCode resuelve `${env:VAR}` desde el shell que lanza VSCode, y `${userHome}`
  desde el home del usuario. Para CI o headless, las vars se inyectan vía entorno.

## Cómo se usa cada MCP en el demo

### Supabase MCP
- "Aplicar las migraciones del proyecto"
- "Crear la función RPC `match_knowledge`"
- "Mostrarme las primeras 10 filas de `knowledge_base`"
- "¿Qué índices tiene la tabla?"

### GCP MCP
- "Habilitar las APIs Cloud Run, Artifact Registry, Secret Manager"
- "Crear el service account para deploy"
- "Subir las secrets del .env a Secret Manager"
- "Desplegar el backend a Cloud Run con esta config"

### mnemos MCP (el que construimos)
- "Buscá en mi knowledge base qué dice sobre HNSW"
- "Buscá en la web cómo funciona pgvector y guardalo"
- "Hacé una síntesis de las últimas 5 entradas que guardé"

## Por qué tres MCPs y no uno solo

1. **Separación de responsabilidades** — Supabase MCP no debería saber nada de GCP, y viceversa.
2. **Reutilización** — Supabase MCP y GCP MCP son productos maduros; reinventarlos sería desperdicio.
3. **El valor de mnemos** está en el agente RAG + búsqueda anónima, no en wrappear APIs que ya tienen MCPs oficiales.
4. **Mensaje del demo** — "Copilot puede usar 1 o 100 MCPs en simultáneo, todos hablan el mismo protocolo".

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| MCPs externos cambian de versión y rompen el demo | Pinear versiones específicas en `.vscode/mcp.json` |
| Token de Supabase / GCP credentials expuestos | Usar variable expansion `${VAR}`, nunca hardcodear |
| Latencia acumulada de 3 MCPs | Cada uno responde independiente, Copilot paraleliza |

## Consecuencias

- El blueprint público debe documentar cómo conseguir el access token de Supabase y configurar `gcloud auth application-default login`
- `docs/flows/copilot-mcp-orchestration.md` describe cuándo usar cuál MCP en el flujo del demo
- El reference repo (este) tiene el `.vscode/mcp.json` armado y validado; el blueprint clonado lo trae igual
- Cada MCP tiene su propio issue de configuración con criterios de aceptación

## Referencias

- [Model Context Protocol — spec](https://modelcontextprotocol.io)
- [Supabase MCP Server](https://github.com/supabase-community/supabase-mcp)
- [GCP MCP](https://github.com/googleapis/genai-toolbox) — o equivalente community
- ADR-007 — repo reference vs blueprint
