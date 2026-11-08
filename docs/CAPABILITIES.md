# Capacidades verificadas del toolchain (nov-2026)

Todo lo de esta página se comprobó contra el entorno real (`android -h`,
subcomandos y `--help`) y contra la documentación oficial. Si algo no aparece
aquí, **no lo inventes**: verifícalo con `android <cmd> -h`.

## Android CLI

CLI oficial para agentes (`android`), estable. Instalación y actualización:

```bash
android update                 # mantenerse al día
android init                   # instala la skill android-cli para tu agente
android skills list            # skills oficiales disponibles
android skills add <name>      # instala en .agents/skills/<name>/
```

Opciones globales: `--sdk=<path>`, `-v`, `-V`, `-h`. Config persistente en
`~/.androidrc` (una opción por línea).

### Proyecto y build

```bash
android create --list                                   # plantillas disponibles
android describe                                        # metadatos: targets, rutas de APK
android build :app@debug                                # build vía CLI
android build gradle://.:app@release -- --offline
android install :app@debug                              # instalación con deltas
android run :app@debug --activity=.MainActivity
```

**Ojo con `android create`**: la CLI puede resolver dos *bundles* distintos con
firmas incompatibles, aunque `android -V` diga lo mismo:

| Interfaz | Flags | Límites |
|---|---|---|
| `legacy` | `--name`, `--minSdk`, `-o`, `[plantilla]` | directorio **vacío**, sin `--force`, **exit 0 aunque falle** |
| `current` | `--name`, `--min-sdk`, `--application-id`, `--namespace`, `--output`, `--force` | la documentada en developer.android.com |

¿Cuál tienes? `android create -h | grep -c -- '--application-id'`.

Por eso el pipeline **nunca** llama a `create` directamente: `scaffold_project.sh`
sondea la interfaz, genera en un directorio temporal, normaliza el paquete
(el bundle legacy ignora `--application-id` y deriva el paquete del nombre de la
app), importa `minSdk/compileSdk/targetSdk` del `spec.json` y valida por
artefactos (`gradlew` + `settings.gradle.kts`), no por código de salida.

Referencia de build: `[system://][path]?[target]` (p. ej. `:app@debug`,
`gradle://./app?:app`, `bazel://?//app:app`).

Plantillas: `empty-activity` (Compose + Activity + AGP 9, por defecto) y
`empty-activity-lightbuild`.

### Emulador y dispositivo

```bash
android emulator create --list-profiles   # small_phone, medium_phone, medium_tablet,
                                          # small_desktop, medium_desktop, large_desktop
android emulator create medium_phone
android emulator start <avd>              # vuelve cuando está completamente arrancado
android emulator list | stop <avd> | remove <avd>
```

### Percepción y control de UI (la clave del bucle visual)

```bash
android screen capture --annotate --output=shot.png   # cajas numeradas #1..#N
android screen resolve --screenshot=shot.png --string="tap #3"
android layout --pretty -o layout.json                # árbol de UI accesible
android input tap "text=Login,clickable=true"
android input text "hola" --device=emulator-5554
android input scroll "scrollable=true" --direction=down
android input key back
```

Selectores por propiedades de accesibilidad: `text|txt`, `id|res`, `class|clz`,
`desc|content`, y booleanos `clickable`, `scrollable`, `checkable`, `focused`,
`selected`, `checked`. Soportan regex con `/.../` y flag `i`. Es la forma
correcta de automatizar sin coordenadas frágiles.

### Previews y testing visual

```bash
android preview list -f json                          # inventario de @Preview
android preview render -o .pipeline/artifacts/previews -f json
android preview render --fqn=com.x.HomePreview --component-tree
```

Renderiza en el host, sin dispositivo y sin IDE. Es el chequeo visual más barato
que existe.

### Calidad y release

```bash
android analyze app-release.apk --analysis=basic -f json
android analyze app-release.apk --analysis=optimization -f json   # R8, tamaño
android profiler ...        # trazas y heap dumps
android signals ...         # Crashlytics: crashes, ANR, no fatales
```

### Conocimiento y Studio

```bash
android docs search "navigation 3 back stack"
android docs fetch kb://...
android studio check
android studio version-lookup androidx.compose:compose-bom com.google.dagger:hilt-android
android studio render-compose-preview
android studio analyze-file | find-usages | find-declaration | open-file
```

`android studio` requiere una instancia de Android Studio en ejecución; todo lo
demás funciona sin IDE.

## Journeys (E2E agéntico)

Android CLI incluye un flujo de *Journeys*: el agente navega la app con
instrucciones en lenguaje natural usando percepción (`screen capture --annotate`,
`layout`) + acción (`input`) + aserción visual. No existe un subcomando de CLI
para ejecutar journeys; la ejecución la hace el agente. El procedimiento está en
`07-device-verification/references/agentic-e2e.md`.

## Skills oficiales de Android (36, nov-2026)

Instalables con `android skills add <nombre>`:

`adaptive` · `agp-9-upgrade` · `android-cli` · `android-for-cars-parked-apps` ·
`android-intent-security` · `android-permissions-security` · `android-profiler` ·
`anr-audit-and-fix` · `appfunctions` · `camerax` ·
`display-glasses-with-jetpack-compose-glimmer` · `edge-to-edge` ·
`engage-sdk-integration` · `glance-appwidget-updates-and-memory` ·
`glance-canonical-layouts` · `ink-app-builder` · `ink-custom-brush-builder` ·
`jetpack-compose-performance` · `leanback-to-compose-tv-migration` · `litert-lm` ·
`litert-runtime` · `media3-cast-integration` · `migrate-xml-views-to-jetpack-compose` ·
`ml-kit-genai-prompt-api` · `mlkit-agent-api` · `navigation-3` ·
`navigation-event` · `play-billing-library-version-upgrade` · `play-policy-insights` ·
`projected-hardware` · `r8-analyzer` · `restore-credentials` · `testing-setup` ·
`verified-email` · `wear-compose-m3` · `wear-widgets`

