extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


func before_each() -> void:
	GameSession.set_process(false)
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	_release_keys()
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.set_process(true)


func test_embody_and_step_out_change_the_body_and_notify() -> void:
	var hero: Hero = _add_hero("Walker")
	watch_signals(GameSession)
	assert_true(GameSession.embody_hero(hero.instance_id))
	assert_eq(GameSession.embodied_hero_id, hero.instance_id)
	assert_true(GameSession.is_embodied(hero))
	assert_signal_emit_count(GameSession, "roster_changed", 1)
	GameSession.step_out()
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY)
	assert_signal_emit_count(GameSession, "roster_changed", 2)


func test_embody_refuses_a_missing_or_away_hero() -> void:
	assert_false(GameSession.embody_hero("not-a-hero"))
	assert_ne(GameSession.last_action_error, "")
	var away: Hero = _add_hero("Away")
	assert_ne(GameSession.dispatch_expedition([away.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	assert_false(GameSession.embody_hero(away.instance_id))
	assert_string_contains(GameSession.last_action_error, "Away")
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY)


func test_every_dispatch_entry_point_refuses_the_body_by_name() -> void:
	var body: Hero = _embodied("Aster Body")
	var ids: Array[String] = [body.instance_id]
	assert_eq(GameSession.dispatch_expedition(ids, "verdant_outskirts", 1, "Out"), "")
	assert_string_contains(GameSession.last_action_error, "Aster Body")
	var preset: String = GameSession.save_team_preset("", "Team", ids, "verdant_outskirts")
	var presets: Array[String] = [preset]
	assert_false(bool(GameSession.preview_force(presets, "verdant_outskirts", 1, {}, LOADOUT).get("valid", true)))
	assert_eq(GameSession.dispatch_force(presets, "verdant_outskirts", 1, {}, LOADOUT), "")
	assert_string_contains(GameSession.last_action_error, "Aster Body")
	GameSession.stranded_incidents.append({"id": "incident", "zone_id": "verdant_outskirts"})
	assert_eq(GameSession.dispatch_rescue("incident", preset, LOADOUT), "")
	assert_string_contains(GameSession.last_action_error, "Aster Body")
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(cache)
	assert_eq(GameSession.recover_cache(cache, [body], BALANCE), GameSession.RECOVERY_INVALID_TEAM)
	assert_string_contains(GameSession.last_action_error, "Aster Body")
	assert_true(GameSession.expedition_orders.is_empty(), "nothing was sent out")
	assert_true(GameSession.lost_caches.has(cache))


func test_the_body_cannot_be_sacrificed_even_in_bulk() -> void:
	var body: Hero = _embodied("Body")
	var target: Hero = _add_hero("Target")
	assert_true(GameSession.is_hero_protected(body))
	assert_false(GameSession.sacrifice_hero(body, target, BALANCE))
	assert_true(GameSession.roster.has(body))
	var plan: Dictionary = GameSession.preview_bulk_sacrifice([body.instance_id], target.instance_id, 0)
	assert_true((plan["entries"] as Array).is_empty())
	assert_eq((plan["excluded"] as Array)[0]["reason"], "town body")
	# The body can still receive: only giving it up is refused.
	var fodder: Hero = _add_hero("Fodder")
	assert_true(GameSession.sacrifice_hero(fodder, body, BALANCE))


func test_the_body_can_still_be_geared_and_ranked_up() -> void:
	var body: Hero = _embodied("Body")
	body.rank = 0
	assert_false(GameSession.is_hero_busy(body), "the body is protected, not busy")
	var ring := Item.new(&"ring", 0)
	GameSession.add_item(ring)
	GameSession.equip_item(body, ring)
	assert_true(body.equipped.values().has(ring))
	GameSession.essence = 1000000
	var rank: int = body.rank
	assert_true(GameSession.rank_up_hero(body, BALANCE))
	assert_eq(body.rank, rank + 1)


func test_the_body_resets_when_it_leaves_the_roster() -> void:
	var body: Hero = _embodied("Doomed")
	GameSession.kill_hero(body, &"verdant_outskirts", BALANCE)
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY)


func test_a_stale_away_or_malformed_body_loads_as_none() -> void:
	var hero: Hero = _add_hero("Walker")
	var state: Dictionary = GameSession.to_dict()
	state["embodied_hero_id"] = hero.instance_id
	GameSession.from_dict(state)
	assert_eq(GameSession.embodied_hero_id, hero.instance_id, "a valid body loads")
	for bad: Variant in ["gone", 7, null]:
		state["embodied_hero_id"] = bad
		GameSession.from_dict(state)
		assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY, "%s loads as none" % bad)
	assert_ne(GameSession.dispatch_expedition([hero.instance_id], "verdant_outskirts", 1, "Out"), "", GameSession.last_action_error)
	state = GameSession.to_dict()
	state["embodied_hero_id"] = hero.instance_id
	GameSession.from_dict(state)
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY, "an away hero loads as none")
	assert_push_error_count(0)


