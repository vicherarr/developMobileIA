# my-android-agentic-pipeline

Sistema agéntico para construir una app Android **de la idea al release** con
DeepSeek Harness (y cualquier agente compatible con skills), usando las
herramientas oficiales actuales: **Android CLI**, plantillas oficiales de
proyecto, AGP 9 con Kotlin integrado, Jetpack Compose + Navigation 3, y
verificación visual/testing sin IDE.

```
my-android-agentic-pipeline/
├── .agents/skills/              # Skills (DSH y Android CLI leen esta misma ruta)
│   ├── 00-pipeline-orchestrator # máquina de estados G0-G7, contrato y gates
│   ├── 01-spec-and-scope        # idea -> spec.json + plan.md (G1)
│   ├── 02-android-scaffold      # android create + catálogo de versiones (G2)
│   ├── 03-domain-and-data       # Room, repositorios, casos de uso (G3)
│   ├── 04-ui-compose            # pantallas, ViewModels, Nav3, previews (G4)
│   ├── 05-build-test-loop       # bucle determinista build/test/lint/preview (G5)
│   ├── 06-testing-strategy      # pirámide de tests y screenshot testing
│   ├── 07-device-verification   # emulador, capturas, layout, input, journeys (G6)
│   ├── 08-release-and-quality   # R8, tamaño, firma, checklist Play (G7)
│   ├── 09-human-review          # cola ASDD: cuándo preguntar y cuándo asumir
│   ├── 10-project-memory        # memoria persistente y economía de tokens
│   └── testing-setup            # skill oficial de Google (android skills add)
├── 00_memory/                   # ARCHITECTURE · TECH_STACK · DECISION_LOG · SESSION_STATE
├── 02_pending_review/           # human_decisions.md (HD-###) que bloquean la línea
├── app_workspace/               # proyecto Android generado + .pipeline/ (estado y evidencia)
├── docs/                        # arquitectura del pipeline e inventario de herramientas
└── scripts/                     # android_env · bootstrap · doctor · setup_host · check_pipeline
```

## Por qué la estructura difiere de la propuesta inicial

Tu boceto tenía `01_skills/01-spec-and-scope/SKILL.md`. Eso **no funciona** en
DSH: el descubrimiento de skills es de **un solo nivel** y solo mira raíces
concretas —`.dsh/skills`, `.agents/skills`, `~/.dsh/skills`, `~/.agents/skills`—,
nunca `**/SKILL.md` anidados. Android CLI instala las suyas exactamente en
`.agents/skills/<nombre>/`, así que esa es la única ruta que ambos leen.

Decisiones tomadas:

| Boceto | Implementación | Motivo |
|---|---|---|
| `01_skills/…/SKILL.md` | `.agents/skills/<slug>/SKILL.md` | descubrimiento real de DSH + Android CLI |
| 5 skills | 11 skills + 1 oficial | cubre el ciclo completo y separa responsabilidades |
| `00_memory/` | igual, más `SESSION_STATE.md` | el estado volátil evita releer el repo |
| `02_pending_review/` | igual, con `HD-###` y plantilla | preguntas con opciones, no diálogos abiertos |
| `app_workspace/` | igual, más `.pipeline/` | la evidencia es lo que decide si un gate pasa |
| scripts sueltos | `scripts/` + `references/` + `assets/` por skill | formato estándar de agent skills |

Los nombres con prefijo numérico se conservan a propósito: ordenan el flujo en el
catálogo y son válidos (kebab-case admite dígitos).

## Ciclo de vida

| Gate | Fase | Evidencia obligatoria |
|---|---|---|
| G0 | intake y memoria | `00_memory/SESSION_STATE.md` actualizado |
| G1 | spec y alcance | `.pipeline/spec.json` + `.pipeline/plan.md` |
| G2 | scaffold | `reports/scaffold-*.json` con `pass` |
| G3 | dominio y datos | `reports/domain-*.json` (tests verdes) |
| G4 | UI Compose | `reports/ui-*.json` (previews renderizan) |
| G5 | build + tests + lint | `reports/verify-*.json` con `pass` |
| G6 | verificación en dispositivo | `reports/device-*.json` + PNGs |
| G7 | release y calidad | `reports/quality-*.json` con `pass` |

Sin archivo de evidencia, el gate está abierto. Esa es la regla que evita el
clásico "ya compila" sin pruebas.

## Inicio rápido

```bash
cd my-android-agentic-pipeline
./scripts/bootstrap.sh          # estado + memoria + verificación de skills
make setup-host                 # fuera del sandbox: JDK, KVM, SDK, AVD
make doctor                     # diagnóstico del entorno (SDK, JDK, CLI, emulador)

# en DeepSeek Harness, desde esta carpeta:
#   «Quiero una app de X. Empieza por el spec y llévame hasta G5.»
```

El agente cargará `00-pipeline-orchestrator`, escribirá `spec.json`, ejecutará
`02-android-scaffold/scripts/scaffold_project.sh`, iterará con
`05-build-test-loop/scripts/verify.sh` y verificará en dispositivo con
`07-device-verification/scripts/device_check.sh`.

