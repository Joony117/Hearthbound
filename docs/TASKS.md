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

**Status: complete except one manual step.** All four tickets are `[DONE]`; the automated
checklist rows pass from a real clean clone. The outstanding item is the human walkthrough of
the exported binary:

> Launch `export/game.exe` → Play → summon several heroes → send them out until one dies →
> quit, relaunch, confirm the dead hero is still gone → Escape → Return to Menu → Play again.

That is the Phase 1 exit gate. Nothing in Phase 2 should start before it passes, because every
Phase 2 ticket builds on the assumption that this loop actually runs in a packaged build.

---

## P1-01 — Project boots to a main menu and into the hub          [DONE]

Landed in `f62e545`. Import gate clean, `hub.tscn` headless smoke exit 0.

### Objective
Launching the game shows a main menu. Pressing Play loads a gray-box 3D hub. Escape opens a
pause menu that can return to the main menu.

### Existing architecture
Nothing exists yet. This ticket creates `project.godot` and the three autoloads.

- `SceneRouter` is the only thing permitted to change the main scene (`ARCHITECTURE.md` r5)
- `GameSession` holds the persistent player profile and must survive the scene change
- `SaveService` is created but does nothing beyond writing a `version` field this ticket

### Acceptance criteria
- `project.godot` pinned to Godot 4.7.1, main scene is `ui/main_menu.tscn`
- Exactly three autoloads registered: `SceneRouter`, `SaveService`, `GameSession`
- Main menu has Play and Quit; Play routes to `hub/hub.tscn`
- Hub is 3D: a ground plane and 3-5 labelled boxes standing in for buildings
- Escape in the hub opens a pause menu with Resume and Return to Menu
- Returning to menu and pressing Play again works repeatedly with no leaked state
- `--headless --quit` imports with zero script errors or warnings

### Files allowed to change
`project.godot`, `systems/`, `ui/main_menu.tscn`, `ui/pause_menu.tscn`, `hub/hub.tscn`,
`hub/hub.gd`, `game/`

### Non-goals
Settings menu, audio, transitions/fades, camera controls, save/load UI, any hero or gear
data, building interaction.

---

## P1-02 — Summon a hero into a visible roster                    [DONE]

Landed in `f62e545`. Roster survives save and reload — proved by
`tests/save_roundtrip_check.gd`, not by the import gate, which cannot see that boundary.

### Objective
A Summon button in the hub adds a hero to a roster list on screen.

### Existing architecture
- `GameSession` owns the roster array (P1-01)
- Hub scene exists with gray-box buildings (P1-01)
- No `HeroDefinition` Resource exists yet — **do not create one in this ticket**

### Acceptance criteria
- Summon button produces a hero with a name from a hardcoded array and `randi() % 8` rank
- Rank displays as `F D C B A S SS SSS`, not as an integer
- Roster list updates via signal, not by the button reaching into the list node
- Roster persists across a return-to-menu-and-back-to-hub cycle
- Roster survives save and reload through `SaveService`

### Files allowed to change
`hub/summon/`, `hub/roster/`, `heroes/hero.gd`, `systems/game_session.gd`,
`systems/save_service.gd`

### Non-goals
Weight tables, `HeroDefinition` Resources, hero stats, portraits, 3D hero models, summon
animation, currency cost, pity, dupes.

---

## P1-03 — Send a hero out; it lives or dies permanently          [DONE]

Landed in `f62e545`. `GameSession.kill_hero()` is the single deletion call site
(`ARCHITECTURE.md` r8); permadeath persisting across reload is covered by
`tests/save_roundtrip_check.gd`.

### Objective
Selecting a hero and pressing Expedition resolves a coin flip. On success the hero returns
and the result is shown. On failure the hero is **permanently deleted** from the roster.

### Existing architecture
- Roster lives in `GameSession`, rendered by the roster list (P1-02)
- Permadeath must be applied in exactly one place (`ARCHITECTURE.md` r8)
- This is the skeleton's win/loss state — checklist item 5

### Acceptance criteria
- Selecting a roster entry and pressing Expedition shows a result: survived or died
- On death the hero is removed from the roster and does not come back after save/reload
- Deletion happens in one function; no other file removes heroes from the roster
- Summoning again after a death works, and the roster stays consistent
- `--headless --quit` still imports clean

### Files allowed to change
`hub/expedition/`, `systems/game_session.gd`

### Non-goals
Combat of any kind, stats, waves, teams of 5, equipment, loot, XP, lost-gear caches,
recovery runs, zones, `CombatResult`, `quick_resolve.gd`.

---

## P1-04 — Export and clean-checkout gate                         [DONE]

Landed in `a8c5e47`. Verified from a real `git clone` into a temp directory: imports with
zero error/warning lines, and exports from the clone itself — `game.exe` (109,071,360 bytes)
plus `game.pck`. The exported binary launches headless with no script errors.

**One criterion remains manually unverified:** "the exported exe launches and the full
P1-01..03 flow works in it". Launching is proven; clicking through summon → expedition →
permadeath inside the packaged binary cannot be driven headlessly and is the human walkthrough
below. Do not read this ticket as evidence that it was checked.

### Objective
The project exports to a runnable Windows exe, and a fresh clone opens and runs.

### Acceptance criteria
- Export templates for 4.7.1 installed
- `export_presets.cfg` committed with a "Windows Desktop" preset
- `--export-release "Windows Desktop" export/game.exe` succeeds
- The exported exe launches and the full P1-01..03 flow works in it
- `git clone` into a temp directory opens in the editor with zero missing resources
- `export/` is gitignored; `export_presets.cfg` is not

### Files allowed to change
`export_presets.cfg`, `.gitignore`

### Non-goals
Icons, version metadata, code signing, installers, Steam integration, Linux/macOS presets.

---

# Phase 2 — Complete but ugly core loop

Backlog. **Deliberately not expanded into full tickets yet** — Phase 1 will teach us things
that change the wording, and writing eleven speculative contracts is exactly the premature
work this process exists to avoid.

Expand each into the full format when it comes up.

| # | Objective | Notes |
|---|---|---|
| P2-01 | `HeroDefinition` / `EquipmentDefinition` / `ZoneDefinition` Resources + `balance.tres` | 5 archetypes, 10 slots, 3 zones |
| P2-02 | Real summon against the weight table; roster and equip UI | Replaces P1-02 |
| P2-03 | `quick_resolve.gd` — waves, HP carry-forward, retreat threshold, permadeath | Replaces P1-03. **Add GUT here.** |
| P2-04 | Lost-gear caches on death + recovery expeditions with damage rolls and decay | |
| P2-05 | Salvage → parts → enhance → part conversion | Cores deferred to Phase 4 |
| P2-06 | Sacrifice → essence → rank up, with dupe resonance | |
| P2-07 | Five buildings as five integers | |
| P2-08 | Full save/load round-trip through `SaveService` | |
| P2b-01 | Minimum playable arena: capsules, WASD + mouse, one attack, one dodge, one enemy | Same `CombatResult` |
| P2b-02 | Controller input path for the arena | Hard constraint, not deferrable to Phase 5 |

**Phase 2 exit question:** is spending a hero's life a decision you actually feel? If not,
the fix is design, not code — and finding out here is much cheaper than after Phase 3.

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
cd /e/Game && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Export:

```bash
cd /e/Game && mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe
```

The `mkdir` is required — Godot does not create its own export directory, and `export/` is
gitignored, so a clean checkout hits this every time.
