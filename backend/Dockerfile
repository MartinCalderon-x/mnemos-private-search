# syntax=docker/dockerfile:1.7
# ─── mnemos backend — TEMPLATE (sin implementación) ──────────────────────
# Copilot debe implementar este Dockerfile siguiendo:
#   · ADR-002: HTTP server local (Hono) — entry dist/index.js
#   · ADR-010: dual entry points HTTP + MCP stdio
#   · docs/flows/agent-decision-flow.md
#
# Restricciones conocidas (no Alpine):
#   · @xenova/transformers usa onnxruntime-node que requiere glibc
#   · @supabase/supabase-js v2 requiere Node 22+ por WebSocket nativo
#   → base recomendada: node:22-slim (Debian)
#
# Estructura esperada:
#   · Stage 1 builder:  npm ci + tsc → dist/
#   · Stage 2 runtime:  npm ci --omit=dev + COPY dist/ + EXPOSE 3000
#   · CMD ["node", "dist/index.js"]
#
# Validador: scripts/smoke/03-http-api.sh debe pasar contra el container.
