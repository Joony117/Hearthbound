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
hazard `ARCHITECTURE.md` names by example. (Note for `P2-07e`: the row below says "no signature
change", and that is about **`sacrifice_hero`**, whose own autoload state `building_levels` is. It
is not licence to let `Hero.compute_essence_yield` reach for the `GameSession` autoload — that
function is a pure `static func` on purpose, so `P2-06a`'s tests could exercise the arithmetic
without booting the engine, and `DECISIONS.md` 2026-08-06 reaffirmed exactly that split. The level
arrives as an argument. `hub.gd`'s pre-sacrifice **preview** calls the same function directly and
must be passed the same level, or it silently disagrees with the payout for players who upgraded —
an arity change the import gate catches, a wrong value it does not.) `P2-07d` wires Forge's enhance cap
(`forge_enhance_cap_per_level * level`, capped at `forge_enhance_cap_max`) and salvage yield
bonus into `enhance_item`/`salvage_item`. `P2-07e` wires Sanctum's essence-yield bonus into
`sacrifice_hero`/`compute_essence_yield`. All three read `building_levels` directly off
`GameSession` — no signature change needed on any consumer method, since the level is the
autoload's own persisted state, not a shared Resource being smuggled through it (the distinction
`P2-05f`'s Findings drew). Sequence: `P2-07b` first — nothing in `c`/`d`/`e` has a level to read
without it. `c`/`d`/`e` are independent of each other and can land in any order.

**The gap `P2-07a` did not close is now ruled.** `forge_salvage_yield_bonus` scales **per level** —
`10% * forge_level`, `0%` unbuilt to `+50%` at cap 5, applied as
`roundi((3 + enhance_level) * (1.0 + 0.10 * forge_level))` (`SYSTEMS.md` § Base buildings, landed in
the commit below). The flat `+10%`-once-built reading was rejected on arithmetic rather than taste:
under truncation it yields **literally zero** extra parts for `enhance_level` 0–6, which is the most
common salvage case there is — a fresh, unenhanced drop. That is the "reads real, measures nothing"
trap this backlog has now hit three times (`LostCache.turn_lost`, `Item.enhance_level`,
`reliquary_decay_turns_bonus`), and it is why the ruling also had to pin the **rounding function**:
`roundi()`, not `int()`, because truncation reproduces the same dead-bonus one level down (Forge
levels 1–3 would still read as zero on unenhanced junk). The recap paragraph that omitted Forge —
the silence that created the gap — is fixed. `P2-07d` is unblocked.

The ruling is marked `PROVISIONAL` on one axis only, and honestly: 0–2 extra parts per salvage at the
ranks players actually farm may not be *felt* as a reward without a tooltip. **Settled by:** a played
build with `P2-07d` wired. The arithmetic is not in question — the self-financing check lands at
~204.7 clears to max a building against `P2-07a`'s 264 baseline, a −22.5% shift that is real but not
degenerate.

**`P2-22` rules the turn concept, and `P2-04f` is no longer blocked.** Its *other* blocker had
already closed without the backlog noticing: `power_deficit_penalty` carries a real value
(`clamp(0.2 * (r - 1), 0.0, 0.2)`, `SYSTEMS.md` § Death and gear recovery) and has since `P2-04e`'s
era, while three rows here and one `SYSTEMS.md` paragraph still called it a gap. Check the ruling
before repeating a row's blocker list — this backlog has now shipped two tickets whose stated
premise was stale (`P2-11`, and this).

**A turn is one resolved expedition.** `GameSession.turns` is a new persisted field; `COMPLETED`,
`RETREATED` and `DEFEATED` tick it, `INVALID_TEAM` does not, and a recovery expedition ticks like
any other. It authored **no new number**, which is why it was director-written per rung 1 rather
than routed to `game-designer` — the four numbers denominated in turns (`15`, `+5`/Reliquary level,
`0.03 * turns_elapsed`, `LostCache.turn_lost`) were all already on the page waiting for a unit. What
it had to do instead was *check* them, because a clock nobody can run out is
`reliquary_decay_turns_bonus` becoming the fifth entry in this file's "reads real, measures nothing"
list. It is missable: a recovery needs `team_power >= zone.power * 0.5`, the deaths worth recovering
from are the ones that wipe the team capable of that, and rebuilding costs `~33.6` Verdant attempts
(`~19.5` with the Training Hall maxed) against a `15`-turn bare window. The Reliquary is what buys
that back, and Training Hall and Reliquary end up reading the same clock from opposite ends.

Two things it leaves. The window count is `PROVISIONAL` — an expedition is one button press with an
instant result, so 15 of them may not *read* as a deadline even though the rebuild arithmetic says
they are; **Settled by:** a played build where an Ashfall/Sundered wipe strands a cache. And the
`clampf` on `damage_chance` is outrun at Reliquary 4–5: the last 3 and 7 turns of those windows
return Damaged gear with certainty and a perfect team. That is `P2-07a`'s zero-cancellation residue
in a new place — sound arithmetic, open design, and `P2-04f`'s to rule rather than discover.

Split out of `P2-04f` rather than left inside it: `P2-23` is the counter itself — `GameSession.turns`,
`LostCache.turn_lost`, and a hub readout — which is a **two-key save-boundary change** (`CLAUDE.md`
boundary 1, mandatory `verifier`) and has nothing to do with the recovery mission it enables. That
leaves `P2-04f` as the mission type, the damage roll and the expiry sweep, and makes the Reliquary
buildable a follow-up in `P2-21`'s shape once its two magnitudes have consumers.

## ~~P2-12 — Salvage and enhance arithmetic moves off the autoload~~          [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. Two of the three methods the row named were extracted; `convert_parts` and
`upgrade_building` are recorded as deliberate non-goals rather than skipped. **Read its Findings
before writing another clamp test** — the first `compute_enhance_cap` assertion passed with the
clamp deleted, because `mini()` saturates.

## ~~P2-07b — Circle, Forge, and Sanctum are levelable~~                    [DONE]

**Landed `4f97261`.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed tickets below.
`c`/`d`/`e` all have a level to read now.

