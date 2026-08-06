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

`P2-05a` (equip UI) followed in `0760d83`, and did **not** split despite the magnitude gap flagged
against it: equip/unequip and persistence are checkable without knowing what a rank-`N` item
contributes, unlike `P2-03e` (win/loss branching could not be *specified* without knowing what a
loss meant) or `P2-04d` (needed a distribution to roll against). The gap bites only the ticket that
wires gear into combat, so it moved there — `P2-05b` is the ruling, `P2-05c` the implementer ticket.
That leaves `P2-04e` unblocked: gear can now be equipped, so there is something to lose on death,
and `P2-05a` already put the interim behavior (equipped items return to inventory) inside
`kill_hero()` for `P2-04e` to replace rather than beside it. `P2-04f` stays blocked on the two
design gaps named above.

`P2-05b` then closed the magnitude gap in `c092fc3` (`SYSTEMS.md` § Primary stat magnitude), so
`P2-05c` is unblocked and equipping is one ticket away from mattering. Two things it surfaced are
*not* `P2-05c`'s and have no ticket yet: `compute_team_power` sums `ATK + DEF + HP/10 + SPD` and so
is permanently blind to the two jewelry slots, and Sundered Vault's `130%`-of-RP boss — proven
unbeatable by an ungeared S/60 team — becomes satisfiable by a fully-geared one. Both are
Expeditions/combat-seam questions; route them through `tech-lead` if they turn out to matter once
`P2-05c` makes gear visible.

`P2-05c` landed in `b5525e7`, so gear is now visible and both flagged items are live rather than
hypothetical. The crit-blindness one is pinned by a test that asserts a ring moves `CRIT_DMG` and
leaves team power alone — deliberate, so whoever fixes it deletes an assertion on purpose instead
of filing a bug. The whole `P2-05a`/`b`/`c` group is shipped; `P2-04e` (lost-gear cache) and
`P2-05` (salvage) are what remain unblocked in the equipment line.

`P2-04e` then landed in `3885a14`, so a dead hero's gear is now held in a `LostCache` instead of
returning to inventory, and `P2-04f` has something to target. It shipped without `turn_lost`: the
field `SYSTEMS.md` authors has no counter anywhere in the codebase to read, and stamping it with a
fabricated value would have read as real data while measuring nothing — so `P2-04f` now owns both
the counter and the field. Two findings generalize past this ticket. The permadeath seam's **second
caller is dynamic** (`tests/save_roundtrip_check.gd` reaches it through `.call()`), so a signature
change on an autoload can leave the import gate green and break the one script that proves
permadeath survives a disk cycle — grep `.call(`/`callv(`/`Callable(`, not just the call syntax.
And the save round-trip test shipped as an in-memory `to_dict`/`from_dict` pair, which is precisely
what `P2-05a`'s row warns against; the implementation was correct, but nothing proved a `LostCache`
carrying an `Item` had ever crossed real JSON until the disk leg was added. That leaves `P2-05`
(salvage) and `P2-04f` — still blocked on `power_deficit_penalty` and the turn concept — as the
equipment line's remaining work.

**P2-05 split.** The line bundles four things: a parts currency that does not exist at all
(`GameSession` holds `roster`, `inventory`, `lost_caches`, `cleared_zone_ids` and no material of
any kind), salvage, enhancement, and 3:1 part conversion. Only one of the four is buildable today.

Salvage is fully authored — `3 + enhance_level` parts of the item's rank (`SYSTEMS.md` § Salvage) —
and `enhance_level` is *zero for every item that can exist* until enhancement ships, so the formula
is checkable now with the field deliberately absent. That is `P2-04e`'s `turn_lost` precedent
exactly: adding a field whose only possible value is a placeholder makes fabricated data read as
real. `P2-05f` adds `Item.enhance_level` and the `+ enhance_level` term together, when there is
something to count.

Enhancement is blocked on three separate gaps, two of them design: (1) the `+8%`-per-level
reading is explicitly deferred — `SYSTEMS.md`'s own headroom check computes *both* readings and
says "`P2-05`/Enhancement's own pass settles the reading"; (2) **gold does not exist** — grep
`*.gd` for it and the only hits are zone `loot_emphasis` prose strings, there is no currency, no
income, and no cost number anywhere in `SYSTEMS.md` beyond the words "plus gold"; (3) the cap is
`min(15, forge_level * 3)` and no building has a level — `balance_table.gd:20-21` authors both
coefficients, so it reads settled, the same "the number is real and the thing it measures is not"
trap the `P2-04` split found in `reliquary_decay_turns_bonus`. (1) and (2) are one ruling and
become `P2-05e`; (3) needs `P2-07`, or a ruling that the cap is flat until buildings exist.

