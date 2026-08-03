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
> · **Settled by:** both combat paths existing and a played build against them, with real gear
> equipped.

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
