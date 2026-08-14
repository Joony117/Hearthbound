# Game Spec

Working title: **Infinite Gacha**

This is the stable reference for what the game is. If a proposed change contradicts this
document, the document wins or the document gets amended — not silently reinterpreted.

---

## Player fantasy

You are a summoner running a mercenary hall. **You never fight as yourself.**

You pull heroes out of a gacha, gear them, and send them into dungeons to die. Progress is
bought with lives: fodder heroes are fed to good ones to rank them up, and the gear of the
dead is left in the dungeon until someone goes back for it.

The feeling being engineered is **attachment vs. expendability**. Every hero is
simultaneously an investment you've poured materials into and raw material for a better one.
The game is working when deciding whose life to spend is uncomfortable.

Inspired by the manhwa *Pick Me Up, Infinite Gacha*.

---

## Core loop

1. **Summon** heroes with Summon Stones. Rank F → SSS, weighted heavily toward junk.
2. **Gear** them from 10 equipment slots, also ranked F → SSS.
3. **Send** a team of up to 5 into a zone.
4. **They return with levels, equipment, and materials — or they don't return.**
   Death is permanent. The dead hero's equipment stays in the dungeon as a recoverable cache.
5. **Salvage** unwanted gear into parts; **enhance** the gear worth keeping.
   **Sacrifice** fodder heroes into a keeper to push its rank up.
6. **Push** a harder zone. Repeat.

Recovery expeditions are a parallel branch of step 3: low-power runs that go fetch a dead
hero's gear before the cache decays.

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
any buildings are built.

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
- **No real-money monetization.** No wall-clock timers, no energy, no offline accrual. The
  gacha is a game mechanic, not a storefront.
- **Controller support required.** Real-time action combat means gamepad is a first-class
  input path, not an afterthought bolted on in Phase 5.
- **60 FPS** with 5 heroes and ~20 enemies active on mid-range hardware.
- **Save system required**, human-readable, versioned from the first commit.
- **Instant / turn-based hub.** Actions resolve when the player presses the button. There is
  no clock running when the game is closed.

---

## Combat model

Two resolution paths behind one seam. Both take `(team, wave)` and return a `CombatResult`,
and nothing upstream can tell them apart.

- **Quick resolve** — statistical. The "skip" button for farming zones you've already
  cleared.
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

**Excluded from the draft is not the same as excluded forever.** Hard constraints above is the
never list; this one is a *now* list. Direction above already names town NPCs as eventual, and
"not to be invented by an implementer" is what both readings have in common — a feature arrives
as a ticket, never as something that appeared while someone was building an adjacent thing.
