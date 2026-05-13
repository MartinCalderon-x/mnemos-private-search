# Plan: Modo Profesional

> Plan operativo para correr mnemos en Google Cloud Run. Tiempo objetivo: **~20 minutos** desde cero.

---

## Para qué sirve el modo Profesional

- Demo en vivo en conferencia con URL pública
- Compartir la app con colegas o usuarios
- Mostrar capacidades reales de scaling
- Referencia para otros proyectos del ecosistema ArX

---

## Prerequisitos del usuario

| Requisito | Cómo conseguirlo |
|-----------|-----------------|
| Cuenta GCP con billing habilitado | https://console.cloud.google.com → New Project + Link Billing |
| `gcloud` CLI instalado | https://cloud.google.com/sdk/docs/install |
| Repo forkeado en GitHub | Botón "Fork" en https://github.com/MartinCalderon-x/mnemos |
| Modo Local validado | Ver `docs/plans/local-mode.md` — criterios de done |
| `.env` con todas las credenciales | Mismo `.env` que modo Local |

---

## Arquitectura resultante

```
                    Internet
                       │
                       ▼
            ┌──────────────────────┐
            │  Cloud Run Frontend   │  https://mnemos-frontend-xxx.run.app
            │  (Nginx + Vite build) │  Pública, allow-unauthenticated
            └──────────┬────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  Supabase Edge        │  https://xxx.supabase.co/functions/v1/
            │  Functions            │
            └──────┬───────┬────────┘
                   │       │
        ┌──────────┘       └──────────┐
        ▼                              ▼
┌────────────────┐          ┌──────────────────────┐
│  Supabase DB   │          │  Cloud Run SearxNG   │  Privada (allUsers ❌)
│  (pgvector)    │          │  Solo desde backend  │
└────────────────┘          └──────────────────────┘

GCP Secret Manager: SUPABASE_*, OPENROUTER_API_KEY, SEARXNG_SECRET
```

---

## Setup paso a paso

### Paso 1 — Validar modo Local primero (variable)

NO arrancar producción sin haber pasado todos los criterios de done de `docs/plans/local-mode.md`. Esto es non-negotiable — evita debugging en vivo durante el demo.

### Paso 2 — Setup GCP automatizado (5 min)

```bash
./scripts/gcp-setup.sh <PROJECT_ID> <GITHUB_REPO>
# Ejemplo: ./scripts/gcp-setup.sh mnemos-prod MartinCalderon-x/mnemos
```

El script automatiza:
1. Habilitar APIs (Cloud Run, Artifact Registry, Secret Manager, IAM)
2. Crear Artifact Registry repo `mnemos`
3. Crear service account `mnemos-deploy`
4. Asignar permisos mínimos (run.developer, secretmanager.secretAccessor, etc.)
5. Configurar Workload Identity Federation para GitHub Actions
6. Crear secrets en Secret Manager desde `.env` (excluyendo `VITE_*`)
7. Imprimir los GitHub Secrets a configurar

### Paso 3 — Configurar GitHub Secrets (2 min)

El script imprime los valores. Copiarlos a:

GitHub repo → Settings → Secrets and variables → Actions → New secret:

| Secret | Valor |
|--------|-------|
| `GCP_PROJECT_ID` | El project ID |
| `GCP_REGION` | `us-central1` |
| `GCP_SERVICE_ACCOUNT` | `mnemos-deploy@<PROJECT>.iam.gserviceaccount.com` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/.../providers/github` |
| `VITE_SUPABASE_URL` | URL Supabase (no secret, pero el frontend lo necesita en build) |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Publishable key |

### Paso 4 — Aplicar migraciones a Supabase (1 min)

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push
```

### Paso 5 — Deploy Edge Functions de Supabase (3 min)

```bash
cd supabase/functions
supabase functions deploy semantic-search
supabase functions deploy anonymous-search
supabase functions deploy synthesize
supabase functions deploy save-knowledge
```

### Paso 6 — Build & deploy a Cloud Run (5 min)

```bash
git push origin main
```

GitHub Actions ejecuta automáticamente:

```
Job 1 (paralelo):  Job 2 (paralelo):  Job 3 (paralelo):
build backend      build frontend     build searxng
push AR            push AR            push AR
deploy Cloud Run   deploy Cloud Run   deploy Cloud Run
```

