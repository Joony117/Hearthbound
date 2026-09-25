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

### Save migration is explicit rather than general
`ig-6l4` introduces schema 2 and a version-1 migration for stable identities, saved teams,
expedition orders, and active recovery time. Future-version or malformed new-schema saves
must refuse entry to play and further writes, preserving the canonical file and displaying the
reason. The main menu implements the refusal surface anticipated by `P2-17`.

There is no generic migration framework. A future schema change must supply its own explicit
migration and actual disk save/reload verification. The schema-2 migration does not establish
compatibility with formats that have not been authored.

### Timed expedition and recovery pacing is provisional
The first `ig-6l4` durations are 60/180/300 seconds for a full team at its zone's reference
strength, with diminishing strength-based reductions and a small-party workload factor.
Recovery windows use 15 active minutes plus 5 per Reliquary level and pause on new losses until
reviewed. These are authored starting values, not a playtest result.

**Settled by:** a fresh three-pull save reaching a second viable team; comparing one heavily
geared squad with several squads; and rebuilding for gear recovery after a harder-zone wipe.
Keep functional test results separate from those pacing judgments.
Tracked in Bead `ig-2ah` (Playtest timed expedition and recovery pacing).

### No GUT until Phase 2
There is no logic worth testing in the walking skeleton. Verification for Phase 1 is manual
plus a clean headless import.
**Fix in:** Phase 2, step 3.

### A quit while saves fail resumes from the last good save
Every profile action commits or rolls back (`ig-8hj`), so a failed save never keeps a pull, a
rank-up or a death. Expedition progress is different: the periodic save writes it every 15 s
(`PERIODIC_SAVE_SECONDS`). Until that save fails, a failed settle just retries on the next pulse,
silently. The failed periodic save shows the error and pauses expeditions. A quit before then
resumes from the last good save, up to 15 s back, the same as a crash.
**Revisit if:** a player hits it. The draft fix pauses at once and shows a lasting "can't save"
banner on the first failed commit.

