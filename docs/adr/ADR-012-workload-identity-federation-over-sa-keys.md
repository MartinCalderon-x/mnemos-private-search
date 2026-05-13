# ADR-012: Workload Identity Federation en lugar de Service Account Keys

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

El demo necesita que GitHub Actions (y/o GitHub Copilot Coding Agent) deploye
mnemos a Google Cloud Run. Para eso el workflow tiene que **autenticarse como
una identidad** que tenga permisos en GCP.

La forma tradicional es generar una **Service Account Key** (JSON con private
key), pegarla como GitHub Secret, y usarla con `google-github-actions/auth`.
Esto tiene problemas serios:

1. La key es estática: si se filtra (logs, dump, fork malicioso, employee
   leak), el atacante tiene acceso indefinido hasta que la rotás manualmente.
2. Audit log es genérico: "SA hizo X", sin trazar qué workflow / commit /
   actor de GitHub originó la acción.
3. Google explícitamente **deprecó** SA keys como mecanismo recomendado para
   integraciones externas en 2024.
4. Rotación manual cada 90 días = overhead operacional.
5. El repo `mnemos` es privado pero el `mnemos-private-search` será público; tener
   menos secrets vivos por sistema es estratégicamente sano (ADR-013).

## Decisión

Usar **Workload Identity Federation (WIF)** para que GitHub Actions impersone
una service account de GCP usando un OIDC token efímero firmado por GitHub.
**Cero private keys** en el repo.

## Cómo funciona

```
┌────────────────────┐
│  GitHub Actions    │
│  workflow corre    │
│  (id-token: write) │
└──────────┬─────────┘
           │ OIDC token { sub: "repo:MartinCalderon-x/mnemos:...", ... }
           ▼
┌────────────────────┐
│   GCP STS          │
│  1. Verifica firma │ con JWKS pública de GitHub
│  2. Matchea claims │ ¿assertion.repository == 'MartinCalderon-x/mnemos'?
│  3. Emite token    │ federated, válido 1h
└──────────┬─────────┘
           │
           ▼
┌────────────────────┐
│ Service Account    │ → impersonation via roles/iam.workloadIdentityUser
│ mnemos-deploy@...  │ Con los roles reales: run.admin, secretmanager.admin, etc.
└──────────┬─────────┘
           │
           ▼
   gcloud / GCP APIs operan como la SA, audit log preserva el contexto GitHub
```

## Las 3 piezas creadas (one-time)

Implementadas en `scripts/setup-gcp-wif.sh`. Todas idempotentes:

### 1. Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "mnemos-pool" \
  --location=global --project="$PROJECT_ID"
```

### 2. OIDC Provider (con condition que restringe el repo)

```bash
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --workload-identity-pool="mnemos-pool" --location=global \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,..." \
  --attribute-condition="assertion.repository == 'MartinCalderon-x/mnemos'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

**La línea crítica:** `attribute-condition`. Sin ella, CUALQUIER repo de
GitHub (incluido un fork malicioso de un atacante) podría usar este provider.
Con ella, solo tokens cuyo claim `repository` matchea exactamente nuestro
repo son aceptados.

### 3. Service Account + binding

```bash
gcloud iam service-accounts create mnemos-deploy --project="$PROJECT_ID"

# Roles que el deploy necesita
for role in roles/run.admin roles/iam.serviceAccountUser \
            roles/secretmanager.admin roles/artifactregistry.writer roles/storage.admin; do
  gcloud projects add-iam-policy-binding ...
done

# La parte mágica: solo principalSet del repo puede impersonar la SA
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://.../attribute.repository/MartinCalderon-x/mnemos"
```

## Lo que termina en GitHub Secrets

Solo dos strings, **ninguno es una key privada**:

| Secret | Valor de ejemplo |
|--------|------------------|
| `GCP_WIF_PROVIDER` | `projects/<your-gcp-project-number>/locations/global/workloadIdentityPools/mnemos-pool/providers/github-provider` |
| `GCP_WIF_SERVICE_ACCOUNT` | `mnemos-deploy@<your-gcp-project>.iam.gserviceaccount.com` |

Si esos strings se filtran, son **inútiles** sin un OIDC token firmado por
GitHub que cumpla la `attribute-condition`. No hay private key que rotar.

## Workflow consumiendo WIF

```yaml
permissions:
  contents: read
  id-token: write          # ← clave: permite a GH generar el OIDC token

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WIF_PROVIDER }}
          service_account:           ${{ secrets.GCP_WIF_SERVICE_ACCOUNT }}
      - run: gcloud run deploy ...   # autenticado por 1h con los roles de la SA
```

## Alternativas evaluadas

| Opción | Pros | Contras | Decisión |
|--------|------|---------|----------|
| **WIF** | Cero keys, audit con contexto, efímero, Google-recommended | Setup inicial 15 min one-time | ✅ Elegida |
| Service Account Key (JSON en GH Secret) | 2 min setup | Key estática, deprecated, leaks indefinidos | ❌ |
| OAuth user account | Fácil para humanos | No diseñado para CI; requiere refresh tokens | ❌ |
| Cloud Identity (gcloud auth login en CI) | — | No funciona en entornos no-interactivos | ❌ |

## Validación

Setup ejecutado el 2026-05-12 contra GCP project `<your-gcp-project>`
(<your-google-account>) via `scripts/setup-gcp-wif.sh --write-env`.

Output:

```
GCP_PROJECT_ID=<your-gcp-project>
GCP_WIF_PROVIDER=projects/<your-gcp-project-number>/locations/global/workloadIdentityPools/mnemos-pool/providers/github-provider
GCP_WIF_SERVICE_ACCOUNT=mnemos-deploy@<your-gcp-project>.iam.gserviceaccount.com
```

Persistidos en `.env` y luego subidos a GitHub Secrets/Variables vía
`scripts/setup-github-secrets.sh`. Validación de uso real pendiente — depende
del workflow `.github/workflows/deploy.yml` (issue #7).

## Consecuencias

- **Cero JSON keys** en `.env`, `.env.example`, GitHub Secrets, ni filesystem
  del runner. La superficie de leak se reduce a las dos strings inertes.
- **Audit log de GCP** muestra el contexto GitHub: workflow, run_id, actor,
  ref, repository. Trazabilidad granular.
- **Reproducible** — `scripts/setup-gcp-wif.sh` puede correr contra otro
  proyecto / otro repo cambiando vars. Lo va a usar el blueprint público
  (ADR-013) para que cada clone se setee su propio WIF.
- **El SA mismo no cambia** — sigue siendo `mnemos-deploy@<project>` con sus
  roles. Lo único que cambia es **cómo** se autentica el caller.

## Referencias

- [Google Cloud — Configure WIF with GitHub](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [google-github-actions/auth](https://github.com/google-github-actions/auth)
- ADR-013 — repo privado + público clone
- `scripts/setup-gcp-wif.sh`
