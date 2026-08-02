# Infinite Gacha — repo rules

A Godot 4.7.1 GDScript game. `docs/` is the spec set and it is authoritative:
`GAME_SPEC.md` (what the game is) · `ARCHITECTURE.md` (the nine boundary rules) ·
`CODING_RULES.md` (how GDScript is written here) · `SYSTEMS.md` (the numbers) ·
`DECISIONS.md` (ADRs) · `TASKS.md` (tickets, and the delegation payload) ·
`KNOWN_ISSUES.md` (deliberate shortcuts).

**Inheritance.** The global routing rules in `~/.claude/CLAUDE.md` apply here unchanged —
cheapest-sufficient-path routing, the Codex tiers, `~/.claude/WORKER-CONTRACT.md`. This file adds
only what the global file says each repo must supply: the risky boundary and what BUILT means,
plus the doc-ownership table. It removes nothing.

## BUILT

```bash
cd /e/Game && powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1
```

Exit 0 with **zero script errors and zero warnings**. Warnings count — a shadowed variable or an
unused signal is how the next runtime failure gets introduced quietly.

**Run the script, not the engine directly.** `--headless --quit` on its own is not a gate: it
**exits 0 while printing script errors**. Measured on a fresh `git clone` of this repo — 8
`SCRIPT ERROR`/`ERROR:` lines including a failed autoload instantiation, process exit code **0**.
Any agent reporting BUILT off `$LASTEXITCODE` alone reports green on a project that does not load,
and every downstream `BUILT:` claim inherits it.

The script exists because the gate needs two things the raw command cannot give:

1. **It greps the output** and fails on `SCRIPT ERROR`/`ERROR:`/`WARNING` regardless of exit code.
2. **It warms the class cache first** (`--headless --import`, output printed but not asserted,
   then `--headless --quit` is the pass that gets checked). On a cold `.godot/` the global script
   class cache does not exist, so `Hero` and friends are unresolvable and the autoloads fail to
   compile — and `--quit` alone never rebuilds it, so a clean checkout stays red *permanently*
   rather than self-healing on the second run.

It also redirects `%APPDATA%` to a temp path for the duration, so running BUILT cannot mutate the
real `user://save.json`.

Use the `_console` binary. `Godot_v4.7.1-stable_win64.exe` detaches from the terminal and swallows
stdout, so a scripted run against it reports success no matter what happened
(`docs/KNOWN_ISSUES.md`). The script already does this; the note matters for ad-hoc runs.

`tools/` is gitignored, so the script's relative engine path only resolves in a checkout that
already has `tools/godot/` populated. A fresh clone has no engine binary at all.

**GUT is not installed yet, and BUILT does not require it until it is.** `addons/` does not
exist in this checkout; `docs/TASKS.md` P2-03 is the ticket that installs it, and installing a
test framework is a dependency addition needing director sign-off. Until then the gate above is
the whole of BUILT, and a worker that runs the GUT command will correctly find nothing — that is
the current state, not a defect in its change.

From **P2-03 onward**, BUILT also requires the GUT suite green:

