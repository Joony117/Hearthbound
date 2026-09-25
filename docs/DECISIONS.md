# Decisions

Dated architecture decision records. **Record what was rejected and why**, so a later pass
doesn't "simplify" the architecture by undoing something deliberate.

Newest first.

---

## 2026-09-25: Casters shape the field — zones and walls are checkpoint-saved field objects; pathfinding is a per-state pure function, not a nav service

**ACCEPTED by the director, 2026-09-25** (godot-architect role, for `ig-vl1.2`; `ig-vl1.4`, `ig-0qh`, `ig-vl1.5`). Owner
ruling, 2026-09-24: casters are "rare but battlefield shaping"; the first shapes are zones and
walls, "we're eventually going to need pathfinding anyways". Build order: zones (no pathfinding
needed), then pathfinding, then walls. Numbers (radius, length, durations, the object cap) are
`game-designer`'s, after this entry. Amends nothing; extends the skills ADR (2026-09-23) and must
keep fitting the battle-sim-threading entry directly below.

**Decision.**

1. `BattleState` gains `field_objects` (Array of Dictionaries) and `field_sequence` (int, for
   deterministic ids), both additive optional keys — missing means empty/zero, `SIMULATION_VERSION`
   stays 1 (the objective-state/`P2-23` precedent). An object holds `id`, `kind` (`"zone"` or
   `"wall"`), `skill_id`, `owner_actor_id`, `faction`, geometry (zone: center + radius; wall:
   segment endpoints + thickness), `remaining_seconds` and its pulse timer. What it *does* is read
   from `BattleSimulation.ABILITIES[skill_id]` — the skills ADR's const dict of already-loaded
   `AbilityDefinition`s, not a `ResourceLoader.load()` by id — so a worker thread never repeats the
   `ZoneDefinition`-by-id bug the threading entry below just called out. An unknown `skill_id`
   drops the object with `push_warning` (the `ability_auto` migration precedent). Bad geometry or
   an out-of-bounds object rejects the checkpoint, checked the way objective-state fields are
   checked today (`_valid_point`, `_point_within_bounds`, `_valid_number`) — **not** the marker
   validator's exact-match-to-the-authored-zone shape, since a field object has no authored
   counterpart to match; it is cast at runtime.
   - *Amended 2026-09-25 (`ig-vl1.7`, godot-architect, to match what `ig-vl1.4` built):* there is
     no stored pulse timer. A zone pulses each time its `remaining_seconds` crosses a multiple of
     `skill_status_tick_seconds`, the crossing test `_tick_statuses` already uses
     (`battle_simulation.gd` `_update_field_objects`), so the pulse times follow from the one saved
     number. The object also stores the caster's `atk` and `heal_scale` from the cast, so a zone
     keeps its amounts after its caster is downed or leaves. A zone is the 10 keys the validator
     checks exactly: `id, kind, skill_id, owner_actor_id, faction, center, radius,
     remaining_seconds, atk, heal_scale`. Walls (`ig-vl1.5`) add their own geometry keys then.
2. The closed set of effect primitives (2026-09-23) grows by one: **zone**, an area over time that
   applies existing primitives (status, heal, damage, shield) to actors inside it, by faction.
   - *Amended 2026-09-25 (`ig-vl1.7`, godot-architect):* a v1 zone pulse is damage, heal or
     status. No shield: no zone uses one, and `_pulse_zone` has no shield branch. A zone that
     needs one adds it with its own ADR line, not quietly.
   **Wall** is not a primitive the effect picker applies to a target; it is a shape the movement
   code consults. v1 walls block movement only — not attacks, not line of sight — for both
   factions.
3. Field objects update at one fixed point in `_tick`, in `field_sequence` (creation) order, and
   apply to actors in actor order. Zone pulses draw no RNG (no crit).
