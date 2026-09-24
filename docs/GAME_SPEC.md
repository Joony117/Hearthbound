# Game Spec

Working title: **Infinite Gacha**

This is the stable reference for what the game is. If a proposed change contradicts this
document, the document wins or the document gets amended — not silently reinterpreted.

---

## Direction (owner, 2026-09-24)

**Approved by the owner on 2026-09-24,** after an eight-round debate (director vs GPT-6 Astra).
This is where the game is going, and it outranks older direction text in this file. It is a
target, not a build list:
- Each step arrives as a ticket under the `ig-m6o` epic, in order.
- Nothing is built toward a later step ahead of time.
- Until a step lands, the rules in the rest of this document hold.
- Lines this direction contradicts are marked **Amended 2026-09-24**, not deleted.

### The pitch

*Infinite Gacha is a living-world squad RPG where every summon brings someone worth knowing,
every battle changes their relationships, and the town you build can rise to rescue them.*

**Spine:** summon a person → give them a home → discover whom they love and what they want →
fight together → let their choices, achievements and losses change the world.

### The six pillars

**1. The Door Opens Onto Lives.** Every summon changes two worlds.
- Open a homeland rift and glimpse someone mid-adventure, before rank, name, passion and dream
  appear.
- Summon extraordinary power, and the pursuer who knows how to defeat it.
- Watch pity become a beacon: a particular recruit approaches a guaranteed arrival.
- Pull distinct relatives, rivals and pupils instead of duplicate souls.
- Face an entire homeland demanding its missing person back.
- **Joy:** rift potlucks bring singing bread, impossible recipes and embarrassing reunions.

**2. A Home Worth Returning To.** Build streets full of people who have reasons to stay.
- Neighbours become friends, rivals and collaborators. Adjoining workshops invent techniques.
- Fulfil a dream by founding a tavern, school or forge that seeds other people's dreams.
- Feed households through winter. Design evacuation routes around actual rescue promises.
- Watch apprentices found independent settlements that reinterpret your traditions.
- Call a retiree into one legendary battle: their pupils and institutions combine into **The
  Founder Walks Again**.
- **Joy:** soup factions, petty hobbies, monster pets, nickname traditions and festivals arise
  from residents' histories.

**3. People Inside the Fight.** Their relationships change what your squad can do.
- Program skills across bonded heroes: one commits, another counters the retaliation.
- Pilot a frightened veteran through the killing pattern they finally recognise.
- Turn a dream into a rescue chain: break pursuit, lift a friend, cast while carrying.
- Let an apprentice answer the missing beat in a grieving survivor's old combo.
- Confront a refusal with a visible reason: a hero breaks formation to save someone, and may be
  right, or tragically mistaken.
- **Joy:** squads invent sports and ridiculous skill exhibitions. Apprentices parody a nemesis's
  famous pose.

**4. Power Has Witnesses.** Everyone remembers how you became extraordinary.
- Raise an overlooked F-rank through deeds into a **Risen** SSS whom fate can no longer ignore.
- Earn Essence through living achievements, or sacrifice someone for irreversible power.
- Face protests, hidden victims, purposeful volunteers, and desertions that found rival towns.
- Unleash the **Parliament of Ghosts**: sacrificed people perform their real techniques,
  cooperating or resisting according to their promises.
- Discover that you, the conscious Door, can be loved, hunted, rescued or overthrown by your own
  heroes.
- **Joy:** the terrifying champion still has a ridiculous nickname, and a pet that steals their
  chair.

**5. Fate Has a Face.** Outwit a Guest who engineers collisions from your actual history.
- Choose Mother Briar's tangled affections, the Gilded Jackal's outrageous wagers or Sister
  Cinder's unfinished promises.
- Read omens, bargain over opportunities, and discover the causal chain behind an encounter.
- Hunt named, scarred nemeses who remember your tactics, and who may eventually retire to teach
  counters to them.
- Recover a stolen name through the habits and techniques its forgotten owner left behind.
- Raise a Risen hero capable of stealing the Guest's chair.
- **Joy:** the Guest can arrange a disastrous reunion banquet as readily as a siege, and
  residents create the punchline.

