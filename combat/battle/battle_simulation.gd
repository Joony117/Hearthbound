class_name BattleSimulation
extends RefCounted

const BALANCE: BalanceTable = preload("res://balance.tres")
## Every skill, keyed by skill id, each class in kit order (SYSTEMS.md § The v1 kits) and then the
## general pool. Kit order is bar order when a hero has no bar of its own.
const ABILITIES: Dictionary[String, AbilityDefinition] = {
	"knight_bulwark": preload("res://combat/abilities/knight_bulwark.tres"),
	"knight_rally": preload("res://combat/abilities/knight_rally.tres"),
	"knight_iron_cut": preload("res://combat/abilities/knight_iron_cut.tres"),
	"knight_follow_through": preload("res://combat/abilities/knight_follow_through.tres"),
	"knight_buckler_blow": preload("res://combat/abilities/knight_buckler_blow.tres"),
	"knight_gauntlet_toss": preload("res://combat/abilities/knight_gauntlet_toss.tres"),
	"knight_sweeping_blow": preload("res://combat/abilities/knight_sweeping_blow.tres"),
	"knight_anvilheart": preload("res://combat/abilities/knight_anvilheart.tres"),
	"knight_charge": preload("res://combat/abilities/knight_charge.tres"),
	"knight_ground_slam": preload("res://combat/abilities/knight_ground_slam.tres"),
	"rogue_blindside": preload("res://combat/abilities/rogue_blindside.tres"),
	"rogue_flank_interrupt": preload("res://combat/abilities/rogue_flank_interrupt.tres"),
	"rogue_quick_cut": preload("res://combat/abilities/rogue_quick_cut.tres"),
	"rogue_gutting_strike": preload("res://combat/abilities/rogue_gutting_strike.tres"),
	"rogue_slip": preload("res://combat/abilities/rogue_slip.tres"),
	"rogue_venom_edge": preload("res://combat/abilities/rogue_venom_edge.tres"),
	"rogue_knife_flurry": preload("res://combat/abilities/rogue_knife_flurry.tres"),
	"rogue_deathmark": preload("res://combat/abilities/rogue_deathmark.tres"),
	"ranger_long_sight": preload("res://combat/abilities/ranger_long_sight.tres"),
	"ranger_piercing_shot": preload("res://combat/abilities/ranger_piercing_shot.tres"),
	"ranger_heron_shot": preload("res://combat/abilities/ranger_heron_shot.tres"),
	"ranger_true_mark": preload("res://combat/abilities/ranger_true_mark.tres"),
	"ranger_pinning_shot": preload("res://combat/abilities/ranger_pinning_shot.tres"),
	"ranger_barbed_arrow": preload("res://combat/abilities/ranger_barbed_arrow.tres"),
	"ranger_hail_of_arrows": preload("res://combat/abilities/ranger_hail_of_arrows.tres"),
	"ranger_hunters_focus": preload("res://combat/abilities/ranger_hunters_focus.tres"),
	"mage_arcane_flow": preload("res://combat/abilities/mage_arcane_flow.tres"),
	"mage_burst": preload("res://combat/abilities/mage_burst.tres"),
	"mage_ember_bolt": preload("res://combat/abilities/mage_ember_bolt.tres"),
	"mage_tinder_hex": preload("res://combat/abilities/mage_tinder_hex.tres"),
	"mage_frost_bind": preload("res://combat/abilities/mage_frost_bind.tres"),
	"mage_chain_spark": preload("res://combat/abilities/mage_chain_spark.tres"),
	"mage_warding_glyph": preload("res://combat/abilities/mage_warding_glyph.tres"),
	"mage_hanging_star": preload("res://combat/abilities/mage_hanging_star.tres"),
	"mage_rime_circle": preload("res://combat/abilities/mage_rime_circle.tres"),
	"mage_rime_wall": preload("res://combat/abilities/mage_rime_wall.tres"),
	"cleric_grace": preload("res://combat/abilities/cleric_grace.tres"),
	"cleric_mend": preload("res://combat/abilities/cleric_mend.tres"),
	"cleric_censer_swing": preload("res://combat/abilities/cleric_censer_swing.tres"),
	"cleric_hush": preload("res://combat/abilities/cleric_hush.tres"),
	"cleric_sheltering_word": preload("res://combat/abilities/cleric_sheltering_word.tres"),
	"cleric_wellspring": preload("res://combat/abilities/cleric_wellspring.tres"),
	"cleric_prayer_circle": preload("res://combat/abilities/cleric_prayer_circle.tres"),
	"cleric_hearthcall": preload("res://combat/abilities/cleric_hearthcall.tres"),
	"cleric_hearthward": preload("res://combat/abilities/cleric_hearthward.tres"),
	"general_catch_breath": preload("res://combat/abilities/general_catch_breath.tres"),
	"general_field_dressing": preload("res://combat/abilities/general_field_dressing.tres"),
	"general_brace": preload("res://combat/abilities/general_brace.tres"),
	"general_tumble": preload("res://combat/abilities/general_tumble.tres"),
	"general_disrupt": preload("res://combat/abilities/general_disrupt.tres"),
	"general_hearten": preload("res://combat/abilities/general_hearten.tres"),
	"enemy_knight_crushing_blow": preload("res://combat/abilities/enemy_knight_crushing_blow.tres"),
}
const ROLE_CYCLE: Array[String] = ["knight", "knight", "ranger", "mage", "rogue"]
const STANCES: Array[String] = ["advance", "stay_together", "defend", "protect"]
## Rows, SYSTEMS.md § Archetypes.
const FRONT_ROW: Array[String] = ["knight", "rogue"]
const BACK_ROW: Array[String] = ["ranger", "mage", "cleric"]
const TICK_EPSILON: float = 0.000001
## ig-gy0.5, _chain_step's answers: a step fired; the chain waits on a step (the buff and attack bands stay
## shut and the swing still lands); no chain is running.
const CHAIN_NONE: int = 0
const CHAIN_FIRED: int = 1
const CHAIN_WAITING: int = 2
## ig-1jw: the largest pace a checkpoint may carry. Settlement rolls loot `pace` times, so a corrupt save
## must not name a huge one. Not a balance number: raise it if battle_pace ever goes past it.
const MAX_PACE: int = 20
# _validate_field_objects' key lists (ig-7sn.10: constants, so a save builds none per object).
const _FIELD_STRING_KEYS: Array[String] = ["id", "kind", "skill_id", "owner_actor_id", "faction"]
const _FIELD_KINDS: Array[String] = ["zone", "wall"]
const _WALL_NUMBER_KEYS: Array[String] = ["thickness", "remaining_seconds"]
const _ZONE_NUMBER_KEYS: Array[String] = ["radius", "remaining_seconds", "atk", "heal_scale"]
## ig-9gf: positions are float32, so an approach aimed exactly at a reach can park one ulp outside it
## (1.6000000238 from 1.6) and never close. _move_actors aims this far inside a reach instead, and
## counts a point as reached within it, so every reach check compares bare.
const REACH_TOLERANCE: float = 0.0001
## ig-0qh: how far outside a wall's footprint its corners sit and a cut move stops, so a Vector2's float32
## rounding never lands a center inside one.
const WALL_MARGIN: float = 0.001
const CORNER_SIGNS: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)]

const COMMAND_MOVE: String = "move"
const COMMAND_ATTACK: String = "attack"
const COMMAND_ATTACK_MOVE: String = "attack_move"
const COMMAND_HOLD: String = "hold"
const COMMAND_GUARD: String = "guard"
const COMMAND_CARRY: String = "carry"
const COMMAND_RETREAT: String = "retreat"
const COMMAND_ABILITY: String = "ability"
## ig-gy0.6: one hero fires one skill of its bar by hand, at a target or a ground point.
const COMMAND_USE_SKILL: String = "use_skill"
const COMMAND_ITEM_HEALING: String = "item_healing"
const COMMAND_ITEM_REVIVAL: String = "item_revival"
const COMMAND_SET_STANCE: String = "set_stance"
const COMMAND_SET_AUTO_BATTLE: String = "set_auto_battle"
const COMMAND_SET_ABILITY_AUTO: String = "set_ability_auto"
const COMMAND_SET_ITEM_AUTO: String = "set_item_auto"
const COMMANDS: Array[String] = [
	COMMAND_MOVE, COMMAND_ATTACK, COMMAND_ATTACK_MOVE, COMMAND_HOLD, COMMAND_GUARD,
	COMMAND_CARRY, COMMAND_RETREAT, COMMAND_ABILITY, COMMAND_USE_SKILL, COMMAND_ITEM_HEALING,
	COMMAND_ITEM_REVIVAL, COMMAND_SET_STANCE, COMMAND_SET_AUTO_BATTLE,
	COMMAND_SET_ABILITY_AUTO, COMMAND_SET_ITEM_AUTO,
]


static func create_run(
	order_id: String,
	team_snapshots: Array[Dictionary],
	zone: ZoneDefinition,
	squads: Array[Dictionary],
	policies: Dictionary,
	supply_escrow: Dictionary,
	run_seed: int,
	kind: String = "normal",
	pace: int = 0,
) -> BattleState:
	assert(not order_id.is_empty())
	assert(zone != null)
	assert(kind in BattleState.VALID_KINDS)
	assert(not team_snapshots.is_empty())
	var state := BattleState.new()
	state.order_id = order_id
	state.zone_id = str(zone.zone_id)
	state.zone = zone
	state.kind = kind
	# pace 0: the live battle_pace. A rescue passes its incident's.
	state.pace = pace if pace > 0 else BALANCE.battle_pace
	state.max_seconds = zone.max_battle_seconds * state.pace
	state.rng_state = str(run_seed)
	state.squads = squads.duplicate(true)
	state.policies = _normalized_policies(policies)
	state.supplies_remaining = _normalized_supplies(supply_escrow)
	state.objective_state = _initial_objective_state(zone)
	var has_enemy_snapshot: bool = false
	# Heroes placed fresh (no saved facing) turn to the enemy once it has spawned.
	var fresh: Array[BattleActor] = []
	for snapshot: Dictionary in team_snapshots:
		var actor: BattleActor = _actor_from_team_snapshot(snapshot, state.actors.size(), zone, state.pace)
		if not snapshot.has("facing") and not (snapshot.has("max_hp") and snapshot.has("effect_state")):
			fresh.append(actor)
		# Timestamps are relative to this battle's tick, which starts at 0; carried ones would sit ahead of it.
		for key: String in ["last_hit_tick", "last_skill_tick", "last_crit_tick"]:
			actor.effect_state[key] = 0
		actor.effect_state.erase("last_push_tick")
		actor.effect_state.erase("hit_from")
		actor.effect_state.erase("kite_point")
		actor.effect_state.erase("kite_ready_tick")
		# A chain's ticks are this battle's too (ig-gy0.5): one carried across a leg would sit ahead of it.
		# A weaponskill set for the next swing (ig-gy0.6) ends with the leg, as a chain does.
		actor.end_chain()
		actor.effect_state.erase("next_swing_skill")
		state.actors.append(actor)
		has_enemy_snapshot = has_enemy_snapshot or actor.faction == "enemy"
	if not has_enemy_snapshot and kind != "rescue":
		_spawn_initial_enemies(state, zone)
	for actor: BattleActor in fresh:
		actor.facing = _facing_toward_opponents(state, actor.faction, actor.position, actor.facing)
	_initialize_squads(state)
	return state


static func advance(state: BattleState, elapsed_seconds: float) -> BattleOutcome:
	assert(state != null)
	if elapsed_seconds <= 0.0 or state.status != "active":
		return snapshot_outcome(state)
	var bounded_elapsed: float = minf(elapsed_seconds, maxf(state.max_seconds - state.elapsed_seconds, 0.0))
	var accumulated: float = state.tick_remainder + bounded_elapsed
	var ticks_to_run: int = floori((accumulated + TICK_EPSILON) / BALANCE.battle_tick_seconds)
	state.tick_remainder = accumulated - float(ticks_to_run) * BALANCE.battle_tick_seconds
	if state.tick_remainder < TICK_EPSILON:
		state.tick_remainder = 0.0
	var rng := RandomNumberGenerator.new()
	rng.state = state.rng_state.to_int()
	for ignored_tick: int in ticks_to_run:
		if state.status != "active":
			break
		_tick(state, rng)
	state.rng_state = str(rng.state)
	if state.status == "active" and state.elapsed_seconds + TICK_EPSILON >= state.max_seconds:
		_finish_timeout(state)
	return snapshot_outcome(state)


static func issue_command(state: BattleState, command: Dictionary) -> Dictionary:
	if state == null or state.status != "active":
		return _command_result(false, "That battle is no longer active.", state)
	var kind: Variant = command.get("kind")
	if not kind is String or not (kind as String) in COMMANDS:
		return _command_result(false, "Unknown battle command.", state)
	var command_kind: String = kind as String
	if command_kind == COMMAND_SET_AUTO_BATTLE:
		if not command.get("value") is bool:
			return _command_result(false, "Auto Battle needs a bool value.", state)
		state.policies["auto_battle"] = command.get("value") as bool
		return _accept_command(state)
	if command_kind == COMMAND_SET_ITEM_AUTO:
		var item_auto: Variant = command.get("value")
		if not item_auto is Dictionary or (item_auto as Dictionary).size() != 2:
			return _command_result(false, "Item automation needs auto_heal and auto_revive bool values.", state)
		if not (item_auto as Dictionary).get("auto_heal") is bool or not (item_auto as Dictionary).get("auto_revive") is bool:
			return _command_result(false, "Item automation needs auto_heal and auto_revive bool values.", state)
		state.policies["auto_heal"] = (item_auto as Dictionary).get("auto_heal") as bool
		state.policies["auto_revive"] = (item_auto as Dictionary).get("auto_revive") as bool
		return _accept_command(state)
	var actors_or_error: Variant = _command_actors(state, command)
	if actors_or_error is String:
		return _command_result(false, actors_or_error as String, state)
	var actors: Array[BattleActor] = actors_or_error as Array[BattleActor]
	if command_kind == COMMAND_SET_ABILITY_AUTO:
		if not command.get("value") is bool:
			return _command_result(false, "Ability automation needs a bool value.", state)
		# The actors' modes are the truth; an old order's ability_auto policy is kept as saved, never
		# written (ig-gy0.3; nothing reads it, ig-28b).
		for actor: BattleActor in actors:
			actor.set_abilities_auto(command.get("value") as bool)
		return _accept_command(state)
	if command_kind == COMMAND_SET_STANCE:
		if not command.get("value") is String or not str(command.get("value")) in STANCES:
			return _command_result(false, "Stance is invalid.", state)
		for actor: BattleActor in actors:
			_set_squad_stance(state, actor.squad_id, str(command.get("value")))
		return _accept_command(state)
	var target: BattleActor = _actor_by_id(state, str(command.get("target_id", "")))
	var point: Vector2 = _command_point(command)
	if command_kind in [COMMAND_MOVE, COMMAND_ATTACK_MOVE] and not _valid_point(command.get("point")):
		return _command_result(false, "That command needs a finite ground point.", state)
	if command_kind == COMMAND_ATTACK and (target == null or target.faction != "enemy" or target.life != BattleActor.LIFE_ALIVE):
		return _command_result(false, "That attack target is unavailable.", state)
	if command_kind == COMMAND_GUARD:
		if target == null and not _valid_point(command.get("point")):
			return _command_result(false, "Guard needs a living ally or finite ground point.", state)
		if target != null and (target.faction != "ally" or target.life != BattleActor.LIFE_ALIVE):
			return _command_result(false, "That guard target is unavailable.", state)
	if command_kind in [COMMAND_ITEM_HEALING, COMMAND_ITEM_REVIVAL] and command.has("masterwork") and not command.get("masterwork") is bool:
		return _command_result(false, "The draught tier needs a bool masterwork value.", state)
	if command_kind == COMMAND_CARRY:
		if actors.size() != 1 or target == null or target.faction != "ally" or target.life != BattleActor.LIFE_DOWNED:
			return _command_result(false, "Carry needs one living carrier and one downed ally.", state)
		if actors[0].position.distance_to(target.position) > BALANCE.battle_carry_range or not target.carried_by_id.is_empty():
			return _command_result(false, "The downed ally is out of carry range or already carried.", state)
	if command_kind in [COMMAND_MOVE, COMMAND_ATTACK, COMMAND_ATTACK_MOVE, COMMAND_HOLD, COMMAND_GUARD, COMMAND_RETREAT]:
		for actor: BattleActor in actors:
			_drop_carried(state, actor)
	match command_kind:
		COMMAND_MOVE, COMMAND_ATTACK_MOVE:
			_assign_group_points(state, actors, point, command_kind)
		COMMAND_ATTACK:
			for actor: BattleActor in actors:
				_replace_direct_order(actor, COMMAND_ATTACK, target.id, target.position)
		COMMAND_HOLD:
			for actor: BattleActor in actors:
				_replace_direct_order(actor, COMMAND_HOLD, "", actor.position)
		COMMAND_GUARD:
			for actor: BattleActor in actors:
				actor.guard_target_id = target.id if target != null else ""
				_replace_direct_order(actor, COMMAND_GUARD, actor.guard_target_id, target.position if target != null else point)
		COMMAND_CARRY:
			_replace_direct_order(actors[0], COMMAND_CARRY, target.id, target.position)
			actors[0].effect_state["carry_progress"] = 0.0
		COMMAND_RETREAT:
			var exit_position: Vector2 = _objective_point(state, "exit_position")
			for actor: BattleActor in actors:
				_drop_carried(state, actor)
				_replace_direct_order(actor, COMMAND_RETREAT, "", exit_position)
		COMMAND_ABILITY:
			if actors.size() != 1 or not _manual_abilities(state, actors, target, point):
				return _command_result(false, "No selected ability can resolve against that target now.", state)
		COMMAND_USE_SKILL:
			var refusal: String = _use_skill_by_hand(state, actors, command, target, point)
			if not refusal.is_empty():
				return _command_result(false, refusal, state)
		COMMAND_ITEM_HEALING:
			if actors.size() != 1 or target == null or not _use_healing(state, actors[0], target, bool(command.get("masterwork", false))):
				return _command_result(false, "Healing cannot resolve against that target now.", state)
		COMMAND_ITEM_REVIVAL:
			if actors.size() != 1 or target == null or not _use_revival(state, actors[0], target, true, bool(command.get("masterwork", false))):
				return _command_result(false, "Revival cannot resolve against that target now.", state)
		_:
			return _command_result(false, "That command is not implemented.", state)
	return _accept_command(state)


static func forecast(
	order_id: String,
	team_snapshots: Array[Dictionary],
	zone: ZoneDefinition,
	squads: Array[Dictionary],
	policies: Dictionary,
	supply_escrow: Dictionary,
	run_seed: int,
) -> Dictionary:
	var normal: Dictionary = forecast_leg(order_id, team_snapshots, zone, squads, policies, supply_escrow, run_seed, false)
	var stress: Dictionary = forecast_leg(order_id, team_snapshots, zone, squads, policies, supply_escrow, run_seed, true)
	return forecast_verdict(normal, stress)


## One of forecast's two runs, the normal one or the stress one (enemies always crit, allies never).
## A repeat's check sends each as its own job (ig-7sn.6). Returns {"outcome": its outcome's to_dict(),
## "clean": won with no downing}, or {} when job was cancelled.
static func forecast_leg(
	order_id: String,
	team_snapshots: Array[Dictionary],
	zone: ZoneDefinition,
	squads: Array[Dictionary],
	policies: Dictionary,
	supply_escrow: Dictionary,
	run_seed: int,
	stress: bool,
	job: BattleJob = null,
) -> Dictionary:
	var leg_id: String = order_id
	var leg_policies: Dictionary = policies
	if stress:
		leg_id = order_id + ":stress"
		leg_policies = policies.duplicate(true)
		leg_policies["force_enemy_crit"] = true
		leg_policies["suppress_ally_crit"] = true
	var state := create_run(leg_id, team_snapshots, zone, squads, leg_policies, supply_escrow, run_seed)
	if not BattleJob.advance(state, state.max_seconds, job):
		return {}
	return {"outcome": snapshot_outcome(state).to_dict(), "clean": state.status == "victory" and state.downed_ever_ids.is_empty()}


## forecast's verdict from its two legs: safe only when both won with no downing.
static func forecast_verdict(normal: Dictionary, stress: Dictionary) -> Dictionary:
	var safe: bool = bool(normal["clean"]) and bool(stress["clean"])
	return {
		"safe": safe,
		"reason": "Victory with no downings in normal and stress runs." if safe else "Unattended simulation did not clear both runs without a downing.",
		"normal": normal["outcome"],
		"stress": stress["outcome"],
	}


static func validate_snapshot(data: Dictionary) -> String:
	for key: String in ["simulation_version", "tick", "completed_waves", "command_sequence"]:
		if not _nonnegative_integer(data.get(key)):
			return "Battle %s must be a non-negative integer." % key
	if int(data.get("simulation_version")) != BattleState.SIMULATION_VERSION:
		return "Battle simulation_version is unsupported."
	for key: String in ["order_id", "zone_id", "kind", "status", "rng_state"]:
		if not data.get(key) is String:
			return "Battle %s must be a String." % key
	if str(data.get("order_id")).is_empty() or str(data.get("zone_id")).is_empty():
		return "Battle order_id and zone_id must be non-empty."
	var zone_path: String = ZoneDefinition.DEF_PATH_TEMPLATE % str(data.get("zone_id"))
	if not ResourceLoader.exists(zone_path):
		return "Battle zone_id is unknown."
	var zone: ZoneDefinition = ResourceLoader.load(zone_path) as ZoneDefinition
	if zone == null or str(zone.zone_id) != str(data.get("zone_id")):
		return "Battle zone_id is unknown."
	if not str(data.get("kind")) in BattleState.VALID_KINDS or not str(data.get("status")) in BattleState.VALID_STATUSES:
		return "Battle kind or status is invalid."
	if not _valid_int64_string(str(data.get("rng_state"))):
		return "Battle rng_state must be a signed decimal int64 string."
	for key: String in ["tick_remainder", "elapsed_seconds", "max_seconds"]:
		if not _valid_number(data.get(key)):
			return "Battle %s must be finite." % key
	if float(data.get("tick_remainder")) < 0.0 or float(data.get("tick_remainder")) >= BALANCE.battle_tick_seconds:
		return "Battle tick_remainder is outside the logical tick."
	if float(data.get("elapsed_seconds")) < 0.0 or float(data.get("max_seconds")) <= 0.0 or float(data.get("elapsed_seconds")) > float(data.get("max_seconds")):
		return "Battle elapsed/max time is invalid."
	if data.has("pace") and (not _nonnegative_integer(data.get("pace")) or int(data.get("pace")) < 1 or int(data.get("pace")) > MAX_PACE):
		return "Battle pace must be an integer from 1 to %d." % MAX_PACE
	var pace: int = int(data.get("pace", 1))
	if float(data.get("max_seconds")) > zone.max_battle_seconds * pace + TICK_EPSILON:
		return "Battle max_seconds exceeds the authored zone bound."
	var maximum_encounters: int = zone.trash_wave_count + 1
	if zone.battle_kind == "raid":
		maximum_encounters = 2
	elif zone.battle_kind == "region":
		maximum_encounters = 4
	if int(data.get("completed_waves")) > maximum_encounters:
		return "Battle completed_waves exceeds the authored encounter count."
	var logical_elapsed: float = float(int(data.get("tick"))) * BALANCE.battle_tick_seconds
	if absf(float(data.get("elapsed_seconds")) - logical_elapsed) > TICK_EPSILON:
		return "Battle tick and elapsed_seconds are inconsistent."
	for key: String in ["actors", "squads", "downed_ever_ids", "extracted_ids"]:
		if not data.get(key) is Array:
			return "Battle %s must be an Array." % key
	for key: String in ["objective_state", "supplies_remaining", "policies"]:
		if not data.get(key) is Dictionary:
			return "Battle %s must be a Dictionary." % key
	var actor_ids: Dictionary[String, bool] = {}
	var spawn_indices: Dictionary[int, bool] = {}
	var hero_actors: Dictionary[String, Dictionary] = {}
	var actors: Array = data["actors"]
	# ig-7sn.10: every save runs this on every actor, so the loops read each field once. After
	# BattleActor.validate_dict, an actor's keys hold their checked types. Same checks, order and messages.
	var bounds: float = zone.battle_bounds
	for raw_actor: Variant in actors:
		if not raw_actor is Dictionary:
			return "Every battle actor must be a Dictionary."
		var actor_data: Dictionary = raw_actor as Dictionary
		var actor_error: String = BattleActor.validate_dict(actor_data)
		if not actor_error.is_empty():
			return actor_error
		var actor_id: String = actor_data["id"]
		var spawn_index: int = int(actor_data["spawn_index"])
		if actor_ids.has(actor_id) or spawn_indices.has(spawn_index):
			return "Battle actor IDs and spawn indices must be unique."
		if not _valid_point_within_bounds(actor_data["position"], bounds) or not _valid_point_within_bounds(actor_data["order_point"], bounds):
			return "Battle actor positions must remain inside the authored bounds."
		if not _valid_point_within_bounds((actor_data["effect_state"] as Dictionary)["home_position"], bounds):
			return "Battle actor home positions must remain inside the authored bounds."
		actor_ids[actor_id] = true
		spawn_indices[spawn_index] = true
	var tick: int = int(data["tick"])
	for raw_actor: Variant in actors:
		var actor_data: Dictionary = raw_actor as Dictionary
		var hero_id: String = actor_data["hero_id"]
		if not hero_id.is_empty():
			if hero_actors.has(hero_id):
				return "Battle hero IDs must be unique."
			hero_actors[hero_id] = actor_data
		var carried_by_id: String = actor_data["carried_by_id"]
		var carrying_id: String = actor_data["carrying_id"]
		var effects: Dictionary = actor_data["effect_state"]
		if int(effects["last_hit_tick"]) > tick or int(effects["last_skill_tick"]) > tick or int(effects.get("last_crit_tick", 0)) > tick or int(effects.get("last_push_tick", 0)) > tick:
			return "Battle effect timestamps cannot be ahead of the simulation tick."
		if not carried_by_id.is_empty() and not carrying_id.is_empty():
			return "A battle actor cannot carry and be carried simultaneously."
		if not carried_by_id.is_empty():
			var carrier_data: Dictionary = _raw_actor_by_id(actors, carried_by_id)
			if not actor_ids.has(carried_by_id) or str(carrier_data.get("carrying_id", "")) != str(actor_data.get("id")):
				return "Battle carry links must be mutual and reference existing actors."
			if str(actor_data.get("life")) != BattleActor.LIFE_DOWNED or str(carrier_data.get("life")) != BattleActor.LIFE_ALIVE or str(carrier_data.get("faction")) != str(actor_data.get("faction")):
				return "Only a living same-faction actor can carry a downed actor."
		if not carrying_id.is_empty():
			var carried_data: Dictionary = _raw_actor_by_id(actors, carrying_id)
			if not actor_ids.has(carrying_id) or str(carried_data.get("carried_by_id", "")) != str(actor_data.get("id")):
				return "Battle carry links must be mutual and reference existing actors."
			if str(actor_data.get("life")) != BattleActor.LIFE_ALIVE or str(carried_data.get("life")) != BattleActor.LIFE_DOWNED or str(carried_data.get("faction")) != str(actor_data.get("faction")):
				return "Only a living actor can carry a same-faction downed actor."
		var order_target_id: String = actor_data["order_target_id"]
		var guard_target_id: String = actor_data["guard_target_id"]
		var chain_target_id: String = effects.get("chain_target", "")
		if (not order_target_id.is_empty() and not actor_ids.has(order_target_id)) or (not guard_target_id.is_empty() and not actor_ids.has(guard_target_id)) or (not chain_target_id.is_empty() and not actor_ids.has(chain_target_id)):
			return "Battle actor references must target existing actors."
	var supplies_error: String = supplies_shape_error(data.get("supplies_remaining") as Dictionary, BALANCE.battle_supply_allocation_cap)
	if not supplies_error.is_empty():
		return "Battle supplies: %s" % supplies_error
	var policy_error: String = _validate_policies(data.get("policies") as Dictionary)
	if not policy_error.is_empty():
		return policy_error
	var squad_error: String = _validate_squads(data.get("squads") as Array, hero_actors, str(data.get("kind")), str(data.get("status")))
	if not squad_error.is_empty():
		return squad_error
	for key: String in ["downed_ever_ids", "extracted_ids"]:
		var seen: Dictionary[String, bool] = {}
		for raw_id: Variant in data.get(key) as Array:
			if not raw_id is String or (raw_id as String).is_empty() or seen.has(raw_id as String):
				return "Battle %s must contain unique non-empty Strings." % key
			if not hero_actors.has(raw_id as String):
				return "Battle %s must reference deployed heroes." % key
			if key == "extracted_ids" and str(hero_actors[raw_id as String].get("life")) != BattleActor.LIFE_EXTRACTED:
				return "Battle extracted_ids must match extracted hero actors."
			seen[raw_id as String] = true
		if key == "extracted_ids":
			for hero_id: String in hero_actors:
				if str(hero_actors[hero_id].get("life")) == BattleActor.LIFE_EXTRACTED and not seen.has(hero_id):
					return "Battle extracted hero actors must appear in extracted_ids."
	var field_error: String = _validate_field_objects(data, zone, actor_ids)
	if not field_error.is_empty():
		return field_error
	return _validate_objective_state(data.get("objective_state") as Dictionary, zone, pace)