## ~~P2-07d — Forge level raises the enhance cap and the salvage yield~~     [DONE]

**Landed in the commit below, and the `P2-07` group is closed.** Body moved to
[`TASKS-DONE.md`](TASKS-DONE.md); row in Completed tickets below. All five of the Forge's,
Circle's and Sanctum's authored magnitudes are now read by the systems they were written for.

## ~~P2-16 — Pulls cost Summon Stones, and a clear pays them~~                [DONE]

**Landed in the commit below, and `P2-09`'s ruling is now wired end to end.** Body moved to
[`TASKS-DONE.md`](TASKS-DONE.md); row in Completed tickets below. Summon Stones are the first
currency in this game that a player can run out of.

## ~~P2-08 — A save survives a reload with items still in the bag and zones still cleared~~  [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. All eight persisted `GameSession` keys now have disk-level coverage, and no
production code changed to get there — the two untested keys were untested, not broken. Opened
`P2-17`: a refused save is left intact by `load_game()` and then overwritten by the first thing
the player does.

## ~~P2-04a — XP-per-level curve for expedition rewards~~                     [DONE]

**Landed in the commit below.** No body — this was a backlog row, and the ruling itself is
`SYSTEMS.md` § Hero leveling — XP curve and income. **Heroes level for real**: `Hero.level` and
`Hero.xp` become persisted fields, `xp_to_next_level(level) = xp_coefficient * (level + 1)` with
`xp_coefficient = 10`, income is `xp_per_wave = 4` per wave resolved on *every* outcome plus a
per-zone `xp_reward` of `24`/`72`/`192` on `COMPLETED` only. `~33.6` expected Verdant attempts to
climb F's cap, `~19.5` with the Training Hall maxed — which closes that building's PROVISIONAL and
gives `training_hall_xp_bonus` its first consumer. Retires § "Combat's level baseline" outright:
`BASELINE_LEVEL` goes away and `Hero.level_for()` becomes a clamp on a real field rather than a
derivation from rank.

