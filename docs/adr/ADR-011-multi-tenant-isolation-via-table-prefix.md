# ADR-011: Aislamiento multi-tenant del demo vía TABLE_PREFIX

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

El demo de mnemos corre en distintas modalidades sobre el **mismo proyecto Supabase**:

1. **Dev local** — el presenter usa la base de conocimiento real con la fila de
   "MCP" guardada manualmente y otros datos persistidos.
2. **Coding Agent runs** — cada vez que se asigna un issue al Copilot Coding
   Agent, este corre en una sandbox y reconstruye el sistema desde cero.
3. **Demos en vivo / dry-runs** — múltiples ejecuciones con datos de test que
   no deben contaminar la KB real.

Si los tres comparten `public.knowledge_base`, los demos contaminan los datos
del presenter y los runs paralelos del Coding Agent se pisan.

Las alternativas evaluadas:

| Opción | Aislamiento | Costo | Operacional |
|--------|-------------|-------|-------------|
| Proyecto Supabase nuevo por demo | Total | Alto ($25+/proyecto/mes) | Provisioning lento (minutos) |
| Schema PostgreSQL por demo | Bueno | $0 | supabase-js requiere config extra |
| **Prefix por nombre de tabla/función** | Bueno | $0 | Drop-in en el código existente |
| Branch databases (Supabase preview) | Bueno | Beta, costo variable | Inmaduro al momento de la decisión |

## Decisión

Usar **prefijo configurable por env var** (`TABLE_PREFIX`) que se concatena a
todos los nombres de tablas y funciones específicas del demo. Default vacío =
comportamiento canónico (sin prefix).

```
TABLE_PREFIX=""                       → public.knowledge_base, public.match_knowledge
TABLE_PREFIX="demo_a3f9b2c1_"         → public.demo_a3f9b2c1_knowledge_base, public.demo_a3f9b2c1_match_knowledge
```

### Forma del prefijo

`demo_<id>_` donde `<id>` son 8 chars derivados de:

- **CI / Coding Agent:** `GITHUB_RUN_ID` truncado, opcionalmente combinado con
  un nonce aleatorio
- **Local debugging:** elegido manualmente (ej: `demo_test_001_`)

El prefijo debe cumplir `^[a-z0-9_]+_$` (lowercase alfanumérico + underscore,
termina en `_`). Esta restricción está validada en
`scripts/render-demo-migration.sh`.

## Implementación

### Backend (`backend/src/lib/env.ts`)

```ts
export const env = {
  // ... otros vars
  TABLE_PREFIX: process.env.TABLE_PREFIX ?? '',
};

export const dbNames = {
  knowledgeBaseTable: `${env.TABLE_PREFIX}knowledge_base`,
  matchKnowledgeFn:   `${env.TABLE_PREFIX}match_knowledge`,
} as const;
```

Los tools (`semanticSearch`, `saveToKnowledge`) importan `dbNames` y consumen
el nombre resuelto en lugar de literales. **Sin prefix, el comportamiento es
idéntico al anterior** (backwards compatible).

### Template SQL (`supabase/templates/demo-migration.sql.template`)

Replica del schema canónico con `{{PREFIX}}` insertado donde corresponde:

```sql
CREATE TABLE IF NOT EXISTS public.{{PREFIX}}knowledge_base ( ... );
CREATE INDEX IF NOT EXISTS {{PREFIX}}knowledge_base_embedding_idx ...;
CREATE OR REPLACE FUNCTION public.{{PREFIX}}match_knowledge ( ... );
```

### Scripts en `scripts/`

| Script | Rol | Requiere |
|--------|-----|----------|
| `render-demo-migration.sh <prefix>` | Substituye `{{PREFIX}}` e imprime SQL a stdout | Nada — determinístico |
| `apply-demo-migration.sh <prefix>` | Aplica el render via Supabase Management API | `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` |
| `cleanup-demo.sh <prefix>` | Drop tabla + función + Cloud Run services + Secret Manager secrets matching | Mismos + `GCP_PROJECT_ID` + `gcloud` |

Los tres son **idempotentes** y **safe re-run**.

## Validación

Test end-to-end ejecutado el 2026-05-12:

1. Apply prefix `demo_test_001_` → tabla + función creadas
2. Backend con `TABLE_PREFIX=demo_test_001_` → save fila (id `e52ba01c`)
3. Backend con prefix → search query similar → encuentra la fila (sim 0.857)
4. Backend **sin** prefix → misma búsqueda → NO encuentra la fila demo, solo
   la canónica de "MCP" (id `34552a9b`)
5. Cleanup → drop tabla + función
6. Backend con prefix post-cleanup → falla con "Could not find the function
   public.demo_test_001_match_knowledge" (confirma drop real)

**Aislamiento perfecto:** dos datasets viven en el mismo proyecto Supabase sin
ver datos del otro.

## Alcance

El prefijo aplica a recursos que el demo crea durante su run:

- ✅ Tabla `knowledge_base` y función `match_knowledge` (Supabase)
- ✅ Cloud Run services (`mnemos-{backend,frontend,searxng}-<prefix>`)
- ✅ Secret Manager secrets (ver `cleanup-demo.sh`)

**No** aplica a recursos compartidos del proyecto (extensiones de Postgres,
buckets de Storage compartidos, etc).

## Consecuencias

- **Local dev sigue idéntico** al anterior (TABLE_PREFIX vacío).
- **Cleanup es operacionalmente crítico** — sin él, las tablas demo se
  acumulan. La política elegida es manual (`scripts/cleanup-demo.sh`); se
  documenta en `BLUEPRINT.md`.
- **Búsquedas globales en Supabase Studio** ahora muestran tablas
  `demo_*_knowledge_base` además de la canónica. Es visualmente obvio cuáles
  son ephemeral.
- **El backend cachea el nombre al inicio** — si cambiás `TABLE_PREFIX` hay
  que reiniciar el proceso.

## Referencias

- ADR-001 (HNSW index) — el prefix preserva el mismo tipo de índice
- ADR-008 (Embeddings 384D) — el schema demo es idéntico al canónico
- `scripts/render-demo-migration.sh`
- `supabase/templates/demo-migration.sql.template`
