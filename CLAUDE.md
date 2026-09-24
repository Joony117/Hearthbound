# Infinite Gacha — repo rules

A Godot 4.7.1 GDScript game. `docs/` is the spec set and it is authoritative:
`GAME_SPEC.md` (what the game is) · `ARCHITECTURE.md` (the nine boundary rules) ·
`CODING_RULES.md` (how GDScript is written here) · `SYSTEMS.md` (the numbers) ·
`DECISIONS.md` (ADRs) · `TASKS.md` (ticket format, split reasoning, shipped bodies, findings) ·
`KNOWN_ISSUES.md` (deliberate shortcuts).

**The live backlog is Beads (`bd`), not `docs/TASKS.md`.** Start a session with `bd ready`;
`bd blocked` says what is waiting and on what. `docs/TASKS.md` was retired as a backlog on
2026-09-04 — its `[TODO]`/`[DONE]`/`[BLOCKED]` markers are frozen history, and status,
priority and dependencies now live only in `bd`. It stays authoritative for everything else
it holds, including findings later work inherits. Beads points there for bodies; it points to
Beads for status.

`docs/TASKS-DONE.md` is **archive, not spec** — 78 shipped ticket bodies, ~18k tokens, append-only.
Grep it; never read it into context. Nothing in the live workflow depends on it.

**Inheritance.** The global routing rules in `~/.claude/CLAUDE.md` apply here unchanged —
cheapest-sufficient-path routing, the Codex tiers, `~/.claude/WORKER-CONTRACT.md`. This file adds
only what the global file says each repo must supply: the risky boundary and what BUILT means,
plus the doc-ownership table. It removes nothing.

**Panther relay.** Chapman's Panther AI (LibreChat, unlimited Sonnet 4.6 and GPT-5.2) is available
as a manual worker and displaces most rung-2 Codex dispatch. `panther/README.md` has the loop; the
rule that makes it worth doing is that **source file contents never enter the director's context**
— the director writes a brief naming files, the user carries the files, and only the returned edit
blocks come back. Panther has no shell and no engine, so `BUILT` and `VERIFIED` stay with the
director; a Panther reply claiming either is fabricated and gets rejected whole.

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

**GUT 9.7.1 is installed** under `addons/gut/`, committed and not gitignored. It landed ahead of
`docs/TASKS.md` P2-03 rather than as part of it. See `docs/KNOWN_ISSUES.md` for why the suite
lives in `tests/unit/` and not `tests/`.

> The sentence that used to follow here claimed `P2-03` was still `TODO` and still owed the
> first real combat tests. That was stale on both halves — `P2-03a` through `P2-03f` have all
> landed, and `tests/unit/` now runs 148 tests including `test_arena.gd`. No bead was filed for
> it because there is no work left in it.

BUILT therefore also requires the GUT suite green:

```bash
cd /e/Game && APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

**The `APPDATA=` prefix is not optional.** Without it the suite overwrites the owner's real
`user://save.json` with a test roster (`docs/KNOWN_ISSUES.md`), and two runs share one save file,
so a concurrent run shows up as a "flake" in `test_save_service.gd` (`ig-8lj`). This command
shipped here without the prefix until 2026-09-23. Verified that day: the real save's mtime did not
change across a redirected full run.

## The risky boundary

No FFI here. The boundary is everything Godot resolves **at runtime**, where static typing catches
nothing and the failure surfaces on load rather than on import. A green import gate is not
evidence that any of the following still works.

A change touching any of these makes a `verifier` pass mandatory.

**The adversarial reviewer here is GPT-6 Sol**:
`codex-worker.ps1 -Profile verifier -Effort high` (owner, 2026-09-23). Claude writes most of this
repo, and a Claude reviewer shares Claude's blind spots. Brief it read-only with no Godot runs, so it can
review while another worker holds the engine. Fall back to a Claude `verifier-hard`
only when the wrapper is down or out of quota, and say so in the bead. Codex-authored work goes
the other way: it gets a Claude reviewer.

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

