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

6. **Autoloads hold no level-specific state.**

7. **`combat/` never reaches into `hub/`.** It takes data in and returns a `CombatResult`.
   It does not know the roster exists.

8. **Permadeath is applied in exactly one place — the expedition resolver.**
   This one matters more than it looks. A roster that can be mutated from three places is
   how this specific game rots: a hero half-deleted from the party but still in the roster,
   gear duplicated into a cache *and* left equipped. One writer, one code path.

9. **Balance numbers live in `balance.tres`, not in code.** A magic number in a `.gd` file
   is a bug unless it is structural (array sizes, tick rates).

---

## Autoloads

**Three. That is the budget.** A fourth requires a `DECISIONS.md` entry justifying it.

| Autoload | Owns | Does not own |
|---|---|---|
| `SceneRouter` | Main-scene transitions, transition state | Anything about the game |
| `SaveService` | Serialization to/from `user://save.json`, version field | Game rules |
| `GameSession` | Persistent player profile: roster, inventory, buildings, caches, currencies | Combat, UI, level state |

`GameSession` exists because the player profile must outlive scene changes (menu → hub →
arena → hub). That is the *only* justification, and it is not a licence to grow into a
`GameManager`. If a system's logic can live in a plain function taking `GameSession` as an
argument, it lives there — not as a method on the autoload.

Rejected: a `GameManager` owning health, enemies, inventory, quests, combat, UI, level
loading, music, saving, and dialogue. See `DECISIONS.md`.

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
