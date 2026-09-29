extends GutTest

## ig-gy0.2: the primitives, the status list and the one picker (SYSTEMS.md § Skills).

const SIM = preload("res://combat/battle/battle_simulation.gd")


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_every_skill_validates_and_the_kits_open_by_level() -> void:
	assert_eq(SIM.ABILITIES.size(), 52)
	for skill_id: String in SIM.ABILITIES:
		assert_eq(SIM.ABILITIES[skill_id].validate(), "", skill_id)
		assert_eq(str(SIM.ABILITIES[skill_id].skill_id), skill_id)
	for archetype: String in ["knight", "ranger", "mage", "rogue", "cleric"]:
		var sizes: Array = [1, 5, 15, 25, 100].map(func(level: int) -> int: return SIM.known_kit(archetype, level).size())
		# The Knight also opens Charge and Ground Slam at level 1 (ig-zht), the Mage Rime Circle and the
		# Cleric Hearthward (ig-vl1.4), and the Mage Rime Wall (ig-vl1.5).
		var want: Array = [5, 7, 8, 9, 9] if archetype in ["knight", "mage"] else [4, 6, 7, 8, 8] if archetype == "cleric" else [3, 5, 6, 7, 7]
		assert_eq(sizes, want, "%s: 3 at level 1, then one or two per tier; the book skill never" % archetype)
	assert_eq(_ids(SIM.known_kit("knight", 5)), ["knight_bulwark", "knight_rally", "knight_iron_cut", "knight_follow_through", "knight_buckler_blow", "knight_charge", "knight_ground_slam"])


## General skills add no damage by construction, not only while they sit unused.
func test_no_general_skill_deals_damage() -> void:
	var generals: Array = []
	for path: String in DirAccess.get_files_at("res://combat/abilities"):
		if not path.trim_suffix(".remap").ends_with(".tres"):
			continue
		var skill: AbilityDefinition = load("res://combat/abilities/%s" % path.trim_suffix(".remap")) as AbilityDefinition
		if skill.archetype == "general":
			generals.append(str(skill.skill_id))
			for effect: Dictionary in skill.effects:
				assert_ne(str(effect["type"]), "damage", "%s must not deal damage" % skill.skill_id)
	assert_eq(generals.size(), 6, str(generals))


func test_a_level_snapshot_carries_its_known_kit_and_legal_learned_skills() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var fresh: BattleActor = SIM._actor_from_team_snapshot(_unit("hero:a", "knight", "ally", Vector2.ZERO, {"level": 0}), 0, zone)
	assert_eq(_kit(fresh), ["knight_bulwark", "knight_rally", "knight_iron_cut", "knight_charge", "knight_ground_slam"], "level 0 has the level-1 kit")
	var learned: Array = ["knight_anvilheart", "general_brace", "mage_hanging_star", "knight_rally", "no_such_skill"]
	var veteran: BattleActor = SIM._actor_from_team_snapshot(_unit("hero:b", "knight", "ally", Vector2.ZERO, {"level": 15, "learned_skills": learned, "ability_auto": false}), 0, zone)
	assert_eq(_kit(veteran), ["knight_bulwark", "knight_rally", "knight_iron_cut", "knight_follow_through", "knight_buckler_blow", "knight_gauntlet_toss", "knight_charge", "knight_ground_slam", "knight_anvilheart", "general_brace"])
	assert_eq(veteran.skills[1]["mode"], "manual")
	assert_eq(veteran.skills[2]["mode"], "auto", "a weaponskill is always on")
	assert_eq(veteran.skill_cooldowns.keys(), ["knight_rally", "knight_buckler_blow", "knight_gauntlet_toss", "knight_charge", "knight_ground_slam", "knight_anvilheart", "general_brace"])
	var plain: BattleActor = SIM._actor_from_team_snapshot(_unit("hero:c", "knight", "ally", Vector2.ZERO), 0, zone)
	assert_eq(_kit(plain), ["knight_bulwark", "knight_rally"], "no level, no skills: the default kit")


func test_a_status_refreshes_instead_of_stacking_and_the_strongest_reduction_wins() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("hero:r", "ranger", "ally", Vector2(1, -16)), _unit("enemy:1", "knight", "enemy", Vector2(5, -16))])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[2]
	_give(knight, ["knight_rally", "general_brace"])
	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_rally"], knight, knight.position))
	assert_eq(state.actors[1].statuses, [{"id": "knight_rally", "kind": "damage_reduction", "source": knight.id, "remaining": 4.0, "magnitude": 0.3}], "Stand Fast covers the ally near")
	SIM._add_status(knight, "knight_rally", "damage_reduction", "someone", 2.0, 0.1)
	assert_eq(knight.statuses, [{"id": "knight_rally", "kind": "damage_reduction", "source": "someone", "remaining": 4.0, "magnitude": 0.3}], "refreshed: the longer time, the larger magnitude, one entry")
	SIM._add_status(knight, "general_brace", "damage_reduction", knight.id, 4.0, 0.25)
	assert_eq(knight.statuses.size(), 2)
	SIM._damage(state, enemy, knight, 1.0, null)
	assert_almost_eq(knight.hp, 100.0 - 10.0 * 0.7, 0.0001, "0.3 wins; 0.25 does not multiply in")


