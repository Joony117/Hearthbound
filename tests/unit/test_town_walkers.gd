extends GutTest

# ig-6m2.6.1: keepers and workers walk House -> work -> House over the hex walk graph. Walking is
# cosmetic: nothing is saved and the global RNG is never drawn.

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
	assert_false(town.walkers.has(keeper.instance_id), "unstationed: gone")
	assert_true(GameSession.station_hero(keeper, &"Forge"), GameSession.last_action_error)
	assert_true(town.walkers[keeper.instance_id].is_walking(), "stationed later: it walks in")
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


func test_the_body_and_the_partner_never_get_a_figure_and_the_old_body_steps_out_where_it_stood() -> void:
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
	assert_false(town.walkers.has(bea.instance_id), "the partner has no figure")
	var stood: Vector3 = TownRules.hex_to_world(Vector2i(3, 2))
	town.body.global_position = town.to_global(stood)
	assert_true(GameSession.step_out())
	var walker: TownWalker = town.walkers.get(ada.instance_id)
	assert_not_null(walker, "out of the body: a figure")
	assert_almost_eq(walker.position.distance_to(stood), 0.0, 0.001, "where the body stood")
	assert_almost_eq(walker.destination().distance_to(town.work_spot(&"Forge")), 0.0, 0.001, "walking to work")
	_walk_out(town, walker, "out of the body")
	assert_true(town.walkers.has(bea.instance_id), "no body, no partner: Bea walks again")


func test_walking_saves_nothing_and_never_draws_the_global_rng() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	town.show_buildings(GameSession.town_buildings)
	var worker: Hero = _worker("Wren", house, mill)
	var keeper: Hero = _add_hero("Kira")
	assert_true(GameSession.station_hero(keeper, &"Forge"))
	var before: Dictionary = GameSession.to_dict()
	seed(1234)
	var expected: int = randi()
	seed(1234)
	town.show_walkers([worker, keeper])
	var walker: TownWalker = town.walkers[worker.instance_id]
	assert_true(walker.has_loop())
	var activities: Dictionary = {}
	for _step: int in 300:
		for figure: TownWalker in town.walkers.values():
			figure.step(0.25)
		activities[walker.activity] = true
	assert_eq(randi(), expected, "the global RNG was never drawn")
	assert_eq(activities.keys().size(), 3, "75 s covers work, the walk home, rest and back")
	assert_eq(GameSession.to_dict(), before, "nothing saved moved")
	for script: String in ["res://hub/town/town_walker.gd", "res://hub/town/town_view.gd"]:
		var code: PackedStringArray = []
		for line: String in FileAccess.get_file_as_string(script).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		assert_false("\n".join(code).contains("GameSession"), "%s never reads GameSession (comments aside)" % script)


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
	assert_eq(TownWalker.work_clip(&"Mine_1"), TownWalker.DEFAULT_WORK_CLIP, "a station without a row works too")
	assert_eq(TownWalker.work_clip(&"Lumbermill_2"), &"Chopping")


## ---- helpers

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


func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
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
