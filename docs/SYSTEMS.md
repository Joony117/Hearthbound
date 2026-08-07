# Systems Reference

The target design. **This is a reference, not a build order.** Each section is tagged with
the phase that implements it — do not build a Phase 4 system during Phase 2 because it was
written down here.

Every number below ends up in `balance.tres`, editable in the inspector without touching
code. The values here are starting points to be tuned against play, not commitments.

---

## Ranks — *Phase 2*

`F D C B A S SS SSS` → int `0..7`. Applies to heroes and equipment alike.

| Rank | F | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|---|
| Stat multiplier | 1.00 | 1.35 | 1.82 | 2.46 | 3.32 | 4.48 | 6.05 | 8.17 |
| Level cap | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 |
| Equipment affixes | 1 | 1 | 2 | 2 | 3 | 3 | 4 | 4 |
| Core sockets | 0 | 0 | 0 | 0 | 1 | 1 | 2 | 2 |

Geometric ×1.35 per rank. An SSS is ~8× an F before levels and gear. Verified: `1.35^0..7`
rounds cleanly to every printed value with no drift (`8.1722 → 8.17`).

**`rank_mult` and per-level `growth` apply to `HP`, `ATK`, `DEF`, `SPD` only.** `CRIT_RATE` and
`CRIT_DMG` are archetype constants (see Heroes) moved only by equipment, never by rank or level.
Applying the generic formula to `CRIT_RATE` uniformly breaks it: a 15% base at SSS (`×8.17`)
comes out to 122.55% — a hard-cap violation before gear is even added, and it's already at
90.75% one rank earlier at SS. This is a correction to the formula as originally written, not a
new rule — catch it before `balance.tres` bakes the generic formula in per-stat.

---

## Heroes — *Phase 2*

**Six stats. This is a ceiling, not a starting point.**

`HP`, `ATK`, `DEF`, `SPD`, `CRIT_RATE`, `CRIT_DMG`

A fifteen-stat sheet is a real risk in this genre and nobody can balance one. If a seventh
stat is proposed, it needs a `DECISIONS.md` entry.

```
final = (base + growth * level) * rank_mult + equip_flat
final *= 1.0 + equip_pct
```

### Archetypes

| Archetype | Row | Role |
|---|---|---|
| Knight | Front | Mitigate, hold aggro |
| Rogue | Front | Single-target burst |
| Ranger | Back | Sustained single-target |
| Mage | Back | AoE |
| Cleric | Back | Heal |

**Formation is 3 front / 2 back.** In quick resolve, front row takes a heavier share of
incoming damage. In the arena, it is literal spawn position. Same data, two readings.

Note the asymmetry: only **two** archetypes are Front (Knight, Rogue) but the formation needs
**three** front bodies. A "one of each" five-hero roster physically cannot fill the formation —
it fields 2 front / 3 back against a 3/2 shape. Fielding a legal team means either running a
second Knight or Rogue up front, or leaving the third front slot empty and eating the damage
share penalty. This is deliberate, not an oversight: it forces a real composition choice (and a
duplicate front-liner is never dead weight either, courtesy of dupe resonance) instead of
"collect one of everything." Don't fix it by adding a sixth archetype or rebalancing the row
split — the tension is the point.

### Base stats

`base / growth` per stat, applied through the `Ranks` formula. `CRIT_RATE` / `CRIT_DMG` are
flat — no growth, no `rank_mult` (see Ranks). `CRIT_DMG` is a damage multiplier on crit hits
(`1.50` = crit hits for 150% damage).

| Archetype | HP | ATK | DEF | SPD | CRIT_RATE | CRIT_DMG |
|---|---|---|---|---|---|---|
| Knight | 140 / 14 | 18 / 1.8 | 24 / 2.4 | 90 / 1.0 | 5% | 1.50 |
| Rogue | 95 / 8 | 32 / 3.2 | 12 / 1.0 | 110 / 1.6 | 15% | 1.80 |
| Ranger | 100 / 9 | 26 / 2.6 | 14 / 1.2 | 100 / 1.4 | 10% | 1.60 |
| Mage | 80 / 6 | 34 / 3.4 | 10 / 0.8 | 95 / 1.2 | 8% | 1.65 |
| Cleric | 110 / 10 | 16 / 1.4 | 16 / 1.4 | 95 / 1.1 | 5% | 1.50 |

Knight and Cleric anchor the HP/DEF end; Rogue and Mage anchor the ATK/SPD glass-cannon end;
Ranger sits in between. Rogue carries both the highest ATK-adjacent kit *and* the highest crit
line — it is the highest-`hero_power` archetype at every checkpoint, which is intentional for a
front-line burst unit, but means Rogue is the one to watch for "obviously best" creep once gear
is layered on.

Verified `hero_power` (`ATK + DEF + HP/10 + SPD`, no equipment) at three rank/level checkpoints:

| Archetype | F, lvl 10 | B, lvl 40 | S, lvl 60 |
|---|---|---|---|
| Knight | 212.0 | 1,008.6 | 2,428.2 |
| Rogue | 229.5 | 1,051.7 | 2,506.6 |
| Ranger | 211.0 | 969.2 | 2,311.7 |
| Mage | 207.0 | 952.0 | 2,271.4 |
| Cleric | 187.0 | 821.6 | 1,935.4 |
| **5-hero avg × 5** | **1,046.5** | **4,803.2** | **11,453.1** |

The bottom row is a same-rank, same-level, ungeared reference team — the baseline that
Expeditions' recommended power is pinned against.

> ⚠️ **PROVISIONAL** — the five archetype stat lines and the `hero_power` checkpoints above are
> internally consistent but never played. Rogue reads as the highest-`hero_power` archetype at
> every checkpoint by design; whether that plays as "intentional burst carry" or "obviously best,
> take five" once gear is layered on is a feel question arithmetic can't answer. · **Settled by:**
> a played build with real teams and real gear, since gear is exactly where this kind of gap
> would show up.

---

## Sacrifice → rank up — *Phase 2*

```
yield = essence_base[fodder.rank] * (1.0 + fodder.level / level_cap[fodder.rank])
if fodder.def_id == target.def_id:
    yield *= 3
    target.resonance += 1
```

| Sacrificed rank | F | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|---|
| Essence base | 10 | 25 | 65 | 165 | 420 | 1050 | 2600 | 6500 |

| Rank up | F→D | D→C | C→B | B→A | A→S | S→SS | SS→SSS |
|---|---|---|---|---|---|---|---|
| Essence cost | 40 | 110 | 300 | 800 | 2200 | 6000 | 16000 |

F→D costs four fresh F heroes exactly (`4 × 10 = 40`, no remainder). SS→SSS does **not** land
on six — six fresh SS yields `6 × 2,600 = 15,600`, short of the `16,000` cost; it takes **seven**
(`18,200`, an excess of `2,200`). Corrected from an earlier draft that hadn't been checked.
Brutally expensive at the top **by design** — that is the long-term goal of the whole game. The
"N fresh heroes of the rank just below" count isn't flat across the table, it climbs gently:
`4, 5, 5, 5, 6, 6, 7` for F→D through SS→SSS.

**The spine number, computed end to end.** Feeding *every* pulled hero you don't keep into one
target (any rank, level 0, no dupe bonus) costs on average `78.38` essence per pull
(`Σ weight_i/10000 × essence_base_i`), against a `25,450`-essence F→SSS chain — **~327 summon
pulls** total, including the ~2.5 pulls to land the F keeper. That's **~15× cheaper** than the
`~5,000` pulls expected for a lucky direct SSS pull (below), which numerically backs the
"manufacture, don't pray" claim in `GAME_SPEC.md`.

The catch: this only holds if a player feeds the *natural spread* of pulled ranks. A player who
only ever scraps F-rank junk and treats everything else as "too good to feed" needs **~6,363**
pulls of F-fodder alone — *worse* than gambling for SSS directly. The tutorial/UI needs to teach
"feed what you don't keep, any rank," not "grind F trash," or the intended economy inverts for
exactly the players following the naive strategy. An optimistic bound — Sanctum +10%, all fodder
happens to be max-level — comes down to **~150 pulls**; that excludes the cost of leveling
fodder before feeding it, so treat it as a ceiling, not a target.

> ⚠️ **RESOLVED, in part, by `P2-09`'s ruling (Summoning → Summon Stones — cost and income,
> below).** The `~327`-pull spine number now maps to a real, countable unit: at `100` stones/pull
> and the ruled per-zone income, it's `~1,308` clears farming Verdant alone, `~436` Ashfall alone,
> or `~164` Sundered alone. That was the actual gap — "327 pulls" is no longer stranded with
> nothing to divide it by.
>
> ⚠️ **PROVISIONAL, narrower than before** — the arithmetic above is checked against every
> existing spine number in this document (Codex thread `019fdae0-d06f-7e82-b408-93d55716a5f1`),
> but "clears" still isn't "sessions" or "hours": nothing in this codebase counts a play session,
> so the clears-to-spine figures can't be honestly converted further without a fact this ruling
> doesn't have — how many clears a player completes per sitting. · **Settled by:** a played build
> with `P2-09`'s pricing wired in, to see how many clears (and therefore how many pulls) a real
> session actually yields.

A max-level sacrifice yields double, so levelling fodder before feeding it is a real (if
slow) strategy.

**Rank-up preserves the hero's level and raises the cap.** Resetting level would make
ranking up feel like a punishment. See `DECISIONS.md`.

### Dupes and resonance

Feeding a hero into another instance of the *same* `def_id` grants ×3 essence **and** a
resonance point. Resonance unlocks traits from that hero's definition's **resonance trait
pool** at **1, 3, and 6** — see § Traits, below, for the pool, the numbers, and the type.

This is why a duplicate is never dead weight, and it gives chasing a specific unit a payoff
ladder beyond raw stats.

> ⚠️ **PROVISIONAL** — resonance unlocking at 1, 3, and 6 dupes is an untested curve; nobody has
> checked it against how often a player actually accumulates duplicates of one `def_id` at the
> weights in Summoning, so "6 dupes" could be a routine milestone or a near-unreachable one
> depending on rank. · **Settled by:** a played build, or a dupe-rate calculation cross-referenced
> against the Summoning weight table (not yet done).

### Traits

`P2-06b` was blocked on this: the paragraph above named a "definition trait pool" that did not
exist anywhere in the codebase. This section is the ruling that unblocks it — the type, the
per-archetype pools, the resonance/instructor partition, and the `Hero` storage.

**1. Trait type — a `Resource`, not a `BalanceTable` effect table.**

```
class_name TraitDefinition extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var stat: EquipmentDefinition.PrimaryStat = EquipmentDefinition.PrimaryStat.HP
@export var magnitude: float = 0.0
```

`stat` reuses `EquipmentDefinition.PrimaryStat` rather than inventing a second enum —
`Hero.compute_final_stats` already treats that enum's ordinal as positionally mirroring
`Hero.STAT_NAMES` (`heroes/hero.gd:73`), so a trait and an equipped item route to a stat through
the exact same index, no new mapping to keep in sync.

**Reason: per-archetype content belongs on the per-archetype Resource, not on the shared curve
table.** `HeroDefinition` already carries per-archetype tunables directly as exported fields
(`base_hp`, `hp_growth`, `crit_rate`, `crit_dmg` — none of them live on `BalanceTable`) — a trait
pool is the same kind of content, authored per archetype, so it belongs beside them. A `StringName`
id plus an effect table on `BalanceTable` would need `BalanceTable` to start carrying per-archetype
content, which breaks its established shape (shared, rank-indexed curves only —
`equip_pct_per_rank`, `stat_multipliers`, and the like) and still needs something to say which
archetype each id belongs to, which is exactly what `HeroDefinition` already is for. This also
costs no fourth autoload: a trait pool is reached exactly the way `HeroDefinition` itself already
is — `Hero.definition_for()` (`heroes/hero.gd:33-41`) — and the compute function that reads it can
stay a pure `static func` taking `definition: HeroDefinition` as an argument, the same shape
`compute_final_stats` already has and `DECISIONS.md`'s 2026-08-06 entry requires for balance-driven
rule logic.

**2. The pools — two, on `HeroDefinition`, not one tagged pool.**

```
@export var resonance_trait_pool: Array[TraitDefinition] = []   # exactly 3, ordered
@export var instructor_trait_pool: Array[TraitDefinition] = []  # empty until P2-13
```

**Ruling: two separate arrays, not a `source` tag on a single pool.** Three reasons:

- Resonance's own unlock rule is "1st/3rd/6th dupe → 1st/2nd/3rd trait" — an ordered array of
  exactly 3 entries makes that a type-level fact (unlock index *is* array index) instead of
  something every reader has to filter for by tag.
- The two pools are read completely differently. Resonance traits are **derived**, every time,
  from `hero.resonance` (already a saved `int`, `heroes/hero.gd:20`) plus this pool — nothing new
  needs to be written to a save. Instructor-taught traits are **granted directly** with no counter
  behind them, so they must be stored per-hero as an explicit list (§4, below). Two pools mirror
  "one is computed, one is stored" directly; a single tagged pool would blur that distinction at
  every call site that has to remember to filter.
- `P2-13`'s stated requirement is that instructor-taught traits are **obtainable no other way**.
  An empty `instructor_trait_pool` today, read by no resonance code path, is a stronger guarantee
  of that than a shared pool where every future reader has to correctly exclude the tagged-instructor
  entries to preserve exclusivity. This ticket reserves the field; it does not populate it — `P2-13`
  is what authors instructor trait content later, unchanged in shape.

**3. Per-archetype resonance pools — 3 traits each, one per threshold, in unlock order.**

Each trait moves exactly one stat, through the same two channels Primary stat magnitude already
established for equipment: HP/ATK/DEF/SPD traits are a **percentage** bonus, summed into that
stat's existing `equip_pct` accumulator before `compute_final_stats`'s one `final *= 1.0 +
equip_pct[index]` multiply (`heroes/hero.gd:96-97`) — trait and gear contributions to the same stat
add together, then multiply once, same "additive-then-single-multiply" shape Enhancement's own
ruling names as the pipeline's only precedent. CRIT_RATE/CRIT_DMG traits are a **flat**
percentage-point/decimal bonus added the same way `equip_crit_pct_per_rank` already is
(`heroes/hero.gd:90-95`), ahead of the existing `equip_crit_rate_cap` clamp — so the clamp still
catches CRIT_RATE overflow even though the arithmetic below shows no archetype comes close.

| Archetype | T1 (resonance 1) | T2 (resonance 3) | T3 (resonance 6) |
|---|---|---|---|
| Knight | Bulwark — DEF +4% | Stalwart — HP +5% | Iron Wall — DEF +8% |
| Rogue | Opening Strike — CRIT_RATE +1.5pp | Killer Instinct — ATK +5% | Executioner — CRIT_DMG +0.08 |
| Ranger | Quickdraw — SPD +4% | Marksman — ATK +5% | Deadeye — CRIT_RATE +1.5pp |
| Mage | Arcane Focus — ATK +5% | Overload — CRIT_DMG +0.06 | Archmage — ATK +6% |
| Cleric | Devotion — HP +5% | Sanctuary — DEF +4% | Guardian Light — HP +6% |

Traits accumulate: at resonance 6 all three of an archetype's traits are simultaneously active
(T1+T2+T3), not the most-recent one alone — the reward for the 6th dupe is the full stack, not a
replacement of what the 1st and 3rd already gave.

Magnitudes are chosen to read as a meaningful passive, not a stealth equipment slot. Every
archetype's picked so its identity role gets the trait weight (Knight/Cleric lean DEF/HP, Rogue
leans ATK/CRIT, Mage leans ATK/CRIT_DMG, Ranger splits SPD/ATK/CRIT_RATE) — matching the Base
stats section's own archetype framing rather than inventing a new axis per hero.

**Verified (Codex thread `019fd972-7c95-7330-8ad1-658bfede671d`), against the real per-slot and
per-rank tables (§ Primary stat magnitude, § Enhancement):**

- Cumulative full-resonance totals per stat: Knight DEF +12% / HP +5%; Rogue CRIT_RATE +1.5pp /
  ATK +5% / CRIT_DMG +0.08; Ranger SPD +4% / ATK +5% / CRIT_RATE +1.5pp; Mage ATK +11% / CRIT_DMG
  +0.06; Cleric HP +11% / DEF +4%.
- Every non-crit cumulative total is below what **one single A-rank slot** already contributes
  alone (`13.28%`, § Primary stat magnitude) — let alone one SSS slot (`32.68%`) or the two-slot
  summed total a stat actually receives from full same-rank gear. A full-resonance trait stack
  never outweighs a single piece of equipment, at any rank at or above A.
