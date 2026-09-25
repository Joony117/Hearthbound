extends GutTest

## ig-zht: the Knight's Charge and Ground Slam (SYSTEMS.md § The v1 kits). Charge lands 1.2 short of
## its target at once and pushes the other opponents in its lane aside; Ground Slam, its combo, hits
## and stuns every opponent around the Knight.

const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
var CHARGE: AbilityDefinition = SIM.ABILITIES["knight_charge"]
var SLAM: AbilityDefinition = SIM.ABILITIES["knight_ground_slam"]
var TICK: float = SIM.BALANCE.battle_tick_seconds


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_charge_lands_short_on_the_cast_tick_and_pushes_its_lane_aside() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(0, 0)),
		_unit("enemy:target", "knight", "enemy", Vector2(8, 0)),
		_unit("enemy:left", "knight", "enemy", Vector2(3, 0.5)),
		_unit("enemy:right", "knight", "enemy", Vector2(5, -0.3)),
		_unit("enemy:on_line", "knight", "enemy", Vector2(4, 0)),
		_unit("enemy:elite", "knight", "enemy", Vector2(6, 0.2)),
		_unit("enemy:wide", "knight", "enemy", Vector2(4, 0.9)),
		_unit("enemy:behind", "knight", "enemy", Vector2(-1, 0)),
		_unit("enemy:past", "knight", "enemy", Vector2(9, 0.3)),
		_unit("hero:ally", "ranger", "ally", Vector2(2, 0)),
	])
	var knight: BattleActor = _actor(state, "hero:k")
	var target: BattleActor = _actor(state, "enemy:target")
	_actor(state, "enemy:elite").effect_state["elite"] = true
	state.tick = 30
	assert_true(SIM._use_skill(state, knight, CHARGE, target, target.position))
	assert_eq(state.tick, 30, "no tick passed")
	assert_almost_eq(knight.position, Vector2(6.8, 0), Vector2.ONE * 0.0001, "1.2 short, on the cast tick")
	assert_eq(knight.facing, Vector2(1, 0))
	assert_eq(knight.skill_cooldowns["knight_charge"], 15.0, "15 s at pace 1")
	# The lane's right, as the view draws it (sim y is its z), is +y here.
	for pushed: Array in [["enemy:left", Vector2(3, 2.0), [0.0, 1.0]], ["enemy:right", Vector2(5, -1.8), [0.0, -1.0]], ["enemy:on_line", Vector2(4, 1.5), [0.0, 1.0]]]:
		var enemy: BattleActor = _actor(state, pushed[0])
		assert_almost_eq(enemy.position, pushed[1] as Vector2, Vector2.ONE * 0.0001, "%s: 1.5 to its own side" % pushed[0])
		assert_eq(enemy.effect_state["hit_from"], pushed[2], pushed[0])
		assert_eq(int(enemy.effect_state["last_push_tick"]), 30, pushed[0])
	for still: Array in [["enemy:target", Vector2(8, 0)], ["enemy:elite", Vector2(6, 0.2)], ["enemy:wide", Vector2(4, 0.9)], ["enemy:behind", Vector2(-1, 0)], ["enemy:past", Vector2(9, 0.3)], ["hero:ally", Vector2(2, 0)]]:
		var actor: BattleActor = _actor(state, still[0])
		assert_eq(actor.position, still[1] as Vector2, "%s stays put" % still[0])
		assert_false(actor.effect_state.has("last_push_tick"), still[0])
	for actor: BattleActor in state.actors:
		assert_eq(actor.hp, 100.0, "%s: Charge deals no damage" % actor.id)
		assert_eq(float(actor.effect_state.get("stun_remaining", 0.0)), 0.0, actor.id)


func test_charge_keeps_its_range_band_and_its_pushes_in_bounds() -> void:
	for gap: float in [3.9, 12.1]:
		var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(gap, 0))])
		var knight: BattleActor = state.actors[0]
		assert_false(SIM._use_skill(state, knight, CHARGE, state.actors[1], state.actors[1].position), "%.1f is out of its 4-12 band" % gap)
		assert_eq(knight.position, Vector2(0, 0))
		assert_eq(knight.skill_cooldowns.get("knight_charge", 0.0), 0.0)

	var bounds: float = ZoneDefinition.definition_for(&"verdant_outskirts").battle_bounds
	var edge: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(bounds - 2.0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(bounds - 2.0, -10)), _unit("enemy:2", "knight", "enemy", Vector2(bounds - 1.4, -5))])
	assert_eq(float(edge.objective_state["bounds"]), bounds)
	assert_true(SIM._use_skill(edge, edge.actors[0], CHARGE, edge.actors[1], edge.actors[1].position))
	assert_almost_eq(edge.actors[0].position, Vector2(bounds - 2.0, -8.8), Vector2.ONE * 0.0001)
	assert_almost_eq(edge.actors[2].position, Vector2(bounds, -5), Vector2.ONE * 0.0001, "pushed out of bounds: held at the edge")

	# A carrier's body comes along, as a push carries it.
	var carry: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0)), _unit("hero:down", "ranger", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(8, 0))])
	var carrier: BattleActor = carry.actors[0]
	var body: BattleActor = carry.actors[1]
	body.life = BattleActor.LIFE_DOWNED
	carrier.carrying_id = body.id
	body.carried_by_id = carrier.id
	assert_true(SIM._use_skill(carry, carrier, CHARGE, carry.actors[2], carry.actors[2].position))
	assert_eq(body.position, carrier.position, "the body lands with the Knight")