### A reload is within 1 ulp, not bit-exact
The save writes floats at full precision (`ig-85w`), but Godot 4.7.1's `JSON.parse_string` (and
`String.to_float`) misrounds about 1 in 9 seventeen-digit numbers by 1 ulp (probe: 11,517 of
100,000, `.agent-results/ig-85w/float_probe.log`). So a battle reloaded from disk can differ from
the unsaved one in the last bit. No fork has been measured (`ig-36y`: 0 of 28; `ig-85w`: 30 s).
**Revisit if:** a real fork is ever seen. Then store floats as their 64-bit pattern in hex. That is
a save-schema change (boundary #1), so an ADR comes first.

### With no heroes, the town mood's recovery waits for the next save
Found by Sol in `ig-0og.1`'s review (finding 1). With an empty roster, nothing usually holds the
periodic save open (`game_session.gd:371`): no order, no worker, no eater. The town mood still
climbs on the live tick (`town_mood_rise_per_minute`, 2 a minute), because no heroes means none
are homeless. So the climb isn't written until the next profile change, and a reload can show an
older, lower mood.
It's harmless. No heroes means no homeless, so no revolt. The next pull is a commit, and it saves
the live mood. All that's lost is the climb since the last save, and the mood climbs again from
there.
**Revisit if:** anything else starts to move with an empty roster. Then the periodic save's gate
also opens while the mood is under 100.

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

**Deferred 2026-08-11, not closed** (`DECISIONS.md`, arena-as-feel-prototype). The arena resolves
nothing: its `CombatResult` is display-only and permadeath is deliberately unwired, so there is
currently no outcome for the two paths to disagree *about*. Sizing the divergence now would be
measuring a number nothing reads.
**Revisit in:** the first ticket that lets a played run resolve a real expedition — controlled
expeditions (`GAME_SPEC.md` § Direction), not Phase 3 by date.

### RTS controller support remains unimplemented
The approved `ig-544` direction supersedes the direct-control arena as the primary combat
surface. Its first RTS acceptance is desktop mouse and keyboard. A complete controller
selection, targeting and camera scheme remains future work; the legacy arena's controller
inputs do not establish controller support for commanding squads. See the 2026-09-22 ADR.

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

### Our tools see Claude's private copy of the owner's save folder, not the real one
The Claude desktop app is an MSIX package (`Claude_pzs8sxrjxfjjc`), and every shell or engine it
starts sees `%APPDATA%` through an overlay: Claude's private copy in
`%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\`, merged over the real folder.
The owner plays from Explorer, outside the package, so the game only ever touches the real folder.
Measured on throwaway folders on 2026-09-24:
- A read gets the private file when both exist.
- A write or a new file goes to the private copy when the private folder exists, and to the real
  folder when it does not.
- A delete removes the private file first. With no private file, it deletes the real one.

So `%APPDATA%\Godot\app_userdata\Infinite Gacha\save.json` read from any tool is Claude's private
copy (an empty roster written by a GUT run on 2026-09-23), while files that only the game wrote
(`ledger.jsonl`, the rotated logs) show through from the real folder. On 2026-09-24 that mix looked
like "the ledger was written but the save never landed" (ig-7is). It was not a game bug: the real
save was 18 KB, saved at 15:41, with all six heroes.

Read the real folder through the loopback share, which bypasses the overlay:
`\\localhost\C$\Users\Joony\AppData\Roaming\Godot\app_userdata\Infinite Gacha`. Copy files out;
never write there. The overlay is no shield: an engine run that forgets the temp `APPDATA` can
still delete the owner's real files, and its writes hide them from every later read. The real
save.json was created fresh on 2026-09-23 at 16:14, after that day's GUT runs without a temp
`APPDATA`, which suggests one of them deleted it.

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

### An engine run rewrites `project.godot`'s header comment
Godot rewrites `project.godot` wholesale when it saves, and the header it writes back is its own
boilerplate ("It's best edited using the editor UI...") — the pin comment this repo keeps on line 2
(`Pinned to Godot 4.7.1 stable - see docs/DECISIONS.md.`) is discarded. It surfaces as an unexplained
`M project.godot` in a tree nobody edited, and `git checkout -- project.godot` is the whole fix.
Check `git status` before starting work; committing it silently drops a documented pin.

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

### ~~`test_hit_stop_pauses_both_animation_players_and_resumes_the_same_frames` is flaky~~ — fixed 2026-08-12

**Resolved during the Mixamo animation swap.** Kept because the mechanism bites any test that drives
an `AnimationPlayer` from a manually-called `_physics_process`, and because chasing it turned up a
real gameplay bug that the flake had been hiding.

The original diagnosis was right: both `AnimationPlayer`s use Godot's default
`callback_mode_process = ANIMATION_PROCESS_IDLE`, so only a `_process` pass advances playback, and
the test awaited `wait_physics_frames(1)`. What the earlier pass missed is that **one frame of
either kind is never enough** — the awaiting coroutine resumes before that frame's animation
processing has run. Probed directly: position was unchanged after `wait_physics_frames(1)` *and*
after `wait_idle_frames(1)`, then advanced normally after `wait_idle_frames(3)`.

The fix is asymmetric, which is why `wait_process_frames(2)` everywhere failed before: the
**frozen** assertion stays on `wait_physics_frames(1)`, so no uncapped idle delta can leak into a
player that is supposed to be stopped, and only the **resume** assertion moves to
`wait_idle_frames(4)`. Four idle frames still land inside the light-attack window, so the swing clip
is what advances rather than a fallback to idle.

**The bug it was hiding:** the resume path called a bare `AnimationPlayer.play()`, which defaults
`custom_speed` to `1.0` and silently discarded the swing's authored rate — measured 3.57× dropping
to 1.0× for the hero, 1.36× to 1.0× for the enemy. Barely visible while only the short `_Rec`
recovery clip was left to play; the Mixamo swap made one clip span the whole attack, so it began
dragging the entire remainder of every swing that got hit-stopped. `arena.gd:_play_animation()` now
restates `custom_speed` on the way back in, and the test asserts the playing speed survives the
freeze — the assertion whose absence let this sit unnoticed.

Verified 4/4 green full-suite runs after the fix, against 9/9 red before it.

### Console binary required for CLI
`tools/godot/Godot_v4.7.1-stable_win64.exe` detaches from the terminal and swallows stdout.
Always use `Godot_v4.7.1-stable_win64_console.exe` for headless and scripted runs.

### `gut_cmdln.gd` exits 0 when a test script fails to *parse*

A test file with a parse error is dropped from the run entirely and the run still reports success.
Measured during `P2-28`, with `tests/unit/test_equipment.gd` unparseable:

```
Scripts              13
Tests               120
Passing Tests       120
---- All tests passed! ----      (exit code 0)
```

The real totals that day were `Scripts 14 / Tests 153`. GUT prints `SCRIPT ERROR: Parse Error` and
`Failed to load script ... with error "Parse error"` to stdout before the summary, but neither the
summary nor the exit code reflects it — **a suite that silently got 33 tests smaller is
indistinguishable from a suite that passed.**

So a green GUT run is only evidence when its counts are checked: compare `Scripts` and `Tests`
against the previous run, and treat any drop as a red. `tests/import_gate.ps1` is the backstop that
actually catches this, since it greps for `SCRIPT ERROR` regardless of exit code — which is another
reason BUILT is both gates and not either one.

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

**`save.json` is not the only file under this gap.** `P2-33` added the second one:
`user://settings.cfg`, written by `Settings` (`systems/settings.gd`, static, not an autoload) and
now touched by `test_hub_controls.gd`'s `ScreenShake` test. It uses the same backup/restore idiom,
plus one thing `test_save_service.gd` does not need — `Settings._config` is a **static cache**, so
restoring the bytes is not enough on its own; `after_all` nulls it too, or a later reader in the
same process serves the test's value from memory and never re-reads the restored file. Verified
2026-08-13: the real `settings.cfg` came back SHA-256 identical across ten full-suite runs. Anything
that adds a third `user://` file inherits both halves of this.

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

Reproduced 2026-08-12 during `P2b-13`, under the *same* conditions this entry already names: the
first full-suite run of the session, immediately after an `import_gate.ps1` pass had rewritten
`.godot/`; the next run of the identical tree was `193/193`. Two observations, both first-run-after-a-
gate, is now the strongest thing here — if you are about to investigate a red on line 114, check
whether the gate ran first, because that has been true every time.

### Backward is the one direction with no locomotion clip

**Superseded in part, 2026-08-12.** The entry below is still true of the two UAL packs, but the arena
does not load them any more, and the Mixamo set now has directional clips: `Sword And Shield Strafe
left`/`right` for locomotion and four `Standing Dodge` clips. `combat/arena/arena.gd` picks the
nearest of four by the angle between travel and facing (`_local_quadrant()`), which is exactly the
cheap route `P2b-13` scoped — one clip at a time, the default blend smoothing the switch, a 30° run
playing the 0° clip verbatim.

**What is still missing is backward.** There is no backpedal in the Mixamo pack either, so moving
away from the camera plays `Jog_Fwd` and the hero moonwalks. Three of four directions are honest and
the fourth is not; `_locomotion_clip()` names this at the call site. Fixing it is one more Mixamo
download (`sword and shield walk backward`) and one line in `_locomotion_clip()`, not an
`AnimationTree` — the paragraph below explaining why a continuous mix needs one still holds, and is
still the reason 8-way-with-real-blending is a different, larger ticket than 4-way-by-nearest.

### Neither animation pack contains a directional locomotion clip

**Every locomotion clip in both UAL packs faces forward.** `UAL1_Standard.glb` has `Idle`, `Jog_Fwd`,
`Sprint`, `Walk`, `Walk_Formal`, `Crouch_Fwd`, `Swim_Fwd`; `UAL2_Standard.glb` adds `Walk_Carry` and
`Zombie_Walk_Fwd`. There is **no backward, left, or right locomotion in either file** — read out of
the glTF JSON chunk directly, 2026-08-12.

This is the real blocker on 8-way movement, and it is not the one the arena's animation code looks
like it is. `P2b-13` asked whether `playback_default_blend_time` can carry directional blending later
or whether an `AnimationTree` becomes mandatory; the answer is that neither is reachable, because
there are no clips to blend. **8-way starts with a pack swap**, which `P2b-13`'s non-goals flag as
hazardous on its own terms (`SuperHero_Male`'s capital `H` is load-bearing in three `get_node()`
calls, `P2b-10`).

Two facts worth keeping with it, for whoever writes that ticket:

- **A transition blend and a directional blend are different mechanisms.** `playback_default_blend_time`
  crossfades clip A into clip B over a fixed time and scales to any number of states — no ceiling.
  A continuous mix of Fwd/Bwd/Left/Right whose weights change every frame with the input vector is
  `AnimationNodeBlendSpace2D` and **cannot** be done by an `AnimationPlayer` at all, which plays one
  clip at a time. Picking the nearest of 8 clips by input angle and letting the default blend smooth
  the switch *is* available on the cheap method; what it costs is within-bucket accuracy, since a
  `30°` run plays the `45°` clip verbatim.
- **Adoption is all-or-nothing per skeleton.** An active `AnimationTree` owns the tracks it drives, so
  a blend space for locomotion cannot coexist with `AnimationPlayer.play()` for attacks on the same
  player — they fight over the same properties. That is why `P2b-13` scoped the tree as a rewrite of
  both updaters rather than a partial adoption.

Note the clip names on disk carry `_Loop` suffixes (`Idle_Loop`, `Jog_Fwd_Loop`) that the code does
not use. That is not a mismatch: `nodes/use_name_suffixes=true` in the `.import` files makes Godot
strip the suffix and set the loop mode from it, so the imported name is `Idle`. `P2b-09` recorded the
imported names; this entry records the source names, and both are correct.

### Godot AI editor plugin: start the backend from the client, not the editor

On this PC the plugin's own server launch fails ("server start blocked: The launched server process
exited or changed identity before publishing capabilities"), which is a Windows launcher bug in
v4.2.1 (upstream #1105/#1107). The v4 design lets the MCP client own the backend instead:
`uvx godot-ai==4.2.1 attach` (the `godot-ai` entry in Claude Code, local scope for `E:\Game`) spawns
it on 127.0.0.1:8000/9500, and an editor opened after that logs "adopted external server" and
connects. So if the dock shows blocked, restart the editor once a Claude session with `godot-ai` is up.
Launch the editor with `GODOT_AI_DISABLE_TELEMETRY=true` and
`UV_CACHE_DIR=C:\Users\Joony\.cache\uv-godot-ai`. The shared uv cache gets locked by other sessions.
**An open editor blocks `import_gate.ps1`**, so close it before any gate run.
