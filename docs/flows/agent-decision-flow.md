# Flujo de Decisión del Agente mnemos

> Este documento describe el flujo completo de razonamiento del agente. GitHub Copilot debe usar este documento como spec para implementar los endpoints HTTP y las Edge Functions.

---

## Diagrama de flujo

```
Usuario envía query
        │
        ▼
┌─────────────────────────────┐
│  1. semantic_search(query)  │  ← tool: semanticSearch.ts
│     threshold: 0.7          │  ← busca en knowledge_base via pgvector
│     limit: 3                │
└─────────────┬───────────────┘
              │
      ┌───────┴────────┐
      │                │
   found?           not found
      │                │
      ▼                ▼
┌──────────┐   ┌────────────────────────────┐
│ usar RAG │   │  2. anonymous_search(query) │  ← tool: anonymousSearch.ts
│ context  │   │     categories: general     │  ← SearxNG, sin tracking
│          │   │     limit: 5                │
└────┬─────┘   └────────────┬───────────────┘
     │                      │
     │              ┌───────┴────────┐
     │              │                │
     │           found?          not found
     │              │                │
     │              ▼                ▼
     │        ┌──────────┐   ┌──────────────────┐
     │        │ usar web │   │ responder: "no    │
     │        │ context  │   │ encontré info"   │
     │        └────┬─────┘   └──────────────────┘
     │             │
     └──────┬──────┘
            │
            ▼
┌───────────────────────────────────────┐
│  3. synthesize(query, context,        │  ← endpoint: POST /api/synthesize
│               sourceType)            │  ← llama a LLM via OpenRouter
│                                       │  ← genera respuesta en markdown
│   sourceType: 'rag' | 'web' | 'none' │
└─────────────────┬─────────────────────┘
                  │
                  ▼
         Respuesta mostrada al usuario
         con SourceBadge + SourceCards
                  │
                  ▼
         ¿Guardar en knowledge base?
         [botón "💾 Guardar"]
                  │
                  ▼ (si el usuario hace click)
┌─────────────────────────────────────┐
│  4. save_to_knowledge(title,        │  ← tool: saveToKnowledge.ts
│                       content,      │  ← genera embedding
│                       source)       │  ← inserta en knowledge_base
└─────────────────────────────────────┘
```

---

## Endpoints HTTP (local dev — Hono)

### POST /api/search/semantic
Busca en la knowledge base privada.

**Request:**
```json
{
  "query": "string",
  "threshold": 0.7,
  "limit": 3
}
```

**Response (found):**
```json
{
  "found": true,
  "results": [
    {
      "id": "uuid",
      "title": "string",
      "content": "string",
      "source": "string | null",
      "similarity": 0.92
    }
  ],
  "message": "Encontré 2 resultado(s) relevante(s) en la knowledge base"
}
```

**Response (not found):**
```json
{
  "found": false,
  "results": [],
  "message": "No encontré información relevante en la knowledge base"
}
```

---

### POST /api/search/web
Busca en la web de forma anónima via SearxNG.

**Request:**
```json
{
  "query": "string",
  "categories": ["general"],
  "language": "es",
  "limit": 5
}
```

**Response:**
```json
{
  "found": true,
  "results": [
    {
      "title": "string",
      "url": "https://...",
      "snippet": "string",
      "engine": "google"
    }
  ],
  "message": "Encontré 5 resultado(s) web de forma anónima"
}
```

---

### POST /api/synthesize
Genera una respuesta en lenguaje natural a partir del contexto.

**Request:**
```json
{
  "query": "string",
  "context": "string (texto de los resultados concatenados)",
  "sourceType": "rag | web | none"
}
```

**Response:**
```json
{
  "answer": "string (markdown)"
}
```

**Implementación:** Llamar a OpenRouter con el modelo `anthropic/claude-3-5-haiku` (rápido y económico para síntesis). Prompt del sistema:

```
Eres un asistente de investigación privado. Responde en español, de forma clara y concisa.
Basa tu respuesta ÚNICAMENTE en el contexto provisto. Si el contexto es insuficiente, dilo.
Usa markdown para estructurar la respuesta cuando sea útil.
```

---

### POST /api/knowledge/save
Guarda contenido en la knowledge base con embedding semántico.

**Request:**
```json
{
  "title": "string",
  "content": "string",
  "source": "string (opcional)"
}
```

**Response:**
```json
{
  "success": true,
  "id": "uuid",
  "title": "string",
  "saved_at": "ISO timestamp",
  "message": "\"título\" guardado en la knowledge base"
}
```

---

## Supabase Edge Functions (producción)

Cada endpoint HTTP local tiene su equivalente como Edge Function.

| HTTP local (Hono) | Edge Function (Deno) |
|-------------------|---------------------|
| `POST /api/search/semantic` | `supabase/functions/semantic-search/index.ts` |
| `POST /api/search/web` | `supabase/functions/anonymous-search/index.ts` |
| `POST /api/synthesize` | `supabase/functions/synthesize/index.ts` |
| `POST /api/knowledge/save` | `supabase/functions/save-knowledge/index.ts` |

La lógica de negocio (`tools/`, `lib/`) se reutiliza en ambas capas.

---

## Variables de entorno requeridas

| Variable | Usado en | Descripción |
|----------|----------|-------------|
| `SUPABASE_URL` | backend | URL del proyecto Supabase |
| `SUPABASE_SECRET_KEY` | backend | Secret key para operaciones server-side |
| `OPENROUTER_API_KEY` | backend | Para embeddings y síntesis LLM |
| `SEARXNG_URL` | backend | URL de SearxNG (default: http://localhost:8080) |
| `VITE_SUPABASE_URL` | frontend | Mismo SUPABASE_URL |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | frontend | Publishable key para auth frontend |

---

## Razonamiento visible en la UI

El frontend muestra cada paso del flujo como un "thinking step":

| Paso | Texto visible | Ícono |
|------|--------------|-------|
| semantic_search | "Revisando knowledge base..." | 🧠 |
| anonymous_search | "Buscando en la web de forma anónima..." | 🌐 |
| synthesize | "Sintetizando respuesta..." | ✨ |
| save_to_knowledge | "Guardando resultado..." | 💾 |

Cada paso aparece con animación de puntos mientras está en progreso, y se tacha al completarse.
