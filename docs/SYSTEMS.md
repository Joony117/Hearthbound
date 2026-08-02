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

A max-level sacrifice yields double, so levelling fodder before feeding it is a real (if
slow) strategy.

**Rank-up preserves the hero's level and raises the cap.** Resetting level would make
ranking up feel like a punishment. See `DECISIONS.md`.

### Dupes and resonance

Feeding a hero into another instance of the *same* `def_id` grants ×3 essence **and** a
resonance point. Resonance unlocks traits from that hero's definition trait pool at
**1, 3, and 6**.

This is why a duplicate is never dead weight, and it gives chasing a specific unit a payoff
ladder beyond raw stats.

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

### Enhancement

- `cost(n → n+1) = 2 + n` parts of matching rank, plus gold
- `+8%` to the item's primary stat per level
- Cap: `min(15, forge_level * 3)`

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

### The three zones

Three zones carry the entire F→SSS span, so each one covers a wide rank band rather than a
single rank. Recommended power is pinned to the ungeared 5-hero reference team from the Heroes
section (real teams carry gear on top, so "recommended" sits at or slightly below what a
same-rank team already has in base kit alone):

| Zone | Unlock | Recommended power | Waves | Loot emphasis |
|---|---|---|---|---|
| Verdant Outskirts | Available from start | 900 | 5 trash (50%→90% of RP) + 1 boss (110% RP) | Gold, F–C parts, light Summon Stones |
| Ashfall Reaches | Clear Verdant Outskirts | 4,800 | 6 trash (50%→100% RP) + 1 boss (120% RP) | Gold, C–A parts, moderate Summon Stones, first A+ drops |
| Sundered Vault | Clear Ashfall Reaches | 11,500 | 7 trash (60%→110% RP) + 1 boss (130% RP) | Gold, S–SSS parts, heavy Summon Stones, best A+ drop rate |

A wave's "contents" here is a single `enemy_power` scalar (a fraction of the zone's recommended
power, from the ramp above) that quick_resolve compares statistically against the team's
`hero_power` — not a bestiary of named enemies with individual stat lines. Authoring actual
enemy species and their stat blocks is its own follow-up ticket; nothing in P2-01 or P2-03
depends on it existing yet, and inventing one here would be scope creep past what this pass was
asked for.

### Retreat threshold

Each expedition carries a retreat threshold, default: bail at 25% party HP.

Three lines of code. It converts permadeath from something that happens *to* the player into
something they gambled on, which is the difference between the mechanic feeling unfair and
feeling tense.

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
damage_chance = 0.15 + 0.03 * turns_elapsed + power_deficit_penalty
```

Damaged means enhancement halved (rounded down), or if already at `+0`, one affix rolled
down. **Any socketed Cores are lost.**

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

Summoning Circle level shifts weight up the table.

**No pity system until Phase 4.** Pity is a player-frustration feature, not a correctness
one, and adding it before the loop is proven would be tuning something that may not survive.

---

## Base buildings — *Phase 2*

Five buildings. **Five integers.** Each read by exactly one system.

| Building | Effect per level | Read by |
|---|---|---|
| Summoning Circle | Shifts summon weight toward higher ranks | summon |
| Forge | Enhance cap `level * 3` (max 15); salvage yield +10% | forge |
| Training Hall | Post-expedition XP +15% | expedition |
| Sanctum | Sacrifice essence yield +10% | sacrifice |
| Reliquary | Cache decay +5 turns; recovery damage chance −3% | recovery |

Upgrade cost: gold + parts.

No build queues, no adjacency bonuses, no timers, no construction animation. Add complexity
only when a building needs to express something an integer can't.

---

## Save — *Phase 2*

`GameSession` → `Dictionary` → `JSON.stringify` → `user://save.json`. Written only by
`SaveService`.

Human-readable and diffable, which matters enormously when a balance change corrupts
progression and you need to see what actually happened.

**Include a `version: int` field from the first commit.** Migration logic is Phase 5, but
retrofitting the field onto existing saves is not something you want to do later.
