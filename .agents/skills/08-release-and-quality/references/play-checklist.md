# Play Store readiness checklist (G7)

Use this list before a release upload. Every box needs evidence: a command
output, a file path, or a recorded human decision. Check items in order; later
groups assume the build and signing path already work. Commands run from
`app_workspace/`. A checked box with no evidence is not checked.

## 1. Build and artifact integrity

- [ ] Release build completes from a clean state: `./gradlew :app:assembleRelease :app:bundleRelease` exits 0.
- [ ] AAB exists: `ls -l app/build/outputs/bundle/release/app-release.aab`.
- [ ] APK exists for device spot checks: `ls -l app/build/outputs/apk/release/app-release.apk`.
- [ ] R8 ran: `ls -l app/build/outputs/mapping/release/mapping.txt` exists and is non-empty.
- [ ] Release build is minified and shrunk (AGP 9 defaults on): inspect `quality-gradle-*.log` for the `minifyReleaseWithR8` and `shrinkReleaseRes` tasks.
- [ ] Unit tests and lint are green: `./gradlew :app:testDebugUnitTest :app:lintRelease` exits 0.
- [ ] Version bumped: `grep -nE 'versionCode|versionName' app/build.gradle.kts` shows a strictly higher `versionCode` than the last upload.
- [ ] `applicationId` unchanged since the last release (changing it creates a new app).
- [ ] No debug-only dependency or `debugImplementation` artifact leaks into release (check `android analyze ... --analysis=basic` output).

## 2. Manifest and components

- [ ] Every component with an intent filter declares `android:exported`: `grep -n -A3 '<intent-filter>' app/src/main/AndroidManifest.xml` and confirm each parent has `android:exported` (the quality gate flags violations).
- [ ] Exported components are intentional and minimal; no exported `Activity`/`Service`/`Receiver`/`Provider` without a reason.
- [ ] No `android:debuggable="true"` anywhere in release paths: `grep -rn 'android:debuggable' app/src/*/AndroidManifest.xml`.
- [ ] No `android:usesCleartextTraffic="true"`: `grep -rn 'usesCleartextTraffic' app/src/*/AndroidManifest.xml`.
- [ ] Network security config is explicit if used, and release forbids cleartext: check `app/src/main/res/xml/network_security_config.xml`.
- [ ] Backup policy decided: `android:allowBackup`, `android:dataExtractionRules` (API 31+) and `android:fullBackupContent` are set intentionally.
- [ ] Merged release manifest inspected: `app/build/intermediates/merged_manifests/release/AndroidManifest.xml`.
- [ ] App icon and label present; adaptive icon for API 26+.
- [ ] `android:enableOnBackInvokedCallback` is not set to `false`; predictive back works.

## 3. SDK levels and platform support

- [ ] `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`: `grep -nE 'compileSdk|targetSdk|minSdk' app/build.gradle.kts`.
- [ ] `targetSdk` meets the Play policy in force at submission time (baseline 36); record the policy check date in `SESSION_STATE.md`.
- [ ] JVM target 17: `grep -n 'jvmTarget\|JavaVersion' app/build.gradle.kts`.
- [ ] AGP 9 built-in Kotlin: no `org.jetbrains.kotlin.android` plugin applied; KSP2 in use, no kapt.
- [ ] 64-bit support: if native code exists, the AAB ships `arm64-v8a`; inspect `android analyze app/build/outputs/apk/release/app-release.apk --analysis=basic -f json`.
- [ ] 16 KB page-size support if native code targets Android 15+: verify `.so` alignment/packaging evidence; this is a Play requirement for new app versions.
- [ ] No `abiFilters` accidentally dropping 64-bit ABIs.

## 4. Permissions and privacy

- [ ] Every permission in the merged manifest is used by a feature: `grep -n 'uses-permission' app/build/intermediates/merged_manifests/release/AndroidManifest.xml`.
- [ ] Dangerous permissions have a user-facing rationale and a runtime request path.
- [ ] Sensitive declarations match Play forms: background location, exact alarms, SMS/call log, all-files access — remove what is not needed.
- [ ] Foreground services declare a valid `android:foregroundServiceType` (required for targetSdk 34+).
- [ ] Notification permission (`POST_NOTIFICATIONS`) is requested in context and denied gracefully.
- [ ] Photo picker or scoped media access is used instead of broad storage permissions.
- [ ] Advertising ID usage declared (`com.google.android.gms.permission.AD_ID`) only if ads/analytics need it.
- [ ] Data safety form matches reality: what is collected, shared, encrypted in transit, deletion path.
- [ ] Privacy policy URL is live and reachable from the store listing and, if required, in-app.
- [ ] If the app creates accounts, in-app and web account deletion are implemented and documented (Play account deletion policy).
- [ ] No personal data, tokens or passwords in logs: `grep -rn 'Log\.[dvi](' app/src/main | head -n 20` and review hits.
- [ ] No hardcoded secrets: the quality gate `hardcoded-secret` finding is empty.