Split into: `P2-05d` is salvage — parts currency, a salvage path, no enhance, no conversion; it
depends on nothing outstanding and is the shippable one. `P2-05e` is the enhancement design
ruling. `P2-05f` is enhancement itself. `P2-05g` is 3:1 conversion — the rule is one authored line
and needs no ruling, but it needs `P2-05d`'s parts to convert and its "at the Forge" siting trails
`P2-07`.

`P2-05d` landed in the commit below, so parts exist and `P2-05g` has something to convert. It cost
one review cycle: the first pass guarded the rank-indexed write with `assert()`, which Godot strips
from release exports — the game's shipped form — so the guard was absent in the only build a player
runs, and neither new test could reach it (both used in-range ranks, and asserts are *active* in an
editor run, so a hand-check would have masked it). The generalizable rule is in its Findings:
**an `assert()` is not a guard for anything that can arrive from a save file.** `Item.from_dict`
still does not validate `rank`, so every future consumer of it inherits the same problem — the
codebase's answer is `clampi` before indexing, which `Item.rank_label` and `Hero.compute_final_stats`
already did and salvage now does too.

`P2-05g` then landed in `4595b3f`, so parts have somewhere to go and the `P2-05` group is down to
enhancement alone — `P2-05e` (the ruling) and `P2-05f` (the code), in that order. Its open siting
question resolved to **not the Forge**: `hub/hub.tscn`'s five buildings are decoration with no
panel until `P2-07`, so the control sits under the `Parts` label in the Inventory column and moves
with the readout when buildings become real. Any later ticket taking `SYSTEMS.md`'s "at the Forge"
literally should expect that. It also left one gap on the record: **no test presses the Convert
button.** `tests/unit/test_expedition.gd` instantiates `hub.tscn` for unrelated reasons, which
reddens the suite if a `%UniqueName` stops resolving — that accident is the only thing behind the
scene↔script seam here, and it is not coverage of the handler.

`P2-05e` then ruled all three open inputs, so `P2-05f` is unblocked and the `P2-05` group is one
ticket from closed. The `+8%` is **additive** — `contribution * (1 + 0.08 * enhance_level)` — ruled
on precedent, not on a cap: both readings clear the `75%` crit cap (`41.96%` additive against
`53.87%` compounded), so the cap decided nothing here the way it decided the crit channel in
`P2-05b`. What decided it is that nothing else in `Hero.compute_final_stats` compounds — level and
rank are additive-then-one-multiply, `rank_mult` is an authored array and not a runtime `pow()` —
and `1.08^15` would stack a second steep exponent on the already-rank-scaled equip curve, taking
gear share of a maxed SSS stat to `67.46%` against additive's `58.98%`. **Gold is struck**, not
valued: zero hits across `*.gd`/`*.tres`/`*.tscn` and no income source anywhere, so pricing it
would ship a wall a player has no way to clear. It comes out of Enhancement's *and* Buildings'
cost lines until a ticket gives it a rate — `P2-10` below, opened for exactly the reason `P2-09`
and `P2-04a` were. The cap ships **flat at 15**: `forge_level` does not exist, so
`min(15, forge_level * 3)` evaluates to `0` today and Enhancement could apply no level at all;
`forge_enhance_cap_per_level` stays authored-but-unread until `P2-07`. That third question was
outside the backlog row's two and folded in anyway, because nothing else owned it and `P2-05f`
would still have been blocked without it.

`P2-05f` then landed in the commit below and **the `P2-05` group is closed** — items now gain
levels, cost parts to do it, hit harder for it, and salvage back more. Two findings outlive it.
The ticket's own criterion 3 specified `enhance_item(item: Item) -> bool`, a signature that
*cannot* read a balance number without an autoload holding a shared Resource — which
`ARCHITECTURE.md` § "Reaching shared Resources" prohibits by name. The first pass did exactly
that, and the import gate plus 53 green tests said nothing, because there is no functional bug:
`ResourceLoader` caches by path. Only the review caught it. **A ticket can specify a boundary
violation, and gates cannot tell you it did.** Corrected to `balance: BalanceTable` passed
explicitly, on `enhance_item` *and* `salvage_item` — an autoload signature change, whose second
caller is dynamic, which is `P2-04e`'s trap all over again. And `Dictionary.get(key, default)`
does **not** absorb an explicit `null`, only a missing key: `int(data.get("rank", 0))` throws on
a save containing `"rank": null` and hands `null` back into `inventory`. That predated the ticket
and adding `enhance_level` in the same shape doubled it; `Item._int_field()` now fixes both.
`Hero.from_dict` and `LostCache.from_dict` still carry it — that is `P2-11`.

