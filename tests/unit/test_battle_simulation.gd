extends GutTest


func test_fixed_ticks_are_identical_when_elapsed_time_is_chunked() -> void:
	var zone: ZoneDefinition = _zone(20)
	var first: BattleState = BattleSimulation.create_run("order:a", [_hero("hero:a", "knight")], zone, _squads(["hero:a"]), {}, {"healing": 1, "revival": 1}, 98123)
	var second: BattleState = BattleState.from_dict(first.to_dict())

	BattleSimulation.advance(first, 5.0)
	for step: int in 50:
		BattleSimulation.advance(second, 0.1)

	assert_eq(second.to_dict(), first.to_dict())


func test_snapshot_round_trip_preserves_rng_and_validates() -> void:
	var state: BattleState = BattleSimulation.create_run("order:roundtrip", [_hero("hero:a", "mage")], _zone(20), _squads(["hero:a"]), {}, {"healing": 2, "revival": 1}, -9223372036854770000)
	BattleSimulation.advance(state, 1.3)
	var snapshot: Dictionary = state.to_dict()

	assert_eq(BattleSimulation.validate_snapshot(snapshot), "")
	assert_typeof(snapshot["rng_state"], TYPE_STRING)
	assert_eq(BattleState.from_dict(snapshot).to_dict(), snapshot)


func test_invalid_command_is_atomic_and_valid_move_gets_sequence() -> void:
	var state: BattleState = BattleSimulation.create_run("order:command", [_hero("hero:a", "ranger")], _zone(20), _squads(["hero:a"]), {}, {"healing": 0, "revival": 0}, 3)
	var actor: BattleActor = state.actors[0]
	var carried := BattleActor.new()
	carried.id = "hero:carried"
	carried.hero_id = "hero:carried"
	carried.archetype = "knight"
	carried.set_default_kit()
	carried.faction = "ally"
	carried.spawn_index = state.actors.size()
	carried.max_hp = 100.0
	carried.hp = 0.0
	carried.atk = 1.0
	carried.speed = 1.0
	carried.life = BattleActor.LIFE_DOWNED
	carried.carried_by_id = actor.id
	carried.effect_state = actor.effect_state.duplicate(true)
	actor.carrying_id = carried.id
	state.actors.append(carried)
	var before: Dictionary = state.to_dict()

	var rejected: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_MOVE, "actor_ids": [actor.id], "point": [INF, 0.0]})
	assert_false(bool(rejected["accepted"]))
	assert_eq(state.to_dict(), before)

	var accepted: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_MOVE, "actor_ids": [actor.id], "point": [4.0, 2.0]})
	assert_true(bool(accepted["accepted"]))
	assert_eq(int(accepted["sequence"]), 1)
	assert_eq(actor.order_point, Vector2(4.0, 2.0))


func test_basic_attack_uses_speed_interval_in_actual_combat() -> void:
	var snapshot: Dictionary = _hero("hero:slow", "knight")
	snapshot["speed"] = 90.0
	var state: BattleState = BattleSimulation.create_run("order:interval", [snapshot], _zone(20), _squads(["hero:slow"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 4)
	var attacker: BattleActor = state.actors[0]
	var target: BattleActor = state.actors[1]
	attacker.set_abilities_auto(false)
	attacker.position = Vector2.ZERO
	target.position = Vector2(0.0, 1.0)
	target.effect_state["home_position"] = [0.0, 1.0]
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [attacker.id], "target_id": target.id})
	assert_true(bool(result["accepted"]))

	while int(target.effect_state.get("last_hit_tick", 0)) == 0:
		BattleSimulation.advance(state, 0.1)

	assert_almost_eq(attacker.attack_cooldown, 100.0 / 90.0, 0.00001)
	assert_eq(int(target.effect_state["last_hit_tick"]), state.tick)