### Paso 7 — Verificar URLs (1 min)

```bash
gcloud run services list --region us-central1
```

Debe mostrar 3 servicios:
- `mnemos-backend` (privado, solo accedido por edge functions)
- `mnemos-frontend` (público)
- `mnemos-searxng` (privado, solo accedido por backend)

Abrir la URL del frontend en el navegador. Hacer una query.

---

## Criterios de done para "modo Profesional funcional"

- [ ] `gcloud run services list` muestra los 3 servicios `READY`
- [ ] `supabase functions list` muestra las 4 edge functions `ACTIVE`
- [ ] La URL pública del frontend carga sin errores
- [ ] Una query end-to-end funciona desde la URL pública
- [ ] Cloud Logging muestra los logs estructurados
- [ ] `gcloud secrets list` muestra los 3 secrets en Secret Manager
- [ ] Cold start del backend <5s (con `min-instances 1`)
- [ ] El smoke test `scripts/smoke/06-production.sh` pasa contra las URLs públicas

---

## Configuración de Cloud Run por servicio

### mnemos-backend
```bash
--memory 512Mi
--cpu 1
--min-instances 1   # anti cold-start para demo
--max-instances 10
--no-allow-unauthenticated
--set-secrets "SUPABASE_URL=supabase-url:latest"
--set-secrets "SUPABASE_SECRET_KEY=supabase-secret-key:latest"
--set-secrets "OPENROUTER_API_KEY=openrouter-api-key:latest"
--set-env-vars "SEARXNG_URL=<searxng-internal-url>"
```

### mnemos-frontend
```bash
--memory 256Mi
--cpu 1
--min-instances 0
--max-instances 5
--allow-unauthenticated
```

### mnemos-searxng
```bash
--memory 256Mi
--cpu 1
--min-instances 1
--max-instances 5
--no-allow-unauthenticated
--set-secrets "SEARXNG_SECRET=searxng-secret:latest"
```

---

## Costos estimados

| Servicio | Mensual |
|----------|---------|
| Cloud Run (3 servicios, low traffic) | $1-3 |
| Artifact Registry storage | <$1 |
| Secret Manager | <$0.50 |
| Cloud Logging | <$0.50 |
| Egress | $0.50-2 (depende de tráfico) |
| **Total** | **~$2-5/mes** |

Supabase y OpenRouter siguen siendo iguales que en local.

---

## Procedimiento anti cold-start para demos en vivo

1 hora antes del demo:

```bash
# Calentar los 3 servicios
for SERVICE in mnemos-backend mnemos-frontend mnemos-searxng; do
  URL=$(gcloud run services describe $SERVICE --region us-central1 --format 'value(status.url)')
  curl -s -o /dev/null -w "%{http_code}\n" $URL
done
```

Cloud Scheduler puede automatizarlo:

```bash
gcloud scheduler jobs create http mnemos-warmup \
  --schedule "*/5 * * * *" \
  --uri https://mnemos-frontend-xxx.run.app \
  --http-method GET \
  --location us-central1
```

---

## Rollback

Si un deploy rompe producción:

```bash
# Revisar revisiones
gcloud run revisions list --service mnemos-backend --region us-central1

# Revertir a la anterior
gcloud run services update-traffic mnemos-backend \
  --to-revisions <revision-anterior>=100 \
  --region us-central1
```

---

## Cómo apagar todo (no romper la cuenta del mes)

```bash
# Borrar servicios
gcloud run services delete mnemos-backend --region us-central1 --quiet
gcloud run services delete mnemos-frontend --region us-central1 --quiet
gcloud run services delete mnemos-searxng --region us-central1 --quiet

# Borrar imágenes (opcional, ahorra storage)
gcloud artifacts repositories delete mnemos --location us-central1 --quiet

# Secrets se quedan (cuesta casi nada y son útiles para re-deployar)
```

---

## Referencias

- ADR-004 — separación local vs profesional
- ADR-006 — SearxNG en Cloud Run
- ADR-007 — reference repo vs blueprint
- `scripts/gcp-setup.sh` — automatización del setup
- `docs/testing/production-checklist.md` — validación previa al demo