func test_a_body_takes_the_camera_and_stepping_out_gives_it_back() -> void:
	var world: Array = _town_world()
	var town: TownView = world[0]
	var overview: Camera3D = world[1]
	assert_eq(town.get_viewport().get_camera_3d(), overview)
	town.embody(_add_hero("Walker"))
	assert_not_null(town.body)
	assert_eq(town.get_viewport().get_camera_3d(), town.body.camera, "the follow camera shows")
	assert_eq(town.body.global_position, town.to_global(TownView.BODY_SPAWN))
	town.embody(null)
	assert_null(town.body)
	assert_eq(town.get_viewport().get_camera_3d(), overview, "the overview is back")


func test_wasd_walks_away_from_the_camera_and_animates() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	var body: TownHero = town.body
	var start: Vector3 = body.global_position
	_set_key(KEY_W, true)
	await _step(20)
	assert_lt(body.global_position.z, start.z - 1.0, "W walks away from the camera")
	assert_almost_eq(body.global_position.x, start.x, 0.01)
	assert_eq(_clip(body), "Walking_A")
	_set_key(KEY_W, false)
	await _step(1)
	assert_eq(_clip(body), "Idle_A")
	body.controls_enabled = false
	_set_key(KEY_D, true)
	var stopped: Vector3 = body.global_position
	await _step(20)
	assert_eq(body.global_position, stopped, "no walking behind a panel")


func test_the_wheel_zooms_the_follow_camera_within_bounds() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	var body: TownHero = town.body
	var near: float = body.camera.position.length()
	for _tick: int in 50:
		body.set_zoom(body.zoom + TownHero.ZOOM_STEP)
	assert_eq(body.zoom, TownHero.ZOOM_MAX)
	assert_gt(body.camera.position.length(), near)


func test_a_far_click_walks_the_body_there_before_naming_the_building() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body: TownHero = town.body
	var forge: Node3D = town.get_node("Forge") as Node3D
	watch_signals(town)
	town._unhandled_input(_left_click(body.camera.unproject_position(forge.global_position)))
	assert_signal_not_emitted(town, "building_selected", "nothing opens at the click")
	assert_true(body.is_walking())
	await _step_until_arrived(body)
	assert_signal_emitted_with_parameters(town, "building_selected", [&"Forge"])
	var flat := Vector2(forge.global_position.x - body.global_position.x, forge.global_position.z - body.global_position.z)
	assert_lte(flat.length(), TownView.ARRIVE_RADIUS + 0.1, "it stands at the Forge")


func test_a_blocked_walk_still_arrives_instead_of_hanging() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	await get_tree().physics_frame
	var body: TownHero = town.body
	watch_signals(body)
	# Radius 0 at a building's centre can never be reached: the body stops against its wall.
	body.walk_to((town.get_node("TrainingHall") as Node3D).global_position, 0.0, &"TrainingHall")
	await _step_until_arrived(body)
	assert_signal_emitted_with_parameters(body, "arrived", [&"TrainingHall"])
	assert_gt(body.global_position.z, 1.5, "it never walked through the wall")


func test_walk_as_this_hero_embodies_it_and_step_out_returns_the_overview() -> void:
	var hero: Hero = _add_hero("Walker")
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var walk: Button = hub.get_node("%WalkAsHero") as Button
	var step_out: Button = hub.get_node("%StepOut") as Button
	assert_false(step_out.visible, "no body, nothing to step out of")
	hub._open(&"Forge")
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	assert_false(walk.disabled)
	walk.pressed.emit()
	assert_eq(GameSession.embodied_hero_id, hero.instance_id)
	assert_false((hub.get_node("%ArmoryView") as Control).visible, "the building closes so the town shows")
	assert_not_null(town.body)
	assert_true(step_out.visible)
	step_out.pressed.emit()
	assert_eq(GameSession.embodied_hero_id, GameSession.NO_BODY)
	assert_null(town.body)
	assert_eq(hub.get_viewport().get_camera_3d(), hub.get_node("Camera3D"))