func test_a_shield_soaks_damage_before_hp_and_is_dropped_when_spent() -> void:
	var state: BattleState = _battle([_unit("hero:m", "mage", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(2, -16), {"current_hp": 40.0}), _unit("enemy:1", "knight", "enemy", Vector2(3, -16), {"atk": 15.0})])
	var mage: BattleActor = state.actors[0]
	var knight: BattleActor = state.actors[1]
	var enemy: BattleActor = state.actors[2]
	_give(mage, ["mage_arcane_flow", "mage_warding_glyph"])
	assert_eq(SIM._rule_aim(state, mage, SIM.ABILITIES["mage_warding_glyph"], null, "heal"), knight, "below half")
	assert_true(SIM._use_skill(state, mage, SIM.ABILITIES["mage_warding_glyph"], knight, knight.position))
	assert_eq(knight.statuses, [{"id": "mage_warding_glyph", "kind": "shield", "source": mage.id, "remaining": 6.0, "magnitude": 20.0}], "2 x ATK")
	assert_almost_eq(mage.skill_cooldowns["mage_warding_glyph"], 22.5, 0.0001, "Arcane Flow: 25 x 0.9")
	SIM._damage(state, enemy, knight, 1.0, null)
	assert_eq(knight.hp, 40.0, "15 soaked")
	assert_almost_eq(float(knight.statuses[0]["magnitude"]), 5.0, 0.0001)
	SIM._damage(state, enemy, knight, 1.0, null)
	assert_almost_eq(knight.hp, 30.0, 0.0001, "5 soaked, 10 through")
	SIM._tick_statuses(state, knight)
	assert_eq(knight.statuses, [], "a spent shield is dropped")


func test_bleed_ticks_each_second_through_damage_reduction_and_credits_the_kill() -> void:
	var state: BattleState = _battle([_unit("hero:r", "ranger", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(5, -16))])
	var ranger: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	_give(ranger, ["ranger_heron_shot", "ranger_barbed_arrow"])
	assert_eq(SIM._pick_weaponskill(state, ranger, enemy), SIM.ABILITIES["ranger_barbed_arrow"], "the target has no bleed")
	SIM._use_weaponskill(state, ranger, SIM.ABILITIES["ranger_barbed_arrow"], enemy, null)
	assert_almost_eq(enemy.hp, 90.0, 0.0001)
	assert_eq(enemy.statuses, [{"id": "ranger_barbed_arrow", "kind": "bleed", "source": ranger.id, "remaining": 8.0, "magnitude": 1.5}])
	assert_eq(SIM._pick_weaponskill(state, ranger, enemy), SIM.ABILITIES["ranger_heron_shot"], "bled already: the default")
	SIM._add_status(enemy, "test_guard", "damage_reduction", "", 99.0, 0.2)
	for tick: int in 9:
		SIM._tick_statuses(state, enemy)
	assert_almost_eq(enemy.hp, 90.0, 0.0001, "nothing before a full second")
	SIM._tick_statuses(state, enemy)
	assert_almost_eq(enemy.hp, 90.0 - 1.5 * 0.8, 0.0001, "0.15 x ATK a second, through the reduction")
	enemy.hp = 1.0
	for tick: int in 10:
		SIM._tick_statuses(state, enemy)
	assert_eq(enemy.life, BattleActor.LIFE_DEAD)
	assert_eq(state.kills, {"hero:r": 1}, "the bleed's source gets the kill")
	assert_true(state.moments.is_empty(), "statuses write nothing to the Ledger")


func test_wellspring_heals_over_time_with_grace() -> void:
	var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(2, -16), {"current_hp": 50.0})])
	var cleric: BattleActor = state.actors[0]
	var knight: BattleActor = state.actors[1]
	_give(cleric, ["cleric_grace", "cleric_wellspring"])
	assert_true(SIM._auto_cast(state, cleric, null, ["heal"], null))
	assert_eq(knight.statuses.size(), 1)
	assert_eq([knight.statuses[0]["kind"], knight.statuses[0]["remaining"]], ["heal_over_time", 10.0])
	assert_almost_eq(float(knight.statuses[0]["magnitude"]), 3.6, 0.0001, "0.3 x ATK, +20% Grace")
	assert_null(SIM._rule_aim(state, cleric, SIM.ABILITIES["cleric_wellspring"], null, "heal"), "not on someone who has it")
	for tick: int in 10:
		SIM._tick_statuses(state, knight)
	assert_almost_eq(knight.hp, 53.6, 0.0001)


func test_interrupts_stun_root_and_silence() -> void:
	var state: BattleState = _battle([_unit("hero:r", "ranger", "ally", Vector2(0, -16)), _unit("hero:c", "cleric", "ally", Vector2(1, -16)), _unit("hero:k", "knight", "ally", Vector2(4, -16)), _unit("enemy:1", "rogue", "enemy", Vector2(5, -16))])
	var ranger: BattleActor = state.actors[0]
	var cleric: BattleActor = state.actors[1]
	var knight: BattleActor = state.actors[2]
	var enemy: BattleActor = state.actors[3]
	_give(ranger, ["ranger_pinning_shot"])
	_give(cleric, ["cleric_hush"])
	_give(knight, ["knight_buckler_blow"])
	_give(enemy, ["rogue_quick_cut", "rogue_slip"])
	enemy.effect_state["attack_windup_remaining"] = 0.5
	assert_true(SIM._use_skill(state, ranger, SIM.ABILITIES["ranger_pinning_shot"], enemy, enemy.position))
	assert_eq(enemy.effect_state["attack_windup_remaining"], 0.0, "the swing is cut")
	assert_almost_eq(enemy.hp, 95.0, 0.0001)
	assert_true(SIM._has_status(enemy, "root"))
	assert_false(SIM._use_skill(state, enemy, SIM.ABILITIES["rogue_slip"], ranger, enemy.position), "rooted: no move skill")
	enemy.order_kind = SIM.COMMAND_MOVE
	enemy.order_point = Vector2(12, -16)
	SIM._move_actors(state)
	assert_eq(enemy.position, Vector2(5, -16), "rooted: it stays put")

	assert_true(SIM._use_skill(state, cleric, SIM.ABILITIES["cleric_hush"], enemy, enemy.position))
	enemy.statuses = enemy.statuses.filter(func(status: Dictionary) -> bool: return status["kind"] != "root")
	assert_false(SIM._use_skill(state, enemy, SIM.ABILITIES["rogue_slip"], ranger, enemy.position), "silenced: no ability")
	assert_null(SIM._pick_weaponskill(state, enemy, ranger), "silenced: basic hits only")

	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_buckler_blow"], enemy, enemy.position))
	assert_eq(enemy.effect_state["stun_remaining"], 1.5)
	assert_almost_eq(enemy.hp, 87.0, 0.0001)