**6. Nothing Ends Without Leaving Something.** Every life changes the world's possibilities.
- Visit graves with friends. Face hollow bosses carrying the dead hero's real kit and gear.
- Welcome the Winter of Names, when unfinished dreams return to familiar homes.
- Discover a dead defender's protection in their doorway. Eventually pilot **The Town Gets Up**
  to rescue an expedition.
- Read Chronicle chapters grounded in deeds, with witnesses who disagree about their meaning.
- Enter **The Old World** (approved, ruling 1): former towns become homeland rifts, your champion
  becomes a future nemesis, and a chair-thief becomes the next town's Guest.
- **Joy:** recipes, jokes and festivals outlive their founders. One soul remains one person
  throughout the afterlife.

### The addiction stack

- **30 seconds:** reveal a person through a rift, recognise a telegraph, land a personal combo.
- **5 minutes:** check a household, discover a dream complication, pick the next squad or summon.
- **Session:** pursue a promise, come back with changed relationships, build or celebrate the
  consequence.
- **"At work":** "Her brother arrives tomorrow. Will she still volunteer?" Anticipation lasts
  without punishing you for closing the game.
- **Hour 5:** squad sports reveal personality once basic automation is familiar.
- **Hour 20:** former apprentices build an independent town you want to visit.
- **Hour 100:** a retired nemesis's school teaches your enemies, and your pupils.
- **Hour 500:** a congress of homeland societies and former worlds contests the Door's future.

### The first hour

- **Minute 0:** summon someone with a passion, a dream and a homeland connection.
- **Minute 5:** place their home and workplace, and witness a specific interaction with another
  resident.
- **Minute 15:** deploy, read a telegraph, pilot a hero and program a short learned-skill chain.
- **Minute 30:** choose how to tackle an exposed rescue or a dangerous objective. Actual play
  produces protection, a near-loss or a loss. No death is scripted.
- **Minute 60:** come back to a relationship change, a dream milestone and a Chronicle entry. An
  omen connects tomorrow's expedition to what actually happened.

### Owner rulings, 2026-09-24

1. **The Old World: yes, runs stack up.** A fallen or retired town becomes a homeland rift for the
   next town. This amends the one-roster-forever premise (§ Win and loss).
2. **Power source: both.** Living deeds, finished dreams and Founding earn Essence and rank-ups.
   Sacrifice stays as the fast, dark path, with social fallout: protests, hidden victims,
   volunteers and desertions. This amends sacrifice as the only Essence source (§ Core loop,
   § Win and loss, § The town builder). The formulas touch the spine, so they wait for a restated
   spine (`SYSTEMS.md` § Sacrifice → rank up, spine flag).
3. **Defiance: yes, both.** A mid-fight refusal always shows its reason, and it can be right or
   wrong. It is never unexplained noise. Overthrowing the player, the Door, is rare and earned.
   This amends "preferences remain authoritative" (§ Combat model).
4. **Afterlife: a dead hero is never playable again.** There is no revive and no re-summon, in the
   Old World too. Ghost visits, hollows and the Parliament are fine: the dead act, but never
   rejoin the roster. `kill_hero()` stays the only roster exit, and nothing comes back through it.
5. **Director call: only Risen heroes can steal the Guest's chair.** A Risen hero is one that
   climbed F→SSS by deeds. A hero born above F cannot take the chair, by design. The underdog is
   the culmination.

> ⚠️ **PROVISIONAL** — game-designer readings of ruling 1, not owner rulings:
> - The old town's living people become its rift's population, and can arrive again carrying
>   their history. The dead never do (ruling 4).
> - A town "falls" when its Door is overthrown or its roster is lost beyond recovery. "Retired"
>   is the player's own choice.
>
> · **Settled by:** the owner, when `ig-m6o.8` is scoped

### The build order (`ig-m6o`)

Each step lands one new feeling. Each is wired after the one before it.

1. **The Ledger** (`ig-m6o.1`). Record settled events: who did what to whom, when and where.
   History readers derive from it, and combat still resolves combat. *"The game remembers what we
   did."* ADR: `DECISIONS.md` 2026-09-24.
2. **People at home** (`ig-m6o.2`). Quirks, dreams, meals, neighbourhood encounters and Bonds.
   *Affection and everyday amusement.*
3. **People in combat** (`ig-m6o.3`). The skill foundation finished, personal chains, informed
   refusals, rescue motives and recognition. *Trust in a particular squad.*
