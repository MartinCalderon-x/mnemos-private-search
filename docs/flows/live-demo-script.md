# Live Demo Script — mnemos × Copilot Agent Mode

> Guion paso a paso del demo en vivo. Tiempo estimado: **30 minutos**.  
> Audiencia: developers familiarizados con AI tools, no necesariamente con MCP.

---

## Estado inicial

- Repo abierto: `mnemos-private-search` (clonado limpio, sin código en `backend/src/` ni `frontend/src/`)
- VS Code con Copilot Agent Mode habilitado
- `.vscode/mcp.json` ya configurado con los 3 MCPs
- Variables de entorno cargadas (`.env` con credenciales del presenter)
- Docker Desktop corriendo

---

## Acto 1 — La promesa (3 min)

### 1.1 Hook (30s)
> "Voy a construir, frente a ustedes, un agente de investigación privado con RAG y búsqueda anónima.  
> Ningún dato sale a Google. Cero tracking. Y lo voy a hacer en 30 minutos.  
> No yo solo — Copilot va a hacer el 80% del trabajo, hablando con 3 servicios externos en paralelo."

### 1.2 Mostrar el repo vacío (1 min)
- Abrir `mnemos-private-search` en VS Code
- Mostrar que `backend/src/` y `frontend/src/` están vacíos
- Mostrar que `docs/` SÍ tiene contenido completo: ADRs, flows, plans
- Mostrar `BLUEPRINT.md` con las instrucciones para Copilot

### 1.3 Mostrar `.vscode/mcp.json` (1.5 min)
- Abrir el archivo
- Resaltar las 3 entries: `supabase`, `gcp`, `mnemos`
- Frase clave: **"Esto es todo lo que Copilot necesita para hablar con los 3 servicios. Antes esto era un día de glue code."**

---

## Acto 2 — Setup automático (5 min)

### 2.1 Prompt único a Copilot (30s)

Abrir Copilot chat y pegar:

```
Configurá toda la infraestructura siguiendo docs/adr/ADR-004 y docs/plans/professional-mode.md.
- Habilitá APIs GCP necesarias
- Aplicá las migraciones de Supabase
- Cargá los secrets a Secret Manager
- Reportá al final qué se hizo
```

### 2.2 Ver a Copilot orquestar (4 min)

La audiencia ve en pantalla:
- Copilot leyendo los ADRs (citas literales)
- Copilot llamando a **GCP MCP**: `enable_apis(...)`
- Copilot llamando a **Supabase MCP**: `apply_migration(...)`
- Resultados volviendo en paralelo
- Reporte final: "✓ APIs habilitadas, ✓ migraciones aplicadas, ✓ 4 secrets en Secret Manager"

**Frase clave del presenter:**
> "Fíjense que está usando dos MCPs distintos al mismo tiempo. No tuve que decirle 'usá GCP para esto, Supabase para aquello'. Lee los specs y elige."

### 2.3 Validación visible (30s)

Pegar al chat:

```
Verificá que la tabla knowledge_base existe en Supabase y mostrame su schema
```

Copilot usa Supabase MCP, devuelve el schema. **El público ve que es real, no truco.**

---

## Acto 3 — Construcción del MCP server (15 min)

### 3.1 Issue #1 — HTTP API server (5 min)

Pegar:

```
Implementá el Issue #1. Seguí los criterios de aceptación.
Cuando termines, corré el smoke test scripts/smoke/03-http-api.sh y mostrame el output.
```

Audiencia ve:
- Copilot creando `backend/src/http/server.ts`, `routes/*.ts`
- Copilot ejecutando `npm run dev` en una terminal
- Copilot ejecutando el smoke test
- Output verde con los 4 endpoints respondiendo

### 3.2 Issue #4 — Frontend chat (5 min)

```
Implementá el Issue #4. El backend ya está corriendo en :3000.
```

Audiencia ve:
- Copilot creando los componentes React
- Copilot levantando el dev server
- VS Code abriendo http://localhost:5173 en el preview
- Una primera query funcionando con thinking steps animados

