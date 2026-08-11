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

`P2-17`'s refused-save ruling (`docs/SYSTEMS.md` § Refused-save recovery) already covers what the
newer-than-this-build branch (`version > SAVE_VERSION`) must do once it's reachable: refuse to
boot, not move the file aside — that data isn't corrupt, only unreadable by this build, and
move-aside would discard it. Unreachable today (`SAVE_VERSION` has never been bumped past `1`), so
the error-rendering UI for it isn't built yet; whichever ticket first bumps `SAVE_VERSION` inherits
that requirement rather than re-deciding it.

### No GUT until Phase 2
There is no logic worth testing in the walking skeleton. Verification for Phase 1 is manual
plus a clean headless import.
**Fix in:** Phase 2, step 3.

---

## Open questions

### Does spending a hero's life actually feel like something?
The Phase 2 exit question, and the only one that matters. If the answer is no, the fix is
design, not code. Findings go in `DECISIONS.md`.

### Permadeath severity at the top of the curve has no documented stance
A manufactured SSS hero costs `~327` summon pulls fed as sacrifice fodder — verified arithmetic,
`docs/SYSTEMS.md:140-141`. A full 5-hero manufactured-SSS team is therefore `5 * 327 = 1,635`
pulls' worth of fodder lost to one wipe, with no partial-credit or inheritance mechanic on death
(`GameSession.kill_hero()`, `systems/game_session.gd:26`, is an unconditional roster removal). How
that maps to play *time* isn't settled either — Summon Stone income has no defined rate yet
(`docs/SYSTEMS.md:153-157`, `P2-09` unstarted), so an hour estimate against the 1,635-pull figure
is a rough external guess, not a verified number.

Undiscussed, not contradicted: nothing in `SYSTEMS.md`, `GAME_SPEC.md`, or `DECISIONS.md` states
whether losing a fully-built SSS team is the *intended* weight of permadeath at the top of the
curve, or whether it needs softening (partial essence refund, rank inheritance on death, insurance
via a building, etc.). `GAME_SPEC.md`'s attachment-vs-expendability goal argues the decision to
risk a hero should be uncomfortable — it does not say how uncomfortable the worst case should be
once "the hero" represents 1,635 pulls of sunk cost rather than one lucky pull.

Deliberately not inventing a softening mechanic here — that's a design decision, not a doc-cleanup
default, and a wrong default (e.g. quietly adding rank inheritance) would understate permadeath's
weight without anyone deciding that was the goal. **Revisit in:** the same played build the retreat
and gear-recovery `PROVISIONAL` markers are waiting on — this question can't be settled at a desk,
since "uncomfortable" vs. "not worth playing around" is exactly the thing that needs to be felt,
not calculated. If a played build says the 1,635-pull wipe reads as "not worth playing around,"
the fix is a `DECISIONS.md` ADR for a softening mechanic, not a quiet SYSTEMS.md edit.

### Quick resolve and the arena will disagree
A statistical resolver and a real-time arena will not produce the same outcomes for the same
team and wave. Some divergence is acceptable — the quick path is a convenience. How much is
acceptable is unknown until both exist.
**Revisit in:** Phase 3.

### Controller support is a hard constraint but unimplemented
`GAME_SPEC.md` requires gamepad as a first-class input path for the arena. Nothing in Phase 1
addresses it. It must land with the arena in Phase 2b, not be deferred to Phase 5.

### Retreat only fires at F rank, in the only zone that exists today
**Was:** retreat never fired at all. Solo, Verdant Outskirts, every rank F–SSS, all 5 archetypes,
all 5 trash checkpoints — the 25% threshold was never crossed, closest miss 39.9% remaining.
Cause was the win/loss branch making a lost wave an instant full-team wipe, so HP could only erode
through *won* waves, and won-wave damage has to stay cheap for a Verdant clear to exist at all.

**Fixed in `P2-03f`** (`a412c4a`): a lost wave now deals `clamp(1.0 * r^3, 0, 1)` graduated damage,
which gives retreat an erosion pathway independent of the clear-reachability budget.
`OUTCOME_RETREATED` is reachable and covered by a test that drives F Knight's `LWWWL` sequence.

