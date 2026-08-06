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

> ⚠️ **PROVISIONAL** — the `~327`-pull spine number is arithmetically solid (`78.38` essence/pull
> checked directly against the weight and essence-base tables), but unvalidatable against actual
> play time: there is no Summon Stone income rate yet, so "327 pulls" doesn't map to a session
> count or an hour count. · **Settled by:** Summon Stone income being defined (`P2-09`), then a
> played build to see how many pulls a session actually yields.

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

> ⚠️ **PROVISIONAL** — resonance unlocking at 1, 3, and 6 dupes is an untested curve; nobody has
> checked it against how often a player actually accumulates duplicates of one `def_id` at the
> weights in Summoning, so "6 dupes" could be a routine milestone or a near-unreachable one
> depending on rank. · **Settled by:** a played build, or a dupe-rate calculation cross-referenced
> against the Summoning weight table (not yet done).

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
upgrade-cost line (below) until a ticket gives it an income rate — same shape as `P2-09`/`P2-04a`.
That ticket is not this one; flagging it for `tech-lead` to open.

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
| Gold (drop rate, cost values) | Not authored anywhere — deferred | Same shape as `P2-09`/`P2-04a`. A follow-up ticket gives it a `BalanceTable` field once it has a source; not this one. |

`P2-05f`'s "files allowed to change" follows: `equipment/item.gd` (`enhance_level` field +
`to_dict`/`from_dict`), `BalanceTable`/`balance_table.gd` (`enhance_pct_per_level`) + `balance.tres`,
and `Hero.compute_final_stats` to scale each item's per-item contribution before the existing
per-stat summation. No change to `EquipmentDefinition`.

> ⚠️ **PROVISIONAL** — the `58.98%` maxed-enhancement gear share (question 1) is arithmetically
> checked, not played — it's the same open question Primary stat magnitude's own gear-share marker
> already named ("gear matters" vs "gear dominates"), now with a number attached for the ceiling
> case rather than just the unenhanced one. · **Settled by:** the same played build that marker
> calls for, at an additional checkpoint — maxed rank *and* maxed enhancement, not just maxed rank.

> ⚠️ **PROVISIONAL** — gold is named in cost lines and loot-table prose but has no value, no
> `BalanceTable` field, and no income source anywhere in code. · **Settled by:** a ticket giving
> gold an income rate (same shape as `P2-09`), after which Enhancement's and Buildings' cost lines
> can add a real gold term.

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
| Verdant Outskirts | Available from start | 900 | 5 trash (50%→90% of RP) + 1 boss (110% RP) | Gold, F–C parts, light Summon Stones |
| Ashfall Reaches | Clear Verdant Outskirts | 4,800 | 6 trash (50%→100% RP) + 1 boss (120% RP) | Gold, C–A parts, moderate Summon Stones, first A+ drops |
| Sundered Vault | Clear Ashfall Reaches | 11,500 | 7 trash (60%→110% RP) + 1 boss (130% RP) | Gold, S–SSS parts, heavy Summon Stones, best A+ drop rate |

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
damage_chance = 0.15 + 0.03 * turns_elapsed + power_deficit_penalty
```

Damaged means enhancement halved (rounded down), or if already at `+0`, one affix rolled
down. **Any socketed Cores are lost.**

> ⚠️ **PROVISIONAL** — `power_deficit_penalty` is named in the formula above with no value or
> formula defined anywhere; the two terms that do carry numbers (`0.15` base, `0.03 *
> turns_elapsed`) haven't been played either. · **Settled by:** defining `power_deficit_penalty`'s
> formula, then a played build to feel whether `damage_chance` lands where "damaged gear is a
> real cost" needs it to.

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

**Implementation note, not a doc change:** this needs two `BalanceTable` fields (a per-level
rate and a level cap), not the single placeholder currently authored
(`summoning_circle_weight_shift = 0.0`, `balance.tres`) — a schema change, not a value fill-in.
Route through `tech-lead` as a ticket; this document does not edit `balance.tres` or
`balance_table.gd`.

**No pity system until Phase 4.** Pity is a player-frustration feature, not a correctness
one, and adding it before the loop is proven would be tuning something that may not survive.

---

## Base buildings — *Phase 2*

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

> ⚠️ **PROVISIONAL** — Training Hall, Sanctum, and Reliquary carry no level cap at all; only Forge
> has one (`level * 3 ≤ 15`, implied by Enhancement). Nothing stops the other three scaling into
> a magnitude nobody has checked. · **Settled by:** a design pass giving each an explicit cap, and
> a played build to find where the effect stops being fun to keep pushing.

> ⚠️ **PROVISIONAL** — Training Hall's "+15% XP" reads against an XP-per-level curve that doesn't
> exist anywhere in this document (`P2-04a`). The percentage is meaningless until there's a curve
> to apply it to. · **Settled by:** `P2-04a` defining the XP curve.

Upgrade cost: parts — gold struck per Enhancement's ruling (`P2-05e`) that gold has no value and
no income source anywhere in this game yet. Add back once a ticket gives gold a rate.

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
