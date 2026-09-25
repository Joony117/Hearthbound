# Systems Reference

The target design. **This is a reference, not a build order.** Each section is tagged with
the phase that implements it — do not build a Phase 4 system during Phase 2 because it was
written down here.

Every number below ends up in `balance.tres`, editable in the inspector without touching
code. The values here are starting points to be tuned against play, not commitments.

---

## Autonomous squad combat and rescue — *ig-544, approved 2026-09-22*

This section supersedes the future direct-control combat direction and immediate-death
semantics for production autonomous expeditions. Legacy action-arena and quick-resolve
numbers below remain their compatibility reference. The six hero stats, rank/gear formulas,
existing zone power ramps and economic rewards remain authored as before.

### Battle clocks and commands

The simulation uses fixed 0.1-second logical ticks with stable actor ordering and a saved RNG
state. Route minimum and combat run in parallel. Success waits for both before reward
settlement; wipe creates a stranded incident. Current-run offline progress is bounded by
mission duration and never chains repeats. Tactical pause stops only the watched combat,
clears on leaving/reload, and does not create an income speed bonus.

Commands validate actor ownership/life, target, position, range, cooldown and supplies before
applying atomically. A new direct movement/target order replaces the previous one; no custom
queue. Auto Battle advances objectives; per-hero Manual abilities remain manual. Automatic
support priority is revival skill, permitted revival item, heal, then offensive abilities and
basic attacks. Automatic decisions use stable spawn order. Downed allies cannot be executed
by enemies and cannot act, move or spend supplies.

Desktop controls use plain A for camera pan and Shift+A to arm attack-move, followed by a
right-click destination. Editable text fields suppress battle hotkeys. Shift still adds to
selection. Enemy Ranger and Mage signatures show their fixed aim for 0.8 seconds before
resolving; interruption cancels the effect but retains its spent cooldown. Death/downing or
stun also cancels a pending attack. Allied signatures resolve immediately. Allies on Auto Battle
walk out of telegraphed danger toward the nearest safe point before resuming their objective. A
hero under any direct order (move, attack, attack-move, hold, guard, carry or retreat) does not walk
out: the order is obeyed as given. Its Auto counter skills still answer the telegraph
(§ Skills, Counters), because they are skills, not moves.
*Amended 2026-09-24 (extra, from the `ig-ap2` review):* this used to say "unless the player has an
explicit move, hold or guard order in effect". The code has skipped the walk-out for every direct
order since `ig-544`, and that is the rule. Why:
- A direct order beats automation everywhere else in this section.
- Direct orders exist only in a watched battle, where the player sees the 0.8 s aim and can give a
  new order. A dispatched battle has no direct orders, so the walk-out always runs there.
- The doc's version would need a resume after each walk-out for an attack, a carry and a retreat.

**Attack-move** (`ig-ap2`). A direct order to a ground point that fights on the way.
- The hero keeps its point. Only a new direct order changes it: never the squad AI, a stance or
  § Hero AI on auto.
- On the way, it fights the nearest living enemy within its contact range,
  `max(battle_detection_range, its attack range)` (12 today, the Formation term): it closes to
  attack range and attacks. It keeps that enemy while the enemy lives and stays in contact range.
  Otherwise it picks again. With no enemy in contact range, it walks on.
- It ends on reaching its point with no enemy engaged, like a move. Auto, if on, then takes over.
- Auto Battle on or off makes no difference while the order stands.
- Why contact range, not the 6-unit cohesion distance: enemy Rangers and Mages shoot from 8
  (`battle_ranged_range`) and allied ones from 12 (`battle_ally_ranged_range`). At 6, a hero would
  walk on under fire it never answers, or walk 6 units into danger before shooting.

Advance pursues the squad's assigned objective without a cohesion leash. Stay Together uses
the lowest living spawn index as leader, who waits when a living member is over 6 units away;
followers regroup within 4 and engage threats within 6 of the leader. Defend anchors at the
squad's current centroid, holds within 4 and pursues only threats within 4 of that anchor.
Protect stays within 4 of the squad's explicit guard target, falling back to its living member
with the lowest maximum HP (spawn order breaks ties). Direct commands override stances.

Enemies detect living opponents within 12 units and pursue at most 18 from their saved spawn
home, returning home when the target leaves that leash. Squads divide active capture/camp
objectives before choosing enemies within 12 of their assigned site. Escort squads follow the
cart together and engage nearby threats; future waypoints do not draw squads away from it.

### Hero AI on auto — *ig-uu7, design 2026-09-24*

Four rules make auto allies fight as a party. They apply only to allies on Auto Battle without a
direct order, outside rescue battles, and enemy AI does not change. Precedence: direct order
(attack-move included, § Attack-move above), then evasion, then a hop, then the stance's own
regroup, anchor or guard move, then cover or formation, then the stance's usual target. Anything that returns earlier in the planning pass (the rescue
carry, the supplies retreat) wins without a check. Rows are those of § Archetypes: the front row is
Knight and Rogue, the back row is Ranger, Mage and Cleric.

**A piloted hero is not on auto** (`ig-gy0.6`, design 2026-09-24). While the player controls it:
- None of this section's rules move it: no evasion, hop, stance move, cover or formation. It
  claims no telegraph, so the claim passes to the next hero (§ Skills, Counters).
- It moves only on the player's orders. After a target order it closes in and swings, as the
  order does today. After a move order it holds at the point and swings only at a target in reach.
  When its target dies it picks no new one. It stands until the player picks.
- Anything that returns earlier in the planning pass (the rescue carry, the supplies retreat)
  still wins, as it does over any direct order.
- To the other heroes it is an ordinary squadmate. It still counts as the front-liner for
  formation and hop points. A piloted Knight's target still keeps other Knights off that threat,
  and its hits still give the cover taunt ("auto or not", below).
- Its chains run when the player fires a trigger, with no cut-ins, because cut-ins are the AI's. A
  skill fired by hand that is not a trigger leaves the chain running.
- Piloting is view state and never saved. When it ends, the hero is on auto again on the next tick.

**Formation.** A back-row hero never walks closer to its reference point (its attack target, else
its squad's objective point) than its squad's nearest living front-liner is, plus one formation
spacing (1.8). Already that close, it holds. The rule is off while a living enemy is within the
hero's contact range, `max(battle_detection_range, its attack range)`, and when its squad has no
living front-liner. Contact range is the enemy detection range, so the first enemy to notice the
squad finds a front-liner nearer. It applies under Advance and Stay Together only; Defend and
Protect already hold the squad on one spot. Stay Together targets lie inside contact range (within
6 of a leader the hero stays within 4 of), so there it shapes only the march. A back-row hero may
pause while its front-liner is busy elsewhere, and moves on when the front-liner does.

**Cover.** A Knight covers a back-row ally of its own squad that an enemy is on. A threat is a
living enemy targeting such an ally, inside the Knight's stance zone: within 6 of the leader (Stay
Together), 4 of the anchor (Defend), 4 of the guarded ally (Protect) or 12 of the Knight (Advance).
Cover chooses only after the stance's regroup, anchor or guard check, so it never pulls a Knight out
of its stance. A Knight keeps its threat while it stays a threat, and never takes one that another
Knight is already targeting. A new pick takes the victim first in its cover order (below), then the
lowest victim HP fraction, then the nearest threat, then spawn order. Rogues do not cover.

Every Knight hit (any direct hit: a basic, a weaponskill or an ability, auto or not; not a bleed or burn tick) on an enemy targeting a back-row ally gives
that enemy a taunt from the Knight (`battle_cover_taunt_seconds`), the same status Gauntlet Toss
uses. The enemy switches on the next tick, when enemy targets are chosen, and stays on the Knight
after the taunt ends because enemies keep their target. Gauntlet Toss aims at the covered threat
first (§ The v1 kits, Knight).

**Kiting.** A back-row hero whose attack range exceeds `battle_kite_trigger_range` hops once when
a living enemy targeting it comes that close and its hop is ready. The hop point sits one formation
spacing behind its own squad's nearest living front-liner, as seen from that enemy, so the tank ends up between
them. With no living front-liner, or when that point would end nearer the enemy, it hops straight
away instead. A hop is at most `battle_kite_distance` long and clamped to the battle bounds. A clamp
that leaves under half of that (cornered) means no hop: stand and fight. The hop ends on arrival or
once no living enemy targets the hero, and the next is ready `battle_kite_cooldown_seconds` after
this one started. A hop lasts at most the time to cover `battle_kite_distance` at the hero's speed, plus
one tick, so bodies pinning it short of its point can't hold it forever. Evasion cancels a hop in flight; the cooldown stays spent. After a hop the
stance's own return applies as usual. Clerics swing at melee range 1.6 and would hop, walk back to
swing and hop again, so the range test leaves them out; formation and cover still protect them.

**Bonds.** A Knight's cover order lists its bond partner first when the partner is a back-row
teammate, then the other back-row teammates it has bond points with, most first, spawn order
breaking ties. It is read from the Bonds pair index once per launch and snapshotted with the battle
like stats; bonds themselves stay derived (`DECISIONS.md` 2026-09-24 "Bonds stay derived"). A Knight
already covering switches only to a threat on a victim strictly earlier in its cover order, so
claims never ping-pong.

Cost: each back-row hero and each Knight makes at most one extra pass over the battle's actors per
tick and works on the short list it collects; the worst case is Frontier March, 50 heroes against
30. Saved state is three optional actor `effect_state` keys, each validated only when present:
`kite_point` (two finite numbers), `kite_ready_tick` (a non-negative integer) and `cover_order`
(hero id Strings). A new run clears the two kite keys. `SIMULATION_VERSION` stays 1.

| `balance.tres` field | Value | Why |
|---|---|---|
| `battle_kite_trigger_range` | 3.0 | Melee 1.6 plus a step: about 0.9 s of warning before a 1.5 u/s enemy can swing |
| `battle_kite_distance` | 4.0 | One hop clears the trigger zone even after the enemy's ~1.6 u of pursuit during it (3 + 4 − 1.6 > 3) |
| `battle_kite_cooldown_seconds` | 5.0 | At most 12 hops a minute. Each cycle is about 1 s hopping, 2.5 s shooting while the enemy walks back, then 1.5 s in reach |
| `battle_cover_taunt_seconds` | 3.0 | Equals `battle_basic_interval_max`, so a pull outlasts the gap to the Knight's next hit at any SPD; enemy stickiness holds it after that |

> ⚠️ **PROVISIONAL** — all four come from the arithmetic above, none from play · **Settled by:** the
> ig-uu7 balance gate on the eight ig-544 starter cases once .3 and .4 land, plus one played run
> watching a back-row hero under melee pressure

### Provisional shared combat numbers

All values are starting points, not a claim of tested game feel. Shared values belong in
`balance.tres`; kit values belong in their ability Resources. A director ruling is required
before changing these values based on measurements.

| Rule | Initial value |
|---|---|
| Basic damage before crit/effects | `max(1, ATK * 100 / (100 + DEF))` |
| Basic attack interval | `clamp(100 / SPD, 0.3, 3.0)` seconds |
| Attack windup | 0.3 seconds |
| Movement | `clamp(SPD * 0.04, 1.5, 5.0)` units/second |
| Basic melee / ranged range | 1.6 / 8.0 units |
| Ally ranged range (ranger, mage) | 12.0 units (owner ruling 2026-09-24: "our ranged heroes" stood too close; enemies keep 8.0; `basic_range` still multiplies it) |
| Separation / formation spacing | 0.65 / 1.8 units |
| Guard distance | 4 units |
| Enemy HP / ATK / DEF from per-enemy wave budget | budget × 1.15 / × 0.03 / × 0.10 (`ig-el4`; was × 1 / × 0.04) |
| Enemy SPD / crit rate / crit damage | 20 / 0.05 / 1.5 |

Per-enemy budget is `Wave` power scaled by deployed force/reference force, divided by the
authored enemy count. The reference force is five for existing zones, thirty for Fallen
Citadel and fifty for Frontier March. Enemy archetypes cycle Knight, Knight, Ranger, Mage,
Rogue; they use the same signatures/passives with their own faction, cannot consume allied
supplies, and die at zero HP. Elite marks an objective/visual role, not an extra stat bonus.

> **History, measured with the ig-9gf reach bug.** Every clear time and downing count in the next
> paragraph and in both "Restated 2026-09-24" blocks below came from a sim where a unit walking to
> a still target could stop a float32 hair outside reach and never act. The multipliers they name
> were × 1 / × 0.04. The current band is the `ig-el4` block after them.

The first HP×2 / ATK×0.20 translation stranded all eight measured F-rank starter runs before
Verdant completion. The director revised only these new enemy conversion multipliers to the
values above. The resource-backed check verified enemy HP/ATK of 90/3.6 for five heroes and
54/2.16 for three. Across seeds 1 and 2, five mixed F-rank level-1 heroes cleared in
60.1–65.6 seconds; three starter Knights cleared in 132.5–173.9 seconds. All eight
team/seed/loadout cases won. Every unsupplied case had at least one downing; the suggested
supplies prevented downings in these samples. These observations establish a playable
starting point, not a broad win-rate or game-feel claim; pacing remains tracked in ig-2ah.
The earlier runtime Resource override that printed candidate values but spawned original
enemies remains invalid evidence. Existing hero stats, zone power/rewards and economic
formulas are unchanged. Evidence: `.agent-results/logs/ig-544-starter-measure-r1.log`.

**Restated 2026-09-24, after the facing fixes.** Since that measurement, the only combat-rule
changes are the two facing fixes: `ig-oit` (970856f) and `ig-hb2` (c8b09e2). Stats, enemy
conversion, zones and kits are unchanged. Rear checks now read real facing. A Rogue no longer
gets a free rear hit on an enemy that stands with its back to the fight, and Flank picks its slot
from where the target really faces. Old code gave the faster times, but it was wrong, so the band
is restated rather than restored. The same eight cases now measure:

- **Five mixed heroes: 72.5–79.0 s.** All four won. This is the current band. It replaces
  60.1–65.6 as the target for later tuning.
- **Three starter Knights:** seed 1 won (130.3 s bare, 125.5 s supplied). Seed 2 timed out at
  180 s, bare and supplied. It is not a stall. The Knights were still trading blows and reviving
  each other with Rally when the clock ran out. The lone final-wave boss was 87% dead (bare) and
  57% dead (supplied). This case sits on the timeout edge: the old top was 173.9 of 180 s. Small
  early changes swing it by tens of seconds either way. In the same change, seed 1 went from
  173.9 to 130.3 s.

Evidence: `.agent-results/ig-gy0.1/golden_before.json`, captured before any `ig-gy0.1` edit.

**Restated 2026-09-24, after kiting (`ig-uu7.3`, the epic's balance gate).** The band above was
already stale before kiting: the tree just before `ig-uu7.3` measured 60.9–86.8 s mixed. The same
eight cases, before kiting, then with it:

| Case | Before kiting (s, downings) | With kiting (s, downings, hops) |
|---|---|---|
| mixed:1 | 86.8, 5 | 65.9, 2, 2 |
| mixed_suggested:1 | 60.9, 0 | 66.6, 0, 2 |
| mixed:2 | 73.3, 1 | 83.3, 4, 6 |
| mixed_suggested:2 | 73.0, 1 | 70.6, 0, 2 |
| starter_knights:1 / suggested:1 | 138.0, 3 / 173.5, 0 | the same (Knights never hop) |
| starter_knights:2 / suggested:2 | 169.2, 1 / timeout 180, 1 | the same |

- **Five mixed heroes: 65.9–83.3 s.** All four won. This is the current band.
- **Three starter Knights:** unchanged. Seed 2 supplied still times out on the edge described above.
- No loss, and no new downing in a supplied case.
- mixed:1 is 24% faster, past the gate's 15% line. Accepted (design verdict, 2026-09-24): the gate
  catches regressions. A clear that is faster and has fewer downings (5 → 2) is the back row
  surviving, which is what kiting is for. The gate counts a time shift over 15% when it is slower,
  or faster with more downings.
- mixed:2 (+14%, downings 1 → 4, bare) is under the line and accepted. The cause is not known yet.
  The mixed team has no Cleric and the case has no supplies, so a hop can't take anyone out of
  healing. The reach effects that guard this team are the Knights' Close Ranks and Stand Fast
  (within 3), and a hop moves toward a Knight. The open suspect is where a hop lands. The hop point is set against the one
  enemy chasing the hero, so a chase from behind the squad lands the hero 1.8 past its Knight,
  toward the enemies the Knight is fighting.

Evidence: `.agent-results/ig-uu7.3/balance_gate.gd`, `balance_head.log`, `balance_new.log`.

**Restated 2026-09-24, after the reach fix and its retune (`ig-9gf`, `ig-el4`).** The fix makes
melee land for both sides. The same eight cases:

| Case | Before the fix (s, downings) | Fix, old enemy values | Retuned |
|---|---|---|---|
| mixed:1 | 65.9, 2 | 68.2, 5 | 66.2, 2 |
| mixed_suggested:1 | 66.6, 0 | 56.7, 1 | 65.5, 0 |
| mixed:2 | 83.3, 4 | 70.8, 6 | 78.6, 4 |
| mixed_suggested:2 | 70.6, 0 | 56.9, 0 | 62.9, 1 |
| starter_knights:1 | 138.0, 3 | stranded 98.8, 3 | 116.4, 1 |
| starter_knights_suggested:1 | 173.5, 0 | 96.4, 0 | 116.4, 0 |
| starter_knights:2 | 169.2, 1 | stranded 112.2, 4 | 113.8, 2 |
| starter_knights_suggested:2 | timeout 180, 1 | 100.1, 0 | 112.2, 0 |

- The retune: enemy ATK multiplier 0.04 → 0.03, HP 1.0 → 1.15 (table above). It was picked from a
  six-config grid over seeds 1–4.
- **Five mixed heroes: 62.9–78.6 s.** All won. This is the current band.
- **Three starter Knights: 112.2–116.4 s.** All won, including seed 2 supplied, which used to time
  out. The Knights' old 138–180 s was mostly the bug (Knights parked beside a still boss), so it
  is not restored.
- ATK brings survival back. Nearly every new downing was an enemy Knight's hit that now landed.
  Both bare Knights losses were the final-wave boss, a single enemy holding the whole wave budget.
- HP brings the mixed clear time back to the band the owner has been playing.
- One waiver (director, 2026-09-24): mixed_suggested:2 has 1 downing where the pre-fix run had 0.
  Over seeds 1–4, every candidate had exactly one supplied downing. The configs that passed on
  seeds 1–2 had theirs on seed 4. The retuned values win all 16 runs on seeds 1–4.
- Pins moved with it. The pre-skills checkpoint fight goes from stranded at 71.7 s to a win at
  92.7 s. The formation digests changed for the Ranger, Mage and Cleric fights (advance and
  stay_together). The two Knight-party fights didn't change.

> ⚠️ **PROVISIONAL** — picked on eight cases and four seeds at Verdant, F-rank level 1, and not yet
> played · **Settled by:** the owner playing the retuned build, then the `ig-eek` mid and late stage
> saves

Evidence: `.agent-results/ig-9gf/balance_head.log` and `balance_final.log`;
`.agent-results/ig-el4/table.txt` (the grid) and `balance_final.log` (the real `balance.tres`).

| Hero kit | Signature | Passive |
|---|---|---|
| Knight | Stand Fast: 16s cooldown; revive a downed ally within 3 to 25% HP, otherwise guard allies within radius 3 for 4s with 30% damage reduction | 10% damage reduction within 3 of another living ally; multiplicative with one Stand Fast effect |
| Ranger | Threadneedle: 10s cooldown, range 10, line width 1, 1.8× attack damage | +20% basic range |
| Mage | Arcane Bloom: 12s cooldown, range 8, radius 2.5, 1.5× attack damage; auto prefers at least 3 enemies or an elite | Signature cooldown reduced by 10% |
| Rogue | Turncoat Cut: 10s cooldown, range 6, moves to an available rear slot, interrupts windup with 0.3s stagger, 1.6× attack damage | +25% basic damage from behind |

**Spawn facing (director ruling, 2026-09-23):** both sides spawn facing the other side's centre; "behind" reads actual facing, so a Rogue earns the rear bonus by flanking a unit turned toward someone else, never from spawn orientation.
> ⚠️ **PROVISIONAL** — how often an idle-flank bonus now lands is unmeasured · **Settled by:** a played build

The four kits add effects and decision rules, not a seventh hero stat. Multiple Stand Fast effects
do not stack their reduction; use the strongest active effect. Knight's ally-proximity
passive requires another actor, not the Knight itself.
Turncoat Cut tests the rear center and then rear ±45-degree positions against actor separation;
when all are occupied, it refuses without spending cooldown. Ranger's fixed enemy telegraph spans
its full authored range along the chosen direction.

### Knockback — *ig-n9r, proposed 2026-09-23*

A qualifying hit moves its living target instantly, in the same tick, away from the hit's
source. No new saved state: no velocity, no timer, no per-target cooldown field. The push
rewrites `position` (already saved and bounds-validated) and reads only fields that already
save: `facing`, `effect_state.last_crit_tick`, `effect_state.elite`, `carrying_id`.

| Hit (either faction) | Push | Away from |
|---|---|---|
| Basic attack that crits | 1.0 units, crit gate below | the attacker |
| Ranger Threadneedle, each target | 1.0 units | along the shot line |
| Mage Arcane Bloom, each target | 1.5 units | the burst center |
| Knight Stand Fast, Rogue Turncoat Cut, Cleric | none | — |

> ⚠️ **PROVISIONAL** — the three push distances and the 1.0 s crit gate are arithmetic only (sustained crit pushes stay under the 1.5 u/s every enemy walks at), never seen on screen · **Settled by:** a played build plus the ig-544 starter re-measure below

- **One push per hit.** Skill hits push by the table whether or not they crit; basic hits push
  only on a crit. Crit push and gate live in `balance.tres`; skill pushes on their ability
  Resources.
- **Crit gate.** A basic crit pushes only if the target's previous crit (`last_crit_tick`, read
  before this hit writes it) is at least 10 ticks (1.0 s) old. Closer crits still deal crit
  damage. Crit push on one target therefore caps at 1.0 u/s however many attackers it has.
  Skill pushes are not gated; their cooldowns bound them.
- **Immune:** elites, and any hit that downs or kills, so bodies stay where revive and carry
  expect them.
- **No interrupt.** A push never cancels a windup, telegraph or carry; stagger stays Rogue's
  job. A telegraph stays where it was drawn. An attacker whose target was pushed out of range
  holds its finished windup and strikes on reaching range again.
- **Area hits resolve, then push.** Threadneedle and Arcane Bloom compute every hit at pre-push
  positions, then apply all pushes, so Knight proximity reduction never depends on actor order.
- **Bounds:** clamp the landing point to the battlefield square; a wall shortens the push. No
  bounce, no impact damage. Overlaps resolve through normal separation next tick.
- **Carry:** a pushed carrier takes its carried body along in the same tick. A push that takes a
  channeling carrier beyond 1.5 of the body pauses the channel; it resumes, never restarts, once
  the carrier is back in range (carry rule, Downed heroes and rescue).
- **Determinism:** a push draws no RNG. If source and target coincide, push along the attacker's
  `facing`. Orders, stances, leash and evasion are unchanged; the actor re-plans from where it
  landed.

**Balance.** Ranged heroes gain: pushes delay melee enemies, who all walk at 1.5 u/s. Melee
heroes pay a re-close of at most 1.0 unit after their own crit push (0.2–0.7 s at 1.5–5 u/s).
At base crit rates of 5–15% this is a light touch, not a swing. Pushing enemies out of a seal
or cart radius helps; an enemy push can break an ally's seal hold. The forecast needs no special
case: its stress run forces enemy crits (more gated pushes on allies) and suppresses ally crits
(no ally crit pushes; skill pushes remain), so it stays the harsher run and "safe" keeps its
definition. No existing number moves, but the ig-544 starter evidence goes stale: the
implementation re-runs those eight cases on the same seeds, and any loss, any new downing in a
supplied case, or a clear-time shift over 15% returns this to design. Known ceiling: skill
pushes stack per caster, so five Mages bursting one target outpace a 1.5 u/s walk; accepted
because elites are immune and clustered trash is meant to fall.

Rejected: velocity or a knockback timer, and a per-target push cooldown field (new saved state,
boundary #1; the `last_crit_tick` gate replaces the cooldown); interrupting pushes (steal
Rogue's role, and crit-heavy teams would erase enemy signatures); a Stand Fast pulse (shoves enemies
off the Knight holding them); a Turncoat Cut push (throws the target out of the rear slot Turncoat
Cut just took); pushing on the killing hit (moves bodies rescue depends on).

### Supplies and automation

Profile supplies are integer `healing` and `revival` stocks. New profiles and schema migration
receive 3 healing and 1 revival once. Crafting costs 5 F parts per healing draught and 15 F
parts per revival draught, through exact preview and transactional confirmation.

Loadouts specify per-force allocations and stockpile keep-at-least floors; allocations are
limited to 100 of each item per run. Suggested allocation is one healing item per hero and
one revival per squad, but zero is valid. Dispatch and each repeat reserve the full selected
allocation or refuse with a visible reason; no silent partial refill. Unused allocation is
refunded exactly once at settlement, including a wipe. This is a spending budget, not a
physical bag that disappears with a body.

The initial dispatch form allocates zero until configured. Its suggested-fill action sets one
healing item per selected hero and one revival per squad. Independent-team dispatch labels
the allocation per order and suggests the largest selected team's size plus one revival;
combined dispatch labels it per force.

Healing restores 40% maximum HP; revival restores 35%. Each living user has a 15-second item
cooldown. Revival requires a different downed ally within 3 units. Auto heal defaults to
below 35% HP. Auto heal/revive and signature use default on; reserve-last-revival and
retreat-when-supplies-empty default off. Reserving the final revival blocks automatic use
only; the player may spend it manually. Auto Battle defaults on and stance to stay together.

Repeat safety uses the exact unattended simulation for the proposed seed plus a stress run
with enemy criticals forced and allied criticals suppressed. Both must win without downings,
with valid supplies/reserves. This forecast is not an unconditional promise after manual
intervention. Finite orders also stop after downing, withdrawal, wipe, missing member,
insufficient refill or a stop request.

### Authored missions and force sizes

Existing zones retain their power ramps/rewards and use five enemies per trash wave, followed
by one elite boss. The standard battlefield spans ±20 units, with enemies centered at (0,8)
and extraction at (0,-16). Formation rows use the authored 1.8-unit spacing.

| Mission | Force cap / reference | Route base / floor | Combat bound | Starting power/reward |
|---|---|---|---|---|
| Existing standard zones | 5 / 5 | Existing authored values | 180s | Existing values |
| Fallen Citadel | 30 / 30 | 600s / 120s | 300s | 6× Ashfall recommended power; 3× its rewards, same initial loot ranks |
| Frontier March | 50 / 50 | 900s / 180s | 420s | 10× Ashfall recommended power; 5× its rewards, same initial loot ranks |

Both new missions unlock after Ashfall. Duration scales against the mission's own reference
force, keeping its workload factor; adding raid capacity cannot accelerate Verdant income.
Timeout withdraws living actors and strands downed actors not extracted.

Fallen Citadel spans ±35. West/North/East seals at (-16,4), (0,14), (16,4), each radius 3,
must all be held by living allies with no enemies inside for 10 continuous seconds. This
unlocks the boss. The capture encounter has 30 enemies, ten per site; the boss encounter has
one elite and ten adds sharing the authored wave budget. Extraction is (0,-31).

