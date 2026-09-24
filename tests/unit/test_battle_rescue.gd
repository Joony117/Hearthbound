extends GutTest


func test_knight_rally_revives_without_profile_mutation() -> void:
	var state: BattleState = _rescue_state(false)
	var knight: BattleActor = state.actors[0]
	var downed: BattleActor = state.actors[1]

	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [knight.id], "target_id": downed.id, "point": [downed.position.x, downed.position.y]})

	assert_true(bool(result["accepted"]))
	assert_eq(downed.life, BattleActor.LIFE_ALIVE)
	assert_almost_eq(downed.hp, downed.max_hp * 0.25, 0.0001)
	assert_gt(knight.skill_cooldowns["knight_rally"], 0.0)


func test_reserved_last_revival_is_automatic_only() -> void:
	var state: BattleState = _rescue_state(true)
	var ranger: BattleActor = state.actors[0]
	ranger.archetype = "ranger"
	ranger.set_default_kit()
	var downed: BattleActor = state.actors[1]
	BattleSimulation.advance(state, 0.1)
	assert_eq(downed.life, BattleActor.LIFE_DOWNED)
	assert_eq(state.supplies_remaining["revival"], 1)

	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ITEM_REVIVAL, "actor_ids": [ranger.id], "target_id": downed.id})
	assert_true(bool(result["accepted"]))
	assert_eq(downed.life, BattleActor.LIFE_ALIVE)
	assert_eq(state.supplies_remaining["revival"], 0)


