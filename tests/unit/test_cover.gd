extends GutTest
## ig-uu7.2 Cover (SYSTEMS.md § Hero AI on auto): Knights cover a back-row ally that an enemy is on.

const BALANCE: BalanceTable = preload("res://balance.tres")


func test_a_level_1_knight_walks_over_and_its_hit_pulls_the_enemy_for_good() -> void:
	var state: BattleState = _run([["knight", Vector2(2, 0)], ["mage", Vector2(10, 0)]], "advance", 1)
	var knight: BattleActor = state.actors[0]
	var mage: BattleActor = state.actors[1]
	var enemy: BattleActor = _lock(state, _enemies(state)[0], Vector2(10, 2), mage)
	assert_gt(knight.position.distance_to(enemy.position), 7.9, "the knight starts about 8 away")
	assert_true(knight.skill_cooldowns.keys().all(func(id: String) -> bool: return id != "knight_gauntlet_toss"), "level 1: no Toss")
	var hit_tick: int = -1
	for _tick: int in int(10.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		if _taunt_source(enemy) == knight.id:
			hit_tick = state.tick
			break
		assert_eq(enemy.order_target_id, mage.id, "still on the mage until the hit")
	assert_gt(hit_tick, 0, "the knight reached it and hit")
	assert_eq(knight.order_target_id, enemy.id, "the knight was covering it")
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(enemy.order_target_id, knight.id, "the tick after the hit, the enemy is on the knight")
	BattleSimulation.advance(state, BALANCE.battle_cover_taunt_seconds + 1.0)
	assert_eq(_taunt_source(enemy), "", "the taunt has ended")
	assert_eq(enemy.order_target_id, knight.id, "and the enemy stays on the knight")


func test_two_knights_cover_one_threat_each_and_never_swap() -> void:
	var state: BattleState = _run([["knight", Vector2(-2, 0)], ["knight", Vector2(2, 0)], ["mage", Vector2(-10, 0)], ["ranger", Vector2(10, 0)]], "advance", 1)
	var knights: Array[BattleActor] = [state.actors[0], state.actors[1]]
	var mage: BattleActor = state.actors[2]
	var ranger: BattleActor = state.actors[3]
	var enemies: Array[BattleActor] = _enemies(state)
	_lock(state, enemies[0], Vector2(-10, 3), mage)
	_lock(state, enemies[1], Vector2(10, 3), ranger)
	# Rooted out of reach, the knights never land the hit that would end the threats.
	for knight: BattleActor in knights:
		knight.move_speed = 0.0
	var claims: Array[String] = []
	for tick: int in int(10.0 / BALANCE.battle_tick_seconds):
		# Swap which victim is hurt worse every tick: a pick by HP alone would ping-pong.
		mage.hp = mage.max_hp * (0.3 if tick % 2 == 0 else 0.6)
		ranger.hp = ranger.max_hp * (0.6 if tick % 2 == 0 else 0.3)
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_true(enemies[0].order_target_id == mage.id and enemies[1].order_target_id == ranger.id, "both threats stand")
		var now: Array[String] = [knights[0].order_target_id, knights[1].order_target_id]
		if claims.is_empty():
			claims = now
		assert_eq(now, claims, "tick %d" % state.tick)
	assert_ne(claims[0], claims[1], "one knight each")
	assert_true(enemies[0].id in claims and enemies[1].id in claims, str(claims))


func test_a_lone_knight_keeps_its_threat_when_another_victim_gets_hurt_worse() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)], ["mage", Vector2(-10, 0)], ["ranger", Vector2(6, 0)]], "advance", 1)
	var knight: BattleActor = state.actors[0]
	var mage: BattleActor = state.actors[1]
	var ranger: BattleActor = state.actors[2]
	var enemies: Array[BattleActor] = _enemies(state)
	var far_threat: BattleActor = _lock(state, enemies[0], Vector2(-10, 3), mage)
	var near_threat: BattleActor = _lock(state, enemies[1], Vector2(6, 3), ranger)
	knight.move_speed = 0.0
	# The mage is hurt worse at first: its threat is the pick, though the ranger's is nearer.
	mage.hp = mage.max_hp * 0.3
	ranger.hp = ranger.max_hp * 0.6
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(knight.order_target_id, far_threat.id, "the lowest victim HP fraction first")
	for _tick: int in int(10.0 / BALANCE.battle_tick_seconds):
		mage.hp = mage.max_hp * 0.6
		ranger.hp = ranger.max_hp * 0.3
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_true(far_threat.order_target_id == mage.id and near_threat.order_target_id == ranger.id, "both threats stand")
		assert_eq(knight.order_target_id, far_threat.id, "tick %d: it keeps its threat" % state.tick)