## ig-vl1.4: additive keys (a checkpoint without them has no zones), checked the way the objective state
## is (DECISIONS.md 2026-09-25, "Casters shape the field", item 1). A skill id this build lacks is not an
## error: BattleState.from_dict drops a zone with that skill with a warning. A wall reads nothing from its
## skill, so it is kept whatever its skill (item 1, amended by ig-vl1.5).
## Objects over the caps are not an error either (ig-vl1.5): from_dict trims them as a cast would, so a
## lowered cap never locks a save out.
static func _validate_field_objects(data: Dictionary, zone: ZoneDefinition, actor_ids: Dictionary[String, bool]) -> String:
	if data.has("field_sequence") and not _nonnegative_integer(data.get("field_sequence")):
		return "Battle field_sequence must be a non-negative integer."
	if not data.has("field_objects"):
		return ""
	# Never an id past its sequence: the next cast's id is field:<sequence + 1>, so one at or below it can't
	# be written twice. The ids' uniqueness bounds the count by the sequence.
	if not data.get("field_objects") is Array:
		return "Battle field_objects must be an Array."
	var sequence: int = int(data.get("field_sequence", 0))
	var ids: Dictionary[String, bool] = {}
	for entry: Variant in data.get("field_objects") as Array:
		if not entry is Dictionary or (entry as Dictionary).size() != (9 if str((entry as Dictionary).get("kind")) == "wall" else 10):
			return "Every battle field object must be a zone {id, kind, skill_id, owner_actor_id, faction, center, radius, remaining_seconds, atk, heal_scale} or a wall {id, kind, skill_id, owner_actor_id, faction, start, end, thickness, remaining_seconds}."
		var field: Dictionary = entry as Dictionary
		for key: String in _FIELD_STRING_KEYS:
			if not field.get(key) is String:
				return "Battle field object %s must be a String." % key
		var number: String = str(field["id"]).trim_prefix("field:")
		if not str(field["id"]).begins_with("field:") or not number.is_valid_int() or str(number.to_int()) != number or number.to_int() < 1 or number.to_int() > sequence or ids.has(str(field["id"])):
			return "Battle field object ids must be unique, field:<1 to field_sequence>."
		ids[str(field["id"])] = true
		if not str(field["kind"]) in _FIELD_KINDS or not str(field["faction"]) in BattleActor.VALID_FACTIONS or not actor_ids.has(str(field["owner_actor_id"])):
			return "Battle field object kind, faction or owner is invalid."
		if str(field["kind"]) == "wall":
			if not _point_within_bounds(field.get("start"), zone.battle_bounds) or not _point_within_bounds(field.get("end"), zone.battle_bounds):
				return "Battle wall ends must remain inside the authored bounds."
			if _array_vector(field["start"]) == _array_vector(field["end"]):
				return "Battle wall ends must differ."
			for key: String in _WALL_NUMBER_KEYS:
				if not _valid_number(field.get(key)) or not (float(field.get(key)) > 0.0):
					return "Battle wall %s must be finite and positive." % key
			if float(field["thickness"]) > zone.battle_bounds * 2.0:
				return "Battle wall thickness must fit the authored bounds."
			continue
		if not _point_within_bounds(field.get("center"), zone.battle_bounds):
			return "Battle field object centers must remain inside the authored bounds."
		for key: String in _ZONE_NUMBER_KEYS:
			if not _valid_number(field.get(key)) or float(field.get(key)) < 0.0:
				return "Battle field object %s must be finite and non-negative." % key
		if not (float(field["radius"]) > 0.0) or not (float(field["remaining_seconds"]) > 0.0):
			return "Battle field object radius and remaining_seconds must be positive."
		# The wall thickness's cap (ig-0qh): the sim compares in float64, but the view's ring is float32.
		if float(field["radius"]) > zone.battle_bounds * 2.0:
			return "Battle zone radius must fit the authored bounds."
	return ""


static func snapshot_outcome(state: BattleState) -> BattleOutcome:
	var outcome := BattleOutcome.new()
	outcome.status = state.status
	outcome.supplies_remaining = state.supplies_remaining.duplicate(true)
	outcome.completed_waves = state.completed_waves
	outcome.elapsed_seconds = state.elapsed_seconds
	outcome.moments = state.moments.duplicate(true)
	outcome.moments_truncated = state.moments_truncated
	outcome.kills = state.kills.duplicate()
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and actor.life == BattleActor.LIFE_DEAD:
			outcome.enemy_dead_ids.append(actor.id)
		elif actor.faction == "ally" and not actor.hero_id.is_empty():
			if state.status == "victory" or actor.life == BattleActor.LIFE_EXTRACTED or actor.life == BattleActor.LIFE_ALIVE:
				outcome.secured_hero_ids.append(actor.hero_id)
			elif actor.life == BattleActor.LIFE_DOWNED:
				outcome.stranded_hero_ids.append(actor.hero_id)
	return outcome


static func _tick(state: BattleState, rng: RandomNumberGenerator) -> void:
	state.tick += 1
	state.elapsed_seconds = minf(state.elapsed_seconds + BALANCE.battle_tick_seconds, state.max_seconds)
	_expire_effects_and_cooldowns(state)
	_update_field_objects(state)
	_answer_telegraphs(state, rng)
	_choose_intentions(state)
	_move_actors(state)
	_support_actions(state)
	_offensive_actions(state, rng)
	_update_objectives(state)
	_evaluate_terminal(state)


## ig-85w: every count-down (here and in _tick_statuses) takes one tick off and snaps what is left within
## TICK_EPSILON of 0 to 0, so a timer of t seconds ends on tick t / 0.1 (ten 0.1 s steps leave 1.0 at about
## 1e-16, which took an 11th tick). Written inline: as a helper call it cost 8% of a forecast.
static func _expire_effects_and_cooldowns(state: BattleState) -> void:
	var step: float = BALANCE.battle_tick_seconds
	for actor: BattleActor in state.actors:
		actor.attack_cooldown = actor.attack_cooldown - step if actor.attack_cooldown - step >= TICK_EPSILON else 0.0
		for skill_id: String in actor.skill_cooldowns:
			var cooldown: float = float(actor.skill_cooldowns[skill_id])
			actor.skill_cooldowns[skill_id] = cooldown - step if cooldown - step >= TICK_EPSILON else 0.0
		actor.item_cooldown = actor.item_cooldown - step if actor.item_cooldown - step >= TICK_EPSILON else 0.0
		actor.ability_lock = actor.ability_lock - step if actor.ability_lock - step >= TICK_EPSILON else 0.0
		_tick_statuses(state, actor)
		for key: String in ["stun_remaining", "attack_windup_remaining", "telegraph_remaining"]:
			if actor.effect_state.has(key):
				var left: float = float(actor.effect_state[key])
				actor.effect_state[key] = left - step if left - step >= TICK_EPSILON else 0.0
		if actor.life != BattleActor.LIFE_ALIVE or float(actor.effect_state.get("stun_remaining", 0.0)) > 0.0:
			_cancel_pending_action(actor)
			# A chain ends when its hero goes non-alive, not when it is stunned (ig-gy0.5); a loaded one too.
			if actor.life != BattleActor.LIFE_ALIVE:
				# ig-gy0.6: a weaponskill set for the next swing goes with it, the same way.
				actor.effect_state.erase("next_swing_skill")
				if actor.effect_state.has("chain_trigger"):
					actor.end_chain()


static func _choose_intentions(state: BattleState) -> void:
	var supplies_out: bool = bool(state.policies.get("retreat_when_supplies_empty", false)) and _supply_count(state, BattleState.SUPPLY_KINDS) == 0
	# Planning changes orders only: no life, position, telegraph or objective moves until the pass ends.
	# So the telegraphing enemies, and each squad's leader and objective, are found once per pass
	# (ig-7sn.7). Per call, not static, so a sim off the main thread stays possible.
	var telegraphs: Array[BattleActor] = []
	for enemy: BattleActor in state.actors:
		if enemy.faction == "enemy" and enemy.life == BattleActor.LIFE_ALIVE and not (float(enemy.effect_state.get("telegraph_remaining", 0.0)) <= 0.0):
			telegraphs.append(enemy)
	var plan: Dictionary = {}
	for actor: BattleActor in state.actors:
		if actor.life != BattleActor.LIFE_ALIVE or actor.effect_state.get("stun_remaining", 0.0) > 0.0:
			continue
		if actor.faction == "enemy":
			_choose_enemy_intention(state, actor)
			continue
		# ig-gy0.6: like a direct order, and then some: nothing below picks for the piloted hero.
		if actor.id == state.piloted_id:
			_keep_piloted_order(state, actor)
			continue
		if actor.order_kind == COMMAND_ATTACK and not bool(actor.effect_state.get("direct_order", false)):
			var automatic_target: BattleActor = _actor_by_id(state, actor.order_target_id)
			if automatic_target == null or automatic_target.life != BattleActor.LIFE_ALIVE:
				actor.order_kind = ""
				actor.order_target_id = ""
		if bool(state.policies.get("auto_battle", true)) and not bool(actor.effect_state.get("direct_order", false)):
			var safe_point: Variant = _danger_safe_point(state, actor, telegraphs)
			if safe_point is Vector2:
				actor.effect_state["evade_point"] = [(safe_point as Vector2).x, (safe_point as Vector2).y]
				# Evasion cancels a hop in flight; its cooldown stays spent (ig-uu7.3).
				actor.effect_state.erase("kite_point")
				continue
		actor.effect_state.erase("evade_point")
		if bool(actor.effect_state.get("direct_order", false)) and actor.order_kind == COMMAND_ATTACK:
			var direct_target: BattleActor = _actor_by_id(state, actor.order_target_id)
			if direct_target == null or direct_target.life != BattleActor.LIFE_ALIVE:
				actor.order_kind = ""
				actor.order_target_id = ""
				actor.effect_state["direct_order"] = false
		# ig-ap2: a direct attack-move keeps its point, on either auto setting. It fights the enemy it
		# engaged while that one lives and stays in contact range, else the nearest enemy in it, else none.
		if bool(actor.effect_state.get("direct_order", false)) and actor.order_kind == COMMAND_ATTACK_MOVE:
			_engage_for_attack_move(state, actor)
			continue
		if bool(actor.effect_state.get("direct_order", false)) and not actor.order_kind.is_empty():
			continue
		# Out of supplies: an ally on auto heads for the exit, ahead of any squad behaviour. A telegraph
		# evade above still wins its tick, and a direct order skips this (ig-axw).
		if supplies_out and not bool(actor.effect_state.get("direct_order", false)):
			actor.order_kind = COMMAND_RETREAT
			actor.order_target_id = ""
			actor.order_point = _objective_point(state, "exit_position")
			continue
		# ponytail: the supplies retreat above skips both this read and the rescue's carry bookkeeping
		# below; a rescue never gets it (dispatch_rescue passes no policies). If one ever does, keep the
		# retreat off kind "rescue", or every pass drops the carry.
		var previous_kind: String = actor.order_kind
		var previous_target_id: String = actor.order_target_id
		if not bool(actor.effect_state.get("direct_order", false)):
			actor.order_kind = ""
			actor.order_target_id = ""
		if state.kind == "rescue" and bool(state.policies.get("auto_battle", true)):
			if actor.squad_id.is_empty():
				actor.order_kind = COMMAND_RETREAT
				actor.order_point = _objective_point(state, "exit_position")
				actor.effect_state["direct_order"] = false
				actor.effect_state.erase("carry_progress")
				continue
			if not actor.carrying_id.is_empty():
				actor.order_kind = COMMAND_RETREAT
				actor.order_point = _objective_point(state, "exit_position")
				actor.effect_state["direct_order"] = false
				actor.effect_state.erase("carry_progress")
				continue
			var downed: BattleActor = _nearest_unassigned_downed(state, actor)
			# ig-ls3: carry_progress belongs to one (carrier, body) pair. It survives a planning pass only
			# when the pass re-picks the same body; any other pick starts over.
			if downed == null or previous_kind != COMMAND_CARRY or previous_target_id != downed.id:
				actor.effect_state.erase("carry_progress")
			if downed != null:
				actor.order_kind = COMMAND_CARRY
				actor.order_target_id = downed.id
				actor.order_point = downed.position
				actor.effect_state["direct_order"] = false
				continue
			actor.order_kind = COMMAND_RETREAT
			actor.order_target_id = ""
			actor.order_point = _objective_point(state, "exit_position")
			actor.effect_state["direct_order"] = false
			continue
		if bool(state.policies.get("auto_battle", true)):
			# One pass for the back row feeds both the kite below and the formation in the stance.
			var rows: RowScan = _scan_rows(state, actor) if actor.archetype in BACK_ROW else null
			if not (rows != null and _kite_order(state, actor, rows)):
				_choose_squad_intention(state, actor, previous_target_id, plan, rows)


## ig-ap2: the enemy a direct attack-move fights, kept while it lives and stays in contact range, else the
## nearest enemy in it, else none.
static func _engage_for_attack_move(state: BattleState, actor: BattleActor) -> void:
	var contact: float = maxf(BALANCE.battle_detection_range, actor.attack_range)
	var engaged: BattleActor = _actor_by_id(state, actor.order_target_id)
	if engaged == null or engaged.faction != "enemy" or engaged.life != BattleActor.LIFE_ALIVE or engaged.position.distance_to(actor.position) > contact:
		engaged = _nearest_enemy_near_point(state, actor.position, actor.position, contact)
	actor.order_target_id = engaged.id if engaged != null else ""


## ig-gy0.6 (SYSTEMS.md § Hero AI on auto): the piloted hero moves on the player's orders alone. The target it
## already has is kept, and its attack-move still finds an enemy; an automatic order of any other kind (a stance
## move, a hold, a hop, an evade) is dropped, and a target that is gone leaves it standing with no new pick.
## The supplies retreat and the rescue carry skip it like any direct order (ig-axw); a carrier keeps its order.
static func _keep_piloted_order(state: BattleState, actor: BattleActor) -> void:
	actor.effect_state.erase("evade_point")
	var direct: bool = bool(actor.effect_state.get("direct_order", false))
	if not direct and actor.order_kind != COMMAND_ATTACK and actor.carrying_id.is_empty():
		actor.order_kind = ""
		actor.order_target_id = ""
		actor.effect_state.erase("kite_point")
	if actor.order_kind == COMMAND_ATTACK:
		var target: BattleActor = _actor_by_id(state, actor.order_target_id)
		if target == null or target.life != BattleActor.LIFE_ALIVE:
			actor.order_kind = ""
			actor.order_target_id = ""
			actor.effect_state["direct_order"] = false
	elif direct and actor.order_kind == COMMAND_ATTACK_MOVE:
		_engage_for_attack_move(state, actor)


static func _move_actors(state: BattleState) -> void:
	var paths: WallPaths = _wall_paths(state)
	var walled: bool = not paths.centers.is_empty()
	for actor: BattleActor in state.actors:
		if actor.life != BattleActor.LIFE_ALIVE or actor.effect_state.get("stun_remaining", 0.0) > 0.0 or _has_status(actor, "root"):
			continue
		_apply_separation(state, actor, paths)
		if actor.order_kind.is_empty() and not actor.effect_state.get("evade_point") is Array:
			continue
		if actor.order_kind == COMMAND_CARRY:
			_update_carry(state, actor)
		var destination: Vector2 = actor.order_point
		var target: BattleActor = _actor_by_id(state, actor.order_target_id)
		# An attack-move with a live target closes on it like ATTACK; with none it walks to its point.
		var engaging: bool = actor.order_kind == COMMAND_ATTACK_MOVE and target != null and target.life == BattleActor.LIFE_ALIVE
		if target != null and (actor.order_kind in [COMMAND_ATTACK, COMMAND_GUARD, COMMAND_CARRY] or engaging):
			destination = target.position
		var desired_range: float = 0.0
		if actor.order_kind == COMMAND_ATTACK or engaging:
			desired_range = actor.attack_range
		elif actor.order_kind == COMMAND_GUARD:
			desired_range = BALANCE.battle_guard_radius
		elif actor.order_kind == COMMAND_CARRY:
			desired_range = BALANCE.battle_carry_range
		elif actor.order_kind == COMMAND_HOLD:
			continue
		if actor.effect_state.get("evade_point") is Array:
			destination = _array_vector(actor.effect_state.get("evade_point"), destination)
			desired_range = 0.0
		if walled:
			# A point inside a footprint is reached at its edge, so the order can end there (Sol, ig-0qh).
			destination = _wall_goal(paths, actor.position, destination)
		var offset: Vector2 = destination - actor.position
		if offset.length() <= maxf(desired_range, REACH_TOLERANCE):
			if actor.order_kind == COMMAND_RETREAT and actor.position.distance_to(_objective_point(state, "exit_position")) <= BALANCE.battle_exit_radius:
				_extract_actor(state, actor)
				continue
			# Only on reaching the point: an attack-move in reach of its target is fighting, not arriving.
			if actor.order_kind == COMMAND_MOVE or (actor.order_kind == COMMAND_ATTACK_MOVE and not engaging):
				actor.order_kind = ""
				actor.order_target_id = ""
				actor.effect_state["direct_order"] = false
			continue
		var speed: float = actor.move_speed
		# ig-vl1.8: a slow works after the floor, once here, so the walled and straight steps both get it.
		var slow: float = _cut(actor, "speed")
		if slow < 0.0:
			speed *= 1.0 + slow
		if not actor.carrying_id.is_empty():
			speed *= BALANCE.battle_carry_speed_fraction
		# A hair inside a reach, never past a point.
		var step: float = minf(speed * BALANCE.battle_tick_seconds, minf(offset.length(), maxf(offset.length() - desired_range + REACH_TOLERANCE, 0.0)))
		if step > 0.0 and walled:
			# ig-0qh: toward the next corner when a wall is in the way, never past it; walled in, it holds.
			var waypoint: Variant = _next_waypoint(paths, actor.position, destination)
			if waypoint is Vector2:
				var heading: Vector2 = (waypoint as Vector2) - actor.position
				step = minf(step, heading.length())
				if step > 0.0:
					actor.facing = heading.normalized()
					actor.position = _wall_cut(paths, actor.position, _clamp_to_bounds(state, actor.position + actor.facing * step))
					if not actor.carrying_id.is_empty():
						var carried: BattleActor = _actor_by_id(state, actor.carrying_id)
						if carried != null:
							carried.position = actor.position
		elif step > 0.0:
			actor.facing = offset.normalized()
			actor.position += actor.facing * step
			actor.position = _clamp_to_bounds(state, actor.position)
			if not actor.carrying_id.is_empty():
				var carried: BattleActor = _actor_by_id(state, actor.carrying_id)
				if carried != null:
					carried.position = actor.position
		if actor.order_kind == COMMAND_RETREAT and actor.position.distance_to(_objective_point(state, "exit_position")) <= BALANCE.battle_exit_radius:
			_extract_actor(state, actor)


static func _support_actions(state: BattleState) -> void:
	# Only work that cannot aim is skipped (ig-7sn.7). With no ally down, the revive band and the revival
	# item have no one to aim at. Every heal rule, band or item, needs a living ally below its threshold,
	# so with the lowest one at or above the highest threshold no heal can aim. Both are read again after
	# any actor tries anything, landed or not: an effect list can stop part way.
	var anyone_down: bool = _ally_downed(state)
	var lowest: float = _lowest_ally_fraction(state)
	var heal_below: float = float(state.policies.get("heal_below", 0.35))
	var heal_ceiling: float = _heal_ceiling(state, heal_below)
	var heal_always: bool = heal_ceiling == INF
	for actor: BattleActor in state.actors:
		if actor.life != BattleActor.LIFE_ALIVE or actor.faction != "ally":
			continue
		# ig-gy0.6: the piloted hero casts and uses items only by the player's command.
		if actor.id == state.piloted_id:
			continue
		if not anyone_down and not heal_always and not (lowest < heal_ceiling):
			continue
		var landed: bool = false
		if anyone_down:
			landed = _auto_cast(state, actor, null, ["revive"], null)
			if not landed:
				var downed: BattleActor = _nearest_actor(state, actor, "ally", BattleActor.LIFE_DOWNED)
				landed = bool(state.policies.get("auto_revive", true)) and downed != null and actor.item_cooldown <= 0.0 and _use_revival(state, actor, downed, false)
		if not landed and (heal_always or lowest < heal_ceiling):
			landed = _auto_cast(state, actor, null, ["heal"], null)
		if not landed and lowest < heal_below and bool(state.policies.get("auto_heal", true)) and actor.item_cooldown <= 0.0:
			var hurt: BattleActor = _lowest_health_ally(state, actor.position, BALANCE.battle_revival_range)
			if hurt != null and hurt.hp / hurt.max_hp < heal_below:
				_use_healing(state, actor, hurt)
		anyone_down = _ally_downed(state)
		lowest = _lowest_ally_fraction(state)


static func _ally_downed(state: BattleState) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_DOWNED:
			return true
	return false


## The lowest HP fraction among living allies, or INF.
static func _lowest_ally_fraction(state: BattleState) -> float:
	var lowest: float = INF
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE and actor.hp / actor.max_hp < lowest:
			lowest = actor.hp / actor.max_hp
	return lowest


## The highest threshold any ally's heal-band ability aims below (heal_below or its ai_fraction), or INF
## when one could aim with no one below it (allies_below needing no ally). A NaN threshold passes no `<`
## test, so it is left out rather than folded in.
static func _heal_ceiling(state: BattleState, heal_below: float) -> float:
	var ceiling: float = -INF
	if heal_below > ceiling:
		ceiling = heal_below
	for actor: BattleActor in state.actors:
		if actor.faction != "ally":
			continue
		for entry: Dictionary in actor.skills:
			# get: a downed ally's skills are read here but not by the pass itself, so no new error on a bad id.
			var skill: AbilityDefinition = ABILITIES.get(entry["id"]) as AbilityDefinition
			if skill == null or not skill.is_ability() or skill.band() != "heal":
				continue
			if skill.ai_rule == "allies_below" and skill.ai_count <= 0:
				return INF
			if skill.ai_rule != "ally_below_heal_below" and skill.ai_fraction > ceiling:
				ceiling = skill.ai_fraction
	return ceiling


