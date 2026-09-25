# Stage saves

Made by `tests/stages/stage_bot.gd` (SYSTEMS.md § Stage saves, `ig-eek`). Each stage folder holds the
save (`save.json`, `ledger.jsonl`) and the bot's run log (`run.log`). Keep them; remake one only on
purpose (SYSTEMS lists when). `tests/unit/test_stage_saves.gd` loads them, and
`playtest/play-<stage>.cmd` plays them.

| Stage | HEAD | Seed N | Step | Wall time | Game clock reached |
|---|---|---|---|---|---|
| early | d0a0ad0 + the ig-eek bot | 1 | 5.0 s | 5.3 s | 7200 s (2 h) |
