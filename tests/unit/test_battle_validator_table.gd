extends GutTest

## ig-7sn.10 ACC 4: one broken field per row, and the message validate_snapshot returns for it. It covers
## every refusal BattleActor.validate_dict and BattleSimulation.validate_snapshot can return, the helpers
## they call included (_validate_skills, _validate_skill_state, supplies_shape_error, _validate_policies,
## _validate_squads, _validate_field_objects with ig-vl1.5's walls, _validate_objective_state and
## _validate_markers). Written against the validators before ig-7sn.10's rewrite, so a verdict or a message
## that changes fails here. Each row breaks a checkpoint as the save's parse gives it (JSON numbers are
## floats). One refusal is not listed: the second "Battle zone_id is unknown." (a zone resource whose
## zone_id differs from its file name), which no checkpoint can reach.

const BALANCE: BalanceTable = preload("res://balance.tres")

var _bases: Dictionary[String, Dictionary] = {}


func before_all() -> void:
	for zone_id: String in ["verdant_outskirts", "fallen_citadel", "frontier_march"]:
		_bases[zone_id] = _base(zone_id)


func test_every_base_is_valid() -> void:
	for zone_id: String in _bases:
		assert_eq(BattleSimulation.validate_snapshot(_bases[zone_id]), "", zone_id)
		assert_true(_enemy_index(_bases[zone_id]) >= 0, "%s has an enemy" % zone_id)
	assert_eq(BattleSimulation.validate_snapshot(_with_fields(_bases["verdant_outskirts"])), "", "a zone and a wall")


func test_actor_refusals() -> void:
	_check(_actor_rows())


func test_actor_skill_and_status_refusals() -> void:
	_check(_skill_rows())


func test_actor_effect_refusals() -> void:
	_check(_effect_rows())


## ig-gy0.5 (boundary #1): an actor's chains and the four keys of a running one.
func test_actor_chain_refusals() -> void:
	_check(_chain_rows())


func test_snapshot_refusals() -> void:
	_check(_snapshot_rows())


func test_snapshot_actor_link_refusals() -> void:
	_check(_link_rows())


func test_supplies_policies_and_squads_refusals() -> void:
	_check(_squad_rows())


func test_field_object_and_wall_refusals() -> void:
	_check(_field_rows())


func test_objective_and_marker_refusals() -> void:
	_check(_objective_rows())


## Each row: [zone, message, a mutation of a deep copy of that zone's base].
func _check(rows: Array[Array]) -> void:
	assert_gt(rows.size(), 0)
	for row: Array in rows:
		var data: Dictionary = (_bases[row[0]] as Dictionary).duplicate(true)
		(row[2] as Callable).call(data)
		assert_eq(BattleSimulation.validate_snapshot(data), row[1] as String, "row: %s" % row[1])


func _actor_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	for key: String in ["id", "hero_id", "archetype", "faction", "squad_id", "life", "order_kind", "order_target_id", "carried_by_id", "carrying_id", "guard_target_id"]:
		rows.append([v, "Battle actor %s must be a String." % key, func(d: Dictionary) -> void: _a(d)[key] = 3])
	rows.append([v, "Battle actor id must be non-empty.", func(d: Dictionary) -> void: _a(d)["id"] = ""])
	rows.append([v, "Battle actor archetype or faction is invalid.", func(d: Dictionary) -> void: _a(d)["archetype"] = "dragon"])
	rows.append([v, "Battle actor archetype or faction is invalid.", func(d: Dictionary) -> void: _a(d)["faction"] = "neutral"])
	rows.append([v, "Battle actor order_kind is invalid.", func(d: Dictionary) -> void: _a(d)["order_kind"] = "dance"])
	rows.append([v, "Allied battle actors need hero IDs and enemies must not have them.", func(d: Dictionary) -> void: _a(d)["hero_id"] = ""])
	rows.append([v, "Allied battle actors need hero IDs and enemies must not have them.", func(d: Dictionary) -> void: _e(d)["hero_id"] = "hero:x"])
	for bad: Variant in [-1.0, 1.5, "1"]:
		rows.append([v, "Battle actor spawn_index must be a non-negative integer.", func(d: Dictionary) -> void: _a(d)["spawn_index"] = bad])
	for key: String in ["position", "facing", "order_point"]:
		rows.append([v, "Battle actor %s must contain two finite numbers." % key, func(d: Dictionary) -> void: _a(d)[key] = [1.0]])
	rows.append([v, "Battle actor position must contain two finite numbers.", func(d: Dictionary) -> void: _a(d)["position"] = [NAN, 0.0]])
	for key: String in ["hp", "max_hp", "atk", "defense", "speed", "crit_rate", "crit_damage", "attack_range", "move_speed", "attack_cooldown", "item_cooldown"]:
		rows.append([v, "Battle actor %s must be finite." % key, func(d: Dictionary) -> void: _a(d)[key] = "x"])
	rows.append([v, "Battle actor hp must be finite.", func(d: Dictionary) -> void: _a(d)["hp"] = INF])
	rows.append([v, "Battle actor HP is outside its valid range.", func(d: Dictionary) -> void: _a(d)["max_hp"] = 0.0])
	rows.append([v, "Battle actor HP is outside its valid range.", func(d: Dictionary) -> void: _a(d)["hp"] = -1.0])
	rows.append([v, "Battle actor HP is outside its valid range.", func(d: Dictionary) -> void: _a(d)["hp"] = float(_a(d)["max_hp"]) + 1.0])
	for key: String in ["atk", "defense", "speed", "attack_range", "move_speed", "attack_cooldown", "item_cooldown"]:
		rows.append([v, "Battle actor %s must be non-negative." % key, func(d: Dictionary) -> void: _a(d)[key] = -1.0])
	rows.append([v, "Battle actor critical values are invalid.", func(d: Dictionary) -> void: _a(d)["crit_rate"] = -0.1])
	rows.append([v, "Battle actor critical values are invalid.", func(d: Dictionary) -> void: _a(d)["crit_rate"] = 1.1])
	rows.append([v, "Battle actor critical values are invalid.", func(d: Dictionary) -> void: _a(d)["crit_damage"] = 0.9])
	rows.append([v, "Battle actor life is invalid.", func(d: Dictionary) -> void: _a(d)["life"] = "zombie"])
	rows.append([v, "Allied battle actors cannot be dead inside a battle snapshot.", func(d: Dictionary) -> void: _a(d).merge({"life": "dead", "hp": 0.0}, true)])
	rows.append([v, "Enemy battle actors cannot be downed.", func(d: Dictionary) -> void: _e(d).merge({"life": "downed", "hp": 0.0}, true)])
	rows.append([v, "Living battle actors need positive HP.", func(d: Dictionary) -> void: _a(d)["hp"] = 0.0])
	rows.append([v, "Downed and dead battle actors must have zero HP.", func(d: Dictionary) -> void: _a(d)["life"] = "downed"])
	rows.append([v, "Downed and dead battle actors must have zero HP.", func(d: Dictionary) -> void: _e(d)["life"] = "dead"])
	return rows


