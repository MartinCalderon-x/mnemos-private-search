# Checklist — Modo Local

> Validación manual antes de declarar el modo Local funcional.  
> Se completa en orden. Si un step falla, NO continuar — resolver primero.

**Fecha de validación:** _____________  
**Validador:** _____________  
**Commit:** _____________

---

## Pre-condiciones

- [ ] Docker Desktop corriendo
- [ ] Node.js 20+ instalado
- [ ] `.env` con todas las variables llenas
- [ ] `supabase` CLI instalado y logueado

---

## Infra (issue #2 + #3)

- [ ] `docker compose up -d searxng` levanta sin errores
- [ ] `docker compose ps` muestra `mnemos-searxng` con status `Up`
- [ ] `curl 'http://localhost:8080/search?q=test&format=json'` devuelve `200` con `results[]`
- [ ] `supabase db push` aplica migraciones sin errores
- [ ] En Supabase Dashboard, tabla `knowledge_base` existe
- [ ] `SELECT indexname FROM pg_indexes WHERE tablename = 'knowledge_base'` incluye índice HNSW

**Smoke:** `./scripts/smoke/01-searxng.sh && ./scripts/smoke/02-supabase.sh`

---

## Backend (issue #1)

- [ ] `cd backend && npm install` sin errores
- [ ] `npm run build` compila sin warnings
- [ ] `npm run dev` levanta el HTTP server en `:3000`
- [ ] `curl localhost:3000/health` devuelve `200`
- [ ] `POST /api/search/semantic` con query devuelve JSON válido
- [ ] `POST /api/search/web` con query devuelve JSON válido
- [ ] `POST /api/synthesize` devuelve `{answer: ...}`
- [ ] `POST /api/knowledge/save` devuelve `{success: true}` y persiste en DB
- [ ] El MCP server stdio responde al `mcp inspector`

**Smoke:** `./scripts/smoke/03-http-api.sh`

---

## Frontend (issue #4)

- [ ] `cd frontend && npm install` sin errores
- [ ] `npm run dev` levanta Vite en `:5173`
- [ ] La UI carga en el browser sin errores de consola
- [ ] El proxy `/api/*` redirige correctamente al backend
- [ ] Las suggestions iniciales son clickeables
- [ ] Una query muestra thinking steps animados
- [ ] La respuesta llega con SourceBadge correcto (🧠 o 🌐)
- [ ] Las SourceCards muestran fuentes
- [ ] El botón "Guardar en knowledge base" funciona
- [ ] Tras guardar, una segunda query del mismo tema usa RAG (badge 🧠)

**Smoke:** `./scripts/smoke/04-frontend.sh`

---

## End-to-end

- [ ] `./scripts/smoke/05-end-to-end.sh` PASA
- [ ] Conversación completa: 3 queries diferentes, todas funcionan
- [ ] No hay leaks de credenciales en consola del browser
- [ ] No hay errores en `docker compose logs searxng`
- [ ] No hay errores en logs del backend (`npm run dev`)

---

## MCP server con Copilot (opcional pero recomendado)

- [ ] `.vscode/mcp.json` tiene la entry de `mnemos`
- [ ] Tras `npm run build`, Copilot reconoce el MCP
- [ ] Prompt "Buscá en mi knowledge base sobre X" → Copilot usa `mnemos.semantic_search`
- [ ] Prompt "Guardá esto en mi knowledge" → Copilot usa `mnemos.save_to_knowledge`

---

## Resultado

- [ ] **TODOS los items pasados** → Listo para promover a Profesional
- [ ] **Algún item falló** → Documentar en sesión y resolver primero

---

## Notas del validador

```
(usar este espacio para anotar cosas raras, latencias, dudas)
```
