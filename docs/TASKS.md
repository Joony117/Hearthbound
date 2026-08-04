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

| # | Objective | Notes |
|---|---|---|
| P2-01a | `HeroDefinition` Resource + 5 archetypes authored | Body in `TASKS-DONE.md`. Start here — unblocks P2-02. |
| P2-01b | `ZoneDefinition` Resource + 3 zones authored | Body in `TASKS-DONE.md`. Unblocks P2-03a. |
| P2-01c | `EquipmentDefinition` Resource + 10-slot enum | Needed before P2-04 (lost-gear caches); no item instances authored yet — no loot table exists before P2-04. |
| P2-01d | `BalanceTable` Resource + `balance.tres` authored from `SYSTEMS.md` | Body in `TASKS-DONE.md`. Container shape is settled (`DECISIONS.md`, one `BalanceTable`). Needed before P2-02 can consume real summon weights — sequence before or alongside P2-02, not after. Did **not** move `Hero.RANK_NAMES` — split out as `P2-01d-2`. |
| P2-01d-2 | Move `Hero.RANK_NAMES` onto `BalanceTable`; repair its three call sites; author the Summoning Circle's two-field schema | Body in `TASKS-DONE.md`. Unblocked by `godot-architect`'s ruling on reaching shared Resources without a fourth autoload. Not required before P2-02 — P2-02 already replaces `hub/summon/summon.gd` wholesale and can read a rank count off `BalanceTable`'s rank table directly, so this can trail P2-02 instead of gating it. |
| P2-02 | Real weighted summon against `BALANCE.summon_weights`; roster displays hero archetype | Replaces P1-02. Body in `TASKS-DONE.md`. Carries the `def_id` → `HeroDefinition` lookup — `godot-architect` returned `cannot-judge` on this seam because no lookup consumer exists yet, but named this the ticket that builds one. A `def_id` matching no `HeroDefinition` must fail loudly, not silently default (`CODING_RULES.md:121-122`). Equip UI moved out — nothing is equippable yet; see `P2-05a`. |
| P2-03a | `Wave` construction (ramp interpolation) + computed hero stats | Body in `TASKS-DONE.md`. Not player-facing by itself, same shape as `P2-01a`/`P2-01b`/`P2-01d`. Unblocks P2-03b. Start here. |
| P2-03b | `combat/quick_resolve.gd` + `CombatResult` — real waves, HP carry-forward, retreat threshold, permadeath | Replaces P1-03. Body in `TASKS-DONE.md`. GUT 9.7.1 is already installed (`addons/gut/`) — this is the first ticket to add real coverage under `tests/unit/`, not a framework install; the original backlog line's "Add GUT here" is stale. |
| P2-03c | Expedition setup UI — multi-hero squad select + zone select | `P2-03b` deliberately hardcodes a **one-hero team and Verdant Outskirts**, because `hub.gd`'s roster list is single-select and no zone-selection UI exists. `SYSTEMS.md` specifies up to five heroes per expedition across three authored zones, so that narrowing leaves two-thirds of the designed expedition setup unbuilt. Recorded here so it stays visible: `P2-03b`'s Non-goals name this as a follow-up ticket, and a follow-up nobody wrote down is how a temporary hardcode becomes permanent. |
| P2-04 | Lost-gear caches on death + recovery expeditions with damage rolls and decay | |
| P2-04a | XP-per-level curve for expedition rewards | Found by `game-designer`, deliberately not authored by it — a genuine missing `balance.tres` input with no ticket owning it yet. Crosses into expedition-reward territory, so it sequences here, not in the P2-01 group. |
| P2-05 | Salvage → parts → enhance → part conversion | Cores deferred to Phase 4 |
| P2-05a | Equip UI for authored equipment | Sequences after `P2-05` — needs item instances to exist before a hero has anything to equip. Split out of `P2-02`'s original backlog line, which named equip UI before equipment, loot, or item instances existed. |
| P2-06 | Sacrifice → essence → rank up, with dupe resonance | |
| P2-07 | Five buildings as five integers | |
| P2-08 | Full save/load round-trip through `SaveService` | |
| P2-09 | Summon Stone income rate — how a player actually acquires stones | Found by `game-designer`, deliberately not authored by it — a design input, not a Resource-authoring task. Nothing defines acquisition rate today, which makes the verified ~327-pull spine number unvalidatable against real play time: the ratio is sound, the pacing is unknowable without this. Needed before the Phase 2 exit question below can be honestly answered. |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3. (See
P2-09 — that question can't be honestly answered until stone income rate is defined.)

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
