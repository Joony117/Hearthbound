# Known Issues

Deferred bugs, deliberate shortcuts, and things that will bite later. Harvested partly from
`ponytail:` comments in the source.

An entry here is a *decision to defer*, not a bug report. Anything that should be fixed now
belongs in `TASKS.md` instead.

---

## Deliberate shortcuts

### Phase 1 summon is not the real summon
`randi() % 8` for rank, name from a hardcoded array. No weight table, no definitions.
**Replaced in:** Phase 2, ticket P2-02.

### Phase 1 expedition is a coin flip
No combat, no stats, no waves. Its only job is proving the scene chain and the permadeath
deletion path work end to end.
**Replaced in:** Phase 2, ticket P2-03.

### No save migration
`SaveService` writes a `version` field from the first commit but does nothing with it. A save
from an older build will load into a newer one and may produce garbage.
**Fix in:** Phase 5.

### No GUT until Phase 2
There is no logic worth testing in the walking skeleton. Verification for Phase 1 is manual
plus a clean headless import.
**Fix in:** Phase 2, step 3.

---

## Open questions

### Does spending a hero's life actually feel like something?
The Phase 2 exit question, and the only one that matters. If the answer is no, the fix is
design, not code. Findings go in `DECISIONS.md`.

### Quick resolve and the arena will disagree
A statistical resolver and a real-time arena will not produce the same outcomes for the same
team and wave. Some divergence is acceptable — the quick path is a convenience. How much is
acceptable is unknown until both exist.
**Revisit in:** Phase 3.

### Controller support is a hard constraint but unimplemented
`GAME_SPEC.md` requires gamepad as a first-class input path for the arena. Nothing in Phase 1
addresses it. It must land with the arena in Phase 2b, not be deferred to Phase 5.

---

## Environment

### The exporter does not create its own output directory
`--export-release` fails with `Prepare Template: The given export path doesn't exist.` and exit 1
if `export/` is absent. `export/` is gitignored, so **every** clean checkout hits this, not just
the first. The documented command in `CLAUDE.md` carries the `mkdir -p export` for this reason.

### A fresh clone has no engine binary
`tools/` is gitignored (170 MB), so `git clone` produces a checkout where
`tests/import_gate.ps1` cannot resolve its relative engine path (`$PSScriptRoot\..\tools\godot\`).
The gate only runs in a checkout that already has `tools/godot/` populated. Deliberately not
fixed with engine discovery or a `GODOT_BIN` fallback — that is speculative until there is CI.

### `--headless --import` regenerates `.gd.uid` sidecars
The gate's cache-warming pass makes Godot write a `.gd.uid` next to any script it has not indexed
yet. Godot owns these and they are committed like every other `.gd.uid` in the repo; a new one
appearing after a cold-cache gate run is expected, and should be committed rather than ignored.
Never hand-edit one (`AGENTS.md`).

### Console binary required for CLI
`tools/godot/Godot_v4.7.1-stable_win64.exe` detaches from the terminal and swallows stdout.
Always use `Godot_v4.7.1-stable_win64_console.exe` for headless and scripted runs.