static func _offensive_actions(state: BattleState, rng: RandomNumberGenerator) -> void:
	# Every attacker in range turns to its target before anyone strikes, so a rear check
	# (_is_behind, _rogue_flank_position) never depends on which actor the loop reaches first.
	# Movement only turns units that are walking.
	for actor: BattleActor in state.actors:
		if actor.life != BattleActor.LIFE_ALIVE or actor.effect_state.get("stun_remaining", 0.0) > 0.0:
			continue
		if str(actor.effect_state.get("telegraph_kind", "")) != "":
			continue
		var in_range: BattleActor = _in_range_target(state, actor)
		if in_range != null:
			_face(actor, in_range.position)
	for actor: BattleActor in state.actors:
		if actor.life != BattleActor.LIFE_ALIVE or actor.effect_state.get("stun_remaining", 0.0) > 0.0:
			continue
		if str(actor.effect_state.get("telegraph_kind", "")) != "":
			if float(actor.effect_state.get("telegraph_remaining", 0.0)) <= 0.0:
				_resolve_telegraph(state, actor, rng)
			continue
		var target: BattleActor = _in_range_target(state, actor)
		# ig-gy0.5: the chain band sits between heal and buff (DECISIONS.md 2026-09-23 item 7). While a chain
		# waits on a step no other ability fires, and the swing below still lands.
		var chain: int = _chain_step(state, actor, rng) if actor.effect_state.has("chain_trigger") else CHAIN_NONE
		if chain == CHAIN_FIRED:
			continue
		# Before the range check: a rule that finds its own aim (Gauntlet Toss) reaches past the swing.
		# ig-gy0.6: the piloted hero picks no skill; it casts by the player's command and its chain steps.
		var piloted: bool = actor.id == state.piloted_id
		if chain == CHAIN_NONE and not piloted and _auto_cast(state, actor, target, ["buff", "attack"], rng):
			continue
		if target == null:
			continue
		if actor.attack_cooldown > 0.0:
			continue
		var windup: float = float(actor.effect_state.get("attack_windup_remaining", 0.0))
		if windup <= 0.0 and str(actor.effect_state.get("attack_target_id", "")).is_empty():
			actor.effect_state["attack_windup_remaining"] = BALANCE.battle_attack_windup_seconds
			actor.effect_state["attack_windup_total"] = BALANCE.battle_attack_windup_seconds
			actor.effect_state["attack_target_id"] = target.id
			continue
		if windup > 0.0:
			continue
		if str(actor.effect_state.get("attack_target_id", "")) != target.id:
			actor.effect_state["attack_target_id"] = ""
			continue
		# A weaponskill rides the swing: same windup, same interval (SYSTEMS.md § Skills). ig-gy0.6: the one the
		# player set comes first (it starts its chain by hand and leaves a waiting step waiting), then the chain's
		# step; the piloted hero's swing is otherwise plain, never a picked weaponskill.
		var by_hand: AbilityDefinition = _take_next_swing_skill(actor)
		var stepped: AbilityDefinition = _chain_weaponskill(actor, target) if chain == CHAIN_WAITING and by_hand == null else null
		var weaponskill: AbilityDefinition = by_hand if by_hand != null else stepped
		if weaponskill == null and not piloted:
			weaponskill = _pick_weaponskill(state, actor, target)
		if weaponskill != null:
			_use_weaponskill(state, actor, weaponskill, target, rng, by_hand != null)
		else:
			_damage(state, actor, target, 1.0, rng, true)
		if stepped != null:
			_chain_advance(state, actor)
		# ig-vl1.8: SPD's raise before the clamp (Hunter's Focus), a slow after it.
		actor.attack_cooldown = clampf(
			BALANCE.battle_basic_interval_numerator / maxf(_stat(actor, "speed", false), 0.001),
			BALANCE.battle_basic_interval_min,
			BALANCE.battle_basic_interval_max,
		)
		var slow: float = _cut(actor, "speed")
		if slow < 0.0:
			actor.attack_cooldown /= 1.0 + slow
		actor.effect_state["attack_target_id"] = ""


static func _update_objectives(state: BattleState) -> void:
	if state.kind == "rescue":
		return
	var zone: ZoneDefinition = state.zone
	if zone == null:
		state.status = "retreated"
		return
	match zone.battle_kind:
		"raid":
			_update_raid(state, zone)
		"region":
			_update_region(state, zone)
		_:
			_update_standard(state, zone)


static func _update_standard(state: BattleState, zone: ZoneDefinition) -> void:
	if _living_enemy_count(state) > 0:
		return
	state.completed_waves += 1
	if state.completed_waves > zone.trash_wave_count:
		state.status = "victory"
		return
	_spawn_wave(state, zone, state.completed_waves)


static func _update_raid(state: BattleState, zone: ZoneDefinition) -> void:
	var markers: Array = state.objective_state.get("markers", []) as Array
	var boss_spawned: bool = bool(state.objective_state.get("boss_spawned", false))
	if not boss_spawned:
		var all_held: bool = true
		for raw_marker: Variant in markers:
			if not raw_marker is Dictionary:
				continue
			var marker: Dictionary = raw_marker as Dictionary
			if str(marker.get("kind", "")) != "capture":
				continue
			var point: Vector2 = _array_vector(marker.get("position"))
			var occupied: bool = _actor_in_radius(state, "ally", point, float(marker.get("radius", 3.0)))
			var contested: bool = _actor_in_radius(state, "enemy", point, float(marker.get("radius", 3.0)))
			all_held = all_held and occupied and not contested
		var hold_limit: float = zone.objective_hold_seconds * state.pace
		var hold_seconds: float = float(state.objective_state.get("simultaneous_hold_seconds", 0.0))
		hold_seconds = minf(hold_seconds + BALANCE.battle_tick_seconds, hold_limit) if all_held else 0.0
		state.objective_state["simultaneous_hold_seconds"] = hold_seconds
		for raw_marker: Variant in markers:
			if raw_marker is Dictionary and str((raw_marker as Dictionary).get("kind", "")) == "capture":
				var marker: Dictionary = raw_marker as Dictionary
				marker["progress"] = hold_seconds / hold_limit
				marker["complete"] = hold_seconds + TICK_EPSILON >= hold_limit
		if hold_seconds + TICK_EPSILON >= hold_limit:
			boss_spawned = true
			state.completed_waves = 1
			state.objective_state["boss_spawned"] = true
			_spawn_group(state, Wave.from_zone(zone, zone.trash_wave_count).enemy_power, zone.boss_add_count + 1, Vector2(0, 8), true)
	if boss_spawned and _living_enemy_count(state) == 0:
		state.completed_waves = 2
		state.status = "victory"


static func _update_region(state: BattleState, zone: ZoneDefinition) -> void:
	var markers: Array = state.objective_state.get("markers", []) as Array
	var camps_complete: bool = true
	for raw_marker: Variant in markers:
		if not raw_marker is Dictionary:
			continue
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("kind", "")) != "camp":
			continue
		var camp_clear: bool = not _living_enemy_with_objective(state, str(marker.get("id", "")))
		marker["complete"] = camp_clear
		marker["progress"] = 1.0 if camp_clear else 0.0
		camps_complete = camps_complete and camp_clear
	if not camps_complete:
		return
	state.completed_waves = maxi(state.completed_waves, 1)
	state.objective_state["escort_active"] = true
	var escort_index: int = int(state.objective_state.get("escort_index", 0))
	if _living_enemy_count(state) > 0:
		return
	if escort_index > 0:
		state.completed_waves = maxi(state.completed_waves, escort_index + 1)
	if escort_index >= zone.escort_waypoints.size():
		state.status = "victory"
		return
	var cart_position: Vector2 = _objective_point(state, "cart_position")
	var destination: Vector2 = zone.escort_waypoints[escort_index]
	if _actor_in_radius(state, "ally", cart_position, 4.0) and not _actor_in_radius(state, "enemy", cart_position, 4.0):
		cart_position = cart_position.move_toward(destination, zone.cart_speed * BALANCE.battle_tick_seconds)
		state.objective_state["cart_position"] = [cart_position.x, cart_position.y]
		_update_cart_marker(state, cart_position)
	if cart_position.distance_to(destination) <= TICK_EPSILON:
		var final_waypoint: bool = escort_index == zone.escort_waypoints.size() - 1
		var wave_index: int = zone.trash_wave_count if final_waypoint else escort_index
		_spawn_group(state, Wave.from_zone(zone, wave_index).enemy_power, 1 if final_waypoint else 10, destination, final_waypoint)
		state.objective_state["escort_index"] = escort_index + 1
		_complete_waypoint_marker(state, escort_index)


static func _evaluate_terminal(state: BattleState) -> void:
	if state.status != "active":
		return
	var living_allies: int = 0
	var extracted_allies: int = 0
	var downed_allies: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction != "ally" or actor.hero_id.is_empty():
			continue
		match actor.life:
			BattleActor.LIFE_ALIVE:
				living_allies += 1
			BattleActor.LIFE_EXTRACTED:
				extracted_allies += 1
			BattleActor.LIFE_DOWNED:
				downed_allies += 1
	if living_allies == 0:
		if extracted_allies > 0:
			state.status = "retreated" if downed_allies == 0 else "stranded"
		else:
			state.status = "stranded"


static func _finish_timeout(state: BattleState) -> void:
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE:
			_drop_carried(state, actor)
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE:
			_extract_actor(state, actor)
	state.status = "timeout"


static func _spawn_initial_enemies(state: BattleState, zone: ZoneDefinition) -> void:
	match zone.battle_kind:
		"raid":
			for index: int in zone.objective_points.size():
				@warning_ignore("integer_division")
				_spawn_group(state, Wave.from_zone(zone, 0).enemy_power / 3.0, zone.objective_enemy_count / 3, zone.objective_points[index], false, "capture:%d" % index)
		"region":
			for index: int in zone.objective_points.size():
				@warning_ignore("integer_division")
				_spawn_group(state, Wave.from_zone(zone, 0).enemy_power / 3.0, zone.objective_enemy_count / 3, zone.objective_points[index], false, "camp:%d" % index)
		_:
			_spawn_wave(state, zone, 0)


static func _spawn_wave(state: BattleState, zone: ZoneDefinition, wave_index: int) -> void:
	var boss: bool = wave_index == zone.trash_wave_count
	var count: int = 1 if boss else zone.trash_enemy_count
	_spawn_group(state, Wave.from_zone(zone, wave_index).enemy_power, count, Vector2(0, 8), boss)


static func _spawn_group(
	state: BattleState,
	wave_power: float,
	count: int,
	center: Vector2,
	boss: bool = false,
	objective_id: String = "",
) -> void:
	var deployed_count: int = maxi(_deployed_hero_count(state), 1)
	var zone: ZoneDefinition = state.zone
	assert(zone != null)
	var scaled_power: float = wave_power * float(deployed_count) / float(maxi(zone.reference_force_size, 1))
	var budget: float = scaled_power / float(maxi(count, 1))
	var facing: Vector2 = _facing_toward_opponents(state, "enemy", center, Vector2.DOWN)
	for index: int in count:
		var actor := BattleActor.new()
		actor.spawn_index = state.actors.size()
		actor.id = "enemy:%s:%d:%d" % [state.order_id, state.completed_waves, actor.spawn_index]
		actor.archetype = "knight" if boss and index == 0 else ROLE_CYCLE[actor.spawn_index % ROLE_CYCLE.size()]
		actor.faction = "enemy"
		actor.squad_id = "enemy"
		actor.position = center + _grid_offset(index, count, BALANCE.battle_formation_spacing)
		actor.facing = facing
		actor.max_hp = budget * BALANCE.battle_enemy_hp_budget_multiplier * state.pace
		actor.hp = actor.max_hp
		actor.atk = budget * BALANCE.battle_enemy_atk_budget_multiplier
		actor.defense = budget * BALANCE.battle_enemy_def_budget_multiplier
		actor.speed = BALANCE.battle_enemy_speed
		actor.crit_rate = BALANCE.battle_enemy_crit_rate
		actor.crit_damage = BALANCE.battle_enemy_crit_damage
		for skill: AbilityDefinition in enemy_kit(actor.archetype):
			actor.add_skill(skill)
		actor.attack_range = _attack_range(actor)
		actor.move_speed = clampf(actor.speed * BALANCE.battle_move_speed_per_stat, BALANCE.battle_move_speed_min, BALANCE.battle_move_speed_max)
		actor.effect_state = _default_effect_state(boss and index == 0)
		actor.effect_state["home_position"] = [actor.position.x, actor.position.y]
		actor.effect_state["objective_id"] = objective_id
		state.actors.append(actor)


## Spawn facing: toward the other side's living centre, so an unengaged unit never shows its back
## to the fight and a Rogue earns its rear bonus by flanking (SYSTEMS.md, director ruling
## 2026-09-23). fallback when the other side is empty or sits on top of from.
static func _facing_toward_opponents(state: BattleState, faction: String, from: Vector2, fallback: Vector2) -> Vector2:
	var total := Vector2.ZERO
	var count: int = 0
	for other: BattleActor in state.actors:
		if other.faction != faction and other.life == BattleActor.LIFE_ALIVE:
			total += other.position
			count += 1
	if count == 0:
		return fallback
	var toward: Vector2 = total / float(count) - from
	return fallback if toward.is_zero_approx() else toward.normalized()


## pace multiplies a fresh snapshot's HP; a checkpointed actor (max_hp and effect_state) already has it.
static func _actor_from_team_snapshot(snapshot: Dictionary, spawn_index: int, zone: ZoneDefinition, pace: int = 1) -> BattleActor:
	if snapshot.has("max_hp") and snapshot.has("effect_state"):
		return BattleActor.from_dict(snapshot)
	var actor := BattleActor.new()
	actor.spawn_index = int(snapshot.get("spawn_index", spawn_index))
	actor.hero_id = str(snapshot.get("hero_id", ""))
	actor.id = str(snapshot.get("id", "hero:%s" % actor.hero_id))
	actor.archetype = str(snapshot.get("archetype", "knight")).to_lower()
	actor.faction = str(snapshot.get("faction", "ally"))
	actor.squad_id = str(snapshot.get("squad_id", "squad:0"))
	actor.position = _array_vector(snapshot.get("position"), zone.exit_position + _grid_offset(spawn_index, maxi(spawn_index + 1, 5), BALANCE.battle_formation_spacing))
	actor.facing = _array_vector(snapshot.get("facing"), Vector2.UP)
	var base_max_hp: float = maxf(float(snapshot.get("max_hp", snapshot.get("hp", 1.0))), 1.0)
	actor.max_hp = base_max_hp * pace
	actor.hp = clampf(float(snapshot.get("current_hp", snapshot.get("hp", base_max_hp))) * pace, 0.0, actor.max_hp)
	actor.atk = maxf(float(snapshot.get("atk", 1.0)), 0.0)
	actor.defense = maxf(float(snapshot.get("defense", 0.0)), 0.0)
	actor.speed = maxf(float(snapshot.get("speed", 1.0)), 0.001)
	actor.crit_rate = clampf(float(snapshot.get("crit_rate", 0.0)), 0.0, 1.0)
	actor.crit_damage = maxf(float(snapshot.get("crit_damage", 1.0)), 1.0)
	actor.life = str(snapshot.get("life", BattleActor.LIFE_ALIVE))
	if snapshot.get("skills") is Array:
		# A snapshot that carries its kit (item 8); ids that are unknown, another class's or repeated
		# are left out, every ability ready. A kit left with no ability falls back to the default.
		for entry: Variant in snapshot.get("skills") as Array:
			var skill_id: String = str((entry as Dictionary).get("id", "")) if entry is Dictionary else ""
			if ABILITIES.has(skill_id) and ABILITIES[skill_id].archetype in BattleActor.kit_archetypes(actor.archetype, actor.faction) and not actor.skills.any(func(kept: Dictionary) -> bool: return kept["id"] == skill_id):
				actor.add_skill(ABILITIES[skill_id], str((entry as Dictionary).get("mode", "auto")))
		if actor.skill_cooldowns.is_empty():
			actor.set_default_kit(bool(snapshot.get("ability_auto", true)))
	elif _valid_number(snapshot.get("level")):
		# The known kit: class skills open at or below the hero's level, then anything learned
		# (books and the Training Hall, ig-gy0.3). Level skills are derived, never saved. Heroes start
		# at level 0 and the first slot opens at level 1 (SYSTEMS.md § Learning), so level 0 has it too.
		# The old per-hero ability_auto flag covers abilities only; weaponskills stay on.
		var mode: String = "auto" if bool(snapshot.get("ability_auto", true)) else "manual"
		for skill: AbilityDefinition in known_kit(actor.archetype, Hero.skill_level(int(snapshot.get("level")))):
			actor.add_skill(skill, mode if skill.is_ability() else "auto")
		var learned: Variant = snapshot.get("learned_skills")
		for skill_id: Variant in learned as Array if learned is Array else []:
			var skill: AbilityDefinition = ABILITIES.get(str(skill_id)) as AbilityDefinition
			if skill != null and skill.archetype in [actor.archetype, "general"] and not actor.skills.any(func(kept: Dictionary) -> bool: return kept["id"] == str(skill_id)):
				actor.add_skill(skill, mode if skill.is_ability() else "auto")
	else:
		actor.set_default_kit(bool(snapshot.get("ability_auto", true)))
	actor.take_chains(snapshot.get("chains"))
	actor.attack_range = _attack_range(actor)
	actor.move_speed = clampf(actor.speed * BALANCE.battle_move_speed_per_stat, BALANCE.battle_move_speed_min, BALANCE.battle_move_speed_max)
	actor.effect_state = _default_effect_state(bool(snapshot.get("elite", false)))
	var snapshot_effects: Variant = snapshot.get("effect_state")
	if snapshot_effects is Dictionary:
		actor.effect_state.merge((snapshot_effects as Dictionary).duplicate(true), true)
	if not snapshot_effects is Dictionary or not (snapshot_effects as Dictionary).has("home_position"):
		actor.effect_state["home_position"] = [actor.position.x, actor.position.y]
	# ig-uu7.4: a Knight's cover order, derived for this one battle and saved with it like its stats.
	if snapshot.get("cover_order") is Array:
		var cover_order: Array = []
		for hero_id: Variant in snapshot.get("cover_order") as Array:
			if hero_id is String:
				cover_order.append(hero_id)
		actor.effect_state["cover_order"] = cover_order
	if actor.life in [BattleActor.LIFE_DOWNED, BattleActor.LIFE_DEAD]:
		actor.hp = 0.0
	return actor


## Casts ability: checks readiness, range and target, then applies its effects in order. Nothing here
## knows which skill it is. False, with nothing changed, when the cast cannot resolve.
static func _use_skill(
	state: BattleState,
	actor: BattleActor,
	skill: AbilityDefinition,
	target: BattleActor,
	point: Vector2,
	rng: RandomNumberGenerator = null,
	across: Vector2 = Vector2.ZERO,
) -> bool:
	if not _skill_refusal(state, actor, skill, target, point).is_empty():
		return false
	if not _apply_effects(state, actor, skill, target, point, rng, false, false, across):
		return false
	# The caster faces what it cast at, manual or auto; a caster that moved, or cast around itself,
	# faces its target.
	_face(actor, target.position if target != null and (not _effect_of(skill, "move").is_empty() or skill.self_centered) else point)
	_spend_ability(state, actor, skill)
	return true


## Why actor cannot cast skill at target (or at point, with none) right now, or "" when it can: the checks of
## _use_skill in its order, each with its own words (ig-gy0.6). It looks at the cast and not at what the
## effects would find: a cast with nobody in reach only shows once _apply_effects has run.
static func _skill_refusal(_state: BattleState, actor: BattleActor, skill: AbilityDefinition, target: BattleActor, point: Vector2) -> String:
	if actor.life != BattleActor.LIFE_ALIVE:
		return "That hero is not standing."
	if not skill.is_ability():
		return "A passive is always on and is never fired." if skill.kind == "passive" else "A weaponskill rides the swing; it is not cast."
	if float(actor.skill_cooldowns.get(str(skill.skill_id), 0.0)) > 0.0:
		return "That skill is still on cooldown."
	if actor.ability_lock > 0.0:
		return "Another ability was just used; the ability lock holds."
	if float(actor.effect_state.get("stun_remaining", 0.0)) > 0.0:
		return "The hero is stunned."
	if _has_status(actor, "silence"):
		return "The hero is silenced."
	var distance: float = actor.position.distance_to(point)
	if distance > skill.range_units:
		return "That is out of range."
	if distance < skill.min_range_units:
		return "That is too close."
	if _needs_enemy_target(skill) and (target == null or target.faction == actor.faction or target.life != BattleActor.LIFE_ALIVE):
		return "That skill needs a living enemy as its target."
	var heal: Dictionary = _effect_of(skill, "heal")
	if not heal.is_empty() and str(heal.get("area", "target")) == "target" and (target == null or target.faction != actor.faction or target.life != BattleActor.LIFE_ALIVE or target.hp >= target.max_hp):
		return "That skill needs a hurt ally as its target."
	if not _effect_of(skill, "shield").is_empty() and (target == null or target.faction != actor.faction or target.life != BattleActor.LIFE_ALIVE):
		return "That skill needs a living ally as its target."
	if not _effect_of(skill, "move").is_empty() and _has_status(actor, "root"):
		return "The hero is rooted."
	return ""


## A weaponskill rides the basic swing (SYSTEMS.md § Skills): no cooldown, no lock. Its primary hit
## counts as a basic hit. A combo step lands its combo_multiplier and combo-only statuses.
## by_hand: the player set it for this swing (ig-gy0.6), so a chain it triggers replaces a running one.
static func _use_weaponskill(state: BattleState, actor: BattleActor, skill: AbilityDefinition, target: BattleActor, rng: RandomNumberGenerator, by_hand: bool = false) -> void:
	if not _apply_effects(state, actor, skill, target, target.position, rng, _combo_ready(state, actor, skill), true):
		_damage(state, actor, target, 1.0, rng, true)
		return
	actor.combo_skill = str(skill.skill_id)
	actor.combo_tick = state.tick
	_start_chain(state, actor, skill, by_hand)


## ig-gy0.6: the weaponskill the player set for this swing, taken off the actor as it is read. Null when none is
## set, when the hero is silenced at the swing (a plain one) or when it has left the bar.
static func _take_next_swing_skill(actor: BattleActor) -> AbilityDefinition:
	if not actor.effect_state.has("next_swing_skill"):
		return null
	var skill_id: String = str(actor.effect_state["next_swing_skill"])
	actor.effect_state.erase("next_swing_skill")
	var skill: AbilityDefinition = ABILITIES.get(skill_id) as AbilityDefinition
	if skill == null or skill.kind != "weaponskill" or _skill_mode(actor, skill_id).is_empty() or _has_status(actor, "silence"):
		return null
	return skill


## The cooldown (x the battle's pace, ig-1jw), the ability lock and the tick the views read.
static func _spend_ability(state: BattleState, actor: BattleActor, skill: AbilityDefinition) -> void:
	actor.skill_cooldowns[str(skill.skill_id)] = _skill_cooldown(actor, skill) * state.pace
	actor.ability_lock = BALANCE.skill_ability_lock_seconds
	actor.effect_state["last_skill_tick"] = state.tick
	actor.effect_state["last_skill_id"] = str(skill.skill_id)
	_start_chain(state, actor, skill, false)


