# Architecture

Boundaries, not a file listing. If you need to know what a file does, read the file. This
document exists so that agents and future-you don't dissolve the boundaries by accident.

---

## Dependency rules

These are the rules this game will actually violate if left unstated.

1. **UI may observe gameplay systems. Gameplay systems may not reference UI.**
   A system announces what happened via signal. It does not find the HUD and update a label.

2. **Definitions are Resources and hold no runtime state.**
   `HeroDefinition` holds base stats and growth. It never holds current HP.

3. **Runtime state lives in Nodes or `RefCounted` domain objects, never in a Definition.**
   `Hero` (runtime, `RefCounted`) points at a `HeroDefinition` by `def_id`. Many `Hero`
   instances share one definition.

4. **Only `SaveService` reads or writes save files.**

5. **Only `SceneRouter` changes the main scene.** No `get_tree().change_scene_to_file()`
   anywhere else.

6. **Autoloads hold no scene objects or level nodes.** Persistent battle checkpoints are
   serialized dispatch-order data in the profile; their rules and runtime domain objects belong
   to `combat/battle/`. This explicit `ig-544` exception permits an expedition to continue while
   its view is closed without making a scene or autoload the combat rule authority.

7. **Combat rules never reach into `hub/` or mutate the profile.** Legacy resolvers take data
   in and return `CombatResult`; autonomous combat takes `BattleState` and produces
   `BattleOutcome`. `BattleView` may observe snapshots and submit validated commands through
   `GameSession`, as a UI adapter under rule 1. It never applies rewards or removes heroes.

8. **Permadeath is applied in exactly one place — `GameSession.kill_hero()`.**
   This one matters more than it looks. A roster that can be mutated from three places is
   how this specific game rots: a hero half-deleted from the party but still in the roster,
   gear duplicated into a cache *and* left equipped. One writer, one code path.
   *Amended 2026-09-23, accepted (`DECISIONS.md`, the town builder, item 11):* the one writer
   is `GameSession.kill_hero()`. Its callers are the expedition resolver, sacrifice and
   starvation. A caller decides that a hero dies; only `kill_hero()` removes it. (Sacrifice has
   called it since before this entry, so the old wording was already narrower than the code.)

9. **Shared balance numbers live in `balance.tres`, not in code.** Per-zone authored values
   (recommended power, wave ramp, rewards, and expedition durations) live on their
   `ZoneDefinition` Resources; signature-specific cooldown/range/effect values live on
   `AbilityDefinition` Resources. A magic number in a `.gd` file is a bug unless it is structural
   (array sizes, tick rates).

---

## Autoloads

**Three. That is the budget.** A fourth requires a `DECISIONS.md` entry justifying it.

| Autoload | Owns | Does not own |
|---|---|---|
| `SceneRouter` | Main-scene transitions, transition state | Anything about the game |
| `SaveService` | Serialization to/from `user://save.json` and the append-only `user://ledger.jsonl`, version field | Game rules |
| `GameSession` | Persistent player profile, supplies, dispatch battle checkpoints and stranded incidents; transaction/tick coordination | Combat rules, UI, scene objects or level nodes |

`GameSession` exists because the player profile must outlive scene changes (menu → hub →
arena → hub). That is the *only* justification, and it is not a licence to grow into a
`GameManager`. If a system's logic can live in a plain function taking `GameSession` as an
argument, it lives there — not as a method on the autoload.

Rejected: a `GameManager` owning health, enemies, inventory, quests, combat, UI, level
loading, music, saving, and dialogue. See `DECISIONS.md`.

---

## Persistent expedition orders and transactional returns

### Autonomous battle extension (`ig-544`, approved 2026-09-22)

The owner replaced direct hero piloting with autonomous squad combat and RTS intervention.
One fixed-tick `BattleSimulation` owns watched and unattended battle rules. `BattleState`,
`BattleActor`, and `BattleOutcome` are typed domain objects; authored kits and zones are
Resources. The profile stores their validated serialized checkpoints alongside each order.
The view receives detached snapshots and routes commands by order ID. Opening a view never
creates another battle, consumes supplies twice, or re-rolls a committed event.

Route minimum and combat advance in parallel. Battle success waits for the remaining route
before rewards settle; wipes instead create a stranded incident. Offline time advances only
the dispatched leg, with a bounded combat simulation and no repeat chain. Tactical pause is
transient for the watched battle and clears on leaving/reload. Practice owns a local domain
state in its view and cannot mutate the profile.