4. **Summoning with consequences** (`ig-m6o.4`). Homeland populations, anchors, beacon pity,
   entourage arrivals and pursuers; deeds and living achievements connect to promotion.
   *Anticipation about who arrives next.*
5. **Ambitions become institutions** (`ig-m6o.5`). Founding, apprentices, schools, food pressure,
   seasons, raids and independent settlements. *Pride in a society with its own future.*
6. **Death and power remain personal** (`ig-m6o.6`). Graves, sacrifice reactions, the Parliament,
   hollows, Winter visitors and inherited techniques. *Grief, responsibility and discovery.*
7. **Fate becomes an opponent** (`ig-m6o.7`). The selectable Guests, causal schemes, evolving
   nemeses, stolen names, Door overthrow and the chair challenge. *Rivalry with a world that knows
   you.*
8. **History becomes spectacle** (`ig-m6o.8`). The Founder's formation, the walking town, the
   homeland congress and Old World succession. *Astonishment at what these lives built.*

The skills lane (`ig-gy0`) and the town lane (`ig-6m2`) keep going. They are foundations steps 2
and 3 build on, not rivals.

### Cut

- **Alternate selves.** They undermine irreplaceability. Replaced by worlds transformed by one
  person's absence.
- **Anonymous duplicate fodder.** It contradicts personhood. Replaced by distinct entourage
  members.
- **Permanent F-rank invisibility.** It contradicts remembered deeds. Replaced by recognition
  earned through audacity.
- **Universal ascension, or compulsory death after retirement's final fight.** It treats
  fulfilment as disposal. Replaced by Founding and the living legendary formation.
- **Generic banners, and seasons with no people behind them.** Merged into homeland arrivals and
  the shared winter of hunger, visitors and promises.
- **A separate joy pillar.** It would isolate happiness from ordinary life. Joy is woven through
  all six.

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

> **Amended 2026-09-24 (§ Direction).** You are also the *Door*, the conscious gate the summons
> come through. You still never fight as yourself, but your heroes can love, hunt, rescue or
> overthrow you (ruling 3). The feeling widens rather than flips. Attachment now comes from
> knowing a person, not only from what you poured into them. Sacrifice stays as the fast, dark
> path, and now it has witnesses.

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

> **Amended 2026-09-24 (§ Direction, ruling 2).** Step 5's sacrifice is no longer the only way
> up. Living deeds, finished dreams and Founding will also earn Essence and rank-ups (`ig-m6o.4`,
> `ig-m6o.5`). Until those steps land, sacrifice is the only source.

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

> **Amended 2026-09-24 (§ Direction, ruling 1: the Old World).** Runs stack up. A town can fall,
> or you can retire it, and it becomes a homeland rift for your next town. Its champion can
> return as a nemesis, and a chair-thief becomes the next town's Guest. So "one roster forever"
> no longer holds. Each town is still persistent, with no roguelite resets inside it. The dead
> never return (ruling 4). Until `ig-m6o.8` lands, there is one town and the text below holds.

- An **expedition** succeeds, retreats, or wipes. That's the only win/loss the player meets.
- Since 2026-09-23 the town can also kill: a housed hero can starve to death if food stays at 0.
  It is warned, one death at a time, and never while the game is closed (§ Heroes eat, and can
  starve to death).
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
any buildings are built. Since 2026-09-23 the last step, SS→SSS, also needs a master priest at
the Sanctum: a hero with a Rites passion, trained to skill 5 (§ Heroes staff the buildings). That
changes when you can finish, not what it costs.

> **Amended 2026-09-24 (§ Direction, rulings 2 and 5).** Manufacturing an SSS will have two roads.
> Sacrifice is the fast, dark one. Living deeds, finished dreams and Founding are the slow, clean
> one, and their high point is the **Risen**: an F-rank raised to SSS by deeds, the only kind of
> hero that can steal the Guest's chair. The ~327-pull and ~15× figures below assume sacrifice
> alone, so they move once living Essence has formulas (`SYSTEMS.md` § Sacrifice → rank up, spine
> flag).

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
- **The town never kills while the game is closed.** Hunger runs only on the live clock, and its
  death clock waits for you to look (§ Heroes eat, and can starve to death). A sent expedition's
  own risk is the only death that can resolve on reopen, and you chose it when you sent the run.
  Owner ruling 2026-09-23 (`ig-6m2`).

---

## Combat model