func test_carry_extracts_one_body_without_duplication() -> void:
	var state: BattleState = _rescue_state(false)
	var carrier: BattleActor = state.actors[0]
	carrier.archetype = "ranger"
	carrier.set_default_kit()
	var downed: BattleActor = state.actors[1]
	carrier.position = Vector2(0, -16)
	downed.position = carrier.position

	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_CARRY, "actor_ids": [carrier.id], "target_id": downed.id})
	assert_true(bool(result["accepted"]))
	BattleSimulation.advance(state, 1.1)

	assert_eq(carrier.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(downed.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(state.extracted_ids.count(carrier.hero_id), 1)
	assert_eq(state.extracted_ids.count(downed.hero_id), 1)
	assert_true(carrier.carrying_id.is_empty())
	assert_true(downed.carried_by_id.is_empty())


func test_full_wipe_strands_all_allies_without_deleting_them() -> void:
	var state: BattleState = _rescue_state(false)
	for actor: BattleActor in state.actors:
		if actor.faction == "ally":
			actor.hp = 0.0
			actor.life = BattleActor.LIFE_DOWNED
	BattleSimulation.advance(state, 0.1)
	var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)

	assert_eq(state.status, "stranded")
	assert_eq(outcome.stranded_hero_ids.size(), 2)
	assert_eq(outcome.secured_hero_ids.size(), 0)


func test_victory_secures_downed_hero() -> void:
	var state: BattleState = _rescue_state(false)
	state.status = "victory"
	var outcome: BattleOutcome = BattleSimulation.snapshot_outcome(state)

	assert_has(outcome.secured_hero_ids, "hero:rescuer")
	assert_has(outcome.secured_hero_ids, "hero:stranded")
	assert_false(outcome.stranded_hero_ids.has("hero:stranded"))


func test_malformed_carry_cycle_is_rejected() -> void:
	var state: BattleState = _rescue_state(false)
	var snapshot: Dictionary = state.to_dict()
	var actors: Array = snapshot["actors"] as Array
	(actors[0] as Dictionary)["carrying_id"] = str((actors[1] as Dictionary)["id"])
	(actors[0] as Dictionary)["carried_by_id"] = str((actors[1] as Dictionary)["id"])
	(actors[1] as Dictionary)["carrying_id"] = str((actors[0] as Dictionary)["id"])
	(actors[1] as Dictionary)["carried_by_id"] = str((actors[0] as Dictionary)["id"])

	assert_eq(BattleSimulation.validate_snapshot(snapshot), "A battle actor cannot carry and be carried simultaneously.")


func test_auto_rescuers_reserve_distinct_bodies() -> void:
	var state: BattleState = _rescue_state(false)
	var second_rescuer: Dictionary = {"hero_id": "hero:rescuer:2", "archetype": "ranger", "hp": 180.0, "atk": 40.0, "defense": 15.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [1.0, -16.0]}
	var second_body: Dictionary = {"hero_id": "hero:stranded:2", "archetype": "rogue", "hp": 100.0, "current_hp": 0.0, "life": "downed", "atk": 60.0, "defense": 10.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "", "position": [1.0, -16.0]}
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = []
	for actor: BattleActor in state.actors:
		snapshots.append(actor.to_dict())
	snapshots.append(second_rescuer)
	snapshots.append(second_body)
	var squads: Array[Dictionary] = [{"id": "rescue", "name": "Rescue", "hero_ids": ["hero:rescuer", "hero:rescuer:2"], "stance": "stay_together", "guard_target_id": ""}]
	state = BattleSimulation.create_run("rescue:2", snapshots, zone, squads, {"auto_battle": true}, {"healing": 0, "revival": 0}, 13, "rescue")

	BattleSimulation.advance(state, 0.1)
	var first: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var second: BattleActor = _actor_for_hero(state, "hero:rescuer:2")
	assert_ne(first.order_target_id, second.order_target_id)


func test_rescue_auto_battle_false_does_not_assign_objective_movement() -> void:
	var state: BattleState = _rescue_state(false)
	state.policies["auto_battle"] = false
	state.policies["auto_revive"] = false
	state.actors[0].set_abilities_auto(false)
	var rescuer: BattleActor = state.actors[0]

	BattleSimulation.advance(state, 0.1)

	assert_eq(rescuer.order_kind, "")


func test_rescue_skips_source_mission_progress_and_requires_extraction() -> void:
	var state: BattleState = _rescue_state(false)
	state.policies["auto_battle"] = false
	state.policies["auto_revive"] = false
	state.actors[0].set_abilities_auto(false)
	var original_actor_count: int = state.actors.size()
	var preserved_enemy: BattleActor = state.actors[2]
	preserved_enemy.hp = 0.0
	preserved_enemy.life = BattleActor.LIFE_DEAD

	BattleSimulation.advance(state, 0.1)

	assert_eq(state.status, "active")
	assert_eq(state.completed_waves, 0)
	assert_eq(state.actors.size(), original_actor_count)
	assert_eq(state.actors[1].life, BattleActor.LIFE_DOWNED)
	var rescuer: BattleActor = state.actors[0]
	rescuer.position = Vector2(0.0, -16.0)
	var retreat: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_RETREAT, "actor_ids": [rescuer.id]})
	assert_true(bool(retreat["accepted"]))
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.status, "stranded")
	assert_eq(rescuer.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(state.actors[1].life, BattleActor.LIFE_DOWNED)


func test_rescue_with_no_preserved_enemies_does_not_spawn_source_wave() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:rescuer", "archetype": "knight", "hp": 200.0, "atk": 40.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [0.0, -16.0]},
		{"hero_id": "hero:stranded", "archetype": "mage", "hp": 100.0, "current_hp": 0.0, "life": "downed", "atk": 60.0, "defense": 10.0, "speed": 95.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "", "position": [0.0, 0.0]},
	]
	var squads: Array[Dictionary] = [{"id": "rescue", "name": "Rescue", "hero_ids": ["hero:rescuer"], "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("rescue:no-enemies", snapshots, zone, squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 14, "rescue")

	assert_eq(state.actors.size(), 2)
	for actor: BattleActor in state.actors:
		assert_ne(actor.faction, "enemy")
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.status, "active")


func test_timeout_drops_carried_body_before_withdrawing_carrier() -> void:
	var state: BattleState = _rescue_state(false)
	state.policies["auto_battle"] = false
	state.policies["auto_revive"] = false
	state.max_seconds = 0.1
	var carrier: BattleActor = state.actors[0]
	carrier.set_abilities_auto(false)
	var body: BattleActor = state.actors[1]
	carrier.carrying_id = body.id
	body.carried_by_id = carrier.id
	body.position = carrier.position

	BattleSimulation.advance(state, 0.1)

	assert_eq(state.status, "timeout")
	assert_eq(carrier.life, BattleActor.LIFE_EXTRACTED)
	assert_eq(body.life, BattleActor.LIFE_DOWNED)
	assert_true(carrier.carrying_id.is_empty())
	assert_true(body.carried_by_id.is_empty())
	assert_eq(BattleSimulation.validate_snapshot(state.to_dict()), "")


# ig-ls3: carrying needs one second of channeling within range of the body, not one unbroken second
# (SYSTEMS.md § Downed heroes and rescue). The progress belongs to one (carrier, body) pair.
func test_carry_pauses_out_of_range_and_resumes_where_it_stopped() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	BattleSimulation.advance(state, 0.5)
	assert_almost_eq(_progress(carrier), 0.5, 0.001)
	carrier.position = body.position + Vector2(10.0, 0.0)
	BattleSimulation.advance(state, 0.5)
	assert_gt(carrier.position.distance_to(body.position), BattleSimulation.BALANCE.battle_carry_range, "still out of range")
	assert_almost_eq(_progress(carrier), 0.5, 0.001, "paused, not reset")
	carrier.position = body.position
	assert_eq(_ticks_to_lift(state, carrier, body), 5, "resumes: half a second more")


func test_a_stun_pauses_the_carry() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	BattleSimulation.advance(state, 0.5)
	carrier.effect_state["stun_remaining"] = 0.3
	BattleSimulation.advance(state, 0.2)
	assert_almost_eq(_progress(carrier), 0.5, 0.001, "held through the stun")
	assert_eq(_ticks_to_lift(state, carrier, body), 5, "resumes when the stun ends")


func test_a_root_pauses_the_carry() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	BattleSimulation.advance(state, 0.5)
	BattleSimulation._add_status(carrier, "test_root", "root", "test", 0.3, 0.0)
	BattleSimulation.advance(state, 0.2)
	assert_almost_eq(_progress(carrier), 0.5, 0.001, "held through the root")
	assert_eq(_ticks_to_lift(state, carrier, body), 5, "resumes when the root ends")


func test_the_rescue_ai_picking_another_body_starts_over() -> void:
	var state: BattleState = _carry_state([Vector2(10.0, -16.0)])
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var first: BattleActor = _actor_for_hero(state, "hero:stranded")
	var second: BattleActor = _actor_for_hero(state, "hero:stranded:2")
	BattleSimulation.advance(state, 0.6)
	assert_eq(carrier.order_target_id, first.id)
	assert_almost_eq(_progress(carrier), 0.6, 0.001)
	carrier.position = second.position
	assert_eq(_ticks_to_lift(state, carrier, second), 10, "a full second on the new body")
	assert_true(first.carried_by_id.is_empty())


func test_the_rescue_ai_keeps_progress_on_the_same_body_across_passes() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	BattleSimulation.advance(state, 0.6)
	assert_almost_eq(_progress(carrier), 0.6, 0.001, "every pass re-picks the body and keeps its progress")
	assert_eq(_ticks_to_lift(state, carrier, body), 4, "lifts at one second in all")


func test_a_downed_carrier_loses_its_progress() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	var enemy: BattleActor = _actor_for_hero(state, "")
	BattleSimulation.advance(state, 0.6)
	BattleSimulation._take_damage(state, enemy, carrier, carrier.hp + 1.0)
	assert_eq(carrier.life, BattleActor.LIFE_DOWNED)
	assert_false(carrier.effect_state.has("carry_progress"))
	BattleSimulation._revive_actor(state, carrier, 0.5, enemy)
	assert_eq(_ticks_to_lift(state, carrier, body), 10, "a full second after the revive")


# A body revived and downed again before the next planning pass is the same pair, but a new channel.
func test_a_body_revived_and_downed_again_starts_over() -> void:
	var state: BattleState = _carry_state()
	var carrier: BattleActor = _actor_for_hero(state, "hero:rescuer")
	var body: BattleActor = _actor_for_hero(state, "hero:stranded")
	var enemy: BattleActor = _actor_for_hero(state, "")
	BattleSimulation.advance(state, 0.6)
	BattleSimulation._revive_actor(state, body, 0.5, carrier)
	BattleSimulation._take_damage(state, enemy, body, body.hp + 1.0)
	assert_eq(body.life, BattleActor.LIFE_DOWNED)
	assert_false(carrier.effect_state.has("carry_progress"))
	assert_eq(_ticks_to_lift(state, carrier, body), 10, "a full second on the downed-again body")


# Boundary #1: a checkpoint saved mid-channel loads and resumes where it stopped.
func test_a_checkpoint_mid_channel_resumes_the_carry() -> void:
	var state: BattleState = _carry_state()
	BattleSimulation.advance(state, 0.5)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict())) as Dictionary
	assert_eq(BattleSimulation.validate_snapshot(saved), "")
	var loaded: BattleState = BattleState.from_dict(saved)
	var carrier: BattleActor = _actor_for_hero(loaded, "hero:rescuer")
	assert_almost_eq(_progress(carrier), 0.5, 0.001)
	assert_eq(_ticks_to_lift(loaded, carrier, _actor_for_hero(loaded, "hero:stranded")), 5)