Frontier March spans ±50. Camps at (-24,-18), (22,-2), (-18,20) contain ten enemies each.
After clearing them, escort a cart from (0,-40) through (-16,-20), (16,10), (0,40). The cart
moves at 1.5 units/second only with an ally within 4 and no enemy within 4. Ten-enemy patrol
waves arrive at waypoints one and two, and one elite contests the final waypoint. Hero
extraction is (0,-46). Auto squads divide objectives deterministically; commands override.

Normal victory retains the existing stone reward and one loot roll. Secured heroes receive
the existing completed-wave XP plus zone XP, with Training Hall bonus. Other normal outcomes
credit completed-wave XP only to returned/extracted heroes, with no stone, loot or clear
unlock. Each settled normal run increments the historical turn once. Rescue attempts award
no mission rewards or turns and cannot reroll the source mission's loot.

Victory calls `Expedition.roll_loot(zone, balance, order.run_seed)` once inside settlement.
The stored run seed fixes the reward without consuming combat RNG. A failed save rolls back
the reward and its inventory insertion; retry uses the same reward seed.

### Downed heroes and rescue

Zero HP downs allied heroes without deleting them or moving their equipment to a cache.
Any living ally in the deployed force keeps combat active. Victory secures every ally.
Revival returns someone to the current fight; carrying secures them at extraction. Carry
requires an ally within 1.5 and one second of channeling beside the body (designer ruling,
2026-09-24, `ig-ls3`). The second need not be unbroken: leaving the 1.5 range (a push, a
dodge), a stun or a root pauses the channel, and it resumes where it stopped. The progress
belongs to one carrier and one body. It starts over on a new order or a new body, and when
the body is revived or taken by another carrier, or the carrier is downed. Why: a push never
interrupts, and with a restart rule a crit push every second (the crit gate's cap) or a stun
chain could hold off a rescue for good. Carry permits one body per carrier, reduces movement
to 65%, and extracts both within 2 of the exit. Downing the carrier drops the body. A retreat
only secures downed heroes actually carried out.

One stranded incident belongs to one source battle; unrelated wipes in the same zone never
merge. It preserves the battlefield and reserved hero/equipment identities. A rescue uses
up to five new heroes, independently of the original deployment cap. Extraction can succeed
partially; failed rescuers join that same incident. No automatic rescue dispatch.

Rescue attempts settle as soon as their combat/extraction simulation ends, with no additional
expedition return timer. Their fight still runs at normal speed and requires actual extraction.
The raid's five-hero return floor would otherwise be 720 seconds, and the region's 1800 seconds,
against a 900-second initial rescue window, obstructing successive carry attempts. Rescues grant
no farming rewards; ordinary expeditions keep their full return gates.

A full wipe commits its incident and closes the source order immediately. After a partial
withdrawal, returning survivors retain the route minimum; arrival creates the incident for
the heroes left behind and closes the source order in one transaction. This ensures a hero
is never both available for rescue/abandonment and still reserved by the source order.

Within an explicitly dispatched rescue, Auto Battle assigns rescuers to the nearest
unassigned body, breaking ties by spawn order. They approach, use a permitted revival if
available, otherwise carry to extraction. Revived incident heroes and rescuers with no
unassigned body withdraw unless manually commanded. Manual mode retains player orders;
rescuing does not require clearing all enemies.

Each incident has a reviewed active-play lifetime of `900 + 300 * Reliquary_level` seconds,
separate from existing gear-cache timing. A new incident waits paused for review; starting
its first rescue also acknowledges it. Failure neither resets nor pauses its age. Expiry
blocks new attempts, while a rescue already dispatched may finish. Its settlement first
secures extracted heroes, then finalizes only the remaining stranded heroes if expired.
Abandonment requires explicit confirmation and cannot occur during an active rescue.

Final deaths go through Expedition's one finalization entry point and GameSession's existing
sole removal writer; only then does ordinary lost-gear cache recovery apply. Rescue time does
not advance offline. These timings and the new combat economy require separate playtesting.

---

## Skills — *ig-gy0, accepted 2026-09-23*

Design: `GAME_SPEC.md` § Skills. Boundaries: `DECISIONS.md` 2026-09-23, skills. Each skill is an
`AbilityDefinition` Resource (rule 9: kit values live there). The shared numbers below are
`balance.tres` rows.

> ⚠️ **PROVISIONAL** — every number in this section is a desk guess. None has been played.
> · **Settled by:** a played build of the kit slice, then the balance pass (both in `ig-gy0`).

### Shared rules

| Row | Value | What it does |
|---|---|---|
| `skill_ability_lock_seconds` | 1.0 | After any ability, the hero waits this long before the next ability |
| `skill_combo_window_seconds` | 6.0 | A combo step gets its bonus only this soon after the step before it |
| `skill_reaction_delay_seconds` | 0.2 | How long after a telegraph starts before a hero may answer it |
| `skill_chain_step_timeout_seconds` | 3.0 | A chain step that cannot fire within this is skipped |
| `skill_chain_max_steps` | 8 | Skills after the trigger, per chain |
| `skill_status_tick_seconds` | 1.0 | Bleed, burn and heal-over-time tick once a second |
| `skill_book_drop_chance` | 0.02 / 0.04 / 0.06 | Per clear, Verdant / Ashfall / Sundered (a `ZoneDefinition` value) |
| `training_hall_teach_levels_per_level` | 5 | A hall at level `L` teaches skills up to `hero.level + 5 * L` |
| `training_hall_teach_parts_per_unlock_level` | 3 | F parts per unlock level: a level-25 skill costs 75 |
| `skill_book_general_share` | 0.5 | Share of book drops that are general books |
| `training_hall_general_parts` | 20 / 40 / 80 | F parts to teach a general skill of tier 1 / 2 / 3 |

**Weaponskills ride the swing.** A weaponskill fires in place of a basic attack. It uses the same
0.3 s windup and resets the same `clamp(100 / SPD, 0.3, 3.0)` interval. So the number of
weaponskills never changes how often a hero hits, only how hard.

**Abilities have their own cooldown,** plus the shared ability lock. Today's signatures fire
between swings without touching the swing timer. That stays.

**Statuses.** Stun, shield, damage reduction, stat changes, bleed, burn, heal over time, root,
silence and taunt. Damage reduction does not stack: the strongest one applies (today's Stand Fast
rule). A shield absorbs damage before HP. The same status from any source refreshes, never
stacks. Stat changes read and change five of the six stats: ATK, DEF, SPD, CRIT_RATE and
CRIT_DMG.

**Amended 2026-09-24 (director rulings).**
- v1 has no HP stat status. No skill needs one, and validation rejects it.
- An SPD change (Hunter's Focus) changes only the swing interval.
- Taunt (Gauntlet Toss) changes only whom the enemy targets.

**Counters.** A counter is an ability with one tag:

| Tag | What it does to a telegraph |
|---|---|
| `stun` | Stuns the caster. A stun already cancels a pending action today, so the telegraph is gone |
| `interrupt` | Cancels the caster's windup or telegraph, with no stun |
| `shield` | Shields or protects the ally or allies inside the telegraph |
| `dodge` | The user steps out, and the telegraph misses it if it resolves within 1 s |

**The AI's answer.** When an enemy telegraph has run `skill_reaction_delay_seconds`, each hero in
stable spawn order may claim it. The first hero with a stun or interrupt in range claims it and
fires. If none, the first with a shield covering someone inside it does. If none, each hero
inside it with a dodge uses it. Everyone else in it walks out, as today. Among a hero's usable
counters it picks the shortest cooldown. One claim per telegraph.

**Amended 2026-09-24 (director ruling): shields and self damage reduction sit in the heal band.**
Stone Posture, Anvilheart, Sheltering Word and Warding Glyph answer a low ally, in the picker's heal
band (`DECISIONS.md` 2026-09-23, item 7: counter, revive, heal, chain, buff, attack). The low-HP
half of each one's "AI uses it when" cell is that rule. A tie with a heal goes by bar order, so the
player's order decides. The telegraph half of each cell arrives with the counters slice, `ig-gy0.4`.

**Chains** (`ig-gy0.5`, design 2026-09-24). The two chain rows above cap and time them.
- **Steps.** Any known skill except the passive can be a trigger or a step, weaponskills included.
  A skill may repeat in a chain (Iron Cut, Follow-Through, Iron Cut), since weaponskills have no
  cooldown. One chain per trigger. On load, a chain over `skill_chain_max_steps` is cut to the cap
  with a `push_warning`, so lowering the cap never deletes a player's chain. Today's other checks
  stand (an unknown or unlearned skill drops the chain).
- **Why 8.** A full kit has seven skills besides the passive. So a chain holds its trigger and the
  other six class skills, with two steps to spare for repeats or general skills. It also bounds a
  chain that skips every step: 8 × 3.0 = 24 s at most.
- **Start.** With no chain running, a trigger starts its chain however it fires: by the picker, as
  a cut-in (so "after my stun, follow with..." works) or by hand. While one runs, only a trigger
  fired by hand replaces it. A chain step never starts a chain.
- **When a step fires.** When it could be fired by hand: off cooldown, the ability lock clear for
  an ability, a swing due for a weaponskill, not stunned or silenced, and a legal target in range.
  Its "AI uses it when" cell is ignored, because the chain is the player saying when. An Off step
  is skipped at once, and a Manual step fires (`DECISIONS.md` 2026-09-23, item 6). Enemy steps aim
  at the hero's target. Self, ally and area steps pick theirs as the picker does, without the
  cell's threshold. A chain never moves the hero: a step out of range waits.
- **Waiting.** Until the next step is ready, the hero keeps swinging (a basic, or the picker's
  weaponskill) but fires no ability outside the chain. Each step must fire within
  `skill_chain_step_timeout_seconds` of the one before it, or of the trigger, or it is skipped. The
  deadline is a saved tick number, and a step may fire on that tick itself. So a timer never ties
  on a float (`ig-85w`), and a weaponskill step always makes the next swing, even at
  `battle_basic_interval_max` (3.0 s).
- **Cut-ins.** Everything above chain in the picker cuts in: counter, revive and heal, including the
  heal band's shields and self damage reduction (`DECISIONS.md` 2026-09-23, item 7). A cut-in
  never ends the chain, and the step's deadline keeps running.
- **End.** The last step fires or is skipped, the hero's target dies or changes (a cover switch or
  a target order), a new trigger replaces the chain, or the hero is downed.
- **Saved.** Four optional actor `effect_state` keys, each validated only when present (the § Hero
  AI on auto pattern): `chain_trigger` (a skill id), `chain_step` (a non-negative integer index
  into its `then`), `chain_deadline_tick` (a non-negative integer) and `chain_target` (an actor
  id). A reload mid-chain resumes it. `SIMULATION_VERSION` stays 1.

### Learning

| Opens at | Slot in every kit |
|---|---|
| Level 1 | The passive, the signature and a starter weaponskill |
| Level 5 | A combo step and a counter |
| Level 15 | A sixth skill |
| Level 25 | A seventh skill |
| Book only | An eighth skill, at any level |

**Amended 2026-09-24 (director ruling).** Heroes start at level 0, and every level check reads
level 0 as level 1 (`max(level, 1)`): skill unlocks, the general tier minimums and the hall's
reach (`hero.level + 5 * hall level`). So a new hero has its level-1 skills.

Level caps by rank (§ Ranks) set how many class skills a hero can reach: F (cap 10) five, D (cap
20) six, C and above (cap 30+) seven, plus its class book skill. General skills come on top (below).
With the v1 pools, a hero can know at most 8 class + 6 general = 14 skills. A Training Hall teaches ahead of level for parts, up to
`hero.level + 5 * hall level`. Taught and book skills are saved on the hero. Level skills are
derived from level and archetype, so they cannot fall out of step with it.

**The general pool: tiers and gating** (owner ruling, 2026-09-23: class plus a shared pool).
General skills never open by level. Each has a tier:

| Tier | Minimum hero level | Training Hall level to teach it | Hall cost |
|---|---|---|---|
| 1 | 1 | 1 | 20 F parts |
| 2 | 10 (F's cap) | 2 | 40 F parts |
| 3 | 20 (D's cap) | 3 | 80 F parts |

A general book teaches its one skill to any hero at or above the minimum level, whatever the hall
level. Half of all book drops are general books (`skill_book_general_share`), picked uniformly
from the pool. The other half are class books, as before. Tiers 4 and 5 are left for later pools,
since the hall caps at level 5.

**Skill books and the spine.** A book drop is an extra roll on a clear. It never replaces Summon
Stones, parts or Essence, and no Essence formula reads skills (`compute_essence_yield` reads rank
and level). Books cannot be salvaged or sold. So ~327 → ~219 → ~188 does not move. A book teaches
one skill. Its class is picked at random, weighted by your roster's archetypes.

### The v1 kits

Five kits of eight. The four signatures and passives keep today's numbers exactly, so the first
slice can prove that nothing changed. Multipliers are on the basic damage formula. "Heal 3.0 ATK"
means ATK times 3.0. The counter column is the tag.

**Renamed 2026-09-24 (director; `DECISIONS.md` 2026-09-23, item 10: no Square Enix skill name,
no close copy).** Display names only. Older text that says Burst, Bulwark, Rally or Flank means
these skills. The last six rows come from the one-time web-checked sweep, `ig-x8g` (evidence:
`.agent-results/ig-x8g/names.md`).

| Old name | New name | Id |
|---|---|---|
| Bulwark | Close Ranks | `knight_bulwark` (kept: saves may hold it) |
| Rally | Stand Fast | `knight_rally` (kept: saves may hold it) |
| Challenge | Gauntlet Toss | `knight_gauntlet_toss` |
| Last Stand | Anvilheart | `knight_anvilheart` |
| Blindside | Knave's Angle | `rogue_blindside` (kept: saves may hold it) |
| Steady Shot | Heron Shot | `ranger_heron_shot` |
| Burst | Arcane Bloom | `mage_burst` (kept: saves may hold it) |
| Blaze | Tinder Hex | `mage_tinder_hex` |
| Skyfall | Hanging Star | `mage_hanging_star` |
| Smite | Censer Swing | `cleric_censer_swing` |
| Rekindle | Hearthcall | `cleric_hearthcall` |
| Flank/Interrupt | Turncoat Cut | `rogue_flank_interrupt` (kept) |
| Piercing Shot | Threadneedle | `ranger_piercing_shot` (kept) |
| Pinning Shot | Burr Arrow | `ranger_pinning_shot` (kept) |
| Brace | Stone Posture | `general_brace` (kept) |
| Disrupt | Break Cadence | `general_disrupt` (kept) |
| Tumble | Dust Roll | `general_tumble` (kept) |

**Knight** (tank)

| Skill | Kind | Opens | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|---|
| Close Ranks | Passive | 1 | — | Today's: 10% less damage within 3 of another living ally | always | — |
| Stand Fast | Ability | 1 | 16 s | Today's: revive a downed ally within 3 to 25% HP, else allies within 3 take 30% less damage for 4 s | revive first; else 2+ allies within 3 | `shield` |
| Iron Cut | Weaponskill | 1 | — | 1.3×, starts the combo | default | — |
| Follow-Through | Weaponskill | 5 | — | 1.8× right after Iron Cut, else 1.1× | after Iron Cut | — |
| Buckler Blow | Ability | 5 | 20 s | Range 1.6: 0.8×, 1.5 s stun | a telegraph in range | `stun` |
| Gauntlet Toss | Ability | 15 | 15 s | Range 6: taunt for 4 s, so that enemy targets the Knight | the Knight's covered threat (§ Hero AI on auto); else an enemy on a back-row or lower-HP ally | — |
| Sweeping Blow | Weaponskill | 25 | — | 0.9× to every enemy within 2 | 3+ enemies within 2 | — |
| Anvilheart | Ability | book | 60 s | Self: 60% less damage for 5 s | a telegraph on the Knight, or HP below 30% | `shield` |

**Rogue** (melee damage)

| Skill | Kind | Opens | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|---|
| Knave's Angle | Passive | 1 | — | Today's: +25% basic damage from behind | always | — |
| Turncoat Cut | Ability | 1 | 10 s | Today's: move to a rear slot, 0.3 s stun, 1.6× | today's rule; also a telegraph in range | `interrupt` |
| Quick Cut | Weaponskill | 1 | — | 1.2×, starts the combo | default | — |
| Gutting Strike | Weaponskill | 5 | — | After Quick Cut: 1.5× and bleed 0.2 ATK/s for 6 s, else 1.0× | after Quick Cut | — |
| Slip | Ability | 5 | 12 s | Self: dodge (see Counters), dash 2 out of the danger | the Rogue is inside a telegraph | `dodge` |
| Venom Edge | Ability | 15 | 30 s | Self: ATK +15% for 10 s | a fight is on | — |
| Knife Flurry | Weaponskill | 25 | — | 0.8× to every enemy within 2.5 | 3+ enemies within 2.5 | — |
| Deathmark | Ability | book | 45 s | 3.0× to a target below 30% HP | target below 30% | — |

**Ranger** (ranged damage)

| Skill | Kind | Opens | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|---|
| Long Sight | Passive | 1 | — | Today's: +20% basic range | always | — |
| Threadneedle | Ability | 1 | 10 s | Today's: range 10, line width 1, 1.8× | today's rule | — |
| Heron Shot | Weaponskill | 1 | — | 1.2×, starts the combo | default | — |
| True Mark | Weaponskill | 5 | — | 1.7× right after Heron Shot, else 1.1× | after Heron Shot | — |
| Burr Arrow | Ability | 5 | 15 s | Range 10: 0.5×, interrupt, 1 s root | a telegraph in range | `interrupt` |
| Barbed Arrow | Weaponskill | 15 | — | 1.0× and bleed 0.15 ATK/s for 8 s | target not bleeding | — |
| Hail of Arrows | Ability | 25 | 20 s | Range 10, radius 3: 0.8× each | 3+ enemies in the circle | — |
| Hunter's Focus | Ability | book | 60 s | Self: SPD +40% for 8 s, which shortens only the swing interval | a fight is on | — |

**Mage** (caster damage)

| Skill | Kind | Opens | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|---|
| Arcane Flow | Passive | 1 | — | Today's: Arcane Bloom cooldown −10%. From the kit slice, every Mage ability | always | — |
| Arcane Bloom | Ability | 1 | 12 s | Today's: range 8, radius 2.5, 1.5× | today's rule: 3+ enemies or an elite | — |
| Ember Bolt | Weaponskill | 1 | — | 1.3×, starts the combo | default | — |
| Tinder Hex | Weaponskill | 5 | — | After Ember Bolt: 1.6× and burn 0.2 ATK/s for 6 s, else 1.1× | after Ember Bolt | — |
| Frost Bind | Ability | 5 | 18 s | Range 8: 0.5×, 1.5 s stun | a telegraph in range | `stun` |
| Chain Spark | Weaponskill | 15 | — | 1.0×, then jumps to 2 more enemies within 3 at 0.6× | 2+ enemies within 3 | — |
| Warding Glyph | Ability | 25 | 25 s | Range 8: shield 2.0 ATK on an ally for 6 s | an ally inside a telegraph, else an ally below 50% | `shield` |
| Hanging Star | Ability | book | 45 s | Range 8, radius 3: 2.5× after a 1.0 s delay | 3+ enemies or an elite | — |

**Cleric** (healer)

| Skill | Kind | Opens | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|---|
| Grace | Passive | 1 | — | +20% to the Cleric's own heals and shields | always | — |
| Mend | Ability | 1 | 8 s | Range 6: heal 3.0 ATK to one ally | an ally below `heal_below` (35%) | — |
| Censer Swing | Weaponskill | 1 | — | 1.1× | default | — |
| Hush | Ability | 5 | 20 s | Range 8: interrupt, 1.5 s silence (no skills) | a telegraph in range | `interrupt` |
| Sheltering Word | Ability | 5 | 20 s | Range 6: shield 2.5 ATK for 8 s | an ally inside a telegraph, else the tank below 50% | `shield` |
| Wellspring | Ability | 15 | 12 s | Range 6: heal 0.3 ATK a second for 10 s | an ally below 70% without it | — |
| Prayer Circle | Ability | 25 | 30 s | Heal 1.5 ATK to every ally within 4 | 3+ allies below 70% | — |
| Hearthcall | Ability | book | 60 s | Range 4: revive a downed ally to 30% HP | a downed ally | — |

The Cleric has no combo, so its level-5 slot is a second counter. Mend's 3.0 ATK is 48 HP at the
Cleric's base ATK of 16: about a third of a base Knight.

### The v1 general pool

Six skills, any class. All are abilities. None is a weaponskill, none deals damage, and none
raises ATK, SPD or crit, so class + general never raises a hero's damage. The general counters
have long cooldowns, so the AI's shortest-cooldown rule reaches for a class counter first and a
general one as the backup.

| Skill | Tier | Cooldown | Effect | AI uses it when | Counter |
|---|---|---|---|---|---|
| Catch Breath | 1 | 60 s | Self: heal 20% of max HP | own HP below 40% | — |
| Field Dressing | 1 | 45 s | Range 2: heal 1.5 ATK to one ally | an ally below 35% and none of the hero's own heals is ready | — |
| Stone Posture | 2 | 40 s | Self: 25% less damage for 4 s | a telegraph on this hero, or HP below 30% | `shield` |
| Dust Roll | 2 | 40 s | Self: dodge, dash 2 out of the danger | the hero is inside a telegraph | `dodge` |
| Break Cadence | 3 | 45 s | Range 1.6: interrupt, no damage | a telegraph in range | `interrupt` |
| Hearten | 3 | 60 s | Allies within 4: DEF +10% for 10 s | a fight is on and 3+ allies are within 4 | — |

Stone Posture's reduction follows the damage-reduction rule: the strongest one applies, so it
never stacks with Stand Fast or Anvilheart. Hearten from two heroes refreshes, never stacks.

**Enemies** (owner ruling, 2026-09-23). Enemies keep today's signatures and telegraphs,
and gain their class's starter weaponskill. Enemy Knights gain **Crushing Blow**: a 1.2 s
telegraph, radius 1.5 on its target, 2.5×, 14 s cooldown. It is the heavy hit that the owner's
example answers with a stun. Enemies do not use chains or the general pool.

### What the kits cost the balance

The combos raise a hero's sustained single-target damage to about 1.4–1.6× its basic swings, and
the new abilities add more. That is a large buff. Enemies with skills only offset part of it.

**Class + general.** The general pool adds no damage. It adds survival: a hero with all six gets
back about 20% of its HP a minute, cuts one telegraph a minute by a quarter or dodges it, and can
patch an ally. That is roughly +20–30% effective HP over a one-minute fight. Its risk is not clear
time but the forecast: `safe` means no downings, so more survival means more orders qualify for
unlimited repeats, sooner.

> ⚠️ **PROVISIONAL** — the kits' effect on clear time is unmeasured · **Settled by:** the balance
> pass, which retunes skill multipliers (not the six stats, not zone power) until five mixed
> F-rank level-1 heroes clear Verdant in the current band again (62.9–78.6 s over seeds 1 and 2,
> restated after `ig-el4` in § Provisional shared combat numbers), and three starter Knights win
> Verdant bare on seeds 1–4. General skills get their own check: a C-rank level-30 team of all five classes with
> full class kits, run at Sundered with and without all six general skills each. With them, clear
> time may fall by at most 10%, and any change in the `safe` verdict is reported to the director.

**Forecast cost.** `BattleSimulation.forecast` runs two full battles per commit, and more skills
mean more work per tick. The first slice measures forecast wall time for a five-hero Verdant
order and a 50-hero Frontier March order. Every later skill slice must stay within 2× that
baseline. A hero with 32 skills is part of that test, because the owner wants 30+ to work.

---

## The Ledger — *ig-m6o.1, accepted 2026-09-24*

The record of settled events that every history reader derives from. The ADR is `DECISIONS.md`
2026-09-24 "The Ledger", and the scope is `ig-m6o.1`.

| Row | Value | Why |
|---|---|---|
| `ledger_max_records` | 10,000 | A routine battle record is a few hundred bytes, so the cap holds the save to roughly 3 MB (an estimate) |
| `battle_max_moments` | 64 | A five-hero battle with every hero downed and revived three times needs 30 moments. A 50-hero region can exceed it; past the cap, `moments_truncated` is set |
| History lines in hero detail | 10 | Newest first. Routine victories at one zone collapse into one line |
| Ledger save budget | ≤ 2 ms | What the ledger may add to any save or profile action, at any size up to the cap. A save's cost must not grow with history. Load compaction and the one-time recovery rewrite are exempt (`DECISIONS.md` The Ledger, item 8) |

The eviction order is tiered, oldest first within each tier: routine victory `battle` records (no
moments, no rescued heroes), then other `battle` records, then `ranked_up`, then `summoned`, and
`died` last (`DECISIONS.md` 2026-09-24, director amendment).

**Measured 2026-09-24 (`ig-m6o.1` acceptance, `.agent-results/ig-m6o.1/gut_ledger2.log`).** At
10,000 records, a real save takes 108 ms and a load takes 197 ms. The file is 3.88 MB, about 390
bytes a record.
- Every profile action and every 15 s periodic save rewrites the whole ledger, so the hitch grows
  by about 11 µs per record.
- It passes one 60 FPS frame at about 1,500 records.
- So the cap is not the problem. The write pattern is. The cap stays 10,000, because that is
  history the direction needs.
- `ig-m6o.9` moves the records to an append-only side file, so a save writes only what is new.
- Until it lands, the hitch is real but slow to arrive: a new save starts empty, and it takes
  about 25 hours of play at the guessed rate to reach one frame.

**Measured 2026-09-24 (`ig-m6o.9` acceptance, `tests/unit/test_ledger_file.gd` and
`test_ledger.gd`).** The side file landed, so the hitch above is gone. At the 10,000-record cap:
- The ledger adds at most 0.31 ms to any save or profile action (re-measured for `ig-9b6`: 10
  runs plus a full suite, best of seven, against an empty ledger). It makes no difference whether
  the ledger holds routine battles or none. A commit takes 0.96-1.21 ms, a periodic save
  0.92-1.27 ms, and a save with nothing new 0.76-0.95 ms.
- The first figures (0.7 ms on a commit, 0.2 ms on a periodic save) were wrong in two ways. In the
  ledger with no routine battles, the test's own routine battle was evicted as soon as it was
  recorded, so that periodic save appended nothing. And saves a millisecond apart paid an OS wait
  of about 2 ms after back-to-back appends, at any ledger size. Play saves seconds apart, so the
  test now waits 20 ms before each timed save. The wait never grew with history.
- The main save is 659 bytes. The side file is 2.67 MB, about 270 bytes a record.
- A load takes about 300 ms, up from 197 ms, because it compacts the file behind the load screen.
- A whole-file rewrite takes about 75 ms. Play does one only in recovery (`DECISIONS.md` The
  Ledger, item 8).

> ⚠️ **PROVISIONAL** — the 10,000 cap and the 64-moment cap. The save-cost half is measured
> (above), and the answer is a new save shape, not a lower cap. Records per hour of real play is
> still a desk guess (about 60) · **Settled by:** a played build that counts records per hour,
> after `ig-m6o.9`

---

## Bonds and dreams, slice 1 — *ig-m6o.2.1, scoped 2026-09-24*

The first test of the living-world bet: one bond, one dream and one moment in town, built only on
what exists today. Nothing is saved. Both are derived from the Ledger when read, like the History
list (`DECISIONS.md` 2026-09-24 "The Ledger": readers count, saved tallies are rejected). Every
row is a `balance.tres` row except the read cost, which is a measurement.

> ⚠️ **PROVISIONAL** — every number in this section is a desk guess. How often a battle is not
> routine has never been counted, so the pace a bond forms at is unknown · **Settled by:** the
> slice's calibration run over a real ledger, then the owner gate (`ig-m6o.2.1`)

| Row | Value | Why |
|---|---|---|
| `bond_points_hard_battle` | 1 | A `battle` with both heroes in `team` that is not routine: someone downed, a rescue, or not a victory. Routine victories score 0: the Ledger evicts them first, so a bond built on them would fade at the cap |
| `bond_points_saved` | 3 | A `revived` or `carried` moment between the two, either way round. Its battle is not routine, so it also scores the hard battle: 4 in all |
| `bond_points_rescued` | 5 | A rescue `battle`: one hero in `rescuers`, the other in `rescued`. With the hard battle, 6 |
| `bond_points_death_witnessed` | 5 | Both in the `team` of the battle that stranded a hero who then died (`died.battle_order`). With the hard battle, 6 |
| `bond_threshold` | 8 | Two saves (4 + 4), or one rescue or witnessed death plus two more hard fights (6 + 2). One fact alone never makes a bond |
| `dream_fight_beside_battles` | 3 | The dream's middle milestone: battles beside the one this hero owes, after the save that opened the debt. Any battle counts, routine too |
| Bond read cost | 39 ms, measured, not a gate | One bond and dream read for one hero, at the 10,000-record cap, best of seven, printed for `ig-m6o.2.1`. The ADR it fed rules bonds derived, read in one pass for every pair and kept until the ledger changes (`DECISIONS.md` 2026-09-24 "Bonds stay derived", accepted). Nobody nears the cap for 100+ hours at the guessed 60 records an hour. Hard rule: it runs on refresh only, never per frame. Kept index (`ig-m6o.2.2.1`), same cap, 50 heroes in 5-hero teams, seven runs, best / worst: the all-pairs rebuild is 103–106 / 121–129 ms and runs once per ledger change. A roster change that writes a record (settle, summon, rank-up) costs 251–259 / 341–351 ms end to end, one rebuild included; one that writes none costs 137–143 / 176–198 ms, most of it the roster list (~60 ms) and the detail panel, then refreshed twice per roster change (~34 ms each, the dream read ~25 of it; once since `ig-7sn.3`). The 0.25 s pulse costs 1.7 / 2.2–2.5 ms and reads no bonds. Against slice 1 (~40–60 ms of bond reads per roster change) a record-writing change is ~50 ms dearer and a quiet one is cheaper. With 50-hero teams the rebuild takes ~4.4 s against slice 1's 434 ms per-hero read. Folded index (`ig-m6o.2.2.9`), same cap and teams, best / worst of seven over four runs: one record in (append, fold in, evict, fold out) costs 0.16 / 9.5–9.8 ms; the worst is the first call, which recomputes tiers. A roster change that writes a record now costs 107–108 / 174–189 ms, against 77–78 / 79–90 ms for one that writes none. With the detail panel refreshed once per roster change (`ig-7sn.3`), same test, best / worst of seven: 99 / 173 ms and 70 / 74 ms. Most of the gap is the one dream re-read. The all-pairs rebuild now runs only on a load or a rolled-back append: 117–119 / 120–125 ms. With 50-hero teams, one hard battle folds in at 10.2 / 16.9 ms and the oldest one comes out at 10.8 / 15.7 ms; the rebuild after a load is still 4.10 / 4.12 s |

Each fact counts at most once per record for a pair, so one long battle full of revives cannot make
a bond by itself.

### The dream catalogue — *ig-m6o.2.2.7, design 2026-09-24*

Four dreams, all proved by today's records (`battle`, `summoned`, `ranked_up`, `died`). The dream's
owner is the hero who holds it. X is the other hero it names, and Z the zone. Each keeps slice 1's
shape: an opening line, a counted milestone, a last milestone, and an end, fulfilled or lost.
Dreams on `encounter` and `meal` records wait for those records (`ig-m6o.2.2.4`, `ig-m6o.2.2.5`) and
are `ig-m6o.2.2.10`'s.
Profession dreams are `ig-m6o.2.2.8`'s.

**Repay a life debt** (`life_debt`, slice 1, unchanged). X saved the owner. The owner wants to save
X back.

**Watch over them** (`watch_over`). The other side of the same save: the saver now feels
responsible.
- Opens: the owner saves X. It revives or carries X, or rescues X as a listed rescuer. The first
  such X in the record, as the life debt picks its saver.
- Desired change: X lives to rise. Beneficiary: X. Methods: fight beside X and keep X up.
- Milestones: saved X at Z; fight beside X again (n / `dream_fight_beside_battles`); see X rank up.
- Fulfilled: a `ranked_up` record for X. Lost: X dies.

**Carry their name** (`carry_name`). A death beside the owner becomes a reason to go back.
- Opens: a `died` record with cause `expedition` whose `battle_order` is a battle with the owner in
  its team (the death the Bonds already call witnessed). Z is the `died` record's zone.
- Desired change: beat the place that took X. Beneficiaries: X's memory, and the squad.
  Methods: go back to Z and win.
- Milestones: was there when X fell at Z; win at Z (n / `dream_name_victories`), any victory with
  the owner in the team.
- Fulfilled: the count is reached. Lost: Z takes another. That is a second witnessed death whose
  zone is Z.

**Be worth it** (`be_worthy`). A life spent as Essence gets a name in someone's story.
- Opens: a `died` record with cause `sacrifice` whose `by` is the owner (X was given up for it). A
  rank-up that spends several heroes opens on the first. The others add nothing.
- Desired change: the owner's strength repays the life spent. Beneficiaries: X's memory, the
  roster. Methods: win hard fights.
- Milestones: X was given up for the owner; win hard fights (n / `dream_worthy_hard_victories`),
  that is, victories that are not routine (`Ledger.is_routine`) with the owner in the team.
- Fulfilled: the count is reached. Lost: the owner is carried home, listed in a rescue battle's
  `rescued`.

**Which dream a hero holds.** One pass, oldest first, one dream at a time (ADR item 6):
- With no dream open, the first record with a formative event for this hero opens that dream.
- One battle can both save the owner and have it save someone. The life debt wins then (catalogue
  order: `life_debt`, `watch_over`). A `died` record opens at most one dream.
- The record that ends a dream never opens the next, as in slice 1.

| Row | Value | Why |
|---|---|---|
| `dream_fight_beside_battles` | 3 | Slice 1's row, now also Watch over's counted milestone. Both count battles beside X |
| `dream_name_victories` | 3 | Any victory at Z. The life debt's pace, three battles |
| `dream_worthy_hard_victories` | 2 | Hard fights are rarer than battles, so two, not three |

The catalogue is still one oldest-first read of one hero's dream (ADR item 6). Carry their name adds
one set to that read: the order ids of the battles the owner fought in. As in slice 1, the first
two counts include routine victories, which the Ledger evicts first at the cap, so they can shrink
there. At the cap, a `died` record can also outlive the battle that proves the owner was there.
The section's PROVISIONAL covers all three numbers.

---

## Stage saves — *ig-eek, scoped 2026-09-24*

Three saves that look like a real player's game at three points, for playtests and for tuning
(bonds first). A bot plays the real game to make each one: it summons, ranks up, gears, builds and
runs expeditions through the public `GameSession` calls, on the live clock, sped up. It never
cheats: no granted resources and no edited heroes. Bonds and dreams read the Ledger, and a
hand-written Ledger would bake in the one rate bond tuning has to measure: how often a battle is
not routine.

A stage is a length of game-clock play. The other columns are checks on the finished save, not
inputs. If the bot falls short of one, the save is still made at that hour, and the gap is filed as
a progression finding. It is never patched over.

| Stage | Game clock | Ledger | Checks the save must pass |
|---|---|---|---|
| Early | 2 h | about 120 records | Verdant cleared. 5–10 heroes, none above D. One team. The free first producers placed; no hall above level 1 |
| Mid | 20 h | about 1,200 | Ashfall cleared. 15–30 heroes; the best team mostly C–B. 2–4 teams. Halls at level 2–3. At least one death, one rescue and one bond in the Ledger |
| Late | Until the Ledger is at its 10,000 cap and has evicted | 10,000 | Sundered Vault cleared; Fallen Citadel and Frontier March tried. 40+ heroes; the best team A–SS. Every built hall at level 5. Several bonds and dreams. 5+ deaths |

- Late is set by the cap, not by hours, so bond tuning sees eviction happen (routine victories go
  first). At the guessed 60 records an hour, that is about 170 hours.
- The bot plays in fixed, greedy order. Summon when stones allow. Fill 5-hero teams by power.
  Send every idle team, with suggested supplies, to the hardest unlocked zone where its power is
  at least 90% of recommended. Spare heroes are fodder for the best ones. Equip the best gear on
  the strongest heroes, and enhance up to the Forge cap. Place the free producers first, then
  upgrade halls when affordable (Circle, Forge, Sanctum, Training Hall, Reliquary). Keep food
  above zero. Rescue every stranded hero it can, and let the rest die as the rules say.
- The bot stops dispatching near the end and saves with no order in flight. A loaded save runs
  offline progress for the time since it was written.
- The bot's records per hour are not the owner's. They don't settle the Ledger's PROVISIONAL.

> ⚠️ **PROVISIONAL** — the stage lengths and every check are desk guesses about what a player has
> at 2 h, 20 h and the cap. How far a greedy bot gets is unmeasured, and Ashfall's boss is already
> flagged unwinnable ungeared (§ The three zones) · **Settled by:** the first bot runs, then the
> owner playing each save

---

## Performance budgets — *ig-7sn, drafted 2026-09-24*

What each scene may cost per frame at its worst case. This table is the hard constraint's worst
case: 60 FPS holds at each row (`GAME_SPEC.md` § Hard constraints, amended 2026-09-24;
`DECISIONS.md` 2026-09-24 "Performance: budgets at each scene's worst case", item 0).
`CODING_RULES.md` § Performance says how hot-path code is measured against these. The baseline
(`ig-7sn.2`) fills the Measured column. These are targets, not test gates: a miss files a bead
under `ig-7sn`.

> ⚠️ **PROVISIONAL** — the only machine measured so far is the owner's (RTX 4090). Half a frame
> on it is a guess at the headroom a mid-range PC needs to keep 60 FPS (`GAME_SPEC.md` § Hard
> constraints) · **Settled by:** the same scenes measured on a mid-range PC

Every scene has the same target. 60 FPS is 16.7 ms a frame. On the owner's PC, with vsync off,
p99 must stay at or under 8.3 ms (half a frame). No frame outside a load or a scene change may
take over 33 ms: two frames, which the owner sees as a hitch. The pulse lands on one frame in
fifteen, so p99 includes it.

| Scene | Worst case it must hold | Measured |
|---|---|---|
| Hub | 100 heroes, the Ledger at its 10,000-record cap, and a roster action with its save. The roster has no cap; 100 fills all five zones at their hero caps (95) | — |
| Town | Every figure out: 16 wanderers (`AMBIENT_HERO_CAP`), every keeper and worker, and the body. Plus the frame of one building change | — |
| Watched battle | fallen_citadel (30 heroes, 30-enemy waves, a boss with 10 adds) and frontier_march (50 heroes, 30 objective enemies). Gore adds on top of this (`ig-c9y`) | — |
| Dispatched battles | All five zones dispatched at their hero caps while the hub or town is shown. The 0.25 s pulse advances every battle on the main thread, and nothing caps how many run | Not yet as a whole. One part, a launch's Knight cover orders (§ Hero AI on auto, Bonds) for a 50-hero team (25 Knights, 25 back row) at the 10,000-record cap with the index kept: 2.2–2.5 ms per team snapshot. The whole 50-hero team snapshot around it: 20–22 ms (`ig-uu7.4`). A launch or repeat run built it 2–3 times (about 60 ms on one frame); since `ig-7sn.4` it builds it once and the forecasts and the run share it, so a 50-hero launch spends 20.5–23.0 ms in team snapshots (best / worst of seven), under the 33 ms hitch line |
| Load | Offline catch-up of every dispatched battle. No target yet: measured and recorded | Not yet as a whole. One part, the bond index rebuild at the 10,000-record cap: 117–119 ms with 5-hero teams, 4.1 s with 50-hero teams (`ig-m6o.2.2.9`) |

> ⚠️ **PROVISIONAL** — the 100-hero roster is a measurement assumption, since the roster has no
> cap · **Settled by:** a roster cap if one is ever set, or a real save that outgrows 100

Budgets set elsewhere still hold: the Ledger adds at most 2 ms to a save (§ The Ledger); a bond
index rebuild fits one frame, 16.7 ms, once the ledger changes on the live tick (`DECISIONS.md`
2026-09-24 "Bonds stay derived", item 5); battle effects cap at 40 live (`MAX_LIVE_EFFECTS` in
`battle_vfx.gd`).

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

> ⚠️ **PROVISIONAL — spine flag (owner ruling, 2026-09-24).** Power comes from BOTH sources now.
> Living deeds, finished dreams and Founding also earn Essence and rank-ups, and sacrifice stays
> the fast, dark path (`GAME_SPEC.md` § Direction). Every number in this section assumes sacrifice
> is the only Essence source. That includes the ~327-pull spine and the ~15× "manufacture, don't
> pray" ratio, so they will move. The living-Essence formulas are undecided. Guardrails for
> `ig-m6o.4` (Direction v2 § 4 made the first two final):
> - Living Essence never makes Summon Stones.
> - Per hour of play, sacrifice stays the fastest route to SSS.
> - Each deed milestone pays once, never a farm. Retelling a deed never mints Essence again, and a
>   deed nobody witnessed still counts.
> - **Risen** (§ 4): born F, reached SSS, with a personal ascent deed before every promotion.
>   Either Essence source can pay the rank-up cost. Sacrifice cannot supply the deed.
> - **Concordance** (§ 4, `ig-m6o.3`) moves the ×3 below off `def_id`, onto a technique the two
>   heroes have practised together (§ Dupes and resonance).
>
> · **Settled by:** `ig-m6o.4`. game-designer restates this section with both sources before any
> formula ships, and the owner signs off on the restated spine.

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
Since 2026-09-23, SS→SSS also needs a master priest at the Sanctum (§ Keepers and professions).
That adds no Essence and is not in the table.

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

**Amended 2026-09-24 (`GAME_SPEC.md` § Direction § 4).** **Concordance** replaces this bonus. The
×3 stays, but it needs a technique the two heroes have practised together, not the same `def_id`.
Kin or not, rivals too. Whether resonance keeps its `def_id` trigger is open (`ig-m6o.4`). Until
`ig-m6o.3` lands, the rule above holds.

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
| Knight | Oaken Guard — DEF +4% | Ox Shoulders — HP +5% | Last Rampart — DEF +8% |
| Rogue | Opening Strike — CRIT_RATE +1.5pp | Sharp Hunger — ATK +5% | Grim Tally — CRIT_DMG +0.08 |
| Ranger | Fleet String — SPD +4% | Bowyer's Pride — ATK +5% | Cold Squint — CRIT_RATE +1.5pp |
| Mage | Arcane Focus — ATK +5% | Cracked Vessel — CRIT_DMG +0.06 | Spire Scholar — ATK +6% |
| Cleric | Lantern Vow — HP +5% | Quiet Nave — DEF +4% | Guardian Light — HP +6% |

**Renamed 2026-09-24 (director; `DECISIONS.md` 2026-09-23, item 10).** The Knight's T1 trait was
Bulwark, a Square Enix skill name, and it shared that name with the Knight's passive skill (now
Close Ranks, § Skills). It is now **Oaken Guard**. The Cleric's T1 trait was Devotion, a retired
Summoner action; it is now **Lantern Vow**. The Ranger's T1 trait Quickdraw is now **Fleet
String**. Display names only: the ids stay `knight_bulwark`, `cleric_devotion` and
`ranger_quickdraw`.

**Renamed 2026-09-24 (`ig-x8g`, the one-time web-checked sweep; evidence:
`.agent-results/ig-x8g/names.md`).** Display names only; every id stays.

| Old name | New name | Id |
|---|---|---|
| Stalwart | Ox Shoulders | `knight_stalwart` |
| Iron Wall | Last Rampart | `knight_iron_wall` |
| Killer Instinct | Sharp Hunger | `rogue_killer_instinct` |
| Executioner | Grim Tally | `rogue_executioner` |
| Marksman | Bowyer's Pride | `ranger_marksman` |
| Deadeye | Cold Squint | `ranger_deadeye` |
| Overload | Cracked Vessel | `mage_overload` |
| Archmage | Spire Scholar | `mage_archmage` |
| Sanctuary | Quiet Nave | `cleric_sanctuary` |

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

### Fodder training (P2-13)

Ruling on the five questions `docs/TASKS.md` filed this ticket `[BLOCKED]` on. Verified arithmetic
throughout is Codex thread `019ff1bc-454a-7070-b180-baa1c7bde669` (read-only pass against real
source: `heroes/hero.gd`, `systems/game_session.gd`, `combat/quick_resolve.gd`,
`hub/expedition/expedition.gd`, this document).

**0. The premise correction that resolves most of the rest.** The backlog row's framing —
"survivors of background 'culling' expeditions gain XP and **rank up naturally**" — describes
something the codebase cannot do. `hero.rank` changes at exactly one runtime call site,
`rank_up_hero()` (`systems/game_session.gd:216-225`), gated on essence spent, itself sourced only
from `sacrifice_hero()`. A repo-wide search for every write to a `Hero`'s `.rank` found the
constructor, that one production mutation, and test fixtures — nothing else, and no expedition,
XP, or leveling code path touches it. **"Rank up naturally" cannot happen. Training only ever
raises `hero.level` toward the trainee's own current rank's cap** (`level_caps[hero.rank]`,
already shipped, `Hero.level_for`, `heroes/hero.gd:35-40`). That single correction settles
questions 1 and 3 almost by itself, and it is why the system below is narrower than the backlog
row conceived it.

**1. The spine conflict — resolved by the premise correction, not re-derived from scratch.**

`Hero.compute_essence_yield` (`heroes/hero.gd:143-160`) reads only `fodder.rank` and
`fodder.level` — never a stat, a trait, or `taught_traits` (new below). Since ranking up is
exclusively sacrifice-gated and essence income reads nothing a leveling system could plausibly
grant, **a leveling-only system cannot manufacture essence or rank out of nothing.** The published
`~327`-pull (natural spread) and `~6,363`-pull (F-only) figures both describe the level-0 case
explicitly, and stay exactly as printed — training touches neither, because neither number was
ever about leveled fodder in the first place.

What training *can* do is move a player from those numbers toward the already-published
`~150`-pull optimistic ceiling, which the Sacrifice section already flags as assuming "all fodder
happens to be max-level" and says outright to "treat as a ceiling, not a target" — this ruling is
what makes that ceiling reachable by play rather than purely theoretical. Re-derived with training
folded in: a natural-spread player who levels every piece of fodder to its rank cap before feeding
it reaches `~165` pulls (`25,450 / (78.38 × 2) + 2.5`); an F-only player doing the same reaches
`~3,181` pulls (`6,363 / 2`). **Both are still worse than the published `~150` ceiling** (which
also assumes Sanctum +10%, not modeled here) — training moves a real player *toward* the ceiling,
never past it, because the level term saturates at exactly `×2` the instant `level == level_cap`;
there is no further gain past max level for any amount of extra training.

**The throttle question 1 asked for already exists, unauthored: permadeath.** Priced end to end:
training a squad of 5 fresh F fodder to level 10 before feeding it creates `50` essence over
baseline (`5×20` capped vs `5×10` fresh) across the same `~33.6` turns the Hero leveling section
already spends climbing a level-0 F team to its own cap. Spending those identical `~33.6` turns
instead clearing Verdant for stones and feeding freshly-pulled F fodder immediately nets `33.6`
essence from F-only pulls, or `~658` feeding the natural spread — both without ever risking the
fodder already in hand. Once the `69.8%` first-attempt full-roster-wipe rate (Hero leveling,
above) is priced in as an expected value rather than a best case, training a squad to cap is worse
than break-even against simply feeding it immediately and spending the same turns pulling fresh
stock: expected training payoff caps at `≤30.2` essence (even under the generous assumption a
squad that survives its first run is safe forever) against an `83.6`-essence alternative that
keeps the original fodder's baseline value *and* adds fresh pulls on top. A wiped squad's
accumulated levels are gone with it — `kill_hero()` removes the hero from the roster before the
XP credit one line later can meaningfully reward it (`hub/expedition/expedition.gd:65-74`).
**No new throttle is needed; naive full-squad training is already a losing trade against immediate
sacrifice, on essence terms alone.**

**Why a player would ever take a losing-EV trade, stated so nobody re-derives it later.** The
comparison above is deliberately unfavorable to training because it compares training against
feeding *fresh, random* pulls — the one thing training doesn't do better. Training earns its keep
on two things that comparison doesn't model: a **specific** dupe of a chase target (a leveled dupe
sacrifices for `essence_base × 2 × 3` instead of `essence_base × 3` — training doubles exactly the
resonance bonus a player is already committed to chasing, not a generic F pull) and the
**instructor-taught trait** (below), a permanent reward essence can't buy at all. Training was
never meant to out-earn immediate sacrifice on essence — the essence uplift is a side effect of a
term the Sacrifice section already priced, not training's reason to exist.

**2. The lethality paradox — the proposed resolution is rejected; nothing replaces it.**

"Instructor rank gates the zone tier" was the backlog row's own guess. Tested against the real
combat math rather than assumed: a squad of one S-rank instructor (hero_power ≈2,290) plus four
fresh F trainees (hero_power ≈149 each, level-0) sums to team_power ≈2,886 in
`Hero.compute_team_power` (`heroes/hero.gd:127-140`, a **sum**, not a per-hero check). Sent into
Verdant trash at 70% RP, `r ≈ 0.20`, `r³ ≈ 0.008` — damage_fraction under 1% on either branch:
trivial. Sent into Sundered trash or boss — the zone an S-rank instructor's *own* rank would
unlock — `r` exceeds `1.0` (`r ≈ 2.8`–`4.8`) and both branches saturate at `1.0`: certain, instant,
whole-squad death. **There is no zone tier where a strong instructor produces "meaningful risk"
for its trainees** — because the sum either lets the instructor trivialize whatever the trainees
could reach, or the trainees contribute too little to the sum for the instructor's own zone to be
survivable regardless of how strong it is. Gating the zone by instructor rank reproduces the exact
binary the "coin flip vs meat grinder" complaint was written against; it does not resolve it.

It is also structurally the wrong shape regardless of the numbers: `quick_resolve`'s loss branch
applies one `damage_fraction` to *every* fielded hero's own max HP in the same wave
(`combat/quick_resolve.gd:34-46`) — a wave is won or lost by the whole team at once. There is no
code path today where the strong live and the weak die within a single fight. "Only the strong
survive" cannot mean per-hero triage inside one run; the combat seam has no per-hero mortality to
triage with, and adding one is a combat-seam change (`CLAUDE.md` risky boundary 4 — both `resolve`
implementations would have to agree), well past what this ruling can decide alone.

**Ruling: the zone is picked by the trainees' own rank, the same way every other expedition's zone
already is — no new gating rule.** An "instructor" is any roster hero of strictly higher rank than
every trainee fielded alongside it — a compositional guard, not a lethality control, no new
numeric threshold. Training runs whatever zone the trainees' own rank would ordinarily unlock
(Verdant for F–C fodder in practice; C-rank fodder pushing toward Ashfall inherits the
recommended-power imbalance "The three zones" (above) already flags PROVISIONAL — not a new
problem this ruling introduces). The already-published, already-measured outcome table (Hero
leveling, above — `69.8%` full-wipe / `30.2%` retreat / `0%` complete at level 0, improving to
`53.1%`/`46.4%`/`0.5%` at cap) **is** the meat grinder; it needs no sharpening. What an instructor's
presence buys is the same unauthored reduction in `r` any strong squadmate already gets the whole
squad under `compute_team_power`'s sum — real, but proportional, with no new formula. "Only the
strong survive" is true across many training runs, not within one: it is the trainee that keeps
surviving its rank's own lethal odds, attempt after attempt, that reaches its cap and earns a
trait — not a per-hero triage inside a single fight.

**Rejected: instructor rank gates zone tier** — per the arithmetic above, every tested
configuration reads as either trivial or certain death; no zone produced a middle.

**3. Rank ceiling on natural growth — there isn't one, and none is needed.**

Dissolved by §0: leveling never touches rank, so "a rank ceiling on natural growth" has nothing to
cap. The only ceiling live during training is the one already shipped — `level_caps[hero.rank]`,
the same clamp every hero's level is already bound by. No new value, no new field. Its interaction
with question 1 is total: because training cannot cross a rank boundary under any configuration,
it structurally cannot manufacture the one thing the sacrifice spine exists to price — a hero of a
higher rank than what was pulled. Training's F–C scope (the backlog row's own framing) is exactly
the band where a level cap alone leaves a hero furthest from combat relevance; training a hero all
the way to B or A would still leave it capped at its own rank's ceiling, worth nothing the spine
doesn't already price through the level-in-yield term.