func test_with_a_body_number_keys_open_at_once_and_a_click_opens_on_arrival() -> void:
	var hero: Hero = _add_hero("Walker")
	assert_true(GameSession.embody_hero(hero.instance_id))
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var armory: Control = hub.get_node("%ArmoryView") as Control
	assert_not_null(town.body, "a saved body walks from the start")
	await get_tree().physics_frame
	await get_tree().physics_frame
	town._unhandled_input(_left_click(town.body.camera.unproject_position((town.get_node("Forge") as Node3D).global_position)))
	assert_false(armory.visible, "the Forge waits for the hero")
	await _step_until_arrived(town.body)
	assert_true(armory.visible, "the Forge opens on arrival")
	assert_false(town.body.controls_enabled, "the body stands still behind the panel")
	(hub.get_node("%ClosePanel") as Button).pressed.emit()
	assert_true(town.body.controls_enabled)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.physical_keycode = KEY_2
	key.pressed = true
	hub.get_viewport().push_input(key)
	assert_true(armory.visible, "key 2 opens the Forge with no walk")
	assert_false(town.body.is_walking())


func test_a_blocked_load_freezes_the_body() -> void:
	var hero: Hero = _add_hero("Walker")
	var other: Hero = _add_hero("Other")
	assert_true(GameSession.embody_hero(hero.instance_id))
	SaveService.load_blocked = true
	SaveService.load_block_reason = "The save is from a newer version."
	assert_false(GameSession.embody_hero(other.instance_id))
	assert_eq(GameSession.last_action_error, "The save is from a newer version.")
	GameSession.step_out()
	assert_eq(GameSession.embodied_hero_id, hero.instance_id, "step out is refused too")


func test_a_building_click_counts_for_nothing_while_input_is_off() -> void:
	var world: Array = _town_world()
	var town: TownView = world[0]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var forge: Vector3 = (town.get_node("Forge") as Node3D).global_position
	town.input_enabled = false
	watch_signals(town)
	town._unhandled_input(_left_click((world[1] as Camera3D).unproject_position(forge)))
	assert_signal_not_emitted(town, "building_selected", "no body: nothing opens")
	town.embody(_add_hero("Walker"))
	await get_tree().physics_frame
	town._unhandled_input(_left_click(town.body.camera.unproject_position(forge)))
	assert_false(town.body.is_walking(), "a body: no walk either")
	assert_signal_not_emitted(town, "building_selected")


func test_the_body_stays_on_the_ground() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	var body: TownHero = town.body
	var edge: float = TownView.walk_bounds().end.x
	body.global_position = town.to_global(Vector3(edge - 0.5, 0.0, 5.0))
	_set_key(KEY_D, true)
	await _step(30)
	assert_almost_eq(body.global_position.x, town.to_global(Vector3.RIGHT * edge).x, 0.001, "held at the edge")


func test_the_body_reaches_the_farthest_hex_in_each_direction() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	var body: TownHero = town.body
	var radius: int = preload("res://balance.tres").town_map_radius
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var hex: Vector2i = step * radius
		assert_eq(TownRules.ring_distance(hex), radius, "a map-edge hex")
		# Start one hex short, toward the centre, and click-walk out to it.
		var centre: Vector3 = town.to_global(TownRules.hex_to_world(hex))
		var inside: Vector3 = town.to_global(TownRules.hex_to_world(step * (radius - 1)))
		body.global_position = inside
		body.walk_to(centre, 0.1, &"Edge")
		await _step_until_arrived(body)
		assert_almost_eq(Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(centre.x, centre.z)), 0.0, 0.2, "reached hex %s" % hex)


func test_a_real_wheel_event_zooms_the_follow_camera() -> void:
	var town: TownView = _town_world()[0]
	town.embody(_add_hero("Walker"))
	var at: Vector2 = _free_point(town.get_viewport())
	assert_ne(at, Vector2(-1, -1), "a point no GUI covers")
	for pressed: bool in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.position = at
		wheel.global_position = at
		wheel.pressed = pressed
		town.get_viewport().push_input(wheel, true)
	assert_almost_eq(town.body.zoom, 1.0 + TownHero.ZOOM_STEP, 0.0001)
	town.body.controls_enabled = false
	var off := InputEventMouseButton.new()
	off.button_index = MOUSE_BUTTON_WHEEL_DOWN
	off.position = at
	off.pressed = true
	town.get_viewport().push_input(off, true)
	assert_almost_eq(town.body.zoom, 1.0 + TownHero.ZOOM_STEP, 0.0001, "no zoom behind a panel")


