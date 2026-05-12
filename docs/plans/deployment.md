# Plan de Deployment — mnemos

## Dos rutas: local → producción

```
RUTA 1 — Local (5 min)           RUTA 2 — Cloud Run (15-20 min)
──────────────────────           ──────────────────────────────
Para validar y desarrollar       Para compartir y producción
docker compose up -d             ./scripts/gcp-setup.sh + gh push
```

---

## Ruta 1: Local con Docker Compose

### Prerequisitos
- Docker Desktop instalado
- Cuenta Supabase (free tier OK)
- API key OpenRouter (free tier OK)

### Pasos

```bash
git clone https://github.com/MartinCalderon-x/mnemos
cd mnemos
cp .env.example .env
# Llenar SUPABASE_URL, SUPABASE_SECRET_KEY, OPENROUTER_API_KEY
docker compose up -d
```

### Servicios que levanta

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| SearxNG | 8080 | Motor de búsqueda anónima |
| MCP Server | 3000 | API del agente (dev mode) |
| Frontend | 5173 | UI chat-style |

### Verificar que funciona

```bash
# SearxNG
curl http://localhost:8080/search?q=test&format=json

# MCP Server health
curl http://localhost:3000/health

# Frontend
open http://localhost:5173
```

---

## Ruta 2: Producción en Google Cloud Run

### Prerequisitos
- GCP project con billing habilitado
- `gcloud` CLI instalado y autenticado
- GitHub repo forkeado

### Paso 1: Setup GCP (una sola vez)

```bash
./scripts/gcp-setup.sh <GCP_PROJECT_ID>
```

El script crea automáticamente:
- APIs habilitadas (Cloud Run, Artifact Registry, Secret Manager)
- Service account con permisos mínimos
- Workload Identity Federation para GitHub Actions
- Secrets en Secret Manager (lee de tu `.env`)
- Artifact Registry repo para imágenes Docker

### Paso 2: Agregar GitHub Secrets al fork

El script imprime los valores exactos al terminar:

```
GCP_PROJECT_ID=tu-proyecto
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/123/.../providers/github
GCP_SERVICE_ACCOUNT=mnemos-deploy@tu-proyecto.iam.gserviceaccount.com
```

Ir a: GitHub → Settings → Secrets and variables → Actions → New secret

### Paso 3: Deploy

```bash
git push origin main
# GitHub Actions despliega automáticamente a Cloud Run
```

### Arquitectura en GCP

```
GitHub Actions (push a main)
    │
    ▼ Workload Identity (sin service account keys)
Artifact Registry
    ├── mnemos-backend:latest
    └── mnemos-searxng:latest
    │
    ▼
Cloud Run
    ├── mnemos-backend (MCP Server)  ← lee secrets de Secret Manager
    └── mnemos-searxng (SearxNG)     ← config baked en imagen
    │
    ▼
Supabase (externo)
```

### Variables de entorno en producción

Secret Manager monta las secrets como env vars en Cloud Run automáticamente. No hay archivos `.env` en producción.

| Secret Manager Key | Env var en Cloud Run |
|-------------------|---------------------|
| `supabase-url` | `SUPABASE_URL` |
| `supabase-secret-key` | `SUPABASE_SECRET_KEY` |
| `openrouter-api-key` | `OPENROUTER_API_KEY` |

---

## Comparación de rutas

| Aspecto | Local | Cloud Run |
|---------|-------|-----------|
| Tiempo setup | ~5 min | ~15-20 min |
| Costo | $0 | ~$2-5/mes |
| Disponibilidad | Solo tu máquina | URL pública |
| Cold start | Instantáneo | ~3s (SearxNG) |
| Ideal para | Desarrollo, demo en vivo | Compartir, conferencias |

---

## Workflow recomendado

1. **Desarrollar** en Ruta 1 (local)
2. **Validar** que todo funciona con `docker compose up`
3. **Deploy** a Cloud Run cuando necesites URL pública
4. El mismo `.env` funciona en ambas rutas
