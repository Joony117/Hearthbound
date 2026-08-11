extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")

var _requested_scene: String = ""
var _combat_result: CombatResult


func before_each() -> void:
	GameSession.from_dict({"roster": []})
	SceneRouter.reset_arena_transition_state()
	_requested_scene = ""
	_combat_result = null


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"attack", &"heavy_attack", &"dodge"]:
		Input.action_release(action)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneRouter.reset_arena_transition_state()


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
	assert_not_null(arena.get_node_or_null("EnemyCapsule/EnemyAttackHitbox"))
	assert_not_null(arena.get_node_or_null("ArenaBounds/LeftWall"))
	var spring_arm := arena.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	assert_not_null(spring_arm)
	assert_almost_eq(spring_arm.spring_length, BALANCE.arena_camera_spring_length, 0.001)
	var camera := arena.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	assert_not_null(camera)
	assert_almost_eq(camera.position.x, 0.5, 0.001)
	assert_not_null(arena.get_node_or_null("Sun"))
	assert_eq(GameSession.to_dict(), profile_before)


func test_arena_capsule_overrides_render_combat_tints_without_mutating_authored_materials() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_mesh := arena.get_node("HeroCapsule/Mesh") as MeshInstance3D
	var enemy_mesh := arena.get_node("EnemyCapsule/Mesh") as MeshInstance3D
	var hero_authored_material := hero_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var enemy_authored_material := enemy_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var hero_base_color: Color = hero_authored_material.albedo_color
	var enemy_base_color: Color = enemy_authored_material.albedo_color

	assert_not_null(hero_mesh.material_override)
	assert_not_null(enemy_mesh.material_override)
	assert_ne(hero_mesh.material_override, hero_authored_material)
	assert_ne(enemy_mesh.material_override, enemy_authored_material)

	arena._enemy_attack_elapsed = 0.0
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.ENEMY_WINDUP_COLOR)
	arena._enemy_attack_elapsed = BALANCE.arena_enemy_attack_startup
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, enemy_base_color)

	arena._hit_stop_outcome = Arena.HitStopOutcome.HIT_HERO
	arena._hit_stop_remaining = BALANCE.arena_enemy_attack_hit_stop
	arena._physics_process(0.0)
	assert_eq((hero_mesh.material_override as StandardMaterial3D).albedo_color, Arena.HIT_HERO_COLOR)
	arena._hit_stop_outcome = Arena.HitStopOutcome.NONE
	arena._hit_stun_remaining = BALANCE.arena_enemy_hit_stun
	arena._physics_process(0.0)
	assert_eq((hero_mesh.material_override as StandardMaterial3D).albedo_color, Arena.HIT_HERO_COLOR)

	arena._hit_stop_outcome = Arena.HitStopOutcome.PARRY_HERO
	arena._hit_stun_remaining = 0.0
	arena._physics_process(0.0)
	assert_eq((hero_mesh.material_override as StandardMaterial3D).albedo_color, Arena.PARRY_HERO_COLOR)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.PARRY_HERO_COLOR)
	arena._hit_stop_outcome = Arena.HitStopOutcome.NONE
	arena._enemy_stagger_remaining = BALANCE.arena_parry_enemy_stagger
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.PARRY_HERO_COLOR)

	arena._enemy_stagger_remaining = 0.0
	arena._hit_stop_outcome = Arena.HitStopOutcome.DEFEAT_ENEMY
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.DEFEAT_ENEMY_COLOR)
	assert_eq(hero_authored_material.albedo_color, hero_base_color)
	assert_eq(enemy_authored_material.albedo_color, enemy_base_color)
	arena._hit_stop_outcome = Arena.HitStopOutcome.NONE
	arena._physics_process(0.0)
	assert_eq((hero_mesh.material_override as StandardMaterial3D).albedo_color, hero_base_color)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, enemy_base_color)