func _skill_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var base: Dictionary = _a(_bases[v])
	var first_id: String = str(((base["skills"] as Array)[0] as Dictionary)["id"])
	var passive: int = -1
	var ability: String = ""
	for index: int in (base["skills"] as Array).size():
		var skill: AbilityDefinition = BattleSimulation.ABILITIES[str(((base["skills"] as Array)[index] as Dictionary)["id"])] as AbilityDefinition
		if skill.kind == "passive" and passive < 0:
			passive = index
		if skill.is_ability() and ability.is_empty():
			ability = str(skill.skill_id)
	assert_true(passive >= 0 and not ability.is_empty(), "the first ally has a passive and an ability")
	var rows: Array[Array] = []
	rows.append([v, "Battle actor ability_cooldown must be finite and non-negative.", func(d: Dictionary) -> void:
		_a(d).erase("skills")
		_a(d)["ability_cooldown"] = -1.0])
	rows.append([v, "Battle actor ability_auto must be a bool.", func(d: Dictionary) -> void:
		_a(d).erase("skills")
		_a(d).merge({"ability_cooldown": 0.0, "ability_auto": "yes"}, true)])
	rows.append([v, "Battle actor skills must be an Array and skill_cooldowns a Dictionary.", func(d: Dictionary) -> void: _a(d)["skills"] = "x"])
	rows.append([v, "Battle actor skills must be an Array and skill_cooldowns a Dictionary.", func(d: Dictionary) -> void: _a(d)["skill_cooldowns"] = []])
	rows.append([v, "Every battle actor skill must be {id, mode} Strings.", func(d: Dictionary) -> void: (_a(d)["skills"] as Array).append({"id": first_id})])
	rows.append([v, "Every battle actor skill must be {id, mode} Strings.", func(d: Dictionary) -> void: (_a(d)["skills"] as Array).append(3)])
	rows.append([v, "Battle actor skill nonexistent is unknown or from another class.", func(d: Dictionary) -> void: ((_a(d)["skills"] as Array)[0] as Dictionary)["id"] = "nonexistent"])
	rows.append([v, "Battle actor skill mage_rime_wall is unknown or from another class.", func(d: Dictionary) -> void: ((_a(d)["skills"] as Array)[0] as Dictionary)["id"] = "mage_rime_wall"])
	rows.append([v, "Battle actor skill %s mode is invalid." % first_id, func(d: Dictionary) -> void: ((_a(d)["skills"] as Array)[0] as Dictionary)["mode"] = "sometimes"])
	var passive_id: String = str(((base["skills"] as Array)[passive] as Dictionary)["id"])
	rows.append([v, "Battle actor skill %s mode is invalid." % passive_id, func(d: Dictionary) -> void: ((_a(d)["skills"] as Array)[passive] as Dictionary)["mode"] = "manual"])
	rows.append([v, "Battle actor skill %s is listed twice." % first_id, func(d: Dictionary) -> void: (_a(d)["skills"] as Array).append(((_a(d)["skills"] as Array)[0] as Dictionary).duplicate())])
	rows.append([v, "Battle actor skill_cooldowns must hold exactly its abilities.", func(d: Dictionary) -> void: (_a(d)["skill_cooldowns"] as Dictionary)["extra"] = 0.0])
	rows.append([v, "Battle actor skill_cooldowns must hold exactly its abilities.", func(d: Dictionary) -> void:
		(_a(d)["skill_cooldowns"] as Dictionary).erase(ability)
		(_a(d)["skill_cooldowns"] as Dictionary)["bogus"] = 0.0])
	rows.append([v, "Battle actor skill cooldowns must be finite and non-negative.", func(d: Dictionary) -> void: (_a(d)["skill_cooldowns"] as Dictionary)[ability] = -1.0])
	rows.append([v, "Battle actor ability_lock must be finite and non-negative.", func(d: Dictionary) -> void: _a(d)["ability_lock"] = -1.0])
	rows.append([v, "Battle actor combo_skill must be a String.", func(d: Dictionary) -> void: _a(d)["combo_skill"] = 3])
	rows.append([v, "Battle actor combo_tick must be a non-negative integer.", func(d: Dictionary) -> void: _a(d)["combo_tick"] = -1.0])
	rows.append([v, "Battle actor statuses must be an Array.", func(d: Dictionary) -> void: _a(d)["statuses"] = "x"])
	rows.append([v, "Every battle actor status must be {id, kind, source, remaining, magnitude}.", func(d: Dictionary) -> void: _a(d)["statuses"] = [{}]])
	rows.append([v, "Every battle actor status must be {id, kind, source, remaining, magnitude}.", func(d: Dictionary) -> void: _a(d)["statuses"] = [3]])
	for key: String in ["id", "kind", "source"]:
		rows.append([v, "Battle actor status %s must be a String." % key, func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({key: 3})]])
	rows.append([v, "Battle actor status id is empty or its kind is unknown.", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"id": ""})]])
	rows.append([v, "Battle actor status id is empty or its kind is unknown.", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"kind": "bogus"})]])
	var status_number: String = "Battle actor status %s must be finite and non-negative (a stat status's magnitude above -1)."
	rows.append([v, status_number % "remaining", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"remaining": -1.0})]])
	rows.append([v, status_number % "remaining", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"remaining": "x"})]])
	rows.append([v, status_number % "magnitude", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"magnitude": -0.5})]])
	rows.append([v, status_number % "magnitude", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"kind": "speed", "magnitude": -1.0})]])
	rows.append([v, "", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"kind": "speed", "magnitude": -0.5})]])
	rows.append([v, "Battle actor damage reduction cannot exceed one.", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({"magnitude": 1.5})]])
	rows.append([v, "Battle actor status guard is listed twice.", func(d: Dictionary) -> void: _a(d)["statuses"] = [_status({}), _status({"remaining": 2.0})]])
	return rows