```bash
cd /e/Game && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

## The risky boundary

No FFI here. The boundary is everything Godot resolves **at runtime**, where static typing catches
nothing and the failure surfaces on load rather than on import. A green import gate is not
evidence that any of the following still works.

A change touching any of these makes a `verifier` pass mandatory.

**1. Save round-trip.** `Hero.to_dict/from_dict` ↔ `GameSession.to_dict/from_dict`
(`systems/game_session.gd:31`) ↔ `SaveService` (`systems/save_service.gd`). A field written but
never read — or read under a different key — fails silently and the import gate stays green.
Acceptance for any state change is a real save/reload cycle, not a passing import. This is why
`docs/TASKS.md` puts "survives save and reload" in the ticket template.

**2. Scene ↔ script seam.** `%UniqueName` lookups, `[connection]` blocks inside `.tscn`, autoload
names in `project.godot`, `.gd.uid` pairs. Renaming a node or a `_on_*_pressed` handler is a
boundary change even though everything still compiles.

**3. Permadeath.** `GameSession.kill_hero()` (`systems/game_session.gd:26`) is the only call site
permitted to remove a hero from the roster (`ARCHITECTURE.md` r8). A second one is a bug
regardless of how correctly it behaves.

**4. Combat seam** (Phase 2+). Two independent implementations of
`resolve(team: Array[Hero], wave: Wave) -> CombatResult` that must agree. Deliberately two plain
functions — no base class, no registry (`DECISIONS.md`).

`Wave` is `zones/wave.gd`, a `RefCounted` derived from `ZoneDefinition`'s ramp — **not** a
`Definition`, and the rename off `WaveDefinition` is itself an ADR (`DECISIONS.md`, 2026-08-02).
The ramp interpolation must live in exactly one place and hand both implementations the same
`Wave` instance; re-deriving it per path is how the two quietly stop agreeing, which is the
failure this seam exists to prevent.

## Who owns what

Nothing edits a document it does not own.

| Change | Route to | Owns |
|---|---|---|
| Vague ask → ticket | `tech-lead` | `docs/TASKS.md` |
| Game numbers, feel, scope | `game-designer` | `docs/SYSTEMS.md`, `GAME_SPEC.md`, `KNOWN_ISSUES.md` **except** its `## Environment` section |
| Boundary moves, autoload count, ADRs | `godot-architect` | `docs/ARCHITECTURE.md`, `DECISIONS.md` |
| Code | global `implementer` → Codex | `*.gd`, `*.tscn`, `project.godot` |
| "How does X work", tracing a flow | global `researcher` | nothing — read-only |
| Gates and tests | `godot-tester` | `tests/`, gate runs, the `## Environment` section of `docs/KNOWN_ISSUES.md` |
| Post-boundary review | global `verifier` | nothing — read-only |

The four repo roles are additions, not replacements: global routing rule 3 (researcher for
questions, implementer for changes) and rule 4 (implementer **then** verifier on any
boundary-crossing change) apply here unchanged.

Codex workers additionally read `AGENTS.md`, which tightens the worker contract for this repo.

`KNOWN_ISSUES.md` is split on purpose. Its design shortcuts — placeholder systems, deferred
features, scope calls — are `game-designer`'s. Its `## Environment` section is `godot-tester`'s,
because the roles that *find* tooling facts are the ones that run the engine, and without this
they have nowhere legal to record them: a finding stranded in a return block is ephemeral, and
`.agent-results/` is gitignored. Both of those lose the knowledge.

## Marking provisional design

`docs/` states decisions, and some are far firmer than others — but a reader cannot tell which
by looking. A number that survived arithmetic verification reads identically to one nobody has
ever played against, and both read identically to a placeholder someone dropped in to make a
field non-zero.

Mark the soft ones:

```
> ⚠️ **PROVISIONAL** — <what is actually uncertain> · **Settled by:** <what would resolve it>
```

**The `Settled by` half is the point.** "Needs tuning" is not actionable. "Needs a played build"
and "needs Summon Stone income to exist first" tell the next reader whether this is resolvable at
a desk or not — which decides whether they can act on it now or must stop.

Two things earn the marker:

- **Unfelt** — arithmetically verified, never played. Most of `SYSTEMS.md`'s numbers are this.
- **Undefined** — named but carrying no value, or a placeholder standing in for one.

An ADR-backed decision is **not** provisional. Six hero stats, ten equipment slots, ranks F–SSS,
the three-autoload cap and the combat seam are settled; marking them dilutes the signal until
nobody reads it. Over-marking is the failure mode here, not under-marking.

Grep `PROVISIONAL` before treating any number as final, and before building a system that assumes
one holds.

## Reporting: what STATUS means

`STATUS: done` means **the problem in the task is solved**, not that the literal acceptance
criteria were satisfied. Those are not the same thing, and when they diverge the difference is
the most valuable thing in the return.

- **`done`** — the acceptance criteria are met *in the scenario that motivated them*. If you
  proved a behavior under conditions other than the ones the task was actually about, that is
  not `done`.
- **`partial`** — anything real is left over. Name what, specifically. This includes the case
  where **your own findings show the task's premise was wrong**: a task built on a mistaken
  assumption cannot be `done` even when you did everything it literally asked. Report the
  corrected premise and what it means for the acceptance criteria.
- **`blocked`** — you cannot proceed. State the single concrete thing that would unblock it.
- **`failed`** — you tried and it does not work. Name the first cause and stop.

`partial` with a precise account of the gap is worth more than `done`, and it is never treated
as a failure. `done` on work that a re-run does not reproduce is the one reporting outcome that
actually costs the project something, because it stops anyone looking again.