## The primitives, in the skill's order (AbilityDefinition.EFFECT_KEYS). False only when a required
## effect (which comes before anything that changes state) finds nothing, or a wall can't be placed.
## across: the line a wall goes across (its caster's aim).
static func _apply_effects(
	state: BattleState,
	actor: BattleActor,
	skill: AbilityDefinition,
	target: BattleActor,
	point: Vector2,
	rng: RandomNumberGenerator,
	combo: bool,
	weaponskill: bool,
	across: Vector2 = Vector2.ZERO,
) -> bool:
	var heal_scale: float = 1.0 + _passive(actor, "heal_bonus")
	# ig-1jw: an ability's ATK amounts and status or control seconds are x the battle's pace. A
	# weaponskill, a dodge window, a delay and max-HP fractions stay as authored.
	var pace: float = 1.0 if weaponskill else float(state.pace)
	for effect: Dictionary in skill.effects:
		match str(effect["type"]):
			"revive":
				if target != null and target.faction == actor.faction and target.life == BattleActor.LIFE_DOWNED:
					_revive_actor(state, target, float(effect["fraction"]), actor)
					if bool(effect.get("stop", false)):
						break
			"status":
				if bool(effect.get("combo", false)) and not combo:
					continue
				var kind: String = str(effect["status"])
				var magnitude: float = float(effect.get("magnitude", 0.0))
				if kind in ["bleed", "burn"]:
					magnitude *= _stat(actor, "atk")
				elif kind == "heal_over_time":
					magnitude *= _stat(actor, "atk") * heal_scale
				for receiver: BattleActor in _status_receivers(state, actor, skill, effect, target):
					_add_status(receiver, str(skill.skill_id), kind, actor.id, float(effect["seconds"]) * (1.0 if kind == "dodge" else pace), magnitude)
			"move":
				var destination: Variant = null
				match str(effect["to"]):
					"behind_target":
						destination = _rogue_flank_position(state, actor, target)
					"charge":
						destination = _charge(state, actor, target, skill, effect)
					_:
						destination = _away_point(state, actor, target, float(effect.get("distance", 0.0)))
				if not destination is Vector2:
					return false
				actor.position = _wall_cut(_wall_paths(state), actor.position, destination as Vector2)
				# A carried body moves with its carrier, as in _push (ig-zht).
				if not actor.carrying_id.is_empty():
					var carried: BattleActor = _actor_by_id(state, actor.carrying_id)
					if carried != null:
						carried.position = actor.position
			"heal":
				var healed: Array[BattleActor] = []
				match str(effect.get("area", "target")):
					"target":
						healed.append(target)
					"self":
						healed.append(actor)
					_:
						healed = _living_in_radius(state, actor.faction, actor.position, skill.radius_units)
				for ally: BattleActor in healed:
					if ally != null and ally.life == BattleActor.LIFE_ALIVE:
						var amount: float = _stat(actor, "atk") * float(effect["multiplier"]) * pace if effect.has("multiplier") else ally.max_hp * float(effect["max_hp_fraction"])
						ally.hp = minf(ally.hp + amount * heal_scale, ally.max_hp)
			"shield":
				_add_status(target, str(skill.skill_id), "shield", actor.id, float(effect["seconds"]) * pace, _stat(actor, "atk") * float(effect["multiplier"]) * heal_scale * pace)
			"interrupt":
				var stunned: Array[BattleActor] = []
				if str(effect.get("area", "target")) == "around_caster":
					stunned = _living_in_radius(state, "enemy" if actor.faction == "ally" else "ally", actor.position, skill.radius_units)
				elif target != null and target.life == BattleActor.LIFE_ALIVE:
					stunned.append(target)
				for victim: BattleActor in stunned:
					victim.effect_state["stun_remaining"] = maxf(float(victim.effect_state.get("stun_remaining", 0.0)), float(effect["stun_seconds"]) * pace)
					_cancel_pending_action(victim)
			"taunt":
				if target != null and target.life == BattleActor.LIFE_ALIVE:
					_add_status(target, str(skill.skill_id), "taunt", actor.id, float(effect["seconds"]) * pace, 0.0)
			"zone":
				# Its lifetime is x the pace; its per-second amounts are not (SYSTEMS.md § Casters, Zones).
				while state.field_objects.size() >= BALANCE.battle_field_object_cap:
					state.field_objects.remove_at(0)
				state.field_sequence += 1
				state.field_objects.append({
					"id": "field:%d" % state.field_sequence,
					"kind": "zone",
					"skill_id": str(skill.skill_id),
					"owner_actor_id": actor.id,
					"faction": actor.faction,
					"center": [point.x, point.y],
					"radius": skill.radius_units,
					"remaining_seconds": float(effect["seconds"]) * pace,
					"atk": _stat(actor, "atk"),
					"heal_scale": heal_scale,
				})
			"wall":
				# A wall is its skill's only effect, so a refusal changes nothing.
				if not _cast_wall(state, actor, skill, effect, point, across, pace):
					return false
			"damage":
				var multiplier: float = (float(effect["combo_multiplier"]) if combo and effect.has("combo_multiplier") else float(effect["multiplier"])) * pace
				if effect.has("delay_seconds"):
					# A delayed area is marked now and lands later, like an enemy's telegraph.
					_start_telegraph(state, actor, skill, point, float(effect["delay_seconds"]))
					continue
				var hit_any: bool = false
				# Every hit lands at pre-push positions, then the pushes (SYSTEMS.md § Knockback).
				var push: float = float(effect.get("push", 0.0))
				var pushes: Array = []
				match str(effect["area"]):
					"target":
						_damage(state, actor, target, multiplier, rng, weaponskill)
						hit_any = true
					"line":
						var direction: Vector2 = (target.position - actor.position).normalized()
						for candidate: BattleActor in state.actors:
							if candidate.faction == actor.faction or candidate.life != BattleActor.LIFE_ALIVE:
								continue
							var along: float = (candidate.position - actor.position).dot(direction)
							var closest: Vector2 = actor.position + direction * along
							if along >= 0.0 and along <= skill.range_units and candidate.position.distance_to(closest) <= skill.radius_units * 0.5:
								_damage(state, actor, candidate, multiplier, rng)
								hit_any = true
								pushes.append([candidate, direction])
					"circle", "around_caster":
						var center: Vector2 = point if str(effect["area"]) == "circle" else actor.position
						for candidate: BattleActor in state.actors:
							if candidate.faction != actor.faction and candidate.life == BattleActor.LIFE_ALIVE and candidate.position.distance_to(center) <= skill.radius_units:
								_damage(state, actor, candidate, multiplier, rng)
								hit_any = true
								pushes.append([candidate, candidate.position - center])
					"near_target":
						for candidate: BattleActor in _nearest_others(state, actor, target, skill.radius_units, int(effect["count"])):
							_damage(state, actor, candidate, multiplier, rng)
							hit_any = true
				_push_all(state, pushes, actor.facing, push)
				if not hit_any and bool(effect.get("required", false)):
					return false
	return true


## Who a status effect lands on: the caster, the target, or the caster's living side near it.
static func _status_receivers(state: BattleState, actor: BattleActor, skill: AbilityDefinition, effect: Dictionary, target: BattleActor) -> Array[BattleActor]:
	var receivers: Array[BattleActor] = []
	match str(effect["target"]):
		"self":
			receivers.append(actor)
		"target":
			if target != null and target.life == BattleActor.LIFE_ALIVE:
				receivers.append(target)
		_:
			receivers = _living_in_radius(state, actor.faction, actor.position, float(effect.get("radius", skill.radius_units)))
	return receivers


static func _living_in_radius(state: BattleState, faction: String, center: Vector2, radius: float) -> Array[BattleActor]:
	var found: Array[BattleActor] = []
	for candidate: BattleActor in state.actors:
		if candidate.faction == faction and candidate.life == BattleActor.LIFE_ALIVE and candidate.position.distance_to(center) <= radius:
			found.append(candidate)
	return found


## Up to count living opponents of actor nearest target (target excluded), within radius of it.
static func _nearest_others(state: BattleState, actor: BattleActor, target: BattleActor, radius: float, count: int) -> Array[BattleActor]:
	var found: Array[BattleActor] = []
	for candidate: BattleActor in state.actors:
		if candidate != target and candidate.faction != actor.faction and candidate.life == BattleActor.LIFE_ALIVE and candidate.position.distance_to(target.position) <= radius:
			found.append(candidate)
	var center: Vector2 = target.position
	found.sort_custom(func(a: BattleActor, b: BattleActor) -> bool: return a.position.distance_squared_to(center) < b.position.distance_squared_to(center) or (a.position.distance_squared_to(center) == b.position.distance_squared_to(center) and a.spawn_index < b.spawn_index))
	found.resize(mini(found.size(), count))
	return found


## distance straight back from target (or from where the actor faces, without one).
static func _away_point(state: BattleState, actor: BattleActor, target: BattleActor, distance: float) -> Vector2:
	var back: Vector2 = (actor.position - target.position).normalized() if target != null and target.position != actor.position else -actor.facing.normalized()
	return _clamp_to_bounds(state, actor.position + back * distance)


## Adds a status, or refreshes the one this skill already put there: the longer time and the larger
## magnitude, never a second copy (SYSTEMS.md § Skills).
static func _add_status(actor: BattleActor, id: String, kind: String, source: String, seconds: float, magnitude: float) -> void:
	for status: Dictionary in actor.statuses:
		if status["id"] == id and status["kind"] == kind:
			status["remaining"] = maxf(float(status["remaining"]), seconds)
			status["magnitude"] = maxf(float(status["magnitude"]), magnitude)
			status["source"] = source
			return
	actor.statuses.append({"id": id, "kind": kind, "source": source, "remaining": seconds, "magnitude": magnitude})


## The strongest magnitude of kind on actor, or 0 (the strongest damage reduction wins).
static func _status_value(actor: BattleActor, kind: String) -> float:
	var strongest: float = 0.0
	for status: Dictionary in actor.statuses:
		if status["kind"] == kind:
			strongest = maxf(strongest, float(status["magnitude"]))
	return strongest


static func _has_status(actor: BattleActor, kind: String) -> bool:
	for status: Dictionary in actor.statuses:
		if status["kind"] == kind:
			return true
	return false


## One of the five combat stats with its strongest raise and its strongest cut applied. Only Rime
## Circle's slow cuts (ig-vl1.4); with no cut lo stays 0.0, so the sum is the old one to the bit.
## with_cut false leaves the cut out: the swing and the walk take a slow after their clamps (_cut).
static func _stat(actor: BattleActor, stat: String, with_cut: bool = true) -> float:
	var base: float = 0.0
	match stat:
		"atk":
			base = actor.atk
		"defense":
			base = actor.defense
		"speed":
			base = actor.speed
		"crit_rate":
			base = actor.crit_rate
		"crit_damage":
			base = actor.crit_damage
	if actor.statuses.is_empty():
		return base
	var hi: float = 0.0
	var lo: float = 0.0
	for status: Dictionary in actor.statuses:
		if status["kind"] == stat:
			hi = maxf(hi, float(status["magnitude"]))
			lo = minf(lo, float(status["magnitude"]))
	return base * (1.0 + hi + (lo if with_cut else 0.0))


## ig-vl1.8: a stat's strongest cut, 0.0 with none (SYSTEMS § Statuses, amended). A slow works after
## the clamps: the swing interval x 1 / (1 + cut), the walk step x (1 + cut).
static func _cut(actor: BattleActor, stat: String) -> float:
	var lo: float = 0.0
	for status: Dictionary in actor.statuses:
		if status["kind"] == stat:
			lo = minf(lo, float(status["magnitude"]))
	return lo


## ig-vl1.4 (DECISIONS.md 2026-09-25, "Casters shape the field", item 3): the one point in the tick where
## zones act, oldest first. Each counts down as _tick_statuses does and pulses each time its time left
## crosses a multiple of skill_status_tick_seconds: 1 s after the cast, and so on to the last as it ends.
## A pulse lands on living actors of its side inside it, in actor order, and draws no RNG. One skill
## lands once per actor per tick, however many of its zones overlap there.
static func _update_field_objects(state: BattleState) -> void:
	if state.field_objects.is_empty():
		return
	var period: float = BALANCE.skill_status_tick_seconds
	var landed: Dictionary = {}
	var kept: Array[Dictionary] = []
	for field: Dictionary in state.field_objects:
		var before: float = float(field["remaining_seconds"])
		var after: float = before - BALANCE.battle_tick_seconds if before - BALANCE.battle_tick_seconds >= TICK_EPSILON else 0.0
		field["remaining_seconds"] = after
		if field["kind"] == "zone" and ceilf(before / period - TICK_EPSILON) > ceilf(after / period - TICK_EPSILON):
			_pulse_zone(state, field, landed)
		if after > 0.0:
			kept.append(field)
	state.field_objects = kept


## Damage the way bleed's lands (through damage reduction and shields, no DEF), credited to the caster
## even when it is down or gone; a heal with Grace's heal_scale from the cast; statuses of 1.5 real s.
static func _pulse_zone(state: BattleState, field: Dictionary, landed: Dictionary) -> void:
	var skill_id: String = str(field["skill_id"])
	var zone: Dictionary = _effect_of(ABILITIES[skill_id], "zone")
	var faction: String = str(field["faction"])
	var side: String = faction if str(zone["side"]) == "allies" else ("enemy" if faction == "ally" else "ally")
	var center: Vector2 = _array_vector(field["center"])
	var owner: BattleActor = _actor_by_id(state, str(field["owner_actor_id"]))
	for actor: BattleActor in state.actors:
		if actor.faction != side or actor.life != BattleActor.LIFE_ALIVE or actor.position.distance_to(center) > float(field["radius"]):
			continue
		var key: String = skill_id + "|" + actor.id
		if landed.has(key):
			continue
		landed[key] = true
		for pulse: Dictionary in zone["pulse"]:
			if actor.life != BattleActor.LIFE_ALIVE:
				break
			match str(pulse["type"]):
				"damage":
					_take_damage(state, owner if owner != null else actor, actor, float(field["atk"]) * float(pulse["multiplier"]) * (1.0 - _status_value(actor, "damage_reduction")))
				"heal":
					actor.hp = minf(actor.hp + float(field["atk"]) * float(pulse["multiplier"]) * float(field["heal_scale"]), actor.max_hp)
				"status":
					_add_status(actor, skill_id, str(pulse["status"]), str(field["owner_actor_id"]), float(pulse["seconds"]), float(pulse["magnitude"]))


## Counts statuses down, on the downed too (as the old guard did: a hero revived inside Stand Fast keeps
## it). Bleed, burn and heal-over-time land, on the living only, each time the time left crosses a
## multiple of skill_status_tick_seconds; damage goes through damage reduction and shields, credited to
## its source.
static func _tick_statuses(state: BattleState, actor: BattleActor) -> void:
	if actor.statuses.is_empty():
		return
	var period: float = BALANCE.skill_status_tick_seconds
	var kept: Array[Dictionary] = []
	for status: Dictionary in actor.statuses.duplicate():
		var before: float = float(status["remaining"])
		# ig-85w: the count-down of _expire_effects_and_cooldowns.
		var after: float = before - BALANCE.battle_tick_seconds if before - BALANCE.battle_tick_seconds >= TICK_EPSILON else 0.0
		status["remaining"] = after
		var kind: String = str(status["kind"])
		if actor.life == BattleActor.LIFE_ALIVE and kind in ["bleed", "burn", "heal_over_time"] and ceilf(before / period - TICK_EPSILON) > ceilf(after / period - TICK_EPSILON):
			var amount: float = float(status["magnitude"]) * period
			if kind == "heal_over_time":
				actor.hp = minf(actor.hp + amount, actor.max_hp)
			else:
				var source: BattleActor = _actor_by_id(state, str(status["source"]))
				_take_damage(state, source if source != null else actor, actor, amount * (1.0 - _status_value(actor, "damage_reduction")))
		if after > 0.0 and not (kind == "shield" and float(status["magnitude"]) <= 0.0):
			kept.append(status)
	actor.statuses = kept


## The living actor that taunted this one, or null.
static func _taunter(state: BattleState, actor: BattleActor) -> BattleActor:
	for status: Dictionary in actor.statuses:
		if status["kind"] == "taunt":
			var source: BattleActor = _actor_by_id(state, str(status["source"]))
			if source != null and source.life == BattleActor.LIFE_ALIVE:
				return source
	return null


## A line, a single-target or chained hit, a move behind someone or a taunt needs a living enemy.
static func _needs_enemy_target(skill: AbilityDefinition) -> bool:
	for effect: Dictionary in skill.effects:
		match str(effect["type"]):
			"move":
				if str(effect["to"]) in ["behind_target", "charge"]:
					return true
			"taunt":
				return true
			"damage":
				if str(effect["area"]) in ["target", "line", "near_target"]:
					return true
	return false


## Arcane Flow's cooldown_reduction covers every ability the Mage casts.
static func _skill_cooldown(actor: BattleActor, skill: AbilityDefinition) -> float:
	return skill.cooldown_seconds * (1.0 - _passive(actor, "cooldown_reduction"))


## The magnitude of the actor's passive status, or 0.
static func _passive(actor: BattleActor, status: String) -> float:
	return float(_passive_effect(actor, status).get("magnitude", 0.0))


static func _passive_effect(actor: BattleActor, status: String) -> Dictionary:
	for entry: Dictionary in actor.skills:
		var skill: AbilityDefinition = ABILITIES[entry["id"]]
		if skill.kind == "passive":
			for effect: Dictionary in skill.effects:
				if str(effect.get("status", "")) == status:
					return effect
	return {}


## An enemy casting a line or circle shows it first (the telegraph); anything else lands at once.
static func _telegraph_kind(skill: AbilityDefinition) -> String:
	var damage: Dictionary = _effect_of(skill, "damage")
	return str(damage["area"]) if str(damage.get("area", "")) in ["line", "circle"] else ""


## The skill's first effect of type, or {}.
static func _effect_of(skill: AbilityDefinition, type: String) -> Dictionary:
	for effect: Dictionary in skill.effects:
		if str(effect["type"]) == type:
			return effect
	return {}


## The actor's abilities in bar order; passives and weaponskills left out.
static func _abilities(actor: BattleActor) -> Array[AbilityDefinition]:
	var abilities: Array[AbilityDefinition] = []
	for entry: Dictionary in actor.skills:
		if ABILITIES[entry["id"]].is_ability():
			abilities.append(ABILITIES[entry["id"]])
	return abilities


## The first ability on the bar not set to Off (a manual cast fires it), or null.
static func _signature(actor: BattleActor) -> AbilityDefinition:
	for entry: Dictionary in actor.skills:
		if ABILITIES[entry["id"]].is_ability() and entry["mode"] != "off":
			return ABILITIES[entry["id"]]
	return null


## The one picker (SYSTEMS.md § Skills): the first ready Auto ability, band by band in the order
## given (revive, heal, buff, attack), then bar order, whose AI rule finds an aim and whose cast
## resolves. An enemy's line or circle starts a telegraph instead. True when something was cast.
static func _auto_cast(state: BattleState, actor: BattleActor, target: BattleActor, bands: Array[String], rng: RandomNumberGenerator) -> bool:
	if actor.ability_lock > 0.0 or float(actor.effect_state.get("stun_remaining", 0.0)) > 0.0 or _has_status(actor, "silence"):
		return false
	for band: String in bands:
		for entry: Dictionary in actor.skills:
			var skill: AbilityDefinition = ABILITIES[entry["id"]]
			if not skill.is_ability() or str(entry["mode"]) != "auto" or float(actor.skill_cooldowns.get(entry["id"], 0.0)) > 0.0:
				continue
			if skill.band() != band and not (band == "revive" and skill.ai_revive_first):
				continue
			var aim_from: BattleActor = target
			if skill.min_range_units > 0.0:
				# ig-zht: a skill with a minimum range (Charge) looks at the actor's current target, near or
				# far. It never retargets, so a Knight's cover holds. The band check repeats _use_skill's so a
				# Knight in melee skips the rule's scan of every actor each tick.
				aim_from = _actor_by_id(state, actor.order_target_id)
				if aim_from == null or aim_from.faction == actor.faction or aim_from.life != BattleActor.LIFE_ALIVE:
					continue
				var gap: float = actor.position.distance_to(aim_from.position)
				if gap < skill.min_range_units or gap > skill.range_units:
					continue
			if skill.ai_rule == "melee_near_back_row":
				# Rime Wall (ig-vl1.5): across the ally-enemy line, ai_offset from the ally. A placement that
				# can't push someone clear is skipped; the rule looks again next tick.
				var threat: Array = _back_row_threat(state, actor, skill)
				if not threat.is_empty() and _use_skill(state, actor, skill, threat[1], _threat_point(threat[0], threat[1], skill), rng, (threat[1] as BattleActor).position - (threat[0] as BattleActor).position):
					return true
				continue
			var aim: BattleActor = _rule_aim(state, actor, skill, aim_from, band)
			if aim == null:
				continue
			if actor.faction == "enemy" and not _telegraph_kind(skill).is_empty():
				# Its own delay when it has one (Crushing Blow), else the shared enemy telegraph.
				var seconds: float = float(_effect_of(skill, "damage").get("delay_seconds", BALANCE.battle_enemy_telegraph_seconds))
				_start_telegraph(state, actor, skill, aim.position, seconds)
				_spend_ability(state, actor, skill)
				return true
			var point: Vector2 = actor.position if skill.self_centered and band != "revive" else aim.position
			if _use_skill(state, actor, skill, aim, point, rng):
				return true
	return false


## ig-gy0.5: how many ticks a chain step waits before it is skipped (skill_chain_step_timeout_seconds).
static func _chain_timeout_ticks() -> int:
	return ceili(BALANCE.skill_chain_step_timeout_seconds / BALANCE.battle_tick_seconds - TICK_EPSILON)


## skill was just used (SYSTEMS.md § Chains). An actor with a chain on it starts that chain at its first
## step, aimed at the hero's current opponent. One already running is only replaced by a trigger fired by
## hand: a step, or a cut-in from another band, never starts a chain.
static func _start_chain(state: BattleState, actor: BattleActor, skill: AbilityDefinition, by_hand: bool) -> void:
	if actor.chains.is_empty() or (actor.effect_state.has("chain_trigger") and not by_hand):
		return
	for chain: Dictionary in actor.chains:
		if chain["trigger"] == str(skill.skill_id):
			var order: BattleActor = _actor_by_id(state, actor.order_target_id)
			actor.effect_state["chain_trigger"] = chain["trigger"]
			actor.effect_state["chain_step"] = 0
			actor.effect_state["chain_deadline_tick"] = state.tick + _chain_timeout_ticks()
			actor.effect_state["chain_target"] = order.id if order != null and order.faction != actor.faction else ""
			return


static func _chain_steps(actor: BattleActor, trigger: String) -> Array:
	for chain: Dictionary in actor.chains:
		if chain["trigger"] == trigger:
			return chain["then"]
	return []


## The bar mode of skill_id on the actor ("" when it is not on its bar).
static func _skill_mode(actor: BattleActor, skill_id: String) -> String:
	for entry: Dictionary in actor.skills:
		if entry["id"] == skill_id:
			return str(entry["mode"])
	return ""


## The chain band (DECISIONS.md 2026-09-23 item 7: counter, revive, heal, chain, buff, attack). CHAIN_FIRED
## when the running chain's step cast, CHAIN_WAITING when it holds a step that could not (the buff and attack
## bands stay shut, the swing still lands), CHAIN_NONE when it has ended. The chain ends when its target is
## dead or gone, when the hero is given another target, or after its last step. A step past its deadline, set
## Off, or not on the bar is skipped, and the next one gets a fresh deadline. A weaponskill step waits for the swing.
static func _chain_step(state: BattleState, actor: BattleActor, rng: RandomNumberGenerator) -> int:
	var effects: Dictionary = actor.effect_state
	if str(effects["chain_target"]).is_empty():
		# Started with no opponent: it takes the first the hero is given.
		var order: BattleActor = _actor_by_id(state, actor.order_target_id)
		if order != null and order.faction != actor.faction:
			effects["chain_target"] = order.id
	var foe_id: String = effects["chain_target"]
	var foe: BattleActor = _actor_by_id(state, foe_id)
	# An empty order (a kite hop, a regroup, a hold) does not end it; a different target does.
	if not foe_id.is_empty() and (foe == null or foe.life != BattleActor.LIFE_ALIVE or (not actor.order_target_id.is_empty() and actor.order_target_id != foe_id)):
		actor.end_chain()
		return CHAIN_NONE
	var steps: Array = _chain_steps(actor, effects["chain_trigger"])
	var step: int = int(effects["chain_step"])
	var deadline: int = int(effects["chain_deadline_tick"])
	while step < steps.size():
		var skill: AbilityDefinition = ABILITIES.get(steps[step]) as AbilityDefinition
		var mode: String = _skill_mode(actor, steps[step])
		if state.tick <= deadline and skill != null and (mode == "auto" or mode == "manual"):
			if skill.kind == "weaponskill":
				return CHAIN_WAITING
			var aim: Array = _chain_aim(state, actor, skill, foe)
			if not aim.is_empty() and _use_skill(state, actor, skill, aim[0], aim[1], rng, aim[2]):
				_chain_advance(state, actor)
				return CHAIN_FIRED
			return CHAIN_WAITING
		step += 1
		deadline = state.tick + _chain_timeout_ticks()
		effects["chain_step"] = step
		effects["chain_deadline_tick"] = deadline
	actor.end_chain()
	return CHAIN_NONE


## The running chain's step is done: the next one gets a fresh deadline, or the chain ends after its last.
static func _chain_advance(state: BattleState, actor: BattleActor) -> void:
	var step: int = int(actor.effect_state["chain_step"]) + 1
	if step >= _chain_steps(actor, actor.effect_state["chain_trigger"]).size():
		actor.end_chain()
		return
	actor.effect_state["chain_step"] = step
	actor.effect_state["chain_deadline_tick"] = state.tick + _chain_timeout_ticks()


## The weaponskill step this swing casts, when the swing is at the chain's target; else null.
static func _chain_weaponskill(actor: BattleActor, target: BattleActor) -> AbilityDefinition:
	if target.id != str(actor.effect_state["chain_target"]) or _has_status(actor, "silence"):
		return null
	var steps: Array = _chain_steps(actor, actor.effect_state["chain_trigger"])
	var skill: AbilityDefinition = ABILITIES.get(steps[int(actor.effect_state["chain_step"])]) as AbilityDefinition
	return skill if skill != null and skill.kind == "weaponskill" else null


## Where a chain step aims, by the band its AI rule puts the skill in and not by its effect (ig-gy0.5):
## [target, point, the line a wall goes across], or [] when there is nothing to aim at and the step waits.
## foe is the chain's opponent, or null. The rule's "AI uses it when" condition is ignored.
static func _chain_aim(state: BattleState, actor: BattleActor, skill: AbilityDefinition, foe: BattleActor) -> Array:
	var band: String = skill.band()
	if band == "revive" or skill.ai_revive_first:
		# The nearest downed ally, as the picker aims a revive. Rally also buffs, so with nobody down it casts as a buff.
		var downed: BattleActor = _nearest_actor(state, actor, actor.faction, BattleActor.LIFE_DOWNED)
		if downed != null:
			return [downed, downed.position, Vector2.ZERO]
		if band == "revive":
			return []
	if band == "heal" or str(_effect_of(skill, "zone").get("side", "")) == "allies":
		if skill.self_centered:
			return [actor, actor.position, Vector2.ZERO]
		# The caster is always in reach of itself, so this is never null.
		var ally: BattleActor = _lowest_health_ally(state, actor.position, skill.range_units)
		return [ally, ally.position, Vector2.ZERO]
	if not _effect_of(skill, "wall").is_empty():
		if foe == null:
			return []
		var hand: Array = _hand_aim(actor, skill, foe, foe.position)
		return [foe, hand[0], hand[1]]
	if skill.self_centered:
		return [foe if foe != null else actor, actor.position, Vector2.ZERO]
	return [foe, foe.position, Vector2.ZERO] if foe != null else []


