-- pgvector vive en el schema "extensions" en Supabase moderno.
-- Lo agregamos al search_path para que `vector`, `<=>`, `vector_cosine_ops`, etc.
-- sean resolubles sin calificar.
SET LOCAL search_path TO public, extensions;

-- Tabla principal del RAG privado
-- embedding: 1536D compatible con OpenAI text-embedding-3-small y Voyage AI
CREATE TABLE IF NOT EXISTS public.knowledge_base (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT NOT NULL,
  content    TEXT NOT NULL,
  source     TEXT,                    -- URL, "manual", nombre de archivo, etc.
  metadata   JSONB DEFAULT '{}',      -- tags, categoría, idioma, etc.
  embedding  extensions.vector(1536),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Índice HNSW para búsqueda por similitud coseno
-- HNSW: mejor recall y velocidad que IVFFlat para tablas < 1M filas
CREATE INDEX IF NOT EXISTS knowledge_base_embedding_idx
  ON public.knowledge_base
  USING hnsw (embedding extensions.vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Índice en source para filtros rápidos por origen
CREATE INDEX IF NOT EXISTS knowledge_base_source_idx
  ON public.knowledge_base (source);

-- Índice GIN para búsqueda en metadata JSONB
CREATE INDEX IF NOT EXISTS knowledge_base_metadata_idx
  ON public.knowledge_base USING gin (metadata);

-- Trigger para mantener updated_at sincronizado
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS knowledge_base_updated_at ON public.knowledge_base;
CREATE TRIGGER knowledge_base_updated_at
  BEFORE UPDATE ON public.knowledge_base
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Función de búsqueda semántica
-- Devuelve filas ordenadas por similitud coseno descendente
-- match_threshold: 0.0 a 1.0 (recomendado: 0.7)
-- match_count: máximo de resultados
CREATE OR REPLACE FUNCTION public.match_knowledge(
  query_embedding extensions.vector(1536),
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

-- RLS: por defecto sin políticas — backend usa SECRET_KEY (bypass).
-- Frontend (publishable) no puede leer hasta que se agregue una política.
ALTER TABLE public.knowledge_base ENABLE ROW LEVEL SECURITY;