**This table assigns judgment, not dispatch.** It says whose call a change is — not that a
subagent must be spawned to type it. Markdown is rung 1 of the global ladder at any size: the
director writes it directly. Route to a role when you actually need its *judgment* — a balance
number that does not exist, a boundary call, a vague ask that needs scoping — then apply the
answer yourself. Spawning a role to perform an edit you already know how to make costs a
15–25k cold start and buys nothing.

| Change | Route to | Owns |
|---|---|---|
| Vague ask → ticket | `tech-lead` | the bead (`bd create`), plus its body in `docs/TASKS.md` when the body is long enough to want the full format |
| Game numbers, feel, scope | `game-designer` | `docs/SYSTEMS.md`, `GAME_SPEC.md`, `KNOWN_ISSUES.md` **except** its `## Environment` section |
| Boundary moves, autoload count, ADRs | `godot-architect` | `docs/ARCHITECTURE.md`, `DECISIONS.md` |
| Code | global `implementer` → Codex | `*.gd`, `*.tscn`, `project.godot` |
| "How does X work", tracing a flow | global `researcher` | nothing — read-only |
| Gates and tests | `godot-tester` | `tests/`, gate runs, the `## Environment` section of `docs/KNOWN_ISSUES.md` |
| Post-boundary review | GPT-6 Sol (`codex-worker.ps1 -Profile verifier -Effort high`); Claude `verifier-hard` as fallback | nothing — read-only |

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
- **One ticket per session, then `/clear`.** `bd ready` then `bd show <id>` reloads a cold
  session's ticket in two commands, and each bead's description carries enough to act without
  this conversation. The spec set exists to make sessions disposable; use it that way. (Why
  this pays, with the measured numbers: `~/.claude/CLAUDE.md`, Session economics.)

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

### Reap what you start

"Until it returns" only holds if the process actually ends when the agent does. Anything that
starts a Godot process kills it before returning, and **checks rather than assumes** —
`Get-Process Godot*` must come back empty. A hung `--headless -s <script>` run is
indistinguishable from a finished one at the call site, which is exactly how this has leaked
twice: once as two processes that outlived a subagent by hours, once as a daemon nobody
remembered starting. Kill by name, since the `_console` wrapper spawns a differently-named child.

The cost of a leak lands on someone else. The gate aborts on any process running from
`tools/godot/`, so a leaked process turns into the next agent's red gate with no obvious cause —
and before that check existed, it was a silent `.godot/` race instead. This binds subagents and
the director equally; the same rule is in `AGENTS.md` for Codex workers.

Engine state is also **not stable across turns**. A "daemon is down" claim in a dispatch prompt
describes when it was written, not when the agent reads it. Re-verify at the point of use.

### A running Godot editor also counts

`tests/import_gate.ps1` aborts with exit 1 if a Godot editor is listening on `127.0.0.1:6005`,
rather than racing it on `.godot/`. Nothing in the workflow starts one now, so a red gate with
that message means a stray editor is up — `Get-Process Godot* | Stop-Process -Force`, then re-run.

## Parallel worker sessions

The owner may run one director session plus peer Claude Desktop sessions as workers. `ListAgents`
shows them; message them with `SendMessage`. **Only sessions whose name ends in `game` work this
repo** — the rest belong to other repos and are never dispatched from here. Names read
`<model>::<effort> <n> game`: `extra` gets reviews and hard calls, `high` gets implementation,
`medium` gets small bounded jobs (docs moves, lookups). Re-run `ListAgents` before dispatching;
the roster changes. Workers must run the director's permission mode, or every message waits for
the owner's approval and expires unread.

The worktree is **shared**, which tightens the engine rule above: a worker's half-written `.gd`
turns another worker's gate red. So parallel code writers are only safe when at most one of them
runs the engine and the other's edits cannot break the import. When in doubt, sequence them.
Worker reports are input, not verification — the director re-runs BUILT before closing a bead.

## Export

```bash
cd /e/Game && mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe
```

**The `mkdir` is not optional.** Godot's exporter does not create its own output directory — it
fails with `Prepare Template: The given export path doesn't exist.` and exit 1. `export/` is
gitignored, so this bites every clean checkout and every CI run, not just the first one.

Templates for 4.7.1 are installed. Produces `export/game.exe` (~109 MB) plus `game.pck`.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