func test_arena_movement_actions_use_physical_wasd_keys() -> void:
	var expected_keys: Dictionary[StringName, Key] = {
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"sprint": KEY_SHIFT,
		&"dodge": KEY_SPACE,
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
	assert_eq(BALANCE.arena_light_attack_startup, 0.10)
	assert_eq(BALANCE.arena_light_attack_active, 0.10)
	assert_eq(BALANCE.arena_light_attack_recovery, 0.22)
	assert_eq(BALANCE.arena_light_attack_displacement, 2.0)
	assert_eq(BALANCE.arena_light_attack_reach, 1.5)
	assert_eq(BALANCE.arena_light_attack_hit_stop, 0.04)


func test_arena_enemy_attack_and_dodge_use_authored_values() -> void:
	assert_eq(BALANCE.arena_enemy_attack_startup, 0.55)
	assert_eq(BALANCE.arena_enemy_attack_active, 0.10)
	assert_eq(BALANCE.arena_enemy_attack_recovery, 0.45)
	assert_eq(BALANCE.arena_enemy_attack_reach, 1.6)
	assert_eq(BALANCE.arena_enemy_attack_trigger_range, 3.0)
	assert_eq(BALANCE.arena_enemy_attack_cooldown, 0.6)
	assert_eq(BALANCE.arena_enemy_turn_speed_degrees, 720.0)
	assert_eq(BALANCE.arena_enemy_attack_hit_stop, 0.06)
	assert_eq(BALANCE.arena_enemy_knockback_speed, 6.0)
	assert_eq(BALANCE.arena_enemy_hit_stun, 0.35)
	assert_eq(BALANCE.arena_enemy_hits_to_kill_hero, 3)
	assert_eq(BALANCE.arena_dodge_speed, 13.5)
	assert_eq(BALANCE.arena_dodge_duration, 0.38)
	assert_eq(BALANCE.arena_dodge_iframe_duration, 0.25)
	assert_eq(BALANCE.arena_dodge_cooldown, 0.15)
	assert_eq(BALANCE.arena_parry_startup, 0.0)
	assert_eq(BALANCE.arena_parry_active_window, 0.18)
	assert_eq(BALANCE.arena_parry_whiff_recovery, 0.35)
	assert_eq(BALANCE.arena_parry_success_recovery, 0.10)
	assert_eq(BALANCE.arena_parry_cooldown, 0.15)
	assert_eq(BALANCE.arena_parry_hit_stop, 0.08)
	assert_eq(BALANCE.arena_parry_enemy_stagger, 0.6)

	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var shape_node := arena.get_node("EnemyCapsule/EnemyAttackHitbox/CollisionShape3D") as CollisionShape3D
	var enemy_attack_shape := shape_node.shape as BoxShape3D
	assert_not_null(enemy_attack_shape)
	assert_almost_eq(enemy_attack_shape.size.z, BALANCE.arena_enemy_attack_reach, 0.001)


func test_arena_attack_captures_camera_facing_after_startup_and_ignores_reentry_during_recovery() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var camera_pivot := arena.get_node("CameraPivot") as Node3D
	enemy_capsule.position = Vector3(8.0, 1.25, 0.0)
	var mouse_event := InputEventMouseMotion.new()
	mouse_event.screen_relative = Vector2(PI * 0.5 / BALANCE.arena_mouse_sensitivity, 0.0)
	arena._unhandled_input(mouse_event)
	var camera_forward: Vector3 = -camera_pivot.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var start_position: Vector3 = hero_capsule.global_position
	arena._physics_process(0.2)
	assert_gt((-hero_capsule.global_basis.z).normalized().dot(camera_forward), 0.99)

	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(attack_event)
	await wait_physics_frames(15)
	arena._unhandled_input(attack_event)
	await wait_physics_frames(20)

	var displacement: Vector3 = hero_capsule.global_position - start_position
	assert_gt(displacement.dot(camera_forward), BALANCE.arena_light_attack_displacement * 0.9)


func test_arena_attack_hitbox_defeats_target_once_after_hit_stop() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var attack_hitbox := arena.get_node("HeroCapsule/AttackHitbox") as Area3D
	assert_true(attack_hitbox.body_entered.is_connected(Callable(arena, "_on_attack_hitbox_body_entered")))
	_make_enemy_die_to_one_clean_hit(arena)
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


func test_enemy_swing_requires_range_and_locks_facing_during_active() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var enemy_hitbox := arena.get_node("EnemyCapsule/EnemyAttackHitbox") as Area3D

	var out_of_range_step: float = BALANCE.arena_enemy_attack_active * 0.5
	var out_of_range_elapsed: float = 0.0
	while out_of_range_elapsed <= BALANCE.arena_enemy_attack_startup + BALANCE.arena_enemy_attack_active:
		arena._physics_process(out_of_range_step)
		assert_false(enemy_hitbox.monitoring)
		out_of_range_elapsed += out_of_range_step
	enemy_capsule.position = Vector3(0.0, 1.25, -2.0)
	arena._physics_process(0.0)
	arena._physics_process(BALANCE.arena_enemy_attack_startup - 0.01)
	arena._physics_process(0.01)
	assert_true(enemy_hitbox.monitoring)
	var facing_before: Vector3 = -enemy_capsule.global_basis.z.normalized()
	var to_hero: Vector3 = (hero_capsule.global_position - enemy_capsule.global_position).normalized()
	assert_gt(facing_before.dot(to_hero), 0.99)

	hero_capsule.position.x = 2.0
	arena._physics_process(BALANCE.arena_enemy_attack_active * 0.5)
	var facing_after: Vector3 = -enemy_capsule.global_basis.z.normalized()
	assert_almost_eq(facing_after.dot(facing_before), 1.0, 0.001)


func test_enemy_hit_stops_then_knocks_back_and_locks_input() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var attack_hitbox := arena.get_node("HeroCapsule/AttackHitbox") as Area3D
	enemy_capsule.position = Vector3(0.0, 1.25, -2.0)

	arena._physics_process(0.0)
	arena._physics_process(BALANCE.arena_enemy_attack_startup - 0.01)
	arena._physics_process(0.01)
	await wait_physics_frames(2)
	arena._physics_process(BALANCE.arena_enemy_attack_hit_stop)
	assert_gt(hero_capsule.velocity.z, 0.0)
	var knockback_speed: float = Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length()
	assert_almost_eq(knockback_speed, BALANCE.arena_enemy_knockback_speed, 0.001)

	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	Input.action_press(&"move_right")
	arena._unhandled_input(attack_event)
	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)
	arena._physics_process(0.01)
	assert_almost_eq(hero_capsule.velocity.x, 0.0, 0.001)
	assert_gt(hero_capsule.velocity.z, 0.0)
	assert_lt(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), knockback_speed)
	assert_false(attack_hitbox.monitoring)


