# ADR-009: Synthesis con LLM judge y fallback automático

**Fecha:** 2026-05-09
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

El flujo original del agente decidía RAG vs Web por un único criterio:
similitud coseno > threshold. Si el match existía, sintetizaba con ese
contexto y devolvía el resultado.

En la práctica esto produce dos clases de fallas:

1. **Falso positivo de similarity**: una fila irrelevante puede caer
   por encima del threshold (ej: una entrada corta de "smoke / test"
   matcheaba 0.76 contra una pregunta sobre pgvector). El usuario veía
   un "Lo siento, no encontré información relevante" generado por el
   LLM, pero como la lógica ya decidió RAG, no había fallback a web.

2. **Match alto pero contenido fuera de tema**: similarity 0.92 entre
   dos preguntas con palabras compartidas, pero el contenido guardado
   no responde la nueva pregunta. Mismo síntoma: respuesta basura sin
   reintento.

El threshold solo no alcanza. La similitud mide cercanía geométrica
de embeddings — no si el contenido **responde** la pregunta.

## Decisión

`synthesize()` ahora devuelve un objeto estructurado:

```typescript
interface SynthesizeResult {
  answer: string;
  sufficient: boolean;
}
```

El system prompt instruye al LLM a clasificar la suficiencia del
contexto y embebe la decisión en tags XML:

```
<sufficient>true|false</sufficient>
<answer>
[respuesta]
</answer>
```

El parser tolera fallas: si el LLM no respeta el formato, hay un
fallback heurístico (markers como "no contiene información",
"contexto insuficiente").

El cliente (`useChat.ts`) usa el flag para enrutar:

```
RAG hit → synthesize(rag)
        → sufficient=true  → mostrar respuesta + badge 🧠
        → sufficient=false → web search → synthesize(web)
                          → mostrar respuesta + badge 🌐 + nota
                            "KB no respondía → web"
```

El botón Guardar se deshabilita cuando `sufficient=false` para evitar
contaminar la KB con respuestas degeneradas.

## Calibración del prompt

El primer borrador del prompt era demasiado estricto:

> "sufficient=true si el contexto contiene información que responde
>  la pregunta de forma **directa y útil**"

Con esto, Claude marcaba como insuficiente contenidos perfectamente
válidos por considerarlos "informales", "borradores" o "no oficiales".
Caso real: una respuesta sobre MCP guardada en la KB matcheaba 0.94
y fue rechazada porque "no parece documentación oficial".

El prompt actual desacopla **suficiencia temática** de **autoridad
académica**:

> "sufficient=true si el contexto trata el tema de la pregunta y
>  permite dar una respuesta razonable, aunque sea breve o no
>  exhaustiva. NO marques insufficient porque el contexto sea informal,
>  breve, o no 'oficial'."

Validado: misma fila + misma pregunta → ahora sufficient=true,
respuesta real generada.

## Alternativas evaluadas

### A. Solo subir el threshold
Probado: 0.7 → 0.78. Reduce falsos positivos del primer tipo (basura
con similarity baja-media), pero no resuelve el segundo (match alto +
contenido fuera de tema). Threshold sigue calibrado a 0.78 como
defensa de baja-altura.

### B. Heurística regex sobre la respuesta
Buscar markers tipo "no encontré", "contexto insuficiente". Frágil:
depende del idioma, del modelo, y de variaciones en el wording. Se
mantiene como fallback del parser cuando el LLM no respeta los tags.

### C. Re-ranker dedicado (ej. Cohere rerank o cross-encoder)
Más preciso pero agrega un componente nuevo, otra API key (Cohere) o
un modelo local extra (~100MB de cross-encoder). Por ahora el judge
LLM es "good enough" porque el LLM ya está en el flujo.

### D. Fundir contextos RAG + Web siempre
Más caro (siempre hace web), pero nunca falla por falta de info.
Descartado por costo y latencia. Podría ser una opción configurable
("modo paranoico") en el futuro.

### E. Function calling / structured output del SDK
Claude soporta tool use con respuestas estructuradas. Más limpio que
parsear tags, pero acopla a un proveedor específico. Los tags XML
funcionan con cualquier modelo de OpenRouter sin cambios.

## Consecuencias

### En la API
- `POST /api/synthesize` ahora retorna `{ answer, sufficient }` en lugar
  de `{ answer }`. Cambio breaking — clientes legacy fallarían silently
  asumiendo `answer` siempre (no devolvemos error). Los únicos clientes
  son nuestro propio frontend + smoke tests, ya actualizados.

### En el frontend
- `ChatMessage` tiene campos nuevos: `sufficient`, `fellbackToWeb`.
- Botón Guardar deshabilitado en respuestas con `sufficient=false`.
- Si hubo fallback automático, se muestra el subtítulo "KB no
  respondía → web" para que el usuario entienda el path.

### En el flujo
- Una query con RAG hit insuficiente cuesta **dos llamadas a Claude**
  en vez de una. Trade-off aceptable para evitar respuestas basura.
- Latencia percibida: +1-2 segundos en el caso de fallback.

### En testing
- Smoke 03 valida que el endpoint responde 200; no valida la calidad
  de la judge call (eso es responsabilidad de tests de regresión que
  pueden venir como integration tests en issue #14).

## Métricas validadas

Pre-fix:
- "¿Qué es MCP?" save → "¿Qué es MCP?" query → similarity 0.94 +
  Claude responde "borrador no oficial, contexto insuficiente" → falso
  insufficient → flujo bloqueado.

Post-fix (prompt calibrado):
- Mismo escenario → similarity 0.94 + sufficient=true + respuesta
  útil con bullets formateados → flujo correcto, badge 🧠.

## Referencias

- ADR-008 — embeddings local (genera los hits que este ADR clasifica)
- `backend/src/lib/openrouter.ts` — implementación del judge
- `frontend/src/hooks/useChat.ts` — orquestación del fallback
- Anthropic — *Claude prompt engineering: structured output with XML tags*
