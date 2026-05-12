# ADR-013: Repo privado de referencia + clone público OSS

**Fecha:** 2026-05-12
**Estado:** Aceptado
**Autores:** Martin Calderon

---

## Contexto

Hasta ADR-007 mnemos era un repo único público con todo: código,
specs, demo, planos. Conforme avanzó la implementación quedaron dos
necesidades en tensión:

- **El reference repo necesita secrets y contexto privado** — el `.env`
  con credenciales reales, los workflows de deploy, la configuración
  WIF (ADR-012), eventualmente artefactos del demo en vivo (deck,
  LinkedIn post, narrativa). Si el repo es público, cada commit es
  oportunidad de leak.
- **La comunidad necesita un blueprint OSS** — la propuesta de valor
  del paper/talk es "podés reconstruir esto desde un blueprint
  clonable, con Copilot en 30 min". Eso no funciona si el blueprint
  está enterrado dentro de un repo privado.

Tener una sola visibilidad obliga a elegir mal:

- Si todo es público → riesgo de filtrar credenciales del presenter,
  ruido de archivos demo en el branch principal del OSS, narrativa
  diluida.
- Si todo es privado → el demo deja de cumplir su promesa ("cualquiera
  puede hacerlo").

## Decisión

**Dos repos hermanos con propósitos disjuntos.**

| Repo | Visibilidad | Contenido | Audiencia |
|------|-------------|-----------|-----------|
| `MartinCalderon-x/mnemos` | **Privado** | Código completo + secrets en GH + `.env` operacional + workflows con WIF apuntando al GCP project del presenter + scripts demo + deck/LinkedIn (gitignored) | Vos, el presenter; CI del presenter |
| `MartinCalderon-x/mnemos-private-search` | **Público / OSS** | Solo specs (ADRs, flows, plans) + smoke tests + validators + `.env.example` + `BLUEPRINT.md` + `package.json` sin `src/` + templates `.github/copilot/`, `.github/workflows/` | Comunidad, attendees del demo, futuros forks |

### Lo que NO va al público

- `backend/src/` y `frontend/src/` (código de implementación)
- `.env` real
- `.github/workflows/` con valores hardcoded del presenter
- WIF / SA bindings del presenter
- `docs/linkedin/`, `docs/presentation/` (entregables narrativos)
- `docs/sessions/` (historial de trabajo personal)
- Imágenes Grok generadas para el demo

### Lo que SÍ va al público

- `docs/adr/` (todas las decisiones)
- `docs/flows/` (specs del agente, flow del demo, MCP orchestration)
- `docs/plans/` (planes ejecutivos para reconstruir)
- `scripts/smoke/`, `scripts/validate/`
- `scripts/setup-gcp-wif.sh` (parameterizado por repo y project)
- `scripts/setup-github-secrets.sh`
- `supabase/migrations/`, `supabase/templates/`
- `docker-compose.yml`, `searxng/`
- `BLUEPRINT.md` con instrucciones de setup en 5 pasos
- `README.md` de blueprint (no de reference)
- `.env.example` y `.vscode/mcp.json.example`

## Cómo se mantiene la sincronía

`scripts/generate-blueprint.sh <output_dir>` (issue #12) materializa
una snapshot del blueprint desde el reference. Hace `rsync` con
exclude lists explícitas y deja un commit que referencia el SHA del
reference.

El flujo de sync es **manual y deliberado**:

```
1. Cambio en mnemos privado (commit + push)
2. Cuando es release-worthy → ./scripts/generate-blueprint.sh ../mnemos-private-search
3. cd ../mnemos-private-search && git add . && git commit -m "sync from <sha>"
4. git push origin main
```

No hay sync automático porque queremos **versionado discreto** del
blueprint — releases curados, no commit-by-commit.

## Implicancias para el demo

El demo en vivo cambia de narrativa:

| Antes (un repo) | Ahora (dos repos) |
|-----------------|-------------------|
| "Voy a generar un blueprint y reconstruirlo" | "Voy a clonar este repo OSS público — cualquiera puede — y reconstruir mnemos en 30 min" |
| El blueprint es un artefacto temporal | El blueprint es un proyecto OSS de verdad: stars, forks, issues |
| Audiencia escéptica: "obvio, el código está en el mismo repo" | Audiencia puede verificar que el blueprint NO tiene el código pero SÍ las specs |

## Implicancias para credenciales

Todos los secrets viven en **mnemos privado**:

```
SUPABASE_URL, SUPABASE_SECRET_KEY, SUPABASE_ACCESS_TOKEN,
SUPABASE_PROJECT_REF, OPENROUTER_API_KEY, SEARXNG_SECRET,
VITE_SUPABASE_*, GCP_WIF_PROVIDER, GCP_WIF_SERVICE_ACCOUNT
```

El **público** tiene:

```
.env.example                         (placeholders, sin valores)
scripts/setup-github-secrets.sh     (toma valores del .env del clonador, los sube a SU repo)
scripts/setup-gcp-wif.sh            (crea SU WIF en SU GCP project)
```

Cualquiera que clone:

```bash
git clone https://github.com/MartinCalderon-x/mnemos-private-search
cd mnemos-private-search
cp .env.example .env                                 # llenar con SUS credenciales
./scripts/setup-gcp-wif.sh --write-env               # crea SU WIF
./scripts/setup-github-secrets.sh --repo SU/FORK     # secrets a SU repo
# Copilot toma el control desde acá
```

## Alternativas evaluadas

| Opción | Por qué se descartó |
|--------|---------------------|
| Un solo repo público, secrets en GH Secrets | Riesgo permanente de leak por commit accidental al branch. Workflows con `secrets.X` sí redactan, pero `.env`, `docs/sessions/`, deck, todo tiene que ser micro-policed |
| Un solo repo privado | Rompe la promesa OSS del demo |
| Monorepo con submódulos | Sync mental compleja, los submódulos rara vez se entienden bien |
| Mirror automático con sanitización | Frágil — un cambio en exclude rules y filtrás algo. Manual y deliberado es más seguro |
| Branch privado + branch público en el mismo repo | GitHub no soporta branch-level visibility |

## Consecuencias

- **Workflow más explícito** — sync es un acto consciente. Bueno para
  versionado del OSS, malo para alguien que quiere ver el commit
  HEAD-by-HEAD.
- **Doble mantenimiento mínimo** — el público se actualiza solo
  cuando hay una release worthwhile. La frecuencia esperada es 1x/mes.
- **El blueprint puede divergir** — si alguien forkea el público y
  agrega features, esos no vuelven al privado automáticamente. Eso
  está bien: el OSS es el "punto de partida congelado", no el
  espejo en vivo del privado.
- **El presenter puede iterar libremente** en el privado sin presión
  de "qué se ve". Mejor calidad de trabajo.
- **Cada clone del público es un demo completo** — el setup script
  crea SU WIF, SU Cloud Run, SU Supabase project. Cero overlap con
  el del presenter.

## Estado de implementación al 2026-05-12

- ✅ `mnemos` switched a privado (`gh repo edit --visibility private`)
- ✅ Credenciales del presenter en GH Secrets / Variables (11 items)
- ✅ WIF setup contra `<your-gcp-project>` (ADR-012)
- ⏳ `mnemos-private-search` repo público — pendiente de crear cuando el
  blueprint generator (issue #12) esté funcional
- ⏳ Primera sincronización — primera release pública del blueprint

## Referencias

- ADR-007 — distinción inicial reference vs blueprint (mismo repo)
- ADR-011 — TABLE_PREFIX para que ambos demos compartan Supabase sin chocar
- ADR-012 — WIF para que ambos demos compartan patrón de auth a GCP
- Issue #12 — `generate-blueprint.sh`