func test_standard_battle_finishes_with_one_deterministic_outcome() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var heroes: Array[Dictionary] = []
	var hero_ids: Array[String] = []
	var roles: Array[String] = ["knight", "ranger", "mage", "rogue", "knight"]
	for index: int in 5:
		var hero_id: String = "hero:%d" % index
		var hero: Dictionary = _hero(hero_id, roles[index])
		hero["atk"] = 5000.0
		heroes.append(hero)
		hero_ids.append(hero_id)
	var state: BattleState = BattleSimulation.create_run("order:finish", heroes, zone, _squads(hero_ids), {}, {"healing": 0, "revival": 0}, 99)

	var outcome: BattleOutcome = BattleSimulation.advance(state, zone.max_battle_seconds)

	assert_eq(outcome.status, "victory")
	assert_eq(outcome.secured_hero_ids.size(), 5)
	assert_eq(state.completed_waves, zone.trash_wave_count + 1)
	assert_lte(outcome.elapsed_seconds, zone.max_battle_seconds)


func test_damage_records_crit_tick_only_when_the_hit_crits() -> void:
	var policies: Dictionary = {"force_enemy_crit": true, "suppress_ally_crit": true}
	var state: BattleState = BattleSimulation.create_run("order:crit", [_hero("hero:a", "ranger")], _zone(20), _squads(["hero:a"]), policies, {"healing": 0, "revival": 0}, 3)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	state.tick = 7

	BattleSimulation._damage(state, enemy, hero, 0.01, null)
	assert_eq(hero.effect_state["last_crit_tick"], 7, "a forced enemy crit is recorded at the current tick")

	BattleSimulation._damage(state, hero, enemy, 0.01, null)
	assert_eq(enemy.effect_state["last_hit_tick"], 7)
	assert_eq(enemy.effect_state["last_crit_tick"], 0, "a suppressed ally crit is not recorded")


func test_enemy_telegraph_is_serialized_before_effect() -> void:
	var zone: ZoneDefinition = _zone(20)
	var state: BattleState = BattleSimulation.create_run("order:telegraph", [_hero("hero:a", "knight")], zone, _squads(["hero:a"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 7)
	var enemy: BattleActor = state.actors[1]
	enemy.archetype = "mage"
	enemy.set_default_kit()
	enemy.attack_range = 8.0
	enemy.position = Vector2(0, -14)
	enemy.effect_state["home_position"] = [0.0, -14.0]
	state.actors[0].position = Vector2(0, -15)

	BattleSimulation.advance(state, 0.1)

	assert_eq(enemy.effect_state["telegraph_kind"], "circle")
	assert_almost_eq(float(enemy.effect_state["telegraph_total"]), 0.8, 0.0001)
	assert_eq(enemy.effect_state["telegraph_point"], [state.actors[0].position.x, state.actors[0].position.y])
	assert_gt(enemy.skill_cooldowns["mage_burst"], 0.0)


func test_auto_attack_reacquires_after_its_target_dies() -> void:
	var state: BattleState = BattleSimulation.create_run("order:reacquire", [_hero("hero:a", "knight")], _zone(20), _squads(["hero:a"]), {}, {"healing": 0, "revival": 0}, 5)
	var hero: BattleActor = state.actors[0]
	var first_enemy: BattleActor = state.actors[1]
	hero.order_kind = BattleSimulation.COMMAND_ATTACK
	hero.order_target_id = first_enemy.id
	hero.effect_state["direct_order"] = false
	first_enemy.hp = 0.0
	first_enemy.life = BattleActor.LIFE_DEAD
	var second_enemy := BattleActor.new()
	second_enemy.id = "enemy:second"
	second_enemy.archetype = "rogue"
	second_enemy.set_default_kit()
	second_enemy.faction = "enemy"
	second_enemy.spawn_index = state.actors.size()
	second_enemy.max_hp = 100.0
	second_enemy.hp = 100.0
	second_enemy.atk = 1.0
	second_enemy.speed = 20.0
	second_enemy.position = hero.position + Vector2(0.0, 2.0)
	second_enemy.effect_state = first_enemy.effect_state.duplicate(true)
	second_enemy.effect_state["home_position"] = [second_enemy.position.x, second_enemy.position.y]
	state.actors.append(second_enemy)

	BattleSimulation.advance(state, 0.1)

	assert_eq(hero.order_target_id, second_enemy.id)


func test_auto_ally_evades_telegraph_but_manual_move_persists() -> void:
	var state: BattleState = BattleSimulation.create_run("order:evade", [_hero("hero:a", "knight")], _zone(20), _squads(["hero:a"]), {}, {"healing": 0, "revival": 0}, 6)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	hero.position = Vector2.ZERO
	enemy.effect_state["telegraph_kind"] = "circle"
	enemy.effect_state["telegraph_point"] = [0.0, 0.0]
	enemy.effect_state["telegraph_radius"] = 2.5
	enemy.effect_state["telegraph_remaining"] = 0.8
	enemy.effect_state["telegraph_total"] = 0.8
	BattleSimulation.advance(state, 0.1)
	assert_gt(hero.position.length(), 0.0)

	var manual_point := Vector2(5.0, 0.0)
	BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_MOVE, "actor_ids": [hero.id], "point": [manual_point.x, manual_point.y]})
	var before: Vector2 = hero.position
	BattleSimulation.advance(state, 0.1)
	assert_gt(hero.position.x, before.x)


