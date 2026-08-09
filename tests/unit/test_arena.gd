extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")

var _requested_scene: String = ""


func before_each() -> void:
	GameSession.from_dict({"roster": []})
	_requested_scene = ""


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)


func test_arena_loads_native_graybox_without_mutating_profile() -> void:
	var hero := Hero.new("Keeper", 0)
	hero.def_id = &"knight"
	GameSession.from_dict({"roster": [hero.to_dict()]})
	var profile_before: Dictionary = GameSession.to_dict()
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	assert_not_null(arena_scene)
	var arena: Node3D = arena_scene.instantiate() as Node3D
	add_child_autofree(arena)

	assert_not_null(arena.get_node_or_null("Floor"))
	var hero_capsule := arena.get_node_or_null("HeroCapsule") as CharacterBody3D
	assert_not_null(hero_capsule)
	assert_not_null(arena.get_node_or_null("HeroCapsule/CollisionShape3D"))
	assert_not_null(arena.get_node_or_null("HeroCapsule/FacingMarker"))
	assert_not_null(arena.get_node_or_null("ArenaBounds/LeftWall"))
	assert_not_null(arena.get_node_or_null("Camera3D"))
	assert_not_null(arena.get_node_or_null("Sun"))
	assert_eq(GameSession.to_dict(), profile_before)


func test_arena_movement_actions_use_physical_wasd_keys() -> void:
	var expected_keys: Dictionary[StringName, Key] = {
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
	}

	for action: StringName in expected_keys:
		assert_true(InputMap.has_action(action))
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_eq(events.size(), 1)
		var key_event := events[0] as InputEventKey
		assert_not_null(key_event)
		assert_eq(key_event.physical_keycode, expected_keys[action])


func test_arena_movement_uses_authored_speed_and_normalizes_diagonal() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	assert_eq(BALANCE.arena_move_speed, 6.0)

	Input.action_press(&"move_right")
	arena._physics_process(0.0)
	assert_almost_eq(hero_capsule.velocity.x, BALANCE.arena_move_speed, 0.001)
	assert_almost_eq(hero_capsule.velocity.z, 0.0, 0.001)

	Input.action_press(&"move_forward")
	arena._physics_process(0.0)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_move_speed, 0.001)
	assert_lt(hero_capsule.velocity.z, 0.0)

	Input.action_release(&"move_right")
	Input.action_release(&"move_forward")
	arena._physics_process(0.0)
	assert_eq(hero_capsule.velocity, Vector3.ZERO)


func test_arena_mouse_aim_turns_capsule_without_pitching() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D

	var mouse_event := InputEventMouseMotion.new()
	mouse_event.position = Vector2(1000.0, 360.0)
	arena._unhandled_input(mouse_event)
	arena._physics_process(0.0)
	var facing_direction := -hero_capsule.global_basis.z.normalized()

	assert_gt(facing_direction.x, 0.0)
	assert_almost_eq(facing_direction.y, 0.0, 0.001)


func test_hub_enter_arena_button_connection_targets_handler() -> void:
	var hub_scene: PackedScene = load(SceneRouter.HUB) as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var button: Button = hub.get_node("UI/Root/Bottom/Buttons/EnterArena") as Button
	var connections: Array = button.pressed.get_connections()

	assert_eq(connections.size(), 1)
	var connection: Dictionary = connections[0]
	var callback: Callable = connection["callable"]
	assert_eq(callback.get_object(), hub)
	assert_eq(callback.get_method(), &"_on_enter_arena_pressed")


func test_arena_cancel_handler_requests_hub() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var router: Callable = SceneRouter.go_to
	assert_true(arena.scene_change_requested.is_connected(router))
	arena.scene_change_requested.disconnect(router)
	arena.scene_change_requested.connect(_capture_scene_request)
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	var other_event := InputEventAction.new()
	other_event.action = &"ui_accept"
	other_event.pressed = true

	arena._unhandled_input(other_event)
	assert_eq(_requested_scene, "")
	arena._unhandled_input(cancel_event)
	assert_eq(_requested_scene, SceneRouter.HUB)


func _capture_scene_request(scene_path: String) -> void:
	_requested_scene = scene_path