func test_a_piloted_knights_target_keeps_an_auto_knight_off_it() -> void:
	var state: BattleState = _run([["knight", Vector2(-2, 0)], ["knight", Vector2(2, 0)], ["mage", Vector2(0, 6)], ["ranger", Vector2(-8, 0)]], "advance", 1)
	var auto_knight: BattleActor = state.actors[0]
	var piloted: BattleActor = state.actors[1]
	var enemies: Array[BattleActor] = _enemies(state)
	var threat: BattleActor = _lock(state, enemies[0], Vector2(0, 9), state.actors[2])
	var other_threat: BattleActor = _lock(state, enemies[1], Vector2(-8, 3), state.actors[3])
	for knight: BattleActor in [auto_knight, piloted]:
		knight.move_speed = 0.0
	# The auto knight covered it last tick; now the player orders the other knight onto it.
	auto_knight.order_kind = BattleSimulation.COMMAND_ATTACK
	auto_knight.order_target_id = threat.id
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [piloted.id], "target_id": threat.id})
	assert_true(bool(result.get("accepted", false)), str(result))
	for _tick: int in int(2.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_eq(piloted.order_target_id, threat.id)
		assert_eq(auto_knight.order_target_id, other_threat.id, "tick %d: it covers the other threat" % state.tick)


func test_defend_does_not_draw_a_knight_out_of_its_anchor() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)], ["mage", Vector2(0, 1)]], "defend", 1)
	var knight: BattleActor = state.actors[0]
	var mage: BattleActor = state.actors[1]
	var anchor: Vector2 = Vector2(0, 0.5)
	state.squads[0]["stance_anchor"] = [anchor.x, anchor.y]
	var enemy: BattleActor = _lock(state, _enemies(state)[0], Vector2(0, 9), mage)
	enemy.speed = 0.0
	enemy.move_speed = 0.0
	for _tick: int in int(3.0 / BALANCE.battle_tick_seconds):
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		assert_gt(enemy.position.distance_to(anchor), BALANCE.battle_guard_radius)
		assert_ne(knight.order_target_id, enemy.id)
		assert_lte(knight.position.distance_to(anchor), BALANCE.battle_guard_radius + 0.01)


func test_a_knight_hit_taunts_only_an_enemy_on_a_back_row_ally() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)], ["rogue", Vector2(2, 0)], ["knight", Vector2(4, 0)], ["cleric", Vector2(6, 0)]], "advance", 1)
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = _enemies(state)[0]
	for victim: BattleActor in [state.actors[1], state.actors[2]]:
		enemy.order_target_id = victim.id
		BattleSimulation._damage(state, knight, enemy, 1.0, null)
		assert_eq(_taunt_source(enemy), "", "no pull off a %s" % victim.archetype)
	enemy.order_target_id = state.actors[3].id
	BattleSimulation._damage(state, knight, enemy, 1.0, null)
	assert_eq(_taunt_source(enemy), knight.id, "a pull off the cleric")


