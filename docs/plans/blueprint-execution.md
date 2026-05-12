# Plan — Convertir mnemos en Blueprint ejecutable por Copilot

> **Actualización 2026-05-12 — ADR-013:** el blueprint ahora vive en un repo
> público hermano (`mnemos-private-search`), no en una carpeta dentro de este repo.
> El reference privado (este) genera + sincroniza al público vía
> `scripts/generate-blueprint.sh` (issue #12).

> Objetivo de la sesión: dejar el repo en un estado donde **alguien con
> GitHub Copilot + un .env válido pueda reconstruir el sistema desde cero**
> en vivo, sin haber visto nuestro código de implementación.

---

## Contexto al arrancar

**Lo que ya existe:**
- 9 ADRs (decisiones auditables)
- Paper completo (`docs/paper/mnemos.md`)
- 15 issues abiertos/cerrados con acceptance + smoke como contrato
- 8 smoke tests + 3 validators ejecutables
- Migraciones SQL listas
- docker-compose y searxng/settings.yml
- Implementación de referencia funcional en `backend/src/` y `frontend/src/`

**Lo que falta para ser blueprint:**
1. Script generador que extrae el subset "specs only"
2. README orientado al modo blueprint
3. `.vscode/mcp.json` con los 3 MCPs (issue #6)
4. Documento `BLUEPRINT.md` con instrucciones de secrets + flujo

---

## Decisión de secrets (tomada en sesión 2026-05-09)

| Capa | Storage | Quién lo lee |
|------|---------|--------------|
| Local dev | `.env` (gitignored) | dev en su máquina |
| CI / Actions | GitHub Secrets | workflows de deploy |
| Cloud Run runtime | GCP Secret Manager | servicios en producción |
| GCP auth en CI | Workload Identity Federation (sin keys) | github-actions/auth |

**Repo público** — viable porque:
- GitHub Secrets son encryption-at-rest, redactados en logs
- No se heredan a forks; PRs de forks no acceden
- WIF elimina service account keys del repo

Lista mínima de secrets a configurar en GitHub:
- `OPENROUTER_API_KEY`
- `SUPABASE_URL`, `SUPABASE_SECRET_KEY` (o usar GCP Secret Manager y pasar refs)
- `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT` (Workload Identity)
- `GCP_PROJECT`

---

## Orden de ejecución

### Fase A — Cerrar #6 (multi-MCP config)
- `scripts/validate/mcp-config.sh` ya define el contrato
- Crear `.vscode/mcp.json` con los 3 servers: supabase, gcp, mnemos
- Validar: `./scripts/validate/mcp-config.sh` → PASS
- Cerrar #6 con evidencia

### Fase B — Cerrar #12 (generate-blueprint.sh)
- `scripts/validate/blueprint.sh` ya define el contrato
- Crear `scripts/generate-blueprint.sh` que:
  1. Acepta dir destino como argumento
  2. Copia: `docs/`, `scripts/smoke/`, `scripts/validate/`, `supabase/`,
     `searxng/`, `docker-compose.yml`, `.env.example`, `.gitignore`,
     `tsconfig.json` raíz si aplica
  3. Crea `backend/` y `frontend/` con `package.json` + configs PERO sin `src/`
  4. Genera `BLUEPRINT.md` (ver Fase C)
  5. Genera `.vscode/mcp.json` desde el ejemplo
  6. NO copia `backend/src/`, `frontend/src/`, `.env`, `node_modules`,
     `dist`, `.git`
- Validar: `./scripts/validate/blueprint.sh` → PASS
- Cerrar #12 con evidencia

### Fase C — Documentación del modo blueprint
Crear `BLUEPRINT.md` en root con secciones:

1. **Qué es esto** — un repo que GitHub Copilot puede usar para
   reconstruir mnemos. No tiene código de implementación; tiene
   contratos.
2. **Setup en 5 pasos:**
   - Clone
   - Copy `.env.example` → `.env` y completá
   - `docker compose up -d searxng`
   - Apuntar Supabase con tu propio proyecto + correr migraciones
   - Abrir VSCode → Copilot detecta `.vscode/mcp.json`
3. **Reconstrucción asistida:**
   - Ir a Issues
   - Empezar por #10 (smoke), seguir #3 → #2 → #1 → #4
   - Cada issue tiene "Definición de done" = smoke pasa
   - Pedirle a Copilot: "implementá lo necesario para cerrar issue #N"
4. **Secrets**: tabla de qué va dónde
5. **Validación final:** `./scripts/smoke/05-end-to-end.sh` → PASS

### Fase D — README rewrite
El README actual mezcla reference + blueprint. Separar:
- README.md → corto, dos modos (Reference para entender, Blueprint para clonar)
- Mover la sección técnica detallada a `docs/paper/mnemos.md` (ya hecho)

### Fase E — Validación E2E del blueprint
1. `./scripts/generate-blueprint.sh /tmp/mnemos-private-search-test`
2. `cd /tmp/mnemos-private-search-test`
3. Inicializar git, instalar Copilot CLI o abrir en VSCode
4. Implementar #3 (SearxNG) — debería tardar < 5min
5. Smoke 01 → PASS
6. Repetir para #2, #1, #4
7. Smoke 05 → PASS
8. Reportar tiempo total — métrica para el demo

---

## Criterio de done de la sesión

- [ ] Issue #6 cerrado con `mcp-config.sh` PASS
- [ ] Issue #12 cerrado con `blueprint.sh` PASS
- [ ] `BLUEPRINT.md` existe y describe los 5 pasos
- [ ] `README.md` separa modos Reference vs Blueprint
- [ ] Validación E2E: blueprint generado + reconstruido + smoke 05 PASS
- [ ] Métrica capturada: tiempo de reconstrucción asistida por Copilot

---

## Riesgos identificados

1. **Copilot puede generar código que no pasa el smoke por matices** —
   ej: nombres de campos JSON ligeramente distintos. Mitigación: el
   smoke debe explicitar el shape esperado en los mensajes de error.
2. **El modelo del agente no respeta el flujo del docs/flows/agent-decision-flow.md** —
   ej: olvida el judge de ADR-009. Mitigación: incluir ADRs en el blueprint
   y hacer referencia explícita en cada issue.
3. **Demo en vivo: ancho de banda variable** — el primer save dispara
   descarga del modelo de embeddings (~80MB). Mitigación: pre-warm
   antes del show, o cambiar a modelo aún más liviano si latencia importa.

---

## Notas para retomar

- La rama activa es `main`, todo pusheado.
- Backend está corriendo en background (`/tmp/mnemos-backend.log`).
  Reiniciar con `cd backend && nohup node dist/index.js > /tmp/mnemos-backend.log 2>&1 &`
- Frontend dev también en background (`/tmp/mnemos-frontend.log`).
- KB tiene 1 fila válida (definición de MCP guardada por el usuario).
- DB password de Supabase no se necesita más (link ya hecho con `.temp/project-ref`).
