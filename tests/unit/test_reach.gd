extends GutTest
## ig-9gf: an approach to a still target parks inside its reach, even when float32 positions would
## leave it a hair (one ulp) outside the float64 range: a melee swing, a Protect guard radius.

const BALANCE: BalanceTable = preload("res://balance.tres")


func test_a_knight_walking_to_a_still_enemy_swings() -> void:
	# From (-6, -6) the approach used to park at 1.6000000238 from (3, 2), and never close or swing.
	var state: BattleState = _run(Vector2(-6, -6))
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = _enemies(state)[0]
	for _tick: int in 80:
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_between(knight.position.distance_to(enemy.position), knight.attack_range - 0.001, knight.attack_range, "parked inside its reach")
	assert_lt(enemy.hp, enemy.max_hp, "and swung")


func test_a_protect_knight_walking_to_its_still_ward_takes_up_the_guard() -> void:
	# From (2, 3.2532) the knight used to park at 4.000000477 from its ward, over the 4.0 guard radius.
	# Out here a float32 step that small rounds to nothing, so it re-issued its GUARD walk every tick
	# and never picked the enemy by the ward.
	var state: BattleState = _protect_run(Vector2(2, 3.2532))
	var knight: BattleActor = state.actors[0]
	for _tick: int in 120:
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(knight.order_kind, BattleSimulation.COMMAND_ATTACK, "it reached the guard and took on the enemy by its ward")


## A knight at start in Protect on a still, harmless ranger ward at (14, 12); a still, harmless enemy
## at (16, 14), inside the ward's guard radius. The other enemies wait far off.
func _protect_run(start: Vector2) -> BattleState:
	var snapshots: Array[Dictionary] = []
	for index: int in 2:
		var point: Vector2 = start if index == 0 else Vector2(14.0, 12.0)
		snapshots.append({"hero_id": "hero:%d" % index, "archetype": ["knight", "ranger"][index], "level": 1, "hp": 100000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0", "position": [point.x, point.y]})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ["hero:0", "hero:1"], "stance": "protect", "guard_target_id": "hero:hero:1"}]
	var state: BattleState = BattleSimulation.create_run("order:9gf", snapshots, _zone(), squads, {}, {"healing": 0, "revival": 0}, 13)
	_still(state, Vector2(16.0, 14.0))
	state.actors[1].move_speed = 0.0
	state.actors[1].atk = 0.0
	return state


## One knight on a direct attack order at a still, harmless enemy at (3, 2); the others wait far off.
func _run(start: Vector2) -> BattleState:
	var snapshots: Array[Dictionary] = [{"hero_id": "hero:0", "archetype": "knight", "level": 1, "hp": 100000.0, "atk": 50.0, "defense": 20.0, "speed": 100.0,
		"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0", "position": [start.x, start.y]}]
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ["hero:0"], "stance": "advance", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("order:9gf", snapshots, _zone(), squads, {}, {"healing": 0, "revival": 0}, 13)
	_still(state, Vector2(3.0, 2.0))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = BattleSimulation.COMMAND_ATTACK
	knight.order_target_id = _enemies(state)[0].id
	knight.effect_state["direct_order"] = true
	return state


## Every enemy still and harmless: the first at point, the rest far off.
func _still(state: BattleState, point: Vector2) -> void:
	var enemies: Array[BattleActor] = _enemies(state)
	for index: int in enemies.size():
		var enemy: BattleActor = enemies[index]
		enemy.position = point if index == 0 else Vector2(float(index) * 3.0 - 6.0, 19.0)
		enemy.effect_state["home_position"] = [enemy.position.x, enemy.position.y]
		enemy.move_speed = 0.0
		enemy.atk = 0.0
		enemy.max_hp = 100000.0
		enemy.hp = enemy.max_hp
		enemy.order_kind = ""
		enemy.order_target_id = ""


func _enemies(state: BattleState) -> Array[BattleActor]:
	var enemies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			enemies.append(actor)
	return enemies


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
	zone.max_battle_seconds = 120.0
	zone.exit_position = Vector2(0, -16)
	return zone
