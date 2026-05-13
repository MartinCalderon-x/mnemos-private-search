# Plan de Deployment — mnemos

## Dos rutas: local → producción

```
RUTA 1 — Local (5 min)           RUTA 2 — Cloud Run (one-time setup ~30 min)
──────────────────────           ──────────────────────────────────────────
Para validar y desarrollar       Para compartir y producción
docker compose up -d             ./scripts/setup-gcp-wif.sh + workflow_dispatch
                                 → <your-domain>
```

---

## Ruta 1: Local con Docker Compose

### Prerequisitos
- Docker Desktop instalado
- Cuenta Supabase (free tier OK)
- API key OpenRouter

### Pasos

```bash
git clone https://github.com/MartinCalderon-x/mnemos
cd mnemos
cp .env.example .env
# Completar SUPABASE_URL, SUPABASE_SECRET_KEY, OPENROUTER_API_KEY, etc.
docker compose up -d searxng              # SearxNG en :8080
cd backend && npm install && npm run build && npm start   # API en :3000
cd ../frontend && npm install && npm run dev              # UI en :5173
```

---

## Ruta 2: Cloud Run con dominio custom

Setup completo end-to-end validado en `<your-domain>`. Tiempo total: ~30-45 min
para la primera vez, ~5 min para deploys posteriores.

### One-time setup (orden importa)

#### 1. GCP project + WIF

```bash
# Apuntar gcloud al project destino
gcloud config set project <tu-gcp-project>

# Crear WIF para que GitHub Actions impersone una SA sin keys (ADR-012)
GITHUB_REPOS="usuario/mnemos" ./scripts/setup-gcp-wif.sh --write-env
# → imprime GCP_WIF_PROVIDER y GCP_WIF_SERVICE_ACCOUNT
```

#### 2. Artifact Registry repo (manual, una vez)

⚠️ **Gotcha:** la SA `mnemos-deploy` tiene `roles/artifactregistry.writer`
(push), NO `admin` (create). El workflow no puede crear el repo. Hay que
crearlo manualmente con tu cuenta de Owner:

```bash
gcloud artifacts repositories create mnemos \
  --repository-format=docker \
  --location=us-central1 \
  --description="Mnemos container images"
```

#### 3. GitHub Secrets

```bash
./scripts/setup-github-secrets.sh        # sube 11 secrets + GCP_PROJECT_ID variable
./scripts/setup-copilot-mcp-secrets.sh   # solo si vas a usar Copilot Coding Agent
```

⚠️ **Gotcha histórico:** versiones anteriores del script usaban
`echo "$val" | gh secret set --body -` (stdin). El stdin truncaba a 1 char,
causando "Invalid audience" en WIF auth. Fix: ahora usan `--body "$val"`
directo. Si re-uploadeás manualmente, **siempre** usar `--body "value"`,
no pipe.

#### 4. Supabase migrations

Aplicar el schema canónico (no prefijado) una vez en el proyecto Supabase:

```bash
supabase link --project-ref <tu-project-ref>
supabase db push
```

### Deploy automatizado

```bash
gh workflow run deploy.yml --repo usuario/mnemos --ref main \
  -f prefix=""                              # → "prod" services
  -f run_migration=false \                   # ya está aplicado
  -f backend_url="https://api.tudominio.com"
```

El workflow:
1. Buildea 3 imágenes en paralelo (backend, frontend, searxng)
2. Pushea a Artifact Registry (<your-gcp-project>/mnemos)
3. Deploya 3 servicios a Cloud Run con WIF auth
4. Reporta URLs en el step summary

⚠️ **Gotcha — backend OOM:** El modelo `multilingual-e5-small` (ADR-008)
necesita ~1.8GB RAM peak al primer query. El workflow ya pasa `--memory=2Gi
--cpu=2 --timeout=120`. Si bajás esos valores y verás SIGKILL en logs.
Ver ADR-014.

### Post-deploy hardening (manual, una vez)

#### Bloquear SearxNG (ADR-016)

```bash
# Quitar acceso público
gcloud run services remove-iam-policy-binding mnemos-searxng-prod \
  --region=us-central1 \
  --member="allUsers" --role="roles/run.invoker"

# Permitir solo al compute SA del backend
gcloud run services add-iam-policy-binding mnemos-searxng-prod \
  --region=us-central1 \
  --member="serviceAccount:<project-number>-compute@developer.gserviceaccount.com" \
  --role="roles/run.invoker"
```

#### Esconder URLs `.run.app`

```bash
# El backend y frontend solo serán accesibles vía dominio custom
gcloud run services update mnemos-frontend-prod --region=us-central1 --no-default-url
gcloud run services update mnemos-backend-prod  --region=us-central1 --no-default-url
```

