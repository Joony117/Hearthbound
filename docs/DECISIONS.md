# Decisions

Dated architecture decision records. **Record what was rejected and why**, so a later pass
doesn't "simplify" the architecture by undoing something deliberate.

Newest first.

---

## 2026-09-23: Masterwork draughts are two more supply kinds, not a tier on the old ones

**ACCEPTED by the director, 2026-09-23**, on the owner's ruling to build masterwork draughts now
(`ig-wgj.11`, after `ig-wgj.10`). Drafted by the `godot-architect` hat. Design: `GAME_SPEC.md`
§ Heroes staff the buildings. Numbers: `SYSTEMS.md` § Keepers and professions. This entry exists
because the change crosses two boundaries: the combat seam (#4), since the battle simulation
spends supplies, and the save (#1), since supplies, loadouts, escrow and in-flight battle states
are all saved.

**What moves.**

1. **Two new kinds, `healing_masterwork` and `revival_masterwork`, in every place `healing` and
   `revival` live today:**
   - `GameSession.supplies`
   - battle loadouts, plus their `keep_*` floors
   - order escrow
   - `BattleState.supplies_remaining` and `BattleOutcome.supplies_remaining`

   Each is a plain integer stock, like the two that exist.
2. **One list of kinds.** Today the two kinds are written out by hand all over
   `systems/game_session.gd`: six `for kind in ["healing", "revival"]` loops, about ten dictionary
   literals, and `_validate_loadout`. `combat/battle/*` names them by hand too. That becomes one
   constant on `BattleState`, which both `systems/` and `combat/` may reference, and every site
   reads it. Adding a kind and missing a loop is exactly how a refund or an escrow silently skips
   the new stock.
3. **The old save shape still loads.** Every missing masterwork key reads as 0: in the profile,
   in saved loadouts, in escrow and in in-flight `BattleState`s. `SAVE_VERSION` is not bumped (the
   `P2-23` precedent). **Trap:** `_validate_loadout` requires exactly four keys today. It must
   accept the old four-key shape, or the loader must add zeroed masterwork keys first. Otherwise
   any save with an order in flight fails to load once this ships.
4. **The battle rule lives in the simulation only.** Restore amounts are `balance.tres` rows.
   - Auto-use spends the regular draught first, and a masterwork one only when that run's regular
     stock of the same kind is gone.
   - Manual use can pick either tier.
   - The 15-second per-user cooldown and the revival range are shared across tiers.
   - "Reserve last revival" counts both tiers together.
   - The unattended run, the watched run and the repeat safety forecast all go through the same
     `BattleSimulation` code, so they cannot disagree. Only `battle_v1` orders spend supplies
     today, and the new kinds follow that. No legacy path gets a draught rule of its own.
5. **Crafting is gated in the mutator.** The craft action refuses a masterwork kind unless
   `GameSession.keeper_is_master(&"Apothecary")` is true, with an exact preview. The Alchemy
   discount applies. Stock already brewed stays usable after the alchemist dies or leaves.

**Rejected.**

- *A tier field on the existing stocks* (for example `healing: {regular, masterwork}`). It turns an
  integer into a dictionary in every saved profile, loadout, escrow and battle state. That is a
  shape change, not an additive key, and every reader would need a migration.
- *A separate masterwork supplies dictionary.* That is a second escrow, refund and validation path
  beside the first. Refund-exactly-once is already hard to hold on one path.
- *Restore strength scaled by the brewer's skill.* Every draught would then carry its own quality,
  so stocks stop being integers. The owner's rule is binary: master or not.
- *Letting the forecast assume regular draughts only.* Then the forecast and the run disagree, and
  that is the failure the repeat safety check exists to prevent.

**Sequencing.** This touches `combat/battle/*`. It does not start while another bead is editing
those files. Engine access is serialized as usual.

---

## 2026-09-23: The town is the interface — buildings open panels, heroes staff them, the body is saved, ambient heroes are not

**ACCEPTED by the director, 2026-09-23**, with the staffing amendment (item 5) folded in. Drafted
by the `godot-architect` hat for `ig-wgj`. The owner scheduled the town on 2026-09-23 and asked for
the UI to live in it: click the blacksmith to upgrade, click the summoning place to summon, and see
your heroes walking around. The same day the owner ruled that the heroes themselves are the
shopkeepers, with their own profession skills. `GAME_SPEC.md` § The town hub and § Heroes staff the
buildings have the design. `SYSTEMS.md` § Keepers and professions has the numbers.
`ARCHITECTURE.md` § The town is the interface has the boundaries.

**What moves.**

1. **Buildings open panels by click.** This supersedes "proximity-gated panel visibility" from
   2026-08-13. It also supersedes the four-tab navigation from 2026-09-22's hub scene seam. The
   views stay as panel containers, with their `%UniqueName` controls intact. The Hall tab's mixed
   contents split across the buildings that own them. The opaque full-screen background from
   `hub_ui_builder.gd` goes, because it is the reason the 3D town has never been visible. A compact
   building list stays as a keyboard fallback: controller support remains a target.
2. **The embodied hero id is saved `GameSession` state.** It is additive: an absent key reads as
   "no body". On load it is dropped if the hero is gone or busy. It is enforced at the mutation
   boundaries, in `is_hero_protected()` and each dispatch entry point, which is where
   busy/protected checks already live (2026-09-22). This is a save-boundary change, so its ticket
   needs a real disk round-trip and a `verifier`.
3. **The town is a view under `hub/town/`,** instanced by `hub.tscn`. It emits ids upward, and
   `hub.gd` owns which panel opens.
4. **The KayKit model and animation loader moves to one helper under `heroes/`,** shared by the
   battle view and the town.
5. **Heroes staff the buildings (amendment, 2026-09-23).** A hero's station, its calling and its
   XP per profession are fields on `Hero`. They are saved through `Hero.to_dict/from_dict` as
   additive keys (`station`, `calling`, `profession_xp`), so this crosses save boundary #1. It needs
   a real disk round-trip and a `verifier`, and `SAVE_VERSION` is not bumped (the `P2-23` precedent
   for additive keys). `station` holds a town building id, and those ids are the building node
   names in `hub/town/town.tscn` (`Forge`, `Sanctum`, `TrainingHall`, `Reliquary`, `Apothecary`),
   the same ids `town_view.gd` emits. Renaming one of those nodes is now a save change too.
   - **Masterwork is a gate checked in the mutator.** Whether a building's keeper is a master
     (calling = the building's profession, and skill 5) is decided by `GameSession`, inside the
     action it gates. The UI only reflects the result. There are three gates:
     - `enhance_item` and bulk enhance read the capped value from `Item.compute_enhance_cap`
       (Forge, +13 to +15).
     - `rank_up_hero` refuses SS→SSS without a master priest who is home at the Sanctum (owner
       ruling, 2026-09-23). This is the only rank-up mutator, and the only caller is `hub.gd`.
     - The draught craft refuses masterwork kinds without a master alchemist (see the masterwork
       draughts entry above).
     What a master made (enhance levels, an SSS rank, draughts) is ordinary state and outlives the
     master. It is not re-checked on load, so heroes already at SSS keep their rank.
   - **Protected, not busy.** A stationed hero counts in `is_hero_protected()`, so sacrifice and
     bulk sacrifice refuse it. It is **not** in `is_hero_busy()`. Stationing must not block equip,
     rank-up or dispatch.
   - **The four dispatch paths are unchanged for keepers.** `dispatch_expedition`,
     `dispatch_force` (through `_preview_force_data`), `dispatch_rescue` and `recover_cache` accept
     a keeper, because keepers can be sent out by design. Their existing body check stays. The
     dispatch preview only reports which buildings lose their keeper while the force is out.
   - **The body and a station compose.** A keeper can be the body. The body is home, so the
     station keeps working. Each rule keeps its own check. Neither implies the other.
   - **Permadeath keeps one writer.** The station lives on the `Hero`, so when `kill_hero()`
     removes a hero, its station goes with it. No second code path runs after a death (rule 8).
   - **One keeper per building.** The `GameSession` stationing mutator enforces it. On load, if
     two heroes claim one building, the first in roster order keeps it and the others are cleared
     with a `push_warning`. Unknown building or profession ids are dropped the same way.
   - **The calling comes from a stable hash of `instance_id`.** New heroes get it at creation.
     Legacy heroes get it on load, and it is written at the next save. `instance_id` is 16 random
     bytes, so the hash is uniform. No summon RNG draw is added, so seeded summons and their tests
     do not shift.
   - **Keeper bonuses go through the existing pure formulas.** `GameSession` finds the home
     keeper's skill for a building and passes it as one more argument to the formula that already
     reads that building's level (`Item.compute_salvage_yield`, `Hero.compute_essence_yield`, the
     Training Hall XP multiplier, the Reliquary lifetime, the draught cost). The magnitudes are
     `balance.tres` rows (rule 9).
   - **Combat never reads a profession.** `combat/`, `Hero.compute_final_stats`, `hero_power` and
     the repeat forecast stay blind to it. A test asserts that final stats are identical whatever
     a hero's professions are.
   - **XP only builds up on the live tick** (`_advance_clocks_in_memory`), never in the
     offline catch-up (§ Hard constraints). The calling multiplier is applied when XP is earned,
     so the saved total is plain XP, and the skill level is derived from it on read.

**Rejected.**

- *A separate town scene.* Already rejected on 2026-08-13; reaffirmed. Instancing a sub-scene is
  not routing.
- *Keeping proximity-only panels.* The owner asked for click, and on 2026-09-23 ruled that a far
  click walks the body there and then opens the panel. That is a view behavior, not a boundary.
- *Treating the body as busy.* `is_hero_busy()` also gates equip, unequip and rank-up. The body
  should be gearable. Only spending it (dispatch, sacrifice) is refused.
- *Not saving the body.* It would be cheaper, and it would lose the player's choice on every
  launch. The rule "you must step out before you spend it" is clearer when the body is stable.
- *Auto-picking a body.* It would silently lock a hero out of dispatch without the player ever
  choosing. `GAME_SPEC.md` says stepping out is a deliberate act. Stepping in should be too.
- *Town code calling `BattleUnitView._shared_clips()`, or a copy of the loader under `hub/`.* The
  first couples the town to battle-view internals. The second drifts: two libraries, two
  loop/root-pin rules.
- *Saving ambient hero positions or townsfolk state.* That is presentation in the save, which
  adds save-boundary surface for no gameplay. It is re-derived on load.
- *A `TownManager` autoload.* Nothing the town holds is both persistent and outside the profile.
- *Making a station a busy state.* It would block dispatch, equip and rank-up. It would also erase
  the tension the owner's ruling creates: your best fighter may be your best smith.
- *A building→keeper map on `GameSession`.* After a death it would need cleaning, either in
  `kill_hero()` or on load. That is a second place that edits state after a death. A field on the
  `Hero` leaves with the hero.
- *Professions as a seventh stat, or read in `compute_final_stats`.* The six stats are settled by
  ADR. A profession is read by its own building and nothing else.
- *Rolling the calling from the summon RNG.* It would shift every seeded summon. Legacy heroes
  would also need a migration roll, and a load must not change on each run.
- *Decorative, non-roster keepers.* The owner ruled that heroes are the keepers.
- *Re-checking masterwork on load, or clawing back a dead master's work.* Enhance levels and
  draughts are ordinary state. If a master's death undid them, a second path would edit state
  after a death (rule 8).
- *A crafting system so the Forge can "make masterwork equips".* § Scope boundaries excludes
  crafting trees. Masterwork gates an output tier the building already has, and adds none.

**Left open on purpose.** Base builder and NPC economy (placement as save state; production;
offline behavior against § Hard constraints) are direction only, with no ticket and no
scaffolding. Professions are the labor it would read, and research is parked there (owner,
2026-09-23). Masterwork draughts have their own entry above.

---

## 2026-09-22: Autonomous squads, RTS intervention, and recoverable downed heroes

The owner approved the director's complete squad-command proposal and downed/rescue rules,
then explicitly authorized implementation with parallel Sol/Luna workers. `ig-544` contains
the accepted implementation plan, exact data/command contracts and validation gates;
`ig-yzc` now means observing and commanding an existing expedition, not piloting one hero.

One fixed-tick simulation serves watched and unattended battles. Persistent battle checkpoints
are an explicit extension of dispatch-order profile data; no scene objects enter the save or
autoload, no fourth autoload is added, and combat rules remain static domain functions.
`BattleView` is a new SceneRouter destination. It renders snapshots and submits commands,
never rewards or deaths. Practice owns a local simulation with no profile consequences.
The legacy action arena/CombatResult seam is preserved for compatibility but no longer defines
the production expedition direction. The six-stat model and one Wave ramp stay unchanged.

**Rejected:** a decorative battle replay over an unrelated statistical result, a second loot
settlement when opening a battle, immediate permanent deletion at zero HP, forcing thirty
individual skill bars onto the player, and building a seamless procedural world for the first
regional mission. Squads remain 1-5 member presets; authored missions set their force caps.

Route minimum and battle time advance in parallel. Completion waits for both; a wipe creates
a stranded incident. Offline processing advances the current run only. Tactical pause stops
the viewed battle, not the other expeditions, and clears on leaving/reload. Supply allocations
are shared per-force spending escrow; unused allocations refund exactly once. Explicit
commands and terminal changes use the existing save transaction boundary.

Downed allies can be revived by living teammates or carried out. A full force wipe permits
rescue or abandonment. Incidents are separate from lost-gear caches and from one another;
failed rescuers join only their source incident. Its reviewed active-play deadline never ages
offline or resets on failure. An active rescue may finish after expiry; remaining stranded
heroes are then finalized through Expedition and the existing sole roster-removal writer.

Rescue settles at the end of its real fight/extraction, without a separate return timer.
Applying raid/region force-size travel to five rescuers produces minimum waits of 720/1800
seconds against an initial 900-second incident window, obstructing successive carry attempts.
Rescue grants no farming rewards, so the expedition return gate serves no purpose there.
Normal full wipes close their order immediately; partial withdrawals wait for survivor return,
then create the incident and close the source order atomically to avoid conflicting reservations.

Schema 3 migration preserves stable identity/resources/orders. For v2 in-flight orders,
prior offline time reduces remaining route once and the new battle starts at tick zero.
This may extend the previous ETA but cannot invent combat, rewards or immediate deaths.
The migration is committed before play and invalid/future saves remain protected.

The first native battlefield capture exposed unreadable small units, an empty gray surround,
and a selection inspector that did not refresh while paused. The director set initial camera
sizes to 32/44/60 for standard/raid/region, centered the standard view at world z=-4, and kept
a local dark forest environment with a larger ground apron, subtle grid and readable chibi
heads/class silhouettes. These are presentation rules; camera or rendering never changes the
simulation. The paused inspector refresh is required for tactical commands.

Initial enemy-budget HP×2/ATK×0.20 values failed all eight measured starter-team runs. Revised
HP×1/ATK×0.04 remains provisional until measured from actual spawned actors. The failed
in-memory override experiment is explicitly excluded from balance evidence.

The first scene/input seam is desktop RTS: box selection, contextual commands, squad hotkeys,
orthographic pan/zoom, abilities/items and tactical pause. The historical first-class action
gamepad requirement remains a future RTS input task, not a claim of gamepad acceptance here.
Chibi primitives are the authored first visual style. Ability/supply/raid numbers are
provisional and must not be described as playtested merely because tests or profiling pass.

---

## 2026-09-22: Timed parallel expeditions, persistent teams, and protected bulk management

Owner approval: implement all of the director's `ig-6l4` proposal. This supersedes the original
`GAME_SPEC.md` no-clock/no-offline-accrual constraint for already-dispatched expeditions. It does
not add an energy system, paid waits, servers, or unlimited offline farming. Each dispatched
run may finish while closed; a repeat starts only in the running app. Separate teams can work
concurrently, with exclusive reservation of their heroes and equipped gear.

Duration falls with the square root of strength relative to the zone's team-size-scaled power,
has a per-zone floor, then accounts for the same workload being covered by fewer heroes through
`5 / team_size`. The last factor matters because existing enemies already scale down linearly:
without it, splitting a squad into five solo parties would multiply output at the same combat
difficulty. Existing combat damage, rewards, and success semantics remain unchanged. A local
lost-wave roll is not an expedition defeat; surviving the boss still completes the run.

**Rejected:** a timer added to the old click loop without presets or repeat orders, manual
reward-claim chores, fixed dispatch slots unrelated to roster depth, and a new stamina currency.
Finite orders stop on casualties/retreat/failure or a stop-after-return request. Unlimited orders
require a worst-case attrition forecast using the actual wave ramp and retreat rule; one lucky
clear is not proof of safety. Timing values remain explicitly provisional in `SYSTEMS.md`.

Stable serialized hero/item identities and schema-2 migration are required by saved presets and
in-flight orders. Presets preserve missing members instead of silently substituting. Orders
capture membership/destination at dispatch. Timed orders belong to the persistent profile,
while transient wave HP still belongs to `Expedition`; this does not reverse the rejected
combat-state autoload decision. There are still exactly three autoloads. Pure expedition and
bulk rules live under `hub/`. Shared balance stays in `balance.tres`; per-zone durations join
the existing authored recommended-power/wave/reward data on `ZoneDefinition`.

`GameSession` batches a return into one state change and `SaveService` persists it atomically,
including rewards, deaths, cache, report and order advancement. A saved local RNG seed makes a
pre-commit retry reproducible.
Write failure rolls memory back; future/invalid new-schema saves refuse play and writes instead
of becoming overwritable fresh profiles. The public combat-result seam and central hero-removal
path remain unchanged. Confirmation previews are revalidated against current identities,
protections, inputs and costs before bulk operations commit.

**Recovery changes deliberately.** Expedition-count cache aging is unsuitable when many
returns can arrive unattended. Caches now age in active recovery minutes, not completed runs
or offline time. New gear losses pause this clock until explicitly reviewed. The base window
is 15 minutes, extended by 5 minutes per Reliquary level; its existing damage reduction remains.
The old elapsed-turn damage term becomes elapsed active minutes. Legacy caches map old elapsed
turns to minutes and begin paused. This preserves the Reliquary's two functions while removing
the punishment for running more teams. These timings require playtesting; source arithmetic
does not settle their feel.

**Hub scene seam:** `hub.tscn` remains the existing main scene. Its panels are reorganized into
Expeditions, Teams, Armory, and Hall views under the same CanvasLayer, with modal confirmation
and pause controls outside view visibility. Reparenting requires updating every affected
`.tscn` connection path and runtime-verifying all existing unique-name lookups and handlers.
No separate town scene or new SceneRouter destination is introduced. The established ink-green,
brass and ivory theme is retained, including dark focused text on brass primary buttons.

The four views are assembled from native Godot controls by `hub/hub_ui_builder.gd` before
`hub.gd` resolves its `@onready` bindings. This replaces the former static panel subtrees and
their `.tscn` connection paths with named controls and script-connected signals; the 3D hub,
CanvasLayer, confirmation and pause roots remain in `hub.tscn`. The tradeoff is that the full
panel layout is previewed by running the scene rather than by inspecting the static scene tree.
Shared roster/detail controls avoid duplicating selection state across Teams and Armory.
Existing `%UniqueName` contracts and interaction tests must remain valid after assembly.

Favorites, preset membership, and active reservations protect heroes from bulk sacrifice;
equipped/favorite items are excluded from salvage. Enhancement may improve favorite inventory
items within explicit per-rank budgets. Conversion exposes a keep-at-least reserve and never
cascades ranks. No automatic destructive processing is added. Existing controlled-expedition
and mid-run-intervention directions (`ig-544`, `ig-yzc`) remain outside this implementation.

---

## 2026-09-21: Serena reinstated on demand for native GDScript symbols

The owner requested Serena, GitNexus, and Ponytail for this repository. Serena is enabled in the
repo's Codex configuration and connects to Godot's built-in GDScript language server on port 6005.
It uses an editor instance that is already open for this project; it does not install another
language server or add an always-running daemon.

This supersedes the 2026-08-04 removal decision only for requested Serena use. The lifecycle
constraint remains: the Godot editor/LSP and `tests/import_gate.ps1` are mutually exclusive because
both access `.godot/`. Close the editor before the build gate, and do not start or stop a user's
editor process as part of tool setup.

GitNexus is registered only as a bounded local index. GitNexus 1.6.9 and the current 1.6.12 release
do not support GDScript or `.gd` in their structural parser/extension maps, so its presence is not
evidence of symbol, call-graph, or impact coverage for game code. Ponytail 4.10.0 is already enabled
as a user plugin and needs no repository copy.

---

## 2026-08-13: The town is `hub.tscn` with an avatar, and the avatar is a controlled hero

User ruling, closing `TASKS.md` D-01a. Two answers, one architectural and one design.

**The town does not get its own scene.** `hub/hub.tscn` is already a `Node3D` — camera, ground,
five building meshes under `Buildings/` — with the roster/equipment/buildings/summon/sacrifice/
expedition panels on a `CanvasLayer` in the same tree. The walkable town is that scene gaining a
player-controlled body and proximity-gated panel visibility. `SceneRouter` is untouched, rule 5
is untouched, and no new seam appears. Written up in `ARCHITECTURE.md` § The town is `hub.tscn`.

**Rejected: a separate `town.tscn` routed to from the hub.** This is the reading the direction
table was warning about, and it is the expensive one for a reason that is easy to miss — it does
not just duplicate scenes, it makes every shipped hub panel reachable from two places, which
means every panel needs an answer for "which scene am I in" forever after. The cheap version of
that (town hosts *copies* of the panels) is the "every shipped hub feature gets rebuilt" outcome
stated verbatim in `TASKS.md`'s D-01 row. Nobody would choose it deliberately; it gets chosen by
assuming a new feature needs a new scene. It does not — the 3D hub has been sitting there since
the skeleton.

**The player embodies a roster hero, swappable at will**, not a summoner avatar.
`GAME_SPEC.md` § The town avatar is the design half. The architectural consequence is the one
worth recording here: **an embodied hero cannot be sent on an expedition.** That is a design
rule with teeth (you must step out of a body before you can spend it) and it is deliberately
*not* implemented as an exception inside the permadeath path — it is a filter on team selection,
upstream of `Expedition.resolve()`, which keeps rule 8 at exactly one writer with no special
case. A rule that reads "permadeath, except when" is how single-writer boundaries rot.

**Rejected: the summoner as the town avatar.** It is the more literal reading of Player fantasy
("You never fight as yourself") and it has a real advantage — an avatar with zero coupling to
permadeath cannot be deleted out from under the camera. Refused because it buys that safety by
putting a body in the world that the roster does not contain, which needs its own model, its own
answer to "what am I to the roster", and an explicit hand-off at the gate for `D-02` where the
summoner stops and a hero starts. The hero avatar makes `D-02` continuity instead of a seam, and
the fantasy still holds: the summoner is steering, which is what the arena already does.

**What changes in the code: nothing.** This ruling produces no scene, no script and no behavior.
`D-01` is still unwritten and still unscheduled — the core loop comes first and the Phase 2 exit
question still governs. What it removes is the reason `D-01` could not be *written*.

---

## 2026-08-11: The arena is a combat-feel prototype; permadeath is not wired to it

User ruling, and it reverses a published line in `GAME_SPEC.md`. That document's Combat model
section said "Permadeath applies identically in both paths" from the first commit. It no longer
does.

**The arena is where combat feel gets prototyped, not a path the core loop resolves through.**
It keeps the seam it already has — a real `Wave` in, a real `CombatResult` out — and that result
stays **display-only** for the foreseeable future. `Expedition.resolve()` remains the sole
permadeath consumer (rule 8, unchanged and now load-bearing for a second reason).

**Why this is an ADR and not a `KNOWN_ISSUES.md` line.** Arena permadeath was unfiled, not
decided. `P2b-05`'s Findings recorded it as "still unwired and now reachable in one sitting",
which reads as a gap somebody should close; the next reader would have closed it. It is not a
gap. Writing it down as a decision is what stops the wiring from happening by default.

**What changes in the code: nothing.** `hub.gd`'s `_show_pending_arena_result()` already only
prints, `arena.gd` already never calls `kill_hero()`, and no ticket was open against either.
The one edit this ruling actually earns is the defeat string, which said a hero *fell* — the
lie was cheaper to fix than to leave (`hub/hub.gd:741`).

**Permadeath in player-controlled combat is deferred, not cancelled.** It lands with controlled
expeditions (`GAME_SPEC.md` § Direction), where a death is the consequence of a run the player
chose to walk into rather than the outcome of a practice bout entered from a hub button. Nothing
about that later wiring is designed here.

**Rejected: wire permadeath to the arena now, matching quick resolve.** It is the consistent
answer and the wrong one at this stage. Every arena number is `PROVISIONAL` and unplayed —
`arena_enemy_hits_to_kill_hero = 3` most of all, since nobody has died in the arena — so the
first thing permadeath would price is a feel value nobody has validated. Tuning combat weight is
a loop you want to run dozens of times per sitting; permanent loss per attempt makes that loop
cost a hero, and the tuning stops happening.

**Rejected: strip the arena's `CombatResult` down to a feel harness with no seam.** Tempting on
laziness grounds — the result is display-only, so the type buys nothing today. Refused because
the seam is the one structural decision `DECISIONS.md` 2026-08-01 made before the vertical slice
existed, and a controlled expedition is a third `resolve()`-shaped consumer of it. The arena is
the only live proof that a second implementation can satisfy the shape at all.

**Consequence for `KNOWN_ISSUES.md` § "Quick resolve and the arena will disagree".** Divergence
between the two paths is no longer a defect to size — the arena resolves nothing, so there is no
outcome to disagree about. That entry is amended rather than closed: it comes back the moment a
played path resolves a real run.

---

## 2026-08-06: The 2026-08-01 rejection of rank-up/salvage logic on `GameSession` is reaffirmed, not reversed — three shipped methods are debt

`godot-architect` ruling on a conflict `tech-lead` flagged while scoping `P2-06a`: the 2026-08-01
"Three autoloads, hard cap" entry rejects "putting rank-up and salvage logic as methods on
`GameSession`, which would make them untestable without booting the engine." `salvage_item`
(`P2-05d`), `enhance_item` (`P2-05f`), and `convert_parts` (`P2-05g`) shipped anyway, as instance
methods on `GameSession` that inline their own validation and arithmetic
(`systems/game_session.gd:57,70,86`).

**Ruling: the code is wrong, not the ADR.** The rejection's predicted cost came true exactly as
written — every GUT test that exercises these methods reaches them through the live `GameSession`
autoload singleton (`GameSession.salvage_item(...)` etc. in `tests/unit/test_equipment.gd`), and
there is no `GameSession.new()` anywhere in the codebase to test the logic in isolation. That is
evidence the original warning was correct, not evidence the project outgrew it. `CODING_RULES.md`
§ Autoloads still states the general principle in the present tense ("Game rules do **not** live
on autoloads") and its own worked example is named `compute_essence_yield(fodder, target,
balance) -> int` — the exact function `P2-06a` needs — so no reconciling document was ever
updated to bless the pattern that shipped. This was drift, not a considered re-decision.

The distinction the ADR draws is between **structural roster/inventory bookkeeping** (moving an
item between arrays, erasing a roster entry, deduplicating a cleared-zone flag — `kill_hero`,
`equip_item`, `unequip_item`, `mark_zone_cleared`, `add_hero`) and **balance-driven rule logic**
(a cost formula, a threshold check against a `BalanceTable`-sourced number, a multiplier). The
former is unavoidably a `GameSession` method because the state lives there and nothing else
should reach in and mutate it directly (that would just be a second, worse violation). The latter
is exactly what the rejection named, and `salvage_item`/`enhance_item`/`convert_parts` are the
latter: they take `balance: BalanceTable` and compute a cost or a credited amount inline instead
of calling a pure function that does.

**Disposition of the three shipped methods:** debt. Not reverted here — a working, tested,
save-round-tripped feature does not get unwound by a documentation ruling — but named so a future
pass doesn't read them as precedent. A remediation ticket (extract each method's arithmetic into
a `static func` taking the same arguments plus `balance`, leaving the `GameSession` method as a
thin validate → call → mutate → emit wrapper) is `tech-lead`'s to open; this entry is the citation
for why.

**Outcome (`P2-12`, landed).** Two of the three were extracted — `Item.compute_salvage_yield` and
`Item.compute_enhance_cap`, both pure `static func`s that `tests/unit/test_equipment.gd` now calls
without an autoload in the test body. `convert_parts` was **not**, deliberately: its arithmetic is
`-3` and `+1` against a fixed rank index, with no `BalanceTable` number in it at all, so it is not
the "balance-driven rule logic" this entry defined the debt as. `upgrade_building` shipped the same
inline `10 * (level + 2)` shape after this entry was written and is the one open instance; its only
honest home is a `buildings/` file that does not exist, so it stays named rather than relocated.
The ruling itself is unchanged by any of this.

**`P2-06a` may add `sacrifice_hero` and `rank_up_hero` to `GameSession`** — the orchestration
(precondition checks against `roster`/`equipped`, calling `kill_hero()` for removal per
`ARCHITECTURE.md` r8, mutating `essence`, incrementing `resonance`, one `roster_changed.emit()`)
is structural bookkeeping of the kind `kill_hero` already does, and `sacrifice_hero` cannot be
relocated off `GameSession` regardless, since r8 makes `kill_hero()` the sole roster-removal call
site and only `GameSession` may call it as an internal step of one atomic operation. **But the
yield/cost arithmetic may not be inlined into those methods.** `P2-06a`'s ticket body must extract
two pure functions — `compute_essence_yield(fodder: Hero, target: Hero, balance: BalanceTable) ->
int` (the resonance-tripling condition included) and `compute_rank_up_cost(hero: Hero, balance:
BalanceTable) -> int` — that `sacrifice_hero`/`rank_up_hero` call before applying the result. This
is a naming/placement correction to acceptance criteria 2–3 as currently written, not a redesign:
the ticket body's own "Existing architecture" section already cites `CODING_RULES.md`'s
`compute_essence_yield` shape without applying it. The ticket body's line "Follow the code;
reconciling the ADR text is outside this ticket's remit" is struck by this ruling — the ADR text
did not need reconciling, the ticket's method bodies do.

**Rejected (this entry):** editing the 2026-08-01 sentence to say the opposite, on the theory that
four tickets shipping the same pattern makes it retroactively correct. Frequency of violation is
not evidence a rule should change; it is evidence nobody was checking. Also rejected: reverting or
refactoring `salvage_item`/`enhance_item`/`convert_parts` as part of this entry — that is a code
change belonging to an implementer ticket, not a documents-only ruling.

---

## 2026-08-02: The combat seam's second argument is `Wave` (`zones/wave.gd`, `RefCounted`), not `WaveDefinition`

`ARCHITECTURE.md:96` committed to `func resolve(team: Array[Hero], wave: WaveDefinition) ->
CombatResult` before `WaveDefinition` existed anywhere. A repo-wide sweep (all `.gd`/`.tscn`/
`.tres`/`project.godot`, non-docs) found zero references to `WaveDefinition` — no field list, no
consumer, nothing to preserve by keeping the name. P2-01b stored `ZoneDefinition`'s ramp
(`trash_wave_count`, `trash_wave_start_fraction`, `trash_wave_end_fraction`, `boss_fraction`) and
explicitly declined to write the interpolation that turns those endpoints into one wave's actual
composition, deferring the question to whoever names the type P2-03 implements against.

**Reason:** rules 2–3 reserve the `Definition` suffix and the `Resource` base for **authored**
data a human edits in the inspector — confirmed against the only two other implementations in
the tree, `heroes/hero_definition.gd` and `equipment/equipment_definition.gd`, both pure
`@export`-only `Resource`s with no methods. A wave is not that: nobody hand-authors individual
wave `.tres` files, and `zone_definition.gd` (read in full) stores only the ramp's endpoints, not
per-wave values — the per-wave composition is *derived* by interpolating that ramp for a given
index, at runtime, once an expedition is underway. That derivation is exactly the "runtime state
lives in `RefCounted` domain objects, never in a Definition" split rule 3 already draws for
`Hero`/`HeroDefinition`; a wave's relationship to `ZoneDefinition` is the same shape.

Naming it `zones/wave.gd` rather than `combat/wave.gd` follows that same precedent: `Hero`
(runtime) sits next to `HeroDefinition` (authored) in `heroes/`, so `Wave` (runtime) sits next to
`ZoneDefinition` (authored) in `zones/`. `combat/` keeps owning only what it produces
(`combat_result.gd`); it does not also own the type of the data fed into it.

Whatever computes the interpolation must do so in exactly one place and pass the same `Wave`
instance to both `resolve()` implementations. `CLAUDE.md` calls the two combat implementations
"independent... that must agree" — if each path re-derived a wave's enemy composition from
`ZoneDefinition`'s raw fractions independently, a lerp bug in one path would silently make that
path easier or harder than the other for the same zone and index, which is a correctness
regression the seam exists to prevent, not a legitimate independence between the two
implementations. Passing a pre-built `Wave` makes that agreement structural rather than a
discipline someone has to remember.

Also considered and rejected: taking `(zone: ZoneDefinition, wave_index: int)` directly and
dropping the wave type entirely, since it needs no new type at all and `ARCHITECTURE.md` already
warns against the combat seam growing. Rejected because it relocates the interpolation into
`combat/` itself (or worse, into each of the two implementations separately) with nothing in the
signature forcing both paths to share one computation — the exact duplication risk above. Adding
`Wave` is not seam growth in the sense the existing warning targets: that warning is about the
seam's *implementation shape* (no base class, no strategy registry for the two `resolve()`
functions), not about the number of plain data types crossing it — `CombatResult` already crosses
the seam on the way out without objection, and `Wave` is the same kind of thing on the way in.

**Rejected:** keeping the `WaveDefinition` name/`Resource` base (violates rules 2–3, since it
would carry runtime-derived data under the authored-only suffix); authoring per-wave `.tres`
files to make the `Definition` label literally true (nobody has asked for this, and it
contradicts what `ZoneDefinition` actually stores — a ramp, not a per-wave table); and dropping
the wave type in favor of `(zone, wave_index)` args (moves the "must agree" duplication risk into
`combat/`, where it's harder to catch, instead of eliminating it).

---

## 2026-08-02: Consumers reach `balance.tres` via `preload()`, not an autoload or `GameSession`

P2-01d-2 was blocked on this: `RANK_NAMES` "moves onto `BalanceTable`" only fixes where the data
ends up, not how anything downstream of the top of a call chain gets a `BalanceTable` reference
to pass into the pure functions `CODING_RULES.md` already specifies.

**Reason:** a repo-wide sweep found zero existing `preload`/`load`/`ResourceLoader.load` call
sites anywhere in this codebase's `.gd` files — this is a first-precedent decision, not a
convention lookup — and zero prior sketch of a registry/service-locator pattern in code, ADRs, or
`TASKS.md`. Godot's `ResourceLoader` caches by path: every `preload("res://balance.tres")`
anywhere in the project returns the same object, so no single call site needs to own loading it
and hand out the reference — the coordination problem a `GameSession`-held reference would exist
to solve doesn't exist. Putting it on `GameSession` instead would grow the one autoload whose
sole justification is surviving scene changes (`ARCHITECTURE.md`'s autoload table only lists
roster/inventory/buildings/caches/currencies under its ownership) and would make every
balance-consuming function's test depend on booting `GameSession` first to obtain it — the exact
"untestable without booting the engine" failure the three-autoloads ADR already rejects for
methods on a singleton. P2-01d's own acceptance criteria already assume a standalone headless
test can `preload`/`load` `balance.tres` directly with no `GameSession` involved; that only holds
if the production path is the same call.

The mutation hazard of one shared Resource instance (writing into an exported array in place
corrupts it for every consumer and can persist to disk) is identical under a `preload()`, a
`GameSession`-held reference, or an explicit pass-down — it is a property of sharing one instance,
not of how a consumer obtained the reference, so it is not a point against `preload()`
specifically. `TASKS.md`'s P2-01d ticket already documents the discipline (read-only by
construction, derive a local value, never write back) at the one consumer that comes close
(P2-07's building effects); no new enforcement mechanism is being added for it here.

**Rejected:** `BalanceTable` as a fourth autoload — no case exists for a permanently-loaded root
node over a plain Resource with a cached path. Also rejected: `GameSession` holding a
`BalanceTable` reference and consumers reading `GameSession.balance` — scope creep on the one
autoload already at its stated limit, and it reintroduces an engine-boot dependency for testing
balance-consuming functions that a plain `preload()` doesn't have.

---

## 2026-08-02: `Hero.rank_label()` takes `balance: BalanceTable`, not a UI-side lookup

Follows from the entry above and from `RANK_NAMES` moving off `Hero` (2026-08-01 entry below). A
sweep found exactly three real consumer call sites of `Hero.RANK_NAMES`/`rank_label()`:
`hub/summon/summon.gd:17`, `hub/hub.gd:26`, `hub/hub.gd:35` (`heroes/hero.gd:7,20-21` is the
definition itself, not a consumer) — the prior 2026-08-01 entry's claim that
`tests/save_roundtrip_check.gd` also references `RANK_NAMES` does not hold; that file has zero
hits for it.

**Reason:** `rank_label()` stays an instance method on `Hero` and gains a `balance: BalanceTable`
parameter — `func rank_label(balance: BalanceTable) -> String` — indexing `balance.rank_names`
instead of the removed `Hero.RANK_NAMES` const. This is the smallest diff at the three real call
sites (add one argument, once each), it mirrors the exact shape `CODING_RULES.md` already
prescribes for functions that need balance data, and it keeps "describe this hero" behavior next
to the `Hero` it describes rather than teaching every UI call site to index a `BalanceTable`
array (and repeat the clamp) directly.

This is **not** a scene↔script boundary change under `CLAUDE.md`. `hub/hub.tscn`'s only
`[connection]` entries wire `_on_summon_pressed`/`_on_expedition_pressed` by method name, and the
`pressed` signal carries no arguments — adding a parameter to an internal call to `rank_label()`
inside those method bodies renames no node, no `%UniqueName`, and no `[connection]` entry. The
recommended access shape (a `const` `preload` inside `hub.gd`) needs no new node or unique-name
binding either. A `verifier` pass on the resulting diff is still reasonable given the file sits on
that seam, but is not mandated by `CLAUDE.md`'s own definition of boundary item 2 for a diff of
this shape.

**Rejected:** a shared static helper (e.g. a `RankLabels` free function) ahead of a second real
consumer — `EquipmentDefinition`/`Item` don't exist until `P2-01c`, and building shared
infrastructure for a duplication that isn't real yet repeats the ordering the "Skeleton first,
architecture third" entry below already rejected. Also rejected: a lookup method on `BalanceTable`
itself — the 2026-08-01 entry already commits `BalanceTable` to holding "only exported data, no
methods," and the smallest diff that respects that without reopening it keeps the method on
`Hero`.

---

## 2026-08-01: `balance.tres` is one `BalanceTable` Resource, not several

P2-01d left the shape of the shared tunables container as an open `godot-architect` call:
one `BalanceTable` holding every table in `docs/SYSTEMS.md` (rank multipliers, level caps,
affix/socket counts, essence bases, rank-up costs, summon weights, building effects), or
several smaller Resources split by subsystem.

**Reason:** r9 already names a single file (`balance.tres`), and `CODING_RULES.md`'s own
convention is "prefer one Resource type with exported fields over N subclasses" — the same
reasoning that gave `EquipmentDefinition` one shape instead of ten. More concretely,
`SYSTEMS.md`'s own formulas already cross-reference multiple tables in one expression (the
sacrifice formula reads `essence_base[fodder.rank]` and `level_cap[fodder.rank]` in the same
line; the rank table itself groups stat multiplier, level cap, affix count, and socket count
per rank as one row). Splitting these into separate resources doesn't remove any coupling —
the game design already coupled them — it just forces every pure function that consumes
balance data to thread N resource arguments instead of one, for no isolation gained.

This is not the rejected `GameManager` shape. The god-object failure mode that entry
describes is *behavior* accreting onto a *singleton* until nothing is testable without
booting the engine. `BalanceTable` holds only exported data, no methods, and is not an
autoload — it is passed as a plain argument into pure static functions
(`compute_essence_yield(fodder, target, balance: BalanceTable)`, per `CODING_RULES.md`).
A data resource with many exported fields is not the same shape as a singleton that
accumulates responsibilities.

**Rejected:** several small Resources split by subsystem (one for ranks, one for essence,
one for summon weights, one for building effects). `BalanceTable` is one Resource, one
`.tres`, authored under the project root as `balance.tres`, per `ARCHITECTURE.md` r9's own
wording.

---

## 2026-08-01: `Hero.RANK_NAMES` moves to `BalanceTable`, not before P2-01d

P2-01a explicitly left "moving `Hero.RANK_NAMES` off `Hero`" as a `godot-architect` open
call and out of that ticket's scope. Ranks apply to heroes and equipment identically
(`SYSTEMS.md`): once `EquipmentDefinition`/`Item` exist, they need the same eight labels.

**Reason:** `RANK_NAMES` is presentation data about the rank *system*, not about any one
`Hero` instance — it is the same shape as the rank table's other columns (stat multiplier,
level cap, affix/socket counts), which are already headed for `BalanceTable`. Leaving it as
a `const` on `Hero` (a `RefCounted` *instance* type) means the eventual equipment runtime
class either duplicates the same eight-string array or reaches across into `heroes/` to read
`Hero.RANK_NAMES` — the second option is a cross-feature-folder dependency this repo's
layout (`ARCHITECTURE.md`, "Project layout") is structured to avoid, and the first is the
kind of duplicated hardcoded array `ARCHITECTURE.md` rule 9 exists to prevent for numbers and
should equally apply to the labels describing the same axis.

This is **not** part of P2-01a. `hero.gd` is a file Phase 1 ships and gates green
(`tests/save_roundtrip_check.gd`, `hub/summon/summon.gd:17` both reference
`Hero.RANK_NAMES` today), and moving the const is a call-site-breaking change, not an
additive one — it belongs to whichever ticket first builds `BalanceTable` (`P2-01d`) or
first needs rank labels from a second domain (equipment, `P2-01c`), not to `P2-01a`.

**Rejected:** leaving `RANK_NAMES` on `Hero` permanently and having equipment either
duplicate it or reach into `heroes/hero.gd` for it.

---

## 2026-08-01: No `CombatState` autoload

Proposed fourth autoload holding the current expedition's wave index and per-hero HP between
waves, readable by both `combat/quick_resolve.gd` and `combat/arena/`.

**Reason:** rule 6 — "Autoloads hold no level-specific state" — is a direct hit. Wave index and
per-hero HP mid-expedition is created when an expedition starts and meaningless once it ends;
even `GameSession`, the one autoload justified by surviving scene changes, is explicitly barred
from owning combat or level state, so a new autoload for the same reason doesn't get a pass
either. It also undermines the seam it was meant to serve: the combat seam's whole point is that
`resolve(team, wave) -> CombatResult` is the only channel data flows through between the two
implementations, and a shared autoload both paths read from is a second, implicit channel
alongside it.

**Rejected:** the autoload. Wave index and in-progress HP belong on an expedition-scoped
`RefCounted`/`Node` (e.g. growing `hub/expedition/expedition.gd`'s `Expedition` past its current
Phase-1 placeholder) passed explicitly into `resolve()` — or read back out of `CombatResult`,
which already carries HP-after between waves.

---

## 2026-08-01: Skeleton first, architecture third

Development order is: thin walking skeleton → complete-but-ugly vertical slice →
architecture pass → content → hardening.

**Reason:** designing the full architecture before the loop is proven produces clean code for
the wrong game. Building an uncontrolled prototype produces something that looks 70% done and
is 25% done. The middle path is a skeleton small enough to throw away, then a slice ugly
enough to be honest, then extraction driven by observed pressure.

**Rejected:** designing the whole system up front. An earlier draft of the plan did exactly
this — full data model, systems layout, and folder structure before a single scene existed.

---

## 2026-08-01: Combat behind a two-function seam

Both combat paths implement `resolve(team, wave) -> CombatResult`. Nothing upstream can tell
which one ran.

**Reason:** the game needs a fast statistical resolver (for farming cleared content) and a
real-time playable arena (the selling point). Retrofitting the seam later means rewriting the
expedition system, so it is the one structural decision made before the slice exists.

**Rejected:** a `CombatStrategy` base class with two subclasses. Two functions with the same
signature do not need a hierarchy in GDScript.

---

## 2026-08-01: Three autoloads, hard cap

`SceneRouter`, `SaveService`, `GameSession`. A fourth requires an entry in this file.

**Reason:** Autoloads are just permanently-loaded root nodes, not a requirement for shared
systems. The failure mode in this genre is a `GameManager` that accumulates health, enemies,
inventory, quests, combat, UI, level loading, music, saving, and dialogue until nothing can
be tested in isolation.

`GameSession` earns its place because the player profile must survive scene changes
(menu → hub → arena → hub). That is its only justification — game *rules* stay in plain
functions that take what they need as arguments.

**Rejected:** a `GameManager`. Also rejected: putting rank-up and salvage logic as methods on
`GameSession`, which would make them untestable without booting the engine.

---

## 2026-08-01: Feature-grouped folders, not type-grouped

`heroes/` holds `hero.gd`, `hero_definition.gd`, and `defs/*.tres` together. There is no
`all_scripts/` or `all_resources/`.

**Reason:** Godot's own project-organization guidance favours grouping assets close to the
scenes that use them. Type-based silos mean every feature change touches five distant
directories.

**Rejected:** `src/defs/`, `src/model/`, `src/systems/` — proposed in an earlier plan draft
and reversed before any code was written.

---

## 2026-08-01: Rank-up preserves hero level

Ranking a hero up raises its level cap and keeps its current level and XP.

**Reason:** resetting level on rank-up makes the reward feel like a punishment, which is
exactly wrong for the mechanic the entire game is built around.

**Rejected:** level reset on rank-up (common in the genre, and consistently disliked).

---

## 2026-08-01: Godot pinned to 4.7.1 stable

The engine binary lives in `tools/godot/` (gitignored) and the project is pinned to 4.7.1.

**Reason:** mid-development engine upgrades break scenes and shaders in ways that are
expensive to diagnose while other things are also in flux. Upgrade deliberately, between
phases, as its own change.

**Rejected:** floating on latest stable.

---

## 2026-08-01: Six hero stats, hard cap

`HP ATK DEF SPD CRIT_RATE CRIT_DMG`. A seventh requires an entry here.

**Reason:** collector games accrete stats until no human can reason about a balance change.
Six is enough for meaningful gear differentiation and few enough to actually tune.

**Rejected:** separate magic/physical attack and defence lines, accuracy/evasion, resistances.

---

## 2026-08-04: Serena removed; built-in Read/Grep/Edit are the tools

Serena's MCP server is unregistered, its hooks deleted, and the "symbolic tools are primary"
mandate is gone from `~/.claude/CLAUDE.md`, both project agent files, and the three global ones.
`.serena/` is deleted and gitignored.

**Reason:** measured 13 Serena calls against 289 built-in file operations in this repo (4.3%),
and 0 of 357 in the other project on this machine. Three causes, none of them discipline:
its LSP daemon cannot coexist with `import_gate.ps1` (both want `.godot/`), so the mandated
tool was unavailable by design in every session that runs the gate; the game is ~550 lines
across 25 files, where `get_symbols_overview` on a 22-line file costs more than reading it; and
the rule charged a self-check on *every* `Read`/`Glob`/`Grep`/`Edit` call to route 13 of them.
The `import_gate.ps1` port-6005 guard stays — a hand-started editor still races `.godot/`.

**Rejected:** keeping the server registered without the mandate (still pays the prefix and the
`initial_instructions` pull for a tool nothing reaches for); scoping the mandate off for this
repo only (the other project ignored it 357 times out of 357).
