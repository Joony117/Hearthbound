# Completed tickets

> **ARCHIVE — do not read this file into context.** ~18k tokens and append-only. Grep it for a
> specific ticket ID and read only the hit. It is history, not spec: nothing in the live
> workflow depends on it, and `git log` holds every body in its closing commit. If you find
> yourself opening it in full, you want `TASKS.md` instead.

Split out of [`TASKS.md`](TASKS.md) so the live backlog stays small — that file is read in
full by every `tech-lead` dispatch, and these bodies were the bulk of it.

Nothing here is edited after it lands. A shipped ticket's acceptance criteria are the record
of why the code looks the way it does, and several of these carry findings that later tickets
inherit — the `[DONE]` notes are where a boundary decision or a caught bug is written down.

Newest work is at the bottom, matching the order they were written in.

---

## P1-01 — Project boots to a main menu and into the hub          [DONE]

Landed in `f62e545`. Import gate clean, `hub.tscn` headless smoke exit 0.

### Objective
Launching the game shows a main menu. Pressing Play loads a gray-box 3D hub. Escape opens a
pause menu that can return to the main menu.

### Existing architecture
Nothing exists yet. This ticket creates `project.godot` and the three autoloads.

- `SceneRouter` is the only thing permitted to change the main scene (`ARCHITECTURE.md` r5)
- `GameSession` holds the persistent player profile and must survive the scene change
- `SaveService` is created but does nothing beyond writing a `version` field this ticket

### Acceptance criteria
- `project.godot` pinned to Godot 4.7.1, main scene is `ui/main_menu.tscn`
- Exactly three autoloads registered: `SceneRouter`, `SaveService`, `GameSession`
- Main menu has Play and Quit; Play routes to `hub/hub.tscn`
- Hub is 3D: a ground plane and 3-5 labelled boxes standing in for buildings
- Escape in the hub opens a pause menu with Resume and Return to Menu
- Returning to menu and pressing Play again works repeatedly with no leaked state
- `--headless --quit` imports with zero script errors or warnings

### Files allowed to change
`project.godot`, `systems/`, `ui/main_menu.tscn`, `ui/pause_menu.tscn`, `hub/hub.tscn`,
`hub/hub.gd`, `game/`

### Non-goals
Settings menu, audio, transitions/fades, camera controls, save/load UI, any hero or gear
data, building interaction.

---
## P1-02 — Summon a hero into a visible roster                    [DONE]

Landed in `f62e545`. Roster survives save and reload — proved by
`tests/save_roundtrip_check.gd`, not by the import gate, which cannot see that boundary.

### Objective
A Summon button in the hub adds a hero to a roster list on screen.

### Existing architecture
- `GameSession` owns the roster array (P1-01)
- Hub scene exists with gray-box buildings (P1-01)
- No `HeroDefinition` Resource exists yet — **do not create one in this ticket**

### Acceptance criteria
- Summon button produces a hero with a name from a hardcoded array and `randi() % 8` rank
- Rank displays as `F D C B A S SS SSS`, not as an integer
- Roster list updates via signal, not by the button reaching into the list node
- Roster persists across a return-to-menu-and-back-to-hub cycle
- Roster survives save and reload through `SaveService`

### Files allowed to change
`hub/summon/`, `hub/roster/`, `heroes/hero.gd`, `systems/game_session.gd`,
`systems/save_service.gd`

### Non-goals
Weight tables, `HeroDefinition` Resources, hero stats, portraits, 3D hero models, summon
animation, currency cost, pity, dupes.

---
## P1-03 — Send a hero out; it lives or dies permanently          [DONE]

Landed in `f62e545`. `GameSession.kill_hero()` is the single deletion call site
(`ARCHITECTURE.md` r8); permadeath persisting across reload is covered by
`tests/save_roundtrip_check.gd`.

### Objective
Selecting a hero and pressing Expedition resolves a coin flip. On success the hero returns
and the result is shown. On failure the hero is **permanently deleted** from the roster.

### Existing architecture
- Roster lives in `GameSession`, rendered by the roster list (P1-02)
- Permadeath must be applied in exactly one place (`ARCHITECTURE.md` r8)
- This is the skeleton's win/loss state — checklist item 5

### Acceptance criteria
- Selecting a roster entry and pressing Expedition shows a result: survived or died
- On death the hero is removed from the roster and does not come back after save/reload
- Deletion happens in one function; no other file removes heroes from the roster
- Summoning again after a death works, and the roster stays consistent
- `--headless --quit` still imports clean

### Files allowed to change
`hub/expedition/`, `systems/game_session.gd`

### Non-goals
Combat of any kind, stats, waves, teams of 5, equipment, loot, XP, lost-gear caches,
recovery runs, zones, `CombatResult`, `quick_resolve.gd`.

---
## P1-04 — Export and clean-checkout gate                         [DONE]

Landed in `a8c5e47`. Verified from a real `git clone` into a temp directory: imports with
zero error/warning lines, and exports from the clone itself — `game.exe` (109,071,360 bytes)
plus `game.pck`. The exported binary launches headless with no script errors.

**Manually verified.** The packaged binary was walked by hand: summon → expedition →
permadeath, then quit and relaunch, and the dead hero stayed dead. This could not be driven
headlessly, so it was the one criterion carried as unproven until a human ran it.

### Objective
The project exports to a runnable Windows exe, and a fresh clone opens and runs.

### Acceptance criteria
- Export templates for 4.7.1 installed
- `export_presets.cfg` committed with a "Windows Desktop" preset
- `--export-release "Windows Desktop" export/game.exe` succeeds
- The exported exe launches and the full P1-01..03 flow works in it
- `git clone` into a temp directory opens in the editor with zero missing resources
- `export/` is gitignored; `export_presets.cfg` is not

### Files allowed to change
`export_presets.cfg`, `.gitignore`

### Non-goals
Icons, version metadata, code signing, installers, Steam integration, Linux/macOS presets.

---
## P2-01a — HeroDefinition Resource + five archetypes authored     [DONE]

Landed in `034a6df`, hardened in `9605d3e` after an adversarial `verifier` pass.

Two decisions worth carrying forward. A missing `def_id` defaults to **empty**, never to an
archetype — `to_dict` always emits the field and `roster_changed` triggers a save, so
defaulting to a real archetype would have written a fabrication to disk on the first roster
change and permanently destroyed the fact that those heroes predate archetypes. A `def_id`
present but not a `String` is corrupt rather than legacy, and gets a `push_error` naming the
type before falling back to empty.

Both new assertions were mutation-tested, not assumed: reintroducing either defect makes the
suite fail with the specific wrong value and exit 1.

**P2-02 inherits the consequence** — empty `def_id` is the input its fail-loud lookup criterion
exists to handle.

### Objective
Five hero archetypes (Knight, Rogue, Ranger, Mage, Cleric) exist as data — a `HeroDefinition`
Resource class with one authored `.tres` per archetype — and a `Hero` runtime instance can
carry a `def_id` pointing at one, surviving save and reload. This ticket makes no player-facing
change by itself: summon still rolls the Phase-1 placeholder. P2-02 is what makes this visible.

### Existing architecture
- `Hero` (`heroes/hero.gd:1-28`) is a `RefCounted` with only `hero_name`, `rank`, and
  `to_dict`/`from_dict`; its own header comment (`heroes/hero.gd:5-6`) already earmarks this
  ticket to add `def_id`.
- `GameSession.roster: Array[Hero]` (`systems/game_session.gd:10`) serializes heroes through
  `GameSession.to_dict`/`from_dict` (`systems/game_session.gd:31-43`), which calls straight
  through to `Hero.to_dict`/`from_dict`. Any new `Hero` field must round-trip through both
  layers or it is silently dropped on load — this is risky-boundary item 1 in `CLAUDE.md`.
- No `heroes/hero_definition.gd` or `heroes/defs/` exist yet. `ARCHITECTURE.md` rules 2-3
  (Definitions are Resources holding no runtime state; runtime state lives in a `RefCounted`
  pointing at a definition by `def_id`) and `CODING_RULES.md`'s own `HeroDefinition` sketch
  (lines 46-52, `@export` fields, no `current_hp`) set the shape.
- `hub/summon/summon.gd` (`hub/summon/summon.gd:1-18`) is explicitly reserved for P2-02's
  replacement and is not touched here. Nothing running today constructs a `Hero` with a
  `def_id`, so prove the round trip with a standalone headless script in the style of
  `tests/save_roundtrip_check.gd` (which drives `GameSession`/`SaveService` directly, not
  through the hub UI), not by clicking Summon.
- Per-archetype base stats and growth are now in `docs/SYSTEMS.md`'s Archetypes/Base-stats
  tables (`docs/SYSTEMS.md:49-83`). Read the values from there, not invented, and do not
  restate them in this ticket or in code comments — a second copy drifts.
