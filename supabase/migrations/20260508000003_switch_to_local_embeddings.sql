-- Cambio de modelo de embeddings: text-embedding-3-small (1536D) → multilingual-e5-small (384D).
-- Razón: dev usa transformers.js local (sin API key), schema debe coincidir.
-- Se trunca la tabla porque los vectores 1536 no son convertibles a 384.

SET LOCAL search_path TO public, extensions;

-- Drop dependents
DROP FUNCTION IF EXISTS public.match_knowledge(extensions.vector, float, int, text);
DROP INDEX IF EXISTS public.knowledge_base_embedding_idx;

-- Truncar y recrear columna con dimensión nueva
TRUNCATE TABLE public.knowledge_base;
ALTER TABLE public.knowledge_base
  ALTER COLUMN embedding TYPE extensions.vector(384);

-- Recrear índice HNSW
CREATE INDEX knowledge_base_embedding_idx
  ON public.knowledge_base
  USING hnsw (embedding extensions.vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Recrear función con dimensión 384
CREATE OR REPLACE FUNCTION public.match_knowledge(
  query_embedding extensions.vector(384),
  match_threshold  float  DEFAULT 0.7,
  match_count      int    DEFAULT 5,
  filter_source    text   DEFAULT NULL
)
RETURNS TABLE (
  id         uuid,
  title      text,
  content    text,
  source     text,
  metadata   jsonb,
  similarity float
)
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
  SELECT
    id,
    title,
    content,
    source,
    metadata,
    1 - (embedding <=> query_embedding) AS similarity
  FROM public.knowledge_base
  WHERE
    1 - (embedding <=> query_embedding) > match_threshold
    AND (filter_source IS NULL OR source = filter_source)
  ORDER BY embedding <=> query_embedding
  LIMIT match_count;
$$;
