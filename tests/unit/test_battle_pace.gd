extends GutTest

## ig-1jw (SYSTEMS.md § Battle pace): at pace P every actor's max HP, an ability's cooldown, its ATK
## amounts and its seconds, and a battle's rewards scale by P. Swings, weaponskills, the windup,
## telegraphs and the dodge window stay real. Each check runs the same fight at pace 1 and at PACE.

const SIM = preload("res://combat/battle/battle_simulation.gd")
const BALANCE: BalanceTable = preload("res://balance.tres")
const PACE: int = 6


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	GameSession.last_action_error = ""
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_max_hp_scales_for_heroes_and_spawned_enemies() -> void:
	var slow: BattleState = _zone_run(1)
	var fast: BattleState = _zone_run(PACE)
	assert_eq(fast.pace, PACE)
	assert_eq(fast.max_seconds, slow.max_seconds * PACE)
	assert_eq(fast.actors.size(), slow.actors.size())
	assert_true(slow.actors.any(func(actor: BattleActor) -> bool: return actor.faction == "enemy"), "the first wave spawned")
	for index: int in slow.actors.size():
		assert_almost_eq(fast.actors[index].max_hp, slow.actors[index].max_hp * PACE, 0.0001, slow.actors[index].id)
		assert_almost_eq(fast.actors[index].hp, slow.actors[index].hp * PACE, 0.0001, slow.actors[index].id)
		assert_eq(fast.actors[index].atk, slow.actors[index].atk, "ATK stays real")


func test_a_heal_and_its_cooldown_scale() -> void:
	for pace: int in [1, PACE]:
		var state: BattleState = _cleric_run(pace)
		BattleSimulation.advance(state, 0.1)
		assert_almost_eq(state.actors[1].hp, (30.0 + 16.0 * 3.0 * 1.2) * pace, 0.0001, "Mend: 3.0 x ATK +20% Grace, xP")
		assert_almost_eq(state.actors[0].skill_cooldowns["cleric_mend"], 8.0 * pace, 0.1001, "Mend's 8 s, xP")


func test_a_stun_an_ability_hit_and_a_cooldown_scale() -> void:
	var results: Array[Dictionary] = []
	for pace: int in [1, PACE]:
		var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "rogue", "enemy", Vector2(1, -16))], pace)
		var knight: BattleActor = state.actors[0]
		var enemy: BattleActor = state.actors[1]
		_give(knight, ["knight_buckler_blow"])
		assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_buckler_blow"], enemy, enemy.position))
		results.append({"stun": float(enemy.effect_state["stun_remaining"]), "damage": enemy.max_hp - enemy.hp, "cooldown": knight.skill_cooldowns["knight_buckler_blow"]})
	assert_eq(results[0]["stun"], 1.5, "Buckler Blow's authored stun")
	assert_almost_eq(float(results[1]["stun"]), 1.5 * PACE, 0.0001)
	assert_gt(float(results[0]["damage"]), 0.0)
	assert_almost_eq(float(results[1]["damage"]), float(results[0]["damage"]) * PACE, 0.0001)
	assert_gt(float(results[0]["cooldown"]), 0.0)
	assert_almost_eq(float(results[1]["cooldown"]), float(results[0]["cooldown"]) * PACE, 0.0001)


func test_a_weaponskill_the_windup_a_telegraph_and_the_dodge_window_stay_real() -> void:
	for pace: int in [1, PACE]:
		# A weaponskill: Barbed Arrow's hit and its bleed.
		var state: BattleState = _battle([_unit("hero:r", "ranger", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(5, -16))], pace)
		var enemy: BattleActor = state.actors[1]
		SIM._use_weaponskill(state, state.actors[0], SIM.ABILITIES["ranger_barbed_arrow"], enemy, null)
		assert_almost_eq(enemy.max_hp - enemy.hp, 10.0, 0.0001, "pace %d: the weaponskill hit" % pace)
		assert_eq(enemy.statuses, [{"id": "ranger_barbed_arrow", "kind": "bleed", "source": state.actors[0].id, "remaining": 8.0, "magnitude": 1.5}], "pace %d" % pace)

		# The windup of a basic swing (the enemy's AI swings; Auto Battle is off for the hero).
		state = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16))], pace)
		SIM.advance(state, 0.3)
		assert_ne(str(state.actors[1].effect_state.get("attack_target_id", "")), "", "pace %d: a swing started" % pace)
		assert_eq(float(state.actors[1].effect_state["attack_windup_total"]), BALANCE.battle_attack_windup_seconds, "pace %d: the windup" % pace)

		# A telegraph: Crushing Blow's 1.2 s.
		state = _battle([_unit("hero:k", "knight", "ally", Vector2(0, -16)), _unit("enemy:1", "knight", "enemy", Vector2(1, -16))], pace)
		_give(state.actors[1], ["enemy_knight_crushing_blow"])
		assert_true(SIM._auto_cast(state, state.actors[1], state.actors[0], ["attack"], null))
		assert_eq(state.actors[1].effect_state["telegraph_remaining"], 1.2, "pace %d: the telegraph" % pace)

		# The dodge window: Slip's status seconds.
		state = _battle([_unit("hero:g", "rogue", "ally", Vector2(0, -16)), _unit("enemy:1", "mage", "enemy", Vector2(3, -16))], pace)
		var rogue: BattleActor = state.actors[0]
		_give(rogue, ["rogue_slip"])
		assert_true(SIM._use_skill(state, rogue, SIM.ABILITIES["rogue_slip"], state.actors[1], rogue.position))
		var dodges: Array = rogue.statuses.filter(func(status: Dictionary) -> bool: return status["kind"] == "dodge")
		assert_eq(dodges.size(), 1, "pace %d" % pace)
		assert_eq(float(dodges[0]["remaining"]), _slip_seconds(), "pace %d: the dodge window" % pace)


