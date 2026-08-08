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

## P2-04b — Equipment loot table: which item a cleared zone yields      [DONE]

Design pass, `game-designer`. A ruling recorded in `SYSTEMS.md`, not an implementer contract —
`P2-04d` is the ticket that consumes it. Same shape as `P2-03e`.

### Objective
Rule on what a cleared zone drops, so `P2-04d` can have checkable acceptance criteria. Today
`ZoneDefinition.loot_emphasis` is free prose — `"Gold, F–C parts, light Summon Stones"` — which
names a feel, not a distribution, and no code can act on it.

### The questions to rule on
1. **Does a clear drop equipment at all, or only sometimes?** A flat rate, or one that scales
   with the zone.
2. **Which slot.** Uniform across the ten `Slot` values, or weighted.
3. **What rank.** `Item.rank` exists and nothing sets it. Zones already carry an authored rank
   feel in `loot_emphasis` (`F–C` in Verdant, `C–A` in Ashfall, `S–SSS` in Sundered) — that
   band is the natural input, but it is prose today and must become a distribution.
4. **Where the numbers live.** `BalanceTable` is the settled shared-tunables container
   (`DECISIONS.md`, one `BalanceTable`), but a per-zone drop rate is arguably `ZoneDefinition`'s.
   Rule on which, because `P2-04d` has to read it from somewhere.

### Existing architecture
- `ZoneDefinition.loot_emphasis` (`zones/zone_definition.gd:11`) is a free-text `String`, authored
  in all three `zones/defs/*.tres`. Whatever this ticket rules replaces or supplements it; note
  `tests/zone_definition_check.gd` asserts its exact current text and will need updating by
  whoever implements, not by this ticket.
- `CombatResult.loot_seed` (`combat/combat_result.gd:8`) is already set on every resolve
  (`combat/quick_resolve.gd:33`) and has **no consumer**. It exists precisely so a drop roll can
  be deterministic per expedition — rule on whether the drop is seeded from it.
- `Item` (`equipment/item.gd`) exists as of `P2-04c`: `def_id: StringName` + `rank: int`, and
  `def_id` resolves 1:1 to `equipment/defs/<slot>.tres`. A drop must be expressible as those two
  fields and nothing more — anything richer is a different ticket.
- `BalanceTable`'s rank table is the existing home for rank-indexed arrays; `stat_multipliers`
  and `summon_weights` are the precedent for a per-rank distribution's shape.
- `GameSession.mark_zone_cleared()` is where a clear is already recorded, and `add_item()` is
  the only mutator that persists inventory.

### Acceptance criteria
- Recorded in `SYSTEMS.md` as a formula or table with named rejections, the way § Wave damage
  and § Lost-wave damage were.
- Every number is either derived from something already in `SYSTEMS.md` or marked
  `⚠️ PROVISIONAL` with a real **Settled by** clause. Unfelt is fine and expected here; undefined
  is not.
- The ruling names which file each number lives in (`balance.tres` vs `ZoneDefinition`), so
  `P2-04d`'s "Files allowed to change" can be written without reopening the question.
- Arithmetic checked against the real `.tres` data, not asserted — the three authored zones and
  the ten authored slots.
- States whether the drop is seeded from `loot_seed` or rolled independently.

### Non-goals
No code. No `.tres` edits — `P2-04d` authors the fields once their shape is ruled. No stat
magnitude for equipment (what a rank-`N` item *does* is a separate gap, and neither this ticket
nor `P2-04d` needs it). No affixes, no Cores, no salvage rates, no `power_deficit_penalty` and no
turn clock — those belong to `P2-05`/`P2-04f` and are tracked there.

### Findings
The ruling is `SYSTEMS.md` § Loot table. All four questions answered, six rejections recorded.

**No new `BalanceTable` field.** The rank curve is `summon_weights` reused verbatim, sliced to a
per-zone band and renormalized; slot uniformity and the guaranteed drop are formula-shape, not
magnitudes. The only new authored data anywhere is two `int` fields on `ZoneDefinition`
(`loot_rank_min`/`loot_rank_max`), which is `P2-04d`'s to add.

**`loot_emphasis` is supplemented, not replaced** — it stays as zone-select display copy, and the
bands are a checked transcription of it (`F–C` → `0..2`, `C–A` → `2..4`, `S–SSS` → `5..7`). So
`tests/zone_definition_check.gd`'s exact-text assertion needs no change, contrary to what this
ticket's own "Existing architecture" note anticipated.

**The Summoning precedent is close but not identical.** The Summoning Circle scales the A–SSS
block and renormalizes all eight weights; the loot band *drops* out-of-band ranks entirely. Same
array, same renormalize step, different operation — the doc says so explicitly, because reading
it as "the same slice" sends the next implementer looking for a slice that isn't there.

**Left for `P2-04d`:** the RNG call order. Slot and rank are independent, so the ruling doesn't
order them — but code needs a fixed order for the `loot_seed` to reproduce. Pick one; it is not
a design question.

### Files changed
`docs/SYSTEMS.md`

---

## P2-04d — Expedition clears can drop a real item into inventory      [DONE]

### Objective
Clearing a zone drops exactly one `Item` into `GameSession.inventory`, and the hub says which
one. First player-visible ticket in the `P2-04` group.

### Existing architecture
- **The rule is already written.** `SYSTEMS.md` § Loot table is `P2-04b`'s complete ruling:
  one guaranteed item per `OUTCOME_COMPLETED`, slot uniform over the ten `EquipmentDefinition.Slot`
  values, rank drawn from `BALANCE.summon_weights` **sliced to the zone's band and renormalized**,
  seeded from the boss wave's `CombatResult.loot_seed`. Nothing here is a design call; deviating
  from that section is a rejection, not a judgment.
- `Item` (`equipment/item.gd`) is `def_id: StringName + rank: int`, with `definition_for()` doing
  the `res://equipment/defs/<def_id>.tres` lookup. `GameSession.add_item()` already appends and
  emits `roster_changed` (which saves).
- `Expedition.resolve()` (`hub/expedition/expedition.gd:32-59`) loops `trash_wave_count + 1` waves;
  the last iteration is the boss. `result` is block-scoped to the loop body, so the boss wave's
  `loot_seed` has to be hoisted to survive past it. `mark_zone_cleared()` fires immediately after.
- `def_id` **is** the slot: each `Slot` has exactly one authored `.tres`, named for it
  (`main_hand` → `equipment/defs/main_hand.tres`). Rolling a slot is rolling a `def_id`.
- `Summon.rank_for_ticket(ticket, weights, total)` (`hub/summon/summon.gd:27`) already maps a
  weighted ticket to a rank index, with the guards. Reuse it; do not write a second cumulative walk.

### Implementation decisions (fixed here, not open)
- **Roll slot first, then rank**, from one `RandomNumberGenerator` seeded with the boss
  `loot_seed`. The ruling left the order open only because the two are independent — it still has
  to be pinned for `loot_seed` to reproduce a drop. Slot first. Comment it.
- The roll is a **static pure function** `Expedition.roll_loot(zone, balance, loot_seed) -> Item`,
  not a new file — `Summon.roll()`'s shape. Band slicing is a masked copy of `summon_weights`
  (out-of-band entries zeroed) handed to `Summon.rank_for_ticket`; that renormalizes implicitly.
- The ten slots come from `EquipmentDefinition.Slot.keys()`, lowercased — not a hardcoded list of
  ten strings alongside the enum that already holds them.
- `roll_loot` + `GameSession.add_item()` are called from `resolve()` at the `mark_zone_cleared()`
  call site. The dropped `Item` is also held on the instance (`var loot: Item = null`) so the hub
  can name it; that is transient per-run state, same as `waves_resolved`.

### Acceptance criteria
- Verdant/Ashfall/Sundered carry `loot_rank_min`/`loot_rank_max` of `0/2`, `2/4`, `5/7`.
- A completed expedition adds exactly one `Item` to `GameSession.inventory`; `RETREATED`,
  `DEFEATED` and `INVALID_TEAM` add none.
- The same `loot_seed` and zone produce the same `def_id` and `rank` every time.
- Every rank the roll can return for a zone is inside that zone's band, and over many seeds all
  three in-band ranks and all ten slots are reachable.
- All ten rolled `def_id`s resolve to a real `EquipmentDefinition` — no `push_error`.
- The hub status line after a clear names the item's rank and display name.
- **Survives save and reload**: the dropped item is in `inventory` after a
  `to_dict()` → `from_dict()` round-trip.
- Existing tests still pass. `tests/unit/test_expedition.gd:138` asserts the exact cleared-status
  text and will need the new suffix.

### Files allowed to change
`zones/zone_definition.gd`, `zones/defs/*.tres` (all three), `hub/expedition/expedition.gd`,
`hub/hub.gd`, `equipment/item.gd` (a `rank_label(balance)` mirroring `Hero.rank_label`),
`tests/unit/test_loot.gd` (new), `tests/unit/test_expedition.gd`.

### Non-goals
No `balance.tres` field (the ruling is explicit — the rank curve is `summon_weights` reused). No
inventory UI, no equipping (`P2-05a`), no salvage (`P2-05`), no lost-gear cache (`P2-04e`). No
change to `loot_emphasis` or to `tests/zone_definition_check.gd`'s exact-text assertion — the band
supplements the prose. No second item, no drop-chance roll, no per-slot weighting: all three are
explicitly rejected in `SYSTEMS.md` § Loot table.

### Findings
**An `Item` had never reached disk before this ticket.** `P2-04c` proved the inventory round-trip
through `GameSession.to_dict()`/`from_dict()` in memory only, and `tests/save_roundtrip_check.gd`
covers heroes exclusively — so the JSON leg was untested for items. Driven by hand here against a
redirected `%APPDATA%`: a Sundered Vault drop at `loot_seed = 7` (`gloves`, rank 6) wrote to a real
`user://save.json` and came back with `rank` as `int`, not the `float` JSON numbers decode to.
`Item.from_dict`'s `int(data.get("rank", 0))` is what absorbs that, and it is now known to be
load-bearing rather than defensive.

**A `-s` script cannot statically reference `Expedition`.** With `--headless -s <script>`, the
script compiles *before* the autoloads register, so any dependency naming `GameSession` at compile
time fails with `Identifier not found: GameSession` — and the run then **hangs** rather than
exiting, because `quit()` is never reached. `expedition.gd` has named `GameSession` since `P2-03b`,
so this is not new, but it is why `tests/save_roundtrip_check.gd` reaches everything through
`root.get_node()` and `.call()` strings instead of static types. `load()` the script at runtime
inside the deferred callback and it compiles fine. Worth knowing before writing the next one-off
disk check; GUT is unaffected, since it loads test scripts after the autoloads exist.

**The retreat branch is not deterministic without seeding.** `test_loot.gd`'s retreat case wins its
wave ~5.7% of the time; three consecutive wins would have produced `COMPLETED` and a spurious
failure at roughly 1-in-5500 runs. Seeded, the way `test_expedition.gd` already does everywhere.

**`EquipmentDefinition.Slot.keys()` assigns cleanly to a `PackedStringArray`** and lowercases to
the ten authored `.tres` filenames exactly — so the slot list has one home (the ADR-settled enum)
rather than a parallel array of ten strings that can drift from it.

### Files changed
`zones/zone_definition.gd`, `zones/defs/verdant_outskirts.tres`, `zones/defs/ashfall_reaches.tres`,
`zones/defs/sundered_vault.tres`, `hub/expedition/expedition.gd`, `hub/hub.gd`,
`equipment/item.gd`, `tests/unit/test_loot.gd` (new), `tests/unit/test_expedition.gd`

---

## P2-05a — Equip UI for authored equipment                              [DONE]

### Objective
A player can equip an item out of `GameSession.inventory` onto a hero's matching slot through a
real (ugly) hub panel, unequip it back, and both the assignment and the inventory survive a real
save/reload cycle. Equipping changes nothing about combat — no formula exists yet for what a
rank-`N` item contributes to a hero's stats, and inventing one here would be authoring a balance
number as an implementer instead of shipping the ticket in front of it.

### Existing architecture
- `Item` (`equipment/item.gd:1-51`) is `def_id: StringName` + `rank: int`, `RefCounted`, with
  `to_dict`/`from_dict` and `static definition_for(def_id) -> EquipmentDefinition`, which
  `push_error`s and returns `null` on a bad id rather than silently defaulting
  (`CODING_RULES.md:121-122`). An item's slot is **not** stored on `Item` — it is always read off
  `Item.definition_for(item.def_id).slot`. Do not add a second place to store it.
- `EquipmentDefinition.Slot` (`equipment/equipment_definition.gd:4`) has 10 values, one authored
  `.tres` per slot under `equipment/defs/`.
- `GameSession` (`systems/game_session.gd:10-11`) owns `inventory: Array[Item]` — the single pool
  of *unequipped* items. `add_item()` (line 26) is the only mutator that emits `roster_changed`,
  which is what `SaveService.save` is wired to; appending to the array directly persists nothing.
  `kill_hero()` (line 41) is the sole permadeath call site (`ARCHITECTURE.md` r8) — this ticket
  adds one line of behavior to it, not a second removal path.
- `Hero` (`heroes/hero.gd:16-18, 84-101`) has three fields today and no equipment slot at all.
  `to_dict`/`from_dict` is the per-instance serialization pattern this ticket extends.
- `ARCHITECTURE.md:33-35` names "gear duplicated into a cache *and* left equipped" as exactly the
  rot the one-writer-one-path rule exists to prevent — the ownership rule below is required by
  that rule, not a style choice.
- `P2-04c`'s Findings (`TASKS-DONE.md`): `Dictionary.get(key, default)` only substitutes on a
  *missing* key, never an explicit `null` — `GameSession._array_field()` was written to guard
  exactly that for `roster`/`inventory`/`cleared_zone_ids`. `Hero.from_dict` predates that fix and
  has no array field yet; the new `equipped` field must use the same guard, not reintroduce the
  bug `P2-04c` just fixed.
- `hub/hub.tscn`/`hub/hub.gd`: `%RosterList` (multi-select, hero in metadata) is the only list
  that exists. There is no inventory or equip UI anywhere — a dropped item is currently named once
  in `%Status` and then invisible forever (`P2-04d`).

### Decision — where equipped gear lives
On `Hero`, not a `GameSession`-keyed mapping. `Hero` has no stable id field, and heroes are
rebuilt fresh from the save array on load — a `GameSession`-side `Dictionary` keyed by object
identity doesn't survive that round trip, and keying by roster index isn't stable either, since
`kill_hero()` removing an entry is the entire point of permadeath. Storing equip state on `Hero`
lets it travel through `to_dict`/`from_dict` and through death with the hero, with no separate
bookkeeping to keep in sync.

```gdscript
# heroes/hero.gd
var equipped: Dictionary[int, Item] = {}   # keyed by EquipmentDefinition.Slot; sparse — only filled slots present
```

Serialized as an array of entries, matching the shape `GameSession` already uses for
`cleared_zone_ids` rather than a raw `Dictionary` (JSON dictionary keys are strings only, and this
sidesteps that):

```gdscript
# Hero.to_dict() adds:
"equipped": [{"slot": slot, "item": equipped[slot].to_dict()} for each populated slot]
```

`from_dict` reads that array the same guarded way `_array_field()` does (missing or explicit-null
key → empty), validates `int(entry.get("slot", -1))` against the `Slot` range, and skips (with
`push_error`) rather than crashes on an out-of-range slot — same shape as the `def_id` guard
already in `Hero.from_dict`/`Item.from_dict`.

### Decision — ownership and displacement
An `Item` instance is in exactly one of `GameSession.inventory` or one hero's `equipped[slot]`,
never both, never on two heroes. This is enforced structurally, not by a runtime check: the equip
action only ever sources from `%InventoryList`, which lists `GameSession.inventory` and nothing
else — an item already equipped on some hero is not offered, so double-equipping isn't reachable
through the UI.

Equipping into a slot that already holds an item **displaces** it: remove the old item from
`hero.equipped[slot]` and append it to `GameSession.inventory`, then remove the new item from
`inventory` and write it into `hero.equipped[slot]`. Net effect is a swap — neither item is ever
duplicated or destroyed.

### Decision — a dead hero's equipped items
`P2-04e` (the lost-gear cache) has not landed. Until it does, `kill_hero()` moves every item out
of the dying hero's `equipped` dict into `GameSession.inventory` before erasing the hero from
`roster` — no item vanishes, and this ticket does not build any part of a cache. `P2-04e`'s job
when it lands is to replace that inventory-return with the cache hook, at the same call site.

### Decision — UI
Two plain `ItemList`s and two buttons, added to `hub/hub.tscn` under `UI/Root`, same register as
the existing `%RosterList`/`%ZoneOption` — no drag-and-drop, no icons, no tooltip:
- `%InventoryList` (single-select) — lists `GameSession.inventory`, label `rank_label + " " +
  definition.display_name`, item in metadata.
- `%EquippedList` (single-select) — lists the currently-selected hero's `equipped` slots, label
  `slot name + rank_label + display_name`; refreshes on `roster_changed` and on roster selection
  change.
- `Equip` / `Unequip` buttons, wired the same way `Summon`/`Expedition` are (`[connection]`
  blocks to `_on_equip_pressed`/`_on_unequip_pressed`).
- Equip requires exactly one hero selected in `%RosterList` and one item selected in
  `%InventoryList`; anything else is a `%Status` message, matching `_on_expedition_pressed`'s
  existing empty-selection guard style, not a crash.

### Acceptance criteria
- Equipping moves the selected item out of `GameSession.inventory` into the selected hero's
  `equipped[slot]` (slot read from `Item.definition_for(item.def_id).slot`); it disappears from
  `%InventoryList` and a row appears in `%EquippedList` for that hero.
- Equipping into an already-filled slot displaces the previous occupant back into
  `GameSession.inventory` (it reappears in `%InventoryList`) without duplicating or destroying
  either item.
- Unequipping returns the item to `GameSession.inventory` and clears that slot in `%EquippedList`.
- An `Item` is never simultaneously present in `GameSession.inventory` and in any hero's
  `equipped` — covered by a GUT test that equips an item and asserts
  `GameSession.inventory.has(item) == false`.
- Calling `GameSession.kill_hero()` on an equipped hero leaves every item it was wearing in
  `GameSession.inventory` afterward — none lost, none duplicated.
- **Survives save and reload:** equip an item, round-trip `GameSession.to_dict()` →
  `from_dict()` (or a real `SaveService.save()` → `load_game()` cycle), and the same hero has the
  same item in the same slot afterward. A save with no `"equipped"` key on a hero (pre-ticket
  save) loads with that hero's `equipped` empty, not an error.
- `Hero.compute_final_stats()` and `Hero.compute_team_power()` return identical output before and
  after equipping the same team — equipping causes no combat-number change as a side effect.
- Existing GUT suite (`tests/unit/`) still passes; import gate (`tests/import_gate.ps1`) is clean.

### Files allowed to change
`heroes/hero.gd`, `systems/game_session.gd`, `hub/hub.tscn`, `hub/hub.gd`, new file(s) under
`tests/unit/`.

### Non-goals
- Equipped items affecting `compute_final_stats`/`compute_team_power`/combat resolution. No
  number exists for what a rank-`N` item contributes — `SYSTEMS.md` has the slot→primary-stat
  table but no magnitude, and `P2-04b` explicitly left this out of scope. Authoring one is
  `game-designer`'s call, the same shape as `P2-03e`/`P2-04b`; wiring it in is a follow-up
  implementer ticket once that ruling exists.
- The lost-gear cache and recovery expedition (`P2-04e`/`P2-04f`) — neither exists yet; on death,
  equipped items return to `GameSession.inventory`, not a cache.
- Enhance levels, affixes, cores, salvage (`P2-05`) — untouched fields, no UI for them.
- A hero-id/UUID scheme, or any `GameSession`-side equipped-items mapping — rejected above in
  favor of storing equip state on `Hero`.
- A designed inventory screen, drag-and-drop, tooltips, icons, sorting, or filtering.
- Any change to `EquipmentDefinition` or the 10 authored `.tres` resources.

### Findings
**A plain GUT run overwrites the real `user://save.json`.** `KNOWN_ISSUES.md` claimed the opposite
— "confirmed this is read-only" — and that claim was reasoning about *startup* only. It is correct
that `GameSession._ready()` loads before connecting `roster_changed` to `SaveService.save`, so the
load's own emission never writes back. But the connection is live by the time any test runs, and
every test file's `before_each()` calls `GameSession.from_dict(...)`, whose emission does reach
`SaveService.save`. Measured here: a plain run left the real save at an empty roster. The note is
corrected. Redirect `%APPDATA%` when running GUT by hand — `tests/import_gate.ps1` already does, and
this is the reason it does.

**The in-memory round-trip test could not have caught the `slot` JSON type.** `to_dict()` straight
into `from_dict()` never touches JSON, so the field types it round-trips are the ones it was handed.
Driven to disk by hand: `"slot": 8.0` is what lands in the file, and `Hero.from_dict`'s
`elif raw_slot is float:` branch is what reads it back as an `int`. Same trap `P2-04d` recorded for
`Item.rank`, one field over — an in-memory round-trip test is not evidence about the save boundary,
and the acceptance criterion that permits one ("or a real `SaveService` cycle") is weaker than it
looks. Prefer the disk leg for the next serialized field.

**Equip state had nowhere durable to live except `Hero`.** A `GameSession`-side mapping was the
obvious shape and does not survive: `Hero` carries no stable id, heroes are rebuilt fresh from the
save array on load, so object identity is gone across a reload — and a roster-index key is not
stable either, because `kill_hero()` removing an entry is the entire point of permadeath. This is
worth remembering before proposing any other per-hero side table.

**The one-item-one-owner invariant is enforced by the caller, not the API.** `equip_item()` is
public and reachable with an item from anywhere; called twice with the same item, it duplicates it
into both `inventory` and `equipped`. Nothing in the shipped UI can reach that, because the
inventory list is rebuilt from `GameSession.inventory` alone and never offers an equipped item. The
ticket chose that structurally rather than adding a runtime check; the constraint is now a comment
on the function, since the next caller is where it breaks.

**`kill_hero()` grew behavior instead of a sibling.** Returning a dead hero's gear to inventory
happens inside the sole permadeath call site, before `roster.erase()`. `P2-04e` replaces exactly
that line with the lost-gear cache hook — it does not add a second path to reconcile.

### Files changed
`heroes/hero.gd`, `systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`,
`tests/unit/test_equipment.gd` (new), `docs/KNOWN_ISSUES.md`

---

## P2-05b — What a rank-`N` item contributes to a hero's stat            [DONE]

