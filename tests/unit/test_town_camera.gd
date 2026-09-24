extends GutTest

# ig-6m2.8.1: the overview camera pans and zooms over the whole map, clamped; the grass is tinted on
# the ground only; the Lumbermill's label clears its crane.

const EXTENT: float = 48.0

## Where the last held right-drag move ended, for the next one's relative.
var _last_move: Vector2


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)


func test_the_extent_is_the_map_radius_in_metres() -> void:
	assert_almost_eq(preload("res://balance.tres").town_map_radius * TownRules.HEX_SIZE * sqrt(3.0), EXTENT, 0.01)


func test_a_pan_far_past_each_edge_stops_the_focus_on_the_map_circle() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	var height: float = camera.global_position.y
	for offset: Vector3 in [Vector3(1000, 0, 0), Vector3(-1000, 0, 0), Vector3(0, 0, 1000), Vector3(0, 0, -1000)]:
		town.pan_overview(offset)
		var focus: Vector3 = _focus(camera)
		assert_almost_eq(Vector2(focus.x, focus.z).length(), EXTENT, 0.01, str(offset))
		assert_gt(focus.normalized().dot(offset.normalized()), 0.99, "it stops on the side it went")
		assert_eq(camera.global_position.y, height, "a pan keeps the height")


func test_zoom_stops_at_both_heights_and_keeps_the_pitch_and_the_focus() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	var basis: Basis = camera.global_basis
	var focus: Vector3 = _focus(camera)
	town.zoom_overview(1)
	assert_lt(camera.global_position.y, 9.0, "positive zooms in")
	town.zoom_overview(100)
	assert_almost_eq(camera.global_position.y, TownView.OVERVIEW_HEIGHT_MIN, 0.001)
	town.zoom_overview(-100)
	assert_almost_eq(camera.global_position.y, TownView.OVERVIEW_HEIGHT_MAX, 0.001)
	assert_eq(camera.global_basis, basis, "the pitch never changes")
	assert_almost_eq(_focus(camera).distance_to(focus), 0.0, 0.01, "a zoom keeps the focus")


func test_the_wheel_and_a_right_drag_move_the_overview_camera() -> void:
	var hub: Node3D = _instantiate_hub()
	var camera: Camera3D = _camera(hub)
	var at: Vector2 = _reachable_point(hub)
	assert_ne(at, Vector2(-1, -1), "a point over the town")
	var height: float = camera.global_position.y
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_UP)
	assert_lt(camera.global_position.y, height, "the wheel zooms in")
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_DOWN)
	assert_gt(camera.global_position.y, height, "and out")
	var town: TownView = hub.get_node("%Town") as TownView
	var grabbed: Variant = town.ground_point(at)
	_drag(hub, at, at + Vector2(40, 30))
	assert_almost_eq((town.ground_point(at + Vector2(40, 30)) as Vector3).distance_to(grabbed as Vector3), 0.0, 0.01, "the ground stays under the cursor")
	town.placing = TownRules.HOUSE
	height = camera.global_position.y
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_UP)
	assert_lt(camera.global_position.y, height, "placing zooms too")


func test_a_wheel_over_a_control_leaves_the_camera() -> void:
	var hub: Node3D = _instantiate_hub()
	var camera: Camera3D = _camera(hub)
	var at: Vector2 = (hub.get_node("%ForgeButton") as Button).get_global_rect().get_center()
	assert_false(_reachable(hub, at))
	assert_true(hub.is_ancestor_of(hub.get_viewport().gui_get_hovered_control()), "the pointer is on a hub control")
	var start: Transform3D = camera.global_transform
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_UP)
	assert_eq(camera.global_transform, start)


