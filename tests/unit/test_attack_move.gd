extends GutTest
## ig-ap2: a direct attack-move keeps its point, fights what it meets on the way, then ends on arrival.

const BALANCE: BalanceTable = preload("res://balance.tres")
const POINT := Vector2(6.0, -12.0)


func test_an_attack_move_fights_on_the_way_and_keeps_its_point() -> void:
	for auto_battle: bool in [true, false]:
		var state: BattleState = _run(auto_battle)
		var hero: BattleActor = state.actors[0]
		var enemy: BattleActor = _enemy(state)
		# Far from the hero at first, then on its path.
		enemy.position = Vector2(0.0, 8.0)
		enemy.atk = 1.0
		enemy.hp = 1.0
		var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK_MOVE, "actor_ids": [hero.id], "point": [POINT.x, POINT.y]})
		assert_true(bool(result.get("accepted", false)), str(result))
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_eq(hero.order_target_id, "", "auto %s: no enemy within reach yet" % auto_battle)
		enemy.position = Vector2(3.0, -14.0)
		var start_hp: float = enemy.hp
		var engaged: bool = false
		var arrived: bool = false
		for _tick: int in int(20.0 / BALANCE.battle_tick_seconds):
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
			if hero.order_kind != BattleSimulation.COMMAND_ATTACK_MOVE:
				arrived = true
				break
			assert_eq(hero.order_point, POINT, "auto %s: the destination never changes" % auto_battle)
			assert_true(bool(hero.effect_state.get("direct_order", false)), "auto %s: still the player's order" % auto_battle)
			engaged = engaged or hero.order_target_id == enemy.id
		assert_true(engaged, "auto %s: it took on the enemy it met" % auto_battle)
		assert_lt(enemy.hp, start_hp, "auto %s: and hit it" % auto_battle)
		assert_true(arrived, "auto %s: then went on" % auto_battle)
		assert_lte(hero.position.distance_to(POINT), 0.01, "auto %s: to its point" % auto_battle)
		assert_false(bool(hero.effect_state.get("direct_order", false)))
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		if auto_battle:
			assert_false(hero.order_kind.is_empty(), "auto resumes")
		else:
			assert_eq(hero.order_kind, "", "manual stays idle")


func test_an_attack_move_answers_a_ranged_enemy_shooting_from_its_range() -> void:
	for auto_battle: bool in [true, false]:
		var state: BattleState = _run(auto_battle)
		var hero: BattleActor = state.actors[0]
		var enemy: BattleActor = _enemy(state)
		# A ranger off to the side of the path, at the distance it shoots from.
		enemy.archetype = "ranger"
		enemy.attack_range = BALANCE.battle_ranged_range
		enemy.position = hero.position + Vector2(-BALANCE.battle_ranged_range, 0.0)
		enemy.atk = 1.0
		enemy.hp = 1.0
		BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK_MOVE, "actor_ids": [hero.id], "point": [POINT.x, POINT.y]})
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_eq(hero.order_target_id, enemy.id, "auto %s" % auto_battle)
		for _tick: int in int(10.0 / BALANCE.battle_tick_seconds):
			if enemy.life != BattleActor.LIFE_ALIVE:
				break
			assert_eq(hero.order_point, POINT, "auto %s" % auto_battle)
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_ne(enemy.life, BattleActor.LIFE_ALIVE, "auto %s: it closed on the ranger and cut it down" % auto_battle)


func test_a_reloaded_attack_move_at_its_point_fights_on() -> void:
	var state: BattleState = _run(false)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = _enemy(state)
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	enemy.atk = 1.0
	# Standing on its point with a live enemy in reach: fighting, not arriving.
	_order_attack_move(hero, hero.position, enemy.id)
	enemy.position = hero.position + Vector2(hero.attack_range * 0.5, 0.0)
	state = _through_save_json(state)
	hero = state.actors[0]
	enemy = _enemy(state)
	for _tick: int in 10:
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_eq(hero.order_kind, BattleSimulation.COMMAND_ATTACK_MOVE)
		assert_eq(hero.order_target_id, enemy.id)
	assert_lt(enemy.hp, enemy.max_hp, "and it hits")


func test_a_reloaded_attack_move_drops_an_ally_target() -> void:
	var state: BattleState = _run(false, {}, ["hero:a", "hero:b"])
	var hero: BattleActor = state.actors[0]
	var ally: BattleActor = state.actors[1]
	# A save naming a nearby ally; the enemy is far off. Nothing to fight, so it has arrived.
	_order_attack_move(hero, hero.position, ally.id)
	state = _through_save_json(state)
	hero = state.actors[0]
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(hero.order_target_id, "")
	assert_eq(hero.order_kind, "")
	assert_false(bool(hero.effect_state.get("direct_order", false)))


func test_an_attack_move_ignores_the_supplies_retreat() -> void:
	var state: BattleState = _run(true, {"retreat_when_supplies_empty": true})
	var hero: BattleActor = state.actors[0]
	BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK_MOVE, "actor_ids": [hero.id], "point": [POINT.x, POINT.y]})
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(hero.order_kind, BattleSimulation.COMMAND_ATTACK_MOVE)
	assert_eq(hero.order_point, POINT)


func _run(auto_battle: bool, extra_policies: Dictionary = {}, ids: Array[String] = ["hero:a"]) -> BattleState:
	var heroes: Array[Dictionary] = []
	for id: String in ids:
		heroes.append({"hero_id": id, "archetype": "knight", "hp": 400.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0"})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ids, "stance": "stay_together", "guard_target_id": ""}]
	var policies: Dictionary = {"auto_battle": auto_battle}
	policies.merge(extra_policies)
	return BattleSimulation.create_run("order:ap2", heroes, _zone(), squads, policies, {"healing": 0, "revival": 0}, 5)


func _order_attack_move(hero: BattleActor, point: Vector2, target_id: String) -> void:
	hero.order_kind = BattleSimulation.COMMAND_ATTACK_MOVE
	hero.order_point = point
	hero.order_target_id = target_id
	hero.effect_state["direct_order"] = true


# The save file's round trip, in memory: to JSON and back, checked, then rebuilt. No file is written.
func _through_save_json(state: BattleState) -> BattleState:
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	assert_eq(BattleSimulation.validate_snapshot(data), "")
	return BattleState.from_dict(data)


func _enemy(state: BattleState) -> BattleActor:
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			return actor
	return null


func _zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = 20
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.9
	zone.trash_wave_end_fraction = 0.9
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 1
	zone.max_battle_seconds = 60.0
	zone.exit_position = Vector2(0, -16)
	return zone
