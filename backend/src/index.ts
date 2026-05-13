import { serve } from '@hono/node-server';
import { createApp } from './http/server.js';
import { env } from './lib/env.js';

const app = createApp();

console.log(`▸ Backend HTTP server starting on port ${env.PORT}...`);

serve({
  fetch: app.fetch,
  port: env.PORT,
});

console.log(`✓ Server listening on http://localhost:${env.PORT}`);
