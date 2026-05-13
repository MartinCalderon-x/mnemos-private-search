# ADR-007: Reference repo vs Blueprint clonado

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

mnemos cumple dos roles que normalmente entran en conflicto:

1. **Reference repo** — código completo, validado, que demuestra que la arquitectura funciona
2. **Blueprint** — punto de partida limpio para que Copilot Agent Mode reconstruya el proyecto en vivo durante el demo

Si solo tenemos el reference repo, el demo "queda hecho de antemano" y no demuestra la velocidad de Copilot.  
Si solo tenemos el blueprint, no podemos garantizar que las decisiones funcionan antes del show.

## Decisión

Mantener **dos repos separados** que comparten el mismo `docs/` pero difieren en código:

| Repo | URL | Contenido |
|------|-----|-----------|
| `mnemos` | github.com/MartinCalderon-x/mnemos | Reference completo (este repo) |
| `mnemos-private-search` | github.com/MartinCalderon-x/mnemos-private-search | Limpio, solo specs |

## Diferencias entre ambos

### Lo que va en `mnemos` (reference) — y NO en blueprint
- `backend/src/` — código TypeScript del MCP server
- `frontend/src/` — código React del chat
- `supabase/functions/` — Edge Functions
- `backend/dist/`, `node_modules/` — artefactos
- `package-lock.json` — lockfiles

### Lo que va en ambos
- `README.md`
- `CLAUDE.md`
- `.env.example`
- `docker-compose.yml`
- `searxng/settings.yml`
- `supabase/migrations/*.sql`
- `scripts/gcp-setup.sh`
- `.github/workflows/`
- `docs/` completo (ADRs, flows, plans, testing)
- `.vscode/mcp.json`
- `package.json` (sin código pero con dependencias declaradas)
- Issues de GitHub con criterios de aceptación

### Lo que va SOLO en blueprint
- `BLUEPRINT.md` — instrucciones específicas de cómo Copilot debe reconstruir
- `prompts/` — prompts pre-armados para el demo en vivo

## Proceso de generación del blueprint

```
mnemos (reference)
       │
       ▼
   git clone
       │
       ▼
   eliminar:
   - backend/src/
   - frontend/src/
   - supabase/functions/
   - **/node_modules/
   - **/dist/
       │
       ▼
   agregar:
   - BLUEPRINT.md
   - prompts/
       │
       ▼
   git push → mnemos-private-search
```

Esto se automatiza en `scripts/generate-blueprint.sh`.

## Cómo Copilot reconstruye desde el blueprint

Copilot tiene 3 fuentes de verdad:

1. **`docs/adr/`** — entiende las decisiones tomadas
2. **`docs/flows/agent-decision-flow.md`** — entiende QUÉ construir
3. **GitHub Issues** — entiende EN QUÉ ORDEN y CÓMO VALIDAR

Workflow del demo:

```
1. Audiencia ve repo blueprint (vacío de código)
2. Presenter abre Issue #1 en Copilot
3. Copilot lee criterios + flow doc + ADRs
4. Copilot escribe el código
5. Smoke test del Issue #1 pasa
6. Avanzar al Issue #2
7. Repetir
```

## Por qué separar y no usar branches

Alternativa rechazada: tener una branch `blueprint` en el mismo repo.

**Por qué no:**
- Confunde a la audiencia: ¿estoy en main o en blueprint?
- Riesgo de mergear blueprint a main por accidente
- URLs públicas necesitan repos distintos para ser claras

## Consecuencias

- El reference repo mantiene la verdad completa; cualquier mejora al código se origina acá
- El blueprint se regenera tras cambios significativos en el reference
- Los specs (`docs/`) son el contrato que ambos respetan — si cambian, ambos repos se actualizan
- El demo en vivo es **honestamente reproducible** porque cualquiera puede clonar el blueprint y seguir el mismo path

## Cadencia de actualización del blueprint

| Trigger | Acción |
|---------|--------|
| Issue cerrado en reference con cambios estructurales | Regenerar blueprint |
| ADR nuevo agregado | Regenerar blueprint |
| Cambio en `docs/flows/` | Regenerar blueprint |
| Bugfix en código del reference | NO regenerar (no afecta specs) |

## Referencias

- ADR-003 — multi-MCP orchestration
- `scripts/generate-blueprint.sh` — automatización del proceso
- `docs/plans/blueprint-replication.md` — plan operativo