This binds every worker and subagent in this repo, and it is a tightening of the global
contract, not a replacement for it.

## Standing constraints

- **Three autoloads, hard cap**: `SceneRouter`, `SaveService`, `GameSession`. A fourth requires a
  `DECISIONS.md` entry and goes through `godot-architect` first. Autoloads hold no level state and
  are not where game rules live.
- **Stop rule.** After two or three failed patches on the same error, stop patching. That is a
  structural problem being treated as a syntax problem — reassess instead of trying a fourth
  (`docs/TASKS.md`).
- **Tickets, not feature names.** "Add an inventory system" hands an implementer dozens of
  architectural decisions. Route it through `tech-lead` first.
- Never edit `.godot/` or `tools/` — both gitignored, both engine-owned.
- `docs/` is the spec. If code and docs disagree, that is a finding, not something to silently
  reconcile in either direction.
- **One Godot process against this project at a time.** See below — this one is not obvious and
  has already bitten twice.

## Serialize engine access

**Never dispatch two agents that run Godot concurrently against `E:\Game`.** The director
serializes them, no exceptions.

This is not ordinary file-locking caution. The gates deliberately put the project into a broken
state as part of doing their job:

- `godot-tester` proving the import gate goes red **injects a bad type into a real `.gd` file**,
  runs, then restores it.
- Proving the cold-cache path **moves `.godot/` aside entirely**, so the class cache is absent.
- Both leave the tree correct at the end, and wrong in the middle.

Anything else touching the engine during that window sees the broken tree and believes it. An
export run concurrent with a red-proof packages a knowingly-broken build and reports exit 0.
A second process also races the first on `.godot/`, whose rebuild is not concurrency-safe.

Neither failure announces itself: you get a green result describing a state that never existed.

**What is safe in parallel:** agents whose bounds do not overlap and that do not run the engine
— a `docs/`-only writer alongside a `tests/` writer is fine, and was done here. Judge by whether
the engine gets invoked, not by whether the file lists collide.

Practically: when a dispatch will run BUILT, the export, or any `--headless` invocation, it gets
the engine to itself until it returns. Two Godot-touching agents in one message is a bug.

### Serena's LSP daemon is a fourth engine consumer

Serena's GDScript backend is an LSP **client**, not a server. It attaches to a running Godot
editor on `127.0.0.1:6005` (`.serena/project.yml` sets this; Serena's built-in default is Godot
3's 6008, which never connects). That daemon is a fourth thing running the engine against this
project — and the only *persistent* one, so it does not fit the "gets the engine to itself until
it returns" model above.

```bash
# start — verified: --headless --editor does serve the LSP
./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --editor --path E:/Game
# stop
Get-Process Godot* | Stop-Process -Force
```

The `_console` wrapper spawns `Godot_v4.7.1-stable_win64.exe`, and that child is what holds the
port — kill by name, not by the pid you launched.

**The daemon must already be listening when Serena's MCP server starts.** The connection is made
once, at project activation, and there is no retry: start the daemon afterwards and every
symbolic call fails for the rest of the session with a cached
`Could not connect to 127.0.0.1:6005 within 30.0s`. It returns *instantly*, which is how you tell
a cached failure from a real timeout. Reconnecting the MCP server is the only fix — waiting is
not one.

**Serena up and BUILT are mutually exclusive.** `tests/import_gate.ps1` aborts with exit 1 when
6005 is listening rather than racing the daemon on `.godot/`, whose rebuild is not
concurrency-safe. So a session runs one way or the other:

> daemon up → start Claude Code → symbolic work → stop daemon → run the gate

After that stop, Serena stays dead until the next session. That is the design, not a fault.
`godot-tester` and any dispatch that runs BUILT, GUT, or the export therefore never get Serena
tools — the daemon must be down for their whole window.

Codex workers never see Serena; they read `AGENTS.md`, which needs no change for any of this.

## Export

```bash
cd /e/Game && mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe
```

**The `mkdir` is not optional.** Godot's exporter does not create its own output directory — it
fails with `Prepare Template: The given export path doesn't exist.` and exit 1. `export/` is
gitignored, so this bites every clean checkout and every CI run, not just the first one.

Templates for 4.7.1 are installed. Produces `export/game.exe` (~109 MB) plus `game.pck`.
