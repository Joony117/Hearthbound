class_name BattleState
extends RefCounted

const SIMULATION_VERSION: int = 1
const VALID_KINDS: Array[String] = ["normal", "rescue", "practice"]
const VALID_STATUSES: Array[String] = ["active", "victory", "retreated", "stranded", "timeout"]

var simulation_version: int = SIMULATION_VERSION
var order_id: String = ""
var zone_id: String = ""
var kind: String = "normal"
var status: String = "active"
var tick: int = 0
var tick_remainder: float = 0.0
var rng_state: String = "0"
var elapsed_seconds: float = 0.0
var max_seconds: float = 180.0
var actors: Array[BattleActor] = []
var squads: Array[Dictionary] = []
var objective_state: Dictionary = {}
var supplies_remaining: Dictionary = {"healing": 0, "revival": 0}
var policies: Dictionary = {}
var completed_waves: int = 0
var downed_ever_ids: Array[String] = []
var extracted_ids: Array[String] = []
var command_sequence: int = 0
## The Ledger's moments (DECISIONS.md 2026-09-24 item 7): {tick, what, hero, by}, capped at
## battle_max_moments. Bookkeeping only: nothing in the fight reads them.
var moments: Array[Dictionary] = []
var moments_truncated: bool = false
## {hero_id: enemies that hero finished}.
var kills: Dictionary = {}


func to_dict() -> Dictionary:
	var actor_entries: Array[Dictionary] = []
	for actor: BattleActor in actors:
		actor_entries.append(actor.to_dict())
	return {
		"simulation_version": simulation_version,
		"order_id": order_id,
		"zone_id": zone_id,
		"kind": kind,
		"status": status,
		"tick": tick,
		"tick_remainder": tick_remainder,
		"rng_state": rng_state,
		"elapsed_seconds": elapsed_seconds,
		"max_seconds": max_seconds,
		"actors": actor_entries,
		"squads": squads.duplicate(true),
		"objective_state": objective_state.duplicate(true),
		"supplies_remaining": supplies_remaining.duplicate(true),
		"policies": policies.duplicate(true),
		"completed_waves": completed_waves,
		"downed_ever_ids": downed_ever_ids.duplicate(),
		"extracted_ids": extracted_ids.duplicate(),
		"command_sequence": command_sequence,
		"moments": moments.duplicate(true),
		"moments_truncated": moments_truncated,
		"kills": kills.duplicate(),
	}


static func from_dict(data: Dictionary) -> BattleState:
	var state := BattleState.new()
	state.simulation_version = int(data.get("simulation_version", 0))
	state.order_id = str(data.get("order_id", ""))
	state.zone_id = str(data.get("zone_id", ""))
	state.kind = str(data.get("kind", "normal"))
	state.status = str(data.get("status", "active"))
	state.tick = int(data.get("tick", 0))
	state.tick_remainder = float(data.get("tick_remainder", 0.0))
	state.rng_state = str(data.get("rng_state", "0"))
	state.elapsed_seconds = float(data.get("elapsed_seconds", 0.0))
	state.max_seconds = float(data.get("max_seconds", 180.0))
	var raw_actors: Variant = data.get("actors")
	if raw_actors is Array:
		for raw_actor: Variant in raw_actors as Array:
			if raw_actor is Dictionary:
				state.actors.append(BattleActor.from_dict(raw_actor as Dictionary))
	var raw_squads: Variant = data.get("squads")
	if raw_squads is Array:
		for raw_squad: Variant in raw_squads as Array:
			if raw_squad is Dictionary:
				state.squads.append((raw_squad as Dictionary).duplicate(true))
	for raw_id: Variant in data.get("downed_ever_ids", []) as Array:
		if raw_id is String:
			state.downed_ever_ids.append(raw_id as String)
	for raw_id: Variant in data.get("extracted_ids", []) as Array:
		if raw_id is String:
			state.extracted_ids.append(raw_id as String)
	for key: String in ["objective_state", "supplies_remaining", "policies"]:
		var raw_dictionary: Variant = data.get(key)
		if raw_dictionary is Dictionary:
			state.set(key, (raw_dictionary as Dictionary).duplicate(true))
	state.completed_waves = int(data.get("completed_waves", 0))
	state.command_sequence = int(data.get("command_sequence", 0))
	# Additive keys (ig-m6o.1): a checkpoint without them has no moments and no kills yet.
	var raw_moments: Variant = data.get("moments")
	if raw_moments is Array:
		for raw_moment: Variant in raw_moments as Array:
			if raw_moment is Dictionary:
				var moment: Dictionary = raw_moment as Dictionary
				state.moments.append({"tick": int(moment.get("tick", 0)), "what": str(moment.get("what", "")), "hero": str(moment.get("hero", "")), "by": str(moment.get("by", ""))})
	var raw_truncated: Variant = data.get("moments_truncated")
	state.moments_truncated = raw_truncated is bool and raw_truncated as bool
	var raw_kills: Variant = data.get("kills")
	if raw_kills is Dictionary:
		for hero_id: Variant in raw_kills as Dictionary:
			if hero_id is String:
				state.kills[hero_id] = int((raw_kills as Dictionary)[hero_id])
	return state