func test_ground_slam_hits_and_stuns_every_opponent_around_the_knight_and_cancels_a_windup() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(0, 0)),
		_unit("enemy:near", "knight", "enemy", Vector2(2, 0)),
		_unit("enemy:edge", "knight", "enemy", Vector2(0, -2.5)),
		_unit("enemy:far", "knight", "enemy", Vector2(2.6, 0)),
		_unit("hero:ally", "ranger", "ally", Vector2(1, 0)),
	])
	var knight: BattleActor = _actor(state, "hero:k")
	var near: BattleActor = _actor(state, "enemy:near")
	near.effect_state["attack_windup_remaining"] = 0.2
	near.effect_state["attack_target_id"] = knight.id
	var edge: BattleActor = _actor(state, "enemy:edge")
	edge.effect_state["telegraph_kind"] = "circle"
	edge.effect_state["telegraph_remaining"] = 0.5
	edge.effect_state["telegraph_total"] = 1.0
	assert_true(SIM._use_skill(state, knight, SLAM, null, knight.position))
	for hit: String in ["enemy:near", "enemy:edge"]:
		assert_lt(_actor(state, hit).hp, 100.0, "%s: 1.0x" % hit)
		assert_eq(float(_actor(state, hit).effect_state["stun_remaining"]), 1.5, "%s: stunned 1.5 s at pace 1" % hit)
	assert_eq(near.hp, _actor(state, "enemy:edge").hp, "the same 1.0x")
	assert_eq(float(near.effect_state["attack_windup_remaining"]), 0.0, "its windup is cancelled")
	assert_eq(str(near.effect_state["attack_target_id"]), "")
	assert_eq(str(edge.effect_state["telegraph_kind"]), "", "and a telegraph")
	assert_eq(float(edge.effect_state["telegraph_remaining"]), 0.0)
	for missed: String in ["enemy:far", "hero:ally", "hero:k"]:
		assert_eq(_actor(state, missed).hp, 100.0, missed)
		assert_eq(float(_actor(state, missed).effect_state.get("stun_remaining", 0.0)), 0.0, missed)
	assert_eq(knight.skill_cooldowns["knight_ground_slam"], 15.0)

	var empty: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(3, 0))])
	assert_false(SIM._use_skill(empty, empty.actors[0], SLAM, null, empty.actors[0].position), "nobody around: it waits")
	assert_eq(empty.actors[0].skill_cooldowns.get("knight_ground_slam", 0.0), 0.0)


func test_the_ai_charges_its_own_target_then_slams() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0)), _unit("enemy:t", "knight", "enemy", Vector2(8, 0)), _unit("enemy:n", "knight", "enemy", Vector2(9, 1))])
	var knight: BattleActor = state.actors[0]
	_give(knight, ["knight_charge", "knight_ground_slam"])
	state.tick = 50
	assert_false(SIM._auto_cast(state, knight, null, ["buff", "attack"], null), "no target yet: no Charge")
	knight.order_target_id = "enemy:t"
	assert_true(SIM._auto_cast(state, knight, null, ["buff", "attack"], null), "8 away with a second enemy near it")
	assert_almost_eq(knight.position, Vector2(6.8, 0), Vector2.ONE * 0.0001)
	assert_eq(str(knight.effect_state["last_skill_id"]), "knight_charge")
	assert_false(SIM._auto_cast(state, knight, state.actors[1], ["buff", "attack"], null), "the ability lock holds the Slam")
	state.tick += 10
	knight.ability_lock = 0.0
	assert_true(SIM._auto_cast(state, knight, state.actors[1], ["buff", "attack"], null))
	assert_eq(str(knight.effect_state["last_skill_id"]), "knight_ground_slam")
	assert_gt(float(state.actors[1].effect_state["stun_remaining"]), 0.0)
	assert_gt(float(state.actors[2].effect_state["stun_remaining"]), 0.0)


