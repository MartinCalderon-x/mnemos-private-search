# Plan: Blueprint Replication

> Cómo este reference repo se transforma en un blueprint limpio (`mnemos-private-search`) para que Copilot lo reconstruya en vivo.

---

## Contexto

Ver ADR-007. Este repo (`mnemos`) es el **reference completo y validado**. Para el demo en vivo necesitamos un **blueprint vacío de código pero rico en specs**.

---

## Qué se transfiere y qué no

| Path | Reference (`mnemos`) | Blueprint (`mnemos-private-search`) |
|------|---------------------|-------------------------------|
| `README.md` | Completo | Reemplazado con versión orientada a blueprint |
| `BLUEPRINT.md` | No existe | Nuevo, instrucciones para Copilot |
| `CLAUDE.md` | Completo | Igual |
| `.env.example` | Completo | Igual |
| `docker-compose.yml` | Completo | Igual |
| `searxng/settings.yml` | Completo | Igual |
| `supabase/migrations/*.sql` | Completas | Iguales |
| `supabase/functions/` | Con código | Vacío con `.gitkeep` |
| `scripts/gcp-setup.sh` | Completo | Igual |
| `scripts/smoke/` | Completo | Igual |
| `.github/workflows/` | Completos | Iguales |
| `.vscode/mcp.json` | Completo | Igual |
| `docs/` (todo) | Completo | Igual |
| `backend/package.json` | Completo | Igual (con dependencies) |
| `backend/tsconfig.json` | Completo | Igual |
| `backend/Dockerfile` | Completo | Igual |
| `backend/src/` | Con código | Vacío |
| `frontend/package.json` | Completo | Igual |
| `frontend/tsconfig.json`, `vite.config.ts`, etc | Completos | Iguales |
| `frontend/src/` | Con código | Vacío |
| `frontend/index.html` | Completo | Igual |
| `node_modules/`, `dist/` | Existen | NO transferir |
| `*.lock`, `package-lock.json` | Existen | Transferir (acelera install) |

---

## Script de generación

`scripts/generate-blueprint.sh`:

```bash
#!/bin/bash
set -euo pipefail

REFERENCE_DIR="$(pwd)"
BLUEPRINT_DIR="${1:-../mnemos-private-search}"

# Crear o vaciar blueprint
mkdir -p "$BLUEPRINT_DIR"
rm -rf "$BLUEPRINT_DIR"/*
rm -rf "$BLUEPRINT_DIR"/.[!.]*

# Copiar todo excepto node_modules, dist, .git, .env
rsync -av \
  --exclude 'node_modules' \
  --exclude 'dist' \
  --exclude '.git' \
  --exclude '.env' \
  --exclude '.DS_Store' \
  --exclude 'backend/src' \
  --exclude 'frontend/src' \
  --exclude 'supabase/functions' \
  "$REFERENCE_DIR/" "$BLUEPRINT_DIR/"

# Crear estructuras vacías con .gitkeep
mkdir -p "$BLUEPRINT_DIR/backend/src"
mkdir -p "$BLUEPRINT_DIR/frontend/src"
mkdir -p "$BLUEPRINT_DIR/supabase/functions"

touch "$BLUEPRINT_DIR/backend/src/.gitkeep"
touch "$BLUEPRINT_DIR/frontend/src/.gitkeep"
touch "$BLUEPRINT_DIR/supabase/functions/.gitkeep"

# Copiar BLUEPRINT.md (versión específica)
cp "$REFERENCE_DIR/docs/blueprint/BLUEPRINT.md" "$BLUEPRINT_DIR/BLUEPRINT.md"
cp "$REFERENCE_DIR/docs/blueprint/README.blueprint.md" "$BLUEPRINT_DIR/README.md"

cd "$BLUEPRINT_DIR"
git init
git add .
git commit -m "feat: initial blueprint generated from mnemos@$(cd $REFERENCE_DIR && git rev-parse --short HEAD)"

echo "✓ Blueprint generado en $BLUEPRINT_DIR"
echo "  Próximo paso:"
echo "    cd $BLUEPRINT_DIR"
echo "    git remote add origin git@github.com:MartinCalderon-x/mnemos-private-search.git"
echo "    git push -u origin main"
```

---

## Contenido de `BLUEPRINT.md`

Archivo que solo existe en el blueprint, no en el reference:

```markdown
# mnemos — Blueprint para construir con Copilot

Este repo está intencionalmente vacío de código. Las specs están completas.
Copilot Agent Mode lee `docs/` e implementa cada Issue en orden.

## Cómo arrancar

1. Configurar `.env` (ver `.env.example`)
2. Configurar `.vscode/mcp.json` con tus credenciales
3. Abrir Issue #1 en GitHub
4. Pegarle a Copilot: "Implementá este issue. Seguí los criterios de aceptación."
5. Validar con `scripts/smoke/0X-*.sh`
6. Avanzar al siguiente issue

## Lectura mandatoria para Copilot

Antes de implementar cualquier issue, leer:
- `docs/adr/` — todas las decisiones arquitectónicas
- `docs/flows/agent-decision-flow.md` — qué construir
- `docs/flows/copilot-mcp-orchestration.md` — cómo orquestar MCPs
- El issue específico — qué validar

## Orden de issues

1. Setup local (issues #1-4)
2. MCPs externos (issues #6-7) 
3. Producción (issues #8-13)
```

---

## Cadencia de regeneración

| Trigger | Acción |
|---------|--------|
| Merge a main del reference con cambios en `docs/` | Regenerar blueprint y push |
| Merge a main del reference con cambios solo en `src/` | NO regenerar |
| Cambio en ADRs o flows | Regenerar obligatorio |
| Antes de cada conferencia | Regenerar para tener última versión |

---

## Cómo se ve el blueprint en GitHub

```
mnemos-private-search/
├── README.md (versión blueprint)
├── BLUEPRINT.md (instrucciones Copilot)
├── CLAUDE.md
├── .env.example
├── .vscode/mcp.json
├── docker-compose.yml
├── docs/                       ← completo
├── searxng/settings.yml
├── supabase/
│   ├── migrations/             ← completas
│   └── functions/.gitkeep
├── backend/
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile
│   └── src/.gitkeep
├── frontend/
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── index.html
│   └── src/.gitkeep
├── scripts/
│   ├── gcp-setup.sh
│   └── smoke/
└── .github/workflows/
    └── deploy.yml
```

---

## Validación post-generación

Antes de pushear el blueprint, correr:

```bash
cd $BLUEPRINT_DIR
ls backend/src/    # debe estar vacío salvo .gitkeep
ls frontend/src/   # debe estar vacío salvo .gitkeep
cat docs/adr/ADR-001*.md | wc -l    # >50 líneas (no se rompió)
```

---

## Referencias

- ADR-007 — decisión de reference vs blueprint
- `scripts/generate-blueprint.sh` — script de automatización
- `docs/blueprint/BLUEPRINT.md` — template del archivo
- `docs/blueprint/README.blueprint.md` — template del README