func test_challenge_pulls_an_enemy_off_a_weaker_ally() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("hero:r", "ranger", "ally", Vector2(4, -16), {"current_hp": 30.0}), _unit("enemy:1", "knight", "enemy", Vector2(5, -16))])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[2]
	_give(knight, ["knight_gauntlet_toss"])
	enemy.order_kind = SIM.COMMAND_ATTACK
	enemy.order_target_id = "hero:hero:r"
	assert_gt(knight.position.distance_to(enemy.position), knight.attack_range, "out of the Knight's swing, inside Gauntlet Toss's 6")
	SIM._offensive_actions(state, null)
	assert_gt(knight.skill_cooldowns["knight_gauntlet_toss"], 0.0)
	assert_eq(enemy.statuses, [{"id": "knight_gauntlet_toss", "kind": "taunt", "source": knight.id, "remaining": 4.0, "magnitude": 0.0}])
	SIM._choose_enemy_intention(state, enemy)
	assert_eq(enemy.order_target_id, knight.id)


func test_a_dodge_slips_a_telegraph_that_lands_on_everyone_else() -> void:
	var state: BattleState = _battle([_unit("hero:g", "rogue", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16)), _unit("enemy:1", "mage", "enemy", Vector2(3, -16))])
	var rogue: BattleActor = state.actors[0]
	var knight: BattleActor = state.actors[1]
	var enemy: BattleActor = state.actors[2]
	_give(rogue, ["rogue_slip"])
	_give(enemy, ["mage_burst"])
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["mage_burst"], Vector2(0.5, -16), 1.0)
	assert_true(SIM._use_skill(state, rogue, SIM.ABILITIES["rogue_slip"], enemy, rogue.position))
	assert_almost_eq(rogue.position.x, -2.0, 0.0001, "two back from the enemy, still inside the circle")
	SIM._resolve_telegraph(state, enemy, null)
	assert_eq(rogue.hp, 100.0, "dodged")
	assert_almost_eq(knight.hp, 85.0, 0.0001, "Arcane Bloom: 1.5 x ATK")


func test_hanging_star_marks_its_circle_and_lands_a_second_later() -> void:
	var state: BattleState = _battle([_unit("hero:m", "mage", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(6, -16)), _unit("enemy:2", "knight", "enemy", Vector2(7, -16)), _unit("enemy:3", "knight", "enemy", Vector2(10, -16))])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_arcane_flow", "mage_hanging_star"])
	for enemy: BattleActor in state.actors.slice(1):
		_give(enemy, [])
		enemy.effect_state["stun_remaining"] = 999.0
	assert_true(SIM._use_skill(state, mage, SIM.ABILITIES["mage_hanging_star"], state.actors[1], state.actors[1].position))
	assert_eq(str(mage.effect_state["telegraph_skill"]), "mage_hanging_star")
	assert_almost_eq(mage.skill_cooldowns["mage_hanging_star"], 40.5, 0.0001, "Arcane Flow: 45 x 0.9")
	SIM.advance(state, 0.9)
	assert_eq(state.actors[1].hp, 100.0, "not yet")
	SIM.advance(state, 0.1)  # ig-85w: the 1.0 s telegraph lands on tick 10
	assert_eq(state.actors.slice(1).map(func(enemy: BattleActor) -> float: return enemy.hp), [75.0, 75.0, 100.0], "2.5 x ATK within 3")
	assert_eq(str(mage.effect_state["telegraph_kind"]), "")


func test_area_weaponskills_hit_around_the_caster_and_near_the_target() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16)), _unit("enemy:2", "knight", "enemy", Vector2(-1, -16)), _unit("enemy:3", "knight", "enemy", Vector2(0, -15)), _unit("enemy:4", "knight", "enemy", Vector2(0, -13))])
	var knight: BattleActor = state.actors[0]
	_give(knight, ["knight_iron_cut", "knight_sweeping_blow"])
	assert_eq(SIM._pick_weaponskill(state, knight, state.actors[1]), SIM.ABILITIES["knight_sweeping_blow"], "three within 2")
	SIM._use_weaponskill(state, knight, SIM.ABILITIES["knight_sweeping_blow"], state.actors[1], null)
	assert_eq(state.actors.slice(1).map(func(enemy: BattleActor) -> float: return snappedf(enemy.hp, 0.0001)), [91.0, 91.0, 91.0, 100.0])

	state = _battle([_unit("hero:m", "mage", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(6, -16)), _unit("enemy:2", "knight", "enemy", Vector2(7, -16)), _unit("enemy:3", "knight", "enemy", Vector2(6, -14)), _unit("enemy:4", "knight", "enemy", Vector2(8.5, -16)), _unit("enemy:5", "knight", "enemy", Vector2(6, -12))])
	var mage: BattleActor = state.actors[0]
	_give(mage, ["mage_ember_bolt", "mage_chain_spark"])
	assert_eq(SIM._pick_weaponskill(state, mage, state.actors[1]), SIM.ABILITIES["mage_chain_spark"])
	SIM._use_weaponskill(state, mage, SIM.ABILITIES["mage_chain_spark"], state.actors[1], null)
	assert_eq(state.actors.slice(1).map(func(enemy: BattleActor) -> float: return snappedf(enemy.hp, 0.0001)), [90.0, 94.0, 94.0, 100.0, 100.0], "the two nearest within 3")


