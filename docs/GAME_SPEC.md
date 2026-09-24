# Game Spec

Working title: **Infinite Gacha**

This is the stable reference for what the game is. If a proposed change contradicts this
document, the document wins or the document gets amended — not silently reinterpreted.

---

## Player fantasy

You are a summoner running a mercenary hall. **You never fight as yourself.**

You pull heroes out of a gacha, gear them, and command autonomous squads on expeditions.
You can watch, issue RTS orders, use abilities and supplies, or let configured tactics run
the battle. Progress still carries stakes: fodder can strengthen other heroes, downed heroes
need help, a stranded force needs a rescue, and permanent losses leave recoverable gear.

The feeling being engineered is **attachment vs. expendability**. Every hero is
simultaneously an investment you've poured materials into and raw material for a better one.
The game is working when deciding whose life to spend is uncomfortable.

Inspired by the manhwa *Pick Me Up, Infinite Gacha*.

---

## Core loop

1. **Summon** heroes with Summon Stones. Rank F → SSS, weighted heavily toward junk.
2. **Gear** them from 10 equipment slots, also ranked F → SSS.
3. **Send** saved squads of up to 5 into timed expeditions. Standard zones accept one squad;
   authored raids and regional missions combine squads into larger forces, initially 30 and
   50 heroes. Separate forces can run concurrently; their heroes, gear and allocated supplies
   are reserved. Watch and intervene, or use the same simulation unattended.
4. **Return, extract, or rescue.** Zero HP means downed. Living teammates can revive allies
   with a skill/item or carry them to extraction. A full wipe strands the force; send another
   team, attempt a partial rescue, or abandon them. Final abandonment/active rescue expiry
   causes permanent death and the existing recoverable gear caches.
5. **Salvage** unwanted gear into parts; **enhance** the gear worth keeping.
   **Sacrifice** fodder heroes into a keeper to push its rank up.
6. **Push** a harder zone, or issue finite repeat orders to established teams. Unlimited farming
   requires a conservative safety forecast for the current team and zone.

Strength reduces expedition duration with diminishing returns and a nonzero floor. Small
parties take longer to cover the same workload, so splitting one team into solo parties does
not multiply income simply because combat already scales with party size. Returns bank rewards
automatically. Timers limit throughput; repeated claim clicks do not.

Recovery expeditions are a parallel branch of step 3: low-power runs that go fetch a dead
hero's gear before the cache decays. Recovery time is active gameplay time, paused on new losses
until the player reviews them; parallel returns and time with the game closed do not age caches.

---

## Win and loss

**There is no run structure and no meta-loss state.** This is a persistent roster game, not
a roguelite.

- An **expedition** succeeds, retreats, or wipes. That's the only win/loss the player meets.
- A **session** ends when the player stops playing. State is fully persistent.
- The only real failure mode is attrition you can't dig out of. Gear recovery runs exist
  specifically so that a wipe is a setback, not a dead save.

Long-term goal: build an SSS hero. The design assumes you *manufacture* one through
sacrifice rather than pull one — the pull rate is 0.02%. Checked against the current
`SYSTEMS.md` numbers: a lucky direct pull takes ~5,000 summons on average; feeding every hero
you don't keep into one target takes ~327 — about 15× cheaper, which is what "manufacture,
don't pray" needs to be true to hold up as a claim rather than flavor text. The Summoning
Circle (base building, `SYSTEMS.md`) erodes this ratio as it levels up, but by design not past
~12× even at its cap — checked so the claim holds at every stage of the game, not just before
any buildings are built. Since 2026-09-23 the last step, SS→SSS, also needs a born master priest
at the Sanctum (§ Heroes staff the buildings). That changes when you can finish, not what it costs.

> ⚠️ **PROVISIONAL** — the ~327-pull and ~12×/~15× ratios are arithmetically verified
> (`SYSTEMS.md`) but unvalidatable against real play time: there is no Summon Stone income rate
> yet, so "327 pulls" doesn't map to a session count, and the ratio itself has never been played,
> only computed. · **Settled by:** Summon Stone income being defined (`P2-09`) and a played build.

