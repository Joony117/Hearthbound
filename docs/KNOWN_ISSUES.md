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

### GUT lives under `tests/unit/`, not `tests/`
`-gdir=res://tests` cannot be pointed at the repo root: the three `SceneTree` gate scripts
(`save_roundtrip_check.gd`, `balance_table_check.gd`, `zone_definition_check.gd`) are not
`GutTest` subclasses, and GUT tries to load anything under `-gdir` as a test script. GUT tests
live in `tests/unit/`; the three gate scripts stay in `tests/` unchanged and keep running exactly
as before (`--headless -s res://tests/<name>.gd`). The Phase-2 GUT gate command is:

```
./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Installed: GUT 9.7.1 (`bitwes/Gut`, source zip from the GitHub release tag, not the asset-less
release page — the tag's zipball is just `addons/gut/`, no demo/example tests bundled). Committed
under `addons/gut/`, not gitignored; `addons/` was not previously excluded and still isn't. The
plugin is not enabled in `project.godot`'s `[editor_plugins]` — `gut_cmdln.gd` runs standalone via
`-s` and never needed it enabled, so no project.godot edit was necessary.

GUT's own `class_name`-declared scripts (`GutTest`, `GutTestCollector`, etc.) get pulled into the
global script class cache the same as any other `class_name` script, whether or not the plugin is
"enabled" — confirmed this adds no warnings or errors to `tests/import_gate.ps1`; it still exits 0
clean with GUT present. `addons/gut/fonts/*.import` sidecars appear on first reimport (GUT ships
its own runner UI fonts) and are committed like every other `.import`/`.gd.uid` in this repo.

Running `gut_cmdln.gd` directly (not through `import_gate.ps1`) does not redirect `%APPDATA%`, so
it exercises the real `user://save.json` via the `GameSession`/`SaveService` autoloads on startup
— confirmed this is read-only (`GameSession._ready()` loads before connecting `roster_changed` to
`SaveService.save`, so the load's own signal emission never triggers a write). Redirect `%APPDATA%`
to a temp dir when running GUT manually anyway, for the same reason `import_gate.ps1` does.