func test_the_ai_holds_charge_close_in_alone_and_off_its_target() -> void:
	# Under 4 away, with a second enemy near.
	var close: BattleState = _charger([Vector2(3.5, 0), Vector2(4, 1)])
	assert_false(SIM._auto_cast(close, close.actors[0], close.actors[1], ["buff", "attack"], null))
	assert_eq(close.actors[0].position, Vector2(0, 0))
	# Its target alone, while a pair stands elsewhere in range: it never retargets.
	var alone: BattleState = _charger([Vector2(8, 0), Vector2(0, 8), Vector2(0.5, 9)])
	assert_false(SIM._auto_cast(alone, alone.actors[0], null, ["buff", "attack"], null))
	assert_eq(alone.actors[0].position, Vector2(0, 0))
	# Alone but elite.
	alone.actors[1].effect_state["elite"] = true
	assert_true(SIM._auto_cast(alone, alone.actors[0], null, ["buff", "attack"], null))
	assert_almost_eq(alone.actors[0].position, Vector2(6.8, 0), Vector2.ONE * 0.0001)


func test_ground_slam_waits_for_charge_within_the_combo_window() -> void:
	var state: BattleState = _battle([_unit("hero:k", "knight", "ally", Vector2(0, 0)), _unit("enemy:1", "knight", "enemy", Vector2(1, 0))])
	var knight: BattleActor = state.actors[0]
	_give(knight, ["knight_ground_slam"])
	state.tick = 200
	assert_false(SIM._auto_cast(state, knight, state.actors[1], ["buff", "attack"], null), "no Charge: no Slam")
	knight.effect_state["last_skill_id"] = "knight_charge"
	knight.effect_state["last_skill_tick"] = 200 - roundi(SIM.BALANCE.skill_combo_window_seconds / TICK) - 1
	assert_false(SIM._auto_cast(state, knight, state.actors[1], ["buff", "attack"], null), "past the window")
	knight.effect_state["last_skill_tick"] = 200 - roundi(SIM.BALANCE.skill_combo_window_seconds / TICK)
	assert_true(SIM._auto_cast(state, knight, state.actors[1], ["buff", "attack"], null), "the window's last tick")