func _effect_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	rows.append([v, "Battle actor effect_state must be a Dictionary.", func(d: Dictionary) -> void: _a(d)["effect_state"] = []])
	rows.append([v, "Battle actor elite effect flag must be a bool.", func(d: Dictionary) -> void: _fx(d)["elite"] = 1.0])
	for key: String in ["stun_remaining", "attack_windup_remaining", "attack_windup_total", "telegraph_radius", "telegraph_remaining", "telegraph_total"]:
		rows.append([v, "Battle actor effect %s must be finite and non-negative." % key, func(d: Dictionary) -> void: _fx(d)[key] = -1.0])
		rows.append([v, "Battle actor effect %s must be finite and non-negative." % key, func(d: Dictionary) -> void: _fx(d)[key] = "x"])
	rows.append([v, "Battle actor effect guard_remaining must be finite and non-negative.", func(d: Dictionary) -> void: _fx(d)["guard_remaining"] = -1.0])
	rows.append([v, "Battle actor effect guard_reduction must be finite and non-negative.", func(d: Dictionary) -> void: _fx(d)["guard_reduction"] = "x"])
	rows.append([v, "Battle actor guard_reduction cannot exceed one.", func(d: Dictionary) -> void: _fx(d)["guard_reduction"] = 1.5])
	for key: String in ["telegraph_skill", "last_skill_id", "telegraph_claimed_by"]:
		rows.append([v, "Battle actor effect %s must be a String." % key, func(d: Dictionary) -> void: _fx(d)[key] = 3])
	for key: String in ["last_hit_tick", "last_skill_tick"]:
		rows.append([v, "Battle actor effect %s must be a non-negative integer." % key, func(d: Dictionary) -> void: _fx(d)[key] = -1.0])
		rows.append([v, "Battle actor effect %s must be a non-negative integer." % key, func(d: Dictionary) -> void: _fx(d)[key] = 1.5])
	for key: String in ["last_counter_tick", "last_crit_tick", "last_push_tick", "kite_ready_tick"]:
		rows.append([v, "Battle actor effect %s must be a non-negative integer." % key, func(d: Dictionary) -> void: _fx(d)[key] = -1.0])
	rows.append([v, "Battle actor effect hit_from must contain two finite numbers.", func(d: Dictionary) -> void: _fx(d)["hit_from"] = [1.0]])
	for key: String in ["attack_target_id", "telegraph_kind"]:
		rows.append([v, "Battle actor effect %s must be a String." % key, func(d: Dictionary) -> void: _fx(d)[key] = 3])
	rows.append([v, "Battle actor effect attack_target_id must be a String.", func(d: Dictionary) -> void: _fx(d).erase("attack_target_id")])
	rows.append([v, "Battle actor telegraph_kind is invalid.", func(d: Dictionary) -> void: _fx(d)["telegraph_kind"] = "square"])
	for key: String in ["telegraph_origin", "telegraph_point", "home_position"]:
		rows.append([v, "Battle actor effect %s must contain two finite numbers." % key, func(d: Dictionary) -> void: _fx(d)[key] = [1.0]])
	rows.append([v, "Battle actor direct_order effect must be a bool.", func(d: Dictionary) -> void: _fx(d)["direct_order"] = 1.0])
	rows.append([v, "Battle actor carry_progress must be finite and non-negative.", func(d: Dictionary) -> void: _fx(d)["carry_progress"] = -1.0])
	for key: String in ["kite_point", "evade_point"]:
		rows.append([v, "Battle actor effect %s must contain two finite numbers." % key, func(d: Dictionary) -> void: _fx(d)[key] = [1.0]])
	rows.append([v, "Battle actor effect kite_point needs kite_ready_tick.", func(d: Dictionary) -> void:
		_fx(d).erase("kite_ready_tick")
		_fx(d)["kite_point"] = [0.0, 0.0]])
	rows.append([v, "Battle actor effect cover_order must be an Array of Strings.", func(d: Dictionary) -> void: _fx(d)["cover_order"] = [3]])
	rows.append([v, "Battle actor effect cover_order must be an Array of Strings.", func(d: Dictionary) -> void: _fx(d)["cover_order"] = "x"])
	return rows