### Approved autonomous squad direction (`ig-544`, 2026-09-22)

Heroes handle basic attacks and role positioning themselves. Auto Battle advances authored
objectives, while per-ability/item Auto or Manual preferences remain authoritative.
(**Amended 2026-09-24, § Direction, ruling 3:** a hero may refuse or break an order mid-fight. It
always shows its reason, and it can be right or wrong (`ig-m6o.3`). Until then, preferences stay
authoritative.) Players
select heroes/squads, move, attack-move, hold, guard, retreat, target abilities/items and pause
the watched battle for orders. There is no direct hero-piloting requirement. Since 2026-09-23
you *may* take direct control of one hero in a watched battle (§ Skills). It stays optional.

The first visual style is chibi, using readable class silhouettes, selection rings, HP/downed
indicators and restrained effects. Standard encounters prove five-hero play; a 30-hero raid
uses simultaneous objectives and a 50-hero region uses camps, patrols and an escort route.
These are authored bounded maps, not a seamless world or procedural generation.

The four existing archetypes get signature abilities and passives. § Skills grows each into a
full kit, and gives the Cleric one. Supplies have explicit
per-run allocations and stockpile reserves. A repeat cannot silently drain protected supplies.
The same deterministic battle rules run whether a view is open or closed. Rendering and
observing grant no extra rewards; return timers remain the minimum reward-arrival gate.

Downed heroes remain in the roster but unavailable. Any living allied squad keeps a raid
active. Victory secures the downed; retreat secures bodies actually brought out. Each stranded
incident has its own reviewed active-play rescue window, never an offline countdown. Rescue
can succeed partially or fail; failed rescuers join that incident without resetting its age.
An attempt dispatched before expiry can finish before any remaining losses are finalized.

### Skills — owner direction 2026-09-23 (`ig-gy0`, accepted)

> "I want each hero to have customizable skill bar, I want them to be able to have 30+ skills if
> I wanted. We can bulk up the skills list by poaching skills from final fantasy 14, the mmo"
>
> "I want AI to intelligently pick skills, but players can also take control basically play an
> mmo character. I think players should be able to program skill order too, as in theres one
> trigger skill and the player can choose what skills come after it. Also the heros AI should be
> able correctly respond to enemie skills too. As in enemie telegraphed heavy attack/skill ->
> hero uses available stun skill etc etc" — the owner

The owner also ruled: skills are learned three ways (level and rank-ups, skill books, the
Training Hall), and there is no bar limit. Every learned skill is usable.

**Inspired by FFXIV, owned by us.** FFXIV is where the ideas come from: weaponskills on a shared
swing, abilities woven between them, two-step combos, tank interrupts, healer shields,
telegraphed big hits. Nothing else comes from it. Every name, number, icon, effect and line of
text is ours. No Square Enix skill names, icons or VFX, and no names that are close copies.

**What a skill is.** Four kinds, all data:

- **Passive.** Always on. Each class has one: today's four passives, plus one for the Cleric.
- **Weaponskill.** Replaces the next basic attack. It rides the same swing timer, so a hero with
  thirty weaponskills still swings at the same speed. Some are the second step of a combo and hit
  harder right after the first step.
- **Ability.** Has its own cooldown and fires between swings. After any ability a hero waits a
  short lock before the next, so thirty abilities cannot all go off in one moment. Today's four
  signatures are abilities.
- **Counter.** An ability with a counter tag: stun, interrupt, dodge or shield. Counters are what
  the AI reaches for when an enemy telegraphs.

There is no mana or other skill resource. Cooldowns, the swing timer and the ability lock are
the only limits. A skill never adds a seventh stat: its effects read and change the six stats,
damage, healing, shields, statuses and position.

**The bar.** A hero's bar is every skill it knows, in an order you set. There is no slot limit.
Each skill has a mode:

- **Auto.** The AI may use it. This is the default, so a hero you never open still fights with
  its whole kit.
- **Manual.** Only you fire it, by command or while you control the hero.
- **Off.** Never used.

Bar order is priority: when the AI has two good choices, the one higher on the bar wins. That is
how you tune the AI without programming it. The 2026-09-22 rejection of "forcing thirty
individual skill bars onto the player" still holds, because nothing forces you to open a bar.

**How the AI picks.** Each time a hero can act, it takes the first of these that applies:

