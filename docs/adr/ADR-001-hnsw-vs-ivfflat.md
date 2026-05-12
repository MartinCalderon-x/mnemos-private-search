# ADR-001: HNSW como índice de búsqueda vectorial en pgvector

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

mnemos necesita búsqueda semántica sobre la tabla `knowledge_base` (embeddings de 1536 dimensiones). pgvector soporta dos tipos de índice: **IVFFlat** y **HNSW**. La elección impacta directamente en velocidad de consulta, precisión (recall) y costo operativo.

## Decisión

Usar **HNSW** (Hierarchical Navigable Small World) con los siguientes parámetros:

```sql
CREATE INDEX knowledge_base_embedding_idx
ON knowledge_base
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

## Alternativa considerada: IVFFlat

```sql
CREATE INDEX ... USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

## Comparación

| Criterio | HNSW | IVFFlat |
|----------|------|---------|
| Recall | ~98% | ~90-95% |
| Latencia p99 | ~5ms | ~15ms |
| Build time | Más lento (1x) | Más rápido |
| Requiere VACUUM | No | Sí (para optimizar) |
| Memoria | Más alto | Más bajo |
| Escala óptima | <10M filas | >10M filas |

## Razones para elegir HNSW

1. **Recall superior sin tuning** — IVFFlat requiere ajustar `lists` según volumen; HNSW da buen recall out-of-the-box.
2. **Sin VACUUM periódico** — IVFFlat degrada con inserts frecuentes hasta que se ejecuta VACUUM. En mnemos guardamos resultados de búsqueda en tiempo real, por lo que inserts son frecuentes.
3. **Escala de mnemos** — La knowledge base personal no superará 1M documentos. HNSW está optimizado para este rango.
4. **Distancia coseno** — Para embeddings de texto, similitud coseno es más apropiada que L2. HNSW soporta `vector_cosine_ops` nativamente.

## Parámetros elegidos

| Parámetro | Valor | Razón |
|-----------|-------|-------|
| `m` | 16 | Balance entre recall y memoria. Rango recomendado: 5-48. |
| `ef_construction` | 64 | Calidad del grafo durante build. Más alto = mejor recall, más tiempo de indexación. |

Para búsqueda, `ef_search` se puede ajustar por query (default: 40).

## Consecuencias

- El índice HNSW se construye una vez y no requiere mantenimiento periódico.
- Si el volumen supera 5M filas, re-evaluar con IVFFlat particionado o pgvector 0.7+ con índices paralelos.
- El `Dockerfile` del backend no necesita configuración extra — pgvector en Supabase ya soporta HNSW desde la versión 0.5.0.

## Referencias

- [pgvector HNSW docs](https://github.com/pgvector/pgvector#hnsw)
- Malkov & Yashunin (2018) — *Efficient and robust approximate nearest neighbor search using HNSW graphs*
- Supabase pgvector guide — vector indexes
