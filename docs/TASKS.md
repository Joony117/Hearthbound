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

**On `[DONE]`, the director moves the body to [`TASKS-DONE.md`](TASKS-DONE.md)** and leaves a row
in Completed tickets below. This file is read start-to-finish by every `tech-lead` dispatch, so
it stays the *live* backlog; shipped bodies are the bulk of the text and the part nobody needs to
re-read. Move them verbatim — a shipped ticket's acceptance criteria are the record of why the
code looks the way it does, and several carry findings later tickets inherit.

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

# Phase 2 — Complete but ugly core loop

Backlog. **Deliberately not expanded into full tickets yet** — Phase 1 will teach us things
that change the wording, and writing eleven speculative contracts is exactly the premature
work this process exists to avoid.

Expand each into the full format when it comes up.

**P2-01 split.** The original backlog line bundled three independent Resource domains (hero,
equipment, zone) plus a shared tunables container behind one line. That is a subsystem, not
one behavior, and the tunables container's shape is still an open `godot-architect` call. Split
into a numbered sequence; `P2-01a` was the starting point; all four have landed (`TASKS-DONE.md`).

**P2-03 split.** The original backlog line bundled a not-yet-existing `Wave` type, its
ramp-interpolation rule, a computed hero-stat formula, a new `combat/` directory with two new
files, and the expedition/permadeath wiring behind one line — a type, a formula, a subsystem
directory, and a combat loop is not one behavior. Split in two: `P2-03a` builds `Wave` and
computed hero stats and makes no player-facing change by itself, matching the precedent already
accepted for `P2-01a`/`P2-01b`/`P2-01d`. `P2-03b` is what makes it visible — pressing Expedition
produces real win/loss/retreat outcomes and permadeath instead of a coin flip. Start with
`P2-03a`; nothing in `P2-03b` compiles against a real `Wave` or real stats without it.

**P2-03e split.** `P2-03d`'s per-wave damage model made `OUTCOME_COMPLETED` reachable but left
`OUTCOME_RETREATED` provably unreachable in the only configuration the game can build today
(`SYSTEMS.md` § Retreat threshold, `KNOWN_ISSUES.md`) — a lost wave is an instant full-team wipe,
so HP only erodes on wins, and won-wave damage has to stay cheap for a clear to exist. Fixing this
bundles a decision nobody but `game-designer` can make (if a loss becomes survivable, does the
expedition continue, force a retreat, or end through a new outcome — nothing in `SYSTEMS.md`
answers that today) with a code change to `combat/quick_resolve.gd` and
`hub/expedition/expedition.gd` that can't honestly be written before that decision exists —
checkable acceptance criteria need to know what "loss" means. Split in two: `P2-03e` is the design
ruling, recorded in `SYSTEMS.md` the way the wave-damage coefficient and its rejections were, not
an implementer contract. `P2-03f` is the implementer ticket once it lands. Sequence ahead of
`P2-03c` (squad select): `P2-03c` only builds the mixed-rank rosters that let retreat's *existing*
threshold fire in Ashfall/Sundered, which masks this symptom without touching its cause; the
win/loss branch is reachable and provably broken in solo Verdant today, with no squad-select
dependency, so fixing it first means `P2-03c` inherits correct win/loss semantics rather than the
other way around.

All three landed: `P2-03e` in `5118853` (the ruling is `SYSTEMS.md` § Lost-wave damage), `P2-03f`
in `a412c4a`, and `P2-03c` in `85caa66` — which inherited the corrected win/loss semantics, as the
sequencing above intended. The whole `P2-03` group is now shipped.