`P2-11` closed that thread, and **half its premise was wrong**. `LostCache.from_dict` never
crashed: it type-validates every field it reads and contains no `int()` at all, so an explicit
`null` was already caught, reported and defaulted. Grepping for the pattern instead of trusting
the row found the real second site — `SaveService.load_game()`'s `version` read, which the row
never named and which crashes **at boot, before any `from_dict` runs**. The red-proof turned up a
third consequence nobody predicted: a `null` `Hero` appended to `roster` poisons
`GameSession.to_dict()` two lines later, because `from_dict` ends in `roster_changed.emit()` →
`SaveService.save()`. That crash unwinds *before* `FileAccess.open`, so the corrupt file survives
instead of being truncated — luck, not design. `Item._int_field` is now public as
`Item.int_field(data, key, fallback, subject)` and used at all three sites: `systems/` is
autoloads only and the layout has no home for a save-decode util, so the alternative was copying
thirteen lines twice.

**P2-06 split.** The line bundles three things: a sacrifice/essence/rank-up mechanic, dupe
resonance as a *counter*, and dupe resonance as a *payoff*. The counter is buildable today
against already-authored `BalanceTable` data (`essence_bases` and `rank_up_essence_costs`,
`balance_table.gd:8-9`); the payoff is not — `HeroDefinition` (`heroes/hero_definition.gd`) is
`display_name`/`role`/eight stat fields/two crit fields and nothing else, no trait type exists
anywhere in the codebase, and `SYSTEMS.md:167-169`'s "unlocks traits from that hero's definition
trait pool" names data nobody has authored. That is the `P2-04a`/`P2-09`/`P2-04b` "found, not
authored" shape, not something a ticket body can specify around.

A second omission sits inside the buildable half rather than forcing a further split:
`SYSTEMS.md`'s yield formula multiplies by `(1.0 + fodder.level / level_cap[fodder.rank])`, and
`Hero` (`heroes/hero.gd:16-19`) has no `level` field — only `hero_name`, `rank`, `def_id`,
`equipped`. The only place a "level" exists today is `combat/quick_resolve.gd:21-23`, which
passes `BALANCE.level_caps[hero.rank]` into `compute_final_stats` — every hero is treated as
permanently max-level for *combat stats*, a convenience for a system with no real level yet, not
evidence a stored value exists. Multiplying every sacrifice by a constant `2.0` and shipping "a
max-level sacrifice yields double" as a real mechanic would be exactly the trap `P2-04e` flagged
for `turn_lost` and `P2-05f` flagged for `enhance_level`: a field whose only possible value today
is a placeholder reads as real data. `P2-06a` ships the flat rate — `essence_base[fodder.rank]`,
no level multiplier — and leaves the term for whichever ticket adds `Hero.level`; `P2-04a`
(XP-per-level curve) is the nearest candidate, and is not reopened or expanded here.

Split into: `P2-06a` is sacrifice, essence, rank-up, and dupe resonance *counted* — the ×3 yield
and the resonance increment — buildable now, no ruling needed. `P2-06b` is resonance's payoff,
the trait unlocks at 1/3/6, blocked on `game-designer` authoring a trait pool on
`HeroDefinition`.

The boundary call `P2-06a` cannot dodge: sacrifice removes a hero from the roster, and
`GameSession.kill_hero()` (`systems/game_session.gd:105`) is the only call site `ARCHITECTURE.md`
r8 permits, and it builds a zone-scoped `LostCache` when the dying hero's `equipped` is
non-empty — a branch that means nothing for a sacrifice, which never happens "in" a zone. Rather
than generalizing `kill_hero()` for a death that never occurred in a zone, `P2-06a` requires
fodder to be unequipped first, the same "only unowned items" precondition `P2-05d` already put on
salvage. That makes `hero.equipped.is_empty()` hold by construction, so `kill_hero(fodder, &"")`
never builds a cache — `LostCache`'s `zone_id` already defaults to `&""`
(`equipment/lost_cache.gd:9`), so no default value needs adding. The single call site stays
single.

