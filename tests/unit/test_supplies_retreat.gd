extends GutTest
## ig-axw: "Retreat when supplies run out" really sends the heroes out.

const BALANCE: BalanceTable = preload("res://balance.tres")
const IDS: Array[String] = ["hero:a", "hero:b", "hero:c"]
const EMPTY: Dictionary = {"healing": 0, "revival": 0}


func test_out_of_supplies_every_ally_on_auto_walks_out_and_extracts() -> void:
	for auto_battle: bool in [true, false]:
		var state: BattleState = _run({"retreat_when_supplies_empty": true, "auto_battle": auto_battle}, EMPTY)
		BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
		for ally: BattleActor in _allies(state):
			assert_eq(ally.order_kind, BattleSimulation.COMMAND_RETREAT, "auto_battle %s: %s" % [auto_battle, ally.id])
		BattleSimulation.advance(state, state.max_seconds)
		# Not a timeout, which pulls every living ally out wherever it stands: each walked to the exit.
		assert_eq(state.status, "retreated", "auto_battle %s" % auto_battle)
		assert_lt(state.elapsed_seconds, state.max_seconds)
		for ally: BattleActor in _allies(state):
			assert_eq(ally.life, BattleActor.LIFE_EXTRACTED, "auto_battle %s: %s" % [auto_battle, ally.id])
			assert_lte(ally.position.distance_to(Vector2(0, -16)), BALANCE.battle_exit_radius + 0.01, ally.id)
		assert_eq(state.extracted_ids.size(), IDS.size())


func test_policy_off_or_supplies_left_never_retreats() -> void:
	for setup: Array in [[{"retreat_when_supplies_empty": false}, EMPTY], [{"retreat_when_supplies_empty": false, "auto_battle": false}, EMPTY], [{"retreat_when_supplies_empty": true}, {"healing": 1, "revival": 0}]]:
		var state: BattleState = _run(setup[0], setup[1])
		for _step: int in 20:
			BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
			for ally: BattleActor in _allies(state):
				assert_ne(ally.order_kind, BattleSimulation.COMMAND_RETREAT, "%s: %s" % [setup, ally.id])
		assert_true(state.extracted_ids.is_empty(), str(setup))


func test_a_direct_order_overrides_the_retreat() -> void:
	var state: BattleState = _run({"retreat_when_supplies_empty": true}, EMPTY)
	var mover: BattleActor = _allies(state)[0]
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_MOVE, "actor_ids": [mover.id], "point": [6.0, 0.0]})
	assert_true(bool(result.get("accepted", false)), str(result))
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_eq(mover.order_kind, BattleSimulation.COMMAND_MOVE)
	for ally: BattleActor in _allies(state).slice(1):
		assert_eq(ally.order_kind, BattleSimulation.COMMAND_RETREAT, ally.id)


func test_a_telegraph_evade_still_wins_its_tick() -> void:
	var state: BattleState = _run({"retreat_when_supplies_empty": true}, EMPTY)
	var dodger: BattleActor = _allies(state)[0]
	var caster: BattleActor = null
	for actor: BattleActor in state.actors:
		if actor.faction == "enemy":
			caster = actor
	assert_not_null(caster)
	# A circle on the dodger alone, too fresh for a hero to answer this tick.
	caster.effect_state.merge({"telegraph_kind": "circle", "telegraph_point": [dodger.position.x, dodger.position.y],
		"telegraph_origin": [caster.position.x, caster.position.y], "telegraph_radius": 0.5, "telegraph_remaining": 5.0, "telegraph_total": 5.0}, true)
	var before: String = dodger.order_kind
	BattleSimulation.advance(state, BALANCE.battle_tick_seconds)
	assert_true(dodger.effect_state.get("evade_point") is Array, "the dodger evades")
	assert_eq(dodger.order_kind, before, "the evade tick leaves its order alone")
	for ally: BattleActor in _allies(state).slice(1):
		assert_eq(ally.order_kind, BattleSimulation.COMMAND_RETREAT, ally.id)


func _run(policies: Dictionary, supplies: Dictionary) -> BattleState:
	var heroes: Array[Dictionary] = []
	for index: int in IDS.size():
		heroes.append({"hero_id": IDS[index], "archetype": ["knight", "ranger", "mage"][index], "hp": 200.0, "atk": 50.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.1, "crit_damage": 1.5, "squad_id": "squad:0"})
	var squads: Array[Dictionary] = [{"id": "squad:0", "name": "Alpha", "hero_ids": IDS, "stance": "stay_together", "guard_target_id": ""}]
	return BattleSimulation.create_run("order:axw", heroes, _zone(), squads, policies, supplies, 7)


func _allies(state: BattleState) -> Array[BattleActor]:
	var allies: Array[BattleActor] = []
	for actor: BattleActor in state.actors:
		if actor.faction == "ally":
			allies.append(actor)
	return allies


func _zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"verdant_outskirts"
	zone.recommended_power = 20
	zone.trash_wave_count = 1
	zone.trash_wave_start_fraction = 0.5
	zone.trash_wave_end_fraction = 0.5
	zone.boss_fraction = 1.0
	zone.reference_force_size = 1
	zone.trash_enemy_count = 1
	zone.max_battle_seconds = 30.0
	zone.exit_position = Vector2(0, -16)
	return zone
