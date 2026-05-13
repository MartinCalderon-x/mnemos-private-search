import { z } from 'zod';

const envSchema = z.object({
  TABLE_PREFIX: z.string().optional().default(''),
  SUPABASE_URL: z.string().url(),
  SUPABASE_SECRET_KEY: z.string().min(1),
  OPENROUTER_API_KEY: z.string().optional().default(''),
  SEARXNG_URL: z.string().url().optional().default('http://localhost:8080'),
  PORT: z.coerce.number().optional().default(3000),
});

export const env = envSchema.parse({
  TABLE_PREFIX: process.env.TABLE_PREFIX,
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY,
  OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY,
  SEARXNG_URL: process.env.SEARXNG_URL,
  PORT: process.env.PORT,
});

export const dbNames = {
  knowledgeBaseTable: `${env.TABLE_PREFIX}knowledge_base`,
  matchKnowledgeFn: `${env.TABLE_PREFIX}match_knowledge`,
} as const;