One ruling *was* needed, and it went the opposite way to the obvious reading. `DECISIONS.md`
2026-08-01 rejects "putting rank-up and salvage logic as methods on `GameSession`" by name, and
`salvage_item`/`enhance_item`/`convert_parts` shipped that way regardless — three contradictions
that read like a stale ADR. They are not. `CODING_RULES.md:93-103` still states the rule in the
present tense, and its worked example is named `compute_essence_yield(fodder, target, balance)`
— the exact function this ticket needs, authored before any of the violations. Two documents
agreed and only the code drifted, so `DECISIONS.md` 2026-08-06 **reaffirmed** the rejection and
named the three methods debt (`P2-12`). What decided it was that the rejection's stated cost had
come true rather than been avoided: there is no `GameSession.new()` anywhere in the codebase, so
every test of those formulas boots the engine, exactly as predicted. Frequency of violation is
not evidence a rule should change. `P2-06a` therefore splits: orchestration on `GameSession`
(which r8 pins there anyway, since only it may call `kill_hero()`), arithmetic in two pure
`static func`s on `Hero`.

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
| P2-05d | Salvage an unwanted item into parts | Body in `TASKS-DONE.md`. `parts` is a fixed 8-element `Array[int]` indexed by rank, which sidesteps the JSON int-key trap rather than working around it. **Read its Findings before writing another `assert()` on a value that can come from a save file** — asserts are stripped in release, so the first pass was unguarded in the only build a player runs, and a negative rank did not even throw: it credited SSS while displaying F. |
| P2-05e | Enhancement design ruling — the `+8%` reading, and what gold is | No body — this was a backlog row, and the ruling itself is `SYSTEMS.md` § Enhancement. Additive `+8%`, gold struck, cap flat at 15; took the cap question too, which the row had left to `P2-07`. Also corrected a stale `SYSTEMS.md` line claiming nothing clamps `CRIT_RATE` against `equip_crit_rate_cap` — `P2-05c` shipped that clamp (`heroes/hero.gd:92`). Unblocked `P2-05f`, opened `P2-10`. |
| P2-05f | Enhancement — `Item.enhance_level`, `+8%`/level, parts-only cost | Body in `TASKS-DONE.md`. Closes the `P2-05` group. Shipped exactly `P2-05e`'s terms. **Read its Findings before writing a ticket that hands an autoload a balance number** — criterion 3 as written specified a signature that could only be satisfied by violating `ARCHITECTURE.md` § "Reaching shared Resources", and no gate could tell. `salvage_item`/`enhance_item` now take `balance: BalanceTable` explicitly. Also fixed `Item.from_dict`'s explicit-`null` crash on `rank` (pre-existing) and `enhance_level` via `_int_field()`; the same defect survived elsewhere as `P2-11`, which found `LostCache` was already safe and `SaveService` was not. |
| P2-05g | 3:1 part conversion | Body in `TASKS-DONE.md`. Sited in the Inventory column, **not** the Forge — buildings have no panel until `P2-07`, so siting it there meant inventing one inside this ticket. Confirms `OptionButton.selected` is never `-1` while items exist, which `%ZoneOption` had been assuming unwritten. Read its Findings before adding another persisted mutation: the disk leg deliberately omits an explicit `save` so a missing `roster_changed.emit()` fails it. |
| P2-05a | Equip UI for authored equipment | Body in `TASKS-DONE.md`. Not split — assignment, persistence and an ugly UI shipped; combat effect stayed an explicit non-goal, since no ticket has ever authored what a rank-`N` item contributes. That gap is now `P2-05b`'s. Unblocked `P2-04e`. Corrected a false `KNOWN_ISSUES.md` claim: a plain GUT run **does** overwrite the real `user://save.json`. Read its Findings before trusting another in-memory `to_dict`/`from_dict` test as save-boundary evidence — `slot` reaches disk as `8.0`, and only the disk leg proves the float branch. |
| P2-05b | What a rank-`N` item contributes to a hero's stat | Body in `TASKS-DONE.md`; the ruling itself is `SYSTEMS.md` § Primary stat magnitude. Three new `BalanceTable` fields — `equip_pct_per_rank` (`0.04 × rank_mult`, eight non-crit slots, two per stat summing into one `equip_pct`), `equip_crit_pct_per_rank` (`0.015 × rank_mult`, necklace/ring, via `equip_flat`), `equip_crit_rate_cap = 0.75`. Not a reuse of `stat_multipliers`: same ratios, own scalar, so a hero-curve retune can't silently reprice every item. Unblocked `P2-05c`. |
| P2-05c | Equipped gear changes combat power | Body in `TASKS-DONE.md`. **No signature change was needed** — this row predicted "the seam is an extra argument"; `compute_final_stats` already takes the `Hero`, and `equipped` has been on it since `P2-05a`, so gear applies in one function and `combat/` was never touched. `compute_team_power`'s crit-blindness is now pinned by an assertion (a ring moves `CRIT_DMG` and not team power), so the eventual fix has to delete it deliberately. Gear routing is indexed by `PrimaryStat` ordinal with `Hero.STAT_NAMES` mirroring it positionally — reordering either enum misroutes gear with a green gate, and only `tests/unit/test_equipment.gd` notices. |
| P2-04e | Lost-gear cache created on hero permadeath | Body in `TASKS-DONE.md`. `turn_lost` deliberately absent from `LostCache` — no turn counter exists to stamp it with, so `P2-04f` adds both. `kill_hero()` gained a `zone_id`; its **second caller is dynamic** (`tests/save_roundtrip_check.gd` via `.call()`), which grep for `kill_hero(` misses and the import gate cannot catch — read its Findings before changing any autoload signature. Also reopened once: the round-trip test shipped as in-memory `to_dict`/`from_dict`, the exact gap `P2-05a` warned about, and the disk leg had to be added to `save_roundtrip_check.gd`. Unblocks `P2-04f`. |
| P2-04f | Recovery expedition — damage roll + cache decay | `P2-04e` shipped the cache to target, and left this ticket the `turn_lost` field as well as the counter behind it. Blocked on two more design gaps: `power_deficit_penalty` in the damage formula (already PROVISIONAL in `SYSTEMS.md`) and a "turn" concept, which doesn't exist anywhere in the codebase today despite the decay clock being turn-denominated. |
| P2-06a | Sacrifice a hero for essence; spend essence to rank another up, dupe resonance counted | **Full body below.** Ships the flat `essence_base[fodder.rank]` yield with no level term — `Hero` has no `level` field yet (`P2-04a` is the nearest candidate to add one). Unblocked now; no ruling needed. |
| P2-06b | Resonance trait payoff — unlock a trait at 1/3/6 dupes | Found by `tech-lead` splitting `P2-06`, deliberately not authored — `SYSTEMS.md:167-169` names traits unlocking "from that hero's definition trait pool," but no trait type or pool exists anywhere in the codebase (`HeroDefinition` is eight stat fields and two crit fields, nothing else). Same shape as `P2-04a`/`P2-09`/`P2-04b`: a design gap found while scoping, not a ruling a ticket body can specify around. |
| P2-12 | Extract `salvage_item`/`enhance_item`/`convert_parts`'s arithmetic into pure functions | Debt named by `DECISIONS.md` 2026-08-06, which reaffirmed the 2026-08-01 rejection of balance logic on `GameSession` rather than reversing it: the rejection's predicted cost came true — no `GameSession.new()` exists anywhere, so every test of these formulas boots the engine. Each method keeps its signature and becomes validate → call a `static func` → mutate → emit. Not urgent (all three are shipped, tested and round-tripping); it exists so the next ticket reads them as debt rather than precedent. |
| P2-07 | Five buildings as five integers | |
| P2-08 | Full save/load round-trip through `SaveService` | |
| P2-10 | Gold — what it is and how a player gets it | Found by `game-designer` during `P2-05e`, deliberately not authored there — an income rate is a design input, not something a ruling can pick. Gold is named in three zones' loot-table Reward prose and was named in Enhancement's and Buildings' cost lines; it has no `BalanceTable` field, no `GameSession` currency, and zero hits in `*.gd`/`*.tres`/`*.tscn`. `P2-05e` struck it from both cost lines rather than price a currency with no source. Add it back there once this lands. Same shape as `P2-09`/`P2-04a`. |
| P2-09 | Summon Stone income rate — how a player actually acquires stones | Found by `game-designer`, deliberately not authored by it — a design input, not a Resource-authoring task. Nothing defines acquisition rate today, which makes the verified ~327-pull spine number unvalidatable against real play time: the ratio is sound, the pacing is unknowable without this. Needed before the Phase 2 exit question below can be honestly answered. |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3. (See
P2-09 — that question can't be honestly answered until stone income rate is defined.)

---

## P2-06a — Sacrifice a hero for essence; spend essence to rank another up      [TODO]

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
| `P2-05a` | Equip UI for authored equipment | `0760d83` |
| `P2-05b` | Equipment magnitude ruling — what a rank-`N` item contributes | `c092fc3` |
| `P2-05c` | Equipped gear changes a hero's stats and team power | `b5525e7` |
| `P2-04e` | Lost-gear cache created on hero permadeath | `3885a14` |
| `P2-05d` | Salvage an unwanted item into parts | `5deb84e` |
| `P2-05g` | 3:1 part conversion | `4595b3f` |
| `P2-05e` | Enhancement design ruling — the `+8%` reading, and what gold is | `7ac7459` |
| `P2-05f` | Enhancement — spend parts to make one item stronger | `b6b5c47` |
| `P2-11` | An explicit JSON `null` no longer crashes the load path | `e9f661a` |

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
