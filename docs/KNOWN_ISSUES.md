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

### Serena's GDScript backend is an LSP client, not a server
It attaches to a Godot editor daemon already listening on `127.0.0.1:6005`; it never launches one
itself. That daemon is a fourth, persistent engine consumer against this project (`CLAUDE.md`,
"Serialize engine access"), which is why `tests/import_gate.ps1` now checks the port before
touching `.godot/` rather than assuming it has the engine to itself.

Start it with `./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --editor --path E:/Game`
(confirmed this serves LSP). The `_console` wrapper is not what holds the port — it spawns a child
`Godot_v4.7.1-stable_win64.exe`, and that child process is the one bound to 6005. `Get-Process
Godot* | Stop-Process -Force` kills both by name, so this only matters if you were trying to target
one PID specifically.

Serena's built-in GDScript port default is 6008 (Godot 3's); `.serena/project.yml` overrides it to
6005 via `ls_specific_settings`, and without that override nothing connects at all. Serena also
connects **once**, at MCP server startup, with no retry (`serena/project.py:512`,
`get_language_server_manager_or_raise`): if the daemon isn't already listening at that moment,
every symbolic call fails for the rest of the session with a cached "Could not connect to
127.0.0.1:6005 within 30.0s" — and starting the daemon afterwards does not help, since Serena never
looks again. The tell that distinguishes this cached failure from a real timeout: the cached one
returns *instantly*, not after 30s.

### The LSP guard in `import_gate.ps1` aborts before any `.godot/` write, confirmed
Verified directly: with the daemon up and 6005 listening, the gate exits 1 immediately and
`.godot/`'s mtime is unchanged from before the run (the port check is the first thing the script
does, ahead of the `--headless --import` warmup pass). With the daemon down, the gate behaves
exactly as before the guard was added — exit 0, zero script errors and warnings, `.godot/` rebuilds
normally. Stopping the daemon afterward frees the port immediately and a subsequent gate run is
green again, so an aborted run leaves no residue for the next one to trip over.