func test_heal_primitives_and_the_revive_band_goes_first() -> void:
	var state: BattleState = _battle([
		_unit("hero:c", "cleric", "ally", Vector2(0, -16), {"current_hp": 30.0}),
		_unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 50.0}),
		_unit("hero:r", "ranger", "ally", Vector2(2, -16), {"current_hp": 50.0}),
		_unit("hero:m", "mage", "ally", Vector2(6, -16), {"current_hp": 50.0}),
		_unit("hero:g", "rogue", "ally", Vector2(1, -15), {"current_hp": 0.0, "life": "downed"}),
	])
	var cleric: BattleActor = state.actors[0]
	var rogue: BattleActor = state.actors[4]
	_give(cleric, ["cleric_prayer_circle", "cleric_mend", "general_catch_breath", "cleric_hearthcall"])
	SIM._support_actions(state)
	assert_eq(rogue.life, BattleActor.LIFE_ALIVE, "Hearthcall before Mend, though Mend sits earlier on the bar")
	assert_almost_eq(rogue.hp, 30.0, 0.0001)
	assert_eq(cleric.skill_cooldowns["cleric_mend"], 0.0)
	assert_eq(state.moments.map(func(moment: Dictionary) -> String: return str(moment["what"])), ["revived"])
	cleric.ability_lock = 0.0
	assert_true(SIM._auto_cast(state, cleric, null, ["heal"], null), "four below 70% within 4: Prayer Circle")
	assert_eq(state.actors.map(func(ally: BattleActor) -> float: return snappedf(ally.hp, 0.0001)), [45.0, 65.0, 65.0, 50.0, 45.0], "1.5 x ATK within 4")
	cleric.ability_lock = 0.0
	cleric.skill_cooldowns["cleric_mend"] = 8.0
	assert_false(SIM._auto_cast(state, cleric, null, ["heal"], null), "45% is not below Catch Breath's 40%")
	cleric.hp = 30.0
	assert_true(SIM._auto_cast(state, cleric, null, ["heal"], null))
	assert_almost_eq(cleric.hp, 50.0, 0.0001, "a fifth of max HP")


func test_same_band_heals_go_in_bar_order() -> void:
	for kit: Array in [["cleric_wellspring", "cleric_mend"], ["cleric_mend", "cleric_wellspring"]]:
		var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 30.0})])
		_give(state.actors[0], kit)
		SIM._support_actions(state)
		assert_eq(state.actors[0].skill_cooldowns[kit[0]] > 0.0, true, "%s: the first on the bar" % str(kit))
		assert_eq(state.actors[0].skill_cooldowns[kit[1]], 0.0, str(kit))


func test_field_dressing_waits_while_a_class_heal_is_ready() -> void:
	for kit: Array in [["general_field_dressing", "cleric_mend"], ["cleric_mend", "general_field_dressing"]]:
		var heal_state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 30.0})])
		_give(heal_state.actors[0], kit)
		SIM._support_actions(heal_state)
		assert_almost_eq(heal_state.actors[1].hp, 60.0, 0.0001, "%s: Mend, wherever it sits" % str(kit))
	var state: BattleState = _battle([_unit("hero:c", "cleric", "ally", Vector2(0, -16)), _unit("hero:k", "knight", "ally", Vector2(1, -16), {"current_hp": 30.0})])
	var cleric: BattleActor = state.actors[0]
	_give(cleric, ["general_field_dressing", "cleric_mend"])
	cleric.skill_cooldowns["cleric_mend"] = 5.0
	SIM._support_actions(state)
	assert_almost_eq(state.actors[1].hp, 45.0, 0.0001, "Mend cooling down: Field Dressing, 1.5 x ATK")
	state = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16), {"current_hp": 30.0})])
	_give(state.actors[0], ["general_field_dressing"])
	SIM._support_actions(state)
	assert_almost_eq(state.actors[0].hp, 45.0, 0.0001, "a hero with no class heal uses it on itself")


func test_iron_cut_then_follow_through_lands_the_combo_inside_its_window() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16), {"hp": 1000.0})])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	_give(knight, ["knight_iron_cut", "knight_follow_through"])
	assert_eq(knight.skill_cooldowns, {}, "weaponskills have no cooldown")
	var landed: Array[float] = []
	for swing: int in 3:
		var before: float = enemy.hp
		SIM._use_weaponskill(state, knight, SIM._pick_weaponskill(state, knight, enemy), enemy, null)
		landed.append(snappedf(before - enemy.hp, 0.0001))
	assert_eq(landed, [13.0, 18.0, 13.0], "Iron Cut, Follow-Through at 1.8, then the chain restarts")
	state.tick += 60
	assert_eq(SIM._pick_weaponskill(state, knight, enemy), SIM.ABILITIES["knight_follow_through"], "6 s is still inside")
	state.tick += 1
	assert_eq(SIM._pick_weaponskill(state, knight, enemy), SIM.ABILITIES["knight_iron_cut"], "the window closed")
	knight.combo_skill = ""
	var before_plain: float = enemy.hp
	SIM._use_weaponskill(state, knight, SIM.ABILITIES["knight_follow_through"], enemy, null)
	assert_almost_eq(before_plain - enemy.hp, 11.0, 0.0001, "out of combo: 1.1")