Design pass, `game-designer`. A ruling recorded in `SYSTEMS.md`, not an implementer contract —
`P2-05c` is the ticket that consumes it. Same shape as `P2-04b`/`P2-03e`.

### Objective
Rule on what equipping a rank-`N` item actually does to a hero's stats, so `P2-05c` can have
checkable acceptance criteria. Today a player can equip a full ten slots and every number on the
screen is unchanged, because no ticket has ever authored a magnitude. `SYSTEMS.md` § Equipment
gives each slot a primary stat and Enhancement gives `+8%` per level — `+8%` of nothing.

### The questions to rule on
1. **How large is an item's primary stat at rank `N`, and through which channel?** The hero
   formula (`SYSTEMS.md:45-46`) already names two: `equip_flat`, added after `rank_mult`, and
   `equip_pct`, multiplied at the end. Both are named and neither has ever carried a value. Rule
   on which channel the primary stat uses and what the rank-`N` magnitude is. If both channels
   are kept, say what distinguishes them — an unused channel is worse than a deleted one.
2. **What do the two crit slots contribute?** `necklace` → `CRIT_RATE` and `ring` → `CRIT_DMG`
   are 2 of the 10 slots and cannot be skipped. They are the case the generic curve breaks:
   `SYSTEMS.md:26-31` already established that `rank_mult` must **not** apply to crit stats,
   because a 15% base at `×8.17` is 122.55% — a cap violation, and already 90.75% one rank
   earlier. Whatever this ticket rules for the other eight slots hits that same wall here. Also
   name the `CRIT_RATE` cap explicitly if the ruling depends on one; `SYSTEMS.md` implies a cap
   in that passage and states one nowhere.
3. **Where does the number live?** `BalanceTable` is the settled shared-tunables container
   (`DECISIONS.md`, one `BalanceTable`), and `stat_multipliers` is already a rank-indexed array of
   exactly the right shape — but it is the *hero* rank curve, so reusing it is a decision with a
   justification, not a default. The alternatives are a new rank-indexed field on `BalanceTable`
   or a per-slot magnitude on `EquipmentDefinition` (which today carries `slot`, `primary_stat`,
   `display_name` and no numbers at all). Rule on which, because `P2-05c`'s "Files allowed to
   change" cannot be written without it.
4. **How much of a geared hero's power is gear?** A hero wears ten items, so the per-item number
   is multiplied by ten before it reaches `hero_power`. State the intended gear share at a named
   checkpoint. Without it the magnitude is unanchored, and `P2-05c` has nothing to assert against
   beyond "the number went up."

### Existing architecture
- `Hero.compute_final_stats` (`heroes/hero.gd:42-66`) is `static`, takes hero + definition +
  balance + level, and applies `stat_multipliers[rank]` to HP/ATK/DEF/SPD only; `CRIT_RATE` and
  `CRIT_DMG` pass through as archetype constants. `compute_team_power` (line 69) sums
  `ATK + DEF + HP/10 + SPD` — note **crit contributes nothing to `hero_power`**, so a ruling that
  puts real value in the two jewelry slots makes `hero_power` an increasingly poor proxy for team
  strength. Say so if it does; `P2-05c` needs to know whether it is wiring one function or two.
- `Item` (`equipment/item.gd:10-11`) is `def_id: StringName` + `rank: int` and nothing else. Any
  ruling that needs a third field per item is a different ticket — say so rather than assuming it.
- `EquipmentDefinition` (`equipment/equipment_definition.gd`) is `slot` + `primary_stat` +
  `display_name`, one authored `.tres` per slot under `equipment/defs/`. `PrimaryStat` and
  `Hero`'s six `STAT_*` constants are the same six stats under two spellings.
- `Hero.equipped` (`heroes/hero.gd:19`) is `Dictionary[int, Item]` keyed by `Slot`, sparse,
  persisted, shipped in `P2-05a`. Every slot a hero has filled is already reachable.
- `BalanceTable` (`balance_table.gd`) holds eight rank-indexed arrays and thirteen scalars.
  `equipment_affix_counts` and `core_socket_counts` are authored there and have **no consumer** —
  affixes and Cores do not exist. Do not let the affix column pull this ruling into inventing one.
- The verified ungeared `hero_power` checkpoints (`SYSTEMS.md:91-103`) are the calibration
  reference: 1,046.5 / 4,803.2 / 11,453.1 for a five-hero team at F·10, B·40, S·60. The three
  zones' recommended power (900 / 4,800 / 11,500) is pinned against exactly those ungeared
  numbers, and `SYSTEMS.md:809` marks that PROVISIONAL. A gear magnitude changes what those
  figures mean — rule on whether recommended power moves, or explicitly leave it and say why.

### Acceptance criteria
- Recorded in `SYSTEMS.md` § Equipment as a formula or table with named rejections, the way
  § Wave damage, § Lost-wave damage and § Loot table were.
- All four questions above answered. Question 2 answered *separately* from question 1 if the
  general rule does not survive contact with the crit cap.
- Every number is either derived from something already in `SYSTEMS.md` or marked
  `⚠️ PROVISIONAL` with a real **Settled by** clause. Unfelt is expected here; undefined is not.
- Arithmetic checked against the real authored data — `balance.tres`, the five archetype stat
  lines, the ten `equipment/defs/*.tres` — not asserted. Show the ten-slot total at a checkpoint.
- Names which file each number lives in, so `P2-05c`'s scope can be written without reopening it.
- States the effect on the three recommended-power figures, or states that they hold and why.
- Says whether `compute_team_power` stays a usable proxy once the jewelry slots carry value.

### Non-goals
No code. No `.tres` edits — `P2-05c` authors the fields once their shape is ruled. No affixes and
no Cores, whatever `equipment_affix_counts`/`core_socket_counts` suggest. No enhancement levels:
`Item` has no enhance level and `P2-05` owns that system — note only that the base ruled here is
what `+8%` per level will later compound on. No salvage rates, no set bonuses, no per-archetype
gear preference, no drop-rate revisit (`P2-04b` settled that). No new stat.

### Findings
The ruling is `SYSTEMS.md` § Primary stat magnitude. All four questions answered, four rejections
recorded, the whole section marked PROVISIONAL on the target band rather than on the arithmetic.

**Question 2 did split from question 1, as the ticket anticipated — but not for the reason it
gave.** The ticket predicted the crit slots would break the general curve on the cap. They do not:
at `base_pct = 4%`, running crit through `equip_pct` reaches `15% × 1.3268 = 19.9%` at SSS, nowhere
near the `122%` violation `rank_mult` produced in § Ranks. The separation holds on legibility
instead — `equip_pct` is a relative modifier and `CRIT_RATE`/`CRIT_DMG` are already percentages, so
routing them through it is a percentage of a percentage. Same shape of problem, different severity,
same answer. Anyone reopening this should know the cap argument alone would not have forced it.

**Three new `BalanceTable` fields, and `equip_flat` survives.** `equip_pct_per_rank` and
`equip_crit_pct_per_rank` share `stat_multipliers`' eight ratios with their own scalars
(`0.04`, `0.015`) — deliberately independent arrays, so a hero-curve retune does not silently
reprice every item in the game. Plus `equip_crit_rate_cap = 0.75`, named because question 2
depends on a cap existing and `SYSTEMS.md` had only ever implied one. The formula's `equip_flat`
channel is *not* dead after all: the eight non-crit slots reject it, the two crit slots use it.

**Recommended power holds; two consequences flagged rather than fixed.** 900 / 4,800 / 11,500 were
already pinned to the ungeared baseline, so this quantifies the intended headroom instead of moving
the anchor (`+19.75%` geared at B, `+35.3%` at S; gear share `7.41% → 16.44% → 26.38% → 39.53%`
across F/B/S/SSS). Both flagged items are out of this ticket's scope and belong to `tech-lead`:
`compute_team_power` stays permanently blind to the necklace and ring, since crit is not in its
`ATK + DEF + HP/10 + SPD` formula — a hero in best-in-slot SSS jewelry reads identically to one with
both slots empty. And Sundered Vault's `130%`-of-RP boss, proven arithmetically unbeatable by an
ungeared S/60 team, becomes satisfiable by a fully-geared one (`r = 0.9609`) — the first number
behind the "gear is the intended headroom" reading.

**Corrected on director review.** The Enhancement headroom check labelled `×2.2` as the compounded
reading of `+8%`/level when it is the additive one (`1.08^15 = ×3.172`). Both are now stated —
full-Enhanced Rogue lands at `53.88%` compounded or `41.97%` additive — so the `75%` cap holds
either way and the ruling does not depend on which reading `P2-05` eventually picks. The
compounded case spends 21 of the 60 available points rather than 33; the margin is real, not
generous.

### Files changed
`docs/SYSTEMS.md`

---

## P2-05c — Equipped gear changes combat power                          [DONE]

Implementer ticket. `P2-05b` already ruled every number this needed — `SYSTEMS.md` § Primary stat
magnitude was the contract, and nothing here was a fresh design call.

### Objective
Equipping an item raises the hero's stats and the team's power. Before this, a player could fill
all ten slots and no number on any screen moved — `P2-05a` shipped assignment and persistence with
combat effect as an explicit non-goal. This closed that.

### Existing architecture
- `Hero.compute_final_stats` (`heroes/hero.gd:42`) is the single point where a hero's numbers are
  produced. `QuickResolve.resolve` (`combat/quick_resolve.gd:26`) and `compute_team_power` both go
  through it, and nothing re-derives stats anywhere else — so gear applied there reaches combat
  with no second call site to keep in sync.
- `hero.equipped` is `Dictionary[int, Item]` keyed by `EquipmentDefinition.Slot`, sparse, already
  persisted (`P2-05a`). The function already receives the `Hero`, so **no signature change was
  needed** on either static function; per-item lookup goes through `Item.definition_for()`.
- `EquipmentDefinition.PrimaryStat` (ordinals 0-5) and `Hero`'s six `STAT_*` `StringName`s are the
  same six stats under two spellings; the mapping is positional and needed no authored table.
- `tests/unit/test_equipment.gd:115` asserted both functions were byte-identical across an equip.
  That assertion was this ticket's target, not a constraint to preserve.

### Acceptance criteria
1. Three new `BalanceTable` fields, present in both `balance_table.gd` and `balance.tres`:
   `equip_pct_per_rank` `[0.04, 0.054, 0.0728, 0.0984, 0.1328, 0.1792, 0.242, 0.3268]`,
   `equip_crit_pct_per_rank` `[0.015, 0.02025, 0.0273, 0.0369, 0.0498, 0.0672, 0.09075, 0.12255]`,
   `equip_crit_rate_cap = 0.75`.
2. Non-crit slots sum into one per-stat `equip_pct`, applied as a single `* (1.0 + equip_pct)`
   after `rank_mult`. Worked example: `base_hp 100 / hp_growth 10`, rank `2`, level `5` → ungeared
   `HP = 273.0`; one rank-`4` head item → `309.2544`.
3. `necklace` adds `equip_crit_pct_per_rank[rank]` flat to `CRIT_RATE`, `ring` the same to
   `CRIT_DMG` — no `rank_mult`, no `equip_pct`.
4. `CRIT_RATE` clamped to `equip_crit_rate_cap`.
5. Fully same-rank-geared team power is exactly `(1.0 + 2.0 * equip_pct_per_rank[rank])` times the
   ungeared power.
6. `test_equipping_does_not_change_combat_stats_or_team_power` inverted, not deleted, and split.
7. Gear survives save and reload.
8. `tests/balance_table_check.gd` checks the new `.tres` values.
9. BUILT green and the full GUT suite passes.

### Non-goals
No `compute_team_power` formula change, no new field on `Item` or `EquipmentDefinition`, no
Enhancement/affixes/Cores, no UI change, no move of the recommended-power figures.

### Findings
**No signature change was needed, and the ticket's own framing was wrong about that.** The backlog
row predicted "the seam is an extra argument, not new state" — but `compute_final_stats` already
takes the `Hero`, and `Hero.equipped` has been on it since `P2-05a`. Gear needed nothing threaded
through; `Item.definition_for()` resolves each item's `EquipmentDefinition` at the point of use.
Every call site is untouched, `combat/` is untouched, and `QuickResolve` picked up geared numbers
for free because it already routed through this one function.

**The crit-blindness of `compute_team_power` is now an assertion, not a comment.**
`test_equipping_changes_hp_and_team_power_but_ring_is_crit_blind` equips a ring and asserts team
power does *not* move. `SYSTEMS.md` flagged this as a real gap for `tech-lead`; pinning it in a
test means the eventual fix has to delete an assertion deliberately rather than discover the
behavior as a bug.

**Gear routing is coupled to two enum orderings.** `equip_pct` is indexed by `PrimaryStat` ordinal
and `Hero.STAT_NAMES` mirrors it positionally, so reordering either enum silently routes gear to
the wrong stat with a green import gate. `tests/unit/test_equipment.gd` is the only thing that
would notice; a comment at `heroes/hero.gd:70` says so.

**The GUT command in `CLAUDE.md` was run with `APPDATA` redirected to a scratch path**, not
verbatim. `P2-05a` established that a plain GUT run overwrites the real `user://save.json`, and
`tests/import_gate.ps1` already does the same redirect for the same reason. The Codex worker
additionally reported the verbatim command crashing before test discovery on a `user://logs`
failure; that was not reproduced outside its sandbox and is recorded here as a worker observation,
not an environment fact.

**Verified by re-run, not by relay.** Import gate exit 0 with zero `SCRIPT ERROR`/`ERROR:`/
`WARNING` lines; GUT 40/40 tests, 9308 assertions, exit 0. Both re-run by the director after the
worker returned, and again after the review fix-up.

### Files changed
`balance_table.gd`, `balance.tres`, `heroes/hero.gd`, `tests/unit/test_equipment.gd`,
`tests/balance_table_check.gd`

---

## P2-04e — Lost-gear cache created on hero permadeath                   [DONE]

Route: **implementer, then verifier — mandatory, not optional.** This ticket changes the
signature of the sole permadeath call site (`ARCHITECTURE.md` r8) and adds a new persisted
field, both named as risky-boundary changes in `CLAUDE.md` (§ Permadeath, § Save round-trip).

### Objective
A hero's equipped gear survives their death instead of quietly reappearing in the shared
inventory. Before this, `kill_hero()` dumped every equipped item straight into
`GameSession.inventory` — `P2-05a`'s deliberate interim behavior, standing in for "gear is
recoverable" until something real existed to lose it into. This ticket replaced that dump
with a persisted `LostCache`, so the observable change is: **a dead hero's gear no longer
shows up in the equip screen's inventory list.** It is held instead, not deleted — the screen
to browse or reclaim a cache is `P2-04f`'s, the same way `P2-04c` made `Item` persist with no
UI attached and `P2-04d` made the next ticket responsible for surfacing it.

### Existing architecture
- `GameSession.kill_hero(hero)` (`systems/game_session.gd:64`) is the only call site permitted
  to remove a hero from the roster (`ARCHITECTURE.md` r8). Its body — return every
  `hero.equipped` item to `inventory`, clear `equipped`, erase from `roster`, emit
  `roster_changed` — is exactly what this ticket replaced, not a second path to reconcile.
  `hub/expedition/expedition.gd:58` is its only caller, inside `Expedition.resolve(team, zone)`,
  so `zone` (and `zone.zone_id`) is already in scope there.
- `Item` (`equipment/item.gd`) is the precedent for a small `RefCounted` runtime type with its
  own `to_dict`/`from_dict`, matching `Hero`'s shape. `GameSession` already persists three
  fields the same way — `roster`, `inventory`, `cleared_zone_ids` — each built inside
  `to_dict`/collected inside `from_dict`, guarded on the read side by the shared `_array_field`
  helper for an untrusted or hand-edited save.
- `SYSTEMS.md` § Death and gear recovery (line 1105) authors the cache's shape as
  `LostCache { hero_name, zone_id, items[], turn_lost }`. No `turn` concept exists anywhere in
  the codebase to stamp `turn_lost` with — see Non-goals.
- `ARCHITECTURE.md` r8's own cautionary example is this exact bug: "gear duplicated into a
  cache *and* left equipped." The cache must be built from the same items that get cleared out
  of `hero.equipped`, in the same call, not a second pass over the hero.

### Acceptance criteria
1. New `equipment/lost_cache.gd`: `class_name LostCache`, `extends RefCounted`, fields
   `hero_name: String`, `zone_id: StringName`, `items: Array[Item]`. No `turn_lost` field (see
   Non-goals).
2. `GameSession.kill_hero(hero: Hero, zone_id: StringName) -> void` — signature gains
   `zone_id`. It builds one `LostCache` from `hero.equipped.values()` and appends it to a new
   `GameSession.lost_caches: Array[LostCache]`, then clears `hero.equipped` as before. If
   `hero.equipped` is empty (a hero with nothing geared), no cache is created.
3. `hub/expedition/expedition.gd:58` updates its sole call to `GameSession.kill_hero(hero,
   zone.zone_id)`. `tests/save_roundtrip_check.gd:142` calls it dynamically —
   `_game_session.call("kill_hero", doomed_hero)` — so it does not fail at import and must be
   updated too, or the disk-level permadeath check breaks at runtime with the gate still green.
   That is the second caller, and `.call()` is why grep for `kill_hero(` alone misses it.
4. `GameSession.inventory` no longer gains anything on death — the item that moved is the
   destination, not the fact that it moves.
5. `lost_caches` persists through `GameSession.to_dict()`/`from_dict()`, following the existing
   `roster`/`inventory`/`cleared_zone_ids` pattern (including the `_array_field` guard on read).
6. `tests/unit/test_equipment.gd:59`'s `test_kill_hero_returns_all_equipped_items_to_inventory`
   is **inverted, not deleted** — same shape as `P2-05c`'s treatment of
   `test_equipping_does_not_change_combat_stats_or_team_power`. The new version asserts a dead
   hero's items land in a `LostCache` on `GameSession.lost_caches` (not `inventory`), tagged
   with the right `hero_name`/`zone_id`, and that `hero.equipped` ends up empty.
7. A new test proves a cache survives a real save/reload: kill a geared hero, round-trip
   `GameSession` through `to_dict`/`from_dict`, and assert the reloaded `lost_caches` entry has
   the same `hero_name`, `zone_id`, and item `def_id`/`rank` pairs.
8. A test proves a hero who dies with nothing equipped creates no cache entry.
9. Existing GUT suite passes, including every other `test_equipment.gd` case unmodified by
   this ticket.
10. BUILT green (`tests/import_gate.ps1`, zero errors/warnings) and the full GUT suite green.
11. `verifier` re-runs both commands above independently and confirms the `kill_hero` signature
    change reaches its only real call site correctly — this is the mandatory boundary pass, not
    an optional one.

