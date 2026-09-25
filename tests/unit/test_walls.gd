extends GutTest

## ig-0qh: walking around walls (SYSTEMS.md § Casters, "Walking around walls"; DECISIONS.md 2026-09-25,
## "Casters shape the field", items 5-6). No skill casts a wall yet (ig-vl1.5), so these place them by hand.

const SIM = preload("res://combat/battle/battle_simulation.gd")
const Compare = preload("res://tests/unit/compare.gd")
const Session = preload("res://systems/game_session.gd")
## A wall 1.2 thick grows 0.6 + 0.325 each way; a cut or a corner sits WALL_MARGIN past that.
const GROW: float = 0.925
const EDGE: float = 0.926


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	GameSession.from_dict({"roster": []})
	SaveService.load_blocked = false


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_an_actor_sent_behind_a_wall_walks_the_shortest_corner_path_and_never_enters_it() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-5, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(state, Vector2(0, -3), Vector2(0, 3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(5, 0)
	var walked: float = 0.0
	var top: float = -INF
	var inside: int = 0
	for tick: int in 300:
		var before: Vector2 = knight.position
		SIM._move_actors(state)
		walked += before.distance_to(knight.position)
		top = maxf(top, knight.position.y)
		if absf(knight.position.x) < GROW and absf(knight.position.y) < 3.0 + GROW:
			inside += 1
		if knight.order_kind.is_empty():
			break
	assert_true(knight.order_kind.is_empty(), "it arrives")
	assert_almost_eq(knight.position.distance_to(Vector2(5, 0)), 0.0, 0.0001)
	assert_eq(inside, 0, "its center never enters the footprint")
	var corner := Vector2(-EDGE, 3.0 + EDGE)
	assert_almost_eq(walked, 2.0 * Vector2(-5, 0).distance_to(corner) + 2.0 * EDGE, 0.001, "the shortest corner path")
	assert_gt(top, 3.0 + GROW, "over the top: the tie goes to corner 0")


func test_a_goal_inside_a_footprint_moves_to_its_edge_on_the_goal_s_side() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-5, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(state, Vector2(0, -3), Vector2(0, 3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(0.3, 1.0)
	for tick: int in 300:
		SIM._move_actors(state)
	assert_true(knight.order_kind.is_empty(), "the order ends at the edge (Sol)")
	assert_almost_eq(knight.position.x, EDGE, 0.0001, "the far side: the goal's")
	assert_almost_eq(knight.position.y, 1.0, 0.0001)


## Sol pass 2: the goal's edge point sits in a second, overlapping wall, so the far edge wins. At the bounds'
## edge the near face is out of bounds, so the far one wins there too.
func test_a_goal_whose_edge_is_blocked_or_out_of_bounds_takes_the_nearest_reachable_point() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-5, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(state, Vector2(0, -3), Vector2(0, 3))
	_wall(state, Vector2(1.5, -3), Vector2(1.5, 3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(0.7, 0.0)
	for tick: int in 300:
		SIM._move_actors(state)
	assert_true(knight.order_kind.is_empty(), "the order ends")
	assert_almost_eq(knight.position.distance_to(Vector2(-EDGE, 0.0)), 0.0, 0.0001, "on the far edge")
	var paths: SIM.WallPaths = SIM._wall_paths(state)
	assert_eq(SIM._wall_containing(paths, knight.position), -1, "outside both")
	var bounds: float = paths.bounds
	state.field_objects.clear()
	state.field_sequence += 1
	_wall(state, Vector2(bounds - 0.3, -3), Vector2(bounds - 0.3, 3))
	paths = SIM._wall_paths(state)
	var goal: Vector2 = SIM._wall_goal(paths, Vector2(-5, 0), Vector2(bounds - 0.1, 0.0))
	assert_almost_eq(goal.x, bounds - 0.3 - EDGE, 0.0001, "the near face is past the bounds")


func test_walled_in_it_holds_then_walks_on_the_tick_a_wall_ends() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(0, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(state, Vector2(-3, -3), Vector2(3, -3))
	_wall(state, Vector2(3, -3), Vector2(3, 3), 2.0)
	_wall(state, Vector2(3, 3), Vector2(-3, 3))
	_wall(state, Vector2(-3, 3), Vector2(-3, -3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(10, 0)
	for tick: int in 19:
		SIM._update_field_objects(state)
		SIM._move_actors(state)
	assert_eq(knight.position, Vector2.ZERO, "no way out: it holds")
	assert_eq(state.field_objects.size(), 4)
	SIM._update_field_objects(state)
	SIM._move_actors(state)
	assert_eq(state.field_objects.size(), 3, "2 s of wall ends on tick 20 (ig-85w)")
	assert_gt(knight.position.x, 0.0, "and it walks that tick")


## ig-7sn.15 keeps a decoded state between advances; a command or a load decodes afresh. Both must walk
## the same path mid-detour, and after a wall ends (the kept state has to drop its corner graph).
func test_a_fresh_decode_walks_as_the_kept_state_mid_detour_and_after_a_wall_ends() -> void:
	var kept: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-5, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(kept, Vector2(0, -3), Vector2(0, 3), 1.5)
	kept.actors[0].order_kind = SIM.COMMAND_MOVE
	kept.actors[0].order_point = Vector2(5, 0)
	var fresh: BattleState = null
	for tick: int in 40:
		if tick == 5 or tick == 16:
			fresh = BattleState.from_dict(kept.to_dict())
		for state: BattleState in [kept, fresh]:
			if state != null:
				SIM._update_field_objects(state)
				SIM._move_actors(state)
		if tick == 14:
			assert_eq(kept.field_objects.size(), 0, "the wall is gone")
		if fresh != null:
			assert_eq(fresh.actors[0].position, kept.actors[0].position, "tick %d" % tick)
	assert_almost_eq(kept.actors[0].position.distance_to(Vector2(5, 0)), 0.0, 0.0001, "it arrives")


func test_every_instant_move_stops_at_the_first_footprint_edge() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-6, 0)),
		_unit("hero:carrier", "ranger", "ally", Vector2(-2, 2)),
		_unit("hero:body", "ranger", "ally", Vector2(-2, 2)),
		_unit("hero:a", "ranger", "ally", Vector2(-0.95, -2)),
		_unit("hero:b", "ranger", "ally", Vector2(-1.2, -2)),
		_unit("enemy:pushed", "rogue", "enemy", Vector2(-2, 0.5)),
		_unit("enemy:target", "rogue", "enemy", Vector2(4, 0)),
	])
	_wall(state, Vector2(0, -3), Vector2(0, 3))
	var paths: SIM.WallPaths = SIM._wall_paths(state)
	# _push: every push goes through it (Arcane Bloom, Threadneedle, telegraphs, the crit push, Charge's lane).
	var pushed: BattleActor = state.actors[5]
	SIM._push(state, pushed, Vector2.RIGHT, Vector2.RIGHT, 5.0)
	assert_almost_eq(pushed.position.x, -EDGE, 0.00001, "a push stops at the edge")
	assert_almost_eq(pushed.position.y, 0.5, 0.00001)
	# A carried body moves with its carrier.
	var carrier: BattleActor = state.actors[1]
	var body: BattleActor = state.actors[2]
	body.life = BattleActor.LIFE_DOWNED
	carrier.carrying_id = body.id
	body.carried_by_id = carrier.id
	SIM._push(state, carrier, Vector2.RIGHT, Vector2.RIGHT, 5.0)
	assert_almost_eq(carrier.position.x, -EDGE, 0.00001)
	assert_eq(body.position, carrier.position, "the body stays with its carrier")
	# The move effect: Charge's dash (and Slip, Dust Roll, Turncoat Cut, a flank) stops at the edge.
	var knight: BattleActor = state.actors[0]
	_give(knight, ["knight_charge"])
	assert_true(SIM._use_skill(state, knight, SIM.ABILITIES["knight_charge"], state.actors[6], state.actors[6].position, _rng()))
	assert_almost_eq(knight.position.x, -EDGE, 0.00001, "the dash stops at the wall")
	# Separation.
	var first: BattleActor = state.actors[3]
	SIM._apply_separation(state, first, paths)
	assert_almost_eq(first.position.x, -EDGE, 0.00001, "separation stops at the edge")
	for actor: BattleActor in state.actors:
		if actor != state.actors[6]:
			assert_false(absf(actor.position.x) < GROW and absf(actor.position.y) < 3.0 + GROW, "%s outside" % actor.id)


func test_one_that_spawned_in_a_wall_walks_out_its_own_side() -> void:
	var state: BattleState = _battle([
		_unit("hero:k", "knight", "ally", Vector2(-0.5, 0)),
		_unit("enemy:far", "rogue", "enemy", Vector2(15, 15)),
	])
	_wall(state, Vector2(0, -3), Vector2(0, 3))
	var knight: BattleActor = state.actors[0]
	knight.order_kind = SIM.COMMAND_MOVE
	knight.order_point = Vector2(5, 0)
	SIM._move_actors(state)
	SIM._move_actors(state)
	assert_lt(knight.position.x, -0.5, "out the way it stood, not through")


func test_a_mid_detour_save_through_disk_reloads_exactly_and_walks_on_as_the_unbroken_run() -> void:
	GameSession.cleared_zone_ids[&"verdant_outskirts"] = true
	var ids: Array[String] = []
	for archetype: StringName in [&"knight", &"knight", &"ranger", &"rogue", &"cleric"]:
		var hero := Hero.new("Waller %d" % ids.size(), 7)
		hero.def_id = archetype
		hero.level = 20
		hero.instance_id = "hero:wall:%d" % ids.size()
		GameSession.roster.append(hero)
		ids.append(hero.instance_id)
	var preset_id: String = GameSession.save_team_preset("", "Walls", ids, "ashfall_reaches")
	var order_id: String = GameSession.dispatch_force([preset_id], "ashfall_reaches", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0})
	assert_ne(order_id, "", GameSession.last_action_error)
	var seeded: Dictionary = Compare.json_round_trip(GameSession.to_dict())
	var battle: Dictionary = _battle_of(seeded)
	battle["rng_state"] = "1"
	var heroes: Vector2 = _centroid(battle, "ally")
	var enemies: Vector2 = _centroid(battle, "enemy")
	var way: Vector2 = (enemies - heroes).normalized()
	var center: Vector2 = heroes + (enemies - heroes) * 0.4
	var across := Vector2(-way.y, way.x)
	battle["field_sequence"] = 1
	battle["field_objects"] = [{
		"id": "field:1", "kind": "wall", "skill_id": "test_wall", "owner_actor_id": str((battle["actors"] as Array)[0]["id"]), "faction": "ally",
		"start": [(center - across * 3.0).x, (center - across * 3.0).y], "end": [(center + across * 3.0).x, (center + across * 3.0).y],
		"thickness": 1.2, "remaining_seconds": 5.0,
	}]
	assert_eq(Session.validate_saved_state(seeded, 3), "", "a checkpoint with a wall is valid")
	GameSession.from_dict(seeded)
	GameSession.tick_expeditions(2.0)
	var snapshot: Dictionary = GameSession.get_battle_snapshot(order_id)
	assert_eq(str(snapshot["status"]), "active")
	var state := BattleState.from_dict(snapshot)
	var paths: SIM.WallPaths = SIM._wall_paths(state)
	assert_eq(paths.centers.size(), 1)
	assert_true(state.actors.any(func(actor: BattleActor) -> bool: return actor.faction == "ally" and SIM._wall_blocked(paths, actor.position, enemies)), "someone is mid-detour")
	_save_to_disk()
	var first: Dictionary = GameSession.to_dict()
	var want: Dictionary = Compare.json_round_trip(first)
	for _second: int in 8:
		GameSession.tick_expeditions(1.0)
	var straight: Array = _where(GameSession.get_battle_snapshot(order_id))

	# The wall ends 3 s after the save. A fresh decode after that (a command, ig-7sn.15) walks as the kept
	# state, which had to drop its corner graph when the wall ended.
	GameSession.from_dict(first.duplicate(true))
	for _second: int in 4:
		GameSession.tick_expeditions(1.0)
	GameSession._battle_states.clear()
	for _second: int in 4:
		GameSession.tick_expeditions(1.0)
	assert_eq(Compare.first_difference(_where(GameSession.get_battle_snapshot(order_id)), straight), "", "a fresh decode walks as the kept state")

	GameSession.from_dict({"roster": []})
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var got: Dictionary = GameSession.to_dict()
	got.erase("saved_at_unix")
	want.erase("saved_at_unix")
	assert_eq(Compare.first_difference(got, want), "", "the reload is the round trip")
	for _second: int in 8:
		GameSession.tick_expeditions(1.0)
	assert_eq(Compare.mismatch(_where(GameSession.get_battle_snapshot(order_id)), straight), "", "and walks on as the unbroken run")

	var profile: Dictionary = Compare.json_round_trip(first)
	assert_eq(BattleState.from_dict(_battle_of(profile)).field_objects.size(), 1, "a wall reads nothing from its skill, so an unknown one keeps it")
	var legacy: Dictionary = profile.duplicate(true)
	_battle_of(legacy).erase("field_objects")
	_battle_of(legacy).erase("field_sequence")
	assert_eq(Session.validate_saved_state(legacy, 3), "", "a checkpoint from before walls loads")
	for bad: Array in [["start", [999.0, 0.0]], ["end", [NAN, 0.0]], ["end", [1.0]], ["thickness", 0.0], ["thickness", -1.0], ["thickness", INF], ["thickness", 1e39],["remaining_seconds", 0.0], ["extra", 1], ["kind", "zone"]]:
		var broken: Dictionary = profile.duplicate(true)
		(_battle_of(broken)["field_objects"] as Array)[0][bad[0]] = bad[1]
		assert_ne(Session.validate_saved_state(broken, 3), "", "%s %s is rejected" % bad)
	var point: Dictionary = profile.duplicate(true)
	var wall: Dictionary = (_battle_of(point)["field_objects"] as Array)[0]
	wall["end"] = (wall["start"] as Array).duplicate()
	assert_ne(Session.validate_saved_state(point, 3), "", "a wall with no length is rejected")
	var short: Dictionary = profile.duplicate(true)
	((_battle_of(short)["field_objects"] as Array)[0] as Dictionary).erase("thickness")
	assert_ne(Session.validate_saved_state(short, 3), "", "a wall missing a field is rejected")


func _wall(state: BattleState, start: Vector2, finish: Vector2, seconds: float = 60.0) -> void:
	state.field_sequence += 1
	state.field_objects.append({
		"id": "field:%d" % state.field_sequence,
		"kind": "wall",
		"skill_id": "test_wall",
		"owner_actor_id": state.actors[0].id,
		"faction": "ally",
		"start": [start.x, start.y],
		"end": [finish.x, finish.y],
		"thickness": 1.2,
		"remaining_seconds": seconds,
	})


func _centroid(battle: Dictionary, faction: String) -> Vector2:
	var sum := Vector2.ZERO
	var count: int = 0
	for actor: Dictionary in battle["actors"]:
		if actor["faction"] == faction:
			sum += Vector2(float(actor["position"][0]), float(actor["position"][1]))
			count += 1
	return sum / float(count)


## A real SaveService write, stamped ahead so the reload adds no offline time.
func _save_to_disk() -> void:
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	on_disk["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	var file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(on_disk, "	", true, true))
	file.close()


func _battle_of(profile: Dictionary) -> Dictionary:
	return ((profile["expedition_orders"] as Array)[0] as Dictionary)["battle"] as Dictionary


## The exact facts first (walls included), then each actor's floats.
func _where(snapshot: Dictionary) -> Array:
	var result: Array = []
	var walls: String = str((snapshot["field_objects"] as Array).map(func(field: Dictionary) -> String: return "%s %s" % [field["id"], field["kind"]]))
	for actor: Dictionary in snapshot["actors"]:
		result.append(["%s %s %s %d %s" % [snapshot["rng_state"], actor["id"], actor["life"], int(snapshot["tick"]), walls], float(actor["hp"]), float(actor["position"][0]), float(actor["position"][1])])
	return result


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return rng


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


## No zone spawns (the enemies come in the list), Auto Battle off, empty kits.
func _battle(snapshots: Array[Dictionary]) -> BattleState:
	var hero_ids: Array = snapshots.filter(func(snapshot: Dictionary) -> bool: return snapshot["faction"] == "ally").map(func(snapshot: Dictionary) -> String: return snapshot["hero_id"])
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]
	var state: BattleState = SIM.create_run("walls:1", snapshots, ZoneDefinition.definition_for(&"verdant_outskirts"), squads, {"auto_battle": false}, {"healing": 0, "revival": 0}, 7, "rescue", 1)
	for actor: BattleActor in state.actors:
		actor.skills.clear()
		actor.skill_cooldowns.clear()
	return state


func _give(actor: BattleActor, skill_ids: Array) -> void:
	actor.skills.clear()
	actor.skill_cooldowns.clear()
	for skill_id: String in skill_ids:
		actor.add_skill(SIM.ABILITIES[skill_id])