1. **Counter** an enemy telegraph (below).
2. **Revive** a downed ally.
3. **Heal** an ally who is low.
4. **Continue a chain** you programmed (below).
5. **Buff** when a fight is on and the buff is not already up.
6. **Attack**: area skills when enough enemies are close, otherwise the best single-target
   skill, with combo steps in order.

Each skill carries its own small rule (how many targets, below what HP, only on a downed ally),
so the AI is one general picker, not code per skill.

**The AI answers telegraphs.** When an enemy starts a telegraphed skill, the heroes who can see it
decide, after a short reaction delay, how to answer it:

1. Stop it: **interrupt** or **stun** the caster, if one is in range.
2. Else **shield** or protect whoever is standing in it.
3. Else **dodge**, if the hero itself is in it.
4. Else walk out of it, as heroes already do today.

One hero answers each telegraph, so three stuns are not wasted on one swing. The AI prefers the
counter with the shortest cooldown, and keeps the long ones for later. A skill set to Manual or
Off is never used as a counter.

**Chains: you program the order.** A chain is one trigger skill and the skills you want after it,
in order. When the trigger fires, by the AI or by you, the hero follows with the rest as each
becomes ready. A step that cannot fire in time is skipped. A counter or a revive can cut in, and
the chain carries on after. A Manual skill inside a chain fires: programming it into the chain
counts as firing it by hand (director ruling, 2026-09-23). A chain is a preference, not an order
queue. Orders still replace orders.

**Take control of one hero.** In a watched battle you can take one hero over and play it like an
MMO character. Its AI stops picking skills and targets for it. It keeps auto-attacking your
target. Its bar appears with number keys for the first ten skills; the rest are a click away.
Your other heroes keep their AI. Leave the battle view, and the AI takes the hero back. Control
changes nothing about rewards: the same simulation runs either way.

- **First version** (owner ruling, 2026-09-23): click to move and to target, number keys and
  clicks to fire skills, one controlled hero, watched battles only.
- **Later:** WASD movement, tab-targeting, a camera that follows the hero, and bar pages with
  your own keybinds.

**Two pools: the class and the general pool** (owner ruling, 2026-09-23). A hero learns its own
class's skills, plus skills from one shared general pool that every class can learn. No hero
learns another class's skills. The general pool is the road to the owner's 30+: each general
skill serves all five classes, so it grows the most bars for the least work.

- **General skills are utility, not damage.** Self-heals, a heal for an ally, damage reduction, a
  dodge, an interrupt, a small party buff. None replaces the swing, and none hits harder than a
  basic attack. They make a hero harder to kill and give every class a backup counter. They do
  not make a class hit harder, so the class kit stays what defines a hero.
- **General skills are never free.** They come only from books and the Training Hall, never by
  level. Each has a minimum hero level, so rank still gates them.

**Learning skills.**

- **Level and rank.** Each class skill opens at a level. Rank caps level (F at 10, D at 20, and on
  up), so ranking a hero up is what opens its later skills.
- **Skill books.** Rare expedition drops. A class book teaches its class's book-only skill to one
  hero of that class. A general book teaches one general skill to any hero at or above its
  minimum level.
- **The Training Hall.** Teaches a class skill before its level, and teaches general skills, for
  parts. A higher hall teaches further ahead and opens more of the general pool. It never teaches
  a class book-only skill.

A hero keeps what it learned for life. Death and sacrifice erase it, as they erase profession
skill (owner ruling, 2026-09-23).

**What skills never touch.** Books add no Summon Stones, Essence or parts, and sacrifice reads only
rank and level, so skills do not move the ~327-pull claim in § Win and loss. Stronger heroes clear
faster, which changes time, not pulls, the same as gear does.

**The Cleric gets a kit** (`ig-4if`). Today it has no battle ability at all. It gets a heal first,
then the rest of its kit with the others.

**Enemies use skills too** (owner ruling, 2026-09-23). They keep telegraphing their big hits, and
enemy Knights gain one, so the heroes have something to answer. Enemies do not use the general
pool.

> ⚠️ **PROVISIONAL** — every skill number, the reaction delay, the ability lock and the drop rates
> are unfelt · **Settled by:** a played build of `ig-gy0`'s first kit slice, then its balance
> pass.

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