---

## Target platform

- **Windows desktop**, primary and only Phase 1–4 target.
- Steam Deck is plausible later (controller support is already a hard constraint).
- **No mobile. No web. No console.**

---

## Hard constraints

These are non-negotiable and shape architecture. Changing one requires a `DECISIONS.md` entry.

- **Single-player, fully offline.** No accounts, no servers, no telemetry.
- **No multiplayer, ever.** Nothing gets designed "in case we add co-op."
- **No real-money monetization and no energy meter.** The gacha is a game mechanic, not a
  storefront. Timed expeditions are roster-management commitments, not paid waiting gates.
- **Controller support remains a target.** The approved first RTS implementation and its
  acceptance use desktop mouse/keyboard controls. The former action-combat gamepad requirement
  does not imply an already implemented RTS controller interface; that work remains explicit.
- **60 FPS** with 5 heroes and ~20 enemies active on mid-range hardware.
- **Save system required**, human-readable, versioned from the first commit.
- **Timed sent expeditions; immediate management actions.** Dispatched runs can finish while
  the game is closed. Repeats launch only while the game is running: reopening resolves each
  already-dispatched run once, then starts its next run at full duration if its order continues.
  There is no chain of offline farming. This supersedes the original no-clock rule by owner
  approval on 2026-09-22 (`DECISIONS.md`, `ig-6l4`).

---

## Combat model

### Approved autonomous squad direction (`ig-544`, 2026-09-22)

Heroes handle basic attacks and role positioning themselves. Auto Battle advances authored
objectives, while per-ability/item Auto or Manual preferences remain authoritative. Players
select heroes/squads, move, attack-move, hold, guard, retreat, target abilities/items and pause
the watched battle for orders. There is no direct hero-piloting requirement.

The first visual style is chibi, using readable class silhouettes, selection rings, HP/downed
indicators and restrained effects. Standard encounters prove five-hero play; a 30-hero raid
uses simultaneous objectives and a 50-hero region uses camps, patrols and an escort route.
These are authored bounded maps, not a seamless world or procedural generation.

The four existing archetypes get signature abilities and passives. Supplies have explicit
per-run allocations and stockpile reserves. A repeat cannot silently drain protected supplies.
The same deterministic battle rules run whether a view is open or closed. Rendering and
observing grant no extra rewards; return timers remain the minimum reward-arrival gate.

Downed heroes remain in the roster but unavailable. Any living allied squad keeps a raid
active. Victory secures the downed; retreat secures bodies actually brought out. Each stranded
incident has its own reviewed active-play rescue window, never an offline countdown. Rescue
can succeed partially or fail; failed rescuers join that incident without resetting its age.
An attempt dispatched before expiry can finish before any remaining losses are finalized.

### Historical quick-resolve and action-arena direction

The following describes the legacy implementation, superseded as the target by the approved
autonomous direction above. Its isolated action arena and resolver API remain compatibility
surfaces during migration; they are not the new combat design.

Two resolution paths behind one seam. Both take `(team, wave)` and return a `CombatResult`,
and nothing upstream can tell them apart.

- **Quick resolve** — statistical. Resolves a sent expedition when its timer completes.
  The timer does not change combat odds, attrition, loot, or permadeath.
- **Action arena** — real-time 3D. The player takes direct control of one party member
  (WASD + mouse aim, attack, dodge); AI runs the other four.

**The arena is a combat-feel prototype, not a path the core loop resolves through**
(decided 2026-08-11, `DECISIONS.md`). It is where attack timing, dodge, parry, hit reaction
and weight get tuned by hand. It takes a real `Wave` in and returns a real `CombatResult`
out — and that result is **display-only**. Permadeath is deliberately **not** wired to it:
`Expedition` remains the sole permadeath consumer (`ARCHITECTURE.md` r8), and a hero that
loses in the arena loses nothing. Player-controlled combat gets permadeath when controlled
expeditions exist (Direction, below), because that is the first path where losing a hero is
a decision the player made about a run rather than an outcome of a practice bout.

