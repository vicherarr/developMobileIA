# Session state

> Volatile. Rewrite at the start and end of every session. Keep it under ~40
> lines. This is the file another agent reads first.

- Updated: `2026-11-08T16:21:00Z`
- Stage: `G0` (intake)
- Status: `idle`
- Project: `<app-name>` (`<applicationId>`)

## Next action

Run `01-spec-and-scope`: turn the user's idea into
`app_workspace/.pipeline/spec.json` + `plan.md`, then stop at G1.

## Open questions (blocking)

None.

## Open questions (non-blocking, defaults applied)

None.

## Work in progress

Nothing yet. `app_workspace/` has no generated project.

## Evidence on disk

None. Reports will appear in `app_workspace/.pipeline/reports/`.

## Known risks / watch list

- The agent sandbox mounts `/home` read-only and hides `/dev/kvm`; the host
  itself is fine (verified build + AVD). Run `make setup-host` in a real shell.
- `android preview list|render` fails in CLI 1.1.16717390 (pack unzip bug);
  preview steps are advisory in G5 until `android update` ships a fix.
- Gradle first run downloads the distribution and dependencies (~1 GB).

## Files touched this session

- Pipeline kit created: 11 skills + official `testing-setup`, memory layer,
  scripts (doctor/bootstrap/check/scaffold/verify/device/quality), Makefile, docs.

## Notes for the next session

Start at `G1`. Do not scaffold before the spec exists.