func test_an_ability_locks_the_others_for_one_second() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("hero:r", "ranger", "ally", Vector2(1, -16))])
	var knight: BattleActor = state.actors[0]
	_give(knight, ["knight_rally", "general_brace"])
	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_rally"], knight, knight.position))
	assert_eq(knight.ability_lock, 1.0)
	assert_false(SIM._use_skill(state, knight, SIM.ABILITIES["general_brace"], knight, knight.position))
	for tick: int in 9:
		SIM._expire_effects_and_cooldowns(state)
	assert_false(SIM._use_skill(state, knight, SIM.ABILITIES["general_brace"], knight, knight.position))
	# ig-85w: timers are tick-exact, so the 1.0 s lock clears on tick 10.
	SIM._expire_effects_and_cooldowns(state)
	assert_eq(knight.ability_lock, 0.0)
	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["general_brace"], knight, knight.position))


## ig-85w: a timer of t seconds ends on tick t / 0.1, exactly: an 8.0 s skill cooldown on tick 80 and a
## 0.3 s stun on tick 3.
func test_timers_end_on_the_tick_their_seconds_say() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16))])
	var knight: BattleActor = state.actors[0]
	knight.skill_cooldowns["knight_rally"] = 8.0
	knight.effect_state["stun_remaining"] = 0.3
	for tick: int in range(1, 81):
		SIM._expire_effects_and_cooldowns(state)
		if tick == 2:
			assert_gt(float(knight.effect_state["stun_remaining"]), 0.0, "stunned after tick 2")
		elif tick == 3:
			assert_eq(float(knight.effect_state["stun_remaining"]), 0.0, "the stun ends on tick 3")
		elif tick == 79:
			assert_gt(float(knight.skill_cooldowns["knight_rally"]), 0.0, "cooling after tick 79")
	assert_eq(float(knight.skill_cooldowns["knight_rally"]), 0.0, "ready on tick 80")


## A test-only kit: 32 skills across the classes, which no save would accept; the fight must still run.
func test_a_thirty_two_skill_actor_fights_a_full_battle() -> void:
	var snapshots: Array[Dictionary] = []
	for index: int in 5:
		snapshots.append(_unit("hero:%d" % index, SIM.ROLE_CYCLE[index], "ally", Vector2(-2.0 + index, -16.0), {"hp": 400.0, "atk": 30.0, "defense": 20.0}))
	var state: BattleState = SIM.create_run("stress:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {}, {"healing": 0, "revival": 0}, 1)
	var stress: BattleActor = state.actors[0]
	stress.skills.clear()
	stress.skill_cooldowns.clear()
	for skill: AbilityDefinition in SIM.ABILITIES.values().slice(0, 32):
		stress.add_skill(skill)
	assert_eq(stress.skills.size(), 32)
	var cast: Dictionary = {}
	while state.status == "active":
		SIM.advance(state, 1.0)
		cast[str(stress.effect_state.get("last_skill_id", ""))] = true
	assert_ne(state.status, "active")
	assert_gt(cast.size(), 3, "it cast several of its abilities: %s" % str(cast.keys()))


## The six generals' rules never fire for a healthy solo hero: the fight is the class-only fight.
func test_the_six_generals_change_nothing_while_their_rules_hold_off() -> void:
	for archetype: String in ["knight", "ranger", "mage", "rogue", "cleric"]:
		var class_only: float = _duel(archetype, false)
		assert_gt(class_only, 0.0, archetype)
		assert_eq(_duel(archetype, true), class_only, "%s: equal damage dealt with the generals on the bar" % archetype)


func test_a_checkpoint_with_statuses_round_trips_through_the_save_file() -> void:
	var order_id: String = _dispatch_knights()
	var state := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	while state.status == "active" and not state.actors.any(func(actor: BattleActor) -> bool: return not actor.statuses.is_empty()):
		SIM.advance(state, 0.5)
	assert_eq(state.status, "active")
	var knight: BattleActor = state.actors[0]
	SIM._add_status(knight, "ranger_barbed_arrow", "bleed", "enemy:x", 5.0, 1.5)
	SIM._add_status(knight, "mage_warding_glyph", "shield", knight.id, 3.0, 12.5)
	SIM._add_status(knight, "cleric_wellspring", "heal_over_time", knight.id, 7.0, 3.6)
	knight.combo_skill = "knight_iron_cut"
	knight.combo_tick = state.tick
	knight.ability_lock = 0.4
	GameSession.expedition_orders[0]["battle"] = state.to_dict()
	assert_eq(SIM.validate_snapshot(state.to_dict()), "")
	# The reference is the battle as the file reads back: full precision (ig-85w), parsed, since Godot's
	# parser misrounds some 17-digit numbers by 1 ulp.
	var reference := BattleState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)) as Dictionary)
	var before: String = _exact_json(reference.to_dict())

	assert_true(_through_disk(GameSession.to_dict()), SaveService.load_block_reason)
	var loaded := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	assert_eq(_exact_json(loaded.to_dict()), before, "the same battle, statuses and all")
	assert_false(GameSession.get_battle_snapshot(order_id).is_empty())
	SIM.advance(reference, reference.max_seconds)
	SIM.advance(loaded, loaded.max_seconds)
	assert_eq(loaded.to_dict(), reference.to_dict(), "and it finishes the same, every field ==")
	for moment: Dictionary in loaded.moments:
		assert_true(str(moment["what"]) in ["downed", "revived", "carried"], str(moment))


