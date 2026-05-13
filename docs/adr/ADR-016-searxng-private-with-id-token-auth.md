# ADR-016: SearxNG como servicio privado + auth con ID token de Cloud Run

**Fecha:** 2026-05-13
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

La propuesta de valor de mnemos incluye "búsqueda web anónima vía SearxNG
self-hosted". Si el SearxNG es accesible al público, dos problemas serios:

1. **Cualquiera puede usar nuestra instancia** como proxy de búsqueda anónimo.
   Eso consume cuota nuestra (a futuro: rate-limits de search engines downstream)
   y nos hace cómplices de uso indebido.
2. **Rompe la promesa de privacidad**: la audiencia podría asumir que SearxNG
   está abierto a todos, y por lo tanto Google podría correlacionar búsquedas
   desde nuestra IP de Cloud Run con búsquedas de terceros — diluye la
   "anonimidad" si nuestro tráfico se mezcla con el de scrapers.

El primer deploy a Cloud Run dejó SearxNG con `--allow-unauthenticated`
(default). Un curl a la URL `.run.app` devolvía el UI completo, navegable.

## Decisión

SearxNG corre como **Cloud Run service privado**: sin `allUsers` en el binding
`roles/run.invoker`. Solo la SA del backend (`<project_number>-compute@...`,
o explícita en deploys futuros) tiene permiso para invocarlo.

El backend autentica cada request via **identity token de Cloud Run**:
fetcha el token del metadata server local (`metadata.google.internal`)
con audience = SearxNG URL, y lo manda como `Authorization: Bearer <token>`.

Cloud Run valida el token automáticamente antes de routear el request a la
instancia de SearxNG.

## Implementación

### Lado SearxNG (Cloud Run service)

Setup one-time (ya hecho en producción):

```bash
# 1. Quitar acceso público
gcloud run services remove-iam-policy-binding mnemos-searxng-prod \
  --region=us-central1 --project=<your-gcp-project> \
  --member="allUsers" --role="roles/run.invoker"

# 2. Permitir al backend (compute SA por default)
gcloud run services add-iam-policy-binding mnemos-searxng-prod \
  --region=us-central1 --project=<your-gcp-project> \
  --member="serviceAccount:<your-gcp-project-number>-compute@developer.gserviceaccount.com" \
  --role="roles/run.invoker"
```

### Lado backend (`backend/src/lib/searxng.ts`)

```ts
async function getIdentityToken(audience: string): Promise<string | null> {
  // K_SERVICE es seteado por Cloud Run runtime; en local no existe → return null
  if (!process.env.K_SERVICE) return null;
  try {
    const res = await fetch(
      `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=${encodeURIComponent(audience)}`,
      { headers: { 'Metadata-Flavor': 'Google' } },
    );
    if (!res.ok) return null;
    return (await res.text()).trim();
  } catch {
    return null;
  }
}

// En cada request a SearxNG:
const headers: Record<string, string> = {};
const token = await getIdentityToken(env.SEARXNG_URL);
if (token) headers['Authorization'] = `Bearer ${token}`;
const res = await fetch(`${env.SEARXNG_URL}/search?...`, { headers });
```

**Backwards compatible con dev local**: si `K_SERVICE` no está (estás
corriendo en tu máquina con Docker), `getIdentityToken()` devuelve `null` y
no se envía Authorization. SearxNG en Docker no requiere auth → funciona.

## Alternativas evaluadas

| Opción | Pros | Contras | Decisión |
|--------|------|---------|----------|
| **ID token via metadata server** (elegida) | Pattern oficial Google Cloud; cero secrets; rotación automática; audit-friendly | Requiere `K_SERVICE` env (solo presente en Cloud Run runtime) | ✅ |
| **VPC connector** + ingress=internal | Cero IAM logic; tráfico literalmente nunca sale al internet | Setup pesado (VPC + connector + IP allocation); $10/mes baseline | ❌ |
| **Basic Auth / API key** en SearxNG | Simple | SearxNG no soporta nativo; habría que configurar filter; key estática rotable manual | ❌ |
| **`--ingress=internal-and-cloud-load-balancing`** | Bloquea externo a nivel network | Cloud Run service-to-service NO cuenta como internal sin VPC connector. Rompe el llamado del backend | ❌ |
| **`limiter.toml`** de SearxNG (rate-limit by IP) | Frena scrapers obvios | No bloquea, solo demora; deja el UI público | ❌ |

## Trade-offs

- **Cold start del metadata server**: +50-150ms en el primer request de cada
  instancia Cloud Run. Aceptable; el embedding del modelo tarda 30s, esto
  es ruido.
- **Token caching**: por simplicidad, cada `searchWeb()` fetcha un token nuevo.
  Los tokens duran ~1h. Si la latencia molesta, agregar in-memory cache con
  TTL de 50min. Por ahora prematuro.
- **Multi-tenant demo**: si en el futuro varios demos corren en paralelo (ver
  ADR-011 TABLE_PREFIX), todos comparten una sola instancia de SearxNG. OK
  mientras no haga falta aislar. Si llegado el caso, cada prefix puede tener
  su propio SearxNG con el patrón generalizable.

## Validación

Post-fix verificado en producción:

```bash
# Sin token (lo que vería un externo)
curl -I https://mnemos-searxng-prod-XXX.run.app
# → HTTP 403

# Desde el backend (con ID token automático)
curl -X POST https://api.<your-domain>/api/search/web \
  -H "Content-Type: application/json" \
  -d '{"query":"hello","limit":1}'
# → {"found":true,"results":[...],"message":"Encontré 1 resultado..."}
```

Backend logs muestran 200 OK contra SearxNG. SearxNG IAM policy verificada:

```yaml
bindings:
- members:
  - serviceAccount:<your-gcp-project-number>-compute@developer.gserviceaccount.com
  role: roles/run.invoker
```

No hay `allUsers`. Confirmado.

## Consecuencias

- **Privacy claim sostenido**: el SearxNG es **exclusivamente** consumido por
  el backend de mnemos. Nadie más puede usar nuestra instancia como proxy.
- **Trazabilidad**: el audit log de Cloud Run muestra cada invocación con
  identidad de caller. Si el backend hace mal uso, queda registrado.
- **Operacional**: cualquier nuevo servicio que necesite SearxNG (ej. un job
  de Cloud Run que sincronice search trends) necesita ser agregado al
  binding `roles/run.invoker` explícitamente. Patrón de allow-list.
- **El blueprint público (`mnemos-private-search`)** documenta este patrón
  para que cada clone lo aplique a SU SearxNG sin filtraciones por default.

## Referencias

- [Authenticating service-to-service](https://cloud.google.com/run/docs/authenticating/service-to-service)
- [Cloud Run service identity](https://cloud.google.com/run/docs/securing/service-identity)
- ADR-006 — SearxNG en Cloud Run con settings baked
- ADR-013 — repo privado vs público OSS
- `backend/src/lib/searxng.ts`
