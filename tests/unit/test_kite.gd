extends GutTest
## ig-uu7.3 Kiting (SYSTEMS.md § Hero AI on auto): a back-row hero hops once toward its tank when an
## enemy on it closes in, then fights out the cooldown.

const BALANCE: BalanceTable = preload("res://balance.tres")


func test_a_ranger_hops_toward_its_knight_and_the_knight_pulls_the_enemy() -> void:
	var state: BattleState = _run([["knight", Vector2(2, -4)], ["ranger", Vector2(0, 0)]], 1)
	var knight: BattleActor = state.actors[0]
	var ranger: BattleActor = state.actors[1]
	var enemy: BattleActor = _lock(_melee(state)[0], Vector2(0, 2.5), ranger)
	var apart: float = ranger.position.distance_to(knight.position)
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("kite_point") is Array, "the enemy closed in, so the ranger hops")
	assert_eq(int(ranger.effect_state["kite_ready_tick"]), state.tick + ceili(BALANCE.battle_kite_cooldown_seconds / BALANCE.battle_tick_seconds), "and its next hop is a cooldown away")
	assert_eq(ranger.order_kind, BattleSimulation.COMMAND_MOVE)
	var landed: float = -1.0
	var pulled: bool = false
	for _tick: int in int(10.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		if landed < 0.0 and not ranger.effect_state.has("kite_point"):
			landed = ranger.position.distance_to(knight.position)
		if enemy.order_target_id == knight.id:
			pulled = true
			break
	assert_between(landed, 0.0, apart - 1.0, "the hop ended nearer the knight than the ranger began")
	assert_true(pulled, "the knight pulled the enemy off the ranger")


func test_a_cornered_ranger_stands_and_keeps_its_hop() -> void:
	var state: BattleState = _run([["ranger", Vector2(0, -19.5)]], 1)
	var ranger: BattleActor = state.actors[0]
	_lock(_melee(state)[0], Vector2(0, -17.5), ranger)
	ranger.effect_state["kite_ready_tick"] = 0
	for _tick: int in int(2.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_false(ranger.effect_state.has("kite_point"), "tick %d: a hop into the wall is no hop" % state.tick)
	assert_eq(ranger.effect_state["kite_ready_tick"], 0, "the hop was never spent")


func test_a_slow_hop_lined_up_behind_its_knight_still_ends_within_its_cap() -> void:
	# At the slowest pace (1.5 u/s, the enemy's own) knight, ranger and enemy in one line pinned the
	# hop short of its point for good, and the ranger never shot.
	var state: BattleState = _run([["knight", Vector2(0, -4)], ["ranger", Vector2(0, 0)]], 1)
	var ranger: BattleActor = state.actors[1]
	for hero: BattleActor in [state.actors[0], ranger]:
		hero.move_speed = BALANCE.battle_move_speed_min
	_lock(_melee(state)[0], Vector2(0, 2.5), ranger)
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("kite_point") is Array, "hopping")
	var started: int = state.tick
	var longest: int = ceili(BALANCE.battle_kite_distance / (ranger.move_speed * BALANCE.battle_tick_seconds)) + 1
	var ended: int = -1
	for _tick: int in longest + 5:
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		if not ranger.effect_state.has("kite_point"):
			ended = state.tick
			break
	assert_between(ended - started, 1, longest, "the hop ends by its cap")
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_ne(ranger.order_kind, BattleSimulation.COMMAND_MOVE, "and the ranger goes back to fighting")


func test_a_60_second_chase_hops_at_most_once_a_cooldown() -> void:
	var state: BattleState = _run([["ranger", Vector2(-3, 0)], ["mage", Vector2(3, 0)]], 1)
	var heroes: Array[BattleActor] = [state.actors[0], state.actors[1]]
	var enemies: Array[BattleActor] = _melee(state)
	_lock(enemies[0], Vector2(-3, 2.5), heroes[0])
	_lock(enemies[1], Vector2(3, 2.5), heroes[1])
	var hops: Array[int] = [0, 0]
	var ready: Array[int] = [0, 0]
	for _tick: int in int(60.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		for index: int in heroes.size():
			var now: int = int(heroes[index].effect_state.get("kite_ready_tick", 0))
			if now != ready[index]:
				hops[index] += 1
				ready[index] = now
	var cap: int = ceili(60.0 / BALANCE.battle_kite_cooldown_seconds)
	for index: int in heroes.size():
		assert_between(hops[index], 1, cap, "%s hopped %d times" % [heroes[index].archetype, hops[index]])


func test_a_cleric_never_hops() -> void:
	var state: BattleState = _run([["knight", Vector2(0, -4)], ["cleric", Vector2(0, 0)]], 1)
	var cleric: BattleActor = state.actors[1]
	_lock(_melee(state)[0], Vector2(0, 2.0), cleric)
	for _tick: int in int(5.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_false(cleric.effect_state.has("kite_point"), "tick %d" % state.tick)


func test_an_evade_during_a_hop_cancels_it_and_keeps_the_cooldown_spent() -> void:
	var state: BattleState = _run([["ranger", Vector2(0, 0)]], 1)
	var ranger: BattleActor = state.actors[0]
	var enemy: BattleActor = _lock(_melee(state)[0], Vector2(0, 2.5), ranger)
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("kite_point") is Array, "hopping")
	var ready: int = int(ranger.effect_state["kite_ready_tick"])
	# Another enemy telegraphs a circle on the ranger.
	var caster: BattleActor = _melee(state)[1]
	caster.effect_state["telegraph_kind"] = "circle"
	caster.effect_state["telegraph_point"] = [ranger.position.x, ranger.position.y]
	caster.effect_state["telegraph_origin"] = [ranger.position.x, ranger.position.y]
	caster.effect_state["telegraph_radius"] = 3.0
	caster.effect_state["telegraph_remaining"] = 1.0
	caster.effect_state["telegraph_total"] = 1.0
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("evade_point") is Array, "the ranger evades")
	assert_false(ranger.effect_state.has("kite_point"), "which cancels the hop")
	assert_eq(int(ranger.effect_state["kite_ready_tick"]), ready, "and the cooldown stays spent")
	assert_eq(enemy.order_target_id, ranger.id)


func test_a_hop_saved_mid_flight_reloads_and_lands_exactly_where_it_would_have() -> void:
	var run_on: BattleState = _hopping()
	var reloaded: BattleState = _through_save_json(_hopping())
	assert_eq(reloaded.actors[0].effect_state["kite_point"], run_on.actors[0].effect_state["kite_point"])
	assert_eq(reloaded.actors[0].effect_state["kite_ready_tick"], run_on.actors[0].effect_state["kite_ready_tick"])
	for _tick: int in int(3.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(run_on, BALANCE.battle_tick_seconds)
		BattleSimulation.advance(reloaded, BALANCE.battle_tick_seconds)
		for index: int in run_on.actors.size():
			assert_eq(reloaded.actors[index].position, run_on.actors[index].position, "tick %d actor %d" % [run_on.tick, index])


func test_a_legacy_snapshot_without_the_keys_loads_and_hops() -> void:
	var state: BattleState = _run([["knight", Vector2(0, -4)], ["ranger", Vector2(0, 0)]], 1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for actor_data: Dictionary in data["actors"]:
		(actor_data["effect_state"] as Dictionary).erase("kite_point")
		(actor_data["effect_state"] as Dictionary).erase("kite_ready_tick")
	assert_eq(BattleSimulation.validate_snapshot(data), "")
	var loaded: BattleState = BattleState.from_dict(data)
	var ranger: BattleActor = loaded.actors[1]
	_lock(_melee(loaded)[0], Vector2(0, 2.5), ranger)
	BattleSimulation.advance(loaded, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("kite_point") is Array, "a legacy hero hops at once")


func test_malformed_kite_and_evade_keys_are_refused_at_load() -> void:
	var clean: Dictionary = JSON.parse_string(JSON.stringify(_hopping().to_dict()))
	assert_eq(BattleSimulation.validate_snapshot(clean), "")
	for bad: Array in [["kite_point", [1.0]], ["kite_point", "0,0"], ["kite_point", [1.0, INF]], ["kite_ready_tick", -1], ["kite_ready_tick", 2.5], ["kite_ready_tick", "5"], ["evade_point", [0.0]], ["evade_point", [NAN, 0.0]]]:
		var data: Dictionary = clean.duplicate(true)
		(data["actors"][0]["effect_state"] as Dictionary)[bad[0]] = bad[1]
		assert_ne(BattleSimulation.validate_snapshot(data), "", "%s = %s is refused" % bad)
	var orphan: Dictionary = clean.duplicate(true)
	(orphan["actors"][0]["effect_state"] as Dictionary).erase("kite_ready_tick")
	assert_ne(BattleSimulation.validate_snapshot(orphan), "", "a hop in flight without its ready tick is refused")


func test_a_loaded_zero_speed_hop_keeps_a_finite_cap() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify(_hopping().to_dict()))
	data["actors"][0]["move_speed"] = 0.0
	assert_eq(BattleSimulation.validate_snapshot(data), "")
	var state: BattleState = BattleState.from_dict(data)
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(state.actors[0].effect_state.get("kite_point") is Array, "the cap is counted at the slowest real pace, not cut to nothing")


func test_a_new_run_clears_a_carried_hop() -> void:
	var old: BattleState = _hopping()
	var snapshot: Dictionary = old.actors[0].to_dict()
	(snapshot["effect_state"] as Dictionary)["kite_ready_tick"] = 900
	var state: BattleState = BattleSimulation.create_run("order:uu73:next", [snapshot], _zone(), old.squads, {}, {"healing": 0, "revival": 0}, 13)
	var ranger: BattleActor = state.actors[0]
	assert_false(ranger.effect_state.has("kite_point"))
	assert_false(ranger.effect_state.has("kite_ready_tick"))
	_park(state)
	ranger.position = Vector2.ZERO
	_lock(_melee(state)[0], Vector2(0, 2.5), ranger)
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(ranger.effect_state.get("kite_point") is Array, "the hop is ready at the start of the new run")


## A lone ranger one tick into a hop away from an enemy on it.
func _hopping() -> BattleState:
	var state: BattleState = _run([["ranger", Vector2(0, 0)]], 1)
	_lock(_melee(state)[0], Vector2(0, 2.5), state.actors[0])
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(state.actors[0].effect_state.get("kite_point") is Array, "hopping")
	return state


func _through_save_json(state: BattleState) -> BattleState:
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	assert_eq(BattleSimulation.validate_snapshot(data), "")
	return BattleState.from_dict(data)


func _lock(enemy: BattleActor, point: Vector2, victim: BattleActor) -> BattleActor:
	enemy.position = point
	enemy.effect_state["home_position"] = [point.x, point.y]
	enemy.order_kind = BattleSimulation.COMMAND_ATTACK
	enemy.order_target_id = victim.id
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	enemy.atk = 1.0
	return enemy


func _enemies(state: BattleState) -> Array[BattleActor]:
	var enemies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			enemies.append(actor)
	return enemies


## The melee enemies (the kind that walks up and trips a hop); ranged ones stop at 8.
func _melee(state: BattleState) -> Array[BattleActor]:
	var melee: Array[BattleActor] = []
	for enemy: BattleActor in _enemies(state):
		if enemy.attack_range < BALANCE.battle_kite_trigger_range:
			melee.append(enemy)
	return melee


## Enemies no test has placed wait far off, inside the zone's 20-unit bounds.
func _park(state: BattleState) -> void:
	for enemy: BattleActor in _enemies(state):
		_lock(enemy, Vector2(float(enemy.spawn_index % 3) * 2.0 - 2.0, 19.0), state.actors[0])
		enemy.order_kind = ""
		enemy.order_target_id = ""


## heroes: [archetype, position] pairs in one Advance squad, at speed 100 (4 u/s, a real hero's pace;
## the design's hop math assumes 3.8 or more). Four enemies (two of them melee), parked.
func _run(heroes: Array, level: int) -> BattleState:
	var snapshots: Array[Dictionary] = []
	var ids: Array[String] = []
	for index: int in heroes.size():
		var id: String = "hero:%d" % index
		ids.append(id)
		var point: Vector2 = heroes[index][1]
		snapshots.append({"hero_id": id, "archetype": heroes[index][0], "level": level, "hp": 4000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0", "position": [point.x, point.y]})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ids, "stance": "advance", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("order:uu73", snapshots, _zone(), squads, {}, {"healing": 0, "revival": 0}, 13)
	_park(state)
	return state


func _zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = 20
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.9
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 4
	zone.max_battle_seconds = 120.0
	zone.exit_position = Vector2(0, -16)
	return zone
