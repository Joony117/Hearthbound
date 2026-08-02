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
  (WASD + mouse aim, attack, dodge); AI runs the other four. Permadeath applies identically
  in both paths.

The arena is the selling point. Quick resolve is what makes grinding tolerable.

---

## Scope boundaries for the draft

Explicitly **not** in the rough draft, and not to be invented by an implementer:

story/campaign, dialogue, town NPCs, crafting trees, gear set bonuses, hero injuries or
morale, pity system, achievements, difficulty settings, procedural dungeon generation,
day/night, weather, mounts, pets, guilds.