Rank-up handling was **already ADR-settled** (`DECISIONS.md` 2026-08-01, "Rank-up preserves hero
level") and the ruling verified it arithmetically rather than re-deciding it — every one of the
seven transitions is a strict power increase, no dip. Spot-checked here: `212.0 × 1.35 = 286.2`
(F-cap Knight → D) and `3678.4 × 8.17/6.05 = 4967.36` (SS-cap → SSS) are exact, as are the
Training Hall cap figures (`4 × 1.75 = 7`, `24/72/192 × 1.75 = 42/126/336`).

Two things it surfaced are **not** `P2-04g`'s and are filed separately as `P2-18` and `P2-19`.
Read them before scheduling either: the first is a genuinely new softlock that only becomes
reachable *because* fresh heroes now fight below their cap.

## ~~P2-04g — A hero levels up from expeditions~~                             [DONE]

**Landed in the commit below, and `P2-04a`'s ruling is now wired end to end.** Body moved to
[`TASKS-DONE.md`](TASKS-DONE.md); row in Completed tickets below. Heroes carry a real persisted
`level` and `xp`, every expedition outcome pays, and a **retreat banks progress instead of losing
it** — which needed one file the ticket's own allowed-list had left out. **`fodder.level` is now a
real field**, so `P2-19` is live rather than moot.

## ~~P2-18 — A wiped roster always affords one more pull~~                     [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. The softlock `P2-04a` opened is closed for six lines of production code, and the
ticket crosses **no risky boundary** — because the ruling's `from_dict()` leg was cut as
speculative. Read its Findings before implementing another `game-designer` ruling verbatim.

## ~~P2-17 — A refused save is moved aside, not overwritten~~                 [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. A corrupt `user://save.json` is now preserved as `save.corrupt.json` and the main
menu says so, instead of being silently clobbered by the first thing the player does. Opened
`P2-20` (atomic write), which the ruling named rather than folded in. **Read its Findings before
writing another ticket's call-site audit** — this one cited `P2-04e`'s archive instead of grepping
the tree, and named one of three `load_game()` callers.

## ~~P2-20 — A crashed save leaves the previous save intact~~                  [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. `save()` stages to `user://save.tmp.json` and renames, so a crash mid-write can no
longer truncate the only save. **Read its Findings before adding another staged write** — the first
implementation discarded `store_string()`'s `bool` return and relocated the data loss from open-time
to write-time, and staging turned eight pre-existing unclosed read handles into failed saves.

## ~~P2-21 — The Training Hall is buildable, so its XP bonus can actually fire~~  [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. Four of the five buildings are now levelable, and `training_hall_xp_bonus` finally
multiplies by something a player can raise. **Read its Findings before citing a test as coverage** —
the ticket's own claim that `save_roundtrip_check.gd` round-tripped all five building indices was
wrong, and the `verifier` caught it: the loop ran over five and only ever drove one non-zero.

## ~~P2-23 — Turns exist, and a lost cache records the one it died on~~        [DONE]

**Landed in the commit below.** Body moved to [`TASKS-DONE.md`](TASKS-DONE.md); row in Completed
tickets below. The game counts something for the first time, and `LostCache.turn_lost` — the field
`P2-04e` refused to fabricate — is now a real number. The mandatory `verifier` pass returned
**pass-with-concerns** on all 8 criteria, its one finding being this ticket's own allowed-file list.
**Read its Findings before writing a test that drives an error branch** — GUT fails a test on an
unconsumed `push_error`, so the `INVALID_TEAM` test went red on the error rather than the assertion.

---

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
| P2-04a | XP-per-level curve for expedition rewards | **Landed** in the commit below. No body — this was a backlog row, and the ruling itself is `SYSTEMS.md` § Hero leveling — XP curve and income. `xp_coefficient * (level + 1)` at `10`, `xp_per_wave = 4` on every outcome, `xp_reward` `24`/`72`/`192` on `COMPLETED` only; `~33.6` Verdant attempts to climb F's cap. Retires § "Combat's level baseline" and `BASELINE_LEVEL` outright rather than tuning them, and gives `training_hall_xp_bonus` its first consumer. **Rank-up was already ADR-settled** (`DECISIONS.md` 2026-08-01) and was verified arithmetically rather than re-decided — worth copying: the row asked a question the archive had already answered. Opened `P2-04g` (the wiring), `P2-18` and `P2-19`. |
| P2-04g | A hero levels up from expeditions | Body in `TASKS-DONE.md`. Director-written per rung 1; `verifier` passed. **Read its Findings before writing another ticket's "Files allowed to change" list** — this one omitted `systems/game_session.gd`, and that omission was the ticket's only real defect: `OUTCOME_RETREATED` returns with no `roster_changed.emit()`, so XP earned on a retreat would have mutated the roster and never reached disk. Retreat is the *common* outcome for a climbing hero (`30.2%` at level 0 against `0%` completed), so the curve's whole premise depended on the file the list forbade. Two more criteria were wrong as written: 7 asked to delete a `BASELINE_LEVEL` that an earlier dispatch had already removed, and 1 specified a `clampi` that indexes `level_caps` with an unclamped `rank`. The GUT suite reddening was a **fixture** problem, not a regression — `HERO_POWER`/`HERO_MAX_HP` were F-cap figures, fixed with `hero.level = 10` in the factories rather than by retuning constants. |
| P2-18 | A wiped roster always affords one more pull | **Landed** in the commit below; body in [`TASKS-DONE.md`](TASKS-DONE.md). Ruled by `game-designer` (`SYSTEMS.md` § Roster-wipe recovery floor) as a **recovery floor**: `kill_hero()` tops `stones` up to exactly `summon_pull_cost` when it leaves the roster empty below that — one guaranteed pull, no hero, no essence, no items. The hero-count floor was rejected for cheapening every death near it, and the reserved-last-pull rule for only relocating the identical dead end. **Read its Findings before implementing a ruling verbatim:** the ruling also specified the same guard in `from_dict()` to rescue pre-existing stuck saves, and cutting that leg — no such save exists — is what kept this ticket off `CLAUDE.md` boundary 1 and out of a mandatory `verifier` pass. Also the second consecutive ticket whose allowed-file list omitted a real call site. Original row, for reference — `P2-09` sized the `300` starting stones against the pull spine assuming stones and hero survival are independent: `P2-09` sized the `300` starting stones against the pull spine assuming stones and hero survival are independent. Once fresh heroes fight at level 0 instead of at their rank's cap, a save that spends all `300` on 3 pulls and wipes that roster in one Verdant attempt (measured at up to `69.8%`) reaches `0` heroes and `<100` stones at once — cannot pull, cannot expedition. Needs a scope call before code: a hero-count floor, refusing to let the last pull-worth of stones be spent, or shipping nothing and teaching "field one hero at a time early", which costs nothing. |
| P2-19 | Sacrifice's `fodder.level` term — wire it or strike it | **Landed** in the commit below. No body — director-written per rung 1; the choice was **wire**, and it needed no `game-designer` pass because it authored no number: `SYSTEMS.md` § Sacrifice already *spends* the term, deriving its `~150`-pull optimistic bound from all-max-level fodder, so striking it would have invalidated published arithmetic while wiring it only made the code match. `P2-06a` had parked the term for "whichever ticket adds `Hero.level`" and `P2-04g` added it. Six lines in `heroes/hero.gd`, no signature change — both callers already pass `fodder` and `balance`, so `hub.gd`'s pre-sacrifice preview and `GameSession.sacrifice_hero`'s payout cannot disagree (contrast `P2-07e`, where the level arrived as a new argument and preview/payout had to be kept in step by hand). **The trap was integer division**: `fodder.level / level_cap` on two `int`s floors to `0` everywhere below the cap and `1` at it, which is the entire bonus dead and every existing test still green — the same "reads real, measures nothing" shape as `P2-07d`'s `roundi()`-not-`int()` ruling, `LostCache.turn_lost` and `reliquary_decay_turns_bonus`. The accumulator is `float` from the first line rather than cast at the end. Yield reads the **clamped** level (`Hero.level_for`), so a corrupt save carrying `level: 999` cannot mint essence; pinned by a test, along with the level term landing *inside* the `×3` dupe multiplier and not after it. Original row, for reference — `SYSTEMS.md` § Sacrifice's formula box has always read `essence_base[fodder.rank] * (1.0 + fodder.level / level_cap[fodder.rank])`; `Hero.compute_essence_yield()` has never implemented the level term, because there was no `fodder.level` to read. Two lines either way. Do not fold it into `P2-04g`; it is a Sacrifice-balance question, not an XP one. |
| P2-04d | Expedition clears can drop a real item into inventory | Body in `TASKS-DONE.md`. Unblocked `P2-05a`. Roll order is **slot then rank** — the ruling left it open, this pinned it. First disk-level proof that an `Item` survives JSON (`rank` decodes as `float` and `from_dict`'s `int()` absorbs it); read its Findings before writing another one-off `-s` check, which cannot statically name `Expedition`. |
| P2-05d | Salvage an unwanted item into parts | Body in `TASKS-DONE.md`. `parts` is a fixed 8-element `Array[int]` indexed by rank, which sidesteps the JSON int-key trap rather than working around it. **Read its Findings before writing another `assert()` on a value that can come from a save file** — asserts are stripped in release, so the first pass was unguarded in the only build a player runs, and a negative rank did not even throw: it credited SSS while displaying F. |
| P2-05e | Enhancement design ruling — the `+8%` reading, and what gold is | No body — this was a backlog row, and the ruling itself is `SYSTEMS.md` § Enhancement. Additive `+8%`, gold struck, cap flat at 15; took the cap question too, which the row had left to `P2-07`. Also corrected a stale `SYSTEMS.md` line claiming nothing clamps `CRIT_RATE` against `equip_crit_rate_cap` — `P2-05c` shipped that clamp (`heroes/hero.gd:92`). Unblocked `P2-05f`, opened `P2-10`. |
| P2-05f | Enhancement — `Item.enhance_level`, `+8%`/level, parts-only cost | Body in `TASKS-DONE.md`. Closes the `P2-05` group. Shipped exactly `P2-05e`'s terms. **Read its Findings before writing a ticket that hands an autoload a balance number** — criterion 3 as written specified a signature that could only be satisfied by violating `ARCHITECTURE.md` § "Reaching shared Resources", and no gate could tell. `salvage_item`/`enhance_item` now take `balance: BalanceTable` explicitly. Also fixed `Item.from_dict`'s explicit-`null` crash on `rank` (pre-existing) and `enhance_level` via `_int_field()`; the same defect survived elsewhere as `P2-11`, which found `LostCache` was already safe and `SaveService` was not. |
| P2-05g | 3:1 part conversion | Body in `TASKS-DONE.md`. Sited in the Inventory column, **not** the Forge — buildings have no panel until `P2-07`, so siting it there meant inventing one inside this ticket. Confirms `OptionButton.selected` is never `-1` while items exist, which `%ZoneOption` had been assuming unwritten. Read its Findings before adding another persisted mutation: the disk leg deliberately omits an explicit `save` so a missing `roster_changed.emit()` fails it. |
| P2-05a | Equip UI for authored equipment | Body in `TASKS-DONE.md`. Not split — assignment, persistence and an ugly UI shipped; combat effect stayed an explicit non-goal, since no ticket has ever authored what a rank-`N` item contributes. That gap is now `P2-05b`'s. Unblocked `P2-04e`. Corrected a false `KNOWN_ISSUES.md` claim: a plain GUT run **does** overwrite the real `user://save.json`. Read its Findings before trusting another in-memory `to_dict`/`from_dict` test as save-boundary evidence — `slot` reaches disk as `8.0`, and only the disk leg proves the float branch. |
| P2-05b | What a rank-`N` item contributes to a hero's stat | Body in `TASKS-DONE.md`; the ruling itself is `SYSTEMS.md` § Primary stat magnitude. Three new `BalanceTable` fields — `equip_pct_per_rank` (`0.04 × rank_mult`, eight non-crit slots, two per stat summing into one `equip_pct`), `equip_crit_pct_per_rank` (`0.015 × rank_mult`, necklace/ring, via `equip_flat`), `equip_crit_rate_cap = 0.75`. Not a reuse of `stat_multipliers`: same ratios, own scalar, so a hero-curve retune can't silently reprice every item. Unblocked `P2-05c`. |
| P2-05c | Equipped gear changes combat power | Body in `TASKS-DONE.md`. **No signature change was needed** — this row predicted "the seam is an extra argument"; `compute_final_stats` already takes the `Hero`, and `equipped` has been on it since `P2-05a`, so gear applies in one function and `combat/` was never touched. `compute_team_power`'s crit-blindness is now pinned by an assertion (a ring moves `CRIT_DMG` and not team power), so the eventual fix has to delete it deliberately. Gear routing is indexed by `PrimaryStat` ordinal with `Hero.STAT_NAMES` mirroring it positionally — reordering either enum misroutes gear with a green gate, and only `tests/unit/test_equipment.gd` notices. |
| P2-04e | Lost-gear cache created on hero permadeath | Body in `TASKS-DONE.md`. `turn_lost` deliberately absent from `LostCache` — no turn counter exists to stamp it with, so `P2-04f` adds both. `kill_hero()` gained a `zone_id`; its **second caller is dynamic** (`tests/save_roundtrip_check.gd` via `.call()`), which grep for `kill_hero(` misses and the import gate cannot catch — read its Findings before changing any autoload signature. Also reopened once: the round-trip test shipped as in-memory `to_dict`/`from_dict`, the exact gap `P2-05a` warned about, and the disk leg had to be added to `save_roundtrip_check.gd`. Unblocks `P2-04f`. |
| P2-04f | Recovery expedition — damage roll + cache decay | **Unblocked.** Both design gaps are closed: `power_deficit_penalty` is `clamp(0.2 * (r - 1), 0.0, 0.2)` (`SYSTEMS.md` § Death and gear recovery, and it had been valued for some time while three rows here still called it a gap), and a turn is one resolved expedition (`P2-22`). Scope shrank — `P2-23` takes the counter and `turn_lost`, leaving the mission type, the damage roll and the expiry sweep. Needs a `tech-lead` pass: a distinct mission type is a new hub flow, and no UI lists `lost_caches` at all today. Inherits **two** rulings `P2-07a`/`P2-22` raised and did not own, both about the same `clampf`: at Reliquary 5 the `−3%`/level reduction cancels `damage_chance`'s `0.15` base exactly, so a same-turn recovery has **zero** damage chance and Damaged gear is unreachable at the bottom of the window — while at Reliquary 4–5 the extended window outruns the clamp at the top, making the last 3 and 7 turns certain-damage with a perfect team. This ticket rules both rather than discovering them. |
| P2-06a | Sacrifice a hero for essence; spend essence to rank another up, dupe resonance counted | Body in `TASKS-DONE.md`. Shipped the flat `essence_base[fodder.rank]` yield with no level term. First ticket to follow `DECISIONS.md` 2026-08-06 instead of the `P2-12` debt shape — the arithmetic is two pure `static func`s on `Hero` and `tests/unit/test_sacrifice.gd` reaches both without booting an autoload. **Read its Findings before wiring another `OptionButton` to a destructive action:** `add_item()` auto-selects index 0 on a cleared button, so the fodder slot silently retargeted the next hero after a sacrifice and a blind second press killed the wrong one — permanently. Both gates stayed green through it; only driving the real scene caught it. Sharpens `P2-05g`'s `selected`-is-never-`-1` note into a data-loss rule. |
| P2-06b | Resonance trait payoff — unlock a trait at 1/3/6 dupes | **Landed `26103f7`.** No body — this was a backlog row, and `SYSTEMS.md` § Traits was the spec. Shipped as eight lines in `Hero.compute_final_stats` and four tests: no new field, no signature change, no save key, no `.tres` touched. Left one gap nothing owns — **no hub UI shows resonance, traits or hero stats**, so the payoff is only observable through expedition outcomes; see above. Original spec, for reference — the data, the pools and `Hero.active_resonance_traits()` all exist; this ticket is the one call site that consumes them, extending `compute_final_stats`'s existing `equip_pct` accumulator (non-crit) and flat crit add (ahead of the `equip_crit_rate_cap` clamp). It touches no save key. Was a design gap — `SYSTEMS.md` named a "definition trait pool" that existed nowhere in the codebase. `SYSTEMS.md` § Traits is now the ruling: `TraitDefinition` Resource, two pools on `HeroDefinition`, 15 authored traits, and the `resonance_trait_thresholds` shape. Depends on `P2-06c` shipping the data first — this ticket is the *payoff* (traits applying in `compute_final_stats`), not the type. Resonance traits need **no new `Hero` field**: they derive from the already-saved `resonance` int, so this half is not a save-boundary change. |
| P2-06c | Trait data exists — `TraitDefinition`, the two pools, the 15 authored traits | **Landed `f4eea87`.** No body — this was a backlog row, and `SYSTEMS.md` § Traits was the spec. Shipped **without `Hero.taught_traits`** (deferred to `P2-13`; see above and `SYSTEMS.md` § Traits §4), so no save key changed, no `verifier` pass was needed, and no ADR was written. Read its finding above before hand-authoring another `.tres` — typed arrays of a custom script class had no precedent here, and Godot omits default-valued fields so the five authored files are legitimately not uniform. Original spec, for reference — authored by `game-designer` in `SYSTEMS.md` § Traits, which settles every open input: the Resource type and why it isn't a `BalanceTable` effect table, `resonance_trait_pool` (exactly 3, ordered, unlock index = array index) and `instructor_trait_pool` (empty, reserved for `P2-13`), `resonance_trait_thresholds` on `BalanceTable`, and the two effect channels (percentage into `equip_pct` for HP/ATK/DEF/SPD, flat into `equip_flat` for the crit stats, ahead of the existing `equip_crit_rate_cap` clamp). `stat` reuses `EquipmentDefinition.PrimaryStat` rather than a second enum — **`P2-05c`'s warning applies: that ordinal positionally mirrors `Hero.STAT_NAMES`, so reordering either enum misroutes traits with a green gate.** Ships the data and the pure `static func`; `P2-06b` is what makes it visible. `godot-architect` should rule first on whether a new Resource class plus exported fields on two existing definition Resources needs an ADR. Adding `Hero.taught_traits` is a **save-boundary change** (`CLAUDE.md` risky boundary 1) and requires a `verifier` pass with a real save/reload cycle — a green import gate is not evidence. If it ships without `taught_traits` (reserved, unpopulated until `P2-13`), say so explicitly rather than leaving the field half-wired. |
| P2-12 | Extract `salvage_item`/`enhance_item`/`convert_parts`'s arithmetic into pure functions | **Landed** in the commit below; body in [`TASKS-DONE.md`](TASKS-DONE.md). Director-written per rung 1, Codex-implemented, no `verifier` — no save key, no signature and no scene seam moved, so it crosses none of `CLAUDE.md`'s four boundaries. Shipped **two** static funcs, not three: `Item.compute_salvage_yield` and `Item.compute_enhance_cap`, with `clamped_enhance_level` public alongside them. `convert_parts` was named by this row and deliberately **not** extracted — `-3`/`+1` is not a formula — and `upgrade_building`'s `10 * (level + 2)`, which shipped after the row was written, is left with it; both are in the body's Non-goals so the next reader sees a decision, not an oversight. The clamps moved *into* the pure funcs rather than staying at the mutation sites, which retires `P2-07e`'s preview-disagrees-with-payout hazard by construction. **Read its Findings before writing another clamp test** (`mini()` saturates, so the obvious assertion passes with the clamp deleted) and before extracting arithmetic anywhere else (the caller still needs the intermediate, so the intermediate is public API — the `Item._int_field` → `Item.int_field` correction, a third time). Original row, for reference — Debt named by `DECISIONS.md` 2026-08-06, which reaffirmed the 2026-08-01 rejection of balance logic on `GameSession` rather than reversing it: the rejection's predicted cost came true — no `GameSession.new()` exists anywhere, so every test of these formulas boots the engine. Each method keeps its signature and becomes validate → call a `static func` → mutate → emit. Not urgent (all three are shipped, tested and round-tripping); it exists so the next ticket reads them as debt rather than precedent. |
| P2-14 | Hero detail readout — final stats, resonance, active traits | Body in `TASKS-DONE.md`. Closes the gap `P2-06b` flagged and nothing owned: gear, resonance and traits were observable only through test output. `Hero.level_for()` now single-sources the rank→level derivation `combat/quick_resolve.gd` owned inline. Widened its own file list to `tests/unit/test_expedition.gd` — criteria 2/3/5 are scene behavior and that file already owns every hub-scene drive. **Read its Findings before writing another scene test:** `ItemList.select()` does not emit `multi_selected`, so emitting the signal is what exercises the `.tscn` `[connection]` block. Also read them before believing a red gate relayed from a Codex worker — the documented GUT command cannot run inside a `workspace-write` sandbox at all (`KNOWN_ISSUES.md` § Environment). |
| P2-07a | Building ruling — upgrade cost in parts, and the level caps | No body — this was a design gap inside `P2-07`, and the ruling itself is `SYSTEMS.md` § Base buildings. `10*(n+2)` parts of rank index `n`, cap 5 for all five, and **three buildings ship, not five**. Also corrected a stale § Summoning Circle note claiming the Circle still needs a `BalanceTable` schema change — both fields already exist (`balance_table.gd:18,21`) and `summoning_circle_weight_shift` appears nowhere. Unblocked `P2-07`. |
| P2-07 | ~~Circle, Forge and Sanctum are levelable, and their bonuses apply~~ **SPLIT** | `tech-lead` pass done — split into `P2-07b`/`c`/`d`/`e`, rationale above. Scoped to **three** buildings by `P2-07a`; Training Hall and Reliquary trail `P2-04a`/`P2-04f`. The four authored-but-unread magnitudes (`balance_table.gd:18,21-24,26`) are wired by `c`/`d`/`e`, not `b`. |
| P2-07b | Building levels exist, persist, and are spendable — Circle/Forge/Sanctum upgrade panel | **Landed `4f97261`.** Body in `TASKS-DONE.md`. The foundation `c`/`d`/`e` all read. The mandatory `verifier` pass returned **pass** on all 11 criteria. Criterion 8 (real-disk round-trip, not in-memory `to_dict`/`from_dict`) passed first time, unlike `P2-05a` and `P2-04e` which both shipped that shortcut and were reopened — **read its Findings for why: the failure history was written into the criterion itself** rather than left in an archive, so the trap was in front of the implementer at the point of decision. Also records a `%APPDATA%` collision that makes parallel gate runs unsafe, which belongs in `KNOWN_ISSUES.md` § Environment and is `godot-tester`'s to file. |
| P2-07c | Wire the Summoning Circle's multiplier into `Summon.roll()` | Trickiest of the three wirings. `Summon.roll()` is a `static func` on a plain `RefCounted` with no autoload access, so `hub.gd` reads the level off `GameSession.building_levels` and passes it in. **The renormalized weight table must be a local copy** — scaling `BALANCE.summon_weights` in place persists to the `.tres` on disk for every consumer, the hazard `ARCHITECTURE.md` § "Reaching shared Resources" names by example. **Landed** in the merge below; `BALANCE.summon_weights` is `duplicate()`d before any scaling and a GUT canary asserts the authored `[4000, 2700, 1700, 1000, 450, 120, 28, 2]` intact *after* rolling at level 5. Three things outlive it. **`roll()` took a default — `roll(circle_level: int = 0)`** — to preserve `tests/summon_def_id_roundtrip_check.gd`, an out-of-scope caller passing zero args; the cost is that any future caller which forgets the argument silently summons with no Circle bonus and every gate stays green, so grep callers rather than trusting arity. The renormalization target is `_total_weight()` of the array passed in, **not a literal `10000`** — `SYSTEMS.md`'s "sum to 10000" states the proportion rule, and its own worked table carries fractional weights (`2.28`, `2.82`) that cannot be `Array[int]` entries; the post-`roundi()` total is recomputed rather than assumed, which is what keeps `rank_for_ticket`'s ticket range consistent with the array it indexes. The A+ block boundary ships as a bare `rank < 4` literal. |
| P2-07d | Wire Forge's enhance cap + salvage yield into `enhance_item`/`salvage_item` | **Landed** in the commit below; body in `TASKS-DONE.md`. Closes the `P2-07` group. Two caps now sit eight lines apart in `game_session.gd` and **both are correct** — `enhance_item` gates on the forge-scaled `mini(15, forge_level * 3)`, `salvage_item` keeps clamping against flat `forge_enhance_cap_max`, because one gates *gaining* a level and the other bounds *trusting* a level an item already has; tidying them into one constant confiscates enhancement a player paid for, and criterion 3's test catches it. The wiring also gates enhancement behind Forge level 1 for a fresh save — ruled, not a regression (`SYSTEMS.md:807-811`) — which needed a refusal message that names the missing building instead of reading "already at the +0 cap". Read its Findings before writing another hub-scene test: the Salvage/Enhance buttons have no `%UniqueName`, so the test reaches them by absolute node path and a re-parent reddens it with a null node. Original row, for reference — `P2-07b` landed and the scaling law is ruled (`SYSTEMS.md` § Base buildings): `10% * forge_level`, `0%` unbuilt to `+50%` at cap, as `roundi((3 + enhance_level) * (1.0 + 0.10 * forge_level))`. The flat reading was rejected because truncation makes it yield **zero** for `enhance_level` 0–6 — the commonest salvage case. **The rounding function is part of the ruling, not an implementation detail:** `roundi()`, never `int()`, or the dead bonus reappears at Forge levels 1–3. Needs a `tech-lead` pass or a director-written body; it wires *two* consumers (`enhance_item`'s cap and `salvage_item`'s yield), which is more than `c` or `e` each do. |
| P2-07e | Wire Sanctum's essence-yield bonus into `sacrifice_hero`/`compute_essence_yield` | **Landed** in the merge below, and the row's "no signature change" held only for `sacrifice_hero`, as predicted: `Hero.compute_essence_yield` gained a required `sanctum_level: int` and stayed a pure `static func`, so `tests/unit/test_sacrifice.gd` still exercises the arithmetic without booting `GameSession`. **Contrast it with `P2-07c` deliberately:** `roll()` took a *defaulted* level and `compute_essence_yield` took a *required* one. The required form is the safer default — it makes every call site declare its level, so a forgotten argument is a compile error instead of a silently unbonused result. Prefer it for `P2-07d`. `hub.gd`'s pre-sacrifice preview computes the identically-clamped level, so preview equals payout; a scene-driven test pins that at a `building_levels[3] = 999` corrupt value clamping to 5. Rounding is `roundi()`, matching `SYSTEMS.md`'s Forge ruling — `195 × 1.10 = 214.5 → 215`. |
| P2-08 | Full save/load round-trip through `SaveService` | **Landed** in the commit below; body in `TASKS-DONE.md`. Director-written body per rung 1 — the row had no body and no design input was needed, only an audit of which persisted keys had disk coverage. Six of the eight did; `inventory` and `cleared_zone_ids` were in-memory-only, the `P2-05a`/`P2-04e` shortcut again. **No production code changed** — both keys round-trip correctly, so the ticket bought coverage, not a fix. Read its Findings before adding a check to `tests/save_roundtrip_check.gd`: the checks share one `GameSession` in a fixed `_run()` order, so one that leaves an item in `inventory` reddens a later check by name-unrelated means. Opened `P2-17`. |
| P2-17 | A refused save is moved aside, not overwritten | **Landed** in the commit below; body in [`TASKS-DONE.md`](TASKS-DONE.md). `game-designer` ruled the three refusal branches **apart** rather than uniformly (`SYSTEMS.md` § Refused-save recovery): corrupt moves aside to `save.corrupt.json`, newer-version refuses to boot, missing file is untouched. What decided it is that the two failing branches are not the same situation — corrupt bytes have no in-app recovery path, so the cheapest fix that stops the clobber is right; a newer-version file is *undamaged data* recoverable by running the build that wrote it, so discarding it would be the very loss the check exists to prevent. Rejected read-only mode (no resolution path — collapses into move-aside with a flag watched forever) and refuse-to-boot for the corrupt branch (a permanent wall, against `P2-18`'s precedent that a player must be able to act their way out). The ruling also **added a cost the row had not priced**: a silent rename is indistinguishable from data loss, so one line of on-screen text is part of the fix, not polish. Opened `P2-20`. Original row, for reference — found by `P2-08`, which pinned that `load_game()`'s three refusal branches leave `GameSession` untouched and cannot pin what happens after. Not urgent — `SAVE_VERSION` has never been bumped, so the newer-version branch is unreachable in shipped builds today; the corrupt-file branch is not. |
| P2-20 | `SaveService.save()` writes atomically — temp file, then rename | **Landed** in the commit below; body in [`TASKS-DONE.md`](TASKS-DONE.md). Director-written per rung 1; the mandatory `verifier` pass returned **fail** first time and was right. **Read its Findings before adding another staged write anywhere:** staging only protects the window between truncate and write, so the first implementation — which discarded `store_string()`'s `bool` return — simply relocated the same data loss from open-time to write-time, where no test looked. Check open, write **and** rename. Second lesson is the inverse of the first: staging makes an open read handle on the target *fatal* on Windows, and this repo held **eight** unclosed ones (`load_game()` across `from_dict()`, plus seven in `tests/save_roundtrip_check.gd`, a file the allowed-list omitted — the third consecutive ticket to omit a real call site after `P2-04g` and `P2-18`). Third: the ticket's own premise was overstated and the `verifier` corrected it — "the first save after every boot is lost" is **false**, because `GameSession._ready()` connects `roster_changed` *after* `load_game()` returns; the fix is defensive, not a shipped-build bug, and a GUT backtrace is not a call graph. Godot's `rename` is also **not** atomic on Windows (remove-then-move), recorded as residue rather than chased — recovering from that window would mean loading a temp file, which is the one thing a staged write must never do. Original row, for reference — `save()` stores directly into `user://save.json` with no staging, so a crash mid-`store_string` truncates the only save; that is *why* `P2-17`'s corrupt branch is reachable. Needs no design ruling — write-to-temp-then-rename is not a game decision. |
| P2-10 | ~~Gold — what it is and how a player gets it~~ **CLOSED — will not do** | Superseded by `SYSTEMS.md` § Enhancement's gold-removal ruling (2026-08-06), which struck gold from the document entirely rather than deferring it. This row asked for an income rate; the ruling's **Rejected: give gold an income rate and keep it as a third currency** answers it directly — Summon Stones (pulling) and parts (upgrading) already cover the two earned-currency tracks, and every cost line downstream of `P2-05e` settled on parts-only, so nothing was left to spend it on. Do not re-open without a system that needs a third currency. Left the residue as `P2-15`. |
| P2-15 | Sync three zones' `loot_emphasis` strings to the gold-removal ruling | **Landed** in the commit below. Six literals, not the four the row predicted — three `.tres` `loot_emphasis` fields **and** three expected-string literals in `tests/zone_definition_check.gd`, which asserts them by exact match, so the `.tres` edits alone would have reddened the gate. Director-written per rung 1; no delegation, no design input, no boundary crossed. `SYSTEMS.md` § Enhancement's follow-up note is closed out to match. Gold now appears nowhere in `*.gd`/`*.tres`/`*.tscn`. |
| P2-09 | Summon Stone income rate — how a player actually acquires stones | **Landed** in the commit below. No body — this was a backlog row, and the ruling itself is `SYSTEMS.md` § Summon Stones — cost and income. `100` stones/pull flat, `25`/`75`/`200` per `COMPLETED` clear (Verdant/Ashfall/Sundered, reducing to `1:3:8`), `300` on a fresh save. Took the **pull cost** as well as the income rate, which the row's title did not name: an income rate with no price is not checkable, and the gold-removal ruling's surviving "two earned-currency tracks" claim is only true once a pull spends a stone. Opened `P2-16`. |
| P2-16 | Pulls cost Summon Stones, and a clear pays them | **Landed** in the commit below; body in `TASKS-DONE.md`. Ticket written by the director per rung 1 rather than routed to `tech-lead` as this row predicted — `SYSTEMS.md` § Summon Stones §5 had already settled every number, named every file, and specified the check-and-deduct guard shape, so no scoping judgment was left to route. The mandatory `verifier` pass returned **pass** on all 8 criteria. **Read its Findings before adding another currency:** the priced path is `summon_hero()`, but `add_hero()` survives with zero production callers and 17 test ones — an unpriced door into `roster` that no gate guards, the `P2-07c` `roll()`-default hazard in a new shape. Also records why a `300` default that is *also* a legitimate value (`0` stones, spent out) needs all three untrusted shapes checked separately rather than "a round trip", and why `300` arrived as three literals before consolidating to `GameSession.STARTING_STONES`. Original row, for reference — it is a **save-key change** (a new `GameSession` stone field, `CLAUDE.md` boundary 1, mandatory `verifier`) *plus* a new `BalanceTable` field, a new `ZoneDefinition` field across three `.tres`, a check-and-deduct guard on the summon path, and a hub scene-seam change (the button must read the balance and disable itself below cost). `SYSTEMS.md` § Summon Stones § 5 states where each number lives. Two traps already on the record apply: the fresh-save default is `300` and **not** "starts at 0" — an empty roster plus a priced pull means a zero balance is unplayable from boot, not merely slow — and `zones/defs/*.tres` edits redden `tests/zone_definition_check.gd`, which asserts zone fields by exact match (`P2-15`). |
| P2-22 | Turn concept ruling — what advances the decay clock | **Landed** in the commit below. No body — this was a design gap inside `P2-04f`, and the ruling itself is `SYSTEMS.md` § Turns. **A turn is one resolved expedition**; `INVALID_TEAM` does not tick, a recovery run does, the deadline is evaluated at the attempt rather than frozen at death, and `GameSession.turns` is the counter. Director-written per rung 1: it authored **no new number** — all four turn-denominated numbers were already on the page — so what it owed was an arithmetic check that the clock is *missable*, which is the whole reason `reliquary_decay_turns_bonus` isn't the fifth "reads real, measures nothing" entry. Rejected wall-clock time (OS-settable, runs while closed, no idle income to justify it), hub actions (ages a cache for sorting your bag) and play sessions (nothing counts them, and never-quit is a free exploit). Also found `power_deficit_penalty` had **already been valued** while three rows here called it a gap. Opened `P2-23`; unblocked `P2-04f`. |
| P2-23 | Turns exist, persist, and a lost cache records the one it died on | **Landed** in the commit below; body in [`TASKS-DONE.md`](TASKS-DONE.md). Director-written and director-implemented per rung 1 (the account was at 2% Codex usage), with the mandatory `verifier` pass returning **pass-with-concerns** on all 8 criteria. `GameSession.turns` ticks once per resolved expedition **before** the wave loop, so a same-expedition death stamps `turn_lost` with the turn the run became and an immediate recovery reads `turns_elapsed == 0` rather than `-1`. `kill_hero()` took **no new argument** — `turns` is the autoload's own state, the distinction `P2-05f` drew. **Read its Findings before writing a test that drives an error branch** (GUT fails on an unconsumed `push_error`, and names the error instead of the assertion) and before appending a field to `LostCache.from_dict` (it returns early on a malformed `items` array, so `turn_lost` decodes above it). Its one `verifier` finding was the **fifth consecutive wrong allowed-file list**, and the first to err by naming a file that did not change rather than omitting one that did — write the list after the grep. Original row, for reference — Opened by `P2-22`, split out of `P2-04f` because it is a **two-key save-boundary change** (`GameSession.turns` and `LostCache.turn_lost`, `CLAUDE.md` boundary 1 — mandatory `verifier`, real disk cycle, not an in-memory `to_dict`/`from_dict` pair) and has nothing to do with the recovery mission it enables. Scope: the field, the tick on the three real outcomes, the stamp inside `kill_hero()`, and a hub readout so the number is observable — `P2-07b`'s reasoning, not `P2-04c`'s, since a clock nobody can see is not checkable by playing. **`turn_lost` is the field `P2-04e` refused to ship** for want of a counter, so this is the ticket that retires that precedent rather than repeating it. Two traps already on the record apply: `kill_hero()`'s **second caller is dynamic** (`tests/save_roundtrip_check.gd` via `.call()`, `P2-04e`), and the last four tickets' allowed-file lists each omitted a real call site (`P2-04g`, `P2-18`, `P2-20`). No recovery mission, no damage roll, no expiry sweep, no Reliquary — all `P2-04f`. |
| P2-13 | **[BLOCKED]** Fodder training — an instructor hero trains F–C fodder; survivors of background "culling" expeditions gain XP and rank up naturally | **All four missing systems have now landed or are ruled**, so the block is down to one thing: the `game-designer` ruling on the five questions below. `P2-04a`/`P2-04g` gave heroes a real `level` and `xp`; `P2-06c` shipped `instructor_trait_pool` (reserved and empty as intended, and this ticket still inherits `Hero.taught_traits`, which `P2-06c` deliberately deferred — `SYSTEMS.md` § Traits §4 specifies it in full); `P2-21` made the Training Hall buildable so `training_hall_xp_bonus` reads against something; and `P2-22` ruled the turn concept, with `P2-23` shipping the counter. **Do not read that as "nearly unblocked."** The dependency list was never the hard part — question 1 below is a conflict with the sacrifice spine's published `~327`-pull arithmetic, and it is now *more* pressing rather than less, since every system it would compete with is live. Four missing systems in one ticket was the "add an inventory system" shape this file exists to prevent; five unruled design questions is the same shape wearing a different coat. |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3.

`P2-09` moved that question as far as a desk can move it: the `~327`-pull spine now divides by a
unit the game can count, landing at `~1,308`/`~436`/`~164` clears depending on which zone is farmed.
What it cannot do is turn clears into sessions or hours — **nothing in this codebase counts a play
session**. `P2-22` did not close that: a turn is an expedition, which is a unit of *play* and not a
unit of *time*, so `~1,308` clears still converts to hours only by someone sitting down and
clicking. `P2-16` has since wired the price in, so the honest remaining dependency is no longer a
ticket at all — it is someone playing it.

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
| `P2-07b` | Building levels exist, persist, and are spendable | `4f97261` |
| `P2-07c` | Summoning Circle level shifts summon weights toward A+ | `51d2ce6` |
| `P2-07e` | Sanctum level raises sacrifice essence yield | `f93f547` |
| `P2-07d` | Forge level raises the enhance cap and the salvage yield | `453eb86` |
| `P2-15` | Drop the struck gold currency from three zones' reward prose | `342f498` |
| `P2-09` | Summon Stone ruling — what a pull costs, and what a clear pays | `b5f42a4` |
| `P2-16` | Pulls cost Summon Stones, and a clear pays them | `4937ded` |
| `P2-08` | Full save/load round-trip through `SaveService` | `e4e08c2` |
| `P2-04a` | XP-per-level curve ruling — heroes level for real | `6e00e6f` |
| `P2-04g` | A hero levels up from expeditions | `dc6e090` |
| `P2-18` | A wiped roster always affords one more pull | `afa4cb7` |
| `P2-19` | Sacrifice's `fodder.level` term — wired, not struck | `4922d2e` |
| `P2-17` | A refused save is moved aside, not overwritten | `786acf5` |
| `P2-20` | A crashed save leaves the previous save intact | `8c526b7` |
| `P2-21` | The Training Hall is buildable, so its XP bonus can fire | `332466a` |
| `P2-12` | Salvage and enhance arithmetic moves off the autoload | `18fe317` |
| `P2-22` | Turn concept ruling — a turn is one resolved expedition | `44e112a` |
| `P2-23` | Turns exist, and a lost cache records the one it died on | |

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