## hero:a is a Knight. Its chains are checked against the class kit, not its bar, and never for length.
func _chain_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var shape: String = "Every battle actor chain must be {trigger, then}: a String and a non-empty Array of Strings."
	var rally_then_charge: Array = [{"trigger": "knight_rally", "then": ["knight_charge"]}]
	var running: Dictionary = {"chain_trigger": "knight_rally", "chain_step": 0.0, "chain_deadline_tick": 40.0, "chain_target": ""}
	var rows: Array[Array] = []
	rows.append([v, "", func(d: Dictionary) -> void: _a(d)["chains"] = rally_then_charge.duplicate(true)])
	rows.append([v, "", func(d: Dictionary) -> void: _a(d)["chains"] = [{"trigger": "knight_rally", "then": ["knight_charge", "knight_charge", "knight_charge", "knight_charge", "knight_charge", "knight_charge", "knight_charge", "knight_charge", "knight_charge"]}]])
	rows.append([v, "Battle actor chains must be an Array of {trigger, then}.", func(d: Dictionary) -> void: _a(d)["chains"] = "x"])
	rows.append([v, "Enemy battle actors cannot have chains.", func(d: Dictionary) -> void: _e(d)["chains"] = []])
	for bad: Variant in [3, {"trigger": "knight_rally"}, {"trigger": "knight_rally", "then": []}, {"trigger": 3, "then": ["knight_charge"]}, {"trigger": "knight_rally", "then": [3]}, {"trigger": "knight_rally", "then": ["knight_charge"], "extra": 1}]:
		rows.append([v, shape, func(d: Dictionary) -> void: _a(d)["chains"] = [bad]])
	for bad_id: String in ["knight_bulwark", "nonexistent", "mage_rime_wall"]:
		var problem: String = "Battle actor chain skill %s is unknown, a passive or from another class." % bad_id
		rows.append([v, problem, func(d: Dictionary) -> void: _a(d)["chains"] = [{"trigger": bad_id, "then": ["knight_charge"]}]])
		rows.append([v, problem, func(d: Dictionary) -> void: _a(d)["chains"] = [{"trigger": "knight_rally", "then": [bad_id]}]])
	rows.append([v, "Battle actor chain trigger knight_rally is listed twice.", func(d: Dictionary) -> void: _a(d)["chains"] = [{"trigger": "knight_rally", "then": ["knight_charge"]}, {"trigger": "knight_rally", "then": ["knight_ground_slam"]}]])
	rows.append([v, "", func(d: Dictionary) -> void:
		_a(d)["chains"] = rally_then_charge.duplicate(true)
		_fx(d).merge(running, true)])
	rows.append([v, "", func(d: Dictionary) -> void:
		_a(d)["chains"] = rally_then_charge.duplicate(true)
		_fx(d).merge(running, true)
		_fx(d)["chain_target"] = _e(d)["id"]])
	rows.append([v, "Battle actor references must target existing actors.", func(d: Dictionary) -> void:
		_a(d)["chains"] = rally_then_charge.duplicate(true)
		_fx(d).merge(running, true)
		_fx(d)["chain_target"] = "enemy:nobody"])
	for key: String in ["chain_trigger", "chain_step", "chain_deadline_tick", "chain_target"]:
		rows.append([v, "Battle actor chain state needs chain_trigger, chain_step, chain_deadline_tick and chain_target together.", func(d: Dictionary) -> void:
			_a(d)["chains"] = rally_then_charge.duplicate(true)
			_fx(d).merge(running, true)
			_fx(d).erase(key)])
	for key: String in ["chain_trigger", "chain_target"]:
		rows.append([v, "Battle actor effects chain_trigger and chain_target must be Strings.", func(d: Dictionary) -> void:
			_a(d)["chains"] = rally_then_charge.duplicate(true)
			_fx(d).merge(running, true)
			_fx(d)[key] = 3])
	rows.append([v, "Battle actor effect chain_trigger must name one of its chains.", func(d: Dictionary) -> void:
		_a(d)["chains"] = rally_then_charge.duplicate(true)
		_fx(d).merge(running, true)
		_fx(d)["chain_trigger"] = "knight_charge"])
	rows.append([v, "Battle actor effect chain_trigger must name one of its chains.", func(d: Dictionary) -> void: _fx(d).merge(running, true)])
	for step: Variant in [1.0, -1.0, 0.5, "x"]:
		rows.append([v, "Battle actor effect chain_step must be a non-negative integer inside its chain.", func(d: Dictionary) -> void:
			_a(d)["chains"] = rally_then_charge.duplicate(true)
			_fx(d).merge(running, true)
			_fx(d)["chain_step"] = step])
	for deadline: Variant in [-1.0, 1.5, "x"]:
		rows.append([v, "Battle actor effect chain_deadline_tick must be a non-negative integer.", func(d: Dictionary) -> void:
			_a(d)["chains"] = rally_then_charge.duplicate(true)
			_fx(d).merge(running, true)
			_fx(d)["chain_deadline_tick"] = deadline])
	return rows


