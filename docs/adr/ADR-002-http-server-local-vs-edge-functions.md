# ADR-002: HTTP API local vs Supabase Edge Functions

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

El frontend (React/Vite) necesita llamar al agente para:
1. Buscar en la knowledge base (semantic search)
2. Buscar en la web anónimamente (SearxNG)
3. Sintetizar una respuesta a partir del contexto
4. Guardar un resultado en la knowledge base

Hay dos opciones para exponer estas operaciones como endpoints HTTP.

## Decisión

Usar **dos capas según el entorno**:

| Entorno | Implementación |
|---------|---------------|
| **Local / dev** | HTTP server embebido en el backend Node.js (Hono) |
| **Producción** | Supabase Edge Functions (Deno) |

## Opción A: Solo Supabase Edge Functions

```
Frontend → Supabase Edge Functions → Supabase DB / SearxNG
```

**Pros:** Una sola implementación, deploy automático con Supabase CLI.  
**Contras:** Requiere `supabase functions serve` en local (overhead), Deno runtime diferente a Node.js, cold starts en producción, no puede llamar a SearxNG local directamente.

## Opción B: HTTP server local (elegida para dev)

```
Frontend → localhost:3000 (Hono) → Supabase DB / SearxNG local
```

**Pros:** Un solo proceso Node.js, mismo runtime que el MCP server, sin cold starts, SearxNG en docker accesible directamente, fácil de debuggear.  
**Contras:** Hay que mantener dos implementaciones (Hono local + Edge Functions prod). Se mitiga: la lógica de negocio vive en `src/tools/` y `src/lib/` — los handlers solo son adaptadores delgados.

## Arquitectura resultante

```
src/
├── tools/          ← Lógica de negocio (compartida)
│   ├── saveToKnowledge.ts
│   ├── semanticSearch.ts
│   └── anonymousSearch.ts
├── lib/            ← Clientes (compartidos)
│   ├── supabase.ts
│   └── embeddings.ts
├── http/           ← HTTP server local (Hono) — NEW
│   ├── server.ts   ← entry point HTTP
│   └── routes/
│       ├── search.ts
│       ├── save.ts
│       └── synthesize.ts
└── index.ts        ← MCP server (stdio) — sin cambios
```

Los Edge Functions de Supabase importarán la misma lógica de `tools/` cuando se implemente la capa de producción.

## Consecuencias

- `npm run dev` levanta el HTTP server en puerto 3000
- `npm run mcp` levanta el MCP server (stdio) para GitHub Copilot
- Vite proxy redirige `/api/*` → `localhost:3000`
- En producción, Edge Functions reemplazan al HTTP server sin cambiar el frontend

## Referencias

- [Hono — lightweight web framework for Node.js/Deno/Bun](https://hono.dev)
- ADR-001 — contexto de la knowledge base