Quick resolve is what makes grinding tolerable, and today it is the only path that resolves
anything.

---

## Direction — where this goes after the core loop

**2026-09-22 amendment:** the sent/controlled split and direct-piloting intervention below are
superseded by `ig-544` / `ig-yzc`: one autonomous simulation, optionally watched and commanded.
The town and caravan paragraphs remain historical future directions, not extra scope in this
combat implementation. In particular, the old demand that every future result fit
`CombatResult` is replaced by the explicit `BattleOutcome` boundary in `ARCHITECTURE.md`.

**2026-09-23 amendment:** the town is scheduled (`ig-wgj`). § The town hub below is its spec and
supersedes the town bullet further down. Caravans, controlled expeditions and hopping in stay
unscheduled.

### The town hub — scheduled 2026-09-23 (`ig-wgj`)

The owner's direction, 2026-09-23: the town is the main hub. **The menu goes away and the town
becomes the interface.**

- **You use a building by clicking it.** The Forge is the blacksmith: click it to equip, enhance,
  salvage and convert gear, and to upgrade the Forge itself. Click the Summoning Circle to summon.
  Every action the hub has today stays reachable. What changes is that a building opens it
  instead of a tab.
- **The town looks alive.** Your heroes who are home walk around and use its stalls. "Home" means
  not away on an expedition and not stranded. A hero you send out leaves the town, and a hero who
  returns shows up again. Heroes you station at a building work there (§ Heroes staff the
  buildings). You walk the town as one of them (§ The town avatar).
- **Buildings show their level.** Upgrading a building changes how it looks. Levels already
  persist (`P2-07b`); this slice only draws them.
- **Later: a base builder with an NPC-driven economy.** This is direction only: no ticket and no
  scaffolding. See the end of this subsection.

Where today's actions live:

| Building | Opens | Today it is in |
|---|---|---|
| Summoning Circle | Summon; Circle upgrade | Hall tab |
| Forge | Inventory, equip/unequip, enhance, salvage, convert; Forge upgrade | Armory tab, plus the Hall upgrade list |
| Sanctum | Sacrifice and rank-up; Sanctum upgrade | Teams tab (Advancement) |
| Training Hall | Team presets, practice battle; Training Hall upgrade | Teams tab and Hall tab |
| Reliquary | Lost-gear recovery; Reliquary upgrade | Hall tab |
| Town Gate (new, no level) | Dispatch, active orders, recent returns, stranded incidents | Expeditions tab |
| Apothecary stall (new, no level) | Supply crafting | Hall tab |

Clicking a hero in town opens that hero's detail. Any panel that needs you to pick heroes shows
the shared roster list, as the Teams and Armory tabs do today. Summon Stones, Essence and the
status line stay on screen as a HUD. A compact building list, bound to a key, stays as a backup
so that nothing can only be reached with the mouse: controller support is still a hard-constraint
target. The two new buildings have no level, and they gain none here. Giving them levels would
add save state and a balance row, and nothing asks for either.

**Owner rulings, 2026-09-23 (`ig-wgj`).**

- **Far click.** If you have a body, clicking a building walks your hero there, and the panel opens
  when the hero arrives. With no body, the panel opens at once.
- **Fallback.** The building list is bound to keys 1-7.
- **Townsfolk.** Only your heroes live in the town. The heroes run the buildings themselves
  (§ Heroes staff the buildings, below). There are no decorative keepers and no NPCs.

### Heroes staff the buildings — owner ruling 2026-09-23 (`ig-wgj`)

The owner, 2026-09-23: "I want the heroes themselves be the shopkeep NPCs, they have their own
blacksmith skills, research skills, ect".

