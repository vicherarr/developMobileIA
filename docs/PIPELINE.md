# Arquitectura del pipeline

Este documento explica **por qué** el kit está construido así. Para el uso
diario, basta `README.md`; para operar la máquina de estados, la skill
`00-pipeline-orchestrator`.

## Problema que resuelve

Un agente sin estructura falla de tres maneras predecibles:

1. **Construye rápido lo equivocado** — no hay fase de especificación.
2. **Declara éxito sin evidencia** — "ya compila" sin build, sin tests, sin
   captura de pantalla.
3. **Quema contexto** — relee el repositorio entero en cada sesión y repite
   comandos que no cambian el resultado.

El kit ataca cada una con un mecanismo distinto: `spec.json` (1), reportes JSON
por gate (2) y la capa de memoria de cuatro archivos (3).

## Separación de responsabilidades

| Capa | Qué contiene | Qué NO contiene |
|---|---|---|
| Skills (`.agents/skills/`) | procedimientos reutilizables, comandos exactos, criterios de parada | estado del proyecto |
| Memoria (`00_memory/`) | decisiones, versiones, arquitectura, estado de sesión | procedimientos |
| Estado (`.pipeline/`) | gate actual, spec, evidencia | conocimiento reutilizable |
| Proyecto (`app_workspace/`) | código Android real | estado del agente |

La regla de oro: **una skill no guarda estado y la memoria no guarda
procedimientos**. Cuando algo se aprende de un proyecto concreto, va a memoria;
cuando sirve para cualquier proyecto, va a la skill.

## Máquina de estados

```
G0 intake ──▶ G1 spec ──▶ G2 scaffold ──▶ G3 domain/data ──▶ G4 ui
                                              │                │
                                              ▼                ▼
                                          G5 build+test ◀──────┘
                                              │
                                              ▼
                                          G6 device ──▶ G7 release
```

Propiedades:

- **Cada gate tiene un dueño** (una skill) y **una evidencia** (un archivo).
- **Los gates pueden retroceder**: un cambio tras G5 reabre G5.
- **Un gate bloqueado detiene la línea**: si `STATE.json.blocking` no está vacío,
  lo único legítimo es resolver la pregunta.
- **La evidencia es dato, no narrativa**: se escribe con `emit_report` de forma
  atómica para que un script interrumpido no deje un archivo a medias.

Formato de evidencia (`reports/verify-<UTC>.json`):

```json
{
  "schema": 1,
  "gate": "G5",
  "status": "pass",
  "steps": [{"name": "build", "status": "pass"}, {"name": "test", "status": "pass"}],
  "unit_tests": {"tests": 12, "failures": 0, "errors": 0, "skipped": 0},
  "lint": {"errors": 0, "warnings": 3},
  "previews": {"count": 6},
  "apk": "app/build/outputs/apk/debug/app-debug.apk",
  "timestamp": "2026-11-08T16:05:42Z"
}
```

## Contrato entre skills

Cada `SKILL.md` abre con un bloque `## Contract`:

- **Reads** — archivos que necesita (y solo esos).
- **Writes** — archivos que produce.
- **Gate** — qué gate sirve.
- **Handoff** — qué skill continúa.

Eso permite al orquestador encadenar sin leer todas las skills, y permite
ejecutar una skill aislada con garantías.

## Economía de contexto

| Situación | Leer | No leer |
|---|---|---|
| Empezar sesión | `SESSION_STATE.md` | el repo |
| Añadir dependencia | `TECH_STACK.md` + `libs.versions.toml` | todos los `build.gradle.kts` |
| Añadir pantalla | `SESSION_STATE.md` + `spec.json` + 1 pantalla existente | todo `ui/` |
| Arreglar build | el primer `e:` del log | el log completo |
| Reanudar tras bloqueo | `human_decisions.md` + `STATE.json` | historial de chat |

El estado volátil se reescribe al final de cada sesión; el histórico de
decisiones es *append-only*.

## Por qué Android CLI

`android` es el CLI oficial pensado para agentes: abstrae Gradle, instala con
deltas, arranca emuladores y **hace visible el resultado** (`screen capture
--annotate`, `layout`, `preview render`). Eso convierte "creo que funciona" en
una captura que el agente puede mirar. Detalle en `docs/CAPABILITIES.md`.

## Cómo extender el kit

Añadir una skill (p. ej. `11-payments`):

1. Crea `.agents/skills/11-payments/SKILL.md` (hijo **directo** de la raíz, no
   anidado) con frontmatter `name`, `description`, `metadata`.
2. Escribe el `## Contract` y el gate que sirve (puede ser un sub-gate de G7).
3. Añade la fila a la tabla de routing de `00-pipeline-orchestrator`.
4. Añade el gate a la tabla de `README.md` y a `AGENTS.md` si cambia el flujo.
5. Verifica que aparece en el catálogo (DSH lo recarga sin reiniciar).

Añadir un gate: nuevo id, evidencia propia, dueño, y actualizar orquestador +
`README.md` + `AGENTS.md`. No añadas un gate sin evidencia: sería teatro.

## Anti-patrones que el kit prohíbe explícitamente

- Escribir Gradle a mano "porque es más rápido".
- Marcar un gate en verde sin el JSON de evidencia.
- Desactivar lint/tests/R8 para pasar el gate.
- Suponer precios, autenticación o datos personales.
- Reintentar el mismo comando esperando otro resultado.
- Duplicar versiones entre `TECH_STACK.md` y el catálogo.
- Añadir skills anidadas (`x/y/SKILL.md`): no se descubren.

## Métricas de salud

| Señal | Sano | Enfermo |
|---|---|---|
| Gates con evidencia | 100% | "creo que pasó" |
| `TECH_STACK.md` vs catálogo | idénticos | drift |
| Preguntas bloqueantes abiertas | ≤ 3 | cola infinita |
| Iteraciones por error | ≤ 3 | bucles |
| `DECISION_LOG.md` | crece | vacío |