4. A cap on live field objects per battle (a `SYSTEMS.md` number, `game-designer`'s) bounds the
   cost; the oldest ends first when a new one would exceed it.
5. Pathfinding is per-state pure data: no `NavigationServer`, no scene tree, no RNG, fixed
   tie-breaks, and it costs nothing while no wall is up (a segment-vs-wall test gates it). v1 picks
   a visibility graph over the inflated wall corners, with the next waypoint recomputed each tick
   as a pure function of `(position, destination, walls)`. The corner-to-corner graph itself may be
   a derived, per-state, unsaved cache keyed only by the current wall set — rebuilt when a wall is
   added or ends, or lazily after a reload — because it is a pure function of the checkpoint, so a
   cache hit and a fresh recompute agree and reload/worker copies stay identical; nothing about the
   cache is saved or order-dependent, and only actor-to-corner and destination-to-corner visibility
   plus a small Dijkstra run per actor per tick. Unlike a rebuilt grid, nothing here can desync
   across a reload or a worker-thread copy: the cache is disposable, never read from or written to
   the checkpoint, and a miss just recomputes the same graph the walls already imply. If walled in with no
   path, the actor holds until a wall ends.
6. Charge's dash, knockback and separation stop at a wall instead of crossing it. A wall dropped
   onto an actor already standing on it pushes the actor out perpendicular to the segment, toward
   the side the actor was already on when the wall was cast (a fixed, deterministic rule — never
   RNG, never simulation order).
7. The forecast sees zones and walls for free (same sim, seam #4). `ExpeditionOrders.safety_forecast`
   and `QuickResolve`/`legacy_v2` stay skill-blind — zones and walls are skill effects, not a new
   exception to the skills ADR's item 2. Enemy kits may reuse the same primitives later.
8. Field objects and pathfinding live per-`BattleState`, no static scratch data, matching the
   2026-09-25 threading entry directly below.
9. `BattleView` draws field objects read from the checkpoint, view-only (rule 1); it never derives
   or owns field-object state.

**Rejected.**

- **`NavigationServer2D`/`NavigationAgent2D`.** Global engine-owned server state: not per-`BattleState`
  data, not reproducible identically from a saved checkpoint or off the main thread — the same
  reason the threading entry below keeps the job touching no `Node`, autoload or shared `Resource`.
- **A script or subclass per zone/wall shape.** The skills ADR's closed-set-of-primitives reason;
  a registry of per-spell behaviors is the same anti-pattern the combat seam already refuses for
  `resolve()` itself.
- **Walls authored as permanent terrain on `ZoneDefinition`.** The owner asked for caster-placed,
  timed, per-battle walls, not authored zone terrain — that would put runtime state (rules 2–3) on
  a Definition Resource.
- **`AStarGrid2D` as the v1 default.** Left open, not rejected outright: it is a live object that
  must be rebuilt deterministically on every wall change and every reload, more moving parts than
  a pure per-tick function. Revisit only under a measured budget miss (2026-09-24 performance ADR,
  item 1: no structure goes in without one).

**Left open on purpose.** The object cap and all geometry/duration numbers (`game-designer`,
after this entry). Whether enemy kits pick up zone/wall in v1 or later. `AStarGrid2D` as a
fallback if the visibility graph measures over budget once walls ship.

---

## 2026-09-25: Battle sim threading — per-order jobs on WorkerThreadPool, round-committed catch-up, and a settle-time "checking" phase for the repeat forecast

**ACCEPTED by the director, 2026-09-25** (godot-architect role, for `ig-7sn.13`; `ig-7sn.12`, `ig-7sn.6`). Amends the
2026-09-24 "Performance: budgets..." entry's item 5, which required this decision before the sim
was threaded. Owner/director ruling (`ig-7sn.13`): yes to threads for the battle sim, no for the
UI; nothing touches `GameSession`, the save or the scene tree from a thread; results identical to
the single-thread run.

**Decision.**

1. A job runs on `WorkerThreadPool.add_task`, owns a deep-copied `BattleState` (or `create_run`'s
   inputs: snapshots, squads, policies, escrow, seed), advances in fixed 5-battle-second chunks,
   returns plain data, and touches no `Node`, autoload, signal, `Hero`, `GameSession` or
   `SaveService`. **Not yet true as coded:** `advance()`'s `_update_objectives` calls
   `ZoneDefinition.definition_for()` → `ResourceLoader.load()` by `zone_id` internally
   (`combat/battle/battle_simulation.gd:735, 890`) rather than using a reference the caller holds —
   `create_run()` takes `zone: ZoneDefinition` (:92) but `BattleState` only stores `zone_id`, a
   `String` (:105). A job as specified still calls `ResourceLoader.load()` itself, from a worker
   thread, every tick. Godot 4.7's thread-safety docs warn against loading the same Resource from
   multiple threads at once; the cache doc describes reuse of a cached instance but does not say
   that a main-thread preload first makes concurrent `load()` calls safe. `BattleState` must carry
   the resolved `ZoneDefinition` (set once in `create_run`) so a worker never calls
   `ResourceLoader`. Required before item 5 is satisfied. The same goes for `validate_snapshot`,
   which loads the zone by id too (`battle_simulation.gd:296-298`, director 2026-09-25): a job
   never builds or validates a `BattleState` from a Dictionary itself. The main thread builds it,
   or hands the check the zone it resolved.
2. The six static scratch vars (`_cover_victims`, `_cover_claims`, `_cover_nearby` at
   `battle_simulation.gd:2209-2211`; `_row_front`, `_row_contact`, `_row_threat` at :2266-2268)
   become locals or per-state fields first. Two concurrent jobs sharing static state is a
   correctness bug, not a perf one.
3. One job function, callable directly by the main thread too, with a GUT test comparing
   `to_dict()` byte for byte across both call paths, several seeds, `frontier_march` and
   `fallen_citadel` included — satisfies item 5's test requirement.
4. Results commit on the main thread only, at the pulse, each order in its fixed place, never
   completion order. Battle-dictionary identity alone is not enough: `remaining_seconds`, pause
   state and repeat/settlement fields mutate on the order in place without replacing that
   Dictionary, so a landing job must also check the order is still in the phase and generation it
   was dispatched under, not identity alone.
5. Cancellation: a shared flag checked between chunks; on quit and before `load_game`'s
   `from_dict`, `GameSession` sets it and waits for outstanding tasks (bounded to one chunk).
   Cancelled results are dropped.
6. The job table is a private, unsaved `GameSession` field, the same shape as the existing
   `_paused_battle_orders` (`systems/game_session.gd:92`). No fourth autoload.
7. The live 0.25 s pulse stays on the main thread in this change. Moving it is a later bead under
   `ig-7sn`, measured first — not `ig-7sn.11`, which is the Town frames bead.
8. `ig-7sn.12` (load catch-up): `apply_offline_expedition_progress` does no sim work; it sets an
   additive order key `catch_up_seconds` (missing = 0, bad value → 0 with `push_warning`,
   `SAVE_VERSION` unchanged, the `P2-23` precedent). The first pulse sends one job per owed order;
   the order's battle clock stops until its job lands. Amended by the director on 2026-09-25, with
   high1: `catch_up_seconds > 0` stops the clock at the paused-skip sites, instead of an entry in
   `_paused_battle_orders`. That set is the player's pause, and leaving the battle view clears it
   (`battle_view.gd` `_release_live_binding` → `set_battle_paused(false)`), which would free a
   catching-up order mid-job. A round commits only once every job in it has landed, through today's
   `_resolve_due_orders_in_memory` order — never completion order. An interrupted catch-up resumes
   from the same saved state, so it ends at the same `to_dict()` as an uninterrupted one.
9. `ig-7sn.6` (settle forecast): confirmed against `systems/game_session.gd:2143-2177` —
   `_start_battle_repeat` already draws one seed, calls `forecast()` with it, and, only if safe,
   calls `create_run()` with that *same* seed and `order_id`. Reusing the check's seed for the
   landed run in the new "checking" phase is not a new risk; it is today's synchronous behavior,
   made async. At settle, a due repeat spends escrow, draws the seed, builds snapshots, sets phase
   `"checking"` with the existing `run_seed`/`escrow` keys, and sends the forecast as two parallel
   jobs (normal, stress). A `"checking"` order is excluded from `_resolve_due_orders_in_memory`
   (else a reload double-settles). Landing: safe → `create_run` with that seed/snapshots, phase
   `"fighting"`; unsafe → refund escrow, stop with `unsafe_repeat` on that settle's report. The
   in-progress forecast lives only in the unsaved job table; the order's saved fields are all
   additive or reused, not new save keys.

**Rejected.**

- **`QuickResolve` for offline legs.** Changes outcomes, and the skills ADR (2026-09-23, item 2)
  already limits `QuickResolve` to `legacy_v2` orders.
- **A blocking, time-sliced load screen.** ~40 s wait at pace 6 for no gain over the background job.
- **A main-thread background slice.** Frontier catch-up (~150 s) would eat the frame budget the
  dispatched-battles row already misses (`SYSTEMS.md` § Performance budgets).
- **Threading one battle's own ticks.** Serial by nature; a thread moves the wall time off the
  main thread but cannot shorten one battle.

---

## 2026-09-24: Performance: budgets at each scene's worst case; threads only for measured pure-data work

**ACCEPTED by the director, 2026-09-24** (godot-architect role, for `ig-7sn.1`). The owner asked:
"make sure we're optimizing and planning for performance as we go. threading, code perf audits,
etc". Sol's read-only audit (`.agent-results/perf-audit/sol-code-audit-2026-09-24.md`) supplies
the candidates and risk ratings below. It ranked risks by reading; nothing is measured yet.
Item 0 amends a hard constraint in `GAME_SPEC.md`, which needs an entry here.

**Decision.**

0. **60 FPS holds at each scene's worst case**, as listed in `SYSTEMS.md` § Performance budgets.
   This replaces "60 FPS with 5 heroes and ~20 enemies" in `GAME_SPEC.md` § Hard constraints.
   The zones now field up to 50 heroes (frontier_march) and 30 enemies a wave (fallen_citadel).
   Director ruling, 2026-09-24: a target that leaves out the real worst case is no target. When a
   new scene or a bigger zone raises a worst case, its row in that table changes with it.
1. **Measure first.** No thread goes in without a measured number over its budget in
   `SYSTEMS.md` § Performance budgets. The baseline (`ig-7sn.2`) comes first.
2. **Cheaper fixes first.** A redundant refresh, copy or cache miss is fixed before anything is
   threaded. The audit's order-card and double-detail findings are `ig-7sn.3`.
3. **Engine options before our own threads, each measured.** The physics engine is decided by
   the gore spike (`ig-c9y.2`). The physics thread (`physics/3d/run_on_separate_thread`) is not
   free here: `town_view.gd` picks with `direct_space_state.intersect_ray` from input, and with a
   separate physics thread Godot allows space queries only during the physics step. It goes on
   only after that pick moves into the physics step and a measurement shows the win.
4. **Our own threads run pure-data jobs on `WorkerThreadPool`.** A job takes copied plain data
   (Dictionaries, Arrays, packed arrays). It touches no Node, no autoload, no signal and no
   Resource that anything writes, and it returns a value. The main thread applies the result,
   and first checks a change key (such as `ledger_next_seq`) so a stale result is dropped.
5. **The battle simulation stays on the main thread** (boundary #4). Dispatched battles may run
   on workers only with all of these: one job per order; the same tick chunks and RNG state as
   the main-thread run; results committed on the main thread in each order's fixed place, never
   in completion order; and a test showing byte-identical `BattleState.to_dict()` checkpoints
   both ways for the same seeds. Building that amends this entry first.
   *Amended by 2026-09-25, "Battle sim threading" (above).*
6. **No thread touches the save** (boundary #1). `GameSession.to_dict()`, the file writes and
   the validation stay on the main thread. Preparing the text of an already detached payload is
   a candidate, but save order needs its own review first.

**Candidates, with the audit's risk to battle determinism.**

| Job | Pure data? | Risk |
|---|---|---|
| Ledger history, bond and dream scans over an unchanging Ledger snapshot | Yes | None. Drop a stale result by Ledger sequence |
| Town route search over a copied graph and endpoints. The live AStar and the nodes stay on the main thread | After the copy | Low |
| Preparing save text from a detached payload | Maybe | Low. Save order needs its own review |
| Independent battle simulations | After each order's state is detached | High if committed in completion order. Low only under item 5 |

**Rejected.**

- **Threads by default.** They add ordering bugs, and they pay off only where a measurement says
  the work is over budget.
- **View work on threads** (nodes, the scene tree, `BattleVfx`). Godot's scene tree is not
  thread-safe.
- **A thread pool around `BattleSimulation` without item 5's test.** It could pass every gate and
  still drift the outcome.

---

## 2026-09-24: Bonds stay derived from the Ledger, read in one pass for every pair; knowledge and testimony are per-hero state that points into it

**ACCEPTED by the director, 2026-09-24** (godot-architect role, for `ig-m6o.2.2`), after a
read-only Sol review. Its six wording fixes are applied. The owner gate on `ig-m6o.2.1` passed,
and `ig-m6o.2.2`'s body asks two questions before any code:
are bonds derived or stored, using the slice's measured read cost, and how does testimony relate
to the Ledger (architecture note 9, on `ig-m6o.2`)? `SYSTEMS.md` § Bonds and dreams has the
numbers.

**What the slice measured.** One bond and dream read for one hero costs 39 ms at the
10,000-record cap (best of seven). It walks the whole ledger. The slice reads one hero at a time:
the selected hero's detail and the body's partner. `ig-m6o.2.2`'s first slice needs every hero's
partner at once: a partner sign on every roster row and over every bonded walker. A per-hero read
for each would cost up to N × 39 ms, about 2 s for 50 heroes at the cap. Nobody nears the cap
for 100+ hours at the guessed 60 records an hour.

**Bonds.**

1. **Bonds stay derived.** No saved bond state: no `Hero` key, no `GameSession` field, no save
   key. Save boundary #1 is untouched.
2. **One pass reads every pair.** One oldest-first pass builds directed entries for every ordered
   hero pair. Both directions share the scoring rules but retain each hero's fact wording, first
   qualifying save within a record, strongest-fact precedence, and existing partner tie-breaks.
   `Bonds.bond` for one hero answers from that index, so there is one set of rules. The index
   keeps every hero it saw; living heroes are filtered when it is asked, not when it is built.
   - The dream is not in the index. It stays a separate oldest-first read for one hero (item 6).
   - Hero ids are 128 random bits (`Item.new_instance_id`), so a reused id is negligible. The index
     treats an id as one hero for life, with no code guard.
3. **The index is kept until the ledger changes.** The holder identifies the in-memory ledger
   array and its `ledger_next_seq`; a new array on load or a changed next sequence invalidates the
   index. Clear it on a rule or balance change.
   - A rollback needs nothing: it puts the old list back (`_commit_profile_mutation`), truncated,
     with its old `ledger_next_seq`. `_read_ledger` always builds a new list, never clears one in
     place. Eviction runs before the deferred notifications flush, so no refresh reads between an
     append and its eviction.
   - Every other refresh asks the kept index: `roster_changed`, the 0.25 s pulse, selecting a hero.
     It is never saved, so it cannot drift: a load or a rule change rebuilds it from the records.
   - The reader keeps no state. Its holder keeps the index: hub.gd in the first slice, as view
     state beside `_partner_id`. If a `GameSession` rule needs bonds later, `GameSession` may hold
     the same index as an unsaved field, rebuilt the same way. That needs no new ADR.
   - This replaces the slice's "no cache that outlives one read", which was about the reader.
   - *Amended 2026-09-24 (`ig-m6o.2.2.9`, director ruling):* the index moved from hub.gd to
     `GameSession`, the ledger's owner. It was moved, not copied: `GameSession` holds it as an
     unsaved field, and the hub and `_team_snapshots` (`ig-uu7.4`) read that one index, so one
     rebuild or fold per ledger change serves both. The key is unchanged (array identity plus
     `ledger_next_seq`), with one guard beside it: an append made while the index is out of step
     drops the index. Without it, appends after a rolled-back append could bring `ledger_next_seq`
     level with the index again while it still held the dropped records. The rules stay in
     `Bonds`; `GameSession` only holds and calls. ARCHITECTURE rule 1 holds: `GameSession` never
     reads hub.gd.
4. **Never per frame.** Today the ledger changes only when a battle settles or a hero is summoned,
   ranked up or dies, so a rebuild follows one of those.
5. **The budget, and the trigger to change.** The 39 ms was one hero's bond and dream, not an
   all-pairs rebuild. So the first slice times, at the cap and with the largest team size, a full
   all-pairs rebuild and the end-to-end roster refresh, and prints both. Not a gate.
   - A slice that writes records on the live tick (meals, encounters) makes the ledger change
     every few minutes of play. That slice keeps a rebuild within one 60 FPS frame (16.7 ms) at
     the cap, measured as the worst of seven runs, not the best. If it cannot, it first switches
     the index to an incremental fold: fold each appended record in, and take each evicted record
     out.
   - The fold is still derived from the records and still unsaved. It is the upgrade path, not a
     reason to save tallies.
   - *Amended 2026-09-24 (`ig-m6o.2.2.9`):* `ig-m6o.2.2.1`'s measurements pulled the fold forward
     before any live-tick record. At the 10,000-record cap the all-pairs rebuild cost 103–129 ms
     with 5-hero teams and about 4.4 s with 50-hero teams, and a record-writing roster change cost
     251–351 ms end to end, against the 33 ms no-hitch line (`SYSTEMS.md` § Performance budgets;
     § Bonds and dreams, the Bond read cost row). The index now folds each appended record in and
     each evicted record out. A load or a rolled-back append rebuilds, as does an eviction the fold
     cannot take out exactly (none under today's tiers). The dream stays out of the fold (items 2
     and 6); the hub keeps each hero's dream until the ledger changes.
6. **Dreams stay derived too.** A hero's dream is read from its records by a fixed rule, for one
   hero at a time (the detail panel), as the slice does. The dream catalogue keeps that. A dream
   becomes saved per-hero state only when something that is not a record can choose or revise it:
   new knowledge (`GAME_SPEC.md` § Direction § 5) or a player's choice. That lands with the
   knowledge slice and its own amendment.
7. **Meals and encounters are settled events.** `meal` (reserved in the Ledger ADR, item 5) and
   `encounter` are records, one per event, never one per tick or per hero.
   - The `GameSession` mutator that settles the event writes it, on the live tick only. Never in
     the offline catch-up, the same as food.
   - Never from where walker figures meet. Walking is cosmetic (`ig-6m2.6`), so a record that
     followed render timing would differ between sessions. The event comes from saved state: who
     is home and not busy, who works where, whose Houses are near.
   - Each slice settles its record's shape (additive keys) and game-designer sets its volume.
   - They are evicted first, as a new tier ahead of routine battles. This amends the Ledger ADR's
     item 8, which puts routine battles first, and that item says so. Each is frequent and matters
     little alone. A friendship built on them fades at the cap, the same way a bond built on
     routine victories would, which is why those score nothing.
   - The slice that adds the first of them changes `Ledger.tier()` and `TIER_BY_KIND`. Today an
     unknown kind falls to tier 1 with the other battles (`TIER_BY_KIND.get(kind, 1)`), and
     routine battles are tier 0.

**Testimony against the Ledger (architecture note 9).**

8. **The Ledger holds settled events only** (Ledger ADR, item 4, unchanged). A retelling, a
   rumour, a belief or a hero's knowledge is never a record. A gossip exchange writes nothing to
   the Ledger.
9. **Knowledge and testimony are per-hero saved state that points into the Ledger by `seq`.**
   - An entry keeps the gist it needs beside the pointer (who, what, where, how it felt), so it
     survives its record's eviction. Memory keeps the gist and the feeling longer than the wording
     (`GAME_SPEC.md` § Kept in full, gossip), and forgetting a betrayal does not restore trust.
   - The entries per hero are capped (number: game-designer), so the save stays small.
   - It crosses save boundary #1. The knowledge slice brings its own amendment, a real disk
     round-trip, a legacy save and a verifier.
10. **Only consequential statements become records:** a Herald's covenant, a confession, a
    public accusation. Each is a new kind with one writer (Ledger ADR, item 5), added by the slice
    that first needs it. None is in step 2's first slices.
11. **Witnessed details** (step 1's missing piece, `GAME_SPEC.md` § 10 ruling) land with the
    knowledge slice. A battle record's `team` is already the witness list (Ledger ADR, item 5).
    What each witness knows is knowledge, not a new record field.
12. The side file (`ig-m6o.9`) keeps a save's write cost flat either way. What items 8–10 protect
    is the cap and the records-per-hour estimate.

**Rejected.**

- *Saved bond tallies: a per-pair points table in the save.*
  - The Ledger ADR already rejects saved tallies. A tally is a second source of truth that drifts.
  - Every bond row is PROVISIONAL, and calibration has not run: the owner's save has no fights
    yet. A saved tally bakes today's rows into every save, so each tuning pass needs a migration,
    and a wrong tally can never be recomputed. A derived bond re-reads history under the new rows.
  - It would carry the most-tuned numbers in the game across save boundary #1.
  - It grows with pairs: 50 heroes make 1,225.
  - The cost it would save is removed by items 2 and 3, which save nothing.
- *A per-hero read for every hero.* Up to N × 39 ms at the cap.
- *A read on every pulse or frame.* `ig-m6o.2.1`'s review caught one: the 0.25 s pulse read the
  ledger four times a second.
- *The incremental fold now.* Eviction and the dream's order make it fiddly, and nothing needs it
  until records arrive on the live tick. It is item 5's upgrade path. *Superseded 2026-09-24 by
  item 5's amendment.*
- *A static cache on `Bonds`.* Global state that every test would have to reset. The holder keeps
  the index instead.
- *Encounter records from walker positions.* Render timing (item 7).
- *A record per gossip exchange or retelling.* It breaks the cap and the records-per-hour
  estimate (note 9).

**Left open on purpose.**

- The `meal` and `encounter` shapes and volumes (their slices; the volumes are game-designer's).
- The knowledge save shape (the knowledge slice's amendment).
- Where a departed hero's knowledge lives, so step 6's departed testimony can still read it after
  the hero leaves the roster (the knowledge slice).
- A relationship layer that must outlive its records goes to knowledge (item 9), not to a bond
  tally. If one ever cannot, that needs a new ADR.

---

## 2026-09-24: The Ledger — one append-only record of settled events on `GameSession`; every history reader derives from it

**ACCEPTED by the director, 2026-09-24, with three amendments** (items 5 and 8 below: every
`battle` record names its team, an expedition `died` record points at its battle, and eviction
is tiered so the dead are forgotten last). Drafted for `ig-m6o.1`,
step 1 of the living-world direction (`GAME_SPEC.md` § Direction, owner, 2026-09-24). Nemesis,
the Guest, the Chronicle, graves, the Parliament and Risen promotion all read history. A fact
that is not recorded when it happens can never be told later, so the record comes first.
`SYSTEMS.md` § The Ledger has the numbers.

**What moves.**

1. **The Ledger is `GameSession` state, split across two files.** Records live in an
   append-only JSON Lines side file, `user://ledger.jsonl` (one record per line, not
   indented), written by `SaveService`. The main save keeps one additive key:
   `ledger_next_seq` (an int that starts at 1 and is never reused), the high-water mark for
   the side file. `SAVE_VERSION` is not bumped (the `P2-23` precedent). A save without the key
   loads an empty ledger. Nothing is backfilled. This crosses save boundary #1, so it needs a
   real disk round-trip, a legacy-save load and a `verifier`. *Amended 2026-09-24 (`ig-m6o.9`,
   save budget): a real save at the 10,000-record cap cost 108 ms and 3.9 MB, growing about
   11 µs per record on every profile commit and every 15 s periodic save
   (`.agent-results/ig-m6o.1/gut_ledger2.log`). That crosses one 60 FPS frame near 1,500
   records. The side file keeps a commit's write cost independent of ledger size: a commit
   appends only its new lines, then writes the main save as before. On load, lines with
   `seq >= ledger_next_seq` are dropped: they were appended, but the main save that would have
   advanced the mark never landed. That keeps item 4 ("never one without the other") across
   two files instead of one. A failed append fails the mutation, the same as a failed save
   today. An orphan line must never collide with a later `seq`: the loader either truncates the
   file back to the last committed length, or leaves the gap and never reuses the `seq`. A
   legacy save with an embedded `ledger` key migrates its records to the file once on load and
   stops writing the key. A missing or unreadable side file loads as an empty ledger with a
   `push_warning`. Acceptance for this amendment adds two crash cases through a real disk
   reload: an append that lands with a main save that fails (the orphan lines are dropped, and
   the next `seq` does not collide), and a missing side file (the ledger loads empty and the
   game plays on).* *Director amendment (Sol, `ig-m6o.9`): a missing side file warns only when
   `ledger_next_seq` is above 1. At 1 nothing was ever written, so it loads silently. A side
   file that exists but cannot be opened blocks the load, the same as an unreadable main save,
   instead of loading empty: the load's compaction would write the empty list over the real
   history, and a lock is often temporary.*
2. **A record is `{seq, time, kind, ...fields}`.** `time` is unix seconds when the event settles,
   and `seq` orders records. Heroes are named by `instance_id`. Enemies have no identity yet, so
   they appear as `enemy:<archetype>` plus the zone. Only `summoned` and `died` carry a name.
3. **Append-only.** No code edits a record. Only the size cap removes records (item 8).
4. **Settled facts only.** A record is written by the same `GameSession` mutator that changes the
   state it describes, so one snapshot never holds the change without its record, or the reverse.
   Forecasts, repeat-safety forecasts, previews and the arena prototype write nothing.
5. **One writer per kind.**
   - `summoned`: `summon_hero`.
   - `battle`: `_settle_battle_order` and `_settle_rescue_order`, one record per settled battle.
     It names its `team`: the `instance_id` of every hero who fought, downed or not. That is
     every allied actor in the battle, so a rescue's team includes the stranded heroes it found.
     The team is the battle's witness list, so a later per-hero-knowledge reader (a hero knows
     what they saw) needs no backfill. *Director amendment.* A rescue's record also names its
     `rescuers`, the rescue order's own heroes, next to `rescued`, so a reader can tell who came
     from who was found. It is additive: a record without it reads neutrally, with no "by".
     *Director amendment (Sol, `ig-m6o.1`): the team alone made every witness read as a rescuer.*
   - `died`: `kill_hero`, and only there. An `expedition` death carries `battle_order`: the id
     of the order whose battle stranded that hero. A reader finds the `battle` record whose
     `order` matches. Most expedition deaths settle later than that battle (abandon, expiry or
     a failed rescue), so the stranded incident carries the link: its `source_order_id` for the
     heroes the first battle stranded, and the additive incident key `battle_orders` (hero id to
     order id) for a rescuer that a failed rescue stranded, whose link is the rescue's order. A
     legacy incident falls back to `source_order_id`. It is the first causal link between
     records. *Director amendment, corrected 2026-09-24.* It is an order id, not a `seq`,
     because the incident already holds one and legacy incidents do too.
   - `ranked_up`: `rank_up_hero`.
   - `meal` is reserved for step 2. Eating ticks are not events.
6. **Permadeath keeps one writer.** `kill_hero()` gains optional `cause` (`expedition`,
   `sacrifice` or `starvation`) and `by` arguments and writes the `died` record itself. A
   sacrifice is one `died` record with `by` = the keeper. Rule 8 is unchanged: `kill_hero()` is
   still the only code that removes a hero, and now it is also the only code that records one
   leaving.
7. **Combat resolves combat, and reports moments.** `combat/` never reads or writes the Ledger.
   - The simulation appends a *moment* to `BattleState.moments` when a hero is downed, revived or
     carried out: `{tick, what, hero, by}`.
   - `moments` is an additive `BattleState` key, so a mid-fight save and reload keeps them
     (boundary #1). `BattleOutcome` gains `moments` as a copy, and `GameSession` writes them into
     the `battle` record at settle.
   - Moments draw no RNG and change no result. The forecast still predicts the same battle.
   - The `legacy_v2` backend writes no `battle` record, and its deaths carry no `battle_order`.
     Its orders exist only in saves from before `ig-544` and resolve through `QuickResolve`,
     which never builds a `BattleOutcome`. *Corrected 2026-09-24: this line first said the path
     reports an empty `moments` list (Sol, `ig-m6o.1`).*
8. **Bounded size.**
   - `ledger_max_records` caps the list, and `battle_max_moments` caps each battle; past it,
     `moments_truncated` is set.
   - Over the cap, eviction is tiered, and within a tier the oldest record goes first:
     1. routine battles: a victory `battle` with no moments and no rescued heroes
     2. other `battle` records
     3. `ranked_up`
     4. `summoned`
     5. `died`, last of all. A game about remembering the dead forgets them last.
     *Director amendment.*
     *Amended 2026-09-24 by "Bonds stay derived" (item 7): `meal` and `encounter` records go
     first, as a new tier ahead of routine battles. The slice that adds the first of them changes
     `Ledger.tier()`.*
   - Every reader tolerates gaps ("arrived before the records begin"). Legacy saves need that
     anyway.
   - *Amended 2026-09-24 (`ig-m6o.9`, save budget): eviction stays in-memory, on the list held
     during play, exactly as above. It never touches the side file mid-play. The file is
     compacted — rewritten to match the capped, evicted list — only at load, behind the load
     screen. The rollback snapshot in `_commit_profile_mutation` excludes the records: a
     rollback truncates the in-memory list back to its old length instead of deep-copying up to
     10,000 dicts on every commit. Eviction must not break that truncate, so eviction runs only
     after a mutation commits; the list sits above the cap for at most one mutation. Compaction
     writes a temporary file and renames it over the side file, the way `SaveService` already
     replaces the main save, so an interrupted compaction leaves the old file whole. A torn last
     line (a crash mid-append) is dropped at load, because its main save never landed. The
     budget this meets: at most 2 ms added to any save or profile action, at any ledger size up
     to the cap (`SYSTEMS.md` § The Ledger, the save budget row).* *Director amendment (Sol,
     `ig-m6o.9`): a recovery rewrite is exempt from that budget, the same as load compaction. It
     rewrites the whole file once, on the first save after a failed compaction or a failed undo:
     about 75 ms at the cap. Steady play only appends.*
9. **Rules are pure static functions in one script,** following `ExpeditionOrders`: append with
   cap and eviction, records for a hero, and history lines. `GameSession` calls it. The first
   visible reader is the hero detail panel.
10. **No fourth autoload.**

**Rejected.**

- *Event sourcing: rebuilding game state by replaying the Ledger.* The save stays the state, and
  the Ledger is history beside it. Replay would make every past bug permanent and every rule
  change a migration.
- *A history array on each `Hero`.* A dead hero leaves the roster and would take its history with
  it. A battle shared by five heroes would be stored five times.
- *A `Ledger` autoload.* The cap is three autoloads; `SaveService` already owns file I/O.
- *A separate save file.* *Amended 2026-09-24 (`ig-m6o.9`, save budget): this line first
  rejected any second file, reasoning that it "could be written without the main save, which
  breaks item 4's `never one without the other`." That is now the accepted shape (item 1): a
  second file only breaks item 4 if there is no way to tell an orphan write from a committed
  one, and `ledger_next_seq` as a high-water mark in the main save is that tell. What stays
  rejected, and why:*
  - *A lower cap, to fit one save-cost frame.* About 1,500 records would fit, but that throws
    away the history Nemesis, the Guest and the Chronicle exist to read.
  - *One compact file, written whole each time, with the rollback deep-copy dropped.* Roughly
    halves the cost but is still O(history) on every commit and every periodic save; it still
    crosses one frame at the cap.
  - *Caching the serialized ledger text and only appending to the cache.* The bytes written on
    each save still grow with history; caching moves where the cost is paid, not whether it
    grows.
  - *A save thread.* The snapshot is still built on the main thread before handoff, so it adds
    concurrency to the save boundary for no removed cost, and the save path has no thread today.
- *Recording every hit or kill.* It would flood the log. A per-battle kill count carries what a
  history needs.
- *Mutable records or saved tallies ("battles won: 37").* A tally is a second source of truth
  that drifts. Readers count.
- *Letting `combat/` append to the Ledger directly.* The simulation would then have to know about
  profile state, and the forecast would have to be kept from writing. Moments ride out on the
  battle's own state instead.
- *Backfilling legacy heroes' history.* It would be invented.

**Left open on purpose.**

- The cap numbers (`SYSTEMS.md`, PROVISIONAL, settled by measuring records per hour and save
  write time on a full ledger).
- The shape of `meal` (step 2).
- Stable enemy identity for nemeses (step 7, its own ADR).
- Whether the Ledger carries into the next town in the Old World (step 8, its own ADR).

---

## 2026-09-23: Skills are data the one simulation reads — bars and chains are profile state, the forecast stays the simulation, and one hero can be piloted inside it

**ACCEPTED by the director, 2026-09-23,** on the owner's four answers. Item 11's no-damage line is
scoped to v1. Drafted for `ig-gy0`. The owner, 2026-09-23:
"I want each hero to have customizable skill bar, I want them to be able to have 30+ skills if I
wanted." `GAME_SPEC.md` § Skills has the design. `SYSTEMS.md` § Skills has the numbers and the v1
kits. The owner answered its four questions the same day: class skills plus a shared general pool,
skills die with the hero, click and number keys first, enemies get skills.

**What moves.**

1. **A skill is an `AbilityDefinition` Resource.** The class that holds today's four signatures
   grows the fields a skill needs: kind (passive, weaponskill, ability), archetype (one of the five,
   or `general` for the shared pool), unlock level or general tier, book-only, counter tag, combo
   predecessor, the AI rule, and a list of effects. There is no new
   base class and no script per skill.
   - Effects are a closed set of primitives (damage, heal, shield, status, revive, interrupt,
     move, taunt). One function in `BattleSimulation` applies them. It replaces
     `match actor.archetype` in `_use_ability`.
   - `BattleSimulation.ABILITIES`, keyed by archetype, becomes a const dict keyed by skill id.
     `HeroDefinition.battle_ability` duplicates it today and is removed, so there is one source.
   - A test loads every skill `.tres` and fails on an unknown primitive or field.
2. **The forecast stays the simulation. No second implementation is written.** A `battle_v1`
   order's safe check is already `BattleSimulation.forecast`: two real runs. Skills live only in
   `combat/battle/`, so the forecast sees every skill for free. Two paths are skill-blind, and stay
   that way by rule:
   - `ExpeditionOrders.safety_forecast`, the closed-form estimate. It feeds the dispatch preview's
     "Power forecast" line in `hub.gd` and `GameSession`'s repeat of `legacy_v2` orders. It
     already ignores abilities. It is never the unlimited-repeat gate for a `battle_v1` order.
   - `QuickResolve`. It resolves only `legacy_v2` orders saved before `ig-544`.
   Skill logic anywhere outside `combat/battle/` is a bug. The cost that is real is speed: every
   skill slice keeps forecast wall time within 2× the first slice's baseline (`SYSTEMS.md`).
3. **A hero's skills are profile state** (save boundary #1). Three additive `Hero` keys, saved in
   `Hero.to_dict/from_dict`:
   - `learned_skills`: skills from books and the Training Hall only. Level skills are derived
     from level and archetype, never saved, so they cannot fall out of step.
   - `skill_bar`: `[{id, mode}]`, where order is priority and mode is `auto`, `manual` or `off`.
     A hero without one gets a derived default: every known skill, `auto`, in kit order.
   - `skill_chains`: `[{trigger, then: [ids]}]`, at most `skill_chain_max_steps` after the trigger.
   Plus `GameSession.skill_books`, `{skill_id: count}`. `SAVE_VERSION` is not bumped (the `P2-23`
   precedent). On load, unknown ids, ids from another class, skills the hero does not know and bad
   modes are dropped with a `push_warning`. A `general` id is valid on every class. All of it lives on the `Hero`, so a death takes it
   away and `kill_hero()` stays the only writer (rule 8).
4. **The dispatch snapshot carries the kit.** A team snapshot gains `skills` (known skills in bar
   order, with modes) and `chains`, fixed at dispatch like gear. A snapshot without them derives
   the archetype's signature and passive, which is exactly today's battle.
5. **Battle checkpoints migrate** (dispatch-order profile data, boundary #1). A `BattleActor` gains
   per-skill cooldowns, the ability lock, a status list, combo state and chain state. An old
   checkpoint loads like this:
   - `ability_cooldown` becomes the signature's cooldown.
   - The per-order `ability_auto` policy becomes the signature's mode. New orders stop writing it.
   - `guard_remaining`/`guard_reduction` become a damage-reduction status, in the slice that adds
     statuses. `stun_remaining` stays as it is.
   `validate_snapshot` accepts both shapes.
6. **A chain is an AI preference, not an order queue.** "A new direct movement/target order
   replaces the previous one; no custom queue" (`SYSTEMS.md`) stands. A chain only changes which
   skill is picked next. Its step and deadline are saved in the checkpoint like a cooldown. A
   Manual skill inside a chain fires: programming it counts as firing it by hand (director ruling,
   2026-09-23).
7. **One generic picker.** Counter, then revive, heal, chain, buff and attack, with ties broken by
   bar order. Each skill's rule is data. Enemies use the same picker with their own kits and no
   chains.
8. **Counters read the telegraph state that exists** (`telegraph_kind`, `_origin`, `_point`,
   `_radius`, `_remaining`). There is no new telegraph system. The claim is saved on the
   telegraphing actor (`telegraph_claimed_by`), so a reload mid-telegraph does not answer twice.
9. **Piloting is a view mode of the same simulation.** This amends 2026-09-22 ("`ig-yzc` now means
   observing and commanding an existing expedition, not piloting one hero"): piloting one hero is
   one more way to command, not a separate arena or simulation.
   - The battle view marks one ally as piloted. The simulation then skips that actor's skill and
     target choice. It still auto-attacks its current target.
   - The view sends `use_skill {actor_id, skill_id, target_id or point}`, validated like today's
     commands, plus today's move and attack commands.
   - Piloted is watched-view state, like tactical pause: cleared on leaving and on reload, never
     saved in the checkpoint, never set in an unwatched run or a forecast.
   - WASD later needs a held movement direction on the actor, read each tick. That is state, not
     a queue, and it gets its own amendment when it comes.
10. **FFXIV is inspiration only.** Names, numbers, icons, effects and text are ours. A skill whose
    name matches a Square Enix skill name, or closely copies one, is refused in review. Effects
    are one generic visual per primitive, tinted per skill. Icons are our own glyphs.
11. **Skills touch no Summon Stone, Essence or parts formula, and add no seventh stat.** A book is
    an extra roll in `Expedition.roll_loot` (`hub/expedition/expedition.gd`), either a class book or
    a general book. Teaching is a `GameSession` mutator that spends parts and checks the Training
    Hall's level: class skills ahead of level, general skills by tier. General skills never open by
    level. In v1, none deals damage or raises ATK, SPD or crit, so the v1 pool cannot raise a
    hero's damage (`SYSTEMS.md` § The v1 general pool). That is a balance choice, not part of this
    ADR. A later damage-dealing general skill needs a `SYSTEMS.md` balance check, not an amendment.
12. **No fourth autoload.**

**Rejected.**

- *A closed-form skill model for the forecast.* It would drift from the simulation, which is the
  exact failure the combat seam exists to prevent.
- *A script or a subclass per skill.* Forty skills now and more later. Data plus a closed set of
  primitives scales, and keeps the seam free of a registry of behaviors.
- *Mana or another skill resource.* A second thing to balance and show. The swing timer, cooldowns
  and the ability lock already bound output.
- *Weaponskills on their own cooldowns.* Thirty of them would multiply damage by the size of the
  bar.
- *A bar slot limit.* The owner ruled there is none.
- *Chains as a command queue.* It breaks the replace-order rule and the synchronous command model.
- *Saving level skills.* They are derivable, and a saved copy can disagree with the level.
- *Piloting as its own arena or simulation.* That is a second implementation of a battle.
- *Piloting in unwatched runs.* There is no view to take input from.
- *Square Enix names, icons or effects.*
- *Learning another class's skills.* The owner chose class plus a shared general pool instead. It
  keeps each class's identity and still gives the 30+ a road.
- *General skills by level.* Every hero would carry the whole pool for free, and the pool would
  flatten the classes.

**Left open on purpose.** Whether `legacy_v2` and `QuickResolve` get retired: skills widen how far
the two `resolve()` paths disagree, but they already disagreed on abilities. The director files it
separately if skills make the disagreement real. Whether the preview's "Power forecast" line gets replaced by a
simulation forecast. The WASD input model.

---

## 2026-09-23: The town builder — placed buildings are profile state, `station` is a hero's one job, `home` is its house, and the town runs only on the live tick

**ACCEPTED by the director, 2026-09-23,** on the owner's answers (houses gate workplace jobs; heroes eat and can starve; multi-passion job skills; live play only). Drafted for `ig-6m2`. The owner, 2026-09-23:
"build their own town, manage work, have the heros have their own house, city management like the
game banished". `GAME_SPEC.md` § The town builder has the design. `SYSTEMS.md` § Town builder has
the numbers. The owner answered its four questions the same day; items 5, 11 and 12 fold them in.

**What moves.**

1. **Placed buildings and the stockpile are `GameSession` state.** There are three additive keys:
   `town_buildings` (a list of `{id, type, q, r}`), `town_resources` (`{wood: float}`, with more
   kinds in later slices) and `town_next_id`. `SAVE_VERSION` is not bumped (the `P2-23` precedent).
   A save without `town_resources` gets `town_start_wood` once. This crosses save boundary #1, so
   each slice needs a real disk round-trip and a `verifier`.
2. **Hex coordinates are axial `(q, r)` integers in the save.** The world position is derived,
   never saved.
3. **The seven halls stay unique, and a hall's id is its type name** (`Forge`, `Sanctum`, and so
   on). `station` values that `ig-wgj.9` saves stay valid, and `building_levels` keeps its indexes.
   Placed buildings get `<type>_<n>`, where `n` comes from `town_next_id` and is never reused.
   - In the first slice, the halls stay authored nodes in `hub/town/town.tscn`, and their hexes
     count as taken.
   - In the second slice, the halls join `town_buildings` at default hexes, and each building type
     gets its own scene. "Renaming a hall node is a save change" then becomes "renaming a hall type
     id is a save change".
4. **A hero's one job is `Hero.station`.** It holds a hall id or a placed workplace id. One field,
   not two, so a hero can never hold two jobs. The `ig-wgj.9` rules carry over to workers:
   - protected, not busy
   - the four dispatch paths are unchanged
   - a worker who is away produces nothing
   - the stationing mutator enforces the slot count
   On load, a workplace id is kept only if that building exists and has a free slot. Otherwise it
   is cleared with a `push_warning`, and the first hero in roster order wins.
5. **A hero's house is `Hero.home`,** a placed House id, saved as the additive key `home`. A house
   holds `house_capacity` heroes, enforced by the mutator and on load. A workplace job needs a home.
   A hall keeper does not, for now (owner ruling, 2026-09-23).
6. **Permadeath keeps one writer.** `home` and `station` live on the `Hero`, so a death takes them
   away. There is no building-to-hero map to clean (rule 8, and the same reasoning as 2026-09-23
   item 5). Demolishing a building, when it exists, clears its residents and workers in its own
   mutator. That is not a death path.
7. **Town rules are pure static functions in one script under `hub/town/`,** following
   `ExpeditionOrders`: hex math, whether a hex is free, and production for a tick. `GameSession`
   mutators call them (`place_building`, `assign_home`, and `station_hero` extended to workplaces),
   and refuse there. The town view spawns buildings from `town_buildings` and emits ids upward, as
   it does today.
8. **Production runs only on the live tick** (`_advance_clocks_in_memory`). The offline catch-up
   (`_advance_orders_in_memory`) makes nothing (`GAME_SPEC.md` § Hard constraints).
9. **The town makes no Summon Stones, Essence or parts,** and `combat/` never reads town state.
10. **No fourth autoload.**
11. **Starvation is a third caller of `kill_hero()`, not a second writer** (owner ruling,
    2026-09-23: "They eat and can starve to death"). Rule 8 is amended to match: `kill_hero()` is
    the only code that removes a hero from the roster, and its callers are the expedition resolver,
    sacrifice and starvation.
    - The pure town script computes the tick: food made, food eaten, the starving clock, and which
      hero is due to die (lowest rank, then lowest level, then newest). It returns an
      `instance_id` or nothing. It never touches the roster.
    - `GameSession`'s live tick applies it: every equipped item goes back to inventory through the
      existing `unequip_item`, then `kill_hero(hero, &"", balance)`. With nothing equipped,
      `kill_hero()` makes no Lost Cache. Its embodied-hero and empty-roster rules apply unchanged.
    - Only housed heroes who are home eat. Away and busy heroes do not, so nothing a hero does on a
      run moves food.
    - One global clock, not one per hero. Three additive keys: `town_resources.food`,
      `town_starving_seconds` and `town_starve_acked`. The clock stops at each death's last
      warning until `acknowledge_starvation()` sets `town_starve_acked`. It resets only once food
      climbs back above the food-low line, so a farm that makes slightly less than the town eats
      cannot hold it off forever (`SYSTEMS.md` § Food and starvation).
    - Like all town state, it runs only in `_advance_clocks_in_memory`. The offline catch-up never
      moves food or the clock. A new hard constraint says so: the town never kills while the game
      is closed (`GAME_SPEC.md` § Hard constraints).
12. **Passions replace the calling** (owner ruling, 2026-09-23: "I like the rimworld inspired multi
    passion idea"). This amends the calling bullet of 2026-09-23 item 5, below.
    - `Hero.passions` holds `passions_per_hero = 2` different professions, saved as the additive
      key `passions` (a list of strings). `SAVE_VERSION` is not bumped. It crosses save boundary
      #1, so it needs a real disk round-trip and a `verifier`.
    - The roll uses a fixed list of eight: the five hall professions in today's order, then
      `woodcutting`, `mining` and `farming`. `Hero.PROFESSIONS` (profession → hall id) stays the
      five halls, because `station` validation reads it. The three workplace professions map to
      workplace types in the town script.
    - The roll is still a stable hash of `instance_id`, with no summon RNG draw: the first passion
      is `ALL[hash(id) mod 8]`, the second is from the other seven by a second hash
      (`hash(id + "#2") mod 7`). New heroes get it at creation.
    - **Migration.** A save with `calling` and no `passions` keeps the calling as the first
      passion, and the second comes from the second hash. A save with neither derives both. On the
      next save, `passions` is written and `calling` is not.
    - A master is a hero whose passions include the profession, at skill 5. Both passions can be
      mastered. The ×4 XP applies to either passion; the balance row `calling_xp_multiplier` is
      renamed `passion_xp_multiplier` in the same change as `balance.tres`, since a row renamed in
      the script but not the resource falls back to its default silently.

**Rejected.**

- *A square grid (`GridMap`).* The art is hex tiles. A square grid fights every tile in the pack.
- *A separate `job` field next to `station`.* Two fields that must never both be set is a bug
  waiting to happen.
- *A building-to-workers map on `GameSession`.* It would need cleaning after a death. That is a
  second writer after `kill_hero()`.
- *Duplicate halls.* A second Forge would do nothing. It would also break type-name ids, `station`
  values and the `building_levels` indexes.
- *Physical hauling and per-building storage.* Banished's logistics cost a lot to build and give a
  gacha game nothing. One shared stockpile.
- *Production while the game is closed.* It breaks § Hard constraints. Changing that is an owner
  ruling and its own entry.
- *Iron, or a town that makes Summon Stones or parts.* Iron needs a crafting tree, which
  § Scope boundaries excludes. Stones or parts would move every income number and the ~327-pull
  spine.

- *Hunger that only slows work.* It was the recommendation. The owner chose death knowingly.
- *A hunger meter per hero.* Deaths come one at a time, so one clock carries the same information,
  and it is one saved number instead of one per hero.
- *A Lost Cache for a hero who starves.* A cache is gear lost out on a run. In the town the gear is
  right there, so it goes to inventory.
- *Removing a starving hero anywhere except `kill_hero()`.* That is a second writer (rule 8).
- *One passion from eight.* A Rites passion would drop from 1 in 5 to 1 in 8, and the SS→SSS wait
  would grow from 5 pulls to 8.
- *Three passions.* 37.5% of heroes would have any given passion. A passion stops being special.
- *A `calling` field kept next to `passions`.* Two fields for one idea, which drift.

**Left open on purpose.** Whether a hall keeper ever needs a house (the ruling says "for now"). Stone,
construction and hall-upgrade numbers now live in `SYSTEMS.md` § Town builder; they and every food
number are set but unfelt.

---

## 2026-09-23: Dev-tool autoloads that exports strip do not count toward the three-autoload cap

**ACCEPTED, owner ruling 2026-09-23.** The Godot AI editor plugin (`addons/godot_ai/`, MIT, v4.2.1)
writes `_mcp_game_helper` into `project.godot` `[autoload]` whenever it is enabled. That autoload
lets the director see and drive the running game: framebuffer screenshots and simulated input.

**Rule.** The cap of three (`SceneRouter`, `SaveService`, `GameSession`) covers game autoloads. An
autoload is exempt only if **all** of these hold:
- It belongs to a dev tool under `addons/`.
- It is stripped from exported builds. Godot AI's `export/mcp_export_plugin.gd` does this.
- It holds no game state, and no game code references it.

Anything else still needs its own ADR.

**Rejected.**
- Patching the plugin so it never registers the autoload. Editor-viewport screenshots would still
  work, but running-game capture and input would be lost, and every plugin update would need the
  patch again.
- Counting it against the cap. That would block the tool, and it guards nothing: the cap exists
  to stop game rules and level state from collecting in globals.

**Check.** After any export, `export/game.pck` must not contain `_mcp_game_helper`.

---

## 2026-09-23: Masterwork draughts are two more supply kinds, not a tier on the old ones

**ACCEPTED by the director, 2026-09-23**, on the owner's ruling to build masterwork draughts now
(`ig-wgj.11`, after `ig-wgj.10`). Drafted by the `godot-architect` hat. Design: `GAME_SPEC.md`
§ Heroes staff the buildings. Numbers: `SYSTEMS.md` § Keepers and professions. This entry exists
because the change crosses two boundaries: the combat seam (#4), since the battle simulation
spends supplies, and the save (#1), since supplies, loadouts, escrow and in-flight battle states
are all saved.

**What moves.**

1. **Two new kinds, `healing_masterwork` and `revival_masterwork`, in every place `healing` and
   `revival` live today:**
   - `GameSession.supplies`
   - battle loadouts, plus their `keep_*` floors
   - order escrow
   - `BattleState.supplies_remaining` and `BattleOutcome.supplies_remaining`

   Each is a plain integer stock, like the two that exist.
2. **One list of kinds.** Today the two kinds are written out by hand all over
   `systems/game_session.gd`: six `for kind in ["healing", "revival"]` loops, about ten dictionary
   literals, and `_validate_loadout`. `combat/battle/*` names them by hand too. That becomes one
   constant on `BattleState`, which both `systems/` and `combat/` may reference, and every site
   reads it. Adding a kind and missing a loop is exactly how a refund or an escrow silently skips
   the new stock.
3. **The old save shape still loads.** Every missing masterwork key reads as 0: in the profile,
   in saved loadouts, in escrow and in in-flight `BattleState`s. `SAVE_VERSION` is not bumped (the
   `P2-23` precedent). **Trap:** `_validate_loadout` requires exactly four keys today. It must
   accept the old four-key shape, or the loader must add zeroed masterwork keys first. Otherwise
   any save with an order in flight fails to load once this ships.
4. **The battle rule lives in the simulation only.** Restore amounts are `balance.tres` rows.
   - Auto-use spends the regular draught first, and a masterwork one only when that run's regular
     stock of the same kind is gone.
   - Manual use can pick either tier.
   - The 15-second per-user cooldown and the revival range are shared across tiers.
   - "Reserve last revival" counts both tiers together.
   - The unattended run, the watched run and the repeat safety forecast all go through the same
     `BattleSimulation` code, so they cannot disagree. Only `battle_v1` orders spend supplies
     today, and the new kinds follow that. No legacy path gets a draught rule of its own.
5. **Crafting is gated in the mutator.** The craft action refuses a masterwork kind unless
   `GameSession.keeper_is_master(&"Apothecary")` is true, with an exact preview. The Alchemy
   discount applies. Stock already brewed stays usable after the alchemist dies or leaves.

**Rejected.**

- *A tier field on the existing stocks* (for example `healing: {regular, masterwork}`). It turns an
  integer into a dictionary in every saved profile, loadout, escrow and battle state. That is a
  shape change, not an additive key, and every reader would need a migration.
- *A separate masterwork supplies dictionary.* That is a second escrow, refund and validation path
  beside the first. Refund-exactly-once is already hard to hold on one path.
- *Restore strength scaled by the brewer's skill.* Every draught would then carry its own quality,
  so stocks stop being integers. The owner's rule is binary: master or not.
- *Letting the forecast assume regular draughts only.* Then the forecast and the run disagree, and
  that is the failure the repeat safety check exists to prevent.

**Sequencing.** This touches `combat/battle/*`. It does not start while another bead is editing
those files. Engine access is serialized as usual.

---

## 2026-09-23: The town is the interface — buildings open panels, heroes staff them, the body is saved, ambient heroes are not

**ACCEPTED by the director, 2026-09-23**, with the staffing amendment (item 5) folded in. Drafted
by the `godot-architect` hat for `ig-wgj`. The owner scheduled the town on 2026-09-23 and asked for
the UI to live in it: click the blacksmith to upgrade, click the summoning place to summon, and see
your heroes walking around. The same day the owner ruled that the heroes themselves are the
shopkeepers, with their own profession skills. `GAME_SPEC.md` § The town hub and § Heroes staff the
buildings have the design. `SYSTEMS.md` § Keepers and professions has the numbers.
`ARCHITECTURE.md` § The town is the interface has the boundaries.

**What moves.**

1. **Buildings open panels by click.** This supersedes "proximity-gated panel visibility" from
   2026-08-13. It also supersedes the four-tab navigation from 2026-09-22's hub scene seam. The
   views stay as panel containers, with their `%UniqueName` controls intact. The Hall tab's mixed
   contents split across the buildings that own them. The opaque full-screen background from
   `hub_ui_builder.gd` goes, because it is the reason the 3D town has never been visible. A compact
   building list stays as a keyboard fallback: controller support remains a target.
2. **The embodied hero id is saved `GameSession` state.** It is additive: an absent key reads as
   "no body". On load it is dropped if the hero is gone or busy. It is enforced at the mutation
   boundaries, in `is_hero_protected()` and each dispatch entry point, which is where
   busy/protected checks already live (2026-09-22). This is a save-boundary change, so its ticket
   needs a real disk round-trip and a `verifier`.
3. **The town is a view under `hub/town/`,** instanced by `hub.tscn`. It emits ids upward, and
   `hub.gd` owns which panel opens.
4. **The KayKit model and animation loader moves to one helper under `heroes/`,** shared by the
   battle view and the town.
5. **Heroes staff the buildings (amendment, 2026-09-23).** A hero's station, its calling and its
   XP per profession are fields on `Hero`. They are saved through `Hero.to_dict/from_dict` as
   additive keys (`station`, `calling`, `profession_xp`), so this crosses save boundary #1. It needs
   a real disk round-trip and a `verifier`, and `SAVE_VERSION` is not bumped (the `P2-23` precedent
   for additive keys). `station` holds a town building id, and those ids are the building node
   names in `hub/town/town.tscn` (`Forge`, `Sanctum`, `TrainingHall`, `Reliquary`, `Apothecary`),
   the same ids `town_view.gd` emits. Renaming one of those nodes is now a save change too.
   - **Masterwork is a gate checked in the mutator.** Whether a building's keeper is a master
     (calling = the building's profession, and skill 5) is decided by `GameSession`, inside the
     action it gates. The UI only reflects the result. There are three gates:
     - `enhance_item` and bulk enhance read the capped value from `Item.compute_enhance_cap`
       (Forge, +13 to +15).
     - `rank_up_hero` refuses SS→SSS without a master priest who is home at the Sanctum (owner
       ruling, 2026-09-23). This is the only rank-up mutator, and the only caller is `hub.gd`.
     - The draught craft refuses masterwork kinds without a master alchemist (see the masterwork
       draughts entry above).
     What a master made (enhance levels, an SSS rank, draughts) is ordinary state and outlives the
     master. It is not re-checked on load, so heroes already at SSS keep their rank.
   - **Protected, not busy.** A stationed hero counts in `is_hero_protected()`, so sacrifice and
     bulk sacrifice refuse it. It is **not** in `is_hero_busy()`. Stationing must not block equip,
     rank-up or dispatch.
   - **The four dispatch paths are unchanged for keepers.** `dispatch_expedition`,
     `dispatch_force` (through `_preview_force_data`), `dispatch_rescue` and `recover_cache` accept
     a keeper, because keepers can be sent out by design. Their existing body check stays. The
     dispatch preview only reports which buildings lose their keeper while the force is out.
   - **The body and a station compose.** A keeper can be the body. The body is home, so the
     station keeps working. Each rule keeps its own check. Neither implies the other.
   - **Permadeath keeps one writer.** The station lives on the `Hero`, so when `kill_hero()`
     removes a hero, its station goes with it. No second code path runs after a death (rule 8).
   - **One keeper per building.** The `GameSession` stationing mutator enforces it. On load, if
     two heroes claim one building, the first in roster order keeps it and the others are cleared
     with a `push_warning`. Unknown building or profession ids are dropped the same way.
   - **The calling comes from a stable hash of `instance_id`.** *Amended 2026-09-23: passions
     replace the calling; see the town builder entry, item 12. The stable hash stays.* New heroes
     get it at creation.
     Legacy heroes get it on load, and it is written at the next save. `instance_id` is 16 random
     bytes, so the hash is uniform. No summon RNG draw is added, so seeded summons and their tests
     do not shift.
   - **Keeper bonuses go through the existing pure formulas.** `GameSession` finds the home
     keeper's skill for a building and passes it as one more argument to the formula that already
     reads that building's level (`Item.compute_salvage_yield`, `Hero.compute_essence_yield`, the
     Training Hall XP multiplier, the Reliquary lifetime, the draught cost). The magnitudes are
     `balance.tres` rows (rule 9).
   - **Combat never reads a profession.** `combat/`, `Hero.compute_final_stats`, `hero_power` and
     the repeat forecast stay blind to it. A test asserts that final stats are identical whatever
     a hero's professions are.
   - **XP only builds up on the live tick** (`_advance_clocks_in_memory`), never in the
     offline catch-up (§ Hard constraints). The calling multiplier is applied when XP is earned,
     so the saved total is plain XP, and the skill level is derived from it on read.

**Rejected.**

- *A separate town scene.* Already rejected on 2026-08-13; reaffirmed. Instancing a sub-scene is
  not routing.
- *Keeping proximity-only panels.* The owner asked for click, and on 2026-09-23 ruled that a far
  click walks the body there and then opens the panel. That is a view behavior, not a boundary.
- *Treating the body as busy.* `is_hero_busy()` also gates equip, unequip and rank-up. The body
  should be gearable. Only spending it (dispatch, sacrifice) is refused.
- *Not saving the body.* It would be cheaper, and it would lose the player's choice on every
  launch. The rule "you must step out before you spend it" is clearer when the body is stable.
- *Auto-picking a body.* It would silently lock a hero out of dispatch without the player ever
  choosing. `GAME_SPEC.md` says stepping out is a deliberate act. Stepping in should be too.
- *Town code calling `BattleUnitView._shared_clips()`, or a copy of the loader under `hub/`.* The
  first couples the town to battle-view internals. The second drifts: two libraries, two
  loop/root-pin rules.
- *Saving ambient hero positions or townsfolk state.* That is presentation in the save, which
  adds save-boundary surface for no gameplay. It is re-derived on load.
- *A `TownManager` autoload.* Nothing the town holds is both persistent and outside the profile.
- *Making a station a busy state.* It would block dispatch, equip and rank-up. It would also erase
  the tension the owner's ruling creates: your best fighter may be your best smith.
- *A building→keeper map on `GameSession`.* After a death it would need cleaning, either in
  `kill_hero()` or on load. That is a second place that edits state after a death. A field on the
  `Hero` leaves with the hero.
- *Professions as a seventh stat, or read in `compute_final_stats`.* The six stats are settled by
  ADR. A profession is read by its own building and nothing else.
- *Rolling the calling from the summon RNG.* It would shift every seeded summon. Legacy heroes
  would also need a migration roll, and a load must not change on each run.
- *Decorative, non-roster keepers.* The owner ruled that heroes are the keepers.
- *Re-checking masterwork on load, or clawing back a dead master's work.* Enhance levels and
  draughts are ordinary state. If a master's death undid them, a second path would edit state
  after a death (rule 8).
- *A crafting system so the Forge can "make masterwork equips".* § Scope boundaries excludes
  crafting trees. Masterwork gates an output tier the building already has, and adds none.

**Left open on purpose.** The town builder has its own entry above (accepted 2026-09-23).
Research is parked there (owner, 2026-09-23). Masterwork draughts have their own entry above.

---

## 2026-09-22: Autonomous squads, RTS intervention, and recoverable downed heroes

The owner approved the director's complete squad-command proposal and downed/rescue rules,
then explicitly authorized implementation with parallel Sol/Luna workers. `ig-544` contains
the accepted implementation plan, exact data/command contracts and validation gates;
`ig-yzc` now means observing and commanding an existing expedition, not piloting one hero.

One fixed-tick simulation serves watched and unattended battles. Persistent battle checkpoints
are an explicit extension of dispatch-order profile data; no scene objects enter the save or
autoload, no fourth autoload is added, and combat rules remain static domain functions.
`BattleView` is a new SceneRouter destination. It renders snapshots and submits commands,
never rewards or deaths. Practice owns a local simulation with no profile consequences.
The legacy action arena/CombatResult seam is preserved for compatibility but no longer defines
the production expedition direction. The six-stat model and one Wave ramp stay unchanged.

**Rejected:** a decorative battle replay over an unrelated statistical result, a second loot
settlement when opening a battle, immediate permanent deletion at zero HP, forcing thirty
individual skill bars onto the player, and building a seamless procedural world for the first
regional mission. Squads remain 1-5 member presets; authored missions set their force caps.

Route minimum and battle time advance in parallel. Completion waits for both; a wipe creates
a stranded incident. Offline processing advances the current run only. Tactical pause stops
the viewed battle, not the other expeditions, and clears on leaving/reload. Supply allocations
are shared per-force spending escrow; unused allocations refund exactly once. Explicit
commands and terminal changes use the existing save transaction boundary.

Downed allies can be revived by living teammates or carried out. A full force wipe permits
rescue or abandonment. Incidents are separate from lost-gear caches and from one another;
failed rescuers join only their source incident. Its reviewed active-play deadline never ages
offline or resets on failure. An active rescue may finish after expiry; remaining stranded
heroes are then finalized through Expedition and the existing sole roster-removal writer.

Rescue settles at the end of its real fight/extraction, without a separate return timer.
Applying raid/region force-size travel to five rescuers produces minimum waits of 720/1800
seconds against an initial 900-second incident window, obstructing successive carry attempts.
Rescue grants no farming rewards, so the expedition return gate serves no purpose there.
Normal full wipes close their order immediately; partial withdrawals wait for survivor return,
then create the incident and close the source order atomically to avoid conflicting reservations.

Schema 3 migration preserves stable identity/resources/orders. For v2 in-flight orders,
prior offline time reduces remaining route once and the new battle starts at tick zero.
This may extend the previous ETA but cannot invent combat, rewards or immediate deaths.
The migration is committed before play and invalid/future saves remain protected.

The first native battlefield capture exposed unreadable small units, an empty gray surround,
and a selection inspector that did not refresh while paused. The director set initial camera
sizes to 32/44/60 for standard/raid/region, centered the standard view at world z=-4, and kept
a local dark forest environment with a larger ground apron, subtle grid and readable chibi
heads/class silhouettes. These are presentation rules; camera or rendering never changes the
simulation. The paused inspector refresh is required for tactical commands.

Initial enemy-budget HP×2/ATK×0.20 values failed all eight measured starter-team runs. Revised
HP×1/ATK×0.04 remains provisional until measured from actual spawned actors. The failed
in-memory override experiment is explicitly excluded from balance evidence. After the ig-9gf
reach fix, ig-el4 (2026-09-24) retuned them to HP×1.15/ATK×0.03, measured on spawned actors
(SYSTEMS.md § Provisional shared combat numbers). They stay provisional until played.

The first scene/input seam is desktop RTS: box selection, contextual commands, squad hotkeys,
orthographic pan/zoom, abilities/items and tactical pause. The historical first-class action
gamepad requirement remains a future RTS input task, not a claim of gamepad acceptance here.
Chibi primitives are the authored first visual style. Ability/supply/raid numbers are
provisional and must not be described as playtested merely because tests or profiling pass.

---

## 2026-09-22: Timed parallel expeditions, persistent teams, and protected bulk management

Owner approval: implement all of the director's `ig-6l4` proposal. This supersedes the original
`GAME_SPEC.md` no-clock/no-offline-accrual constraint for already-dispatched expeditions. It does
not add an energy system, paid waits, servers, or unlimited offline farming. Each dispatched
run may finish while closed; a repeat starts only in the running app. Separate teams can work
concurrently, with exclusive reservation of their heroes and equipped gear.

Duration falls with the square root of strength relative to the zone's team-size-scaled power,
has a per-zone floor, then accounts for the same workload being covered by fewer heroes through
`5 / team_size`. The last factor matters because existing enemies already scale down linearly:
without it, splitting a squad into five solo parties would multiply output at the same combat
difficulty. Existing combat damage, rewards, and success semantics remain unchanged. A local
lost-wave roll is not an expedition defeat; surviving the boss still completes the run.

**Rejected:** a timer added to the old click loop without presets or repeat orders, manual
reward-claim chores, fixed dispatch slots unrelated to roster depth, and a new stamina currency.
Finite orders stop on casualties/retreat/failure or a stop-after-return request. Unlimited orders
require a worst-case attrition forecast using the actual wave ramp and retreat rule; one lucky
clear is not proof of safety. Timing values remain explicitly provisional in `SYSTEMS.md`.

Stable serialized hero/item identities and schema-2 migration are required by saved presets and
in-flight orders. Presets preserve missing members instead of silently substituting. Orders
capture membership/destination at dispatch. Timed orders belong to the persistent profile,
while transient wave HP still belongs to `Expedition`; this does not reverse the rejected
combat-state autoload decision. There are still exactly three autoloads. Pure expedition and
bulk rules live under `hub/`. Shared balance stays in `balance.tres`; per-zone durations join
the existing authored recommended-power/wave/reward data on `ZoneDefinition`.

`GameSession` batches a return into one state change and `SaveService` persists it atomically,
including rewards, deaths, cache, report and order advancement. A saved local RNG seed makes a
pre-commit retry reproducible.
Write failure rolls memory back; future/invalid new-schema saves refuse play and writes instead
of becoming overwritable fresh profiles. The public combat-result seam and central hero-removal
path remain unchanged. Confirmation previews are revalidated against current identities,
protections, inputs and costs before bulk operations commit.

**Recovery changes deliberately.** Expedition-count cache aging is unsuitable when many
returns can arrive unattended. Caches now age in active recovery minutes, not completed runs
or offline time. New gear losses pause this clock until explicitly reviewed. The base window
is 15 minutes, extended by 5 minutes per Reliquary level; its existing damage reduction remains.
The old elapsed-turn damage term becomes elapsed active minutes. Legacy caches map old elapsed
turns to minutes and begin paused. This preserves the Reliquary's two functions while removing
the punishment for running more teams. These timings require playtesting; source arithmetic
does not settle their feel.

**Hub scene seam:** `hub.tscn` remains the existing main scene. Its panels are reorganized into
Expeditions, Teams, Armory, and Hall views under the same CanvasLayer, with modal confirmation
and pause controls outside view visibility. Reparenting requires updating every affected
`.tscn` connection path and runtime-verifying all existing unique-name lookups and handlers.
No separate town scene or new SceneRouter destination is introduced. The established ink-green,
brass and ivory theme is retained, including dark focused text on brass primary buttons.

The four views are assembled from native Godot controls by `hub/hub_ui_builder.gd` before
`hub.gd` resolves its `@onready` bindings. This replaces the former static panel subtrees and
their `.tscn` connection paths with named controls and script-connected signals; the 3D hub,
CanvasLayer, confirmation and pause roots remain in `hub.tscn`. The tradeoff is that the full
panel layout is previewed by running the scene rather than by inspecting the static scene tree.
Shared roster/detail controls avoid duplicating selection state across Teams and Armory.
Existing `%UniqueName` contracts and interaction tests must remain valid after assembly.

Favorites, preset membership, and active reservations protect heroes from bulk sacrifice;
equipped/favorite items are excluded from salvage. Enhancement may improve favorite inventory
items within explicit per-rank budgets. Conversion exposes a keep-at-least reserve and never
cascades ranks. No automatic destructive processing is added. Existing controlled-expedition
and mid-run-intervention directions (`ig-544`, `ig-yzc`) remain outside this implementation.

---

## 2026-09-21: Serena reinstated on demand for native GDScript symbols

The owner requested Serena, GitNexus, and Ponytail for this repository. Serena is enabled in the
repo's Codex configuration and connects to Godot's built-in GDScript language server on port 6005.
It uses an editor instance that is already open for this project; it does not install another
language server or add an always-running daemon.

This supersedes the 2026-08-04 removal decision only for requested Serena use. The lifecycle
constraint remains: the Godot editor/LSP and `tests/import_gate.ps1` are mutually exclusive because
both access `.godot/`. Close the editor before the build gate, and do not start or stop a user's
editor process as part of tool setup.

GitNexus is registered only as a bounded local index. GitNexus 1.6.9 and the current 1.6.12 release
do not support GDScript or `.gd` in their structural parser/extension maps, so its presence is not
evidence of symbol, call-graph, or impact coverage for game code. Ponytail 4.10.0 is already enabled
as a user plugin and needs no repository copy.

---

## 2026-08-13: The town is `hub.tscn` with an avatar, and the avatar is a controlled hero

User ruling, closing `TASKS.md` D-01a. Two answers, one architectural and one design.

**The town does not get its own scene.** `hub/hub.tscn` is already a `Node3D` — camera, ground,
five building meshes under `Buildings/` — with the roster/equipment/buildings/summon/sacrifice/
expedition panels on a `CanvasLayer` in the same tree. The walkable town is that scene gaining a
player-controlled body and proximity-gated panel visibility. `SceneRouter` is untouched, rule 5
is untouched, and no new seam appears. Written up in `ARCHITECTURE.md` § The town is `hub.tscn`.

**Rejected: a separate `town.tscn` routed to from the hub.** This is the reading the direction
table was warning about, and it is the expensive one for a reason that is easy to miss — it does
not just duplicate scenes, it makes every shipped hub panel reachable from two places, which
means every panel needs an answer for "which scene am I in" forever after. The cheap version of
that (town hosts *copies* of the panels) is the "every shipped hub feature gets rebuilt" outcome
stated verbatim in `TASKS.md`'s D-01 row. Nobody would choose it deliberately; it gets chosen by
assuming a new feature needs a new scene. It does not — the 3D hub has been sitting there since
the skeleton.

**The player embodies a roster hero, swappable at will**, not a summoner avatar.
`GAME_SPEC.md` § The town avatar is the design half. The architectural consequence is the one
worth recording here: **an embodied hero cannot be sent on an expedition.** That is a design
rule with teeth (you must step out of a body before you can spend it) and it is deliberately
*not* implemented as an exception inside the permadeath path — it is a filter on team selection,
upstream of `Expedition.resolve()`, which keeps rule 8 at exactly one writer with no special
case. A rule that reads "permadeath, except when" is how single-writer boundaries rot.

**Rejected: the summoner as the town avatar.** It is the more literal reading of Player fantasy
("You never fight as yourself") and it has a real advantage — an avatar with zero coupling to
permadeath cannot be deleted out from under the camera. Refused because it buys that safety by
putting a body in the world that the roster does not contain, which needs its own model, its own
answer to "what am I to the roster", and an explicit hand-off at the gate for `D-02` where the
summoner stops and a hero starts. The hero avatar makes `D-02` continuity instead of a seam, and
the fantasy still holds: the summoner is steering, which is what the arena already does.

**What changes in the code: nothing.** This ruling produces no scene, no script and no behavior.
`D-01` is still unwritten and still unscheduled — the core loop comes first and the Phase 2 exit
question still governs. What it removes is the reason `D-01` could not be *written*.

---

## 2026-08-11: The arena is a combat-feel prototype; permadeath is not wired to it

User ruling, and it reverses a published line in `GAME_SPEC.md`. That document's Combat model
section said "Permadeath applies identically in both paths" from the first commit. It no longer
does.

**The arena is where combat feel gets prototyped, not a path the core loop resolves through.**
It keeps the seam it already has — a real `Wave` in, a real `CombatResult` out — and that result
stays **display-only** for the foreseeable future. `Expedition.resolve()` remains the sole
permadeath consumer (rule 8, unchanged and now load-bearing for a second reason).

**Why this is an ADR and not a `KNOWN_ISSUES.md` line.** Arena permadeath was unfiled, not
decided. `P2b-05`'s Findings recorded it as "still unwired and now reachable in one sitting",
which reads as a gap somebody should close; the next reader would have closed it. It is not a
gap. Writing it down as a decision is what stops the wiring from happening by default.

**What changes in the code: nothing.** `hub.gd`'s `_show_pending_arena_result()` already only
prints, `arena.gd` already never calls `kill_hero()`, and no ticket was open against either.
The one edit this ruling actually earns is the defeat string, which said a hero *fell* — the
lie was cheaper to fix than to leave (`hub/hub.gd:741`).

**Permadeath in player-controlled combat is deferred, not cancelled.** It lands with controlled
expeditions (`GAME_SPEC.md` § Direction), where a death is the consequence of a run the player
chose to walk into rather than the outcome of a practice bout entered from a hub button. Nothing
about that later wiring is designed here.

**Rejected: wire permadeath to the arena now, matching quick resolve.** It is the consistent
answer and the wrong one at this stage. Every arena number is `PROVISIONAL` and unplayed —
`arena_enemy_hits_to_kill_hero = 3` most of all, since nobody has died in the arena — so the
first thing permadeath would price is a feel value nobody has validated. Tuning combat weight is
a loop you want to run dozens of times per sitting; permanent loss per attempt makes that loop
cost a hero, and the tuning stops happening.

**Rejected: strip the arena's `CombatResult` down to a feel harness with no seam.** Tempting on
laziness grounds — the result is display-only, so the type buys nothing today. Refused because
the seam is the one structural decision `DECISIONS.md` 2026-08-01 made before the vertical slice
existed, and a controlled expedition is a third `resolve()`-shaped consumer of it. The arena is
the only live proof that a second implementation can satisfy the shape at all.

**Consequence for `KNOWN_ISSUES.md` § "Quick resolve and the arena will disagree".** Divergence
between the two paths is no longer a defect to size — the arena resolves nothing, so there is no
outcome to disagree about. That entry is amended rather than closed: it comes back the moment a
played path resolves a real run.

---

## 2026-08-06: The 2026-08-01 rejection of rank-up/salvage logic on `GameSession` is reaffirmed, not reversed — three shipped methods are debt

`godot-architect` ruling on a conflict `tech-lead` flagged while scoping `P2-06a`: the 2026-08-01
"Three autoloads, hard cap" entry rejects "putting rank-up and salvage logic as methods on
`GameSession`, which would make them untestable without booting the engine." `salvage_item`
(`P2-05d`), `enhance_item` (`P2-05f`), and `convert_parts` (`P2-05g`) shipped anyway, as instance
methods on `GameSession` that inline their own validation and arithmetic
(`systems/game_session.gd:57,70,86`).

**Ruling: the code is wrong, not the ADR.** The rejection's predicted cost came true exactly as
written — every GUT test that exercises these methods reaches them through the live `GameSession`
autoload singleton (`GameSession.salvage_item(...)` etc. in `tests/unit/test_equipment.gd`), and
there is no `GameSession.new()` anywhere in the codebase to test the logic in isolation. That is
evidence the original warning was correct, not evidence the project outgrew it. `CODING_RULES.md`
§ Autoloads still states the general principle in the present tense ("Game rules do **not** live
on autoloads") and its own worked example is named `compute_essence_yield(fodder, target,
balance) -> int` — the exact function `P2-06a` needs — so no reconciling document was ever
updated to bless the pattern that shipped. This was drift, not a considered re-decision.

The distinction the ADR draws is between **structural roster/inventory bookkeeping** (moving an
item between arrays, erasing a roster entry, deduplicating a cleared-zone flag — `kill_hero`,
`equip_item`, `unequip_item`, `mark_zone_cleared`, `add_hero`) and **balance-driven rule logic**
(a cost formula, a threshold check against a `BalanceTable`-sourced number, a multiplier). The
former is unavoidably a `GameSession` method because the state lives there and nothing else
should reach in and mutate it directly (that would just be a second, worse violation). The latter
is exactly what the rejection named, and `salvage_item`/`enhance_item`/`convert_parts` are the
latter: they take `balance: BalanceTable` and compute a cost or a credited amount inline instead
of calling a pure function that does.

**Disposition of the three shipped methods:** debt. Not reverted here — a working, tested,
save-round-tripped feature does not get unwound by a documentation ruling — but named so a future
pass doesn't read them as precedent. A remediation ticket (extract each method's arithmetic into
a `static func` taking the same arguments plus `balance`, leaving the `GameSession` method as a
thin validate → call → mutate → emit wrapper) is `tech-lead`'s to open; this entry is the citation
for why.

**Outcome (`P2-12`, landed).** Two of the three were extracted — `Item.compute_salvage_yield` and
`Item.compute_enhance_cap`, both pure `static func`s that `tests/unit/test_equipment.gd` now calls
without an autoload in the test body. `convert_parts` was **not**, deliberately: its arithmetic is
`-3` and `+1` against a fixed rank index, with no `BalanceTable` number in it at all, so it is not
the "balance-driven rule logic" this entry defined the debt as. `upgrade_building` shipped the same
inline `10 * (level + 2)` shape after this entry was written and is the one open instance; its only
honest home is a `buildings/` file that does not exist, so it stays named rather than relocated.
The ruling itself is unchanged by any of this.

**`P2-06a` may add `sacrifice_hero` and `rank_up_hero` to `GameSession`** — the orchestration
(precondition checks against `roster`/`equipped`, calling `kill_hero()` for removal per
`ARCHITECTURE.md` r8, mutating `essence`, incrementing `resonance`, one `roster_changed.emit()`)
is structural bookkeeping of the kind `kill_hero` already does, and `sacrifice_hero` cannot be
relocated off `GameSession` regardless, since r8 makes `kill_hero()` the sole roster-removal call
site and only `GameSession` may call it as an internal step of one atomic operation. **But the
yield/cost arithmetic may not be inlined into those methods.** `P2-06a`'s ticket body must extract
two pure functions — `compute_essence_yield(fodder: Hero, target: Hero, balance: BalanceTable) ->
int` (the resonance-tripling condition included) and `compute_rank_up_cost(hero: Hero, balance:
BalanceTable) -> int` — that `sacrifice_hero`/`rank_up_hero` call before applying the result. This
is a naming/placement correction to acceptance criteria 2–3 as currently written, not a redesign:
the ticket body's own "Existing architecture" section already cites `CODING_RULES.md`'s
`compute_essence_yield` shape without applying it. The ticket body's line "Follow the code;
reconciling the ADR text is outside this ticket's remit" is struck by this ruling — the ADR text
did not need reconciling, the ticket's method bodies do.

**Rejected (this entry):** editing the 2026-08-01 sentence to say the opposite, on the theory that
four tickets shipping the same pattern makes it retroactively correct. Frequency of violation is
not evidence a rule should change; it is evidence nobody was checking. Also rejected: reverting or
refactoring `salvage_item`/`enhance_item`/`convert_parts` as part of this entry — that is a code
change belonging to an implementer ticket, not a documents-only ruling.

---

## 2026-08-02: The combat seam's second argument is `Wave` (`zones/wave.gd`, `RefCounted`), not `WaveDefinition`

`ARCHITECTURE.md:96` committed to `func resolve(team: Array[Hero], wave: WaveDefinition) ->
CombatResult` before `WaveDefinition` existed anywhere. A repo-wide sweep (all `.gd`/`.tscn`/
`.tres`/`project.godot`, non-docs) found zero references to `WaveDefinition` — no field list, no
consumer, nothing to preserve by keeping the name. P2-01b stored `ZoneDefinition`'s ramp
(`trash_wave_count`, `trash_wave_start_fraction`, `trash_wave_end_fraction`, `boss_fraction`) and
explicitly declined to write the interpolation that turns those endpoints into one wave's actual
composition, deferring the question to whoever names the type P2-03 implements against.

**Reason:** rules 2–3 reserve the `Definition` suffix and the `Resource` base for **authored**
data a human edits in the inspector — confirmed against the only two other implementations in
the tree, `heroes/hero_definition.gd` and `equipment/equipment_definition.gd`, both pure
`@export`-only `Resource`s with no methods. A wave is not that: nobody hand-authors individual
wave `.tres` files, and `zone_definition.gd` (read in full) stores only the ramp's endpoints, not
per-wave values — the per-wave composition is *derived* by interpolating that ramp for a given
index, at runtime, once an expedition is underway. That derivation is exactly the "runtime state
lives in `RefCounted` domain objects, never in a Definition" split rule 3 already draws for
`Hero`/`HeroDefinition`; a wave's relationship to `ZoneDefinition` is the same shape.

Naming it `zones/wave.gd` rather than `combat/wave.gd` follows that same precedent: `Hero`
(runtime) sits next to `HeroDefinition` (authored) in `heroes/`, so `Wave` (runtime) sits next to
`ZoneDefinition` (authored) in `zones/`. `combat/` keeps owning only what it produces
(`combat_result.gd`); it does not also own the type of the data fed into it.

Whatever computes the interpolation must do so in exactly one place and pass the same `Wave`
instance to both `resolve()` implementations. `CLAUDE.md` calls the two combat implementations
"independent... that must agree" — if each path re-derived a wave's enemy composition from
`ZoneDefinition`'s raw fractions independently, a lerp bug in one path would silently make that
path easier or harder than the other for the same zone and index, which is a correctness
regression the seam exists to prevent, not a legitimate independence between the two
implementations. Passing a pre-built `Wave` makes that agreement structural rather than a
discipline someone has to remember.

Also considered and rejected: taking `(zone: ZoneDefinition, wave_index: int)` directly and
dropping the wave type entirely, since it needs no new type at all and `ARCHITECTURE.md` already
warns against the combat seam growing. Rejected because it relocates the interpolation into
`combat/` itself (or worse, into each of the two implementations separately) with nothing in the
signature forcing both paths to share one computation — the exact duplication risk above. Adding
`Wave` is not seam growth in the sense the existing warning targets: that warning is about the
seam's *implementation shape* (no base class, no strategy registry for the two `resolve()`
functions), not about the number of plain data types crossing it — `CombatResult` already crosses
the seam on the way out without objection, and `Wave` is the same kind of thing on the way in.

**Rejected:** keeping the `WaveDefinition` name/`Resource` base (violates rules 2–3, since it
would carry runtime-derived data under the authored-only suffix); authoring per-wave `.tres`
files to make the `Definition` label literally true (nobody has asked for this, and it
contradicts what `ZoneDefinition` actually stores — a ramp, not a per-wave table); and dropping
the wave type in favor of `(zone, wave_index)` args (moves the "must agree" duplication risk into
`combat/`, where it's harder to catch, instead of eliminating it).

---

## 2026-08-02: Consumers reach `balance.tres` via `preload()`, not an autoload or `GameSession`

P2-01d-2 was blocked on this: `RANK_NAMES` "moves onto `BalanceTable`" only fixes where the data
ends up, not how anything downstream of the top of a call chain gets a `BalanceTable` reference
to pass into the pure functions `CODING_RULES.md` already specifies.

**Reason:** a repo-wide sweep found zero existing `preload`/`load`/`ResourceLoader.load` call
sites anywhere in this codebase's `.gd` files — this is a first-precedent decision, not a
convention lookup — and zero prior sketch of a registry/service-locator pattern in code, ADRs, or
`TASKS.md`. Godot's `ResourceLoader` caches by path: every `preload("res://balance.tres")`
anywhere in the project returns the same object, so no single call site needs to own loading it
and hand out the reference — the coordination problem a `GameSession`-held reference would exist
to solve doesn't exist. Putting it on `GameSession` instead would grow the one autoload whose
sole justification is surviving scene changes (`ARCHITECTURE.md`'s autoload table only lists
roster/inventory/buildings/caches/currencies under its ownership) and would make every
balance-consuming function's test depend on booting `GameSession` first to obtain it — the exact
"untestable without booting the engine" failure the three-autoloads ADR already rejects for
methods on a singleton. P2-01d's own acceptance criteria already assume a standalone headless
test can `preload`/`load` `balance.tres` directly with no `GameSession` involved; that only holds
if the production path is the same call.

The mutation hazard of one shared Resource instance (writing into an exported array in place
corrupts it for every consumer and can persist to disk) is identical under a `preload()`, a
`GameSession`-held reference, or an explicit pass-down — it is a property of sharing one instance,
not of how a consumer obtained the reference, so it is not a point against `preload()`
specifically. `TASKS.md`'s P2-01d ticket already documents the discipline (read-only by
construction, derive a local value, never write back) at the one consumer that comes close
(P2-07's building effects); no new enforcement mechanism is being added for it here.

**Rejected:** `BalanceTable` as a fourth autoload — no case exists for a permanently-loaded root
node over a plain Resource with a cached path. Also rejected: `GameSession` holding a
`BalanceTable` reference and consumers reading `GameSession.balance` — scope creep on the one
autoload already at its stated limit, and it reintroduces an engine-boot dependency for testing
balance-consuming functions that a plain `preload()` doesn't have.

---

## 2026-08-02: `Hero.rank_label()` takes `balance: BalanceTable`, not a UI-side lookup

Follows from the entry above and from `RANK_NAMES` moving off `Hero` (2026-08-01 entry below). A
sweep found exactly three real consumer call sites of `Hero.RANK_NAMES`/`rank_label()`:
`hub/summon/summon.gd:17`, `hub/hub.gd:26`, `hub/hub.gd:35` (`heroes/hero.gd:7,20-21` is the
definition itself, not a consumer) — the prior 2026-08-01 entry's claim that
`tests/save_roundtrip_check.gd` also references `RANK_NAMES` does not hold; that file has zero
hits for it.

**Reason:** `rank_label()` stays an instance method on `Hero` and gains a `balance: BalanceTable`
parameter — `func rank_label(balance: BalanceTable) -> String` — indexing `balance.rank_names`
instead of the removed `Hero.RANK_NAMES` const. This is the smallest diff at the three real call
sites (add one argument, once each), it mirrors the exact shape `CODING_RULES.md` already
prescribes for functions that need balance data, and it keeps "describe this hero" behavior next
to the `Hero` it describes rather than teaching every UI call site to index a `BalanceTable`
array (and repeat the clamp) directly.

This is **not** a scene↔script boundary change under `CLAUDE.md`. `hub/hub.tscn`'s only
`[connection]` entries wire `_on_summon_pressed`/`_on_expedition_pressed` by method name, and the
`pressed` signal carries no arguments — adding a parameter to an internal call to `rank_label()`
inside those method bodies renames no node, no `%UniqueName`, and no `[connection]` entry. The
recommended access shape (a `const` `preload` inside `hub.gd`) needs no new node or unique-name
binding either. A `verifier` pass on the resulting diff is still reasonable given the file sits on
that seam, but is not mandated by `CLAUDE.md`'s own definition of boundary item 2 for a diff of
this shape.

**Rejected:** a shared static helper (e.g. a `RankLabels` free function) ahead of a second real
consumer — `EquipmentDefinition`/`Item` don't exist until `P2-01c`, and building shared
infrastructure for a duplication that isn't real yet repeats the ordering the "Skeleton first,
architecture third" entry below already rejected. Also rejected: a lookup method on `BalanceTable`
itself — the 2026-08-01 entry already commits `BalanceTable` to holding "only exported data, no
methods," and the smallest diff that respects that without reopening it keeps the method on
`Hero`.

---

## 2026-08-01: `balance.tres` is one `BalanceTable` Resource, not several

P2-01d left the shape of the shared tunables container as an open `godot-architect` call:
one `BalanceTable` holding every table in `docs/SYSTEMS.md` (rank multipliers, level caps,
affix/socket counts, essence bases, rank-up costs, summon weights, building effects), or
several smaller Resources split by subsystem.

**Reason:** r9 already names a single file (`balance.tres`), and `CODING_RULES.md`'s own
convention is "prefer one Resource type with exported fields over N subclasses" — the same
reasoning that gave `EquipmentDefinition` one shape instead of ten. More concretely,
`SYSTEMS.md`'s own formulas already cross-reference multiple tables in one expression (the
sacrifice formula reads `essence_base[fodder.rank]` and `level_cap[fodder.rank]` in the same
line; the rank table itself groups stat multiplier, level cap, affix count, and socket count
per rank as one row). Splitting these into separate resources doesn't remove any coupling —
the game design already coupled them — it just forces every pure function that consumes
balance data to thread N resource arguments instead of one, for no isolation gained.

This is not the rejected `GameManager` shape. The god-object failure mode that entry
describes is *behavior* accreting onto a *singleton* until nothing is testable without
booting the engine. `BalanceTable` holds only exported data, no methods, and is not an
autoload — it is passed as a plain argument into pure static functions
(`compute_essence_yield(fodder, target, balance: BalanceTable)`, per `CODING_RULES.md`).
A data resource with many exported fields is not the same shape as a singleton that
accumulates responsibilities.

**Rejected:** several small Resources split by subsystem (one for ranks, one for essence,
one for summon weights, one for building effects). `BalanceTable` is one Resource, one
`.tres`, authored under the project root as `balance.tres`, per `ARCHITECTURE.md` r9's own
wording.

---

## 2026-08-01: `Hero.RANK_NAMES` moves to `BalanceTable`, not before P2-01d

P2-01a explicitly left "moving `Hero.RANK_NAMES` off `Hero`" as a `godot-architect` open
call and out of that ticket's scope. Ranks apply to heroes and equipment identically
(`SYSTEMS.md`): once `EquipmentDefinition`/`Item` exist, they need the same eight labels.

**Reason:** `RANK_NAMES` is presentation data about the rank *system*, not about any one
`Hero` instance — it is the same shape as the rank table's other columns (stat multiplier,
level cap, affix/socket counts), which are already headed for `BalanceTable`. Leaving it as
a `const` on `Hero` (a `RefCounted` *instance* type) means the eventual equipment runtime
class either duplicates the same eight-string array or reaches across into `heroes/` to read
`Hero.RANK_NAMES` — the second option is a cross-feature-folder dependency this repo's
layout (`ARCHITECTURE.md`, "Project layout") is structured to avoid, and the first is the
kind of duplicated hardcoded array `ARCHITECTURE.md` rule 9 exists to prevent for numbers and
should equally apply to the labels describing the same axis.

This is **not** part of P2-01a. `hero.gd` is a file Phase 1 ships and gates green
(`tests/save_roundtrip_check.gd`, `hub/summon/summon.gd:17` both reference
`Hero.RANK_NAMES` today), and moving the const is a call-site-breaking change, not an
additive one — it belongs to whichever ticket first builds `BalanceTable` (`P2-01d`) or
first needs rank labels from a second domain (equipment, `P2-01c`), not to `P2-01a`.

**Rejected:** leaving `RANK_NAMES` on `Hero` permanently and having equipment either
duplicate it or reach into `heroes/hero.gd` for it.

---

## 2026-08-01: No `CombatState` autoload

Proposed fourth autoload holding the current expedition's wave index and per-hero HP between
waves, readable by both `combat/quick_resolve.gd` and `combat/arena/`.

**Reason:** rule 6 — "Autoloads hold no level-specific state" — is a direct hit. Wave index and
per-hero HP mid-expedition is created when an expedition starts and meaningless once it ends;
even `GameSession`, the one autoload justified by surviving scene changes, is explicitly barred
from owning combat or level state, so a new autoload for the same reason doesn't get a pass
either. It also undermines the seam it was meant to serve: the combat seam's whole point is that
`resolve(team, wave) -> CombatResult` is the only channel data flows through between the two
implementations, and a shared autoload both paths read from is a second, implicit channel
alongside it.

**Rejected:** the autoload. Wave index and in-progress HP belong on an expedition-scoped
`RefCounted`/`Node` (e.g. growing `hub/expedition/expedition.gd`'s `Expedition` past its current
Phase-1 placeholder) passed explicitly into `resolve()` — or read back out of `CombatResult`,
which already carries HP-after between waves.

---

## 2026-08-01: Skeleton first, architecture third

Development order is: thin walking skeleton → complete-but-ugly vertical slice →
architecture pass → content → hardening.

**Reason:** designing the full architecture before the loop is proven produces clean code for
the wrong game. Building an uncontrolled prototype produces something that looks 70% done and
is 25% done. The middle path is a skeleton small enough to throw away, then a slice ugly
enough to be honest, then extraction driven by observed pressure.

**Rejected:** designing the whole system up front. An earlier draft of the plan did exactly
this — full data model, systems layout, and folder structure before a single scene existed.

---

## 2026-08-01: Combat behind a two-function seam

Both combat paths implement `resolve(team, wave) -> CombatResult`. Nothing upstream can tell
which one ran.

**Reason:** the game needs a fast statistical resolver (for farming cleared content) and a
real-time playable arena (the selling point). Retrofitting the seam later means rewriting the
expedition system, so it is the one structural decision made before the slice exists.

**Rejected:** a `CombatStrategy` base class with two subclasses. Two functions with the same
signature do not need a hierarchy in GDScript.

---

## 2026-08-01: Three autoloads, hard cap

`SceneRouter`, `SaveService`, `GameSession`. A fourth requires an entry in this file.

**Reason:** Autoloads are just permanently-loaded root nodes, not a requirement for shared
systems. The failure mode in this genre is a `GameManager` that accumulates health, enemies,
inventory, quests, combat, UI, level loading, music, saving, and dialogue until nothing can
be tested in isolation.

`GameSession` earns its place because the player profile must survive scene changes
(menu → hub → arena → hub). That is its only justification — game *rules* stay in plain
functions that take what they need as arguments.

**Rejected:** a `GameManager`. Also rejected: putting rank-up and salvage logic as methods on
`GameSession`, which would make them untestable without booting the engine.

---

## 2026-08-01: Feature-grouped folders, not type-grouped

`heroes/` holds `hero.gd`, `hero_definition.gd`, and `defs/*.tres` together. There is no
`all_scripts/` or `all_resources/`.

**Reason:** Godot's own project-organization guidance favours grouping assets close to the
scenes that use them. Type-based silos mean every feature change touches five distant
directories.

**Rejected:** `src/defs/`, `src/model/`, `src/systems/` — proposed in an earlier plan draft
and reversed before any code was written.

---

## 2026-08-01: Rank-up preserves hero level

Ranking a hero up raises its level cap and keeps its current level and XP.

**Reason:** resetting level on rank-up makes the reward feel like a punishment, which is
exactly wrong for the mechanic the entire game is built around.

**Rejected:** level reset on rank-up (common in the genre, and consistently disliked).

---

## 2026-08-01: Godot pinned to 4.7.1 stable

The engine binary lives in `tools/godot/` (gitignored) and the project is pinned to 4.7.1.

**Reason:** mid-development engine upgrades break scenes and shaders in ways that are
expensive to diagnose while other things are also in flux. Upgrade deliberately, between
phases, as its own change.

**Rejected:** floating on latest stable.

---

## 2026-08-01: Six hero stats, hard cap

`HP ATK DEF SPD CRIT_RATE CRIT_DMG`. A seventh requires an entry here.

**Reason:** collector games accrete stats until no human can reason about a balance change.
Six is enough for meaningful gear differentiation and few enough to actually tune.

**Rejected:** separate magic/physical attack and defence lines, accuracy/evasion, resistances.

---

## 2026-08-04: Serena removed; built-in Read/Grep/Edit are the tools

Serena's MCP server is unregistered, its hooks deleted, and the "symbolic tools are primary"
mandate is gone from `~/.claude/CLAUDE.md`, both project agent files, and the three global ones.
`.serena/` is deleted and gitignored.

**Reason:** measured 13 Serena calls against 289 built-in file operations in this repo (4.3%),
and 0 of 357 in the other project on this machine. Three causes, none of them discipline:
its LSP daemon cannot coexist with `import_gate.ps1` (both want `.godot/`), so the mandated
tool was unavailable by design in every session that runs the gate; the game is ~550 lines
across 25 files, where `get_symbols_overview` on a 22-line file costs more than reading it; and
the rule charged a self-check on *every* `Read`/`Glob`/`Grep`/`Edit` call to route 13 of them.
The `import_gate.ps1` port-6005 guard stays — a hand-started editor still races `.godot/`.

**Rejected:** keeping the server registered without the mandate (still pays the prefix and the
`initial_instructions` pull for a tool nothing reaches for); scoping the mandate off for this
repo only (the other project ignored it 357 times out of 357).