**The shopkeepers are your own heroes.** You station a roster hero at a building, and that hero
works there. Nobody is hired. The town still has no NPCs, so § Scope boundaries holds. Every face
behind a counter is a hero you pulled and can lose.

**Professions.** Each profession belongs to one building:

| Profession | Building | What a working keeper improves |
|---|---|---|
| Smithing | Forge | Salvage yield |
| Rites | Sanctum | Sacrifice Essence yield |
| Drill | Training Hall | Expedition XP |
| Tracking | Reliquary | How long lost-gear caches and rescue windows last |
| Alchemy | Apothecary | The parts cost of supply draughts |

The Summoning Circle and the Town Gate take no keeper in this pass.

- **Circle.** A keeper bonus on summon odds would wear down the ~12× "manufacture, don't pray"
  margin that § Win and loss guards. A Circle keeper needs its own ruling and its own check.
- **Gate.** It has nothing for a keeper to improve.
- **Research.** The owner parked "research skills" for the base builder on 2026-09-23. It has no
  system today, and it gets none in this pass.

The numbers are in `SYSTEMS.md` § Keepers and professions.

**Where skills come from: born + practice.** Owner, 2026-09-23: "Born + practice. The calling is an
immense xp boost, like the progression system in rim world. Also only the ones with calling can make
masterwork(the final tier) equips/food/etc".

- **Born: a calling, rolled once.** Every hero is born with one calling: one of the five
  professions, picked at random when the hero is created. The roll ignores rank and archetype, on
  purpose. An F-rank Knight can be a born smith, and an SS Mage can be useless at the Forge. Dupes
  of one definition roll their callings separately, so two copies of the same hero are not
  interchangeable.
- **Practice: XP from working.** A keeper earns XP in its building's profession by working there
  while you play. XP only builds up during live play, on the same clock that ages recovery caches.
  It never builds up while the game is closed (§ Hard constraints).
- **The calling is a huge XP boost,** like a RimWorld passion. A hero learns its calling several
  times faster than anything else. Every hero can reach the top skill level in every profession;
  a born smith just gets there in a fraction of the time.
- **Only a born master makes masterwork.** Masterwork is the top tier of a profession's output
  (below). It needs a keeper whose calling *is* that profession and whose skill is at the top
  level. A hero who learned the trade without the calling gets the full skill bonus, but never
  masterwork.
- **Skill lasts the hero's life.** A hero keeps what it learned when you move it to another building,
  and when it ranks up. Death and sacrifice erase it. Skill cannot be passed on, recovered or
  inherited. What a master already made stays made.

**Professions are not stats.** The six combat stats are settled by ADR, and a profession is not a
seventh. No combat path reads a profession: not the battle simulation, not `hero_power`, not the
repeat safety forecast, not rank multipliers and not gear. Gear never changes a profession, and a
profession never changes a fight. Exactly one thing reads a profession: its own building, while
that keeper is home.

**What a keeper changes.** A building has one keeper, and a hero keeps one building. A keeper who is
home adds a skill bonus on top of the building's level bonus. With no keeper, or with its keeper
away, a building works as it does today, except for masterwork. Masterwork is the only thing that
needs a keeper. Keepers are visible: they stand at their building doing its work, like hammering at
the Forge. Clicking a keeper opens the building.

**Masterwork, profession by profession.** "Equips/food/etc" means professions whose output comes in
tiers. Today only two buildings make anything, so only those two have a masterwork tier. Nothing
here adds a recipe or a crafting tree.

| Profession | What the building makes today | Masterwork | Needs |
|---|---|---|---|
| Smithing | Enhancement levels on gear, +1 to +15 | Enhancing past +12, into +13 to +15. A level-5 Forge opens that band, and only a born master smith may use it. | Nothing new. It gates a band that exists today. |
| Alchemy | Healing and revival draughts | A masterwork draught of each kind, stronger than the regular one (PROVISIONAL, below) | A new supply tier. It changes battle rules and the supplies save. |
| Rites | Rank-ups, F→D through SS→SSS | The final rank-up, SS→SSS. Only a born master priest who is stationed at the Sanctum and home can perform it. | Nothing new. It gates a step that exists today. |
| Drill | Expedition XP. It makes nothing. | None. Skill bonus only. | — |
| Tracking | Longer lost-gear and rescue windows. It makes nothing. | None. Skill bonus only. | — |

