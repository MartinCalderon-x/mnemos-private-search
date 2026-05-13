# Estrategia de Testing — operativa

> Este documento traduce ADR-005 (decisión de testing) a comandos concretos.

---

## Tres niveles, tres herramientas

| Nivel | Cuándo se corre | Herramienta | Bloquea |
|-------|----------------|-------------|---------|
| 1. Smoke | Al cerrar issue | bash + curl + jq | Cierre del issue |
| 2. Integration | CI en cada push | Vitest + Playwright | Merge a main |
| 3. Demo checklist | 1h antes del show | Markdown manual | Salida al escenario |

---

## Nivel 1 — Smoke tests

### Filosofía
Cada smoke test corresponde a un issue. Si el smoke pasa, el issue se puede cerrar con esa salida como evidencia.

### Estructura

```
scripts/smoke/
├── 01-searxng.sh           ← issue #3
├── 02-supabase.sh          ← issue #2
├── 03-http-api.sh          ← issues #1, #5 (Edge Functions con API_URL=Cloud Run)
├── 04-frontend.sh          ← issue #4
├── 05-end-to-end.sh        ← validación full Local (orquesta 01-04)
├── 06-production.sh        ← validación full Producción (Cloud Run)
├── 07-frontend-docker.sh   ← issue #8 (Frontend Dockerfile + Nginx)
└── 08-cold-start.sh        ← issue #11 (Anti cold-start)
```

### Variables de entorno por script

| Script | Variables | Default |
|--------|-----------|---------|
| 01-searxng | `SEARXNG_URL` | `http://localhost:8080` |
| 02-supabase | `SUPABASE_URL`, `SUPABASE_SECRET_KEY` | lee de `.env` |
| 03-http-api | `API_URL` | `http://localhost:3000` |
| 04-frontend | `FRONTEND_URL` | `http://localhost:5173` |
| 06-production | `BACKEND_URL`, `FRONTEND_URL` | requeridas |
| 07-frontend-docker | `FRONTEND_DOCKER_URL` | `http://localhost:8081` |
| 08-cold-start | `BACKEND_URL`, `COLD_START_THRESHOLD_MS` | URL requerida, umbral 5000 |

---

## Validators de configuración

A diferencia de los smoke tests (que ejercitan servicios runtime), los validators
chequean artefactos de configuración estáticos. Mismo formato de output, distinta
naturaleza: un validator pasa o falla sin levantar nada.

```
scripts/validate/
├── mcp-config.sh         ← issue #6  (.vscode/mcp.json)
├── deploy-workflow.sh    ← issue #7  (.github/workflows/deploy.yml)
└── blueprint.sh          ← issue #12 (scripts/generate-blueprint.sh)
```

### Cuándo usar smoke vs validate

| Tipo | Qué chequea | Necesita servicio corriendo |
|------|-------------|----------------------------|
| `smoke/` | endpoints HTTP, latencia, datos reales | Sí |
| `validate/` | sintaxis, schema, contenido de archivos | No |

Ambos son obligatorios para cerrar el issue al que apuntan.

### Convenciones de output

Cada script DEBE imprimir:
- ✓ verde cuando un step pasa
- ✗ rojo cuando un step falla
- Línea de cierre `RESULTADO: PASS` o `RESULTADO: FAIL`
- Exit code 0 si pasó, 1 si falló

Template:

```bash
#!/bin/bash
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }

echo "=== Smoke 0X: <descripción> ==="

# Test 1
RESPONSE=$(curl -s -w "\n%{http_code}" http://...)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "<endpoint> respondió 200"
else
  fail "<endpoint> devolvió $HTTP_CODE"
fi

# Cierre
if [[ "${FAILED:-0}" -eq 1 ]]; then
  echo "RESULTADO: FAIL"; exit 1
else
  echo "RESULTADO: PASS"; exit 0
fi
```

### Cómo se cita el smoke al cerrar un issue

Comentar en el issue:

> Closing #1.
> 
> Evidencia smoke test:
> ```
> $ ./scripts/smoke/03-http-api.sh
> === Smoke 03: HTTP API server ===
> ✓ /api/search/semantic respondió 200
> ✓ /api/search/web respondió 200
> ✓ /api/synthesize respondió 200
> ✓ /api/knowledge/save respondió 200
> RESULTADO: PASS
> ```

---

## Nivel 2 — Integration tests

### Backend (Vitest)

`backend/tests/integration/`:

```
saveToKnowledge.test.ts    ← inserta + verifica embedding
semanticSearch.test.ts     ← busca con threshold
anonymousSearch.test.ts    ← parsea respuesta de SearxNG
http.routes.test.ts        ← happy path por endpoint
```

Target: cobertura del 70% en `tools/` y `lib/`. UI no se mide.

Setup:
```bash
cd backend
npm install
npm test                    # corre todos
npm test -- --coverage      # con cobertura
```

### Frontend (Playwright)

`frontend/tests/e2e/`:

```
chat-happy-path.spec.ts    ← query → ver respuesta → guardar
chat-empty-kb.spec.ts      ← query → fallback web search
```

No testeamos componentes individuales (no aporta para un demo).

Setup:
```bash
cd frontend
npm install
npx playwright install
npm test
```

### CI

`.github/workflows/test.yml`:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: cd backend && npm ci && npm test
  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: cd frontend && npm ci && npx playwright install --with-deps && npm test
```

---

## Nivel 3 — Demo checklist

Ver `docs/testing/local-checklist.md` y `docs/testing/production-checklist.md`.

Estos son markdowns con `[ ]` que el presenter completa a mano antes del show.

---

## Lo que explícitamente NO testeamos

- **Implementación de Supabase** (es plataforma)
- **Configuración de SearxNG** (config válida = config funcional)
- **Respuestas LLM textuales** (no determinístico)
- **CSS / posicionamiento de UI** (revisión visual)
- **Cloud Run runtime** (es plataforma; smoke en producción cubre)

---

## Política de fallas

| Falla | Acción |
|-------|--------|
| Smoke falla al cerrar issue | Issue se queda abierto, fix-forward |
| Integration test falla en CI | PR no mergea hasta pasar |
| Demo checklist falla | Cancelar el demo o usar backup grabado |

---

## Comandos de validación rápida

| Quiero validar... | Comando |
|------------------|---------|
| Modo Local funciona end-to-end | `./scripts/smoke/05-end-to-end.sh` |
| Producción funciona end-to-end | `./scripts/smoke/06-production.sh` |
| Backend compila | `cd backend && npm run build` |
| Frontend compila | `cd frontend && npm run build` |
| Tests unitarios pasan | `cd backend && npm test` |
| Lint pasa | `cd backend && npm run lint` (cuando se agregue) |

---

## Referencias

- ADR-005 — decisión de testing
- `scripts/smoke/` — implementación
- `docs/testing/local-checklist.md`
- `docs/testing/production-checklist.md`
