# Known Issues

Deferred bugs, deliberate shortcuts, and things that will bite later. Harvested partly from
`ponytail:` comments in the source.

An entry here is a *decision to defer*, not a bug report. Anything that should be fixed now
belongs in `TASKS.md` instead.

---

## Deliberate shortcuts

### Phase 1 summon is not the real summon
`randi() % 8` for rank, name from a hardcoded array. No weight table, no definitions.
**Replaced in:** Phase 2, ticket P2-02.

### Phase 1 expedition is a coin flip
No combat, no stats, no waves. Its only job is proving the scene chain and the permadeath
deletion path work end to end.
**Replaced in:** Phase 2, ticket P2-03.

### No save migration
`SaveService` writes a `version` field from the first commit but does nothing with it. A save
from an older build will load into a newer one and may produce garbage.
**Fix in:** Phase 5.

### No GUT until Phase 2
There is no logic worth testing in the walking skeleton. Verification for Phase 1 is manual
plus a clean headless import.
**Fix in:** Phase 2, step 3.

---

## Open questions

### Does spending a hero's life actually feel like something?
The Phase 2 exit question, and the only one that matters. If the answer is no, the fix is
design, not code. Findings go in `DECISIONS.md`.

### Quick resolve and the arena will disagree
A statistical resolver and a real-time arena will not produce the same outcomes for the same
team and wave. Some divergence is acceptable — the quick path is a convenience. How much is
acceptable is unknown until both exist.
**Revisit in:** Phase 3.

### Controller support is a hard constraint but unimplemented
`GAME_SPEC.md` requires gamepad as a first-class input path for the arena. Nothing in Phase 1
addresses it. It must land with the arena in Phase 2b, not be deferred to Phase 5.

---

## Environment

### Export templates not yet installed
`--export-release` fails until the 4.7.1 templates are downloaded via
*Editor → Manage Export Templates* (~1 GB). Blocks Phase 1 checklist item 7.

### Console binary required for CLI
`tools/godot/Godot_v4.7.1-stable_win64.exe` detaches from the terminal and swallows stdout.
Always use `Godot_v4.7.1-stable_win64_console.exe` for headless and scripted runs.