func test_dodge_iframes_prevent_enemy_hit() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var enemy_hitbox := arena.get_node("EnemyCapsule/EnemyAttackHitbox") as Area3D
	enemy_capsule.position = Vector3(0.0, 1.25, -2.0)
	arena._physics_process(0.0)
	arena._physics_process(BALANCE.arena_enemy_attack_startup - 0.01)

	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)
	arena._physics_process(0.01)
	await wait_physics_frames(2)
	arena._physics_process(0.01)

	assert_true(enemy_hitbox.monitoring)
	assert_gt(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_enemy_knockback_speed)


func test_dodge_cooldown_starts_when_burst_ends() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_dodge_speed, 0.001)
	arena._physics_process(BALANCE.arena_dodge_duration)
	assert_eq(hero_capsule.velocity, Vector3.ZERO)
	arena._unhandled_input(dodge_event)
	assert_eq(hero_capsule.velocity, Vector3.ZERO)
	arena._physics_process(BALANCE.arena_dodge_cooldown)
	arena._unhandled_input(dodge_event)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_dodge_speed, 0.001)


func test_dodge_cooldown_does_not_gate_parry() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)
	arena._physics_process(BALANCE.arena_dodge_duration)
	assert_almost_eq(arena._dodge_cooldown_remaining, BALANCE.arena_dodge_cooldown, 0.001)

	Input.action_release(&"move_back")
	arena._unhandled_input(dodge_event)
	assert_eq(arena._parry_elapsed, 0.0)


func test_dodge_cancels_light_attack_startup() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(attack_event)
	arena._physics_process(BALANCE.arena_light_attack_startup * 0.5)
	assert_gt(arena._attack_elapsed, 0.0)

	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)

	assert_eq(arena._attack_elapsed, -1.0)
	assert_eq(arena._dodge_elapsed, 0.0)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), BALANCE.arena_dodge_speed, 0.001)


## The cancel drops `monitoring` in the same frame, so a hit that had not already registered is
## lost outright — `SYSTEMS.md` ruling 1. The enemy assertion is what measures that: asserting the
## flag alone would still pass if the overlap had already been credited.
func test_dodge_during_active_attack_eats_the_pending_hit() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var attack_hitbox := arena.get_node("HeroCapsule/AttackHitbox") as Area3D
	watch_signals(arena)
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(attack_event)
	arena._physics_process(BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active * 0.5)
	assert_true(attack_hitbox.monitoring)

	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)

	assert_false(attack_hitbox.monitoring)
	assert_eq(arena._attack_elapsed, -1.0)
	await wait_physics_frames(35)
	assert_signal_emit_count(arena, "enemy_defeated", 0)
	assert_true(is_instance_valid(enemy_capsule))