## The weaponskill for this swing: a conditional one whose rule holds (a combo step when its combo
## is live), in bar order, else the first "default" one, else null (a plain basic hit).
static func _pick_weaponskill(state: BattleState, actor: BattleActor, target: BattleActor) -> AbilityDefinition:
	if _has_status(actor, "silence"):
		return null
	var fallback: AbilityDefinition = null
	for entry: Dictionary in actor.skills:
		var skill: AbilityDefinition = ABILITIES[entry["id"]]
		if skill.kind != "weaponskill" or str(entry["mode"]) != "auto":
			continue
		match skill.ai_rule:
			"default":
				if fallback == null:
					fallback = skill
			"combo":
				if _combo_ready(state, actor, skill):
					return skill
			_:
				if _rule_aim(state, actor, skill, target, "attack") != null:
					return skill
	return fallback


## The step before skill landed within skill_combo_window_seconds.
## An ability follows the last ability cast (ig-zht: Ground Slam after Charge), read from the saved
## last_skill_id and last_skill_tick, so a swing between them does not break it.
static func _combo_ready(state: BattleState, actor: BattleActor, skill: AbilityDefinition) -> bool:
	if skill.combo_after == &"":
		return false
	if skill.is_ability():
		return str(actor.effect_state.get("last_skill_id", "")) == str(skill.combo_after) and (state.tick - int(actor.effect_state.get("last_skill_tick", 0))) * BALANCE.battle_tick_seconds <= BALANCE.skill_combo_window_seconds + TICK_EPSILON
	return actor.combo_skill == str(skill.combo_after) and (state.tick - actor.combo_tick) * BALANCE.battle_tick_seconds <= BALANCE.skill_combo_window_seconds + TICK_EPSILON


## Whom the skill's AI rule (AbilityDefinition.AI_RULES) wants to cast at, or null when it does not
## want to. target is the actor's in-range opponent (null in the support pass). Enemies fire whenever
## ready.
static func _rule_aim(state: BattleState, actor: BattleActor, skill: AbilityDefinition, target: BattleActor, band: String) -> BattleActor:
	if band == "revive":
		return _nearest_actor(state, actor, actor.faction, BattleActor.LIFE_DOWNED)
	if actor.faction == "enemy":
		return target
	if skill.ai_no_ready_heal and _class_heal_ready(state, actor):
		return null
	match skill.ai_rule:
		"always", "fight_on":
			return target
		"combo":
			# An ability combo (Ground Slam): cast around itself, so no target needed.
			if _combo_ready(state, actor, skill):
				return target if target != null else actor
		"enemies_near_target":
			if target != null and (_opponents_in_radius(state, actor.faction, target.position, skill.ai_radius) >= skill.ai_count or (skill.ai_or_elite and bool(target.effect_state.get("elite", false)))):
				return target
		"enemies_near_self":
			if target != null and _opponents_in_radius(state, actor.faction, actor.position, skill.ai_radius) >= skill.ai_count:
				return target
		"target_below":
			if target != null and target.hp / target.max_hp < skill.ai_fraction:
				return target
		"target_lacks_status":
			if target != null and not _has_status(target, skill.ai_status):
				return target
		"allies_near":
			if target != null and _living_in_radius(state, actor.faction, actor.position, skill.ai_radius).size() >= skill.ai_count:
				return target
		"allies_near_ally":
			return _pressed_group_aim(state, actor, skill)
		"enemy_on_weaker_ally":
			# ig-uu7.2: the covered threat first: this hero's own target, in range and on a back-row ally.
			var covered: BattleActor = _actor_by_id(state, actor.order_target_id)
			if covered != null and covered.faction != actor.faction and covered.life == BattleActor.LIFE_ALIVE and covered.position.distance_to(actor.position) <= skill.range_units:
				var covered_victim: BattleActor = _actor_by_id(state, covered.order_target_id)
				if covered_victim != null and covered_victim.faction == actor.faction and covered_victim.life == BattleActor.LIFE_ALIVE and covered_victim.archetype in BACK_ROW:
					return covered
			for enemy: BattleActor in state.actors:
				if enemy.faction == actor.faction or enemy.life != BattleActor.LIFE_ALIVE or enemy.position.distance_to(actor.position) > skill.range_units:
					continue
				var victim: BattleActor = _actor_by_id(state, enemy.order_target_id)
				if victim != null and victim != actor and victim.faction == actor.faction and victim.life == BattleActor.LIFE_ALIVE and (victim.archetype in BACK_ROW or victim.hp / victim.max_hp < actor.hp / actor.max_hp):
					return enemy
		"ally_below_heal_below":
			var hurt: BattleActor = _lowest_ally(state, actor, skill)
			if hurt != null and hurt.hp / hurt.max_hp < float(state.policies.get("heal_below", 0.35)):
				return hurt
		"ally_below":
			var low: BattleActor = _lowest_ally(state, actor, skill)
			if low != null and low.hp / low.max_hp < skill.ai_fraction:
				return low
		"allies_below":
			var below: int = 0
			for ally: BattleActor in _living_in_radius(state, actor.faction, actor.position, skill.ai_radius):
				if ally.hp / ally.max_hp < skill.ai_fraction:
					below += 1
			if below >= skill.ai_count:
				return actor
		"self_below":
			if actor.hp / actor.max_hp < skill.ai_fraction:
				return actor
	return null


## allies_near_ally (Hearthward, ig-vl1.4): the lowest-HP living ally within range_units with ai_count
## living allies (itself included) within ai_radius, one of them below ai_fraction, inside an enemy
## telegraph or targeted by a living enemy (ig-vl1.8); ties go to actor order. With no pressed ally in reach it stops after one pass, so a ready
## Hearthward costs a scan per tick, not a scan per ally.
static func _pressed_group_aim(state: BattleState, actor: BattleActor, skill: AbilityDefinition) -> BattleActor:
	var telegraphs: Array[BattleActor] = []
	var targeted: Dictionary[String, bool] = {}
	for enemy: BattleActor in state.actors:
		if enemy.faction != actor.faction and enemy.life == BattleActor.LIFE_ALIVE:
			if not str(enemy.effect_state.get("telegraph_kind", "")).is_empty():
				telegraphs.append(enemy)
			if not enemy.order_target_id.is_empty():
				targeted[enemy.order_target_id] = true
	var pressed: Array[BattleActor] = []
	for ally: BattleActor in state.actors:
		if ally.faction == actor.faction and ally.life == BattleActor.LIFE_ALIVE and ally.position.distance_to(actor.position) <= skill.range_units + skill.ai_radius and (ally.hp / ally.max_hp < skill.ai_fraction or targeted.has(ally.id) or _inside_telegraph(telegraphs, ally.position)):
			pressed.append(ally)
	if pressed.is_empty():
		return null
	var lowest: BattleActor = null
	var lowest_fraction: float = INF
	for candidate: BattleActor in state.actors:
		if candidate.faction != actor.faction or candidate.life != BattleActor.LIFE_ALIVE or not (candidate.position.distance_to(actor.position) <= skill.range_units) or not (candidate.hp / candidate.max_hp < lowest_fraction):
			continue
		if not _any_within(pressed, candidate.position, skill.ai_radius):
			continue
		if _living_in_radius(state, actor.faction, candidate.position, skill.ai_radius).size() >= skill.ai_count:
			lowest = candidate
			lowest_fraction = candidate.hp / candidate.max_hp
	return lowest


## melee_near_back_row (Rime Wall, ig-vl1.5): [back-row ally, enemy] for the nearest living enemy melee
## actor ai_min_radius to ai_radius from a living back-row ally whose cast point is in range; ties go to
## the lower spawn index, the enemy's and then the ally's (actor order, strict <). [] for none. Worst
## case: the back row in reach x the enemies, 50 x 30 on frontier_march, per ready caster per tick.
static func _back_row_threat(state: BattleState, actor: BattleActor, skill: AbilityDefinition) -> Array:
	# Only a back-row ally within range + ai_offset of the caster can have its point in range.
	var reach: float = skill.range_units + skill.ai_offset
	var guarded: Array[BattleActor] = []
	for ally: BattleActor in state.actors:
		if ally.faction == actor.faction and ally.life == BattleActor.LIFE_ALIVE and ally.archetype in BACK_ROW and ally.position.distance_to(actor.position) <= reach:
			guarded.append(ally)
	if guarded.is_empty():
		return []
	var best: Array = []
	var best_gap: float = INF
	for enemy: BattleActor in state.actors:
		if enemy.faction == actor.faction or enemy.life != BattleActor.LIFE_ALIVE or enemy.attack_range > BALANCE.battle_melee_range:
			continue
		for ally: BattleActor in guarded:
			var gap: float = ally.position.distance_to(enemy.position)
			if gap < skill.ai_min_radius or gap > skill.ai_radius or not (gap < best_gap):
				continue
			if actor.position.distance_to(_threat_point(ally, enemy, skill)) > skill.range_units:
				continue
			best = [ally, enemy]
			best_gap = gap
	return best


## Rime Wall's AI point: ai_offset from the ally toward the enemy, on the line between them.
static func _threat_point(ally: BattleActor, enemy: BattleActor, skill: AbilityDefinition) -> Vector2:
	return ally.position + (enemy.position - ally.position).normalized() * skill.ai_offset


static func _inside_telegraph(telegraphs: Array[BattleActor], position: Vector2) -> bool:
	for enemy: BattleActor in telegraphs:
		if _in_telegraph(enemy, position):
			return true
	return false


static func _any_within(actors: Array[BattleActor], center: Vector2, radius: float) -> bool:
	for actor: BattleActor in actors:
		if actor.position.distance_to(center) <= radius:
			return true
	return false


## One of the actor's own class abilities that heals is off cooldown, on Auto and has an ally its own rule
## would heal (ig-gy0.7): a ready heal with nobody to aim at does not hold Field Dressing back. The heal has
## no ai_no_ready_heal of its own, so _rule_aim does not come back here.
static func _class_heal_ready(state: BattleState, actor: BattleActor) -> bool:
	for entry: Dictionary in actor.skills:
		var skill: AbilityDefinition = ABILITIES[entry["id"]]
		if skill.is_ability() and skill.archetype == actor.archetype and str(entry["mode"]) == "auto" and float(actor.skill_cooldowns.get(entry["id"], 0.0)) <= 0.0 and not _effect_of(skill, "heal").is_empty() and _rule_aim(state, actor, skill, null, "heal") != null:
			return true
	return false


## The lowest-HP living ally (the caster included) within the skill's range, of its ai_archetype and
## without its ai_status when those are set.
static func _lowest_ally(state: BattleState, actor: BattleActor, skill: AbilityDefinition) -> BattleActor:
	var lowest: BattleActor = null
	var lowest_fraction: float = INF
	# _living_in_radius's filter, inline: no array per call (ig-7sn.7).
	for ally: BattleActor in state.actors:
		if ally.faction != actor.faction or ally.life != BattleActor.LIFE_ALIVE or not (ally.position.distance_to(actor.position) <= skill.range_units):
			continue
		if (not skill.ai_archetype.is_empty() and ally.archetype != skill.ai_archetype) or (not skill.ai_status.is_empty() and _has_status(ally, skill.ai_status)):
			continue
		if ally.hp / ally.max_hp < lowest_fraction:
			lowest = ally
			lowest_fraction = ally.hp / ally.max_hp
	return lowest


## The archetype's level-1 kit, passive first then its signature ability. A snapshot without skills
## or a level gets this (DECISIONS.md 2026-09-23 item 4): exactly the battle from before the v1 kits.
## Only the first level-1 ability is the signature: the Knight's Charge and Ground Slam also open at
## level 1 (ig-zht) and stay out.
static func default_kit(archetype: String) -> Array[AbilityDefinition]:
	var kit: Array[AbilityDefinition] = []
	for kind: String in ["passive", "ability"]:
		for skill: AbilityDefinition in ABILITIES.values():
			if skill.archetype == archetype and skill.kind == kind and skill.unlock_level <= 1 and not skill.book_only:
				kit.append(skill)
				break
	return kit


## An enemy's kit (SYSTEMS.md § Skills, Enemies): its class's level-1 skills (the passive, the
## signature and the starter weaponskill), then its enemy-only skills. No chains, no general pool.
static func enemy_kit(archetype: String) -> Array[AbilityDefinition]:
	# Of the level-1 abilities only the signature: enemies never Charge or Ground Slam (ig-zht).
	var signature: AbilityDefinition = signature_for(archetype)
	var kit: Array[AbilityDefinition] = known_kit(archetype, 1).filter(func(skill: AbilityDefinition) -> bool: return not skill.is_ability() or skill == signature)
	for skill: AbilityDefinition in ABILITIES.values():
		if skill.archetype == "enemy_" + archetype:
			kit.append(skill)
	return kit


## The class skills a hero of level knows without a book, in kit order (SYSTEMS.md § The v1 kits).
static func known_kit(archetype: String, level: int) -> Array[AbilityDefinition]:
	var kit: Array[AbilityDefinition] = []
	for skill: AbilityDefinition in ABILITIES.values():
		if skill.archetype == archetype and skill.unlock_level <= level and not skill.book_only:
			kit.append(skill)
	return kit


## The archetype's signature (its first default ability), or null. The battle view names it.
static func signature_for(archetype: String) -> AbilityDefinition:
	for skill: AbilityDefinition in default_kit(archetype):
		if skill.kind == "ability":
			return skill
	return null


static func _in_range_target(state: BattleState, actor: BattleActor) -> BattleActor:
	var target: BattleActor = _actor_by_id(state, actor.order_target_id)
	if target == null or target.life != BattleActor.LIFE_ALIVE or target.faction == actor.faction:
		return null
	if actor.position.distance_to(target.position) > actor.attack_range:
		return null
	return target


## Knockback (SYSTEMS.md § Knockback): moves a living, non-elite target distance along direction (the
## source's facing when the two coincide), clamped to the battlefield; a carrier takes its body along.
## Instant, no RNG, no interrupt. Shared with ig-zht's Charge.
static func _push(state: BattleState, target: BattleActor, direction: Vector2, facing: Vector2, distance: float) -> void:
	if target.life != BattleActor.LIFE_ALIVE or bool(target.effect_state.get("elite", false)):
		return
	var away: Vector2 = _push_direction(direction, facing)
	target.position = _wall_cut(_wall_paths(state), target.position, _clamp_to_bounds(state, target.position + away * distance))
	target.effect_state["hit_from"] = [away.x, away.y]
	target.effect_state["last_push_tick"] = state.tick
	if not target.carrying_id.is_empty():
		var carried: BattleActor = _actor_by_id(state, target.carrying_id)
		if carried != null:
			carried.position = target.position


## An area's hits, after all of them landed: each target's view cue points away from the area (a
## killed one keeps it for its fling), then each living one is pushed distance, if the skill pushes.
static func _push_all(state: BattleState, pushes: Array, facing: Vector2, distance: float) -> void:
	for pushed: Array in pushes:
		var target: BattleActor = pushed[0]
		var away: Vector2 = _push_direction(pushed[1] as Vector2, facing)
		target.effect_state["hit_from"] = [away.x, away.y]
		if distance > 0.0:
			# The raw direction: normalizing twice can move the last bit.
			_push(state, target, pushed[1] as Vector2, facing, distance)


## direction, else facing when they coincide, else +x for a saved zero facing.
static func _push_direction(direction: Vector2, facing: Vector2) -> Vector2:
	if direction != Vector2.ZERO:
		return direction.normalized()
	return facing.normalized() if facing != Vector2.ZERO else Vector2.RIGHT


## Charge (ig-zht, SYSTEMS.md § The v1 kits): the landing point, distance short of the target on the
## straight line from the caster, clamped. First, every other living opponent whose center is within
## radius_units / 2 of that line is pushed lane_push sideways to its own side (one on it: the caster's
## right as the view draws it, sim y being its z), all read at pre-push positions; _push keeps elites
## put. Instant: nothing can stun or push the Knight mid-dash.
static func _charge(state: BattleState, actor: BattleActor, target: BattleActor, skill: AbilityDefinition, effect: Dictionary) -> Vector2:
	var lane: Vector2 = target.position - actor.position
	var direction: Vector2 = lane.normalized()
	var right := Vector2(-direction.y, direction.x)
	var pushes: Array = []
	for candidate: BattleActor in state.actors:
		if candidate == target or candidate.faction == actor.faction or candidate.life != BattleActor.LIFE_ALIVE:
			continue
		var offset: Vector2 = candidate.position - actor.position
		var along: float = offset.dot(direction)
		var side: float = offset.dot(right)
		if along >= 0.0 and along <= lane.length() and absf(side) <= skill.radius_units * 0.5:
			pushes.append([candidate, right if side >= 0.0 else -right])
	_push_all(state, pushes, actor.facing, float(effect.get("lane_push", 0.0)))
	return _clamp_to_bounds(state, target.position - direction * float(effect["distance"]))


static func _face(actor: BattleActor, at: Vector2) -> void:
	var aim: Vector2 = at - actor.position
	if aim != Vector2.ZERO:
		actor.facing = aim.normalized()


## Marks skill's line or circle at point; it lands after seconds (_resolve_telegraph) unless the
## caster is stunned or downed first.
static func _start_telegraph(_state: BattleState, actor: BattleActor, skill: AbilityDefinition, point: Vector2, seconds: float) -> void:
	var kind: String = _telegraph_kind(skill)
	actor.effect_state["telegraph_kind"] = kind
	actor.effect_state["telegraph_skill"] = str(skill.skill_id)
	actor.effect_state["telegraph_origin"] = [actor.position.x, actor.position.y]
	var telegraph_point: Vector2 = point
	if kind == "line":
		var aim: Vector2 = (point - actor.position).normalized()
		telegraph_point = actor.position + aim * skill.range_units
	actor.effect_state["telegraph_point"] = [telegraph_point.x, telegraph_point.y]
	actor.effect_state["telegraph_radius"] = skill.radius_units
	actor.effect_state["telegraph_remaining"] = seconds
	actor.effect_state["telegraph_total"] = seconds
	actor.effect_state["telegraph_claimed_by"] = ""


static func _resolve_telegraph(state: BattleState, actor: BattleActor, rng: RandomNumberGenerator) -> void:
	var kind: String = str(actor.effect_state.get("telegraph_kind", ""))
	if kind.is_empty():
		return
	var skill: AbilityDefinition = ABILITIES.get(str(actor.effect_state.get("telegraph_skill", ""))) as AbilityDefinition
	if skill == null:
		# A checkpoint from before ig-gy0.2: the actor's first ability of that shape.
		for ability: AbilityDefinition in _abilities(actor):
			if _telegraph_kind(ability) == kind:
				skill = ability
				break
	# Only an ability starts a telegraph, so its hit is x the battle's pace (ig-1jw).
	var multiplier: float = float(_effect_of(skill, "damage").get("multiplier", 0.0)) * state.pace if skill != null else 0.0
	var push: float = float(_effect_of(skill, "damage").get("push", 0.0)) if skill != null else 0.0
	var point: Vector2 = _array_vector(actor.effect_state.get("telegraph_point"))
	var line: Vector2 = point - _array_vector(actor.effect_state.get("telegraph_origin"))
	var pushes: Array = []
	for candidate: BattleActor in state.actors:
		if candidate.faction != actor.faction and candidate.life == BattleActor.LIFE_ALIVE and not _has_status(candidate, "dodge") and _in_telegraph(actor, candidate.position):
			_damage(state, actor, candidate, multiplier, rng)
			pushes.append([candidate, line if kind == "line" else candidate.position - point])
	_push_all(state, pushes, actor.facing, push)
	_cancel_telegraph(actor)


## position is inside actor's marked line or circle.
static func _in_telegraph(actor: BattleActor, position: Vector2) -> bool:
	var point: Vector2 = _array_vector(actor.effect_state.get("telegraph_point"))
	var radius: float = float(actor.effect_state.get("telegraph_radius", 0.0))
	if str(actor.effect_state.get("telegraph_kind", "")) == "line":
		return _distance_to_segment(position, _array_vector(actor.effect_state.get("telegraph_origin")), point) <= radius * 0.5
	return position.distance_to(point) <= radius


## The AI's answer to enemy telegraphs (SYSTEMS.md § Skills, Counters and The AI's answer;
## DECISIONS.md 2026-09-23, Skills, item 8). Runs before the picker each tick, so a counter outranks
## every band. Once a telegraph has run skill_reaction_delay_seconds, one hero claims it: the first
## in spawn order with a stun or interrupt that reaches the caster; else the first whose shield
## covers someone inside it; else every hero inside it with a dodge (the first holds the claim).
## Only Auto counters, the shortest cooldown first. The claim is saved on the caster
## (telegraph_claimed_by), so a reload never answers twice. Everyone else inside walks out
## (_danger_safe_point). Enemies never counter.
static func _answer_telegraphs(state: BattleState, rng: RandomNumberGenerator) -> void:
	for caster: BattleActor in state.actors:
		if caster.faction != "enemy" or caster.life != BattleActor.LIFE_ALIVE or str(caster.effect_state.get("telegraph_kind", "")).is_empty():
			continue
		var run: float = float(caster.effect_state.get("telegraph_total", 0.0)) - float(caster.effect_state.get("telegraph_remaining", 0.0))
		if not str(caster.effect_state.get("telegraph_claimed_by", "")).is_empty() or run < BALANCE.skill_reaction_delay_seconds - TICK_EPSILON:
			continue
		var claimer: BattleActor = _answer(state, caster, rng)
		if claimer != null:
			caster.effect_state["telegraph_claimed_by"] = claimer.id


## Fires the answer to caster's telegraph and returns the hero that claimed it, or null.
static func _answer(state: BattleState, caster: BattleActor, rng: RandomNumberGenerator) -> BattleActor:
	var inside: Array[BattleActor] = []
	for ally: BattleActor in state.actors:
		if ally.faction == "ally" and ally.life == BattleActor.LIFE_ALIVE and _in_telegraph(caster, ally.position):
			inside.append(ally)
	if inside.is_empty():
		return null
	var first_dodge: BattleActor = null
	for tags: Array in [["stun", "interrupt"], ["shield"], ["dodge"]]:
		for hero: BattleActor in state.actors:
			# ig-gy0.6: the piloted hero claims nothing; the next hero with a counter does.
			if hero.faction != "ally" or hero.id == state.piloted_id:
				continue
			for skill: AbilityDefinition in _counters(hero, tags):
				var aim: BattleActor = caster
				if tags[0] == "shield":
					aim = _shield_aim(caster, hero, skill, inside)
				elif tags[0] == "dodge" and not hero in inside:
					aim = null
				if aim != null and _use_skill(state, hero, skill, aim, hero.position if skill.self_centered else aim.position, rng):
					hero.effect_state["last_counter_tick"] = state.tick
					if tags[0] != "dodge":
						return hero
					# Every hero inside dodges; the first holds the claim.
					first_dodge = hero if first_dodge == null else first_dodge
					break
	return first_dodge


## hero's ready Auto counters with one of tags, shortest cooldown first, then bar order. Manual and
## Off skills are never counters.
static func _counters(hero: BattleActor, tags: Array) -> Array[AbilityDefinition]:
	var found: Array[AbilityDefinition] = []
	var order: Dictionary = {}
	for entry: Dictionary in hero.skills:
		var skill: AbilityDefinition = ABILITIES[entry["id"]]
		if skill.counter_tag in tags and str(entry["mode"]) == "auto" and float(hero.skill_cooldowns.get(entry["id"], 0.0)) <= 0.0:
			order[skill] = found.size()
			found.append(skill)
	found.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
		var a_cooldown: float = _skill_cooldown(hero, a)
		var b_cooldown: float = _skill_cooldown(hero, b)
		return a_cooldown < b_cooldown or (a_cooldown == b_cooldown and order[a] < order[b]))
	return found


## Whom hero's shield counter is cast at to cover someone inside the telegraph, or null. A shield,
## or a status on its target, goes to the ally inside within its range nearest a circle's centre
## (the first in a line); a self status needs hero inside; an aura needs someone inside within it.
static func _shield_aim(caster: BattleActor, hero: BattleActor, skill: AbilityDefinition, inside: Array[BattleActor]) -> BattleActor:
	var status: Dictionary = _effect_of(skill, "status")
	var reach: String = "target" if not _effect_of(skill, "shield").is_empty() else str(status.get("target", ""))
	if reach == "self":
		return hero if hero in inside else null
	if reach == "allies_near_caster":
		var radius: float = float(status.get("radius", skill.radius_units))
		return hero if inside.any(func(ally: BattleActor) -> bool: return ally.position.distance_to(hero.position) <= radius) else null
	var center: Vector2 = _array_vector(caster.effect_state.get("telegraph_point"))
	var line: bool = str(caster.effect_state.get("telegraph_kind", "")) == "line"
	var best: BattleActor = null
	for ally: BattleActor in inside:
		if hero.position.distance_to(ally.position) <= skill.range_units and (best == null or (not line and ally.position.distance_to(center) < best.position.distance_to(center))):
			best = ally
	return best