**What remains:** reachable at F rank only — all 5 F archetypes reach it via some real win/loss
sequence, none of the 35 D-through-SSS combinations do at any coefficient tested. That is not a
shortfall of the constant. Verdant's `recommended_power` is fixed at 900 while hero power grows
`×1.35` per rank, so F is the only rank where its ramp is a fight at all — the *win* branch already
had that ceiling, and a loss rule tied to the same `r` inherits it. Escaping it means decoupling
from `r`, which the combat seam forbids. Still don't "fix" this by nudging the 25% threshold or
`wave_damage_coefficient`; both were tried and rejected with numbers in `SYSTEMS.md`.
**`P2-03c` has since shipped** (`85caa66`), so mixed-rank rosters and the Ashfall/Sundered unlock
now exist — the enabler is in place. Whether retreat actually fires more widely against them is
**unverified**: the reachability claim was arithmetic on hypothetical rosters, and nobody has swept
the real code with a multi-hero mixed-rank team in a harder zone.
**Revisit in:** the first ticket that sweeps retreat reachability against the shipped squad select,
or a played build — whichever comes first.

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

### A `-s` script compiles before the autoloads register — and hangs if it fails
`--headless -s <script>` loads and compiles that script *before* `SceneRouter`/`SaveService`/
`GameSession` exist as identifiers. Any dependency it names statically that references an autoload
at compile time therefore fails with `Identifier not found: GameSession` — `hub/expedition/
expedition.gd` does, and has since `P2-03b`. Worse than the error: the run then **hangs** instead
of exiting, because the script's own `quit()` is never reached, and a hung `-s` run is
indistinguishable from a finished one at the call site.

This is why `tests/save_roundtrip_check.gd` reaches everything through `root.get_node()` and
`.call()` strings rather than static types. `load()` the script inside the deferred callback and
it compiles normally, since the autoloads are up by then. GUT is unaffected — `gut_cmdln.gd` loads
test scripts after `_ready()`, which is why `tests/unit/*` can name `Expedition` freely.

Measured 2026-08-04 during `P2-04d`; the hung process had to be reaped with
`Get-Process Godot* | Stop-Process -Force`.

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
it exercises the real `user://save.json` via the `GameSession`/`SaveService` autoloads. **It
overwrites that file.** Startup itself is read-only — `GameSession._ready()` loads before
connecting `roster_changed` to `SaveService.save`, so the load's own emission never writes back —
but the connection is live by the time any test runs, and every test file's `before_each()`
(`test_loot.gd`, `test_item.gd`, `test_expedition.gd`, `test_equipment.gd`) calls
`GameSession.from_dict(...)`, whose emission does reach `SaveService.save`. Measured 2026-08-04
verifying `P2-05a`: a plain GUT run left the real save at an empty roster.

The earlier claim here that the run was read-only was reasoning about startup only and did not
survive measurement. Redirect `%APPDATA%` to a temp dir when running GUT manually, the same way
`import_gate.ps1` does — this is a real-save-destroying command otherwise, not merely untidy.

One exception, added by `P2-08`: `tests/unit/test_save_service.gd` backs the file up in
`before_all` and restores it byte-identically in `after_all` (measured — a sentinel save came back
SHA-256 identical after a `-gtest=` run of that file alone). It is the only file that does. The
redirect stays mandatory for a suite run, because the other eleven files still overwrite.

### A Godot editor serves LSP on 6005 and is a second engine consumer
`--headless --editor --path E:/Game` serves the LSP port. The `_console` wrapper is not what holds
it — it spawns a child `Godot_v4.7.1-stable_win64.exe`, and that child is bound to 6005.
`Get-Process Godot* | Stop-Process -Force` kills both by name, so this only matters if you were
targeting one PID specifically. Nothing in the workflow starts an editor now (Serena was removed
2026-08-04, see `DECISIONS.md`), but the guard below stays because a hand-started one still races
`.godot/`.

### The LSP guard in `import_gate.ps1` aborts before any `.godot/` write, confirmed
Verified directly: with an editor up and 6005 listening, the gate exits 1 immediately and
`.godot/`'s mtime is unchanged from before the run (the port check is the first thing the script
does, ahead of the `--headless --import` warmup pass). With nothing on the port, the gate behaves
exactly as before the guard was added — exit 0, zero script errors and warnings, `.godot/` rebuilds
normally. Stopping the editor afterward frees the port immediately and a subsequent gate run is
green again, so an aborted run leaves no residue for the next one to trip over.