func test_standstill_dodge_press_parries_out_of_attack_startup() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(attack_event)
	arena._physics_process(BALANCE.arena_light_attack_startup * 0.5)
	arena._unhandled_input(dodge_event)

	assert_eq(arena._parry_elapsed, 0.0)
	assert_eq(arena._attack_elapsed, -1.0)


## Ruling 4 — the cooldown is charged when the burst ends, so a cancel pays exactly what a clean
## dodge pays. No branch implements this; deleting the guard must not have bought a free dodge.
func test_cancel_started_dodge_pays_the_same_cooldown() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(attack_event)
	arena._physics_process(BALANCE.arena_light_attack_startup * 0.5)
	Input.action_press(&"move_back")
	arena._unhandled_input(dodge_event)
	arena._physics_process(BALANCE.arena_dodge_duration)

	assert_eq(arena._dodge_elapsed, -1.0)
	assert_almost_eq(arena._dodge_cooldown_remaining, BALANCE.arena_dodge_cooldown, 0.001)


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


func test_neutral_dodge_press_starts_parry_instead_of_dodge() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(dodge_event)

	assert_eq(arena._dodge_elapsed, -1.0)
	assert_eq(arena._parry_elapsed, 0.0)


func test_parry_in_window_staggers_enemy_without_knockback_or_hit_stun() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_hitbox := arena.get_node("EnemyCapsule/EnemyAttackHitbox") as Area3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	arena._unhandled_input(dodge_event)
	arena._enemy_attack_active = true
	arena._on_enemy_attack_hitbox_body_entered(hero_capsule)

	assert_eq(arena._hit_stop_outcome, Arena.HitStopOutcome.PARRY_HERO)
	arena._physics_process(BALANCE.arena_parry_hit_stop)

	assert_eq(hero_capsule.velocity, Vector3.ZERO)
	assert_eq(arena._hit_stun_remaining, 0.0)
	assert_almost_eq(arena._enemy_stagger_remaining, BALANCE.arena_parry_enemy_stagger, 0.001)
	assert_false(enemy_hitbox.monitoring)


func test_parry_after_active_window_uses_ordinary_hit_reaction() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	arena._unhandled_input(dodge_event)
	arena._physics_process(BALANCE.arena_parry_active_window)
	arena._enemy_attack_active = true
	arena._on_enemy_attack_hitbox_body_entered(hero_capsule)
	arena._physics_process(BALANCE.arena_enemy_attack_hit_stop)

	assert_gt(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), 0.0)
	assert_almost_eq(arena._hit_stun_remaining, BALANCE.arena_enemy_hit_stun, 0.001)


func test_parry_whiff_recovery_locks_actions() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(dodge_event)
	arena._physics_process(BALANCE.arena_parry_active_window + 0.01)
	arena._unhandled_input(attack_event)
	arena._unhandled_input(dodge_event)

	assert_gt(arena._parry_elapsed, BALANCE.arena_parry_active_window)
	assert_eq(arena._attack_elapsed, -1.0)
	assert_eq(arena._dodge_elapsed, -1.0)


func test_attack_cancels_successful_parry_recovery() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(dodge_event)
	arena._enemy_attack_active = true
	arena._on_enemy_attack_hitbox_body_entered(hero_capsule)
	arena._physics_process(BALANCE.arena_parry_hit_stop)
	arena._unhandled_input(attack_event)

	assert_eq(arena._parry_elapsed, -1.0)
	assert_eq(arena._attack_elapsed, 0.0)


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