- Worst-case crit-cap stack, Rogue (highest base `CRIT_RATE`, 15%, plus a `CRIT_RATE` trait): base
  15% + max-enhanced SSS necklace (26.96pp, § Enhancement's own verified figure) + trait
  (+1.5pp) = **43.46%**, `31.54pp` of margin remaining under the `75%` cap.
- Same check, Ranger (also carries a `CRIT_RATE` trait, base 10%): 10% + max-enhanced SSS necklace
  (26.972pp) + trait (+1.5pp) = **38.472%**, `36.528pp` of margin remaining.

Neither the "outscales a slot" nor the "blows the crit cap" risk the task brief flagged materializes
at the chosen magnitudes.

**4. `Hero` storage — one new field, save-boundary change.**

Resonance traits need **no new `Hero` field**: they are derived at read time from the existing
`resonance: int` (`heroes/hero.gd:20`, already round-tripped through `to_dict`/`from_dict`) plus
the definition's `resonance_trait_pool`. A pure `static func`, following the `compute_essence_yield`
/`compute_rank_up_cost` shape already on `Hero`:

```
static func active_resonance_traits(hero: Hero, definition: HeroDefinition, balance: BalanceTable) -> Array[TraitDefinition]:
    var unlocked_count := 0
    for threshold: int in balance.resonance_trait_thresholds:
        if hero.resonance >= threshold:
            unlocked_count += 1
    return definition.resonance_trait_pool.slice(0, mini(unlocked_count, definition.resonance_trait_pool.size()))
```

`resonance_trait_thresholds: Array[int] = [1, 3, 6]` is a **new `BalanceTable` field** — the
thresholds are a shared, systemic tunable (identical for every archetype), which is why they live
on `BalanceTable` rather than per-archetype, the same split `equip_pct_per_rank` (shared curve, on
`BalanceTable`) already draws against `EquipmentDefinition.primary_stat` (per-item identity, on the
definition).

Instructor-taught traits **are** a new `Hero` field, because they are granted directly with no
counter to derive them from:

```
var taught_traits: Array[StringName] = []
```

`to_dict`: `"taught_traits": [str(id) for id in taught_traits]`, sorted for diff-stability — same
reasoning `to_dict`'s existing `equipped_slots.sort()` already uses (`heroes/hero.gd:136-137`).
`from_dict`: default to `[]` when the key is missing (pre-trait saves, backward compatible, same
as `resonance` defaulting via `Item.int_field`) **and** when it is explicitly `null` — mirroring
the explicit-null defensive shape `e9f661a` already added for `equipped`, not `Dictionary.get()`'s
default alone. Each entry validated as `String` before converting to `StringName`, `push_error` and
skip otherwise — the same per-entry validation shape `GameSession.from_dict`'s
`cleared_zone_ids` loop already uses (`systems/game_session.gd:195-197`). `taught_traits` stays
empty in every save until `P2-13` ships a write path for it — nothing today ever appends to it, so
this field's presence in `Hero.to_dict/from_dict` right now is inert, not speculative: it exists so
`P2-13` doesn't need a second save-format bump later, at zero behavioral cost until then.

**This is a save-boundary change** (`CLAUDE.md` risky boundary 1, `Hero.to_dict`/`from_dict`,
`heroes/hero.gd:133-201`). The implementing ticket needs a `verifier` pass and a real save/reload
cycle — a hero with `resonance >= 1` (trait present via derivation) and, separately, a hand-seeded
`taught_traits` entry, both surviving a round trip — not just a green import gate.

**`P2-06c` shipped without `taught_traits`, deliberately — `P2-13` owns the field.** The "so
`P2-13` doesn't need a second save-format bump" argument above does not hold: `Hero.from_dict`
already defaults every missing key, so adding the field in `P2-13` costs exactly what adding it
in `P2-06c` would have cost. What it *would* have cost then is real — a save-boundary change and
a mandatory `verifier` pass for a field nothing writes and whose only possible value is `[]`.
That is `LostCache.turn_lost` (`P2-04e`) and `Item.enhance_level` (`P2-05d`) a third time, and it
went the same way. Everything specified above still stands for whoever adds it; only the timing
moved, and with it cut, `P2-06c` touched no save key at all.

**5. Where the numbers live.**

| Number | File | Notes |
|---|---|---|
| `TraitDefinition` (new Resource type) | `heroes/trait_definition.gd` | `id`, `display_name`, `stat` (`EquipmentDefinition.PrimaryStat`), `magnitude`. |
| `resonance_trait_pool` (3 `TraitDefinition`s per archetype) | `HeroDefinition` (→ `heroes/defs/*.tres`) | New field. Per-archetype content, same footing as `base_hp`/`crit_rate`. |
| `instructor_trait_pool` (empty) | `HeroDefinition` (→ `heroes/defs/*.tres`) | New field, reserved. Not populated by this ruling — `P2-13`'s. |
| `resonance_trait_thresholds = [1, 3, 6]` | `BalanceTable` (→ `balance.tres`) | New field. Shared tunable, same footing as `equip_pct_per_rank`. |
| `Hero.taught_traits: Array[StringName]` | `heroes/hero.gd` | New field + `to_dict`/`from_dict` keys. Save-boundary change (§4). |
| Trait application in `compute_final_stats` | `heroes/hero.gd:44-99` | Same accumulate-then-multiply (non-crit) / add-then-clamp (crit) channels equipment already uses — extend the existing loop, no new formula shape. |

**Rejected: a `StringName` id plus a `BalanceTable` effect table.** Would force `BalanceTable` to
carry per-archetype content for the first time, breaking its established "shared curve only" shape,
and still needs an archetype-to-id mapping somewhere — which `HeroDefinition` already is. See §1.

**Rejected: a single tagged pool (`source: RESONANCE|INSTRUCTOR` on `TraitDefinition`) instead of
two arrays.** Works, but every future reader must filter by tag to preserve `P2-13`'s "obtainable
no other way" requirement; two pools make that a structural guarantee instead of a discipline
requirement. See §2.

**Rejected: authoring "abilities" (on-kill effects, lifesteal, guaranteed openers) instead of stat
modifiers.** Out of scope per the task brief — `combat/quick_resolve.gd` is statistical
(`team_power` vs `wave.enemy_power` plus a damage fraction), not a simulated per-action combat
system; an active-skill trait has nothing to hook into today. That is exactly the job Cores already
have (§ Cores, above — "lifesteal, on-kill party heal, guaranteed opening crit" as *rolled unique
effects*, Phase 4, a different system with its own unique-effect precedent) — traits stay
stat-only so the two systems don't duplicate each other's job.

> ⚠️ **PROVISIONAL** — the fifteen trait magnitudes above are arithmetically checked against the
> real equipment and enhancement tables (Codex thread `019fd972-7c95-7330-8ad1-658bfede671d`:
> nothing outscales a single A-rank-or-higher slot, nothing threatens the `75%` CRIT_RATE cap even
> stacked with maxed gear) but never played — whether a resonance payoff this size reads as
> "worth chasing the dupe" or "didn't notice" once `P2-06c` ships it is a feel question the
> arithmetic can't answer, same shape as every other PROVISIONAL marker in this document.
> **Settled by:** `P2-06c` shipping resonance traits end to end, then a played build with a hero
> actually pushed to 6 dupes.

---

## Equipment — *Phase 2, Cores Phase 4*

Ten slots:

`head` `chest` `legs` `gloves` `boots` `main_hand` `off_hand` `necklace` `ring` `belt`

Affix count and socket count come from the rank table. An SSS item is better on three
independent axes at once — higher base, more affixes, larger affix rolls — which is why a
high-rank drop reads as an event.

### Primary stat per slot

Enhancement needs a target stat per slot. Two "armor" slots split HP, two split DEF, two
"mobility" slots carry SPD, two "weapon" slots carry ATK, and the two jewelry slots each take
one crit stat:

| Slot | Primary stat |
|---|---|
| head | HP |
| legs | HP |
| chest | DEF |
| off_hand | DEF |
| main_hand | ATK |
| gloves | ATK |
| boots | SPD |
| belt | SPD |
| necklace | CRIT_RATE |
| ring | CRIT_DMG |

### Loot table — which item a cleared zone yields

`P2-04b`. `Item` (`equipment/item.gd`) is `def_id: StringName + rank: int` and nothing else
(`P2-04c`) — a drop is exactly one instance of that shape. Placed here, ahead of Enhancement,
because enhancement needs an item to already exist.

**Ruling, in order of the ticket's four questions:**

**1. Drop rate — guaranteed, one item, flat across all three zones.** A successful expedition
(`Expedition.resolve()` reaching `OUTCOME_COMPLETED`, `hub/expedition/expedition.gd:58-59`, the
same call site as `mark_zone_cleared()`) yields exactly one `Item`. Not zone-scaled, not
probabilistic on the "does it drop" question — only *which* item is randomized (slot, rank
below). `RETREATED` and `DEFEATED` yield nothing; only a full clear does.

**2. Slot — uniform across all ten `Slot` values (10% each).** No existing number in this
document weights one slot over another — Primary stat per slot (above) treats all ten
symmetrically (2 HP / 2 DEF / 2 SPD / 2 ATK / 2 crit slots), so there's no established asymmetry
to carry into a drop weighting. `def_id` follows the slot directly: each `Slot` has exactly one
authored `EquipmentDefinition` today (`equipment/defs/<slot_name>.tres`), so rolling a slot *is*
rolling a `def_id` — no second roll needed.

**3. Rank — reuse `summon_weights`, sliced to the zone's band and renormalized.** Each zone
carries a rank band as two new `int` fields, `loot_rank_min` / `loot_rank_max` (rank indices,
`0..7`, inclusive), matching the band each zone's `loot_emphasis` prose already names:

| Zone | Band (prose) | `loot_rank_min` | `loot_rank_max` |
|---|---|---|---|
| Verdant Outskirts | F–C | 0 | 2 |
| Ashfall Reaches | C–A | 2 | 4 |
| Sundered Vault | S–SSS | 5 | 7 |

Within the band, a rank's drop weight is `BALANCE.summon_weights[i]` for `i` in
`[loot_rank_min, loot_rank_max]`, renormalized so the band sums to 1.0. The Summoning Circle
already renormalizes this same array after reweighting it (Summoning, above) — note it scales a
block and renormalizes all eight, where this *drops* the out-of-band ranks entirely, so the two
are the same array and the same renormalize step, not the same operation. No new weight table is
authored; the existing rank-rarity curve is reused verbatim.

Verified against `summon_weights = [4000, 2700, 1700, 1000, 450, 120, 28, 2]`
(`balance.tres`) and the three authored zones (`zones/defs/*.tres` — bands above match each
zone's authored `loot_emphasis` band exactly):

| Zone | Ranks (band) | Weights | Sum | Renormalized |
|---|---|---|---:|---|
| Verdant Outskirts | F, D, C | 4000, 2700, 1700 | 8400 | 47.62% / 32.14% / 20.24% |
| Ashfall Reaches | C, B, A | 1700, 1000, 450 | 3150 | 53.97% / 31.75% / 14.29% |
| Sundered Vault | S, SS, SSS | 120, 28, 2 | 150 | 80.00% / 18.67% / 1.33% |

Each row sums to exactly 1.0 (verified as exact fractions: Verdant `10/21 + 9/28 + 17/84 = 1`;
Ashfall `34/63 + 20/63 + 1/7 = 1`; Sundered `4/5 + 14/75 + 1/75 = 1` — Codex thread
`019fcff0-e9de-7622-9c81-4d1391557dbf`). Sundered's own top end stays true to the "near-mythical"
feel Summoning already established: an SSS-rank drop is 1.33% *of a Sundered clear*, not 1.33% of
all drops everywhere — expected clears to a first SSS-rank item of *any* slot from Sundered is
`1/0.013333 ≈ 75`; to a *specific* slot at SSS (e.g. a Sundered main-hand at SSS) is
`1/(0.013333 * 0.10) = 750` (same thread).

**4. Where the numbers live.**

| Number | File | Notes |
|---|---|---|
| `loot_rank_min` / `loot_rank_max` per zone | `ZoneDefinition` (→ `zones/defs/*.tres`) | New fields. Genuinely per-zone, per the ticket's own framing. |
| Rank weights within the band | Nowhere new — derived at runtime from `BalanceTable.summon_weights` (already in `balance.tres`) | Slice-and-renormalize is a formula, same footing as the Summoning Circle's own renormalization (written into the rule, not authored as a second table). |
| Slot uniformity (1/10) | Nowhere — formula-shape (`10` is `EquipmentDefinition.Slot`'s fixed size, an ADR-settled count, not a tunable) | No `BalanceTable` field. |
| Guaranteed one-item-per-clear | Nowhere — formula-shape, written into the drop rule itself | Same footing as the team-size `/5.0` divisor and the win/loss cubic exponent (Expeditions, above): a shape choice, not a magnitude. |

`P2-04d`'s "files allowed to change" follows directly: `ZoneDefinition` (`zones/zone_definition.gd`
+ the three `.tres`, two new fields) and whatever loot-roll code it adds. `BalanceTable`/
`balance.tres` need no new field for this ticket.

**`loot_emphasis` is supplemented, not replaced.** The prose stays — it is display copy for the
zone-select UI, unaffected by whether a machine-readable band also exists — and the band above is
a direct, checked transcription of that prose (`F–C` → `0..2`, `C–A` → `2..4`, `S–SSS` → `5..7`),
not a reinterpretation of it. `tests/zone_definition_check.gd`'s exact-text assertion on
`loot_emphasis` is therefore untouched by this ruling; `P2-04d` only adds the two new fields.

**Seeded from `CombatResult.loot_seed`, specifically the boss wave's result.** `loot_seed` is set
on every `QuickResolve.resolve()` call (`combat/quick_resolve.gd:33`) and `Expedition.resolve()`
calls `resolve()` once per wave in a loop, discarding each wave's `CombatResult` except for
bookkeeping (`hub/expedition/expedition.gd:32-58`). `mark_zone_cleared()` fires immediately after
the loop's last iteration — the boss wave (`wave_index == zone.trash_wave_count`) — so the boss
wave's `CombatResult.loot_seed` is the one in scope at exactly the point the drop must be rolled,
and is the only one that exists once per clear rather than once per wave. Seed a
`RandomNumberGenerator` with it; roll slot and rank from that generator.

**Rejected: chance-based drop (e.g. a flat 70% "does it drop at all" roll).** Nothing in this
document names a scarcity goal for equipment acquisition itself — the rank/slot rolls already
supply rarity variance, and salvage/parts (above) already gate re-gearing speed. A dry roll on
top adds a frustration axis with no stated purpose. Revisit only if `P2-04d`/`P2-05a` surface
inventory bloat as a real problem.

**Rejected: more than one item per clear, scaled by zone.** The ticket's own framing is singular
("which item a cleared zone yields"), and none of the four questions asked about count. Adding a
per-zone item count is scope this ticket wasn't asked to rule on.

**Rejected: weighted slot distribution.** No basis exists to prefer one slot over another — the
Primary stat per slot table (above) is already symmetric across all ten slots — so weighting one
would be an arbitrary number invented for this ticket alone, which the acceptance criteria
explicitly rule out ("undefined is not [fine]").

**Rejected: an independently-authored rank-drop curve**, rather than reusing `summon_weights`.
Would need its own justification and its own from-scratch PROVISIONAL marker; reusing the game's
one already-tuned rarity curve costs nothing new, stays internally consistent (an SSS is
near-mythical everywhere it appears, not just in Summoning), and reuses the array the Summoning
Circle already renormalizes in this same document.

**Rejected: rolling independently instead of seeding from `loot_seed`.** `loot_seed` exists in
`CombatResult` with **no consumer** specifically for this (`docs/TASKS.md` P2-04b's own
"Existing architecture" note) — using it costs nothing and makes a clear's drop reproducible from
the same expedition data, for free.

**Rejected: seeding from every wave's `loot_seed` (e.g. XOR-combining all of them).** Only the
boss wave's `CombatResult` is in scope where the clear is actually recorded, and a clear happens
exactly once per expedition — there is exactly one natural seed, not several to combine.

> ⚠️ **PROVISIONAL** — the rank/slot arithmetic above is verified against real `.tres` data and
> internally consistent with Summoning's existing rarity curve, but nobody has played against a
> guaranteed one-item-per-clear rate: whether it reads as generous or floods inventory once
> `P2-04d` wires drops into a real run and `P2-05` (salvage) exists to absorb the flow is unfelt.
> · **Settled by:** `P2-04d` shipping drops end-to-end, then a played build across all three
> zones once salvage exists to close the loop on unwanted items.

### Primary stat magnitude — what a rank-`N` item contributes

`P2-05b`. Rules what equipping a rank-`N` item actually does to `Hero.compute_final_stats`
(`heroes/hero.gd:42-66`). Placed here, ahead of Enhancement, because Enhancement's `+8%` per
level needs a base magnitude to compound on — same reasoning as Loot table's placement ahead of
it.

**Ruling, in order of the ticket's four questions:**

**1. Channel and magnitude — the eight non-crit slots use `equip_pct`, not `equip_flat`.**

```
equip_pct_per_rank[i] = 0.04 * rank_mult[i]
```

| Rank | F | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|---|
| `equip_pct_per_rank` | 4.00% | 5.40% | 7.28% | 9.84% | 13.28% | 17.92% | 24.20% | 32.68% |

A rank-`N` item in `head` / `legs` / `chest` / `off_hand` / `main_hand` / `gloves` / `boots` /
`belt` adds `equip_pct_per_rank[item.rank]` to its slot's primary stat's `equip_pct`. Two slots
feed each of HP/ATK/DEF/SPD (Primary stat per slot, above), and their contributions **sum**
before the formula's single `final *= 1.0 + equip_pct` multiply — the formula already names
`equip_pct` as one scalar per stat, and summing same-stat item contributions into it before that
multiply is the only reading that doesn't need a second multiply pass per item.

`equip_pct` over `equip_flat` for these eight slots because `equip_pct` is self-scaling: one
curve serves HP (base 80–140), ATK (base 16–34), DEF (base 10–24) and SPD (base 90–110) at once,
because a *percentage* of each archetype's own stat is meaningful regardless of that stat's raw
size. `equip_flat` would need four separately-authored rank-indexed tables — one per stat's own
scale, since a flat bonus sized right for HP (hundreds) is either negligible or absurd applied to
DEF (tens) — for the same job one `equip_pct` curve already does. This makes `equip_flat`,
named in the hero formula and never given a magnitude anywhere, the unused channel the ticket
itself calls "worse than a deleted one" for these eight slots specifically — see Where the
numbers live, below, for what still uses it.

**New `BalanceTable` field, not a reuse of `stat_multipliers`.** `equip_pct_per_rank` shares
`stat_multipliers`' 8 ratios (`1.00, 1.35, 1.82, 2.46, 3.32, 4.48, 6.05, 8.17`) scaled by a
`base_pct = 0.04` — a deliberately *independent* array, not a live reference to the hero curve.
A literal reuse would mean any future retune of `stat_multipliers` (hero balance) silently
reprices every piece of equipment in the game in the same pass — exactly the kind of one-field-
reprices-another coupling the essence/parts/enhancement note warns about, just between hero and
equipment instead of within equipment. An independent field with the same *shape* keeps a
familiar, already-vetted growth curve without wiring the two systems together.

Verified against the real archetype data (`heroes/defs/*.tres`) and `balance.tres`'s
`stat_multipliers`, full ten-slot same-rank gear, at all three existing checkpoints (Codex thread
`019fd35a-8937-7ae2-9038-324f4bcfdd6e`, ungeared baselines reproduced independently and matched
the published `1,046.5` / `4,803.15` / `11,453.12` team totals before rounding):

| Checkpoint | Ungeared team power | Fully-geared team power (10 same-rank slots) | Gear share |
|---|---:|---:|---:|
| F, lvl 10 | 1,046.50 | 1,130.22 | 7.41% |
| B, lvl 40 | 4,803.15 | 5,748.41 | 16.44% |
| S, lvl 60 | 11,453.12 | 15,557.92 | 26.38% |

Per-archetype breakdown is identical proportionally at every checkpoint — HP/ATK/DEF/SPD each
get exactly two items, so every archetype's power gets the same `(1 + 2 * equip_pct_per_rank[i])`
factor regardless of its own stat spread (full per-archetype table in the Codex thread). At SSS
(not run through Codex, but the same formula on the same ratios, so it's arithmetic, not a new
claim): `q = 2 * 32.68% = 65.36%`, gear share `= 0.6536 / 1.6536 = 39.53%` — gear share climbs
with rank because `equip_pct_per_rank` is itself rank-scaled, same shape as the hero's own curve.

**Rejected: `equip_flat` for the eight non-crit slots.** Needs four separately-authored
rank-indexed tables (one per stat scale) to do what one `equip_pct` curve already does across
all eight — more surface area, no benefit, and it doesn't auto-adapt to the archetype variance
already baked into each archetype's own base/growth line the way a percentage does.

**Rejected: reusing `stat_multipliers` directly** (i.e. `equip_pct_per_rank = stat_multipliers`
verbatim, or a runtime reference to the same array). Ties equipment magnitude to hero-curve
retunes with no independent knob — named as the risk to avoid in the ticket's own framing of this
question ("a decision with a justification, not a default"). A new field with matching ratios and
its own scalar keeps both curves visible and independently tunable.

**2. The two crit slots — answered separately; `equip_flat`, no `equip_pct`, no `rank_mult`.**

```
equip_crit_pct_per_rank[i] = 0.015 * rank_mult[i]
```

| Rank | F | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|---|
| `equip_crit_pct_per_rank` | 1.50% | 2.03% | 2.73% | 3.69% | 4.98% | 6.72% | 9.08% | 12.26% |

`necklace` adds `equip_crit_pct_per_rank[item.rank]` **percentage points** directly to
`CRIT_RATE`; `ring` adds the same table's value as a **flat decimal** directly to `CRIT_DMG`
(`+0.1226` at SSS, i.e. `+12.26%` more crit damage). Neither passes through `rank_mult` — Ranks
already rules `rank_mult` and `growth` apply to HP/ATK/DEF/SPD only, and CRIT_RATE/CRIT_DMG "move
only by equipment" — this ruling is that move, and it stays consistent with the existing rule
rather than reopening it. Crit stats also skip `equip_pct` entirely, for a different reason than
the cap: `equip_pct` is a *relative* modifier appropriate for stats measured in absolute units
(a percentage of an HP pool means something); CRIT_RATE/CRIT_DMG are already percentages, so
running them through `equip_pct` would be a percentage-of-a-percentage a player has to mentally
unpack twice for one number, where "+12.26 points" reads at a glance. This is the same "don't run
a relative multiplier through an already-relative stat" principle Ranks' rejection of `rank_mult`
on crit stands on — not the identical failure (the magnitude chosen here doesn't hit the literal
122% cap-violation Ranks found), but the same shape of problem, and it is answered the same way:
route crit stats around the channel that causes it.

**`CRIT_RATE` cap: 75%, named explicitly since this ruling depends on one existing.** Verified
against the highest-base-`CRIT_RATE` archetype (Rogue, 15%) at every checkpoint, full same-rank
gear (Codex thread above): `16.50%` (F) / `18.69%` (B) / `21.72%` (S) / `27.26%` (SSS, computed
directly — `15% + 12.26pp`). Comfortably under 75% at every rank on the base ruled here.
**Enhancement headroom check.** Enhancement's `+8%` per level is ruled additive in § Enhancement
(`P2-05e`): `contribution *= 1 + enhance_pct_per_level * enhance_level`. At max enhance (`15`),
Rogue's SSS necklace contribution grows from `12.26pp` unenhanced to `26.96pp`, landing
full-Enhanced Rogue `CRIT_RATE` at `41.96%` — comfortably under the `75%` cap, with `33.04pp` of
margin remaining. (The rejected compounded reading would have spent more of that margin: `53.87%`,
leaving only `21.13pp`.) Both clear the cap, so the cap alone didn't force the choice — see
§ Enhancement for the full ruling, the rejected compounded reading, and what maxed enhancement
does to the non-crit-slot gear-share figure above.

**Rejected: applying the general `equip_pct` rule uniformly to crit slots.** At the magnitude
chosen for the other eight slots (`base_pct = 4%`), crit doesn't literally blow the cap the way
`rank_mult` did in Ranks (`15% * 1.3268 = 19.9%` at SSS, not `122%`) — so the cap-violation
argument alone doesn't force a separate channel here the way it did for `rank_mult`. It's ruled
separately anyway on the legibility ground above (a relative modifier on an already-relative
stat), which is a real cost even where it isn't a hard violation.

**3. Where the numbers live.**

| Number | File | Notes |
|---|---|---|
| `equip_pct_per_rank` (8 floats, HP/ATK/DEF/SPD slots) | `BalanceTable` (→ `balance.tres`) | New field. Same shape as `stat_multipliers`, independently scaled — not a reuse. |
| `equip_crit_pct_per_rank` (8 floats, necklace/ring) | `BalanceTable` (→ `balance.tres`) | New field. Serves both crit stats — `CRIT_RATE` reads it as percentage points, `CRIT_DMG` reads it as a flat decimal; same underlying curve, two units at the point of use. |
| `equip_crit_rate_cap = 0.75` | `BalanceTable` (→ `balance.tres`) | New scalar. Named because question 2 depends on it. `P2-05c` shipped the clamp — `minf` against it as the last line of `compute_final_stats` (`heroes/hero.gd:92`) — since headroom is real but not infinite once Enhancement stacks on top. |
| Two-item-per-stat summation rule (HP/ATK/DEF/SPD) | Nowhere new — formula-shape, written into `compute_final_stats`'s equip_pct accumulation | Same footing as the loot table's slot-uniformity rule: `2` is fixed by Primary stat per slot's authored table, not a tunable. |
| `equip_flat` channel for the eight non-crit slots | Nowhere — deliberately unused | Named in the hero formula, ruled against for these slots (see rejection above). Still used by the two crit slots. |

`P2-05c`'s "files allowed to change" follows directly: `BalanceTable`/`balance_table.gd` (three
new fields above) + `balance.tres`, and `Hero.compute_final_stats` to read `Hero.equipped`,
look up each `Item`'s `EquipmentDefinition.primary_stat`, and accumulate into `equip_pct` or
`equip_flat` per the channel ruled here. No `EquipmentDefinition` change and no `Item` change —
both already carry everything this ruling needs (`slot`, `primary_stat`, `def_id`, `rank`).

**Rejected: a per-slot magnitude authored on `EquipmentDefinition`** (ten `.tres` files each
carrying their own rank-indexed array). Primary stat per slot already established all ten slots
are symmetric within their stat group — two HP slots, two DEF, two ATK, two SPD, one each crit —
so the magnitude curve has no per-slot variation to express. Ten copies of the same eight numbers
(or two, since crit needs its own) is pure duplication with a real cost: retuning the curve later
means editing ten files instead of one `BalanceTable` field, and the ten copies can drift out of
sync with each other. Same reasoning the loot table ruling already used to reject a per-zone
rank-drop curve: one already-justified shared curve costs nothing new and stays consistent by
construction.

**4. Gear share of power, and what it means for recommended power and `compute_team_power`.**

**Recommended power figures (900 / 4,800 / 11,500) hold, unchanged.** They were already pinned to
the *ungeared* reference team by explicit prior design intent ("real teams carry gear on top,"
The three zones, above) — this ruling doesn't move that anchor, it quantifies what was already
implied by it. At calibration rank, an ungeared team sits at or just below recommended power
(`4,803.15` vs `4,800` at B; `11,453.12` vs `11,500` at S — both within a fraction of a percent);
a fully same-rank-geared team clears it with real margin (`5,748.41`, `+19.75%` over RP at B;
`15,557.92`, `+35.3%` over RP at S). That gap **is** the headroom the existing PROVISIONAL marker
on recommended power already named as the intended reading ("bosses are not meant to be beatable
by an ungeared reference team… gear is the intended headroom") — this ruling is the first time
that headroom has a checkable number attached to it, not a reason to move the anchor itself.

**Notable implication, not independently re-verified here (out of this ticket's combat scope):**
Sundered Vault's boss sits at `130%` of RP (`14,950`), proven arithmetically impossible for an
ungeared S/60 team (`11,453.12 < 14,950`, Expeditions above). A fully same-rank-geared S/60 team
(`15,557.92`) clears that bar (`r = 14,950 / 15,557.92 = 0.9609 < 1`, so the win check is
satisfiable again, though still a narrow roll). This is the specific mechanism the "gear is the
intended headroom" reasoning predicted, now with a real number behind it — but it's a power-ratio
observation, not a played or simulated combat result, and full ten-slot same-rank gear on every
hero is a best case, not what a typical mid-progression roster carries.

**`compute_team_power` stays a usable-but-incomplete proxy.** It sums `ATK + DEF + HP/10 + SPD`
(`heroes/hero.gd:81`) — exactly the four stats the eight non-crit slots feed, and none of what
the two crit slots feed. Under this ruling, `hero_power`/`team_power` becomes visible to 8 of a
hero's 10 equipped slots (up from 0 before this ticket — equipping anything previously changed no
number at all) but stays permanently blind to the necklace and ring: a hero with best-in-slot
SSS crit gear (`CRIT_RATE +12.26pp`, `CRIT_DMG +12.26%`) reads identically in `hero_power` to the
same hero with both jewelry slots empty, even though crit is a real damage-output difference in
any eventual per-hit combat model. This is a real gap, worth flagging plainly per the ticket's own
question rather than routing around it silently — but fixing `compute_team_power`'s formula is an
Expeditions/combat-seam change, out of this equipment-magnitude ticket's scope and forbidden by
its own non-goals ("no code"). Flagged here for `tech-lead` to pick up if crit-blind power reads
as a real problem once `P2-05c` ships it and jewelry gear is actually equippable.

> ⚠️ **PROVISIONAL** — `base_pct = 4%` and `base_crit = 1.5%` are arithmetically checked against
> real archetype and rank data (Codex thread `019fd35a-8937-7ae2-9038-324f4bcfdd6e`) to land gear
> share in a chosen 20–30% target band at the S/60 checkpoint while keeping the highest-crit
> archetype comfortably under the 75% `CRIT_RATE` cap, but the 20–30% target itself is a design
> guess — nobody has played against a hero that is 16–40% stronger for being fully same-rank
> geared, and no combat model exists yet where crit being invisible to `hero_power` has a felt
> consequence. · **Settled by:** `P2-05c` wiring this into `Hero.compute_final_stats` and
> `Item`/`EquipmentDefinition` lookups, then a played build across at least the B and S
> checkpoints to feel whether the gear-share curve reads as "gear matters" or "gear dominates" —
> and separately, whatever ships the arena/real damage model, to find out whether a crit-blind
> `hero_power` is a cosmetic gap or a UI lie players notice.

### Enhancement

`P2-05e`. Rules the two unvalued inputs Enhancement's lines named but never priced — which `+8%`
reading applies, and what gold is — plus whether the level cap can ship without `forge_level`.

**1. The `+8%` reading — additive, not compounded.**

```
enhanced_contribution = base_contribution * (1 + enhance_pct_per_level * enhance_level)
```

Applied per item, to that item's own `equip_pct_per_rank[item.rank]` (eight non-crit slots) or
`equip_crit_pct_per_rank[item.rank]` (necklace/ring) — the same per-item value Primary stat
magnitude already sums across a stat's two slots, just scaled up first. `enhance_pct_per_level =
0.08`; `enhance_level` capped at 15 (question 3).

Verified against the real authored tables, not an extrapolation (Codex thread
`019fd4d6-b240-7262-8339-0cc8064519a3`), both readings at max enhance (15) on SSS-rank gear:

| | Compounded (`1.08^15 = ×3.1722`) | Additive (`1 + 0.08*15 = ×2.2`) |
|---|---:|---:|
| Rogue full-Enhanced `CRIT_RATE` (base 15%, SSS necklace unenhanced `+12.255pp`) | `15% + 38.87pp = 53.87%` | `15% + 26.96pp = 41.96%` |
| Margin under the `75%` cap | `21.13pp` | `33.04pp` |
| Two-SSS-item stat, gear share of the final stat (= of team power, per the formula's uniform per-stat scaling) | `67.46%` | `58.98%` |

Both clear the `75%` `CRIT_RATE` cap, so — unlike the non-crit-slot channel question in Primary
stat magnitude, which the cap decided outright — the cap doesn't force this choice either way.
Ruling additive on precedent, not on a cap violation:

- Every other growth formula in `Hero.compute_final_stats` is additive-then-a-single-multiply,
  never compounding: `(base + growth * level) * rank_mult[rank]` (`heroes/hero.gd:63-66`) for
  level — `rank_mult` itself a fixed authored array, not a runtime `pow()` — and Primary stat
  magnitude's own equip_pct is summed before one multiply. Nothing in the hero stat pipeline runs
  an exponential; giving Enhancement alone a `pow()` introduces a second kind of math with no
  other system in this doc behaving as precedent for it.
- Compounded pushes gear share of a maxed-SSS-Enhanced stat to `67.46%` — well past even the
  unenhanced-SSS `39.53%` Primary stat magnitude already flagged as needing a played build to
  confirm isn't "gear dominates." Additive's `58.98%` is still a large jump over unenhanced (that's
  the point of enhancing), but doesn't compound on top of Primary stat magnitude's own
  already-rank-scaled curve the way `1.08^15` does — two independently-steep exponents stacking is
  exactly the kind of one-field-reprices-another interaction this doc's essence/parts/enhancement
  note warns about.
- "+8% per level" reads as additive absent a stated "each level multiplies by 1.08" — the
  compounded case is the one that needs the exponent spelled out to be understood at all, which
  makes it the reading requiring justification, not the default one.

**Rejected: compounded.** Not forced by any cap (both clear `75%`), and it would be the only
exponential growth formula anywhere in `Hero.compute_final_stats` — a second, steeper kind of
scaling with no other system in this doc sharing its shape, on the one input that has no hard
ceiling in play to force a choice.

**2. Gold does not exist — struck from the cost line, deferred.**

```
cost(n → n+1) = 2 + n parts of matching rank
```

No "plus gold." `grep -rn "gold" --include=*.gd --include=*.tres --include=*.tscn .` returns zero
hits — no `BalanceTable` field, no `GameSession` currency, no drop source anywhere. Gold appears in
exactly two other places in this document: the three zones' loot-table Reward columns (prose only
— `P2-04b`'s authored loot table covers rank/slot for equipment drops and never touched gold) and
Buildings' "Upgrade cost: gold + parts" line, which has the identical problem.

This is the same shape as Summoning's Summon Stone income rate (`P2-09`) and Expeditions' XP curve
(`P2-04a`): a value named in prose with no acquisition rate, no drop formula, and nothing in code
— a genuine missing design input, not something this document can settle by picking a number.
Authoring a gold cost with no income source would make the cost line unimplementable-honestly: a
player could hit a wall with no way to know how to clear it, which is worse than a system that
costs parts only until gold has a source.

**Ruling: Enhancement costs parts only.** Gold is struck from this cost line and from Buildings'
upgrade-cost line (below). At the time of this ruling that was provisional — deferred pending a
ticket to give gold an income rate. It has since been settled further: see the gold-removal
ruling below, which strikes gold from the document entirely rather than merely deferring it.

**3. Cap: `forge_enhance_cap_max` (15), flat — no `forge_level` term until `P2-07`.**

`forge_level` doesn't exist: no `Building` resource, no per-building level field anywhere
(`P2-07` unstarted). `balance_table.gd` already authors both coefficients
(`forge_enhance_cap_per_level = 3`, `forge_enhance_cap_max = 15`), which makes `min(15, forge_level
* 3)` read settled the same way `reliquary_decay_turns_bonus` did before the `P2-04` split found
the building behind it didn't exist yet.

Unlike Buildings' other four bonuses (Training Hall XP, Sanctum essence, Reliquary decay/damage),
which are additive *bonuses* that default sensibly to "no bonus" in the building's absence, the
enhance cap is a hard *ceiling* Enhancement needs in order to function at all: gating it at
`forge_level * 3` with no `forge_level` evaluates to `cap = 0`, and Enhancement could never apply
a single level. That can't be what shipping `P2-05f` now is for.

**Ruling: `P2-05f` reads the cap as `balance.forge_enhance_cap_max` (15) flat, with no
`forge_level` term.** When `P2-07` gives the Forge a real level, the formula becomes
`min(forge_enhance_cap_max, forge_level * forge_enhance_cap_per_level)` for real —
`forge_enhance_cap_per_level` sits unused in `balance_table.gd` today for exactly that reason, not
stranded, just not yet wired to a level that exists.

**4. Where the numbers live.**

| Number | File | Notes |
|---|---|---|
| `enhance_pct_per_level = 0.08` | `BalanceTable` (→ `balance.tres`) | New scalar. The tunable knob for question 1's ruling; applied per-item as `base_contribution * (1 + enhance_pct_per_level * enhance_level)`. |
| `Item.enhance_level` (int, 0–15) | `equipment/item.gd` | New field — `P2-05f`'s, per `docs/TASKS.md`'s split note (`P2-04e`/`turn_lost` precedent: add the field when there's something to count). Not authored here; this ruling only fixes what multiplies against it. |
| `cost(n → n+1) = 2 + n` parts of matching rank | Nowhere new — formula-shape, unchanged here except "plus gold" struck | Same footing as the loot table's slice-and-renormalize: a formula, not a table. |
| `forge_enhance_cap_max = 15` | `BalanceTable` (already in `balance.tres`) | Existing field, now the sole cap value per question 3 — no new field needed. |
| `forge_enhance_cap_per_level = 3` | `BalanceTable` (already in `balance.tres`) | Existing field, unused until `P2-07` gives the Forge a real level; not read by `P2-05f`. |
| Gold | Removed — see the gold-removal ruling below | Not deferred pending a future ticket; struck from this document entirely. Parts (this cost line, Buildings' upgrade cost) and Summon Stones (Summoning) already cover the two earned-currency tracks a non-monetized gacha economy needs — a third, unimplemented currency added nothing. |

`P2-05f`'s "files allowed to change" follows: `equipment/item.gd` (`enhance_level` field +
`to_dict`/`from_dict`), `BalanceTable`/`balance_table.gd` (`enhance_pct_per_level`) + `balance.tres`,
and `Hero.compute_final_stats` to scale each item's per-item contribution before the existing
per-stat summation. No change to `EquipmentDefinition`.

> ⚠️ **PROVISIONAL** — the `58.98%` maxed-enhancement gear share (question 1) is arithmetically
> checked, not played — it's the same open question Primary stat magnitude's own gear-share marker
> already named ("gear matters" vs "gear dominates"), now with a number attached for the ceiling
> case rather than just the unenhanced one. · **Settled by:** the same played build that marker
> calls for, at an additional checkpoint — maxed rank *and* maxed enhancement, not just maxed rank.

**Gold removal — settled, not provisional.** An external design review (2026-08-06) argued a
non-monetized gacha economy needs two separate earned-currency tracks — one for pulling, one for
upgrading — to avoid gridlock where a player must constantly choose between roster expansion and
vertical power. This game already has exactly that: Summon Stones pull, and parts (rank-tiered,
salvage- and drop-sourced) upgrade, via Enhancement's cost line above and Buildings' upgrade cost
below. Gold would be a third currency filling a role the other two already cover, with zero
implementation behind it (`grep -rn "gold" --include=*.gd --include=*.tres --include=*.tscn .`
returns hits only in three `ZoneDefinition` resources' and one test's `loot_emphasis` *display
string* — decorative prose, not a `BalanceTable` field, `GameSession` currency, or drop source).

**Ruling: gold is struck from this document, not deferred.** The three zones' Reward columns
(Expeditions → The three zones, below) drop the "Gold, " prefix. This is a scope/clarity call, not
an arithmetic one — reviving gold as a real third currency would be a scope change (a new income
source, a new `BalanceTable`/`GameSession` field, new drop tables) that nothing in the current
design needs, since the two-track requirement the research raises is already met.

**Rejected: give gold an income rate and keep it as a third currency**, per the original `P2-05e`
deferral above. Rejected because nothing downstream of `P2-05e` ever found a use for it — Buildings
(`P2-04`/`P2-07`) settled on parts-only, Enhancement (`P2-05e`/`P2-05f`) settled on parts-only, and
no other cost line in this document has ever named gold. Keeping a currency "deferred" with no
system left that would spend it is worse than removing it: it invites a future ticket to invent a
sink for a currency that exists only because the doc never finished striking it.

**Code follow-up: done (`P2-15`).** `zones/defs/verdant_outskirts.tres`, `ashfall_reaches.tres`,
`sundered_vault.tres` (the `loot_emphasis` field) and `tests/zone_definition_check.gd` (the matching
expected strings) no longer say "Gold, …" — all six literals were synced to the Reward column below.
Nothing in the codebase names gold in any form now.

### Salvage

Breaking an item returns `3 + enhance_level` parts of its rank — roughly half the
investment. Re-gearing is viable but not free.

### Cores — *Phase 4*

Salvaging a rank **A or higher** item always yields one **Core** carrying a rolled unique
effect: lifesteal, on-kill party heal, guaranteed opening crit, and similar.

Cores socket into equipment with free sockets. **Socketing consumes the Core. Unsocketing
destroys it.** No free experimentation — socketing is a commitment.

This is the entire reason to hunt A+ gear you have no intention of wearing.

### Material economy — one rule

**3 parts of rank N convert to 1 part of rank N+1.** At the Forge.

That is the whole system. No per-tier currencies, no conversion matrix, no recipes.

---

## Expeditions — *Phase 2*

`ZoneDefinition`: name, recommended power, wave list, loot table, unlock condition.

Up to 5 heroes. Waves resolve in order; **HP carries forward between waves**. A hero reaching
0 HP is **permanently deleted** — applied in exactly one place (see `ARCHITECTURE.md` rule 8).

`hero_power = ATK + DEF + HP/10 + SPD`, summed across the team. Used for UI warnings and
quick-resolve scaling only. **Never a hard gate** — let players throw units away if they want.

### Team size scaling

`recommended_power` is authored against the 5-hero reference team in Heroes. Nothing said what a
smaller team should face, and `P2-03b` ships with exactly one hero — the only team size that
exists until squad select (`P2-03c`) lands — so the gap stayed silent until it made every
expedition unwinnable: a wave's win check is `team_power * randf() > enemy_power`, and a
one-hero team's power is roughly a fifth of the reference team's while `enemy_power` was still
computed off the full-team `recommended_power`, so most waves demanded `randf()` to exceed values
above `1.0` — arithmetically impossible, not unlucky.

```
effective_enemy_power = wave.enemy_power * (team.size() / 5.0)
```

Applied wherever a `resolve()` implementation compares `wave.enemy_power` against `team_power` —
not inside `Wave` itself, which has no team parameter and isn't getting one (`P2-03a`'s ramp
construction is out of scope for this fix, and the ADR still requires the ramp interpolation to
live in exactly one place). Both combat paths apply the same team-size factor to the same `Wave`
they already receive, so they stay in agreement without `Wave` needing to know about teams.

At `team.size() == 5` this is a no-op (`5/5 = 1.0`) — a full squad's difficulty is unchanged from
today's authored figures. The rule only changes anything for team sizes other than 5, which today
means exactly one case: solo.

**Why linear, not sub-linear.** `hero_power` is already a flat sum across the team with no
formation or synergy bonus (`heroes/hero.gd:54-67`, `compute_team_power`) — difficulty scaling by
anything other than the same linear rule would make the two silently disagree. Linear scaling
also makes per-wave win probability identical at any team size for same-rank/level heroes
(verified below). A full squad still ends up meaningfully stronger in practice, through a route
this rule doesn't need to invent: clearing a zone with 5 heroes takes one successful expedition;
clearing the same headcount solo takes five independent expeditions — five independent
death-exposure rolls instead of one, since a hero at 0 HP is permanently deleted. That's the
incentive to field a squad. A difficulty curve that *also* punishes small teams would double that
incentive and risks re-breaking solo at low ranks, which is the one team size that ships today.

**Rejected: fixed bar regardless of team size.** Today's behavior, and the bug this rule exists
to fix — arithmetically impossible for solo at every zone (verified: Codex thread
`019fc92f-cad5-7b91-91df-7852d0794eef`).

**Rejected: sub-linear scaling**, i.e. a small team facing more than its literal headcount share
of difficulty. Nothing in the `hero_power` model justifies it — there's no synergy term a small
team is failing to benefit from — and it stacks on top of the run-count penalty above, which is
already enough incentive on its own. Stacking both risks making solo unwinnable again at exactly
the rank band (F, low levels) where it's the only option that exists.

**Rejected: leave `enemy_power` fixed and instead change post-win damage distribution per team
size.** Doesn't touch the win/loss check itself, so solo stays arithmetically impossible at the
coin flip regardless of what happens to survivors afterward.

> ⚠️ **PROVISIONAL** — linear team-size scaling is arithmetically verified to restore per-wave
> win probability parity between solo and full-squad play (Codex thread
> `019fc92f-cad5-7b91-91df-7852d0794eef`), but whether that parity *feels* right once `P2-03c`
> ships real squad select — whether solo ever feels like a legitimate choice rather than a
> stopgap — is unplayed. · **Settled by:** `P2-03c` shipping squad select, then a played build
> comparing solo and squad runs at the same rank.

### Combat's level baseline — found verifying the fix above, not requested

Team-size scaling alone does not make any zone winnable. `recommended_power`'s own calibration
(Heroes' checkpoint table: `hero_power` at F/level 10, B/level 40, S/level 60 — each rank's level
cap) assumes a hero computed **at its rank's level cap**. `combat/quick_resolve.gd`'s
`BASELINE_LEVEL = 0` computes every hero at level 0 instead, because no leveling/XP system exists
yet (`P2-04a`) and nothing in this document ever said what level to use in its absence.

Verified (Codex thread `019fc92f-cad5-7b91-91df-7852d0794eef`): at level 0, even a full,
same-rank 5-hero reference team fails **every** wave of Ashfall Reaches and Sundered Vault
outright, and fails Verdant Outskirts' last trash wave and boss — independent of team size, and
independent of the fix above. This is the dominant cause of "unwinnable at every rank," not team
size. Team-size scaling is necessary but was never going to be sufficient by itself.

**Rule, until `P2-04a` ships real leveling:** compute combat stats — quick-resolve and, later,
the arena — at the hero's rank's level cap (the Ranks table's `Level cap` row: F=10, D=20, C=30,
B=40, A=50, S=60, SS=70, SSS=80), not level 0. This is exactly the level the checkpoint table
already assumes, so it costs no rebalance — it makes the implementation match what
`recommended_power` was already calibrated against, rather than inventing new numbers.

**Retired by `P2-04a` (below), not adjusted.** `BASELINE_LEVEL` and the "always compute at the
rank's cap" rule stop applying the moment real leveling ships: `Hero.level_for()` becomes
`clampi(hero.level, 0, balance.level_caps[hero.rank])`, reading the hero's actual, persisted
level instead of deriving a constant from rank. A freshly-summoned hero starts at `level = 0`,
below its rank's cap — see "Hero leveling — XP curve and income" for what that does to
winnability and why it's an accepted, not overlooked, consequence.

With both fixes applied (verified, same thread): solo and full-squad win probability become
identical at every wave, and every trash wave becomes winnable at each zone's calibration rank
for every archetype except Cleric on the Verdant boss (`198` enemy power vs `187` team power — one
archetype, one zone's boss, short by 6%). Ashfall's boss and Sundered's last two trash waves plus
its boss remain arithmetically impossible even for a full, same-rank, *ungeared* squad at the
calibration level — consistent with the recommended-power PROVISIONAL marker below ("real teams
carry gear on top"): bosses in this design are not meant to be beatable by an ungeared reference
team at any size, gear is the intended headroom, not more heroes. That sharpens rather than
resolves that marker — still untested against a played, geared build.

**This is a code change** (`combat/quick_resolve.gd`'s `BASELINE_LEVEL` constant, and whatever
the arena does once `P2b-01` exists), not a doc-only fix — route to `tech-lead`/`implementer`.
Until it lands, the team-size rule above is only a partial fix: it stops solo from being uniquely
broken relative to a full squad, but neither is winnable at level 0.

> ⚠️ **PROVISIONAL** — the rank-cap-level baseline is arithmetically verified to match the
> checkpoint table it's derived from and to restore winnability at the calibration rank for both
> team sizes (Codex thread `019fc92f-cad5-7b91-91df-7852d0794eef`), but it's a placeholder for
> real leveling, not real leveling — nobody has played against it, and `P2-04a`'s actual XP curve
> will replace it outright rather than tune it. · **Settled by:** `P2-04a` shipping the XP curve
> (which retires this rule entirely, not just adjusts it), then a played build.

> ⚠️ **RETIRED by `P2-04a`'s ruling below.** The rank-cap baseline is no longer the rule —
> `Hero.level_for()` reads a real, persisted `hero.level` that starts at 0, not a derived
> constant. This does not close the PROVISIONAL above; it replaces what it was provisional
> *about*. The new open question, carried into the ruling below: a level-0 hero is
> considerably less safe than the rank-cap placeholder ever let it be, and that's now measured
> rather than assumed — see "Hero leveling," bootstrap paragraph.

### Hero leveling — XP curve and income (`P2-04a`)

**Heroes level for real.** Two new `Hero` fields — `level: int = 0` and `xp: int = 0` (progress
toward `level + 1`) — replace the derivation `Hero.level_for()` used to do. **This is a
save-boundary change** (`CLAUDE.md`'s risky-boundary rule 1): `Hero.to_dict`/`from_dict` need
both fields added, and any implementer ticket against this inherits a mandatory `verifier` pass.
`Hero.level_for(hero, balance)` becomes `clampi(hero.level, 0, balance.level_caps[hero.rank])` —
a clamp, not a derivation; the clamp only matters as a corrupt-save guard, since normal play
never lets `hero.level` exceed the current cap (see rank-up, below).

**Rank-up: already settled, not reopened here.** `DECISIONS.md`, 2026-08-01, "Rank-up preserves
hero level": *"Ranking a hero up raises its level cap and keeps its current level and XP... reason:
resetting level on rank-up makes the reward feel like a punishment."* That ADR predates this
ruling and this ruling doesn't touch it — it only had no `hero.level` to act on until now. Verified
here as a cross-check, not a new decision (Codex thread `019fdda9-5327-7a22-823c-fb53c0399d0a`,
question C): carrying `level` forward unchanged makes every one of the seven rank-up transitions a
strict, immediate `hero_power` increase, no exceptions — e.g. an F-cap (level 10) Knight goes
212.0 → 286.2 the instant it becomes D, an SS-cap (level 70) Knight goes 3,678.4 → 4,967.36 the
instant it becomes SSS. Resetting level would have produced the opposite — a real, felt power dip
right after spending the game's most expensive currency — confirming the ADR's own reasoning
arithmetically rather than just by feel. `level_caps` steps by a flat `+10` every rank
(`[10,20,30,40,50,60,70,80]`), so — also verified — every rank-up opens exactly 10 more levels of
climbing room regardless of which rank it is; there's no reason to special-case any transition.

**The XP curve — one global coefficient, not rank-indexed.**

```
xp_to_next_level(level) = xp_coefficient * (level + 1)
```

New `BalanceTable` field: `xp_coefficient: int = 10`. Deliberately **not** a per-rank array like
`essence_bases`: unlike essence (which resets its accounting per sacrifice), `hero.level` is
already a single monotonic number running 0→80 across a hero's whole life — rank-up only raises
the reachable ceiling (above), it doesn't reset the number the cost formula reads. A second,
rank-indexed base would be redundant complexity buying no behavioral difference, since `level`
itself already encodes how far along a hero is. Total XP from level 0 to level `L` is the
triangular number `xp_coefficient * L*(L+1)/2` — climbing all of F (0→10) costs `550` XP.

**Income — per-wave on every outcome, plus a per-zone completion bonus. Deliberately not the same
shape as Summon Stones.**

- **`xp_per_wave: int = 4`** (new `BalanceTable` field) — paid `xp_per_wave * waves_resolved`
  (`Expedition.waves_resolved`, already public, `hub/expedition/expedition.gd:13`) on **every**
  outcome: `OUTCOME_COMPLETED`, `OUTCOME_RETREATED`, and `OUTCOME_DEFEATED` alike. This is
  deliberately more generous than the Stones rule (`P2-09`, `COMPLETED`-only): a fresh, level-0
  hero's completion probability in Verdant is measured at exactly `0%` (below), so a
  `COMPLETED`-only rule would pay a climbing hero nothing for its first several dozen attempts,
  defeating the entire point of a curve that's supposed to be climbed gradually.
- **`xp_reward` per zone** (new `ZoneDefinition` field, same shape as `P2-09`'s `stone_reward`) —
  `Verdant Outskirts: 24, Ashfall Reaches: 72, Sundered Vault: 192`, the same `1:3:8` ratio as
  stones, paid only on `OUTCOME_COMPLETED` (same trigger as `stone_reward` and the loot table).

Verified (Codex thread `019fdda9-5327-7a22-823c-fb53c0399d0a`, question B, exact state-recurrence,
not the coarser per-level estimate): with these constants, a level-0 F-rank hero/team in Verdant
earns `~12.3` expected XP per attempt, climbing to `~19.3` by level 9, and reaching level 10 (F's
cap) takes **`~33.6` expected attempts**. That's the target order of magnitude asked for —
"tens," matching this document's other spine numbers (`~327` pulls to manufacture an SSS, `~264`
clears to max one building) rather than either "one attempt" (pointless curve) or "thousands" (out
of step with everything else here).

**Training Hall's `+15%/level` now has a real consumer**, closing the PROVISIONAL that sat on it
since Base Buildings was written: `effective_xp = base_xp * (1.0 + training_hall_xp_bonus *
building_levels[2])`, applied to both `xp_per_wave` and `xp_reward`, the same per-level-percentage
shape every other building already uses. Verified at cap (level 5, `+75%`): `xp_per_wave` becomes
exactly `7` and `xp_reward` becomes exactly `42/126/336` — no fractional XP at the cap level, and
the climb to F's cap drops to **`~19.5` expected attempts**, a `41.85%` reduction. Meaningful, not
decorative.

**The bootstrap — measured, not assumed, and the honest answer is harsher than "a fresh hero can
clear an easy wave."** Question A of the same Codex thread enumerated the *whole* Verdant run
(not just per-wave win chance) for a same-rank, ungeared, 5-archetype reference team:

| Level | Defeated (whole roster) | Retreated (safe) | Completed |
|---:|---:|---:|---:|
| 0 (fresh summon) | 69.8% | 30.2% | 0% |
| 5 | 55.7% | 44.3% | 0% |
| 10 (F's own cap) | 53.1% | 46.4% | 0.5% |

Two things fall out of this table that the ruling has to say plainly rather than paper over:

1. **A level-0 team's first attempt has no path to `COMPLETED` at all** — it always ends in either
   a full-roster wipe or an automatic retreat, never a clear. Waves 1–2 are survived almost
   always (this is where the per-wave XP income does its job — an early, likely-to-retreat
   attempt still banks real XP); the team typically dies or retreats at trash wave 3.
2. **This lethality is not new and is not this ticket's to fix.** Even at F's own calibration
   level (10) — the level the rank-cap placeholder used for every single fight until this ruling
   — a full run still wipes the roster `53.1%` of the time. That number was always true of
   Verdant's wave-damage formula (`wave_damage_coefficient`/`wave_loss_damage_coefficient`,
   `P2-03b`, already flagged provisional in "Wave damage" below); it was simply never visible
   before, because nobody had enumerated a whole run rather than one wave in isolation. Retuning
   those coefficients is out of scope here — flagging it is not.

Given that, the honest bootstrap answer is: **there is no level at which a fresh F-rank hero is
"safe" in Verdant — that's true today and stays true after this ruling.** What this ruling *does*
guarantee, and what the rank-cap placeholder didn't need to: partial progress is never wasted (a
retreating or even a losing attempt still pays `xp_per_wave` for whatever it survived), and the
existing team-size incentive (`Team size scaling`, above — fielding fewer heroes per attempt
limits how much of a roster is exposed to any one death roll) is the lever a player already has
for managing that risk, not a new one this ruling needs to invent.

**A genuinely new failure state this ruling makes reachable — ruled below, not solved here.**
`P2-09` sizes the starting balance (`300` stones) against the *pull* spine, on the assumption
stones and hero survival are independent. They're less independent than that ruling assumed: a new
save that spends all `300` stones on 3 pulls, then sends every pulled hero into one Verdant
attempt that wipes the roster (measured above at up to `69.8%` per attempt for a level-0 team),
reaches `0` heroes and `<100` stones simultaneously — unable to pull (short of cost) and unable to
expedition (no roster). This didn't exist as a reachable state under the placeholder (every hero
fought at its rank's cap, where completion is still rare but the roster-wipe rate is lower); it
becomes reachable the moment fresh heroes fight at level 0. Not this ruling's numbers to fix (it's
an interaction between `P2-09`'s economy and this one, not a defect in either alone) — filed as
`P2-18` and ruled immediately below.

### Roster-wipe recovery floor (`P2-18`)

**Ruling: when `kill_hero()` leaves `roster` empty and `stones < balance.summon_pull_cost`, top
`stones` up to exactly `balance.summon_pull_cost` — one guaranteed pull, nothing more.** This is
`P2-09`'s own boot-time correctness floor restated for the identical state reached mid-game
instead of at boot: "a starting balance below `100` (one pull's cost) makes the summon button, and
therefore the entire game, unplayable from boot" (Summon Stones § Starting balance, above).
`roster.is_empty()` with fewer than `summon_pull_cost` stones is exactly as unplayable on attempt
40 as on attempt 0 — a fresh save and a wiped save are the same dead state, and this closes it with
the same fix: guarantee one pull is affordable, nothing more. It refunds no essence, no items
(`lost_caches` already exists for the equipped-gear case and is untouched by this), and grants no
extra hero — only the stone balance needed to attempt the single pull a brand-new save already
gets for free.

**Exact inputs for an implementer ticket:**

- **Trigger:** inside `GameSession.kill_hero()` (`systems/game_session.gd:174`), immediately after
  `roster.erase(hero)` — check `roster.is_empty() and stones < balance.summon_pull_cost`.
  `kill_hero()` doesn't take a `balance: BalanceTable` parameter today; both its existing call
  sites (`expedition.gd:64`, and `sacrifice_hero()` internally) already hold one in scope, so this
  is a signature change threading an existing value through, not a new dependency.
- **Effect:** `stones = balance.summon_pull_cost` — an assignment, not `+=`. There is nothing to
  add to: the guard only fires when `stones` is already below `summon_pull_cost`. Read
  `balance.summon_pull_cost` live rather than inlining `100`, so a future balance change can't
  strand this check silently out of sync.
- **Also apply on load**, in `GameSession.from_dict()` after `roster`/`stones` are populated: same
  condition, same effect. This rescues a save file that already reached the terminal state (one
  saved before this ships, for instance) rather than only guarding it going forward. This second
  site is not roster mutation, so `ARCHITECTURE.md` r8 — `kill_hero()` as the sole roster-*removal*
  call site — doesn't apply to it; nothing here adds or removes a hero.
- **Scope, precisely:** a wipe that leaves `stones >= summon_pull_cost` (the player kept a reserve)
  is untouched — they were never stuck. A non-empty roster sitting on few stones is untouched —
  they can still expedition for more. Only the exact conjunction `P2-18` names is touched, so no
  live save with a legal move available is ever altered.
- **What the player sees: nothing new.** The stones display already reacts to any `stones` change
  through `roster_changed` — the same signal `credit_stones()` emits today with no dedicated
  message — so this top-up surfaces the same way a zone-clear stone reward already does. No
  toast/notification system exists anywhere in this codebase (checked); building one for an edge
  case a player hits at most once is a disproportionate addition, not a requirement of this ruling.
  If a played build shows the balance jump reads as a bug rather than a recovery, that's a
  UI-feedback ticket to open then, not a reason to withhold the floor now.
- **Never reachable from `sacrifice_hero()`.** It requires `fodder != target` and both already
  roster members, so `roster` always still holds `target` after its `kill_hero()` call — sacrifice
  can never itself empty the roster. This guard can only ever fire from the combat-wipe path
  (`expedition.gd:64`, the `dead_heroes` loop).

**Rejected: a hero-count floor (`roster` cannot drop below `N`).** Not a currency patch — a
redefinition of what permadeath means, for every roster at size `N`, not only the one save that's
actually stuck. It requires `kill_hero()` (or the resolver feeding it) to sometimes not apply a
death combat already decided, which makes the last hero's death cheaper than every other hero's —
backwards for a game whose spine is "deciding whose life to spend is uncomfortable"
(`GAME_SPEC.md`). It also doesn't fit `kill_hero()`'s contract cleanly: a `defeated` `CombatResult`
whose `dead_heroes` includes the last hero would need that hero spared at 0 HP with no heal, a
second mechanic this ticket doesn't otherwise need.

**Rejected: refusing to let the last pull-worth of stones be spent.** Read as an unconditional
floor (`summon_hero()` refuses whenever `stones - cost < summon_pull_cost`), the reserved `100`
becomes permanently unspendable the moment the player has no surviving hero left to earn more —
the identical dead end `P2-18` names, only relabeled from "stones `<100`, can't pull" to "stones
`=100`, the rule won't let it be spent." It doesn't terminate the failure state, it renames it.
Read instead as a conditional exception — block spending below `100` *except* when it's the
player's only path back to a hero — it collapses into the recovery floor above, just implemented
as *never let stones drop* (a guard on every `summon_hero()` call, forever) rather than *top back
up only in the dead state* (a guard on the one path that can empty the roster). Same outcome, more
standing code. Rejected for that reason, not a different verdict on the state itself.

**Rejected: ship nothing; teach "field one hero at a time early."** Teaches nothing the game
currently shows — no tutorial, no tooltip, no in-fiction signal that fielding fewer heroes
protects the *stone balance* specifically, as opposed to the roster (which is the lesson the
retreat threshold and team-size scaling already teach, for a different reason). Spending all `300`
on 3 pulls before a first expedition is a legible reading of "gacha game, empty roster, currency
exists to fill it," not a misplay — and it hits a true dead end with no signal beforehand and no
recovery after. Costing nothing to ship is not the same as costing nothing to hit.

> ⚠️ **PROVISIONAL** — the trigger condition and the top-up amount are arithmetically exact (they
> reuse `P2-09`'s own boot-floor number rather than inventing one), but whether a silent stones
> top-up reads as a fair recovery or as the game quietly undoing a death's consequence is a feel
> question only a played wipe can answer. · **Settled by:** a played build reaching this state at
> least once — does the top-up read as "the game caught me" or as "that wasn't really permadeath"?

**A pre-existing spec/code mismatch this ruling surfaces, not caused.** The Sacrifice formula box
at the top of this document's "Sacrifice → rank up" section reads
`yield = essence_base[fodder.rank] * (1.0 + fodder.level / level_cap[fodder.rank])` — a
level-scaled essence bonus. `Hero.compute_essence_yield()` (`heroes/hero.gd:130-142`) has never
implemented that term; it couldn't, since `fodder.level` had no backing field before this ruling.
Now that `hero.level` is real, the mismatch is live rather than moot: either wire the bonus in (a
code change) or strike the term from the formula box as never-shipped. Not this ruling's call —
flagging for `tech-lead` to route as a small follow-up, since it's a Sacrifice-formula question,
not an XP-curve one.

**Where every number lives.**

| Number | File | Notes |
|---|---|---|
| `level: int = 0`, `xp: int = 0` | `Hero` | New fields. Save-boundary change — `to_dict`/`from_dict` both need it, mandatory `verifier` pass. |
| `xp_coefficient: int = 10` | `BalanceTable`/`balance.tres` | New field. Single global constant — not rank-indexed (see above). |
| `xp_per_wave: int = 4` | `BalanceTable`/`balance.tres` | New field. Paid × `waves_resolved` on every outcome. |
| `xp_reward` (`24`/`72`/`192`) | `ZoneDefinition` (→ `zones/defs/*.tres`) | New field, same shape as `P2-09`'s `stone_reward`. `COMPLETED`-only. |
| `Hero.level_for()` | `heroes/hero.gd:33-34` | Changes from a derivation to a clamp: `clampi(hero.level, 0, balance.level_caps[hero.rank])`. |
| `BASELINE_LEVEL` | `combat/quick_resolve.gd` | Retired outright — removed, not tuned (per "Combat's level baseline," above). |
| XP overflow at cap | — | Discarded, not banked. Same simplicity precedent as "no pity system" — no ruling anywhere in this document banks overflow on any other currency either. |

This is the shape a follow-up implementer ticket needs, same footing as `P2-09`'s own closing
table; writing that ticket body is `tech-lead`'s call. Flagging for that ticket: `GameSession`
needs an XP-grant path mirroring `credit_stones()`'s shape (apply the Training Hall multiplier,
then loop level-ups while `xp >= xp_to_next_level(level)` and `level < balance.level_caps[rank]`,
discarding overflow at cap) — called from wherever `Expedition.resolve()` returns, alongside the
existing `credit_stones()` call.

**Rejected: a rank-indexed `xp_base` array mirroring `essence_bases`.** Considered and dropped —
see above, `level`'s own value already encodes rank progress since it never resets, so a second
per-rank array would change no arithmetic, only add a table nobody reads differently.

**Rejected: XP paid only on `OUTCOME_COMPLETED`, mirroring Stones exactly.** Rejected because
completion probability at level 0 is measured at exactly `0%` (above) — a hero climbing from
level 0 would earn nothing for its first several dozen attempts under that rule, which is the
opposite of a gradual curve.

**Rejected: a non-zero starting level (e.g. half of the rank's cap) to soften the bootstrap.**
This was the first draft of this ruling, dropped once per-wave income was modeled: waves 1–2 are
survived almost unconditionally even at level 0 (question A), so a level-0 start already earns
real XP from its very first attempt without an invented starting number — adding one would solve
a problem the per-wave rule already closes.

**Rejected: retuning `wave_damage_coefficient`/`wave_loss_damage_coefficient` to soften the
`53–70%` whole-run defeat rate found above.** Out of scope for an XP-curve ticket — those
coefficients are `P2-03b`'s, already flagged provisional in "Wave damage" below, and changing them
here would be re-litigating combat balance under cover of a leveling ticket.

> ⚠️ **PROVISIONAL** — the curve, the income constants, and the `~33.6`/`~19.5`-attempt spine
> numbers are arithmetically verified against every existing spine number in this document (Codex
> thread `019fdda9-5327-7a22-823c-fb53c0399d0a`) but entirely unfelt: nobody has leveled a hero
> against a built XP bar, and whether losing heroes mid-climb (measured as the dominant outcome,
> not an edge case) reads as "the game's whole point" or "leveling is pointless, they die before
> it matters" is a feel question this document cannot answer alone. · **Settled by:** a played
> build with XP wired in, across enough attempts in Verdant to see whether a climbing hero
> functionally ever reaches F's cap before dying, or whether in practice almost none do.

### Wave damage

The rule above (team-size scaling) and the one before it (level baseline) fix whether a wave can
be *won*. Neither says what a won wave *costs*. The rule that shipped with `P2-03b` was an
implementer's placeholder, never a design decision:

```
damage_fraction = effective_enemy_power / team_power
hp_after = maximum_hp * (1.0 - damage_fraction)
```

This charges a **fixed fraction of max HP equal to the wave's raw power ratio**, win or lose how
narrowly. Since `recommended_power` is pinned to the reference team's `hero_power` (Heroes,
above), that ratio tracks the zone's authored ramp fraction almost exactly at calibration rank —
Verdant Outskirts' five trash waves (50%→90% of RP) sum to `0.5+0.6+0.7+0.8+0.9 ≈ 2.97×` max HP
before the boss is even reached. A hero can win *every single wave* and still be mathematically
guaranteed to die partway through trash. No zone clear exists at any rank — the game has a
success path (`OUTCOME_COMPLETED`) that plain arithmetic proves unreachable.

**New rule:**

```
r = effective_enemy_power / team_power        # same r the win check already uses
damage_fraction = clamp(0.35 * r^3, 0.0, 1.0)
```

`r` is exactly the value already computed for the win/loss check (`combat/quick_resolve.gd`),
post team-size scaling — no new input, no current-HP dependency, so it fits the stateless seam
(`resolve(team, wave) -> CombatResult`) unchanged and is identical to derive in a future arena
implementation, since it only needs `effective_enemy_power` and `team_power`, both of which the
arena must already compute to run the same win condition.

**Why cubic, not linear or quadratic.** A wave a hero can comfortably beat should barely scratch
it; a wave that's a near-even fight should hurt. Cubing sharpens that gap far more than the
alternatives at the same target margin — at Verdant calibration (5-hero reference team), the
first trash wave (`r≈0.43`) costs `2.8%` max HP under the cubic rule versus `8.6%` under a
linear rule tuned to hit the same zone-clear total, and the ramp's hardest wave (the boss,
`r≈0.95`) costs `29.6%` versus `18.9%` — roughly a `10.6×` spread cubic vs. `2.2×` linear between
the ramp's easiest and hardest hits. Linear compression makes every wave cost *roughly the same*
regardless of where it sits on the ramp, which erases the ramp's own point (waves are authored to
get harder). Cubic keeps that shape while still landing in a survivable total.

**Verified (Codex thread `019fc9fc-1c10-7a40-aa8e-90640c1d3911`, checkpoints recomputed
independently from base/growth/rank data, not trusted from this document):**

| Case (Verdant, calibration = F/lvl10) | Team power | Cumulative damage, full clear (5 trash + boss) | HP remaining |
|---|---:|---:|---:|
| 5-hero reference team | 1,046.50 | 0.7249 | 27.5% |
| Knight solo | 212.00 | 0.6975 | 30.3% |
| Rogue solo | 229.50 | 0.5498 | 45.0% |
| Ranger solo | 211.00 | 0.7075 | 29.3% |
| Mage solo | 207.00 | 0.7493 | 25.1% |
| Cleric solo (trash only) | 187.00 | 0.6009 | 39.9% |

A full zone clear is now arithmetically reachable — not guaranteed (the win/loss coin flip is
still the gate on each wave, unchanged by this ticket), but a hero who wins every roll survives
with real margin instead of being dead by construction. Cleric solo still cannot win the Verdant
boss at all (`r=1.0588` — the win check itself fails, `6%` short) — pre-existing, called out
already, and unrelated to the damage rule; trash-only Cleric solo survives comfortably (39.9%
remaining) up to that wall.

**Team-size parity holds exactly**, as it must (Team size scaling above claims per-wave win
probability parity; this rule must not silently break it). Verdant boss, Knight archetype:
solo `r = 198/212 = 0.933962…`, five Knights `r = 990/1060 = 0.933962…` — identical `r`, so
identical `damage_fraction = 0.285139` both ways.

**Retreat is not reachable in the only configuration that exists today** (solo, Verdant
Outskirts, any rank F–SSS — squad select is unbuilt (`P2-03c`) and every other zone is locked
behind a Verdant clear, so nothing else is constructible yet). An earlier draft of this section
claimed retreat was proven reachable using a 5-hero mixed-rank Ashfall roster; that roster cannot
be built by the game that ships today, so it does not stand as proof of criterion 3. Corrected —
see **Retreat threshold**, below, for the full accounting: this rule's own arithmetic, swept
exhaustively across all 40 archetype/rank combinations and 200 trash checkpoints in solo Verdant,
never crosses the 25% line. That mixed-rank Ashfall example is kept there, relabeled honestly, as
evidence retreat *will* be reachable once squad select and the Ashfall unlock exist — not as
evidence for today.

**Death remains reachable today**, and not only through attrition. F Cleric solo can win all
five Verdant trash waves (ending at 39.9% HP, per the table above) and then face the boss at
`r = 198/187 = 1.0588` — a guaranteed loss (`r≥1` makes the win check unsatisfiable, independent
of this damage rule) that wipes the team outright regardless of remaining HP. That is a real,
buildable-today death path: clear every trash wave, survive with margin, still permadeath at the
boss. Attrition-driven death (cumulative damage reaching 1.0 across multiple *won* waves, without
ever hitting a guaranteed-loss wave) is a separate, real failure mode this rule also produces —
demonstrated below with the same Ashfall example, again honestly labeled as future-reachable
rather than proof for today, since it needs the same unbuilt squad select and zone unlock.

**A new finding, not requested but surfaced verifying this rule:** the same arithmetic run
against Ashfall Reaches and Sundered Vault at *their own* calibration ranks shows their reference
teams cannot survive attrition through trash even winning every roll — Ashfall's reference team
dies on trash wave 6 (before ever reaching its already-known-unwinnable boss); Sundered's
reference team is forced to retreat on trash wave 5. Every individual wave up to that point is
still winnable in isolation (`r<1`); it is the *stack* of six-to-seven near-parity wins in a row
that exceeds the HP budget, same shape as the original Verdant bug, just not fully absorbed by a
constant tuned against Verdant alone. This sharpens rather than contradicts the existing
recommended-power finding below ("bosses are not meant to be beatable by an ungeared reference
team… gear is the intended headroom") — it extends that same reasoning from "the boss" to "the
back half of trash, too," for the two harder zones. Retuning `0.35` upward would fix Ashfall/
Sundered but push Verdant's total damage down toward risk-free (see rejected alternatives), and
tuning it down loses attrition-death reachability entirely (below `k≈0.25`, no wave can ever
chain enough damage to kill before the 25% retreat line intervenes first). One constant cannot
serve a zone meant to be an ungeared-clearable tutorial and two zones meant to demand gear
progression from that tutorial's loot — this is not a defect in the formula, it is what "each
zone covers a wide rank band" (The three zones, below) already implies, made concrete.

**Rejected: linear (`p=1`).** At a `k` tuned to the same Verdant-clear target (`k≈0.20`, sum
`0.7912`), every wave costs a similar proportion of the total regardless of where it sits on the
ramp — a `2.2×` spread between the easiest and hardest wave versus cubic's `10.6×`. Flattens the
ramp's own difficulty curve into near-uniform cost per wave, which undercuts the reason the ramp
is authored as a ramp at all.

**Rejected: quadratic (`p=2`).** Sits between linear and cubic on both the differentiation
question and the reachability tuning — `k≈0.22` lands Verdant reference-team damage at `0.6118`,
survivable but with less separation between "comfortable win" and "nail-biter" than cubic gives
at a comparable margin. No numeric defect, just a weaker fit to the "cheap when easy, expensive
when close" feel than cubic at the same target total.

**Rejected: tie damage magnitude to the win-check's own `randf()` roll** (e.g.
`damage_fraction = r / roll` for the roll that decided the win), so a narrowly-won fight costs
more than a comfortably-won one at the *same* `r`. Mathematically sound and even more textured,
but not portable to the arena: a live, player-controlled fight (`P2b-01`) has no single scalar
"roll" to hand back symmetrically with quick-resolve's coin flip, and the combat seam requires
both paths produce comparable results from the same `(team, wave)` inputs. A pure function of
`r` alone is derivable by both; a formula keyed to quick-resolve's internal RNG draw is not.

**Rejected: leave `recommended_power` or the wave ramp fractions untouched but change the
*shape* of team_power/enemy_power comparison itself** (e.g. non-linear enemy scaling). Out of
this ticket's bounds — the win/loss check is settled, and reshaping it risks re-breaking the
team-size parity the previous ticket just established. This ticket is about what a *won* wave
costs, not whether it's won.

**Implementation note.** This is a code change to `combat/quick_resolve.gd`'s post-win branch
(lines 41-45 today), not a doc-only fix — route to `tech-lead`/`implementer`. It needs **one new
balance constant** — a `wave_damage_coefficient: float = 0.35` field, following the pattern of
every other tunable number in this document living in `balance.tres`. The cubic exponent is a
formula-shape choice, not a tunable magnitude — same footing as the team-size rule's `/5.0`,
which is written into the rule rather than authored as data. **No zone `.tres` value needs to
change** — `recommended_power` and the wave ramp fractions (`trash_wave_start_fraction`,
`trash_wave_end_fraction`, `boss_fraction`) are untouched; only the post-win damage formula in
code changes.

> ⚠️ **PROVISIONAL** — `0.35` is arithmetically the best-fitting constant found for making Verdant
> clearable with real (not trivial) margin while keeping retreat and death reachable elsewhere,
> but it was solved for Verdant specifically and knowingly leaves Ashfall and Sundered
> attrition-gated through trash, not just at the boss (see finding above). Nobody has played a
> single wave against this number. · **Settled by:** a played build at Verdant calibration rank to
> feel whether 27.5% margin on a full clear is "close" or "coasting," which is the actual
> question a constant can't answer by itself — then a decision on whether Ashfall/Sundered are
> meant to stay attrition-gated through late trash pre-gear (consistent with the existing
> boss-headroom reasoning) or need their own ramp/RP retuning, which is a separate pass.

### Lost-wave damage

`P2-03d`'s per-wave damage model fixed what a *won* wave costs. It didn't touch what a *lost* one
costs, because that branch was out of that ticket's bounds. Before this rule, a lost wave was an
instant, unconditional full-team wipe — `hp_after = 0.0` for every hero, regardless of `r`. That
was an implementer placeholder, not a decision, and it had a real consequence proven exhaustively
under Retreat threshold below: HP could only erode through *won* waves, and won-wave damage is
capped specifically to keep a clear survivable, so nothing buildable could ever cross the 25%
retreat line. `RETREATED` was dead code in the only configuration the game can build.

**Shipped in `P2-03f` (`a412c4a`)** — the rule below is what the code does now, not a proposal.

**Ruling: replace the instant wipe with graduated damage, same shape as the win rule.**

```
r = effective_enemy_power / team_power        # the same r, unchanged
damage_fraction_loss = clamp(1.0 * r^3, 0.0, 1.0)
```

Applied exactly the way the win rule already is: `hp_after = maximum_hp * (1.0 - damage_fraction_loss)`,
fed into the *same* Expedition pipeline that already runs after a won wave
(`hub/expedition/expedition.gd:38-57`) — subtract the delta from current HP, check for death
(`current_hp <= 0`), check for retreat (party fraction `<= 0.25`, trash waves only), otherwise
continue. `QuickResolve` still takes no current-HP input and stays a pure function of
`(team, wave)` — the combat seam does not move.

**Why the coefficient is `1.0`, not tuned by feel.** `1.0` is the *minimum* value for which a
mathematically-unwinnable wave (`r >= 1`, the win check is unsatisfiable regardless of the roll)
still clamps to `100%` damage — i.e., a guaranteed loss can still kill a full-health team outright,
which is what "guaranteed loss" already meant under the old instant-wipe branch and what F Cleric's
boss death (below, and already documented under Wave damage) depends on. Below `1.0` that
guarantee breaks: verified at `L=0.7`, F Cleric's guaranteed-loss boss (`r=198/187=1.058824`) deals
only `83.09%` damage — survivable even at full HP, which contradicts calling it a guaranteed loss
with real stakes. `1.0` is the smallest constant that doesn't break that property, so nothing larger
is doing useful work at `r>=1` (already clamped) and nothing smaller is honest about what
"guaranteed loss" means.

**No fifth outcome needed.** This answers the ticket's second question directly: the run does not
gain a new state. `Expedition.resolve()` already re-derives death and retreat from cumulative
`current_hp` after *every* wave, win or lose (`hub/expedition/expedition.gd:44-55`) — it has never
branched on whether a wave was won. Folding the loss branch into the same damage-then-check
pipeline the win branch already uses means `OUTCOME_COMPLETED` / `OUTCOME_RETREATED` /
`OUTCOME_DEFEATED` / `OUTCOME_INVALID_TEAM` (`hub/expedition/expedition.gd:6-9`) cover the ruling
unchanged. What does change: `CombatResult.dead_heroes`/`survivors`/`hp_after` currently assume
"lost the wave" means "dead" (`combat/quick_resolve.gd:35-39`); a graduated loss needs the same
survivor/hp_after bookkeeping the win branch already does, not the old unconditional dead_heroes
fill. `tests/unit/test_expedition.gd`'s `result.dead_heroes.is_empty()` win/loss proxy breaks for
the same reason — already flagged in `docs/TASKS.md`'s `P2-03f` line; this confirms it's real, not
speculative.

**Verified (Codex thread `019fce28-66c9-7412-a07c-45327b3f2d9c`, recomputed independently from
`heroes/defs/*.tres`, `balance.tres`, `zones/defs/verdant_outskirts.tres`, `heroes/hero.gd`,
`zones/wave.gd` — not trusted from this document or the prior thread):**

*Retreat reachability, exhaustive sweep* — all `2^5 = 32` win/loss sequences across Verdant's 5
trash waves, all 40 archetype/rank combinations, `L=1.0`:

| Archetype/rank | Shortest sequence reaching `(0%, 25%]` | HP at that checkpoint |
|---|---|---:|
| Knight F | `LWWWL` (wave 5) | 24.78% |
| Rogue F | `LWWLL` (wave 5) | 24.66% |
| Ranger F | `LWWWL` (wave 5) | 23.71% |
| Mage F | `LLLL` (wave 4) | 21.36% |
| Cleric F | `WLWL` (wave 4) | 20.46% |
| All D–SSS, all 5 archetypes (35 combos) | none | — |

`RETREATED` is reachable — for the first time in a buildable-today configuration — but only at F
rank: all 5 F archetypes reach it via some real win/loss sequence, and every D-through-SSS combo
(35 of 40) does not, at any `L` tested (`0.7`, `1.0`, `1.5` all produce the same F-only footprint).
This isn't a shortfall of the constant — it's the same fact Retreat threshold already established
about the *win* branch: F is "the only rank where Verdant's ramp is even a fight," because
`recommended_power` is fixed at 900 while a hero's own power grows geometrically with rank
(Ranks, above). A loss branch that scales with the same `r` inherits the same rank ceiling the win
branch already has; it couldn't do otherwise without decoupling from `r` entirely, which the
combat-seam constraint (pure function of `team, wave`) rules out.

*Win-only clear numbers, reproduced from real data, unchanged* (this rule only touches the loss
branch):

| Case | Team power | Full-clear win damage | HP remaining |
|---|---:|---:|---:|
| 5-hero reference team | 1,046.50 | 0.724874 | 27.51% |
| Knight solo | 212.00 | 0.697529 | 30.25% |
| Rogue solo | 229.50 | 0.549822 | 45.02% |
| Ranger solo | 211.00 | 0.707494 | 29.25% |
| Mage solo | 207.00 | 0.749305 | 25.07% |
| Cleric solo (trash only) | 187.00 | 0.600885 | 39.91% |

Matches the Wave damage table above to shown precision — Verdant stays clearable with the same
27.5%/30.3%/45.0%/29.3%/25.1% margins; F Mage's one-point-from-unreachable margin is untouched.

*Team-size parity, reproduced* — Verdant boss, Knight archetype: solo `r = 198/212 = 0.933962`,
five Knights `r = 990/1060 = 0.933962` — identical, so identical `damage_fraction_loss =
0.814682` either way (same property the win rule already had; this rule inherits it for free by
also being a pure function of `r`).

*Guaranteed-loss-is-fatal, reproduced* — F Cleric vs. Verdant boss, `r = 198/187 = 1.058824`:
`clamp(1.0 * r^3, 0, 1) = clamp(1.187055, 0, 1) = 1.0`. Still fatal at full HP, same as the old
instant-wipe branch produced for this case — the death path Wave damage already documented
(clear every trash wave, still permadeath at the boss) is unchanged by this ruling.

**A death path this ruling adds, not present before:** because losses now erode HP gradually
instead of always wiping instantly, a chain of unlucky *non-guaranteed* losses in trash (every
`r<1`, so individually winnable) can now also drive `current_hp` to `0` without ever hitting a
guaranteed-loss wave — e.g. two bad rolls compounding on top of partial win damage. This doesn't
need a new outcome: `OUTCOME_DEFEATED` already covers `current_hp <= 0` regardless of source
(`hub/expedition/expedition.gd:45-46`). It's a new *route* to an existing state, not a new state,
and it sits alongside the two death routes Wave damage already named (guaranteed-loss-wave death,
and won-wave attrition once Ashfall/Sundered rosters exist).

**Rejected: `L=0.7`.** Reaches fewer combos (`4/40` vs. `1.0`'s `5/40` — Ranger F does not reach
retreat at this coefficient) and, more importantly, breaks the guaranteed-loss-is-fatal property
this ruling is built around: F Cleric's guaranteed-loss boss only deals `83.09%` damage at `L=0.7`,
survivable at full HP. A "guaranteed loss" that a full-health team can walk away from isn't
guaranteed to cost anything in particular, which undercuts the whole reason `r>=1` is called a
guaranteed loss rather than just a hard fight.

**Rejected: `L=1.5`.** Reaches the identical `5/40` combos `1.0` does — no additional reachability
bought — just via shorter sequences and earlier, lower checkpoints (e.g. Cleric F reaches
`(0%,25%]` in 3 waves at `21.32%` instead of 4 waves at `20.46%`). Same logic that picked `1.0` as
the minimum sufficient value applies here in reverse: `1.5` spends extra severity on near-miss
losses (`r<1`) without unlocking anything `1.0` doesn't already unlock, since `r>=1` is clamped to
`1.0` either way. Punishing losses further than the minimum the guaranteed-loss property requires
isn't free — it just means every non-fatal loss along the way hurts more for no stated reason.

**Rejected: a different curve shape for the loss branch (linear/quadratic in `r`, or an
RNG-keyed magnitude).** Same reasoning as Wave damage's own rejections of these, inherited rather
than re-argued: a non-cubic loss curve would flatten the same "cheap when the mismatch is small,
expensive when it's not" differentiation cubic buys for wins, and an RNG-keyed magnitude (e.g. tying
loss severity to how badly the `randf()` roll missed) isn't portable to the arena for the same
reason given there — no single scalar roll exists on a player-controlled fight, and the combat seam
requires both paths derive the same result from `(team, wave)` alone.

**Rejected: leave the instant wipe and wait for `P2-03c`.** This is the alternative `docs/TASKS.md`
named as this ticket's other exit and explicitly did not take: `P2-03c` only builds the mixed-rank
rosters that let the *existing* threshold fire in Ashfall/Sundered — it masks the symptom (no
buildable-today roster to trigger retreat) without touching the cause (the branch that makes
retreat unreachable by construction wherever it's tried). The win/loss branch is reachable and
provably broken in solo Verdant today, with no squad-select dependency, so ruling on it now means
`P2-03c` inherits correct win/loss semantics instead of building mixed rosters on top of a branch
that still needs fixing later.

**Implementation note.** Code change to `combat/quick_resolve.gd`'s loss branch (lines 35-39
today) plus `CombatResult` population on that path — route to `tech-lead`/`implementer`
(`P2-03f`). One new balance constant, following `wave_damage_coefficient`'s pattern: a
`wave_loss_damage_coefficient: float = 1.0` field in `BalanceTable`/`balance.tres`. The cubic
exponent stays a formula-shape choice written into the rule, same footing as the win rule's own
exponent. No `Expedition` outcome-state change and no zone `.tres` change. `Expedition`'s existing
death/retreat checks (`hub/expedition/expedition.gd:44-55`) need no edit — they already run
identically regardless of which branch produced the HP delta; only `CombatResult`'s
survivor/dead_heroes bookkeeping on the loss path needs to match the win path's shape, and
`tests/unit/test_expedition.gd`'s win/loss proxy (named above) needs a replacement that doesn't
assume loss implies death.

> ⚠️ **PROVISIONAL** — `1.0` is arithmetically the minimum coefficient that keeps the
> guaranteed-loss-is-fatal property intact, and it's verified to make `RETREATED` reachable for
> every F-rank solo Verdant archetype without re-breaking the Wave damage clear margins or
> team-size parity. Nobody has played a single lost wave against this number, and the reachable
> footprint is narrow by construction (F rank only — D and above never reach it, at any tested
> coefficient, because Verdant's fixed 900 RP falls behind rank-scaled hero power past F).
> · **Settled by:** a played build at F rank to feel whether losing a wave for roughly `2.9×` a
> win's damage at the same `r` (`1.0` vs. `0.35`) reads as a real, felt gamble or as an arbitrary
> tax — the same "close vs. coasting" question Wave damage's own constant is waiting on — and
> separately, `P2-03c` shipping mixed-rank rosters plus the Ashfall/Sundered unlock, which is what
> widens `RETREATED`'s reachable footprint past F-rank Verdant rather than this coefficient.
> **`P2-03c` has since shipped (`85caa66`)**, so that half of the condition is met — but the wider
> footprint is still *predicted*, not measured: no sweep has been run against the shipped
> multi-hero path in Ashfall or Sundered. The F-only result above remains the only verified one.

### The three zones

Three zones carry the entire F→SSS span, so each one covers a wide rank band rather than a
single rank. Recommended power is pinned to the ungeared 5-hero reference team from the Heroes
section (real teams carry gear on top, so "recommended" sits at or slightly below what a
same-rank team already has in base kit alone):

| Zone | Unlock | Recommended power | Waves | Loot emphasis |
|---|---|---|---|---|
| Verdant Outskirts | Available from start | 900 | 5 trash (50%→90% of RP) + 1 boss (110% RP) | F–C parts, light Summon Stones |
| Ashfall Reaches | Clear Verdant Outskirts | 4,800 | 6 trash (50%→100% RP) + 1 boss (120% RP) | C–A parts, moderate Summon Stones, first A+ drops |
| Sundered Vault | Clear Ashfall Reaches | 11,500 | 7 trash (60%→110% RP) + 1 boss (130% RP) | S–SSS parts, heavy Summon Stones, best A+ drop rate |

A wave's "contents" here is a single `enemy_power` scalar (a fraction of the zone's recommended
power, from the ramp above) that quick_resolve compares statistically against the team's
`hero_power` — not a bestiary of named enemies with individual stat lines. Authoring actual
enemy species and their stat blocks is its own follow-up ticket; nothing in P2-01 or P2-03
depends on it existing yet, and inventing one here would be scope creep past what this pass was
asked for.

> ⚠️ **PROVISIONAL** — the recommended power figures (900 / 4,800 / 11,500) are derived from the
> ungeared reference team in Heroes, not from any fought wave. Whether "recommended" actually
> predicts a fair fight once `quick_resolve`'s statistical comparison and real gear are both in
> play is untested. Sharpened by the Team size scaling arithmetic above: it is not just untested,
> it is arithmetically impossible for an ungeared reference team of any size to beat Ashfall's
> boss (`1.2×RP`) or Sundered's last two trash waves and boss (`1.0167×`/`1.1×`/`1.3×RP`) at their
> calibration rank — the team-power deficit is 20%+ in places. That may be intentional
> boss-needs-gear headroom rather than a bug, but nobody has fought it with real gear to confirm.
> Sharpened by the Wave damage arithmetic above: it isn't only the boss — Ashfall's and Sundered's
> reference teams die or retreat to cumulative trash attrition before even reaching their
> (separately unwinnable) boss, even winning every individual roll. Every trash wave stays
> individually winnable; it's the stack of six-to-seven near-parity wins in a row that exceeds the
> HP budget. Consistent with "gear is the intended headroom," just extended further into the zone
> than previously shown. · **Settled by:** both combat paths existing and a played build against
> them, with real gear equipped.

### Retreat threshold

Each expedition carries a retreat threshold, default: bail at 25% party HP.

Three lines of code. It converts permadeath from something that happens *to* the player into
something they gambled on, which is the difference between the mechanic feeling unfair and
feeling tense — that's the intent, and it's real in the zones where a mixed-rank team can be
under-ranked for what it's facing (verified above: a concrete Ashfall roster retreats at 13.1%
HP, another dies by attrition on trash wave 6 — both real outcomes of the Wave damage rule, once
squad select and the Ashfall unlock exist to build those rosters).

**Historical finding, now superseded below:** under the old instant-wipe loss branch, this
threshold had no trigger in the only configuration the game could build. Solo, Verdant Outskirts,
any rank F through SSS — swept exhaustively (Codex thread `019fc9fc-1c10-7a40-aa8e-90640c1d3911`,
second pass): 40 archetype/rank combinations, 200 trash-wave checkpoints, zero crossings of the
25% line. The closest was F Cleric after the last trash wave, at 39.9% remaining. Every rank above
F collapsed toward negligible damage almost immediately, because Verdant's `recommended_power` is
fixed at 900 while a hero's own power grows geometrically with rank (`×1.35` per rank, Ranks
above) — F was the only rank where Verdant's ramp was even a fight.

**Why it was dormant:** a lost wave was an instant, full-team wipe (`combat/quick_resolve.gd` —
`won == false` set every hero's `hp_after` to `0.0`), not graduated damage. HP could therefore
only erode through *won* waves, and a won wave's damage is capped by `0.35 * r^3` — capped there
specifically because Verdant's own clear has to stay survivable (Wave damage, above). Those two
constraints both had to hold at once: the only erosion pathway available to retreat was the same
pathway that has to stay cheap enough for a clear to exist. At Verdant's specific ramp (5 waves,
tops out at `r=0.9` for trash), that left every archetype short of 25% cumulative damage by
construction.

**Resolved by `P2-03e` (Lost-wave damage, above).** The loss branch is no longer an instant wipe —
it's graduated damage on the same `r`, coefficient `1.0`. That gives retreat a second erosion
pathway independent of the win-branch's clear-reachability budget, and it's now reachable: all 5
F-rank solo-Verdant archetypes reach `(0%, 25%]` via some real win/loss sequence (table above,
Codex thread `019fce28-66c9-7412-a07c-45327b3f2d9c`). It stays unreachable at D rank and above,
for the same structural reason it was unreachable everywhere before — Verdant's fixed 900 RP falls
behind rank-scaled hero power past F, so there's no fight left for either branch to erode HP in.
That's not a shortfall of this fix; it's the pre-existing rank-vs-RP mismatch showing through
unchanged.

**The two rejections below predate `P2-03e`'s ruling and are kept as the record of why tuning
existing constants alone couldn't fix this** — they're still individually correct, just no longer
the live question now that the loss branch itself changed (Lost-wave damage, above).

**Rejected: raise `0.35`.** Already explored under Wave damage — F Mage sits at 25.1% remaining
after a full clear, one point of margin from becoming the *first* archetype for whom the clear
itself stops being reachable. Pushing `0.35` up to buy retreat headroom for the worst case spends
the exact margin criterion 2 (a clear must be reachable) was tuned to protect. This would trade
one dead mechanic for the other, which is precisely what this ticket's acceptance criteria warn
against.

**Rejected: raise the 25% threshold to catch F Cleric specifically.** The
closest miss (F Cleric, 39.9% remaining) is real, so a threshold somewhere in `(39.9%, 62.7%]`
would catch it — but the sweep shows every threshold below `62.7%` remaining can only ever
fire at the *last* trash checkpoint (wave 5, immediately before the boss), never earlier: F
Cleric's own wave-4 checkpoint sits at 62.7% remaining and wave-5 at 39.9%, a 22.8-point gap with
nothing in between for any other archetype or rank to land in either. Reaching genuine
multi-checkpoint graduation (a retreat that can fire at wave 2 for one team and wave 4 for
another, which is what "gambled on" implies) needs a threshold at roughly 62.7% remaining or
higher — i.e., "retreat if you've lost more than a third of your HP," which would fire
constantly, on nearly every real run, turning retreat from a last-resort gamble into background
noise. And this threshold is shared by every zone, not scoped to Verdant — raising it to serve
one archetype's one checkpoint in the one zone that's reachable today would also fire far more
eagerly in Ashfall and Sundered, where the current 25% already produces real, meaningful retreats
(above). A global change to fix a local gap.

> ⚠️ **RESOLVED, by `P2-03e`'s ruling (Lost-wave damage, above).** Retreat was dormant in solo
> Verdant at every rank, as a direct arithmetic consequence of the Wave damage rule plus the
> instant-wipe-on-loss branch — not a deliberate design choice. The fix was the win/loss branch
> itself: a lost wave now deals graduated damage (`clamp(1.0 * r^3, 0, 1)`, same `r`) instead of
> an instant wipe, which gives retreat an erosion pathway independent of the win branch's
> clear-reachability budget. Verified: `COMPLETED`, `DEFEATED`, and now `RETREATED` are all
> reachable in solo Verdant — but `RETREATED` only at F rank (all 5 archetypes; D-through-SSS
> reach none, at any coefficient tested), for the same structural reason F was already the only
> rank where Verdant's ramp is a real fight. No `P2-03c` dependency remains for retreat to exist
> in solo Verdant at all; `P2-03c` (mixed-rank rosters) and the Ashfall/Sundered unlock are still
> what widens the reachable footprint past F-rank Verdant — that half of the original `Settled by`
> still holds.
>
> ⚠️ **PROVISIONAL, narrower scope than before** — the `1.0` coefficient and the resulting F-only
> footprint are arithmetically verified (Codex thread `019fce28-66c9-7412-a07c-45327b3f2d9c`,
> cross-referenced in Lost-wave damage above) but unplayed. **Settled by:** a played build at F
> rank to feel whether a graduated loss reads as a real gamble, and `P2-03c` shipping to widen
> where retreat can fire beyond F-rank Verdant.

---

## Death and gear recovery — *Phase 2*

A dead hero's equipment does not vanish:

```
LostCache { hero_name, zone_id, items[], turn_lost }
```

**Recovery expeditions** are a distinct mission type targeting one cache. Required power is
`zone.power * 0.5` — deliberately low, so a weak B-team can go fetch a dead SSS hero's gear.
**That is the point of the system**, not an oversight.

Retrieved items may come back **Damaged**:

```
r = zone.power / team_power                              # same r convention as Wave damage, above
power_deficit_penalty = clamp(0.2 * (r - 1), 0.0, 0.2)
damage_chance = clamp(0.15 + 0.03 * turns_elapsed + power_deficit_penalty, 0.0, 1.0)
```

Damaged means enhancement halved (rounded down), or if already at `+0`, one affix rolled
down. **Any socketed Cores are lost.**

`power_deficit_penalty` scales continuously with how underpowered the retrieval team is relative
to the zone, rather than the pass/fail shape a flat bonus would give it — the required-power gate
already reads `team_power >= zone.power * 0.5`, i.e. `r <= 2.0` for any legal team, so `r`'s range
is `(0, 2]` for every team allowed to attempt the mission at all. The weakest legal team (exactly
at the gate) reads `r = 2.0`, so `power_deficit_penalty` hits its `0.2` cap exactly there — the cap
isn't dead headroom, it's reached at the floor of what the mission permits. A team at or above the
zone's own power (`r <= 1.0`) pays no penalty at all: `power_deficit_penalty` is purely a tax on
sending a team the recovery gate let in under-strength, not a bonus for overkill.

Verified (Codex thread `019fd9c8-efdf-7473-8101-5a57b92756d8`): weakest legal team, fresh cache —
`0.15 + 0 + 0.20 = 0.35`. Weakest legal team, cache about to expire at the un-upgraded 15-turn mark
— `0.15 + 0.45 + 0.20 = 0.80`. Fully-geared team (`r -> 0`) — floors at the `0.15` base regardless
of `turns_elapsed`. The outer `clamp` on `damage_chance` is not decorative: a maxed Reliquary
(below) stretches cache life to 40 turns, and the un-clamped formula reaches `0.15 + 1.2 + 0.2 =
1.55` at `turns_elapsed = 40, r = 2.0` — the `0.03`-per-turn base term alone crosses `1.0` around
`turns_elapsed ~= 28`, before `power_deficit_penalty` is even added. Reliquary's own `-3%`/level
reduction (capped at `-15%`, Buildings below) softens this but doesn't prevent it — the clamp is
load-bearing at the top end of cache life, not a formality.

> ⚠️ **PROVISIONAL** — `power_deficit_penalty`'s shape and coefficient (`0.2 * (r-1)`, capped at
> `0.2`) are picked and arithmetically checked at a desk (bounds verified above, Codex thread
> `019fd9c8-efdf-7473-8101-5a57b92756d8`) to keep the penalty continuous rather than binary and to
> stay a minority contributor next to the time-based base term, not from a played build. The two
> terms that already carried numbers (`0.15` base, `0.03 * turns_elapsed`) remain unplayed too.
> **Settled by:** a played build across at least one weak-team and one strong-team recovery run to
> feel whether `damage_chance` lands where "damaged gear is a real cost, but the system is still
> usable by a weak B-team" needs it to — the design intent stated two lines above (`zone.power *
> 0.5`) is specifically that a weak team *can* attempt this, so a played `0.80`-chance outcome that
> reads as "don't bother" would contradict the system's own stated point.

Caches **expire after 15 turns** (+5 per Reliquary level). The clock is what makes a death
hurt: you choose between pushing progression and mounting a salvage run.

---

## Summoning — *Phase 2*

| Rank | F | D | C | B | A | S | SS | SSS |
|---|---|---|---|---|---|---|---|---|
| Weight /10000 | 4000 | 2700 | 1700 | 1000 | 450 | 120 | 28 | 2 |
| Effective | 40% | 27% | 17% | 10% | 4.5% | 1.2% | 0.28% | 0.02% |

Roll a rank from the table, then a random definition from that rank's pool.

SSS at 0.02% is near-mythical on purpose — the design assumes you **build** an SSS through
sacrifice. Pulling one is a lightning strike, not a plan. Expected pulls to a first hit: **~83**
for a first S (`1/0.012`), **~5,000** for a first SSS (`1/0.0002`) — at 1,000 pulls the chance of
having hit at least one SSS by luck alone is ~18%; at 5,000 pulls, ~63%. See Sacrifice for the
~327-pull manufactured route, which is why this table can afford to be this stingy.

### Summoning Circle

The building table below used to say "shifts summon weight toward higher ranks" with no
magnitude — not implementable as written, and the gap only surfaced when P2-01d tried to
transcribe it into `balance.tres`. The formula:

```
circle_multiplier = 1 + 0.15 * level   (level capped at 5)
```

Applied to the four highest ranks (**A, S, SS, SSS** — indices 4-7) as a block; **F, D, C, B are
untouched**. The full 8-value table is then renormalized back to sum `10000`. Because both
blocks are scaled uniformly before renormalizing, this only moves mass *between* the two
blocks — the relative odds *within* each block are unchanged (`A:S:SS:SSS` stays `450:120:28:2`;
`F:D:C:B` stays `4000:2700:1700:1000`).

| Circle level | 0 (unbuilt) | 1 | 3 | 5 (cap) |
|---|---|---|---|---|
| `circle_multiplier` | 1.00 | 1.15 | 1.45 | 1.75 |
| SSS weight /10000 | 2.00 | 2.28 | 2.82 | 3.35 |
| SSS probability | 0.0200% | 0.0228% | 0.0282% | 0.0335% |
| Expected pulls to first SSS | 5,000 | 4,387 | 3,541 | 2,986 |
| Expected pulls to first S | 83 | 73 | 59 | 50 |
| Manufactured pulls per SSS (spine number, re-derived) | 327 | ~307 | ~274 | ~248 |
| Manufactured-vs-direct-pull advantage | ~15.0× | ~14.3× | ~12.9× | ~12.0× |

At the level cap, an SSS is still ~2,986 expected pulls direct — comfortably past the doc's own
"near-mythical" bar (it takes ~5,000 pulls of bad luck at any Circle level for even a coin-flip
chance of one) — and manufacturing is still ~12× cheaper than pulling, not inverted. The
Summoning Circle is a mid-game convenience on top of the sacrifice economy, not a route around
it: this was the explicit design risk this ticket asked to weigh, and the magnitude above was
chosen to keep both the "near-mythical" claim and the "manufacture, don't pray" ratio intact at
max level, not just at level 0. Verified arithmetic: Codex thread `019fc33f-8055-73b1-89a2-5ba881ce0cc4`,
spot-checked independently (`D = 9400 + 600*m`, `SSS_weight = 2*m*10000/D`, `direct_pulls =
D/(2*m)`).

> ⚠️ **PROVISIONAL** — the `0.15`/level curve is verified to preserve "near-mythical" and the
> "manufacture, don't pray" ratio at every Circle level (arithmetic above), but nobody has played
> against a built Circle to see if the mid-game convenience actually feels like one, or feels like
> nothing. · **Settled by:** a played build with the Circle built to at least level 3.

**Rejected:** an exponential-per-rank-index tilt (`weight_i *= mult ^ (level * i)`), which
compounds across level *and* rank index at once — at modest-looking per-step rates it exceeds
100× at the top rank by level 5, which both breaks "near-mythical" and makes the number
impossible to sanity-check by eye. Also rejected: scaling only S/SS/SSS and leaving A alone —
that block is `150/10000` of the table versus `600/10000` for A-and-above, so a S+-only version
barely moves at low Circle levels and the building would read as doing nothing until near its
cap. Also rejected (as a gentler alternative, computed but not recommended): `0.05 * level` —
SSS still near-mythical (~4,060 pulls at cap) but the effect is small enough (~19% relative
lift in top-rank odds at max level) that the building risks feeling like it does nothing, which
fails "does this need to exist" for the one building whose whole job is to be felt.

**Implementation note, stale as of `P2-07a` — corrected here.** This paragraph used to say the
schema needed two new `BalanceTable` fields in place of a single placeholder
(`summoning_circle_weight_shift`). Checked against `balance_table.gd:18,21` directly: both fields
already exist and are already authored — `summoning_circle_multiplier_per_level = 0.15` and
`summoning_circle_level_cap = 5` — and `summoning_circle_weight_shift` does not appear in
`balance_table.gd` at all (grepped; zero hits). The schema change this paragraph asked for has
already shipped. Nothing left to route to `tech-lead` on this point.

**No pity system until Phase 4.** Pity is a player-frustration feature, not a correctness
one, and adding it before the loop is proven would be tuning something that may not survive.

### Summon Stones — cost and income (`P2-09`)

`P2-09`. Summon Stones do not exist anywhere in code today (grepped `stone|Stone` case-insensitive
across every `*.gd`; the only hits are three `loot_emphasis` display-string literals in
`tests/zone_definition_check.gd`). A pull currently costs nothing — the hub's summon button is
free and unlimited. This ruling gives the currency a price, an income rate, and a starting
balance, the same "found, not authored" gap the loot table (`P2-04b`, above) and the resonance
trait pool (`P2-06`) each closed.

**1. Pulls cost stones — flat `100` per pull, regardless of rank rolled.** The gold-removal ruling
(Enhancement, above) kept two earned-currency tracks deliberately: *"Summon Stones pull, and
parts... upgrade, via Enhancement's cost line above and Buildings' upgrade cost below."* That
sentence is only true once a pull actually spends a stone — until now it was aspirational, and an
unpriced pull leaves Summon Stones in exactly the state gold was struck for: named, ledgered
nowhere, and doing no work. Flat, not rank-scaled: a player doesn't choose what rank a pull
returns (Summoning, above — you roll the rank, then the definition), so there is nothing for a
variable price to attach to. Same reasoning the loot table used for guaranteed-one-item-per-clear
being unscaled by zone on the "does it drop" question, only the "which" is randomized.

**2. Income — guaranteed, flat per zone, `COMPLETED` clears only.**

```
stone_reward = { Verdant Outskirts: 25, Ashfall Reaches: 75, Sundered Vault: 200 }
```

Paid on the same trigger as the loot-table drop (`Expedition.resolve()` reaching
`OUTCOME_COMPLETED`, `hub/expedition/expedition.gd:65-67`) — `RETREATED` and `DEFEATED` pay
nothing, the identical rule `P2-04b` already ruled for the item drop, so the two rewards land on
the same clear together rather than needing a second condition authored.

| Zone | Stones/clear | Pulls this buys |
|---|---:|---:|
| Verdant Outskirts (light) | 25 | 1/4 pull |
| Ashfall Reaches (moderate) | 75 | 3/4 pull |
| Sundered Vault (heavy) | 200 | 2 pulls |

`25 : 75 : 200` reduces to `1 : 3 : 8` — clean, and deliberately tamer than the zones'
`recommended_power` ratio (`900 : 4,800 : 11,500`, roughly `1 : 5.3 : 12.8`). Pricing income
directly off recommended power was considered and rejected (below); the ratio actually chosen
still rewards pushing to a harder zone (a Sundered clear buys 8× a Verdant one) without making
Verdant-only farming pay for less than a quarter-pull per clear, which would starve the sacrifice
engine's own claim that it's fed by *the natural spread of pulled ranks* from the very first pull
(Sacrifice, above) — that claim needs pulls to stay reachable at F-rank content, not just at
Sundered.

Verified (Codex thread `019fdae0-d06f-7e82-b408-93d55716a5f1`): the `25/75/200` banding reduces
exactly to `1:3:8`, and a Sundered clear buys exactly 2 pulls, an Ashfall clear exactly 0.75 of
one, a Verdant clear exactly 0.25 — no rounding anywhere in the banding itself.

**3. Starting balance — `300` stones (3 pulls) on a fresh save.** This is not a feel choice, it is
a correctness floor: `roster` starts empty on a fresh save (`systems/game_session.gd:10`, no
starting-hero grant exists anywhere), and `Expedition` accepts a team as small as one hero
(`hub/expedition/expedition.gd:20`, `assert(team.size() >= 1 ...)`) — so the *only* way a fresh
save can field any expedition at all is to pull first. A starting balance below `100` (one pull's
cost) makes the summon button, and therefore the entire game, unplayable from boot. `300` is
three pulls, chosen against a number this document already verified rather than invented fresh:
the spine's own "~2.5 expected pulls to land the F keeper" (Sacrifice, above — `1/0.4`, the F-rank
weight). Three pulls clears that expectation with headroom — `78.4%` chance of landing at least
one F-rank hero within exactly 3 pulls (`1 - 0.6^3`, Codex thread above) — and leaves a fresh
roster with more than a single point of failure if the first pull rolls an archetype the player
doesn't want to lead with.

**4. The spine, re-derived into clears.** `327` manufactured pulls × `100` stones = `32,700`
stones (minus the `300` starting balance, `32,400` net — a `<1.3%` difference at every zone's
rounded clear count, negligible against a number that was already `~327`, not exact). Clears
needed to earn that many stones, farming one zone exclusively:

| Zone | Clears to fund 327 pulls |
|---|---:|
| Verdant Outskirts only | ~1,308 |
| Ashfall Reaches only | ~436 |
| Sundered Vault only | ~164 |

This closes the PROVISIONAL at the top of Sacrifice → rank up (above): the `~327`-pull spine
number now maps to a real, countable unit — clears — the same denominator Buildings' own upgrade
cost already uses (`264` expected clears to max one building). Sundered-only farming lands at
`~164` clears per manufactured SSS, `~0.62×` the building anchor — same order of magnitude,
comfortably inside what this document already treats as a reasonable long-horizon grind. Nothing
about this ruling touches the manufacture-vs-direct-pull ratio: stone pricing changes what a pull
costs to reach, not how many pulls each route needs, so the existing `~15×` "manufacture, don't
pray" advantage (Summoning, above) is unaffected — reconfirmed at `5,000/327 ≈ 15.3×`.

**What this does *not* settle.** Clears are countable; sessions and hours are not. Nothing in this
codebase counts a play session or a wall-clock minute (the same gap `P2-04f`/`P2-13` are blocked
on), so "164 clears" cannot honestly become "N sessions" or "N hours" without a further, separate
fact this ruling doesn't have: how many clears a player actually completes per sitting. That
number can only come from a played build, not a desk.

**5. Where the numbers live.**

| Number | File | Notes |
|---|---|---|
| `summon_pull_cost = 100` | `BalanceTable`/`balance.tres` | New field. Single global constant — pulls don't vary by rank, so no per-zone or per-rank split. |
| `stone_reward` per zone (`25`/`75`/`200`) | `ZoneDefinition` (→ `zones/defs/*.tres`) | New field, same shape as `P2-04b`'s `loot_rank_min`/`loot_rank_max` — genuinely per-zone. |
| Starting balance (`300`) | `GameSession` | New field entirely — `GameSession` has no stone/currency field of any kind today (`systems/game_session.gd:10-16`); this is the "found, not authored" gap this whole ruling closes. Needs `to_dict`/`from_dict` persistence like every other `GameSession` field (`CLAUDE.md`'s save-round-trip boundary), and a default of `300` on a fresh save specifically, not merely "starts at 0." |
| `COMPLETED`-only payout | Nowhere new — formula-shape, written into the reward rule itself, same footing as the loot table's own guaranteed-drop condition | No `BalanceTable` field. |

This is the shape a follow-up implementer ticket needs; writing that ticket body is `tech-lead`'s
call, not this ruling's. Flagging for that ticket: pricing a pull means `GameSession`'s summon-roll
call site needs a stones-check-and-deduct guard mirroring `enhance_item`'s
parts-check-and-deduct shape (`systems/game_session.gd:73-88`) — return `false`/no-op on
insufficient balance rather than letting the roll happen for free. The `.tscn` summon button UI
also needs to read and display the balance and disable itself below `summon_pull_cost`, the same
class of scene-seam change `CLAUDE.md`'s risky-boundary section already flags for any state
change.

**Rejected: keep pulls free.** This was the status quo, considered as "do nothing." Rejected
because it leaves the gold-removal ruling's own reasoning false — Summon Stones would join gold as
a currency that is named, prosed about in three zone files, and does nothing, the exact "third
currency filling a role... with zero implementation behind it" problem gold was struck for. The
difference is Summon Stones already have a real consumer (the pull) the moment a price exists;
striking them the way gold was struck would mean rewriting the zone prose and the gold-removal
ruling's own two-track claim, a larger and unjustified change.

**Rejected: price pulls by target rank** (e.g. cheaper for a guaranteed-low-rank pull, more
expensive for a rank-weighted-up pull). Rejected because Summoning doesn't let a player choose a
rank to pull — the rank is rolled, then the definition (Summoning, above) — so there is no "which
rank did you buy" decision for a variable price to price. The Summoning Circle already spends its
whole budget shifting the *odds*, not selling ranks directly; a second, pull-priced lever for the
same knob would be redundant with a building that already exists.

**Rejected: income proportional to `recommended_power`** (`900 : 4,800 : 11,500`, ≈`1 : 5.3 :
12.8`). Computed and rejected: at that ratio a Verdant clear would fund under a fifth of a pull
(`25 * (1/5.3) ≈ 4.7` at the same Sundered anchor), which risks the sacrifice engine's own
"natural spread, not just F-fodder" design intent (Sacrifice, above) never being reachable from
starter content — a new player would need to reach Ashfall or Sundered before pulling felt
worthwhile at all, undermining the "manufacture, don't pray" loop the whole spine number exists to
support.

**Rejected: a turn/session/hour-denominated rate.** Named explicitly as the trap in this ticket's
own framing, and it would be the fifth time this backlog authored a number against a clock that
doesn't exist (`LostCache.turn_lost`, `Item.enhance_level`, `reliquary_decay_turns_bonus`, the flat
Forge salvage bonus, all flagged earlier in this document). Clears are the only repeatable,
already-countable player action in this codebase; denominating in anything else would read as real
and measure nothing, same as every prior instance of this trap.

**Rejected: starting balance of `100` (exactly one pull).** Every pull always returns *some*
hero — the weight table sums to `10000` across F..SSS with no "miss" outcome — so one pull never
literally strands a fresh save. Rejected anyway: it clears none of the spine's own `~2.5`-pull
expectation to land an F-rank hero specifically, and leaves a brand-new roster at exactly one
hero with no fallback if that pull's archetype doesn't suit the player's first fight. `300` is the
smallest multiple of `100` that clears the `2.5`-pull expectation with a full pull of headroom.

> ⚠️ **PROVISIONAL** — `100`/pull, the `25:75:200` zone banding, and the `300` starting balance
> are arithmetically self-consistent (verified above, Codex thread `019fdae0-d06f-7e82-b408-93d55716a5f1`)
> and checked against every existing spine number in this document, but nobody has spent a stone
> against a built summon button. Whether `100` reads as a real cost or an invisible tax, and
> whether the `1,308`/`436`/`164` clears-to-spine figures feel like "a long-term goal" or "a
> chore" the way Buildings' own cost anchor asks the same question, is unfelt. · **Settled by:** a
> played build with pricing wired in, across at least a few dozen real clears in each zone.

---

## Base buildings — *Phase 2*

`P2-07a`. Rules the two gaps `P2-07` cannot be written against: an upgrade-cost formula in
`parts` (rank-indexed, so a flat "N parts" is not implementable — the same gap `P2-01d` found in
the Summoning Circle line), and the level caps for the three buildings that had none.

Five buildings. **Not five integers** — corrected here after P2-01d's transcription into
`balance.tres` found the original "five integers" line false: it's eight magnitudes across the
five (nine if the Forge's cap and its own ceiling are counted as separate numbers, which is
arguable either way). Every magnitude is still read by exactly one system; the count was wrong,
not the "one system" claim.

| Building | Effect per level | Magnitudes | Read by |
|---|---|---|---|
| Summoning Circle | `circle_multiplier = 1 + 0.15*level` (cap 5) applied to the A/S/SS/SSS block, table renormalized — see Summoning | 2 | summon |
| Forge | Enhance cap `level * 3` (max 15); salvage yield +10% | 2 (arguably 3: rate, cap, ceiling) | forge |
| Training Hall | Post-expedition XP +15% | 1 | expedition |
| Sanctum | Sacrifice essence yield +10% | 1 | sacrifice |
| Reliquary | Cache decay +5 turns; recovery damage chance −3% | 2 | recovery |

### Level caps — all five cap at level 5

**Ruling: Training Hall, Sanctum, and Reliquary cap at level 5, the same cap Forge
(`forge_enhance_cap_per_level * level ≤ forge_enhance_cap_max`, i.e. `3*5=15`) and the Summoning
Circle (`summoning_circle_level_cap = 5`) already carry.** Closes the PROVISIONAL that used to
sit here.

Two reasons, one per building family:

- **No basis exists to make the other three a different cadence than Forge/Circle.** All five
  buildings read exactly one system each and none of their bonuses is tied to another leveled
  resource the way Enhancement's cap is tied to `Item.enhance_level` (0-15) — there is nothing in
  this document that would justify Training Hall progressing on a faster or slower clock than the
  Circle. Absent a reason to diverge, the smallest surprising choice is the cap already used
  twice.
- **Reliquary's own numbers corroborate 5 specifically, not just "pick something."** `recovery
  damage chance −3%` per level against `damage_chance`'s base `0.15` (Death and gear recovery,
  above): `0.03 * 5 = 0.15` exactly cancels the base term at `turns_elapsed = 0` (Codex thread
  `019fd9c2-ea81-7780-8275-cb11eb903de3`, question 5). A cap of 4 leaves `0.03pp` of the base
  permanently un-cancellable for no reason; a cap of 6 makes a maxed Reliquary net *negative*
  before `power_deficit_penalty` is even added, which would need a `clampf(..., 0.0, 1.0)` this
  document hasn't asked for. 5 is the only cap where the base term cancels clean.

At cap, the remaining per-level bonuses read: Forge `+50%` salvage yield (ruled at the end of this
section — this paragraph's prior silence on Forge is the gap `P2-07d` flagged), Training Hall
`+75%` XP (meaningless number until `P2-04a` exists — see below), Sanctum `+50%` essence yield,
Reliquary `+25` decay turns (cache lifetime 15 → 40) stacked with the `−15%` damage-chance
cancellation above.

> ⚠️ **PROVISIONAL** — the cap-5 choice for Training Hall/Sanctum/Reliquary is justified by
> consistency with Forge/Circle and by Reliquary's clean cancellation at 5; it has not been
> played at any level, and Training Hall's and Sanctum's magnitudes at cap (`+75%` XP, `+50%`
> essence yield) have no played reference point the way Reliquary's does. · **Settled by:** a
> played build with at least one of these three built past level 1.

> ⚠️ **RESOLVED by `P2-04a`** (Expeditions § "Hero leveling — XP curve and income," above).
> Training Hall's `+15%/level` now multiplies `xp_per_wave` and `xp_reward`; at cap (level 5,
> `+75%`) it cuts the expected attempts to climb F's level cap from `~33.6` to `~19.5` — verified,
> not decorative. The PROVISIONAL below (cap-5 choice, unplayed) still stands; only "the
> percentage is meaningless" is retired, since there's now a curve for it to multiply.

### Which buildings ship in `P2-07`

**Ruling: three buildings now — Summoning Circle, Forge, Sanctum. Training Hall and Reliquary
wait for their consumers.** A player who spends parts on a building that provably does nothing is
a worse outcome than the building not being offered yet, and two of the five have no consumer to
read them at all:

- **Training Hall** read against `P2-04a`'s XP curve, which was unstarted when `P2-07` shipped —
  there was no expedition-XP system anywhere in the codebase for `+15%` to modify. `P2-04a`'s
  ruling above (Expeditions § "Hero leveling") now defines that curve, but the curve is a
  doc-only number until an implementer wires `Hero.level`/`xp` and the XP-grant path into code;
  whether Training Hall ships alongside that work or waits for a further ticket is `tech-lead`'s
  scheduling call, not this ruling's.
- **Reliquary** reads against two things neither of which exists: the recovery-expedition damage
  roll (`P2-04f`, blocked on `power_deficit_penalty`) and a "turn" concept at all (also `P2-04f`,
  and the decay clock is turn-denominated). Same outcome — parts spent here are inert until
  `P2-04f` unblocks and ships.
- **Circle, Forge, and Sanctum** each read a system that already exists in code today: `summon`
  (roll-a-rank-then-a-definition, live), `forge` (`enhance_item`/`salvage_item`,
  `systems/game_session.gd:58-84`, live), and `sacrifice` (`sacrifice_hero`,
  `systems/game_session.gd:104-111`, live). Their bonuses aren't wired to a building level yet —
  that's `P2-07`'s own job — but the thing being boosted is real, so a level spent on any of the
  three does something the moment `P2-07` wires it in.

`P2-07`'s ticket should therefore scope to three buildings, not five. Training Hall and Reliquary
are not cancelled — they're the same shape as `Item.enhance_level` was before `P2-05f`: a real,
ruled design (this section) waiting on a field nobody needs yet. Re-open them as a follow-up once
`P2-04a` (Training Hall) or `P2-04f` (Reliquary) lands; no further design pass should be needed
at that point since the cost formula and cap below already cover all five uniformly.

### Upgrade cost — parts, rank keyed to level

**Ruling:**

```
cost(level n -> n+1) = 10 * (n + 2) parts of rank index n      (n = 0..4)
```

`n` is the building's *current* level before the upgrade (0 = unbuilt, same convention the
Summoning Circle table already uses), and it doubles as the parts *rank index* the upgrade
consumes: level 0→1 costs F-rank parts, 1→2 costs D-rank, 2→3 costs C-rank, 3→4 costs B-rank,
4→5 (the cap) costs A-rank. Same shape as Enhancement's `2 + n` — a building's cost climbing in
*rank* as it levels is the direct analogue of Enhancement's cost climbing in *quantity* as an
item levels, since a building has no fixed rank of its own the way an item does. Applies
uniformly to all five buildings, including the two deferred above, so no separate cost pass is
needed when they ship.

| Level | 0→1 | 1→2 | 2→3 | 3→4 | 4→5 |
|---|---|---|---|---|---|
| Rank | F | D | C | B | A |
| Cost | 20 | 30 | 40 | 50 | 60 |

Checked against real parts income — one guaranteed drop per clear, salvage `3 + enhance_level`
parts of the drop's own rank (worst case 3, unenhanced), banded per zone, no downward conversion
(Codex thread `019fd9c2-ea81-7780-8275-cb11eb903de3`, direct-farming-only, no credit taken for
converting spare lower-rank parts up):

| Level | Rank | Best zone | Band weight | Parts/clear | Clears needed |
|---|---|---|---:|---:|---:|
| 0→1 | F | Verdant | 47.62% | 1.429 | 14 |
| 1→2 | D | Verdant | 32.14% | 0.964 | 32 |
| 2→3 | C | Ashfall | 53.97% | 1.619 | 25 |
| 3→4 | B | Ashfall | 31.75% | 0.952 | 53 |
| 4→5 | A | Ashfall | 14.29% | 0.429 | 140 |

**264 expected clears to max one building** (14+32+25+53+140, Codex thread
`019fd9c2-ea81-7780-8275-cb11eb903de3`) — **792 to max all three shipped in `P2-07`**
(`264*3`), **1,320 if Training Hall and Reliquary are counted too** (`264*5`, the eventual
all-five total once they unblock). 264 is the same order of magnitude as the ~327-pull
manufactured-SSS spine number (Summoning, above), which is the anchor this was chosen against: a
building's payoff is permanent and account-wide (every future pull, every future enhance, every
future sacrifice), so a single building maxed should cost roughly as much patience as
manufacturing one SSS, not less. The undercount direction only: this assumes every clear's drop
is dedicated to the plan and ignores the time a clear itself takes.

**Rejected: multiplier 5** (`5*(n+2)`, half the coefficient) — 133 clears to max one building,
under half the SSS spine number for a bonus that, unlike an SSS hero, applies to *every* future
pull/enhance/sacrifice forever. Undersells what a permanent, account-wide multiplier should cost
relative to a one-time hero.

**Rejected: multiplier 20** (`20*(n+2)`, double) — 526 clears to max one building, 1,578 for the
three shipped buildings alone — ~1.6× the spine number per building, which risks buildings
becoming the dominant parts sink in the game rather than a complement to summon/sacrifice/enhance,
the systems this doc treats as the actual core loop.

**Rejected: fixed rank per building, quantity-only scaling** (e.g. every level of a building
costs C-rank parts, with quantity climbing per level) — considered because it avoids the
mid-progression gate where level 4→5 needs Ashfall access. Rejected because it breaks the
Enhancement-formula parallel (rank fixed, quantity climbing) for no gain: a building's cost
climbing in rank models "this building is now asking for a deeper commitment" the same way a
hero's own rank-up costs climb in essence: rank F→D costs 40, SS→SSS costs 16,000 (Sacrifice →
rank up, above) — an established pattern in this doc, not a new one being invented here.

> ⚠️ **PROVISIONAL** — the cost formula is arithmetically checked against real drop/salvage rates
> (table above) and picked to land in the same order of magnitude as the already-verified SSS
> spine number, but nobody has spent parts against a built UI to feel whether 14-to-140 clears per
> level reads as "a long-term goal" or "a chore." · **Settled by:** a played build with `P2-07`'s
> UI, spending real parts income against these costs across at least one full building.

Gold stays struck from this line — see Enhancement's gold-removal ruling above. This is no longer
a "waiting on an income source" deferral: gold is removed from the document, not paused.

No build queues, no adjacency bonuses, no timers, no construction animation. Add complexity
only when a building needs to express something an integer can't.

### Forge salvage-yield bonus — scaling law

**Ruling: per-level, `10% * forge_level`, same cadence as every sibling field of this exact
shape — not flat-on-build.**

```
salvage_bonus(forge_level) = 0.10 * forge_level      (forge_level = 0..5)
yield = roundi((3 + enhance_level) * (1.0 + salvage_bonus))
```

`forge_level = 0` (unbuilt) gives `+0%` — Forge contributes nothing until level 1, the same gate
every building's level-0→1 cost pays for. At the cap (level 5) it reaches `+50%`, the magnitude
now folded into the "at cap" recap above and identical to Sanctum's essence-yield bonus at cap.

The field name settles nothing on its own (`P2-07d`'s table row already says so), but the pattern
across its siblings does: `training_hall_xp_bonus`, `sanctum_essence_yield_bonus`,
`reliquary_decay_turns_bonus`, and `reliquary_damage_chance_reduction` (`balance_table.gd:24-28`)
share the identical no-`_per_level`-suffix shape as `forge_salvage_yield_bonus`, and every one of
them is already ruled per-level elsewhere in this section. Forge's salvage-yield row also sits
under the Base-buildings table's own "Effect per level" column header alongside all four —
nothing in the table distinguishes it. The ambiguity `P2-07a` left open was created entirely by
the "at cap" recap paragraph omitting Forge, not by anything in the field itself or its neighbors.

**Rejected: flat `+10%` once built, regardless of level.** Two reasons:

1. **No internal consistency.** Forge's *other* effect (`forge_enhance_cap_per_level`) is
   explicitly per-level; nothing in this document gives one Forge effect a different progression
   shape than the other, and every sibling field above is per-level too.
2. **The rounding trap, measured.** Salvage yield is `3 + enhance_level`, an integer with no
   fractional part today. Introducing a float bonus on top of it forces a rounding choice, and
   under truncation (`int()`) a flat `+10%` produces **zero extra parts for `enhance_level` 0
   through 6** — `3*1.10 = 3.3 -> 3`, `4*1.10 = 4.4 -> 4`, … `9*1.10 = 9.9 -> 9`; the first
   nonzero result needs `enhance_level >= 7` (`base >= 10`) (Codex thread
   `019fda99-8a2b-7c40-a78f-c54406c640bc`). `enhance_level = 0` — a freshly-dropped, unenhanced
   item — is the single most common salvage case; nobody spends Forge parts enhancing gear they
   intend to break. A flat reading under truncation reads real in the buildings table and
   measures nothing on the majority of actual salvage actions — the same trap `LostCache.turn_lost`,
   `Item.enhance_level`, and `reliquary_decay_turns_bonus` each hit before this was caught.

**Rounding: `roundi()` (round-half-away-from-zero), not `int()`/floor truncation — this call
holds regardless of which reading had won.** Truncation reproduces the same trap one level down
even under the ruled per-level reading: `floor((3+enhance_level)*(1+0.10*level))` still yields
zero extra parts for `enhance_level = 0` at Forge levels 1 through 3 — `3*1.10=3.3->3`,
`3*1.20=3.6->3`, `3*1.30=3.9->3` — three of the building's five levels would read as doing
nothing on the most common salvage case. `roundi()` fixes this from level 2 onward
(`3*1.20=3.6->4`), leaving only level 1 (`3*1.10=3.3->3`) as zero-effect on unenhanced junk, which
is acceptable: level 1 is the building's cheapest rung, and every other per-level bonus in this
document is also smallest at level 1. (Same Codex thread, confirmed by hand-checked subtraction
after an initial summary error was caught and corrected on the thread.)

**Self-financing check — not degenerate.** A live per-level bonus feeds the same parts currency
that funds the next building level. Applying each level's live bonus to the "parts/clear" figure
while grinding toward the *next* level (e.g. level 1's `+10%` applies while grinding 1→2, level
4's `+40%` while grinding 4→5) reduces the 264-expected-clears anchor above to **~204.7 clears
(-22.5%)** (same Codex thread). Real and felt, not nothing — but not an order-of-magnitude
collapse of the cost anchor, and the final level's own `+50%` never gets to fund itself since
there is no level 5→6 to grind toward.

> ⚠️ **PROVISIONAL** — the per-level reading and `roundi()` rounding are arithmetically settled
> (the only combination of the two choices in front of this ruling that avoids a zero-effect level
> past the first), but nobody has salvaged gear against a built Forge to feel whether a bonus this
> small (0-2 extra parts per salvage at the ranks players actually farm) registers at all versus
> needing to be read off a tooltip. · **Settled by:** a played build with `P2-07d` wired, salvaging
> real drops against a Forge leveled past 1.

---

## Save — *Phase 2*

`GameSession` → `Dictionary` → `JSON.stringify` → `user://save.json`. Written only by
`SaveService`.

Human-readable and diffable, which matters enormously when a balance change corrupts
progression and you need to see what actually happened.

**Include a `version: int` field from the first commit.** Migration logic is Phase 5, but
retrofitting the field onto existing saves is not something you want to do later.