func test_a_checkpoint_from_before_statuses_loads_with_its_guard_as_rally() -> void:
	_dispatch_knights()
	var profile: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict())) as Dictionary
	var battle: Dictionary = (profile["expedition_orders"] as Array)[0]["battle"]
	for actor: Dictionary in battle["actors"]:
		for key: String in ["ability_lock", "combo_skill", "combo_tick", "statuses"]:
			actor.erase(key)
		(actor["effect_state"] as Dictionary).erase("last_skill_id")
		(actor["effect_state"] as Dictionary).erase("telegraph_skill")
		actor["effect_state"]["guard_remaining"] = 0.0
		actor["effect_state"]["guard_reduction"] = 0.0
	battle["actors"][0]["effect_state"]["guard_remaining"] = 2.0
	battle["actors"][0]["effect_state"]["guard_reduction"] = 0.3
	assert_eq(SIM.validate_snapshot(battle), "", "the old shape still validates")

	assert_true(_through_disk(profile), SaveService.load_block_reason)
	var state := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	assert_eq(state.actors[0].statuses, [{"id": "knight_rally", "kind": "damage_reduction", "source": "", "remaining": 2.0, "magnitude": 0.3}])
	assert_true(state.actors.all(func(actor: BattleActor) -> bool: return not actor.effect_state.has("guard_remaining") and not actor.effect_state.has("guard_reduction")))
	# A hand-made checkpoint carrying both shapes keeps one Stand Fast status, so it re-saves.
	var both: Dictionary = state.actors[0].to_dict()
	both["effect_state"]["guard_remaining"] = 3.0
	both["effect_state"]["guard_reduction"] = 0.3
	assert_eq(BattleActor.from_dict(both).statuses.size(), 1)
	assert_eq(state.actors[1].statuses, [], "no guard, no status")
	assert_eq(SIM.validate_snapshot(state.to_dict()), "", "it re-saves in the new shape")
	SIM.advance(state, state.max_seconds)
	assert_ne(state.status, "active")


## ---- ig-gy0.4: the AI's answer to enemy telegraphs, and enemy kits

func test_enemies_carry_their_starter_kit_and_knights_crushing_blow() -> void:
	assert_eq(_ids(SIM.enemy_kit("knight")), ["knight_bulwark", "knight_rally", "knight_iron_cut", "enemy_knight_crushing_blow"])
	assert_eq(_ids(SIM.enemy_kit("ranger")), _ids(SIM.known_kit("ranger", 1)), "no enemy-only skill yet")
	var snapshots: Array[Dictionary] = [_unit("hero:k", "knight", "ally", Vector2(0, -16))]
	var state: BattleState = SIM.create_run("kits:enemies", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {}, {"healing": 0, "revival": 0}, 3)
	var enemies: Array[BattleActor] = state.actors.filter(func(actor: BattleActor) -> bool: return actor.faction == "enemy")
	assert_false(enemies.is_empty())
	for enemy: BattleActor in enemies:
		assert_eq(_kit(enemy), _ids(SIM.enemy_kit(enemy.archetype)), enemy.id)
	# A hero snapshot never keeps an enemy-only skill; an enemy one does.
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var hero: BattleActor = SIM._actor_from_team_snapshot(_unit("hero:x", "knight", "ally", Vector2.ZERO, {"skills": [{"id": "enemy_knight_crushing_blow"}, {"id": "knight_rally"}]}), 0, zone)
	assert_eq(_kit(hero), ["knight_rally"])
	var enemy_knight: BattleActor = SIM._actor_from_team_snapshot(_unit("enemy:x", "knight", "enemy", Vector2.ZERO, {"skills": [{"id": "enemy_knight_crushing_blow"}]}), 0, zone)
	assert_eq(_kit(enemy_knight), ["enemy_knight_crushing_blow"])


func test_a_buckler_blow_stuns_a_crushing_blow_after_the_reaction_delay() -> void:
	var state: BattleState = _crushing_blow_on("knight", [])
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors[1]
	_give(knight, ["knight_buckler_blow"])
	assert_eq(enemy.effect_state["telegraph_remaining"], 1.2, "Crushing Blow's own delay")
	SIM.advance(state, 0.1)
	assert_eq(knight.skill_cooldowns["knight_buckler_blow"], 0.0, "not before the reaction delay")
	assert_eq(enemy.effect_state["telegraph_claimed_by"], "")
	SIM.advance(state, 0.1)
	assert_gt(knight.skill_cooldowns["knight_buckler_blow"], 0.0, "answered at the reaction delay")
	assert_eq(enemy.effect_state["telegraph_claimed_by"], knight.id)
	assert_eq(knight.effect_state["last_counter_tick"], state.tick)
	assert_eq(enemy.effect_state["telegraph_kind"], "", "the telegraph is cut")
	SIM.advance(state, 1.2)
	assert_eq(knight.hp, 100.0, "it never lands")


func test_two_heroes_with_stuns_spend_only_one() -> void:
	var state: BattleState = _crushing_blow_on("knight", [_unit("hero:m", "mage", "ally", Vector2(-3, -16))])
	_give(state.actors[0], ["knight_buckler_blow"])
	_give(state.actors[2], ["mage_frost_bind"])
	SIM.advance(state, 0.3)
	assert_gt(state.actors[0].skill_cooldowns["knight_buckler_blow"], 0.0, "the first in spawn order answers")
	assert_eq(state.actors[2].skill_cooldowns["mage_frost_bind"], 0.0, "the other stun is kept")