func test_arena_win_returns_surviving_hero_without_mutating_profile() -> void:
	var hero := Hero.new("Winner", 0)
	hero.def_id = &"knight"
	GameSession.from_dict({"roster": [hero.to_dict()]})
	hero = GameSession.roster[0]
	var profile_before: Dictionary = GameSession.to_dict()
	var wave: Wave = Wave.from_zone(preload("res://zones/defs/verdant_outskirts.tres"), 0)
	var team: Array[Hero] = [hero]
	SceneRouter.prepare_arena(team, wave)
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var router: Callable = SceneRouter.go_to
	assert_true(arena.scene_change_requested.is_connected(router))
	arena.scene_change_requested.disconnect(router)
	arena.scene_change_requested.connect(_capture_scene_request)
	arena.combat_resolved.connect(_capture_combat_result)
	_make_enemy_die_to_one_clean_hit(arena)

	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	arena._unhandled_input(attack_event)
	for _frame: int in range(80):
		await wait_physics_frames(1)
		if _combat_result != null:
			break

	assert_not_null(_combat_result)
	assert_true(_combat_result.survivors.has(hero))
	assert_true(_combat_result.dead_heroes.is_empty())
	assert_true(_combat_result.maximum_hp.has(hero))
	assert_true(_combat_result.hp_after.has(hero))
	assert_gt(_combat_result.maximum_hp[hero], 0.0)
	assert_eq(_combat_result.hp_after[hero], _combat_result.maximum_hp[hero])
	assert_eq(GameSession.to_dict(), profile_before)
	assert_eq(_requested_scene, "")
	var return_time_remaining: float = arena._result_return_remaining
	assert_gt(return_time_remaining, 0.0)
	arena._physics_process(return_time_remaining * 0.5)
	assert_eq(_requested_scene, "")
	arena._physics_process(return_time_remaining)
	assert_eq(_requested_scene, SceneRouter.HUB)


func test_arena_loss_returns_dead_hero_without_mutating_profile() -> void:
	var hero := Hero.new("Loser", 0)
	hero.def_id = &"knight"
	GameSession.from_dict({"roster": [hero.to_dict()]})
	hero = GameSession.roster[0]
	var profile_before: Dictionary = GameSession.to_dict()
	var wave: Wave = Wave.from_zone(preload("res://zones/defs/verdant_outskirts.tres"), 0)
	var team: Array[Hero] = [hero]
	SceneRouter.prepare_arena(team, wave)
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var router: Callable = SceneRouter.go_to
	assert_true(arena.scene_change_requested.is_connected(router))
	arena.scene_change_requested.disconnect(router)
	arena.scene_change_requested.connect(_capture_scene_request)
	arena.combat_resolved.connect(_capture_combat_result)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	enemy_capsule.position = Vector3(0.0, 1.25, -2.0)

	for hit_index: int in BALANCE.arena_enemy_hits_to_kill_hero:
		var hits_before: int = arena._hits_taken
		for _frame: int in range(240):
			await wait_physics_frames(1)
			if arena._hits_taken > hits_before:
				break
		assert_eq(arena._hits_taken, hits_before + 1)
		if hit_index < BALANCE.arena_enemy_hits_to_kill_hero - 1:
			enemy_capsule.global_position = hero_capsule.global_position + Vector3(0.0, 0.0, -2.0)
			for _frame: int in range(240):
				await wait_physics_frames(1)
				if not arena._enemy_attack_hit:
					break
			assert_false(arena._enemy_attack_hit)

	assert_not_null(_combat_result)
	assert_true(_combat_result.dead_heroes.has(hero))
	assert_true(_combat_result.survivors.is_empty())
	assert_true(_combat_result.maximum_hp.has(hero))
	assert_true(_combat_result.hp_after.has(hero))
	assert_eq(_combat_result.hp_after[hero], 0.0)
	assert_eq(GameSession.to_dict(), profile_before)
	assert_eq(_requested_scene, "")
	var return_time_remaining: float = arena._result_return_remaining
	assert_gt(return_time_remaining, 0.0)
	arena._physics_process(return_time_remaining * 0.5)
	assert_eq(_requested_scene, "")
	arena._physics_process(return_time_remaining)
	assert_eq(_requested_scene, SceneRouter.HUB)


func test_arena_cancel_during_result_countdown_requests_hub_once() -> void:
	var hero := Hero.new("Countdown", 0)
	hero.def_id = &"knight"
	var wave: Wave = Wave.from_zone(preload("res://zones/defs/verdant_outskirts.tres"), 0)
	SceneRouter.prepare_arena([hero], wave)
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var router: Callable = SceneRouter.go_to
	assert_true(arena.scene_change_requested.is_connected(router))
	arena.scene_change_requested.disconnect(router)
	arena.scene_change_requested.connect(_capture_scene_request)
	watch_signals(arena)

	arena._finish_combat()
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	arena._unhandled_input(cancel_event)
	arena._physics_process(BALANCE.arena_result_return_delay)

	assert_eq(_requested_scene, SceneRouter.HUB)
	assert_signal_emit_count(arena, "scene_change_requested", 1)
	assert_signal_emit_count(arena, "combat_resolved", 1)