## 5. Size, R8 and performance

- [ ] APK within budget vs `artifacts/size-baseline.json`: read `size` in `reports/quality-<UTC>.json`; growth ≤ limit.
- [ ] `android analyze ... --analysis=optimization -f json` reviewed for unexpected classes, resources, native libs.
- [ ] `android analyze ... --analysis=basic -f json` reviewed for permissions, SDK levels and components.
- [ ] Dependencies pruned; no unused Compose or support libraries dragged in transitively.
- [ ] Resources shrunk (AGP 9 optimized shrinking on); no unused large assets in `app/src/main/res/raw`.
- [ ] Startup measured at least once (cold start), and no blocking work on the main thread.
- [ ] Optional upgrade: baseline profiles / Macrobenchmark when startup or scroll performance is a stated requirement.
- [ ] Optional: `android profiler` used for a jank or memory investigation with evidence saved.

## 6. Signing and upload

- [ ] `keystore.properties` exists only locally or in CI and is git-ignored: `git check-ignore -v keystore.properties` (or confirm the `.gitignore` entry).
- [ ] No keystore, `.jks`, `.keystore`, passwords or tokens committed: `grep -rn 'storePassword\|keyPassword' --include='*.gradle*' --include='*.kts' .` shows no literals.
- [ ] Release `signingConfig` reads from properties or Play App Signing, not debug keys.
- [ ] AAB is signed with the upload key and verifies: `"$ANDROID_SDK/build-tools/<ver>/apksigner" verify --print-certs app/build/outputs/apk/release/app-release.apk`.
- [ ] Play App Signing enabled; upload key backed up by the human owner (human action).
- [ ] `mapping.txt` retained for deobfuscation; upload it with the release or keep it versioned outside the repo.
- [ ] Internal testing track install verified before production rollout.
- [ ] Signing and keystore-handling decisions recorded in `DECISION_LOG.md` (`DL-###`).

## 7. Accessibility

- [ ] Every interactive element has text or a content description; icons without labels are fixed: inspect `android layout --flat` output.
- [ ] Touch targets ≥ 48dp; check bounds in the hierarchy for small buttons.
- [ ] TalkBack can complete the main journey (enable, walk, disable, record in `SESSION_STATE.md`).
- [ ] Content scales with font size: test `adb shell settings put system font_scale 1.3`, then reset to `1.0`.
- [ ] No color-only meaning; error and success states also carry text or icons with descriptions.
- [ ] Contrast and dark theme reviewed on a real device screenshot.
- [ ] Important state changes are announced (live regions/semantics), not just visually highlighted.
- [ ] No `contentDescription` on decorative elements; no duplicated announcements.

## 8. Adaptive layouts, edge-to-edge and navigation

- [ ] Edge-to-edge enabled and insets handled: no content under status/navigation bars (`enableEdgeToEdge()` in Compose).
- [ ] Layout survives phone, tablet and foldable widths; verify at least `medium_phone` and `medium_tablet` emulator profiles.
- [ ] Resizable/multi-window and orientation changes do not lose state or clip controls.
- [ ] Predictive back works and no legacy `onBackPressed`/`OnBackPressedDispatcher` override blocks the animation.
- [ ] Navigation 3 back stack restores after process death (`adb shell am kill <package>`, reopen the app).
- [ ] Large-screen taskbar/window insets do not overlap critical actions.
- [ ] `android skills add edge-to-edge` and `android skills add adaptive` guidance followed if either area was touched.

## 9. Crash and ANR monitoring

- [ ] Release build does not crash on the riskiest journey (release spot check from `07-device-verification`).
- [ ] No `FATAL EXCEPTION` or `ANR in` in the final G6 crash buffer.
- [ ] Crash reporting or Play vitals will surface release crashes; deobfuscation via `mapping.txt` is possible.
- [ ] Main-thread work reviewed for blocking I/O and long recompositions.
- [ ] Play pre-launch report reviewed when available (human action).

## 10. Store listing and compliance

- [ ] Content rating questionnaire completed (human action).
- [ ] Target audience and families policy decisions recorded.
- [ ] Ads declaration matches the app; no unexpected ad SDKs.
- [ ] Data safety section consistent with permissions and network calls.
- [ ] App access instructions provided if login is required for review.
- [ ] Screenshots and feature graphic match the current UI (no stale pre-redesign shots).
- [ ] Release notes and rollout percentage decided; staged rollout planned for risky releases.
- [ ] Human release decision recorded as `HD-###`/`DL-###` and in `SESSION_STATE.md`.

## Final sign-off

A release is ready when:

1. `reports/quality-<UTC>.json` says `pass` with zero error findings.
2. `reports/device-<UTC>.json` says `pass` for the release spot check.
3. Sections 1-9 above are checked with evidence; section 10 items are assigned
   to a human with a recorded decision.

If any box cannot be checked, do not ship: record the gap in
`02_pending_review/human_decisions.md` as an `HD-###` with the evidence path.