func _snapshot_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	for key: String in ["simulation_version", "tick", "completed_waves", "command_sequence"]:
		rows.append([v, "Battle %s must be a non-negative integer." % key, func(d: Dictionary) -> void: d[key] = -1.0])
	rows.append([v, "Battle simulation_version is unsupported.", func(d: Dictionary) -> void: d["simulation_version"] = 99.0])
	for key: String in ["order_id", "zone_id", "kind", "status", "rng_state"]:
		rows.append([v, "Battle %s must be a String." % key, func(d: Dictionary) -> void: d[key] = 3])
	rows.append([v, "Battle order_id and zone_id must be non-empty.", func(d: Dictionary) -> void: d["order_id"] = ""])
	rows.append([v, "Battle order_id and zone_id must be non-empty.", func(d: Dictionary) -> void: d["zone_id"] = ""])
	rows.append([v, "Battle zone_id is unknown.", func(d: Dictionary) -> void: d["zone_id"] = "missing_zone"])
	rows.append([v, "Battle kind or status is invalid.", func(d: Dictionary) -> void: d["kind"] = "bogus"])
	rows.append([v, "Battle kind or status is invalid.", func(d: Dictionary) -> void: d["status"] = "bogus"])
	rows.append([v, "Battle rng_state must be a signed decimal int64 string.", func(d: Dictionary) -> void: d["rng_state"] = "abc"])
	for key: String in ["tick_remainder", "elapsed_seconds", "max_seconds"]:
		rows.append([v, "Battle %s must be finite." % key, func(d: Dictionary) -> void: d[key] = "x"])
	rows.append([v, "Battle tick_remainder is outside the logical tick.", func(d: Dictionary) -> void: d["tick_remainder"] = -0.01])
	rows.append([v, "Battle tick_remainder is outside the logical tick.", func(d: Dictionary) -> void: d["tick_remainder"] = BALANCE.battle_tick_seconds])
	rows.append([v, "Battle elapsed/max time is invalid.", func(d: Dictionary) -> void: d["max_seconds"] = 0.0])
	rows.append([v, "Battle elapsed/max time is invalid.", func(d: Dictionary) -> void: d["elapsed_seconds"] = float(d["max_seconds"]) + 1.0])
	rows.append([v, "Battle pace must be an integer from 1 to %d." % BattleSimulation.MAX_PACE, func(d: Dictionary) -> void: d["pace"] = 0.0])
	rows.append([v, "Battle max_seconds exceeds the authored zone bound.", func(d: Dictionary) -> void: d["max_seconds"] = 1000000.0])
	rows.append([v, "Battle completed_waves exceeds the authored encounter count.", func(d: Dictionary) -> void: d["completed_waves"] = 99.0])
	rows.append([v, "Battle tick and elapsed_seconds are inconsistent.", func(d: Dictionary) -> void: d["elapsed_seconds"] = float(d["elapsed_seconds"]) + 0.05])
	for key: String in ["actors", "squads", "downed_ever_ids", "extracted_ids"]:
		rows.append([v, "Battle %s must be an Array." % key, func(d: Dictionary) -> void: d[key] = "x"])
	for key: String in ["objective_state", "supplies_remaining", "policies"]:
		rows.append([v, "Battle %s must be a Dictionary." % key, func(d: Dictionary) -> void: d[key] = []])
	rows.append([v, "Every battle actor must be a Dictionary.", func(d: Dictionary) -> void: (d["actors"] as Array).append(3)])
	return rows


func _link_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	rows.append([v, "Battle actor IDs and spawn indices must be unique.", func(d: Dictionary) -> void: _b(d)["id"] = _a(d)["id"]])
	rows.append([v, "Battle actor IDs and spawn indices must be unique.", func(d: Dictionary) -> void: _b(d)["spawn_index"] = _a(d)["spawn_index"]])
	rows.append([v, "Battle actor positions must remain inside the authored bounds.", func(d: Dictionary) -> void: _a(d)["position"] = [99.0, 0.0]])
	rows.append([v, "Battle actor positions must remain inside the authored bounds.", func(d: Dictionary) -> void: _a(d)["order_point"] = [0.0, -99.0]])
	rows.append([v, "Battle actor home positions must remain inside the authored bounds.", func(d: Dictionary) -> void: _fx(d)["home_position"] = [99.0, 0.0]])
	rows.append([v, "Battle hero IDs must be unique.", func(d: Dictionary) -> void: _b(d)["hero_id"] = _a(d)["hero_id"]])
	for key: String in ["last_hit_tick", "last_skill_tick", "last_crit_tick", "last_push_tick"]:
		rows.append([v, "Battle effect timestamps cannot be ahead of the simulation tick.", func(d: Dictionary) -> void: _fx(d)[key] = float(d["tick"]) + 1.0])
	rows.append([v, "A battle actor cannot carry and be carried simultaneously.", func(d: Dictionary) -> void: _a(d).merge({"carried_by_id": "x", "carrying_id": "y"}, true)])
	rows.append([v, "Battle carry links must be mutual and reference existing actors.", func(d: Dictionary) -> void: _a(d)["carried_by_id"] = "ghost"])
	rows.append([v, "Battle carry links must be mutual and reference existing actors.", func(d: Dictionary) -> void: _a(d)["carried_by_id"] = _b(d)["id"]])
	rows.append([v, "Only a living same-faction actor can carry a downed actor.", func(d: Dictionary) -> void:
		_a(d)["carried_by_id"] = _b(d)["id"]
		_b(d)["carrying_id"] = _a(d)["id"]])
	rows.append([v, "Only a living same-faction actor can carry a downed actor.", func(d: Dictionary) -> void:
		_a(d).merge({"carried_by_id": _e(d)["id"], "life": "downed", "hp": 0.0}, true)
		_e(d)["carrying_id"] = _a(d)["id"]])
	rows.append([v, "Battle carry links must be mutual and reference existing actors.", func(d: Dictionary) -> void: _a(d)["carrying_id"] = "ghost"])
	rows.append([v, "Battle carry links must be mutual and reference existing actors.", func(d: Dictionary) -> void: _a(d)["carrying_id"] = _b(d)["id"]])
	rows.append([v, "Only a living actor can carry a same-faction downed actor.", func(d: Dictionary) -> void:
		_a(d)["carrying_id"] = _b(d)["id"]
		_b(d)["carried_by_id"] = _a(d)["id"]])
	rows.append([v, "Only a living actor can carry a same-faction downed actor.", func(d: Dictionary) -> void:
		_a(d)["carrying_id"] = _e(d)["id"]
		_e(d)["carried_by_id"] = _a(d)["id"]])
	rows.append([v, "", func(d: Dictionary) -> void:
		_a(d)["carrying_id"] = _b(d)["id"]
		_b(d).merge({"carried_by_id": _a(d)["id"], "life": "downed", "hp": 0.0}, true)])
	for key: String in ["order_target_id", "guard_target_id"]:
		rows.append([v, "Battle actor references must target existing actors.", func(d: Dictionary) -> void: _a(d)[key] = "ghost"])
	return rows