The Forge row changes today's game. A level-5 Forge enhances to +15 on its own today. After this, it
stops at +12 unless a born master smith is home at the Forge. Gear already past +12 keeps its
level: the gate limits gaining a level, not keeping one. This is the owner's rule applied to the
one output tier the Forge has.

**The Rites gate touches the spine, and the owner chose it knowingly (2026-09-23).** The designer
and the director both recommended against it. An SSS hero is the game's long-term goal (§ Win and
loss). From now on, the last step to it needs a born master priest: a hero whose calling is Rites,
at skill 5, stationed at the Sanctum and home when you press rank-up. Heroes already at SSS keep
their rank.

- **The risk.** Your master priest can die on an expedition, or you can feed away every hero born
  for Rites. Either way, your SS hero cannot finish until you raise another master. The essence you
  saved is not lost, but the goal is on hold.
- **The way out is a delay, never a dead end.** One hero in five is born for Rites, whatever its
  rank. You can always pull again: expeditions pay Summon Stones, and an empty roster gets a free
  pull (`SYSTEMS.md` § Roster-wipe recovery floor). Once a Rites-born hero works at the Sanctum, it
  reaches master in 75 minutes of live play. `SYSTEMS.md` § Keepers and professions has the odds
  and the time.
- **How to never wait.** Keep one Rites-born hero and station it early. Its training then runs
  alongside the grind, and the gate costs you nothing but the one hero you did not feed.

**The tension: keepers can leave, and keepers can die.** This brings the game's core tension home.

- **A keeper can be sent out.** Stationing does not reserve a hero. The dispatch screen says what
  you give up, for example "The Forge runs without Mira while she's away". The hero stays assigned,
  and the bonus comes back when the keeper does. A keeper on an endless repeat order is a keeper in
  name only.
- **A keeper who dies takes the skill with them.** Permadeath empties the station and erases the
  skill. Recovery brings the gear back. It never brings the skill back. When your best fighter is
  also your best smith, that is a real dilemma.
- **A stationed keeper cannot be sacrificed.** It is protected like team-preset members and the
  body. You unassign it first, as a separate, deliberate act. Feeding a born smith to another hero
  should be a choice, not a bulk-select accident.
- **Fodder gets a second job.** The spine says to feed every hero you don't keep, at any rank. A
  calling pulls the other way. That F-rank Knight is 10 Essence in the Sanctum, or your Forge's
  future master. Both answers should hurt.

**A keeper can be your body.** Walking as a keeper does not stop its work, because the body is at
home. While you are that hero, its counter stands empty. The body rules still apply: you cannot
dispatch the hero you are in.

**How this feeds the economy later.** Professions are the labor a future NPC economy would read.
More slots per building would mean more keepers, and production would scale with keeper skill.
Whether anyone besides roster heroes ever works in the town is still § Scope boundaries' call.
Nothing is built toward it now.

**Owner rulings on staffing, 2026-09-23.**

- Keepers can be sent out, and death erases the skill.
- Skill is born + practice, and masterwork is reserved to the calling.
- The Forge's +13 to +15 band needs a master smith who is home.
- Masterwork draughts are built now, after the keeper bonuses (`DECISIONS.md` 2026-09-23,
  masterwork draughts).
- SS→SSS needs a master priest.
- Research is parked for the base builder.

> ⚠️ **PROVISIONAL** — masterwork draughts have never been played. They heal or revive for more,
> cost more, and are spent after the regular stock (`SYSTEMS.md`). Whether a stronger draught
> changes how raids feel, or only how often you craft, is unknown. · **Settled by:** a played build
> with masterwork draughts in a 30-hero raid.

