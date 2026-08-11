# Panther relay

Chapman's Panther AI (LibreChat 0.8.6) gives unlimited Sonnet 4.6 and GPT-5.2. It has file
upload and saved agents, no API key. This directory is the manual relay that offloads code
generation and review onto it.

## Why the relay is shaped this way

Cost in a Claude Code session is dominated by re-reading context, not by producing it —
measured on this account, 367M cache-read tokens against 605K of tool output. So the offload
only pays if **source files never enter the director's context**. The director writing a file
into a prompt has already paid the bill Panther was supposed to save.

Hence: the user pilots the file transfer. The director writes a brief naming files, never
their contents, and reads back only the returned edit blocks — a fraction of the tokens the
files themselves would cost.

The trade-off is explicit: the director reviews the change without the surrounding code. It
catches a bad edit but not "this duplicates a helper three files over." The gate and the
reviewer agent cover that gap.

## One-time setup

Create three LibreChat agents from `AGENT-IMPLEMENTER.md` and `AGENT-REVIEWER.md` — one
implementer on Sonnet 4.6, two reviewers (one Sonnet 4.6, one GPT-5.2). Attach `CLAUDE.md`,
`AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/CODING_RULES.md` and `docs/SYSTEMS.md` to each as
persistent agent files. Re-attach after any of those change materially.

## The loop, per ticket

1. Director writes `panther/in.md` — the ticket body, acceptance criteria, non-goals, and the
   list of files to attach. It does not contain file contents.
2. User opens a `gacha-impl` chat, attaches the named files plus `in.md`, sends.
3. User saves the reply verbatim to `panther/out.md`.
4. Director applies the `EDITS` blocks, then runs BUILT and the GUT suite (`CLAUDE.md`).
5. Boundary-touching change? Before step 4 lands, user runs the same files plus the edit
   blocks through both reviewer agents and pastes both replies into `panther/review.md`.

## What does not go to Panther

- Running the gate, the test suite, or the export — Panther has no engine.
- Cross-file discovery ("where else is this called") — Panther cannot grep a repo it cannot see.
- Ticket scoping, boundary calls, ADRs, and routing — director's judgment, and prose is cheap.

## What Panther must never claim

`BUILT` and `VERIFIED` are unsatisfiable there. Both agent prompts forbid those fields. A
Panther reply containing one is fabricated evidence — reject the whole reply rather than
salvaging it, and re-run the task.
