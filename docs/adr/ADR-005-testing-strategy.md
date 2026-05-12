# ADR-005: Estrategia de Testing

**Fecha:** 2026-05-08  
**Estado:** Aceptado  
**Autores:** Martin Calderon

---

## Contexto

mnemos es un demo público que debe ser **confiable**. No queremos:
- Tests que existen pero nadie corre
- Tests sin sentido del tipo "espía la implementación"
- Falta total de tests que rompa el demo en vivo
- Suite de 200 tests para un proyecto de 5 archivos

Para un demo blueprint, la estrategia debe ser **mínima pero efectiva**.

## Decisión

**Tres niveles de testing**, cada uno con su propósito y tooling claro:

```
┌─────────────────────────────────────────────────────────────┐
│  Nivel 1 — Smoke tests (curl scripts)                       │
│  Validan que cada servicio responde                         │
│  Corrida: manual, antes de cerrar issue                     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Nivel 2 — Integration tests (Vitest, en backend)           │
│  Validan flujos end-to-end con DB real (Supabase test)      │
│  Corrida: CI en cada PR                                     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Nivel 3 — Demo checklist (manual, antes del show)          │
│  Garantiza que el demo en vivo funciona                     │
│  Corrida: 1 hora antes de la presentación                   │
└─────────────────────────────────────────────────────────────┘
```

## Nivel 1 — Smoke tests

**Tooling:** bash + curl + jq.  
**Ubicación:** `scripts/smoke/`  
**Cuándo correr:** al cerrar cada issue, manualmente.

Ejemplos:

```bash
scripts/smoke/01-searxng.sh      # cierra issue #3
scripts/smoke/02-supabase.sh     # cierra issue #2
scripts/smoke/03-http-api.sh     # cierra issue #1
scripts/smoke/04-frontend.sh     # cierra issue #4
scripts/smoke/05-end-to-end.sh   # smoke completo del modo Local
```

Cada script imprime:
- ✓ verde si pasa
- ✗ rojo + razón si falla
- Output crudo para adjuntar como evidencia al cerrar el issue

## Nivel 2 — Integration tests

**Tooling:** Vitest (backend), Playwright (frontend).  
**Ubicación:** `backend/tests/integration/`, `frontend/tests/e2e/`  
**Cuándo correr:** CI en cada push.

Cobertura objetivo:

| Componente | Tests | Foco |
|-----------|-------|------|
| `tools/saveToKnowledge` | 2-3 | Insert + embedding generation |
| `tools/semanticSearch` | 2-3 | Match con threshold, filter source |
| `tools/anonymousSearch` | 1-2 | SearxNG response parsing |
| `http/routes/*` | 4 | 1 por endpoint |
| Frontend `useChat` | 2 | Happy path + error handling |

**No vamos a testear:**
- Configuración de Supabase (es plataforma)
- Detalles de UI (clases CSS, posiciones)
- LLM responses textuales (no determinístico)

## Nivel 3 — Demo checklist

**Tooling:** Markdown checklist humana.  
**Ubicación:** `docs/testing/production-checklist.md`  
**Cuándo correr:** ~1 hora antes del demo en vivo.

Pasos:
1. Abrir URL pública en navegador limpio
2. Ejecutar las 3 queries del demo script
3. Verificar que thinking steps son visibles
4. Verificar que se guarda al knowledge base
5. Probar que Copilot conecta con los 3 MCPs
6. Backup: tener video pre-grabado del demo por si falla algo en vivo

## Política de tests rotos

- Si un smoke test rompe → bloquea cierre de issue
- Si un integration test rompe → bloquea merge
- Si demo checklist falla → cancelar el demo o usar el backup

## Tests del MCP server

El MCP server tiene una particularidad: lo consume Copilot, no testers humanos. Para validarlo:

```bash
# Iniciar MCP server con el inspector oficial
npx @modelcontextprotocol/inspector node backend/dist/index.js
```

El inspector permite invocar las 3 tools manualmente y ver request/response. Esto reemplaza tests unitarios para el MCP transport — la lógica de las tools sí se testea con Vitest.

## Consecuencias

- `scripts/smoke/` es la "single source of truth" para validar issues
- CI corre Vitest pero no smoke tests (smoke requiere infra real)
- Los smoke tests se incluyen en el blueprint clonado — Copilot los corre tras implementar
- Cada issue de implementación incluye, en su sección Testing, qué smoke script lo valida

## Referencias

- ADR-004 — modos Local vs Profesional
- `docs/testing/strategy.md` — guía operativa
- `docs/testing/local-checklist.md` y `production-checklist.md`