> ⚠️ **PROVISIONAL** — whether the Rites gate feels like a fair delay or like a wall. The arithmetic
> says it costs nothing to a player who stations a Rites-born hero early, and at most about 75
> minutes plus a few pulls to one who loses theirs. Nobody has lost a master priest at SS yet.
> · **Settled by:** a played build that reaches SS→SSS, once with a master kept and once after
> losing one.

**Base builder and NPC economy — direction only.** The owner eventually wants to lay out and grow
the town, with an economy run by NPCs. Nothing gets built toward that now. Three questions are
recorded here so that no town slice closes them off by accident:

1. **Placement.** The choice is authored plots or free placement. Today building positions are
   authored in the scene and are not save state. Either answer makes them save state.
2. **Offline.** Under § Hard constraints, only dispatched expeditions progress while the game is
   closed. An economy that produced while closed would need a `DECISIONS.md` entry amending that
   line. The default is that it runs only during play, like the recovery clock.
3. **Output.** An economy that mints Summon Stones or parts competes with expedition income. That
   moves every income number in `SYSTEMS.md` and the ~327-pull claim in § Win and loss.

"Defend it against attack" (the old town bullet) belongs to this same later tier. Keeper
professions (§ Heroes staff the buildings) are the labor this economy would read. They do not
answer any of the three questions above.

> ⚠️ **PROVISIONAL** — undefined as a whole: placement, what NPCs produce, and whether anything
> runs while closed. · **Settled by:** an owner ruling when the base-builder epic is scheduled,
> made against measured Summon Stone and parts income from a played build, since economy output
> is priced against it.

Recorded 2026-08-11. **None of this is the draft, none of it is next, and none of it gets
built toward speculatively** — no scaffolding, no interfaces with one implementation, no
"we'll need this later" fields. It is written down because it changes what "the hub" and
"an expedition" eventually mean, and because a boundary dissolved now is expensive to
restore. Each row becomes a ticket through `tech-lead` when its turn comes; the backlog rows
live in `TASKS.md` § Direction backlog.

The game becomes open-ish world. The hub stops being a menu and becomes a place you leave.

- **The town.** The hub is walkable. You move around it, talk to your own heroes and to
  NPCs, build it up, and eventually defend it against attack. See § The town avatar below
  for who you walk around as.
- **Two kinds of expedition.** *Sent* expeditions stay math (`combat/quick_resolve.gd`) —
  that path is not being replaced, and it is what makes a large roster playable.
  *Controlled* expeditions walk out of the town gate into an instanced open-world map with
  objectives, and are played rather than resolved.
- **Hopping into a sent expedition.** Take direct control of one hero mid-run to raise its
  chance of success. The math path stays the default and the fallback; this is an
  intervention, not a replacement.
- **Caravans.** Escort a cargo wagon to another town to trade resources. Send heroes and let
  the NPCs handle it, or ride along with a controlled hero and defend the cargo. A
  **simulated event**, not background arithmetic — the distinction is the point of the
  feature.

**What this asks of the code today: nothing built, three seams kept honest.**

1. **`SceneRouter` stays the only thing that changes the main scene** (`ARCHITECTURE.md`
   r5). Town, world map and instance are more destinations, not a second routing mechanism
   that grows next to it.
2. **A played run reports through `CombatResult`** (`ARCHITECTURE.md` § The combat seam).
   Whatever produces an outcome — quick resolve, arena, a controlled expedition later —
   hands back that one type, and the systems upstream keep consuming only it. The moment
   something upstream branches on *which* path produced a result, the seam is gone.
3. **Permadeath keeps exactly one writer** (`ARCHITECTURE.md` r8). Every path above can
   eventually kill a hero. None of them gets its own kill call.

---

## The town avatar

Ruled 2026-08-13. Settles the question § Direction left open.