## A PASS gap in the building bar lets a right press through to the town, but it is still UI.
func test_a_right_drag_that_starts_on_the_ui_leaves_the_camera() -> void:
	var hub: Node3D = _instantiate_hub()
	var camera: Camera3D = _camera(hub)
	var gap: Vector2 = _pass_gap(hub)
	assert_ne(gap, Vector2(-1, -1), "a PASS gap in the hub UI")
	var at: Vector2 = _reachable_point(hub)
	var start: Transform3D = camera.global_transform
	_right(hub, gap, true)
	_last_move = gap
	for to: Vector2 in [at, at + Vector2(40, 30)]:
		_move_held(hub, to, to - _last_move)
	_right(hub, at + Vector2(40, 30), false)
	assert_eq(camera.global_transform, start, "a drag from the UI onto the town grabs nothing")
	_drag(hub, at, at + Vector2(40, 30))
	assert_ne(camera.global_transform, start, "the same drag from the town does")
	var town: TownView = hub.get_node("%Town") as TownView
	for interrupt: Callable in [func() -> void: town.input_enabled = false; town.input_enabled = true, func() -> void: town.embody(_add_hero("Mira")); town.embody(null)]:
		_right(hub, at, true)
		interrupt.call()
		start = camera.global_transform
		_last_move = at
		_move_held(hub, at + Vector2(40, 30), Vector2(40, 30))
		_right(hub, at + Vector2(40, 30), false)
		assert_eq(camera.global_transform, start, "a menu or a body in between drops the grab")


func test_the_keys_pan_away_from_the_camera_and_arrows_leave_the_focus() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	var start: Vector3 = camera.global_position
	_hold(KEY_W, true)
	town._process(0.5)
	_hold(KEY_W, false)
	assert_almost_eq(camera.global_position, start + Vector3(0, 0, -10), Vector3.ONE * 0.01, "W: 20 m/s at 9 m, away from the camera")
	_hold(KEY_LEFT, true)
	town._process(0.5)
	_hold(KEY_LEFT, false)
	assert_almost_eq(camera.global_position, start + Vector3(-10, 0, -10), Vector3.ONE * 0.01, "an arrow pans too")
	town.zoom_overview(-100)
	var high: Vector3 = camera.global_position
	_hold(KEY_W, true)
	town._process(0.5)
	_hold(KEY_W, false)
	assert_almost_eq(camera.global_position, high + Vector3(0, 0, -30), Vector3.ONE * 0.01, "three times as fast at 27 m")
	var button: Button = hub.get_node("%ForgeButton") as Button
	button.grab_focus()
	for key: Key in [KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_LEFT]:
		_push_key(hub, key)
	assert_eq(hub.get_viewport().gui_get_focus_owner(), button, "the arrows pan, not move the focus")
	town.input_enabled = false
	for key: Key in [KEY_DOWN, KEY_RIGHT]:
		_push_key(hub, key)
	assert_ne(hub.get_viewport().gui_get_focus_owner(), button, "with a panel open they move the focus again")


func test_with_a_body_or_input_off_the_overview_camera_stays() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	var at: Vector2 = _reachable_point(hub)
	var start: Transform3D = camera.global_transform
	town.input_enabled = false
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_UP)
	_drag(hub, at, at + Vector2(40, 30))
	assert_eq(camera.global_transform, start, "input off")
	town.input_enabled = true
	town.embody(_add_hero("Mira"))
	_wheel(hub, at, MOUSE_BUTTON_WHEEL_UP)
	_drag(hub, at, at + Vector2(40, 30))
	var follow: Transform3D = town.body.camera.global_transform
	town.pan_overview(Vector3(10, 0, 0))
	town.zoom_overview(3)
	town.zoom_overview(-3)
	assert_eq(camera.global_transform, start, "a body")
	assert_eq(town.body.camera.global_transform, follow, "nor the body's own camera")


func test_stepping_out_brings_back_the_panned_overview() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	town.pan_overview(Vector3(10, 0, 5))
	town.zoom_overview(2)
	var before: Transform3D = camera.global_transform
	town.embody(_add_hero("Mira"))
	assert_ne(hub.get_viewport().get_camera_3d(), camera)
	town.embody(null)
	assert_eq(hub.get_viewport().get_camera_3d(), camera)
	assert_eq(camera.global_transform, before)


