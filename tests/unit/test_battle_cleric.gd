extends GutTest

## ig-4if: the Cleric's Grace + Mend (SYSTEMS.md § Skills, Cleric).


func test_cleric_default_kit_is_grace_then_mend() -> void:
	var kit: Array[AbilityDefinition] = BattleSimulation.default_kit("cleric")
	assert_eq(kit.map(func(skill: AbilityDefinition) -> String: return str(skill.skill_id)), ["cleric_grace", "cleric_mend"])
	assert_same(BattleSimulation.signature_for("cleric"), BattleSimulation.ABILITIES["cleric_mend"])


func test_mend_heals_three_atk_with_grace_then_holds_eight_seconds() -> void:
	var state: BattleState = _run(16.0, 30.0)
	var cleric: BattleActor = state.actors[0]
	var knight: BattleActor = state.actors[1]

	BattleSimulation.advance(state, 0.1)

	assert_almost_eq(knight.hp, 30.0 + 16.0 * 3.0 * 1.2, 0.0001, "3.0 x ATK, +20% Grace")
	assert_almost_eq(cleric.skill_cooldowns["cleric_mend"], 8.0, 0.1001)
	assert_gt(int(cleric.effect_state["last_skill_tick"]), 0)
	knight.hp = 30.0
	BattleSimulation.advance(state, 7.7)
	assert_eq(knight.hp, 30.0, "still on cooldown")
	BattleSimulation.advance(state, 0.4)
	assert_gt(knight.hp, 30.0, "ready again after 8 s")


func test_mend_never_heals_past_max_hp() -> void:
	var state: BattleState = _run(100.0, 30.0)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].hp, state.actors[1].max_hp)


func test_mend_waits_until_an_ally_is_below_heal_below() -> void:
	var state: BattleState = _run(16.0, 40.0)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].hp, 40.0, "hurt, but above heal_below")
	assert_eq(state.actors[0].skill_cooldowns["cleric_mend"], 0.0, "no cast, no cooldown")


func test_mend_skips_downed_and_out_of_range_allies() -> void:
	var state: BattleState = _run(16.0, 0.0)
	var knight: BattleActor = state.actors[1]
	assert_eq(knight.life, BattleActor.LIFE_DOWNED)
	BattleSimulation.advance(state, 0.1)
	assert_eq(knight.life, BattleActor.LIFE_DOWNED, "Mend is not a revive")
	assert_eq(knight.hp, 0.0)

	state = _run(16.0, 30.0)
	state.actors[1].position = state.actors[0].position + Vector2(6.5, 0.0)
	BattleSimulation.advance(state, 0.1)
	assert_eq(state.actors[1].hp, 30.0, "range 6")


func test_manual_mend_waits_for_the_command() -> void:
	var state: BattleState = _run(16.0, 30.0)
	var cleric: BattleActor = state.actors[0]
	var knight: BattleActor = state.actors[1]
	var result: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_SET_ABILITY_AUTO, "actor_ids": [cleric.id], "value": false})
	assert_true(bool(result["accepted"]))
	BattleSimulation.advance(state, 0.1)
	assert_eq(knight.hp, 30.0, "Manual: the AI leaves it alone")

	var full_hp_cast: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [cleric.id], "target_id": cleric.id, "point": [cleric.position.x, cleric.position.y]})
	assert_false(bool(full_hp_cast["accepted"]), "a full-HP target is refused")
	knight.position = cleric.position + Vector2(6.5, 0.0)
	var far_cast: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [cleric.id], "target_id": knight.id, "point": [cleric.position.x, cleric.position.y]})
	assert_false(bool(far_cast["accepted"]), "range 6 is measured to the target, not to the point sent with it")
	knight.position = cleric.position + Vector2(2.0, 0.0)
	# What the battle view sends for a clicked unit: a target and no point.
	var cast: Dictionary = BattleSimulation.issue_command(state, {"kind": BattleSimulation.COMMAND_ABILITY, "actor_ids": [cleric.id], "target_id": knight.id})
	assert_true(bool(cast["accepted"]))
	assert_almost_eq(knight.hp, 87.6, 0.0001)
	assert_eq(BattleSimulation.validate_snapshot(state.to_dict()), "")


func test_cleric_kit_survives_a_profile_save_and_reload() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	var hero := Hero.new("Healer", 0)
	hero.def_id = &"cleric"
	hero.instance_id = "hero:healer"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Healer", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	GameSession.tick_expeditions(0.5)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict())) as Dictionary
	assert_eq(GameSession.validate_saved_state(saved, 3), "")
	GameSession.from_dict(saved)
	var actor: Dictionary = (GameSession.get_battle_snapshot(order_id)["actors"] as Array)[0]
	# A level-0 hero carries its level-1 kit: Grace, Mend, the Censer Swing weaponskill (no cooldown) and
	# Hearthward (ig-vl1.4).
	assert_eq(actor["skills"], [{"id": "cleric_grace", "mode": "auto"}, {"id": "cleric_mend", "mode": "auto"}, {"id": "cleric_censer_swing", "mode": "auto"}, {"id": "cleric_hearthward", "mode": "auto"}])
	assert_eq((actor["skill_cooldowns"] as Dictionary).keys(), ["cleric_hearthward", "cleric_mend"])
	GameSession.set("_save_deferred_depth", 0)


## A Cleric and a Knight (max HP 100, so 30 is below heal_below 0.35) standing 2 apart, nothing
## else acting: no enemies, no supplies, Auto Battle off. Pace 1: the authored numbers (test_battle_pace
## covers xP).
func _run(cleric_atk: float, knight_hp: float) -> BattleState:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var snapshots: Array[Dictionary] = [
		{"hero_id": "hero:cleric", "archetype": "cleric", "hp": 110.0, "atk": cleric_atk, "defense": 10.0, "speed": 95.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "s", "position": [0.0, -16.0]},
		{"hero_id": "hero:knight", "archetype": "knight", "hp": 100.0, "current_hp": knight_hp, "life": "alive" if knight_hp > 0.0 else "downed", "atk": 10.0, "defense": 20.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "squad_id": "s", "position": [2.0, -16.0]},
	]
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": ["hero:cleric", "hero:knight"], "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = BattleSimulation.create_run("cleric:1", snapshots, zone, squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 5, "rescue", 1)
	state.actors[1].set_abilities_auto(false)
	return state