func test_arrows_steer_the_body_not_the_building_list_focus() -> void:
	assert_true(GameSession.embody_hero(_add_hero("Walker").instance_id))
	var hub: Node3D = _instantiate_hub()
	var forge: Button = hub.get_node("%ForgeButton") as Button
	forge.grab_focus()
	_push_arrow(hub, KEY_RIGHT)
	assert_eq(hub.get_viewport().gui_get_focus_owner(), forge, "walking: the arrow is the body's")
	hub._open(&"Forge")
	_push_arrow(hub, KEY_RIGHT)
	assert_ne(hub.get_viewport().gui_get_focus_owner(), forge, "in a building the arrows move focus as before")


func test_a_team_holding_the_body_is_not_ready_and_recovery_refuses_it_by_name() -> void:
	var body: Hero = _add_hero("Aster Body")
	var ids: Array[String] = [body.instance_id]
	var preset_id: String = GameSession.save_team_preset("", "Team", ids, "verdant_outskirts")
	var cache := LostCache.new("Lost", &"verdant_outskirts", 0)
	GameSession.lost_caches.append(cache)
	var hub: Node3D = _instantiate_hub()
	hub._open(&"Reliquary")
	var option: OptionButton = hub.get_node("%RecoveryTeamOption") as OptionButton
	assert_eq(option.item_count, 1, "a free team is offered")
	assert_true(GameSession.embody_hero(body.instance_id))
	var preset: Dictionary = GameSession.team_presets[0]
	assert_eq(hub._preset_status(preset), "In town: Aster Body")
	assert_eq(option.item_count, 0, "the body's team is no longer offered")
	# A stale picker still cannot send it: the refusal comes before the confirm dialog.
	option.add_item("Team")
	option.set_item_metadata(0, preset)
	option.select(0)
	(hub.get_node("%LostCacheList") as ItemList).select(0)
	(hub.get_node("%Recover") as Button).pressed.emit()
	assert_string_contains((hub.get_node("%Status") as Label).text, "Aster Body")
	assert_false((hub.get_node("%ConfirmDialog") as Window).visible, "no dialog for a refused team")
	var team: Array[Hero] = [body]
	hub._do_recover(cache, team)
	assert_eq((hub.get_node("%Status") as Label).text, "Aster Body is your body in town. Step out first.")
	assert_true(GameSession.lost_caches.has(cache))
	assert_eq(preset_id, str(preset["id"]))


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


func _embodied(hero_name: String) -> Hero:
	var hero: Hero = _add_hero(hero_name)
	assert_true(GameSession.embody_hero(hero.instance_id))
	return hero


## The town scene with its own overview camera, as hub.tscn has it: [TownView, Camera3D].
func _town_world() -> Array:
	var world := Node3D.new()
	var overview := Camera3D.new()
	overview.transform = Transform3D(Basis.from_euler(Vector3(-PI / 6.0, 0.0, 0.0)), Vector3(0, 9, 15))
	world.add_child(overview)
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	world.add_child(town)
	town.show_buildings(GameSession.town_buildings)
	add_child_autofree(world)
	overview.make_current()
	return [town, overview]


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


## Real physics ticks: move_and_slide called outside one moves by the frame delta, not the tick.
func _step(ticks: int) -> void:
	for _tick: int in ticks:
		await get_tree().physics_frame


func _step_until_arrived(body: TownHero) -> void:
	for _tick: int in 600:
		if not body.is_walking():
			return
		await get_tree().physics_frame
	fail_test("the walk never ended")


func _left_click(at: Vector2) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = true
	return click


## A viewport point no GUI control covers (GUT's own output panel eats input where it sits).
func _free_point(viewport: Viewport) -> Vector2:
	var size: Vector2 = viewport.get_visible_rect().size
	for y: int in range(40, int(size.y), 40):
		for x: int in range(40, int(size.x), 40):
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(x, y)
			motion.global_position = motion.position
			viewport.push_input(motion, true)
			if viewport.gui_get_hovered_control() == null:
				return motion.position
	return Vector2(-1, -1)


func _push_arrow(hub: Node3D, key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		hub.get_viewport().push_input(event)


func _set_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_keys() -> void:
	for key: Key in TownHero.MOVE_KEYS:
		if Input.is_physical_key_pressed(key):
			_set_key(key, false)


func _clip(body: TownHero) -> String:
	return (body.find_children("AnimationPlayer", "AnimationPlayer", true, false)[0] as AnimationPlayer).current_animation