func test_the_grass_is_tinted_and_nothing_else() -> void:
	var hub: Node3D = _instantiate_hub()
	var ground := hub.get_node("%Town/HexGround") as MultiMeshInstance3D
	var grass := ground.material_override as StandardMaterial3D
	assert_not_null(grass)
	assert_eq(grass.albedo_color, TownView.GRASS_TINT)
	var tile_material := ground.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	assert_ne(tile_material, grass, "a copy, not the shared tile material")
	assert_eq(tile_material.albedo_color, Color.WHITE, "the tile's own material is untouched")
	var house: Node3D = TownView.SCENES[TownRules.HOUSE].instantiate() as Node3D
	add_child_autofree(house)
	for mesh: MeshInstance3D in house.get_node("Model").find_children("*", "MeshInstance3D"):
		assert_null(mesh.material_override)
		assert_eq((mesh.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color, Color.WHITE, "the House is untinted")


func test_the_lumbermill_label_clears_its_crane() -> void:
	var mill: Node3D = TownView.SCENES[TownRules.LUMBERMILL].instantiate() as Node3D
	add_child_autofree(mill)
	assert_almost_eq((mill.get_node("Label") as Label3D).position.y, 5.6, 0.001)


func test_a_building_still_picks_after_a_pan_and_at_both_zoom_bounds() -> void:
	var hub: Node3D = _instantiate_hub()
	var town: TownView = hub.get_node("%Town") as TownView
	var camera: Camera3D = _camera(hub)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var forge: Node3D = town.get_node("Forge") as Node3D
	var focus: Vector3 = _focus(camera)
	town.pan_overview(forge.global_position - focus)
	for steps: int in [0, 100, -100]:
		town.zoom_overview(steps)
		var at: Vector2 = camera.unproject_position(forge.global_position + Vector3(0.0, 1.5, 0.0))
		assert_eq(town.building_at(at), &"Forge", "zoom %d" % steps)


## Where the overview camera looks at the ground (the town sits at the origin in hub.tscn).
func _focus(camera: Camera3D) -> Vector3:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.global_position, -camera.global_basis.z) as Vector3


func _camera(hub: Node3D) -> Camera3D:
	var camera: Camera3D = hub.get_node("Camera3D") as Camera3D
	assert_eq(hub.get_viewport().get_camera_3d(), camera)
	return camera


func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _push_key(hub: Node3D, key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		hub.get_viewport().push_input(event)


func _wheel(hub: Node3D, at: Vector2, button: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = button
		wheel.position = at
		wheel.global_position = at
		wheel.pressed = pressed
		hub.get_viewport().push_input(wheel, true)


## A right press at from, one move to to, and the release there.
func _drag(hub: Node3D, from: Vector2, to: Vector2) -> void:
	_right(hub, from, true)
	_move_held(hub, to, to - from)
	_right(hub, to, false)



func _move_held(hub: Node3D, to: Vector2, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	hub.get_viewport().push_input(motion, true)
	_last_move = to


func _right(hub: Node3D, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	hub.get_viewport().push_input(event, true)


## A screen point over bare town, under no control (the hub's or GUT's own output panel, bd memory:
## headless GUT click tests), on the ground at every zoom, and so is its drag target.
func _reachable_point(hub: Node3D) -> Vector2:
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	for y: int in range(0, int(size.y) - 40, 16):
		for x: int in range(0, int(size.x) - 50, 16):
			if _on_ground(hub, Vector2(x, y)) and _on_ground(hub, Vector2(x + 40, y + 30)):
				return Vector2(x, y)
	return Vector2(-1, -1)


## Reachable, and in the lower half of the screen, whose rays meet the ground at every zoom.
func _on_ground(hub: Node3D, at: Vector2) -> bool:
	return at.y > hub.get_viewport().get_visible_rect().size.y * 0.5 and _reachable(hub, at)


func _reachable(hub: Node3D, at: Vector2) -> bool:
	return _hover(hub, at) == null


## The control under at after a pushed move there, or null over bare town.
func _hover(hub: Node3D, at: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	hub.get_viewport().push_input(motion, true)
	return hub.get_viewport().gui_get_hovered_control()


## A point on a hub control that passes the mouse on (a gap in a container), or (-1, -1).
func _pass_gap(hub: Node3D) -> Vector2:
	var size: Vector2 = hub.get_viewport().get_visible_rect().size
	for y: int in range(0, int(size.y), 8):
		for x: int in range(0, int(size.x), 8):
			var hovered: Control = _hover(hub, Vector2(x, y))
			if hovered != null and hub.is_ancestor_of(hovered) and hovered.mouse_filter == Control.MOUSE_FILTER_PASS:
				return Vector2(x, y)
	return Vector2(-1, -1)


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	return hero


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
