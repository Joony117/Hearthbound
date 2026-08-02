# Decisions

Dated architecture decision records. **Record what was rejected and why**, so a later pass
doesn't "simplify" the architecture by undoing something deliberate.

Newest first.

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
