# Infinite Gacha — repo rules

Godot 4.7.1 GDScript game. Global rules (`~/.claude/CLAUDE.md`) apply; this file adds what is repo-specific.

## Where things live

- `docs/` is the spec, and it is authoritative: `GAME_SPEC` (what the game is), `ARCHITECTURE` (the boundary
  rules), `CODING_RULES`, `SYSTEMS` (the numbers), `DECISIONS` (ADRs), `KNOWN_ISSUES` (deliberate
  shortcuts). If code and docs disagree, that is a finding. Don't quietly reconcile it either way.
- The backlog is Beads (`bd ready`). `docs/TASKS.md` status markers are frozen history, but its
  bodies and findings still count. `docs/TASKS-DONE.md` is an archive: grep it, never read it whole.
- Never edit `.godot/` or `tools/`. Both are engine-owned and gitignored.
- Grep `PROVISIONAL` before treating a number as final. To mark a soft number:
  `> ⚠️ **PROVISIONAL** — <what is uncertain> · **Settled by:** <what would resolve it>`.
  Don't mark ADR-backed decisions.

## BUILT = both green

```bash
cd /e/Game && powershell -NoProfile -ExecutionPolicy Bypass -File tests/import_gate.ps1
cd /e/Game && APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

- The gate needs exit 0 with zero errors AND zero warnings. Never use bare `--headless --quit`: it exits 0 on
  script errors. The script greps the output and warms the class cache first.
- The `APPDATA=` prefix is mandatory. Without it, GUT overwrites the owner's real save.
- Use the `_console` binary. The plain exe swallows stdout and always looks green.
- The director re-runs BUILT before any commit or bead close. A worker's report is not verification.

Export: `mkdir -p export && ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --export-release "Windows Desktop" export/game.exe`
(the exporter won't create the directory).

## Engine: one Godot at a time

- Never run two Godot processes against this repo. Gates break the tree on purpose mid-run, so a
  second process sees a broken tree and reports it green.
- Whoever starts Godot reaps it: `Get-Process Godot* | Stop-Process -Force`, then check that the count is 0.
  A leaked process turns the next gate red. An open editor (port 6005) also blocks the gate.
- The worktree is shared. Parallel writers are safe only if at most one runs the engine and the
  other's edits can't break the import.

## Risky boundaries: review mandatory

Godot resolves these at runtime, so a green gate proves nothing about them:

1. **Save round-trip.** `Hero`/`GameSession` `to_dict`/`from_dict` ↔ `SaveService`. Acceptance is a
   real save and reload through disk, plus a legacy save that is missing the new field.
2. **Scene ↔ script seam.** `%UniqueName`, `.tscn` connections, autoload names, `.gd.uid` pairs.
3. **Permadeath.** `GameSession.kill_hero()` is the only place allowed to remove a hero from the roster.
4. **Combat seam.** Both `resolve(team, wave)` implementations must agree, and both get the same `Wave`
   (`zones/wave.gd`), whose ramp lives in one place.

The reviewer is **GPT-6 Sol**: `codex-worker.ps1 -Profile verifier -Effort high`. Brief it
read-only, with no Godot runs. Fall back to a Claude `verifier-hard` only if Sol is down, and say so in the bead.
Codex-written work gets a Claude reviewer.

## Standing constraints

- **Three autoloads, hard cap:** `SceneRouter`, `SaveService`, `GameSession`. A fourth needs an ADR first.
  Autoloads hold no level state and no game rules.
- **Stop rule:** after 2-3 failed patches on the same error, stop and rethink the structure.
- **Vague feature asks** ("add inventory") become a scoped bead before any code.
- **Doc ownership** (whose judgment, not who types): numbers and scope → `game-designer`
  (`SYSTEMS`, `GAME_SPEC`, `KNOWN_ISSUES`); boundaries and ADRs → `godot-architect`
  (`ARCHITECTURE`, `DECISIONS`); tests and gates → `godot-tester` (`tests/`, the `## Environment` section of `KNOWN_ISSUES`).

## Workers

- Peer sessions: only names ending in `game` work this repo. `extra` = reviews and hard calls,
  `high` = implementation, `medium` = small jobs. Re-run `ListAgents` before dispatching.
- Panther relay (manual, no shell): see `panther/README.md`. Any BUILT or VERIFIED claim from it is rejected.
- STATUS: `done` = the motivating problem is solved. `partial` = name what's left, including a wrong
  premise. `blocked` = the one thing that would unblock it. `failed` = the first cause.
