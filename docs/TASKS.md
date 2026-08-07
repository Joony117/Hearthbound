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

**`P2-06b` unblocked; `P2-06c` opened.** `game-designer` authored `SYSTEMS.md` § Traits, which
closes the gap the split flagged — there is now a `TraitDefinition` type, a per-archetype pool
shape, and fifteen authored traits with magnitudes checked against the real equipment tables (no
archetype's full-resonance stack outweighs a single A-rank slot; the worst crit stack lands at
`43.46%`, well under the `75%` cap). It split one further time on its own terms: the *data* is
`P2-06c` and the *payoff* stays `P2-06b`, because the two have different risk profiles. Resonance
traits derive from the already-saved `resonance` int and touch no save key, while the reserved
`Hero.taught_traits` field does — so one half is a plain feature and the other is a boundary
change, and bundling them would hide that.

The ruling deliberately made one call it did not have to: **two pools rather than one tagged
pool.** `resonance_trait_pool` is read by resonance code, `instructor_trait_pool` is empty and
read by nothing until `P2-13`. That makes "instructor-taught traits are obtainable no other way"
a structural fact instead of a filtering discipline every future reader has to remember. Deciding
it now cost nothing; retrofitting it after `Hero.taught_traits` reaches a save file would cost a
migration, and `SaveService` has none (`systems/save_service.gd:35-38`, the `ponytail:` debt
comment — Phase 5 owns migration).

`P2-06c` then landed in `f4eea87` and **dropped the one thing the ruling specified that it did not
need: `Hero.taught_traits`.** The ruling justified shipping the field now as avoiding "a second
save-format bump later" — there is no bump to avoid, because `Hero.from_dict` already defaults every
missing key, so `P2-13` adding it later costs exactly what adding it today costs. What it would have
cost *today* is real: a save-boundary change (`CLAUDE.md` boundary 1) and a mandatory `verifier`
pass, for a field nothing writes and whose only possible value is `[]`. That is `LostCache.turn_lost`
(`P2-04e`) and `Item.enhance_level` (`P2-05d`) a third time. With it cut, `Hero.to_dict`/`from_dict`
are untouched and the ticket crosses no risky boundary — `P2-06b` inherits a plain feature.

**No ADR was written, and that omission is deliberate.** The `P2-06c` row asked `godot-architect`
to rule on whether a new Resource class plus exported fields on two existing definition Resources
needs one. `ARCHITECTURE.md`'s own amendment rule answers it: update it "when a boundary **actually
moves**, not when a file is added." `TraitDefinition` adds no autoload, no seam, and no new way of
reaching authored data — § "Reaching shared Resources" already covers "every `Definition` Resource",
and a trait pool arrives through the existing `Hero.definition_for()` path. A fifth definition
Resource built like the four before it is precedent, not a boundary move.

One finding outlives the ticket, for whoever authors a `.tres` next. **A typed array of a custom
script class serializes as `Array[ExtResource("<id>")]([SubResource(...)])`**, with the elements as
`[sub_resource]` blocks in the same file — no precedent for this existed here before `P2-06c`, every
prior typed array in a `.tres` being `Array[int]`/`Array[float]`. And Godot omits any field left at
its default, so `knight_stalwart` carries no `stat =` line at all (HP is ordinal `0`): the five
authored files are **not** structurally uniform, and that is correct rather than a dropped field.
`tests/unit/test_traits.gd` loads all five from disk and asserts `id`/`stat`/`magnitude` precisely
because a mis-serialized pool is invisible to the import gate.

`P2-06b` then landed in `26103f7` and **closes the `P2-06` group**. It shipped exactly the scope the
row named — eight lines in `Hero.compute_final_stats`, no new field, no signature change, no save
key — because `P2-06c` had already built the type, the pools and `active_resonance_traits()`. Traits
join gear's existing `equip_pct` accumulator rather than getting their own multiply, so a DEF trait
and a DEF chestpiece sum before the single `*= 1.0 + equip_pct[index]`, which is the only shape
`SYSTEMS.md` § Enhancement's ruling recognises.