Para ver el pipeline en acción sin escribir código a mano:

```bash
# 1. spec (lo escribe el agente en G1)
# 2. proyecto real, generado por la plantilla oficial
.agents/skills/02-android-scaffold/scripts/scaffold_project.sh --dry-run
# 3. bucle cerrado
.agents/skills/05-build-test-loop/scripts/verify.sh
```

Atajos (`make help` lista todo):

| Comando | Hace |
|---|---|
| `make check` | autolint del kit (skills, scripts, contratos, CLI) |
| `make doctor` | diagnostica SDK, JDK, CLI, emulador |
| `make scaffold` | G2: crea el proyecto y lo compila |
| `make verify` | G5: build + tests + lint + previews |
| `make device` | G6: arranca emulador y ejecuta la app |
| `make device-check` | G6: captura + layout + crash log como evidencia |
| `make release` | G7: release, R8, tamaño y QA |
| `make skills` | lista skills del pipeline y oficiales |

## Entorno verificado en esta máquina

Comprobado ejecutando el toolchain real, no leyendo documentación:

| Comprobación | Resultado | Qué hacer |
|---|---|---|
| JDK 25 (JBR) + Gradle 9.1 + AGP 9.0.1 | **build OK**: `:app:assembleDebug` → APK de 11,9 MB | nada; Gradle 9.1 trae soporte Java 25 y el toolchain de AGP sigue en 17 |
| `/dev/kvm` | ausente **solo dentro del sandbox del agente** (el kernel lo expone en `/proc/misc` como `232 kvm`) | en tu terminal: `ls -l /dev/kvm`; si falta, `make setup-host -- --yes` |
| SDK escribible | solo-lectura dentro del sandbox (`/home` va montado `ro`) | tu shell puede escribir; `make setup-host` lo verifica |
| AVD | **creado**: `medium_phone` (android-36, google_apis_playstore, x86_64, 2 GB RAM) | `android emulator list` |
| HOME escribible | necesario para el keystore de debug | los scripts usan `ANDROID_USER_HOME=.cache/android-user-home` cuando `HOME` es de solo lectura |
| `android preview` | bug del CLI 1.1.16717390 al descomprimir su pack (`gradle-build-system`) | no bloquea G5; usa Roborazzi/Paparazzi o `--require-preview` cuando se corrija |

Consecuencia práctica: **los avisos del doctor son del sandbox, no de tu host**.
Fuera del agente solo queda confirmar que `/dev/kvm` es accesible para tu
usuario (`make setup-host`). El AVD ya está creado.

## Herramientas que usa (verificadas, nov-2026)

- **Android CLI** (`android`), el CLI oficial para agentes: `create`, `build`,
  `install`, `run`, `emulator`, `preview list|render`, `screen capture|resolve`,
  `layout`, `input`, `analyze`, `profiler`, `signals`, `docs`, `skills`, `studio`.
- **Plantilla oficial** `empty-activity` (AGP 9.0.1, Gradle 9.1.0, Kotlin 2.3.20,
  Compose BOM 2026.03.01, compileSdk 36, minSdk 24, Navigation 3).
- **AGP 9 con Kotlin integrado** (sin `kotlin-android`, sin kapt: KSP2).
- **Compose Preview Screenshot Testing vía AGP test suites** (recomendado por
  Google) y, como alternativa estable, Roborazzi / Paparazzi.
- **Android skills oficiales**: `android skills add <name>` (`adaptive`,
  `edge-to-edge`, `navigation-3`, `testing-setup`, `r8-analyzer`, …).

Detalle y comandos exactos: `docs/CAPABILITIES.md`. Versiones y política de
actualización: `docs/PIPELINE.md` y `.agents/skills/02-android-scaffold/references/agp9-baseline.md`.

## Adoptarlo en otro proyecto

```bash
# copia el kit donde quieras y enlázalo como raíz de proyecto
cp -R my-android-agentic-pipeline ~/src/mi-app
cd ~/src/mi-app
./scripts/bootstrap.sh --link-into /ruta/al/proyecto-existente
```

`bootstrap.sh --link-into` crea el symlink `.agents -> <kit>/.agents` en el
proyecto destino, que es lo que hace que DSH y Android CLI vean las skills sin
duplicarlas.

## Mantenimiento

```bash
android update                       # actualizar Android CLI
android skills add testing-setup     # refrescar skills oficiales
./scripts/doctor.sh                  # comprobar entorno tras actualizar
```

## Principios

1. **Especificar antes de codificar.** El fallo más caro es construir rápido lo
   equivocado.
2. **Evidencia sobre opinión.** Cada gate deja un JSON verificable.
3. **Asumir lo técnico, preguntar lo de negocio.** `DL` para lo reversible, `HD`
   para lo que cuesta dinero o es irreversible.
4. **Una corrección por iteración.** Tres intentos sobre el mismo error → parar
   y escalar.
5. **Contexto mínimo.** Cuatro archivos de memoria en vez de releer el repo.
6. **Nunca desactivar un check para pasar un gate.**