### 3.3 Probar el agente recién construido (5 min)

En la UI del chat (que acaba de cobrar vida), el presenter escribe:

> "¿Qué es HNSW?"

Audiencia ve:
- Thinking step: "Revisando knowledge base..." (vacía, no encuentra)
- Thinking step: "Buscando en la web de forma anónima..."
- SourceBadge: 🌐 Búsqueda anónima
- 5 cards de resultados de SearxNG
- Respuesta sintetizada en markdown
- Botón "💾 Guardar en knowledge base"

Click en guardar.

> "Ahora preguntame lo mismo."

Esta vez:
- Thinking step: "Revisando knowledge base..." ✓ found
- SourceBadge: 🧠 Knowledge base
- Respuesta usando el contenido recién guardado

**Frase clave:**
> "Esto es RAG en acción. Lo guardé hace 30 segundos y ya el agente lo usa. Sin reentrenamiento, sin pipeline, sin nada."

---

## Acto 4 — Deploy a producción (4 min)

### 4.1 Prompt al deploy (30s)

```
Llevá esto a Cloud Run siguiendo docs/plans/professional-mode.md.
3 servicios: backend, frontend, searxng. 
Cuando termines, dame las URLs públicas.
```

### 4.2 Ver el deploy (3 min)

- Copilot llama GCP MCP en paralelo para los 3 servicios
- Audiencia ve el log de Artifact Registry recibiendo imágenes
- Cloud Run mostrando los servicios "Deploying"
- Final: 3 URLs públicas

### 4.3 Probar la URL pública (30s)

Abrir `https://mnemos-frontend-xxx.run.app` en pantalla. Hacer una query. Funciona.

**Frase clave:**
> "Hace 25 minutos estaba vacío. Ahora hay un producto desplegado, accesible desde cualquier parte del mundo, y está usando MI knowledge base privada."

---

## Acto 5 — Cierre (3 min)

### 5.1 Lo que se mostró (1 min)
- 3 MCPs orquestados en paralelo
- Repo vacío → producto deployado en 25 minutos
- 0 líneas de código escritas a mano por el presenter
- Cero datos saliendo a tracking de Google

### 5.2 El blueprint es público (1 min)
- Mostrar URL del repo `mnemos-private-search`
- "Cualquiera puede clonarlo y reproducir esto. Las instrucciones para Copilot están todas escritas."

### 5.3 Q&A o demo extra (1 min)

Demo opcional si hay tiempo:
- "¿Querés ver cómo agrego una nueva tool al MCP?" → Copilot lo hace en vivo en 90s
- "¿Querés ver cómo Copilot debuggea un error?" → trigger un error a propósito

---

## Backups y contingencias

| Falla | Plan B |
|-------|--------|
| Cold start de Cloud Run en pleno demo | Pre-warming con cron 5 min antes |
| SearxNG bloqueado por Google | DuckDuckGo fallback ya configurado |
| Copilot tarda demasiado en una tool | Tener video pre-grabado de esa parte |
| Wifi del venue lento | Hotspot del celular como backup |
| Demo total muere | Video completo pre-grabado de 5 min de "highlights" |

---

## Materiales de soporte

- Slides con frases clave para overlay durante el demo
- Tarjeta con los 3 prompts principales para no olvidarlos
- Backup video subido a `docs/sessions/reports/` antes del show
- URL fija del demo en producción para Q&A

---

## Métricas de éxito del demo

| Métrica | Target |
|---------|--------|
| Tiempo total | <30 min |
| Tiempo de "click a deploy URL" | <30 min |
| Errores en vivo | 0 (o resueltos en <30s) |
| Aplausos al ver MCPs en paralelo | Alto |
| Preguntas técnicas en Q&A | >5 |

---

## Referencias

- `docs/flows/copilot-mcp-orchestration.md` — qué hace cada MCP
- `docs/plans/professional-mode.md` — cómo es el setup pro
- `docs/testing/production-checklist.md` — validación 1h antes del demo