func test_toss_aims_at_the_covered_threat_first() -> void:
	var state: BattleState = _run([["knight", Vector2(0, 0)], ["knight", Vector2(1, 0)], ["mage", Vector2(0, 5)]], "advance", 15)
	var knight: BattleActor = state.actors[0]
	var hurt_knight: BattleActor = state.actors[1]
	var mage: BattleActor = state.actors[2]
	hurt_knight.hp = hurt_knight.max_hp * 0.1
	var enemies: Array[BattleActor] = _enemies(state)
	# Earlier in state.actors: an enemy on a weaker ally, which the old loop took first.
	var other: BattleActor = _lock(state, enemies[0], Vector2(0, -3), hurt_knight)
	var covered: BattleActor = _lock(state, enemies[1], Vector2(0, 4), mage)
	knight.order_target_id = covered.id
	var toss: AbilityDefinition = BattleSimulation.ABILITIES["knight_gauntlet_toss"]
	assert_eq(BattleSimulation._rule_aim(state, knight, toss, covered, "buff"), covered)
	knight.order_target_id = ""
	assert_eq(BattleSimulation._rule_aim(state, knight, toss, null, "buff"), other, "without a covered threat, the old pick")


func test_the_same_seed_gives_the_same_fight() -> void:
	var digests: Array[String] = []
	for _run_index: int in 2:
		var state: BattleState = _run([["knight", Vector2(-2, 0)], ["knight", Vector2(2, 0)], ["mage", Vector2(-8, 0)], ["ranger", Vector2(8, 0)], ["cleric", Vector2(0, -2)]], "advance", 15)
		var enemies: Array[BattleActor] = _enemies(state)
		_lock(state, enemies[0], Vector2(-8, 3), state.actors[2])
		_lock(state, enemies[1], Vector2(8, 3), state.actors[3])
		var trace := PackedStringArray()
		for _tick: int in int(20.0 / BALANCE.battle_tick_seconds):
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
			for actor: BattleActor in state.actors:
				trace.append("%s|%s|%s|%s|%s" % [actor.position, actor.hp, actor.order_target_id, actor.life, actor.statuses])
		digests.append("\n".join(trace).md5_text())
	assert_eq(digests[0], digests[1])


## An enemy placed at point, locked on victim, with its home there so the leash holds.
func _lock(state: BattleState, enemy: BattleActor, point: Vector2, victim: BattleActor) -> BattleActor:
	enemy.position = point
	enemy.effect_state["home_position"] = [point.x, point.y]
	enemy.order_kind = BattleSimulation.COMMAND_ATTACK
	enemy.order_target_id = victim.id
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	enemy.atk = 1.0
	return enemy


func _taunt_source(actor: BattleActor) -> String:
	for status: Dictionary in actor.statuses:
		if status["kind"] == "taunt":
			return str(status["source"])
	return ""


func _enemies(state: BattleState) -> Array[BattleActor]:
	var enemies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			enemies.append(actor)
	return enemies


## heroes: [archetype, position] pairs in one squad. Two enemies spawn; tests place the ones they use
## and park the rest far away, inside the zone's 20-unit bounds.
func _run(heroes: Array, stance: String, level: int) -> BattleState:
	var snapshots: Array[Dictionary] = []
	var ids: Array[String] = []
	for index: int in heroes.size():
		var id: String = "hero:%d" % index
		ids.append(id)
		var point: Vector2 = heroes[index][1]
		snapshots.append({"hero_id": id, "archetype": heroes[index][0], "level": level, "hp": 4000.0, "atk": 50.0, "defense": 20.0, "speed": 20.0,
			"crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "squad:0", "position": [point.x, point.y]})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": ids, "stance": stance, "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("order:uu72", snapshots, _zone(), squads, {}, {"healing": 0, "revival": 0}, 13)
	for enemy: BattleActor in _enemies(state):
		_lock(state, enemy, Vector2(float(enemy.spawn_index % 3) * 2.0 - 2.0, 19.0), state.actors[0])
		enemy.order_kind = ""
		enemy.order_target_id = ""
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
	zone.trash_enemy_count = 2
	zone.max_battle_seconds = 120.0
	zone.exit_position = Vector2(0, -16)
	return zone
