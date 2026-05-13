# ADR-004: Separación entre modo Local y modo Profesional

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

mnemos es a la vez un producto demostrable Y un blueprint clonable. Para que sirva en ambos casos, debe ofrecer dos modos de operación con costo y complejidad muy distintos pero **con la misma base de código**.

Sin esta decisión, el repo se llenaría de ifs por entorno, configs duplicadas y deuda silenciosa.

## Decisión

Definir **dos modos** estrictamente separados a nivel de configuración pero con código idéntico:

| Aspecto | Modo Local | Modo Profesional |
|---------|-----------|------------------|
| Tiempo setup | <5 min | ~20 min |
| Audiencia | Dev probando, hackeando | Demo en vivo, URL pública |
| SearxNG | Docker container | Cloud Run service |
| Backend | `npm run dev` (Hono :3000) | Cloud Run service |
| Frontend | `npm run dev` (Vite :5173) | Cloud Run con Nginx |
| Knowledge DB | Supabase (mismo proyecto) | Supabase (mismo proyecto) |
| Auth/Secrets | `.env` local | GCP Secret Manager |
| LLM | OpenRouter | OpenRouter |
| Tracing | Console logs | Cloud Logging |
| Costo | $0 | ~$2-5/mes |

## Lo que comparten ambos modos

- Toda la lógica en `backend/src/tools/*` y `backend/src/lib/*`
- Toda la UI en `frontend/src/`
- El mismo `.env` (Local lee directo; Pro lo carga a Secret Manager)
- Las mismas migraciones y la misma instancia Supabase
- El mismo schema de tipos compartido entre frontend y backend

## Lo que cambia

- **Adapter de transporte**: Local usa `http/server.ts` (Hono). Pro usa `supabase/functions/*` (Edge Functions Deno).
- **URLs en frontend**: Local apunta a `/api/*` (proxy Vite). Pro apunta a `${VITE_SUPABASE_URL}/functions/v1/*`.
- **Imágenes Docker**: Pro construye y pushea a Artifact Registry. Local solo levanta SearxNG.

## Criterios de promoción Local → Profesional

Antes de promover a profesional, todos los siguientes deben pasar en Local:

1. Issue #2 cerrado: migraciones aplicadas, tabla `knowledge_base` existe
2. Issue #3 cerrado: SearxNG responde JSON en `:8080`
3. Issue #1 cerrado: HTTP server responde 200 en `:3000` para los 4 endpoints
4. Issue #4 cerrado: UI funcional end-to-end con thinking steps
5. Una conversación completa de demo guardada en knowledge_base
6. Backend `npm run build` sin warnings ni errores
7. Frontend `npm run build` sin warnings ni errores

## Comandos canónicos

### Modo Local
```bash
docker compose up -d
cd backend && npm run dev    # terminal 1 — HTTP + MCP
cd frontend && npm run dev   # terminal 2 — UI
```

### Modo Profesional
```bash
./scripts/gcp-setup.sh <PROJECT_ID>
git push origin main          # GitHub Actions despliega
```

## Anti-patrones explícitamente prohibidos

- ❌ `if (process.env.NODE_ENV === 'production')` en lógica de negocio
- ❌ Configs duplicadas tipo `config.local.ts` y `config.prod.ts`
- ❌ Lógica de "feature flag por entorno" — los modos comparten features
- ❌ Hacks como "mock SearxNG en local pero real en prod" — siempre se usa SearxNG real

## Consecuencias

- El blueprint clonado puede correr en Local sin tocar nada GCP
- Promover a Profesional es un cambio de configuración, no de código
- Se evita el síndrome "funciona en local, rompe en prod" porque el código ejecutado es idéntico
- ADR-002 (HTTP local vs Edge Functions) materializa la separación de adapters

## Referencias

- ADR-002 — HTTP local vs Edge Functions (decisión de adapters)
- ADR-005 — Estrategia de testing (qué se testea en cada modo)
- `docs/plans/local-mode.md` y `docs/plans/professional-mode.md`
