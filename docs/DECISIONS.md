# Decisions

Dated architecture decision records. **Record what was rejected and why**, so a later pass
doesn't "simplify" the architecture by undoing something deliberate.

Newest first.

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