func _squad_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	rows.append([v, "Battle supplies: an unknown supply kind.", func(d: Dictionary) -> void: (d["supplies_remaining"] as Dictionary)["gold"] = 1.0])
	rows.append([v, "Battle supplies: healing is missing.", func(d: Dictionary) -> void: (d["supplies_remaining"] as Dictionary).erase("healing")])
	rows.append([v, "Battle supplies: healing must be a non-negative integer up to %d." % BALANCE.battle_supply_allocation_cap, func(d: Dictionary) -> void: (d["supplies_remaining"] as Dictionary)["healing"] = -1.0])
	rows.append([v, "Battle supplies: revival must be a non-negative integer up to %d." % BALANCE.battle_supply_allocation_cap, func(d: Dictionary) -> void: (d["supplies_remaining"] as Dictionary)["revival"] = float(BALANCE.battle_supply_allocation_cap + 1)])
	for key: String in ["auto_battle", "auto_heal", "auto_revive", "reserve_last_revival", "retreat_when_supplies_empty"]:
		rows.append([v, "Battle policy %s must be a bool." % key, func(d: Dictionary) -> void: (d["policies"] as Dictionary)[key] = 1.0])
	rows.append([v, "Battle default_stance is invalid.", func(d: Dictionary) -> void: (d["policies"] as Dictionary)["default_stance"] = "bogus"])
	rows.append([v, "Battle heal_below must be between zero and one.", func(d: Dictionary) -> void: (d["policies"] as Dictionary)["heal_below"] = 2.0])
	rows.append([v, "Battle ability_auto policy must be a Dictionary.", func(d: Dictionary) -> void: (d["policies"] as Dictionary)["ability_auto"] = []])
	rows.append([v, "Every per-hero ability_auto value must be a bool.", func(d: Dictionary) -> void: (d["policies"] as Dictionary)["ability_auto"] = {"hero:a": 1.0}])
	rows.append([v, "Every battle squad must be a Dictionary.", func(d: Dictionary) -> void: (d["squads"] as Array).append(3)])
	for key: String in ["id", "name", "stance", "guard_target_id"]:
		rows.append([v, "Battle squad %s must be a String." % key, func(d: Dictionary) -> void: _squad(d)[key] = 3])
	rows.append([v, "Battle squad IDs must be unique and non-empty.", func(d: Dictionary) -> void: _squad(d)["id"] = ""])
	rows.append([v, "Battle squad IDs must be unique and non-empty.", func(d: Dictionary) -> void: (d["squads"] as Array).append(_squad(d).duplicate(true))])
	rows.append([v, "Battle squad stance is invalid.", func(d: Dictionary) -> void: _squad(d)["stance"] = "bogus"])
	rows.append([v, "Battle squad stance_anchor must contain two finite numbers.", func(d: Dictionary) -> void: _squad(d)["stance_anchor"] = [1.0]])
	rows.append([v, "Battle squads must contain one to five hero IDs.", func(d: Dictionary) -> void: _squad(d)["hero_ids"] = []])
	rows.append([v, "Battle squads must contain one to five hero IDs.", func(d: Dictionary) -> void: _squad(d)["hero_ids"] = "x"])
	rows.append([v, "Battle squad hero IDs must be unique deployed heroes.", func(d: Dictionary) -> void: (_squad(d)["hero_ids"] as Array).append("ghost")])
	rows.append([v, "Battle squad hero IDs must be unique deployed heroes.", func(d: Dictionary) -> void: (_squad(d)["hero_ids"] as Array).append("hero:a")])
	rows.append([v, "Battle hero squad_id must match squad membership.", func(d: Dictionary) -> void: _a(d)["squad_id"] = "squad:9"])
	rows.append([v, "Battle squad guard_target_id must reference a living allied actor.", func(d: Dictionary) -> void: _squad(d)["guard_target_id"] = "ghost"])
	rows.append([v, "Battle squad guard_target_id must reference a living allied actor.", func(d: Dictionary) -> void:
		_squad(d)["guard_target_id"] = _a(d)["id"]
		_a(d).merge({"life": "downed", "hp": 0.0}, true)])
	rows.append([v, "Every deployed hero must belong to one battle squad.", func(d: Dictionary) -> void:
		_a(d)["squad_id"] = ""
		(_squad(d)["hero_ids"] as Array).erase("hero:a")])
	rows.append([v, "Battle hero squad_id must match squad membership.", func(d: Dictionary) -> void: (_squad(d)["hero_ids"] as Array).erase("hero:b")])
	for key: String in ["downed_ever_ids", "extracted_ids"]:
		rows.append([v, "Battle %s must contain unique non-empty Strings." % key, func(d: Dictionary) -> void: d[key] = [3]])
		rows.append([v, "Battle %s must contain unique non-empty Strings." % key, func(d: Dictionary) -> void: d[key] = [""]])
		rows.append([v, "Battle %s must reference deployed heroes." % key, func(d: Dictionary) -> void: d[key] = ["ghost"]])
	rows.append([v, "Battle downed_ever_ids must contain unique non-empty Strings.", func(d: Dictionary) -> void: d["downed_ever_ids"] = ["hero:a", "hero:a"]])
	rows.append([v, "Battle extracted_ids must match extracted hero actors.", func(d: Dictionary) -> void: d["extracted_ids"] = ["hero:a"]])
	rows.append([v, "Battle extracted hero actors must appear in extracted_ids.", func(d: Dictionary) -> void: _a(d)["life"] = "extracted"])
	return rows


