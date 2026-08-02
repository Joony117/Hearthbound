# Tasks

Tickets, not feature names. "Add an inventory system" hands an implementer dozens of
architectural decisions; the format below doesn't.

Every ticket produces **one observable player-facing behavior**. A ticket that produces a
file is too small. A ticket that produces a subsystem is too large.

This document doubles as the delegation payload — scope, acceptance criteria, constraints,
build/test commands, decision bounds. One write, both purposes.

**Status:** `TODO` · `WIP` · `DONE` · `BLOCKED`

`tech-lead` owns ticket **bodies**; the director owns **status transitions**. A status word is
not content, and the director is the only role that sees a ticket's gates come back green.
Stale status is expensive here — `tech-lead` reads this file first and an `implementer` takes
its scope from the ticket, so a ticket left `[TODO]` after it lands gets rebuilt.

---

## Ticket format

```md
## PX-NN — Title                                          [STATUS]

### Objective
One observable player-facing behavior.

### Existing architecture
The 3-5 facts the implementer needs. Which Resources exist, who owns state,
which signals already fire.

### Acceptance criteria
Concrete and checkable. Include "survives save and reload" whenever state changes.
Include "existing tests still pass."

### Files allowed to change
Explicit paths.

### Non-goals
The adjacent features the implementer must NOT invent.
```

**Per-ticket loop:** inspect → explain the existing flow → propose the smallest change →
implement only approved scope → run tests and launch the scene → review errors and warnings
→ inspect the diff → commit the working state → update docs if a boundary moved.

**Stop rule:** after two or three failed patches on the same error, stop patching. That is a
structural problem being treated as a syntax problem. Reassess.

---

# Phase 1 — Walking skeleton

Goal: prove the project travels launch → gameplay → completion → back, and exports from a
clean checkout. **Resist making any of it good.** Everything here is replaced in Phase 2.

**Status: COMPLETE.** All four tickets `[DONE]`, all eight checklist rows pass, and the manual
exit gate passed — the packaged binary was walked by hand and **permadeath persisted across a
real quit and relaunch**. That was the one criterion no headless run could prove, and it is the
whole reason Phase 1 existed: the loop runs in a shipped build, not just in the editor.

Phase 2 is cleared to start.

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

# Phase 2 — Complete but ugly core loop

Backlog. **Deliberately not expanded into full tickets yet** — Phase 1 will teach us things
that change the wording, and writing eleven speculative contracts is exactly the premature
work this process exists to avoid.

Expand each into the full format when it comes up.

**P2-01 split.** The original backlog line bundled three independent Resource domains (hero,
equipment, zone) plus a shared tunables container behind one line. That is a subsystem, not
one behavior, and the tunables container's shape is still an open `godot-architect` call. Split
into a numbered sequence; `P2-01a` is expanded below and is where to start.

| # | Objective | Notes |
|---|---|---|
| P2-01a | `HeroDefinition` Resource + 5 archetypes authored | Expanded below. Start here — unblocks P2-02. |
| P2-01b | `ZoneDefinition` Resource + 3 zones authored | Expanded below. Unblocks P2-03. |
| P2-01c | `EquipmentDefinition` Resource + 10-slot enum | Needed before P2-04 (lost-gear caches); no item instances authored yet — no loot table exists before P2-04. |
| P2-01d | `BalanceTable` Resource + `balance.tres` authored from `SYSTEMS.md` | Expanded below. Container shape is settled (`DECISIONS.md`, one `BalanceTable`). Needed before P2-02 can consume real summon weights — sequence before or alongside P2-02, not after. Does **not** move `Hero.RANK_NAMES` — split out below. |
| P2-01d-2 | Move `Hero.RANK_NAMES` onto `BalanceTable`; repair its three call sites; author the Summoning Circle's two-field schema | Expanded below. Unblocked by `godot-architect`'s ruling on reaching shared Resources without a fourth autoload. Not required before P2-02 — P2-02 already replaces `hub/summon/summon.gd` wholesale and can read a rank count off `BalanceTable`'s rank table directly, so this can trail P2-02 instead of gating it. |
| P2-02 | Real summon against the weight table; roster and equip UI | Replaces P1-02. Carries the `def_id` → `HeroDefinition` lookup — `godot-architect` returned `cannot-judge` on this seam because no lookup consumer exists yet, but named this the ticket that builds one. A `def_id` matching no `HeroDefinition` must fail loudly, not silently default (`CODING_RULES.md:121-122`). |
| P2-03 | `quick_resolve.gd` — waves, HP carry-forward, retreat threshold, permadeath | Replaces P1-03. **Add GUT here.** |
| P2-04 | Lost-gear caches on death + recovery expeditions with damage rolls and decay | |
| P2-04a | XP-per-level curve for expedition rewards | Found by `game-designer`, deliberately not authored by it — a genuine missing `balance.tres` input with no ticket owning it yet. Crosses into expedition-reward territory, so it sequences here, not in the P2-01 group. |
| P2-05 | Salvage → parts → enhance → part conversion | Cores deferred to Phase 4 |
| P2-06 | Sacrifice → essence → rank up, with dupe resonance | |
| P2-07 | Five buildings as five integers | |
| P2-08 | Full save/load round-trip through `SaveService` | |
| P2-09 | Summon Stone income rate — how a player actually acquires stones | Found by `game-designer`, deliberately not authored by it — a design input, not a Resource-authoring task. Nothing defines acquisition rate today, which makes the verified ~327-pull spine number unvalidatable against real play time: the ratio is sound, the pacing is unknowable without this. Needed before the Phase 2 exit question below can be honestly answered. |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3. (See
P2-09 — that question can't be honestly answered until stone income rate is defined.)

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

## Commands

Import check / `BUILT`:

```bash
cd /e/Game && powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1
```

Run the script, not `--headless --quit` directly — the raw command **exits 0 while printing
script errors**, so it is not a gate. See `CLAUDE.md` for why, and for the cold-cache warm-up
the script performs.

Tests (Phase 2 onward):

```bash
cd /e/Game && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Export:

```bash
cd /e/Game && mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe
```

The `mkdir` is required — Godot does not create its own export directory, and `export/` is
gitignored, so a clean checkout hits this every time.
