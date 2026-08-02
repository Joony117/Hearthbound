# Coding Rules

Godot 4.7.1, GDScript. Follows the official GDScript style guide; the rules below are the
ones that matter for this project specifically.

---

## Naming

| Thing | Convention | Example |
|---|---|---|
| Files and folders | `snake_case` | `quick_resolve.gd`, `hero_definition.gd` |
| Classes (`class_name`) | `PascalCase` | `class_name HeroDefinition` |
| Functions, variables | `snake_case` | `func compute_essence_yield()` |
| Private members | leading `_` | `var _cached_power: int` |
| Constants, enums | `CONSTANT_CASE` | `const MAX_PARTY_SIZE := 5` |
| Signals | past tense, describes what happened | `hero_died`, `rank_changed` |
| Node names in scenes | `PascalCase` | `SummonPanel`, `RosterList` |

A file defining a `class_name` is named after it: `HeroDefinition` → `hero_definition.gd`.

---

## Static typing is mandatory

Type every variable, parameter, and return. Use `:=` inference where the type is obvious
from the right-hand side.

```gdscript
var rank: int = 0
var heroes: Array[Hero] = []
func essence_yield(hero: Hero) -> int:
```

Untyped GDScript silently accepts nonsense and this game is full of integer ranks and array
indices where a typo becomes a balance bug rather than a crash. Typing is the cheap check.

`Variant` requires a comment explaining why.

---

## Resources vs. runtime objects

**Definitions are `Resource`. Instances are `RefCounted`.** This distinction is load-bearing.

```gdscript
class_name HeroDefinition extends Resource
@export var display_name: String
@export var base_hp: float
@export var hp_growth: float
# no current_hp here, ever
```

```gdscript
class_name Hero extends RefCounted
var def_id: StringName
var level: int
var current_hp: float
```

A Resource is shared by every instance that references it. Writing runtime state into one
mutates it for everything else and, worse, can persist into the `.tres` on disk.

**Prefer one Resource type with exported fields over N subclasses.** Ten weapon subclasses
that differ only in numbers is the wrong shape — one `EquipmentDefinition` with exported
values is the right one.

---

## Signals over reaching

Announce; don't go find the listener.

```gdscript
# good — the health owner announces
signal health_changed(current: float, maximum: float)

# bad — gameplay reaching into UI, violates ARCHITECTURE.md rule 1
get_node("/root/Hub/HUD/HealthBar").value = current
```

No `get_node("../../..")` chains across scene boundaries. A node may reach *down* into its
own children. Reaching *up* or *sideways* means the dependency is backwards — use a signal,
or an exported `NodePath`.

---

## Autoloads

Three exist (`SceneRouter`, `SaveService`, `GameSession`). Do not add a fourth without a
`DECISIONS.md` entry.

Game rules do **not** live on autoloads. A function that takes what it needs as arguments is
testable without booting the engine; a method on a singleton is not.

```gdscript
# good — pure, testable
static func compute_essence_yield(fodder: Hero, target: Hero, balance: BalanceTable) -> int:

# bad — reaches into global state
func compute_essence_yield(fodder: Hero) -> int:
    return fodder.rank * GameSession.sanctum_level
```

---

## Balance numbers

Every tunable lives in `balance.tres`. No magic numbers in `.gd` files.

Structural constants (`MAX_PARTY_SIZE`, `EQUIPMENT_SLOT_COUNT`, tick rates) are fine as
`const` — they aren't tuned, they're facts about the code.

---

## Errors

Validate at trust boundaries: save-file load, `.tres` loading, anything from disk. Inside
the codebase, `assert()` for programmer errors and let it crash loudly in debug.

Never silently swallow a failed load. A missing Resource must be visible, not fall back to
a default that makes the bug appear later somewhere unrelated.

---

## Comments

Comment *why*, not *what*. The code says what.

Deliberate shortcuts with a known ceiling get a `ponytail:` comment naming the ceiling and
the upgrade path:

```gdscript
# ponytail: linear scan over the roster, fine under ~500 heroes; index by def_id if it grows
```

Those get harvested into `KNOWN_ISSUES.md`.

---

## Tests

GUT 9.x, arriving in Phase 2. Test what can break **silently**:

damage math, essence and rank-up thresholds, salvage yields, recovery damage rolls, summon
weight distribution, save/load round-trip.

Do not test particles, animations, or that a button emits `pressed`.

---

## Commits

One working state per commit. A commit that doesn't launch is not a commit.
Message says what changed and why, not "fixes".