func _progress(carrier: BattleActor) -> float:
	return float(carrier.effect_state.get("carry_progress", 0.0))


## Advances one tick at a time until carrier holds body (or has already carried it out at a near exit);
## the tick count, or -1 after 3 seconds.
func _ticks_to_lift(state: BattleState, carrier: BattleActor, body: BattleActor) -> int:
	for tick: int in range(1, 31):
		BattleSimulation.advance(state, 0.1)
		if carrier.carrying_id == body.id or (body.life == BattleActor.LIFE_EXTRACTED and carrier.life == BattleActor.LIFE_EXTRACTED):
			return tick
	return -1


## A ranger rescuer (no rally) on top of the stranded mage, no revival to spend, plus downed rogues at bodies.
func _carry_state(bodies: Array[Vector2] = []) -> BattleState:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:rescuer", "archetype": "ranger", "hp": 200.0, "atk": 40.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [0.0, -16.0]},
		{"hero_id": "hero:stranded", "archetype": "mage", "hp": 100.0, "current_hp": 0.0, "life": "downed", "atk": 60.0, "defense": 10.0, "speed": 95.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "", "position": [0.0, -16.0]},
		{"id": "enemy:preserved", "hero_id": "", "archetype": "knight", "faction": "enemy", "hp": 100.0, "atk": 0.0, "defense": 10.0, "speed": 20.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "enemy", "position": [15.0, 15.0]},
	]
	for index: int in bodies.size():
		snapshots.append({"hero_id": "hero:stranded:%d" % (index + 2), "archetype": "rogue", "hp": 100.0, "current_hp": 0.0, "life": "downed", "atk": 60.0, "defense": 10.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "", "position": [bodies[index].x, bodies[index].y]})
	var squads: Array[Dictionary] = [{"id": "rescue", "name": "Rescue", "hero_ids": ["hero:rescuer"], "stance": "stay_together", "guard_target_id": ""}]
	return BattleSimulation.create_run("rescue:carry", snapshots, zone, squads, {"auto_battle": true}, {"healing": 0, "revival": 0}, 12, "rescue")


func _actor_for_hero(state: BattleState, hero_id: String) -> BattleActor:
	for actor: BattleActor in state.actors:
		if actor.hero_id == hero_id:
			return actor
	return null


func _rescue_state(reserve_last: bool) -> BattleState:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:rescuer", "archetype": "knight", "hp": 200.0, "atk": 40.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "rescue", "position": [0.0, -16.0]},
		{"hero_id": "hero:stranded", "archetype": "mage", "hp": 100.0, "current_hp": 0.0, "life": "downed", "atk": 60.0, "defense": 10.0, "speed": 95.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "", "position": [0.0, -16.0]},
		{"id": "enemy:preserved", "hero_id": "", "archetype": "knight", "faction": "enemy", "hp": 100.0, "atk": 0.0, "defense": 10.0, "speed": 20.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "enemy", "position": [15.0, 15.0]},
	]
	var squads: Array[Dictionary] = [{"id": "rescue", "name": "Rescue", "hero_ids": ["hero:rescuer"], "stance": "stay_together", "guard_target_id": ""}]
	return BattleSimulation.create_run("rescue:1", snapshots, zone, squads, {"auto_battle": true, "reserve_last_revival": reserve_last}, {"healing": 0, "revival": 1}, 12, "rescue")