func _field_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var shape: String = "Every battle field object must be a zone {id, kind, skill_id, owner_actor_id, faction, center, radius, remaining_seconds, atk, heal_scale} or a wall {id, kind, skill_id, owner_actor_id, faction, start, end, thickness, remaining_seconds}."
	var rows: Array[Array] = []
	rows.append([v, "Battle field_sequence must be a non-negative integer.", func(d: Dictionary) -> void: d["field_sequence"] = -1.0])
	rows.append([v, "Battle field_objects must be an Array.", func(d: Dictionary) -> void: d["field_objects"] = "x"])
	rows.append([v, shape, func(d: Dictionary) -> void: _fields(d, [3])])
	rows.append([v, shape, func(d: Dictionary) -> void:
		var zone: Dictionary = _zone_object(d)
		zone.erase("atk")
		_fields(d, [zone])])
	rows.append([v, shape, func(d: Dictionary) -> void:
		var wall: Dictionary = _wall_object(d)
		wall["extra"] = 1.0
		_fields(d, [wall])])
	rows.append([v, shape, func(d: Dictionary) -> void:
		var wall: Dictionary = _wall_object(d)
		wall["kind"] = "zone"
		_fields(d, [wall])])
	# Not "kind": a non-String kind never reaches this check. The shape check's get("kind") == "wall" is a
	# script error on a number, and the validator returns "" (a finding at HEAD, reported with ig-7sn.10).
	for key: String in ["id", "skill_id", "owner_actor_id", "faction"]:
		rows.append([v, "Battle field object %s must be a String." % key, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({key: 3}, true)])])
	var ids: String = "Battle field object ids must be unique, field:<1 to field_sequence>."
	for bad: String in ["field:9", "field:0", "zone:1", "field:01", "field:x"]:
		rows.append([v, ids, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({"id": bad}, true)])])
	rows.append([v, ids, func(d: Dictionary) -> void: _fields(d, [_zone_object(d), _wall_object(d).merged({"id": "field:1"}, true)])])
	var owner_error: String = "Battle field object kind, faction or owner is invalid."
	rows.append([v, owner_error, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({"kind": "blob"}, true)])])
	rows.append([v, owner_error, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({"faction": "neutral"}, true)])])
	rows.append([v, owner_error, func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({"owner_actor_id": "ghost"}, true)])])
	rows.append([v, "Battle wall ends must remain inside the authored bounds.", func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({"start": [99.0, 0.0]}, true)])])
	rows.append([v, "Battle wall ends must remain inside the authored bounds.", func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({"end": [1.0]}, true)])])
	rows.append([v, "Battle wall ends must differ.", func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({"end": [0.0, 0.0]}, true)])])
	for key: String in ["thickness", "remaining_seconds"]:
		rows.append([v, "Battle wall %s must be finite and positive." % key, func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({key: 0.0}, true)])])
		rows.append([v, "Battle wall %s must be finite and positive." % key, func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({key: "x"}, true)])])
	rows.append([v, "Battle wall thickness must fit the authored bounds.", func(d: Dictionary) -> void: _fields(d, [_wall_object(d).merged({"thickness": 41.0}, true)])])
	rows.append([v, "Battle field object centers must remain inside the authored bounds.", func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({"center": [99.0, 0.0]}, true)])])
	for key: String in ["radius", "remaining_seconds", "atk", "heal_scale"]:
		rows.append([v, "Battle field object %s must be finite and non-negative." % key, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({key: -1.0}, true)])])
		rows.append([v, "Battle field object %s must be finite and non-negative." % key, func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({key: "x"}, true)])])
	for key: String in ["radius", "remaining_seconds"]:
		rows.append([v, "Battle field object radius and remaining_seconds must be positive.", func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({key: 0.0}, true)])])
	rows.append([v, "Battle zone radius must fit the authored bounds.", func(d: Dictionary) -> void: _fields(d, [_zone_object(d).merged({"radius": 41.0}, true)])])
	return rows