**2026-09-24:** § Direction (owner, 2026-09-24), at the top of this file, is the current
direction. This section records how the town and combat got here, and it still specs them.

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
- **Next: you build the town.** You place houses and workplaces, and your heroes work them. See
  § The town builder, below (`ig-6m2`, owner direction 2026-09-23).

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
- **Research.** The owner parked "research skills" for the town builder on 2026-09-23. It has no
  system today, and it gets none in this pass.

The numbers are in `SYSTEMS.md` § Keepers and professions.

**Where skills come from: born + practice.** Owner, 2026-09-23: "Born + practice. The calling is an
immense xp boost, like the progression system in rim world. Also only the ones with calling can make
masterwork(the final tier) equips/food/etc".

- **Born: two passions, rolled once.** Owner, 2026-09-23: "I like the rimworld inspired multi
  passion idea." Every hero is born with two passions: two different professions out of the eight
  (the five hall professions plus the town builder's woodcutting, mining and farming), picked at
  random when the hero is created. This replaces the single calling. The roll ignores rank and
  archetype, on purpose. An F-rank Knight can be a born smith, and an SS Mage can be useless at the
  Forge. Dupes of one definition roll separately, so two copies of the same hero are not
  interchangeable.
- **Practice: XP from working.** A hero earns XP in its job's profession by working there while you
  play. XP only builds up during live play, on the same clock that ages recovery caches. It never
  builds up while the game is closed (§ Hard constraints).
- **A passion is a huge XP boost,** as in RimWorld. A hero learns its two passions several times
  faster than anything else. Every hero can reach the top skill level in every profession; a born
  smith just gets there in a fraction of the time.
- **Only a born master makes masterwork.** Masterwork is the top tier of a profession's output
  (below). It needs a hero with a passion for that profession, at the top skill level. A hero who
  learned the trade without the passion gets the full skill bonus, but never masterwork. A hero can
  master both of its passions.
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
| Woodcutting, mining, farming | Wood, stone and food for the town (`ig-6m2`) | None. Skill bonus only. | — |

The Forge row changes today's game. A level-5 Forge enhances to +15 on its own today. After this, it
stops at +12 unless a born master smith is home at the Forge. Gear already past +12 keeps its
level: the gate limits gaining a level, not keeping one. This is the owner's rule applied to the
one output tier the Forge has.

**The Rites gate touches the spine, and the owner chose it knowingly (2026-09-23).** The designer
and the director both recommended against it. An SSS hero is the game's long-term goal (§ Win and
loss). From now on, the last step to it needs a born master priest: a hero with a Rites passion,
at skill 5, stationed at the Sanctum and home when you press rank-up. Heroes already at SSS keep
their rank.

- **The risk.** Your master priest can die on an expedition, or you can feed away every hero born
  for Rites. Either way, your SS hero cannot finish until you raise another master. The essence you
  saved is not lost, but the goal is on hold.
- **The way out is a delay, never a dead end.** One hero in four has a Rites passion, whatever its
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
  passion pulls the other way. That F-rank Knight is 10 Essence in the Sanctum, or your Forge's
  future master. Both answers should hurt.

**A keeper can be your body.** Walking as a keeper does not stop its work, because the body is at
home. While you are that hero, its counter stands empty. The body rules still apply: you cannot
dispatch the hero you are in.