func test_auto_battle_off_keeps_an_idle_ally_in_place() -> void:
	var state: BattleState = BattleSimulation.create_run("order:idle", [_hero("hero:a", "knight")], _zone(20), _squads(["hero:a"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 8)
	var hero: BattleActor = state.actors[0]
	var initial_position: Vector2 = hero.position

	BattleSimulation.advance(state, 1.0)

	assert_eq(hero.position, initial_position)


func test_manual_ability_uses_and_persists_saved_rng_atomically() -> void:
	var state: BattleState = BattleSimulation.create_run("order:manual-rng", [_hero("hero:ranger", "ranger")], _zone(20), _squads(["hero:ranger"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 2468)
	var ranger: BattleActor = state.actors[0]
	var target: BattleActor = state.actors[1]
	ranger.position = Vector2.ZERO
	ranger.crit_rate = 1.0
	target.position = Vector2(0.0, 2.0)
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.defense = 0.0
	var rng_before: String = state.rng_state
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [ranger.id], "target_id": target.id, "point": [target.position.x, target.position.y]})

	assert_true(bool(result["accepted"]))
	assert_ne(state.rng_state, rng_before)
	assert_almost_eq(target.hp, 865.0, 0.0001)
	assert_gt(ranger.skill_cooldowns["ranger_piercing_shot"], 0.0)

	var invalid: BattleState = BattleSimulation.create_run("order:manual-invalid", [_hero("hero:ranger", "ranger")], _zone(20), _squads(["hero:ranger"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 2468)
	var invalid_before: Dictionary = invalid.to_dict()
	var rejected: Dictionary = BattleSimulation.issue_command(invalid, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [invalid.actors[0].id], "target_id": invalid.actors[1].id, "point": [20.0, 20.0]})
	assert_false(bool(rejected["accepted"]))
	assert_eq(invalid.to_dict(), invalid_before)


func test_rogue_rear_passive_applies_to_basic_hit_but_not_signature() -> void:
	var signature_state: BattleState = BattleSimulation.create_run("order:rogue-skill", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var rogue: BattleActor = signature_state.actors[0]
	var signature_target: BattleActor = signature_state.actors[1]
	rogue.position = Vector2.ZERO
	rogue.atk = 100.0
	rogue.crit_rate = 0.0
	signature_target.position = Vector2(0.0, 2.0)
	signature_target.facing = Vector2.DOWN
	signature_target.max_hp = 1000.0
	signature_target.hp = 1000.0
	signature_target.defense = 0.0
	var result: Dictionary = BattleSimulation.issue_command(signature_state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [rogue.id], "target_id": signature_target.id, "point": [signature_target.position.x, signature_target.position.y]})
	assert_true(bool(result["accepted"]))
	assert_almost_eq(signature_target.hp, 840.0, 0.0001)
	assert_almost_eq(float(signature_target.effect_state["stun_remaining"]), 0.3, 0.0001)
	assert_eq(int(signature_target.effect_state["last_hit_tick"]), signature_state.tick)

	var basic_state: BattleState = BattleSimulation.create_run("order:rogue-basic", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var basic_rogue: BattleActor = basic_state.actors[0]
	var basic_target: BattleActor = basic_state.actors[1]
	basic_rogue.position = Vector2(0.0, 1.0)
	basic_rogue.atk = 100.0
	basic_rogue.crit_rate = 0.0
	basic_rogue.set_abilities_auto(false)
	basic_target.position = Vector2.ZERO
	basic_target.facing = Vector2.UP
	basic_target.max_hp = 1000.0
	basic_target.hp = 1000.0
	basic_target.defense = 0.0
	basic_target.set_abilities_auto(false)
	# Stunned, so it cannot turn to fight back and stays facing away.
	basic_target.effect_state["stun_remaining"] = 10.0
	BattleSimulation.issue_command(basic_state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [basic_rogue.id], "target_id": basic_target.id})
	while int(basic_target.effect_state.get("last_hit_tick", 0)) == 0:
		BattleSimulation.advance(basic_state, 0.1)
	assert_almost_eq(basic_target.hp, 875.0, 0.0001)


func test_a_fresh_spawn_faces_the_other_side_so_no_front_hit_counts_as_behind() -> void:
	var state: BattleState = BattleSimulation.create_run("order:spawn-facing", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	assert_gt(hero.facing.dot(enemy.position - hero.position), 0.0, "the hero faces the enemy")
	assert_gt(enemy.facing.dot(hero.position - enemy.position), 0.0, "the enemy faces the hero")
	assert_false(BattleSimulation._is_behind(hero, enemy), "a Rogue in front gets no rear bonus")
	assert_false(BattleSimulation._is_behind(enemy, hero))
	# A saved facing is kept: only fresh heroes turn.
	var saved: Dictionary = _hero("hero:saved", "knight")
	saved["facing"] = [1.0, 0.0]
	var kept: BattleState = BattleSimulation.create_run("order:kept-facing", [saved], _zone(20), _squads(["hero:saved"]), {}, {"healing": 0, "revival": 0}, 5)
	assert_eq(kept.actors[0].facing, Vector2.RIGHT)


func test_stationary_attackers_turn_to_face_their_targets() -> void:
	var state: BattleState = BattleSimulation.create_run("order:face", [_hero("hero:knight", "knight")], _zone(20), _squads(["hero:knight"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var hero: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	hero.position = Vector2(0.0, 1.0)
	hero.facing = Vector2.DOWN
	hero.set_abilities_auto(false)
	enemy.position = Vector2.ZERO
	enemy.facing = Vector2.UP
	enemy.set_abilities_auto(false)
	BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [hero.id], "target_id": enemy.id})
	BattleSimulation.advance(state, 0.1)
	assert_eq(hero.position, Vector2(0.0, 1.0), "already in range, so the hero never walks")
	assert_almost_eq(hero.facing.dot(Vector2.UP), 1.0, 0.0001, "the hero turns from facing away to face the enemy")
	assert_eq(enemy.order_target_id, hero.id)
	assert_almost_eq(enemy.facing.dot(Vector2.DOWN), 1.0, 0.0001, "the enemy turns to face the hero it attacks")


func test_rogue_signature_faces_the_target_it_lands_behind() -> void:
	var state: BattleState = BattleSimulation.create_run("order:rogue-land", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var rogue: BattleActor = state.actors[0]
	var target: BattleActor = state.actors[1]
	rogue.position = Vector2.ZERO
	rogue.facing = Vector2.UP
	target.position = Vector2(0.0, 2.0)
	target.facing = Vector2.DOWN
	target.max_hp = 1000.0
	target.hp = 1000.0
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [rogue.id], "target_id": target.id, "point": [target.position.x, target.position.y]})
	assert_true(bool(result["accepted"]))
	assert_ne(rogue.position, Vector2.ZERO, "the rogue teleported")
	assert_almost_eq(rogue.facing.dot((target.position - rogue.position).normalized()), 1.0, 0.0001, "and strikes facing its target")


func test_a_manual_cast_turns_the_caster_to_its_aim() -> void:
	var state: BattleState = BattleSimulation.create_run("order:ranger-aim", [_hero("hero:ranger", "ranger")], _zone(20), _squads(["hero:ranger"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var ranger: BattleActor = state.actors[0]
	var target: BattleActor = state.actors[1]
	ranger.position = Vector2.ZERO
	ranger.facing = Vector2.DOWN
	target.position = Vector2(3.0, 0.0)
	target.max_hp = 1000.0
	target.hp = 1000.0
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [ranger.id], "target_id": target.id, "point": [3.0, 0.0]})
	assert_true(bool(result["accepted"]))
	assert_almost_eq(ranger.facing.dot(Vector2.RIGHT), 1.0, 0.0001)


func test_rear_bonus_does_not_depend_on_which_side_the_tick_reaches_first() -> void:
	for reversed: bool in [false, true]:
		var state: BattleState = BattleSimulation.create_run("order:rogue-order", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
		var rogue: BattleActor = state.actors[0]
		var enemy: BattleActor = state.actors[1]
		rogue.position = Vector2(0.0, 1.0)
		rogue.atk = 100.0
		rogue.crit_rate = 0.0
		rogue.set_abilities_auto(false)
		rogue.attack_range = 2.0
		# Facing away from the rogue until it picks the rogue as its target this very tick.
		enemy.position = Vector2.ZERO
		enemy.facing = Vector2.UP
		enemy.max_hp = 1000.0
		enemy.hp = 1000.0
		enemy.defense = 0.0
		enemy.set_abilities_auto(false)
		enemy.attack_range = 2.0
		BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [rogue.id], "target_id": enemy.id})
		# The rogue's swing is wound up and lands on the first tick.
		rogue.effect_state["attack_windup_remaining"] = 0.0
		rogue.effect_state["attack_target_id"] = enemy.id
		rogue.attack_cooldown = 0.0
		if reversed:
			state.actors.reverse()
		assert_eq(enemy.order_target_id, "", "the enemy has not chosen yet")
		BattleSimulation.advance(state, 0.1)
		assert_eq(enemy.order_target_id, rogue.id)
		assert_eq(int(enemy.effect_state.get("last_hit_tick", 0)), state.tick, "reversed=%s: the swing landed this tick" % reversed)
		assert_almost_eq(enemy.hp, 900.0, 0.0001, "reversed=%s: the enemy turned to the rogue before it struck" % reversed)


func test_rogue_gets_no_rear_bonus_on_a_target_fighting_it() -> void:
	var state: BattleState = BattleSimulation.create_run("order:rogue-front", [_hero("hero:rogue", "rogue")], _zone(20), _squads(["hero:rogue"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5)
	var rogue: BattleActor = state.actors[0]
	var target: BattleActor = state.actors[1]
	rogue.position = Vector2(0.0, 1.0)
	rogue.atk = 100.0
	rogue.crit_rate = 0.0
	rogue.set_abilities_auto(false)
	target.position = Vector2.ZERO
	target.facing = Vector2.UP
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.defense = 0.0
	target.set_abilities_auto(false)
	BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ATTACK, "actor_ids": [rogue.id], "target_id": target.id})
	while int(target.effect_state.get("last_hit_tick", 0)) == 0:
		BattleSimulation.advance(state, 0.1)
	assert_almost_eq(target.hp, 900.0, 0.0001, "the target turned to fight the rogue, so the rogue is in front of it")


func test_exact_overlap_separates_deterministically_inside_bounds() -> void:
	var state: BattleState = BattleSimulation.create_run("order:overlap", [_hero("hero:a", "knight")], _zone(20), _squads(["hero:a"]), {"auto_battle": false}, {"healing": 0, "revival": 0}, 2)
	state.actors[0].position = Vector2(20.0, 20.0)
	state.actors[1].position = Vector2(20.0, 20.0)
	state.actors[1].effect_state["home_position"] = [20.0, 20.0]

	BattleSimulation.advance(state, 0.1)

	assert_gt(state.actors[0].position.distance_to(state.actors[1].position), 0.0)
	for actor: BattleActor in state.actors:
		assert_lte(absf(actor.position.x), 20.0)
		assert_lte(absf(actor.position.y), 20.0)


func test_enemy_budget_uses_actual_authored_resource_values() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var five_ids: Array[String] = ["hero:0", "hero:1", "hero:2", "hero:3", "hero:4"]
	var five: Array[Dictionary] = []
	for index: int in five_ids.size():
		five.append(_hero(five_ids[index], ["knight", "ranger", "mage", "rogue", "knight"][index]))
	var full_state: BattleState = BattleSimulation.create_run("order:budget-five", five, zone, _squads(five_ids), {}, {"healing": 0, "revival": 0}, 1)
	var full_enemy: BattleActor = full_state.actors[5]
	assert_almost_eq(full_enemy.max_hp, 90.0, 0.0001)
	assert_almost_eq(full_enemy.atk, 3.6, 0.0001)

	var three_ids: Array[String] = ["hero:a", "hero:b", "hero:c"]
	var three: Array[Dictionary] = [_hero("hero:a", "knight"), _hero("hero:b", "ranger"), _hero("hero:c", "mage")]
	var small_state: BattleState = BattleSimulation.create_run("order:budget-three", three, zone, _squads(three_ids), {}, {"healing": 0, "revival": 0}, 1)
	var small_enemy: BattleActor = small_state.actors[3]
	assert_almost_eq(small_enemy.max_hp, 54.0, 0.0001)
	assert_almost_eq(small_enemy.atk, 2.16, 0.0001)


func test_snapshot_validation_rejects_corrupt_persistent_shapes() -> void:
	var state: BattleState = BattleSimulation.create_run("order:validation", [_hero("hero:a", "knight")], _zone(20), _squads(["hero:a"]), {}, {"healing": 1, "revival": 1}, 9)
	var valid: Dictionary = state.to_dict()
	assert_eq(BattleSimulation.validate_snapshot(valid), "")

	var corrupt: Dictionary = valid.duplicate(true)
	corrupt["zone_id"] = "missing_zone"
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle zone_id is unknown.")
	corrupt = valid.duplicate(true)
	corrupt["max_seconds"] = 181.0
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle max_seconds exceeds the authored zone bound.")
	corrupt = valid.duplicate(true)
	corrupt["elapsed_seconds"] = 0.1
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle tick and elapsed_seconds are inconsistent.")
	corrupt = valid.duplicate(true)
	((corrupt["actors"] as Array)[0] as Dictionary)["position"] = [21.0, 0.0]
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle actor positions must remain inside the authored bounds.")
	corrupt = valid.duplicate(true)
	(corrupt["supplies_remaining"] as Dictionary)["gold"] = 1
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle supplies: an unknown supply kind.")
	corrupt = valid.duplicate(true)
	((corrupt["actors"] as Array)[0] as Dictionary)["squad_id"] = "wrong"
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle hero squad_id must match squad membership.")
	corrupt = valid.duplicate(true)
	(corrupt["extracted_ids"] as Array).append("hero:a")
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Battle extracted_ids must match extracted hero actors.")
	corrupt = valid.duplicate(true)
	var markers: Array = (corrupt["objective_state"] as Dictionary)["markers"] as Array
	(markers[0] as Dictionary)["position"] = [99.0, 0.0]
	assert_eq(BattleSimulation.validate_snapshot(corrupt), "Objective marker positions must remain inside the authored bounds.")


func test_authored_fallen_citadel_force_captures_seals_and_defeats_boss() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"fallen_citadel")
	var state: BattleState = BattleSimulation.create_run("order:fallen-real", _authored_heroes(30), zone, _authored_squads(30), {"default_stance": "advance"}, {"healing": 0, "revival": 0}, 991)
	var saw_boss: bool = false
	while state.status == "active":
		BattleSimulation.advance(state, 0.1)
		if bool(state.objective_state.get("boss_spawned", false)):
			saw_boss = true

	assert_true(saw_boss)
	assert_eq(state.status, "victory")
	assert_eq(state.completed_waves, 2)
	assert_true(_dead_elite_exists(state))
	for marker: Dictionary in state.objective_state["markers"] as Array:
		if str(marker.get("kind")) == "capture":
			assert_true(bool(marker.get("complete")))


func test_authored_frontier_force_clears_camps_patrols_and_final_elite() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"frontier_march")
	var state: BattleState = BattleSimulation.create_run("order:frontier-real", _authored_heroes(50), zone, _authored_squads(50), {"default_stance": "advance"}, {"healing": 0, "revival": 0}, 992)
	var highest_escort_index: int = 0
	var saw_final_elite: bool = false
	while state.status == "active":
		BattleSimulation.advance(state, 0.1)
		highest_escort_index = maxi(highest_escort_index, int(state.objective_state.get("escort_index", 0)))
		for actor: BattleActor in state.actors:
			if actor.faction == "enemy" and bool(actor.effect_state.get("elite", false)):
				saw_final_elite = true

	assert_eq(highest_escort_index, 3)
	assert_true(saw_final_elite)
	assert_eq(state.status, "victory")
	assert_eq(state.completed_waves, 4)
	assert_true(_dead_elite_exists(state))
	for marker: Dictionary in state.objective_state["markers"] as Array:
		if str(marker.get("kind")) in ["camp", "waypoint"]:
			assert_true(bool(marker.get("complete")))


func _zone(enemy_power: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = enemy_power
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.5
	zone.trash_wave_end_fraction = 0.5
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 1
	zone.max_battle_seconds = 30.0
	zone.exit_position = Vector2(0, -16)
	return zone


func _hero(id: String, archetype: String) -> Dictionary:
	return {"hero_id": id, "archetype": archetype, "hp": 200.0, "atk": 50.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.1, "crit_damage": 1.5, "squad_id": "squad:0"}


func _squads(hero_ids: Array[String]) -> Array[Dictionary]:
	return [{"id": "squad:0", "name": "Alpha", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]


func _authored_heroes(count: int) -> Array[Dictionary]:
	var heroes: Array[Dictionary] = []
	var roles: Array[String] = ["knight", "ranger", "mage", "rogue"]
	for index: int in count:
		var archetype: String = roles[index % roles.size()]
		var hero := Hero.new("Authored %d" % index, 7)
		hero.instance_id = "hero:authored:%d" % index
		hero.def_id = StringName(archetype)
		hero.level = 80
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(hero, definition, preload("res://balance.tres"), Hero.level_for(hero, preload("res://balance.tres")))
		heroes.append({
			"hero_id": hero.instance_id,
			"archetype": archetype,
			"hp": stats[Hero.STAT_HP],
			"atk": stats[Hero.STAT_ATK],
			"defense": stats[Hero.STAT_DEF],
			"speed": stats[Hero.STAT_SPD],
			"crit_rate": stats[Hero.STAT_CRIT_RATE],
			"crit_damage": stats[Hero.STAT_CRIT_DMG],
			"squad_id": "squad:%d" % (index / 5),
		})
	return heroes


func _authored_squads(hero_count: int) -> Array[Dictionary]:
	var squads: Array[Dictionary] = []
	for squad_index: int in ceili(float(hero_count) / 5.0):
		var hero_ids: Array[String] = []
		for member_index: int in range(squad_index * 5, mini((squad_index + 1) * 5, hero_count)):
			hero_ids.append("hero:authored:%d" % member_index)
		squads.append({"id": "squad:%d" % squad_index, "name": "Squad %d" % squad_index, "hero_ids": hero_ids, "stance": "advance", "guard_target_id": ""})
	return squads


func _dead_elite_exists(state: BattleState) -> bool:
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy" and bool(actor.effect_state.get("elite", false)) and actor.life == BattleActor.LIFE_DEAD:
			return true
	return false