static func _cancel_pending_action(actor: BattleActor) -> void:
	actor.effect_state["attack_windup_remaining"] = 0.0
	actor.effect_state["attack_target_id"] = ""
	_cancel_telegraph(actor)


static func _cancel_telegraph(actor: BattleActor) -> void:
	actor.effect_state["telegraph_kind"] = ""
	actor.effect_state["telegraph_remaining"] = 0.0
	actor.effect_state["telegraph_total"] = 0.0


## telegraphs: the living enemies with a telegraph running, in state.actors order.
static func _danger_safe_point(state: BattleState, actor: BattleActor, telegraphs: Array[BattleActor]) -> Variant:
	for enemy: BattleActor in telegraphs:
		var kind: String = str(enemy.effect_state.get("telegraph_kind", ""))
		var origin: Vector2 = _array_vector(enemy.effect_state.get("telegraph_origin"))
		var point: Vector2 = _array_vector(enemy.effect_state.get("telegraph_point"))
		var radius: float = float(enemy.effect_state.get("telegraph_radius", 0.0))
		if kind == "circle" and actor.position.distance_to(point) <= radius:
			var outward: Vector2 = actor.position - point
			if outward == Vector2.ZERO:
				outward = Vector2.RIGHT if actor.spawn_index % 2 == 0 else Vector2.LEFT
			return _clamp_to_bounds(state, point + outward.normalized() * (radius + BALANCE.battle_separation_radius))
		if kind == "line" and _distance_to_segment(actor.position, origin, point) <= radius * 0.5:
			var line_direction: Vector2 = (point - origin).normalized()
			var perpendicular := Vector2(-line_direction.y, line_direction.x)
			if actor.spawn_index % 2 != 0:
				perpendicular = -perpendicular
			return _clamp_to_bounds(state, actor.position + perpendicular * (radius + BALANCE.battle_separation_radius))
	return null


static func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	if segment.length_squared() <= TICK_EPSILON:
		return point.distance_to(start)
	var projection: float = clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * projection)


static func _manual_abilities(state: BattleState, actors: Array[BattleActor], target: BattleActor, point: Vector2) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.state = state.rng_state.to_int()
	var used: bool = false
	for actor: BattleActor in actors:
		# The signature: the first ability on the bar not set to Off. A clicked unit is the aim,
		# whatever point came with it (the view sends none); a ground point is only for a cast
		# without a target.
		var skill: AbilityDefinition = _signature(actor)
		if skill == null:
			continue
		var hand: Array = _hand_aim(actor, skill, target, point)
		if _use_skill(state, actor, skill, actor if hand[2] else target, hand[0], rng, hand[1]):
			used = true
			# ig-gy0.5: a trigger fired by hand starts its chain, and replaces one already running.
			_start_chain(state, actor, skill, true)
	state.rng_state = str(rng.state)
	return used


## COMMAND_USE_SKILL (ig-gy0.6): the one hero in actors fires one skill of its bar by hand, in any mode. "" when
## it fired (or set the skill for its next swing), else why it did not, with nothing changed. The aim is the
## clicked unit, else the ground point, else where a chain step would aim (the hero's own enemy as the foe).
## A cast that lands on another enemy then retargets the hero as a right-click does, and a trigger starts its
## chain by hand (a refused cast changes nothing). A weaponskill is set for the swing instead.
static func _use_skill_by_hand(state: BattleState, actors: Array[BattleActor], command: Dictionary, target: BattleActor, point: Vector2) -> String:
	const NOBODY: String = "Nobody is in reach."
	if actors.size() != 1:
		return "use_skill needs exactly one hero."
	var actor: BattleActor = actors[0]
	var skill_id: Variant = command.get("skill_id")
	var skill: AbilityDefinition = ABILITIES.get(skill_id) as AbilityDefinition if skill_id is String else null
	if skill == null or _skill_mode(actor, skill_id as String).is_empty():
		return "That skill is not on this hero's bar."
	if target == null and not str(command.get("target_id", "")).is_empty():
		return "That target is not in the battle."
	if target == null and command.has("point") and not _valid_point(command.get("point")):
		return "That command needs a finite ground point."
	if skill.kind == "weaponskill":
		if _has_status(actor, "silence"):
			return "The hero is silenced."
		var foe: BattleActor = target
		if foe == null and not command.has("point"):
			foe = _actor_by_id(state, actor.order_target_id)
		if foe == null or foe.faction == actor.faction or foe.life != BattleActor.LIFE_ALIVE:
			return "That skill needs a living enemy as its target."
		actor.effect_state["next_swing_skill"] = skill_id
		_retarget_by_hand(state, actor, foe)
		return ""
	var aimed: BattleActor = target
	var aim_point: Vector2 = point
	var across: Vector2 = Vector2.ZERO
	if target != null or command.has("point"):
		var hand: Array = _hand_aim(actor, skill, target, point)
		aim_point = hand[0]
		across = hand[1]
		aimed = actor if hand[2] else target
	else:
		var order_foe: BattleActor = _actor_by_id(state, actor.order_target_id)
		var aim: Array = _chain_aim(state, actor, skill, order_foe if order_foe != null and order_foe.faction != actor.faction and order_foe.life == BattleActor.LIFE_ALIVE else null)
		if aim.is_empty():
			# Nothing to aim at: nobody downed for a revive, no enemy for anything else.
			return NOBODY if skill.band() == "revive" else "That skill needs a living enemy as its target."
		aimed = aim[0]
		aim_point = aim[1]
		across = aim[2]
	var refusal: String = _skill_refusal(state, actor, skill, aimed, aim_point)
	if not refusal.is_empty():
		return refusal
	# A pure revive lands only on a downed ally; Rally, which also buffs, casts on anyone.
	if skill.band() == "revive" and (aimed == null or aimed.life != BattleActor.LIFE_DOWNED):
		return NOBODY
	var rng := RandomNumberGenerator.new()
	rng.state = state.rng_state.to_int()
	var fired: bool = _use_skill(state, actor, skill, aimed, aim_point, rng, across)
	state.rng_state = str(rng.state)
	if not fired:
		return "There is no room for the wall." if not _effect_of(skill, "wall").is_empty() else NOBODY
	if aimed != null and aimed.faction != actor.faction and aimed.life == BattleActor.LIFE_ALIVE:
		_retarget_by_hand(state, actor, aimed)
	_start_chain(state, actor, skill, true)
	return ""


## A right-click on an enemy (COMMAND_ATTACK) for one hero: it drops a body it carries and takes an attack order
## on foe, unless it already has exactly that one.
static func _retarget_by_hand(state: BattleState, actor: BattleActor, foe: BattleActor) -> void:
	if actor.order_kind == COMMAND_ATTACK and actor.order_target_id == foe.id:
		return
	_drop_carried(state, actor)
	_replace_direct_order(actor, COMMAND_ATTACK, foe.id, foe.position)


## Where a cast by hand at target (or at point, with no target) aims: [the point, the line a wall goes
## across, whether the caster is its own target]. A chain step's wall aims the same way (ig-gy0.5).
static func _hand_aim(actor: BattleActor, skill: AbilityDefinition, target: BattleActor, point: Vector2) -> Array:
	var self_cast: bool = skill.self_centered and target == null
	var aim: Vector2 = actor.position if self_cast else (target.position if target != null else point)
	var across := Vector2.ZERO
	var wall: Dictionary = _effect_of(skill, "wall")
	if not wall.is_empty():
		# ig-vl1.5, the hand rule (SYSTEMS.md § Casters, Walls): across the line from the caster to the aim,
		# centered on it. A clicked unit's point first moves half the footprint's width and WALL_MARGIN
		# toward the caster, so the unit ends on the far side. An aim on the caster takes its facing.
		across = aim - actor.position
		if across == Vector2.ZERO:
			across = _push_direction(actor.facing, Vector2.ZERO)
		elif target != null:
			aim -= across.normalized() * (float(wall["thickness"]) * 0.5 + BALANCE.battle_separation_radius * 0.5 + WALL_MARGIN)
	return [aim, across, self_cast]


## masterwork: the tier a manual use picked; null for auto-use (DECISIONS.md 2026-09-23, masterwork draughts).
static func _use_healing(state: BattleState, user: BattleActor, target: BattleActor, masterwork: Variant = null) -> bool:
	if user.life != BattleActor.LIFE_ALIVE or user.item_cooldown > 0.0 or target == null or target.life != BattleActor.LIFE_ALIVE or target.faction != user.faction:
		return false
	if user.position.distance_to(target.position) > BALANCE.battle_revival_range or target.hp >= target.max_hp:
		return false
	var supply_kind: String = _draught_kind(state, "healing", masterwork)
	if supply_kind.is_empty():
		return false
	state.supplies_remaining[supply_kind] = int(state.supplies_remaining.get(supply_kind, 0)) - 1
	target.hp = minf(target.hp + target.max_hp * _draught_fraction(supply_kind), target.max_hp)
	user.item_cooldown = BALANCE.battle_item_cooldown_seconds
	return true


static func _use_revival(state: BattleState, user: BattleActor, target: BattleActor, manual: bool, masterwork: Variant = null) -> bool:
	if user.life != BattleActor.LIFE_ALIVE or user.item_cooldown > 0.0 or target == null or target == user:
		return false
	if target.faction != user.faction or target.life != BattleActor.LIFE_DOWNED or user.position.distance_to(target.position) > BALANCE.battle_revival_range:
		return false
	# Reserve last revival holds back the last draught of either tier.
	if not manual and bool(state.policies.get("reserve_last_revival", false)) and int(state.supplies_remaining.get("revival", 0)) + int(state.supplies_remaining.get("revival" + BattleState.MASTERWORK_SUFFIX, 0)) == 1:
		return false
	var supply_kind: String = _draught_kind(state, "revival", masterwork if manual else null)
	if supply_kind.is_empty():
		return false
	state.supplies_remaining[supply_kind] = int(state.supplies_remaining.get(supply_kind, 0)) - 1
	_revive_actor(state, target, _draught_fraction(supply_kind), user)
	user.item_cooldown = BALANCE.battle_item_cooldown_seconds
	return true


## The stock one draught comes from, or "" when it is empty. A manual use names its tier (masterwork is
## a bool); auto-use (null) spends the regular one first and masterwork only once regular is gone.
static func _draught_kind(state: BattleState, regular_kind: String, masterwork: Variant) -> String:
	var masterwork_kind: String = regular_kind + BattleState.MASTERWORK_SUFFIX
	for supply_kind: String in [regular_kind, masterwork_kind]:
		if masterwork is bool and (masterwork as bool) != (supply_kind == masterwork_kind):
			continue
		if int(state.supplies_remaining.get(supply_kind, 0)) > 0:
			return supply_kind
	return ""


## The share of max HP one draught restores: the balance row battle_<kind>_fraction.
static func _draught_fraction(supply_kind: String) -> float:
	return float(BALANCE.get("battle_%s_fraction" % supply_kind))


static func _supply_count(state: BattleState, supply_kinds: Array[String]) -> int:
	var total: int = 0
	for supply_kind: String in supply_kinds:
		total += int(state.supplies_remaining.get(supply_kind, 0))
	return total


static func _revive_actor(state: BattleState, target: BattleActor, fraction: float, by: BattleActor) -> void:
	_add_moment(state, "revived", target, by)
	# ig-ls3: a revive ends every channel on this body, even one downed again before the next pass.
	for carrier: BattleActor in state.actors:
		if carrier.order_kind == COMMAND_CARRY and carrier.order_target_id == target.id:
			carrier.effect_state.erase("carry_progress")
	_drop_from_carrier(state, target)
	target.life = BattleActor.LIFE_ALIVE
	target.hp = maxf(target.max_hp * fraction, 1.0)
	if state.kind == "rescue" and target.squad_id.is_empty():
		target.order_kind = COMMAND_RETREAT
		target.order_point = _objective_point(state, "exit_position")
		target.effect_state["direct_order"] = false
	else:
		target.order_kind = ""


static func _damage(
	state: BattleState,
	attacker: BattleActor,
	target: BattleActor,
	multiplier: float,
	rng: RandomNumberGenerator,
	basic_hit: bool = false,
) -> void:
	if target.life != BattleActor.LIFE_ALIVE:
		return
	var damage: float = maxf(1.0, _stat(attacker, "atk") * BALANCE.battle_damage_defense_scale / (BALANCE.battle_damage_defense_scale + _stat(target, "defense"))) * multiplier
	var critical: bool = false
	if attacker.faction == "enemy" and bool(state.policies.get("force_enemy_crit", false)):
		critical = true
	elif attacker.faction == "ally" and bool(state.policies.get("suppress_ally_crit", false)):
		critical = false
	elif rng != null:
		critical = rng.randf() < _stat(attacker, "crit_rate")
	if critical:
		damage *= _stat(attacker, "crit_damage")
	if not target.statuses.is_empty():
		damage *= 1.0 - _status_value(target, "damage_reduction")
	var near_ally: Dictionary = _passive_effect(target, "ally_near_damage_reduction")
	if not near_ally.is_empty() and _living_ally_near(state, target, float(near_ally["radius"])):
		damage *= 1.0 - float(near_ally["magnitude"])
	if basic_hit:
		var rear: Dictionary = _passive_effect(attacker, "rear_basic_damage")
		if not rear.is_empty() and _is_behind(attacker, target):
			damage *= 1.0 + float(rear["magnitude"])
	# Read before this hit writes it; 0 is no crit yet (tick 0 never holds one).
	var previous_crit: int = int(target.effect_state.get("last_crit_tick", 0))
	var away: Vector2 = _push_direction(target.position - attacker.position, attacker.facing)
	_take_damage(state, attacker, target, damage, critical)
	# View only: where the hit came from, for recoil and the death fling. The sim never reads it.
	target.effect_state["hit_from"] = [away.x, away.y]
	if basic_hit and critical and (previous_crit <= 0 or state.tick - previous_crit >= BALANCE.battle_crit_push_gate_ticks):
		_push(state, target, away, attacker.facing, BALANCE.battle_crit_push_units)
	# ig-uu7.2: any direct Knight hit, auto or not, pulls an enemy that is on a back-row ally. Bleed and
	# burn ticks go straight to _take_damage and never get here.
	if attacker.faction == "ally" and attacker.archetype == "knight" and target.life == BattleActor.LIFE_ALIVE:
		var victim: BattleActor = _actor_by_id(state, target.order_target_id)
		if victim != null and victim.faction == "ally" and victim.life == BattleActor.LIFE_ALIVE and victim.archetype in BACK_ROW:
			_add_status(target, "knight_cover", "taunt", attacker.id, BALANCE.battle_cover_taunt_seconds, 1.0)


## Damage after every reduction: shields soak it first, then HP. Downs an ally or kills an enemy at 0.
static func _take_damage(state: BattleState, attacker: BattleActor, target: BattleActor, damage: float, critical: bool = false) -> void:
	for status: Dictionary in target.statuses:
		if status["kind"] == "shield" and damage > 0.0:
			var absorbed: float = minf(float(status["magnitude"]), damage)
			status["magnitude"] = float(status["magnitude"]) - absorbed
			damage -= absorbed
	target.hp = maxf(target.hp - damage, 0.0)
	target.effect_state["last_hit_tick"] = state.tick
	if critical:
		target.effect_state["last_crit_tick"] = state.tick
	if target.hp > 0.0:
		return
	_cancel_pending_action(target)
	if target.faction == "ally":
		target.life = BattleActor.LIFE_DOWNED
		if not target.hero_id in state.downed_ever_ids:
			state.downed_ever_ids.append(target.hero_id)
		_add_moment(state, "downed", target, attacker)
		# ig-ls3: a downed carrier's channel is over; after a revive it starts at 0.
		target.effect_state.erase("carry_progress")
		# A chain ends when its hero is downed (ig-gy0.5), so none is checkpointed on a downed body.
		# The weaponskill set for the next swing goes too (ig-gy0.6).
		target.end_chain()
		target.effect_state.erase("next_swing_skill")
		_drop_carried(state, target)
		_drop_from_carrier(state, target)
	else:
		target.life = BattleActor.LIFE_DEAD
		if not attacker.hero_id.is_empty():
			state.kills[attacker.hero_id] = int(state.kills.get(attacker.hero_id, 0)) + 1


## A Ledger moment (DECISIONS.md 2026-09-24 item 7). Bookkeeping only: no RNG, and nothing in the
## fight reads it. `by` is a hero id, or enemy:<archetype> for an enemy.
static func _add_moment(state: BattleState, what: String, hero: BattleActor, by: BattleActor) -> void:
	if hero.hero_id.is_empty():
		return
	if state.moments.size() >= BALANCE.battle_max_moments:
		state.moments_truncated = true
		return
	var by_id: String = by.hero_id if not by.hero_id.is_empty() else "%s:%s" % [by.faction, by.archetype]
	state.moments.append({"tick": state.tick, "what": what, "hero": hero.hero_id, "by": by_id})


static func _update_carry(state: BattleState, carrier: BattleActor) -> void:
	var target: BattleActor = _actor_by_id(state, carrier.order_target_id)
	if target == null or target.life != BattleActor.LIFE_DOWNED or (not target.carried_by_id.is_empty() and target.carried_by_id != carrier.id):
		carrier.order_kind = ""
		carrier.effect_state.erase("carry_progress")
		return
	if carrier.carrying_id == target.id:
		carrier.order_kind = COMMAND_RETREAT
		carrier.order_point = _objective_point(state, "exit_position")
		return
	if carrier.position.distance_to(target.position) > BALANCE.battle_carry_range:
		return
	var progress: float = float(carrier.effect_state.get("carry_progress", 0.0)) + BALANCE.battle_tick_seconds
	carrier.effect_state["carry_progress"] = progress
	if progress + TICK_EPSILON >= BALANCE.battle_carry_seconds:
		carrier.carrying_id = target.id
		target.carried_by_id = carrier.id
		target.position = carrier.position
		carrier.order_kind = COMMAND_RETREAT
		carrier.order_target_id = ""
		carrier.order_point = _objective_point(state, "exit_position")


static func _extract_actor(state: BattleState, actor: BattleActor) -> void:
	actor.life = BattleActor.LIFE_EXTRACTED
	# ig-gy0.5: no chain key outlives a living hero (a retreat and a timeout both end here), nor does
	# a weaponskill set for the next swing (ig-gy0.6).
	actor.end_chain()
	actor.effect_state.erase("next_swing_skill")
	if not actor.hero_id.is_empty() and not actor.hero_id in state.extracted_ids:
		state.extracted_ids.append(actor.hero_id)
	if not actor.carrying_id.is_empty():
		var carried: BattleActor = _actor_by_id(state, actor.carrying_id)
		if carried != null:
			_add_moment(state, "carried", carried, actor)
			carried.life = BattleActor.LIFE_EXTRACTED
			carried.carried_by_id = ""
			if not carried.hero_id.is_empty() and not carried.hero_id in state.extracted_ids:
				state.extracted_ids.append(carried.hero_id)
		actor.carrying_id = ""


static func _drop_carried(state: BattleState, carrier: BattleActor) -> void:
	if carrier.carrying_id.is_empty():
		return
	var carried: BattleActor = _actor_by_id(state, carrier.carrying_id)
	if carried != null:
		carried.carried_by_id = ""
		carried.position = carrier.position
	carrier.carrying_id = ""


static func _drop_from_carrier(state: BattleState, carried: BattleActor) -> void:
	if carried.carried_by_id.is_empty():
		return
	var carrier: BattleActor = _actor_by_id(state, carried.carried_by_id)
	if carrier != null:
		carrier.carrying_id = ""
	carried.carried_by_id = ""


static func _initial_objective_state(zone: ZoneDefinition) -> Dictionary:
	var markers: Array[Dictionary] = []
	markers.append(_marker("exit", "exit", "Extraction", zone.exit_position, BALANCE.battle_exit_radius))
	if zone.battle_kind == "raid":
		for index: int in zone.objective_points.size():
			markers.append(_marker("capture:%d" % index, "capture", "Capture %d" % (index + 1), zone.objective_points[index], 3.0))
	elif zone.battle_kind == "region":
		for index: int in zone.objective_points.size():
			markers.append(_marker("camp:%d" % index, "camp", "Camp %d" % (index + 1), zone.objective_points[index], 5.0))
		markers.append(_marker("cart", "cart", "Escort Cart", Vector2(0, -40), 2.0))
		for index: int in zone.escort_waypoints.size():
			markers.append(_marker("waypoint:%d" % index, "waypoint", "Waypoint %d" % (index + 1), zone.escort_waypoints[index], 2.0))
	return {
		"battle_kind": zone.battle_kind,
		"bounds": zone.battle_bounds,
		"exit_position": [zone.exit_position.x, zone.exit_position.y],
		"cart_position": [0.0, -40.0],
		"escort_index": 0,
		"escort_active": false,
		"boss_spawned": false,
		"simultaneous_hold_seconds": 0.0,
		"markers": markers,
	}


static func _marker(id: String, kind: String, label: String, position: Vector2, radius: float) -> Dictionary:
	return {"id": id, "kind": kind, "label": label, "position": [position.x, position.y], "radius": radius, "progress": 0.0, "active": true, "complete": false}


static func _normalized_policies(policies: Dictionary) -> Dictionary:
	var normalized: Dictionary = {
		"auto_battle": bool(policies.get("auto_battle", true)),
		"default_stance": str(policies.get("default_stance", "stay_together")),
		"auto_heal": bool(policies.get("auto_heal", true)),
		"auto_revive": bool(policies.get("auto_revive", true)),
		"heal_below": clampf(float(policies.get("heal_below", 0.35)), 0.0, 1.0),
		"reserve_last_revival": bool(policies.get("reserve_last_revival", false)),
		"retreat_when_supplies_empty": bool(policies.get("retreat_when_supplies_empty", false)),
	}
	# Only an old order carries ability_auto; a new one never gains it (ig-28b).
	var raw_auto: Variant = policies.get("ability_auto")
	if raw_auto is Dictionary:
		normalized["ability_auto"] = (raw_auto as Dictionary).duplicate(true)
	if normalized["default_stance"] not in STANCES:
		normalized["default_stance"] = "stay_together"
	for internal_key: String in ["force_enemy_crit", "suppress_ally_crit"]:
		if policies.get(internal_key) is bool:
			normalized[internal_key] = policies.get(internal_key)
	return normalized


static func _default_effect_state(elite: bool = false) -> Dictionary:
	return {
		"elite": elite,
		"stun_remaining": 0.0,
		"attack_windup_remaining": 0.0,
		"attack_windup_total": 0.0,
		"attack_target_id": "",
		"last_hit_tick": 0,
		"last_skill_tick": 0,
		"last_crit_tick": 0,
		"telegraph_kind": "",
		"telegraph_origin": [0.0, 0.0],
		"telegraph_point": [0.0, 0.0],
		"telegraph_radius": 0.0,
		"telegraph_remaining": 0.0,
		"telegraph_total": 0.0,
		"home_position": [0.0, 0.0],
		"direct_order": false,
	}


static func _normalized_supplies(supplies: Dictionary) -> Dictionary:
	return BattleState.supplies_from(supplies)


## Why a saved supplies dictionary (a stock, an escrow, a battle's remainder) is malformed, or "".
## The regular kinds are required; a masterwork kind may be missing, as in every save from before it.
## cap < 0 means no cap.
static func supplies_shape_error(supplies: Dictionary, cap: int = -1) -> String:
	for raw_key: Variant in supplies.keys():
		if not raw_key is String or not (raw_key as String) in BattleState.SUPPLY_KINDS:
			return "an unknown supply kind."
	for supply_kind: String in BattleState.SUPPLY_KINDS:
		if not supplies.has(supply_kind):
			if supply_kind.ends_with(BattleState.MASTERWORK_SUFFIX):
				continue
			return "%s is missing." % supply_kind
		if not _nonnegative_integer(supplies.get(supply_kind)) or (cap >= 0 and float(supplies.get(supply_kind)) > cap):
			return "%s must be a non-negative integer%s." % [supply_kind, "" if cap < 0 else " up to %d" % cap]
	return ""


static func _command_actors(state: BattleState, command: Dictionary) -> Variant:
	var raw_ids: Variant = command.get("actor_ids")
	if not raw_ids is Array or (raw_ids as Array).is_empty():
		return "Select at least one living allied actor."
	var actors: Array[BattleActor] = []
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in raw_ids as Array:
		if not raw_id is String or seen.has(raw_id as String):
			return "Actor IDs must be unique Strings."
		var actor: BattleActor = _actor_by_id(state, raw_id as String)
		if actor == null or actor.faction != "ally" or actor.life != BattleActor.LIFE_ALIVE:
			return "Every commanded actor must be a current living ally."
		seen[actor.id] = true
		actors.append(actor)
	return actors


static func _accept_command(state: BattleState) -> Dictionary:
	state.command_sequence += 1
	return _command_result(true, "", state)


static func _command_result(accepted: bool, error: String, state: BattleState) -> Dictionary:
	return {"accepted": accepted, "error": error, "sequence": state.command_sequence if state != null else 0}


static func _assign_group_points(state: BattleState, actors: Array[BattleActor], center: Vector2, kind: String) -> void:
	for index: int in actors.size():
		var destination: Vector2 = _clamp_to_bounds(state, center + _grid_offset(index, actors.size(), BALANCE.battle_formation_spacing))
		_replace_direct_order(actors[index], kind, "", destination)


static func _replace_direct_order(actor: BattleActor, kind: String, target_id: String, point: Vector2) -> void:
	actor.order_kind = kind
	actor.order_target_id = target_id
	actor.order_point = point
	actor.effect_state.erase("carry_progress")
	actor.effect_state["direct_order"] = true


