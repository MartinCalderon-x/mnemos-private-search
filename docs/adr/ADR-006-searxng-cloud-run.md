# ADR-006: SearxNG en Cloud Run

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

SearxNG es un servicio Python que en local corre con `docker compose` y monta `searxng/settings.yml` como volumen (`./searxng:/etc/searxng:rw`). Esto funciona en local pero **Cloud Run no soporta volúmenes persistentes** — los containers son efímeros y stateless.

Hay que decidir cómo se entrega la configuración de SearxNG en producción.

## Decisión

**Bake la configuración dentro de la imagen Docker** que se sube a Artifact Registry.

```dockerfile
# searxng/Dockerfile.cloud-run
FROM searxng/searxng:latest

# Copiamos la config dentro de la imagen
COPY settings.yml /etc/searxng/settings.yml

# Aseguramos permisos correctos
RUN chmod 644 /etc/searxng/settings.yml

EXPOSE 8080
```

La imagen resultante es **autocontenida**: tiene SearxNG + nuestro `settings.yml` específico.

## Alternativas consideradas

### Opción B — Cloud Storage (descartada)

Montar GCS como FUSE en Cloud Run para leer `settings.yml` desde un bucket.

**Por qué no:**
- Latencia adicional en cold start
- Requiere permisos extra al service account
- Para un archivo de config estático, es ingeniería innecesaria

### Opción C — Variables de entorno (descartada)

SearxNG soporta override de algunos settings vía env vars (`SEARXNG_BASE_URL`, etc.) pero no todos. Requeriría parchear la imagen igual.

**Por qué no:**
- No cubre todos los settings que necesitamos (engines, categorías, idiomas)
- Mezcla configuración con secretos

### Opción D — Init container con git clone (descartada)

Container que arranca antes y descarga el config desde el repo.

**Por qué no:**
- Cloud Run no soporta init containers nativos
- Acoplaría el deployment al estado del repo en runtime

## Consecuencias

- Cada cambio en `searxng/settings.yml` requiere rebuild + redeploy de la imagen
- Esto es aceptable porque la config cambia con baja frecuencia (categorías de búsqueda, idioma default)
- La imagen producida es portable: corre igual en local (docker), Cloud Run, Kubernetes
- El Dockerfile vive en `searxng/Dockerfile` (nuevo archivo, separado del Dockerfile del backend)

## Configuración de Cloud Run

```bash
gcloud run deploy mnemos-searxng \
  --image us-central1-docker.pkg.dev/${PROJECT_ID}/mnemos/searxng:latest \
  --region us-central1 \
  --memory 256Mi \
  --cpu 1 \
  --min-instances 1 \           # anti cold-start para el demo
  --max-instances 5 \
  --port 8080 \
  --no-allow-unauthenticated \  # solo accesible desde el backend
  --set-env-vars "SEARXNG_SECRET=${SEARXNG_SECRET}"
```

**Importante:** SearxNG en Cloud Run **NO** debe ser público. Solo el backend de mnemos lo consume vía service-to-service auth, dentro de la VPC.

## Settings.yml comparativo

```yaml
# settings.yml — funciona en local Y en Cloud Run
use_default_settings: true

server:
  port: 8080
  bind_address: "0.0.0.0"
  secret_key: "$SEARXNG_SECRET"   # se sustituye al runtime
  limiter: false                   # deshabilitado para que el agente no se rate-limitee
  image_proxy: false

ui:
  default_locale: "es"
  query_in_title: true

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "es"
  formats:
    - html
    - json

engines:
  - name: google
    disabled: false
  - name: duckduckgo
    disabled: false
  - name: bing
    disabled: true   # tiende a bloquear con CAPTCHA
```

## Riesgos para el demo

| Riesgo | Mitigación |
|--------|-----------|
| Google detecta tráfico bot y bloquea | Tener DuckDuckGo + Brave como fallback |
| Cold start de SearxNG (~3s) | `--min-instances 1` durante el demo |
| Imagen pesada (>500MB) | Aceptable, SearxNG ya es ese tamaño base |

## Referencias

- ADR-004 — modos Local vs Profesional
- [SearxNG Docker docs](https://docs.searxng.org/admin/installation-docker.html)
- [Cloud Run sandbox limitations](https://cloud.google.com/run/docs/container-contract)