func test_with_no_stun_in_range_a_shield_lands_on_the_target() -> void:
	var state: BattleState = _crushing_blow_on("knight", [_unit("hero:m", "mage", "ally", Vector2(0, -30)), _unit("hero:c", "cleric", "ally", Vector2(0, -12))])
	var knight: BattleActor = state.actors[0]
	var mage: BattleActor = state.actors[2]
	var cleric: BattleActor = state.actors[3]
	_give(mage, ["mage_frost_bind"])
	_give(cleric, ["cleric_sheltering_word"])
	SIM.advance(state, 0.2)
	assert_eq(mage.skill_cooldowns["mage_frost_bind"], 0.0, "out of range")
	assert_eq(state.actors[1].effect_state["telegraph_claimed_by"], cleric.id)
	assert_true(SIM._has_status(knight, "shield"), "the shield is on the Knight inside the circle")


func test_a_rogue_inside_the_circle_slips_it_and_takes_no_damage() -> void:
	var state: BattleState = _crushing_blow_on("rogue", [])
	var rogue: BattleActor = state.actors[0]
	_give(rogue, ["rogue_slip"])
	SIM.advance(state, 1.2)  # ig-85w: the 1.2 s countdown lands on tick 12
	assert_gt(rogue.skill_cooldowns["rogue_slip"], 0.0)
	assert_eq(state.actors[1].effect_state["telegraph_kind"], "", "the blow landed")
	assert_eq(rogue.hp, 100.0, "on nobody")


func test_with_no_stun_or_shield_every_hero_inside_dodges() -> void:
	var state: BattleState = _crushing_blow_on("rogue", [_unit("hero:r2", "rogue", "ally", Vector2(0, -15)), _unit("hero:r3", "rogue", "ally", Vector2(0, -10))])
	for hero: BattleActor in [state.actors[0], state.actors[2], state.actors[3]]:
		_give(hero, ["rogue_slip"])
	SIM.advance(state, 0.2)
	assert_gt(state.actors[0].skill_cooldowns["rogue_slip"], 0.0)
	assert_gt(state.actors[2].skill_cooldowns["rogue_slip"], 0.0, "both inside dodge")
	assert_eq(state.actors[3].skill_cooldowns["rogue_slip"], 0.0, "outside: no dodge")
	assert_eq(state.actors[1].effect_state["telegraph_claimed_by"], state.actors[0].id, "the first holds the claim")


func test_a_manual_counter_is_never_auto_fired() -> void:
	var state: BattleState = _crushing_blow_on("knight", [])
	var knight: BattleActor = state.actors[0]
	knight.add_skill(SIM.ABILITIES["knight_buckler_blow"], "manual")
	SIM.advance(state, 1.2)
	assert_eq(knight.skill_cooldowns["knight_buckler_blow"], 0.0)
	assert_eq(state.actors[1].effect_state["telegraph_claimed_by"], "")
	assert_lt(knight.hp, 100.0, "the blow lands")


func test_the_shortest_cooldown_counter_answers_first() -> void:
	var state: BattleState = _crushing_blow_on("knight", [])
	var knight: BattleActor = state.actors[0]
	_give(knight, ["general_disrupt", "knight_buckler_blow"])
	SIM.advance(state, 0.2)
	assert_gt(knight.skill_cooldowns["knight_buckler_blow"], 0.0, "Buckler Blow (20 s) before Break Cadence (45 s)")
	assert_eq(knight.skill_cooldowns["general_disrupt"], 0.0)


func test_a_claim_saved_mid_telegraph_reloads_without_a_second_answer() -> void:
	_dispatch_knights()
	var state := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	var knight: BattleActor = state.actors[0]
	var enemy: BattleActor = state.actors.filter(func(actor: BattleActor) -> bool: return actor.faction == "enemy")[0]
	var enemy_id: String = enemy.id
	enemy.position = knight.position + Vector2(1, 0)
	for hero: BattleActor in _heroes(state):
		hero.skill_cooldowns["knight_buckler_blow"] = 5.0
	SIM._start_telegraph(state, enemy, SIM.ABILITIES["enemy_knight_crushing_blow"], knight.position, 1.2)

	# A battle saved before ig-gy0.4, mid-telegraph: no claim key. It loads and is answered once.
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict())) as Dictionary
	var legacy_battle: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict())) as Dictionary
	for actor: Dictionary in legacy_battle["actors"]:
		(actor["effect_state"] as Dictionary).erase("telegraph_claimed_by")
	legacy["expedition_orders"][0]["battle"] = legacy_battle
	assert_eq(SIM.validate_snapshot(legacy_battle), "", "the old shape validates")
	assert_true(_through_disk(legacy), SaveService.load_block_reason)
	state = BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	SIM.advance(state, 0.2)
	var claimer: String = str(_actor(state, enemy_id).effect_state.get("telegraph_claimed_by", ""))
	assert_ne(claimer, "", "answered with Stand Fast (the stuns are cooling)")
	assert_eq(_actor(state, enemy_id).effect_state["telegraph_kind"], "circle", "a shield leaves the telegraph live")

	# Every counter ready again, then saved and reloaded through disk: the claim holds.
	for hero: BattleActor in _heroes(state):
		for skill_id: String in hero.skill_cooldowns:
			hero.skill_cooldowns[skill_id] = 0.0
		hero.ability_lock = 0.0
	GameSession.expedition_orders[0]["battle"] = state.to_dict()
	var reference := BattleState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())) as Dictionary)
	var unclaimed := BattleState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())) as Dictionary)
	_actor(unclaimed, enemy_id).effect_state["telegraph_claimed_by"] = ""
	assert_true(_through_disk(GameSession.to_dict()), SaveService.load_block_reason)
	var loaded := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	assert_eq(str(_actor(loaded, enemy_id).effect_state["telegraph_claimed_by"]), claimer)
	for battle: BattleState in [reference, loaded, unclaimed]:
		SIM.advance(battle, 0.1)
	assert_false(_answered(loaded), "no second answer after the reload")
	assert_eq(_exact_json(loaded.to_dict()), _exact_json(reference.to_dict()))
	assert_true(_answered(unclaimed), "control: without the claim a ready counter answers again")