One gap outlives it, and no ticket owns it: **nothing in the hub displays resonance, traits, or any
hero stat.** `P2-06a` shipped the resonance counter invisible and this ticket shipped its payoff the
same way, so the only way a player observes either is an expedition outcome shifting — the arithmetic
is proven by `tests/unit/test_traits.gd`, not by anything on screen. That is a display ticket, not a
combat one; route it through `tech-lead` if the Phase 2 exit question ("is spending a hero's life a
decision you actually feel?") turns out to need it, since a payoff nobody can see is a plausible
reason the answer comes back no.

**`P2-14` closed that gap** rather than waiting for the exit question to fail on it — the hub now
shows a selected hero's six computed stats, its resonance count and its active traits, so gear,
rank-ups and dupes are visible where they happen. It went straight to an implementer without a
`tech-lead` pass: the scope was one readout over functions that already existed
(`compute_final_stats`, `active_resonance_traits`), needed no design ruling and no balance number,
and touched no save key. The one design decision inside it was rendering crit to one decimal instead
of an integer, which its Findings explain.

**`P2-07a` ruled buildings' two missing numbers**, so `P2-07` can be written. The gap was narrower
than the backlog row implied: all eight magnitudes were already authored (`balance_table.gd:18-28`)
and nothing reads any of them. What was missing was a **cost** — `SYSTEMS.md` said "Upgrade cost:
parts", and `parts` is an 8-element rank-indexed array (`game_session.gd:12`), so that names no
number — and **caps** for the three buildings that had none.

Upgrade cost is `10 * (n + 2)` parts of **rank index `n`**, `n` being the level before the upgrade:
`20` F → `30` D → `40` C → `50` B → `60` A. The rank climbs with the level rather than the quantity,
which is Enhancement's `2 + enhance_level` turned sideways — an item has a rank of its own to charge
against and a building does not. 264 expected clears to max one building against real
drop-and-salvage income, anchored deliberately against the ~327-pull manufactured-SSS number: a
building's payoff is permanent and account-wide, so one maxed should cost roughly what one
manufactured SSS costs. `5*(n+2)` (133 clears, undersells it) and `20*(n+2)` (526, makes buildings
the dominant parts sink) are both recorded as rejected. All five cap at level 5.

**The staging is the part that changes `P2-07`'s scope: three buildings, not five.** Training Hall's
`+15%` XP has no XP curve to modify (`P2-04a`, unstarted) and Reliquary's two effects have neither a
recovery expedition nor a turn counter (`P2-04f`, blocked on both) — so parts spent on either
provably change nothing. Circle, Forge and Sanctum each read a system that is live today. The cost
formula and the cap cover all five uniformly, so the two deferred ones need no second design pass
when their consumers land.

One assertion inside the ruling that `P2-04f` should not inherit unexamined: cap 5 is corroborated by
`0.03 * 5` exactly cancelling `damage_chance`'s `0.15` base term, which at `turns_elapsed = 0` is not
"clean" so much as **zero** — a maxed Reliquary makes a same-turn recovery risk-free and the
Damaged-gear mechanic unreachable. Sound as arithmetic, open as design; `P2-04f` owns that formula
and should rule on it rather than discover it.

`P2-07` itself is a `tech-lead` pass, not a direct implementer dispatch. Building levels are new
`GameSession` state and therefore a save-key change (`CLAUDE.md` boundary 1, mandatory `verifier`),
and no building panel exists in `hub.tscn` at all — `P2-05g` sited part conversion in the Inventory
column precisely because there was none to put it in.

**P2-07 split.** The backlog line bundles four things behind one row: new `GameSession` save
state (a level per building), a UI panel that doesn't exist anywhere in `hub.tscn` today, and
three independent consumer wirings — Circle into `summon` (a shared-Resource-array
renormalization, the exact hazard `ARCHITECTURE.md` § "Reaching shared Resources" names by
example), Forge into `enhance_item`'s cap and `salvage_item`'s yield, and Sanctum into
`sacrifice_hero`'s essence formula. `P2-05f` (Enhancement) — a single consumer wiring of
comparable size to any one of these three — was already a full ticket on its own; three of those
plus the state-and-UI foundation is a subsystem, not one behavior. Split into: `P2-07b` is the
foundation — `building_levels` exists, persists, and has a real (ugly) upgrade panel for
Circle/Forge/Sanctum, spending real parts against the ruled cost ladder, with every bonus still
inert. This mirrors `P2-05a` (equip UI shipped before any stat formula existed to move) rather
than `P2-04c`'s stricter "no UI at all" shape, because a level with no way to raise it isn't
observable at all. `P2-07c` wires the Summoning Circle's multiplier into `Summon.roll()` — the
trickiest of the three, since `Summon.roll()` is a static function on a plain `RefCounted` with
no autoload access, so the circle level has to be read out of `GameSession.building_levels` by
the caller (`hub.gd`) and passed in as an argument, and the renormalized weight table must be a
local copy — writing the scaled block back into `BALANCE.summon_weights` in place is exactly the
"mutating a shared Resource's exported array persists to the `.tres` on disk for every consumer"
hazard `ARCHITECTURE.md` names by example. `P2-07d` wires Forge's enhance cap
(`forge_enhance_cap_per_level * level`, capped at `forge_enhance_cap_max`) and salvage yield
bonus into `enhance_item`/`salvage_item`. `P2-07e` wires Sanctum's essence-yield bonus into
`sacrifice_hero`/`compute_essence_yield`. All three read `building_levels` directly off
`GameSession` — no signature change needed on any consumer method, since the level is the
autoload's own persisted state, not a shared Resource being smuggled through it (the distinction
`P2-05f`'s Findings drew). Sequence: `P2-07b` first — nothing in `c`/`d`/`e` has a level to read
without it. `c`/`d`/`e` are independent of each other and can land in any order.

**A gap `P2-07a` did not close: `forge_salvage_yield_bonus`'s scaling law is unruled.**
`SYSTEMS.md` § Base buildings states Training Hall's `+15%`/level and Sanctum's `+10%`/level both
scale to their cap-5 values (`+75%`, `+50%`) in the "at cap" recap paragraph, but that paragraph
never mentions Forge's salvage-yield bonus at all, and the field name (`forge_salvage_yield_bonus`
— no `_per_level` suffix, the same shape as `sanctum_essence_yield_bonus`, which *is* ruled to
scale) gives no answer either way: flat `+10%` once Forge is built at all, or `10% * level` up to
`+50%` at cap? `P2-07d` cannot be written against this until it's ruled — flagged here rather
than invented inside `P2-07d`'s own body. Route to `game-designer` before expanding `P2-07d`.

