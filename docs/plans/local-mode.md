# Plan: Modo Local

> Plan operativo para correr mnemos en local. Tiempo objetivo: **<5 minutos** desde clonar.

---

## Para qué sirve el modo Local

- Desarrollar y probar features rápidamente
- Demo offline en una laptop sin internet de la conferencia
- Onboarding de contributors externos
- Validar cambios antes de promover a producción

---

## Prerequisitos del usuario

| Requisito | Cómo verificarlo |
|-----------|-----------------|
| Docker Desktop instalado y corriendo | `docker info` (sin errores) |
| Node.js 20+ | `node --version` |
| Cuenta Supabase con un proyecto creado | URL accesible |
| API key de OpenRouter | https://openrouter.ai/keys |
| Git | `git --version` |

---

## Setup paso a paso

### Paso 1 — Clonar y configurar (1 min)

```bash
git clone https://github.com/MartinCalderon-x/mnemos
cd mnemos
cp .env.example .env
```

Editar `.env` con valores reales:
- `VITE_SUPABASE_URL` y `SUPABASE_URL` (mismo valor)
- `VITE_SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_...`)
- `SUPABASE_SECRET_KEY` (`sb_secret_...`)
- `OPENROUTER_API_KEY` (`sk-or-v1-...`)

### Paso 2 — Aplicar migraciones a Supabase (1 min)

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push
```

Validación: `supabase db dump --schema public` muestra `knowledge_base` con índice HNSW.

### Paso 3 — Levantar SearxNG (30s)

```bash
docker compose up -d searxng
```

Validación:
```bash
curl 'http://localhost:8080/search?q=test&format=json' | jq '.results[0]'
# Debe devolver un objeto con title, url, content
```

### Paso 4 — Levantar backend (1 min)

```bash
cd backend
npm install
npm run dev
```

Esto levanta:
- HTTP server en `:3000` (consumido por el frontend)
- MCP server por stdio (consumido por GitHub Copilot)

Validación:
```bash
curl -X POST http://localhost:3000/api/search/web \
  -H "Content-Type: application/json" \
  -d '{"query":"test"}' | jq '.found'
# Debe devolver true
```

### Paso 5 — Levantar frontend (1 min)

En otra terminal:
```bash
cd frontend
npm install
npm run dev
```

Abrir http://localhost:5173 — debe mostrar la UI del chat.

---

## Servicios resultantes

| Puerto | Servicio | Uso |
|--------|----------|-----|
| 8080 | SearxNG | Búsqueda anónima |
| 3000 | Backend HTTP + MCP | API del agente |
| 5173 | Frontend | UI Perplexity-style |

---

## Criterios de done para "modo Local funcional"

Todos deben pasar antes de declarar el modo Local validado:

- [ ] `docker compose ps` → `searxng` UP
- [ ] `curl localhost:8080/search?q=test&format=json` devuelve resultados
- [ ] `curl localhost:3000/api/search/semantic` con query devuelve JSON válido
- [ ] `curl localhost:3000/api/search/web` con query devuelve JSON válido
- [ ] `curl localhost:3000/api/synthesize` con context devuelve `{answer: ...}`
- [ ] `curl localhost:3000/api/knowledge/save` con data devuelve `{success: true}`
- [ ] UI en `:5173` carga sin errores en consola
- [ ] Una query end-to-end muestra thinking steps + respuesta + botón guardar
- [ ] Click en "Guardar" persiste en knowledge_base (verificable con SQL)
- [ ] Segunda query del mismo tema usa RAG (no web)

Smoke test completo:
```bash
./scripts/smoke/05-end-to-end.sh
```

---

## Conexión con Copilot Agent Mode (opcional pero recomendado)

Una vez funcionando el modo local, agregar al setup del editor:

`.vscode/mcp.json` (ya existe en el repo):
```jsonc
{
  "servers": {
    "mnemos": {
      "command": "node",
      "args": ["${workspaceFolder}/backend/dist/index.js"]
    }
  }
}
```

Compilar el backend:
```bash
cd backend && npm run build
```

Reiniciar Copilot. Validar:
```
Humano: "Buscá en mi knowledge base sobre HNSW"
Copilot: usa mnemos.semantic_search → devuelve resultados
```

---

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| `:5173` no carga | Frontend no levantó | Ver logs de `npm run dev` en frontend |
| 500 en `/api/synthesize` | OpenRouter key inválida | Verificar `OPENROUTER_API_KEY` |
| `:8080` cierra | SearxNG bloqueado por engine | Esperar 30s, reintentar |
| `match_knowledge` no existe | Migración no aplicada | `supabase db push` |
| Embeddings tardan >5s | Free tier OpenRouter rate-limit | Pagar tier o usar otro provider |

---

## Costo del modo Local

- Supabase free tier: $0
- OpenRouter free tier: ~$0 hasta 200 queries/día
- Docker local: $0
- **Total: $0/mes**

---

## Cuándo promover a Profesional

Promover cuando se cumplen TODOS:
1. Modo Local 100% funcional con `scripts/smoke/05-end-to-end.sh` verde
2. Querés URL pública para compartir
3. Querés demo en vivo en conferencia
4. Tenés cuenta GCP con billing habilitado
5. Aceptás costo de ~$2-5/mes

Ver siguiente: `docs/plans/professional-mode.md`.
