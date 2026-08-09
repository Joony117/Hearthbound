extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")

var _requested_scene: String = ""


func before_each() -> void:
	GameSession.from_dict({"roster": []})
	_requested_scene = ""


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"attack"]:
		Input.action_release(action)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	assert_not_null(arena.get_node_or_null("HeroCapsule/AttackHitbox"))
	assert_not_null(arena.get_node_or_null("EnemyCapsule"))
	assert_not_null(arena.get_node_or_null("ArenaBounds/LeftWall"))
	var spring_arm := arena.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	assert_not_null(spring_arm)
	assert_almost_eq(spring_arm.spring_length, BALANCE.arena_camera_spring_length, 0.001)
	var camera := arena.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	assert_not_null(camera)
	assert_almost_eq(camera.position.x, 0.5, 0.001)
	assert_not_null(arena.get_node_or_null("Sun"))
	assert_eq(GameSession.to_dict(), profile_before)


func test_arena_movement_actions_use_physical_wasd_keys() -> void:
	var expected_keys: Dictionary[StringName, Key] = {
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"sprint": KEY_SHIFT,
	}

	for action: StringName in expected_keys:
		assert_true(InputMap.has_action(action))
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_eq(events.size(), 1)
		var key_event := events[0] as InputEventKey
		assert_not_null(key_event)
		assert_eq(key_event.physical_keycode, expected_keys[action])


func test_arena_attack_uses_left_mouse_and_authored_timeline() -> void:
	assert_true(InputMap.has_action(&"attack"))
	var events: Array[InputEvent] = InputMap.action_get_events(&"attack")
	assert_eq(events.size(), 1)
	var mouse_event := events[0] as InputEventMouseButton
	assert_not_null(mouse_event)
	assert_eq(mouse_event.button_index, MOUSE_BUTTON_LEFT)
	assert_eq(BALANCE.arena_light_attack_startup, 0.12)
	assert_eq(BALANCE.arena_light_attack_active, 0.10)
	assert_eq(BALANCE.arena_light_attack_recovery, 0.22)
	assert_eq(BALANCE.arena_light_attack_displacement, 2.0)
	assert_eq(BALANCE.arena_light_attack_reach, 1.5)
	assert_eq(BALANCE.arena_light_attack_hit_stop, 0.04)


func test_arena_attack_uses_character_facing_and_ignores_reentry_during_recovery() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var camera_pivot := arena.get_node("CameraPivot") as Node3D
	hero_capsule.rotation.y = PI * 0.5
	enemy_capsule.position = Vector3(8.0, 1.25, 0.0)
	var attack_direction: Vector3 = -hero_capsule.global_basis.z.normalized()
	var camera_forward: Vector3 = -camera_pivot.global_basis.z.normalized()
	var start_position: Vector3 = hero_capsule.global_position
	assert_lt(absf(attack_direction.dot(camera_forward)), 0.01)

	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(attack_event)
	await wait_physics_frames(15)
	arena._unhandled_input(attack_event)
	await wait_physics_frames(20)

	var displacement: Vector3 = hero_capsule.global_position - start_position
	assert_almost_eq(displacement.dot(attack_direction), BALANCE.arena_light_attack_displacement, 0.05)
	assert_almost_eq(displacement.dot(camera_forward), 0.0, 0.05)


func test_arena_attack_hitbox_defeats_target_once_after_hit_stop() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var attack_hitbox := arena.get_node("HeroCapsule/AttackHitbox") as Area3D
	assert_true(attack_hitbox.body_entered.is_connected(Callable(arena, "_on_attack_hitbox_body_entered")))
	watch_signals(arena)

	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(attack_event)
	var saw_active: bool = false
	var saw_contact: bool = false
	for _frame: int in range(20):
		await wait_physics_frames(1)
		if attack_hitbox.monitoring:
			saw_active = true
		elif saw_active:
			saw_contact = true
			assert_true(is_instance_valid(enemy_capsule))
			break
	assert_true(saw_contact)
	await wait_physics_frames(35)

	assert_signal_emit_count(arena, "enemy_defeated", 1)
	assert_false(is_instance_valid(enemy_capsule))


func test_arena_movement_uses_authored_kinematics_and_normalizes_diagonal() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	assert_eq(BALANCE.arena_move_speed, 5.8)
	assert_eq(BALANCE.arena_sprint_speed, 8.0)
	assert_eq(BALANCE.arena_acceleration, 42.0)
	assert_eq(BALANCE.arena_deceleration, 65.0)
	assert_eq(BALANCE.arena_turn_speed_degrees, 1200.0)

	Input.action_press(&"move_right")
	arena._physics_process(0.1)
	assert_almost_eq(hero_capsule.velocity.x, 4.2, 0.001)
	arena._physics_process(0.1)
	assert_almost_eq(hero_capsule.velocity.x, BALANCE.arena_move_speed, 0.001)
	assert_almost_eq(hero_capsule.velocity.z, 0.0, 0.001)

	Input.action_press(&"move_forward")
	arena._physics_process(0.2)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_move_speed, 0.001)
	assert_lt(hero_capsule.velocity.z, 0.0)

	Input.action_press(&"sprint")
	arena._physics_process(0.1)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_sprint_speed, 0.001)

	Input.action_release(&"move_right")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	arena._physics_process(0.1)
	assert_gt(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), 0.0)
	arena._physics_process(0.1)
	assert_eq(hero_capsule.velocity, Vector3.ZERO)


func test_arena_mouse_orbit_makes_movement_camera_relative_and_turns_capsule() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var camera_pivot := arena.get_node("CameraPivot") as Node3D

	var mouse_event := InputEventMouseMotion.new()
	mouse_event.screen_relative = Vector2(PI * 0.5 / BALANCE.arena_mouse_sensitivity, 0.0)
	arena._unhandled_input(mouse_event)
	assert_almost_eq(camera_pivot.rotation.y, -PI * 0.5, 0.001)

	Input.action_press(&"move_forward")
	arena._physics_process(0.2)
	var facing_direction := -hero_capsule.global_basis.z.normalized()

	assert_gt(hero_capsule.velocity.x, 0.0)
	assert_almost_eq(hero_capsule.velocity.z, 0.0, 0.001)
	assert_gt(facing_direction.x, 0.99)
	assert_almost_eq(facing_direction.y, 0.0, 0.001)


func test_arena_mouse_pitch_uses_authored_clamps() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var camera_pivot := arena.get_node("CameraPivot") as Node3D
	var mouse_event := InputEventMouseMotion.new()

	mouse_event.screen_relative = Vector2(0.0, 10000.0)
	arena._unhandled_input(mouse_event)
	assert_almost_eq(camera_pivot.rotation.x, -deg_to_rad(BALANCE.arena_camera_pitch_down_degrees), 0.001)

	mouse_event.screen_relative = Vector2(0.0, -10000.0)
	arena._unhandled_input(mouse_event)
	assert_almost_eq(camera_pivot.rotation.x, deg_to_rad(BALANCE.arena_camera_pitch_up_degrees), 0.001)


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