func _objective_rows() -> Array[Array]:
	var v: String = "verdant_outskirts"
	var rows: Array[Array] = []
	rows.append([v, "Battle objective kind must match the authored zone.", func(d: Dictionary) -> void: _objective(d)["battle_kind"] = "raid"])
	rows.append([v, "Battle objective kind must match the authored zone.", func(d: Dictionary) -> void: _objective(d)["battle_kind"] = 3])
	rows.append([v, "Battle objective bounds must match the authored zone.", func(d: Dictionary) -> void: _objective(d)["bounds"] = 99.0])
	rows.append([v, "Battle objective exit must match the authored zone.", func(d: Dictionary) -> void: _objective(d)["exit_position"] = [5.0, 5.0]])
	rows.append([v, "Battle objective cart_position must contain two finite numbers.", func(d: Dictionary) -> void: _objective(d)["cart_position"] = [1.0]])
	rows.append(["frontier_march", "Battle objective cart_position must remain inside the authored bounds.", func(d: Dictionary) -> void: _objective(d)["cart_position"] = [99.0, 0.0]])
	rows.append([v, "Battle objective escort_index is invalid.", func(d: Dictionary) -> void: _objective(d)["escort_index"] = -1.0])
	rows.append([v, "Battle objective escort_index is invalid.", func(d: Dictionary) -> void: _objective(d)["escort_index"] = 1.0])
	for key: String in ["escort_active", "boss_spawned"]:
		rows.append([v, "Battle objective %s must be a bool." % key, func(d: Dictionary) -> void: _objective(d)[key] = 1.0])
	rows.append([v, "Battle objective hold time must be finite.", func(d: Dictionary) -> void: _objective(d)["simultaneous_hold_seconds"] = "x"])
	rows.append([v, "Battle objective hold time is outside its authored range.", func(d: Dictionary) -> void: _objective(d)["simultaneous_hold_seconds"] = -1.0])
	rows.append(["fallen_citadel", "Battle objective hold time is outside its authored range.", func(d: Dictionary) -> void: _objective(d)["simultaneous_hold_seconds"] = 1000000.0])
	rows.append([v, "Only a raid objective can have a spawned boss.", func(d: Dictionary) -> void: _objective(d)["boss_spawned"] = true])
	rows.append(["fallen_citadel", "A raid boss requires completed simultaneous capture.", func(d: Dictionary) -> void: _objective(d)["boss_spawned"] = true])
	rows.append([v, "Battle objective markers must be an Array.", func(d: Dictionary) -> void: _objective(d)["markers"] = "x"])
	rows.append([v, "Battle objective markers must match the authored zone.", func(d: Dictionary) -> void: (_objective(d)["markers"] as Array).clear()])
	rows.append([v, "Every objective marker must be a Dictionary.", func(d: Dictionary) -> void: (_objective(d)["markers"] as Array)[0] = 3])
	for key: String in ["id", "kind", "label"]:
		rows.append([v, "Objective marker %s must be a String." % key, func(d: Dictionary) -> void: _marker(d)[key] = 3])
	rows.append([v, "Objective marker IDs must be unique and non-empty.", func(d: Dictionary) -> void: _marker(d)["id"] = "bogus"])
	rows.append(["fallen_citadel", "Objective marker IDs must be unique and non-empty.", func(d: Dictionary) -> void: ((_objective(d)["markers"] as Array)[1] as Dictionary)["id"] = "exit"])
	rows.append([v, "Objective marker kinds must match the authored zone.", func(d: Dictionary) -> void: _marker(d)["kind"] = "camp"])
	for key: String in ["position", "radius", "progress"]:
		rows.append([v, "Objective marker geometry/progress must be finite.", func(d: Dictionary) -> void: _marker(d)[key] = "x"])
	rows.append([v, "Objective marker radius/progress is outside its range.", func(d: Dictionary) -> void: _marker(d)["radius"] = -1.0])
	rows.append([v, "Objective marker radius/progress is outside its range.", func(d: Dictionary) -> void: _marker(d)["progress"] = 2.0])
	rows.append([v, "Objective marker positions must remain inside the authored bounds.", func(d: Dictionary) -> void: _marker(d)["position"] = [99.0, 0.0]])
	rows.append([v, "Objective marker positions must match objective state.", func(d: Dictionary) -> void: _marker(d)["position"] = [1.0, 1.0]])
	rows.append(["frontier_march", "Objective marker positions must match objective state.", func(d: Dictionary) -> void: _objective(d)["cart_position"] = [1.0, 1.0]])
	for key: String in ["active", "complete"]:
		rows.append([v, "Objective marker state must be bool.", func(d: Dictionary) -> void: _marker(d)[key] = 1.0])
	return rows


## A battle as the save's parse gives it: two heroes in one squad (a Knight and a Cleric), a moment in,
## so the first wave is out.
func _base(zone_id: String) -> Dictionary:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(StringName(zone_id))
	var heroes: Array[Dictionary] = [
		{"hero_id": "hero:a", "archetype": "knight", "hp": 2000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.1, "crit_damage": 1.5, "squad_id": "squad:0"},
		{"hero_id": "hero:b", "archetype": "cleric", "hp": 2000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.1, "crit_damage": 1.5, "squad_id": "squad:0"},
	]
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ["hero:a", "hero:b"], "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("order:table:%s" % zone_id, heroes, zone, squads, {}, {"healing": 1, "revival": 1}, 11)
	BattleSimulation.advance(state, 1.0)
	return JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)) as Dictionary


func _enemy_index(data: Dictionary) -> int:
	var actors: Array = data["actors"] as Array
	for index: int in actors.size():
		if str((actors[index] as Dictionary)["faction"]) == "enemy":
			return index
	return -1


func _hero_actor(data: Dictionary, hero_id: String) -> Dictionary:
	for actor: Variant in data["actors"] as Array:
		if actor is Dictionary and str((actor as Dictionary).get("hero_id")) == hero_id:
			return actor as Dictionary
	return {}


func _a(data: Dictionary) -> Dictionary:
	return _hero_actor(data, "hero:a")


func _b(data: Dictionary) -> Dictionary:
	return _hero_actor(data, "hero:b")


func _e(data: Dictionary) -> Dictionary:
	return (data["actors"] as Array)[_enemy_index(data)] as Dictionary


func _fx(data: Dictionary) -> Dictionary:
	return _a(data)["effect_state"] as Dictionary


func _squad(data: Dictionary) -> Dictionary:
	return (data["squads"] as Array)[0] as Dictionary


func _objective(data: Dictionary) -> Dictionary:
	return data["objective_state"] as Dictionary


func _marker(data: Dictionary) -> Dictionary:
	return (_objective(data)["markers"] as Array)[0] as Dictionary


## A valid damage_reduction status, with overrides.
func _status(overrides: Dictionary) -> Dictionary:
	return {"id": "guard", "kind": "damage_reduction", "source": "hero:a", "remaining": 1.0, "magnitude": 0.5}.merged(overrides, true)


func _zone_object(data: Dictionary) -> Dictionary:
	return {"id": "field:1", "kind": "zone", "skill_id": "mage_rime_circle", "owner_actor_id": str(_a(data)["id"]), "faction": "ally", "center": [0.0, 0.0], "radius": 2.0, "remaining_seconds": 3.0, "atk": 10.0, "heal_scale": 0.0}


func _wall_object(data: Dictionary) -> Dictionary:
	return {"id": "field:2", "kind": "wall", "skill_id": "mage_rime_wall", "owner_actor_id": str(_a(data)["id"]), "faction": "ally", "start": [0.0, 0.0], "end": [2.0, 0.0], "thickness": 0.5, "remaining_seconds": 3.0}


func _fields(data: Dictionary, objects: Array) -> void:
	data["field_sequence"] = 2.0
	data["field_objects"] = objects


func _with_fields(base: Dictionary) -> Dictionary:
	var data: Dictionary = base.duplicate(true)
	_fields(data, [_zone_object(data), _wall_object(data)])
	return data