**You walk around town as one of your own heroes, and you can swap which one at will.** The
summoner is still who you *are* — you run the hall, you pull, you decide whose life to spend —
but the body standing in the town square is a roster hero you are puppeting, the same way you
take direct control of one party member in the arena. Player fantasy above holds unchanged and
literally: the summoner never fights, because the thing that fights is a hero you are steering.
The avatar is a **view onto the roster, not a member of it** — embodying a hero grants it
nothing, costs it nothing, and changes no stat.

**When the hero you are embodying dies, you are standing in a corpse's shoes — so the game does
not let you get there.** A hero currently being embodied cannot be added to a sent expedition
team. To spend the hero you have been walking around as, you first step out of it and into
another body, deliberately, as its own act. That is the point rather than a safety rail: this
game is about how uncomfortable it is to decide whose life to spend, and making you leave a body
before you can feed it to a zone is the strongest version of that decision the town can offer.
Permadeath itself is untouched — `Expedition.resolve()` stays the only writer, and the town
observes the roster rather than editing it.

**Pinned down 2026-09-23 (`ig-wgj`).** "Spending" includes sacrifice. The body you are in cannot be
fed to another hero, just as it cannot be dispatched. It can still be geared, enhanced and
ranked up, because none of that spends it. Only a hero who is home can be a body: a hero reserved
by an order or a stranded incident cannot, and that covers the downed ones too. You pick a body
deliberately, from a hero's detail ("Walk as this hero"). The game never picks one for you,
because that would quietly lock your best hero out of dispatch. Your choice is saved with the
profile. A new profile, or one whose body is gone, starts at the fixed overview until you choose.
The other heroes you see walking around are also views onto the roster. Where they stand and
what they are doing is never saved. A hero stationed at a building can still be your body, and its
building keeps working (§ Heroes staff the buildings).

The remaining death case is the **empty roster**: a wipe can leave you with no hero to embody.
The town's answer is that it is a place you can be standing in with no body — the camera detaches
to a fixed overview of the square and the panels still work, which is exactly the state the hub
is in today. You always afford one more pull (`SYSTEMS.md`, `TASKS.md` P2-18), so the way out of
it is the way out of every wipe.

> ⚠️ **PROVISIONAL** — whether swapping bodies at will is right, or whether the embodied hero
> should be a commitment you pay to change. Free swapping is the cheaper build and the weaker
> attachment; a cost makes the body matter but risks feeling like a tax on walking around.
> **Settled by:** a played build with a walkable town and more than one hero worth standing in.

**What this costs the other direction rows.** `D-02` inherits an avatar that is already a hero,
so walking out the gate is continuity rather than a hand-off — and it inherits the reason
permadeath belongs there: the moment a controlled expedition can kill you, the "you cannot send
the body you are in" rule stops protecting anything, because you walked it out yourself. `D-02`
decides what happens then; this ruling does not. `D-04` inherits it twice over, since riding
along with a caravan is the same walk-out, and a second town is a second place the same avatar
stands.

---

## Scope boundaries for the draft

Explicitly **not** in the rough draft, and not to be invented by an implementer:

story/campaign, dialogue, town NPCs, crafting trees, gear set bonuses, hero injuries or
morale, pity system, achievements, difficulty settings, procedural dungeon generation,
day/night, weather, mounts, pets, guilds.

**Clarified 2026-09-23 (`ig-wgj`).** Heroes stationed at buildings are roster heroes, not town
NPCs, so the "town NPCs" exclusion still holds. "Crafting trees" still holds too. Professions have
no recipes and unlock nothing. They only scale bonuses the buildings already give.

**Excluded from the draft is not the same as excluded forever.** Hard constraints above is the
never list; this one is a *now* list. Direction above already names town NPCs as eventual, and
"not to be invented by an implementer" is what both readings have in common — a feature arrives
as a ticket, never as something that appeared while someone was building an adjacent thing.