static func _initialize_squads(state: BattleState) -> void:
	for squad: Dictionary in state.squads:
		if not squad.has("stance") or not str(squad.get("stance")) in STANCES:
			squad["stance"] = str(state.policies.get("default_stance", "stay_together"))
		if not squad.has("guard_target_id"):
			squad["guard_target_id"] = ""
		squad["stance_anchor"] = _vector_array(_squad_centroid(state, str(squad.get("id", ""))))


static func _set_squad_stance(state: BattleState, squad_id: String, stance: String) -> void:
	for squad: Dictionary in state.squads:
		if str(squad.get("id", "")) == squad_id:
			squad["stance"] = stance
			if stance == "defend":
				squad["stance_anchor"] = _vector_array(_squad_centroid(state, squad_id))


static func _choose_enemy_intention(state: BattleState, actor: BattleActor) -> void:
	var home: Vector2 = _array_vector(actor.effect_state.get("home_position"), actor.position)
	var target: BattleActor = _actor_by_id(state, actor.order_target_id)
	if target == null or target.life != BattleActor.LIFE_ALIVE or target.position.distance_to(home) > BALANCE.battle_enemy_leash_range:
		target = _nearest_actor_within(state, actor.position, "ally", BALANCE.battle_detection_range, home, BALANCE.battle_enemy_leash_range)
	var taunter: BattleActor = _taunter(state, actor)
	if taunter != null:
		target = taunter
	if target != null:
		actor.order_kind = COMMAND_ATTACK
		actor.order_target_id = target.id
	else:
		actor.order_kind = COMMAND_MOVE
		actor.order_target_id = ""
		actor.order_point = home
	actor.effect_state["direct_order"] = false


## plan: _choose_intentions' cache for this pass, by squad: "leader:<id>" and "objective:<id>".
## rows: the back row's _scan_rows, null for everyone else.
static func _choose_squad_intention(state: BattleState, actor: BattleActor, previous_target_id: String, plan: Dictionary, rows: RowScan) -> void:
	var squad: Dictionary = _squad_for(state, actor.squad_id)
	var stance: String = str(squad.get("stance", state.policies.get("default_stance", "stay_together")))
	var objective_key: String = "objective:" + actor.squad_id
	if not plan.has(objective_key):
		plan[objective_key] = _assigned_objective_point(state, actor)
	# Its fallback is the actor's own position, which is not the squad's to share.
	var objective: Vector2 = actor.position
	if plan[objective_key] is Vector2:
		objective = plan[objective_key] as Vector2
	var target: BattleActor = null
	# The stance's zone, where a Knight looks for a threat to cover (ig-uu7.2).
	var zone_center: Vector2 = actor.position
	var zone_radius: float = BALANCE.battle_detection_range
	match stance:
		"stay_together":
			var leader_key: String = "leader:" + actor.squad_id
			if not plan.has(leader_key):
				plan[leader_key] = _squad_leader(state, actor.squad_id)
			var leader: BattleActor = plan[leader_key] as BattleActor
			if leader != null:
				if actor == leader and _squad_member_beyond(state, actor.squad_id, leader.position, BALANCE.battle_cohesion_wait_distance):
					_set_auto_order(actor, COMMAND_HOLD, "", actor.position)
					return
				if actor != leader and actor.position.distance_to(leader.position) > BALANCE.battle_cohesion_regroup_distance:
					_set_auto_order(actor, COMMAND_MOVE, "", leader.position)
					return
				target = _nearest_enemy_near_point(state, actor.position, leader.position, BALANCE.battle_cohesion_wait_distance)
				zone_center = leader.position
				zone_radius = BALANCE.battle_cohesion_wait_distance
		"defend":
			var anchor: Vector2 = _array_vector(squad.get("stance_anchor"), _squad_centroid(state, actor.squad_id))
			objective = anchor
			if actor.position.distance_to(anchor) > BALANCE.battle_guard_radius:
				_set_auto_order(actor, COMMAND_MOVE, "", anchor)
				return
			target = _nearest_enemy_near_point(state, actor.position, anchor, BALANCE.battle_guard_radius)
			zone_center = anchor
			zone_radius = BALANCE.battle_guard_radius
		"protect":
			var protected: BattleActor = _protected_actor(state, squad)
			if protected != null:
				objective = protected.position
			if protected != null and actor != protected and actor.position.distance_to(protected.position) > BALANCE.battle_guard_radius:
				_set_auto_order(actor, COMMAND_GUARD, protected.id, protected.position)
				return
			var protect_center: Vector2 = protected.position if protected != null else objective
			target = _nearest_enemy_near_point(state, actor.position, protect_center, BALANCE.battle_guard_radius)
			zone_center = protect_center
			zone_radius = BALANCE.battle_guard_radius
		_:
			target = _assigned_objective_enemy(state, actor, objective)
	if actor.archetype == "knight":
		var threat: BattleActor = _cover_threat(state, actor, previous_target_id, zone_center, zone_radius)
		if threat != null:
			target = threat
	if (stance == "advance" or stance == "stay_together") and rows != null and _formation_order(actor, rows, target.position if target != null else objective):
		return
	if target != null:
		_set_auto_order(actor, COMMAND_ATTACK, target.id, target.position)
	else:
		_set_auto_order(actor, COMMAND_MOVE, "", objective)


## ig-uu7.2 Cover (SYSTEMS.md § Hero AI on auto): the enemy in the stance zone that is on a back-row
## ally of this Knight's squad and that no other living Knight targets (auto or piloted). A pick takes
## the victim earliest in the Knight's cover_order (ig-uu7.4; unlisted counts as last), then the lowest
## victim HP fraction, then the nearest, then state.actors order. It keeps its previous threat while
## that stays one, unless a threat's victim is strictly earlier in cover_order. Worst case: one pass
## over state.actors (80 at frontier_march 50v30) per Knight per tick, then a filter over the enemies
## inside the zone.
static func _cover_threat(state: BattleState, knight: BattleActor, previous_target_id: String, center: Vector2, radius: float) -> BattleActor:
	# Per call, not static: sims run on worker threads (ig-7sn.13).
	var victims: Dictionary = {}
	var claims: Dictionary = {}
	var nearby: Array[BattleActor] = []
	for other: BattleActor in state.actors:
		if other == knight or other.life != BattleActor.LIFE_ALIVE:
			continue
		if other.faction == "enemy":
			if other.position.distance_to(center) <= radius:
				nearby.append(other)
		elif other.faction == "ally":
			if other.squad_id == knight.squad_id and other.archetype in BACK_ROW:
				victims[other.id] = other
			if other.archetype == "knight" and not other.order_target_id.is_empty():
				claims[other.order_target_id] = true
	var cover_order: Array = knight.effect_state.get("cover_order", [])
	var kept: BattleActor = null
	var kept_rank: int = 0
	var best: BattleActor = null
	var best_rank: int = cover_order.size() + 1
	var best_fraction: float = INF
	var best_distance: float = INF
	for enemy: BattleActor in nearby:
		var victim: BattleActor = victims.get(enemy.order_target_id) as BattleActor
		if victim == null or claims.has(enemy.id):
			continue
		var rank: int = cover_order.find(victim.hero_id)
		if rank < 0:
			rank = cover_order.size()
		if enemy.id == previous_target_id:
			kept = enemy
			kept_rank = rank
			continue
		var fraction: float = victim.hp / victim.max_hp
		var distance: float = enemy.position.distance_to(knight.position)
		if rank < best_rank or (rank == best_rank and (fraction < best_fraction or (fraction == best_fraction and distance < best_distance))):
			best = enemy
			best_rank = rank
			best_fraction = fraction
			best_distance = distance
	return kept if kept != null and kept_rank <= best_rank else best


## What _scan_rows found for one back-row hero this tick. Per call, not static: sims run on worker
## threads (ig-7sn.13).
class RowScan:
	var front: Array[BattleActor] = []
	var contact: bool = false
	var threat: BattleActor = null


## ig-0qh: what walking reads of the walls (DECISIONS.md 2026-09-25, "Casters shape the field", item 5),
## derived from state.field_objects and never saved. Keyed by field_sequence and the object count: a cast
## raises the one and an end lowers the other, so any change to the walls misses, and a fresh decode
## (a reload, a command: ig-7sn.15) starts with none. Per state, not static (ig-7sn.13).
class WallPaths:
	var sequence: int = -1
	var count: int = -1
	var bounds: float = 20.0
	## Per wall in cast order: its footprint's center, unit axis along the segment, half length and half
	## width (x, y), and the box around it for the pre-test.
	var centers := PackedVector2Array()
	var alongs := PackedVector2Array()
	var halves := PackedVector2Array()
	var box_low := PackedVector2Array()
	var box_high := PackedVector2Array()
	## The corners a path may use (inside the bounds, in no footprint): walls in cast order, each wall's in
	## CORNER_SIGNS order. Then, n x n, the shortest corner path's length and its first corner after the start.
	var corners := PackedVector2Array()
	var lengths := PackedFloat64Array()
	var firsts := PackedInt32Array()


## SYSTEMS.md § Casters, "Walking around walls": a footprint is the segment grown by half its thickness
## plus half battle_separation_radius, ends included. The corner graph is shortest paths over the corners
## that see each other, rebuilt only on a miss.
static func _wall_paths(state: BattleState) -> WallPaths:
	var paths: WallPaths = state.wall_paths
	if paths != null and paths.sequence == state.field_sequence and paths.count == state.field_objects.size():
		return paths
	paths = WallPaths.new()
	paths.sequence = state.field_sequence
	paths.count = state.field_objects.size()
	state.wall_paths = paths
	for field: Dictionary in state.field_objects:
		if field["kind"] == "wall":
			_add_footprint(paths, _array_vector(field["start"]), _array_vector(field["end"]), float(field["thickness"]))
	var bounds: float = float(state.objective_state.get("bounds", 20.0))
	paths.bounds = bounds
	for wall: int in paths.centers.size():
		var along: Vector2 = paths.alongs[wall]
		var across := Vector2(-along.y, along.x)
		var reach: Vector2 = paths.halves[wall] + Vector2(WALL_MARGIN, WALL_MARGIN)
		for corner_sign: Vector2 in CORNER_SIGNS:
			var corner: Vector2 = paths.centers[wall] + along * (corner_sign.x * reach.x) + across * (corner_sign.y * reach.y)
			if absf(corner.x) <= bounds and absf(corner.y) <= bounds and _wall_containing(paths, corner) < 0:
				paths.corners.append(corner)
	var n: int = paths.corners.size()
	paths.lengths.resize(n * n)
	paths.firsts.resize(n * n)
	for i: int in n:
		paths.lengths[i * n + i] = 0.0
		paths.firsts[i * n + i] = i
		for j: int in range(i + 1, n):
			var seen: bool = not _wall_blocked(paths, paths.corners[i], paths.corners[j])
			paths.lengths[i * n + j] = paths.corners[i].distance_to(paths.corners[j]) if seen else INF
			paths.lengths[j * n + i] = paths.lengths[i * n + j]
			paths.firsts[i * n + j] = j if seen else -1
			paths.firsts[j * n + i] = i if seen else -1
	for via: int in n:
		for i: int in n:
			for j: int in n:
				var through: float = paths.lengths[i * n + via] + paths.lengths[via * n + j]
				if through < paths.lengths[i * n + j]:
					paths.lengths[i * n + j] = through
					paths.firsts[i * n + j] = paths.firsts[i * n + via]
	return paths


static func _add_footprint(paths: WallPaths, start: Vector2, finish: Vector2, thickness: float) -> void:
	var along: Vector2 = (finish - start).normalized()
	var grow: float = thickness * 0.5 + BALANCE.battle_separation_radius * 0.5
	var half := Vector2(start.distance_to(finish) * 0.5 + grow, grow)
	var center: Vector2 = (start + finish) * 0.5
	var reach := Vector2(absf(along.x) * half.x + absf(along.y) * half.y, absf(along.y) * half.x + absf(along.x) * half.y)
	paths.centers.append(center)
	paths.alongs.append(along)
	paths.halves.append(half)
	paths.box_low.append(center - reach)
	paths.box_high.append(center + reach)


## Where the straight move from -> to first enters the wall's footprint (its open rectangle), as a
## fraction of the move, or -1.0 if it never does (Liang-Barsky in the wall's frame, after a box pre-test).
## A move along an edge never enters; a move from inside enters at 0.
static func _wall_entry(paths: WallPaths, wall: int, from: Vector2, to: Vector2) -> float:
	var low: Vector2 = paths.box_low[wall]
	var high: Vector2 = paths.box_high[wall]
	if maxf(from.x, to.x) <= low.x or minf(from.x, to.x) >= high.x or maxf(from.y, to.y) <= low.y or minf(from.y, to.y) >= high.y:
		return -1.0
	var along: Vector2 = paths.alongs[wall]
	var half: Vector2 = paths.halves[wall]
	var local: Vector2 = from - paths.centers[wall]
	var move: Vector2 = to - from
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in 2:
		var unit: Vector2 = along if axis == 0 else Vector2(-along.y, along.x)
		var at: float = local.dot(unit)
		var rate: float = move.dot(unit)
		var bound: float = half.x if axis == 0 else half.y
		if rate == 0.0:
			if absf(at) >= bound:
				return -1.0
			continue
		var first: float = (-bound - at) / rate
		var second: float = (bound - at) / rate
		enter = maxf(enter, minf(first, second))
		leave = minf(leave, maxf(first, second))
	return enter if enter < leave else -1.0


static func _wall_blocked(paths: WallPaths, from: Vector2, to: Vector2) -> bool:
	for wall: int in paths.centers.size():
		if _wall_entry(paths, wall, from, to) >= 0.0:
			return true
	return false


static func _in_wall(paths: WallPaths, wall: int, point: Vector2) -> bool:
	if point.x <= paths.box_low[wall].x or point.x >= paths.box_high[wall].x or point.y <= paths.box_low[wall].y or point.y >= paths.box_high[wall].y:
		return false
	var local: Vector2 = point - paths.centers[wall]
	var along: Vector2 = paths.alongs[wall]
	return absf(local.dot(along)) < paths.halves[wall].x and absf(local.dot(Vector2(-along.y, along.x))) < paths.halves[wall].y


## The first wall whose footprint has point strictly inside, or -1.
static func _wall_containing(paths: WallPaths, point: Vector2) -> int:
	for wall: int in paths.centers.size():
		if _in_wall(paths, wall, point):
			return wall
	return -1


## Which side of the wall's line point is on: 1.0, -1.0, or 0.0 on it.
static func _wall_side(paths: WallPaths, wall: int, point: Vector2) -> float:
	var along: Vector2 = paths.alongs[wall]
	return signf((point - paths.centers[wall]).dot(Vector2(-along.y, along.x)))


## point moved across the wall to just outside its long edge on side, keeping its place along it.
static func _wall_face(paths: WallPaths, wall: int, point: Vector2, side: float) -> Vector2:
	var along: Vector2 = paths.alongs[wall]
	var across := Vector2(-along.y, along.x)
	var local: Vector2 = point - paths.centers[wall]
	return paths.centers[wall] + along * local.dot(along) + across * (side * (paths.halves[wall].y + WALL_MARGIN))


## ig-vl1.5: a wall effect (Rime Wall; SYSTEMS.md § Casters, Walls). A segment of its length centered on
## point and across the line `across` (the aim, pointing away from the caster's side), its ends pulled in
## along it to the bounds; it never turns. Every alive or downed actor it lands on, elites too (not _push,
## which skips both), goes out across it through _wall_face: to the side it stood on, one exactly on its
## line to the caster's (DECISIONS.md 2026-09-25 item 6); when that face is out of bounds, to the far one.
## A carried body rides with its carrier; the dead and extracted stay put. The oldest wall at
## battle_wall_cap ends first, then the oldest object at battle_field_object_cap. False, with nothing
## changed, when a pushed actor's spot is out of bounds or in a wall that stays up: so no actor is ever
## left inside a footprint. The AI tries again next tick; a hand cast is refused and spends no cooldown.
static func _cast_wall(state: BattleState, actor: BattleActor, skill: AbilityDefinition, effect: Dictionary, point: Vector2, across: Vector2, pace: float) -> bool:
	var bounds: float = float(state.objective_state.get("bounds", 20.0))
	if across == Vector2.ZERO or absf(point.x) > bounds or absf(point.y) > bounds:
		return false
	var normal: Vector2 = across.normalized()
	# The footprint's across axis, (-along.y, along.x), is then normal.
	var along := Vector2(normal.y, -normal.x)
	var half: float = float(effect["length"]) * 0.5
	var start: Vector2 = _clamp_to_bounds(state, point - along * minf(half, _reach_to_bounds(point, -along, bounds)))
	var finish: Vector2 = _clamp_to_bounds(state, point + along * minf(half, _reach_to_bounds(point, along, bounds)))
	if start == finish:
		return false
	var kept: Array[Dictionary] = state.field_objects.duplicate()
	var walls: int = 0
	for field: Dictionary in kept:
		if field["kind"] == "wall":
			walls += 1
	while walls >= BALANCE.battle_wall_cap:
		for index: int in kept.size():
			if kept[index]["kind"] == "wall":
				kept.remove_at(index)
				break
		walls -= 1
	while kept.size() >= BALANCE.battle_field_object_cap:
		kept.remove_at(0)
	# The walls that stay up, then the new one: geometry only, no corner graph.
	var paths := WallPaths.new()
	paths.bounds = bounds
	for field: Dictionary in kept:
		if field["kind"] == "wall":
			_add_footprint(paths, _array_vector(field["start"]), _array_vector(field["end"]), float(field["thickness"]))
	var wall: int = paths.centers.size()
	_add_footprint(paths, start, finish, float(effect["thickness"]))
	var caster_side: float = _wall_side(paths, wall, actor.position)
	if caster_side == 0.0:
		caster_side = -1.0
	var moves: Array = []
	for other: BattleActor in state.actors:
		if not other.life in [BattleActor.LIFE_ALIVE, BattleActor.LIFE_DOWNED] or not other.carried_by_id.is_empty() or not _in_wall(paths, wall, other.position):
			continue
		var side: float = _wall_side(paths, wall, other.position)
		if side == 0.0:
			side = caster_side
		var spot: Vector2 = _wall_face(paths, wall, other.position, side)
		if absf(spot.x) > bounds or absf(spot.y) > bounds:
			spot = _wall_face(paths, wall, other.position, -side)
		if absf(spot.x) > bounds or absf(spot.y) > bounds:
			return false
		for older: int in wall:
			if _in_wall(paths, older, spot):
				return false
		moves.append([other, spot])
	state.field_objects = kept
	state.field_sequence += 1
	state.field_objects.append({
		"id": "field:%d" % state.field_sequence,
		"kind": "wall",
		"skill_id": str(skill.skill_id),
		"owner_actor_id": actor.id,
		"faction": actor.faction,
		"start": [start.x, start.y],
		"end": [finish.x, finish.y],
		"thickness": float(effect["thickness"]),
		"remaining_seconds": float(effect["seconds"]) * pace,
	})
	for move: Array in moves:
		var pushed: BattleActor = move[0]
		pushed.position = move[1]
		if not pushed.carrying_id.is_empty():
			var carried: BattleActor = _actor_by_id(state, pushed.carrying_id)
			if carried != null:
				carried.position = pushed.position
	return true


## How far from `from` along the unit `direction` the point stays inside the bounds (from is inside).
static func _reach_to_bounds(from: Vector2, direction: Vector2, bounds: float) -> float:
	var reach: float = INF
	for axis: int in 2:
		if direction[axis] > 0.0:
			reach = minf(reach, (bounds - from[axis]) / direction[axis])
		elif direction[axis] < 0.0:
			reach = minf(reach, (-bounds - from[axis]) / direction[axis])
	return maxf(reach, 0.0)


## ig-0qh: every instant move (a push, a move skill, separation, a walk step) stops at the first footprint
## edge it meets, WALL_MARGIN outside it. A footprint the mover already stands in doesn't stop it, so one
## that spawned in a wall can leave.
static func _wall_cut(paths: WallPaths, from: Vector2, to: Vector2) -> Vector2:
	var first: float = INF
	var hit: int = -1
	for wall: int in paths.centers.size():
		var enter: float = _wall_entry(paths, wall, from, to)
		if enter >= 0.0 and enter < first and (enter > 0.0 or not _in_wall(paths, wall, from)):
			first = enter
			hit = wall
	if hit < 0:
		return to
	# Onto the edge it crossed: the axis whose bound the entry point is nearer.
	var along: Vector2 = paths.alongs[hit]
	var across := Vector2(-along.y, along.x)
	var half: Vector2 = paths.halves[hit]
	var local: Vector2 = from + (to - from) * first - paths.centers[hit]
	var x: float = local.dot(along)
	var y: float = local.dot(across)
	if half.x - absf(x) < half.y - absf(y):
		x = (1.0 if x >= 0.0 else -1.0) * (half.x + WALL_MARGIN)
	else:
		y = (1.0 if y >= 0.0 else -1.0) * (half.y + WALL_MARGIN)
	# ig-vl1.5: a footprint within WALL_MARGIN of the bounds puts its edge outside them; the mover stays in.
	var cut: Vector2 = paths.centers[hit] + along * x + across * y
	return Vector2(clampf(cut.x, -paths.bounds, paths.bounds), clampf(cut.y, -paths.bounds, paths.bounds))


## A goal inside a footprint (a point order, an evade, the exit) moves to the long edge on the goal's side
## (on the line: the walker's, else the wall's left); any other goal stays. When that edge point is in
## another footprint or out of bounds, the nearest of the far edge point and the usable corners that is
## neither wins, ties to the earlier; none: the edge point stands and the walker holds as if walled in.
static func _wall_goal(paths: WallPaths, from: Vector2, goal: Vector2) -> Vector2:
	var holder: int = _wall_containing(paths, goal)
	if holder < 0:
		return goal
	var side: float = _wall_side(paths, holder, goal)
	if side == 0.0:
		side = _wall_side(paths, holder, from)
	if side == 0.0:
		side = 1.0
	var face: Vector2 = _wall_face(paths, holder, goal, side)
	var candidates := PackedVector2Array([face, _wall_face(paths, holder, goal, -side)])
	candidates.append_array(paths.corners)
	var best: Vector2 = face
	var best_distance: float = INF
	for candidate: Vector2 in candidates:
		var distance: float = goal.distance_to(candidate)
		if distance < best_distance and absf(candidate.x) <= paths.bounds and absf(candidate.y) <= paths.bounds and _wall_containing(paths, candidate) < 0:
			best = candidate
			best_distance = distance
	return best


## ig-0qh: where an actor at from walks this tick on its way to goal. Straight at it when no footprint is
## in the way; else the first corner of the shortest corner path, ties to the lower corner; null when
## walled in (it holds until a wall ends). One standing in a footprint (it spawned there) first walks out
## across its long edge. goal is outside every footprint: _move_actors has put it through _wall_goal.
static func _next_waypoint(paths: WallPaths, from: Vector2, goal: Vector2) -> Variant:
	var inside: int = _wall_containing(paths, from)
	if inside >= 0:
		var own_side: float = _wall_side(paths, inside, from)
		var face: Vector2 = _wall_face(paths, inside, from, own_side if own_side != 0.0 else 1.0)
		# ig-vl1.5: that face out of bounds (the field's edge), the far one.
		if absf(face.x) > paths.bounds or absf(face.y) > paths.bounds:
			face = _wall_face(paths, inside, from, -own_side if own_side != 0.0 else -1.0)
		return face
	if not _wall_blocked(paths, from, goal):
		return goal
	var n: int = paths.corners.size()
	var to_corner := PackedFloat64Array()
	var from_corner := PackedFloat64Array()
	to_corner.resize(n)
	from_corner.resize(n)
	for i: int in n:
		var corner: Vector2 = paths.corners[i]
		to_corner[i] = from.distance_to(corner) if not _wall_blocked(paths, from, corner) else INF
		from_corner[i] = goal.distance_to(corner) if not _wall_blocked(paths, corner, goal) else INF
	var best: float = INF
	var best_start: int = -1
	var best_end: int = -1
	for i: int in n:
		if to_corner[i] == INF:
			continue
		for j: int in n:
			var cost: float = to_corner[i] + paths.lengths[i * n + j] + from_corner[j]
			if cost < best:
				best = cost
				best_start = i
				best_end = j
	if best_start < 0:
		return null
	if to_corner[best_start] > REACH_TOLERANCE:
		return paths.corners[best_start]
	# Standing on that corner: on to the path's next one, or the goal from the last.
	return goal if best_start == best_end else paths.corners[paths.firsts[best_start * n + best_end]]


## The back row's one pass over state.actors per tick (ig-uu7.1 formation, ig-uu7.3 kiting): whether
## a living enemy is within the hero's contact range, its squad's living front-liners, and the
## nearest living enemy targeting it. Worst case: 80 actors at frontier_march 50v30.
static func _scan_rows(state: BattleState, actor: BattleActor) -> RowScan:
	var rows := RowScan.new()
	var contact: float = maxf(BALANCE.battle_detection_range, actor.attack_range)
	var threat_distance: float = INF
	for other: BattleActor in state.actors:
		if other.life != BattleActor.LIFE_ALIVE:
			continue
		if other.faction == "enemy":
			var distance: float = other.position.distance_to(actor.position)
			rows.contact = rows.contact or distance <= contact
			if other.order_target_id == actor.id and distance < threat_distance:
				rows.threat = other
				threat_distance = distance
		elif other.squad_id == actor.squad_id and other.archetype in FRONT_ROW:
			rows.front.append(other)
	return rows


