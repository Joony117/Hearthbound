extends GutTest

# ig-6m2.6.1: keepers and workers walk House -> work -> House over the hex walk graph. ig-6m2.6.2:
# heroes with no job wander the streets, up to a cap, and a click on any walker opens that hero.
# Walking is cosmetic: nothing is saved and the global RNG is never drawn.

const HOUSE_HEX: Vector2i = Vector2i(1, -2)
## South of the halls' row, so the House -> Lumbermill route has a hall between its ends.
const MILL_HEX: Vector2i = Vector2i(0, 2)
const ZONE: String = "verdant_outskirts"


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0


func after_each() -> void:
	GameSession.set_process(true)


func test_a_route_goes_around_buildings_and_follows_a_place_and_a_move() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var path: PackedVector3Array = town.route(house, mill)
	_assert_clear(town, path, "around, not through")
	assert_almost_eq(path[path.size() - 1].distance_to(town.work_spot(mill)), 0.0, 0.001, "ends at the WorkSpot")
	var crossed: Vector2i = TownRules.world_to_hex(path[path.size() >> 1])
	_place(TownRules.LUMBERMILL, crossed)
	town.show_buildings(GameSession.town_buildings)
	var around: PackedVector3Array = town.route(house, mill)
	assert_false(around.is_empty())
	for point: Vector3 in around:
		assert_ne(TownRules.world_to_hex(point), crossed, "the new route avoids the placed hex")
	_assert_clear(town, around, "around the placed building too")
	var hero: Hero = _worker("Wren", house, mill)
	town.show_walkers([hero])
	assert_true(GameSession.move_building(mill, Vector2i(-3, 3)), GameSession.last_action_error)
	town.show_buildings(GameSession.town_buildings)
	var walker: TownWalker = town.walkers[hero.instance_id]
	assert_true(walker.is_walking(), "its building moved: it walks to the new spot")
	assert_almost_eq(walker.destination().distance_to(town.work_spot(mill)), 0.0, 0.001)
	_walk_out(town, walker, "to the moved Lumbermill")


func test_a_built_over_figure_and_body_step_onto_free_ground() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var hero: Hero = _worker("Wren", house, mill)
	town.show_walkers([hero])
	var walker: TownWalker = town.walkers[hero.instance_id]
	var standing: Vector2i = Vector2i(3, 2)
	walker.position = TownRules.hex_to_world(standing) + Vector3(0.5, 0.0, 0.5)
	town.embody(_add_hero("Body"))
	var under_body: Vector2i = Vector2i(-3, 2)
	town.body.global_position = town.to_global(TownRules.hex_to_world(under_body))
	_place(TownRules.HOUSE, standing)
	_place(TownRules.HOUSE, under_body)
	town.show_buildings(GameSession.town_buildings)
	_assert_on_free_ground(town, walker.position, "the figure")
	_assert_on_free_ground(town, town.to_local(town.body.global_position), "the body")
	assert_true(walker.is_walking(), "then it walks on")
	_walk_out(town, walker, "on from the snap")


func test_a_walled_in_worker_stands_and_works() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	for hex: Vector2i in town.approach_hexes(mill):
		_place(TownRules.HOUSE, hex)
	town.show_buildings(GameSession.town_buildings)
	var hero: Hero = _worker("Wren", house, mill)
	town.show_walkers([] as Array[Hero])
	town.show_walkers([hero])
	var walker: TownWalker = town.walkers[hero.instance_id]
	assert_false(walker.has_loop())
	assert_false(walker.is_walking(), "no way in: it does not walk from the gate")
	assert_eq(walker.activity, TownWalker.WORK)
	assert_almost_eq(walker.position.distance_to(town.work_spot(mill)), 0.0, 0.001, "at its spot")
	for _step: int in 100:
		walker.step(1.0)
	assert_eq(walker.activity, TownWalker.WORK, "and stays there")