func test_a_knight_on_auto_charges_then_slams_in_a_running_fight() -> void:
	var snapshots: Array[Dictionary] = [_unit("hero:k", "knight", "ally", Vector2(0, -16), {"hp": 100000.0, "skills": [{"id": "knight_charge", "mode": "auto"}, {"id": "knight_ground_slam", "mode": "auto"}]})]
	snapshots.append(_unit("enemy:1", "knight", "enemy", Vector2(0, -4), {"hp": 50000.0, "atk": 1.0}))
	snapshots.append(_unit("enemy:2", "knight", "enemy", Vector2(1, -3), {"hp": 50000.0, "atk": 1.0}))
	var state: BattleState = SIM.create_run("charge:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots, "advance"), {}, {"healing": 0, "revival": 0}, 11, "normal", 1)
	for enemy: BattleActor in state.actors.slice(1):
		_give(enemy, [])
	var knight: BattleActor = state.actors[0]
	var casts: Array[String] = []
	var leap: float = -1.0
	var landing: float = -1.0
	for step: int in 200:
		var before: Vector2 = knight.position
		var last: int = int(knight.effect_state.get("last_skill_tick", -1))
		SIM.advance(state, TICK)
		if int(knight.effect_state.get("last_skill_tick", -1)) != last:
			casts.append(str(knight.effect_state["last_skill_id"]))
			if casts[-1] == "knight_charge":
				leap = before.distance_to(knight.position)
				landing = knight.position.distance_to(SIM._actor_by_id(state, knight.order_target_id).position)
	assert_eq(casts, ["knight_charge", "knight_ground_slam"], "Charge, then its Slam")
	assert_gt(leap, 2.5, "a dash, not a walk: at least 4 away less the 1.2 short, give or take a step")
	assert_almost_eq(landing, 1.2, 0.3, "landed 1.2 short of its target, give or take the target's step")


## ACC 2, the 85w standard (boundary #1): a fight saved mid-fight by the real SaveService reads back as
## its full-precision round trip, ==, and runs on as it, ==, through the charges and pushes; against the
## unbroken fight it is held to 1e-6 (Godot's parser misrounds some 17-digit numbers by 1 ulp).
func test_a_mid_fight_save_and_reload_repeats_the_charges_and_pushes() -> void:
	var ids: Array[String] = []
	for index: int in 5:
		var hero := Hero.new("Charger %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 20
		hero.instance_id = "hero:charge:%d" % index
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Charge", ids, "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var seeded: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict(), "", true, true)) as Dictionary
	((seeded["expedition_orders"] as Array)[0] as Dictionary)["battle"]["rng_state"] = "1"
	GameSession.from_dict(seeded)
	GameSession.tick_expeditions(0.5)
	# Staged at the save: one Knight ordered onto an enemy 8 away with a second beside it, and a third in
	# its lane, so a lane push surely falls after the save. The fight's own Charges may find their lanes empty.
	var staged: Dictionary = JSON.parse_string(JSON.stringify(GameSession.to_dict(), "", true, true)) as Dictionary
	var actors: Array = (((staged["expedition_orders"] as Array)[0] as Dictionary)["battle"] as Dictionary)["actors"]
	var knight: Dictionary = actors.filter(func(actor: Dictionary) -> bool: return actor["faction"] == "ally")[0]
	var enemies: Array = actors.filter(func(actor: Dictionary) -> bool: return actor["faction"] == "enemy" and actor["life"] == "alive")
	assert_gte(enemies.size(), 3, "three enemies to stage")
	knight["position"] = [-4.0, 0.0]
	knight["order_kind"] = SIM.COMMAND_ATTACK
	knight["order_target_id"] = enemies[0]["id"]
	knight["effect_state"]["direct_order"] = true
	knight["skill_cooldowns"]["knight_charge"] = 0.0
	knight["ability_lock"] = 0.0
	enemies[0]["position"] = [4.0, 0.0]
	enemies[1]["position"] = [5.0, 1.0]
	enemies[2]["position"] = [0.0, 0.3]
	GameSession.from_dict(staged)
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(str(battle["status"]), "active", "mid-fight")
	var straight := BattleState.from_dict(battle.duplicate(true))
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(battle, "", true, true)) as Dictionary
	var written := BattleState.from_dict(round_trip)
	var start: int = written.tick
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	var stamp := RegEx.create_from_string("\"saved_at_unix\": [^,\\n]+")
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(stamp.sub(text, "\"saved_at_unix\": %d" % int(Time.get_unix_time_from_system() + 3600.0)))
	file.close()
	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var read_back: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(Compare.first_difference(read_back, round_trip), "", "the file reads back as the round trip, raw")
	var loaded := BattleState.from_dict(read_back)
	var ready: Array[String] = []
	for actor: BattleActor in written.actors:
		if actor.faction == "ally" and float(actor.skill_cooldowns.get("knight_charge", 1.0)) == 0.0:
			ready.append(actor.id)
	var charges: int = 0
	var lane_pushes: int = 0
	for step: int in 150:
		SIM.advance(straight, TICK)
		SIM.advance(written, TICK)
		SIM.advance(loaded, TICK)
		# A Charge just cast: its lane's pushes carry its cast tick (a crit push on that very tick aside).
		for actor: BattleActor in loaded.actors:
			if actor.id in ready and float(actor.skill_cooldowns["knight_charge"]) > 0.0:
				ready.erase(actor.id)
				charges += 1
				for enemy: BattleActor in loaded.actors:
					if enemy.faction == "enemy" and int(enemy.effect_state.get("last_push_tick", -1)) == int(actor.effect_state["last_skill_tick"]):
						lane_pushes += 1
	assert_eq(written.tick, start + 150, "it ran on all 15 s")
	assert_gt(charges, 0, "the Knights charged after the save")
	assert_gt(lane_pushes, 0, "and pushed their lanes aside")
	assert_eq(Compare.first_difference(loaded.to_dict(), written.to_dict()), "", "the reload runs on as its round trip")
	assert_eq(Compare.mismatch(_where(loaded.to_dict()), _where(straight.to_dict())), "", "and as the unbroken fight, to 1e-6")


func _charger(enemies: Array[Vector2]) -> BattleState:
	var snapshots: Array[Dictionary] = [_unit("hero:k", "knight", "ally", Vector2(0, 0))]
	for index: int in enemies.size():
		snapshots.append(_unit("enemy:%d" % index, "knight", "enemy", enemies[index]))
	var state: BattleState = _battle(snapshots)
	_give(state.actors[0], ["knight_charge"])
	state.actors[0].order_target_id = "enemy:0"
	return state


## What the charges and pushes decide: the exact facts first, then the floats.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	for actor: Dictionary in snapshot["actors"]:
		var effects: Dictionary = actor["effect_state"]
		var from: Array = effects.get("hit_from", [0.0, 0.0])
		result.append(["%s %s %s %d %d %s %d" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), int(effects.get("last_push_tick", 0)), effects.get("last_skill_id", ""), int(effects.get("last_skill_tick", 0))], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1]), float(from[0]), float(from[1]), float(effects.get("stun_remaining", 0.0))])
	return result


## A hero's actor id is "hero:" + its hero_id.
func _actor(state: BattleState, id: String) -> BattleActor:
	var actor: BattleActor = SIM._actor_by_id(state, id)
	return actor if actor != null else SIM._actor_by_id(state, "hero:" + id)


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


## No zone spawns (the enemies come in the list), Auto Battle off, no crits, empty kits, pace 1.
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var state: BattleState = SIM.create_run("charge:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), _squads(snapshots), {"auto_battle": false, "suppress_ally_crit": true}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		_give(actor, [])
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