## P2-07b — Circle, Forge, and Sanctum are levelable                        [TODO]

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
  keys (`P2-05d`'s Findings, `TASKS-DONE.md`). Building levels follow the same shape.
- `hub.tscn`'s `Buildings` node (`hub/hub.tscn:39-86`) lists all five buildings in a fixed child
  order — `SummoningCircle`, `Forge`, `TrainingHall`, `Sanctum`, `Reliquary` — as `MeshInstance3D`
  decoration with a `Label3D` each, no script, no interaction; `hub.gd` never references any of
  them. This is the only place all five buildings are already named in the project, and this
  ticket's array indices follow that same order so a later ticket adding Training Hall/Reliquary
  is an append, not a renumber.
- `BalanceTable.summoning_circle_level_cap = 5` (`balance_table.gd:21`) is the only authored
  per-building cap field. `SYSTEMS.md` § Base buildings' "Level caps" ruling states all five
  buildings share cap 5 "absent a reason to diverge" — this ticket reuses that one field as the
  shared cap for every building rather than adding four more identically-valued fields. (Forge's
  own enhance-level cap, `forge_enhance_cap_max`, is a different number for a different thing —
  untouched by this ticket.)
- Upgrade cost is `10 * (n + 2)` parts of rank index `n` (`SYSTEMS.md` § Base buildings, `n` =
  the building's level before the upgrade, 0 = unbuilt) — the same "rank climbs with level,
  quantity fixed" shape `enhance_item`'s `2 + enhance_level` already established sideways.
- `hub.tscn`'s `UI/Root` has `RosterPanel` and `EquipmentPanel` as its only two panels today, each
  a `VBoxContainer` of `ItemList`s/`Button`s wired through `[connection]` blocks to `_on_*_pressed`
  handlers in `hub.gd` — `Equip`/`Salvage`/`Enhance`/`Convert` under
  `EquipmentPanel/Columns/Inventory` (`hub/hub.tscn:178-200`) is the pattern to copy. No building
  panel exists anywhere; `P2-05g`'s Findings note the 3:1 conversion control had to be sited in
  the Inventory column for exactly this reason.
- `enhance_item`/`salvage_item`/`sacrifice_hero` (`systems/game_session.gd:58-111`) already take
  `balance: BalanceTable` as an explicit argument rather than reading a preloaded const off the
  autoload (`ARCHITECTURE.md` § "Reaching shared Resources"; `P2-05f`'s Findings — the ticket that
  got this wrong the first time and was corrected in review). `building_levels` is different: it
  is `GameSession`'s own persisted *state*, not a shared Resource, so `GameSession`'s own methods
  may read it directly with no signature change — the rule this ticket must respect is about
  `balance.tres`, not about a method reading its own autoload's fields.

### Acceptance criteria
1. `GameSession.building_levels: Array[int] = [0, 0, 0, 0, 0]`, indexed to match `hub.tscn`'s
   `Buildings` child order (0 = Summoning Circle, 1 = Forge, 2 = Training Hall, 3 = Sanctum,
   4 = Reliquary). Persists through `to_dict`/`from_dict` using the exact guard `parts` already
   uses (`_array_field` + explicit int-or-integral-float decode, `push_error` and skip anything
   else, `mini(saved.size(), building_levels.size())` so a save from before this ticket defaults
   every entry to 0).
2. `GameSession.upgrade_building(index: int, balance: BalanceTable) -> bool` — returns `false`
   without writing anything when `index` is outside `[0, building_levels.size())`. Otherwise reads
   `building_levels[index]` clamped to `[0, balance.summoning_circle_level_cap]` (defensive
   against a hand-edited save — same clamp-before-index convention `item.rank`/`enhance_level`
   already use, `P2-05d`/`P2-05f`'s Findings) as `level`; returns `false` if
   `level >= balance.summoning_circle_level_cap`, or if
   `parts[clampi(level, 0, parts.size() - 1)] < 10 * (level + 2)`. On success it spends that many
   parts of rank `level`, sets `building_levels[index] = level + 1`, and emits `roster_changed`.
3. Only indices 0 (Circle), 1 (Forge), 3 (Sanctum) are reachable through the UI this ticket ships
   (criterion 5). Indices 2 and 4 stay `0` forever until a future ticket adds their buttons — the
   same "authored but unread" status `training_hall_xp_bonus`/`reliquary_*` already carry,
   extended to a save-state slot.
4. No building's bonus changes any gameplay number yet.
   `summoning_circle_multiplier_per_level`, `forge_enhance_cap_per_level`,
   `forge_salvage_yield_bonus`, `sanctum_essence_yield_bonus` stay authored-and-unread — wiring
   them is `P2-07c`/`P2-07d`/`P2-07e`.
5. A new `BuildingsPanel` under `hub.tscn`'s `UI/Root`, sibling to `RosterPanel`/`EquipmentPanel`,
   same register style: one row per shipped building (Circle, Forge, Sanctum) — a `Label` showing
   name and current level (e.g. "Summoning Circle — Lv 2") and an "Upgrade" `Button`. Three
   separate handlers (`_on_upgrade_circle_pressed`/`_on_upgrade_forge_pressed`/
   `_on_upgrade_sanctum_pressed`), matching the existing one-handler-per-button convention, each
   calling `GameSession.upgrade_building(<index>, BALANCE)`. Labels refresh on `roster_changed`,
   matching `_refresh_parts`/`_refresh_essence`.
6. On success the `%Status` line names the building, its new level, and the cost paid; on refusal
   (cap or insufficient parts) it says which reason applied, matching `_on_enhance_pressed`'s
   existing style.
7. GUT coverage in a new `tests/unit/test_buildings.gd`: the cost ladder for at least two steps
   (0→1 costs 20 F-rank parts, 1→2 costs 30 D-rank parts), refusal at cap 5 without writing,
   refusal on insufficient parts without writing, refusal on an out-of-range index without
   writing.
8. `tests/save_roundtrip_check.gd`: upgrade a building through a **real disk** save/reload cycle
   and assert the reloaded `building_levels` entry against the raw JSON — not an in-memory
   `to_dict`/`from_dict` pair. `P2-05a` and `P2-04e` both shipped that shortcut and both had to be
   reopened; do not repeat it.
9. Existing GUT suite passes unmodified.
10. BUILT green (`tests/import_gate.ps1`, zero `SCRIPT ERROR`/`ERROR:`/`WARNING`) and the full GUT
    suite green
    (`--headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`). Per
    `KNOWN_ISSUES.md` § Environment (`P2-14`'s finding), this command cannot run inside a Codex
    `workspace-write` sandbox — a red result relayed from a worker without checking `APPDATA`
    redirection is not evidence of a broken suite.
11. `verifier` re-runs both commands independently and confirms the save-key change round-trips
    on real disk — mandatory, not optional (`CLAUDE.md` risky boundary 1; global routing rule 4).

### Files allowed to change
`systems/game_session.gd` · `hub/hub.gd` · `hub/hub.tscn` · `tests/unit/test_buildings.gd` (new) ·
`tests/save_roundtrip_check.gd`

### Non-goals
- Any building's bonus actually applying to gameplay — `P2-07c` (Circle → summon), `P2-07d`
  (Forge → enhance cap + salvage yield), `P2-07e` (Sanctum → sacrifice essence). This ticket only
  makes levels exist and be spendable.
- Training Hall and Reliquary buttons — indices reserved, unreachable through this UI
  (`P2-04a`/`P2-04f` unblock them later).
- Gold, in any form — struck from `SYSTEMS.md` entirely.
- A generic `Building` Resource/definition type, a build queue, timers, or construction
  animation — `SYSTEMS.md` § Base buildings explicitly rules these out.
- Renaming `summoning_circle_level_cap` to a more general name. Reused as-is; a rename is a
  docs+code polish pass, not a blocker, and can happen whenever a later ticket next touches this
  field.

**P2-13 — the five questions a `game-designer` ruling must answer before it can be written.**
Filed blocked rather than dropped, because the idea is worth keeping and the dependencies are
real. Recorded here so a cold session inherits the reasoning instead of rediscovering it:

1. **The spine conflict — the load-bearing one.** § Sacrifice → rank up states the economy
   *inverts* on hoarding: feeding the natural spread of pulls costs **~327 pulls** to build an
   SSS, while a player who only scraps F-junk needs **~6,363** — worse than gambling for SSS
   directly. Training is scoped as a *parallel progression track*, which hands players a concrete
   reason to hoard exactly the F–C ranks the spine needs fed. Either the ~327 number gets
   re-derived against a two-sink economy, or training's throughput is capped so it cannot
   displace sacrifice. It cannot simply be assumed to still hold.
2. **The lethality paradox.** "Only the strong survive" needs a zone lethal enough to kill F–C
   heroes, but F–C heroes only survive low-power zones — an F-rank in an F-tuned zone is a coin
   flip, not a meat grinder. Likely resolution: the **instructor's rank gates the survivable zone
   tier**, so the instructor sets the tier and the trainees carry the risk. Unruled.
3. **Rank ceiling on natural growth** — a flat constant (B? A?), or the instructor's rank minus an
   offset. The choice interacts with (1): a higher ceiling makes training more competitive with
   the spine.
4. **The trainee survivability bonus is probably not a trait.** A temporary, rank-limited
   expedition modifier is a different mechanic from a permanent stat modifier, and `SYSTEMS.md`
   § Traits deliberately scoped traits to the latter. Conflating them would push scope back into
   `P2-06c`. This ticket owns it.
5. **Fodder opportunity cost.** A hero in training is unavailable to sacrifice. The two paths have
   to trade against each other rather than stack, or (1) resolves itself the wrong way.

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
| P2-04f | Recovery expedition — damage roll + cache decay | `P2-04e` shipped the cache to target, and left this ticket the `turn_lost` field as well as the counter behind it. Blocked on two more design gaps: `power_deficit_penalty` in the damage formula (already PROVISIONAL in `SYSTEMS.md`) and a "turn" concept, which doesn't exist anywhere in the codebase today despite the decay clock being turn-denominated. Also inherits a question `P2-07a` raised and did not own: at Reliquary level 5 the `−3%`/level reduction cancels `damage_chance`'s `0.15` base exactly, so a same-turn recovery has **zero** damage chance and Damaged gear becomes unreachable. |
| P2-06a | Sacrifice a hero for essence; spend essence to rank another up, dupe resonance counted | Body in `TASKS-DONE.md`. Shipped the flat `essence_base[fodder.rank]` yield with no level term. First ticket to follow `DECISIONS.md` 2026-08-06 instead of the `P2-12` debt shape — the arithmetic is two pure `static func`s on `Hero` and `tests/unit/test_sacrifice.gd` reaches both without booting an autoload. **Read its Findings before wiring another `OptionButton` to a destructive action:** `add_item()` auto-selects index 0 on a cleared button, so the fodder slot silently retargeted the next hero after a sacrifice and a blind second press killed the wrong one — permanently. Both gates stayed green through it; only driving the real scene caught it. Sharpens `P2-05g`'s `selected`-is-never-`-1` note into a data-loss rule. |
| P2-06b | Resonance trait payoff — unlock a trait at 1/3/6 dupes | **Landed `26103f7`.** No body — this was a backlog row, and `SYSTEMS.md` § Traits was the spec. Shipped as eight lines in `Hero.compute_final_stats` and four tests: no new field, no signature change, no save key, no `.tres` touched. Left one gap nothing owns — **no hub UI shows resonance, traits or hero stats**, so the payoff is only observable through expedition outcomes; see above. Original spec, for reference — the data, the pools and `Hero.active_resonance_traits()` all exist; this ticket is the one call site that consumes them, extending `compute_final_stats`'s existing `equip_pct` accumulator (non-crit) and flat crit add (ahead of the `equip_crit_rate_cap` clamp). It touches no save key. Was a design gap — `SYSTEMS.md` named a "definition trait pool" that existed nowhere in the codebase. `SYSTEMS.md` § Traits is now the ruling: `TraitDefinition` Resource, two pools on `HeroDefinition`, 15 authored traits, and the `resonance_trait_thresholds` shape. Depends on `P2-06c` shipping the data first — this ticket is the *payoff* (traits applying in `compute_final_stats`), not the type. Resonance traits need **no new `Hero` field**: they derive from the already-saved `resonance` int, so this half is not a save-boundary change. |
| P2-06c | Trait data exists — `TraitDefinition`, the two pools, the 15 authored traits | **Landed `f4eea87`.** No body — this was a backlog row, and `SYSTEMS.md` § Traits was the spec. Shipped **without `Hero.taught_traits`** (deferred to `P2-13`; see above and `SYSTEMS.md` § Traits §4), so no save key changed, no `verifier` pass was needed, and no ADR was written. Read its finding above before hand-authoring another `.tres` — typed arrays of a custom script class had no precedent here, and Godot omits default-valued fields so the five authored files are legitimately not uniform. Original spec, for reference — authored by `game-designer` in `SYSTEMS.md` § Traits, which settles every open input: the Resource type and why it isn't a `BalanceTable` effect table, `resonance_trait_pool` (exactly 3, ordered, unlock index = array index) and `instructor_trait_pool` (empty, reserved for `P2-13`), `resonance_trait_thresholds` on `BalanceTable`, and the two effect channels (percentage into `equip_pct` for HP/ATK/DEF/SPD, flat into `equip_flat` for the crit stats, ahead of the existing `equip_crit_rate_cap` clamp). `stat` reuses `EquipmentDefinition.PrimaryStat` rather than a second enum — **`P2-05c`'s warning applies: that ordinal positionally mirrors `Hero.STAT_NAMES`, so reordering either enum misroutes traits with a green gate.** Ships the data and the pure `static func`; `P2-06b` is what makes it visible. `godot-architect` should rule first on whether a new Resource class plus exported fields on two existing definition Resources needs an ADR. Adding `Hero.taught_traits` is a **save-boundary change** (`CLAUDE.md` risky boundary 1) and requires a `verifier` pass with a real save/reload cycle — a green import gate is not evidence. If it ships without `taught_traits` (reserved, unpopulated until `P2-13`), say so explicitly rather than leaving the field half-wired. |
| P2-12 | Extract `salvage_item`/`enhance_item`/`convert_parts`'s arithmetic into pure functions | Debt named by `DECISIONS.md` 2026-08-06, which reaffirmed the 2026-08-01 rejection of balance logic on `GameSession` rather than reversing it: the rejection's predicted cost came true — no `GameSession.new()` exists anywhere, so every test of these formulas boots the engine. Each method keeps its signature and becomes validate → call a `static func` → mutate → emit. Not urgent (all three are shipped, tested and round-tripping); it exists so the next ticket reads them as debt rather than precedent. |
| P2-14 | Hero detail readout — final stats, resonance, active traits | Body in `TASKS-DONE.md`. Closes the gap `P2-06b` flagged and nothing owned: gear, resonance and traits were observable only through test output. `Hero.level_for()` now single-sources the rank→level derivation `combat/quick_resolve.gd` owned inline. Widened its own file list to `tests/unit/test_expedition.gd` — criteria 2/3/5 are scene behavior and that file already owns every hub-scene drive. **Read its Findings before writing another scene test:** `ItemList.select()` does not emit `multi_selected`, so emitting the signal is what exercises the `.tscn` `[connection]` block. Also read them before believing a red gate relayed from a Codex worker — the documented GUT command cannot run inside a `workspace-write` sandbox at all (`KNOWN_ISSUES.md` § Environment). |
| P2-07a | Building ruling — upgrade cost in parts, and the level caps | No body — this was a design gap inside `P2-07`, and the ruling itself is `SYSTEMS.md` § Base buildings. `10*(n+2)` parts of rank index `n`, cap 5 for all five, and **three buildings ship, not five**. Also corrected a stale § Summoning Circle note claiming the Circle still needs a `BalanceTable` schema change — both fields already exist (`balance_table.gd:18,21`) and `summoning_circle_weight_shift` appears nowhere. Unblocked `P2-07`. |
| P2-07 | ~~Circle, Forge and Sanctum are levelable, and their bonuses apply~~ **SPLIT** | `tech-lead` pass done — split into `P2-07b`/`c`/`d`/`e`, rationale above. Scoped to **three** buildings by `P2-07a`; Training Hall and Reliquary trail `P2-04a`/`P2-04f`. The four authored-but-unread magnitudes (`balance_table.gd:18,21-24,26`) are wired by `c`/`d`/`e`, not `b`. |
| P2-07b | Building levels exist, persist, and are spendable — Circle/Forge/Sanctum upgrade panel | **Body above.** The foundation; nothing in `c`/`d`/`e` has a level to read without it. New `GameSession.building_levels` = a save-key change, so `CLAUDE.md` boundary 1 and a **mandatory `verifier` pass with a real disk save/reload** — not an in-memory `to_dict`/`from_dict` (`P2-05a`, `P2-04e` both shipped that shortcut and were reopened). Ships the first `BuildingsPanel` in `hub.tscn`; every bonus stays inert, same precedent as `P2-05a` shipping equip UI before any stat formula existed. |
| P2-07c | Wire the Summoning Circle's multiplier into `Summon.roll()` | Trickiest of the three wirings. `Summon.roll()` is a `static func` on a plain `RefCounted` with no autoload access, so `hub.gd` reads the level off `GameSession.building_levels` and passes it in. **The renormalized weight table must be a local copy** — scaling `BALANCE.summon_weights` in place persists to the `.tres` on disk for every consumer, the hazard `ARCHITECTURE.md` § "Reaching shared Resources" names by example. Blocked on `P2-07b`. |
| P2-07d | Wire Forge's enhance cap + salvage yield into `enhance_item`/`salvage_item` | Blocked on `P2-07b` **and on a design gap `P2-07a` did not close** — `forge_salvage_yield_bonus`'s scaling law is unruled: flat `+10%` once built, or `10% * level` to `+50%` at cap? `SYSTEMS.md`'s "at cap" recap covers Training Hall and Sanctum and never mentions Forge, and the field name settles nothing. Route to `game-designer` before expanding this into a body. |
| P2-07e | Wire Sanctum's essence-yield bonus into `sacrifice_hero`/`compute_essence_yield` | Simplest of the three. Blocked on `P2-07b`. Reads `building_levels` directly off `GameSession` — no signature change, since the level is the autoload's own persisted state, not a shared Resource smuggled through it (the distinction `P2-05f`'s Findings drew). |
| P2-08 | Full save/load round-trip through `SaveService` | |
| P2-10 | ~~Gold — what it is and how a player gets it~~ **CLOSED — will not do** | Superseded by `SYSTEMS.md` § Enhancement's gold-removal ruling (2026-08-06), which struck gold from the document entirely rather than deferring it. This row asked for an income rate; the ruling's **Rejected: give gold an income rate and keep it as a third currency** answers it directly — Summon Stones (pulling) and parts (upgrading) already cover the two earned-currency tracks, and every cost line downstream of `P2-05e` settled on parts-only, so nothing was left to spend it on. Do not re-open without a system that needs a third currency. Left the residue as `P2-15`. |
| P2-15 | Sync three zones' `loot_emphasis` strings to the gold-removal ruling | Code follow-up flagged inside `SYSTEMS.md` § Enhancement's gold-removal ruling, out of a docs-only pass's bounds. Drop the `"Gold, "` prefix from `zones/defs/verdant_outskirts.tres`, `ashfall_reaches.tres`, `sundered_vault.tres` and the matching expected literals in `tests/zone_definition_check.gd`. Free-text display strings only — no `BalanceTable` field, no save key, not a boundary change. Rung 1/2: four string edits, not a subsystem. |
| P2-09 | Summon Stone income rate — how a player actually acquires stones | Found by `game-designer`, deliberately not authored by it — a design input, not a Resource-authoring task. Nothing defines acquisition rate today, which makes the verified ~327-pull spine number unvalidatable against real play time: the ratio is sound, the pacing is unknowable without this. Needed before the Phase 2 exit question below can be honestly answered. |
| P2-13 | **[BLOCKED]** Fodder training — an instructor hero trains F–C fodder; survivors of background "culling" expeditions gain XP and rank up naturally | Blocked on four things that do not exist: `P2-04a` (no `Hero.level` or XP field at all — `combat/quick_resolve.gd:21-23` derives level from rank and treats every hero as permanently max-level), `P2-06c` (**landed `f4eea87`** — `instructor_trait_pool` now exists on `HeroDefinition`, reserved and empty as intended, and this ticket also inherits `Hero.taught_traits`, which `P2-06c` deliberately deferred rather than shipping empty; `SYSTEMS.md` § Traits §4 still specifies it in full), `P2-07` (the Training Hall is a grey-box mesh in `hub.tscn:41-89` and `balance_table.gd:24`'s `training_hall_xp_bonus = 0.15` is authored-but-unread), and a **turn concept**, which exists nowhere — `Expedition.resolve()` is synchronous, and `P2-04f` is blocked on the same gap. Four missing systems in one ticket is the "add an inventory system" shape this file exists to prevent; do not start it because one dependency landed. Needs a `game-designer` ruling first, on the five questions below. |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3. (See
P2-09 — that question can't be honestly answered until stone income rate is defined.)

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
| `P2-06a` | Sacrifice a hero for essence; spend essence to rank another up | `fc20c1e` |
| `P2-06c` | Trait data — `TraitDefinition`, two pools, 15 authored traits | `f4eea87` |
| `P2-06b` | Resonance traits change a hero's stats | `26103f7` |
| `P2-14` | The hub shows what a hero's stats actually are | `a47fb87` |
| `P2-07a` | Building ruling — upgrade cost in parts, and the level caps | `d0b04d7` |

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