**Any hero can run any shop.** The owner, 2026-09-23: "It can be anyone. I intend any hero to be
able to be able to run any shop pretty much." Stationing checks no passion. A passion only makes a hero learn
four times faster and lets it make masterwork. The two places where "anyone" stops are the ones the
owner ruled the same day: masterwork (including the Forge's +13 to +15 and SS→SSS) needs a born
master, and the Summoning Circle and the Town Gate take no keeper.

**How this feeds the town builder.** A keeper's station is the first kind of town job. The town
builder (§ The town builder, below) adds workplaces with worker slots, and a worker's job uses the
same field. The town still has no NPCs: every worker is a roster hero.

**Owner rulings on staffing, 2026-09-23.**

- Keepers can be sent out, and death erases the skill.
- Skill is born + practice, and masterwork is reserved to a passion (two passions per hero, ruled later the same day).
- The Forge's +13 to +15 band needs a master smith who is home.
- Masterwork draughts are built now, after the keeper bonuses (`DECISIONS.md` 2026-09-23,
  masterwork draughts).
- SS→SSS needs a master priest.
- Any hero can run any shop.
- Research is parked for the town builder.

> ⚠️ **PROVISIONAL** — masterwork draughts have never been played. They heal or revive for more,
> cost more, and are spent after the regular stock (`SYSTEMS.md`). Whether a stronger draught
> changes how raids feel, or only how often you craft, is unknown. · **Settled by:** a played build
> with masterwork draughts in a 30-hero raid.

> ⚠️ **PROVISIONAL** — whether the Rites gate feels like a fair delay or like a wall. The arithmetic
> says it costs nothing to a player who stations a Rites-born hero early, and at most about 75
> minutes plus a few pulls to one who loses theirs. Nobody has lost a master priest at SS yet.
> · **Settled by:** a played build that reaches SS→SSS, once with a master kept and once after
> losing one.

### The town builder — owner direction 2026-09-23 (`ig-6m2`)

The owner, 2026-09-23: "It can be anyone. I intend any hero to be able to be able to run any shop
pretty much. I also want the player to be able to build their own town, manage work, have the heros
have their own house, city management like the game banished".

**You build the town, and your heroes are its workforce.** You place buildings on a hex map, give
each working hero a house, and assign heroes to jobs. While you play, the town makes wood, then
stone and food, and those build more town. This is a gacha-hero game with a town layer, not a
Banished clone. The people come from the Summoning Circle, not from births. Every worker is a hero
you pulled and can lose.

- **Hexes.** The map is made of hexes because the art is: KayKit Medieval Hexagon, already
  downloaded and owner-approved, has hex tiles, houses, a lumbermill, a mine, a farm field and
  construction scaffolding. One building sits on one hex.
- **The seven hall buildings stay, one of each.** They are the Summoning Circle, Forge, Training
  Hall, Sanctum, Reliquary, Town Gate and Apothecary. Every profile starts with them standing, so
  the game works from the first minute. You can move them. You cannot build a second one: a second
  Forge would add nothing, because nothing a hall does is limited by how many you have. Their
  levels, panels and keepers are unchanged.
- **You place everything else.** First the House and the Lumbermill. A stone workplace and a farm
  come in later slices.
- **Houses.** A house holds one hero. A hero needs a house to work at a workplace. Fighters and
  fodder need none. Hall keepers need none for now (owner ruling, 2026-09-23). A house is also
  what makes a hero eat (below).
- **Work.** A workplace has worker slots, and you assign housed heroes to them. A hero has one job:
  a hall station or a workplace slot. Any hero can do any job. A worker is protected like a keeper,
  not busy: you can still send it out, and its job pauses while it is away.
- **What the town makes, and what it pays for.**
  - Wood builds houses and workplaces. Hall upgrades cost wood and stone on top of their parts, so
    stone is the town's link to the hero game (`SYSTEMS.md` § Town builder).
  - Food feeds housed heroes. Farms make it. In v1 it does not make draughts: they keep their parts
    cost, so a hungry town never also cuts the supplies that rescue heroes.
  - The first of each producer (Lumbermill, Mine, Farm) is free, so a town can never lock itself
    out of wood, stone or food.
  - **No iron.** Its only use would be making gear, which is a crafting tree, and § Scope boundaries
    excludes those. Gear stays loot plus parts.
  - **The town never makes Summon Stones, Essence or parts.** Expedition income and the ~327-pull
    claim in § Win and loss stay where they are.
    **Amended 2026-09-24 (§ Direction, ruling 2):** Founding and finished dreams will earn Essence
    (`ig-m6o.5`). Summon Stones and parts stay expedition-only.
- **Job skills.** The new jobs are professions too: woodcutting (Lumbermill), mining (Mine) and
  farming (Farm) join the five hall professions, so there are eight. A worker earns XP in its job
  like a keeper does, and a skilled worker makes more. Every hero is born with two passions out of
  the eight (§ Heroes staff the buildings).
- **Only while you play** (owner ruling, 2026-09-23). The town works on the same live clock as
  profession XP. Nothing is made, eaten or lost while the game is closed (§ Hard constraints).
  Changing that needs a `DECISIONS.md` entry, not a ticket.

**What we take from Banished, and what we skip.**

| We take | We skip, and why |
|---|---|
| Placing buildings on a map | Births, families and aging: the gacha is where people come from |
| Building costs material and time (scaffolding) | Seasons, winter and freezing: § Scope boundaries excludes weather and day/night |
| Workplaces with worker slots | Hauling and storage distance: one shared stockpile |
| A house for each worker | Roads as a requirement: roads are decoration |
| A stockpile and production rates | Health, happiness and disease: § Scope boundaries excludes morale and injuries |
| Food as the thing to manage, and starving to death | Trade, nomads, schools, and tool or clothing chains |

### Heroes eat, and can starve to death — owner ruling 2026-09-23

> "They eat and can starve to death." — the owner, choosing this over our recommendation (hunger
> only slows work) knowingly.

So the town is a second way to lose a hero. The rules below keep that fair: a starvation death is
never a surprise, and never happens while you are not looking.

- **Who eats.** Only housed heroes, and only while they are home. A hero away on an expedition, or
  busy in a battle, does not eat. Fighters and fodder have no house, so they never eat.
- **The escape hatch.** Unhousing a hero stops it eating. You can always shrink the town to fit the
  food.
- **The warning ladder.**
  1. **Food low** — under 10 minutes of eating left. The HUD shows a warning.
  2. **Starving** — food is 0. Work runs at half speed. The HUD names who dies next, and when.
  3. **Last warning** — 5 minutes before a death, the game stops the death clock and asks you to
     look. It does not start again until you do. Nobody starves while you are away from the keys.
  4. **A death** — one hero at a time. The first dies after 20 minutes of starving, then one every
     10 minutes while food stays at 0.
- **Who dies first.** The lowest rank, then the lowest level, then the newest in the roster.
- **Getting out resets the clock.** Once food climbs back above the "food low" line, the town
  starts over. Between 0 and that line the clock waits, so a farm that makes a little less than the
  town eats cannot hold the danger off forever.
- **The death is a real death.** It goes through `kill_hero()`, the one place a hero leaves the
  roster (`ARCHITECTURE.md` rule 8). Its gear goes back to your inventory first, so no Lost Cache
  appears in the town.
- **Never while the game is closed** (§ Hard constraints). The town runs only on the live clock.

> ⚠️ **PROVISIONAL** — the ladder's minutes, the eating rate and the farm rate are unfelt ·
> **Settled by:** a played build of the food slice (`ig-6m2.5`)

**The fodder tension grows.** Every worker is a hero you did not sacrifice. An F-rank worker costs
about 0.13 of a pull (`SYSTEMS.md` § Town builder), and now it eats too. That is the point: junk
heroes now have a job, and keeping them has a price.

"Defend the town against attack" (the old town bullet) stays later. It has no slice.

**Owner rulings, 2026-09-23 (`ig-6m2`).** A house is needed for a workplace job; fighters, fodder
and hall keepers need none. Heroes eat and can starve to death (above). Heroes have several
passions, RimWorld-style: two each, out of eight professions. The town runs only while you play.

> ⚠️ **PROVISIONAL** — every town number is unfelt · **Settled by:** a played build of the first
> slice (`ig-6m2.1`), and of the food slice (`ig-6m2.5`) for the hunger numbers.

### Earlier direction, recorded 2026-08-11

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

**Clarified 2026-09-23 (`ig-6m2`).** Town workers are roster heroes too, so "town NPCs" still holds.
"Day/night" and "weather" still hold, so the town builder has no seasons and nobody freezes.
Turning wood and stone into buildings is not a crafting tree.

**Amended 2026-09-24 (§ Direction).** The direction schedules several items on this list. Each
leaves the list only when its step's ticket is written, and not before:
- the pity system: beacon pity (`ig-m6o.4`)
- achievements: living deeds (`ig-m6o.4`)
- pets: monster pets
- seasons: the Winter of Names, and winter food pressure (`ig-m6o.5`, seasons only; day/night and
  weather stay out)
- morale: fear and informed refusals (`ig-m6o.3`)
- story/campaign: the Chronicle and the Guest's schemes (`ig-m6o.7`)
- non-roster people: homeland populations (`ig-m6o.4`)

Until then, the list binds implementers exactly as before.

**Excluded from the draft is not the same as excluded forever.** Hard constraints above is the
never list; this one is a *now* list. Direction above already names town NPCs as eventual, and
"not to be invented by an implementer" is what both readings have in common — a feature arrives
as a ticket, never as something that appeared while someone was building an adjacent thing.
