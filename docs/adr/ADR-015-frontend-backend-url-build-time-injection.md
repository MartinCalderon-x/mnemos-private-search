# ADR-015: Frontend → backend URL vía build-time inject (no nginx proxy)

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

Frontend y backend son **dos Cloud Run services separados** con URLs
distintas. El frontend (React + Vite servido vía Nginx static) necesita saber
dónde está el backend para hacer fetch a `/api/search/semantic`, etc.

En local dev, ambos viven en `localhost` con puertos distintos y CORS abierto
para `localhost:5173` → funciona con URLs absolutas o relativas. En Cloud Run
con dominio público (`<your-domain>` → frontend, `api.<your-domain>` → backend) hay
que decidir cómo el frontend resuelve el backend URL.

## Decisión

**Build-time injection de `VITE_BACKEND_URL`** como build-arg del
`frontend/Dockerfile`. Vite inlinea el valor en el bundle al hacer `vite build`.
El frontend hace fetch cross-origin a `https://api.<your-domain>/...` y el
backend tiene CORS configurado para aceptar `https://<your-domain>`.

### Implementación

**`frontend/src/lib/api.ts`** — fallback inteligente:
```ts
const BACKEND = (import.meta.env.VITE_BACKEND_URL ?? '').replace(/\/$/, '');

async function postJson<T>(path: string, body: unknown): Promise<T> {
  const url = BACKEND ? `${BACKEND}${path}` : path;
  // ...
}
```

- Si `VITE_BACKEND_URL` viene del build → absolute (`https://api.<your-domain>/api/...`)
- Si no → relative (`/api/...`) — funciona en dev con Vite proxy o same-origin

**`frontend/Dockerfile`** — recibe el arg:
```dockerfile
ARG VITE_BACKEND_URL
ENV VITE_BACKEND_URL=$VITE_BACKEND_URL
# ... npm run build inlinea el valor en dist/
```

**`.github/workflows/deploy.yml`** — pasa el valor:
```yaml
inputs:
  backend_url:
    default: 'https://api.<your-domain>'
# ...
BUILD_ARGS="--build-arg VITE_BACKEND_URL=${{ inputs.backend_url }}"
```

**`backend/src/http/server.ts`** — CORS permite el dominio público + cualquier
`.run.app` (para que el frontend en su URL Cloud Run también funcione antes
del DNS):
```ts
origin: (origin) => {
  if (!origin) return origin;
  if (allowedOrigins.includes(origin)) return origin;
  if (origin.endsWith('.run.app')) return origin;
  return null;
}
```

## Alternativas evaluadas

| Opción | Pros | Contras | Decisión |
|--------|------|---------|----------|
| **Build-time inject** (elegida) | Simple; el bundle es estático y CDN-cacheable; URL backend explícito en el código | Cambiar URL backend requiere rebuild del frontend | ✅ |
| **Nginx proxy** `/api/*` → backend | Same-origin (sin CORS); frontend usa URLs relativas | nginx.conf necesita el backend URL inyectado vía envsubst; chain extra de hops; el backend tiene que aceptar tráfico del frontend service identity | ❌ |
| **Runtime config endpoint** (`/config.json` servido por nginx con el URL) | Cambiar URL sin rebuild | Extra request en boot; complicación arquitectónica; el JSON tiene que ser inyectado en el container vía envsubst igual que el caso anterior | ❌ |
| **Backend embebido en el container del frontend** | Same-origin trivial | Rompe el principio "1 servicio Cloud Run = 1 responsabilidad"; deploy acoplado | ❌ |

## Trade-off principal

**Build-time inject acopla el frontend a un backend URL específico**. Si en el
futuro el backend cambia de URL (ej. multi-region, blue-green), hay que
rebuildear el frontend. Por hoy aceptable: el dominio es estable (`<your-domain>`)
y los re-builds son rápidos (~2 min en GitHub Actions).

## Consecuencias

- **CORS importa**: el backend acepta `https://<your-domain>` + `https://www.<your-domain>`
  + `*.run.app`. Cualquier dominio nuevo requiere actualizar `CORS_ORIGINS` env
  o el array hardcoded en `server.ts`.
- **El frontend Cloud Run URL sigue funcionando** mientras el dominio propaga DNS:
  `https://mnemos-frontend-XXX.run.app` resuelve al mismo backend porque sus
  llamadas son a `api.<your-domain>` absolute.
- **Cambiar de dominio** = re-trigger workflow con `-f backend_url=https://nuevo.api`.

## Referencias

- `frontend/src/lib/api.ts`
- `frontend/Dockerfile`
- `backend/src/http/server.ts` (CORS config)
- `.github/workflows/deploy.yml` (inputs.backend_url)
