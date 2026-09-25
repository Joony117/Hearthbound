class_name BattleJob
extends RefCounted
## ig-7sn.13 (DECISIONS.md 2026-09-25, "Battle sim threading"): the sim's one job function, run on
## WorkerThreadPool or straight on the main thread with the same result. A job owns the BattleState
## or create_run inputs it is handed, returns plain data, and touches no Node, autoload, signal, Hero,
## GameSession or SaveService. It never loads a resource: the main thread builds every BattleState, so
## its zone is already resolved, and jobs share that zone read-only.

const CHUNK_SECONDS: float = 5.0

## Set by the main thread; the job checks it between chunks. One writer, and a stale read costs at
## most one more chunk.
var cancelled: bool = false
## What the job returned. Read it only after the task is waited on.
var result: Dictionary = {}
var task_id: int = -1


## Advances state by seconds in CHUNK_SECONDS steps. advance() carries tick_remainder and the rng, so
## the steps run the same ticks as one call. Returns false if job was cancelled first.
static func advance(state: BattleState, seconds: float, job: BattleJob) -> bool:
	var left: float = seconds
	while left > 0.0 and state.status == "active":
		if job != null and job.cancelled:
			return false
		var step: float = minf(left, CHUNK_SECONDS)
		BattleSimulation.advance(state, step)
		left -= step
	return true


## A battle job: the main thread's BattleState advanced by seconds, handed back as to_dict().
static func run_battle(state: BattleState, seconds: float, job: BattleJob) -> Dictionary:
	if not advance(state, seconds, job):
		return {"cancelled": true}
	return {"cancelled": false, "battle": state.to_dict()}


## A forecast job, from create_run's inputs: BattleSimulation.forecast's Dictionary under "forecast".
static func run_forecast(
	order_id: String,
	team_snapshots: Array[Dictionary],
	zone: ZoneDefinition,
	squads: Array[Dictionary],
	policies: Dictionary,
	supply_escrow: Dictionary,
	seed: int,
	job: BattleJob,
) -> Dictionary:
	var forecast: Dictionary = BattleSimulation.forecast(order_id, team_snapshots, zone, squads, policies, supply_escrow, seed, job)
	if forecast.is_empty():
		return {"cancelled": true}
	return {"cancelled": false, "forecast": forecast}