## ---- helpers

## hero:<archetype> at (0, -16) and an enemy Knight at (1, -16) whose Crushing Blow (1.2 s) is marked
## on the hero, then extra; every kit empty but the enemy's.
func _crushing_blow_on(archetype: String, extra: Array[Dictionary]) -> BattleState:
	var snapshots: Array[Dictionary] = [_unit("hero:" + archetype, archetype, "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16))]
	snapshots.append_array(extra)
	var state: BattleState = _battle(snapshots)
	_give(state.actors[1], ["enemy_knight_crushing_blow"])
	assert_true(SIM._auto_cast(state, state.actors[1], state.actors[0], ["attack"], null))
	return state


func _actor(state: BattleState, id: String) -> BattleActor:
	return state.actors.filter(func(actor: BattleActor) -> bool: return actor.id == id)[0]


func _heroes(state: BattleState) -> Array[BattleActor]:
	var heroes: Array[BattleActor] = []
	heroes.assign(state.actors.filter(func(actor: BattleActor) -> bool: return actor.faction == "ally"))
	return heroes


## Some hero answered a telegraph on the battle's last tick.
func _answered(state: BattleState) -> bool:
	return state.actors.any(func(actor: BattleActor) -> bool: return int(actor.effect_state.get("last_counter_tick", -1)) == state.tick)


func _unit(id: String, archetype: String, faction: String, position: Vector2, extra: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {"archetype": archetype, "faction": faction, "hp": 100.0, "atk": 10.0, "defense": 0.0, "speed": 100.0, "crit_rate": 0.0, "crit_damage": 1.5, "position": [position.x, position.y]}
	if faction == "ally":
		snapshot["hero_id"] = id
		snapshot["squad_id"] = "s"
	else:
		snapshot["id"] = id
		snapshot["squad_id"] = ""
	snapshot.merge(extra, true)
	return snapshot


func _squads(snapshots: Array[Dictionary], stance: String = "stay_together") -> Array[Dictionary]:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	return [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": stance, "guard_target_id": ""}]


## No zone spawns (the enemies come in the list), Auto Battle off, no crits, empty kits. Pace 1: the
## authored numbers (test_battle_pace covers xP).
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var state: BattleState = SIM.create_run("kits:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])


## Damage a tough solo hero with its whole class kit (and the generals) deals over a full battle
## against enemy Knights too tough to kill (so no wave, and no telegraph, ever comes).
func _duel(archetype: String, generals: bool) -> float:
	var kit: Array = []
	for skill: AbilityDefinition in SIM.ABILITIES.values():
		if skill.archetype == archetype or (generals and skill.archetype == "general"):
			kit.append({"id": str(skill.skill_id), "mode": "auto"})
	var snapshots: Array[Dictionary] = [_unit("hero:solo", archetype, "ally", Vector2(0, -16), {"hp": 100000.0, "atk": 40.0, "defense": 50.0, "skills": kit})]
	for index: int in 6:
		snapshots.append(_unit("enemy:%d" % index, "knight", "enemy", Vector2(-3.0 + index * 1.2, -12.0), {"hp": 50000.0, "atk": 1.0}))
	var state: BattleState = SIM.create_run("duel:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots, "advance"), {}, {"healing": 0, "revival": 0}, 11)
	SIM.advance(state, state.max_seconds)
	assert_eq(state.status, "timeout", archetype)
	assert_eq(state.completed_waves, 0, archetype)
	var hero: BattleActor = state.actors[0]
	assert_gt(hero.hp / hero.max_hp, 0.5, archetype)
	for skill_id: String in hero.skill_cooldowns:
		if skill_id.begins_with("general_"):
			assert_eq(hero.skill_cooldowns[skill_id], 0.0, "%s never cast" % skill_id)
	var dealt: float = 0.0
	for enemy: BattleActor in state.actors.slice(1):
		dealt += enemy.max_hp - enemy.hp
	return dealt


func _dispatch_knights() -> String:
	var ids: Array[String] = []
	for index: int in 3:
		var hero := Hero.new("Knight %d" % index, index)
		hero.def_id = &"knight"
		hero.level = 25
		hero.instance_id = "hero:knight:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Knights", ids, "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "")
	return order_id


## Writes profile as the save file, clears the session and loads it back through SaveService,
## then puts the owner's save back. Saved "in the future" so offline progress adds nothing.
func _through_disk(profile: Dictionary) -> bool:
	profile["version"] = SaveService.SAVE_VERSION
	profile["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	var original_save: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	var original_existed: bool = FileAccess.file_exists(SaveService.SAVE_PATH)
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(profile, "\t", true, true))  # As SaveService writes it (ig-85w).
	file.close()
	GameSession.from_dict({"roster": []})
	var loaded: bool = SaveService.load_game()
	if original_existed:
		FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE).store_buffer(original_save)
	else:
		DirAccess.remove_absolute(SaveService.SAVE_PATH)
	return loaded and not SaveService.load_blocked


func _exact_json(data: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(data, "", true, true)), "", true, true)


func _ids(kit: Array[AbilityDefinition]) -> Array:
	return kit.map(func(skill: AbilityDefinition) -> String: return str(skill.skill_id))


func _kit(actor: BattleActor) -> Array:
	return actor.skills.map(func(entry: Dictionary) -> String: return str(entry["id"]))