Recomendadas para este pipeline: `testing-setup` (incluida), `adaptive`,
`edge-to-edge`, `navigation-3`, `jetpack-compose-performance`, `r8-analyzer`,
`android-profiler`, `android-permissions-security`.

Formato de skill (compatible con DSH): carpeta con `SKILL.md`, frontmatter con
`name` (kebab-case, ≤64), `description` (≤1024) y opcionalmente `metadata`;
recursos en `scripts/`, `references/`, `assets/`.

## Versiones de referencia (2026-11-08)

| Artefacto | Estable | Fuente |
|---|---|---|
| AGP | 9.5.1 (plantilla: 9.0.1) | Google Maven |
| Gradle | 9.1.0 (wrapper de la plantilla) | plantilla oficial |
| Kotlin | 2.4.21 (plantilla: 2.3.20) | Maven Central |
| Compose BOM | 2026.09.00 (plantilla: 2026.03.01) | Google Maven |
| Material 3 | 1.4.0 | Google Maven |
| Navigation 3 | 1.2.1 (plantilla: 1.0.1) | Google Maven |
| Room | 2.8.5 | Google Maven |
| Hilt | 2.60.1 | Maven Central |
| KSP | 2.3.13 | Maven Central |
| Roborazzi | 1.78.0 | Maven Central |
| Paparazzi | 1.3.5 | Maven Central |
| MockK | 1.14.12 | Maven Central |
| Turbine | 1.2.1 | Maven Central |
| Ktor | 3.6.1 | Maven Central |
| Coil | 3.6.3 | Maven Central |

**Política**: la plantilla manda. Adoptar "lo último" exige un cambio con gate
(build + tests + screenshots + dispositivo) y una entrada `DL`. Ver
`.agents/skills/02-android-scaffold/references/agp9-baseline.md`.

## Entorno verificado (build real, 2026-11-08)

Prueba ejecutada con la plantilla oficial materializada en el workspace:

| Paso | Resultado |
|---|---|
| Gradle wrapper 9.1.0 sobre JDK 25 (JBR de Android Studio) | arranca: "Full Java 25 support" en sus release notes |
| AGP 9.0.1 `:app:assembleDebug` | `BUILD SUCCESSFUL` en 28 s (36 tasks) |
| Artefacto | `app-debug.apk` de 11,9 MB |
| Bloqueo encontrado | `:app:validateSigningDebug` falla si `~/.android` no es escribible → se resuelve con `ANDROID_USER_HOME` |

Es decir: **JDK 25 es válido** para este stack; no hace falta instalar 21 salvo
que una actualización futura de AGP lo exija.

Scaffold real ejecutado después (G2 completo):

| Paso | Resultado |
|---|---|
| `android create` con bundle **legacy** sobre `app_workspace` no vacío | OK gracias al staging temporal |
| Paquete generado | `com.example.exampleapp` → normalizado a `com.example.app` |
| SDK levels | `compileSdk 36`, `targetSdk 36`, `minSdk 24` desde `spec.json` |
| `verify.sh` (G5) | build + 2 tests + lint en verde; preview advisory |
| Informe | `reports/scaffold-*.json` con `cli_interface: "legacy"` |

### Incidencia conocida: `android preview`

En la versión instalada (`1.1.16717390`), `android preview list|render` falla
antes de compilar el proyecto:

```
java.lang.SecurityException: Illegal entry path escaping destination directory: gradle-build-system
  at com.android.cli.utils.Unzipper.extractEntry(Unzipper.kt:70)
  at com.android.cli.packs.PackManager.pack(PackManager.kt:158)
  at com.android.cli.ui.commands.Preview.runWithResolvedRunfiles(Preview.kt:289)
```

Es un bug del CLI al descomprimir su *gradle pack* (falso positivo del guard
zip-slip), no del proyecto. `android update` responde "Already up-to-date".
Por eso `05-build-test-loop` trata los previews como **advisory**: G5 se decide
con build + tests + lint, y `--require-preview` los hace bloqueantes cuando el
entorno esté corregido. Alternativas de verificación visual: Roborazzi,
Paparazzi o Android Studio (`render-compose-preview`).

## Notas de entorno (Linux, este equipo)

- SDK en `~/Android/Sdk` (platforms 34–37.1, build-tools 34–37).
- `android` escribe en `$HOME/.android/cli`: si el sandbox es de solo lectura,
  los scripts redirigen `HOME` a `.cache/android-cli-home`.
- Gradle necesita `GRADLE_USER_HOME` escribible; fallback a `.cache/gradle-home`.
- Emulador: requiere `/dev/kvm` para aceleración; sin él, usa dispositivo físico.
- Headless: `emulator -no-window` o `android emulator start --headless` según versión.

## Referencias

- Android CLI: <https://developer.android.com/tools/agents/android-cli>
- Skills oficiales: <https://developer.android.com/tools/agents/android-skills> · <https://github.com/android/skills>
- Plantillas: `android create --list`
- Screenshot testing con test suites de AGP: <https://developer.android.com/studio/preview/compose-screenshot-testing-with-testsuites>
- AGP 9 release notes: <https://developer.android.com/build/releases/agp-9-0-0-release-notes>