func test_a_battle_orders_rewards_scale_by_its_own_pace() -> void:
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var xp: Array[int] = []
	for pace: int in [1, PACE]:
		GameSession.from_dict({"roster": []})
		var order_id: String = _dispatch_knight()
		assert_ne(order_id, "", GameSession.last_action_error)
		var order: Dictionary = GameSession.expedition_orders[0]
		var battle: Dictionary = order["battle"] as Dictionary
		assert_eq(int(battle["pace"]), BALANCE.battle_pace, "a dispatch fights at the live pace")
		# The checkpoint's pace decides the rewards, not the live one.
		battle["pace"] = pace
		battle["max_seconds"] = zone.max_battle_seconds * pace
		battle["status"] = "victory"
		order["remaining_seconds"] = 0.0
		var stones_before: int = GameSession.stones
		GameSession.tick_expeditions(0.1)
		assert_eq(GameSession.expedition_reports.size(), 1, "pace %d: settled" % pace)
		var report: Dictionary = GameSession.expedition_reports[0]
		assert_eq(GameSession.stones - stones_before, zone.stone_reward * pace, "pace %d: stones" % pace)
		assert_eq(report["stones_earned"], zone.stone_reward * pace)
		assert_eq(report["items_earned"], pace, "pace %d: P loot rolls" % pace)
		assert_eq(GameSession.inventory.size(), pace)
		xp.append(int(report["xp_earned"]))
	assert_gt(xp[0], 0)
	assert_eq(xp[1], xp[0] * PACE, "XP xP")


func _slip_seconds() -> float:
	for effect: Dictionary in (SIM.ABILITIES["rogue_slip"] as AbilityDefinition).effects:
		if str(effect.get("status", "")) == "dodge":
			return float(effect["seconds"])
	return -1.0


func _zone_run(pace: int) -> BattleState:
	var snapshots: Array[Dictionary] = [_unit("hero:k", "knight", "ally", Vector2(0, -16), {"current_hp": 60.0})]
	return SIM.create_run("pace:hp", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {}, {"healing": 0, "revival": 0}, 3, "normal", pace)


func _cleric_run(pace: int) -> BattleState:
	var snapshots: Array[Dictionary] = [
		_unit("hero:cleric", "cleric", "ally", Vector2(0, -16), {"hp": 110.0, "atk": 16.0, "defense": 10.0}),
		_unit("hero:knight", "knight", "ally", Vector2(2, -16), {"current_hp": 30.0, "defense": 20.0}),
	]
	var state: BattleState = SIM.create_run("pace:heal", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false}, {"healing": 0, "revival": 0}, 5, "rescue", pace)
	state.actors[1].set_abilities_auto(false)
	return state


## No zone spawns (the enemies come in the list), Auto Battle off, no crits, empty kits.
func _battle(snapshots: Array[Dictionary], pace: int) -> BattleState:
	var state: BattleState = SIM.create_run("pace:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", pace)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])


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


func _squads(snapshots: Array[Dictionary]) -> Array[Dictionary]:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	return [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]


func _dispatch_knight() -> String:
	var hero := Hero.new("Pace Knight", 7)
	hero.def_id = &"knight"
	hero.level = 80
	hero.instance_id = "hero:pace"
	GameSession.roster.append(hero)
	var preset_id: String = GameSession.save_team_preset("", "Pace", [hero.instance_id], "verdant_outskirts")
	return GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