### Domain mapping + DNS

```bash
# Crear los mappings en GCP
gcloud beta run domain-mappings create \
  --service=mnemos-frontend-prod --domain=tudominio.com --region=us-central1
gcloud beta run domain-mappings create \
  --service=mnemos-backend-prod --domain=api.tudominio.com --region=us-central1

# GCP devuelve los DNS records exactos que hay que poner en tu registrar.
```

#### Records DNS típicos (registrar genérico)

**Para `tudominio.com` → frontend:**

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A | @ | 216.239.32.21 | 1h |
| A | @ | 216.239.34.21 | 1h |
| A | @ | 216.239.36.21 | 1h |
| A | @ | 216.239.38.21 | 1h |
| AAAA | @ | 2001:4860:4802:32::15 | 1h |
| AAAA | @ | 2001:4860:4802:34::15 | 1h |
| AAAA | @ | 2001:4860:4802:36::15 | 1h |
| AAAA | @ | 2001:4860:4802:38::15 | 1h |

**Para `api.tudominio.com` → backend:**

| Type | Host | Value | TTL |
|------|------|-------|-----|
| CNAME | api | ghs.googlehosted.com. | 1h |

#### Verificación

```bash
# DNS propagation
dig +short @8.8.8.8 A tudominio.com               # esperar 4 IPs Google
dig +short @8.8.8.8 CNAME api.tudominio.com       # esperar ghs.googlehosted.com.

# SSL cert provisioning status (Google auto-emite ~15 min después de DNS OK)
gcloud beta run domain-mappings describe --domain=tudominio.com \
  --region=us-central1 \
  --format='value(status.conditions[].type,status.conditions[].status)'

# End-to-end
curl https://tudominio.com         # frontend HTML
curl https://api.tudominio.com/health  # {"status":"ok"}
```

### Cleanup operacional

#### Después de un demo aislado por prefix:

```bash
./scripts/cleanup-demo.sh demo_xxxxxxxx_
# Drop Supabase table+function + Cloud Run services + Secret Manager secrets matching
```

#### Tear down completo:

```bash
# Cloud Run services
gcloud run services delete mnemos-{backend,frontend,searxng}-prod --region=us-central1

# Domain mappings
gcloud beta run domain-mappings delete --domain=tudominio.com --region=us-central1
gcloud beta run domain-mappings delete --domain=api.tudominio.com --region=us-central1

# Artifact Registry images (opcional, conviene mantener para rollback)
# gcloud artifacts repositories delete mnemos --location=us-central1
```

---

## Lecciones aprendidas durante el primer deploy a `<your-domain>`

Cosas que costaron tiempo y que están documentadas para no repetirlas:

| Síntoma | Causa real | Fix |
|---------|------------|-----|
| `gh secret set` parecía OK pero WIF fallaba con "Invalid audience" | `gh secret set --body -` (stdin) truncaba a 1 char | Usar `--body "$value"` directo, sin pipe |
| Backend crashloop con SIGKILL al primer query | OOM cargando ONNX model con 512Mi RAM | 2Gi/2CPU (ADR-014) |
| Workflow falla en `gcloud artifacts repositories create` | SA `mnemos-deploy` no tiene `roles/artifactregistry.admin` | Crear AR repo manualmente con Owner una vez |
| Container crash con "Node.js 20 detected without native WebSocket" | `@supabase/supabase-js` v2 necesita Node 22+ para WebSocket nativo | `FROM node:22-slim` (no Alpine — onnxruntime necesita glibc) |
| SearxNG UI accesible al público en la `.run.app` URL | Default `--allow-unauthenticated` | Remove `allUsers` + ID token auth (ADR-016) |
| Frontend devolvía error CORS o 404 en `/api/*` | URLs relativas sin saber dónde está el backend | `VITE_BACKEND_URL` build-arg (ADR-015) |
| Servicios con nombres `mnemos-*-demo-<runid>` cuando se esperaba `prod` | Workflow logic: `workflow_dispatch` con prefix vacío → auto demo prefix | Esperado; pasar input explícito o trigger via push |
| `<your-domain>` resolvía a IPs de GoDaddy parking | WebsiteBuilder Site activado en GoDaddy | Borrar el record + las A heredadas |

---

## Referencias

- ADR-012 — Workload Identity Federation
- ADR-014 — Backend resource sizing for transformers.js
- ADR-015 — Frontend cross-origin vía VITE_BACKEND_URL
- ADR-016 — SearxNG private + ID token auth
- `scripts/setup-gcp-wif.sh`
- `scripts/setup-github-secrets.sh`
- `.github/workflows/deploy.yml`
