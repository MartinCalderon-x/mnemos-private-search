# Checklist — Producción / Demo en vivo

> **CRÍTICO:** Completar 60-90 minutos antes del demo en vivo.  
> Si algún item falla, NO salir al escenario sin resolver o sin tener backup video.

**Fecha del demo:** _____________  
**Hora del demo:** _____________  
**Validador:** _____________  
**Tiempo de validación:** _____________

---

## 90 min antes — Infraestructura

- [ ] `gcloud run services list --region us-central1` muestra los 3 servicios `READY`:
  - [ ] `mnemos-backend`
  - [ ] `mnemos-frontend`
  - [ ] `mnemos-searxng`
- [ ] `supabase functions list` muestra las 4 functions `ACTIVE`
- [ ] `gcloud secrets list` muestra los secrets esperados
- [ ] No hay alertas en Cloud Monitoring para los servicios
- [ ] Billing alerts no se han disparado

---

## 60 min antes — URLs públicas

- [ ] URL frontend abre en navegador limpio (modo incógnito)
- [ ] No hay errores en consola del browser
- [ ] El proxy hacia las edge functions funciona
- [ ] Una query end-to-end funciona desde la URL pública
- [ ] Tiempo de respuesta total <8s (p99)

**Smoke:** `./scripts/smoke/06-production.sh`

---

## 60 min antes — Pre-warm anti cold-start

- [ ] Cloud Scheduler con job `mnemos-warmup` está corriendo
- [ ] Manualmente hacer `curl` a las 3 URLs para pre-warmear
- [ ] Verificar que los servicios respondieron (no 503)

---

## 45 min antes — Datos del demo

- [ ] La knowledge base **NO está vacía** del todo (tener 2-3 entradas pre-cargadas para demos de RAG)
- [ ] La knowledge base **NO tiene entradas duplicadas** que confundan el demo
- [ ] Verificar con `SELECT count(*), title FROM knowledge_base GROUP BY title;`

**Queries de demo a ensayar:**

1. ___________________________  (debe usar RAG)
2. ___________________________  (debe usar web search)
3. ___________________________  (debe usar mixed)

---

## 30 min antes — MCPs externos para Copilot

- [ ] `.vscode/mcp.json` cargado en VS Code
- [ ] Copilot reconoce `supabase` MCP — probar prompt
- [ ] Copilot reconoce `gcp` MCP — probar prompt
- [ ] Copilot reconoce `mnemos` MCP — probar prompt
- [ ] Las credenciales en variables de entorno del shell están vigentes
- [ ] `gcloud auth application-default print-access-token` no expiró

---

## 30 min antes — Backup plans

- [ ] Video pre-grabado del demo subido y accesible
- [ ] Slides con frases clave listos
- [ ] Hotspot del celular probado (red del venue puede fallar)
- [ ] Tener `mnemos-private-search` checkout local por si falla GitHub
- [ ] Power: laptop cargada al 100%, cargador en mochila

---

## 15 min antes — Última validación

- [ ] Refrescar URL del frontend → carga sin error
- [ ] Una query rápida al chat → responde
- [ ] Copilot responde a un prompt de prueba
- [ ] Cerrar todas las tabs/apps que no son del demo
- [ ] Modo "no molestar" del sistema activado

---

## 5 min antes — Rituales

- [ ] Agua al lado
- [ ] Notificaciones del celular silenciadas
- [ ] El timer de 30 min está armado
- [ ] Respirar

---

## Durante el demo — observables a monitorear

(Tener una segunda pantalla con esto si es posible)

- [ ] `gcloud logging tail` corriendo para ver errores en vivo
- [ ] Cloud Run dashboard abierto para ver métricas

---

## Después del demo — post-mortem

- [ ] ¿Cuántos errores en vivo?
- [ ] ¿Qué tardó más de lo esperado?
- [ ] ¿Qué preguntó la audiencia que no estaba en el guion?
- [ ] ¿Qué se podría mejorar?

Anotar en `docs/sessions/reports/<fecha>-demo-postmortem.md`.

---

## Resultado

- [ ] **TODOS los items pasados** → READY for stage
- [ ] **Algún item crítico falló** → Activar plan B (video grabado)

---

## Notas del validador

```
(usar este espacio para anotar cualquier cosa rara o digna de mencionar)
```