**P2-04 split.** The original line bundled four things behind one row: item instances existing at
all (no runtime type exists anywhere — `heroes/hero.gd` has three fields and no equipment slot;
`equipment/equipment_definition.gd` is a shared per-slot template carrying no rank and no runtime
state), a way for one to enter the game (an equipment loot table — `zones/zone_definition.gd`'s
only loot field is a free-text `loot_emphasis` string like "Gold, F–C parts, light Summon Stones",
and `P2-01c`'s own note already flagged this: "no loot table exists before P2-04"), a lost-gear
cache created on hero death, and a distinct recovery-expedition mission type with a damage roll
and a decay clock. That is a type, a missing design input, a permadeath hook, and a second mission
type behind one line — not one behavior. Splitting it also surfaces two more missing design inputs
`SYSTEMS.md`'s own "Death and gear recovery" section already half-names: `power_deficit_penalty`
in the damage-roll formula is explicitly marked PROVISIONAL with no value (`SYSTEMS.md:805-815`),
and the turn clock both it and the cache-expiry rule are denominated in **does not exist**. Note
the shape of that second gap: a turn-denominated *tunable* is already authored
(`reliquary_decay_turns_bonus`, `balance_table.gd:22` and `balance.tres:24`), so it reads as
settled — but nothing anywhere increments a turn, and no counter exists to bonus. The number is
real and the thing it measures is not. Neither gap blocks the earliest tickets below, so they're
flagged against the tickets that actually need them rather than gating the whole split.

Split into: `P2-04b` is the flagged design gap — an authored equipment loot table (drop rate +
rank/slot selection per zone) to replace `loot_emphasis`'s prose, the same "found, not authored"
shape already used for `P2-04a`/`P2-09`. `P2-04c` is the item-instance foundation — a runtime
`Item` type (`ARCHITECTURE.md`'s project-layout diagram and `DECISIONS.md`'s equipment entries
already name this file and this shape, analogous to `Hero`) plus `GameSession.inventory`
persistence, no loot roll, no equip, no UI attached — the same non-player-facing exception already
used for `P2-01a`/`P2-03a`. It needs neither `P2-04b` nor a combat-facing stat-magnitude formula
(equipping's effect on combat power isn't in this backlog line at all), so it can proceed today,
in parallel with the design ruling rather than waiting on it. `P2-04d` is what makes `P2-04c`
visible — an expedition clear can drop a real item into inventory — and is the first ticket that
does need `P2-04b`'s table. `P2-05a` (equip UI) is resequenced to depend on `P2-04c` directly
rather than on `P2-05`: `P2-05` (salvage) presupposes items exist just as much as equipping does,
so gating equip behind salvage was backwards — corrected below. `P2-04e` is the lost-gear cache
itself — it needs equip to exist first, since only equipped gear can be lost, and it hooks the
sole permadeath call site (`ARCHITECTURE.md` r8) rather than adding a second one. `P2-04f` is the
recovery expedition with its damage roll and decay, which is where `power_deficit_penalty` and the
missing turn concept actually bite.

`P2-04c` landed first in `0349a4c`, being the only ticket in the group buildable without a design
ruling, and `P2-04b` followed in `d08211f` (`SYSTEMS.md` § Loot table). Items now exist, persist,
and have a table saying which one a clear yields — so the group's design gate is open. `P2-04d`
followed in `2fbdddf`, the first ticket here that touches code a player sees: a clear now rolls a
banded drop and the hub names it. Note what the ruling did *not* need: no new `BalanceTable`
field, because the rank curve is `summon_weights` reused rather than a second table authored
alongside it.

`P2-05a` (equip UI) is next — items now exist, persist, and arrive on their own, which was the
whole precondition. `P2-04e`/`P2-04f` queue behind it, still blocked on the two design gaps named
above.

| # | Objective | Notes |
|---|---|---|
| P2-01a | `HeroDefinition` Resource + 5 archetypes authored | Body in `TASKS-DONE.md`. Unblocked P2-02. |
| P2-01b | `ZoneDefinition` Resource + 3 zones authored | Body in `TASKS-DONE.md`. Unblocks P2-03a. |
| P2-01c | `EquipmentDefinition` Resource + 10-slot enum | Needed before the `P2-04` group (lost-gear caches); no item instances authored yet — no loot table exists before `P2-04c`/`P2-04b`. |
| P2-01d | `BalanceTable` Resource + `balance.tres` authored from `SYSTEMS.md` | Body in `TASKS-DONE.md`. Container shape is settled (`DECISIONS.md`, one `BalanceTable`). Needed before P2-02 can consume real summon weights — sequence before or alongside P2-02, not after. Did **not** move `Hero.RANK_NAMES` — split out as `P2-01d-2`. |
| P2-01d-2 | Move `Hero.RANK_NAMES` onto `BalanceTable`; repair its three call sites; author the Summoning Circle's two-field schema | Body in `TASKS-DONE.md`. Unblocked by `godot-architect`'s ruling on reaching shared Resources without a fourth autoload. Not required before P2-02 — P2-02 already replaces `hub/summon/summon.gd` wholesale and can read a rank count off `BalanceTable`'s rank table directly, so this can trail P2-02 instead of gating it. |
| P2-02 | Real weighted summon against `BALANCE.summon_weights`; roster displays hero archetype | Replaces P1-02. Body in `TASKS-DONE.md`. Carries the `def_id` → `HeroDefinition` lookup — `godot-architect` returned `cannot-judge` on this seam because no lookup consumer exists yet, but named this the ticket that builds one. A `def_id` matching no `HeroDefinition` must fail loudly, not silently default (`CODING_RULES.md:121-122`). Equip UI moved out — nothing is equippable yet; see `P2-05a`. |
| P2-03a | `Wave` construction (ramp interpolation) + computed hero stats | Body in `TASKS-DONE.md`. Not player-facing by itself, same shape as `P2-01a`/`P2-01b`/`P2-01d`. Unblocked P2-03b. |
| P2-03b | `combat/quick_resolve.gd` + `CombatResult` — real waves, HP carry-forward, retreat threshold, permadeath | Replaces P1-03. Body in `TASKS-DONE.md`. GUT 9.7.1 is already installed (`addons/gut/`) — this is the first ticket to add real coverage under `tests/unit/`, not a framework install; the original backlog line's "Add GUT here" is stale. |
| P2-04b | Equipment loot table — drop rate + rank/slot distribution per zone | Body in `TASKS-DONE.md`; the ruling itself is `SYSTEMS.md` § Loot table. One item per clear, slot uniform 1/10, rank from `summon_weights` sliced to a per-zone band, seeded from the boss wave's `loot_seed`. Supplements `loot_emphasis` rather than replacing it, so `tests/zone_definition_check.gd` needs no change. Unblocked `P2-04d`. |
| P2-04c | Runtime `Item` type + `GameSession.inventory` persistence | Body in `TASKS-DONE.md`. Not player-facing by itself, same shape as `P2-01a`/`P2-03a`. Unblocked `P2-04d` and `P2-05a`. Fixed a pre-existing `from_dict` crash on an explicit `null` field, inherited from `Hero`'s shape — see its Findings before copying that pattern again. |
| P2-04a | XP-per-level curve for expedition rewards | Found by `game-designer`, deliberately not authored by it — a genuine missing `balance.tres` input with no ticket owning it yet. Crosses into expedition-reward territory, so it sequences here, not in the P2-01 group. |
| P2-04d | Expedition clears can drop a real item into inventory | Body in `TASKS-DONE.md`. Unblocked `P2-05a`. Roll order is **slot then rank** — the ruling left it open, this pinned it. First disk-level proof that an `Item` survives JSON (`rank` decodes as `float` and `from_dict`'s `int()` absorbs it); read its Findings before writing another one-off `-s` check, which cannot statically name `Expedition`. |
| P2-05 | Salvage → parts → enhance → part conversion | Cores deferred to Phase 4. Needs `P2-04c` (item type) and `P2-04d` (something to salvage) — presupposes items exist, same as equip does. |
| P2-05a | Equip UI for authored equipment | **Full body below — not split.** Assignment, persistence, and an ugly UI ship now; wiring equipped gear into `compute_final_stats`/`compute_team_power` is an explicit non-goal, since no ticket has ever authored what a rank-`N` item contributes (`P2-04b` left it out of scope on purpose) and no acceptance criterion here needs that number to be checkable. That gap is now `game-designer`'s to rule on next, same shape as `P2-03e`/`P2-04b`, not yet its own numbered ticket. Depends on `P2-04c` directly, not on `P2-05` — salvage presupposes items exist just as much as equip does, so gating equip behind salvage was backwards. |
| P2-04e | Lost-gear cache created on hero permadeath | Needs `P2-05a` (equip) — only equipped gear can be lost. Hooks the sole permadeath call site, `GameSession.kill_hero()` (`ARCHITECTURE.md` r8) — do not add a second one. `P2-05a`'s interim behavior at that same call site (equipped items return to `GameSession.inventory` on death) is exactly what this ticket replaces with the cache; it is not a second removal path to reconcile. |
| P2-04f | Recovery expedition — damage roll + cache decay | Needs `P2-04e` (a cache to target). Blocked on two more design gaps: `power_deficit_penalty` in the damage formula (already PROVISIONAL in `SYSTEMS.md`) and a "turn" concept, which doesn't exist anywhere in the codebase today despite the decay clock being turn-denominated. |
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

## P2-05a — Equip UI for authored equipment                              [TODO]

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

---

## Completed tickets

Full bodies — objective, existing architecture, acceptance criteria, non-goals, and the
findings each one produced — live in [`TASKS-DONE.md`](TASKS-DONE.md). They are moved rather
than deleted: a shipped ticket's acceptance criteria are the record of *why* the code looks
the way it does, and several carry findings later tickets inherit.

They are moved rather than kept inline because this file is read start-to-finish by every
`tech-lead` dispatch, and completed bodies are the bulk of it while being the part nobody
needs to re-read.

| # | Title | Landed |
|---|---|---|
| `P1-01` | Project boots to a main menu and into the hub | `f62e545` |
| `P1-02` | Summon a hero into a visible roster | `f62e545` |
| `P1-03` | Send a hero out; it lives or dies permanently | `f62e545` |
| `P1-04` | Export and clean-checkout gate | `a8c5e47` |
| `P2-01a` | HeroDefinition Resource + five archetypes authored | `034a6df` |
| `P2-01d` | `BalanceTable` Resource + `balance.tres` authored | `c46b153` |
| `P2-01d-2` | Shared rank labels + Summoning Circle schema | `6b691f9` |
| `P2-01b` | `ZoneDefinition` Resource + three zones authored | `cbf8f91` |
| `P2-01c` | EquipmentDefinition Resource + 10-slot enum authored | `eb3c35a` |
| `P2-02` | Real weighted summon + archetype roster display | `0556ce0` |
| `P2-03a` | Wave construction + computed hero stats | `ab11d34` |
| `P2-03b` | Statistical expedition resolution + permadeath | `35cdc5e` |
| `P2-03d` | Per-wave damage model — a zone must be clearable | `28115f5` |
| `P2-03e` | Win/loss branch design ruling — what a lost wave means | `5118853` |
| `P2-03f` | A lost wave hurts instead of wiping the team | `a412c4a` |
| `P2-03c` | Expedition setup: multi-hero squad + zone select, with authored zone unlocks | `85caa66` |
| `P2-04c` | Runtime `Item` type + persistent inventory | `0349a4c` |
| `P2-04b` | Equipment loot table ruling — what a cleared zone yields | `d08211f` |
| `P2-04d` | Expedition clears drop a real, banded item into inventory | `2fbdddf` |

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
cd /e/Game && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Export:

```bash
cd /e/Game && mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe
```

The `mkdir` is required — Godot does not create its own export directory, and `export/` is
gitignored, so a clean checkout hits this every time.