## The enemy's dodge and parry rolls are probabilistic, and its HP pool now takes a full five-hit
## chain to drain. Both would make any test that just wants "one swing kills it" flaky, so tests
## about the defeat path pin the pool to a single hit and hold the two reactions on cooldown. It
## does not touch the shared BALANCE resource, which would leak into every later test.
func _make_enemy_die_to_one_clean_hit(arena: Arena) -> void:
	arena._enemy_hp = 1.0
	arena._enemy_dodge_cooldown_remaining = 999.0
	arena._enemy_parry_cooldown_remaining = 999.0


func test_combo_index_scales_hit_damage_and_five_hits_drain_the_pool() -> void:
	var arena: Arena = _instantiate_arena()
	var expected_hp: float = BALANCE.arena_enemy_max_hp
	for combo_index: int in BALANCE.arena_light_attack_combo_length:
		arena._enemy_hp = expected_hp
		arena._combo_index = combo_index
		arena._attack_active = true
		arena._attack_hit = false
		# Each landed hit leaves a flinch hit-stop behind, and the hitbox refuses to register a
		# second hit while one is running. Clearing it is what makes five hits land in one call
		# stack instead of only the first.
		arena._hit_stop_remaining = 0.0
		expected_hp -= BALANCE.arena_light_attack_damage * (
			1.0 + BALANCE.arena_light_attack_combo_damage_step * float(combo_index)
		)
		arena._on_attack_hitbox_body_entered(arena.get_node("EnemyCapsule") as CharacterBody3D)
		assert_almost_eq(arena._enemy_hp, expected_hp, 0.001)
	# Escalating damage means the pool must survive four hits and die to the fifth, or the combo
	# length and the HP pool have drifted apart.
	assert_lt(expected_hp, 0.0)


func test_enemy_dodge_iframes_whiff_the_hit_and_parry_only_scales_damage() -> void:
	var arena: Arena = _instantiate_arena()
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D

	arena._enemy_state = Arena.EnemyState.DODGE
	arena._enemy_dodge_elapsed = 0.0
	arena._attack_active = true
	arena._attack_hit = false
	arena._on_attack_hitbox_body_entered(enemy_capsule)
	assert_eq(arena._enemy_hp, BALANCE.arena_enemy_max_hp)
	assert_eq(arena._hit_stop_remaining, 0.0)

	# A parry costs the enemy damage and nothing else: no hit-stun, no combo reset, no cooldown
	# charged to the player. That asymmetry is the design, not an oversight.
	arena._enemy_state = Arena.EnemyState.PARRY
	arena._enemy_parry_elapsed = 0.0
	arena._combo_index = 2
	arena._attack_active = true
	arena._attack_hit = false
	arena._hit_stop_remaining = 0.0
	arena._on_attack_hitbox_body_entered(enemy_capsule)
	var full_damage: float = BALANCE.arena_light_attack_damage * (
		1.0 + BALANCE.arena_light_attack_combo_damage_step * 2.0
	)
	var expected_hp: float = BALANCE.arena_enemy_max_hp - full_damage * (
		1.0 - BALANCE.arena_enemy_parry_damage_reduction
	)
	assert_almost_eq(arena._enemy_hp, expected_hp, 0.001)
	assert_eq(arena._hit_stun_remaining, 0.0)
	assert_eq(arena._combo_index, 2)
	assert_eq(arena._dodge_cooldown_remaining, 0.0)
	assert_eq(arena._parry_cooldown_remaining, 0.0)


func test_screen_shake_scales_off_hit_stop_and_the_toggle_switches_it_off() -> void:
	var arena: Arena = _instantiate_arena()
	arena._shake_enabled = true
	arena._start_screen_shake(BALANCE.arena_parry_hit_stop)
	var parry_magnitude: float = arena._shake_magnitude
	assert_almost_eq(
		parry_magnitude,
		BALANCE.arena_parry_hit_stop * BALANCE.arena_screen_shake_magnitude_scale,
		0.0001,
	)
	assert_gt(arena._shake_remaining, 0.0)

	# A heavier contact must shake harder, which is the whole reason it scales off hit-stop.
	arena._start_screen_shake(BALANCE.arena_enemy_hit_flinch_stop)
	assert_lt(arena._shake_magnitude, parry_magnitude)

	# Decay runs off the pivot update, and must land exactly on zero rather than drifting.
	arena._shake_remaining = 0.0
	arena._shake_enabled = false
	arena._start_screen_shake(BALANCE.arena_parry_hit_stop)
	assert_eq(arena._shake_remaining, 0.0)