## ig-uu7.3 Kiting (SYSTEMS.md § Hero AI on auto): a back-row hero that outranges the trigger hops
## once toward the spot behind its nearest front-liner when an enemy on it comes close, then fights
## out the cooldown. Reads _scan_rows. Returns whether it set the order.
static func _kite_order(state: BattleState, actor: BattleActor, rows: RowScan) -> bool:
	if actor.effect_state.get("kite_point") is Array:
		var point: Vector2 = _array_vector(actor.effect_state.get("kite_point"), actor.position)
		# A hop lasts at most a full hop's walk plus one tick, so bodies pinning it short can't hold it
		# forever. It started a cooldown before the next ready tick, so no key of its own is saved.
		var started: int = int(actor.effect_state.get("kite_ready_tick", 0)) - ceili(BALANCE.battle_kite_cooldown_seconds / BALANCE.battle_tick_seconds)
		# A loaded snapshot may carry move_speed 0; a real hero never walks slower than the minimum.
		var longest: int = ceili(BALANCE.battle_kite_distance / (maxf(actor.move_speed, BALANCE.battle_move_speed_min) * BALANCE.battle_tick_seconds)) + 1
		if rows.threat == null or state.tick - started >= longest or actor.position.distance_to(point) <= BALANCE.battle_separation_radius:
			actor.effect_state.erase("kite_point")
			return false
		_set_auto_order(actor, COMMAND_MOVE, "", point)
		return true
	if actor.attack_range <= BALANCE.battle_kite_trigger_range or rows.threat == null or state.tick < int(actor.effect_state.get("kite_ready_tick", 0)):
		return false
	var threat_at: Vector2 = rows.threat.position
	if threat_at.distance_to(actor.position) > BALANCE.battle_kite_trigger_range:
		return false
	var front: BattleActor = null
	for other: BattleActor in rows.front:
		if front == null or other.position.distance_to(actor.position) < front.position.distance_to(actor.position):
			front = other
	var away: Vector2 = actor.position + (actor.position - threat_at).normalized() * BALANCE.battle_kite_distance
	var end: Vector2 = away
	if front != null:
		var behind: Vector2 = front.position + (front.position - threat_at).normalized() * BALANCE.battle_formation_spacing
		end = actor.position + (behind - actor.position).limit_length(BALANCE.battle_kite_distance)
		# The tank is on the far side of the enemy: that hop closes in, so run straight away instead.
		if end.distance_to(threat_at) < actor.position.distance_to(threat_at):
			end = away
	end = _clamp_to_bounds(state, end)
	# Cornered: stand and fight, and keep the hop for next tick.
	if end.distance_to(actor.position) < BALANCE.battle_kite_distance * 0.5:
		return false
	actor.effect_state["kite_point"] = [end.x, end.y]
	actor.effect_state["kite_ready_tick"] = state.tick + ceili(BALANCE.battle_kite_cooldown_seconds / BALANCE.battle_tick_seconds)
	_set_auto_order(actor, COMMAND_MOVE, "", end)
	return true


## ig-uu7.1 Formation (SYSTEMS.md § Hero AI on auto): before contact, a back-row hero stays one
## formation spacing farther from its reference point than its squad's nearest living front-liner.
## Off while any living enemy is within its contact range, or with no living front-liner. Returns
## whether it set the order. Reads _scan_rows, so it adds no pass of its own.
static func _formation_order(actor: BattleActor, rows: RowScan, anchor: Vector2) -> bool:
	if rows.contact or rows.front.is_empty():
		return false
	var front_distance: float = INF
	for other: BattleActor in rows.front:
		front_distance = minf(front_distance, other.position.distance_to(anchor))
	var cap: float = front_distance + BALANCE.battle_formation_spacing
	if actor.position.distance_to(anchor) > cap:
		_set_auto_order(actor, COMMAND_MOVE, "", anchor + (actor.position - anchor).normalized() * cap)
	else:
		_set_auto_order(actor, COMMAND_HOLD, "", actor.position)
	return true


static func _set_auto_order(actor: BattleActor, kind: String, target_id: String, point: Vector2) -> void:
	actor.order_kind = kind
	actor.order_target_id = target_id
	actor.order_point = point
	actor.effect_state["direct_order"] = false


static func _squad_for(state: BattleState, squad_id: String) -> Dictionary:
	for squad: Dictionary in state.squads:
		if str(squad.get("id", "")) == squad_id:
			return squad
	return {}


static func _squad_leader(state: BattleState, squad_id: String) -> BattleActor:
	var leader: BattleActor = null
	for candidate: BattleActor in state.actors:
		if candidate.faction == "ally" and candidate.life == BattleActor.LIFE_ALIVE and candidate.squad_id == squad_id:
			if leader == null or candidate.spawn_index < leader.spawn_index:
				leader = candidate
	return leader


static func _squad_centroid(state: BattleState, squad_id: String) -> Vector2:
	var sum := Vector2.ZERO
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE and actor.squad_id == squad_id:
			sum += actor.position
			count += 1
	return sum / float(count) if count > 0 else Vector2.ZERO


static func _squad_member_beyond(state: BattleState, squad_id: String, center: Vector2, radius: float) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE and actor.squad_id == squad_id and actor.position.distance_to(center) > radius:
			return true
	return false


static func _protected_actor(state: BattleState, squad: Dictionary) -> BattleActor:
	var explicit: BattleActor = _actor_by_id(state, str(squad.get("guard_target_id", "")))
	if explicit != null and explicit.faction == "ally" and explicit.life == BattleActor.LIFE_ALIVE:
		return explicit
	var protected: BattleActor = null
	var squad_id: String = str(squad.get("id", ""))
	for candidate: BattleActor in state.actors:
		if candidate.faction != "ally" or candidate.life != BattleActor.LIFE_ALIVE or candidate.squad_id != squad_id:
			continue
		if protected == null or candidate.max_hp < protected.max_hp or (is_equal_approx(candidate.max_hp, protected.max_hp) and candidate.spawn_index < protected.spawn_index):
			protected = candidate
	return protected



static func _actor_by_id(state: BattleState, id: String) -> BattleActor:
	if id.is_empty():
		return null
	for actor: BattleActor in state.actors:
		if actor.id == id:
			return actor
	return null


static func _nearest_actor(state: BattleState, source: BattleActor, faction: String, life: String) -> BattleActor:
	var nearest: BattleActor = null
	var nearest_distance: float = INF
	for actor: BattleActor in state.actors:
		if actor == source or actor.faction != faction or actor.life != life:
			continue
		var distance: float = source.position.distance_squared_to(actor.position)
		if distance < nearest_distance:
			nearest = actor
			nearest_distance = distance
	return nearest


static func _nearest_actor_within(
	state: BattleState,
	from_point: Vector2,
	faction: String,
	detection_radius: float,
	leash_point: Vector2,
	leash_radius: float,
) -> BattleActor:
	var nearest: BattleActor = null
	var nearest_distance: float = INF
	for candidate: BattleActor in state.actors:
		if candidate.faction != faction or candidate.life != BattleActor.LIFE_ALIVE:
			continue
		if candidate.position.distance_to(leash_point) > leash_radius:
			continue
		var distance: float = candidate.position.distance_squared_to(from_point)
		if distance <= detection_radius * detection_radius and (distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest == null or candidate.spawn_index < nearest.spawn_index))):
			nearest = candidate
			nearest_distance = distance
	return nearest


static func _nearest_enemy_near_point(state: BattleState, from_point: Vector2, center: Vector2, radius: float) -> BattleActor:
	return _nearest_actor_within(state, from_point, "enemy", INF, center, radius)


static func _nearest_unassigned_downed(state: BattleState, source: BattleActor) -> BattleActor:
	var assigned_ids: Dictionary[String, bool] = {}
	for actor: BattleActor in state.actors:
		if actor != source and actor.life == BattleActor.LIFE_ALIVE:
			if actor.order_kind == COMMAND_CARRY and not actor.order_target_id.is_empty():
				assigned_ids[actor.order_target_id] = true
			if not actor.carrying_id.is_empty():
				assigned_ids[actor.carrying_id] = true
	var nearest: BattleActor = null
	var nearest_distance: float = INF
	for candidate: BattleActor in state.actors:
		if candidate.faction != "ally" or candidate.life != BattleActor.LIFE_DOWNED or not candidate.carried_by_id.is_empty() or assigned_ids.has(candidate.id):
			continue
		var distance: float = source.position.distance_squared_to(candidate.position)
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest == null or candidate.spawn_index < nearest.spawn_index)):
			nearest = candidate
			nearest_distance = distance
	return nearest


static func _lowest_health_ally(state: BattleState, center: Vector2, radius: float) -> BattleActor:
	var lowest: BattleActor = null
	var lowest_fraction: float = INF
	for actor: BattleActor in state.actors:
		if actor.faction != "ally" or actor.life != BattleActor.LIFE_ALIVE or actor.position.distance_to(center) > radius:
			continue
		var fraction: float = actor.hp / actor.max_hp
		if fraction < lowest_fraction:
			lowest = actor
			lowest_fraction = fraction
	return lowest


## Null when the zone gives the squad no point and the actor keeps its own position.
static func _assigned_objective_point(state: BattleState, actor: BattleActor) -> Variant:
	if bool(state.objective_state.get("escort_active", false)):
		return _objective_point(state, "cart_position")
	if str(state.objective_state.get("battle_kind", "standard")) == "raid" and bool(state.objective_state.get("boss_spawned", false)):
		return Vector2(0.0, 8.0)
	var markers: Array = state.objective_state.get("markers", []) as Array
	var objective_markers: Array[Dictionary] = []
	for raw_marker: Variant in markers:
		if raw_marker is Dictionary:
			var marker: Dictionary = raw_marker as Dictionary
			if bool(marker.get("active", true)) and not bool(marker.get("complete", false)) and str(marker.get("kind", "")) in ["capture", "camp"]:
				objective_markers.append(marker)
	if not objective_markers.is_empty():
		var squad_index: int = 0
		for index: int in state.squads.size():
			if str(state.squads[index].get("id", "")) == actor.squad_id:
				squad_index = index
				break
		return _array_vector(objective_markers[squad_index % objective_markers.size()].get("position"))
	if str(state.objective_state.get("battle_kind", "standard")) == "standard":
		return Vector2(0.0, 8.0)
	return null


static func _assigned_objective_enemy(state: BattleState, actor: BattleActor, objective: Vector2) -> BattleActor:
	var battle_kind: String = str(state.objective_state.get("battle_kind", "standard"))
	if battle_kind in ["raid", "region"]:
		return _nearest_enemy_near_point(state, actor.position, objective, BALANCE.battle_detection_range)
	return _nearest_actor(state, actor, "enemy", BattleActor.LIFE_ALIVE)


static func _living_enemy_with_objective(state: BattleState, objective_id: String) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and actor.life == BattleActor.LIFE_ALIVE and str(actor.effect_state.get("objective_id", "")) == objective_id:
			return true
	return false


## The archetype sets ranged or melee; a basic_range passive stretches it. Ally ranged heroes
## reach farther than enemy ones (owner ruling 2026-09-24).
static func _attack_range(actor: BattleActor) -> float:
	var base: float = BALANCE.battle_melee_range
	if actor.archetype in ["ranger", "mage"]:
		base = BALANCE.battle_ally_ranged_range if actor.faction == "ally" else BALANCE.battle_ranged_range
	return base * (1.0 + _passive(actor, "basic_range"))


static func _living_ally_near(state: BattleState, source: BattleActor, radius: float) -> bool:
	for actor: BattleActor in state.actors:
		if actor != source and actor.faction == source.faction and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(source.position) <= radius:
			return true
	return false


static func _is_behind(attacker: BattleActor, target: BattleActor) -> bool:
	var to_attacker: Vector2 = (attacker.position - target.position).normalized()
	return to_attacker.dot(target.facing.normalized()) < 0.0


static func _rogue_flank_position(state: BattleState, actor: BattleActor, target: BattleActor) -> Variant:
	var facing: Vector2 = target.facing.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.UP
	var rear: Vector2 = -facing
	for angle: float in [0.0, PI / 4.0, -PI / 4.0]:
		var candidate: Vector2 = _clamp_to_bounds(state, target.position + rear.rotated(angle) * actor.attack_range)
		var occupied: bool = false
		for other: BattleActor in state.actors:
			if other != actor and other.life == BattleActor.LIFE_ALIVE and other.position.distance_to(candidate) < BALANCE.battle_separation_radius:
				occupied = true
				break
		if not occupied:
			return candidate
	return null


static func _actor_in_radius(state: BattleState, faction: String, center: Vector2, radius: float) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == faction and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(center) <= radius:
			return true
	return false


static func _allies_in_radius(state: BattleState, center: Vector2, radius: float) -> int:
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(center) <= radius:
			count += 1
	return count


static func _enemies_in_radius(state: BattleState, center: Vector2, radius: float) -> int:
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(center) <= radius:
			count += 1
	return count


static func _opponents_in_radius(state: BattleState, faction: String, center: Vector2, radius: float) -> int:
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction != faction and actor.life == BattleActor.LIFE_ALIVE and actor.position.distance_to(center) <= radius:
			count += 1
	return count


static func _living_enemy_count(state: BattleState) -> int:
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and actor.life == BattleActor.LIFE_ALIVE:
			count += 1
	return count


static func _deployed_hero_count(state: BattleState) -> int:
	var count: int = 0
	for actor: BattleActor in state.actors:
		if actor.faction == "ally" and not actor.hero_id.is_empty():
			count += 1
	return count


static func _apply_separation(state: BattleState, actor: BattleActor, paths: WallPaths) -> void:
	for other: BattleActor in state.actors:
		if other == actor or other.life != BattleActor.LIFE_ALIVE:
			continue
		var offset: Vector2 = actor.position - other.position
		var distance: float = offset.length()
		if distance <= TICK_EPSILON:
			var lower_index: int = mini(actor.spawn_index, other.spawn_index)
			var upper_index: int = maxi(actor.spawn_index, other.spawn_index)
			match (lower_index + upper_index) % 4:
				0:
					offset = Vector2.RIGHT
				1:
					offset = Vector2.DOWN
				2:
					offset = Vector2.LEFT
				_:
					offset = Vector2.UP
			if actor.spawn_index > other.spawn_index:
				offset = -offset
		if distance < BALANCE.battle_separation_radius:
			if paths.centers.is_empty():
				actor.position += offset.normalized() * (BALANCE.battle_separation_radius - distance) * 0.5
				actor.position = _clamp_to_bounds(state, actor.position)
			else:
				actor.position = _wall_cut(paths, actor.position, _clamp_to_bounds(state, actor.position + offset.normalized() * (BALANCE.battle_separation_radius - distance) * 0.5))


static func _grid_offset(index: int, count: int, spacing: float) -> Vector2:
	var columns: int = mini(5, maxi(count, 1))
	@warning_ignore("integer_division")
	var row: int = index / columns
	var column: int = index % columns
	var row_count: int = mini(columns, count - row * columns)
	return Vector2((float(column) - float(row_count - 1) * 0.5) * spacing, float(row) * spacing)


static func _clamp_to_bounds(state: BattleState, point: Vector2) -> Vector2:
	var bounds: float = float(state.objective_state.get("bounds", 20.0))
	return Vector2(clampf(point.x, -bounds, bounds), clampf(point.y, -bounds, bounds))


static func _objective_point(state: BattleState, key: String) -> Vector2:
	return _array_vector(state.objective_state.get(key))


static func _update_cart_marker(state: BattleState, position: Vector2) -> void:
	for marker: Dictionary in state.objective_state.get("markers", []) as Array:
		if str(marker.get("kind", "")) == "cart":
			marker["position"] = [position.x, position.y]


static func _complete_waypoint_marker(state: BattleState, waypoint_index: int) -> void:
	for marker: Dictionary in state.objective_state.get("markers", []) as Array:
		if str(marker.get("id", "")) == "waypoint:%d" % waypoint_index:
			marker["complete"] = true
			marker["progress"] = 1.0


static func _array_vector(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if not _valid_point(value):
		return fallback
	var entries: Array = value as Array
	return Vector2(float(entries[0]), float(entries[1]))


static func _vector_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func _command_point(command: Dictionary) -> Vector2:
	return _array_vector(command.get("point"))


static func _valid_point(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var entries: Array = value as Array
	return _valid_number(entries[0]) and _valid_number(entries[1])


## _point_within_bounds for a point already checked as two finite numbers (ig-7sn.10: the actor loop's
## positions, which validate_dict checked). The same Vector2, so the same verdict to the bit.
static func _valid_point_within_bounds(entries: Array, bounds: float) -> bool:
	var point := Vector2(float(entries[0]), float(entries[1]))
	return absf(point.x) <= bounds + TICK_EPSILON and absf(point.y) <= bounds + TICK_EPSILON


static func _point_within_bounds(value: Variant, bounds: float) -> bool:
	if not _valid_point(value):
		return false
	var point: Vector2 = _array_vector(value)
	return absf(point.x) <= bounds + TICK_EPSILON and absf(point.y) <= bounds + TICK_EPSILON


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _nonnegative_integer(value: Variant) -> bool:
	return _valid_number(value) and float(value) >= 0.0 and float(value) == floorf(float(value))


static func _valid_int64_string(value: String) -> bool:
	if value.is_empty() or not value.is_valid_int():
		return false
	if value.begins_with("+"):
		return str(value.substr(1).to_int()) == value.substr(1)
	return str(value.to_int()) == value or value == "-0"


static func _raw_actor_by_id(actors: Array, actor_id: String) -> Dictionary:
	for raw_actor: Variant in actors:
		if raw_actor is Dictionary and str((raw_actor as Dictionary).get("id", "")) == actor_id:
			return raw_actor as Dictionary
	return {}


static func _hero_actor_by_actor_id(hero_actors: Dictionary[String, Dictionary], actor_id: String) -> Dictionary:
	for actor_data: Dictionary in hero_actors.values():
		if str(actor_data.get("id")) == actor_id:
			return actor_data
	return {}


static func _validate_policies(policies: Dictionary) -> String:
	for key: String in ["auto_battle", "auto_heal", "auto_revive", "reserve_last_revival", "retreat_when_supplies_empty"]:
		if not policies.get(key) is bool:
			return "Battle policy %s must be a bool." % key
	if not policies.get("default_stance") is String or not str(policies.get("default_stance")) in STANCES:
		return "Battle default_stance is invalid."
	if not _valid_number(policies.get("heal_below")) or float(policies.get("heal_below")) < 0.0 or float(policies.get("heal_below")) > 1.0:
		return "Battle heal_below must be between zero and one."
	if policies.has("ability_auto") and not policies.get("ability_auto") is Dictionary:
		return "Battle ability_auto policy must be a Dictionary."
	for raw_value: Variant in (policies.get("ability_auto", {}) as Dictionary).values():
		if not raw_value is bool:
			return "Every per-hero ability_auto value must be a bool."
	return ""


static func _validate_squads(
	squads: Array,
	hero_actors: Dictionary[String, Dictionary],
	kind: String,
	status: String,
) -> String:
	var squad_ids: Dictionary[String, bool] = {}
	var assigned_heroes: Dictionary[String, bool] = {}
	for raw_squad: Variant in squads:
		if not raw_squad is Dictionary:
			return "Every battle squad must be a Dictionary."
		var squad: Dictionary = raw_squad as Dictionary
		for key: String in ["id", "name", "stance", "guard_target_id"]:
			if not squad.get(key) is String:
				return "Battle squad %s must be a String." % key
		var squad_id: String = str(squad.get("id"))
		if squad_id.is_empty() or squad_ids.has(squad_id):
			return "Battle squad IDs must be unique and non-empty."
		if not str(squad.get("stance")) in STANCES:
			return "Battle squad stance is invalid."
		if not _valid_point(squad.get("stance_anchor")):
			return "Battle squad stance_anchor must contain two finite numbers."
		if not squad.get("hero_ids") is Array or (squad.get("hero_ids") as Array).is_empty() or (squad.get("hero_ids") as Array).size() > 5:
			return "Battle squads must contain one to five hero IDs."
		for raw_hero_id: Variant in squad.get("hero_ids") as Array:
			if not raw_hero_id is String or not hero_actors.has(raw_hero_id as String) or assigned_heroes.has(raw_hero_id as String):
				return "Battle squad hero IDs must be unique deployed heroes."
			if str(hero_actors[raw_hero_id as String].get("squad_id")) != squad_id:
				return "Battle hero squad_id must match squad membership."
			assigned_heroes[raw_hero_id as String] = true
		squad_ids[squad_id] = true
		var guard_target_id: String = str(squad.get("guard_target_id"))
		if not guard_target_id.is_empty():
			var guard_actor: Dictionary = _hero_actor_by_actor_id(hero_actors, guard_target_id)
			if guard_actor.is_empty() or str(guard_actor.get("life")) != BattleActor.LIFE_ALIVE:
				return "Battle squad guard_target_id must reference a living allied actor."
	var preserved_incident: bool = status == "stranded" and squads.is_empty()
	for hero_id: String in hero_actors:
		var actor_squad_id: String = str(hero_actors[hero_id].get("squad_id"))
		if actor_squad_id.is_empty():
			if kind != "rescue" and not preserved_incident:
				return "Every deployed hero must belong to one battle squad."
		elif not squad_ids.has(actor_squad_id) or not assigned_heroes.has(hero_id):
			return "Battle hero squad_id must match squad membership."
	return ""


static func _validate_objective_state(objective_state: Dictionary, zone: ZoneDefinition, pace: int) -> String:
	if not objective_state.get("battle_kind") is String or str(objective_state.get("battle_kind")) != zone.battle_kind:
		return "Battle objective kind must match the authored zone."
	if not _valid_number(objective_state.get("bounds")) or absf(float(objective_state.get("bounds")) - zone.battle_bounds) > TICK_EPSILON:
		return "Battle objective bounds must match the authored zone."
	if not _valid_point(objective_state.get("exit_position")) or _array_vector(objective_state.get("exit_position")).distance_to(zone.exit_position) > TICK_EPSILON:
		return "Battle objective exit must match the authored zone."
	if not _valid_point(objective_state.get("cart_position")):
		return "Battle objective cart_position must contain two finite numbers."
	if zone.battle_kind == "region" and not _point_within_bounds(objective_state.get("cart_position"), zone.battle_bounds):
		return "Battle objective cart_position must remain inside the authored bounds."
	if not _nonnegative_integer(objective_state.get("escort_index")) or int(objective_state.get("escort_index")) > zone.escort_waypoints.size():
		return "Battle objective escort_index is invalid."
	for key: String in ["escort_active", "boss_spawned"]:
		if not objective_state.get(key) is bool:
			return "Battle objective %s must be a bool." % key
	if not _valid_number(objective_state.get("simultaneous_hold_seconds")):
		return "Battle objective hold time must be finite."
	var hold_seconds: float = float(objective_state.get("simultaneous_hold_seconds"))
	if hold_seconds < 0.0 or hold_seconds > zone.objective_hold_seconds * pace + TICK_EPSILON:
		return "Battle objective hold time is outside its authored range."
	if bool(objective_state.get("boss_spawned", false)) and zone.battle_kind != "raid":
		return "Only a raid objective can have a spawned boss."
	if bool(objective_state.get("boss_spawned", false)) and hold_seconds + TICK_EPSILON < zone.objective_hold_seconds * pace:
		return "A raid boss requires completed simultaneous capture."
	var marker_error: String = _validate_markers(objective_state, zone)
	if not marker_error.is_empty():
		return marker_error
	return ""


static func _validate_markers(objective_state: Dictionary, zone: ZoneDefinition) -> String:
	if not objective_state.get("markers") is Array:
		return "Battle objective markers must be an Array."
	var expected_markers: Array = _initial_objective_state(zone).get("markers", []) as Array
	if (objective_state.get("markers") as Array).size() != expected_markers.size():
		return "Battle objective markers must match the authored zone."
	var expected_by_id: Dictionary[String, Dictionary] = {}
	for expected_marker: Dictionary in expected_markers:
		expected_by_id[str(expected_marker.get("id"))] = expected_marker
	var marker_ids: Dictionary[String, bool] = {}
	for raw_marker: Variant in objective_state.get("markers") as Array:
		if not raw_marker is Dictionary:
			return "Every objective marker must be a Dictionary."
		var marker: Dictionary = raw_marker as Dictionary
		for key: String in ["id", "kind", "label"]:
			if not marker.get(key) is String:
				return "Objective marker %s must be a String." % key
		var marker_id: String = str(marker.get("id"))
		if marker_id.is_empty() or marker_ids.has(marker_id) or not expected_by_id.has(marker_id):
			return "Objective marker IDs must be unique and non-empty."
		if str(marker.get("kind")) != str(expected_by_id[marker_id].get("kind")):
			return "Objective marker kinds must match the authored zone."
		marker_ids[marker_id] = true
		if not _valid_point(marker.get("position")) or not _valid_number(marker.get("radius")) or not _valid_number(marker.get("progress")):
			return "Objective marker geometry/progress must be finite."
		if float(marker.get("radius")) < 0.0 or float(marker.get("progress")) < 0.0 or float(marker.get("progress")) > 1.0:
			return "Objective marker radius/progress is outside its range."
		if not _point_within_bounds(marker.get("position"), zone.battle_bounds):
			return "Objective marker positions must remain inside the authored bounds."
		var expected_position: Vector2 = _array_vector(expected_by_id[marker_id].get("position"))
		if str(marker.get("kind")) == "cart":
			expected_position = _array_vector(objective_state.get("cart_position"))
		if _array_vector(marker.get("position")).distance_to(expected_position) > TICK_EPSILON:
			return "Objective marker positions must match objective state."
		if not marker.get("active") is bool or not marker.get("complete") is bool:
			return "Objective marker state must be bool."
	return ""