Schema 3 adds battle checkpoints, supply escrow and distinct stranded-hero incidents. The
v2 migration preserves identities, remaining orders and resources, consumes prior offline
time against the old route once, and starts new battle simulation at tick zero. It invents
neither prior combat nor rewards. The atomic migration must persist before play. RNG state
is a decimal string so JSON cannot round its 64-bit value.

Zero HP only changes an allied actor to downed. Final abandonment/expiry passes IDs to
`Expedition.finalize_permanent_losses`, which calls the sole roster-removal writer,
`GameSession.kill_hero`. Hero rescue and the existing lost-gear caches remain distinct.
Supply allocation, explicit commands and terminal reward/rescue settlement share the
established transaction boundary; periodic checkpoints preserve whole simulation state.

### Historical timer-only implementation (`ig-6l4`)

Ruled 2026-09-22 for `ig-6l4`. A dispatch order is persistent player intent, not live combat
state. `GameSession` owns its captured hero identities, destination, remaining time, repeat
count, and seed. It coordinates ticking and mutations. `ExpeditionOrders` owns pure duration
and safety rules; `BulkOperations` owns pure batch selection and cost planning. Both live under
`hub/`, not in the autoload-only `systems/` directory. `Expedition` still owns transient wave
progress and cumulative HP while resolving a single return. No fourth autoload is introduced.

Heroes and items have stable instance IDs. Presets never identify a hero by display name or
array index. A missing member remains missing; neither load nor dispatch silently substitutes.
Busy/protected checks live at mutation boundaries as well as in the UI. Real combat deaths
continue through the existing `kill_hero` path; protection does not confer immortality.

`GameSession` coordinates the in-memory transaction and calls `SaveService`, the sole file
writer, to commit it. A completion defers intermediate autosaves and commits casualties,
rewards, cache changes, report, and order advancement together. A failed write restores the
previous in-memory state and leaves the previous canonical save intact.
The persisted seed drives a local RNG, so retrying an uncommitted return does not reroll it.
The existing public `resolve(team, wave) -> CombatResult` seam stays intact; seeded quick
resolution is an internal helper, not another combat-result contract.

Schema 2 migrates version-1 profiles and persists generated identities before depending on
them. New-schema identity/order corruption and unsupported future versions refuse play and
writes; they must not become a fresh profile that overwrites the original. Bulk confirmation
plans are revalidated at commit and saved as one transaction.

---

## Reaching shared Resources

`balance.tres` (rule 9) and every `Definition` Resource (`HeroDefinition`, and later
`EquipmentDefinition`, `ZoneDefinition`) are authored data, not player state. A consumer reaches
one with a plain `preload("res://balance.tres")` (or `load()` where the path is only known at
runtime, e.g. a future `def_id` → `.tres` lookup), assigned to a `const` in whichever script sits
at the top of a flow, then passed explicitly into pure functions as an argument — the
`compute_essence_yield(fodder, target, balance: BalanceTable)` shape `CODING_RULES.md` already
specifies.

No autoload holds or hands out a shared Resource. Godot's `ResourceLoader` caches by path — two
`preload()`s of the same `.tres` anywhere in the project return the identical object — so there
is nothing to gain by centralizing the load behind a fourth autoload or behind `GameSession`, and
real cost to doing so: it would make every consumer's tests depend on booting that autoload
first, the same "untestable without booting the engine" failure `CODING_RULES.md`'s autoloads
section already names for methods-on-a-singleton.

Writing into an exported array of a shared Resource in place mutates it for every consumer and
can persist into the `.tres` on disk (`CODING_RULES.md`, "Resources vs. runtime objects"). That
hazard is a property of sharing one Resource instance, not of any particular way a consumer
obtained the reference — treat it the same regardless of whether the reference came from a
`preload`, a passed-down argument, or (hypothetically) an autoload.

See `DECISIONS.md`, 2026-08-02.

---

## The combat seam

The section below records the legacy quick-resolve/action-arena contract. `ig-544` preserves
that API for its existing callers while new production dispatches use `BattleState` /
`BattleOutcome`. The old requirement that all future combat fit `CombatResult` is superseded;
the single wave-ramp function, pure rules and central permanent-death writer remain binding.

The single structural decision made before the vertical slice exists, because retrofitting
it means rewriting the expedition system.

```gdscript
# both have this exact signature
func resolve(team: Array[Hero], wave: Wave) -> CombatResult
```

- `combat/quick_resolve.gd` — statistical, synchronous, returns immediately.
- `combat/arena/` — real-time 3D scene, returns via signal when the run ends.