### The port-6005 guard misses a stray non-LSP headless process; closed via `ExecutablePath` match
The port check only catches the LSP daemon (`--editor`, serves 6005). A plain
`--headless -s <script>` run left alive by something that launched it and never reaped it (e.g. a
subagent's background job) does not serve any port and slips past that check entirely — observed
directly: two such processes (the `_console` wrapper plus its spawned child) outlived a subagent
session with 6005 confirmed free the whole time. A command-line project-path match would have
missed this exact case too: the leaked process had no `--path` argument at all, only `-s
<temp-script-path>` from a cwd of `E:\Game` — the project association was never in the command
line to match against.

Fixed by matching on `ExecutablePath` instead: `tools/godot/` is gitignored and unique per
checkout, so any process (either binary name) running from that exact folder is this repo's
engine, regardless of arguments. `import_gate.ps1` now runs a
`Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'"` scan (after the port check, before
spawning its own two invocations) and aborts naming the PID, binary, and command line if any match
resolves under `tools/godot/`. Confirmed no false positive: a Godot process running a *different*
binary copy from a different folder (same script, same `-s` arg, no `--path`) does not match and
the gate still exits 0. Measured cost: ~20-30ms added per gate run (filtered `Get-CimInstance`
~32ms vs. plain `Get-Process` ~10ms, 5-run average on this machine) against a run that takes
several seconds for engine startup — negligible.

Root cause stays open: this is a net that catches the symptom on this gate's own runs, not a fix
for the underlying leak (a subagent not reaping a background process it launched, or not waiting
for it to exit before returning). That convention belongs in `AGENTS.md`/agent files, not here.

### Engine state can change between the director's check and the subagent's first command
Observed directly, not simulated: at the start of a `godot-tester` dispatch that was told "the LSP
daemon is currently down and port 6005 is free," it was not — both engine processes (`--editor
--path E:/Game`) were already running, started ~3.5 minutes earlier, with an established
connection from a `serena-agent` client process.

This was **not** a leaked leftover, which is what it looked like from inside the dispatch. The
director had verified no Godot process and a free port immediately before dispatching; the daemon
was started deliberately in the gap between that check and the agent's first command. The lesson
is about staleness, not leakage: a "daemon is down" statement in a prompt describes the moment it
was written, and a dispatch that runs the engine should re-verify rather than trust it.
`Get-Process Godot* | Stop-Process -Force` (the documented convention) cleared
it and freed the port immediately; the port-6005 guard would have caught a gate run against it
regardless, but only because that daemon happens to serve a port — the same silent-leftover
failure mode with a non-LSP headless process is the case above. Anyone dispatching a
Godot-touching subagent should verify port 6005 and process list directly rather than trusting a
"daemon is down" assumption carried over from an earlier turn.

### The documented GUT command crashes inside a Codex worker's sandbox
`--headless -s addons/gut/gut_cmdln.gd` writes Godot's own log under `user://logs/`, which resolves
into the real `%APPDATA%`. A Codex worker sandboxed to `workspace-write` cannot write there, so the
documented command dies before the first test with `ERROR: Failed to open 'user://logs/...'` and
exit `-1073741819` (an access violation, not a test failure). Observed during `P2-14`.

Outside the sandbox the same command runs normally — the director's own run of it passed 67 tests.
So a worker reporting this is reporting its own confinement, not a broken suite. The workaround it
found is the one `import_gate.ps1` already uses for itself: point `APPDATA` at a scratch directory
for the duration. That also stops the run from overwriting the real `user://save.json`, which a
plain GUT run does (see above), so it is worth doing in a director-run gate too.

### `test_save_service.gd` has one flaky assert on the corrupt-save rename
`test_non_dictionary_save_is_refused_without_resetting_game_session` failed once at line 114 —
`assert_false(FileAccess.file_exists(SAVE_PATH))` — while every other assert in the same test
passed, including the two that prove `save.corrupt.json` exists with the right bytes. So
`DirAccess.rename_absolute()` returned `OK` and the destination was correct; only the *source* path
briefly still reported as existing.

Observed 2026-08-10, once in five consecutive full-suite runs, on the first run of the session
immediately after two `import_gate.ps1` passes had just rewritten `.godot/`. Four later runs of the
identical tree were 145/145, and the file passes 8/8 in isolation. This is a Windows rename
visibility lag, not `SaveService` logic and not a test-ordering bug — the pair
`test_sanctum.gd,test_save_service.gd` does not reproduce it.

Practical effect: **a single red run on this one assert is not evidence of a regression.** Re-run
before investigating. If it starts landing more than rarely, the fix is to have `load_game()` poll
for the source's disappearance rather than to weaken the assert — the assert is testing the right
thing.