**4. The trainee survivability bonus — rejected outright, not reclassified as trait or modifier.**

No new mechanic is needed, so the trait-vs-modifier choice the question poses doesn't arise.
`compute_team_power`'s sum (§2, above) already gives a fielded instructor a proportional,
unauthored effect on the whole squad's survival odds — the exact lever the question was reaching
for. A second, independent bonus stacked on top double-counts that lever and pushes further toward
the trivializing failure mode §2's arithmetic found (a modest S-instructor-plus-F-squad is already
under 1% damage in Verdant) — undermining the tension "culling" is supposed to deliver, not
protecting it.

**Rejected: a temporary expedition modifier** (would have been a new `BalanceTable` field, e.g.
`instructor_survivability_bonus: float`, read by `Expedition.resolve()`, no save key) — redundant
with the existing sum-based lever.

**Rejected: a permanent trait** — scope creep back into `P2-06c`'s territory exactly as the ticket
brief warned, and self-contradictory besides: a bonus that outlives the training run it was meant
to price is not "temporary."

**5. Fodder opportunity cost — already forced by permadeath and turn scarcity; no new field.**

A hero is in exactly one of three states at any time: available to sacrifice, committed to a
training expedition this turn, or gone. Training and sacrifice already can't stack — a hero
fielded on a training run is by definition not simultaneously fed to `sacrifice_hero()`, and if it
dies mid-training it is gone from the roster before it can ever be sacrificed, its accumulated
level (and the essence that level would have added) lost with it, not banked. That is the entire
trade, and question 1's arithmetic already prices it: every turn spent training a hero already in
hand is a turn not spent clearing for stones, not spent pulling, and not spent feeding that hero's
baseline value immediately — carrying a real, measured `69.8%` chance (at level 0) of losing both
the hero and every turn invested in it. **No cooldown, no lockout field, no new counter is needed
on top of what permadeath and `GameSession.turns` (Turns, above) already enforce.**

---

**New content this ruling authors: the instructor-taught trait.**

`§ Traits` reserved `instructor_trait_pool` (empty, per-archetype, on `HeroDefinition`)
specifically for this ticket. Populate it the same shape resonance already used — three ordered
`TraitDefinition`s per archetype, granted in array order — because a trainee is only ever eligible
for training at F, D, or C rank (§3), a natural three-stage ladder with no invented threshold
count.

```
grant condition: hero.level reaches balance.level_caps[hero.rank] (the hero's own current rank's
                  cap) at the moment an expedition resolves, and a qualifying instructor
                  (instructor.rank > hero.rank, no other requirement) was fielded on that
                  expedition
grant: hero.taught_traits.append(instructor_trait_pool[hero.rank][next unclaimed index].id)
       (rank 0=F -> pool index 0, rank 1=D -> pool index 1, rank 2=C -> pool index 2;
       an already-claimed stage is skipped, never re-granted)
```