- **Corrected formula** (`docs/SYSTEMS.md:26-31`): `rank_mult` and per-level `growth` apply to
  `HP`, `ATK`, `DEF`, `SPD` only. `CRIT_RATE` and `CRIT_DMG` are flat archetype constants with
  no growth and no rank scaling — applying the generic formula to them was a caught bug (a
  Rogue's `CRIT_RATE` would hit 122.55% at SSS, before gear). `HeroDefinition`'s fields must
  reflect this split, not a uniform base+growth pair per stat.
- The existing `from_dict` already tolerates missing keys via `Dictionary.get(key, default)`
  (`heroes/hero.gd:27-28` defaults `name` to `"?"` and `rank` to `0`) — follow the same pattern
  for `def_id` rather than assuming the key is present. Real save files from the Phase 1 exit
  walkthrough exist with no `def_id` key at all, and `Hero.from_dict` must keep loading them.

### Acceptance criteria
- `heroes/hero_definition.gd` defines `class_name HeroDefinition extends Resource` with
  `@export` fields for `HP`/`ATK`/`DEF`/`SPD` as base-and-growth pairs, `@export` fields for
  `CRIT_RATE`/`CRIT_DMG` as single flat values (no growth field for either), plus
  `display_name` and role — this ticket authors data only, not the `final = ...` formula itself
- Five `.tres` instances exist under `heroes/defs/`, one per archetype (Knight, Rogue, Ranger,
  Mage, Cleric), with values copied from `docs/SYSTEMS.md`, not invented
- `Hero` gains a `def_id: StringName` field; `to_dict`/`from_dict` both include it
- A headless round-trip check (extend `tests/save_roundtrip_check.gd` or add a sibling script)
  proves a `Hero` constructed with a non-empty `def_id` survives a `SaveService` save/reload
  cycle unchanged
- A second check loads a **hand-written save fixture in the pre-`def_id` format** (heroes with
  no `def_id` key at all — not a file the test just wrote) and proves it loads without error,
  with those heroes getting a sensible default `def_id`. This is the actual risky-boundary
  proof; a round trip that only reloads its own output does not demonstrate backward
  compatibility (`CLAUDE.md` risky-boundary item 1)
- Existing tests still pass: the P1-02/P1-03 roster and permadeath checks
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean

### Files allowed to change
`heroes/hero_definition.gd`, `heroes/defs/*.tres`, `heroes/hero.gd`, `tests/`

### Non-goals
Wiring `hub/summon/summon.gd` to pick a `HeroDefinition`, roll the weight table, or select from
a definition pool (P2-02); the summon weight table itself; summon/roster/equip UI;
`EquipmentDefinition` or `ZoneDefinition` (`P2-01c`/`P2-01b`, split out above); `balance.tres` or
any shared tunables container (`P2-01d`, shape is `godot-architect`'s open call); applying
`rank_mult` or equipment to a `Hero`'s live stats (no consumer needs computed stats yet — that
lands with combat); adding `level`, `xp`, or equipment slots to `Hero` (deferred to whichever
later ticket first consumes them); moving `Hero.RANK_NAMES` off `Hero` (`godot-architect`'s open
call, not this ticket's); combat, `CombatResult`, `quick_resolve.gd`, XP progression, rank-up,
lost-gear caches, recovery expeditions, salvage, sacrifice, cores, buildings, currencies, or
save-format migrations; a `CRIT_RATE`/`CRIT_DMG` soft cap or diminishing-returns curve — the fix
here is that those two stats simply don't scale with rank or level, not a new capping system.

---
## P2-01d — `BalanceTable` Resource + `balance.tres` authored     [DONE]

Landed in `c46b153`. Every value verified against `SYSTEMS.md` directly, including the rank-up
cost table's seven entries against the rank tables' eight. Transcribing it exposed the
Summoning Circle magnitude gap, fixed in `2d49f6b`; the schema followed in `6b691f9`.

Split off `Hero.RANK_NAMES` relocation as `P2-01d-2` (backlog table above). The two decisions
that unblock this ticket are both settled in `DECISIONS.md` (2026-08-01): `balance.tres` is one
`BalanceTable` Resource, not several split by subsystem, and `RANK_NAMES` does eventually move
onto it — but "moves onto it" only fixes *where the data ends up*, not *how a consumer reaches
`balance.tres` without a fourth autoload*, which is a separate `godot-architect` question still
open and running concurrently with this ticket. Bundling the relocation in here would mean
guessing that mechanism to make `hero.gd`/`summon.gd`/`hub.gd` compile against it. The data
transcription this ticket does is not blocked on that question at all — `BalanceTable`'s shape
and `balance.tres`'s values are fully determined by `SYSTEMS.md` regardless of how anything
later reads them — so it proceeds now and the relocation trails it.

### Objective
`docs/SYSTEMS.md`'s rank table, essence tables, summon weight table, and building-effect
magnitudes exist as one authored `BalanceTable` Resource instance (`balance.tres`), editable in
the inspector without touching code (`ARCHITECTURE.md` r9). This ticket makes no player-facing
change by itself — nothing reads `balance.tres` yet. P2-02 (real summon weights) and later
tickets (sacrifice, buildings) are what make it visible.

### Existing architecture
- No `balance_table.gd` or `balance.tres` exist yet. `DECISIONS.md` (2026-08-01, "`balance.tres`
  is one `BalanceTable` Resource, not several") settled the shape: one Resource type with
  exported fields for every table, authored at the project root as `balance.tres`, per
  `ARCHITECTURE.md` r9's own wording — not one Resource per subsystem.
- `docs/SYSTEMS.md` holds every value this ticket transcribes and nothing else does: the rank
  table (stat multiplier / level cap / affix count / socket count per rank, `SYSTEMS.md:16-21`),
  sacrifice's essence base per rank and essence cost per rank-up (`SYSTEMS.md:116-122`), the
  summon weight per rank (`SYSTEMS.md:289-291`), and the five building effect magnitudes
  (`SYSTEMS.md:313-319`). Read from there — copy values, don't recompute or approximate them,
  and don't restate a single one in this ticket's prose or in code comments; a second copy
  drifts from the first the moment either is tuned.
- Nothing consumes `BalanceTable` yet, and this ticket adds no consumer. `CODING_RULES.md:98`
  sketches the intended shape for later tickets: pure static functions take
  `balance: BalanceTable` as a plain argument (`compute_essence_yield(fodder, target, balance:
  BalanceTable)`) — this ticket only authors the data those functions will read.
- `Hero.RANK_NAMES` (`heroes/hero.gd:7`) and its three call sites (`heroes/hero.gd:20-21`,
  `hub/summon/summon.gd:17`, `hub/hub.gd:26,35`) are untouched by this ticket. They move in
  `P2-01d-2`, once `godot-architect`'s concurrent ruling on the access mechanism lands.
- `BalanceTable` is authored data, not player state. It has no relationship to
  `GameSession.to_dict`/`from_dict` or `SaveService` and must never gain one — see Non-goals.

### Acceptance criteria
- `balance_table.gd` at the project root defines `class_name BalanceTable extends Resource`
  with `@export` fields covering every table named above: per-rank stat multiplier, per-rank
  level cap, per-rank equipment affix count, per-rank core socket count, per-rank essence base,
  per-rank-up essence cost, per-rank summon weight, and one field per building's effect
  magnitude (Summoning Circle, Forge, Training Hall, Sanctum, Reliquary) — field shapes follow
  `SYSTEMS.md`'s own table shapes (one array indexed by rank int `0..7` for the rank-indexed
  tables; the rank-up cost table is indexed by transition, not rank, and is one shorter)
- One authored `balance.tres` instance at the project root with every value copied from
  `SYSTEMS.md`'s tables, not invented or approximated
- A headless check under `tests/` (new script, following `tests/save_roundtrip_check.gd`'s
  style of driving things directly rather than through the hub UI) loads `balance.tres` and
  asserts a representative sample of values against `SYSTEMS.md` verbatim — at minimum the SSS
  stat multiplier, the F and SSS essence bases, the SS→SSS essence cost, and the SSS summon
  weight — catching a transcription typo the import gate cannot see
- Grep-checkable: `BalanceTable` does not appear anywhere in `systems/game_session.gd` or
  `systems/save_service.gd`; `balance.tres` never round-trips through `SaveService`
- No existing file outside this ticket's scope changes: `heroes/hero.gd`, `hub/summon/summon.gd`,
  `hub/hub.gd`, and `hub/hub.tscn` are byte-identical to their pre-ticket state
- Existing tests still pass: P1-02/P1-03 roster and permadeath checks, P2-01a's `def_id`
  round-trip and legacy-fixture checks
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean

### Files allowed to change
`balance_table.gd`, `balance.tres`, `tests/`

### Non-goals
Moving `Hero.RANK_NAMES` off `Hero` and repairing its three call sites (`P2-01d-2`, expanded
separately once `godot-architect`'s ruling on the consumer-access mechanism landed); any function
that consumes `BalanceTable` — `compute_essence_yield`, a real summon roll against the weight
table, `rank_mult`/`growth` applied to a live `Hero`'s stats, or a building reading its own
effect field — those land with the tickets that actually need them (`P2-02`, sacrifice,
buildings, combat). When a building-effect consumer is eventually written (`P2-07`), it must
compute a local value from `BalanceTable`'s exported arrays (e.g. a `var effective_weight :=
base_weight * circle_multiplier`) and never write back into those arrays in place —
`BalanceTable` is one shared Resource instance, and an in-place mutation corrupts every
reference to it and can persist into `balance.tres` on disk; this ticket's data is read-only by
construction, but note the constraint here since P2-07 doesn't own this file. Also out of scope:
`EquipmentDefinition`/`ZoneDefinition` (`P2-01c`/`P2-01b`), `level`/`xp`/equipment slots on
`Hero`, save-format migrations, salvage, sacrifice, cores, combat, `CombatResult`.

---
## P2-01d-2 — Shared rank labels + Summoning Circle schema     [DONE]

Landed in `6b691f9`. First ticket to edit files Phase 1 ships and gates green; the save format
was verified unchanged by diff, not assumed. `rank_label(balance)` and `preload()` consts in
`hub.gd`/`summon.gd` — no autoload, no `GameSession` field.

Unblocked by `godot-architect`'s 2026-08-02 rulings (`DECISIONS.md`, `ARCHITECTURE.md`'s
"Reaching shared Resources"). Folds in a second, unrelated change from the same ruling window:
`game-designer` gave the Summoning Circle a real formula (`SYSTEMS.md`), which needs two new
`BalanceTable` fields in place of the single `summoning_circle_weight_shift` placeholder. Both
changes land in one ticket because both touch only `balance_table.gd` and `balance.tres` plus
their consumers — splitting them means opening the same two files twice for no isolation gained.

### Objective
Roster rank labels and the Phase-1 summon placeholder continue to work after rank-label data
moves from `Hero` into the shared `BalanceTable` Resource. `BalanceTable` also gains the authored
Summoning Circle inputs specified in `SYSTEMS.md`; no building effect consumes them yet.

### Existing architecture
- `BalanceTable` (`balance_table.gd`, `balance.tres`) is the one shared authored-data Resource
  settled by `DECISIONS.md` (2026-08-01). Its exported fields use plural table names and
  building-prefixed, descriptive scalar names (e.g. `forge_enhance_cap_per_level`); it currently
  contains the obsolete `summoning_circle_weight_shift` placeholder.
- `Hero` (`heroes/hero.gd`) is a runtime `RefCounted`. Its `RANK_NAMES` const currently backs
  `rank_label()` (`heroes/hero.gd:7,20-21`), while `hub/summon/summon.gd:17` uses the same const
  to size its placeholder rank roll and `hub/hub.gd:26,35` calls `rank_label()` rendering the
  roster and summon status.
- Per `DECISIONS.md` (2026-08-02, both entries) and `ARCHITECTURE.md`'s "Reaching shared
  Resources" section, `balance.tres` is reached with a plain `preload("res://balance.tres")`
  assigned to a `const` at the top of each flow (`hub/hub.gd` and `hub/summon/summon.gd` both
  qualify) — no autoload, no `GameSession` field. `Hero.rank_label()` gains a
  `balance: BalanceTable` parameter and indexes `balance.rank_names` instead of the removed const.
- `hub/hub.tscn` has exactly two `pressed` connections (`hub.tscn:163-164`), both to no-argument
  button handlers. Passing `balance` to an internal `rank_label()` call changes neither a node nor
  a connection — this is not a scene↔script boundary change under `CLAUDE.md`.
- `Hero.rank` remains a persisted int; `Hero.to_dict`/`from_dict` (`heroes/hero.gd:24-25`) are
  untouched by this ticket — the rank label is presentation only and must not become a
  save-format change. `tests/save_roundtrip_check.gd` already drives the save/reload and P1-03
  permadeath path directly; extend it or a sibling in the same direct style, not through the hub
  scene.
- `SYSTEMS.md`'s Summoning Circle section defines the formula, level cap, affected rank block,
  and the renormalization rule, plus an explicit "Implementation note" naming the current
  one-field placeholder as a schema gap needing two fields (a per-level rate and a level cap).
  Copy the formula's rate and cap values from there — don't restate the worked table in this
  ticket or in code comments.

### Acceptance criteria
- `BalanceTable` gains an exported `rank_names: PackedStringArray` authored in `balance.tres`
  from the rank order already in `Hero.RANK_NAMES`; `Hero.RANK_NAMES` is removed.
- `Hero.rank_label` has the signature `func rank_label(balance: BalanceTable) -> String` and
  returns the clamped label from `balance.rank_names`; all three call sites are updated to pass
  the preloaded `BalanceTable`.
- `hub/hub.gd` and `hub/summon/summon.gd` each declare a typed `const` preloading
  `res://balance.tres` at the top of the file. No autoload, `GameSession` field, service locator,
  or new Resource-loading abstraction is added.
- The roster still renders each hero's rank label, and pressing Summon still produces a `Hero`
  with a valid rank and displays its rank label — same observable behavior as before this ticket.
- `summoning_circle_weight_shift` is replaced in both `balance_table.gd` and `balance.tres` by
  two fields — a per-level rate and a level cap, named consistently with the existing
  `_per_level`/`_cap` suffixes already used elsewhere in the file — with values copied from
  `SYSTEMS.md`'s Summoning Circle section, not invented or approximated. Nothing reads these
  fields in this ticket.
- A headless check (extend `tests/balance_table_check.gd` or add a sibling, following its style
  of loading `balance.tres` directly) asserts `balance.rank_names` matches the prior
  `Hero.RANK_NAMES` order and asserts both new Summoning Circle fields against `SYSTEMS.md`
  verbatim.
- `tests/save_roundtrip_check.gd` still passes in full, including its P1-02/P1-03 roster and
  permadeath checks — no save payload or save version changes.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean with
  zero script errors and zero warnings.

### Files allowed to change
`balance_table.gd`, `balance.tres`, `heroes/hero.gd`, `hub/summon/summon.gd`, `hub/hub.gd`,
`tests/`

### Non-goals
P2-02's real weighted summon roll, the renormalization arithmetic itself, and the `def_id` →
`HeroDefinition` lookup; `ZoneDefinition`/`EquipmentDefinition` (`P2-01b`/`P2-01c`); implementing
any building effect or a Summoning Circle consumer that actually reads the two new fields
(`P2-07` — this ticket authors data only, nothing reads it); combat; the XP curve (`P2-04a`) and
Summon Stone income (`P2-09`); any change to `Hero.to_dict`/`from_dict`, `GameSession`,
`SaveService`, or the save format; any `hub/hub.tscn` node, unique-name, or connection change. A
future Summoning Circle consumer must compute a local value (e.g. `effective_weight :=
base_weight * circle_multiplier`) and never write back into `BalanceTable`'s exported arrays in
place — the same shared-Resource mutation hazard `P2-01d` already flags for `P2-07`.

---
## P2-01b — `ZoneDefinition` Resource + three zones authored     [DONE]

Landed in `cbf8f91`. All 24 authored fields asserted against `SYSTEMS.md`, not sampled. The wave
ramp is stored as endpoints only — no interpolation rule was invented, and P2-03 owns that
transformation. Nothing references `WaveDefinition`, which still has no home in the layout.

**Settled since.** That open type is closed: it is `Wave` (`zones/wave.gd`, `RefCounted`), not a
`Definition` — see `DECISIONS.md`, 2026-08-02. P2-03 inherits a named type instead of the naming
question, and the ramp interpolation this ticket declined to invent must live in exactly one
place. The deferral above was right; it is simply no longer open.

### Objective
`docs/SYSTEMS.md`'s three expedition zones exist as authored `ZoneDefinition` Resource
instances under `zones/defs/`, editable in the inspector without touching code. This ticket
makes no player-facing change by itself — nothing reads a zone yet. `P2-03` is what consumes
the data to build and resolve waves.

### Existing architecture
- No `zones/zone_definition.gd` or `zones/defs/` exist yet, though `ARCHITECTURE.md`'s
  "Project layout" already reserves the folder (`docs/ARCHITECTURE.md:121`). Rules 2-3
  (`docs/ARCHITECTURE.md:15-20`) require a Definition to be a Resource holding no runtime
  state; a zone's wave index and in-progress HP belong to an expedition-scoped
  `RefCounted`/`Node` instead — `DECISIONS.md` already rejected a `CombatState` autoload for
  exactly this and named `hub/expedition/expedition.gd`'s `Expedition` as where it belongs
  (`docs/DECISIONS.md:142-159`).
- `ARCHITECTURE.md`'s "Reaching shared Resources" section names `ZoneDefinition` explicitly
  alongside `HeroDefinition`/`EquipmentDefinition` as authored data reached by a plain
  `preload()`/`load()`, never handed out by an autoload (`docs/ARCHITECTURE.md:62-85`).
- `docs/SYSTEMS.md:240-282` (Expeditions) is the sole source for this ticket's fields and
  values: the `ZoneDefinition` sketch (name, recommended power, wave list, loot table, unlock
  condition), the three-zone table (`SYSTEMS.md:257-261`), and the explicit rejection of
  per-species enemy stats or a bestiary as scope creep (`SYSTEMS.md:263-268`). Copy values and
  descriptive text verbatim — do not recompute, approximate, or restate them in this ticket's
  prose or in code comments; a second copy drifts the moment either is tuned.
- The zone table gives each wave ramp only as a trash-wave count plus start/end fractions of
  recommended power (e.g. "5 trash (50%→90% of RP) + 1 boss (110% RP)") — no intermediate
  per-wave values or interpolation rule. Author the endpoints and count as given; inventing a
  linear-interpolation rule here would be design `SYSTEMS.md` never specified. That
  transformation, and constructing whatever the combat seam's `wave: WaveDefinition` argument
  (`docs/ARCHITECTURE.md:96`) turns out to be, is `P2-03`'s job — `WaveDefinition` is a
  committed type name in the combat-seam signature but appears nowhere in the project layout
  yet (`docs/ARCHITECTURE.md:110-128`); closing that gap is `P2-03`'s call, not this ticket's.
- `docs/SYSTEMS.md`'s recommended-power figures carry a `PROVISIONAL` marker
  (`SYSTEMS.md:270-273`) — settled only by both combat paths existing and a played build.
  Fine to transcribe today; do not present them as balanced or final.
- `tests/balance_table_check.gd` is the precedent for the required headless transcription
  check: `extends SceneTree`, `load()` the `.tres`, compare fields against hardcoded literals
  copied from `SYSTEMS.md`, report through a `_fail()` helper, exit nonzero on the first
  mismatch.

### Acceptance criteria
- `zones/zone_definition.gd` defines `class_name ZoneDefinition extends Resource` with
  `@export` fields for: display name, recommended power, trash-wave count, trash-wave
  start/end fraction of recommended power, boss fraction of recommended power, loot emphasis
  (descriptive text), and unlock condition (descriptive text). No runtime fields, no
  `WaveDefinition` reference or construction.
- Three `.tres` instances exist under `zones/defs/` — Verdant Outskirts, Ashfall Reaches,
  Sundered Vault — with every field copied from `docs/SYSTEMS.md:257-261`, not invented or
  approximated.
- A headless check under `tests/` (new script, following `tests/balance_table_check.gd`'s
  style) loads all three authored zones and asserts every field of every zone against
  `SYSTEMS.md` verbatim — three zones at this size is cheap enough to check exhaustively
  rather than sample.
- Grep-checkable: `ZoneDefinition` does not appear anywhere in `systems/game_session.gd` or
  `systems/save_service.gd`; no zone `.tres` ever round-trips through `SaveService`.
- No existing file outside this ticket's scope changes: `heroes/`, `hub/`, `systems/`, `ui/`,
  and `project.godot` are byte-identical to their pre-ticket state.
- Existing tests still pass: P1-02/P1-03 roster and permadeath checks, P2-01a's `def_id`
  round-trip and legacy-fixture checks, P2-01d's balance-table check.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean.

### Files allowed to change
`zones/zone_definition.gd`, `zones/defs/*.tres`, `tests/`

### Non-goals
Any consumer of `ZoneDefinition` — constructing a `WaveDefinition`, resolving waves,
`quick_resolve.gd`, `CombatResult`, HP carry-forward, permadeath, the retreat threshold (all
`P2-03`). The combat seam names `WaveDefinition`, but nothing in the project layout defines it
yet; closing that gap is `P2-03`'s call, not this ticket's. Also out of scope: per-species
enemy stats or a bestiary (`SYSTEMS.md`'s own rejection); actual loot tables and drop rolls;
lost-gear caches and recovery runs (`P2-04`); `EquipmentDefinition` (`P2-01c`); zone unlock
progression as enforced gating logic — `unlock_condition` here is descriptive authored text
only, nothing reads or enforces it; the arena.

---
## P2-01c — EquipmentDefinition Resource + 10-slot enum authored     [DONE]

Landed in `eb3c35a`. Completes the P2-01 group. All 30 authored fields asserted and all ten
slot→primary-stat mappings re-derived against `SYSTEMS.md` independently. Grep-verified that
`equipment_affix_counts`/`core_socket_counts` are not restated — those stay per-rank tuning in
`balance.tres`.

### Objective
`docs/SYSTEMS.md`'s ten equipment slots and their primary stats exist as authored
`EquipmentDefinition` Resource instances under `equipment/defs/`, editable in the inspector
without touching code. This ticket makes no player-facing change by itself — nothing reads an
equipment definition yet. `P2-04` (lost-gear caches) is what first makes this data visible.

### Existing architecture
- `ARCHITECTURE.md` rules 2-3 require Definitions to be Resources holding no runtime state
  (`docs/ARCHITECTURE.md:15-20`). `CODING_RULES.md` makes the equipment-specific shape explicit:
  prefer one Resource type with exported fields over N subclasses — one `EquipmentDefinition`
  with exported values, not ten slot subclasses (`docs/CODING_RULES.md:64-66`).
- `ARCHITECTURE.md`'s "Reaching shared Resources" section names `EquipmentDefinition` explicitly
  alongside `HeroDefinition`/`ZoneDefinition` as authored data reached by a plain
  `preload()`/`load()`, never handed out by an autoload (`docs/ARCHITECTURE.md:62-85`).
- The project layout already reserves `equipment/` for `item.gd`, `equipment_definition.gd`,
  `core_definition.gd`, and `defs/*.tres` (`docs/ARCHITECTURE.md:110-128`). This ticket creates
  only `equipment_definition.gd` and its `.tres` instances: `item.gd` is P2-05's runtime
  rolled-item `RefCounted`; `core_definition.gd` and Core behavior are Phase 4. Neither is
  touched here.
- `docs/SYSTEMS.md:184-209` is the sole source for this ticket's authored data: the closed
  ten-slot set (`head chest legs gloves boots main_hand off_hand necklace ring belt`) and each
  slot's primary stat (head/legs → HP; chest/off_hand → DEF; main_hand/gloves → ATK;
  boots/belt → SPD; necklace → CRIT_RATE; ring → CRIT_DMG). Copy the names and mapping verbatim
  — do not invent flavor names, rank, affixes, rolled values, or item identities; none of that
  exists in `SYSTEMS.md` yet.
- `BalanceTable` already owns the per-rank `equipment_affix_counts` and `core_socket_counts`
  arrays (`balance_table.gd:6-7`), transcribed from the rank table (`docs/SYSTEMS.md:16-21`).
  Those are rank tuning under `ARCHITECTURE.md` rule 9 (`docs/ARCHITECTURE.md:37-38`), not
  per-definition data, and must not be restated on `EquipmentDefinition` or in `equipment/defs/`
  — a second copy drifts from `balance.tres` the moment either is tuned.
- `HeroDefinition` uses typed, snake_case stat field names — `base_hp`, `base_atk`, `base_def`,
  `base_spd`, `crit_rate`, `crit_dmg` (`heroes/hero_definition.gd:4-15`). No project-wide stat
  enum exists yet (checked — no `enum` naming HP/ATK/DEF/SPD/CRIT anywhere outside `addons/gut`).
  Mirror `HeroDefinition`'s stat names in a new, closed `PrimaryStat` enum on
  `EquipmentDefinition` rather than introducing free-form stat-name strings. Unlike
  `HeroDefinition.role`, which stayed a String with no compile-time enforcement
  (`heroes/hero_definition.gd:5`), the ten slots are a small, permanently fixed, closed set that
  upcoming equip-validation and primary-stat-lookup code will consume by name — an enum turns a
  typo'd slot into a compile error instead of a runtime string mismatch, matching the fail-loud
  philosophy `CODING_RULES.md` already applies elsewhere (`docs/CODING_RULES.md:118-122`).

### Acceptance criteria
- `equipment/equipment_definition.gd` defines `class_name EquipmentDefinition extends Resource`
  with `enum Slot { HEAD, CHEST, LEGS, GLOVES, BOOTS, MAIN_HAND, OFF_HAND, NECKLACE, RING, BELT }`,
  an exported `slot: Slot` field, and an exported `primary_stat` field using a closed enum whose
  members mirror `HeroDefinition`'s existing stat naming (`HP`, `ATK`, `DEF`, `SPD`, `CRIT_RATE`,
  `CRIT_DMG`); it also exports `display_name: String`. No free-form String slot or
  primary-stat field, no runtime state, no rank, affixes, rolled values, or unique item name.
- Ten `.tres` instances exist under `equipment/defs/`, one per slot — Head, Chest, Legs,
  Gloves, Boots, Main Hand, Off Hand, Necklace, Ring, Belt — each authoring exactly `slot`,
  `display_name`, and `primary_stat`, matching `docs/SYSTEMS.md:198-209` verbatim. These are
  authored per-slot data for a future loot table to reference, not item instances in `P2-04`'s
  loot-table sense — the same relationship `HeroDefinition` has to a future summon-weight roll.
- A headless check under `tests/` (new script, following `tests/balance_table_check.gd` and
  `tests/zone_definition_check.gd`'s direct-load, `_fail()`, nonzero-exit-on-mismatch style)
  loads all ten definitions and asserts every authored field of every slot against
  `docs/SYSTEMS.md` verbatim — ten slots at three fields each is cheap enough to check
  exhaustively rather than sample.
- Grep-checkable: `EquipmentDefinition` does not appear anywhere in `systems/game_session.gd` or
  `systems/save_service.gd`; no equipment `.tres` ever round-trips through `SaveService`.
- Grep-checkable: neither `equipment_affix_counts` nor `core_socket_counts` appears in
  `equipment/equipment_definition.gd` or anywhere under `equipment/defs/` — those per-rank
  arrays stay owned solely by `BalanceTable`.
- No existing file outside this ticket's scope changes: `heroes/`, `hub/`, `systems/`, `ui/`,
  `zones/`, and `project.godot` are byte-identical to their pre-ticket state.
- Existing tests still pass: `tests/save_roundtrip_check.gd`'s roster/permadeath and `def_id`
  checks, `tests/balance_table_check.gd`, and `tests/zone_definition_check.gd`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean with
  zero script errors and zero warnings.

### Files allowed to change
`equipment/equipment_definition.gd`, `equipment/defs/*.tres`, `tests/`

### Non-goals
Item instances or rolled items; `Item` as a `RefCounted`; affix rolling; enhancement; salvage,
part conversion, or any other `P2-05` behavior; Cores and sockets as behavior (Phase 4);
equipping anything to a `Hero`; equip UI (`P2-05a`); lost-gear caches or recovery expeditions
(`P2-04`); loot tables; any consumer that reads an `EquipmentDefinition`; `item.gd`;
`core_definition.gd`; save-format changes; restating `BalanceTable`'s
`equipment_affix_counts`/`core_socket_counts` anywhere in this ticket's files.

---
## P2-02 — Real weighted summon + archetype roster display          [DONE]

Landed in `0556ce0`, hardened in `1a67450` after an adversarial `verifier` pass.

The finding worth carrying forward is about *where* logic lives, not what it does. The code was
correct on the first pass; nothing proved it. The three-way archetype-label decision sat inside
`_refresh_roster()`, a method on a `Node3D` bound to `hub.tscn` — and because this repo's checks
deliberately drive things directly rather than through the hub UI, **nothing could reach it**.
Collapsing the loud unresolvable-`def_id` branch into the silent legacy one defeated this
ticket's headline requirement and still passed the gate, all six checks, and GUT. It is now
`Summon.archetype_label_for()`, and `hub/hub.gd` is pure row formatting.

The general lesson for later UI tickets: a branch reachable only by instantiating a scene is
untested by construction here. Extract the decision, leave the rendering.

Second finding, same shape one layer down: `tests/summon_weight_check.gd` proved itself
"exhaustive over the table" while being exhaustive over a *hardcoded copy* of the table, never
reconciled against the shipped `balance.tres`. `balance_table_check.gd` spot-checks only index 7,
so per-index drift anywhere else went uncaught — this repo's own "a second copy drifts" objection,
landed in test code where it is harder to spot. Both fixes were mutation-proven.

`P2-05a` (equip UI) was split out of this ticket's original backlog line and sequences after
`P2-05`. `SYSTEMS.md:324`'s "that rank's pool" wording remains `game-designer`'s to correct.

Narrowed from the original backlog line ("Real summon against the weight table; roster and
equip UI"). Equip UI is split out to `P2-05a`: nothing is equippable yet — `Hero` has no
equipment slots, `equipment/item.gd` doesn't exist (`P2-05` owns it), there is no loot table
(`P2-04` owns it), and adding slots now would touch the save format for a UI with nothing to
put in it.

### Objective
Pressing Summon creates a hero with a rank rolled against `BALANCE.summon_weights` and one of
the five authored archetypes, then the roster displays that archetype alongside the hero's rank
and name.

### Existing architecture
- `hub/summon/summon.gd` is the Phase-1 placeholder explicitly reserved for wholesale
  replacement here (its own header comment says so). Its current `randi() %
  BALANCE.rank_names.size()` roll is uniform across all eight ranks, ignoring weights entirely,
  and its fixed name list creates a `Hero` with no `def_id`.
- `BalanceTable.summon_weights` is already authored and matches `SYSTEMS.md`'s table —
  `[4000, 2700, 1700, 1000, 450, 120, 28, 2]` (`balance_table.gd:10`), same F-through-SSS index
  order as `rank_names`. Nothing reads `summon_weights` yet — this ticket is its first consumer.
- `Hero` (`heroes/hero.gd`) already carries `def_id: StringName` and round-trips it through
  `to_dict`/`from_dict`; `NO_ARCHETYPE_DEF_ID` (`&""`) is the empty sentinel. An empty `def_id`
  is legitimate legacy Phase-1 data and must keep loading without error; a non-empty `def_id`
  that resolves to no `HeroDefinition` is a failed Resource lookup and must fail loudly
  (`CODING_RULES.md:121-122`), never silently default. `tests/save_roundtrip_check.gd` already
  hand-constructs both cases directly — it never calls `Summon.roll()`, so it does not cover the
  gameplay path this ticket adds.
- The five authored `HeroDefinition` Resources are `knight`, `rogue`, `ranger`, `mage`, and
  `cleric` (`heroes/defs/*.tres`). `HeroDefinition` has no rank field, and rank-up preserves a
  hero's level rather than replacing the hero (`DECISIONS.md`, ~line 226) — archetype is
  therefore independent of rolled rank. `SYSTEMS.md:324`'s "a random definition from that rank's
  pool" wording doesn't match the authored data (no rank-scoped pool exists); read the pool as
  all five archetypes, independent of rank, and flag the wording mismatch rather than inventing a
  rank-scoped pool that isn't there (see Unresolved below).
- `hub/hub.gd` already owns roster presentation: `_refresh_roster()` formats each row, and
  `_on_summon_pressed()` calls `Summon.roll()`. `hub/hub.gd` and `hub/summon/summon.gd` both
  already preload `balance.tres` as a typed `const`, matching `ARCHITECTURE.md`'s "Reaching
  shared Resources" section — keep the same pattern for the `def_id → HeroDefinition` lookup
  (`load()`/`preload()` assigned to a `const`, never handed out by an autoload). Adding an
  archetype label to a roster row is a string-format change in `hub/hub.gd`; `hub/hub.tscn` needs
  no node, unique-name, or `[connection]` change for it.

### Acceptance criteria
- `Summon.roll()` replaces the Phase-1 uniform rank roll with a weighted cumulative roll using
  `BALANCE.summon_weights`; each rank's chance is its authored weight divided by the table total,
  with no weight values copied into code.
- A direct headless check proves the deterministic weighted-roll logic assigns exactly 4000,
  2700, 1700, 1000, 450, 120, 28, and 2 of the 10000 possible tickets to F through SSS
  respectively (exhaustive over the table, not a probabilistic sample); it also fails loudly on
  an invalid ticket or an inconsistent weight table rather than indexing silently.
- Each new summon receives a non-empty `def_id` chosen from all five authored archetypes,
  independent of the rolled rank, and the `def_id` resolves to the matching `HeroDefinition`
  through a typed `const` Resource load.
- A non-empty `def_id` that resolves to no `HeroDefinition` emits a visible error and does not
  silently substitute an archetype; an empty `NO_ARCHETYPE_DEF_ID` is legitimate legacy data and
  emits no lookup error.
- Every roster row displays the resolved `HeroDefinition.display_name` alongside the existing
  rank label and hero name; a legacy hero with an empty `def_id` displays an explicit
  no-archetype label without error.
- A headless check calls `Summon.roll()`, adds the resulting hero to `GameSession.roster`, drives
  a real `SaveService` save/reload cycle, and asserts the summoned hero keeps the identical
  non-empty `def_id` and resolves to the same archetype after reload — this is the risky-boundary
  case `tests/save_roundtrip_check.gd`'s existing (hand-constructed) fixtures don't cover.
- No `hub/hub.tscn` node, unique-name, or `[connection]` block changes.
- Existing tests still pass: `tests/save_roundtrip_check.gd` in full (legacy empty-`def_id`,
  malformed-`def_id`, roster, and permadeath checks — no save payload or save version changes)
  and `tests/balance_table_check.gd`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean with
  zero script errors and zero warnings.

### Files allowed to change
`hub/summon/summon.gd`, `hub/hub.gd`, `tests/`

### Non-goals
Summoning Circle weight renormalization (`P2-07` — `summoning_circle_multiplier_per_level` and
`summoning_circle_level_cap` are authored and deliberately unread until then); summon cost,
currency, or income rate of any kind (`P2-09` — no Summon Stone income rate is defined, so there
is no number to charge); equipment slots on `Hero`, `equipment/item.gd`, loot, or equip UI
(`P2-05a`, after `P2-05`); any change to `Hero.to_dict`/`from_dict`, `GameSession`,
`SaveService`, or the save file format/version; combat, `CombatResult`, `quick_resolve.gd`, or
`Wave`; pity timers, duplicate protection, or summon animation.

**Unresolved wording mismatch (for `game-designer`, not blocking this ticket):**
`SYSTEMS.md:324` says "Roll a rank from the table, then a random definition from that rank's
pool," but no rank-scoped pool exists anywhere in the data — `HeroDefinition` has no rank field
and rank-up preserves an existing hero rather than replacing it, so archetype and rank are
independent by construction. This ticket proceeds on the only data-supported reading (one shared
pool of all five archetypes, independent of rank); `SYSTEMS.md`'s wording should be corrected to
match, but that correction is `game-designer`'s call on its own document, not this ticket's.

---
## P2-03a — Wave construction + computed hero stats                 [DONE]

Landed in `ab11d34`, hardened in `32a3f59` after an adversarial `verifier` pass. First ticket to
add real GUT coverage.

Two things worth carrying into `P2-03b`.

**The single-interpolation-site rule is now a grep, not a promise.** The ADR requires the ramp
interpolation to live in one place and hand both `resolve()` paths the same `Wave`. This ticket
satisfied that only because `combat/` did not exist and its file scope kept it that way — which
stops binding the moment `P2-03b` creates the directory. `P2-03b`'s acceptance criteria carry the
mechanical replacement (`2f1602f`).

**`Wave.from_zone()` guards `wave_index` with `assert()`, which Godot strips in release.** An
out-of-range index does not error in a shipped build — `lerpf` extrapolates past
`trash_wave_end_fraction` and returns a plausible `enemy_power` (index 6/7/10 against a
five-trash zone yields fraction 1.1/1.2/1.5, silently). The `verifier` judged this consistent with
`CODING_RULES.md` — `assert` for internal programmer-error invariants, `push_error` at trust
boundaries, and a wave index is a loop counter — so it is not a defect here. It is a landmine for
whoever writes `P2-03b`'s wave loop, and Phase 1's exit gate was specifically that the loop works
in a *shipped* binary.

`compute_team_power()`'s three parallel arrays were left as-is deliberately: no caller exists yet,
`P2-03b` uses a one-hero team, and multi-hero squad select is `P2-03c`. The correspondence test
added in `32a3f59` is what protects it until a real caller informs the shape.

### Objective
A zone's authored ramp produces runtime `Wave` instances with a single `enemy_power`, and combat
has one computed-stat path for deriving each hero's final HP/ATK/DEF/SPD and team `hero_power`.
This ticket makes no player-facing change by itself: `Expedition.survives()` remains the Phase-1
coin flip until P2-03b consumes these outputs.

### Existing architecture
- `ZoneDefinition` (`zones/zone_definition.gd:1-11`) is an authored `Resource` containing only
  `recommended_power`, trash-wave count, ramp endpoints, boss fraction, and descriptive zone
  fields; it stores neither per-wave data nor `Wave` construction.
- The combat seam is fixed at `resolve(team: Array[Hero], wave: Wave) -> CombatResult`
  (`docs/ARCHITECTURE.md:89-106`). `Wave` is specifically `zones/wave.gd`, a runtime
  `RefCounted`, not a Definition: it derives one wave's composition from a zone ramp and index
  (`docs/ARCHITECTURE.md:108-117`; `docs/DECISIONS.md:10-59`). The interpolation must live in
  exactly one place and both combat implementations must receive the same instance.
- A wave's contents are one `enemy_power` scalar, not named enemies or per-species stat lines
  (`docs/SYSTEMS.md:263-268`). `hero_power = ATK + DEF + HP/10 + SPD`, summed across the team,
  is quick-resolve scaling and a UI-warning input only, never a hard gate
  (`docs/SYSTEMS.md:244-248`).
- `Hero` is a runtime `RefCounted` with persisted `hero_name`, `rank`, and `def_id` only
  (`heroes/hero.gd:1-40`); `HeroDefinition` owns base/growth data and flat crit values
  (`heroes/hero_definition.gd:1-15`), while `BalanceTable.stat_multipliers` owns rank multipliers
  (`balance_table.gd:1-20`). `Hero.rank_label(balance)` is the precedent for a `Hero` method
  receiving `BalanceTable` explicitly (`heroes/hero.gd:19-20`; `docs/DECISIONS.md:100-115`).
- The final-stat formula is `final = (base + growth * level) * rank_mult + equip_flat`, then
  `final *= 1.0 + equip_pct` (`docs/SYSTEMS.md:44-47`), but rank/growth apply only to
  HP/ATK/DEF/SPD. `CRIT_RATE` and `CRIT_DMG` remain flat archetype constants, unaffected by rank
  or level (`docs/SYSTEMS.md:26-31,73-75`).
- GUT 9.7.1 is already installed under `addons/gut/`; `tests/unit/test_gut_harness.gd:1-7` is
  only its disposable harness proof. P2-03 is the first ticket to add real GUT coverage
  (`CLAUDE.md:48-57`).

### Acceptance criteria
- `zones/wave.gd` defines `class_name Wave extends RefCounted`; it represents one runtime wave
  with the `enemy_power` derived from `ZoneDefinition.recommended_power` and the stored trash-ramp
  or boss fraction, never from hand-authored per-wave `.tres` data.
- The ramp interpolation is implemented in exactly one place. A caller building a wave for a
  zone/index receives the same `Wave` object that either combat path can pass to its `resolve()`;
  neither resolver re-derives the ramp from raw `ZoneDefinition` endpoints.
- One computed-stat path consumes `Hero`, its resolved `HeroDefinition`, and `BalanceTable` to
  derive final HP/ATK/DEF/SPD and the team `hero_power` formula from
  `docs/SYSTEMS.md:44-47,247-248`. The level is a plain computation input or an internal
  baseline, not persisted state.
- `CRIT_RATE` and `CRIT_DMG` remain the definition's flat constants: GUT coverage proves rank
  multiplier and growth affect HP/ATK/DEF/SPD correctly while leaving both crit values untouched.
- GUT coverage under `tests/unit/` proves trash-ramp interpolation at the first, middle, and last
  trash indices, plus the boss wave; it also proves the computed-stat and CRIT-exemption cases.
- `Hero.to_dict`/`from_dict` and `GameSession.to_dict`/`from_dict` are byte-identical to their
  pre-ticket state; no save payload or version changes.
- Existing tests still pass, including the prior save-roundtrip, authored-data checks, and the GUT
  harness; `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1` exits clean
  with zero script errors and zero warnings; the GUT suite command in `CLAUDE.md:53-57` exits green.

### Files allowed to change
`zones/wave.gd`, `heroes/hero.gd`, `tests/unit/`

### Non-goals
`combat/quick_resolve.gd`, `combat/combat_result.gd`, expedition UI wiring, HP carry-forward,
retreat, and permadeath (P2-03b); `combat/arena/` (P2b-01, which does not exist yet — this
ticket's shape must remain reusable by it without claiming both paths agree today); equipment,
`EquipmentDefinition`, `equip_flat`, or `equip_pct` (P2-01c/P2-05a, not authored as combat
inputs); adding persisted `level`, `xp`, equipment slots, current HP, or any other field to
`Hero` (P2-04a owns the XP curve, and an inert persisted level would create an unjustified save
boundary); any change to `Hero.to_dict`/`from_dict`, `GameSession.to_dict`/`from_dict`,
`SaveService`, or the save format; lost-gear caches and recovery expeditions (P2-04); named enemy
species, per-species stat lines, or a bestiary (`docs/SYSTEMS.md:263-268`); treating provisional
recommended-power figures as final balance (`docs/SYSTEMS.md:270-273`); a `CombatState` or any
fourth autoload.

---
## P2-03b — Statistical expedition resolution + permadeath          [DONE]

Landed in `35cdc5e`; two follow-up fixes in `f98fe04` and `be34b11`, both after adversarial
`verifier` passes. The acceptance criteria are met and independently re-verified — but read the
ceiling below before building on this.

**A wrongful permadeath was reachable in a shipped build** (`f98fe04`). An empty `def_id` is
supported data, not corruption, and real Phase-1 saves carry it. Sending such a hero on an
expedition resolved its definition to `null`; the guarding `assert` is stripped in release, and
Godot 4.7.1's null property read returns a recovery Variant that the VM does not validity-check
without `DEBUG_ENABLED` — so it propagated through the arithmetic into HP 0, which the death check
read as a real death and passed to `kill_hero()`. Guarded now by a preflight in
`Expedition.resolve`, placed there rather than in `hub/hub.gd` because the GUT tests call it
directly and a UI-only guard would have left that path open.

**The loop was unwinnable at every rank** (`be34b11`). Two independent mismatches, neither
sufficient alone: `recommended_power` is authored for a five-hero team while this ticket sends
one, and it is calibrated against heroes at their rank's **level cap** while combat hardcoded
level 0. Rules in `SYSTEMS.md` (`7d1ca27`); F-rank Knight's first wave went from arithmetically
impossible to 57.5%.

**Ceiling — `P2-03d` owns it.** Win, loss, retreat, and death are each reachable, and that is what
this ticket promised. **A zone clear is not.** Damage is charged as a fraction of *max* HP per
wave, so Verdant's five trash waves total 2.97× a hero's max HP: every solo archetype retreats
after wave 2 of 5 at calibration rank, and Cleric dies there. The boss is unreachable, so zone
progression is unreachable. That formula is a worker's invention — `SYSTEMS.md` never specified
one — which is why it routes to `game-designer` rather than being patched here.

Also known: `Hero.compute_final_stats`'s null-definition guard is unreachable dead code — mutating
it leaves the suite green, because every production caller filters before it. Harmless, but it is
not the defense-in-depth layer its artifact claimed.

### Objective
Pressing Expedition resolves real ordered waves instead of `Expedition.survives()`'s coin flip:
heroes carry HP through the expedition, retreat at the authored threshold, and a hero reduced to
0 HP is permanently removed once through `GameSession.kill_hero()`. A bad expedition can now
produce a real loss, retreat, or permanent death.

### Existing architecture
- `hub/expedition/expedition.gd:1-11` is explicitly a Phase-1 coin-flip placeholder, documented
  as replaced by P2-03's `quick_resolve.gd` behind the `CombatResult` seam. `hub/hub.gd:22-52`
  refreshes and resolves the roster through `get_selected_items()[0]`: its existing Expedition
  button supports one selected hero only, then calls `Expedition.survives()` and
  `GameSession.kill_hero()` on loss.
- No zone-selection UI exists. This ticket wires the existing single-hero button to the authored
  Verdant Outskirts zone, `zones/defs/verdant_outskirts.tres`, whose unlock condition is
  "Available from start" (`zones/defs/verdant_outskirts.tres:14`; `docs/SYSTEMS.md:257-261`).
- `combat/` does not exist yet. The required seam is two plain functions with the same
  `resolve(team: Array[Hero], wave: Wave) -> CombatResult` signature
  (`docs/ARCHITECTURE.md:89-103`); `CombatResult` carries survivors, HP after, dead heroes, and a
  loot seed (`docs/ARCHITECTURE.md:105-106`). Rule 7 prohibits `combat/` from reaching into
  `hub/` (`docs/ARCHITECTURE.md:29-30`).
- P2-03a supplies `Wave`: a runtime `RefCounted` containing a pre-resolved `enemy_power`, built
  once from `ZoneDefinition`'s ramp and handed unchanged to combat
  (`docs/ARCHITECTURE.md:108-117`). Quick resolve statistically compares that scalar with team
  `hero_power`, not a bestiary (`docs/SYSTEMS.md:247-248,263-268`).
- Waves resolve in order and HP carries forward; the default retreat threshold is 25% party HP
  (`docs/SYSTEMS.md:244-245,275-280`). Wave index and in-progress HP are expedition-run-scoped
  state on a `RefCounted`/`Node`, not a fourth autoload or `GameSession`
  (`docs/DECISIONS.md:195-212`).
- `GameSession.kill_hero(hero)` is the single roster-removal implementation
  (`systems/game_session.gd:24-28`). Rule 8 requires the expedition resolver to be the one place
  applying permadeath (`docs/ARCHITECTURE.md:32-35`); direct roster mutation anywhere else is
  forbidden.
- `Hero` persistence remains only name/rank/def_id (`heroes/hero.gd:9-40`), serialized by
  `GameSession.to_dict`/`from_dict` (`systems/game_session.gd:31-43`). Per-run HP must not enter
  that save path.

### Acceptance criteria
- `combat/quick_resolve.gd` and `combat/combat_result.gd` implement the stated seam and
  `CombatResult` contract: survivors, HP after, dead heroes, and loot seed. `combat/` accepts
  explicit inputs and never reaches into `hub/`, `GameSession`, or an autoload for combat state.
- Grep-checkable: `combat/` constructs no `Wave` of its own. `trash_wave_count`,
  `trash_wave_start_fraction`, `trash_wave_end_fraction`, and `boss_fraction` appear nowhere under
  `combat/`, and every `Wave` reaching a `resolve()` came from `Wave.from_zone()`. P2-03a left the
  ADR's single-interpolation-site rule enforced only by its own file scope — `combat/` did not
  exist, so the ramp had nowhere else to go. **That stops binding the moment this ticket creates
  the directory**, and this criterion is what replaces it.
- The expedition flow replaces the Phase-1 coin flip with ordered quick-resolve waves built by
  P2-03a. The existing single selected hero is passed as a one-hero `team: Array[Hero]`, and the
  flow loads `zones/defs/verdant_outskirts.tres` as its hardcoded zone. Each wave compares team
  `hero_power` and the supplied wave's `enemy_power` statistically; recommended power remains
  scaling data, never an expedition-entry hard gate.
- HP after each wave becomes the next wave's starting HP during that one expedition run. The
  resolver applies the authored 25% party-HP retreat threshold and returns a retreat outcome
  without continuing later waves.
- Each hero reaching 0 HP is passed to `GameSession.kill_hero()` exactly once by the expedition
  resolver; no file mutates `GameSession.roster` directly. The roster shrinks by exactly the
  number of distinct dead heroes, and the hub displays the resulting win/loss/retreat outcome.
- GUT coverage under `tests/unit/` proves a guaranteed-win wave sequence; a guaranteed-loss
  sequence that kills one hero through `GameSession.kill_hero()` and leaves the roster smaller by
  exactly one; retreat at the 25% threshold; and correct HP carry-forward across two waves in one
  expedition run.
- Existing tests still pass, including P2-03a's Wave/stat tests and the prior save-roundtrip and
  authored-data checks; `powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1`
  exits clean with zero script errors and zero warnings; the GUT suite command in
  `CLAUDE.md:53-57` exits green.
- `Hero.to_dict`/`from_dict` and `GameSession.to_dict`/`from_dict` are byte-identical to their
  pre-ticket state; expedition HP and wave state disappear when the run ends and neither changes
  the save payload or version.

### Files allowed to change
`combat/quick_resolve.gd`, `combat/combat_result.gd`, `hub/expedition/expedition.gd`,
`hub/hub.gd`, `tests/unit/`

### Non-goals
A multi-hero squad-select UI (`hub.gd`'s roster list stays single-select); a zone-select UI (the
zone is hardcoded to Verdant Outskirts; selecting among the three authored zones is a follow-up
ticket); `combat/arena/` (P2b-01, which does not exist yet — the seam must remain reusable by it
without pretending agreement between two implementations is testable today); changing P2-03a's
Wave-ramp construction or duplicating its interpolation in combat; equipment,
`EquipmentDefinition`, `equip_flat`, or `equip_pct` (P2-01c/P2-05a, not authored as combat
inputs); adding `level`, `xp`, equipment slots, current HP, or any other persisted field to
`Hero` (P2-04a owns the XP curve); lost-gear caches and recovery expeditions (P2-04); named enemy
species, per-species stat lines, or a bestiary (`docs/SYSTEMS.md:263-268`); actual loot tables or
loot resolution beyond the `CombatResult` loot-seed contract; any change to
`Hero.to_dict`/`from_dict`, `GameSession.to_dict`/`from_dict`, `SaveService`, or the save file
format/version — HP and wave state are in-memory expedition state only; a `CombatState` or any
fourth autoload; treating provisional recommended-power figures as final balance
(`docs/SYSTEMS.md:270-273`).

---

## P2-03d — Per-wave damage model, a zone must be clearable      [DONE]

Landed in `28115f5`.

Shipped from a backlog row rather than an expanded ticket body — the defect was already stated
precisely enough to act on, and the design work it needed went to `game-designer` rather than to
a `tech-lead` ticket. Recorded here so the Completed table's promise holds.

### Objective
Make `OUTCOME_COMPLETED` reachable. `SYSTEMS.md` specified that quick-resolve "compares
statistically" and nothing more, so the damage rule shipped with `P2-03b` was an implementing
worker's invention: `damage = max_hp * enemy_power / team_power`, charged against **max** HP
every wave regardless of current HP. Verdant's five trash waves cost `2.97×` a hero's max HP, so
win, loss, retreat and death were each individually reachable while a zone clear was not, at any
rank. That blocked the Phase 2 exit question — there was no success path to feel.

### What landed
`damage_fraction = clamp(BALANCE.wave_damage_coefficient * r^3, 0.0, 1.0)`, `r` being the same
`effective_enemy_power / team_power` the win check already computes. One new authored constant
(`wave_damage_coefficient = 0.35`); no zone `.tres` value changed. The full rule, its arithmetic
verification, and the rejected alternatives are in `docs/SYSTEMS.md` § Wave damage — that is the
spec, this is only the record that it shipped.

### Findings this produced
- **Retreat is unreachable in the only configuration the game can build today** (solo, Verdant,
  any rank F–SSS — swept exhaustively, zero crossings of the 25% line). A lost wave is an instant
  wipe, so HP erodes only on *wins*, and won-wave damage must stay cheap for the clear to exist:
  one pathway serving two competing jobs. Neither the coefficient nor the threshold fixes it
  without re-breaking the clear; both were tried with numbers. `KNOWN_ISSUES.md`, and
  `SYSTEMS.md` § Retreat threshold names the win/loss branch as the more plausible target.
- **Ashfall and Sundered reference teams still cannot survive their own trash** even winning
  every roll — Ashfall dies on trash wave 6, Sundered retreats on wave 5. One constant tuned
  against Verdant does not stretch to zones designed to demand gear. Sharpens the existing
  recommended-power PROVISIONAL marker rather than resolving it.
- The clamp is provably unreachable at the authored coefficient (a win requires `randf() > r`, so
  `r < 1`, so `0.35 * r^3 < 0.35`). Kept to match the spec, recorded as genuinely untested — the
  green suite does not cover that branch.

### Verification
Five mutations against the formula (exponent swap, coefficient hardcode, damage-never-applied,
full linear revert, carry-forward removal) — all five caught. Three coverage gaps found by the
verifier pass and closed: the carry-forward test's discrimination margin went from `~2.3×`
`ERROR_MARGIN` to `~500,000×`; the authored coefficient is now pinned to a literal alongside a
hardcoded end-to-end Verdant clear figure (`84.69183285531011` HP) rather than only to values
re-derived from the same resource production reads; team-size parity now asserts HP-after
equality instead of only matching win/loss booleans.

### Files changed
`balance_table.gd`, `balance.tres`, `combat/quick_resolve.gd`, `tests/unit/test_expedition.gd`,
`docs/SYSTEMS.md`, `docs/KNOWN_ISSUES.md`

### Non-goals
The win/loss check itself (instant-wipe-on-loss is deliberate and out of bounds here); the combat
seam signature; `zones/wave.gd`'s ramp interpolation or any `zones/defs/*.tres` value; the 25%
retreat threshold; squad select (`P2-03c`); the XP curve that retires the rank-cap level baseline
(`P2-04a`).

---

## P2-03e — Win/loss branch design ruling, what a lost wave means   [DONE]

Design pass, `game-designer`. Shipped from a backlog row rather than an expanded ticket — like
`P2-03d`, the body is written at close rather than moved verbatim, so this does not read as a
missing record.

### Objective
Rule on what a lost wave means, so `P2-03f` can have checkable acceptance criteria. Two questions:
does a loss stay a full wipe or deal graduated damage, and if graduated, what ends the expedition
— the run continues, a forced retreat, or a distinct new outcome (`Expedition`'s `OUTCOME_*`
constants named none of these).

### The ruling
Graduated damage, same cubic-in-`r` shape as the win rule, at coefficient `1.0`:

```
damage_fraction_loss = clamp(1.0 * r^3, 0.0, 1.0)
```

`1.0` is the minimum coefficient rather than a felt number: it is the smallest value for which a
mathematically unwinnable wave (`r >= 1`) still clamps to 100% damage, so a guaranteed loss can
still kill a full-health team. At `L=0.7` F Cleric's Verdant boss deals `83.09%` — a full-health
team walks away from a "guaranteed" loss, which empties the phrase.

**No fifth outcome.** `Expedition.resolve()` already re-derives death and retreat from cumulative
`current_hp` after every wave and has never branched on whether the wave was won, so the existing
four states cover it and `hub/expedition/expedition.gd` needs no edit. `QuickResolve` still takes
no current-HP input; the combat seam does not move.

### Acceptance criteria
- Recorded in `SYSTEMS.md` at § Wave damage's rigor — formula, why this shape, named rejections.
- Numbers recomputed from real `.tres`/`.gd` data, not asserted (Codex thread
  `019fce28-66c9-7412-a07c-45327b3f2d9c`).
- Verdant stays clearable with the `P2-03d` margins intact, and team-size parity holds exactly.
- The § Retreat threshold PROVISIONAL marker is resolved or honestly re-marked.

### Findings
- **`OUTCOME_RETREATED` becomes reachable in a buildable-today configuration for the first time —
  but only at F rank.** All five F archetypes reach it via some real win/loss sequence (F Knight
  `LWWWL` → 24.78% party HP); none of the 35 D-through-SSS combinations do, at any coefficient
  tested (`0.7`, `1.0`, `1.5`). Not a shortfall of the constant: it is the same rank ceiling the
  win branch already has, since Verdant's `recommended_power` is fixed at 900 while hero power
  grows `×1.35` per rank. A loss rule tied to the same `r` inherits it and could only escape by
  decoupling from `r`, which the combat seam forbids.
- **A new death route, not a new state.** A chain of unlucky non-guaranteed losses (every `r < 1`)
  can now drive `current_hp` to `0` without ever hitting a guaranteed-loss wave.
  `OUTCOME_DEFEATED` already covers it.
- Losing a wave does not stop progress — the run advances to the next wave, exactly as after a
  win. That is the ruling's answer to "what ends the expedition": nothing new does; death and the
  existing retreat threshold do, as they already did.

### Rejections recorded
`L=0.7` (breaks guaranteed-loss-is-fatal, and reaches fewer combos); `L=1.5` (identical `5/40`
reachability to `1.0`, so the extra severity on near-miss losses buys nothing); a non-cubic or
RNG-keyed loss curve (same seam and ramp-shape reasoning § Wave damage already gave); leaving the
instant wipe for `P2-03c` to mask (masks the symptom, leaves the cause).

### Files changed
`docs/SYSTEMS.md` — new § Lost-wave damage, and § Retreat threshold rewritten from "dormant" to
resolved, its closing PROVISIONAL replaced with a narrower one on the unplayed constant.

### Non-goals
The win check itself; the combat seam signature; the 25% threshold; `wave_damage_coefficient`;
any code (this pass wrote none).

---

## P2-03f — A lost wave hurts instead of wiping the team          [DONE]

### Objective
Losing a wave costs the party HP proportional to how outmatched it was, instead of killing
everyone outright. A player can lose a fight in Verdant Outskirts, live, and either push on or
be pulled out by the retreat threshold — which fires for the first time in a configuration the
game can actually build.

### Existing architecture
- `combat/quick_resolve.gd:35-39` is the whole of the loss branch today: `hp_after = 0.0` for
  every hero and every hero appended to `result.dead_heroes`, regardless of `r`.
- `r = effective_enemy_power / team_power` is computed at `combat/quick_resolve.gd:41` — *below*
  the loss branch's early return, so the loss path cannot see it — and drives the *won*-wave
  damage rule (`clamp(BALANCE.wave_damage_coefficient * r * r * r, 0.0, 1.0)`, line 42). Hoisting
  that one line above the branch is most of the change. The loss rule is the same expression with
  a different coefficient — deliberately, so both combat implementations derive it from
  `(team, wave)` alone.
- `Expedition.resolve()` (`hub/expedition/expedition.gd:31-57`) has **never branched on whether a
  wave was won**. It reads `result.maximum_hp` / `result.hp_after`, subtracts the delta from
  carried `current_hp`, then checks death (`<= 0.0`) and retreat (party fraction `<= 0.25`, trash
  waves only). It ignores `result.dead_heroes` and `result.survivors` entirely.
- `BalanceTable` already carries `wave_damage_coefficient`; the new constant follows that pattern.
- `tests/unit/test_expedition.gd` uses `result.dead_heroes.is_empty()` as a "did we win" proxy in
  `test_team_size_scaling_keeps_solo_and_full_team_rolls_in_parity`. That proxy is only valid
  while loss implies death.

### Acceptance criteria
- `combat/quick_resolve.gd`'s loss branch sets `hp_after = maximum_hp * (1.0 -
  clamp(BALANCE.wave_loss_damage_coefficient * r * r * r, 0.0, 1.0))`, with the same `r` the win
  check used — not re-derived.
- `wave_loss_damage_coefficient: float = 1.0` exists on `BalanceTable` and is authored in
  `balance.tres`. No zone `.tres` value changes.
- On a lost wave, `CombatResult` bookkeeping matches the win path's shape: a hero whose
  `hp_after > 0.0` goes in `survivors`, not `dead_heroes`. A hero at `0.0` goes in `dead_heroes`.
- **`r >= 1` still wipes a full-health team.** F Cleric vs. the Verdant boss (`r = 198/187 =
  1.058824`) clamps to `1.0` damage and dies from full HP. This is the property the coefficient
  was chosen for; a test pins it.
- **`OUTCOME_RETREATED` is reachable and proven by a test**, not by argument. `SYSTEMS.md`
  § Lost-wave damage gives concrete sequences: F Knight `LWWWL` ends at `24.78%` party HP, F Mage
  `LLLL` at `21.36%`. Drive one deterministically (seed the RNG or inject the sequence) and assert
  the outcome.
- **The Verdant clear is unchanged.** The win-only figures in `SYSTEMS.md` still hold — 5-hero
  reference team at `27.51%` remaining, F Mage solo at `25.07%`. The existing end-to-end clear
  assertion (`84.69183285531011` HP, pinned by `P2-03d`) must still pass untouched.
- **Team-size parity still holds exactly**: solo and five-hero teams of one archetype produce
  identical `r`, hence identical `damage_fraction` on the loss path too. Assert HP-after equality,
  not just matching win/loss booleans.
- `test_team_size_scaling_keeps_solo_and_full_team_rolls_in_parity`'s win/loss proxy is replaced
  with one that does not assume loss implies death.
- BUILT green (import gate exit 0, zero errors and zero warnings) and the full GUT suite green.
- Survives save and reload: an expedition that ends in `RETREATED` after a survived loss leaves
  the roster and hero HP correct across a real save/reload cycle.

### Files allowed to change
`combat/quick_resolve.gd`, `balance_table.gd`, `balance.tres`, `tests/unit/test_expedition.gd`.

### Non-goals
- **The win check itself.** `team_power * randf() > effective_enemy_power` is settled; this ticket
  changes what a loss *costs*, not what decides one.
- **A fifth `OUTCOME_*` constant.** The ruling explicitly does not need one — `Expedition`'s
  existing death and retreat checks already cover the graduated-loss case, and
  `hub/expedition/expedition.gd` should need no edit at all. If implementation shows otherwise,
  that is a finding to report, not a change to make silently.
- **The combat seam signature.** `resolve(team: Array[Hero], wave: Wave) -> CombatResult` takes no
  current-HP input (`DECISIONS.md`, `CLAUDE.md` risky boundary 4). A design that needs current HP
  inside `QuickResolve` is a `godot-architect` call.
- **Permadeath's single call site.** `GameSession.kill_hero()` at
  `hub/expedition/expedition.gd:51` stays the only one (ARCHITECTURE rule 8).
- The 25% retreat threshold, `wave_damage_coefficient`'s `0.35`, the zone ramps, squad select
  (`P2-03c`), and the Ashfall/Sundered attrition finding — all out of bounds.

### Findings
- **`OUTCOME_RETREATED` fires for the first time in a buildable configuration**, proven by a test
  rather than by argument: `test_graduated_loss_sequence_can_reach_retreat` searches for a seed
  that forces F Knight's `LWWWL` sequence, then asserts the outcome, that the hero survived with
  HP above zero and at or below the 25% line, and that permadeath did not fire.
- **`Expedition` needed no edit at all**, as the ruling predicted. Its death and retreat checks
  already ran identically regardless of which branch produced the HP delta.
- **`CombatResult.dead_heroes`/`survivors` have no reader outside `combat/` and the tests.**
  `Expedition.resolve()` re-derives death from cumulative `current_hp` and ignores both fields.
  They can therefore disagree with the expedition's own verdict without anything noticing today —
  fine while one implementation of the seam exists, worth remembering when the arena adds a second.
- **The "survives save and reload" criterion was satisfied by inspection, not by a disk round-trip.**
  `Hero.to_dict()`/`GameSession.to_dict()` persist only `{name, rank, def_id}`; `current_hp` is
  transient inside `Expedition` per the No-CombatState ADR and reaches `SaveService` nowhere
  (grepped repo-wide, both by the implementer and independently by the verifier). The criterion
  reduces to "the hero stays in the roster after `RETREATED`," which the retreat test asserts in
  memory. Recorded because the acceptance line as worded says "a real save/reload cycle" and one
  was not run.
- **`_seed_for_rolls_above` returns `-1` on an unfindable sequence and `fail_test()` does not
  abort GUT.** No false-green risk — the test still fails — but a caller would then run with
  `seed(-1)` and produce confusing cascading assertions. Diagnostic clarity only; not exercised.

### Verification
Five mutations, all caught: coefficient `1.0` → `0.9` in `balance.tres`; `r * r * r` → `r * r` on
the loss path only; clamp upper bound removed; loss branch classifying everyone as `survivors`
regardless of `hp_after`; full revert to the instant wipe. The arithmetic was re-derived
independently of `SYSTEMS.md`'s tables — F Cleric's `r = 198/187 = 1.058824` clamping to `1.0`,
and F Knight's `LWWWL` walked checkpoint by checkpoint (92.35% → 87.72% → 80.38% → 69.41% →
24.78%) confirming no *earlier* checkpoint crosses the line, which would have made the retreat
test pass for the wrong reason. `P2-03d`'s pinned end-to-end Verdant clear (`84.69183285531011`
HP) passes unedited, so the win path is untouched. Codex threads
`019fce34-6afa-7660-b813-f1ceeaf48112` (implementation), `019fce48-0c98-72b3-8102-8003d2ba66ea`
(adversarial review).

### Files changed
`combat/quick_resolve.gd`, `balance_table.gd`, `balance.tres`, `tests/unit/test_expedition.gd`,
and afterwards `docs/SYSTEMS.md`, `docs/KNOWN_ISSUES.md` (both described the wipe branch as
current).

---

## P2-03c — Expedition setup: multi-hero squad + zone select, with authored zone unlocks   [DONE]

### Objective
From the hub, pick 1-5 heroes (not always exactly one) and pick a zone (not always Verdant
Outskirts) before sending an expedition. Ashfall Reaches and Sundered Vault stay unselectable
until their prerequisite zone has been cleared at least once.

### Existing architecture
- `hub/hub.gd:4,6,44-64` — `EXPEDITION_ZONE` is hardcoded to `verdant_outskirts.tres`. `%RosterList`
  is a single-select `ItemList`; `_on_expedition_pressed()` reads `get_selected_items()[0]` into a
  one-hero `Array[Hero]`.
- `hub/expedition/expedition.gd:18` — `assert(team.size() == 1)` is the only place team size is
  constrained. `combat/quick_resolve.gd:31` already computes `effective_enemy_power = wave.enemy_power
  * (team.size() / 5.0)`, so 2-5 hero teams are numerically supported today — this ticket is the UI
  that assembles one, not a balance change, and nothing drives `Expedition.resolve()` with more than
  one hero today (several tests build 5-hero teams directly against `QuickResolve`, not `Expedition`).
- `zones/zone_definition.gd:1-11` and `zones/defs/*.tres` — three authored zones. `unlock_condition`
  is free text ("Available from start" / "Clear Verdant Outskirts" / "Clear Ashfall Reaches"),
  read by nothing; there is no `zone_id` field and no unlock *state* persisted anywhere in the repo.
- `systems/game_session.gd:8-43` — `GameSession` is the persistent-profile autoload
  (`ARCHITECTURE.md:50`). It owns one persisted array (`roster`) with mutators (`add_hero`,
  `kill_hero`) that each call `roster_changed.emit()`, which `SaveService.save()` is connected to
  (`_ready()`, line 16). A second persisted set follows this exact shape.
- `docs/SYSTEMS.md:672-676` — the unlock order is linear: Verdant (from start) → Ashfall (needs
  Verdant cleared) → Sundered (needs Ashfall cleared). `SYSTEMS.md:661-663` already names this
  ticket as the one that ships the Ashfall/Sundered unlock.
- `hub/expedition/expedition.gd:49-52` — `Expedition` is already the sole writer of permadeath
  into `GameSession` (`ARCHITECTURE.md` rule 8); it is the natural place to also write a zone-clear
  flag on `OUTCOME_COMPLETED`, not `hub.gd`.

### Acceptance criteria
- `%RosterList` allows selecting 1-5 heroes (`select_mode = SELECT_MULTI`). A new zone selector
  (e.g. `%ZoneOption`, an `OptionButton`) is added to `hub.tscn` listing all three zones; Ashfall
  and Sundered are disabled/unselectable until their prerequisite zone has produced
  `OUTCOME_COMPLETED` at least once for the current save.
- Pressing Expedition with 0 heroes selected refuses with a status message and does not call
  `Expedition.resolve()` (same shape as today's "Select a hero first."). With more than 5 selected,
  refuses with a status message naming the 5-hero cap.
- `expedition.gd`'s `assert(team.size() == 1)` becomes `assert(team.size() >= 1 and team.size() <=
  5)`.
- `ZoneDefinition` gains a `zone_id: StringName` export, authored in each `.tres`
  (`verdant_outskirts`, `ashfall_reaches`, `sundered_vault`). `GameSession` gains a persisted
  cleared-zone set and a mutator (mirroring `add_hero`/`kill_hero`'s shape) that `Expedition` calls
  on `OUTCOME_COMPLETED`.
- **Survives save and reload**: `GameSession.to_dict()` → `from_dict()` round-trips the
  cleared-zone set in memory (matching this repo's existing test pattern — no `SaveService`/disk
  I/O required, see `test_expedition.gd`'s `before_each`). A fresh save (empty roster, nothing
  cleared) has only Verdant selectable.
- `tests/unit/test_expedition.gd` gets at least one test that drives `Expedition.resolve()`
  directly with a 2-5 hero `Array[Hero]` (not just `QuickResolve`) through to `OUTCOME_COMPLETED`,
  proving the relaxed assert and the win path both work multi-hero end to end through `Expedition`.
- A new or extended test proves the `GameSession` cleared-zone round trip and that clearing Verdant
  unlocks Ashfall (and not Sundered) while Sundered stays locked until Ashfall is also cleared.
- Existing tests still pass. BUILT green (import gate exit 0, zero errors/warnings) and the full
  GUT suite green.

### Files allowed to change
`hub/hub.gd`, `hub/hub.tscn`, `hub/expedition/expedition.gd`, `zones/zone_definition.gd`,
`zones/defs/verdant_outskirts.tres`, `zones/defs/ashfall_reaches.tres`,
`zones/defs/sundered_vault.tres`, `systems/game_session.gd`, `tests/unit/test_expedition.gd`
(plus a new `tests/unit/test_game_session.gd` if the implementer prefers a separate file over
extending `test_expedition.gd`).

### Non-goals
- Loot (`P2-04`), the equip UI (`P2-05a`), per-hero HP display, retreat-threshold
  configurability, and any change to `quick_resolve.gd`'s combat formulas — all out of bounds.
- Enemy species/bestiary authoring — `SYSTEMS.md:678-683` already defers this.
- No new autoload and no `SceneRouter`-routed expedition-setup scene; squad/zone select stays on
  the existing hub scene (this is a scene ↔ script seam change per `CLAUDE.md` risky boundary 2 —
  a new `%ZoneOption` unique-name node and a `select_mode` change on `%RosterList` — a `verifier`
  pass is required after implementation, on top of the import gate).
- No retroactive unlock for saves written before this ticket ships — an old save simply starts
  with only Verdant unlocked, same as a brand-new one.
- No UI polish beyond function: a working `OptionButton` and multi-select `ItemList` are enough;
  no confirmation dialog, no drag-drop squad builder, no per-zone artwork.
- Parsing the authored `unlock_condition` free-text strings — the new `zone_id` field plus a
  linear Verdant→Ashfall→Sundered check in code is the mechanism; `unlock_condition` remains
  display-only flavor text.

### Findings
- **The zone `OptionButton` was matched to zones by widget position**, and the verifier proved it
  by swapping the Ashfall and Sundered items in `hub.tscn` while leaving `EXPEDITION_ZONES`
  untouched: the full suite stayed green and the import gate stayed clean. An editor reorder or an
  inserted item would have sent a team to the wrong zone — a player picking Ashfall (RP 4,800)
  getting Sundered Vault (RP 11,500), with permadeath on. Fixed by deleting the coupling rather
  than guarding it: the scene authors no zone items at all, `hub.gd` populates the button from
  `EXPEDITION_ZONES` and carries each `ZoneDefinition` as item metadata, and zone order has one
  source. Reverting to positional lookup now fails two tests.
- **`_refresh_roster()` restored selection by stale list index.** Select heroes 2 and 4 of 5, lose
  the expedition so both die, and the reselect landed on a survivor who never fought — the next
  expedition would depart with a team the player never picked. Older than this ticket, but this
  ticket rewrote that loop and multi-select turns one wrong hero into several, so it shipped here.
  Now reselects by hero identity.
- **The scene seam had only reject-path coverage.** The single button-press test selected 6 heroes
  against the 5-cap, and its `assert_string_contains(status.text, "5")` would have passed on a
  success message too. Green path added with an exact-match assertion.
- **`mark_zone_cleared()` emits `roster_changed` though the roster did not change.** Confirmed to
  reach `SaveService.save()` correctly, so a cleared zone does persist, but it also triggers a
  needless roster rebuild on every clear and the signal name no longer describes what happened.
  Deliberately left alone — a second signal is a bigger change than the problem, and this should
  be a considered call rather than a drive-by.
- **Save round-trip is in-memory only.** `to_dict()`/`from_dict()` are exercised directly, matching
  this repo's existing pattern; no disk cycle through `SaveService` was driven. `P2-08` owns that.

### Verification
Two implementer rounds. The first came back green on both gates and the verifier failed it on the
two defects above, each reproduced with a live mutation rather than argued. After the rework, both
gates re-run at director level (import gate exit 0 with zero errors and warnings; GUT 21 tests,
240 asserts, exit 0) plus an independent mutation: reverting the zone lookup to
`EXPEDITION_ZONES[_zone_option.selected]` fails 2 tests and exits 1, restored green afterwards.
Codex threads `019fce59-f95a-70d2-93ed-aefe1561db6b` (implementation, both rounds),
`019fce6f-af15-7752-9cd5-28034500b8bb` (adversarial review).

### Files changed
`hub/hub.gd`, `hub/hub.tscn`, `hub/expedition/expedition.gd`, `zones/zone_definition.gd`,
`zones/defs/verdant_outskirts.tres`, `zones/defs/ashfall_reaches.tres`,
`zones/defs/sundered_vault.tres`, `systems/game_session.gd`, `tests/unit/test_expedition.gd`

---

## P2-04c — Runtime `Item` type + persistent inventory              [DONE]

### Objective
An item instance can exist, be held in the player's persistent inventory, and survive a real
save/reload cycle. No UI, no loot roll, no equipping onto a `Hero` — this ticket makes the type
and its storage real so the tickets that need it (`P2-04d` loot, `P2-05a` equip) have something to
build on, the same non-player-facing role `P2-01a`/`P2-03a` played for their sequences.

### Existing architecture
- `Hero` (`heroes/hero.gd`) is the existing pattern for runtime state pointing at a shared
  Definition by `def_id`: a `DEF_PATH_TEMPLATE` plus `definition_for()` that `push_error`s and
  returns `null` on a bad id rather than silently defaulting — match this shape, don't invent a
  second lookup convention.
- `EquipmentDefinition` is the shared per-slot template — 10 `.tres` files under
  `equipment/defs/`, one per `Slot` enum value, filenames matching the enum names exactly. That
  1:1 naming is the same shape `Hero.DEF_PATH_TEMPLATE` already relies on.
- `docs/ARCHITECTURE.md:50`'s autoload table already scopes `GameSession` to own "roster,
  inventory, buildings, caches, currencies" — `inventory` is not an open boundary question.
- `combat/combat_result.gd:8`'s `loot_seed` is already wired but has no consumer — not read here;
  that's `P2-04d`.

### Acceptance criteria
- `equipment/item.gd` defines `Item` (`RefCounted`) with `def_id: StringName` and `rank: int`.
- A bad or unresolvable `def_id` fails loudly (`push_error`), never silently defaults.
- `GameSession.inventory: Array[Item]` exists; `to_dict()`/`from_dict()` include it.
- Inventory is mutated through a method that emits `roster_changed` — that signal is the only
  thing wired to `SaveService.save`, so appending to the array directly persists nothing.
- **Survives save and reload** through a real `SaveService.save()` → `load_game()` cycle.
- A save written before this ticket (no `"inventory"` key) loads without error, empty inventory.
- GUT coverage under `tests/unit/`; existing tests still pass; import gate clean.

### Findings
- **A pre-existing crash in `GameSession.from_dict`, inherited by copying `Hero`'s shape.**
  `Dictionary.get(key, default)` substitutes the default only when the key is *absent*, never
  when it is present holding `null`. So an explicit `"roster": null` in a hand-edited or corrupt
  save reached `for entry in ...` as Nil and threw
  `SCRIPT ERROR: Unable to iterate on object of type 'Nil'.` — engine-repro'd on `roster` and
  `cleared_zone_ids`, both of which predate this ticket. State was never corrupted (execution
  continues, the field ends up empty) but the logged error is exactly the class this repo's
  `BUILT` definition treats as gate-failing, and no gate could reach it because none feeds a
  malformed save. Fixed once in `_array_field()` for all three fields rather than three times
  inline. **The ticket's own "reuse `Hero`'s shape" instruction is what propagated it** — worth
  remembering the next time a ticket says to copy an existing pattern.
- **The turn clock does not exist, and an authored tunable hides that.**
  `reliquary_decay_turns_bonus` is a real value in `balance.tres` and `balance_table.gd`, so
  turn-denominated decay reads as settled — but nothing anywhere increments a turn, and there is
  no counter to bonus. The number is real and the thing it measures is not. `P2-04f` is where
  this bites.
- **Real-file save coverage is deliberately not in the GUT suite.** A GUT test driving
  `SaveService` would clobber the real `user://save.json` on every run — the GUT command does not
  redirect `%APPDATA%` the way `tests/import_gate.ps1` does (`KNOWN_ISSUES.md` § Environment).
  The on-disk path was proven by implementer and verifier with throwaway drivers; the committed
  GUT test covers the dict layer, where the key-symmetry failure would actually live, and the
  shared file plumbing stays covered for all fields by `tests/save_roundtrip_check.gd`.

### Verification
Import gate exit 0, zero errors and warnings. GUT 25 tests, 253 asserts, exit 0 — re-run at
director level after every edit, including the two post-implementation fixes. Verifier drove a
real `SaveService.save()` → raw-JSON inspection → `load_game()` cycle, plus typed-array poisoning
(string, number, nested array, explicit null), save→load→save byte-identity, and confirmed all 10
`equipment/defs/*.tres` filenames match `EquipmentDefinition.Slot` 1:1. Codex threads
`019fcfa1-ccc5-7821-9ea7-2988000eddeb` (implementation),
`019fcfad-fb09-7312-8ee4-2b90c707b0d1` (adversarial review).

### Files changed
`equipment/item.gd`, `equipment/item.gd.uid`, `systems/game_session.gd`,
`tests/unit/test_item.gd`, `tests/unit/test_item.gd.uid`

---
