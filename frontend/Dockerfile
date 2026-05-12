# syntax=docker/dockerfile:1.7
# ─── mnemos frontend — TEMPLATE (sin implementación) ─────────────────────
# Copilot debe implementar este Dockerfile siguiendo:
#   · React 18 + Vite + Tailwind
#   · Variables VITE_* se inlinea al bundle al hacer vite build → ARG/ENV
#   · Servido como static con Nginx (necesita SPA fallback + envsubst sobre PORT)
#
# Build args esperados:
#   · VITE_SUPABASE_URL
#   · VITE_SUPABASE_PUBLISHABLE_KEY
#   · VITE_BACKEND_URL
#
# Estructura esperada:
#   · Stage 1 builder:  npm ci + npm run build → dist/
#   · Stage 2 nginx:    COPY dist/ + nginx.conf con SPA try_files
#   · CMD ["nginx", "-g", "daemon off;"]