func test_screen_shake_setting_round_trips_through_disk() -> void:
	var restore: bool = Settings.screen_shake_enabled()
	Settings.set_screen_shake_enabled(false)
	Settings._config = null
	assert_false(Settings.screen_shake_enabled())
	Settings.set_screen_shake_enabled(true)
	Settings._config = null
	assert_true(Settings.screen_shake_enabled())
	Settings.set_screen_shake_enabled(restore)


func test_heavy_attack_uses_right_mouse_and_finishes_a_three_hit_chain() -> void:
	assert_true(InputMap.has_action(&"heavy_attack"))
	var events: Array[InputEvent] = InputMap.action_get_events(&"heavy_attack")
	assert_eq(events.size(), 1)
	var mouse_event := events[0] as InputEventMouseButton
	assert_not_null(mouse_event)
	assert_eq(mouse_event.button_index, MOUSE_BUTTON_RIGHT)
	assert_eq(BALANCE.arena_heavy_attack_startup, 0.30)
	assert_eq(BALANCE.arena_heavy_attack_active, 0.12)
	assert_eq(BALANCE.arena_heavy_attack_recovery, 0.50)
	assert_eq(BALANCE.arena_heavy_attack_displacement, 3.0)
	assert_eq(BALANCE.arena_heavy_attack_hit_stop, 0.09)
	assert_eq(BALANCE.arena_heavy_attack_damage, 45.0)

	# The whole point of the smash is that it closes a chain the lights cannot close alone. Three
	# lights plus a smash must kill; two lights plus a smash must not. Retune any of the four
	# numbers involved and this is what catches it.
	var step: float = BALANCE.arena_light_attack_combo_damage_step
	var light: float = BALANCE.arena_light_attack_damage
	var chain_of_three: float = light * (1.0 + step * 0.0) + light * (1.0 + step) + light * (1.0 + step * 2.0)
	var chain_of_two: float = light * (1.0 + step * 0.0) + light * (1.0 + step)
	assert_gt(
		chain_of_three + BALANCE.arena_heavy_attack_damage * (1.0 + step * 3.0),
		BALANCE.arena_enemy_max_hp,
	)
	assert_lt(
		chain_of_two + BALANCE.arena_heavy_attack_damage * (1.0 + step * 2.0),
		BALANCE.arena_enemy_max_hp,
	)


func test_buffered_smash_takes_the_next_chain_step_and_ends_the_chain() -> void:
	var arena: Arena = _instantiate_arena()
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var heavy_event := InputEventAction.new()
	heavy_event.action = &"heavy_attack"
	heavy_event.pressed = true

	arena._unhandled_input(attack_event)
	assert_false(arena._attack_is_heavy)
	arena._unhandled_input(heavy_event)
	assert_true(arena._heavy_buffered)
	assert_eq(arena._combo_index, 0)

	arena._physics_process(
		BALANCE.arena_light_attack_startup
		+ BALANCE.arena_light_attack_active
		+ BALANCE.arena_light_attack_recovery
		+ 0.001
	)
	assert_true(arena._attack_is_heavy)
	assert_eq(arena._combo_index, 1)
	assert_false(arena._heavy_buffered)

	# A smash consumes no buffer and opens no combo window - it returns to neutral at step 0.
	arena._unhandled_input(attack_event)
	arena._physics_process(
		BALANCE.arena_heavy_attack_startup
		+ BALANCE.arena_heavy_attack_active
		+ BALANCE.arena_heavy_attack_recovery
		+ 0.001
	)
	assert_eq(arena._attack_elapsed, -1.0)
	assert_eq(arena._combo_index, 0)
	assert_eq(arena._combo_window_remaining, 0.0)


func test_smash_breaks_the_enemy_parry_that_only_scales_a_light() -> void:
	var arena: Arena = _instantiate_arena()
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	arena._enemy_state = Arena.EnemyState.PARRY
	arena._enemy_parry_elapsed = 0.0
	arena._attack_is_heavy = true
	arena._combo_index = 3
	arena._attack_active = true
	arena._attack_hit = false

	arena._on_attack_hitbox_body_entered(enemy_capsule)

	var expected_damage: float = BALANCE.arena_heavy_attack_damage * (
		1.0 + BALANCE.arena_light_attack_combo_damage_step * 3.0
	)
	assert_almost_eq(arena._enemy_hp, BALANCE.arena_enemy_max_hp - expected_damage, 0.001)
	assert_almost_eq(arena._hit_stop_remaining, BALANCE.arena_heavy_attack_hit_stop, 0.001)

	# The enemy's i-frames still beat it: guard break is not dodge break.
	arena._enemy_hp = BALANCE.arena_enemy_max_hp
	arena._enemy_state = Arena.EnemyState.DODGE
	arena._enemy_dodge_elapsed = 0.0
	arena._hit_stop_remaining = 0.0
	arena._attack_active = true
	arena._attack_hit = false
	arena._on_attack_hitbox_body_entered(enemy_capsule)
	assert_eq(arena._enemy_hp, BALANCE.arena_enemy_max_hp)