Two plain functions. **No base class, no interface, no strategy registry.** Two functions
with the same signature do not need a hierarchy in GDScript.

`CombatResult` is the contract on the way out: survivors, HP after, dead heroes, loot seed.
The expedition system consumes only that, so it cannot tell which path produced it.

`Wave` is the contract on the way in: one wave's already-resolved enemy composition and
power level. It is `zones/wave.gd`, `extends RefCounted` — **not** a `Definition`. A wave is
derived at runtime by interpolating `ZoneDefinition`'s stored ramp
(`trash_wave_start_fraction` → `trash_wave_end_fraction`, `boss_fraction`) for a given wave
index; nobody hand-authors an individual wave in the inspector, so rules 2–3 rule out the
`Definition` suffix and the `Resource` base for it. Whatever computes that interpolation must
do it in exactly one place and hand both `resolve()` implementations the same `Wave`
instance — the two paths must agree on which enemies a given wave contains, and duplicating
the ramp-interpolation math into each implementation is how they'd quietly disagree. See
`DECISIONS.md`, 2026-08-02.

---

## The town is `hub.tscn`, not a destination next to it

Ruled 2026-08-13 (`DECISIONS.md`). **The walkable town is the hub scene gaining an avatar, not a
second scene that has to reach back into the first one.** This is stated here because the
question it answers — "how does the town reach the roster panel?" — sounds like a routing
question and is not one.

`hub/hub.tscn` is already a `Node3D`: camera, ground, and five building meshes under
`Buildings/`, each with a `Label3D`. The roster, equipment, buildings, summon, sacrifice and
expedition panels are `Control` nodes under a `CanvasLayer` **in that same scene**. The 3D town
and the panels already share one scene tree and one script.

So:

- **Every existing hub panel is reached the same way it is today** — it is already there. Walking
  up to the Forge shows the panel that is already parented to the same scene; it does not route
  anywhere. What changes is when a panel is visible, which is `hub.gd`'s business and not a
  boundary's.
- **`SceneRouter` gains nothing and loses nothing.** Rule 5 is untouched, `GAME_SPEC.md`
  § Direction seam 1 is untouched, and no second navigation mechanism appears. The town is not a
  new main scene, so there is no new transition to own.
- **This is not a new seam.** It is the absence of one, which is the entire reason the ruling is
  worth writing down: the alternative reading — town scene *plus* hub scene, with routing between
  them — invents a seam, forces every panel to be reachable from two scenes, and is what the
  direction table meant by "or every shipped hub feature gets rebuilt."
- **Rule 1 governs the avatar.** The town observes the roster; it does not write to it. A hero
  dying mid-expedition reaches the avatar as a signal, never as the town calling `kill_hero()`.
  Rule 8 stays single-writer with no exception carved for the town.

The one thing this does *not* settle is whether a level-3 building looks different from a level-1
one. Levels already persist (`GameSession`), nothing renders them, and that is art, not
architecture.

### The town is the interface (`ig-wgj`, 2026-09-23)

This amends the section above in one place. **Panels open when you click a building, not when you
walk near one.** The owner wants the UI integrated into the town. The ruling that the town is this
scene still holds, and so do rules 1, 5 and 8.

- **The town is a view, under `hub/town/`.** Its buildings, walk spots and heroes sit in a
  sub-scene instanced by `hub.tscn`, with their own scripts. That is instancing, not routing, so
  there is still one main scene. The town reports clicks upward, as a building or hero id, and
  `hub.gd` decides which panel opens. The town never opens a panel and never mutates the profile.
  The panels keep their `%UniqueName` contracts.
- **The embodied hero is profile state.** Its id lives on `GameSession`, is saved, and is dropped
  on load if that hero is no longer home. It is checked where mutations happen, not only in the UI:
  `is_hero_protected()` covers sacrifice and bulk sacrifice, and every dispatch entry point refuses
  it. It is **not** folded into `is_hero_busy()`. That would also block equipping and ranking up
  the body you are in.
