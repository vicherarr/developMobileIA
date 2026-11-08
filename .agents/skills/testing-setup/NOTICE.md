# testing-setup (official Android skill)

This directory is **third-party content**, not part of this pipeline's own
skills. It was installed with the Android CLI:

```bash
android skills add testing-setup
```

- Source: <https://github.com/android/skills> (Google LLC)
- License: Apache License 2.0 — the full text is vendored next to this file as
  `LICENSE.txt`, matching the skill's `license: Complete terms in LICENSE.txt`.
- Do not hand-edit these files: `android skills add testing-setup` overwrites
  them on refresh.

Why it is vendored here: it is the highest-quality reference for Android
testing strategy (unit, Robolectric, Compose UI, screenshot, e2e) and the
pipeline's `06-testing-strategy` skill defers to it for depth.

Refresh or remove:

```bash
android skills add testing-setup      # update to the latest version
rm -rf .agents/skills/testing-setup   # remove; the pipeline still works
```

Related official skills worth installing as needed: `adaptive`, `edge-to-edge`,
`navigation-3`, `jetpack-compose-performance`, `r8-analyzer`, `android-profiler`.
