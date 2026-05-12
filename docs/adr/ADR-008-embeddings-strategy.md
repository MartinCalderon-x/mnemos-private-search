# ADR-008: Estrategia de Embeddings

**Fecha:** 2026-05-08
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

mnemos hace búsqueda semántica sobre una knowledge base privada. Para esto necesita
convertir texto en vectores densos. Hay tres ejes en juego:

1. **Calidad multilingüe**: el demo y los usuarios escriben mayormente en español.
2. **Privacidad**: si el contenido a indexar es sensible, mandarlo a un proveedor
   externo contradice la promesa "RAG privado".
3. **Costo y dependencias**: una API key adicional sube fricción del setup local.

El schema original era `vector(1536)` asumiendo OpenAI `text-embedding-3-small`.
Esta decisión se revisó al detectar que:

- OpenRouter (la única key que el demo ya requería) sí soporta embeddings, pero
  agregar OpenAI direct pasa la fricción al setup.
- El demo es público — el flujo "guardar y reusar" debe funcionar sin pedir
  más credenciales.
- Producción podrá optimizar distinto (ej: Supabase AI nativa).

## Decisión

Separar el modelo de embeddings por entorno:

| Entorno | Modelo | Dim | Provider |
|---------|--------|-----|----------|
| **Local / dev** | `Xenova/multilingual-e5-small` | 384 | `@xenova/transformers` (ONNX en Node) |
| **Producción**  | TBD — candidato `ai.gte_small` (Supabase) | 384 | SQL nativo en Edge Functions |

Schema unificado: `vector(384)` para ambos (la dimensión es lo único acoplado).

## Alternativas evaluadas

### A. OpenAI `text-embedding-3-small` (1536D)
**Pros:** mejor calidad medida en MTEB, sin instalar runtime ML.
**Contras:** API key adicional, mandar contenido sensible al proveedor, costo
($0.02 por millón de tokens), schema vector(1536) ocupa más en disco/RAM.

### B. OpenRouter `openai/text-embedding-3-small` via /embeddings
**Pros:** una sola key cubre embeddings + chat; verificado que funciona (spike).
**Contras:** mismo problema de privacidad; dependencia de proxy externo; sigue
mandando texto al proveedor. La key que ya tenemos sigue siendo de un externo.

### C. Voyage AI `voyage-3` (1024D)
**Pros:** lidera MTEB para retrieval.
**Contras:** API key adicional, no hay free tier productivo, schema cambia.

### D. transformers.js — `all-MiniLM-L6-v2` (384D)
**Pros:** local, gratis, 23MB.
**Contras:** entrenado solo en inglés. El demo es en español → degrada
significativamente en queries cruzadas castellano↔inglés (ej "MCP" ↔ "Model
Context Protocol").

### E. transformers.js — `multilingual-e5-small` (384D) ← elegido
**Pros:**
- 100% local, sin API keys
- ~100 idiomas, español de calidad
- Quantized int8: 30MB en disco, ~80MB descarga inicial
- MTEB ~62% (small es competitivo con modelos 4× su tamaño)
- License MIT
- Convención de prefijos `query: ` / `passage: ` mejora cross-lingual ~3-5pts
- Vectores normalizados al salir → cosine ≡ inner product

**Contras:**
- Primer save/search dispara descarga del modelo (~80MB, ~30s una vez)
- Ligero overhead de RAM (~120MB residente con modelo cargado)
- ONNX runtime tiene una superficie de prebuild nativa; en Linux/macOS
  funciona out-of-the-box pero Windows requiere VCRedist

## Consecuencias

### Schema y migraciones
- `knowledge_base.embedding` cambió de `vector(1536)` a `vector(384)`
  (migración `20260508000003_switch_to_local_embeddings.sql`)
- Función `match_knowledge` actualizada al mismo dim
- Datos previos descartables (truncate) — la dimensión de pgvector no se
  puede convertir entre tamaños

### Threshold default
- Default subido de 0.7 a **0.78**: con e5-small, queries no relacionadas
  caen ~0.65-0.75 — un threshold permisivo provoca falsos positivos.
- Hits relevantes con e5-small suelen quedar ≥ 0.85.
- El threshold es override-able por request.

### Convención E5 obligatoria
- `embed(text)` para passages (lo que se guarda) → prefija `passage: `
- `embedQuery(text)` para queries → prefija `query: `
- Mezclar prefijos rompe el matching cross-lingual. Está encapsulado en
  `lib/embeddings.ts` para que ningún caller pueda equivocarse.

### Producción
- Se mantiene `vector(384)` para que el camino de prod no requiera otra
  migración destructiva.
- Candidato fuerte: Supabase AI (`ai.gte_small`) — también 384D, ejecutable
  desde Edge Functions vía SQL, sin cliente externo.
- Si se elige otro proveedor (OpenAI, Voyage), habrá que migrar el schema
  otra vez. Esa decisión queda para ADR específico al cerrar issue #5.

### Smoke test
- `scripts/smoke/03-http-api.sh` ahora marca filas con `source="smoke-test"`
  y las borra al final, para no contaminar la KB con datos basura que
  hagan match con queries reales (lo que motivó este ADR).

## Métrica de aceptación

Validado: similarity 0.90 entre `"MCP"` (passage corto) y `"¿Qué es el
Modelo de Contexto de Protocolo (MCP)?"` (query expandida en español).
El modelo entiende abreviatura↔expansión y castellano↔inglés del término
técnico, que es el patrón típico del demo.

## Referencias

- Wang et al. 2022 — *Text Embeddings by Weakly-Supervised Contrastive Pre-training* (paper E5)
- MTEB leaderboard — https://huggingface.co/spaces/mteb/leaderboard
- transformers.js — https://huggingface.co/docs/transformers.js
- ADR-001 — HNSW vs IVFFlat (índice asociado)
- ADR-002 — HTTP local vs Edge Functions (consume embeddings)
