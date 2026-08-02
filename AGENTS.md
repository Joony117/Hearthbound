# Worker rules — Infinite Gacha

Extends `C:\Users\Joony\.claude\WORKER-CONTRACT.md`. This file adds fields and tightens
constraints; it removes nothing. Where the two conflict, the stricter verification requirement
wins.

Read `CLAUDE.md` for the risky boundary and what BUILT means here, and `docs/CODING_RULES.md` for
the full convention set. What follows is only what bites most often.

## Before you write anything

`docs/` is the spec. `ARCHITECTURE.md` has nine numbered boundary rules that the existing code
cites by number in its comments — match that. `SYSTEMS.md` holds every balance number; do not
invent one that is already written down, and do not change one that is.

The scope you were given names the files you may change. `docs/TASKS.md` tickets carry an explicit
**Non-goals** list — those adjacent features are not yours to invent, however obvious they look
while you are in there.

## GDScript

- **Static typing is mandatory** on every variable, parameter, and return. `Variant` requires a
  comment justifying it.
- Definitions are `Resource` with exported fields; runtime instances are `Node` or `RefCounted`.
  Prefer one Resource with exported fields over N subclasses.
- Game rules are **static functions taking arguments**, never methods on an autoload. An autoload
  exists to outlive a scene change, not to accumulate behavior.
- `snake_case` files and functions, `PascalCase` for `class_name` and scene nodes, `_` prefix for
  private, `CONSTANT_CASE` for constants, past tense for signals (`hero_died`).
- Signals over `get_node("../../..")`. Scene-unique `%Name` over node paths.
- Comments explain **why**. A deliberate shortcut gets a `ponytail:` comment naming the ceiling
  and the upgrade path — three files already do this; match their shape.
- Validate at trust boundaries, `assert()` internally, never silently swallow a failed load.

## Do not

- Add an autoload. Three is a hard cap and a fourth needs an ADR first.
- Add a hero stat. Six is a hard cap (`DECISIONS.md`).
- Edit `.godot/` or `tools/` — engine-owned, gitignored.
- Hand-edit a `.gd.uid`. Godot owns those; let it regenerate them.
- Reach into a `.tscn` to rename a node or a signal handler without saying so under `DECISIONS` —
  that seam resolves at runtime and nothing will catch the break.

## Evidence

`BUILT` is `tests/import_gate.ps1`, not a raw engine call. Run the script.

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\import_gate.ps1
```

`--headless --quit` on its own **exits 0 while printing script errors** — measured on a fresh
clone of this repo: 8 error lines, exit code 0. Judging BUILT by exit code alone reports green on
a project that does not load. The script greps the output and warms the class cache first; read
the BUILT section of `CLAUDE.md` before you reach for the engine directly.

The plain `Godot_v4.7.1-stable_win64.exe` detaches and swallows stdout, so a run against it proves
nothing regardless of what it printed. Always `_console`.

Zero warnings, not just zero errors.

## STATUS

`done` means the **problem is solved**, not that the literal acceptance criteria were satisfied.
When those diverge, the difference is the most valuable thing you can report.

If your own findings show the task's premise was wrong, the correct status is `partial` with the
corrected premise — not `done` because you did what was literally asked. `partial` naming a
precise gap is never treated as a failure. `done` on work a re-run does not reproduce is, because
it stops anyone looking again.

Full definitions are in `CLAUDE.md` under "Reporting: what STATUS means" and they bind you.

If your change touches the save round-trip, the import gate does not cover it — say so under
`UNRESOLVED` unless you actually drove a save and a reload.

Logs go to `.agent-results/logs/` under the repo root (gitignored). Not to a temp directory — the
manager reads them after you exit.