### Files allowed to change
`equipment/lost_cache.gd` (new), `systems/game_session.gd`, `hub/expedition/expedition.gd`,
`tests/unit/test_equipment.gd` (or a new `tests/unit/test_lost_cache.gd`, implementer's call),
`tests/save_roundtrip_check.gd` (the `.call("kill_hero", ...)` argument only — nothing else).

### Non-goals
No recovery expedition, no damage roll, no cache decay/expiry clock, no `turn_lost` field and
no turn counter to back it — all `P2-04f`, which is explicitly blocked on both the counter and
`power_deficit_penalty`. No UI screen listing or browsing `lost_caches` — `P2-04f`'s
recovery-target picker is the first thing that needs to enumerate them, so building a viewer
here would be thrown away. No salvage of cached items (`P2-05`). No change to
`compute_team_power`, `compute_final_stats`, or anything in `combat/`. No second write path to
`lost_caches` or `hero.equipped` outside `kill_hero()` — one call site, per `ARCHITECTURE.md`
r8.

### Findings

**A `.call()` caller does not fail at import, and grep for `kill_hero(` does not find it.**
`tests/save_roundtrip_check.gd` reaches the autoload dynamically — `_game_session.call("kill_hero",
doomed_hero)` — so a signature change on the sole permadeath seam left the import gate green while
breaking the one script that proves permadeath survives a real disk cycle. The ticket as first
written did not list that file as changeable. Before changing any autoload signature, grep for
`.call(`, `callv(`, and `Callable(` on the method name, not just for the call syntax.

**Criterion 7 shipped as in-memory evidence and had to be reopened.** The GUT test round-trips
`GameSession.to_dict()/from_dict()` with no `SaveService`, no JSON, no disk — the exact pattern
`P2-05a`'s findings warn about, where `slot` reaches actual disk as `8.0` and only the disk leg
exercises the float branch. Worse, the one script that *does* drive a real disk cycle killed a
hero with nothing equipped, so a `LostCache` carrying an `Item` had never crossed JSON at all. The
implementation was in fact correct — raw disk JSON shows `"rank": 8`, and `Item.from_dict`'s
`int()` cast absorbs either shape — but that was confirmed after the fact, not evidence the ticket
had produced. Closed by equipping the doomed hero in `tests/save_roundtrip_check.gd` and asserting
the reloaded cache's `hero_name`, `zone_id`, and item `def_id`/`rank`.

**What makes that assertion disk-sourced rather than in-memory residue:** `from_dict()` clears
`lost_caches` before repopulating it, so a passing assertion after `load_game()` cannot be
satisfied by state left over from before the reload. A round-trip check against a field whose
`from_dict` did *not* clear first would prove nothing.

**A save written before this change has no `lost_caches` key**, and `_array_field` absorbs both a
missing key and an explicit `"lost_caches": null`. Both were proven against a real
`SaveService.load_game()`, not by inspection.

**The GUT command in `CLAUDE.md` was run with `APPDATA` redirected to a scratch path**, not
verbatim, for the reason `P2-05a` established — a plain run overwrites the real
`user://save.json`. Same for the ad-hoc `-s` scripts written during verification.

**Verified by re-run, not by relay.** Import gate exit 0 with zero `SCRIPT ERROR`/`ERROR:`/
`WARNING` lines; GUT 42/42 tests, 9318 assertions, exit 0; `save_roundtrip_check.gd` exit 0 with
its `PASS:` line. All three re-run by the director after the implementer and the verifier had each
reported them, and again after the fix-up. `Get-Process Godot*` empty before and after.

### Files changed
`equipment/lost_cache.gd` (new), `systems/game_session.gd`, `hub/expedition/expedition.gd`,
`tests/save_roundtrip_check.gd`, `tests/unit/test_equipment.gd`

---

## P2-05d — Salvage an unwanted item into parts                        [DONE]

### Objective
Break an unwanted inventory item down into parts of its rank. The parts you own are visible in
the hub and survive a quit and relaunch.

### Existing architecture
- `GameSession` (autoload) owns `inventory: Array[Item]` and emits `roster_changed`; `SaveService.save`
  is connected to it, so every mutating method persists by emitting.
- `Item` (`equipment/item.gd`) is `def_id` + `rank`, nothing else. **No `enhance_level`** — see the
  `P2-05` split note in `TASKS.md`.
- The hub already lists inventory into `%InventoryList` with the `Item` in each row's metadata, and
  the equip path already reads `get_selected_items()`. Salvage is a second button against that same
  selection, not a new screen.
- `BALANCE.rank_names` is 8 entries F…SSS; a rank is an index 0–7.
- `cleared_zone_ids` is the precedent for persisting a keyed collection: written out as a sorted
  `Array[String]` rather than a dict, because JSON has no non-string keys.

### Acceptance criteria
- Salvaging an inventory item removes it from `inventory` and credits **3** parts of that item's rank.
- The yield is literally `3` — `SYSTEMS.md`'s `3 + enhance_level` with `enhance_level == 0`, the only
  value any item can have until `P2-05f`. Do not fabricate the field to make the formula look complete.
- Only items in `inventory` are salvageable; equipped gear unreachable by construction.
- The hub shows the per-rank parts count and updates on salvage with no scene reload.
- **Survives save and reload across real disk JSON**, not a `to_dict`/`from_dict` pair in memory.
- Import gate green with zero warnings; GUT green including a new salvage assertion.
- Existing tests still pass.

### Non-goals
No `Item.enhance_level`, no enhancement (`P2-05f`). No 3:1 conversion (`P2-05g`). No Cores
(Phase 4). No gold, no Forge building (`P2-07`). `forge_salvage_yield_bonus` deliberately unread —
it is authored and has no building level to source from; reading it would invent a Forge. No fourth
autoload, no bulk salvage, no confirmation dialog.

### Findings

**`assert()` is not a guard for anything that can arrive from a save file.** The implementer's
first pass wrote `assert(item.rank >= 0 and item.rank < parts.size())` before `parts[item.rank] += 3`.
Godot strips `assert()` from release exports — the game's shipped form — so in the only build a
player runs, the indexed write was unguarded. `Item.from_dict` never validates `rank`, so a
hand-edited or corrupt save reaches it directly, and the two failure modes differ:

- **positive out-of-range** (`rank: 99`) throws `Out of bounds get index` *after* `inventory.erase(item)`
  has already run — the item is silently destroyed, no parts credited, no `roster_changed.emit()`,
  nothing surfaced to the player;
- **negative** (`rank: -1`) does not throw at all. GDScript indexes arrays from the end, so it
  credits rank 7 (SSS) while `rank_label` clamps the same item to F everywhere it is displayed.

Fixed with `clampi(item.rank, 0, parts.size() - 1)`, which is the convention the codebase had
already established twice — `Item.rank_label` and `Hero.compute_final_stats` both clamp before
indexing a rank-sized array, for exactly this reason. The assert was the outlier, not the fix.

**Neither shipped test could have caught it, and a hand-check in the editor would have masked it.**
The GUT assertion used rank 3 and the round-trip check rank 5, both in range. Worse, asserts are
*active* in a debug/editor run, so anyone verifying by hand would have seen a clean assertion
failure where production silently corrupts. `test_salvage_clamps_a_corrupt_rank` now pins both
directions.

**A fixed `Array[int]` sidesteps the JSON key problem instead of working around it.** The ticket
warned that an int-keyed dict cannot round-trip (keys return as `"3"`), citing `cleared_zone_ids`.
The implementer chose an 8-element array indexed by rank, so there are no keys to lose. The float
trap still applies — `JSON.parse_string` returns `TYPE_FLOAT` for JSON integers, confirmed
empirically — and `from_dict` handles it with an explicit `is float` branch that rejects
non-integral and negative values rather than truncating them.

**A save written before this ticket has no `parts` key**; `_array_field` returns `[]`, the decode
loop does not run, and the zeroed default stands. Covered by `_check_legacy_save`.

**`Item.enhance_level` deliberately absent**, per the `P2-04e`/`turn_lost` precedent: the only
value it could hold today is a placeholder, and a fabricated field reads as real data while
measuring nothing. `P2-05f` adds the field and salvage's `+ enhance_level` term together.

**Verified by re-run, not by relay.** Import gate exit 0 with zero `SCRIPT ERROR`/`ERROR:`/`WARNING`
lines; GUT 44/44 exit 0; `save_roundtrip_check.gd` exit 0 with its `PASS:` line naming `parts`.
All three re-run by the director after the implementer reported them, and again after the clamp
fix-up. `Get-Process Godot*` empty after every run.

### Files changed
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `tests/save_roundtrip_check.gd`,
`tests/unit/test_equipment.gd`

---

## P2-05g — 3:1 part conversion                             [DONE]

### Objective

Three parts of rank N become one part of rank N+1, on a button press in the hub, and the new
totals survive save and reload.

### Existing architecture

- `GameSession.parts` is a fixed 8-element `Array[int]` indexed by rank
  (`systems/game_session.gd:12`), already persisted and already validated on load
  (`from_dict`, `game_session.gd:125-139`). **No new persisted field is needed.**
- `GameSession.salvage_item()` (`game_session.gd:57`) is the precedent for a parts mutation:
  mutate, then `roster_changed.emit()`, which is what triggers the autosave
  (`_ready`, `game_session.gd:20`).
- `BALANCE.rank_names` is `F D C B A S SS SSS` (`balance.tres:14`), positionally the same index
  space as `parts`. `hub/hub.gd:_refresh_parts()` already renders every rank off that pairing.
- The Forge is a `MeshInstance3D` with a `Label3D` and no UI (`hub/hub.tscn:51`); buildings
  become real in `P2-07`.

### Siting decision

**The control goes in the Inventory column of `EquipmentPanel`, under the existing `Parts`
label** — not on the Forge. `P2-07` is what gives the Forge a panel to host anything; siting it
there now means inventing that panel inside this ticket. Parts are displayed in the Inventory
column today, so the action sits where its currency already is, and `P2-07` moves both together.

### Acceptance criteria

- A rank selector offers the seven convertible source ranks (`F`–`SS`). `SSS` is not offered:
  nothing exists above it.
- Pressing Convert with ≥3 parts of the chosen rank spends exactly 3 and credits exactly 1 of the
  next rank. One press, one conversion — not a drain-everything button.
- Pressing Convert with fewer than 3 says so in `%Status` and changes no counts.
- The `Parts` label reflects the new totals immediately.
- The new totals survive a real save and reload — the disk leg, not an in-memory
  `to_dict`/`from_dict` pair (`P2-05a` Findings).
- Conversion is refused for a source rank outside `0..parts.size() - 2`, with no write. The rank
  comes from a UI selector today, but `parts` indices and `assert()` have history here: an
  `assert()` is not a guard (`P2-05d` Findings).
- Import gate exit 0, zero warnings. Existing GUT tests still pass, plus new coverage for the
  three cases above (success, insufficient, refused rank).

### Files allowed to change

`systems/game_session.gd` · `hub/hub.gd` · `hub/hub.tscn` · `tests/unit/test_equipment.gd` ·
`tests/save_roundtrip_check.gd` — the disk-leg criterion above cannot be met without it, and
`P2-05d` touched the same file for the same reason.

### Non-goals

- No Forge building UI, no building levels — that is `P2-07`.
- No downward conversion, no bulk convert, no conversion cost or loss beyond the authored 3:1.
- No `Item.enhance_level`, no enhancement — `P2-05f`, blocked on `P2-05e`.
- No new `BalanceTable` field. The rule is `3`, authored in `SYSTEMS.md` § Material economy as
  the whole system; a tunable for it is a number nobody has asked to tune.

---

### Findings

**The Forge could not host this, and that is a sequencing fact rather than a preference.**
`hub/hub.tscn`'s five buildings are `MeshInstance3D` + `Label3D` decoration with no panel, no
input and no script; `P2-07` is what makes them real. Siting conversion "at the Forge" as
`SYSTEMS.md` words it would have meant inventing that panel inside this ticket. It sits under the
`Parts` label in the Inventory column instead — where its currency is already displayed — and
`P2-07` moves the action and the readout together. Any later ticket that reads `SYSTEMS.md`
§ Material economy literally should expect this.

**`OptionButton.selected` cannot be `-1` once items exist**, so `_on_convert_pressed()`'s
unguarded `get_item_metadata(_convert_rank_option.selected)` is safe. The first `add_item()`
auto-selects index 0 and nothing reverts it while the list is non-empty; `_populate_convert_ranks()`
runs in `_ready()`, before any press is reachable. Verified empirically in a headless probe, not
assumed — `_on_expedition_pressed()` had already been relying on the same property for
`%ZoneOption` without anyone writing down why it holds.

**The disk leg is load-bearing precisely because it does not call `save`.**
`_check_parts_round_trip()` converts and then reads raw JSON off disk, so the autosave
(`roster_changed` → `SaveService.save`, wired in `GameSession._ready()`) is the thing under test.
A mutation that forgets to emit persists nothing while every in-memory assertion still passes —
that is the gap that reopened `P2-04e`. Copy this shape, not an explicit-save one, for the next
persisted mutation.

**`hub.tscn` has an accidental smoke test and it should not be mistaken for coverage.**
`tests/unit/test_expedition.gd` instantiates the hub scene for unrelated reasons, so a
`%ConvertRankOption` that failed to resolve would redden the suite at `_ready()`. That is the only
thing standing behind the scene↔script seam here: **no test presses the Convert button.** The
button handler's metadata cast and its two `%Status` strings rest on structural inspection.

**One press converts one batch**, deliberately — not `parts[rank] / 3`. `SYSTEMS.md` authors a
3→1 exchange and nothing else; a drain-everything button is a UX decision nobody has made.

**Rank 7 refuses structurally, not incidentally.** The guard is
`rank < 0 or rank >= parts.size() - 1 or parts[rank] < 3` — SSS is excluded because there is no
rank above it to credit, and the selector never offers it. Not an `assert()`: `P2-05d` shipped that
mistake once, and asserts are stripped from release exports.

**Pre-existing tension, not introduced here:** `convert_parts` is an instance method on the
`GameSession` autoload, the shape `CODING_RULES.md:93-94` calls the bad pattern. Every mutator in
that file has it (`add_hero`, `add_item`, `equip_item`, `unequip_item`, `salvage_item`), so
matching the precedent was correct for this ticket — but the file now has six of them and no
ticket owns the reconciliation.

**Verified by re-run, not by relay.** Import gate exit 0 with zero `SCRIPT ERROR`/`ERROR:`/`WARNING`
lines; GUT 47/47 exit 0 (was 44); `save_roundtrip_check.gd` exit 0 with its `PASS:` line naming
part conversion. All three re-run by the director after the implementer reported them; the
implementer's own GUT run had hung without output, which reproduced nowhere else.
`Get-Process Godot*` empty after every run.

### Files changed
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `tests/save_roundtrip_check.gd`,
`tests/unit/test_equipment.gd`

---

## P2-05f — Enhancement: spend parts to make one item stronger          [DONE]

### Objective

Select an item in the Inventory column, press **Enhance**, and it gains a level — costing
parts of its own rank, raising the stat it gives the hero wearing it, and raising what it
returns when salvaged. Visible in the item's list entry, in the parts readout, and in the
hero's stats.

### Existing architecture

- `Item` (`equipment/item.gd`) is `RefCounted` with `def_id` and `rank`, and a
  `to_dict`/`from_dict` pair. `from_dict` does **not** validate `rank` — every consumer
  `clampi`s before use instead (`Item.rank_label`, `Hero.compute_final_stats`,
  `GameSession.salvage_item`). Read `P2-05d`'s Findings: an `assert()` is not a guard for
  anything arriving from a save file, because release exports strip it.
- `Hero.compute_final_stats` (`heroes/hero.gd:74-92`) already applies gear: eight non-crit
  slots accumulate into `equip_pct[]` (indexed by `PrimaryStat` ordinal, which `STAT_NAMES`
  mirrors positionally) and get one multiply at the end; necklace/ring add `equip_crit_pct`
  flat to the two crit stats, then `CRIT_RATE` is clamped to `equip_crit_rate_cap`.
- `GameSession.parts` is a fixed 8-element `Array[int]` indexed by rank.
  `salvage_item()` credits a flat `3`; `convert_parts(rank) -> bool` is the shape to copy for
  a spend that can fail — validate, mutate, `roster_changed.emit()`, return `bool`.
- The Inventory column of `hub/hub.tscn` holds `InventoryList`, `Equip`, `Salvage`, `%Parts`,
  `%ConvertRankOption`, `Convert`, each wired by a `[connection]` block to a `_on_*_pressed`
  handler in `hub/hub.gd`. Adding a button is a scene↔script seam change.
- The ruling is `SYSTEMS.md` § Enhancement (`P2-05e`). It is settled; do not re-derive it.

### Acceptance criteria

1. New `BalanceTable` field `enhance_pct_per_level: float = 0.08`, authored into
   `balance.tres`. No other new field — the cap is the existing `forge_enhance_cap_max`.
2. `Item.enhance_level: int`, default `0`, in `to_dict`/`from_dict` in the same shape `rank`
   uses (`int(data.get(...))`, which absorbs the float a JSON integer decodes as off disk).
3. `GameSession.enhance_item(item: Item) -> bool` — returns `false` without writing anything
   when the item is not in `inventory`, when `enhance_level` is already at
   `balance.forge_enhance_cap_max`, or when `parts[item.rank]` is short. On success it spends
   `2 + enhance_level` parts **of the item's own rank**, increments `enhance_level`, and emits
   `roster_changed`.
4. `Hero.compute_final_stats` scales each item's own contribution *before* the existing
   per-stat summation: `contribution * (1.0 + balance.enhance_pct_per_level * enhance_level)`,
   applied to `equip_pct_per_rank[rank]` for the eight non-crit slots **and** to
   `equip_crit_pct_per_rank[rank]` for necklace/ring. Not a second multiply after the sum.
5. `salvage_item` yields `3 + enhance_level` parts, replacing the flat `3`.
6. `enhance_level` is `clampi`ed to `[0, balance.forge_enhance_cap_max]` at each of those
   three read sites, for the same reason `rank` is — it arrives unvalidated from a save, and a
   negative one would shrink a stat or credit negative parts.
7. An **Enhance** button in the Inventory column, wired like `Salvage`. On success the status
   line names the item, its new level, and what it cost; on refusal it says which of the three
   reasons applied. `InventoryList` and `EquippedList` entries show the level when non-zero
   (e.g. `A Ashen Greaves +3`).
8. GUT coverage in `tests/unit/test_equipment.gd`: the cost ladder (`0→1` costs 2, `1→2` costs
   3), refusal at the cap without writing, refusal on insufficient parts without writing,
   a `+8%`-per-level stat change on a non-crit slot and on a crit slot, and **salvage at a
   non-zero `enhance_level`** — the term `P2-05d` could not test.
9. `tests/save_roundtrip_check.gd`: an enhanced item survives a **real disk** save/reload with
   its level intact, asserted against the raw JSON as the parts check already is. An in-memory
   `to_dict`/`from_dict` pair is not evidence here — see `P2-05a` and `P2-04e`.
10. BUILT green (zero errors, zero warnings) and the full GUT suite green.

### Files allowed to change

`equipment/item.gd` · `balance_table.gd` · `balance.tres` · `heroes/hero.gd` ·
`systems/game_session.gd` · `hub/hub.gd` · `hub/hub.tscn` · `tests/unit/test_equipment.gd` ·
`tests/save_roundtrip_check.gd`

### Non-goals

- **Gold.** Struck by `P2-05e`; it has no source. `P2-10` owns it. Cost is parts only.
- **`forge_level`.** The cap is flat `forge_enhance_cap_max`. `forge_enhance_cap_per_level`
  stays authored and unread until `P2-07`.
- **Enhancing equipped gear.** Inventory-only, matching `salvage_item`'s existing reachability
  note. Unequip first.
- Enhancement affecting anything but the item's own primary-stat contribution — no new affix,
  no socket, no rank change.
- A Forge panel. `P2-05g` already sited these controls in the Inventory column for exactly
  this reason; buildings have no panel until `P2-07`.

### Findings

**Criterion 3's signature was wrong, and the review caught it — an autoload must not hold a
shared Resource.** The first pass gave `GameSession` a
`const BALANCE = preload("res://balance.tres")` so `enhance_item` could read
`forge_enhance_cap_max`, justified as matching `hub/hub.gd`'s existing const. That
justification is wrong: `hub.gd` is a scene script. `ARCHITECTURE.md` § "Reaching shared
Resources" prohibits this and names `GameSession` in the prohibition — *"nothing to gain by
centralizing the load behind a fourth autoload or behind `GameSession`"* — because it makes
every consumer's tests depend on booting that autoload. There was no functional bug
(`ResourceLoader` caches by path), which is exactly why the import gate and all 53 tests
stayed green over it. Corrected to the shape the same paragraph prescribes and
`Hero.compute_final_stats` already uses: `balance: BalanceTable` passed in explicitly, on both
`enhance_item` and `salvage_item`. **The ticket asked for the wrong signature and nobody caught
it until review** — criterion 3 as written specified `enhance_item(item: Item) -> bool`, which
cannot read a balance number without violating the rule.

That correction changed an **autoload signature**, which is the `P2-04e` trap: `salvage_item`'s
second caller is dynamic (`tests/save_roundtrip_check.gd` via
`_game_session.call("salvage_item", …)`), invisible to a grep for `salvage_item(` and invisible
to the import gate. The runtime script is the only thing that catches it, and it did.

**`Dictionary.get(key, default)` does not defend against an explicit `null`** — only against a
missing key. `int(data.get("rank", 0))` therefore throws `Invalid call. Nonexistent 'int'
constructor.` on a save containing `"rank": null`, and `from_dict` returns `null` into
`inventory`/`equipped`, where the next `.def_id` read throws again. This defect **predated the
ticket** on `rank`; adding `enhance_level` in the same shape doubled it. Fixed for both fields
with one `Item._int_field()` helper — the scalar analogue of `GameSession._array_field()`,
which `P2-04c` added for exactly this on Array fields. `Hero.from_dict` and
`LostCache.from_dict` still carry it on their own scalar fields; that is `P2-11`.

**The status-string handler duplicates the rule.** `hub.gd`'s `_on_enhance_pressed` re-checks
all three of `enhance_item`'s preconditions so it can name which one fired, then calls
`enhance_item` and discards its `bool`. Judged a maintenance hazard rather than a live bug —
same clamp bounds, same rank index, same cost formula, no intervening mutation — but it is two
sources of truth for one rule, and the honest fix is a reason code on the return rather than a
second copy of the checks. Left as-is deliberately; whoever adds a fourth precondition must
remember to add it twice.

**The `+N` suffix in both `ItemList`s reads `item.enhance_level` unclamped**, so a corrupt save
displays an out-of-range level. Cosmetic by design — all three *gameplay* read sites clamp per
criterion 6, and clamping the display too would hide the corruption from the only place a
player could notice it.

**Verified by re-run, not by relay.** Import gate exit 0 with zero
`SCRIPT ERROR`/`ERROR:`/`WARNING` lines; GUT 54/54, 9360 asserts, exit 0 (was 47);
`save_roundtrip_check.gd` exit 0 with `enhanced equipment` named in its `PASS:` line, run with
`%APPDATA%` redirected so the real `user://save.json` was never touched. All three re-run by
the director after the implementer and the verifier each reported them, and again after the
fix-up. The arithmetic was checked independently against `SYSTEMS.md` § Enhancement's worked
example — SSS necklace at `+15` yields `+26.96pp` additive, exact match. `Get-Process Godot*`
empty after every run.

### Files changed
`balance_table.gd`, `balance.tres`, `equipment/item.gd`, `heroes/hero.gd`,
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `tests/save_roundtrip_check.gd`,
`tests/unit/test_equipment.gd`

---

## P2-06a — Sacrifice a hero for essence; spend essence to rank another up      [DONE]

### Objective
From the hub, a player can sacrifice one hero into essence and spend accumulated essence to
raise another hero's rank. Feeding a hero of the same `def_id` as the target yields triple
essence and adds one resonance point to the target — resonance is only a counter here; what it
unlocks is `P2-06b`.

### Existing architecture
- `essence_bases` (`balance_table.gd:8`, 8 entries F..SSS) and `rank_up_essence_costs`
  (`balance_table.gd:9`, 7 entries F→D..SS→SSS) are already authored on `BalanceTable` — this
  ticket reads them and changes nothing there.
- `Hero` (`heroes/hero.gd:16-19`) carries `hero_name`, `rank`, `def_id`, `equipped` and nothing
  else. It needs a new `resonance: int = 0` field, serialized through `to_dict`/`from_dict` the
  same validated way `rank` already is (`Item.int_field`, per `heroes/hero.gd:133` and the
  `P2-11` null-crash fix) — do not reintroduce an unguarded `int()` read.
- `GameSession` (`systems/game_session.gd`) already holds currency-shaped state the same way
  this needs it: `parts: Array[int]` (line 11) plus `salvage_item`/`enhance_item`/`convert_parts`
  as its own instance methods (lines 66-97) that validate a precondition, mutate state, and
  `roster_changed.emit()` — which `SaveService.save` is connected to (`_ready()`, line 18).
  Mirror the *orchestration* half of that shape for the two new methods — but not the arithmetic.
  `DECISIONS.md` 2026-08-06 ruled those three methods **debt, not precedent**: they inline
  balance-driven cost formulas the 2026-08-01 rejection named, and `CODING_RULES.md:93-103` still
  states the rule in the present tense with a worked example named
  `compute_essence_yield(fodder, target, balance)`. Structural bookkeeping (erasing a roster
  entry, moving an item between arrays, mutating `essence`) is a `GameSession` method; a cost or
  yield formula is a pure `static func`. See criteria 2-3.
- `kill_hero(hero, zone_id)` (`systems/game_session.gd:105`) is the sole call site
  `ARCHITECTURE.md` r8 permits for removing a hero from `roster`. It only builds a `LostCache`
  when `hero.equipped` is non-empty, and `LostCache.zone_id` already defaults to `&""`
  (`equipment/lost_cache.gd:9`).
- `hero.rank`, and any new int field on `Hero` or `GameSession`, can arrive out-of-range from a
  hand-edited or corrupt save — `Item.int_field` validates type, not range. Clamp before indexing
  `essence_bases`/`rank_up_essence_costs`, the same way `salvage_item` already clamps `item.rank`
  (`systems/game_session.gd:72`). Do not `assert()` a save-sourced value — asserts are stripped
  in release, which is exactly how `P2-05d` shipped a negative rank crediting SSS while
  displaying F.

### Acceptance criteria
1. `GameSession` gains `essence: int = 0`.
2. Two pure functions carry all the arithmetic, as `static func` on `heroes/hero.gd` beside
   `compute_final_stats`/`compute_team_power` — the existing precedent for hero rules that take
   `balance` and touch no global state. Both are directly testable without booting the engine,
   which is the whole point of `DECISIONS.md` 2026-08-06:
   - `Hero.compute_essence_yield(fodder: Hero, target: Hero, balance: BalanceTable) -> int` —
     `essence_bases[clampi(fodder.rank, 0, essence_bases.size() - 1)]`, tripled when
     `fodder.def_id == target.def_id` and that `def_id` is not `Hero.NO_ARCHETYPE_DEF_ID`. The
     dupe condition lives here, not in the caller.
   - `Hero.compute_rank_up_cost(hero: Hero, balance: BalanceTable) -> int` —
     `rank_up_essence_costs[clampi(hero.rank, 0, rank_up_essence_costs.size() - 1)]`.
3. `GameSession.sacrifice_hero(fodder: Hero, target: Hero, balance: BalanceTable) -> bool`:
   refuses (returns `false`, no state change) when `fodder == target`, when `fodder` is not in
   `roster`, or when `fodder.equipped` is non-empty. Otherwise adds
   `Hero.compute_essence_yield(fodder, target, balance)` to `essence`, increments
   `target.resonance` when that call tripled (test the same dupe condition — do not re-derive the
   multiplier from the returned number), and removes `fodder` from the roster via
   `kill_hero(fodder, &"")` — no other removal path. `kill_hero` already emits `roster_changed`,
   so do not emit a second time; that is a redundant `SaveService.save()`.
4. `GameSession.rank_up_hero(hero: Hero, balance: BalanceTable) -> bool`: refuses when
   `hero.rank >= rank_up_essence_costs.size()` (already SSS) or when `essence` is below
   `Hero.compute_rank_up_cost(hero, balance)`. Otherwise deducts that cost, increments
   `hero.rank` by 1, leaves every other field on `hero` untouched (rank-up preserves level per
   `DECISIONS.md` 2026-08-01 — currently vacuous since `Hero` has no level field, but the method
   must not reset `equipped` or anything else that does exist), and `roster_changed.emit()` on
   success only.
5. No level term in the yield formula: `essence_bases[fodder.rank]` alone, never
   `1.0 + fodder.level / level_cap[...]` — `Hero` has no `level` to read.
6. `tests/unit/test_sacrifice.gd` covers both pure functions **directly**, without going through
   `GameSession` — a fresh `Hero` and a `BalanceTable`, asserting the dupe triple and the
   non-dupe base. That is the criterion that makes criterion 2's extraction worth anything; a
   suite that only ever reaches the formulas through the autoload has reproduced the debt
   `DECISIONS.md` 2026-08-06 names.
7. A control on the existing hub screen (`hub/hub.tscn`/`hub/hub.gd`, the same "ugly but present"
   bar as `P2-05a`/`P2-05d`/`P2-05g`) lets the player pick a fodder hero and a target hero from
   the roster and trigger sacrifice, and a separate control triggers rank-up on a selected hero
   when `essence` is sufficient. No dedicated scene required.
8. Survives save and reload: `GameSession.essence` and `Hero.resonance` both round-trip through
   `GameSession.to_dict`/`from_dict` and a real `SaveService.save()`/`load_game()` disk cycle —
   extend `tests/save_roundtrip_check.gd`, not just an in-memory `to_dict`/`from_dict` pair
   (`P2-04e`'s finding: the in-memory version proved nothing new).
9. Existing tests still pass (GUT suite + import gate).

### Files allowed to change
- `heroes/hero.gd`
- `systems/game_session.gd`
- `hub/hub.gd`
- `hub/hub.tscn`
- `tests/unit/test_sacrifice.gd` (new)
- `tests/save_roundtrip_check.gd`

### Non-goals
- Resonance trait unlocks at 1/3/6 — `P2-06b`, blocked on an authored trait pool.
- The yield formula's level term — owned by whichever ticket adds `Hero.level` (`P2-04a` is the
  nearest candidate). Do not add a placeholder level field here to make the term nonzero.
- Any change to `kill_hero`'s signature or its `LostCache` branch.
- A dedicated Sacrifice/Forge screen or panel — `P2-07` owns building panels.
- `power_deficit_penalty` or any turn concept (`P2-04f`) — unrelated to this ticket.
- Gold, buildings, or any other currency — `parts` and the new `essence` are separate pools; do
  not merge them or let one pay the other's cost.

### Findings

**`OptionButton.add_item()` auto-selects index 0 on a cleared button, and that silently
retargeted an irreversible action.** `_refresh_hero_option()` rebuilds `%FodderOption` on every
`roster_changed`. The first pass re-selected the previously-chosen hero explicitly inside the
populate loop and did nothing when that hero was gone — which is exactly the state right after a
sacrifice removes the fodder. Godot had already auto-selected index 0 by then, so the dropdown
kept `selected == 0` and quietly pointed at whoever now occupied the slot. A player culling
duplicate fodder back-to-back — the workflow this ticket exists to serve — who pressed Sacrifice
a second time without reopening the dropdown would **permanently lose a hero they never
selected**. Fix is one line: re-select by identity *after* the loop,
`option.select(GameSession.roster.find(previous))`, which lands on `-1` when the hero is gone and
leaves the button blank. The `null` case is free — `Array.find(null)` is `-1`, so a freshly
populated dropdown also starts unselected rather than defaulting to whoever is first.

This sharpens `P2-05g`'s finding rather than repeating it. That one recorded the engine behavior
(`OptionButton.selected` is never `-1` while items exist) as a convenience `%ZoneOption` had been
relying on unwritten. This one is the same behavior turning into a permadeath bug the moment the
button drives an irreversible action: **a stale-but-valid selection is a data-loss bug, not a UI
nit.** Any future dropdown that gates a destructive action re-selects by identity or blanks.

**Neither gate could see it.** Import gate green, GUT 58/58 green, save round-trip green — before
and after the fix. The implementer's own end-to-end UI check passed too, because it selected
freshly before every press; the bug only exists on the *second* press. It took driving the real
scene through the exact repeated-use path to surface it. This is the `CLAUDE.md` scene ↔ script
seam behaving precisely as documented: compiles green while being wrong.

**First ticket to follow `DECISIONS.md` 2026-08-06 instead of the `P2-12` debt shape.** The
arithmetic sits in two pure `static func`s on `Hero` and `tests/unit/test_sacrifice.gd` reaches
both without booting a single autoload — the concrete payoff the reaffirmed ADR predicted, and
the thing no test of `salvage_item`/`enhance_item`/`convert_parts` can currently do.

**The dupe condition is deliberately written twice and nothing keeps the copies honest.**
Criterion 3 forbids re-deriving the multiplier from the returned number, so
`Hero.compute_essence_yield` and `GameSession.sacrifice_hero` each test
`fodder.def_id == target.def_id and fodder.def_id != NO_ARCHETYPE_DEF_ID` independently. That is
the right call — inferring "was it tripled?" from an integer is worse — but it is a real
two-site invariant. `P2-06b` will touch resonance and should collapse it, most likely by having
the yield function report the dupe rather than the caller re-test it.

`hub.gd` also calls both pure functions for its status text and pre-checks. Reviewed and kept:
that is display use of the authoritative function, not a duplicated formula.

**Two additions the ticket did not ask for, both kept.** A `maxi(…, 0)` clamp on the
*pre-existing* `rank` load path (every `hero.rank` use site already clamps locally, so no live
impact was found — recorded because it is a behavior change to shipped save decoding), and
`_check_legacy_save()` now asserts `essence == 0` / `resonance == 0` after loading a save written
before either field existed. The second closes a genuine gap: forward-compatibility of old saves
was safe by construction via `Item.int_field`'s fallback, but untested.

### Files changed
`heroes/hero.gd`, `systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`,
`tests/save_roundtrip_check.gd`, `tests/unit/test_sacrifice.gd`

---

## P2-14 — The hub shows what a hero's stats actually are                 [DONE]

### Objective
Selecting one hero in the roster shows its six computed final stats, its resonance count, and its
active resonance traits. Equipping gear, ranking up, or feeding it a dupe visibly moves those
numbers.

### Existing architecture
- `Hero.compute_final_stats(hero, definition, balance, level)` (`heroes/hero.gd:44`) already returned
  the six stats with gear and traits folded in, and `Hero.active_resonance_traits()` returned the
  unlocked `TraitDefinition`s. Nothing outside `combat/` and `tests/unit/` called either — that was
  the whole gap.
- Combat derives the level it passes: `BALANCE.level_caps[clampi(hero.rank, …)]`
  (`combat/quick_resolve.gd:21-23`). There is no `Hero.level` field (`P2-04a`). A display that
  re-derives this can silently disagree with combat — the same failure the combat seam's one-place
  ramp rule exists to prevent — so the derivation moved into one `static func`.
- `hub/hub.gd:_refresh_equipped()` already ran on single-hero selection through `_selected_hero()`
  and the `multi_selected` connection; `_ready()` already fanned `roster_changed` out to six
  refreshes.
- `Summon.archetype_label_for()` was the precedent for `NO_ARCHETYPE_DEF_ID`: label it rather than
  call `definition_for("")` on every selection and spray `push_error`.

### Acceptance criteria
1. `Hero.level_for(hero, balance) -> int` is the single home of the rank→level derivation, and
   `combat/quick_resolve.gd` calls it instead of indexing `level_caps` inline. The level handed to
   `compute_final_stats` is unchanged.
2. With exactly one roster hero selected, the hub shows its six stats — HP/ATK/DEF/SPD as integers,
   `CRIT_RATE`/`CRIT_DMG` as percentages — plus `Resonance: N` and each active trait's
   `display_name`, or an explicit "none" when the pool yields nothing.
3. Selecting zero or several heroes clears the readout instead of leaving stale numbers on screen.
4. A hero with `NO_ARCHETYPE_DEF_ID` (Phase 1 saves) shows a label, not blank stats, and emits no
   `push_error`.
5. Equipping an item, ranking a hero up, and sacrificing a dupe into it each visibly change the
   readout without leaving the hub.
6. `tests/unit/test_hero_stats.gd` asserts `Hero.level_for` returns `balance.level_caps[rank]` for
   every rank and clamps an out-of-range rank.
7. Both gates green: import gate with zero errors *and* zero warnings, full GUT suite passing.
8. No save key changes — display only, nothing here is persisted.

### Files allowed to change
`hub/hub.gd`, `hub/hub.tscn`, `heroes/hero.gd`, `combat/quick_resolve.gd`,
`tests/unit/test_hero_stats.gd`, `docs/TASKS.md`. **Widened during the ticket** to
`tests/unit/test_expedition.gd` — criteria 2/3/5 are scene behavior, and that file already owns
every hub-scene drive in the suite (its `hub.tscn` instantiation helper and `%UniqueName` lookups).
A second hub-driving test file would have duplicated the setup to satisfy a file list.

### Non-goals
- No `Hero.level` field and no XP — that is `P2-04a`.
- No stat-source breakdown (base vs gear vs trait), no before/after preview, no tooltips.
- No team-power readout: `compute_team_power` is deliberately crit-blind and pinned by an assertion
  (`P2-05c`).
- No hub restyle or new panel layout beyond the one `Label` this needs.

### Findings

**`ItemList.select()` does not emit `multi_selected`.** A scene-driving test has to emit the signal
itself (`roster_list.multi_selected.emit(0, true)`), and doing that is strictly better than calling
the handler directly: it exercises the `[connection]` block inside `hub.tscn`, which is the half of
the scene↔script seam the import gate cannot see. The existing hub tests drive buttons the same way
via `pressed.emit()`.

**Crit renders with one decimal, deliberately.** Jewelry and 3 of the 15 authored traits move only
the crit channel, at `+1.5pp` per rank — a rounded integer can absorb an entire item, which would
make the readout look inert exactly where traits and rings live. The scene test asserts a resonance
trait moves the *displayed* DEF integer, so a magnitude too small to show up fails a test instead of
shipping a readout that never changes.

**"none" is keyed off the trait array being empty, not off `resonance > 0`.** The first pass used
resonance, which is correct only while `resonance_trait_thresholds[0] == 1` *and* every archetype has
a non-empty pool — a definition with an unauthored pool would have printed `Traits: ` with nothing
after it. Two conditions the display has no reason to depend on.

**The worker's `partial` was its own sandbox, not the suite.** The documented GUT command dies inside
a Codex `workspace-write` sandbox because `user://logs/` resolves into the real `%APPDATA%`; it exits
`-1073741819` before the first test. Recorded in `KNOWN_ISSUES.md` § Environment. The director's own
unsandboxed run of the identical command passed. Read the exit code before believing a red gate from
a worker.

**Verified by re-run, not by relay.** Import gate exit 0, zero `SCRIPT ERROR`/`ERROR:`/`WARNING` in
the checked pass. GUT 67/67, 9495 asserts, exit 0 (was 66/9485 — the two new tests). The suite's
three `ERROR:` lines are pre-existing: `git stash` and re-run gave the identical count of 3, all from
deliberate missing-definition and invalid-save tests, none from the display path — which is how
criterion 4 was checked rather than assumed. `Get-Process Godot*` empty before and after.

**Not verified: a windowed run.** No screenshot was taken, so the readout's *appearance* is
unproven — the 9-line `Label` is a non-expanding child of a `VBoxContainer` whose `ItemList` above it
has `size_flags_vertical = 3`, so it takes its full minimum height and the list yields, which is
reasoning rather than evidence.

**Archive integrity, unrelated to this ticket:** `P2-06a`'s body was appended into the *middle* of
`P2-05f`'s Findings section, splitting it — so the block immediately above this one reads as
`P2-06a`'s verification and file list when it is `P2-05f`'s. `P2-06a` has no `### Files changed`
block of its own. Found while appending here; not repaired inside a ticket that does not own it.

### Files changed
`heroes/hero.gd`, `combat/quick_resolve.gd`, `hub/hub.gd`, `hub/hub.tscn`,
`tests/unit/test_hero_stats.gd`, `tests/unit/test_expedition.gd`

---

## P2-07b — Circle, Forge, and Sanctum are levelable                        [DONE]

### Objective
From the hub, spend parts to raise a building's level (Summoning Circle, Forge, or Sanctum), see
the new level and remaining parts update immediately, and have the level survive a real quit and
relaunch. No bonus is wired to gameplay yet — matches `P2-05a`'s own precedent ("Equipping
changes nothing about combat — no formula exists yet"); `P2-07c`/`P2-07d`/`P2-07e` each wire one
building's bonus into its live consumer once this lands.

### Existing architecture
- `GameSession` (autoload, `systems/game_session.gd`) owns all persisted player state as plain
  fields plus `to_dict`/`from_dict`, wired to `SaveService.save` via `roster_changed`.
  `parts: Array[int] = [0,0,0,0,0,0,0,0]` (`game_session.gd:12`) is the direct precedent for a
  fixed-length, index-keyed `Array[int]` — chosen specifically because JSON has no non-string
  keys (`P2-05d`'s Findings). Building levels follow the same shape.
- `hub.tscn`'s `Buildings` node lists all five buildings in a fixed child order —
  `SummoningCircle`, `Forge`, `TrainingHall`, `Sanctum`, `Reliquary` — as `MeshInstance3D`
  decoration with a `Label3D` each, no script, no interaction. This is the only place all five
  buildings are already named in the project, and this ticket's array indices follow that same
  order so a later ticket adding Training Hall/Reliquary is an append, not a renumber.
- `BalanceTable.summoning_circle_level_cap = 5` is the only authored per-building cap field.
  `SYSTEMS.md` § Base buildings' "Level caps" ruling states all five buildings share cap 5
  "absent a reason to diverge" — this ticket reuses that one field as the shared cap rather than
  adding four more identically-valued fields.
- Upgrade cost is `10 * (n + 2)` parts of rank index `n` (`SYSTEMS.md` § Base buildings, `n` =
  the building's level before the upgrade, 0 = unbuilt).
- `hub.tscn`'s `UI/Root` had `RosterPanel` and `EquipmentPanel` as its only two panels; the
  `EquipmentPanel/Columns/Inventory` button block is the pattern copied here. No building panel
  existed anywhere; `P2-05g`'s Findings note the 3:1 conversion control had to be sited in the
  Inventory column for exactly this reason.
- `enhance_item`/`salvage_item`/`sacrifice_hero` already take `balance: BalanceTable` as an
  explicit argument rather than reading a preloaded const off the autoload (`ARCHITECTURE.md`
  § "Reaching shared Resources"; `P2-05f`'s Findings). `building_levels` is different: it is
  `GameSession`'s own persisted *state*, not a shared Resource, so `GameSession`'s own methods may
  read it directly with no signature change.

### Acceptance criteria
1. `GameSession.building_levels: Array[int] = [0, 0, 0, 0, 0]`, indexed to match `hub.tscn`'s
   `Buildings` child order (0 = Summoning Circle, 1 = Forge, 2 = Training Hall, 3 = Sanctum,
   4 = Reliquary). Persists through `to_dict`/`from_dict` using the exact guard `parts` already
   uses (`_array_field` + explicit int-or-integral-float decode, `push_error` and skip anything
   else, `mini(saved.size(), building_levels.size())` so a save from before this ticket defaults
   every entry to 0).
2. `GameSession.upgrade_building(index: int, balance: BalanceTable) -> bool` — returns `false`
   without writing anything when `index` is outside `[0, building_levels.size())`. Otherwise reads
   `building_levels[index]` clamped to `[0, balance.summoning_circle_level_cap]` as `level`;
   returns `false` if `level >= balance.summoning_circle_level_cap`, or if
   `parts[clampi(level, 0, parts.size() - 1)] < 10 * (level + 2)`. On success it spends that many
   parts of rank `level`, sets `building_levels[index] = level + 1`, and emits `roster_changed`.
3. Only indices 0 (Circle), 1 (Forge), 3 (Sanctum) are reachable through the UI this ticket ships.
   Indices 2 and 4 stay `0` forever until a future ticket adds their buttons.
4. No building's bonus changes any gameplay number yet.
   `summoning_circle_multiplier_per_level`, `forge_enhance_cap_per_level`,
   `forge_salvage_yield_bonus`, `sanctum_essence_yield_bonus` stay authored-and-unread.
5. A new `BuildingsPanel` under `hub.tscn`'s `UI/Root`, sibling to `RosterPanel`/`EquipmentPanel`,
   same register style: one row per shipped building (Circle, Forge, Sanctum) — a `Label` showing
   name and current level and an "Upgrade" `Button`. Three separate handlers, matching the
   existing one-handler-per-button convention, each calling
   `GameSession.upgrade_building(<index>, BALANCE)`. Labels refresh on `roster_changed`.
6. On success the `%Status` line names the building, its new level, and the cost paid; on refusal
   (cap or insufficient parts) it says which reason applied.
7. GUT coverage in a new `tests/unit/test_buildings.gd`: the cost ladder for at least two steps
   (0→1 costs 20 F-rank parts, 1→2 costs 30 D-rank parts), refusal at cap 5 without writing,
   refusal on insufficient parts without writing, refusal on an out-of-range index without
   writing.
8. `tests/save_roundtrip_check.gd`: upgrade a building through a **real disk** save/reload cycle
   and assert the reloaded `building_levels` entry against the raw JSON.
9. Existing GUT suite passes unmodified.
10. BUILT green and the full GUT suite green.
11. `verifier` re-runs both commands independently and confirms the save-key change round-trips
    on real disk — mandatory, not optional.

### Files allowed to change
`systems/game_session.gd` · `hub/hub.gd` · `hub/hub.tscn` · `tests/unit/test_buildings.gd` (new) ·
`tests/save_roundtrip_check.gd`

### Non-goals
- Any building's bonus actually applying to gameplay — `P2-07c`/`P2-07d`/`P2-07e`.
- Training Hall and Reliquary buttons — indices reserved, unreachable through this UI.
- Gold, in any form — struck from `SYSTEMS.md` entirely.
- A generic `Building` Resource/definition type, a build queue, timers, or construction animation.
- Renaming `summoning_circle_level_cap` to a more general name.

### Findings

**The ticket's hardest criterion passed first time, and the reason is worth keeping.** Criterion 8
(real-disk round-trip, not an in-memory `to_dict`/`from_dict` pair) had been shipped wrong twice
before — `P2-05a` and `P2-04e` both took the shortcut and both were reopened. Writing the failure
history *into the criterion itself* rather than leaving it in the two archived Findings is what
changed: the implementer had the trap in front of it at the point of decision instead of two
tickets back in an archive nobody re-reads. Cheap to do, and it is the only criterion here with a
100% prior failure rate.

**A `%APPDATA%` collision blocks running gates in parallel, and it is not obvious from the script.**
`tests/import_gate.ps1:29` sets `$env:APPDATA = [System.IO.Path]::GetTempPath()` — the *shared*
system temp path. Two engine runs against two different checkouts therefore land on the **same**
`user://save.json`, so parallel gate runs corrupt each other's save state while both report
plausibly. The gate's own stray-process guard does not catch it: that guard matches on
`ExecutablePath` under *this checkout's* `tools/godot`, so a second worktree reaching the engine
through a junction resolves to a different path string and the two runs never see each other. The
fix at the call site is one line — set `$env:TMP`/`$env:TEMP` (which `GetTempPath()` reads) to a
per-checkout directory before invoking the gate. **This belongs in `KNOWN_ISSUES.md` § Environment,
which `godot-tester` owns**; recorded here because it was found by the director during a parallel
wave and a finding stranded in a return block is ephemeral.

**Layout latitude, exercised and worth naming.** `BuildingsPanel` stacks three `Label`s then three
`Button`s as separate `VBoxContainer` children rather than pairing each into an `HBoxContainer`
row, so criterion 5's "one row per building" renders as six stacked items. The `verifier` raised it
and then downgraded it to cosmetic after cross-checking: this matches `EquipmentPanel`'s own
existing convention (stacked list, then stacked buttons, no per-action pairing container). Recorded
because the *next* panel ticket will face the same choice, and the codebase now has a precedent
rather than an accident.

**Verified.** BUILT exit 0, zero `SCRIPT ERROR`/`ERROR:`/`WARNING`. GUT 9 scripts, 71/71, 9511
asserts, exit 0 (was 8 scripts / 67 tests — `test_buildings.gd` is the new one).
`tests/save_roundtrip_check.gd` exit 0 with `building_levels` asserted against raw JSON off disk.
Run independently three times — implementer, `verifier`, and the director — with matching counts.
The suite's `ERROR:` lines are pre-existing deliberate `push_error` fixtures (missing `def_id`,
invalid save), confirmed against the pre-change commit via `git stash`. `Get-Process Godot*` empty
after every run.

**Not verified.** No pre-`P2-07b` save JSON fixture (one genuinely lacking a `building_levels` key)
was constructed and loaded — the "legacy save defaults to all-zero" claim rests on tracing
`_array_field` and `mini`, not on an executed legacy round-trip. The new decode branch was not
fuzzed beyond the shape the ticket specifies (no NaN/Infinity/string entries), on the grounds that
it is byte-structurally identical to the already-shipped `parts` guard. No windowed run, so the
panel's appearance is unproven.

### Files changed
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `tests/unit/test_buildings.gd` (new),
`tests/save_roundtrip_check.gd`

---

## P2-07d — Forge level raises the enhance cap and the salvage yield      [DONE]

Director-written per the backlog row (rung 1: prose is not delegated). Closes the `P2-07` group.

### Objective

A player who upgrades the Forge can enhance items further and gets more parts back when
salvaging. Both of the Forge's authored-but-unread magnitudes become live.

### Existing architecture

1. `GameSession.building_levels` is `Array[int]` of 5, persisted, **Forge is index 1**
   (`hub/hub.gd:112` is the only place the mapping is written down; Circle 0, Forge 1, Sanctum 3).
   `P2-07b` shipped it, `P2-07c`/`e` already read indices 0 and 3.
2. `salvage_item(item, balance)` and `enhance_item(item, balance)` are methods on the
   `GameSession` autoload (`systems/game_session.gd:59,72`). They already take `balance`
   explicitly (`P2-05f`'s correction) and `building_levels` is the autoload's own state, so
   **neither needs a signature change** — this is the distinction `P2-05f`'s Findings drew.
3. The cap is currently read as flat `balance.forge_enhance_cap_max` (15) in **four** places:
   `enhance_item` (lines 75-76), `salvage_item`'s `enhance_level` clamp (line 67), and twice in
   `hub/hub.gd:315-317`. The flat reading was `P2-05e`'s deliberate interim
   (`SYSTEMS.md` § Enhancement question 3) because no building had a level. One now does.
4. **`hub/hub.gd` re-derives both formulas for its own status text** — `_on_salvage_pressed`
   recomputes the yield at line 302, `_on_enhance_pressed` recomputes the cap check at 315-317
   before calling through. This is `P2-07e`'s preview-equals-payout trap, twice: a wrong value
   here is invisible to the import gate.
5. `BalanceTable` already authors everything needed: `forge_enhance_cap_per_level = 3`,
   `forge_enhance_cap_max = 15`, `forge_salvage_yield_bonus = 0.10`. **No new field, no
   `balance.tres` change.** The level cap for all five buildings is `summoning_circle_level_cap`
   (5) — the existing shared name, however odd it reads for the Forge.

### The two formulas — ruled, not open

`SYSTEMS.md` § Enhancement q3 and § "Forge salvage-yield bonus":

```
cap(forge_level)   = mini(forge_enhance_cap_max, forge_level * forge_enhance_cap_per_level)
yield(forge_level) = roundi((3 + enhance_level) * (1.0 + forge_salvage_yield_bonus * forge_level))
```

Two things are **part of the ruling, not implementation detail**:

- **`roundi()`, never `int()`.** Truncation yields zero extra parts on an unenhanced item for
  Forge levels 1-3 — the commonest salvage case there is. The dead-bonus trap this repo has now
  hit four times.
- **An unbuilt Forge caps enhancement at 0, so enhancement is unavailable until Forge level 1.**
  That is the intended gate, not a bug to route around. `SYSTEMS.md:807-811` names this exact
  consequence and shipped flat-15 only because no Forge level existed to build. Do **not**
  preserve flat 15 as a floor.

`forge_level` is read as `clampi(GameSession.building_levels[1], 0, balance.summoning_circle_level_cap)`
everywhere, matching `sacrifice_hero:124` — a corrupt saved level must clamp, not index off the
authored ladder.

### Acceptance criteria

1. `salvage_item` credits `roundi((3 + enhance_level) * (1.0 + 0.10 * forge_level))` parts of the
   item's rank. Checked at Forge 0 (unenhanced item → 3, unchanged from today), Forge 2
   (unenhanced → 4, the level `roundi()` exists to rescue), and Forge 5 with `enhance_level = 4`
   (`7 * 1.5 = 10.5 → 11`).
2. `enhance_item` refuses at `mini(15, forge_level * 3)` and writes nothing when it refuses —
   parts unchanged, `enhance_level` unchanged. Checked at Forge 0 (refuses a fresh item outright),
   Forge 1 (succeeds three times, refuses the fourth), and Forge 5 (cap 15, today's behavior).
3. `salvage_item`'s own `enhance_level` clamp still uses `forge_enhance_cap_max` (15), **not** the
   forge-scaled cap: an item enhanced at Forge 5 and salvaged after the Forge is somehow lower must
   still credit the levels it actually has. Only `enhance_item`'s gate scales.
4. A corrupt `building_levels[1]` (e.g. `999`) clamps to 5 in both paths — no crash, no
   out-of-ladder yield.

---

## P2-18 — A wiped roster always affords one more pull                        [DONE]

### Objective
A player whose last hero dies with fewer than one pull's worth of stones can still summon.
Before this, that save was unplayable forever: no hero means no expedition, no expedition means
no stones, and no stones means no hero.

### Existing architecture
- `GameSession.summon_hero()` (`systems/game_session.gd:35`) refuses below
  `balance.summon_pull_cost` and is the only priced path into `roster`.
- `GameSession.credit_stones()` has exactly **one** production caller,
  `hub/expedition/expedition.gd:83`, reached only on `OUTCOME_COMPLETED` — which needs a hero.
  So `roster.is_empty() and stones < summon_pull_cost` is terminal.
- `GameSession.kill_hero()` (`systems/game_session.gd:174`) is permadeath's sole call site
  (`ARCHITECTURE.md` r8). Its two production callers — `expedition.gd:64` and `sacrifice_hero()`
  at `game_session.gd:156` — **both already hold a `balance` in scope**, so threading it in is a
  signature change over an existing value, not a new dependency. `sacrifice_hero()` can never
  reach the guard anyway: it requires `fodder != target` with both in the roster, so it cannot
  empty it.
- Autoloads may not hold a shared Resource (`ARCHITECTURE.md` § "Reaching shared Resources",
  and `P2-05f`'s Findings), so `GameSession` cannot `preload("res://balance.tres")` to get the
  cost. It arrives as an argument or not at all.
- The ruling is `SYSTEMS.md` § Roster-wipe recovery floor (`P2-18`).

### Acceptance criteria
1. `kill_hero(hero: Hero, zone_id: StringName, balance: BalanceTable)` — `balance` required, not
   defaulted. `P2-07e` versus `P2-07c`: a required parameter makes a forgotten argument a compile
   error, a defaulted one makes it a silently-wrong result with a green gate.
2. Immediately after `roster.erase(hero)`: if `roster.is_empty() and stones < balance.summon_pull_cost`
   then `stones = balance.summon_pull_cost`. An **assignment**, not `+=` — the guard only fires when
   `stones` is already below the cost. Read `summon_pull_cost` live; no `100` literal.
3. Nothing else is granted — no hero, no essence, no item, no parts. The dead hero's gear still
   goes to a `LostCache` exactly as today.
4. A wipe that leaves `stones >= summon_pull_cost` changes `stones` by nothing.
5. A death leaving a non-empty roster changes `stones` by nothing, however low the balance.
6. `tests/save_roundtrip_check.gd` reaches `kill_hero` through `.call()`, so **the import gate
   cannot catch the arity break** — this is `P2-04e`'s trap verbatim. Grep `kill_hero` across
   `*.gd` for `.call(`/`callv(`/`Callable(` forms as well as direct calls before declaring done.
7. New GUT coverage in `tests/unit/test_expedition.gd`: last hero dies below cost → `stones ==
   BALANCE.summon_pull_cost`; last hero dies at or above cost → unchanged; a hero dies leaving one
   alive with `stones == 0` → still `0`.
8. The top-up survives save and reload. `kill_hero()` already ends in `roster_changed.emit()`,
   which is the only thing that writes the save — so do **not** add an explicit `SaveService.save()`
   to the test, or a dropped emit passes anyway (`P2-05g`'s Findings).
9. BUILT green — import gate with zero errors *and* zero warnings, plus the full GUT suite.

### Files allowed to change
`systems/game_session.gd` · `hub/expedition/expedition.gd` · `tests/save_roundtrip_check.gd` ·
`tests/unit/test_expedition.gd` · `tests/unit/test_equipment.gd`

`tests/unit/test_equipment.gd` was **missing from this list on the first dispatch** and the worker
blocked on it — it holds three direct `kill_hero` calls (`:248`, `:272`, `:288`) covering the
`LostCache` branch. That is `P2-04g`'s omitted-file defect a second time, and the lesson repeats:
grep the symbol before writing the list, do not reason about which files "should" call it. These
three are static calls, so unlike criterion 6's dynamic one the import gate *would* have caught
them — as a red gate on a ticket that was otherwise finished.

### Non-goals
- **The ruling's `from_dict()` leg is deliberately cut.** It exists to rescue a save that reached
  the dead state before this ships, and no such save exists — nobody is playing this build. Adding
  it would put a new write into the save-decode path (`CLAUDE.md` boundary 1) and make a `verifier`
  pass mandatory, to fix a hypothetical file. With it cut this ticket crosses no risky boundary.
  If a real stuck save ever turns up, delete it; that is cheaper than the branch.
- No toast, banner, or notification. None exists in this codebase, and the stones readout already
  refreshes on `roster_changed`. If a played build shows the jump reads as a bug, that is its own
  ticket.
- No change to `STARTING_STONES`, `summon_pull_cost`, or any zone's `stone_reward`.
- Do not generalize this into a "recover from any dead state" system. One conjunction, one guard.
- Do not touch `P2-19`'s `fodder.level` term while you are in `game_session.gd`.

### Findings

**The design ruling asked for more than the problem needed, and the extra half was the risky
half.** `SYSTEMS.md` § Roster-wipe recovery floor specifies the same guard twice — in `kill_hero()`
and again in `from_dict()` — the second to rescue a save that reached the dead state before this
shipped. No such save exists; this game has no players. Cutting that leg removed a new write from
the save-decode path, which is `CLAUDE.md` boundary 1, and with it the mandatory `verifier` pass.
The shipped ticket touches **no risky boundary at all**, and the whole production diff is six lines.
A ruling is an answer to a design question, not an implementation plan — the parts of it that are
speculative are still speculative, and a ticket is allowed to say so in its non-goals.

**The `kill_hero` dynamic-caller trap did not bite, and that is the reusable part.** `P2-04e`
recorded that `tests/save_roundtrip_check.gd` reaches permadeath through `.call()`, where an arity
break survives a green import gate. This ticket wrote that trap into criterion 6 *by name and file*
rather than leaving it in the archive, and it became a non-event. Same mechanism as `P2-07b`'s
disk-round-trip criterion: **a failure history written into the criterion is in front of the
implementer at the point of decision; the same history in `TASKS-DONE.md` is not.**

**Grep the symbol before writing the allowed-file list.** Three of six `kill_hero` call sites live
in `tests/unit/test_equipment.gd`, which the first dispatch's list omitted — `P2-04g`'s defect
repeated one ticket later. The worker blocked instead of working around it, which was correct. Note
the asymmetry the incident exposes: those three are *static* calls the import gate would have
caught, so the omission cost a round trip. The genuinely dangerous site was the single dynamic one,
which no gate catches — and the two failure modes want the same countermeasure, one grep across all
call forms.

**`sacrifice_hero()` can never reach the guard**, and that was worth proving before writing it:
it requires `fodder != target` with both already in the roster, so it cannot empty one. The floor
therefore has exactly one live trigger — the expedition wipe — despite sitting at the shared seam.
Placing it at `kill_hero()` anyway is what makes that a fact about the callers rather than a
discipline future callers must remember.

Gates, director-run: import gate exit `0` clean · GUT `96/96`, 9,647 asserts · standalone
`save_roundtrip_check.gd` PASS.
5. `hub/hub.gd`'s salvage status text reports the same number `salvage_item` credited, and its
   enhance precondition uses the same cap `enhance_item` enforces, at a nonzero Forge level.
   Drive the real scene; a unit call on `GameSession` alone does not prove this.
6. Survives save and reload: upgrade the Forge, quit, reload, salvage — the bonus still applies.
   **Real disk round-trip via `SaveService`, not an in-memory `to_dict`/`from_dict` pair**
   (`P2-05a` and `P2-04e` were both reopened for exactly that shortcut).
7. Existing tests still pass. **Expect this to require edits, not to pass untouched:**
   `tests/unit/test_equipment.gd`'s `before_each` resets `building_levels` to all-zero, so
   `test_enhance_uses_the_cost_ladder` and `test_enhance_refuses_at_cap_without_writing` currently
   enhance against an unbuilt Forge and **will fail** under criterion 2. Set the Forge level in
   those tests rather than weakening the gate. `tests/save_roundtrip_check.gd:191`'s salvage runs
   at Forge 0 and is unaffected.
8. BUILT green — import gate **and** the GUT suite.

### Non-goals

- No new `BalanceTable` field and no `balance.tres` edit — all three numbers are authored.
- No signature change on `salvage_item`/`enhance_item`. The level is the autoload's own state.
- Not `P2-12`: leave the arithmetic on `GameSession` where it already lives.
- No Training Hall or Reliquary wiring — `P2-07a` scoped buildings to three.
- No tooltip or UI surfacing the bonus.

### Findings

**Two caps live in one file and that is correct, not a bug.** `salvage_item` clamps
`enhance_level` against the flat `forge_enhance_cap_max` (15) while `enhance_item` gates against
the forge-scaled `mini(15, forge_level * 3)`. They read like a missed edit sitting eight lines
apart. Criterion 3 pinned the distinction deliberately: the scaled value is a *gate on gaining a
level*, the flat one is a *ceiling on trusting a level an item already has*. Scaling the salvage
clamp too would silently confiscate enhancement a player paid for whenever the two disagree —
which a corrupt saved level is enough to cause. Anyone tidying these into one constant should
expect criterion 3's test to catch them.

**The unbuilt-Forge gate needed one line of prose the ticket did not ask for.** With the cap wired,
a fresh save cannot enhance at all until the Forge reaches level 1 — that is the ruling working as
designed (`SYSTEMS.md:807-811`), but the existing refusal message rendered it as *"Cannot enhance:
item is already at the +0 cap."*, which describes the item rather than the missing building and is
the very first thing a new player hits. Fixed inline as an `enhance_cap <= 0` branch reading "build
the Forge first" (director, rung 1, 3 lines). It is not the tooltip the non-goals excluded — the
refusal path already existed and was simply saying something untrue about why it fired.

**A ruled rounding function is worth more in the ticket than in the ruling.** `roundi()` versus
`int()` is invisible at review: both compile, both look right, and the difference only shows up as
three of five building levels quietly doing nothing. `SYSTEMS.md` had already ruled it, but
restating it inside the acceptance criteria as "part of the ruling, not implementation detail" is
what made it unskippable — the same technique `P2-07b` used when it wrote its own failure history
into criterion 8.

**Test-breakage was predicted in the ticket and that changed how it was received.** Criterion 7
named the two tests that would fail and why (`before_each` zeroes `building_levels`), so the
implementer treated a red suite as expected work rather than as evidence the change was wrong. A
ticket that knows which of its own tests it breaks costs one paragraph to write and saves a
diagnostic round-trip.

**The new hub-scene test reaches its buttons by absolute node path**
(`UI/Root/EquipmentPanel/Columns/Inventory/Salvage`), not by `%UniqueName`, because those two
buttons have no unique name in `hub.tscn`. That is a scene↔script seam with no compile-time
protection: re-parenting the Inventory column reddens `test_buildings.gd` with a null node rather
than a useful message. Giving them unique names is a one-line `.tscn` change nobody has needed yet.

**Verified by re-run, not by relay.** Import gate exit 0, zero `SCRIPT ERROR`/`ERROR:`/`WARNING`.
GUT 11 scripts, 81/81, 9557 asserts, exit 0 — run by the implementer and again by the director
after the refusal-message fix, matching counts both times. `tests/save_roundtrip_check.gd` exit 0
under a redirected `%APPDATA%`, reporting `buildings, Forge salvage yield, ...` — the Forge is
upgraded to level 2 through the real `upgrade_building`, saved, reloaded from disk, and salvaged
after the reload, so criterion 6 rests on an executed disk cycle rather than a `to_dict`/`from_dict`
pair. `Get-Process Godot*` empty after every run. The suite's `ERROR:` lines are pre-existing
deliberate `push_error` fixtures.

**Not verified.** No windowed run — the refusal message's new branch is proven by reading the
handler and by the cap arithmetic under test, not by a human seeing it on screen. The
`PROVISIONAL` marker on the salvage bonus is untouched and still open: whether `+0` to `+2` extra
parts per salvage is *felt* needs a played build, which is what its `Settled by` asks for.

### Files changed
`systems/game_session.gd`, `hub/hub.gd`, `tests/unit/test_equipment.gd`,
`tests/unit/test_buildings.gd`, `tests/save_roundtrip_check.gd`

---

## P2-16 — Pulls cost Summon Stones, and a clear pays them                   [DONE]

### Objective

Pressing **Summon** spends `100` Summon Stones. Below that the button is disabled and the pull
refuses. Clearing a zone pays stones back — `25`/`75`/`200` for Verdant/Ashfall/Sundered — and the
balance is visible in the hub and survives a quit and relaunch. A fresh save starts at `300`.

The ruling is `SYSTEMS.md` § Summon Stones — cost and income; its §5 table says where each number
lives. This ticket wired it and authored nothing new.

### Existing architecture

1. **`Summon.roll()` cannot do the deduction.** It is a `static func` on a plain `RefCounted`
   (`hub/summon/summon.gd:13`) with no autoload access — the same constraint `P2-07c` hit, which is
   why `hub.gd` reads the Circle level and passes it in. Its only production call site is
   `hub/hub.gd:220-223`. Signature frozen; `tests/summon_def_id_roundtrip_check.gd` calls it out of
   scope, and `P2-07c`'s defaulted argument is already on the record as a trap.
2. **`enhance_item` (`systems/game_session.gd:73-88`) is the shape to mirror**: validate → `return
   false` → deduct → `roster_changed.emit()`. Callers branch on the bool and write their own
   message. `upgrade_building` and `rank_up_hero` are the same shape.
3. **The clear branch already pays one reward.** `Expedition.resolve()` reaches
   `hub/expedition/expedition.gd:64-67` only on `OUTCOME_COMPLETED`. Stones ride that same branch —
   `RETREATED` and `DEFEATED` return earlier and pay nothing, no second condition needed.
4. **The hub already has a currency readout pattern.** `%Essence` + `_refresh_essence()`
   (`hub/hub.gd:14,87-88`), connected to `roster_changed` in `_ready`. Stones copy it.
5. **`roster_changed.emit()` is what writes the save** (`systems/game_session.gd:22`). A mutation
   without it round-trips green in memory and loses the value on disk — `P2-05g`'s finding.
6. **`Item.int_field`** (used for `essence`) is the untrusted-int reader: it absorbs the JSON
   `float` decode and an explicit `null`. Both defects are on the record (`P2-05f`, `P2-11`).

### Acceptance criteria

1. `BalanceTable.summon_pull_cost: int = 100` in `balance_table.gd` **and** authored in
   `balance.tres`. `tests/balance_table_check.gd` still passes.
2. `ZoneDefinition.stone_reward: int = 0`, and the three `zones/defs/*.tres` carry `25`/`75`/`200`.
   `tests/zone_definition_check.gd` still passes — it asserts zone fields by **exact match**, which
   is what reddened `P2-15`.
3. `GameSession.stones: int = 300`, persisted through `to_dict`/`from_dict`.
4. Summon with `stones >= 100` adds a hero and leaves the balance exactly `100` lower. With
   `stones < 100` **no hero is added, nothing is deducted**, and `_status` names the shortfall.
5. The Summon button is `disabled` while `stones < summon_pull_cost`, refreshed on
   `roster_changed`, and a stone balance is visible in the hub alongside Essence.
6. A `COMPLETED` expedition credits that zone's `stone_reward`; `RETREATED` and `DEFEATED` credit
   zero. Tested at all three outcomes.
7. **Real-disk round trip, not in-memory `to_dict`/`from_dict`**, plus the three untrusted shapes:
   missing `stones` key → `300`, explicit `"stones": null` → no crash, `300.0` → `300`.
8. Import gate green with zero warnings, GUT suite green.

### Files allowed to change

`balance_table.gd`, `balance.tres`, `zones/zone_definition.gd`, `zones/defs/*.tres`,
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `hub/expedition/expedition.gd`,
`tests/save_roundtrip_check.gd`, `tests/zone_definition_check.gd`,
`tests/unit/test_expedition.gd`, `tests/unit/test_summon.gd`.

### Non-goals

No second income source, no multi-pull/pity/rank-scaled price, no shop or currency conversion, no
change to `Summon.roll()`'s signature, no starting-hero grant.

### Findings

**`add_hero` is now a test-only seam, and nothing enforces that.** The priced path is
`GameSession.summon_hero(hero, balance)`; `add_hero` survives with **zero production call sites**
and 17 test ones. It is a legitimate fixture — a test should not have to fund a roster — but it is
also an unpriced door into `roster` that no gate guards. Any future production caller of `add_hero`
summons for free and every gate stays green. This is the `P2-07c` `roll()`-default hazard in a new
shape: grep call sites rather than trusting that the priced path is the only path.

**The refill trap was real and the code clears it.** `from_dict` resets `stones = STARTING_STONES`
before reading, which looks like it should refill a spent-out save to `300` on every load. It does
not, because `Item.int_field` returns an explicit `0` correctly and falls back only on a
missing/null/non-numeric field — so a player who spent everything reloads at `0`, not topped up.
That distinction is the whole reason criterion 7 named all three untrusted shapes separately
instead of asking for "a round trip": a default that is also a legitimate value cannot be checked
by the presence of the value alone.

**`300` shipped as three literals and was consolidated to one.** The field initializer, the
`from_dict` reset, and `int_field`'s default each carried a bare `300` — three places that must
agree, with nothing to notice if they drift. Now `GameSession.STARTING_STONES`. Director fix-up on
an accepted diff, four lines. Worth flagging in the ticket template: a value that appears in both
an initializer and a deserializer default is always at least two literals, and the reset path makes
it three.

**Verified by re-run, not by relay.** Import gate exit 0, zero `SCRIPT ERROR`/`ERROR:`/`WARNING` —
run by the director after the `STARTING_STONES` edit, not before it. GUT 11 scripts, 87/87, 9583
asserts, exit 0, same run. `tests/save_roundtrip_check.gd` exit 0 under a redirected `%APPDATA%`,
driving a real paid-summon → save → reload → clear-credit → save → reload sequence landing at `200`
then `275` on disk. The mandatory `verifier` pass returned **pass** on all 8 criteria and retracted
one Codex-raised MEDIUM (the disk test's explicit `save()` calls) after establishing it is the
file's convention for every other currency field and that the emit is independently pinned by
`assert_signal_emit_count` in `tests/unit/test_summon.gd`. `Get-Process Godot*` empty after every
run.

**Not verified.** No windowed run — the disabled-button state and the shortfall message are proven
by scene-instantiating GUT tests and by reading the handler, not by a human seeing them. And the
thing this ticket most wants known is not checkable at a desk at all: whether `100` per pull
against `25`/`75`/`200` per clear *feels* like an economy or like a toll booth. That is the Phase 2
exit question, and it needs a played build.

### Files changed
`balance_table.gd`, `balance.tres`, `zones/zone_definition.gd`, `zones/defs/*.tres` (3),
`systems/game_session.gd`, `hub/hub.gd`, `hub/hub.tscn`, `hub/expedition/expedition.gd`,
`tests/save_roundtrip_check.gd`, `tests/zone_definition_check.gd`,
`tests/unit/test_expedition.gd`, `tests/unit/test_summon.gd`

## P2-08 — A save survives a reload with items still in the bag and zones still cleared  [DONE]

### Objective
The two persisted `GameSession` fields that have never been proven to survive a real disk cycle —
`inventory` and `cleared_zone_ids` — do survive one, and `SaveService.load_game()`'s three refusal
branches are pinned, so a corrupt or newer-version save is refused *without* silently resetting
the profile it refused to read.

### Existing architecture
- `GameSession.to_dict/from_dict` (`systems/game_session.gd:179-258`) persists eight keys. Six
  already have a disk-level check in `tests/save_roundtrip_check.gd`: `roster`, `parts`,
  `building_levels`, `essence`, `stones`, `lost_caches`.
- `inventory` and `cleared_zone_ids` are covered **only in memory** (`tests/unit/test_item.gd:24`,
  `tests/unit/test_expedition.gd:87-118`) — the exact shortcut `P2-05a` and `P2-04e` were both
  reopened for. Every existing disk check that touches an `Item` either salvages it or equips it,
  so no item has ever been observed sitting in `inventory` across a reload.
- `cleared_zone_ids` gates zone unlocks (`hub.gd.is_zone_unlocked`) and the Summon Stone clear
  payout (`P2-16`). Losing it relocks zones a player already beat.
- `SaveService.load_game()` (`systems/save_service.gd:21-45`) has three `return false` branches —
  no file, non-`Dictionary` top level, `version > SAVE_VERSION` — and none is exercised anywhere.
  A refusal leaves `GameSession` at its constructor defaults, and `_ready()` then connects
  `roster_changed` to `save`, so **the next mutation overwrites the file that was refused.**
- `tests/save_roundtrip_check.gd` is a `SceneTree` `-s` harness that backs the real
  `user://save.json` up and restores it byte-identically. It already has fixture writers and a
  `_fail(name, expected, actual)` reporter; follow that shape rather than inventing one.
- GUT files under `tests/unit/` write to the **real** `user://save.json` (`test_item.gd:71`) and
  none of them restores it. The new file must not inherit that.

### Acceptance criteria
1. An `Item` added to `inventory` and **left there** survives `save()` → clear → `load_game()`
   with `def_id`, `rank` and `enhance_level` intact, and the raw JSON's `inventory` array is
   asserted directly — decoding the object back is not sufficient evidence (`P2-05a`: `slot`
   reaches disk as `8.0`, and only the raw leg sees the float branch).
2. Two zones marked cleared survive the same cycle: the raw JSON `cleared_zone_ids` carries both
   ids as `String`, and `GameSession.cleared_zone_ids` has both as `StringName` after reload.
3. A save whose top level is not a Dictionary is refused — `load_game() == false` — and `roster`,
   `inventory`, `parts`, `stones` and `cleared_zone_ids` are left **exactly** as they were before
   the call, not reset to defaults.
4. A save carrying `"version": SAVE_VERSION + 1` is refused the same way, state untouched.
5. With no save file present, `load_game()` returns `false` and pushes no error.
6. The new GUT file backs up `user://save.json` in `before_all` and restores it byte-identically
   in `after_all`, including the case where no save existed to begin with.
7. `tests/save_roundtrip_check.gd` still restores the original `user://save.json` byte-identically.
8. Existing tests still pass: import gate clean, full GUT suite green.

### Files allowed to change
- `tests/save_roundtrip_check.gd`
- `tests/unit/test_save_service.gd` (new)

### Non-goals
- **No production code changes.** If a criterion fails, report it — do not repair
  `game_session.gd` or `save_service.gd` under this ticket. A failing criterion here is the
  finding, and it is worth more than a green run.
- No save migration, no `SAVE_VERSION` bump — `save_service.gd:35-37` reserves that for Phase 5.
- No new `-s` harness. Criteria 3–5 go in GUT, which has `assert_push_error`; the `-s` harness
  has no way to expect an error line and a stray one there reads as a failure.

### Findings

**All eight criteria passed and no production code changed.** That is the honest headline: the two
untested keys were untested, not broken. `inventory` and `cleared_zone_ids` both round-trip
correctly through JSON, raw and decoded, and all three refusal branches behave as written. The
ticket's value is that this is now checked rather than assumed — six of eight persisted keys had
disk coverage and two did not, and nothing in the gate could tell the difference.

**A refused save gets overwritten by the first thing the player does.** The tests pin that a
refusal leaves `GameSession` *untouched*; they do not, and cannot, stop what happens next. At boot
`_ready()` calls `load_game()`, and on refusal the session sits at constructor defaults — empty
roster, `STARTING_STONES` — and then `roster_changed` is connected to `SaveService.save`. The first
summon, expedition or upgrade writes a fresh profile over the file that was refused. A player who
runs a downgraded build once loses the save the version check existed to protect. Filed as
`P2-17`; deliberately not fixed here, because the fix is a design call (refuse to boot? rename the
file aside? read-only session?) and not an implementer's to invent.

**`test_save_service.gd` is the first GUT file that does not eat the real save.** Every other file
under `tests/unit/` calls `GameSession.from_dict(...)` in `before_each`, whose emission reaches
`SaveService.save`, and none restores anything (`KNOWN_ISSUES.md` § Environment). This one ports
`save_roundtrip_check.gd`'s `_backup_save`/`_restore_save` into `before_all`/`after_all`, including
the no-save-existed case. Verified by measurement, not by reading: a sentinel `save.json` written
under a scratch `%APPDATA%` came back **SHA-256 identical** after a `-gtest=` run of this file
alone. The suite-wide problem is untouched — the other eleven files still stomp it, which is why
the redirected-`%APPDATA%` invocation stays mandatory.

**Ordering inside the `-s` harness is load-bearing and undeclared.** `_check_inventory_round_trip`
asserts the raw `inventory` array has exactly one entry, which only holds because every earlier
check that touches an `Item` either salvages it or equips it back out. The checks run in a fixed
sequence from `_run()` and share one `GameSession`; inserting a new check that leaves an item
behind reddens a later one for reasons its own name does not explain. Read the whole `_run()`
sequence before adding to that file, not just the neighbouring function.

**Verified by re-run, not by relay.** Import gate exit 0, zero `SCRIPT ERROR`/`ERROR:`/`WARNING`.
GUT 12 scripts, 90/90, 9618 asserts, exit 0 under redirected `%APPDATA%` — 87 before this ticket,
plus the three new refusal tests. `tests/save_roundtrip_check.gd` exit 0, PASS line naming
inventory and cleared zones. The single `ERROR:` line in that run is the deliberate
`def_id: null` fixture in `_check_malformed_def_id`, pre-existing and unrelated. No `verifier` pass
was dispatched: the diff is tests-only and crosses no boundary, and the director re-ran every
acceptance-critical command directly. `Get-Process Godot*` empty after every run.

**Not verified.** Nothing here was seen by a human in a window, and nothing needed to be — every
criterion is a disk or return-value assertion. The `P2-17` overwrite path is described from
reading `_ready()`, not reproduced; reproducing it needs a real quit-and-relaunch, which is the
Phase 1 exit-gate shape and not a headless run.

### Files changed
`tests/save_roundtrip_check.gd`, `tests/unit/test_save_service.gd` (new)

---

## P2-04g — A hero levels up from expeditions                                  [DONE]

### Objective
Sending a hero on an expedition raises its level, and the hub shows the level and the XP toward
the next one. Written by the director per rung 1 — `SYSTEMS.md` § Hero leveling names every
field, every file, every constant and the grant-path shape, so no scoping judgment was left to
route (the `P2-16` precedent).

### Existing architecture
- `Hero` has no `level` and no `xp`. `Hero.level_for(hero, balance)` (`heroes/hero.gd:33-34`)
  returns `balance.level_caps[clampi(hero.rank, 0, 7)]` — a derivation, so every hero is
  permanently at its rank's cap. Two call sites: `combat/quick_resolve.gd:21`, `hub/hub.gd:160`.
- `Expedition.resolve()` (`hub/expedition/expedition.gd:19-67`) already counts `waves_resolved`
  (public, incremented per wave) and already credits the `COMPLETED` rewards *inside* itself —
  `mark_zone_cleared`, `add_item`, `credit_stones(zone.stone_reward)`. The XP grant belongs in
  the same place, not in `hub.gd`.
- `resolve()` has four returns: `OUTCOME_INVALID_TEAM` (before any wave, `waves_resolved == 0`),
  `OUTCOME_DEFEATED`, `OUTCOME_RETREATED`, `OUTCOME_COMPLETED`.
- `GameSession.credit_stones()` (`systems/game_session.gd:44-46`) is the shape to mirror: mutate,
  then `roster_changed.emit()`. That emit is what triggers the save (`_ready()` connects it).
- `building_levels` (`systems/game_session.gd:17`) is a 5-element array; **Training Hall is index
  2** (`0` Circle, `1` Forge, `3` Sanctum). It is not buildable — `P2-07a` scoped the panel to
  three — so the multiplier is `1.0` in normal play and only a test that writes
  `building_levels[2]` directly exercises it. That is the `P2-07c`/`d`/`e` shape, not the
  fabricated-field shape `turn_lost` and `enhance_level` were rejected for: it reads a real
  persisted field that a later ticket makes spendable.
- `%HeroDetail` (`hub/hub.gd:145-177`) is `P2-14`'s readout and already prints rank, seven stats,
  resonance and traits. This is where level becomes observable.

### Acceptance criteria
1. `Hero.level: int = 0` and `Hero.xp: int = 0` exist, and `Hero.level_for()` becomes
   `clampi(hero.level, 0, balance.level_caps[hero.rank])`.
2. **Save-boundary change** (`CLAUDE.md` boundary 1) — a **mandatory `verifier` pass**, and the
   round-trip must be a **real disk write and reload through `SaveService`**, not an in-memory
   `to_dict`/`from_dict` pair. That shortcut shipped and was reopened in `P2-05a` and `P2-04e`
   and passed first time in `P2-07b` only because the criterion said so; it says so here.
   Both fields must survive, and both must survive an explicit JSON `null` and a wrong-typed
   value without crashing the load path (`P2-11`, `_int_field()`).
3. `xp_coefficient: int = 10` and `xp_per_wave: int = 4` on `BalanceTable`/`balance.tres`;
   `xp_reward` on `ZoneDefinition` at `24`/`72`/`192` for Verdant/Ashfall/Sundered. Editing
   `zones/defs/*.tres` reddens `tests/zone_definition_check.gd`, which asserts zone fields by
   exact match — update it in the same commit (`P2-15`).
4. XP is granted inside `Expedition.resolve()`: `xp_per_wave * waves_resolved` on every outcome,
   plus `zone.xp_reward` on `COMPLETED` only. `INVALID_TEAM` needs no special case — it returns at
   `waves_resolved == 0`, so the arithmetic is already zero. Grant to every hero in `team`; heroes
   killed this run are already off the roster, so no filtering is needed.
5. Both amounts are multiplied by `1.0 + balance.training_hall_xp_bonus * clampi(building_levels[2],
   0, balance.summoning_circle_level_cap)` before being applied — the same clamp every other
   building consumer uses. A test that sets `building_levels[2] = 5` sees `xp_per_wave` land as
   exactly `7` and `xp_reward` as exactly `42`/`126`/`336`.
6. Applying XP loops level-ups while `xp >= xp_coefficient * (level + 1)` **and**
   `level < balance.level_caps[hero.rank]`, subtracting the cost each time. **Overflow at the cap
   is discarded, not banked** (ruled). Pure `static func`s on `Hero`, testable without booting
   `GameSession` — the `P2-06a` shape, not the `P2-12` debt shape.
7. `combat/quick_resolve.gd`'s `BASELINE_LEVEL` is **removed**, not tuned.
8. `%HeroDetail` gains a level line showing the level and progress toward the next
   (e.g. `Level: 3 (12/40 XP)`), and reads `Lv 10 (max)` or equivalent at the rank's cap.
9. A hero sent on one expedition has more XP afterwards than before, and this survives a real
   save and reload. Existing tests still pass; import gate and GUT suite both green.

### Files allowed to change
`heroes/hero.gd`, `hub/expedition/expedition.gd`, `hub/hub.gd`, `combat/quick_resolve.gd`,
`balance_table.gd`, `balance.tres`, `zones/zone_definition.gd`, `zones/defs/*.tres`,
`tests/zone_definition_check.gd`, `tests/save_roundtrip_check.gd`, `tests/unit/*.gd`.

### Non-goals
- **Do not retune `wave_damage_coefficient`/`wave_loss_damage_coefficient`.** The ruling measured a
  `53–70%` whole-run roster-wipe rate in Verdant and explicitly refused to fix it here; it is
  `P2-03b`'s and predates this ticket.
- **Do not add a stones or hero-count floor** — that is `P2-18`.
- **Do not wire the Sacrifice formula's `fodder.level` term** — that is `P2-19`.
- Do not make the Training Hall buildable, and do not add it to the `P2-07b` upgrade panel.
- No XP bar, no level-up animation, no notification. A line of text in `%HeroDetail` is the whole

### Findings

**Criterion 7 was already satisfied before the ticket was written.** `BASELINE_LEVEL` no longer
existed in `combat/quick_resolve.gd` — an earlier team-size dispatch had already removed it, and
line 21 already read `Hero.level_for(hero, BALANCE)`. `quick_resolve.gd` is the one file in the
allowed list that ended up with a zero-line diff. `SYSTEMS.md`'s closing table still listed the
constant as live, which is how the ticket inherited it. **Check the code, not the ruling's table,
before writing a "remove X" criterion** — a criterion that is already met costs an implementer a
detour to prove a negative.

**Criterion 1 as written would have crashed on a corrupt save.** It specified
`clampi(hero.level, 0, balance.level_caps[hero.rank])`, which indexes `level_caps` with an
unclamped `rank` — the exact out-of-range access the old derivation had guarded against, and which
`tests/unit/test_hero_stats.gd:12-13` deliberately exercises. Shipped as
`clampi(hero.level, 0, balance.level_caps[clampi(hero.rank, 0, balance.level_caps.size() - 1)])`.
The inner clamp was not a nicety in the old code and dropping it was a transcription loss, not a
decision. This is the second ticket in a row (`P2-05f` was the first) whose criterion specified a
*signature* that could not be satisfied as written; no gate can catch that class of defect.

**`systems/game_session.gd` was missing from the allowed-files list, and that omission was
load-bearing.** `OUTCOME_RETREATED` returns from `Expedition.resolve()` without any
`roster_changed.emit()` — the signal that triggers the save. Granting XP inside `resolve()` with no
emit on that path would have mutated the roster and never reached disk, and **retreat is the common
outcome for a climbing hero** (the ruling's own table: `30.2%` at level 0, `46.4%` at F's cap,
against `0–0.5%` completed). The whole point of the curve is that a retreat still banks progress.
Fixed by adding `GameSession.credit_team_xp(team, amount, balance)` mirroring `credit_stones()`
— which is what `SYSTEMS.md` § Hero leveling had specified in its closing paragraph all along, and
which the ticket's file list silently contradicted. `balance` is an explicit parameter, not a
`preload` — an autoload must not reach a balance Resource directly (`ARCHITECTURE.md` § "Reaching
shared Resources", the `P2-05f` defect).

**The GUT suite went red for a reason that was not a regression, and the fix belongs in the
fixture.** `tests/unit/test_expedition.gd` hardcodes `HERO_POWER = 212.0` and
`HERO_MAX_HP = 280.0` — F-cap (level 10) Knight figures, true only while `level_for()` derived
level from rank. Its `_add_knight()` builds a rank-0 hero, which now computes at level 0. Setting
`hero.level = 10` in the factory keeps every arithmetic assertion in the file exact; retuning the
constants would have silently re-baselined the whole file against whatever the new numbers happened
to be. Same one-line fix in `tests/unit/test_loot.gd`. **When a semantic change reddens a test,
first ask whether the fixture stopped representing what it used to** — the alternative is a suite
that always passes and proves nothing.

**Verifier findings, both recorded rather than fixed** (thread `019fdddb-0e64-7ea2-8fad-09b8c389ec2b`):

1. *Training Hall rounding order at intermediate levels.* The multiplier is applied with one
   `roundi()` over the combined `(xp_per_wave * waves_resolved [+ xp_reward]) * multiplier` rather
   than per term. At the cap (`building_levels[2] = 5`, `×1.75`) this lands exactly on the ruled
   `7`/`42`/`126`/`336`, because every term scales to an integer there. At intermediate levels it
   diverges from a per-term reading by up to 1 XP — e.g. level 1 (`×1.15`) pays `37` combined
   versus `38` per-term. `SYSTEMS.md` says the multiplier applies to both amounts but never settles
   the rounding order, and the Training Hall is not buildable (`P2-07a` scoped the panel to three),
   so the multiplier is `1.0` in all real play. Whoever makes it buildable settles this; it is one
   line either way and there is nothing to fix until then.
2. *Rank-up XP banking is tested by hand-setting `hero.rank`, not through
   `GameSession.rank_up_hero()`.* The ADR (`DECISIONS.md` 2026-08-01) is honored today —
   `rank_up_hero()` touches only `rank` and `essence`, never `level`/`xp`, confirmed by reading it —
   but no test drives `grant_xp` through the real rank-up path, so a future edit that started
   touching level or XP would not be caught by this ticket's coverage.

Also noted, unreachable from production: a negative `amount` passed to `Hero.grant_xp()` leaves
`hero.xp` negative without crashing. Both `xp_per_wave` and `zone.xp_reward` are non-negative
authored constants and no caller can produce one, so no guard was added.

### Files changed
`heroes/hero.gd`, `systems/game_session.gd`, `hub/expedition/expedition.gd`, `hub/hub.gd`,
`balance_table.gd`, `balance.tres`, `zones/zone_definition.gd`, `zones/defs/*.tres` (all three),
`tests/zone_definition_check.gd`, `tests/save_roundtrip_check.gd`, `tests/unit/test_hero_stats.gd`,
`tests/unit/test_expedition.gd`, `tests/unit/test_loot.gd`. `combat/quick_resolve.gd` unchanged.

---

## P2-17 — A refused save is moved aside, not overwritten                    [DONE]

### Objective
A player whose `user://save.json` is corrupt boots into a fresh game and is **told so**, with the
unreadable file preserved as `user://save.corrupt.json` instead of silently clobbered by the first
thing they do.

### Existing architecture
- `SaveService.load_game()` (`systems/save_service.gd:21-45`) has three refusal branches — missing
  file, top-level JSON not a Dictionary, `version > SAVE_VERSION` — each returning `false` and
  leaving `GameSession` at constructor defaults. `tests/unit/test_save_service.gd` already pins
  that "left untouched" half; nothing pins what happens next.
- `GameSession._ready()` (`systems/game_session.gd:24-27`) connects `roster_changed` to
  `SaveService.save` **after** the load, so the first summon/expedition/upgrade emits and
  `save()` overwrites the refused file in place. That is the defect.
- `SaveService.save()` writes directly to `SAVE_PATH` with no temp-file-then-rename — the reason
  the corrupt branch is reachable at all. **Out of scope here** (see Non-goals).
- `run/main_scene` is `res://ui/main_menu.tscn`; autoloads are `_ready()` before it, so anything
  `load_game()` records is available to the menu's `_ready()`.
- The ruling is `SYSTEMS.md` § Refused-save recovery (`P2-17`). It settles every open input —
  read it, do not re-decide it.

### Acceptance criteria
1. A `user://save.json` whose top level is not a Dictionary is renamed to
   `user://save.corrupt.json` before `load_game()` returns `false`; the renamed file's bytes are
   byte-identical to what was on disk. An existing `save.corrupt.json` is overwritten (ruled).
2. After that refusal, the next `roster_changed` emission writes a **valid** save at `SAVE_PATH`,
   and `save.corrupt.json` still holds the original garbage. This is the whole ticket: assert both
   files, not just one.
3. `SaveService` carries a transient, **not persisted**, one-shot notice: set on the corrupt
   branch, returned once and cleared by the reader. It appears in neither `GameSession.to_dict()`
   nor the file on disk.
4. `ui/main_menu.tscn` shows that notice on boot and is otherwise unchanged — hidden when the
   notice is empty, which is every normal boot. Reach the label by `%UniqueName`, not by node
   path: `P2-07d` reddened on absolute paths that a re-parent would break.
5. The other two refusal branches are untouched. Missing file still returns `false` with **zero**
   `push_error` calls (`test_missing_save_is_refused_without_error` asserts the count), and
   `version > SAVE_VERSION` still refuses without renaming anything — ruled deliberately apart,
   because that file is recoverable by running the build that wrote it.
6. If the rename itself fails, `push_error` and return `false` anyway. No notice is set for a
   move that did not happen.
7. `tests/unit/test_save_service.gd` cleans up `save.corrupt.json` in `after_all` and still
   restores `save.json` byte-identically. That file is the **only** one in the suite that backs
   the real save up (`KNOWN_ISSUES.md` § Environment); breaking its restore breaks the guarantee
   for everything after it.
8. BUILT green — import gate **and** the GUT suite, zero errors and zero warnings.

### Files allowed to change
- `systems/save_service.gd`
- `ui/main_menu.gd`, `ui/main_menu.tscn`
- `tests/unit/test_save_service.gd`

Checked before writing this list, because `P2-04g` and `P2-18` both omitted a real call site.
`load_game()`'s only production caller is `GameSession._ready()`. It has **three** test callers,
not the one this paragraph originally claimed — `tests/save_roundtrip_check.gd` and
`tests/summon_def_id_roundtrip_check.gd:119`, both dynamic via `.call()` (`P2-04e`'s trap), and
`tests/unit/test_item.gd:75`, a direct static call. All three feed `load_game()` a valid
Dictionary before every reload and none reaches the corrupt branch, so none needs changing — but
**grep `load_game` again if the signature moves**, since the import gate cannot see a `.call()`.
The miss is itself the finding: the audit was written from the ticket that last touched this seam
rather than from a grep, which is exactly how `P2-04e` describes the trap being sprung.

### Non-goals
- **Atomic write.** `save()` staying non-atomic is what makes branch 2 reachable; fixing it is a
  different code path with a different acceptance test (kill the process mid-write, confirm the
  *previous* save survived). Ruled a separate ticket — `P2-20`.
- **Error-rendering UI for the newer-version branch.** Ruled "refuse to boot", but that branch is
  unreachable until `SAVE_VERSION` is bumped past `1`. Do not build a screen for it.
- Save migration. Phase 5 owns it (`save_service.gd:35-38`).
- Any change to what `GameSession` holds. No new save key, no `to_dict`/`from_dict` edit.

### Findings

**1. The allowed-file list's own audit paragraph was wrong, and it was written to stop exactly
that.** `P2-04g` and `P2-18` each shipped with a file list omitting a real call site, so this
ticket added a paragraph naming every caller of the function it touches. That paragraph then
named one of three: it missed `tests/summon_def_id_roundtrip_check.gd:119` (dynamic `.call()`)
and `tests/unit/test_item.gd:75` (a plain static call). Nothing broke — all three feed valid
dictionaries and none reaches the corrupt branch — but the paragraph is a **record**, and a
wrong record is worse than none, because the next ticket to move this signature will trust it.
The cause is worth copying out: it was written from `P2-04e`'s findings, which name
`save_roundtrip_check.gd` as *the* dynamic caller, rather than from a fresh
`grep -rn "load_game" --include=*.gd`. Citing the archive is not auditing the tree. The
`verifier` caught it; no gate could have.

**2. The mandatory `verifier` pass earned itself on the seam no gate covers.** The change adds a
`%SaveNotice` `Label` to `main_menu.tscn` and a `_ready()` that dereferences it — and
`main_menu.tscn` is `run/main_scene`. Nothing in `tests/` has ever instantiated it. A bad
`unique_name_in_owner`, a misparented node or an erroring `_ready()` means **the game does not
boot**, while the import gate (never instantiates a scene) and the GUT suite (never loads this
one) both stay green. The verifier drove the scene directly with ad-hoc `SceneTree` scripts and
proved both branches — notice shown with the right text, and hidden on a normal boot — plus a
forced OS-level rename failure confirming `save.json` survives and no notice is set on that path.
That coverage lives in a review artifact, not in the repo: **`main_menu.tscn` still has no
committed test.** Whoever touches it next inherits that.

**3. Closing the `FileAccess` before the rename is load-bearing, not tidiness.** `load_game()`
holds the save file open for READ when the corrupt branch fires; on Windows a rename over a live
handle is not reliable. `file.close()` sits immediately before `DirAccess.rename_absolute` for
that reason. The ruled "overwrite any prior `save.corrupt.json`" behavior needs no hand-rolled
delete — Godot's `DirAccess::rename` removes an existing destination first.

**4. Two test gaps the verifier found, both since closed.** The next-save test set the one-shot
notice and never consumed it; `SaveService` is a singleton alive for the whole GUT process, so
that leaked forward into every later test — the `P2-08` cross-test-coupling shape in a new place.
And `before_each()` deletes `save.corrupt.json`, so the ruled overwrite clause had no committed
regression test at all despite the criterion naming it. Both are covered now
(`test_a_second_corrupt_save_overwrites_the_first_one_moved_aside`), which is also the only test
of a *second* corruption arriving before the player has read the first notice.

**5. The ruling priced a cost the backlog row had not.** The row framed this as a choice between
three behaviors; the `game-designer` pass ruled the three refusal branches **apart** rather than
uniformly, and then added a requirement neither the row nor the director's cost estimate carried:
a silent rename is indistinguishable from data loss, so one line of on-screen text is part of the
fix. That turned "~3 lines in `load_game()`, no new UI" into a scene change — which is what made
the `verifier` pass mandatory. Worth remembering when estimating a "three-line" save fix.

### Files changed
`systems/save_service.gd`, `ui/main_menu.gd`, `ui/main_menu.tscn`,
`tests/unit/test_save_service.gd`. Docs: `docs/SYSTEMS.md` (the ruling), `docs/KNOWN_ISSUES.md`
(cross-reference), `docs/TASKS.md`.

---

## P2-20 — A crashed save leaves the previous save intact                    [DONE]

### Objective

Killing the game mid-save leaves the last good `user://save.json` on disk, instead of the
zero-byte file that `P2-17`'s corrupt branch then has to move aside.

### Existing architecture

- `SaveService.save()` (`systems/save_service.gd:12-20`) opens `user://save.json` with
  `FileAccess.WRITE`, **which truncates on open**, and only then `store_string`s the payload.
  Between those two calls the only save on disk is empty. That window is why `P2-17`'s corrupt
  branch is reachable in a shipped build at all.
- `SaveService` is an autoload and the only thing that touches save files (`ARCHITECTURE.md` r4).
  `save()` returns nothing and no caller checks it.
- `load_game()` already handles the aftermath and is **not** in scope: `P2-17` ruled its three
  refusal branches. This ticket reduces how often the corrupt one fires; it does not change it.
- `DirAccess.rename_absolute()` accepts `user://` paths directly — `load_game()`'s corrupt branch
  already uses it that way (`save_service.gd:37`), and its target may already exist.
- `FileAccess` is `RefCounted` and closes on scope exit, which is **too late here**. The handle
  must be explicitly `close()`d before the rename, the same way the corrupt branch does at
  `save_service.gd:36`.
- `tests/unit/test_save_service.gd` owns this file's coverage and already snapshots and restores
  the real `user://save.json` around the suite in `before_all`/`after_all`.

### Acceptance criteria

1. `save()` writes the payload to a temp path (`user://save.tmp.json`, a new `const` beside
   `SAVE_PATH`), closes it, then renames it over `SAVE_PATH`. `SAVE_PATH` is never opened with
   `FileAccess.WRITE` anywhere in `save()`.
2. A failed temp write leaves the existing `user://save.json` **byte-for-byte unchanged** and
   pushes an error. Pinned by a test that forces the failure: pre-create a *directory* at the temp
   path, which makes `FileAccess.open(..., WRITE)` return null. (Confirmed on Windows — it does.)
2b. **A failed `store_string()` also leaves the previous save unchanged.** `store_string()` returns
   `bool`, and a write that fails on a full disk, a quota or a lock leaves the handle **non-null** —
   so the open check in criterion 2 does not cover it. Unchecked, the truncated temp gets renamed
   over the good save, which is criterion 2's data loss relocated from open-time to write-time.
   No test: nothing here can force an OS-level write failure, same as criterion 3.
2c. **`load_game()` closes its read handle before `from_dict()`.** It does not today: the handle
   opened at `save_service.gd:28` stays live through `GameSession.from_dict()`, which emits
   `roster_changed`. Windows will not replace a file that has an open handle, so any `save()`
   re-entered from inside that emit fails its rename. The close moves ahead of the branch rather
   than being added per-branch, so the corrupt path keeps exactly one. Pinned by criterion 4's test.
   **Scoped honestly:** this is *not* reachable on a real boot. `GameSession._ready()`
   (`game_session.gd:24-27`) connects `roster_changed` to `SaveService.save` only **after**
   `load_game()` returns, deliberately and with a comment saying so, and that is `load_game()`'s
   only production call site. The failure is reachable from GUT, where the connection is already
   live when a test calls `load_game()` directly — and from any second call site a later ticket
   adds, such as a reload-from-menu. Defensive, not a shipped-build bug.
3. A failed rename pushes an error naming the failure. No test — nothing available here can force
   a rename to fail on Windows, and inventing a way to would cost more than the branch is worth.
4. A stale `user://save.tmp.json` left by a crashed write is harmless: `load_game()` ignores it and
   the next `save()` overwrites it. Pinned by a test.
5. After a normal `save()` no temp file remains, and `user://save.json` parses as a Dictionary
   carrying the session's state. Pinned by a test.
6. Existing tests still pass — the five already in `tests/unit/test_save_service.gd` (eight after
   this ticket), and `tests/save_roundtrip_check.gd`.
7. BUILT green: zero script errors, **zero warnings**, GUT suite green.

### Files allowed to change

- `systems/save_service.gd`
- `tests/unit/test_save_service.gd`
- `tests/save_roundtrip_check.gd` — **widened during the ticket, not planned.** Staging the write
  makes an open read handle on `save.json` fatal, and this file leaked one at all seven of its raw
  JSON reads. Same class of defect as the `load_game()` fix below, in the file whose whole job is
  to prove the save boundary.

### Non-goals

- Migration, bumping `SAVE_VERSION`, or rotating/backing up old saves.
- **Loading from a stale temp file.** A temp file is by definition an unfinished write; preferring
  it over a good `save.json` is how you lose a good save. Delete-or-overwrite only.
- Touching `load_game()`'s three **refusal branches** — `P2-17` ruled them and they stay as they
  are. This does **not** extend to `load_game()`'s file handle: staging the write turns its leaked
  READ handle into a hard failure of the first save after every boot, so closing it is inside this
  ticket. See criterion 2b.
- A `save()` return value or caller-side error handling. Every caller ignores it today and
  rewiring them is a separate ticket.
- Proving that Godot's `rename` is a single atomic syscall on Windows. It is **not**: on a
  destination that already exists it removes then moves, leaving a window where `save.json` is
  absent while `save.tmp.json` still holds the complete new state. That residue is two filesystem
  calls wide rather than a multi-kilobyte write, and recovering from it would mean loading a temp
  file — the non-goal above. What this ticket buys is that `store_string` no longer runs against
  the live file, which is the window a player actually loses a save in.
  *(Source: Godot `master` via a second-model read, not the 4.7.1 tag — the engine here is
  binary-only. Directionally confirmed, not pinned to this build.)*

### Findings

**The verifier's HIGH is the one to carry forward: `store_string()` returns `bool`, and the first
implementation threw it away.** Staging protects against a crash *between* truncate and write — it
does nothing about a write that *fails*, because the handle stays non-null through it. A full disk,
a quota or an AV lock returns `false`, and the code then closed the truncated temp and renamed it
over the good save: criterion 2's data loss, relocated from open-time to write-time and untested
because criterion 2's test only forces the open-failure path. **Any staged write added anywhere
after this checks all three of open, write and rename, not just open and rename.**

**Staging a write makes an open read handle on the target fatal, and this repo held eight of them.**
Windows will not replace a file with a live handle, so the moment `save()` stopped writing in place,
every unclosed reader of `save.json` became a failed save. `load_game()` held one across
`from_dict()`; `tests/save_roundtrip_check.gd` held one at each of its **seven** raw-JSON reads. All
eight were invisible before this ticket and all eight are one line each. The check file was **not**
in the allowed-file list — the third consecutive ticket whose list omitted a real call site
(`P2-04g`, `P2-18`, this one). The list is now the least reliable field in the template; widen it
out loud rather than working around it.

**A stack trace tells you a defect exists, not how far it reaches.** This ticket's criterion 2c
originally read "the first save after every single boot is lost", inferred from a GUT backtrace
showing `load_game() -> from_dict() -> save() -> rename failed`. It is false on a real boot:
`GameSession._ready()` (`game_session.gd:24-27`) connects `roster_changed` to `SaveService.save`
**after** `load_game()` returns, deliberately and with a comment saying so, and that is
`load_game()`'s only production call site. GUT reaches the failure because the connection is
already live when a test calls `load_game()` directly. The fix stays — it guards the tests and any
reload-from-menu a later ticket adds — but it is defensive code, not a shipped-build bug, and the
ticket says so now. **Check a defect's call graph before writing its blast radius into a ticket**;
the correction came from the `verifier` reproducing a real boot both ways, not from the gates.

**Godot's `rename` is not atomic on Windows.** On an existing destination it removes, then moves,
so there is a two-syscall window where `save.json` is absent while `save.tmp.json` holds the
complete new state. Recovering from that window would mean loading a temp file, which is this
ticket's explicit non-goal — an unfinished write must never outrank a good save. Recorded as a
known residue, not a defect: the window shrank from a multi-kilobyte `store_string` to two
filesystem calls, which was the whole point. *(Read from Godot `master`, not the 4.7.1 tag — the
engine here is binary-only.)*

**A directory at the temp path is a working fault injector.** `FileAccess.open(dir_path, WRITE)`
returns null on Windows, which is what makes criterion 2's test discriminate rather than pass
vacuously. Confirmed by standalone probe. There is no equivalently cheap injector for a failed
*write* or a failed *rename*, which is why 2b and 3 ship guarded but untested and say so.

**An autosave will eat your fixture.** `test_stale_temp_file_is_ignored_then_replaced` first
failed for a reason unrelated to the change: `GameSession.from_dict({"roster": []})`, used to clear
memory before reloading, emits `roster_changed` and autosaves the *empty* roster over the file the
test had just written. Any test in this suite that writes a save, clears the session, then reloads
must re-write the bytes after clearing. `before_each` has the same shape and gets away with it only
because every existing test writes `SAVE_PATH` explicitly afterwards.

---

## P2-21 — The Training Hall is buildable, so its XP bonus can actually fire   [DONE]

### Objective
The Buildings panel offers a fourth building. Spending parts on the Training Hall raises expedition
XP by `+15%` per level — a bonus the code already applies and no player can currently reach.

### Existing architecture
- `building_levels` (`systems/game_session.gd:17`) is a 5-element persisted `Array[int]`; the
  **Training Hall is index 2**, reserved by `P2-07b` and never written outside tests.
- `GameSession.upgrade_building(index, balance)` (`game_session.gd:116`) is already generic over the
  index — bounds check, `10 * (n + 2)` parts of rank index `n`, cap `summoning_circle_level_cap`,
  `roster_changed.emit()`. **It needs no change**, and neither does any balance field.
- `hub/expedition/expedition.gd:33-38` already reads `building_levels[2]` and applies
  `1.0 + BALANCE.training_hall_xp_bonus * level` to `xp_per_wave` and `zone.xp_reward` on every
  outcome. The consumer landed with `P2-04g`; only the level is stuck at zero.
- The panel is `UI/Root/BuildingsPanel/VBox` in `hub/hub.tscn` — three Label/Button pairs, each
  button `[connection]`ed to a `_on_upgrade_*_pressed` handler that delegates to
  `hub.gd:374 _upgrade_building(index, name, upgraded)`. That helper already writes the level, cap
  and cost messages generically; the new handler is two lines.
- **No design pass is needed.** `P2-07a` ruled the cost ladder and the cap for all five buildings
  uniformly and named this exact follow-up (`SYSTEMS.md` § "Which buildings ship in `P2-07`",
  lines 2088-2092): re-open Training Hall once `P2-04a` lands. It landed (`6e00e6f`), and `P2-04g`
  (`dc6e090`) wired the curve.
- **No save key changes** — `building_levels` has persisted all five indices since `P2-07b`, and
  `to_dict`/`from_dict` special-case none of them. But `tests/save_roundtrip_check.gd` only ever
  drove **index 1** to a non-zero value and asserted the other four were `0`, so nothing proved a
  non-zero index 2 crossed real disk. Close that rather than reword it (criterion 8).

### Acceptance criteria
1. The Buildings panel shows `Training Hall — Lv N` with an Upgrade button, sited between Forge and
   Sanctum so the panel order matches the `Buildings` child order the index scheme came from.
2. The label refreshes from `_refresh_buildings()` on `roster_changed`, like the other three.
3. Pressing Upgrade with sufficient parts raises `building_levels[2]` by one, deducts the ruled
   cost, and sets the same status-line shape the other three produce.
4. Pressing at cap, or without the parts, refuses and writes nothing — reusing `_upgrade_building`'s
   existing messages, not new ones.
5. A GUT test in `tests/unit/test_buildings.gd` **instantiates `hub.tscn` and emits `pressed` on the
   real button node**, then asserts `building_levels[2]` moved and the status text is right. Calling
   the handler directly does not satisfy this: the `[connection]` block and the `%UniqueName` are the
   risky boundary here, and a typo'd method name in a `[connection]` leaves the import gate green.
   (`P2-05g` shipped a Convert button no test has ever pressed — do not add a second.)
6. `tests/unit/test_expedition.gd:106`'s existing level-5 XP assertions still pass unchanged; this
   ticket makes that level reachable, it does not retune it.
7. Import gate green with zero errors and zero warnings, and the full GUT suite green.
8. `tests/save_roundtrip_check.gd`'s building check drives **two** buildings to two *different*
   non-zero levels — Forge to 2 and Training Hall to 1 — so a save that persists only the first
   index, or collapses the array, fails there instead of passing on an all-zero tail.

### Files allowed to change
`hub/hub.tscn`, `hub/hub.gd`, `tests/unit/test_buildings.gd`, `tests/save_roundtrip_check.gd`,
`docs/TASKS.md`.

### Non-goals
- **The Reliquary (index 4) stays unbuildable.** `P2-04f` is still blocked on
  `power_deficit_penalty` and a turn concept, so parts spent there would provably do nothing —
  the precise reason `P2-07a` deferred both.
- No change to `upgrade_building`, to any `BalanceTable` field, or to the XP formula.
- No 3D mesh or `Buildings/TrainingHall` node changes — the grey box is already there.
- No tooltip or cost preview on the button; the other three have none.

### Findings

**The verifier's only finding was in the ticket, not the code.** The "Existing architecture" bullet
originally claimed `tests/save_roundtrip_check.gd:403` "already round-trips all five indices through
real disk, index 2 included." It iterates all five, but line 404 read
`expected_level: int = 2 if building_index == 1 else 0` — only the Forge was ever driven non-zero and
the other four were asserted to *be* zero. A citation that names a line number and a loop reads as
verified; what the loop actually asserts is a different question. Criterion 8 was added and the check
now drives Forge to 2 and Training Hall to 1, so persisting only the first index — or collapsing the
array to one value — fails there instead of passing on an all-zero tail.

**The bonus was live before the building was.** `hub/expedition/expedition.gd:33-38` has multiplied
every XP payout by `1.0 + training_hall_xp_bonus * building_levels[2]` since `P2-04g`, and
`tests/unit/test_expedition.gd:106` asserted the level-5 figures by setting the array directly — so a
green suite proved the arithmetic while the multiplier was pinned at `1.0` in every real game. This
is the backlog's recurring "reads real, measures nothing" shape (`LostCache.turn_lost`,
`Item.enhance_level`, `reliquary_decay_turns_bonus`, `P2-07d`'s `roundi()` ruling) inverted: not a
field with no consumer, but a **consumer with no reachable input**. A test that sets the state
directly cannot tell you whether anything in the game can produce that state. Only the Reliquary
(index 4) remains in that condition, deliberately — `P2-04f` is still blocked.

**The generic helper is why this was six lines of production code.** `GameSession.upgrade_building`
and `hub.gd`'s `_upgrade_building` were both written index-generic by `P2-07b`, so the fourth
building needed no new cost logic, no new message, and no new balance field — one `@onready`, one
refresh line, one two-line handler, and a Label/Button/`[connection]` triple in the scene. `P2-07b`
paying that cost once is what made this ticket small.

---

## P2-12 — Salvage and enhance arithmetic moves off the autoload             [DONE]

### Objective

Nothing a player can see changes. `GameSession.salvage_item` and `enhance_item` keep their exact
signatures and their exact outcomes; the two formulas behind them become pure `static func`s a
test can call without booting an autoload. This is the cost `DECISIONS.md` 2026-08-06 predicted,
being paid down.

### Existing architecture

- `DECISIONS.md` 2026-08-01 rejected balance logic as methods on `GameSession`; 2026-08-06
  **reaffirmed** it rather than reversing it, and named these methods debt. `CODING_RULES.md:93-103`
  states the rule in the present tense with `compute_essence_yield(fodder, target, balance)` as its
  worked example.
- `Hero` is the precedent: `compute_essence_yield`, `compute_rank_up_cost` and `grant_xp` are pure
  `static func`s, and `tests/unit/test_sacrifice.gd` exercises the arithmetic with no `GameSession`
  in the scene tree. `Item` (`equipment/item.gd`) is the analogous home for item arithmetic and
  already carries one public static helper (`int_field`).
- Both formulas are authored, not invented here: salvage is
  `roundi((3 + enhance_level) * (1.0 + forge_salvage_yield_bonus * forge_level))` and the enhance
  cap is `mini(forge_enhance_cap_max, forge_level * forge_enhance_cap_per_level)`
  (`SYSTEMS.md` § Base buildings, § Enhancement). **`roundi()`, never `int()`** — truncation
  reproduces `P2-07d`'s dead bonus.
- The two caps eight lines apart in `game_session.gd` are **both correct and must stay different**
  (`P2-07d` Findings): `enhance_item` gates on the forge-scaled cap because it governs *gaining* a
  level, `salvage_item` clamps against the flat `forge_enhance_cap_max` because it governs
  *trusting* a level an item already has.
- Both `item.enhance_level` and `building_levels[1]` arrive from an untrusted save and are clamped
  before use today, at the two mutation sites. Those clamps are part of the arithmetic and move
  **into** the static funcs, which makes them total for any input and kills the `P2-07e`
  preview-disagrees-with-payout hazard by construction rather than by discipline.

### Acceptance criteria

1. `Item.compute_salvage_yield(item: Item, forge_level: int, balance: BalanceTable) -> int` and
   `Item.compute_enhance_cap(forge_level: int, balance: BalanceTable) -> int` exist as pure
   `static func`s. Neither names `GameSession`, `SaveService` or `SceneRouter`.
2. Both clamp their own untrusted inputs: `forge_level` into `[0, summoning_circle_level_cap]`, and
   `item.enhance_level` into `[0, forge_enhance_cap_max]`. `GameSession` passes `building_levels[1]`
   raw and clamps nothing itself.
3. `salvage_item` and `enhance_item` keep their exact signatures and read as validate → call the
   static func → mutate → emit. `enhance_item` still gates on the forge-scaled cap and `salvage_item`
   still clamps against the flat one — criterion 3 of `P2-07d`'s test must still pass untouched.
4. New GUT tests call both static funcs directly with a literal `forge_level` and a loaded
   `BalanceTable`, and **name no autoload in the test body**. That is the entire point of the
   ticket; a test that reaches the formula through `GameSession` does not satisfy it.
5. The clamps are pinned: an `Item` at `enhance_level = 999` yields what one at
   `forge_enhance_cap_max` yields, one at `-1` yields what `0` yields, and `forge_level = 999`
   yields what level 5 yields.
6. Forge level 0 still returns cap `0` (a fresh save cannot enhance — ruled, `SYSTEMS.md:807-811`)
   and still salvages the unbonused `3 + enhance_level`.
7. Every existing assertion in `tests/unit/test_equipment.gd` passes **unchanged** — no behavior
   moved, so no existing expectation should need editing. Editing one is a signal the refactor
   changed something.
8. Import gate green with zero warnings; the full GUT suite green;
   `tests/save_roundtrip_check.gd` green (it drives `salvage_item` and `convert_parts` on real disk
   through `.call()`).

### Files allowed to change

`equipment/item.gd`, `systems/game_session.gd`, `tests/unit/test_equipment.gd`.

### Non-goals

- **`convert_parts` is deliberately not extracted**, though the row named it. Its "arithmetic" is
  `-3` and `+1` against a fixed rank index — there is no formula, and a
  `compute_conversion_cost() -> int` returning `3` is a config for a value that never changes. Its
  guard already sits where the mutation does.
- **`upgrade_building`'s `10 * (level + 2)` is out of scope.** Same shape, but it shipped after this
  row was written, and its only honest home is a `buildings/` directory that does not exist —
  inventing one for a single `static func` costs more than it pays. Recorded here so the next reader
  reads it as known rather than missed.
- No new `BalanceTable` field. The `3 +` and `2 +` literals stay put; moving them is a `.tres`
  change and a different ticket. `2 + enhance_level` stays inline next to its own affordability
  guard — one term is not a formula.
- **No signature change on any `GameSession` method.** `tests/save_roundtrip_check.gd` reaches
  `salvage_item`, `convert_parts` and `upgrade_building` dynamically through `.call()` (`P2-04e`'s
  trap), where the import gate cannot catch an arity break.

### Findings

**The evidence that a pure refactor is pure is the assertions you did *not* touch.** 105/105 GUT
tests pass and not one existing expectation in `tests/unit/test_equipment.gd` was edited — criterion
7 exists so that "I had to adjust a test" becomes a reportable failure rather than a quiet judgment
call. `tests/save_roundtrip_check.gd` is the other half of it: it reaches `salvage_item` and
`convert_parts` through `.call()`, so an arity slip there is invisible to the import gate, and it
was run on real disk rather than assumed.

**The private-helper-called-from-outside mistake, for the third time.** The first pass shipped
`Item._clamped_enhance_level` with a leading underscore and called it from `systems/game_session.gd`.
That is exactly what `P2-05f` shipped as `Item._int_field` and `P2-11` had to correct to
`Item.int_field` — a helper is private or it is cross-file, never both. Renamed to
`clamped_enhance_level` with a comment naming *why* it is public, since the underscore is the only
signal GDScript has and nothing enforces it. Worth generalizing: when arithmetic moves out of a
caller, the caller usually still needs one of the intermediate values, and that intermediate is
public API whether or not it looks like an implementation detail.

**A saturating `mini()` hides a missing clamp.** The first test for `compute_enhance_cap` asserted
`compute_enhance_cap(999) == compute_enhance_cap(5)`, which passes with the `forge_level` clamp
deleted — `mini(15, 2997)` and `mini(15, 15)` are both `15`. Only the negative direction
distinguishes them (`compute_enhance_cap(-1) == 0`), and that assertion was added. The salvage test
did not have this problem because its formula is multiplicative and unbounded, so `forge_level = 999`
diverges loudly. **A clamp test against a saturating operation proves nothing about the clamp.**

**Moving the clamps *into* the pure functions is the part that buys something beyond testability.**
Before, `item.enhance_level` and `building_levels[1]` were clamped at each mutation site, which is
the shape that produced `P2-07e`'s preview-disagrees-with-payout hazard — `hub.gd` had to recompute
"the identically-clamped level" by hand and stay in step forever. Now any caller passing a raw,
corrupt, or negative value gets the same answer as the real path, by construction. That is the
lazy fix and the root-cause fix at once: one clamp where all callers route through, rather than a
clamp per caller.

**Two of the three methods the row named were not worth extracting, and saying so is the ticket's
job.** `convert_parts` has no formula — `-3`/`+1` — and `upgrade_building`'s `10 * (level + 2)` has
no home short of inventing a `buildings/` directory for one function. Both are recorded in Non-goals
rather than silently skipped, so the next reader sees a decision instead of an oversight. The debt
`DECISIONS.md` named was *balance formulas on an autoload*; a constant is not a formula.

---

## P2-23 — Turns exist, and a lost cache records the one it died on          [DONE]

### Objective
The hub shows a turn count that advances by one every time an expedition resolves, and a cache
created by a hero's death records the turn it happened on. Both survive a save and reload.

### Existing architecture
- `GameSession` (`systems/game_session.gd`) is the autoload holding persisted profile state; every
  mutator ends in `roster_changed.emit()`, which `_ready()` wires to `SaveService.save`.
- `Expedition.resolve()` (`hub/expedition/expedition.gd:19`) returns one of four outcomes and is
  the only code path that can kill a hero.
- `kill_hero()` (`systems/game_session.gd:172`) is the sole permadeath writer (`ARCHITECTURE.md`
  r8) and already builds a `LostCache` when the dying hero carries gear.
- `LostCache` (`equipment/lost_cache.gd`) type-validates every field it decodes and has no `int()`
  anywhere — `P2-11` proved it was already `null`-safe.
- `Item.int_field(data, key, fallback, subject)` is the shared save-decode helper (`P2-11`); it
  absorbs a missing key, an explicit `null`, and a JSON `float`.

### Acceptance criteria
1. `GameSession.turns` exists, is `0` on a fresh save, and only ever increases.
2. `Expedition.resolve()` advances it by exactly one on `COMPLETED`, `RETREATED` and `DEFEATED`,
   and **not at all** on `INVALID_TEAM` — that outcome returns before the first wave.
3. The tick happens **before** the wave loop. A cache created by a death on that expedition is
   therefore stamped with the turn the expedition became, so an immediate recovery reads
   `turns_elapsed = 0` — the fresh-cache case `SYSTEMS.md` § Death and gear recovery verified at
   `0.35`. Stamping the pre-increment value makes that case read `-1`.
4. `LostCache.turn_lost` exists, defaults to `0`, and `kill_hero()` stamps it with
   `GameSession.turns`. **No signature change** to `kill_hero()` — `turns` is the same autoload's
   own state, not a balance number being smuggled in (`P2-05f`'s distinction).
5. Both keys survive a **real disk** cycle through `SaveService` — a check in
   `tests/save_roundtrip_check.gd`, not an in-memory `to_dict`/`from_dict` pair. `P2-05a`,
   `P2-04e` and `P2-21` each shipped that shortcut and each was reopened.
6. Both keys tolerate the three untrusted save shapes separately: key missing, explicit `null`,
   and a JSON `float` (`12.0`, which is how an int reaches disk and back). A negative value floors
   at `0`.
7. The hub displays the turn count, and it updates without leaving the scene.
8. The import gate is green with **zero warnings**, and the GUT suite passes.

### Files allowed to change
`systems/game_session.gd`, `equipment/lost_cache.gd`, `hub/expedition/expedition.gd`,
`hub/hub.gd`, `hub/hub.tscn`, `tests/save_roundtrip_check.gd`, `tests/unit/test_expedition.gd`,
`tests/unit/test_item.gd`.

Corrected during the `verifier` pass, which caught it: the list first read
`tests/unit/test_equipment.gd`, and the untrusted-shape tests went to `tests/unit/test_item.gd`
instead, because that is where every existing `GameSession.from_dict` decode test already lives —
including one that already drives `lost_caches`. `test_equipment.gd` was never touched.

Four consecutive tickets have omitted a real call site from a list like this one (`P2-04g`,
`P2-18`, `P2-20`, and `P2-17`'s audit). Grep rather than trust it — `kill_hero`'s second caller
reaches it **dynamically** through `.call()` in `tests/save_roundtrip_check.gd`, which
`grep "kill_hero("` finds but an arity check never would.

### Non-goals
No recovery expedition, no damage roll, no expiry sweep, no Reliquary upgrade panel — all
`P2-04f`. No turn cost on any other action. **Nothing reads `turn_lost` yet**; this ticket makes it
a real number, not a consumed one, which is the precise condition `P2-04e` said had to hold before
the field could ship at all.

### Findings

**GUT fails a test on an unconsumed `push_error`, and the failure names the error rather than the
assertion.** The only way to reach `OUTCOME_INVALID_TEAM` is a hero whose `def_id` resolves to no
`HeroDefinition`, and `Hero.definition_for` pushes an error on that path. The first GUT run went red
with `[Failed]: Unexpected Errors — Missing HeroDefinition for def_id 'not_an_archetype'` while every
assertion in the test passed. `assert_push_error("Missing HeroDefinition")` fixes it, and the general
rule is that **a test exercising an error branch must consume the error** or the suite reports a
failure that looks nothing like the thing being tested. Nothing in `tests/unit/` had needed this
outside `test_item.gd`'s decode tests, which is why it was not obvious.

**`LostCache.from_dict` returns early on a malformed `items` array**, so any field decoded after that
point silently defaults on exactly the saves most likely to be corrupt. `turn_lost` decodes *above*
it, deliberately — a cache that lost its gear to a bad save should still know when it was created.
`P2-11` established that `LostCache` was already `null`-safe; it did not establish that its decode
order was safe to append to, and it is not.

**The allowed-file list was wrong for the fifth consecutive ticket — in the opposite direction this
time.** `P2-04g`, `P2-18`, `P2-20` and `P2-17` each *omitted* a file that had to change. This one
*named* one that did not (`tests/unit/test_equipment.gd`) and omitted the one that did
(`tests/unit/test_item.gd`), because the list was written from where the `LostCache` tests live
rather than from where the `GameSession.from_dict` decode tests live. The `verifier` caught it and
was right to; the list is now correct and the deviation is recorded above rather than left for an
auditor to find. **Write the list after the grep, not before it** — that is the single change that
would have prevented all five.

**The tick's position is a real decision, and the test proves it rather than restating it.** Placing
`advance_turn()` before the wave loop means a hero dying on that expedition stamps its cache with the
turn the expedition *became*, so an immediate recovery run reads `turns_elapsed == 0` — the
fresh-cache case `SYSTEMS.md` verified at `0.35`. Post-increment stamping makes the same case read
`-1`, which no clamp in the formula catches.
`test_a_death_stamps_the_cache_with_the_turn_its_own_expedition_became` asserts `turns == 5` **and**
`turn_lost == 5`, so the off-by-one is a red test and not a code comment. The `verifier` independently confirmed there is no return path between the
`INVALID_TEAM` guard and the loop, which is what makes the placement safe.

**`kill_hero()` took no new argument, and that was the point.** `turns` is the same autoload's own
persisted state, so stamping it needs no signature change — the distinction `P2-05f` drew between an
autoload's own state and a balance number being smuggled through it. That kept this ticket clear of
`P2-04e`'s dynamic-caller trap (`tests/save_roundtrip_check.gd` reaches `kill_hero` through
`.call()`), which was checked anyway rather than assumed.

---

## P2-04f — Recover a dead hero's gear, or lose it to the clock          [DONE]

### Objective
The hub lists every lost cache with the turns it has left. Sending a team after one returns its
items — sometimes Damaged — and a cache nobody reaches in time is gone with its gear.

### Existing architecture

1. `GameSession.lost_caches: Array[LostCache]` already persists and round-trips. `kill_hero()`
   (`systems/game_session.gd:182`) is its only writer, per `ARCHITECTURE.md` r8. **Nothing reads it
   anywhere** — no UI, no system. This ticket is its first consumer.
2. `LostCache` is `hero_name`, `zone_id`, `items: Array[Item]`, `turn_lost` — all four persisted
   (`P2-04e`, `P2-23`). `turn_lost` is stamped with `GameSession.turns` at the moment of death.
3. `GameSession.advance_turn()` (`game_session.gd:49`) is the only place `turns` increases. It has
   exactly **two** callers — `hub/expedition/expedition.gd:36` and `tests/unit/test_expedition.gd:102`
   — and no dynamic ones (grepped `.call(`/`callv(`; the hits in `tests/save_roundtrip_check.gd` do
   not include it).
4. `Hero.compute_team_power(team, definitions, levels, balance)` (`heroes/hero.gd:134`) is the team
   power the gate reads; `combat/quick_resolve.gd:27` shows the call shape, including
   `Hero.definition_for()` and `Hero.level_for()` per hero.
5. `zone.power` in `SYSTEMS.md` is `ZoneDefinition.recommended_power` — `900`/`4800`/`11500`. There
   is **no zone lookup by `zone_id` anywhere in the codebase**: `hub.gd`'s `EXPEDITION_ZONES` is a
   hardcoded `preload` array. A cache stores a `zone_id`, so this ticket needs one. The three
   filenames under `zones/defs/` match their `zone_id`s exactly, so
   `Hero.definition_for`/`Item.definition_for`'s path-template shape ports over unchanged.
6. The ruling is `SYSTEMS.md` § Death and gear recovery, landed in `4772ffe`. **Damaged** halves
   `enhance_level` if the item carries any, else drops one rank, else (F at `+0`) returns the item
   intact. The Cores clause is struck and the affix clause is replaced by rank — do not invent
   either system.

### Acceptance criteria

1. `ZoneDefinition.definition_for(zone_id) -> ZoneDefinition` exists, built like
   `Item.definition_for` — `ResourceLoader.exists()` guard, `push_error` and `null` on a miss, no
   `assert`. A cache carrying an unknown `zone_id` (a hand-edited save, or the `&""` a sacrifice
   would write) must refuse recovery with a message, not crash.
2. The hub shows every entry in `GameSession.lost_caches`: hero name, zone display name, item
   count, and **turns remaining** (`turn_lost + 15 + reliquary_decay_turns_bonus * reliquary_level
   - turns`). The readout refreshes on `roster_changed` like every other panel.
3. Selecting one cache, selecting 1–5 heroes in the roster list, and pressing Recover attempts the
   run. It is refused — with a message naming the shortfall, **no turn spent, nothing mutated** —
   when: no cache is selected, the team is empty or over 5, the zone definition is missing, or
   `team_power < zone.recommended_power * 0.5`. A refused attempt is `OUTCOME_INVALID_TEAM`'s
   precedent: nothing happened, so nothing ticks.
4. A permitted run computes, **before the turn ticks**:
   `r = zone.recommended_power / team_power`,
   `power_deficit_penalty = clampf(0.2 * (r - 1.0), 0.0, 0.2)`,
   `damage_chance = clampf(0.15 + 0.03 * turns_elapsed + power_deficit_penalty
   - reliquary_damage_chance_reduction * reliquary_level, 0.0, 1.0)`,
   with `turns_elapsed = GameSession.turns - cache.turn_lost` and `reliquary_level =
   clampi(building_levels[4], 0, summoning_circle_level_cap)`. **Pre-tick is the ruling, not an
   implementation detail**: `P2-23` shipped `turn_lost` so that an immediate recovery reads
   `turns_elapsed == 0`, and ticking first makes that `1` with every gate still green. The `0.15`,
   `0.03` and `0.2` coefficients are authored nowhere in `BalanceTable` today; leave them as named
   local constants rather than adding fields nothing else reads.
5. Each item rolls independently against `damage_chance`. On a hit, Damaged applies per criterion
   6's function. Every item in the cache then moves into `inventory` (damaged or not), the cache is
   removed from `lost_caches`, and the turn ticks. Nothing is destroyed and no hero can die.
6. The Damaged arithmetic is a pure `static func` on `Item`, callable without booting `GameSession`
   — `DECISIONS.md` 2026-08-06 and `P2-06a`'s precedent. It reads `Item.clamped_enhance_level(item,
   balance)`, not the raw field, since a save can carry any integer; and it clamps `rank` at `0` on
   the way down. `enhance_level > 0` halves (integer division floors — that is the ruling, not a
   bug); otherwise `rank > 0` decrements; otherwise the item is untouched.
7. `advance_turn()` sweeps expired caches after incrementing, dropping them and their items. A cache
   is **alive while `turns - turn_lost <= 15 + reliquary_decay_turns_bonus * reliquary_level`** and
   dead the turn after — pin the boundary with a test at exactly the deadline and exactly one past
   it. This makes `advance_turn(balance: BalanceTable)` an **autoload signature change**: fix both
   callers named in Existing architecture 3.
8. **Survives save and reload through real disk**, in `tests/save_roundtrip_check.gd`, not an
   in-memory `to_dict`/`from_dict` pair — the shortcut `P2-05a` and `P2-04e` both shipped and were
   reopened for. A recovered item is in `inventory` and its cache is gone after reload; a swept
   cache stays gone. Note that file's checks share one `GameSession` in a fixed `_run()` order
   (`P2-08`), so leave `inventory` as you found it.
9. Existing tests still pass and the import gate is green — zero errors, zero warnings.

### Files allowed to change

`zones/zone_definition.gd` · `equipment/item.gd` · `equipment/lost_cache.gd` ·
`systems/game_session.gd` · `hub/hub.gd` · `hub/hub.tscn` · `hub/expedition/expedition.gd` ·
`tests/unit/test_expedition.gd` · `tests/save_roundtrip_check.gd` · a new `tests/unit/test_recovery.gd`

Five consecutive tickets got this list wrong (`P2-04g`, `P2-18`, `P2-20`, `P2-21`, `P2-23`), four by
omitting a live call site and one by naming a file that never changed. **Grep first, then write the
list** — and if the work needs a file that is not here, say so in the return rather than editing it
quietly or skipping the work.

**And this one made it six.** `hub/expedition/expedition.gd` was added above *after* the fact: it is
one of the two `advance_turn()` callers this ticket's own Existing architecture 3 names by
`file:line`, and criterion 7 changes that signature, so the ticket forbade the file it required. The
implementer flagged it and edited it rather than silently skipping criterion 7 — the right call, and
the reason the streak cost nothing this time. The lesson is narrower than "grep first", which this
list *did* do: **the grep found the caller and the list was written from the seam instead.** A
signature change's allowed-file list is its call-site grep, not the files the feature is about.

### Non-goals

- **No combat, no waves, no death, no XP, no loot, no stones.** A recovery run is a power check and
  a retrieval; `SYSTEMS.md` grants it no reward beyond the gear and no risk beyond Damaged. Do not
  route it through `Expedition.resolve()` or `QuickResolve` — it has no wave to fight, and the
  combat seam is ADR-fixed at two implementations of one signature.
- **The Reliquary stays unbuildable.** `hub.tscn` offers upgrade buttons for buildings 0–3;
  `building_levels[4]` stays `0`, so `reliquary_decay_turns_bonus` and
  `reliquary_damage_chance_reduction` are read but never non-zero in play. Both are wired anyway so
  the follow-up ticket is a button, not a rewrite. That follow-up is `P2-21`'s shape and is not
  this ticket.
- No affixes, no Cores, no new `BalanceTable` field, no zone-unlock check on a cache (the cache is
  proof the player was already there).

### Findings

**The design gap was in the spec, not the code, and only reading for the ticket found it.** The row
listed two open questions (both `clampf` residues). The one that actually blocked implementation was
a third nobody had named: `SYSTEMS.md`'s Damaged clause described **two systems that do not exist**
— an `Item` is `def_id`/`rank`/`enhance_level`, while `equipment_affix_counts` and
`core_socket_counts` are authored and read by nothing. Its one implementable clause, halving
enhancement, is **dead for the commonest case in the game**: enhancement is gated behind Forge Lv1
and every fresh drop equips at `+0`, so a literal implementation would have returned typical caches
completely intact and made `damage_chance` decide nothing. That is this backlog's "reads real,
measures nothing" trap for the sixth time. The generalizable part: **a row's stated blocker list is
not its blocker list.** `P2-11` and `P2-22` both shipped against stale premises; this one had a
missing premise instead, and the only thing that surfaced it was tracing the ruling down to the
fields it would have to write.

**The two inherited `clampf` residues were accepted unchanged, and the reason is worth keeping.**
Both are downstream of `P2-07a`'s level-5 cap, which was chosen *because* `0.03 * 5` cancels the
`0.15` base cleanly — so reopening either residue reopens that cap on no stronger evidence than
justified it originally. They are also unreachable in play: the Reliquary has no upgrade button, so
`building_levels[4]` is permanently `0`. Both magnitudes are wired anyway, which makes the follow-up
that adds the button a button and not a rewrite.

**Pre-tick ordering is a ruling, not an implementation detail.** `recover_cache` computes
`damage_chance` from `turns` and calls `advance_turn(balance)` last, so a cache recovered on the turn
it was created reads `turns_elapsed == 0` — which is precisely what `P2-23` shipped `turn_lost` for.
Ticking first would read `1`, and **every gate stays green either way**. It was written into the
criterion rather than left to the implementer for that reason, following `P2-07b`'s precedent of
putting the failure history in front of the person making the decision.

**Sixth consecutive wrong allowed-file list, and the first where the grep was actually done.**
`hub/expedition/expedition.gd` is named by `file:line` in the ticket's own Existing architecture 3 as
one of two `advance_turn()` callers, and criterion 7 changes that signature — so the ticket forbade a
file it required, having already found it. The narrower lesson is above: **a signature change's
allowed-file list is its call-site grep, not the files the feature is about.** It cost nothing here
only because the implementer flagged and edited rather than silently dropping the criterion.

**`recover_cache` never clears `cache.items`,** so each recovered `Item` is briefly reachable from
both `inventory` and the orphaned cache. Nothing duplicates — the cache leaves `lost_caches` in the
same call and is collected — but the disk round-trip originally asserted only *presence* after
reload, which a duplicate would have passed. It counts now. Verifier-flagged, fixed before commit.

**Two accepted gaps.** `_refresh_lost_caches` resolves each cache's zone on every `roster_changed`
emit, so a cache with an unresolvable `zone_id` `push_error`s per refresh rather than once — noise
only, and reachable only from a hand-edited save, but a GUT test that provokes it will redden on the
unconsumed error rather than on its assertion (`P2-23`). And `recover_cache`'s roster-membership
refusal (`not roster.has(hero)`) is defensive code beyond criterion 3's four named refusals and has
no dedicated test; traced correct, not asserted.