- **A keeper's station and skills are hero state.** `station`, `passions` (was `calling`, see
  the town builder entry, item 12) and `profession_xp`
  are `Hero` fields, saved in `Hero.to_dict/from_dict` (save boundary #1). `station` holds a
  hall id (a building node name from `hub/town/town.tscn`) or, once the town builder lands, a placed
  workplace id. Renaming a hall is a save change.
  Masterwork (a passion + skill 5) is a gate `GameSession` checks inside the action it gates:
  `enhance_item` past +12, `rank_up_hero` for SS→SSS, and the masterwork draught craft. The UI only
  reflects it. A station counts in
  `is_hero_protected()`, but not in `is_hero_busy()` and not at the dispatch entry points: keepers
  can be sent out, and only sacrifice refuses them. Because the station lives on the hero,
  `kill_hero()` needs no extra code, and rule 8 keeps one writer. Keeper skill reaches a building
  as one more argument to the pure formula that already reads that building's level. `combat/`
  never reads it. XP builds up only on the live tick, never in the offline catch-up. Details:
  `DECISIONS.md` 2026-09-23, item 5.
- **Ambient heroes are views onto the roster.** They are derived from roster membership and
  `is_hero_busy()`, and refreshed from the existing `roster_changed`/`expeditions_changed` signals.
  Keepers who are home stand at their building instead of wandering.
  Their positions and activities are never saved. A hero leaving or dying reaches the town as one
  of those signals, never as the town calling a mutator.
- **One KayKit loader.** Town heroes and battle units get their model, weapons and shared
  `AnimationLibrary` from one helper under `heroes/`. `combat/battle/battle_unit_view.gd` calls
  it too. Nothing copies the loader, and nothing reaches into `BattleUnitView` internals from
  `hub/`. `combat/` still never references `hub/` (rule 7).
- **Presentation numbers stay in the view scripts** (walk speed, camera distance, the cap on
  ambient heroes), following `battle_unit_view.gd`'s precedent. They are not balance, so they are
  not `balance.tres` rows (rule 9).
- **No fourth autoload.** Town state is either profile state (`GameSession`) or view state
  (`hub/town/`). Nothing sits in between.

**The town builder (`ig-6m2`, proposed 2026-09-23)** moves these boundaries. Details:
`DECISIONS.md` 2026-09-23, the town builder.

- **Placement is profile state.** Placed buildings and the resource stockpile live on
  `GameSession` and save through `SaveService`. The town view spawns buildings from that list. It
  never decides where one goes.
- **A hero's one job is `station`,** and its house is `home`. Both are `Hero` fields, so a death
  takes them away and `kill_hero()` stays the only writer (rule 8).
- **Town rules are pure functions in one script under `hub/town/`,** following `ExpeditionOrders`:
  hex math, whether a hex is free, and production per tick. `GameSession` mutators call them and
  refuse there. The view only reflects the result.
- **Production, eating and starvation run only on the live tick,** never in the offline catch-up
  (`GAME_SPEC.md` § Hard constraints). A starvation death goes through `kill_hero()` (rule 8).
- **The halls stay unique,** so a hall's id is its type name and `building_levels` keeps its
  indexes.

**Skills (`ig-gy0`, accepted 2026-09-23)** move these boundaries. Details: `DECISIONS.md`
2026-09-23, skills.

- **Skills are `AbilityDefinition` data, applied only in `combat/battle/`.** A closed set of
  effect primitives, one picker, no script per skill. Skill logic anywhere else is a bug.
- **The forecast stays the simulation** (seam #4). `ExpeditionOrders.safety_forecast` and
  `QuickResolve` are skill-blind by rule and never gate a `battle_v1` order.
- **Bars, chains and learned skills are `Hero` fields** (save boundary #1), fixed into the team
  snapshot at dispatch. A death takes them away (rule 8).
- **Piloting one hero is watched-view state,** like tactical pause: never saved, never in an
  unwatched run or a forecast.

---

## Project layout

Feature-grouped, per Godot's project-organization guidance: assets live next to the scenes
that use them, not in type-based silos (`all_scripts/`, `all_textures/`).

```
res://
├── game/            session bootstrap
├── hub/             hub.tscn + summon/ roster/ forge/ expedition/
├── heroes/          hero.gd (runtime), hero_definition.gd (Resource), defs/*.tres
├── equipment/       item.gd, equipment_definition.gd, core_definition.gd, defs/*.tres
├── zones/           zone_definition.gd (Resource, authored), wave.gd (RefCounted, runtime), defs/*.tres
├── combat/          combat_result.gd, quick_resolve.gd, arena/
├── ui/              main_menu.tscn, pause_menu.tscn, hud.tscn
├── systems/         AUTOLOADS ONLY
├── tests/           GUT
├── docs/
└── tools/godot/     engine binary, gitignored
```

`systems/` is not a junk drawer. If it is not one of the three autoloads, it does not go
there.

---

## Amending this document

Update it when a boundary **actually moves**, not when a file is added. Every amendment gets
a dated entry in `DECISIONS.md` saying what changed and why.