Reuses `Hero.level_for`'s existing cap read and fires from the same XP-credit path
`Expedition.resolve()` already calls on every outcome — no new counter, no new turn cost. A
trainee that reaches C's cap and later ranks up past C (via ordinary sacrifice) keeps every grant
earned along the way; nothing revokes them, the same "rank-up never punishes" reasoning
`DECISIONS.md`'s 2026-08-01 entry already applies to level.

`compute_final_stats` does **not** read `taught_traits` yet — `§ Traits §4` shipped the field spec
only, deliberately unwired (`P2-06c`'s own Findings). Applying an instructor-taught trait in
combat is real, new work this ticket owns: extend the existing resonance-trait loop
(`heroes/hero.gd:114-120`) to also iterate the `TraitDefinition`s named by `hero.taught_traits`
through the same two channels (percentage into `equip_pct`, flat add on the crit stats ahead of
`equip_crit_rate_cap`) — not a second loop shape, the same one with a second source array.

Magnitude budget: the same ceiling § Traits already verified for resonance — a full three-trait
stack per archetype stays below what one A-rank-or-higher equipment slot alone contributes. The
fifteen actual values are content-authoring work for the implementing ticket, following § Traits
§3's per-archetype identity framing (Knight/Cleric lean DEF/HP, Rogue leans ATK/CRIT, etc.), not a
fresh design axis this ruling needs to invent.

**The fifteen instructor-taught traits — authored here, `instructor_trait_pool`'s content.**
Same shape as § Traits §3's resonance table: three ordered stages, granted in array order. Stage
index is fixed by the grant rule above (`hero.rank` at the moment of grant), not by anything
authored here — stage 0 is whatever a hero earns at F's level cap, stage 1 at D's, stage 2 at C's.
Each stage moves exactly one stat, through the same two channels resonance already established:
HP/ATK/DEF/SPD as a percentage into `equip_pct`, CRIT_RATE/CRIT_DMG as a flat point/decimal add
ahead of `equip_crit_rate_cap`.

| Archetype | Stage 0 (F cap) | Stage 1 (D cap) | Stage 2 (C cap) |
|---|---|---|---|
| Knight | Shield Drill — DEF +3% | Iron Discipline — HP +4% | Veteran's Bastion — DEF +5% |
| Rogue | Quick Hands — ATK +3% | Wrong Foot — CRIT_RATE +1pp | Velvet Knife — CRIT_DMG +0.05 |
| Ranger | Soft Tread — SPD +3% | Steady Aim — ATK +3% | Split Feather — CRIT_RATE +1pp |
| Mage | Apprentice Rites — ATK +3% | Mana Burn — CRIT_DMG +0.04 | Spellweaving — ATK +5% |
| Cleric | Novice Prayer — HP +3% | Chapel Stone — DEF +3% | Evensong — HP +5% |

**Renamed 2026-09-24 (director; `DECISIONS.md` 2026-09-23, item 10).** Feint (a melee role
action) is now **Wrong Foot**, Benediction (a White Mage action) is now **Evensong**, and Coup de
Grace is now **Velvet Knife**. Display names only: the ids stay `rogue_feint`,
`cleric_benediction` and `rogue_coup_de_grace`.

**Renamed 2026-09-24 (`ig-x8g`, the one-time web-checked sweep; evidence:
`.agent-results/ig-x8g/names.md`).** Light Step is now **Soft Tread**, Trueshot is now **Split
Feather**, and Ward is now **Chapel Stone**. Display names only: the ids stay `ranger_light_step`,
`ranger_trueshot` and `cleric_ward`.

Same identity split § Traits §3 already used for resonance, held here too: Knight/Cleric lean
DEF/HP, Rogue leans ATK/CRIT, Mage leans ATK/CRIT_DMG, Ranger splits SPD/ATK/CRIT_RATE — no new
axis. Progressive within each archetype (smallest stage first) the same way resonance's own T1 is
its archetype's smallest trait, for the reachability reason worked out below.

**Content table, for the `.tres` authoring pass** (`id`, `display_name`, `stat` as
`EquipmentDefinition.PrimaryStat` ordinal — `HP=0 ATK=1 DEF=2 SPD=3 CRIT_RATE=4 CRIT_DMG=5` — and
`magnitude`, matching `TraitDefinition`'s four exported fields, § Traits §1):

| Archetype | Stage | `id` | `display_name` | `stat` | `magnitude` |
|---|---|---|---|---|---|
| Knight | 0 | `knight_shield_drill` | Shield Drill | DEF (2) | 0.03 |
| Knight | 1 | `knight_iron_discipline` | Iron Discipline | HP (0) | 0.04 |
| Knight | 2 | `knight_veterans_bastion` | Veteran's Bastion | DEF (2) | 0.05 |
| Rogue | 0 | `rogue_quick_hands` | Quick Hands | ATK (1) | 0.03 |
| Rogue | 1 | `rogue_feint` | Wrong Foot | CRIT_RATE (4) | 0.01 |
| Rogue | 2 | `rogue_coup_de_grace` | Velvet Knife | CRIT_DMG (5) | 0.05 |
| Ranger | 0 | `ranger_light_step` | Soft Tread | SPD (3) | 0.03 |
| Ranger | 1 | `ranger_steady_aim` | Steady Aim | ATK (1) | 0.03 |
| Ranger | 2 | `ranger_trueshot` | Split Feather | CRIT_RATE (4) | 0.01 |
| Mage | 0 | `mage_apprentice_rites` | Apprentice Rites | ATK (1) | 0.03 |
| Mage | 1 | `mage_mana_burn` | Mana Burn | CRIT_DMG (5) | 0.04 |
| Mage | 2 | `mage_spellweaving` | Spellweaving | ATK (1) | 0.05 |
| Cleric | 0 | `cleric_novice_prayer` | Novice Prayer | HP (0) | 0.03 |
| Cleric | 1 | `cleric_ward` | Chapel Stone | DEF (2) | 0.03 |
| Cleric | 2 | `cleric_benediction` | Evensong | HP (0) | 0.05 |

None of these fifteen `id`s collide with the fifteen resonance `id`s already authored in
`heroes/defs/*.tres` (`knight_bulwark`/`knight_stalwart`/`knight_iron_wall` and the other four
archetypes' equivalents) — checked by direct read of all five files, same `<archetype>_<name>`
pattern.

**Verified — the combined stack, resonance and instructor together (Codex thread
`019ff22a-bb1a-75a3-affc-ec806bda59c9`, arithmetic against this section's own figures and
§ Primary stat magnitude's published `equip_pct_per_rank` table: F 4.00% / D 5.40% / C 7.28% /
B 9.84% / A 13.28% / S 17.92% / SS 24.20% / SSS 32.68%).** § Traits §3 checked resonance alone
against a single A-rank-or-higher slot; nothing before this checked what a hero holding a *full*
resonance stack **and** a full instructor stack at once does to the same accumulator, since
`taught_traits` and the resonance derivation both feed `compute_final_stats`'s same `equip_pct`
array (`heroes/hero.gd:99-122`) on the same hero.

1. **Combined per-stat totals, against a single equipment slot.** Yes, the combined stack can
   now outweigh a single equipment slot — something the resonance-only check never triggered —
   but only up to a bounded rank, never SS or SSS:

   | Archetype | Stat | Resonance + instructor | Outweighs a single slot through… | …stops at |
   |---|---|---:|---|---|
   | Knight | DEF | 12% + 8% = 20% | S (17.92%) | SS (24.20%) |
   | Knight | HP | 5% + 4% = 9% | C (7.28%) | B (9.84%) |
   | Rogue | ATK | 5% + 3% = 8% | C (7.28%) | B (9.84%) |
   | Ranger | SPD | 4% + 3% = 7% | D (5.40%) | C (7.28%) |
   | Ranger | ATK | 5% + 3% = 8% | C (7.28%) | B (9.84%) |
   | Mage | ATK | 11% + 8% = 19% | S (17.92%) | SS (24.20%) |
   | Cleric | HP | 11% + 8% = 19% | S (17.92%) | SS (24.20%) |
   | Cleric | DEF | 4% + 3% = 7% | D (5.40%) | C (7.28%) |

   Every archetype's *signature* stat (the one both its resonance and instructor pools both lean
   into — Knight DEF, Mage ATK, Cleric HP) now beats a single S-rank slot, something no
   resonance-only total did; every split/secondary stat (Knight HP, Rogue ATK, both Ranger stats,
   Cleric DEF) stops at C or B. **Nothing reaches SSS (32.68%)** — the largest combined total,
   19–20%, is `12.68`–`13.68` points short of it. The two-system stack is real power, sized to
   read as "worth more than one piece of gear at mid rank," not "worth more than the best gear in
   the game."

2. **Worst-case CRIT_RATE, with the instructor trait folded in.** Rogue's `Wrong Foot` (+1pp) and
   Ranger's `Split Feather` (+1pp) are the only instructor traits on the crit channel — added to
   the already-published worst cases: Rogue `43.46%` (base 15% + max-enhanced SSS necklace 26.96pp +
   resonance 1.5pp) `+ 1pp = 44.46%`, `30.54pp` of margin left under the `75%` cap. Ranger
   `38.472%` (base 10% + max-enhanced SSS necklace 26.972pp + resonance 1.5pp) `+ 1pp = 39.472%`,
   `35.528pp` remaining. Both instructor CRIT_RATE magnitudes were sized well under the resonance
   figures they sit beside (`1pp` vs resonance's `1.5pp`) precisely so the combined worst case
   spends only a sliver of a margin that was already `>30pp` — the clamp is nowhere near load-
   bearing here, so this isn't relying on it.

3. **Reachability — sacrifice can skip a hero past a stage it never earned, and does so for real.**
   `rank_up_hero()` (`systems/game_session.gd:216-225`) increments `hero.rank` by exactly one on
   payment of essence alone; nothing gates it on `hero.level` reaching the rank's own cap. A player
   can chain three `rank_up_hero()` calls (F→D→C→B) back to back without ever fielding the hero on
   an expedition at D or C. Since the grant condition above fires only "at the moment an expedition
   resolves" while `hero.rank` equals the stage's own rank (0=F, 1=D, 2=C), skipping through a rank
   without training at it skips that rank's grant **permanently** — once the hero is B or higher
   there is no stage-3+ pool entry to retroactively claim it from, and rank-up never re-checks a
   rank the hero has already left. Concretely: a hero trained once to F's cap (banking stage 0)
   and then chain-sacrificed straight to B collects stage 0 and *only* stage 0 — stages 1 and 2
   are gone for that hero, not deferred. All three stages are reachable on one hero only if the
   player trains it through F, D, **and** C in turn, letting sacrifice carry it past C afterward if
   it wants to; that was already true from §3's ranking discussion above, this just confirms
   sacrifice doesn't offer a way around it.

   This makes stage 0 the only instructor reward every trained hero can bank under *any* play
   style, including the chain-sacrifice one — which is why it isn't sized as a token first rung:
   each stage-0 magnitude (DEF/HP/ATK/SPD +3%) sits in the same weight class as its archetype's
   own resonance T1 (Knight `+4%`, Ranger `+4%`, Mage/Cleric `+5%`) rather than materially smaller,
   since both are "the cheapest rung of their own system" and a player who never trains past F
   should still feel stage 0 land. No magnitude change follows from this finding — the values above
   were already chosen with it in mind, not after the fact.

**Rejected: giving Knight or Cleric a CRIT_RATE/CRIT_DMG-stat instructor trait** (e.g. to
differentiate a stage from its resonance counterpart) — breaks the DEF/HP identity axis § Traits
§3 already set for these two archetypes and adds nothing the arithmetic needed; Rogue, Ranger, and
Mage already cover every crit-bearing archetype between them.

**Rejected: sizing instructor stages larger than resonance's own tiers** (mirroring the "3-6 dupes
is harder to earn than 3 level caps" asymmetry by making instructor traits the bigger reward) —
would have pushed Knight DEF and Mage/Cleric's signature stats past SS (24.20%) once combined with
resonance, undermining the "never outweighs the best gear in the game" ceiling § Traits set for
resonance alone; kept both systems in the same weight class instead.

**No new zone-gating code, no new survivability field, no idle/auto-resolve path.** "Background,"
in the backlog row's own phrase, describes the fiction — fodder training happens alongside the
player's main progression — not a request for automation. A training expedition is
`Expedition.resolve()` on an ordinary player-selected team in an ordinary player-selected zone,
called from the same hub flow every other expedition already uses. Reading "background" as "runs
without a player click" would be a sixth missing system nobody asked for; ruled out explicitly so
an implementer doesn't invent it. Likewise, the "instructor" is derived from squad composition —
the fielded hero of strictly highest rank, if one exists above the rest — not a new UI picker; a
follow-up may add a label if playtesting shows the implicit read is illegible, but that is UI
polish, not this ruling's to spend a ticket on.

**Tunables.**

| Name | Value | Home | Save key? |
|---|---|---|---|
| `Hero.taught_traits` | `Array[StringName] = []` | `heroes/hero.gd` | **Yes — new.** Already fully specified (§ Traits §4, above); this ticket is what writes to it. Save-boundary change, mandatory `verifier` pass, real save/reload cycle. |
| `instructor_trait_pool` content | 3 `TraitDefinition`s per archetype (15 total) | `HeroDefinition` → `heroes/defs/*.tres` | No — per-archetype definition content, same footing as `resonance_trait_pool`. |
| Grant condition | `hero.level >= balance.level_caps[hero.rank]` at expedition resolution, qualifying instructor fielded | Orchestration inside `Expedition.resolve()` / `GameSession` — not a new field | No — reads existing fields (`level`, `rank`, `level_caps`) and writes only `taught_traits` above. |
| Trait application | Extend `compute_final_stats`'s existing trait loop to also read `taught_traits` | `heroes/hero.gd:114-120` | No — same accumulator, no new field. |

No new `BalanceTable` field. No new `ZoneDefinition` field. No new autoload, no new scene seam.

> ⚠️ **PROVISIONAL** — everything above is arithmetically checked against the real yield,
> level-cap, and combat formulas (Codex thread `019ff1bc-454a-7070-b180-baa1c7bde669`), but nobody
> has trained a hero to a cap and watched a trait land. Whether "one trait every rank-cap, three
> total by C" reads as a real reason to run training expeditions instead of just feeding fodder
> immediately is a feel question, the same shape as every other PROVISIONAL marker in this
> document. · **Settled by:** a played build with `taught_traits` wired end to end and at least one
> hero walked to C's cap under a qualifying instructor.

**Ticket shape: one ticket, not several.** Narrowed this far, `P2-13` is a single coherent slice —
a save-boundary field already specified in full (§ Traits §4), fifteen `TraitDefinition` resources
authored the same way resonance's fifteen already were, one grant check added to the existing
XP-credit path, and one extension to the existing trait-application loop. No new autoload, no new
zone rule, no new combat formula, no new UI seam. It needs the mandatory `verifier` pass
`taught_traits` already requires (`CLAUDE.md` risky boundary 1) and nothing else does — comparable
in size to `P2-06c` (content plus a reserved field) and `P2-06b` (the payoff wiring) landing
together as one ticket instead of two, because training has no separate "does it apply in combat"
step to split out the way resonance's did: this ruling names both the grant condition and the
application loop extension in the same section, so there is nothing left for a second design pass
to discover. `tech-lead` can write the ticket body directly from this section.

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

## Action arena — *Phase 2b*

### Vindictus movement and camera baseline (`P2b-01b-2`)

The target is classic *Vindictus*' grounded, camera-decoupled combat rather than the fixed-camera
absolute-cursor prototype from `P2b-01b`. The earlier `6.0 m/s` instant start/stop and visible-
cursor aim are rejected before attack range or timing is authored around them.

The arena uses camera-relative ground movement. `W` runs along the camera's horizontal forward
vector and `A`/`D` strafe relative to it; diagonal input remains normalized. The capsule turns
toward the movement vector at `arena_turn_speed = 1200°/s`, so an uncommitted character runs in
the requested direction instead of backpedalling. Movement does not force the camera to turn.

| Tunable | Value |
|---|---:|
| `arena_move_speed` | `5.8 m/s` |
| `arena_sprint_speed` | `8.0 m/s` |
| `arena_acceleration` | `42.0 m/s²` |
| `arena_deceleration` | `65.0 m/s²` |
| `arena_turn_speed_degrees` | `1200°/s` |
| `arena_mouse_sensitivity` | `0.003 rad/pixel` |

`Shift` selects sprint speed. Acceleration reaches the jog cap in about `0.14 s`; the higher
deceleration stops it in about `0.09 s`. Sprint stamina does not exist yet, so sprint is an input
state rather than a resource cost.

### Combat result return (`P2b-05`)

| Tunable | Value |
|---|---:|
| `arena_result_return_delay` | `1.0 s` |

After a victory or defeat resolves, the arena holds for this delay so the final capsule state can
read before it returns to the hub through `SceneRouter`.

> ⚠️ **PROVISIONAL** — the beat between the killing blow and the return has never been played · **Settled by:** a played build

Combat captures and hides the cursor. Raw mouse motion orbits a third-person `SpringArm3D` camera
directly: a `4.0 m` boom, `0.5 m` right shoulder offset and `0.25 m` collision sweep. Pitch is
clamped to `35°` upward and `65°` downward. `Esc` releases the cursor and returns through
`SceneRouter`; a combat-time cursor/UI toggle waits for an overlay that can consume it.

### Combat reference carried into future arena slices

This project targets classic *Vindictus* / Vindictus Premiere. Do not borrow XE's jump attacks,
air smashes or emergency i-frame actions, and do not borrow *Vindictus: Defying Fate*'s modern
lock-on behavior: those are separate control models.

~~Attacks follow the character's current facing, not camera forward.~~ **Superseded by
`P2b-01f`:** hero facing now tracks camera forward continuously, so "current facing" and "camera
forward" describe the same target — attacks follow camera forward. Classic Vindictus' actual
reference behavior is movement-direction facing decoupled from the camera; this project departs
from that reference on this one axis by the designer's explicit played-build call after `P2b-01d`,
not by drift. Everything else below is unaffected. A normal/light attack has a short commitment
and modest forward root displacement; a Smash is the high-commitment follow-up with larger
displacement and longer recovery. Facing can adjust during startup only: active swings are limited
to a `15°–35°` cone, with `25°` the initial target. Players must align before the active hit frame
instead of snapping around a target mid-swing.

| Mechanic | Initial carried-forward target | Ticket / constraint |
|---|---|---|
| First light attack root displacement | `1.5–2.5 m` forward | `P2b-01c`; choose one provisional value after its startup/recovery timeline is authored. |
| Light hit-stop | `0.04 s` (`0.03–0.05 s` range) | Freeze attacker and valid target on contact; one hit only in the first slice. |
| Heavy/Smash hit-stop | `0.09 s` (`0.08–0.12 s` range) | A later Smash slice, not a reason to make the first light attack heavier. |
| Input buffer | `0.15–0.25 s` before a transition/cancel gate | Queue Normal, Smash or Dodge once action states exist; execute at the earliest permitted frame. |
| Dodge burst | `13.5 m/s` decaying across `0.38 s` | `P2b-01d`; starts i-frames immediately and has `0.25 s` active invulnerability. |
| Dodge/parry cancel | ~~End-recovery only, primarily after a Smash~~ **Superseded by `P2b-04`:** startup, active and recovery, all three | `P2b-01d`; opened to the whole attack timeline by `P2b-04` — an active-window cancel forfeits any hit not already registered, no chained dodge. |

#### First light attack timeline (`P2b-01c`)

The first graybox light attack uses one short commitment and defeats its one passive target on
contact; it does not introduce HP or a general damage model.

| Tunable | Value |
|---|---:|
| Startup | `0.12 s` |
| Active window | `0.10 s` |
| Recovery | `0.22 s` |
| Root displacement | `2.0 m` forward |
| Hitbox reach | `1.5 m` from the capsule's front |
| Contact hit-stop | `0.04 s` |

Facing may follow movement input during startup, then commits for the active window and recovery.
The root displacement is delivered uniformly across the active window and pauses during hit-stop;
ordinary locomotion and sprint velocity do not run during the attack. Hit-stop freezes only the
attacker and passive target, never the scene tree.

> ⚠️ **PROVISIONAL** — startup, active time, recovery, reach and the exact `2.0 m` displacement are
> first-playable values inside the supplied ranges, not settled feel. · **Settled by:** playing the
> `P2b-01c` graybox and tuning these five provisional fields together.

Hit-stop is contact feedback, not a global slow-motion effect. It lengthens the effective attack
duration by the pause for each valid hit, and should affect both attacker and target. Root
displacement is similarly part of the attack transition, not ordinary locomotion; it lets swings
close distance and must remain distinct from sprint velocity.

Hit-drag is the companion effect: weapon/root motion briefly resists as it crosses a valid hurtbox.
No numeric drag curve was supplied, so it remains a later refinement after the first hit-stop reads
correctly; do not fake it by increasing global movement friction.

When an attack-speed stat is eventually authored, its timing multiplier is:

```
real_attack_time = base_attack_time / ((200 + attack_speed) / 200)
```

Do not map the existing `Hero.SPD` field to `attack_speed` by implication. That needs its own
combat/stat ruling; the formula is reference data, not permission to change hero stats.

The current `4.0 m` SpringArm is inside the source's `3.2–4.5 m` range; its `0.5 m` shoulder offset
and `0.25 m` sweep are likewise in range. Obstruction retracts the camera immediately. Camera
position smoothing (`~0.08–0.12 s` return or an equivalent `12 s⁻¹` filter) is deliberately
deferred: direct orbit is the required baseline, and smoothing only lands if a played build shows
camera jitter rather than solving an unobserved problem.

`P2b-01c` stays one light attack against one passive capsule. `P2b-01d` owns enemy attack, dodge,
i-frames, recovery cancels and buffering; `P2b-01e` alone connects the arena to `Wave` and
`CombatResult`. No slice adds combat state to an autoload or a second result contract.

### Playtest questions after `P2b-01c`

- Does release decelerate with weight without sliding or stopping unnaturally hard?
- Can the player orbit the camera without fighting it to keep the target in view?
- ~~Does a side/backward directional attack follow intended character facing rather than camera
  yaw?~~ **Resolved by `P2b-01f`:** this question presupposed the rejected model. It follows
  camera yaw, by design.
- Does a hit feel dense through root displacement and hit-stop rather than pass through the dummy?
- Does attack displacement naturally close distance without replacing normal movement?

Startup duration, recovery duration, reach and the exact first root-displacement value remain
unsettled: the supplied research gives ranges rather than a single light-attack timeline. Future
tickets must author them as provisional values and test them together, not silently choose a value
inside a helper.

> ⚠️ **PROVISIONAL** — these values are the supplied *Vindictus* prototype targets, not a claim that
> the first implementation already feels identical. · **Settled by:** playing movement, camera,
> root displacement and hit-stop together after `P2b-01c`; tune the authored values, not the control
> model, unless that play pass shows the model itself is wrong.

### Enemy attack, dodge and hit reaction (`P2b-01d`)

The `EnemyCapsule` gains one telegraphed attack and the player gains dodge. This stays graybox:
one enemy, one attack, no HP anywhere, no combo trees, no Wave/`CombatResult` connection — `P2b-01e`
alone does that integration.

**Enemy attack timeline.** Same startup/active/recovery shape as the player's light attack, plus a
proximity trigger the light attack didn't need.

| Tunable | Value |
|---|---:|
| `arena_enemy_attack_startup` | `0.55 s` |
| `arena_enemy_attack_active` | `0.10 s` |
| `arena_enemy_attack_recovery` | `0.45 s` |
| `arena_enemy_attack_reach` | `1.6 m` |
| `arena_enemy_attack_trigger_range` | `3.0 m` |
| `arena_enemy_attack_cooldown` | `0.6 s` |
| `arena_enemy_turn_speed_degrees` | `720°/s` |
| `arena_enemy_attack_hit_stop` | `0.06 s` |
| `arena_enemy_knockback_speed` | `6.0 m/s` |
| `arena_enemy_hit_stun` | `0.35 s` |
| `arena_dodge_speed` | `13.5 m/s` |
| `arena_dodge_duration` | `0.38 s` |
| `arena_dodge_iframe_duration` | `0.25 s` |
| `arena_dodge_cooldown` | `0.15 s` |

The dodge burst, duration and i-frame window were already fixed by the "Combat reference" table
above; they are listed here only because this is the first slice that gives them `BalanceTable`
field names.

**Why `0.55 s` startup is fair.** i-frames last `0.25 s` from the moment dodge is pressed, and the
enemy's active (hit) window is `0.10 s`, so pressing dodge anywhere in the last `0.25 s` of the
telegraph (`t = 0.30 s` to `t = 0.55 s`, telegraph running `t = 0 s` to `t = 0.55 s`) keeps
i-frames overlapping the hit moment at all, and pressing in the last `0.15 s` of that
(`t = 0.40 s` to `t = 0.55 s`) covers the entire active window. That is a real, learnable "dodge
when the swing is about to land" read — not a hair-trigger reaction to the first frame of
telegraph, and not a free reaction window either: a player who dodges the instant the telegraph
starts (`t ≈ 0 s`–`0.2 s`) is too early and gets hit. `0.55 s` is roughly 4.5× the player's own
`0.12 s` attack startup, deliberately: the enemy's tell has to be readable at a glance, the
player's own attack does not.

Dodge is not spam-proof against this timing. The dodge cycle (`0.38 s` burst + `0.15 s` cooldown =
`0.53 s`) and the enemy's attack cycle (`0.55 + 0.10 + 0.45 + 0.6 s` = `1.70 s`) are not integer
multiples of each other, so dodging on cooldown without watching the telegraph does not guarantee
a full-coverage window lands inside every enemy swing — confirmed by interval arithmetic, not
assumed. That is intentional: the decision the Phase 2 exit question asks about ("is spending a
hero's life a decision you actually feel") only exists if avoidance takes a real read, not a
metronome button-press.

**Trigger and facing.** Cadence gated on proximity, the middle option between a pure fixed
cadence (attacks fire uselessly while the player is out of range) and a pure proximity trigger
(attacks the instant the player enters range with no downtime, feels twitchy for a first pass):
the enemy may only start an attack while the player is within `arena_enemy_attack_trigger_range`,
and after a swing's recovery ends it waits `arena_enemy_attack_cooldown` before it is eligible to
attack again, still gated on the player remaining in range. The enemy turns to face the player at
`arena_enemy_turn_speed_degrees = 720°/s` — half the player's own `1200°/s` — during any state
other than its own attack active window and recovery, where facing locks, mirroring the player's
own attack facing-commit rule. `720°/s` covers a full turn in half a second, so in practice the
enemy is always facing the player by the time it attacks regardless of circling; the fairness
lever in this slice is timing, not out-turning the enemy's tracking, and a graybox dummy that
could be out-run by circling would not test the dodge at all. Rejected: instant snap-to-face
(removes the last shred of positioning read, and reads as unfair rather than simple) and a frozen
facing sampled once at telegraph start (lets the player trivially sidestep out of a locked cone,
which tests movement more than it tests dodge — not what this ticket owns).

> **2026-08-12 played-build note.** Tracking for the *entire* `0.55 s` startup, not just avoiding a
> frozen-at-`t=0` cone, turned out to be its own failure in the opposite direction: it makes lateral
> and diagonal dodges provably unable to escape the box regardless of skill, not merely difficult.
> "The played build settles the parry window and the enemy's facing lock" below adds a facing lock
> *partway* through startup — later than the rejected `t=0` freeze, so the original concern (trivial
> sidestep) still doesn't apply, but early enough that a well-timed lateral dodge has real geometry to
> work with. The rejection above stands on its own terms; it is not being reversed, only bracketed.

**Landed hit on the player.** No arena-local HP, no on-screen readout — a physical hit-reaction:
`arena_enemy_attack_hit_stop` freezes both capsules on contact (same pattern as the player's own
light attack landing), then a `arena_enemy_knockback_speed` impulse fires away from the enemy and
decays under the existing `arena_deceleration` (no new decel constant needed — it stops in
`6.0 / 65.0 ≈ 0.09 s`), and `arena_enemy_hit_stun` locks player input (movement, attack, dodge)
starting when hit-stop ends, comfortably outlasting the knockback's own decay. Rejected:
arena-local HP — it would invent a damage number with no real stakes attached (nothing consumes
it), and the obvious next move is wiring it to `kill_hero()` or a home-grown death path, which is
exactly the second result contract `P2b-01e` alone is supposed to own. Rejected: an on-screen
readout — the arena has no HUD yet, so this is new UI scope smuggled into a combat-timing ticket,
and a number on screen is a weaker "you got hit" signal than a shove and a stun.

**Dodge's remaining terms.**
- **Cooldown:** `arena_dodge_cooldown = 0.15 s` after the burst ends before another dodge may
  start. Rejected: no cooldown — immediate re-dodge turns dodge into a near-permanent i-frame
  toggle (the 0.53 s finding above assumes this floor exists; without it there is no "decision" at
  all, which is the opposite of the Phase 2 exit question).
- **Cancels light-attack recovery:** ~~confirmed, not tightened. The already-fixed rule ("end-
  recovery only, primarily after a Smash; no cancel during an active hit and no chained dodge")
  applies as written — dodge may start once the light attack's own state reaches its recovery
  window, and the `0.15 s` dodge cooldown already forecloses chaining a second dodge.~~
  **Superseded by `P2b-04`:** dodge (and parry, through the same gate) may now cancel a light
  attack at any point in its timeline — startup, active or recovery — see "Dodge/parry cancel
  opens to attack startup and active" below. The `0.15 s` dodge cooldown still forecloses chaining
  a second dodge.
- **Neutral dodge (no movement input held):** ~~a backstep — dodge direction is the camera-relative
  input direction if one is held (reusing the existing `_camera_relative_direction` helper used
  for locomotion and attack facing), otherwise directly away from the capsule's current facing.~~
  **Superseded by `P2b-01f`:** a neutral-input press of `dodge` no longer backsteps — it starts the
  parry stance instead (below). Dodge direction is still the camera-relative input direction
  whenever a movement input is held; there is no longer a no-input dodge case. A player wanting
  pure backward evasion now holds `S` and presses `dodge`, an ordinary directional dodge, not a
  special case. The rejection of a facing-forward roll (defaulting a defensive action toward
  whatever the player happens to be facing, usually the enemy, risks rolling into the attack it
  exists to avoid) still holds as reasoning against ever reviving a no-input roll default; only the
  backstep behavior it was defending is gone.
- **Input buffer:** deferred, not authored in this slice. The `0.15–0.25 s` buffer in the
  "Combat reference" table is cross-cutting (Normal, Smash and Dodge together); authoring it for
  dodge alone would give one action a buffer the others lack, which is a worse inconsistency than
  having none yet. Raw per-frame input polling (already how `_start_attack` and locomotion read
  input in `arena.gd`) is sufficient to make one enemy attack and one dodge playable.

> ⚠️ **PROVISIONAL** — every value in the table above is a first-playable number inside a verified
> arithmetic relationship, not felt design; the enemy turn speed and trigger/cooldown cadence in
> particular are guesses with no play behind them. · **Settled by:** playing `P2b-01d` and checking
> whether the `0.40–0.55 s` full-coverage dodge window reads as "timed" rather than "twitch" or
> "trivial," and whether `720°/s` enemy tracking and the `3.0 m` trigger range feel like a dummy
> worth dodging rather than a wall the player just walks around.

### Camera-forward facing and the parry stance (`P2b-01f`)

Two played-build changes from the `P2b-01d` build, ruled after the designer played it. Both
override text written before either was played; the superseded lines are struck and amended in
place above and in "Combat reference carried into future arena slices" and "Playtest questions
after `P2b-01c`" rather than left standing in contradiction.

#### Camera-forward facing

**Ruling:** hero facing tracks camera forward continuously — idle, moving forward, strafing,
backpedaling, and during attack startup alike — not only while a movement input vector happens to
be held. Today `_turn_hero` is called only when `move_direction != Vector3.ZERO` and turns toward
that camera-relative movement vector; the new model turns toward the camera pivot's own yaw
regardless of movement input, still rate-limited by `arena_turn_speed_degrees`.

| Question | Ruling |
|---|---|
| Track camera forward while strafing/backpedalling too, or only when input is neutral? | At all times, as asked — target yaw is always the camera pivot's yaw, whether the movement input is zero, forward, side, or reversed. |
| Still rate-limited at `arena_turn_speed_degrees = 1200°/s`, or snap? | Still rate-limited. At ordinary mouse-look speeds the camera's own per-frame yaw delta stays far below `1200°/s`, so hero yaw keeps pace with camera yaw and the two are visually indistinguishable from a snap — but the cap stays in the model rather than being special-cased away, so an unusually fast orbit still turns the capsule physically instead of teleporting its facing. |
| Does startup track camera forward instead of movement input? | Yes. The committed-active-window rule is unchanged: facing tracks its source through the end of `arena_light_attack_startup`, then commits — `_attack_direction` is still captured once when the active window opens, and the documented `15°–35°` active cone still governs how far a swing may continue to turn relative to its start. Only the *source* facing tracks during startup changes, from movement-direction to camera-forward. |
| Does the enemy's facing logic change? | No. `_turn_enemy` tracks the hero's position, not a camera — the enemy has no camera to track. |
| Does facing track camera forward during dodge, hit-stun, hit-stop, or the parry stance below? | No. Those remain committed states with facing locked at whatever it was on entry, same as today. The ask was that idle/strafing/backpedalling stop being exceptions to camera tracking, not that every combat state gain it; extending this into dodge/hit-stun/parry is a separate, unasked-for change and stays out of scope here. |

**Superseded, struck/amended in place (see those sections, not restated here):**
- "Combat reference carried into future arena slices" — *"Attacks follow the character's current
  facing, not camera forward."*
- "Playtest questions after `P2b-01c`" — *"Does a side/backward directional attack follow intended
  character facing rather than camera yaw?"*

> ⚠️ **PROVISIONAL** — camera-forward facing is an unplayed reversal of a direction that was
> already played and documented once. Nothing has confirmed it reads better than movement-direction
> facing did — only that the designer wants it tried. · **Settled by:** playing the reworked build
> and checking whether strafing/backpedalling while facing the enemy (now possible, previously
> impossible) reads as intentional aim rather than as the capsule's body looking unnaturally
> twisted relative to its own movement, since this is a graybox capsule with no strafe-specific
> animation state to sell the pose.

#### The parry stance

Reference: classic Vindictus Fiona/Vella guard, named explicitly by the user — a stance entered on
command that can stop an incoming attack, stagger the attacker on a good read, and open a counter.
The arena has no HP and no damage model, so "parry/block" here can only mean: negate the physical
hit-reaction a landed enemy attack currently causes, and, on success, punish the enemy with a
matching physical lockout instead.

**Trigger, and the dodge conflict.** Bound to the existing `dodge` action, disambiguated by
movement input at the moment of the press: a **press** (not hold) of `dodge` while the
camera-relative movement input vector is `Vector2.ZERO` starts the parry stance instead of a
dodge. A press with any movement input held still starts an ordinary directional dodge, unchanged.
Press, not hold — every action state in `arena.gd` (`_start_attack`, `_start_dodge`) is a single
press committing to a fixed startup/active/recovery timeline, and nothing in the file tracks a
held-input duration anywhere. A hold-to-guard variant would be the first held-input combat state
in the arena and duplicates dodge's own shape for no reason the user's own phrasing ("pressing
space... initiates a parry stance") asked for.

This **removes the neutral-input backstep** `P2b-01d` gave dodge — struck and amended in that
subsection above, not restated here. A player wanting pure backward evasion now holds `S` and
presses `dodge`: an ordinary directional dodge aimed away from the camera, not a special case.

**Played-build confirmation (2026-08-12).** The user played this exact trigger and confirmed it
directly: *"i actually like the fully release WASD and then press dodge."* It stays exactly as
authored — no separate bind, and the hold-to-guard rejection below stays closed. The `0.18 s` window
that shipped alongside it did not survive the same played build; see "The played build settles the
parry window and the enemy's facing lock" further down for the number that replaces it and why the
window, not the trigger, was the actual defect.

Availability gate: the same base guard `_start_dodge` already uses today (not already dodging,
parrying, hit-stunned, or in hit-stop) plus ~~the same attack-recovery-only cancel rule
(`P2b-01d`'s "Cancels light-attack recovery") — parry can interrupt the player's own attack
recovery on the same terms dodge already does, since it is dispatched from the same button.~~
**Superseded by `P2b-04`:** the same cancel rule dodge now uses, covering the whole attack
timeline rather than recovery alone — since parry shares dodge's entry gate, every term ruled for
dodge below lands on parry automatically, including that an active-window cancel forfeits the
pending hit rather than resolving it first.

| Tunable | Value | Rationale |
|---|---:|---|
| `arena_parry_startup` | `0.0 s` | No windup — the active window opens the instant the stance is entered, matching the dodge i-frame precedent (`P2b-01d`): a defensive window's value is entirely in timing against an already-telegraphed swing, not in adding its own tell. |
| `arena_parry_active_window` | ~~`0.18 s`~~ **`0.30 s`** | ~~Tighter than dodge's `0.25 s` i-frame window — parry's payoff (stagger + counter, below) is stronger than dodge's (avoidance only), so the read it demands is stricter.~~ **Superseded by "The played build settles the parry window and the enemy's facing lock" below.** Wider than dodge's own window now, on purpose: the trigger costs a full movement release before the press can even start, a combined act the bare dodge press never pays, so the number has to be sized for that combined act. |
| `arena_parry_whiff_recovery` | `0.35 s` (reviewed, held — see below) | Movement, attack, and dodge are locked for this long after an active window closes with nothing parried. Set equal to `arena_enemy_hit_stun` on purpose: guessing wrong costs about what actually eating the hit costs, so parry is not a strictly-safer default over standing still and reading the telegraph. |
| `arena_parry_success_recovery` | `0.10 s` | Short recovery after a stopped hit; cancellable early into an attack (below) rather than a fixed lockout. |
| `arena_parry_cooldown` | `0.15 s` | Own `BalanceTable` field, numerically matched to `arena_dodge_cooldown` at first-playable but tracked independently since parry and dodge are different actions sharing only a button. Applies after a successful parry's recovery (or its counter-attack) completes; the `0.35 s` whiff recovery already serves as that path's effective cooldown, so nothing stacks on top of it. |
| `arena_parry_hit_stop` | `0.08 s` | Contact freeze on a successful parry, distinct from `arena_light_attack_hit_stop` (`0.04 s`) and `arena_enemy_attack_hit_stop` (`0.06 s`) — pulled from the already-authored Heavy/Smash hit-stop band (`0.08–0.12 s`) rather than a new range, so a correct parry reads as a bigger moment than an ordinary exchange. |
| `arena_parry_enemy_stagger` | `0.6 s` | On a successful parry, the enemy's attack state is cancelled and it cannot begin a new attack for this long — long enough to fit one full player light-attack cycle (`0.12 + 0.10 + 0.22 = 0.44 s`) with margin for a real counter. Value reused from the already-authored `arena_enemy_attack_cooldown` rather than inventing a new constant. |

**What a successful parry does.** At minimum, negates the standard hit reaction entirely: no
`arena_enemy_knockback_speed` impulse, no `arena_enemy_hit_stun`, no hero-side hit-stop under the
enemy-attack-hit path. In its place: `arena_parry_hit_stop` freezes both capsules on contact, the
enemy is staggered for `arena_parry_enemy_stagger` (its attack state cancels the same way a hero
hit-stun already cancels the hero's own attack/dodge state today, and its cooldown does not begin
ticking again until the stagger ends), and the hero enters `arena_parry_success_recovery` instead
of `arena_parry_whiff_recovery`.

**Counter cancel: yes.** Pressing `attack` during `arena_parry_success_recovery` (or during the
stagger it opens) cancels the remaining recovery early and transitions straight into light-attack
startup — the Vindictus counter window the user named explicitly. This reuses the cancel pattern
`P2b-01d` already established for dodge cancelling attack recovery, mirrored the other direction
(attack cancelling parry-success recovery). Rejected: recover-only with no cancel — it would
mechanically reward a correct parry with nothing but a faster idle, which delivers only half of
what Fiona/Vella guard is actually known for and the user explicitly invoked.

**Binary, not late/early.** In the active window or not — no partial-credit "Just Guard vs. late
guard" tiering. Classic Vindictus does split perfect-guard from ordinary guard, but this slice
already carries seven new unplayed fields; a two-tier response multiplies that by adding a timing
sub-window nothing has tested yet. Matches the binary shape `_hero_has_iframes()` already uses for
dodge, keeping the two defensive mechanics structurally consistent. An attack landing after the
window closes gets the ordinary hit reaction, exactly as if no parry had been attempted — no
special penalty beyond having already spent `arena_parry_whiff_recovery` locked out.

**Rejected.**
- **Hold-to-guard input** — see "Trigger, and the dodge conflict" above; rejected for introducing
  a held-input tracking pattern nothing else in `arena.gd` uses, against the user's own "pressing"
  phrasing.
- **Sharing `arena_dodge_cooldown`** — rejected because parry and dodge are mechanically distinct
  (different payoff, different active-window math) and sharing one tunable would silently retune
  dodge's cooldown every time parry needs adjusting, or vice versa; they only share an input
  binding, not a balance axis.
- **A perfect/late guard split** — rejected above under "Binary, not late/early."
- **Arena-local block damage reduction** — not applicable; there is no damage number to reduce (no
  HP model). Parry's entire payoff has to be physical (negated reaction + stagger), which is what
  is ruled above.

> ⚠️ **PROVISIONAL, `arena_parry_active_window` settled by play, the rest still open** — the played
> build answered exactly the question this marker asked about the window: `0.18 s` read as a
> hair-trigger coin flip, not "you earned that." That value now has an arithmetic precedent (below,
> matching `P2b-01d`'s own overlap method) and is no longer a bare guess. `0.35 s` whiff recovery and
> `0.6 s` enemy stagger remain unplayed at the new window — see "The played build settles the parry
> window and the enemy's facing lock" below for why whiff recovery was reviewed and held rather than
> retuned blind. · **Settled by:** playing the `0.30 s` window and checking whether `0.35 s` whiff
> recovery still reads as a real cost now that the window itself is more forgiving, and whether
> `0.6 s` enemy stagger gives enough room for the counter to land before the enemy recovers control.

### Dodge/parry cancel opens to attack startup and active (`P2b-04`)

Playtest feedback asked that dodge and parry "instantly cancel out of most actions." "Most
actions" names no boundary, and `P2b-01d`'s recovery-only cancel window (confirmed above, not
loosened, until now) was a published ruling — this section reverses it and answers the four
questions the row required before any code changed. Nothing here touches hit-stun or hit-stop as
*cancellable states*; both stay locked exactly as already published, for the reasons below.

**1. A cancel out of an active attack eats the pending hit; it does not refund it.** The moment
`_start_dodge()`/`_start_parry()` fires while `_attack_elapsed` is inside the active window,
`_attack_hitbox.monitoring` is set `false` in that same frame — the branch that already exists at
`arena.gd:408-411` for the recovery case, unconditional on `_attack_elapsed >= 0.0`, needs no new
logic to cover active too. Any hit not already registered through
`_on_attack_hitbox_body_entered` before the cancel is simply lost; there is no retroactive
credit. Rejected: refund the hit on cancel — that would make cancelling strictly dominant over
committing (free defensive window *and* guaranteed damage), which erases the exact commitment the
active window exists to represent. Cancelling out of startup is unaffected by this question: no
hitbox is monitoring yet, so there is nothing to eat or refund.

**2. Hit-stun stays non-cancellable.** This is a confirmation, not a reversal — the existing text
already states `arena_enemy_hit_stun` "locks player input (movement, attack, dodge)," and that
holds. Hit-stun is not a player action; it is the enemy's entire reward for landing a hit, and
`arena_enemy_knockback_speed`'s own decay is already faster (`~0.09 s`) than the stun that outlasts
it (`0.35 s`) specifically so the stun is the real punish, not the shove. Making it cancellable
would mean every enemy swing that lands — after a `0.55 s` telegraph — costs the player nothing
beyond one tick toward `arena_enemy_hits_to_kill_hero`; the enemy's only attack becomes a pure
HP-counter with no positional or tempo cost, which is a different and weaker enemy than the one
`P2b-01d`/`P2b-01e` priced. `P2b-04`'s "most actions" is read narrowly on purpose: the player's own
committed actions (attack) becoming interruptible by the player's own defensive actions
(dodge/parry) is what the playtest note is about; a state the enemy imposes on the player is not
a "player action" in that sense. Rejected: cancellable hit-stun — priced above and rejected on
that price, not on principle.

**3. Hit-stop stays non-cancellable — no code change, and that is deliberately the cheap answer.**
Every hit-stop duration in this arena is under five frames at 60 fps
(`arena_light_attack_hit_stop = 0.04 s`, `arena_enemy_attack_hit_stop = 0.06 s`,
`arena_parry_hit_stop = 0.08 s`): a player cannot see the freeze and react inside it, so "input is
accepted but the freeze eats the frames anyway" and "input is refused outright" are the same
experience from the controller. Per the row's own instruction, rule the cheaper one: leave
`_start_dodge`'s existing `_hit_stop_remaining > 0.0` refusal exactly as it is. This also matches
the per-frame priority chain's own framing (`arena.gd:99-114`) — hit-stop freezing everything
first, before dodge/parry/attack/locomotion are even considered — as a universal freeze-frame
convention rather than a state any action-game reference expects the player to fight through.

**4. A cancel still pays `arena_dodge_cooldown` — cancelling is not free.** This is not a new
charge; it is how the cooldown already works. `arena_dodge_cooldown` is applied when the dodge
*burst ends* (`_update_dodge`, `arena.gd:202-206`), not when it starts, so it already fires
identically whatever state the dodge interrupted — ordinary locomotion, attack recovery, or now
attack startup/active. Exempting a cancel from it would need a new special-cased branch that
tracks *why* a dodge started, which is exactly the kind of unwritten boundary the row calls out
("most actions" is not a specification) — and it would make cancelling strictly better than a
clean dodge, when the two are meant to be the same action entered from a different door. This
follows the `_start_attack()` precedent already published rather than breaking from it: a
parry-cancel-into-attack still pays `arena_parry_cooldown` (`arena.gd:379-382`); a dodge/parry-
cancel-into-out-of-attack pays `arena_dodge_cooldown` the same way.

**Net change to `_start_dodge()`'s guard.** The two lines that refuse a cancel while
`_attack_elapsed` is inside `arena_light_attack_startup + arena_light_attack_active`
(`arena.gd:398-400`) are removed; the existing hit-stun/hit-stop/combat-finished/already-
dodging/already-parrying guard above them (`arena.gd:390-397`) is untouched, since none of those
five are in scope here. No new `BalanceTable` field: every number this section reasons about was
already authored.

> ⚠️ **PROVISIONAL** — this is an unplayed reversal of a term that was itself published from
> arithmetic, not play. Whether an instant startup/active cancel reads as responsive rather than
> as making the light attack's commitment feel hollow — and whether losing the pending hit on an
> active-window cancel reads as a fair trade rather than a punish for pressing the "right" button
> a frame too early — is exactly the Phase 2 exit question (is spending a hero's life a decision
> you actually feel) one level down: is committing to a swing a decision you actually feel, once
> backing out of it is one button away. · **Settled by:** playing it against the existing enemy
> swing (`0.55/0.10/0.45 s`) and dodge cycle (`0.38 s` burst + `0.15 s` cooldown) already on the
> page.

### The played build settles the parry window and the enemy's facing lock (`P2b-12`)

**Opened 2026-08-12 from the user's played build**, the first real play of `P2b-09`/`P2b-10`/`P2b-11`'s
animated arena, verbatim: *"in gameplay, either the parry window is non intuitive or the parry window
is too small, its very to hard to get a parry off. and after dodge, the enemy is able to still reach
the player and hit while the distance looks like its enough to avoid the attack."* This is the exact
question "The parry stance"'s own `PROVISIONAL` marker named as its settling condition, and the harder
half — the dodge complaint — reopens a `P2b-01d` rejection. Nothing here touches `resolve()`,
`CombatResult`, or permadeath; the arena stays display-only (`DECISIONS.md`, 2026-08-11).

**The trigger is not part of this ruling — see the played-build confirmation note under "Trigger, and
the dodge conflict" above.** The user played `P2b-01f`'s shared-button, exactly-zero-input trigger and
kept it on purpose. Everything below is sized around that trigger being real, not around removing it.

#### Parry window: `0.18 s → 0.30 s`

The window was too small, and the arithmetic explains why by the same overlap method `P2b-01d` used
for dodge (Codex-verified, thread `019ff769-a39f-75e0-8900-5697f34dc61c`): treating the enemy's hit-
active window as `t ∈ [0.55, 0.65]` (from `arena_enemy_attack_startup = 0.55 s` and
`arena_enemy_attack_active = 0.10 s`), a parry active window `W` opening instantly at press time `p`
gives a "full coverage of the enemy's active window" press interval of width `W − 0.10`. Dodge's own
`0.25 s` i-frame window gives `0.15 s` of full-coverage press slack — the number "The parry stance"'s
Rationale column called "fair." At the old `0.18 s`, parry's equivalent slack was `0.08 s`, roughly
half of dodge's, **before** accounting for the fact that reaching the parry branch at all costs a full
WASD release the dodge branch never pays. Two guesses stacked on top of each other, not one.

`W = 0.25 s` (exactly `arena_dodge_iframe_duration`) reproduces dodge's own `0.15 s` full-coverage
slack precisely — the floor a bare press-and-time-it action would need, verified rather than assumed.
Landing there is not enough on its own: the parry branch is not a bare press. `arena_parry_active_window`
is set to **`0.30 s`** — the `0.25 s` parity floor plus a `0.05 s` pad for the release-then-press
combined act, giving `0.20 s` of full-coverage slack, `33%` more forgiving than dodge's own already-
verified-fair number. The floor is arithmetic; the pad is a design guess sized to the extra step, not
measured against it — there is no clock on "time to release WASD and hit space" in this project to
verify against.

**`arena_parry_whiff_recovery` reviewed, held at `0.35 s`.** A wider active window raises how often a
well-timed press *lands* inside it; it does not change what a *miss* costs, and "guessing wrong costs
about what actually eating the hit costs" (`P2b-01f`'s own reasoning for setting it equal to
`arena_enemy_hit_stun`) is a per-attempt equivalence between two fixed numbers, `0.35 s` vs `0.35 s`,
neither of which the window touches. What a wider window *does* raise is how often the branch gets
attempted casually rather than read — and the trigger the user just confirmed they like is already the
brake on that: every attempt costs abandoning movement entirely against an enemy that is closing
distance, which is a real tempo cost independent of whether the attempt then succeeds. That existing,
now user-validated cost is judged sufficient here. **Rejected: raising whiff recovery alongside the
window "to be safe."** Retuning a number with no evidence it needs to move, on the same play pass that
already flagged the number that does, is exactly the "reads real, measures nothing" failure this
backlog keeps naming. If a played build shows parry turning spammy despite the release-first cost,
`arena_parry_whiff_recovery` (or `arena_parry_cooldown`) is the next lever — not shrinking the window
back down, which would reintroduce the reported defect.

> ⚠️ **PROVISIONAL** — the `0.25 s` floor has the same arithmetic pedigree dodge's own window does; the
> `0.05 s` pad on top of it does not, and neither does holding whiff recovery unchanged. · **Settled
> by:** playing `0.30 s` against the confirmed trigger and checking whether it reads as earned rather
> than a coin flip, and specifically checking whether parry gets attempted more casually now that it
> succeeds more often — if so, the fix is `arena_parry_whiff_recovery`/`arena_parry_cooldown`, per
> above, not the window.

#### The enemy's facing locks partway through startup, not at it

**Why a lateral or diagonal dodge currently cannot escape, confirmed.** `EnemyAttackHitbox` spans
capsule-local `z ∈ [-2.35, -0.75]`, half-width `0.75`; with both capsules at `CapsuleShape3D` radius
`0.75`, contact reaches `3.10 m` centre-to-centre with a `±1.5 m` lateral corridor around the enemy's
forward axis. `_update_enemy_attack()` calls `_turn_enemy()` (`720°/s`,
`arena_enemy_turn_speed_degrees`) for the *entire* `0.55 s` startup, locking facing only once the
active window opens — so any lateral displacement the player earns during startup is erased by
re-aiming before it can matter. `_start_enemy_attack()` already calls `_stop_enemy_horizontal()`
(`arena.gd:695`): the enemy does not translate during its own attack, only turns, which is what makes
the fix a pure rotation-timing change with no position math to reconcile.

**Fix: lock facing at `arena_enemy_attack_facing_lock = 0.36 s`** (new field), `65%` through the
`0.55 s` startup, rather than at its end. Codex-verified (same thread as above), using the real dodge
speed profile — `v(t) = 13.5 × (1 − t / 0.38)`, `d(t) = 13.5t − 13.5t² / 0.76` — not a linear
approximation:

- The knife-edge minimum is `T_lock = 0.415 s`: a hero exactly on-axis at that instant, dodging pure
  lateral starting immediately, clears the `1.5 m` corridor with *zero* margin exactly as `t = 0.55 s`
  arrives (`d(0.135) = 1.5 m`). Starting the dodge any earlier than the lock does not help — pre-lock
  displacement is erased by continued tracking, and the deceleration profile is front-loaded
  (`d''(t) = −35.53 m/s² < 0`), so a dodge already spent by the time of lock has less post-lock travel
  left than one starting fresh at the lock. `0.415 s` is therefore not a value to ship; it is the
  boundary past which no lock time works at all.
- `T_lock = 0.36 s` leaves `τ' = 0.19 s` of locked corridor before contact, `d(0.19) = 1.924 m` —
  `28%` of spare displacement over the `1.5 m` requirement for a **pure lateral** dodge. This is
  deliberately not knife-edge, matching the margin philosophy `P2b-01d`'s own dodge-window numbers
  already used (`0.15 s` of full-coverage slack, not the bare minimum overlap).
- **Diagonal dodges are not separately guaranteed by this number.** A `45°` lateral/backward dodge
  only delivers `sin(45°) × 1.924 = 1.36 m` of lateral clearance at `T_lock = 0.36 s` — short of `1.5 m`.
  Guaranteeing a `45°` diagonal too would need `T_lock ≤ 0.32 s`, trading margin on the pure-lateral
  case for coverage on the diagonal one. This ruling does not make that trade: pure lateral is the
  strongest form of the user's complaint ("the distance looks like enough"), a diagonal dodge also
  gains real distance along the (now-fixed) forward axis that this single-axis arithmetic doesn't
  credit it for, and proving the multi-axis case exactly is the "needs to be felt, not calculated"
  kind of question this project keeps flagging rather than fabricating a number for. Left open below.
- Range-independence confirmed: the `1.5 m` corridor requirement does not change with how far the
  hero is when the dodge starts (`2.4 m` preferred range or `3.0 m` trigger range) — only the arc angle
  the enemy would have had to close does, and that stopped mattering the moment tracking locks.
- A useful coincidence, not engineered: `T_lock = 0.36 s` falls *before* `t = 0.40 s`, where dodge's
  own already-taught "full coverage" press window begins (`P2b-01d`, "Why `0.55 s` startup is fair").
  A player already using the timing discipline this project asks them to learn for straight avoidance
  gets a guaranteed-locked corridor to reposition into, by construction, without a second read to learn.

**What stays unchanged, and why.** `arena_enemy_attack_reach` (`1.6 m`), `arena_enemy_preferred_range`
(`2.4 m`), and the `±1.5 m` lateral corridor (ungoverned by any tunable — inherited from the shared
graybox `Shape_attack`) are not touched here. The "no spacing margin" finding (`0.7 m` inside the box's
front face at the enemy's own preferred range) is real, but it was never the mechanism the escape
depends on — the facing lock restores lateral/diagonal escape through the corridor's *width*, not
through opening distance at range, so shrinking reach or widening preferred range would change the
enemy's whole approach behaviour to fix a problem the rotation fix already closes. **Rejected: reducing
`arena_enemy_attack_reach` or increasing `arena_enemy_preferred_range` instead of locking facing** — the
smaller, more contained change wins, and retuning either would need its own re-derivation of the "no
spacing margin" framing this section leans on rather than reopening. **Rejected: reducing
`arena_enemy_turn_speed_degrees` instead of adding a lock cutoff** — a slower turn still eventually
re-aims, so it trades a hard, provable guarantee (facing frozen, corridor fixed) for a softer one that
would need its own overlap arithmetic to verify, and `720°/s` is load-bearing elsewhere (the enemy's
general MOVE-state tracking, "always facing the player... regardless of circling") that this section has
no reason to touch.

**Capsule radius vs. the real mesh — flagged, not changed.** `0.75 m` radius (`1.5 m` diameter) was
authored for a graybox capsule in `P2b-01a` and never revisited when `P2b-09`/`P2b-10` landed real
humanoid meshes; a humanoid is visibly narrower, so the hero can look clear of the sword and still
register contact even after the fix above. Left out of this ruling on purpose: it is a locomotion- and
camera-collision-radius change, not an attack-hitbox change, so its blast radius is the whole capsule,
not one attack. That is a larger, separately-scoped change than "smallest set of changes that fixes the
two reported problems" covers here.

> ⚠️ **PROVISIONAL** — `arena_enemy_attack_facing_lock = 0.36 s` is Codex-verified against the real
> dodge deceleration curve for the pure-lateral case, which is more arithmetic backing than most of
> this document's PROVISIONAL numbers carry, but it has never been played. Diagonal-dodge coverage is
> explicitly not guaranteed by it (above). · **Settled by:** playing the corridor-escape lock against
> lateral *and* diagonal dodge attempts and checking whether the diagonal case needs its own lock time,
> a wider corridor, or reads as "good enough" because of the extra distance gained along the fixed
> forward axis that this arithmetic didn't credit.
>
> ⚠️ **PROVISIONAL** — capsule radius `0.75 m` vs. the real mesh silhouette. · **Settled by:** measuring
> the imported mesh's actual width (director can do this) and deciding whether a capsule shrink is
> warranted — and if so, scoping it as its own ticket, since it touches locomotion and camera collision
> project-wide, not just this attack.

#### Clip/phase alignment: real, likely the largest single contributor, and not this ticket's fix

`P2b-10`'s verifier pass already found it: the enemy's `Sword_Regular_A` dominant arm motion peaks at
`0.4 s`; `EnemyAttackHitbox` only goes live at `0.55 s`. The visible sword completes its arc, and
roughly `0.15 s` later — after the blade has already settled — an invisible box registers the hit. Of
the three contributors this ruling found (spacing, facing tracking, clip timing), this is plausibly the
largest: it is the one that makes an already-successful escape *look* successful and then isn't, which
matches "the distance looks like its enough" more precisely than either geometry finding does on its
own.

**Ruling: the target is alignment to `t ≈ 0.55 s`, not moving `0.55 s` to meet the animation.** Startup
`= 0.55 s` carries `P2b-01d`'s whole dodge-fairness arithmetic (the `0.40–0.55 s` full-coverage press
window, the `4.5×`-the-player's-own-startup readability argument, the non-integer-multiple dodge-cycle
spam-proofing) and `P2b-01e`'s timeline check (`1.76 s` landed-hit interval, `~4.07 s` worst-case time
to death). Moving startup to chase the animation's accidental `0.4 s` peak would reprice all of that for
a fix that belongs one layer down. **Rejected: shortening `arena_enemy_attack_startup` to `~0.4 s`** —
correct symptom, wrong layer, and the layer it's wrong for has more verified arithmetic resting on it
than any other number in this document.

**Not fixed here — routed to `P2b-13`.** `P2b-13` already rebuilds the animation layer onto an
`AnimationTree`; retiming the current one-shot clip now and again once `P2b-13` lands is re-timing the
same thing twice, which is exactly the ordering `docs/TASKS.md` already calls out for these two
tickets. This section's contribution is the *target*, not the mechanism: whatever `P2b-13` does to blend
and time enemy attack playback, the sword's peak extension should land at or immediately before
`t = 0.55 s` (the active window's onset), not at `0.4 s`. `P2b-13`'s own acceptance criteria should
carry this number forward rather than re-deriving it.

> ⚠️ **PROVISIONAL** — the `t ≈ 0.55 s` alignment target is a design ruling (contact should read as
> caused by the visible swing, not by an invisible box after it settles); it is not yet arithmetic
> against a specific `AnimationTree` implementation, since `P2b-13` hasn't landed. · **Settled by:**
> `P2b-13` landing with the sword's peak retimed to `~0.55 s` and a played build confirming the
> "invisible box after the blade settles" read is gone.

### Hero HP and the death rule (`P2b-01e`)

`P2b-01d` shipped the enemy's full hit-stop/knockback/hit-stun timeline but deliberately shipped no
HP anywhere, naming this ticket as the owner once `CombatResult` gives the number real stakes
(`docs/TASKS.md:671`). Three questions, ruled in order.

**1. How a landed hit becomes HP loss.** A flat hit count, not a per-hit fraction compared against
a floating HP total. `arena_enemy_hits_to_kill_hero = 3`: the arena tracks one integer,
`_hits_taken`, incremented once per landed, un-dodged, un-parried enemy hit (the existing
`HitStopOutcome.HIT_HERO` branch, `combat/arena/arena.gd:183-191` — it already exists and only
needs the counter added beside it). The hero is dead the instant `_hits_taken >= 3`; that integer
comparison, not a float crossing zero, is the authoritative death signal. `CombatResult.hp_after`
is populated for display/contract purposes only, derived from the same count:

```
damage_fraction = clamp(float(hits_taken) / float(arena_enemy_hits_to_kill_hero), 0.0, 1.0)
hp_after = maximum_hp * (1.0 - damage_fraction)
```

which mirrors `quick_resolve.gd:41`/`:51`'s existing `maximum_hp * (1.0 - damage_fraction)` shape
rather than inventing a new one. `maximum_hp` is sourced from
`Hero.compute_final_stats(hero, definition, BALANCE, level)[Hero.STAT_HP]`, already required by the
ticket's acceptance criterion 1. Routing to `survivors`/`dead_heroes` reads `_hits_taken`, never
`hp_after <= 0.0`.

**Rejected: a per-hit HP fraction with float-threshold death** (`hp_after <= 0.0` decides).
Codex-verified (thread `019fed84-aa60-7591-9d13-585de410ce7f`) that a fixed `1/3`-per-hit fraction
*can* be made to land exactly on `0.0` after three hits, but only if the constant is computed as
the expression `1.0 / 3.0` at the point of use — the moment that value instead comes from a `.tres`
decimal literal with finite digits (the normal way `BalanceTable` fields are authored and the
normal way the Godot editor round-trips a saved float), `3 * fraction` rounds to something a hair
under `1.0`, `clamp(..., 0.0, 1.0)` doesn't trigger, and the "killing" third hit leaves the hero
alive at a `~1e-13`-fraction sliver of HP. An integer hit counter has no equivalent failure mode
and is also less code than getting float rounding right on purpose, so it wins outright — not just
by being safer.

**Rejected: iterative decay (`hp_after *= (1.0 - fraction)` per hit).** Also Codex-verified: this
is a different model (diminishing returns per hit, not three equal-sized hits) and leaves the hero
alive at `~29.6%` HP after three hits instead of dead. It's a plausible model on its own terms but
not the one three hits killing means.

**Why 3, not 1 or 2.** 1 hit is inconsistent with what `P2b-01d` already shipped: hit-stop then a
knockback impulse then `0.35 s` of locked player input only make sense if the encounter continues
afterward — a one-hit death would have to replace that whole reaction with an immediate end-state,
contradicting the "comfortably outlasting the knockback's own decay" framing already written for
it (`SYSTEMS.md:1097`). 2 hits was the tighter alternative considered and rejected for this first
slice: it halves the margin for a player who is still learning the `0.55 s` telegraph read
`P2b-01d` was written to teach, without any played evidence that the tighter number reads better —
3 gives a "first hit is a scare, second is a real warning, third is death" arc, consistent with the
"learnable, not hair-trigger" intent already on record for the dodge window. Nothing here retunes
`P2b-01d`'s own ~21 values; only the new hit-count field is authored.

**Timeline check — winnable, and losable.** Using the already-shipped cadence (`P2b-01d`) and the
already-shipped player attack cycle (`P2b-01c`), Codex-verified from `_update_enemy` and
`_update_hit_stun` directly (same thread):
- **Losable, and not trivially so.** `_update_hit_stun` never gates `_update_enemy`
  (`combat/arena/arena.gd:67-83`), so a player who stands in range and never dodges or parries
  keeps taking hits on the enemy's own clock regardless of being stunned. Landed-hit-to-landed-hit
  interval is `0.06 s` hit-stop + `0.10 s` active + `0.45 s` recovery + `0.6 s` cooldown + `0.55 s`
  startup = `1.76 s` (not the raw `1.70 s` telegraph-to-telegraph figure from `P2b-01d`, which
  didn't account for the hit-stop pause). Third hit — death — lands at roughly `t ≈ 4.07 s` into
  the encounter if the player does nothing but stand still and eat every swing. That is long enough
  to register as "I could have dodged that" more than once, not a single unlucky frame.
- **Winnable without requiring perfect play.** The enemy stays a one-hit kill (below), and the
  player's full attack cycle (`0.12 + 0.10 = 0.22 s` to the active hit frame) is shorter than the
  enemy's own `0.55 s` telegraph, so a player who closes distance and swings during the *first*
  telegraph can land the killing blow before ever being hit, without needing to dodge at all. A
  player who instead reads dodges (already shown non-spammable but learnable in `P2b-01d`'s
  interval-arithmetic finding) survives indefinitely on defense and only needs one clean opening in
  the enemy's `0.45 s` recovery or gaps in its cadence to end it. Both a competent-play win and a
  do-nothing loss are reachable through the real input handlers, which is what the ticket's GUT
  acceptance criteria (2)/(3) need.

**2. Does the enemy capsule get HP too.** No — it keeps `P2b-01c`'s existing one-hit-kill rule,
unconditionally, regardless of `wave.enemy_power`. No new field. **Rejected: enemy HP scaled off
`wave.enemy_power`** — there is no authored player-damage-per-hit number to scale against (light
attack has never had one; it has only ever been "defeats the passive target on contact"), so this
would mean inventing a full enemy stat/damage model, which is exactly the "enemy bestiary/species"
scope the ticket's Non-goals already excludes. It would also retune a mechanic `P2b-01c` shipped
and is itself unplayed feel, which this ruling is told not to touch.

**3. Does either number scale with the power ratio.** No — fixed for this slice. Neither
`arena_enemy_hits_to_kill_hero` nor the enemy's one-hit-kill rule reads `wave.enemy_power` or
`effective_enemy_power / team_power`. **Rejected: deriving the hit count (or a per-hit fraction)
from `r = effective_enemy_power / team_power`**, the ratio `quick_resolve.gd:29-32` already
computes — the arena is exactly one hero against exactly one enemy in real time; there is no
`team_power` analogue for a single capsule (`Hero.compute_team_power` sums four stats across a
roster the arena never builds), and inventing one solely to feed an `r` this slice's timeline
doesn't otherwise use is authoring a system where a constant already suffices. Concretely, this
means a graybox dummy fed Verdant Outskirts' `Wave` (`recommended_power = 900`) and one fed
Sundered Vault's (`recommended_power = 11500`, ~12.8× harder) currently die and kill on identical
terms — the fixed number doesn't know the difference. That's acceptable for an integration slice
whose own enemy is still a single graybox capsule with no bestiary, but it is the concrete fact
that forces this ruling open again once the arena needs to represent more than one zone's actual
difficulty, not a hypothetical. A side effect worth flagging to whoever scopes the implementation:
because nothing here reads `wave.enemy_power`, the `Wave` the ticket requires passing into the
arena is presently an inert pass-through for combat purposes — carried for the
`docs/KNOWN_ISSUES.md` § "Quick resolve and the arena will disagree" reconciliation Phase 3 already
defers, not consumed by anything in this slice. Not a scope change; the ticket already requires
accepting a real `Wave` regardless of whether its number is used yet.

**New `BalanceTable` field.**

| Tunable | Value |
|---|---:|
| `arena_enemy_hits_to_kill_hero` | `3` (int) |

Sits beside `arena_enemy_hit_stun` in both `balance_table.gd` and `balance.tres`, in the same block
as the rest of `P2b-01d`'s enemy attack tunables (`balance.tres:38-40`). No field is added for the
enemy capsule's HP — it has none.

> ⚠️ **PROVISIONAL** — `3` is a first-playable number chosen for consistency with the already-shipped
> (also-PROVISIONAL) hit-reaction timeline, not felt design; nobody has died in the arena yet. The
> `4.07 s` worst-case-tank timeline above is checked arithmetic, not played experience. · **Settled
> by:** playing the real fight `P2b-01e` produces and checking whether three tank-hits reads as
> "I had time to learn the read" or "the fight was already over before I understood what hit me,"
> whether a single landed hit already feels sufficiently costly given the knockback+stun that
> lands before any HP is even lost, and — per the Phase 2 exit question — whether losing the arena
> hero (once this reaches a real permadeath consumer, which this slice explicitly does not) reads
> as a decision anyone felt or as an inevitability nobody could have avoided.

### Five-hit chain, enemy HP and enemy defence

The arena's first slices deliberately shipped one attack against one passive capsule with no HP
anywhere (`P2b-01c`, `P2b-01d`). Both halves of that now have the other side.

**Player chain.** Light attack chains up to `arena_light_attack_combo_length = 5`. A press landing
while an attack is running is *buffered* and fires at the link point (the end of that attack's
recovery) rather than being dropped, so the chain does not demand frame-perfect input — this is the
`0.15–0.25 s` input buffer already carried forward above, spent here. After recovery ends with no
buffered press, `arena_light_attack_combo_window = 0.25 s` keeps the chain open; letting it lapse,
taking a hit, or dodging resets to hit 1.

**Damage.** Hit `i` (0-based) deals
`arena_light_attack_damage * (1 + arena_light_attack_combo_damage_step * i)`. At `20.0` base and
`0.15` per step that is `20 / 23 / 26 / 29 / 32`, summing to `130` across five hits and `98` across
four.

**Enemy HP.** `arena_enemy_max_hp = 120.0`, chosen against that sequence rather than picked round:
`98 < 120 ≤ 130` is the only band where a clean five-hit chain kills and a four-hit chain does not.
Change either the base damage or the step and this number is no longer correct — the constraint is
the arithmetic, not the value. Non-lethal hits get `arena_enemy_hit_flinch_stop = 0.05 s` of
hit-stop plus the existing white tint, sitting between the light (`0.04 s`) and enemy-attack
(`0.06 s`) bands already authored.

**Enemy states.** One state machine — `MOVE / ATTACK / DODGE / PARRY / STAGGER` — not three
overlapping flags. The enemy commits to its own swing: a dodge or parry can only start from `MOVE`.

| Tunable | Value | Note |
|---|---:|---|
| `arena_enemy_move_speed` | `4.2 m/s` | Below the player's `5.8` walk, well below the `8.0` sprint — disengaging stays possible. |
| `arena_enemy_preferred_range` | `2.4 m` | Closes to here; inside `arena_enemy_attack_trigger_range` (`3.0 m`), so it swings before arriving. |
| `arena_enemy_backoff_range` | `1.6 m` | Backs off below this. The `1.6–2.4 m` band is where it holds. |
| `arena_enemy_dodge_chance` | `0.35` | Rolled once, when the player's swing goes active and the enemy is inside `reach + displacement = 3.5 m`. |
| `arena_enemy_dodge_speed` | `11.0 m/s` | Below the player's `13.5` dodge. |
| `arena_enemy_dodge_duration` | `0.32 s` | |
| `arena_enemy_dodge_iframe_duration` | `0.22 s` | Shorter than the player's `0.25 s`. |
| `arena_enemy_dodge_cooldown` | `1.2 s` | Long, so consecutive chain hits cannot all be dodged. |
| `arena_enemy_parry_chance` | `0.25` | Rolled before dodge; parry wins the tie. |
| `arena_enemy_parry_active_window` | `0.2 s` | |
| `arena_enemy_parry_cooldown` | `1.6 s` | |
| `arena_enemy_parry_damage_reduction` | `0.6` | Fraction of the hit removed. |
| `arena_enemy_big_hit_chance` | `0.1` | Rolled on every landed non-lethal hit, light or smash. |
| `arena_enemy_big_hit_stagger` | `0.9 s` | The opening a big hit buys. |

### One hit in ten is a big one

A landed hit normally buys `0.05 s` of hit-stop and nothing else: the enemy keeps its pose and
resumes whatever it was doing. `arena_enemy_big_hit_chance = 0.1` of them instead cancel the enemy's
attack outright and drop it into `STAGGER` for `arena_enemy_big_hit_stagger`, playing the `Big Hit To
Head` reaction. It is the same state a parry produces, on a longer clock and tinted as a hit rather
than as a parry — the player should not read a coin flip as a successful defensive read.

The length is set against the light-attack cycle, not against the clip. Three lights fit in
`0.42 × 3 = 1.26 s`, so playing the Mixamo reaction at its authored `1.30 s` would hand over a free
full chain for something the player did not earn. `0.9 s` fits two, which reads as a real opening
without out-paying the parry's `0.6 s` by more than the parry's own advantage of being deliberate.

> ⚠️ **PROVISIONAL** — the rate and the window are both desk numbers. At `0.1`, a `120 HP` enemy dying
> to roughly six to eight hits sees a big hit in about half of all fights, which is either "a rare
> treat" or "an inconsistency the player cannot plan around" depending entirely on how it feels.
> **Settled by:** a played build. Nothing about this is resolvable by arithmetic.

**The enemy's parry is not the player's parry, and that asymmetry is the design.** A player parry
hit-stops, staggers the enemy for `0.6 s` and opens a counter. An enemy parry does exactly one
thing: scale that hit's damage by `1 - 0.6`. No hit-stun, no knockback, no combo reset, no cooldown
charged to the player, no interruption of the chain. Enemy defence costs the player damage, never
tempo — the enemy is an obstacle to read, not a source of punishes. A dodged hit whiffs outright
for that swing rather than getting a second chance once the i-frames lapse.

> ⚠️ **PROVISIONAL** — every number above is unplayed. The two probabilities are the softest: a
> `0.35` dodge and `0.25` parry rolled per swing mean a five-hit chain lands clean only about a
> sixth of the time, which may read as a fight or as a slot machine. · **Settled by:** playing it,
> and specifically checking whether losing a chain to a roll the player could not have read feels
> different from losing it to a mistake.

### Impact feedback channels — what the arena still has none of

An external hit-feel reference was audited against this section on 2026-08-11. Almost all of it —
the three attack phases, hit-stop durations, target stagger, animation cancelling, tight
anticipation — is already authored above with a source and a rejected-alternatives trail, and the
reference adds nothing to those. It is recorded here only for the three channels the arena
genuinely has **none** of, plus one live tension.

`P2b-01c` through `P2b-04` built the arena's impact feedback entirely out of *timing* — hit-stop,
knockback, hit-stun, stagger — plus one *tint* channel (the capsule albedo overrides in
`combat/arena/arena.gd`). Three of the reference's channels are absent from the codebase outright,
confirmed by grep: no `AudioStreamPlayer` anywhere in the project, no particle system, no camera
shake.

| Missing channel | Reference spec | Ruling |
|---|---|---|
| **Camera shake on impact** | Impulse with decay, scaled by hit weight. **Must be user-toggleable.** | **Taken — shipped.** No assets needed, and it is the only channel that converts a localized freeze into something the whole frame registers. Specified below. Toggle is not optional: motion sensitivity is an accessibility floor, not a preference. |
| **Impact audio** | Multi-layered crunch/slice at contact. The reference's own claim is that audio carries more weight than visuals, and that weak audio flattens good animation. | **Defer — needs assets, not code.** The project has no audio bus, no sound files, and no asset pipeline for them. This is the single largest remaining feel gap and is worth a ticket, but not one an implementer can close. |
| **Directional hit particles** | Short burst along the hit vector. | **Defer.** Two graybox capsules give the eye nothing to follow yet. Revisit when the arena has real geometry. |

**Camera shake — derived, not tabled.** Shake takes no per-outcome table of its own. Both its
amplitude and its length come from the hit-stop already authored for that contact, because hit-stop
length *is* this project's existing encoding of hit weight (`0.04 s` light, `0.05 s` flinch,
`0.06 s` enemy hit, `0.08 s` parry). Two scale factors, and the four contact types stay ordered
without anyone maintaining that ordering twice:

| Tunable | Value | Meaning |
|---|---:|---|
| `arena_screen_shake_magnitude_scale` | `0.4` | Metres of camera-pivot offset per second of hit-stop. A parry (`0.08 s`) shakes `0.032 m`, a flinch (`0.05 s`) shakes `0.020 m`. Was `1.6`; cut by 75% on the owner's 2026-09-24 play-test ("too intense"). |
| `arena_screen_shake_duration_scale` | `3.0` | Seconds of shake per second of hit-stop — a parry shakes for `0.24 s`, roughly three times its own freeze. |

Amplitude falls off linearly with the remaining time, so the shake settles rather than cutting out,
and the offset is applied in camera space on the pivot — never on `CameraPivot.rotation`, which is
the player's mouse look and must not be written to. Shake runs *during* hit-stop rather than being
frozen by it: the freeze is the thing it is decorating.

**Where the toggle lives.** A `ConfigFile` at `user://settings.cfg` (`systems/settings.gd`), not
`GameSession.to_dict()`. Screen shake is a display preference, not game state, and the save
round-trip is this repo's first-listed risky boundary (`CLAUDE.md`) — routing a preference through
it buys a mandatory verifier pass for nothing. `ConfigFile` is stdlib, needs no autoload, and so
does not touch the three-autoload cap. The checkbox is in the pause menu, which is reachable from
the hub and not from inside the arena, so the arena reads the value once on entry.

**The one live tension: anticipation length.** The reference targets `0.05–0.10 s` of wind-up for
fast-paced light attacks. This project authored `arena_light_attack_startup = 0.12 s` above, from
the *Vindictus* ranges, with reasoning already on the page. `0.12` is outside the reference band by
`20 ms` — one to two frames at 60 FPS. **Not changed here.** Both numbers are unplayed, the
existing one has a cited source and this one does not, and re-tuning a published provisional value
against a second unplayed reference trades one guess for another. It is flagged so the next play
pass tests it deliberately rather than rediscovering it.

**Not recorded because it is already above:** the three-phase attack anatomy (`P2b-01c`
timeline), hit-stop bands (`0.03–0.05 s` light / `0.08–0.12 s` heavy), input buffering
(`0.15–0.25 s`), target stagger and knockback (`P2b-01d`), animation cancelling (`P2b-04`, which
opens cancels wider than the reference does), and the white flash on contact (the existing
`HIT_HERO_COLOR` / `DEFEAT_ENEMY_COLOR` overrides). The reference's `2–3 frame` flash duration
(`0.03–0.05 s`) is the one usable number inside that group, and it matches the light hit-stop band
the arena already uses to time those tints.

> ⚠️ **PROVISIONAL** — the owner felt the shake on 2026-09-24 and found it too intense, so the
> magnitude went from `1.6` to `0.4` (75% less; the battle view's `SHAKE_MAX_OFFSET_FRACTION`
> went from `0.03` to `0.0075` with it). The duration scale is unchanged. · **Settled by:** the
> next play-test, which is also the pass that settles the `0.12 s` vs `0.10 s` anticipation
> question above.

### Smash, super armor and the parry cue

Played on 2026-08-11. The play pass the section above asked for happened, and it settled the open
anticipation question and opened three new mechanics. A second external reference — a Pearl Abyss
(*Black Desert Online* / *Crimson Desert*) combat-architecture analysis — was audited on the same
day; what it contributed is marked below, and what it did not is at the end.

**Anticipation, settled.** `arena_light_attack_startup` is now `0.10 s`, down from `0.12 s`. The
tension flagged above ("the reference targets `0.05–0.10 s`, this project authored `0.12`, both
unplayed") is resolved the way it said it would be: by playing it. The designer's read after the
play pass was that the wind-up is still long, which is the reference band's own claim, so the value
moves to the top of that band rather than into it. No longer provisional — this is a played value,
the first one in this section.

Nothing else in the light attack's timeline moves. Active (`0.10 s`) and recovery (`0.22 s`) were
not what read as slow.

#### The smash (right mouse button)

`heavy_attack` is bound to RMB in `project.godot`, alongside `attack` on LMB. It runs through the
same attack state as the light — same `_attack_elapsed` timeline, same three phases, same cancel
rules, same hitbox — reading heavy values where they differ. It is not a second state machine.

| Tunable | Value | Against the light |
|---|---:|---|
| `arena_heavy_attack_startup` | `0.30 s` | `3×` the light's `0.10 s`. The commitment *is* the mechanic — see super armor below. |
| `arena_heavy_attack_active` | `0.12 s` | Slightly wider than `0.10 s`. |
| `arena_heavy_attack_recovery` | `0.50 s` | More than double the light's `0.22 s`. A whiffed smash is punishable. |
| `arena_heavy_attack_displacement` | `3.0 m` | Against `2.0 m`. Reach is deliberately *not* a separate field: the lunge is what extends the smash's range, so both attacks keep one `arena_light_attack_reach` hitbox and no shape is resized at runtime. |
| `arena_heavy_attack_hit_stop` | `0.09 s` | The Heavy/Smash band (`0.08–0.12 s`) carried forward since `P2b-01c`, finally spent. Screen shake derives from hit-stop, so the smash also shakes hardest without a second number saying so. |
| `arena_heavy_attack_damage` | `45.0` | Against `20.0`. Scales on the chain step with the same `arena_light_attack_combo_damage_step` — one step field, both attacks. |

**The smash is a chain finisher, and the arithmetic is the constraint.** It occupies the next chain
step like any other hit (capped at the last one), then ends the chain: after a smash there is no
combo window and no buffered follow-up, and the next press starts at step 1. Against
`arena_enemy_max_hp = 120`:

- three lights + smash = `20 + 23 + 26` + `45 × 1.45` = `69 + 65.25` = **`134.25` — kills**
- two lights + smash = `20 + 23` + `45 × 1.30` = `43 + 58.5` = **`101.5` — does not**

So the smash finishes a chain of three, and cannot shortcut one of two. Five lights (`130`) still
kill on their own — the smash's advantage is not raw damage per second but *fewer swings*: each
swing rolls the enemy's dodge and parry once, so a four-hit kill eats two fewer rolls than a
five-hit one. Change any of the four numbers in that arithmetic and the ticket that changes them
owns re-deriving it; `tests/unit/test_arena.gd` asserts both lines.

**Buffering.** A smash pressed during a light lands at that light's link point, exactly like a
buffered light — that is the `0.15–0.25 s` input buffer already carried forward, now covering both
buttons. A light pressed during a smash is dropped rather than queued, because the chain is over
by the time the smash's recovery ends.

#### Super armor — the arena's first protection state

The reference's defensive triad is Invincibility / Super Armor / Forward Guard. The arena already
has the first (dodge i-frames). It takes the second and skips the third.

**During the smash's startup and active window, an enemy hit no longer cancels the swing.** The hit
still lands and still counts against `arena_enemy_hits_to_kill_hero` — super armor removes the
interruption, never the damage, which is the reference's own definition and the reason it is a
trade rather than a defence. The smash's recovery is unarmored.

That is what the `0.30 s` startup is for. Against an enemy wind-up of `0.55 s`, committing to a
smash inside the enemy's telegraph is a real decision with a real price: one of the hero's three
hits, for a guaranteed `65`-damage finisher.

**Forward Guard is not taken.** It needs a facing-cone check, a guard meter, and a break state, and
the arena's parry already occupies the "read the swing and answer it" slot. Two overlapping block
mechanics before either has been felt is how the arena stops being readable.

**Guard break.** A smash ignores `arena_enemy_parry_damage_reduction` outright. The reference's
argument for an absolute counter is that without one, protected states are strictly dominant; here
the smaller version of that problem is that the enemy's parry roll is invisible until after the
swing lands, so a chain can lose `60%` of its damage to something the player could not have read.
The smash is the answer to a parrying enemy. It is *not* an answer to a dodging one — enemy
i-frames still whiff it completely.

#### Back attacks

`arena_back_attack_damage_multiplier = 1.5` applies when the hero is in the enemy's rear 180°,
measured by position against the enemy's facing at the moment of contact — not by swing angle.

The enemy turns at `720°/s` and tracks the hero constantly, so this only pays out where its facing
is *locked*: mid-swing (facing commits when the active window opens), while staggered by a parry,
or in the instant after the hero dodges through it. It is a reward for the three positions the
arena already produces, not a new mechanic asking to be set up.

The reference's value is `+120%`; `1.5×` is deliberately below it. This is a single-target graybox
where the enemy is nearly always facing the hero, so the multiplier's job is to make dodging
*through* better than dodging *away* — not to make positioning the whole fight.

#### The parry window, made visible

Two tints, no HUD. Both reuse the capsule albedo channel that already carries every other combat
state, so this adds no scene nodes and no overlay.

| Tint | When | Reads as |
|---|---|---|
| `ENEMY_TELEGRAPH_COLOR` (`1.0, 0.95, 0.65`) | The final `arena_enemy_telegraph_flash = 0.2 s` of the enemy's wind-up, replacing the orange | "the hit lands in 0.2 s" |
| `PARRY_WINDOW_COLOR` (`0.14, 0.42, 0.55`) | The hero's `arena_parry_active_window` while it is open | "your window is open right now" |

**Why `0.2 s`, and why that is not the same as the parry window.** The flash is a *reaction* cue,
not a "press now" cue — the reference puts it exactly `200 ms` before the active frame for that
reason, which is roughly human reaction latency. A player who reacts to the flash presses at about
the active frame, and the parry window (`0.18 s`, opening instantly on press) then covers the hit.
Pressing *instantly* on the flash is the failure case: that window closes `20 ms` before the swing
connects. The cue rewards reacting, not anticipating, and the two numbers are set against each
other on purpose.

The enemy's remaining `0.35 s` of wind-up keeps the existing orange, so the telegraph now has the
reference's two-stage shape — posture first, flash second — instead of one flat colour for
`0.55 s`.

The hero's window tint is a dim cyan and a successful parry is the existing bright cyan
(`PARRY_HERO_COLOR`), so a correct read reads as the dim colour snapping bright. Super armor gets
no tint of its own: the smash simply continuing through a hit is its own tell, and a fourth colour
on the hero before any of these have been felt is one too many.

> ⚠️ **PROVISIONAL** — the six smash numbers, `1.5×` back attacks and the `0.2 s` flash are all
> first-playable. The softest is `arena_heavy_attack_startup = 0.30 s`: it is set to be *readable
> as a commitment* against a `0.55 s` enemy wind-up, and whether that reads as weighty or as
> sluggish is exactly the thing that just moved the light attack's own startup down. ·
> **Settled by:** playing a fight that uses the smash as a finisher, and specifically checking
> whether trading a hit under super armor feels earned or feels like a mistake the game let you
> make.

**From the reference, not taken:** degraded use-on-cooldown skills (the arena has no cooldown-gated
skills to degrade), the CC point cap and immunity buffer (no CC system — the arena has hit-stun and
stagger, and neither stacks), directional input-combination skills (`W+F`, `S+E` — that is a
skill-bar replacement, and the arena has no skills), grapples, momentum transfer into attack
startup (attacks already stop locomotion by design, `P2b-01c`), and vector-aligned camera shake
(the existing shake is random-offset; aligning it to the strike vector is a real upgrade and a
small one, but it changes a channel that has never been seen at all). **Already in the arena and
credited to the earlier reference, not this one:** hit-stop, input buffering, recovery-frame
truncation and animation cancels, target stagger, three-phase attack anatomy.

---

## Expeditions — *Phase 2*

`ZoneDefinition`: name, recommended power, wave list, loot table, unlock condition.

Up to 5 heroes. Waves resolve in order; **HP carries forward between waves**. A hero reaching
0 HP is **permanently deleted** — applied in exactly one place (see `ARCHITECTURE.md` rule 8).

`hero_power = ATK + DEF + HP/10 + SPD`, summed across the team. Used for UI warnings and
quick-resolve scaling only. **Never a hard gate** — let players throw units away if they want.

### Timed dispatch and repeat orders (`ig-6l4`, 2026-09-22)

A hero can belong to only one active order; equipped gear is committed with that hero. Distinct
teams run concurrently without an energy system or dispatch-slot cap. Presets store stable
hero IDs, a name, and a preferred zone. Missing members remain visible and require an explicit
edit. Preset edits do not modify an already-dispatched team.

Duration uses the existing power calculation and the existing team-size difficulty scale:

```
strength_ratio = team_power / (zone.recommended_power * team_size / 5)
full_team_seconds = max(zone.minimum_duration_seconds,
                        zone.base_duration_seconds / sqrt(strength_ratio))
duration_seconds = ceil(full_team_seconds * 5 / team_size)
```

| Zone | Base seconds at strength ratio 1, five heroes | Minimum, five heroes |
|---|---:|---:|
| Verdant Outskirts | 60 | 15 |
| Ashfall Reaches | 180 | 45 |
| Sundered Vault | 300 | 75 |

The workload factor `5 / team_size` applies after the floor. For equal-strength heroes, five
solo parties have the same aggregate throughput as one full squad, before whole-second rounding.
The existing enemy scaling, reward amounts, and combat formulas are unchanged. This supersedes
the old assumption below that solo play's only extra cost is repeated manual expedition calls.

> ⚠️ **PROVISIONAL** — duration values and first-session pacing are not playtested. **Settled
> by:** a fresh three-pull save reaching its second viable team, followed by a played comparison
> of one geared team and several teams across all three zones. Automated arithmetic is not feel.

Orders request 1–999 total runs, including the first, or unlimited repeats. Unlimited orders
require a conservative forecast that survives every wave's worst-case damage without triggering
the existing between-wave retreat threshold. A past clear is not a safety certificate. Finite
orders may take risks after a clear warning. Every repeat rechecks membership and eligibility;
casualty, defeat, retreat, invalid membership, or a stop request ends the order. Stopping means
finish the current run; there is no immediate recall that bypasses its risk.

Rewards are banked automatically. Reports show outcome, casualties, completed run count, and
per-run/cumulative rewards; the most recent 50 are retained. Reviewing reports never grants
rewards a second time. Already-dispatched runs can finish offline, but only one such run per
order resolves on reopening; the next repeat starts at its full duration while the app is open.
Online timing uses elapsed process time. Negative offline clock differences grant no progress.

### Protected resources and bulk operations (`ig-6l4`)

Favorites, preset members, and away heroes are excluded from sacrifice; equipped fodder also
remains ineligible. Favorite or equipped items are excluded from salvage. Favorites may be
enhanced or equipped because those operations preserve them. Away heroes cannot be equipped,
unequipped, ranked up, sacrificed, used for recovery, or selected for arena practice.

Batch salvage/sacrifice use selected identities and explicit quantities, show exclusions and
exact outputs, and never fill a batch with unselected new arrivals. Enhancement specifies a
target within the Forge cap and a parts budget for each rank. Items are processed in the captured
display order, using existing per-level costs; no rank budget or available balance is exceeded.
Part conversion uses one source rank and a keep-at-least reserve: maximum conversions are
`floor(max(0, source_parts - reserve) / 3)`. It never cascades into another rank automatically.
All destructive/budgeted batches preview and revalidate the same operation before one atomic
commit. No automatic destructive processing is enabled.

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

**A pre-existing spec/code mismatch this ruling surfaced, not caused — now closed by `P2-19`.** The
Sacrifice formula box at the top of this document's "Sacrifice → rank up" section reads
`yield = essence_base[fodder.rank] * (1.0 + fodder.level / level_cap[fodder.rank])` — a
level-scaled essence bonus. `Hero.compute_essence_yield()` had never implemented that term; it
couldn't, since `fodder.level` had no backing field before this ruling. `P2-19` **wired it rather
than striking it**, on the evidence that this document already spends the term: the `~150`-pull
optimistic bound in § Sacrifice → rank up is derived assuming all fodder is max-level, which is
arithmetic that only exists if a max-level fodder yields double. Striking would have invalidated
that bound and needed a fresh ruling; wiring needed no new number.

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

## Turns and recovery time — *Phase 2*

### Current rule (`ig-6l4`, 2026-09-22)

`GameSession.turns` remains a historical count of resolved normal and successful recovery
expeditions. It no longer ages caches. Parallel returns or repeat orders must not spend a
player's recovery window before the player can respond.

Recovery has a persisted active-gameplay clock. It advances only while gameplay is running and
unpaused, never from time while closed. A new lost-gear cache pauses this clock for all caches
until the player reviews the losses and explicitly chooses **Start recovery window**. A later
loss pauses it again; dismissing or truncating an ordinary report cannot unpause it.

Cache lifetime is `900 + 300 * Reliquary level` active seconds: 15 minutes initially, 40 at
level 5. The current building level extends existing caches. A cache remains available at
exactly zero seconds and expires below zero, matching the former strict-boundary behavior.
Recovery damage aging uses elapsed active minutes in place of elapsed expedition turns; its
other coefficients and damaged-item behavior stay unchanged. Legacy elapsed turns convert to
elapsed minutes on migration, with the recovery clock initially paused for existing caches.

> ⚠️ **PROVISIONAL** — the 15–40-minute recovery window preserves the old numerical scale,
> but has not been tested for rebuilding after a timed-expedition wipe. **Settled by:** a played
> recovery scenario at low and high Reliquary levels with a surviving weak roster.

### Historical expedition-turn rationale (superseded)

The following analysis records the original instant-expedition design. Its turn-based deadlines
and rejected-clock argument are historical, not current behavior; the rule above supersedes
them because timed parallel expeditions change the unit of player opportunity.

`P2-22`. Rules the gap `P2-04f` and `P2-13` are both blocked on, and that four already-authored
numbers are denominated in with nothing to count: cache expiry (`15 turns`),
`reliquary_decay_turns_bonus` (`+5`/level, `balance_table.gd:30`), `damage_chance`'s
`0.03 * turns_elapsed` term, and `LostCache.turn_lost` — a field `P2-04e` deliberately refused to
ship because there was no counter to stamp it from.

**Ruling: a turn is one resolved expedition.**

The counter advances by one when `Expedition.resolve()` returns `COMPLETED`, `RETREATED`, or
`DEFEATED`. `OUTCOME_INVALID_TEAM` returns before the first wave and does **not** tick — nothing
happened. A recovery expedition (`P2-04f`) is an expedition and ticks like any other. The counter
is `GameSession.turns`, a persisted profile field alongside `stones` and `essence`; it only ever
increases and is never reset.

`LostCache.turn_lost` is stamped with the counter's value at the moment of death, and
`turns_elapsed = GameSession.turns - cache.turn_lost`. A cache's deadline is **evaluated at the
recovery attempt, not frozen at death** — `turn_lost + 15 + 5 * reliquary_level` — so upgrading the
Reliquary extends caches that already exist. That is one stored field instead of two, and the
player-favourable reading of the two available; a building that fails to protect the gear you
bought it for reads as a bug.

Why an expedition and not something else:

- **It is the only action in the game that can kill a hero**, and a death is the only thing that
  creates the caches this clock measures. Any denominator that can advance with no possibility of
  a death makes decay a tax on playing rather than a consequence of dying.
- **It makes this document's own claim literally true.** Death and gear recovery below says "you
  choose between pushing progression and mounting a salvage run." That is only a choice if both
  spend the same unit. They do: a recovery run *is* an expedition, so fetching one cache costs
  exactly one progression attempt, and fetching three costs three — with the third cache two turns
  older than when you started.

**Rejected: wall-clock time.** Needs a timestamp in the save, runs the clock while the game is
closed, and is settable from the OS. It also imposes a real-world deadline in a game with no idle
income to justify one — the whole point of `Expedition.resolve()` being synchronous.

**Rejected: one hub action** (equip, salvage, upgrade, convert). Ages a cache for sorting your bag.
The clock would measure UI traffic.

**Rejected: one play session or boot.** Nothing counts sessions — the gap named at the foot of
`docs/TASKS.md` — and it hands the player a trivial exploit: never quit, never decay.

### What the authored decay numbers mean once turns are expeditions

The check that matters is whether `15` is a window a player can actually miss, because a clock
nobody can run out is `reliquary_decay_turns_bonus` joining `LostCache.turn_lost`,
`Item.enhance_level` and the flat Forge reading in this document's list of numbers that read real
and measure nothing.

It is missable, and the reason is structural rather than tuned. A recovery needs
`team_power >= zone.power * 0.5`, and the deaths that create caches worth fetching are the ones
that wipe the squad capable of that. Rebuilding takes `~33.6` Verdant attempts to climb one fresh
hero to F's cap (Expeditions § Hero leveling), `~19.5` with the Training Hall maxed — both longer
than `15`. So an un-Reliquaried player who loses their only capable team loses the cache with it,
and the building is what buys it back:

| Reliquary level | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Cache lifetime (turns) | 15 | 20 | 25 | 30 | 35 | 40 |
| Covers a bare rebuild (`~33.6`) | no | no | no | no | marginal | **yes** |
| Covers a Training-Hall-5 rebuild (`~19.5`) | no | **yes** | yes | yes | yes | yes |

Two buildings reading one clock from opposite ends is worth keeping: the Training Hall shortens the
rebuild, the Reliquary lengthens the window, and either alone gets a player over the line the other
does not.

Against the `~1,308`-clear Verdant spine to a manufactured SSS (Summoning § Summon Stones), `15`
turns is `1.1%` of the run — a deadline inside a session, not a project.

> ⚠️ **PROVISIONAL** — that `15` (and `40` at cap) is the *right* window. The unit is not
> provisional; the count against it is unplayed, and an expedition is one button press with an
> instant result, so 15 of them may read as a formality rather than a deadline at the keyboard even
> though the rebuild arithmetic above says otherwise. · **Settled by:** a played build in which a
> squad wipe in Ashfall or Sundered leaves a cache the surviving roster cannot reach.

**Residue for `P2-04f`, not ruled here.** At Reliquary 4 and 5 the extended window outruns the
`clampf` on `damage_chance`: solving `0.15 + 0.03 * turns_elapsed - 0.03 * reliquary_level >= 1.0`
at `power_deficit_penalty = 0` gives certain damage from turn `33` at level 4 (lifetime `35`) and
from turn `34` at level 5 (lifetime `40`). So the last 3 and 7 turns of those two windows return
Damaged gear with a perfect team and no way to avoid it. This is the same shape as the
zero-cancellation `P2-07a` flagged and did not own — sound as arithmetic, open as design.
`P2-04f` owns the damage roll and should rule on it rather than discover it.

> ⚠️ **RESOLVED by `P2-04f`.** Both residues are accepted as intended; the formula is unchanged.
> Recomputed exactly (Codex thread `019fe03d-ec7d-72a3-aef5-1025b6311b73`): at Reliquary 5,
> `turns_elapsed = 0`, a perfect team, `damage_chance` is precisely `0`; certain damage begins at
> turn `33` (Reliquary 4) and turn `34` (Reliquary 5), matching the figures above exactly.
>
> The same-turn-zero-risk case needs exact rank-5 investment *and* noticing a death and running
> the recovery before doing anything else — it rewards the single fastest possible response, not a
> standing free pass; any turn spent elsewhere first reintroduces `0.03 * turns_elapsed` and starts
> eating the margin back. The certain-damage tail is the mirror case: a Reliquary at that level
> already bought `20`–`25` turns beyond the un-upgraded `15`, and a deadline whose last few turns
> read as genuinely deadline-like is the point of a deadline, not a bug in one. Neither residue is
> reopened on its own, because both are downstream of the level-5 cap chosen for the opposite
> reason in Base buildings (`0.03 * 5` cancelling `0.15` cleanly, below) — reopening either residue
> here would reopen that cap choice too, on no stronger evidence than justified it the first time.
>
> ~~The practical stake is zero today regardless: the Reliquary has no upgrade path in the running
> game (`hub/hub.tscn` offers buildings 0–3 only; `building_levels[4]` is fixed at `0`). This
> callout settles the formula so a future ticket making the Reliquary buildable needs no further
> design pass — it isn't settling something currently reachable in play.~~
>
> **That whole paragraph expired with `P2-24`**, which is the ticket it anticipated: the Buildings
> panel now offers index 4, so both residues are reachable in play and this callout is doing the
> work it was written for rather than deferring it. Nothing above is reopened — the ruling was
> made on the arithmetic and the cap-5 dependency, neither of which a buildable Reliquary
> changes. What *did* change is that "sound as arithmetic, open as design" is no longer answerable
> at a desk on either residue.
>
> ⚠️ **PROVISIONAL** — whether a maxed Reliquary's risk-free same-turn recovery reads as a
> *reward for a fast response* or as *the mechanic switching off* is a feel question, and it is
> now askable for the first time. The arithmetic is not in question and neither is the cap.
> **Settled by:** a played build in which a wipe strands a cache with the Reliquary at 4 or 5.

---

## Death and gear recovery — *Phase 2*

A dead hero's equipment does not vanish:

```
LostCache { hero_name, zone_id, items[], recovery_created_at }
```

**Recovery expeditions** are a distinct mission type targeting one cache. Required power is
`zone.power * 0.5` — deliberately low, so a weak B-team can go fetch a dead SSS hero's gear.
**That is the point of the system**, not an oversight.

Retrieved items may come back **Damaged**:

```
r = zone.power / team_power                              # same r convention as Wave damage, above
power_deficit_penalty = clamp(0.2 * (r - 1), 0.0, 0.2)
recovery_minutes_elapsed = (recovery_clock_seconds - recovery_created_at) / 60
damage_chance = clamp(0.15 + 0.03 * recovery_minutes_elapsed
                      - 0.03 * reliquary_level + power_deficit_penalty, 0.0, 1.0)
```

**Ruling (`P2-04f`): Damaged means `enhance_level` halved (rounded down) if the item carries any;
an item already at `+0` drops one rank instead, clamped at `F`. An `F`-rank item already at `+0`
returns intact.**

```
if item.enhance_level > 0:
    item.enhance_level = floori(item.enhance_level / 2.0)   # unchanged from the original clause
elif item.rank > 0:
    item.rank -= 1                                          # replaces "one affix rolled down"
# else: F-rank, +0 — returns intact, see the boundary paragraph below
```

Two of the original clause's three parts named systems that don't exist in this codebase and
aren't scheduled. `Item` (`equipment/item.gd:10-12`) is exactly `def_id`, `rank`, `enhance_level`
— no affix data to roll down, no socket to hold a Core. **Cores are struck from this clause**, the
way gold was struck from Enhancement's cost line: not deferred, removed. This document already
tags Cores `*Phase 4*` on their own heading (Equipment, above), so a Phase-2 recovery roll naming
them was always describing a system four phases away — struck rather than left to read real and
resolve to nothing. **Affixes are replaced with rank**, not struck outright: `equipment_affix_counts`
(`balance_table.gd:6`) is rank-indexed, so in this codebase's own terms an affix drop already *is*
a rank drop — reading `item.rank` needs no new field, no new roll table, and no new system, only
data every `Item` already carries. This follows a precedent already set on this exact array rather
than reopening it: `P2-05b` (`docs/TASKS-DONE.md:1741-1742`) — "affixes and Cores do not exist. Do
not let the affix column pull this ruling into inventing one."

Checked before ruling (Codex thread `019fe03d-ec7d-72a3-aef5-1025b6311b73`): the magnitude
concern raised against this option is real, and bounded. `equip_pct_per_rank`'s seven rank-down
steps each cost `25.82%–26.02%` of that item's own stat contribution (not exactly geometric — the
authored decimals carry rounding — but tight around `~25.9%`; `SSS→SS` specifically checks at
`25.95%`). Enhancement-halving's cost varies by starting level and is usually *smaller*: `7.41%`
at `+1`, climbing unevenly to `29.09%` only at `+15`. The two don't converge until `+13`
(`27.45%`, the first level at which halving costs more than a rank drop) — below that, a rank drop
is the harsher outcome across most of the enhance range. Ruled anyway, for three reasons:

1. **A `+0` item has zero enhancement investment to lose.** The mechanic exists to make death cost
   something recoverable-but-diminished; an item with nothing enhanced has nothing on that axis to
   take, so the axis has to change or the roll stays inert on this branch — the exact problem this
   ruling exists to fix, not a reason to leave it unfixed.
2. **The fair comparison is the top of the enhance range, not the bottom.** A `+1` item losing
   `7.41%` describes a barely-invested item; a `+13`–`+15` item losing `27–29%` describes a
   heavily-invested one, closer to what a rank-carrying `+0` item actually represents — full rank
   investment (the player chose to equip and carry this rank) paired with zero enhancement
   investment. Read against the top of the range, `~26%` sits inside the band the existing
   mechanic already produces at its own high end, not above it.
3. **It stays inside data the game already has.** No new roll, no new array, no new save field —
   `item.rank -= 1` reuses the same integer `Item.from_dict` already round-trips.

**The `F`-rank, `+0` boundary returns the item intact.** This is a narrower dead case than the one
it replaces — every `+0` item at rank `D` or above now drops a rank, and every item carrying any
`enhance_level` still halves — and it is the correct floor rather than a gap: `F`/`+0` is already
the least-invested item state the game can produce (base rank, zero enhancement), and "Damaged"
cannot mean less than nothing. The alternative was destroying it outright (rejected below).

> ⚠️ **PROVISIONAL** — the rank-drop magnitude (`~26%`, checked above) is arithmetically sized
> against the existing enhancement-halving mechanic, not played. Whether losing a full rank on a
> `+0` item reads as "a death costs something" or "recovery isn't worth it," the same tension the
> `damage_chance` PROVISIONAL above already names, is unfelt. **Settled by:** a played recovery run
> that actually rolls the `+0` branch, ideally on a rank-A-or-higher item so the drop is visible
> against a real rank-name change.

**Rejected: `+0` items return intact (no branch at all).** The status quo this ruling replaces.
Honest, but concedes `damage_chance` decides nothing for the commonest case in the game — every
fresh drop and every un-enhanced equip is `+0` until a built Forge and spent parts change that —
which would make this the sixth "reads real, measures nothing" number this document has caught
(`LostCache.turn_lost`, `Item.enhance_level`, the flat Forge salvage reading,
`reliquary_decay_turns_bonus`, `P2-19`'s fodder-level integer division).

**Rejected: destroy `+0` items outright** instead of rank-dropping them. Considered both
generally and for the `F`/`+0` boundary specifically. Rejected generally because it's
disproportionate at the top of the rank table: the recovery system's own stated point two
paragraphs up is that "a weak B-team can go fetch a dead SSS hero's gear" — deleting an SSS drop
outright on one unlucky roll contradicts a system built to make that gear *recoverable*, not to
stack a second, harsher death roll on top of the first. Rejected at the `F`/`+0` boundary for
consistency: nothing else in this ruling destroys an item, and a destroy branch for exactly one
corner case — when "returns intact" already covers it without inventing a new outcome type — is
the larger diff for no gain.

**Rejected: invent an affix system to make the original clause literal.** Affixes are an
unauthored system with no `Item` field, no roll table, and no ticket behind them; building one to
satisfy a single clause in a recovery ruling is the scope change `CLAUDE.md` requires flagging
explicitly, not a balance tweak, and `P2-05b` already declined this exact invitation once.

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

Caches **expire after 15 active recovery minutes** (+5 per Reliquary level), an expired cache
taking its items with it. New losses pause this clock until reviewed. Expedition count and
offline time no longer age gear; see the current rule under Turns and recovery time above.
Earlier turn-denominated arithmetic in this section is historical: substitute active minutes
for its old turn unit; damaged-item effects, power penalty, and Reliquary reduction are retained.

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
| Forge | Enhance cap `level * 3` (max 15; past 12 only with a master smith home, § Keepers and professions); salvage yield +10% | 2 (arguably 3: rate, cap, ceiling) | forge |
| Training Hall | Post-expedition XP +15% | 1 | expedition |
| Sanctum | Sacrifice essence yield +10% | 1 | sacrifice |
| Reliquary | Cache lifetime +5 active recovery minutes; recovery damage chance −3% | 2 | recovery |

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
- **Reliquary** read against two things neither of which existed: the recovery-expedition damage
  roll (`P2-04f`, then blocked on `power_deficit_penalty`) and a "turn" concept at all (also
  `P2-04f`, and the decay clock is turn-denominated). Same outcome — parts spent here are inert
  until `P2-04f` unblocks and ships. **Both design gaps are now closed** — `power_deficit_penalty`
  is `clamp(0.2 * (r - 1), 0.0, 0.2)` (Death and gear recovery) and a turn is one resolved
  expedition (Turns) — so the block is on `P2-04f`'s *code* landing, not on a further ruling.
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
only when a building needs to express something an integer can't. *(2026-09-23: this still holds
for hall upgrades, which stay instant. Since `ig-6m2.4`, a hall upgrade also costs wood and stone,
and placed town buildings take time to go up. Both are in § Town builder.)*

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

### Keepers and professions (`ig-wgj`, 2026-09-23)

The design is in `GAME_SPEC.md` § Heroes staff the buildings. These are its numbers. They become
`balance.tres` rows (rule 9), not constants in code.

**Skill.** Every hero has an XP total per profession, counted in seconds. XP turns into a skill
level from 0 to 5. The scale is the same for every hero and every profession (owner ruling,
2026-09-23: born + practice, no cap below 5). Level `k` costs `20 * k` minutes of XP:

| Level | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| XP minutes for this level | 20 | 40 | 60 | 80 | 100 |
| Total XP minutes | 20 | 60 | 120 | 200 | 300 |

**Passions (owner ruling, 2026-09-23: "I like the rimworld inspired multi passion idea").** Every
hero is born with `passions_per_hero = 2` different professions out of the eight, picked uniformly.
This replaces the single calling out of five. Two is the smallest count that keeps a Rites passion
at least as common as the old calling:

| Passions from 8 | Chance a new hero has Rites | Pulls to find one, on average |
|---|---|---|
| Old rule: 1 calling from 5 | 20% | 5 |
| 1 from 8 | 12.5% | 8 |
| **2 from 8 (ruled)** | **25%** | **4** |
| 3 from 8 | 37.5% | 2.7 |

Three would make a passion ordinary: a hero would be passionate about three of eight jobs.

**XP.** Only a hero working its job while home earns XP, and only in that job's profession:

```
xp_seconds += work_seconds * (passion_xp_multiplier if profession in hero.passions else 1.0)
passion_xp_multiplier = 4.0
```

| Real minutes of work to reach skill | 1 | 3 | 5 |
|---|---|---|---|
| In one of its passions (×4) | 5 | 30 | 75 |
| Any other profession (×1) | 20 | 120 | 300 |

×4 is the owner's "immense XP boost". It sits close to a RimWorld major passion against no passion
(1.5 / 0.35 ≈ 4.3).

XP builds up on the live tick, the same pass that ages the recovery clock
(`GameSession._advance_clocks_in_memory`). It never builds up in the catch-up that resolves orders
after the game was closed. XP persists the same way `recovery_clock_seconds` does.

**Masterwork.** A hero is a master of a profession when that profession is one of its passions
*and* its skill there is 5. A hero can master both of its passions. A building's masterwork tier is open only while its keeper is home and is a master
of the building's profession.

- **Forge.** This amends the Forge row of § Base buildings:

  ```
  enhance_cap = min(forge_enhance_cap_per_level * forge_level,
                    forge_enhance_cap_max if master_smith_home else forge_masterwork_floor)
  forge_masterwork_floor = 12
  ```

  Only `Item.compute_enhance_cap` changes. `Item.clamped_enhance_level`, the clamp that decides how
  far a saved level is trusted, stays at 15. So gear already at +13 to +15 keeps its level, and
  bulk enhance obeys the same cap. Without a master, the enhanced share of an item tops out at
  `1 + 0.08 * 12 = ×1.96` instead of `×2.2`. That only widens the margin under the 75% `CRIT_RATE`
  cap (§ Enhancement), so nothing needs a re-check.
- **Apothecary.** Built now, on the owner's ruling of 2026-09-23 (`ig-wgj.11`). The save and
  battle rules are in `DECISIONS.md` 2026-09-23, masterwork draughts. These numbers are unplayed:

  | Draught | Regular | Masterwork |
  |---|---|---|
  | Healing | 40% max HP · 5 F parts | 60% max HP · 15 F parts |
  | Revival | 35% max HP · 15 F parts | 50% max HP · 45 F parts |

  The Alchemy discount applies to both tiers. Masterwork draughts are separate stocks with separate
  per-run allocations. Auto-use spends the regular draught first, and a masterwork one only when
  that run's regular stock of the same kind is gone. Manual use can pick either.
- **Rites** (owner ruling, 2026-09-23, against the designer's and the director's advice).
  `rank_up_hero` refuses SS→SSS unless the Sanctum's keeper is home and is a master priest
  (a Rites passion, skill 5). Every other rank-up is unchanged. Heroes already at SSS keep their rank.
  The target may be the priest itself: it is stationed and home.
- **Drill, Tracking.** No masterwork. Skill bonus only.

**The Rites gate against the spine.** It adds no Essence cost. It adds a condition on when you can
finish.

- **Essence.** You keep one Rites-born hero instead of feeding it. At the average of 78.38 Essence
  per pull, that costs at most about one pull; an F-rank priest costs 10 Essence, about 0.13 pull.
  The figures below become ~327 → ~328, ~219 → ~220 and ~188 → ~189. The ~188 case already has a
  skill-5 Rites keeper, so a Rites-born one meets the gate for free.
- **Finding a Rites-born hero.** Passions are uniform, whatever the rank. With two passions from
  eight, each new hero has a 1 in 4 chance of a Rites passion (it was 1 in 5 under the old single
  calling). The chance of at least one in `n` new heroes is `1 − 0.75^n`:

  | New heroes | 4 | 8 | 11 | 16 |
  |---|---|---|---|---|
  | At least one Rites-born | 68% | 90% | 96% | 99% |

  That is 4 pulls on average: 400 stones, or about 16 Verdant, 5.3 Ashfall or 2 Sundered clears at
  § Summon Stones' income (1,308 / 436 / 164 clears per ~327 pulls). Pulls are always possible:
  expeditions pay stones, and § Roster-wipe recovery floor covers an empty roster. A lost priest is
  a delay, never a dead end.
- **Time.** A Rites-born keeper reaches master after 75 minutes of live play at the Sanctum
  (300 XP-minutes at ×4). The training runs alongside the grind. The ~219-pull grind is about 110
  Sundered clears: roughly 9 hours of one squad's timers at base duration, or 2.3 hours at the 75 s
  floor. So a priest stationed early is ready long before the final rank-up, and the gate costs no
  time.
- **Worst case.** You lose your only master at SS and no Rites-born hero is left on the roster. The
  wait is about 4 pulls plus 75 minutes of live play.

**Bonus.** Each skill level is worth half a building level of that building's own effect. It is
added inside the building's existing term:

```
effect = 1.0 + per_level_bonus * (building_level + 0.5 * keeper_skill)
```

| Profession | Building | Per skill level | At skill 5 | Term it joins |
|---|---|---|---|---|
| Smithing | Forge | Salvage yield +5% | +25% | `forge_salvage_yield_bonus` 0.10/level |
| Rites | Sanctum | Essence yield +5% | +25% | `sanctum_essence_yield_bonus` 0.10/level |
| Drill | Training Hall | Expedition XP +7.5% | +37.5% | `training_hall_xp_bonus` 0.15/level |
| Tracking | Reliquary | Cache and rescue lifetime +150 s | +750 s | `recovery_duration_seconds_per_level` 300 s/level |
| Alchemy | Apothecary | Draught parts cost −10% | −50% | none: the Apothecary has no level |

**Tracking never shortens a window** (director ruling, 2026-09-24, `ig-wgj.10`). A Tracking keeper
can lengthen a running rescue window or cache lifetime, and the time stays when the keeper leaves,
dies or is unstationed: each one keeps the longest lifetime it has had. Otherwise sending the
Tracker out would cut every running window by up to 750 s, and could expire an incident at once,
killing its stranded heroes from an unrelated click.

**Workers (town builder, `ig-6m2`).** Woodcutting, mining and farming are professions too, so a
worker earns XP in its job like a keeper, with the same ×4 for a passion. A workplace has no level,
so a worker's skill is a flat multiplier on its own output:

```
worker_output_per_minute = base_rate * (1.0 + worker_skill_bonus_per_level * worker_skill)
worker_skill_bonus_per_level = 0.10      # skill 5 = x1.5
```

> ⚠️ **PROVISIONAL** — `worker_skill_bonus_per_level` is unfelt · **Settled by:** a played build
> of the worker job-skills slice.

A skill-5 keeper is worth 2.5 building levels, and a skill-3 keeper 1.5. A keeper stacks past the
building cap on purpose: a maxed Forge with a skill-5 smith reads as level 7.5 for salvage.

Alchemy's cost is `max(1, roundi(base * (1 - 0.10 * skill)))`:

| Skill | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Healing (base 5 F parts) | 5 | 5 | 4 | 4 | 3 | 3 |
| Revival (base 15 F parts) | 15 | 14 | 12 | 11 | 9 | 8 |

For healing, skills 1 and 3 change nothing over the level below. That is the zero-effect level
the Forge section already warns about. It is accepted here because draughts are cheap either way.

**What a keeper never touches.** Three magnitudes are pinned by other rulings, so keepers stay
off them:

- Summon weights, because they wear down the ~12× manufacture floor. That is why the Circle has
  no keeper.
- The Forge enhance cap, because it is tied to `enhance_level` 0–15. A keeper never raises it.
  Masterwork only decides who may use the band from +13 to +15.
- The Reliquary damage-chance term, because it cancels exactly at level 5. More would go negative.

**Checked against the spine.** Rites makes Essence cheaper, so it only widens the manufacture
advantage. It cannot break the ≥12× floor in `GAME_SPEC.md` § Win and loss. It does lower the pull
count. With the ~327 pulls from § Sacrifice (324.5 of feeding plus ~2.5 to land the keeper), a
level-5 Sanctum (×1.5) brings it to ~219, and a skill-5 Rites keeper on top (×1.75) to ~188. Both
figures are before Circle effects and before levelling fodder.

> ⚠️ **PROVISIONAL** — the Rites gate's time cost. "It costs no time if a priest is stationed
> early" rests on the grind taking hours of live play, and nothing in this codebase measures
> session length. A player with several strong squads farming Sundered at the floor could run the
> last ~110 clears in under 75 minutes, and then the gate is a real wait. · **Settled by:** a played
> build that reaches SS→SSS, timing the live play from the first stationed priest to the rank-up.

> ⚠️ **PROVISIONAL** — every number in this section is unfelt: the 20-minute level, the ×4 passion
> multiplier, the +12 masterwork floor, the half-level bonus, Alchemy's 10% and the masterwork
> draughts. The ~219, ~188 and Rites-gate figures are single-pass arithmetic and have not been
> cross-checked. · **Settled by:** a played build with two or more
> keepers working for a real session, measuring how many minutes of work a session actually
> yields; the pull figures, by a Codex arithmetic check against § Sacrifice.

---

## Town builder — *ig-6m2, accepted 2026-09-23*

Design: `GAME_SPEC.md` § The town builder. Boundaries: `DECISIONS.md` 2026-09-23, the town builder.
Every row below is a `balance.tres` row.

> ⚠️ **PROVISIONAL** — every number in this section is a desk guess. None has been played.
> · **Settled by:** a played build of the first slice (`ig-6m2.1`), measuring how long it takes to
> house and employ five heroes.

### First slice: wood, houses and the Lumbermill

| Row | Value | Why |
|---|---|---|
| `town_map_radius` | 8 hexes (217 hexes) | Room for the 7 halls, about 30 houses and a dozen workplaces |
| `town_start_wood` | 40 | Enough for one Lumbermill and two Houses. Old saves get it once, when the key is missing |
| `house_wood_cost` | 10 | |
| `house_capacity` | 1 | The owner: each hero has its own house |
| `lumbermill_wood_cost` | 20 | |
| `lumbermill_worker_slots` | 2 | |
| `wood_per_worker_minute` | 1.0 | Live play only, and only while the worker is home |

**Pacing check.** The start stock builds one Lumbermill and two Houses, leaving 0. Two workers make
2 wood a minute, so a new House every 5 minutes. A second Lumbermill and its two Houses cost 40,
which is 20 minutes. After that, 4 wood a minute. Housing is bounded by the roster, so this
stops when you run out of heroes worth keeping.

### The first of each producer is free

**A producer type you have none of costs nothing.** The producers are the Lumbermill, the Mine and
the Farm. A House counts too: a worker needs one, so producers with no House make nothing
(deadlock check, 2026-09-24, `ig-6m2.3`). A building still under construction counts as having
one, so only one of each type can be free at a time. The second one costs full price.

It is a restart rule. Without it, a player who spends the starting wood on Houses before placing a
Lumbermill can never make wood again. The mirror case locks too: a free Lumbermill and two more at
20 spend all 40, and nobody can work them without a House. So does a starving town with no wood
and no Farm. Nothing can be demolished, so there would be no way back. With the rule, a town can
never lock itself out. The price is one free building per type, once.

The start stock of 40 now buys five Houses (the first is free), or a second Lumbermill and three
Houses.

### Moving a building (`ig-6m2.2`)

Any building, the seven halls included, can move to a free hex. It keeps its id, so its keeper,
workers, residents and level go with it.

> ⚠️ **PROVISIONAL** — moving is free in this slice: no wood, no cooldown, no build time.
> · **Settled by:** the owner playing with movable halls. If free moves feel cheap, a price comes
> with its own ruling.

### What the town costs the spine

**The town makes no Summon Stones, Essence or parts.** No income number in § Summon Stones moves,
and neither does ~327 → ~219 → ~188 in § Keepers and professions.

The only cost is the heroes you keep as workers instead of sacrificing them. At the average of
78.38 Essence per pull:

| Worker's rank | F | D | C |
|---|---|---|---|
| Essence not fed | 10 | 25 | 65 |
| Pulls this costs | 0.13 | 0.32 | 0.83 |

Ten F-rank workers cost about 1.3 pulls: ~327 → ~328. F is 40% of pulls, so a player who staffs
the town with F-rank heroes pays almost nothing. A player who keeps better heroes as workers pays
more. That is a choice, not a trap.

### Food and starvation (`ig-6m2.5`, owner ruling 2026-09-23)

Design: `GAME_SPEC.md` § Heroes eat, and can starve to death.

| Row | Value | Why |
|---|---|---|
| `town_start_food` | 30 | Five housed heroes eat it in 30 minutes. Old saves get it once, when the key is missing |
| `food_per_housed_hero_minute` | 0.2 | One farmer feeds five |
| `farm_wood_cost` | 20 | Same as a Lumbermill |
| `farm_worker_slots` | 2 | |
| `food_per_worker_minute` | 1.0 | Live play only, and only while the worker is home |
| `food_low_warning_minutes` | 10 | "Food low" shows when food < 10 minutes of the current eating |
| `starving_work_multiplier` | 0.5 | Every workplace, farms included, while starving |
| `starve_first_death_minutes` | 20 | Minutes of starving before the first death |
| `starve_next_death_minutes` | 10 | Minutes between later deaths |
| `starve_last_warning_minutes` | 5 | The death clock stops this long before each death until the player acknowledges |

**Who eats.** Housed heroes who are home. A hero away on an expedition or busy in a battle does
not eat. Unhoused heroes (fighters, fodder, hall keepers without a house) never eat.

**One clock, per live tick.** Food and the clock move only in `_advance_clocks_in_memory`, never in
the catch-up that resolves orders after the game was closed.

```
food += production(dt)            # halved while starving
food -= eaters * food_per_housed_hero_minute * dt_minutes
if food < 0:                      # demand not met: starving
    food = 0
    town_starving_seconds += dt   # unless stopped at a last warning
elif food >= food_low_warning_minutes * current_eating_per_minute:
    town_starving_seconds = 0     # out of the ladder: start over
# otherwise (0 < food < the food-low line) the clock holds
```

The reset needs food back above the food-low line, not just above 0. Otherwise a farm making less
than the town eats would tick food above 0 each tick, reset the clock forever, and nobody would
ever starve.

**Starving** means the clock is above 0. It starts the first time demand goes unmet and ends only
at the reset, so work does not flicker between half and full speed (tech-lead, 2026-09-24,
`ig-6m2.5`).

**Deaths.** Death `n` (from 1) is due at `starve_first_death_minutes + (n - 1) *
starve_next_death_minutes` of starving: 20, 30, 40 minutes. At `due - starve_last_warning_minutes`
(15, 25, 35) the clock stops and the HUD asks the player to look. It runs again only after they
acknowledge. The victim is the eater with the lowest rank, then the lowest level, then the newest
in the roster. Its gear goes to inventory, then `GameSession.kill_hero()` removes it, so no Lost
Cache appears. Saved: `town_resources.food`, `town_starving_seconds`, and whether the current
warning was acknowledged.

**Pacing check.** Five housed heroes and no farm: food low at 20 minutes, starving at 30, the
first last warning at 45, and the first death at 50, but only if the player acknowledged that
warning and still did nothing. The first Farm is free (§ The first of each producer is free).
Later ones cost 20 wood, which is 10 minutes of two woodcutters. With production at half
speed while starving, the way out is to unhouse heroes until the farms outrun the eating; one
starving farmer at 0.5 food a minute still feeds two.

**Starving and skill.** Starving halves the final rate, after the worker skill bonus
(`ig-6m2.7`): `base * (1 + worker_skill_bonus_per_level * skill) * starving_work_multiplier`.

**Food does not make draughts (v1).** Draughts keep their F-parts cost (§ Supplies and automation,
and the draught table in § Keepers and professions). There are four reasons:

1. Starvation already kills heroes. If food also paid for draughts, a hungry town would cut the
   revival draughts that save downed heroes, and the two ways to die would feed each other.
2. Every player would need a staffed Farm before they could brew a single draught.
3. Hall upgrades are the town's link to the hero game (below). One link is enough for v1.
4. `ig-wgj.10` and `ig-wgj.11` build on F-parts costs, so nothing has to be reworked.

Food above what the town eats is a buffer: the eating goes up whenever heroes come home.

> ⚠️ **PROVISIONAL** — every row above is unfelt · **Settled by:** a played build of `ig-6m2.5`.
> If farms beyond the minimum feel pointless, a new bead can give food a second use.

### Stone and construction (`ig-6m2.3`)

| Row | Value | Why |
|---|---|---|
| `mine_wood_cost` | 20 | Same as a Lumbermill. No producer costs stone |
| `mine_worker_slots` | 2 | |
| `stone_per_worker_minute` | 0.5 | Stone is the slow resource. One full Mine makes 1 a minute |
| `house_build_seconds` | 60 | Live play only |
| `workplace_build_seconds` | 120 | The Lumbermill, Mine and Farm. Live play only |

**One resource, one job.** Wood builds houses and workplaces. Stone pays for hall upgrades (below).
Food feeds the town. Houses and workplaces cost wood only.

This replaces the slice's first scope, where houses and workplaces cost stone too. The problem was
a loop: a House that costs stone needs a Mine first, and the Mine's workers need Houses. A fresh
town would need a start stock of stone just to begin. There is no `town_start_stone`.

**Deadlock check** (2026-09-24). Stone cannot lock the town: no building costs stone, and stone
buys only hall upgrades. The first Mine is free, and its workers' Houses are paid in wood, which
§ The first of each producer is free keeps coming. Construction cannot lock it either. It needs no
input, only live play time, so the worst case is waiting for a free producer to finish.

**Construction.**
- A new building shows `building_scaffolding`, then `building_stage_A`, `_B` and `_C`, each for a
  quarter of its build time. Then it shows its own model.
- It does nothing until it is finished. It takes no resident and no worker, and assigning one is
  refused with a reason.
- Its hex is taken. It can be moved, and it keeps its progress when it is.
- Build time moves only on the live tick.
- It is saved as `build_remaining` seconds on the building. A missing key means finished, so every
  older building loads finished.
- The seven halls are never under construction, and a hall upgrade stays instant. § Upgrade cost's
  "no timers" still holds for halls.

**One meaning per model.** `building_scaffolding` and `building_stage_A/B/C` mean "under
construction" and nothing else. `building_destroyed` means "a hall at level 0". `ig-wgj.6`'s
level mapping uses no stage model; its new mapping is in that bead.

### Hall upgrades cost wood and stone (`ig-6m2.4`)

| Row | Value | Cost of level `n -> n+1` |
|---|---|---|
| `hall_upgrade_wood_per_level` | 20 | `20 * (n + 1)` wood |
| `hall_upgrade_stone_per_level` | 10 | `10 * (n + 1)` stone |

`n` is the current level, as in § Upgrade cost. The parts cost does not change.

| Level | 0→1 | 1→2 | 2→3 | 3→4 | 4→5 | Total |
|---|---|---|---|---|---|---|
| Parts (unchanged) | 20 F | 30 D | 40 C | 50 B | 60 A | |
| Wood | 20 | 40 | 60 | 80 | 100 | 300 |
| Stone | 10 | 20 | 30 | 40 | 50 | 150 |

**The parts cost stays.** It is set against the spine: 264 clears to max one hall (§ Upgrade cost).
Cutting it would make hall power a town reward and move the spine. The town adds a gate. It does
not replace the parts.

**Pacing check.** Take a modest town: 2 Lumbermills and 1 Mine with 6 workers, making 4 wood and
1 stone a minute. It pays for 0→1 in 10 minutes of stone and for 4→5 in 50. The parts for the same
levels take 14 and 140 clears. For anyone who keeps a small town going, the town cost is never the
long pole. A player with no Mine cannot upgrade a hall at all. That is the point: the town feeds
the hero game.

- It applies to the five halls that have levels: Circle, Forge, Training Hall, Sanctum and
  Reliquary. The Apothecary and the Town Gate have none.
- Levels already reached stay. Nothing is refunded or charged again.
- The preview shows all three costs. A refusal names every resource that is short, and a refused
  upgrade spends nothing.

> ⚠️ **PROVISIONAL** — stone, construction and hall-upgrade numbers are desk guesses · **Settled
> by:** played builds of `ig-6m2.3` and `ig-6m2.4`.

---

## Save — *Phase 2*

`GameSession` → `Dictionary` → `JSON.stringify` → `user://save.json`. Written only by
`SaveService`.

Human-readable and diffable, which matters enormously when a balance change corrupts
progression and you need to see what actually happened.

**Current schema: 3 (`ig-544`).** Schema 2 introduced stable hero/item identities, team presets,
dispatch orders, reports, and the active recovery clock. Schema 3 adds persistent battle state,
supply allocations, and stranded incidents; the autonomous combat section above defines migration.
Future versions, malformed JSON, and invalid saved state block play and writes while preserving
the canonical file's bytes. A missing file is the fresh-game case. The historical refusal
analysis below describes the earlier version-1 behavior; its corrupt-file move-and-start-fresh
branch and claim that no migration/version bump exists are superseded by this rule.

Dispatch and return persistence are atomic. A return commits its seeded outcome, rewards,
casualties, order advancement, and report together; intermediate mutation signals cannot save
half a return. A failed write rolls memory back. Reopening cannot credit an already committed
return again, and an uncommitted return reuses the saved seed. Bulk operation confirmation also
revalidates current state before one transaction. Actual disk save/reload acceptance is required.

### Refused-save recovery (`P2-17`)

`load_game()` (`systems/save_service.gd:21-45`) has three refusal branches that return `false`
and leave `GameSession` at constructor defaults. `_ready()` (`systems/game_session.gd:24-27`)
then connects `roster_changed` to `SaveService.save` *after* the refused load, so the first
summon/expedition/upgrade overwrites the refused file with that default session — silently,
in place, no backup. This ruling is on what happens instead, per branch.

**Ruling: the three branches do not get the same treatment.**

- **Branch 1 (file missing) — untouched.** This is the legitimate fresh-start path and was never
  the defect; nothing here changes it.
- **Branch 2 (corrupt: top-level JSON is not a Dictionary) — move the file aside and start
  fresh.** `load_game()` renames `user://save.json` to `user://save.corrupt.json` (overwriting
  any prior one — see below) before returning `false`, so the *next* `save()` writes a clean file
  at the canonical path instead of clobbering the refused one in place. `GameSession` proceeds
  with constructor defaults exactly as it does today; nothing about the in-memory session changes,
  only that the bad bytes no longer sit where the good ones are about to land.
- **Branch 3 (`version > SAVE_VERSION`, newer-than-this-build) — refuse to boot instead.** This
  file is not damaged — it is valid data a newer build wrote and this older build has declined to
  parse. Moving it aside or starting fresh over it risks exactly the data loss this ticket exists
  to prevent, except worse, because unlike branch 2 the data was perfectly recoverable by running
  the build that wrote it. The correct recovery action is "run the newer build," not "start over,"
  so the game must stop before entering play rather than pretend nothing is there.
  **This branch is unreachable in shipped builds today** (`SAVE_VERSION` has never been bumped
  past `1`), so nothing needs to render yet — the behavior is ruled now so it doesn't get
  relitigated the first time a version bump makes it reachable, but building the error-rendering
  UI for it is scoped to that future ticket, not `P2-17`. Noted in `KNOWN_ISSUES.md` under "No
  save migration" so this doesn't get lost between now and then.

**What the player sees (branch 2 only, since it's the only one reachable today).** A silent
move-aside is indistinguishable from data loss from the player's side — a save that vanishes with
no message reads as the game ate it, not as a recovery. This ruling therefore requires one line of
on-screen text, which is a real addition beyond the "~3 lines inside `load_game()`" estimate: a
transient, **not persisted**, flag — e.g. `SaveService` holding a one-shot notice string set on
the corrupt branch — read and cleared by whichever scene the player lands on first (the main menu
today, per `CLAUDE.md`'s note that `SceneRouter` and the main menu both already exist). Suggested
copy: *"Your last save couldn't be read and was moved aside as save.corrupt.json. Starting a new
game."* It must not be written into the save file itself — the whole point is that the next
`save()` is clean. If `save.corrupt.json` already exists (a second corruption before the player
has dealt with the first), overwrite it; a corrupt file has no gameplay value beyond one bug
report, and keeping more than the latest is standing state this ruling doesn't need.

**Whether the write side is in scope: named, not included.** `save()` (`save_service.gd:9-17`)
writes directly to `user://save.json` with no temp-file-then-rename, which is *why* branch 2 is
reachable at all — a crash or power loss mid-`store_string` leaves a truncated file that parses to
`null`. Fixing that (write to a temp path, then rename over the real one) reduces how often branch
2 fires; it does not change what happens *after* a refusal, which is the whole of what `P2-17`
asked. They are different code paths (`save()` vs. `load_game()`) with different acceptance tests
(kill the process mid-write and confirm the *previous* save survives intact, vs. drive a corrupt
file through `load_game()` and confirm the notice and the rename). **Atomic write is a separate
ticket**, not folded into `P2-17` and not left unmentioned — small and worth doing given it
directly reduces recurrence of the defect this ruling handles, but the director's to open.

**Rejected: read-only mode for the corrupt branch.** Requires a suppress-saving flag plus
on-screen communication of *why* nothing persists — the harder of the two costs named in the
task, by the task's own estimate — and buys nothing branch 2 needs: there is no in-app action that
repairs corrupt bytes, so "read-only until resolved" has no resolution path and would suppress
every future save indefinitely, converting "lost one save" into "lost this and every session
after it," unless the resolve step *is* moving the file aside — at which point it has collapsed
into the move-aside ruling above with more standing state (a flag watched forever) for the same
outcome.

**Rejected: refuse to boot for the corrupt branch.** Same premise problem as read-only: nothing
in-game can fix a corrupt file, so refusing to boot is a permanent wall until the player manually
deletes or moves it outside the game entirely — worse than `P2-18`'s own precedent that the game
should never sit in a state a player cannot act their way out of. It also needs new
error-rendering UI (the costliest of the three, per the task's own estimate) to protect a state
that move-aside handles for three lines and no new screen.

**Rejected: move-aside for the newer-version branch too (uniform treatment).** This is the point
1 answer stated as a rejection: applying branch 2's fix to branch 3 would discard valid data the
player could recover simply by running the right build, silently starting a fresh 300-stone
session over it. Worse than doing nothing, since branch 3 is unreachable today and doing nothing
about it costs zero risk.

> ⚠️ **PROVISIONAL** — whether one boot-time line of text is enough, or a corruption event needs a
> more persistent, reviewable trace (a settings-menu note, say) once the player is past the
> initial moment. Arithmetically settled; never played. · **Settled by:** a played build that
> actually reaches branch 2 — which needs a deliberately truncated save or a real crash-during-write
> to trigger, so this may need a manufactured repro rather than incidental play.
