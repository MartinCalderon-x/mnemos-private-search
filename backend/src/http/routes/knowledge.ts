import { Hono } from 'hono';
import { supabase } from '../../lib/supabase.js';
import { dbNames } from '../../lib/env.js';

const app = new Hono();

interface KbStatsResponse {
  table: string;
  row_count: number;
  last_inserted_at: string | null;
}

app.get('/stats', async (c) => {
  try {
    const { data, count, error } = await supabase
      .from(dbNames.knowledgeBaseTable)
      .select('created_at', { count: 'exact' });

    if (error) {
      return c.json({ error: error.message }, 500);
    }

    let lastInsertedAt: string | null = null;
    if (data && data.length > 0) {
      // Encontrar el máximo created_at
      lastInsertedAt = data.reduce((max: string, row: any) => {
        const rowTime = new Date(row.created_at).getTime();
        const maxTime = new Date(max).getTime();
        return rowTime > maxTime ? row.created_at : max;
      }, data[0].created_at);
    }

    const response: KbStatsResponse = {
      table: dbNames.knowledgeBaseTable,
      row_count: count ?? 0,
      last_inserted_at: lastInsertedAt,
    };

    return c.json(response);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return c.json({ error: message }, 500);
  }
});

export default app;