func test_back_attack_multiplies_damage_only_from_behind() -> void:
	var arena: Arena = _instantiate_arena()
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	assert_almost_eq(enemy_capsule.rotation.y, PI, 0.001)

	arena._attack_active = true
	arena._attack_hit = false
	arena._on_attack_hitbox_body_entered(enemy_capsule)
	assert_almost_eq(
		arena._enemy_hp,
		BALANCE.arena_enemy_max_hp - BALANCE.arena_light_attack_damage,
		0.001,
	)

	enemy_capsule.rotation.y = 0.0
	arena._enemy_hp = BALANCE.arena_enemy_max_hp
	arena._hit_stop_remaining = 0.0
	arena._attack_active = true
	arena._attack_hit = false
	arena._on_attack_hitbox_body_entered(enemy_capsule)
	assert_almost_eq(
		arena._enemy_hp,
		BALANCE.arena_enemy_max_hp
		- BALANCE.arena_light_attack_damage * BALANCE.arena_back_attack_damage_multiplier,
		0.001,
	)


func test_super_armor_keeps_the_smash_swinging_but_still_counts_the_hit() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var heavy_event := InputEventAction.new()
	heavy_event.action = &"heavy_attack"
	heavy_event.pressed = true

	arena._unhandled_input(heavy_event)
	arena._physics_process(BALANCE.arena_heavy_attack_startup * 0.5)
	assert_true(arena._hero_has_super_armor())
	arena._enemy_attack_active = true
	arena._on_enemy_attack_hitbox_body_entered(hero_capsule)
	arena._physics_process(BALANCE.arena_enemy_attack_hit_stop)

	assert_eq(arena._hits_taken, 1)
	assert_true(arena._attack_is_heavy)
	assert_gt(arena._attack_elapsed, 0.0)
	assert_eq(arena._hit_stun_remaining, 0.0)
	assert_almost_eq(Vector2(hero_capsule.velocity.x, hero_capsule.velocity.z).length(), 0.0, 0.001)

	# Armor covers startup and the active window, and nothing else - the smash's recovery is as
	# exposed as any other.
	arena._attack_elapsed = (
		BALANCE.arena_heavy_attack_startup + BALANCE.arena_heavy_attack_active + 0.01
	)
	assert_false(arena._hero_has_super_armor())


func test_parry_window_and_enemy_telegraph_tint_the_capsules() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_mesh := arena.get_node("HeroCapsule/Mesh") as MeshInstance3D
	var enemy_mesh := arena.get_node("EnemyCapsule/Mesh") as MeshInstance3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true

	arena._unhandled_input(dodge_event)
	arena._physics_process(0.0)
	assert_eq((hero_mesh.material_override as StandardMaterial3D).albedo_color, Arena.PARRY_WINDOW_COLOR)
	arena._parry_elapsed = BALANCE.arena_parry_startup + BALANCE.arena_parry_active_window
	arena._physics_process(0.0)
	assert_ne((hero_mesh.material_override as StandardMaterial3D).albedo_color, Arena.PARRY_WINDOW_COLOR)

	arena._enemy_attack_elapsed = (
		BALANCE.arena_enemy_attack_startup - BALANCE.arena_enemy_telegraph_flash - 0.01
	)
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.ENEMY_WINDUP_COLOR)
	arena._enemy_attack_elapsed = BALANCE.arena_enemy_attack_startup - 0.01
	arena._physics_process(0.0)
	assert_eq((enemy_mesh.material_override as StandardMaterial3D).albedo_color, Arena.ENEMY_TELEGRAPH_COLOR)


func _instantiate_arena() -> Arena:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	return arena


func _capture_scene_request(scene_path: String) -> void:
	_requested_scene = scene_path


func _capture_combat_result(result: CombatResult) -> void:
	_combat_result = result