func test_a_figure_at_a_walled_in_door_steps_out_onto_free_ground() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var hero: Hero = _worker("Wren", house, mill)
	town.show_walkers([hero])
	var walker: TownWalker = town.walkers[hero.instance_id]
	var door: Vector3 = town.work_spot(house)
	walker.position = door
	walker.walk(PackedVector3Array([door]), TownWalker.REST)
	walker.step(0.1)
	assert_eq(walker.activity, TownWalker.REST, "resting at its door")
	for hex: Vector2i in town.approach_hexes(house):
		_place(TownRules.LUMBERMILL, hex)
	town.show_buildings(GameSession.town_buildings)
	assert_almost_eq(walker.position.distance_to(town.free_point(door)), 0.0, 0.001, "stepped onto the nearest free ground")
	_assert_on_free_ground(town, walker.position, "the figure")
	assert_true(walker.is_walking())
	assert_almost_eq(walker.destination().distance_to(town.work_spot(mill)), 0.0, 0.001, "then to work")
	_walk_out(town, walker, "from the walled-in door")


func test_the_figures_follow_the_roster_state() -> void:
	var keeper: Hero = _add_hero("Kira")
	assert_true(GameSession.station_hero(keeper, &"Forge"), GameSession.last_action_error)
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var walker: TownWalker = town.walkers.get(keeper.instance_id)
	assert_not_null(walker, "stationed: a figure")
	assert_eq(walker.activity, TownWalker.WORK, "the first show starts at work")
	assert_almost_eq(walker.position.distance_to(town.work_spot(&"Forge")), 0.0, 0.001)
	GameSession.expeditions_changed.emit()
	assert_eq(town.walkers[keeper.instance_id], walker, "a quiet pulse keeps the node")
	assert_eq(walker.destination(), town.work_spot(&"Forge"), "and its destination")
	assert_true(GameSession.unstation_hero(keeper), GameSession.last_action_error)
	assert_eq(town.walkers.get(keeper.instance_id), walker, "unstationed: the same figure wanders")
	assert_eq(walker.station, Hero.NO_STATION)
	walker.step(2.0)
	var stood: Vector3 = walker.position
	assert_true(GameSession.station_hero(keeper, &"Forge"), GameSession.last_action_error)
	assert_eq(town.walkers[keeper.instance_id], walker, "stationed again: still the same figure")
	assert_eq(walker.position, stood, "it re-plans from where it stands, not from the gate")
	assert_true(walker.is_walking(), "and walks to its place")
	assert_almost_eq(walker.destination().distance_to(town.work_spot(&"Forge")), 0.0, 0.001)
	assert_ne(GameSession.dispatch_expedition([keeper.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	assert_false(town.walkers.has(keeper.instance_id), "dispatched: gone")
	GameSession.expedition_orders.clear()
	GameSession.expeditions_changed.emit()
	walker = town.walkers.get(keeper.instance_id)
	assert_not_null(walker, "back: a figure")
	assert_almost_eq(walker.position.distance_to(town.work_spot(&"TownGate")), 0.0, 0.001, "at the gate")
	assert_true(walker.is_walking())
	assert_almost_eq(walker.destination().distance_to(town.work_spot(&"Forge")), 0.0, 0.001, "walking to its place")
	_walk_out(town, walker, "in from the gate")
	GameSession.kill_hero(keeper, &"verdant_outskirts", preload("res://balance.tres"))
	assert_false(town.walkers.has(keeper.instance_id), "dead: gone")


func test_the_body_has_no_figure_the_partner_has_one_and_the_old_body_steps_out_where_it_stood() -> void:
	var ada: Hero = _add_hero("Ada")
	var bea: Hero = _add_hero("Bea")
	assert_true(GameSession.station_hero(ada, &"Forge"))
	assert_true(GameSession.station_hero(bea, &"Sanctum"))
	for index: int in 2:
		Ledger.append(GameSession.ledger, GameSession.ledger.size() + 1, 0, "battle", {"order": "order:%d" % index, "zone": ZONE, "team": [ada.instance_id, bea.instance_id], "result": "victory", "moments": [{"tick": 1, "what": "revived", "hero": ada.instance_id, "by": bea.instance_id}]})
	GameSession.ledger_next_seq = GameSession.ledger.size() + 1
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	assert_eq(town.walkers.size(), 2, "both keepers at work")
	assert_true(GameSession.embody_hero(ada.instance_id))
	assert_not_null(town.partner, "Bea is Ada's partner")
	assert_false(town.walkers.has(ada.instance_id), "the body has no figure")
	assert_eq(town.partner, town.walkers.get(bea.instance_id), "the partner is its own walker")
	assert_eq(_figures(town, bea.instance_id), 1, "exactly one figure")
	assert_eq(_figures(town, ada.instance_id), 0)
	var stood: Vector3 = TownRules.hex_to_world(Vector2i(3, 2))
	town.body.global_position = town.to_global(stood)
	assert_true(GameSession.step_out())
	var walker: TownWalker = town.walkers.get(ada.instance_id)
	assert_not_null(walker, "out of the body: a figure")
	assert_almost_eq(walker.position.distance_to(stood), 0.0, 0.001, "where the body stood")
	assert_almost_eq(walker.destination().distance_to(town.work_spot(&"Forge")), 0.0, 0.001, "walking to work")
	_walk_out(town, walker, "out of the body")
	assert_null(town.partner, "no body, no partner")
	assert_eq(_figures(town, bea.instance_id), 1, "Bea walks on as one figure")


func test_walking_saves_nothing_and_never_draws_the_global_rng() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var worker: Hero = _worker("Wren", house, mill)
	var keeper: Hero = _add_hero("Kira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var idle: Hero = _add_hero("Ivo")
	var homed: Hero = _add_hero("Hal")
	assert_true(GameSession.assign_home(homed, _place(TownRules.HOUSE, Vector2i(-2, 3))), GameSession.last_action_error)
	town.show_buildings(GameSession.town_buildings)
	var before: Dictionary = GameSession.to_dict()
	seed(1234)
	var expected: int = randi()
	seed(1234)
	town.show_walkers([worker, keeper, idle, homed])
	assert_eq(town.walkers.size(), 4, "the wanderers too")
	var walker: TownWalker = town.walkers[worker.instance_id]
	assert_true(walker.has_loop())
	var activities: Dictionary = {}
	for _step: int in 300:
		for figure: TownWalker in town.walkers.values():
			figure.step(0.25)
		activities[walker.activity] = true
	assert_eq(randi(), expected, "the global RNG was never drawn")
	assert_eq(activities.keys().size(), 3, "75 s covers work, the walk home, rest and back")
	assert_eq(town.walkers[idle.instance_id].station, Hero.NO_STATION, "Ivo wandered")
	assert_eq(GameSession.to_dict(), before, "nothing saved moved")
	for script: String in ["res://hub/town/town_walker.gd", "res://hub/town/town_view.gd"]:
		var code: PackedStringArray = []
		for line: String in FileAccess.get_file_as_string(script).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		assert_false("\n".join(code).contains("GameSession"), "%s never reads GameSession (comments aside)" % script)


# 60 s of wandering, sampled every 0.25 m: never inside a grown box. A wanderer lingering on a hall's
# approach hex faces the hall and plays Interact; one with a House sometimes ends a trip at its door.
func test_wanderers_walk_only_free_ground_use_the_stalls_and_go_home() -> void:
	var town: TownView = _town()
	var houses: Array[StringName] = [_place(TownRules.HOUSE, HOUSE_HEX), _place(TownRules.HOUSE, Vector2i(-2, 3))]
	_place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var heroes: Array[Hero] = []
	for index: int in 6:
		var hero: Hero = _add_hero("W%d" % index)
		hero.instance_id = "wanderer_%d" % index
		if index < houses.size():
			assert_true(GameSession.assign_home(hero, houses[index]), GameSession.last_action_error)
		heroes.append(hero)
	town.show_walkers(heroes)
	assert_eq(town.walkers.size(), 6)
	var halls_at: Dictionary = {}
	for building: Dictionary in GameSession.town_buildings:
		var id := StringName(str(building["id"]))
		if TownRules.type_of(id) == &"":
			for hex: Vector2i in town.approach_hexes(id):
				if not halls_at.has(hex):
					halls_at[hex] = []
				(halls_at[hex] as Array).append(id)
	var boxes: Array[Rect2] = _boxes(town)
	var stall_uses: int = 0
	var home_rests: int = 0
	for _step: int in 600:
		for walker: TownWalker in town.walkers.values():
			walker.step(0.1)
			var at: Vector3 = walker.position
			for box: Rect2 in boxes:
				if box.has_point(Vector2(at.x, at.z)):
					fail_test("%s walked into a box at %s" % [walker.hero_id, at])
					return
			if walker.activity != TownWalker.LINGER:
				continue
			var hex: Vector2i = TownRules.world_to_hex(at)
			if halls_at.has(hex) and at.distance_to(TownRules.hex_to_world(hex)) < 0.001:
				stall_uses += 1
				assert_eq(walker.clip(), &"Interact", "at a stall it uses it")
				var faces_a_hall: bool = false
				for hall: StringName in halls_at[hex]:
					var hall_at: Vector3 = (town.get_node(NodePath(hall)) as Node3D).position
					faces_a_hall = faces_a_hall or absf(angle_difference(walker.facing(), atan2(hall_at.x - at.x, hall_at.z - at.z))) < 0.01
				assert_true(faces_a_hall, "%s faces the hall" % walker.hero_id)
			elif walker.home != Hero.NO_HOME and at.distance_to(town.work_spot(walker.home)) < 0.001:
				home_rests += 1
				assert_eq(walker.clip(), &"Idle_A", "at its door it rests")
	assert_gt(stall_uses, 0, "someone used a stall")
	assert_gt(home_rests, 0, "someone went home")


# The cap counts wanderers only, and keeps the pick order: favorites, higher rank, lower id. Keepers
# show beyond it. The set follows a dispatch, a return, a summon and a death.
func test_the_cap_keeps_the_pick_order_and_follows_the_roster() -> void:
	var keeper: Hero = _add_hero("Kira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var idle: Array[Hero] = []
	for index: int in TownView.AMBIENT_HERO_CAP + 3:
		var hero: Hero = _add_hero("H%02d" % index)
		hero.instance_id = "idle_%02d" % index
		hero.rank = index % 3
		idle.append(hero)
	idle.back().favorite = true
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var order: Array[Hero] = idle.duplicate()
	order.sort_custom(func(a: Hero, b: Hero) -> bool:
		if a.favorite != b.favorite:
			return a.favorite
		if a.rank != b.rank:
			return a.rank > b.rank
		return a.instance_id < b.instance_id)
	assert_eq(order[0], idle.back(), "the favorite first")
	assert_eq(_shown(town), _ids([keeper] + order.slice(0, TownView.AMBIENT_HERO_CAP)), "the keeper and the first CAP wanderers")
	var out: Hero = order[0]
	assert_ne(GameSession.dispatch_expedition([out.instance_id], ZONE, 1, "Out"), "", GameSession.last_action_error)
	assert_eq(_shown(town), _ids([keeper] + order.slice(1, TownView.AMBIENT_HERO_CAP + 1)), "dispatched: the next one in")
	GameSession.expedition_orders.clear()
	GameSession.expeditions_changed.emit()
	assert_eq(_shown(town), _ids([keeper] + order.slice(0, TownView.AMBIENT_HERO_CAP)), "back: the same set")
	var summoned := Hero.new("New", 7)
	summoned.def_id = &"knight"
	summoned.instance_id = "idle_zz"
	summoned.rank = 9
	summoned.favorite = true
	GameSession.stones = 1000
	assert_true(GameSession.summon_hero(summoned, preload("res://balance.tres")), GameSession.last_action_error)
	assert_eq(_shown(town), _ids([keeper, summoned] + order.slice(0, TownView.AMBIENT_HERO_CAP - 1)), "summoned: in first, the last one out")
	GameSession.kill_hero(summoned, &"verdant_outskirts", preload("res://balance.tres"))
	assert_eq(_shown(town), _ids([keeper] + order.slice(0, TownView.AMBIENT_HERO_CAP)), "dead: gone, the set as before")
	# The partner shows on top of the cap wherever it sits in the list (hub.gd sorts it first anyway).
	var partner: Hero = order.back()
	town._partner_id = partner.instance_id
	var listed: Array[Hero] = [keeper]
	listed.append_array(order)
	town.show_walkers(listed)
	assert_eq(_shown(town), _ids([keeper] + order.slice(0, TownView.AMBIENT_HERO_CAP) + [partner]), "the partner beyond the cap")


# ig-6m2.6.2 item 4 (director, 2026-09-24): a click on any walker opens that hero, keepers included,
# even with the building right behind it. A click on the building still names the building. With a
# body, the hero opens at once and the body does not walk.
func test_a_click_on_a_walker_opens_that_hero_and_a_building_click_still_names_it() -> void:
	var keeper: Hero = _add_hero("Kira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var body: Hero = _add_hero("Ada")
	var hub: Node3D = _hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var walker: TownWalker = town.walkers[keeper.instance_id]
	await wait_physics_frames(2)
	var at: Vector2 = _walker_point(hub, walker)
	assert_ne(at, Vector2(-1, -1), "a clickable point on the keeper")
	assert_eq(_building_behind(town, at), "Forge", "the Forge is right behind the keeper there")
	watch_signals(town)
	_click(hub, at)
	assert_signal_emitted_with_parameters(town, "hero_selected", [keeper.instance_id])
	assert_signal_not_emitted(town, "building_selected", "the walker in front wins")
	assert_true((hub.get_node("%SelectedHeroPanel") as Control).visible, "its detail is open")
	assert_true((hub.get_node("%SharedRosterPanel") as Control).visible)
	assert_eq(hub._selected_hero(), keeper, "with that hero selected")
	assert_string_contains((hub.get_node("%HeroDetail") as Label).text, "History:")
	hub._open(&"")
	var forge_at: Vector2 = _town_point(hub, &"Forge")
	assert_ne(forge_at, Vector2(-1, -1), "a clickable point on the Forge")
	_click(hub, forge_at)
	assert_signal_emitted_with_parameters(town, "building_selected", [&"Forge"])
	assert_true((hub.get_node("%KeeperPanel") as Control).visible, "the Forge opens")
	hub._open(&"")
	hub._roster_favorites_only.button_pressed = true
	assert_true(GameSession.embody_hero(body.instance_id))
	await wait_physics_frames(2)
	at = _walker_point(hub, walker)
	assert_ne(at, Vector2(-1, -1), "the keeper is on screen from the body's camera")
	_click(hub, at)
	assert_signal_emit_count(town, "hero_selected", 2)
	assert_eq(hub._selected_hero(), keeper, "opened at once, though favorites-only hid it")
	assert_false(hub._roster_favorites_only.button_pressed, "the filter that hid it is cleared")
	assert_false(town.body.is_walking(), "no walk")


func test_every_work_clip_is_in_the_library_and_loops() -> void:
	var library: AnimationLibrary = HeroModel.shared_clips()
	var clips: Array[StringName] = []
	clips.assign(TownWalker.WORK_CLIPS.values())
	clips.append(TownWalker.DEFAULT_WORK_CLIP)
	for clip: StringName in clips:
		assert_true(library.has_animation(clip), "%s is in the library" % clip)
		if library.has_animation(clip):
			var animation: Animation = library.get_animation(clip)
			assert_eq(animation.loop_mode, Animation.LOOP_LINEAR, "%s loops" % clip)
			assert_lt(_loop_seam(animation), 0.05, "%s ends where it starts" % clip)
	assert_eq(TownWalker.work_clip(&"Mine_1"), &"Pickaxing")
	assert_eq(TownWalker.work_clip(&"Farm_1"), &"Digging")
	assert_eq(TownWalker.work_clip(&"Well_1"), TownWalker.DEFAULT_WORK_CLIP, "a station without a row works too")
	assert_eq(TownWalker.work_clip(&"Lumbermill_2"), &"Chopping")


## ---- helpers

## How many TownWalker figures in town stand for hero_id.
func _figures(town: TownView, hero_id: String) -> int:
	var count: int = 0
	for child: Node in town.get_children():
		if child is TownWalker and (child as TownWalker).hero_id == hero_id:
			count += 1
	return count


func _shown(town: TownView) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(town.walkers.keys())
	ids.sort()
	return ids


func _ids(heroes: Array) -> Array[String]:
	var ids: Array[String] = []
	for hero: Hero in heroes:
		ids.append(hero.instance_id)
	ids.sort()
	return ids


## A point on walker's figure that a pushed click reaches (not under GUT's own output panel), or
## (-1, -1). Chest height first, then down its body.
func _walker_point(hub: Node3D, walker: TownWalker) -> Vector2:
	var camera: Camera3D = hub.get_viewport().get_camera_3d()
	for height: float in [1.0, 0.6, 1.4, 0.3]:
		var point: Vector3 = walker.global_position + Vector3(0.0, height, 0.0)
		if not camera.is_position_in_frustum(point):
			continue
		var at: Vector2 = camera.unproject_position(point)
		if _reachable(hub, at) and (hub.get_node("%Town") as TownView)._pick(at) == walker:
			return at
	return Vector2(-1, -1)


## A reachable screen point where a click names building, or (-1, -1).
func _town_point(hub: Node3D, building: StringName) -> Vector2:
	var town: TownView = hub.get_node("%Town") as TownView
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	for y: int in range(0, int(size.y), 16):
		for x: int in range(0, int(size.x), 16):
			var at := Vector2(x, y)
			if town.building_at(at) == building and _reachable(hub, at):
				return at
	return Vector2(-1, -1)


## The building a ray on the building layer alone meets at at: what the walker stands in front of.
func _building_behind(town: TownView, at: Vector2) -> String:
	var camera: Camera3D = town.get_viewport().get_camera_3d()
	var from: Vector3 = camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * TownView.PICK_DISTANCE, TownView.PICK_LAYER)
	var hit: Dictionary = town.get_world_3d().direct_space_state.intersect_ray(query)
	return "" if hit.is_empty() else str((hit["collider"] as Node).get_parent().name)


## GUT's own output panel covers part of the viewport and eats clicks there (bd memory
## headless-gut-click-tests); a usable point is under the hub or nothing.
func _reachable(hub: Node3D, at: Vector2) -> bool:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	hub.get_viewport().push_input(motion, true)
	var hovered: Control = hub.get_viewport().gui_get_hovered_control()
	return hovered == null or hub.is_ancestor_of(hovered)


func _click(hub: Node3D, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		hub.get_viewport().push_input(click, true)


## The largest rotation jump (radians) between a clip's first and last key over its bone tracks.
func _loop_seam(animation: Animation) -> float:
	var seam: float = 0.0
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or animation.track_get_key_count(track) < 2:
			continue
		var first: Quaternion = animation.track_get_key_value(track, 0)
		var last: Quaternion = animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)
		seam = maxf(seam, first.angle_to(last))
	return seam


## Steps walker to the end of its walk (0.1 s steps, 0.25 m at WALK_SPEED), failing on any position
## inside a building's grown box: the path it actually walks, not only the route it was given.
func _walk_out(town: TownView, walker: TownWalker, what: String) -> void:
	var boxes: Array[Rect2] = _boxes(town)
	for _step: int in 2000:
		if not walker.is_walking():
			assert_eq(walker.activity, TownWalker.WORK, "%s: arrived at work" % what)
			return
		walker.step(0.1)
		for box: Rect2 in boxes:
			if box.has_point(Vector2(walker.position.x, walker.position.z)):
				fail_test("%s: walked through a box at %s" % [what, walker.position])
				return
	fail_test("%s: the walk never ended" % what)


func _assert_clear(town: TownView, path: PackedVector3Array, what: String) -> void:
	assert_gt(path.size(), 1, what)
	var boxes: Array[Rect2] = _boxes(town)
	for index: int in range(1, path.size()):
		var from: Vector3 = path[index - 1]
		var length: float = from.distance_to(path[index])
		var samples: int = maxi(1, ceili(length / 0.25))
		for sample: int in samples + 1:
			var at: Vector3 = from.lerp(path[index], float(sample) / samples)
			for box: Rect2 in boxes:
				if box.has_point(Vector2(at.x, at.z)):
					fail_test("%s: %s is inside a building's box" % [what, at])
					return


func _assert_on_free_ground(town: TownView, at: Vector3, what: String) -> void:
	for box: Rect2 in _boxes(town):
		assert_false(box.has_point(Vector2(at.x, at.z)), "%s is outside every box" % what)
	var hex: Vector2i = TownRules.world_to_hex(at)
	for building: Dictionary in GameSession.town_buildings:
		assert_ne(Vector2i(building["q"], building["r"]), hex, "%s stands on a free hex" % what)


## Every placed building's pick box, read from its scene and grown by 0.3 m, as town-space x/z.
func _boxes(town: TownView) -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	for building: Dictionary in GameSession.town_buildings:
		var node: Node3D = town.get_node(NodePath(str(building["id"])))
		var pick: Node3D = node.get_node("Pick") as Node3D
		var shape: CollisionShape3D = pick.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var centre: Vector3 = node.transform * pick.transform * shape.position
		boxes.append(Rect2(centre.x - size.x / 2.0, centre.z - size.z / 2.0, size.x, size.z).grow(0.3))
	return boxes


## Placed and finished at once: construction (ig-6m2.3.2) is not what this file tests.
func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	GameSession.town_building(id).erase("build_remaining")
	return id


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


func _worker(hero_name: String, house: StringName, mill: StringName) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	assert_true(GameSession.assign_home(hero, house), GameSession.last_action_error)
	assert_true(GameSession.station_hero(hero, mill), GameSession.last_action_error)
	return hero


func _town() -> TownView:
	var world := Node3D.new()
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	world.add_child(town)
	add_child_autofree(world)
	town.show_buildings(GameSession.town_buildings)
	return town


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
