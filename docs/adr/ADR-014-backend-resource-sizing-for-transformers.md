# ADR-014: Sizing del backend para @xenova/transformers en Cloud Run

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

El backend embebe el modelo `multilingual-e5-small` vía `@xenova/transformers`
(ADR-008). El modelo pesa ~80MB en disco pero al cargarse en ONNX Runtime
para inferencia consume **~1.2-1.8GB de RAM peak** durante el primer
`embedQuery()` (tokenizer + weights + ONNX session).

En el primer deploy a Cloud Run con la configuración default (`512Mi RAM`,
`1 CPU`), el container crasheaba con SIGKILL (OOM) al primer hit del
endpoint `/api/search/semantic`. Síntoma observable en logs:

```
[backend] mnemos backend → http://localhost:3000   ← startup
GET /health 200                                     ← healthcheck OK
POST /api/search/semantic                           ← model loads, OOM
[backend] mnemos backend → http://localhost:3000   ← container restarted
```

El healthcheck pasaba porque no toca el modelo. La carga del modelo recién
ocurre en el primer query — clásico cold-start lazy.

## Decisión

Configurar el servicio Cloud Run del backend con recursos suficientes para
cargar el modelo en cold start sin OOM:

| Recurso | Valor | Razón |
|---------|-------|-------|
| **memory** | `2Gi` | Cubre los ~1.8GB peak del modelo + node runtime + supabase client |
| **cpu** | `2` | ONNX Runtime usa todos los cores en inferencia; 1 CPU triplicaba la latencia |
| **timeout** | `120s` | El primer `embedQuery()` puede tardar ~30-40s post-OOM-fix por la inicialización del ONNX session |
| **min-instances** | `0` | OK para demo; en prod real subir a 1 para evitar cold start |

Aplicado en `.github/workflows/deploy.yml` para el job `deploy-backend`:

```yaml
flags: |
  --port=3000
  --memory=2Gi
  --cpu=2
  --timeout=120
  --min-instances=0
  --max-instances=4
  --allow-unauthenticated
```

## Alternativas evaluadas

| Opción | Por qué se descartó |
|--------|---------------------|
| **Pre-cargar el modelo al startup** (warmup hook) | Cloud Run cobra por CPU durante el warmup; subir min-instances=1 es más simple y predecible |
| **Modelo más chico** (ej `nomic-embed-text` distill 64MB) | Calidad de embedding peor; tabla pgvector ya tiene 384D del e5-small (ADR-008) |
| **Embeddings vía API** (OpenAI / Voyage) | Rompe la premisa de privacidad (ADR-008) — los textos saldrían fuera de tu infra |
| **Cloud Run con GPU** | Overkill para 384D; subir RAM/CPU es 100x más barato |

## Consecuencias

- **Costo:** ~$0.05/hora cuando hay tráfico activo (CPU billed only-during-request). En idle, cero.
- **Cold start latency:** primer request post-idle puede tardar 30-40s. Si esto duele para el demo, ver issue #11 (anti cold-start con cron de warmup).
- **Cualquier modelo más grande que e5-small va a necesitar bump a 4Gi** — la curva no es lineal por las activaciones intermedias del transformer.

## Observabilidad

Si Cloud Run loguea SIGKILL o restart-loop en el backend, casi seguro es OOM
del modelo. Comprobación rápida:

```bash
gcloud run services logs read mnemos-backend-<prefix> --region=us-central1 \
  --limit=50 | grep -E "SIGKILL|OOM|killed|memory"
```

## Referencias

- ADR-008 — embeddings strategy (multilingual-e5-small 384D)
- `backend/Dockerfile` — `FROM node:22-slim` (glibc requerido por onnxruntime-node)
- [Cloud Run resource limits](https://cloud.google.com/run/docs/configuring/memory-limits)
