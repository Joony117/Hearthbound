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


## What `_play_animation()` stretches into a balance window: the trimmed swing, not the whole clip.
## `length` is already the trim end, so only the start has to come off.
func _clip_span(animation_player: AnimationPlayer, clip: StringName) -> float:
	var bare := StringName(String(clip).trim_prefix("mixamo/"))
	var start: float = Arena.CLIP_TRIMS[bare].x if Arena.CLIP_TRIMS.has(bare) else 0.0
	return animation_player.get_animation(clip).length - start


func test_arena_loads_animated_characters_without_mutating_profile() -> void:
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
	var hero_model := arena.get_node_or_null("HeroCapsule/HeroModel") as Node3D
	assert_not_null(hero_model)
	assert_gt(hero_model.basis.z.normalized().dot(Vector3.FORWARD), 0.999)
	assert_not_null(hero_model.get_node_or_null("Skeleton3D"))
	assert_not_null(arena.get_node_or_null("HeroCapsule/HeroAnimationPlayer"))
	assert_not_null(arena.get_node_or_null("HeroCapsule/FacingMarker"))
	var attack_hitbox := arena.get_node_or_null("HeroCapsule/AttackHitbox") as Area3D
	assert_not_null(attack_hitbox)
	assert_eq(attack_hitbox.collision_mask, 2)
	var enemy_capsule := arena.get_node_or_null("EnemyCapsule") as CharacterBody3D
	assert_not_null(enemy_capsule)
	assert_gt((-enemy_capsule.basis.z).normalized().dot(Vector3.BACK), 0.999)
	assert_not_null(arena.get_node_or_null("EnemyCapsule/CollisionShape3D"))
	var enemy_model := arena.get_node_or_null("EnemyCapsule/EnemyModel") as Node3D
	assert_not_null(enemy_model)
	assert_gt(enemy_model.basis.z.normalized().dot(Vector3.FORWARD), 0.999)
	assert_not_null(enemy_model.get_node_or_null("Skeleton3D"))
	assert_not_null(arena.get_node_or_null("EnemyCapsule/EnemyAnimationPlayer"))
	var enemy_hitbox := arena.get_node_or_null("EnemyCapsule/EnemyAttackHitbox") as Area3D
	assert_not_null(enemy_hitbox)
	assert_eq(enemy_hitbox.collision_mask, 1)
	assert_eq(enemy_hitbox.position, Vector3(0.0, 0.0, -0.75))
	assert_not_null(arena.get_node_or_null("ArenaBounds/LeftWall"))
	var spring_arm := arena.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	assert_not_null(spring_arm)
	assert_almost_eq(spring_arm.spring_length, BALANCE.arena_camera_spring_length, 0.001)
	var camera := arena.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	assert_not_null(camera)
	assert_almost_eq(camera.position.x, 0.5, 0.001)
	assert_not_null(arena.get_node_or_null("Sun"))
	var profile_after: Dictionary = GameSession.to_dict()
	print("P2B09_PROFILE before=%s after=%s" % [profile_before, profile_after])
	assert_eq(profile_after, profile_before)


func test_arena_capsule_overrides_render_combat_tints_without_mutating_authored_materials() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_meshes: Array[MeshInstance3D] = [
		arena.get_node("HeroCapsule/HeroModel/Skeleton3D/Beta_Surface") as MeshInstance3D,
		arena.get_node("HeroCapsule/HeroModel/Skeleton3D/Beta_Joints") as MeshInstance3D,
	]
	var hero_mesh: MeshInstance3D = hero_meshes[0]
	var enemy_meshes: Array[MeshInstance3D] = [
		arena.get_node("EnemyCapsule/EnemyModel/Skeleton3D/Beta_Surface") as MeshInstance3D,
		arena.get_node("EnemyCapsule/EnemyModel/Skeleton3D/Beta_Joints") as MeshInstance3D,
	]
	var enemy_mesh: MeshInstance3D = enemy_meshes[0]
	var hero_authored_material := hero_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var enemy_authored_material := enemy_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var hero_base_color: Color = hero_authored_material.albedo_color
	var enemy_base_color: Color = enemy_authored_material.albedo_color

	assert_not_null(hero_mesh.material_override)
	for tinted_mesh: MeshInstance3D in hero_meshes:
		assert_eq(tinted_mesh.material_override, hero_mesh.material_override)
	assert_not_null(enemy_mesh.material_override)
	for tinted_mesh: MeshInstance3D in enemy_meshes:
		assert_eq(tinted_mesh.material_override, enemy_mesh.material_override)
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
	for tinted_mesh: MeshInstance3D in hero_meshes:
		assert_eq((tinted_mesh.material_override as StandardMaterial3D).albedo_color, Arena.HIT_HERO_COLOR)
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
	assert_eq(BALANCE.arena_enemy_attack_facing_lock, 0.36)
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
	assert_eq(BALANCE.arena_parry_active_window, 0.30)
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


func test_enemy_attack_locks_facing_before_the_active_window() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	enemy_capsule.position = Vector3(0.0, 1.25, -2.0)
	arena._physics_process(0.0)

	hero_capsule.position.x = 2.0
	var pre_lock_step: float = BALANCE.arena_enemy_attack_facing_lock * 0.5
	arena._physics_process(pre_lock_step)
	var facing_before_lock: Vector3 = -enemy_capsule.global_basis.z.normalized()
	var hero_before_lock: Vector3 = (hero_capsule.global_position - enemy_capsule.global_position).normalized()
	assert_gt(facing_before_lock.dot(hero_before_lock), 0.99)

	arena._physics_process(BALANCE.arena_enemy_attack_facing_lock - pre_lock_step)
	var facing_at_lock: float = enemy_capsule.rotation.y
	hero_capsule.position.x = -2.0
	var post_lock_startup_step: float = (BALANCE.arena_enemy_attack_startup - BALANCE.arena_enemy_attack_facing_lock) * 0.5
	arena._physics_process(post_lock_startup_step)
	assert_almost_eq(enemy_capsule.rotation.y, facing_at_lock, 0.001)
	arena._physics_process(post_lock_startup_step)
	assert_almost_eq(enemy_capsule.rotation.y, facing_at_lock, 0.001)


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


func test_parry_between_dodge_iframes_and_active_window_succeeds() -> void:
	var arena_scene: PackedScene = load(SceneRouter.ARENA) as PackedScene
	var arena: Arena = arena_scene.instantiate() as Arena
	add_child_autofree(arena)
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	arena._unhandled_input(dodge_event)
	var late_parry_time: float = (BALANCE.arena_dodge_iframe_duration + BALANCE.arena_parry_active_window) * 0.5
	arena._physics_process(late_parry_time)
	arena._enemy_attack_active = true
	arena._on_enemy_attack_hitbox_body_entered(hero_capsule)

	assert_eq(arena._hit_stop_outcome, Arena.HitStopOutcome.PARRY_HERO)


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
	var button: Button = hub.get_node("%EnterArena") as Button
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
	var hero_mesh := arena.get_node("HeroCapsule/HeroModel/Skeleton3D/Beta_Surface") as MeshInstance3D
	var enemy_mesh := arena.get_node("EnemyCapsule/EnemyModel/Skeleton3D/Beta_Surface") as MeshInstance3D
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


func test_hero_animations_do_not_change_attack_or_dodge_displacement() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	enemy_capsule.position = Vector3(8.0, 1.25, 8.0)
	var attack_event := InputEventAction.new()
	attack_event.action = &"attack"
	attack_event.pressed = true
	var attack_start: Vector3 = hero_capsule.global_position
	arena._unhandled_input(attack_event)
	for _frame: int in range(120):
		await wait_physics_frames(1)
		if arena._attack_elapsed < 0.0:
			break
	var attack_displacement: float = hero_capsule.global_position.distance_to(attack_start)

	var dodge_event := InputEventAction.new()
	dodge_event.action = &"dodge"
	dodge_event.pressed = true
	Input.action_press(&"move_back")
	var dodge_start: Vector3 = hero_capsule.global_position
	arena._unhandled_input(dodge_event)
	for _frame: int in range(120):
		await wait_physics_frames(1)
		if arena._dodge_elapsed < 0.0:
			break
	Input.action_release(&"move_back")
	var dodge_displacement: float = hero_capsule.global_position.distance_to(dodge_start)
	print("P2B09_DISPLACEMENT attack=%.6f dodge=%.6f" % [attack_displacement, dodge_displacement])
	assert_almost_eq(attack_displacement, 2.0, 0.001)
	assert_almost_eq(dodge_displacement, 2.464957, 0.001)


func test_hero_animation_player_covers_every_arena_state_and_fits_authored_windows() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	assert_true(animation_player.has_animation_library(&"mixamo"))
	var jog_animation: Animation = animation_player.get_animation(&"mixamo/Jog_Fwd")
	var hips_track: int = jog_animation.find_track(
		NodePath("Skeleton3D:mixamorig_Hips"),
		Animation.TYPE_POSITION_3D,
	)
	var first_hips_position: Vector3 = jog_animation.track_get_key_value(hips_track, 0)
	var last_hips_position: Vector3 = jog_animation.track_get_key_value(
		hips_track,
		jog_animation.track_get_key_count(hips_track) - 1,
	)
	assert_almost_eq(
		Vector2(first_hips_position.x, first_hips_position.z).distance_to(
			Vector2(last_hips_position.x, last_hips_position.z),
		),
		0.0,
		0.0001,
	)

	arena._physics_process(0.0)
	assert_eq(animation_player.current_animation, &"mixamo/Idle")
	arena._hero_capsule.velocity.z = BALANCE.arena_move_speed
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Jog_Fwd")
	arena._hero_capsule.velocity.z = BALANCE.arena_sprint_speed
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Sprint")

	arena._hero_capsule.velocity = Vector3.ZERO
	arena._attack_elapsed = 0.0
	arena._combo_index = 0
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_A")
	var light_attack_animation: StringName = animation_player.current_animation
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_A")
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)
	arena._attack_elapsed = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, light_attack_animation)
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_A")
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)
	arena._combo_index = 1
	arena._attack_elapsed = 0.0
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_B")
	var second_light_attack_animation: StringName = animation_player.current_animation
	arena._attack_elapsed = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, second_light_attack_animation)
	arena._combo_index = 2
	arena._attack_elapsed = 0.0
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_C")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_C")
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)

	arena._attack_is_heavy = true
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_Heavy")
	var heavy_attack_animation: StringName = animation_player.current_animation
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_Heavy")
		/ (
			BALANCE.arena_heavy_attack_startup
			+ BALANCE.arena_heavy_attack_active
			+ BALANCE.arena_heavy_attack_recovery
		),
		0.001,
	)
	arena._attack_elapsed = BALANCE.arena_heavy_attack_startup + BALANCE.arena_heavy_attack_active
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, heavy_attack_animation)
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_Heavy")
		/ (
			BALANCE.arena_heavy_attack_startup
			+ BALANCE.arena_heavy_attack_active
			+ BALANCE.arena_heavy_attack_recovery
		),
		0.001,
	)
	arena._attack_elapsed = -1.0
	arena._attack_is_heavy = false
	arena._dodge_elapsed = 0.0
	arena._dodge_direction = Vector3.FORWARD
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Standing Dodge Forward")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Standing Dodge Forward")
		/ BALANCE.arena_dodge_duration,
		0.001,
	)
	arena._dodge_elapsed = -1.0
	arena._parry_elapsed = 0.0
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Block")
	assert_almost_eq(animation_player.get_playing_speed(), 1.0, 0.001)
	arena._parry_elapsed = -1.0
	arena._hit_stun_remaining = BALANCE.arena_enemy_hit_stun
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Hit_Chest")
	# The reaction is fitted to the stun now, so it finishes instead of being cut by Idle.
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Hit_Chest") / BALANCE.arena_enemy_hit_stun,
		0.001,
	)


func test_enemy_animations_do_not_change_attack_or_dodge_displacement() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	hero_capsule.position = Vector3(8.0, 1.25, 8.0)

	var attack_start: Vector3 = enemy_capsule.global_position
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = 0.0
	arena._stop_enemy_horizontal()
	for _frame: int in range(120):
		await wait_physics_frames(1)
		if arena._enemy_state == Arena.EnemyState.MOVE:
			break
	var attack_displacement: float = enemy_capsule.global_position.distance_to(attack_start)

	var dodge_start: Vector3 = enemy_capsule.global_position
	arena._enemy_state = Arena.EnemyState.DODGE
	arena._enemy_dodge_elapsed = 0.0
	arena._enemy_dodge_direction = Vector3.RIGHT
	for _frame: int in range(120):
		await wait_physics_frames(1)
		if arena._enemy_state == Arena.EnemyState.MOVE:
			break
	var dodge_displacement: float = enemy_capsule.global_position.distance_to(dodge_start)

	print("P2B10_DISPLACEMENT attack=%.6f dodge=%.6f" % [attack_displacement, dodge_displacement])
	# The coroutine resumes one MOVE tick after ATTACK ends, contributing 4.2 / 60 = 0.07.
	# Literal measurements match the hero regression test and avoid a second, desynchronized clock.
	assert_almost_eq(attack_displacement, 0.07, 0.001)
	assert_almost_eq(dodge_displacement, 3.483334, 0.001)


func test_enemy_animation_player_covers_every_state_and_fits_authored_windows() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	assert_true(animation_player.has_animation_library(&"mixamo"))

	arena._enemy_state = Arena.EnemyState.MOVE
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Idle")
	arena._enemy_capsule.velocity.z = BALANCE.arena_enemy_move_speed
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Jog_Fwd")

	arena._enemy_capsule.velocity = Vector3.ZERO
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = 0.0
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_A")
	var enemy_attack_animation: StringName = animation_player.current_animation
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_A")
		/ (
			BALANCE.arena_enemy_attack_startup
			+ BALANCE.arena_enemy_attack_active
			+ BALANCE.arena_enemy_attack_recovery
		),
		0.001,
	)
	arena._enemy_attack_elapsed = (
		BALANCE.arena_enemy_attack_startup + BALANCE.arena_enemy_attack_active
	)
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, enemy_attack_animation)
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_A")
		/ (
			BALANCE.arena_enemy_attack_startup
			+ BALANCE.arena_enemy_attack_active
			+ BALANCE.arena_enemy_attack_recovery
		),
		0.001,
	)

	arena._enemy_state = Arena.EnemyState.DODGE
	arena._enemy_attack_elapsed = -1.0
	# The enemy only ever dodges straight away from a hero it is facing, so its dodge is always the
	# backward clip. It gets the other three for free if a later ticket gives it a sidestep.
	arena._enemy_dodge_direction = arena._enemy_capsule.global_basis.z.normalized()
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Standing Dodge Backward")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Standing Dodge Backward")
		/ BALANCE.arena_enemy_dodge_duration,
		0.001,
	)

	arena._enemy_state = Arena.EnemyState.PARRY
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Block")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Block")
		/ BALANCE.arena_enemy_parry_active_window,
		0.001,
	)

	arena._enemy_state = Arena.EnemyState.STAGGER
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Hit_Chest")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Hit_Chest")
		/ BALANCE.arena_parry_enemy_stagger,
		0.001,
	)


func test_hero_locomotion_picks_the_strafe_clip_its_travel_direction_calls_for() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	arena._hero_capsule.rotation.y = 0.0
	arena._hero_capsule.velocity = Vector3(BALANCE.arena_move_speed, 0.0, 0.0)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Sword And Shield Strafe right")
	arena._hero_capsule.velocity = Vector3(-BALANCE.arena_move_speed, 0.0, 0.0)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Sword And Shield Strafe left")
	arena._hero_capsule.velocity = Vector3(0.0, 0.0, -BALANCE.arena_move_speed)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Jog_Fwd")

	# The pick is relative to facing, not to the world. Yawed a quarter turn the hero's forward is
	# world -X, so the velocity that just jogged now strafes and the one that strafed now jogs.
	arena._hero_capsule.rotation.y = PI * 0.5
	arena._hero_capsule.velocity = Vector3(-BALANCE.arena_move_speed, 0.0, 0.0)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Jog_Fwd")
	arena._hero_capsule.velocity = Vector3(0.0, 0.0, -BALANCE.arena_move_speed)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Sword And Shield Strafe right")


func test_big_hit_staggers_the_enemy_out_of_its_attack_and_plays_its_own_reaction() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer

	# The 90% case first: an ordinary flinch is hit-stop only and leaves the enemy's attack running.
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = 0.0
	arena._hit_stop_outcome = Arena.HitStopOutcome.FLINCH_ENEMY
	arena._hit_stop_remaining = BALANCE.arena_enemy_hit_flinch_stop
	arena._update_hit_stop(BALANCE.arena_enemy_hit_flinch_stop)
	assert_eq(arena._enemy_state, Arena.EnemyState.ATTACK)

	arena._enemy_attack_active = true
	arena._enemy_attack_hitbox.monitoring = true
	arena._enemy_big_hit = true
	arena._hit_stop_outcome = Arena.HitStopOutcome.FLINCH_ENEMY
	arena._hit_stop_remaining = BALANCE.arena_enemy_hit_flinch_stop
	arena._update_hit_stop(BALANCE.arena_enemy_hit_flinch_stop)
	assert_eq(arena._enemy_state, Arena.EnemyState.STAGGER)
	assert_almost_eq(arena._enemy_stagger_remaining, BALANCE.arena_enemy_big_hit_stagger, 0.001)
	assert_eq(arena._enemy_attack_elapsed, -1.0)
	assert_false(arena._enemy_attack_active)
	assert_false(arena._enemy_attack_hitbox.monitoring)

	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Big Hit To Head")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Big Hit To Head")
		/ BALANCE.arena_enemy_big_hit_stagger,
		0.001,
	)
	# A big hit is a hit. Reading as a parry here would credit the player with a read they never made.
	assert_eq(arena._enemy_tint(), Arena.DEFEAT_ENEMY_COLOR)

	arena._update_enemy_stagger(BALANCE.arena_enemy_big_hit_stagger)
	assert_eq(arena._enemy_state, Arena.EnemyState.MOVE)
	assert_false(arena._enemy_big_hit)


func test_big_hit_landing_mid_parry_still_puts_that_parry_on_cooldown() -> void:
	var arena: Arena = _instantiate_arena()
	arena._enemy_state = Arena.EnemyState.PARRY
	arena._enemy_parry_elapsed = 0.0
	arena._enemy_parry_cooldown_remaining = 0.0
	arena._enemy_big_hit = true
	arena._hit_stop_outcome = Arena.HitStopOutcome.FLINCH_ENEMY
	arena._hit_stop_remaining = BALANCE.arena_enemy_hit_flinch_stop
	arena._update_hit_stop(BALANCE.arena_enemy_hit_flinch_stop)
	assert_eq(arena._enemy_state, Arena.EnemyState.STAGGER)
	assert_eq(arena._enemy_parry_elapsed, -1.0)
	assert_almost_eq(
		arena._enemy_parry_cooldown_remaining,
		BALANCE.arena_enemy_parry_cooldown,
		0.001,
	)


func test_enemy_attack_dominant_motion_lands_inside_telegraph_window() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = 0.0
	arena._update_enemy_animation()
	var animation: Animation = animation_player.get_animation(animation_player.current_animation)
	var dominant_key_time: float = _dominant_rotation_key_time(animation)
	# Playback starts at the trim, so on-screen time is measured from there, not from clip zero.
	var trim: Vector2 = Arena.CLIP_TRIMS[&"Attack_A"]
	var scaled_key_time: float = (dominant_key_time - trim.x) / animation_player.get_playing_speed()
	print(
		"MIXAMO_ATTACK_A_TIMING length=%.6f dominant=%.6f scaled=%.6f"
		% [animation.length, dominant_key_time, scaled_key_time],
	)

	assert_almost_eq(animation.length, trim.y, 0.001)
	assert_almost_eq(dominant_key_time, 0.593333, 0.001)
	# `SYSTEMS.md`'s alignment target is the active-window onset itself. The trim closes the old
	# 0.435 s miss to within a frame of it; the residual is the trim being on a round 1/100 s.
	assert_almost_eq(scaled_key_time, BALANCE.arena_enemy_attack_startup, 1.0 / 60.0)
	assert_almost_eq(scaled_key_time, 0.539524, 0.001)
	assert_gte(
		scaled_key_time,
		BALANCE.arena_enemy_attack_startup - BALANCE.arena_enemy_telegraph_flash,
	)
	assert_lt(scaled_key_time, BALANCE.arena_enemy_attack_startup)


func test_hero_smash_uses_one_swing_with_its_arm_peak_at_the_active_boundary() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	arena._attack_is_heavy = true
	arena._attack_elapsed = 0.0
	arena._update_hero_animation()
	var animation: Animation = animation_player.get_animation(animation_player.current_animation)
	var dominant_key_time: float = _dominant_rotation_key_time(animation)
	var scaled_key_time: float = dominant_key_time / animation_player.get_playing_speed()
	print(
		"MIXAMO_ATTACK_HEAVY_TIMING length=%.6f dominant=%.6f scaled=%.6f"
		% [animation.length, dominant_key_time, scaled_key_time],
	)

	assert_eq(animation_player.current_animation, &"mixamo/Attack_Heavy")
	assert_almost_eq(dominant_key_time, 0.333333, 0.001)
	assert_almost_eq(scaled_key_time, BALANCE.arena_heavy_attack_startup, 0.05)


func _dominant_rotation_key_time(animation: Animation) -> float:
	var dominant_speed: float = -1.0
	var dominant_key_time: float = -1.0
	for track_index: int in range(animation.get_track_count()):
		if (
			animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D
			or animation.track_get_path(track_index)
			!= NodePath("Skeleton3D:mixamorig_RightArm")
		):
			continue
		for key_index: int in range(1, animation.track_get_key_count(track_index)):
			var previous_time: float = animation.track_get_key_time(track_index, key_index - 1)
			var key_time: float = animation.track_get_key_time(track_index, key_index)
			var key_duration: float = key_time - previous_time
			assert(key_duration > 0.0)
			var previous_rotation: Quaternion = animation.rotation_track_interpolate(
				track_index,
				previous_time,
			)
			var rotation: Quaternion = animation.rotation_track_interpolate(track_index, key_time)
			var angular_speed: float = previous_rotation.angle_to(rotation) / key_duration
			if angular_speed > dominant_speed:
				dominant_speed = angular_speed
				dominant_key_time = key_time
	assert(dominant_key_time >= 0.0)
	return dominant_key_time


## A successful hero parry has no enemy-side armor carve-out: unlike HIT_HERO, PARRY_HERO cannot
## later resolve into a non-stagger result. The reaction therefore starts on registration so its
## first freeze frame agrees with the existing cyan tint instead of waiting for hit-stop to end.
func test_enemy_parry_registration_starts_stagger_animation_during_hit_stop() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = BALANCE.arena_enemy_attack_startup
	arena._update_enemy_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_A")

	arena._hit_stop_outcome = Arena.HitStopOutcome.PARRY_HERO
	arena._hit_stop_remaining = BALANCE.arena_parry_hit_stop
	arena._physics_process(0.0)
	assert_eq(animation_player.assigned_animation, &"mixamo/Hit_Chest")


## Chain steps 3 and 4 reuse the A and B clips — the `% 3` wrap that makes `A / B / C / A / B`
## free rather than needing five authored clips. Steps 0-2 are covered above; without these two
## the wrap itself is never exercised.
func test_hero_light_attack_chain_wraps_back_onto_the_a_and_b_clips() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer

	arena._attack_elapsed = 0.0
	arena._combo_index = 3
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_A")
	arena._combo_index = 4
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_B")
	var wrapped_attack_animation: StringName = animation_player.current_animation
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_B")
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)
	arena._attack_elapsed = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, wrapped_attack_animation)
	assert_almost_eq(
		animation_player.get_playing_speed(),
		_clip_span(animation_player, &"mixamo/Attack_B")
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)


## `HIT_HERO` is registered the instant the enemy hitbox connects and stays set for the whole
## hit-stop freeze, while `_update_hit_stop()` only resolves super armor when that freeze ends.
## Without the armor check in `_update_hero_animation()`, those freeze frames cut to a hit
## reaction and then restart the smash from frame 0 — desyncing the pose from `_attack_elapsed`,
## which never paused. This is the animation half of `test_super_armor_keeps_the_smash_swinging`.
func test_super_armor_keeps_the_smash_animation_through_the_hit_freeze() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer

	arena._attack_is_heavy = true
	arena._attack_elapsed = BALANCE.arena_heavy_attack_startup
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_Heavy")

	arena._hit_stop_outcome = Arena.HitStopOutcome.HIT_HERO
	arena._update_hero_animation()
	assert_eq(
		animation_player.current_animation,
		&"mixamo/Attack_Heavy",
		"An armored smash must hold its pose, not cut to a reaction and restart the swing.",
	)

	# The same hit past the armor window is an ordinary interrupt.
	arena._attack_elapsed = (
		BALANCE.arena_heavy_attack_startup + BALANCE.arena_heavy_attack_active + 0.01
	)
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Hit_Chest")


func test_hit_stop_pauses_both_animation_players_and_resumes_the_same_frames() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	var enemy_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	arena._attack_elapsed = 0.0
	arena._enemy_state = Arena.EnemyState.ATTACK
	arena._enemy_attack_elapsed = 0.0
	arena._update_hero_animation()
	arena._update_enemy_animation()
	hero_player.advance(0.05)
	enemy_player.advance(0.05)
	var hero_swing_speed: float = hero_player.get_playing_speed()
	var enemy_swing_speed: float = enemy_player.get_playing_speed()
	arena._hit_stop_outcome = Arena.HitStopOutcome.FLINCH_ENEMY
	arena._hit_stop_remaining = BALANCE.arena_light_attack_hit_stop
	arena._physics_process(0.0)
	var hero_frozen_position: float = hero_player.current_animation_position
	var enemy_frozen_position: float = enemy_player.current_animation_position

	await wait_physics_frames(1)
	assert_almost_eq(hero_player.current_animation_position, hero_frozen_position, 0.0001)
	assert_almost_eq(enemy_player.current_animation_position, enemy_frozen_position, 0.0001)

	arena._physics_process(BALANCE.arena_light_attack_hit_stop)
	# Both players run on the idle callback, and one frame is not enough — the awaiting coroutine
	# resumes before that frame's animation processing has run, which is what made this test flaky.
	# Four idle frames still land inside the attack window, so the swing clip is what advances.
	await wait_idle_frames(4)
	assert_gt(hero_player.current_animation_position, hero_frozen_position)
	assert_gt(enemy_player.current_animation_position, enemy_frozen_position)
	# Resuming used to hand the rest of the swing back at the clip's native rate.
	assert_almost_eq(hero_player.get_playing_speed(), hero_swing_speed, 0.0001)
	assert_almost_eq(enemy_player.get_playing_speed(), enemy_swing_speed, 0.0001)


func test_both_animation_players_crossfade_instead_of_cutting() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	var enemy_player := arena.get_node("EnemyCapsule/EnemyAnimationPlayer") as AnimationPlayer
	assert_eq(hero_player.playback_default_blend_time, Arena.ANIMATION_BLEND_TIME)
	assert_eq(enemy_player.playback_default_blend_time, Arena.ANIMATION_BLEND_TIME)
	# The blend has to finish inside the shortest authored phase, or the swing pose is still a
	# mixture when the hitbox opens.
	assert_lt(Arena.ANIMATION_BLEND_TIME, BALANCE.arena_light_attack_startup)


## Inverts `P2b-09`'s `test_dodge_capsules_face_their_roll_direction`. With one roll clip a dodge had
## to spin the capsule so that a forward animation pointed the right way. Four authored directions
## make the opposite the contract: a dodge turns nobody, and the clip follows the direction instead.
func test_dodge_turns_neither_capsule_and_picks_the_clip_from_the_direction() -> void:
	var arena: Arena = _instantiate_arena()
	var hero_capsule := arena.get_node("HeroCapsule") as CharacterBody3D
	var enemy_capsule := arena.get_node("EnemyCapsule") as CharacterBody3D
	var hero_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	hero_capsule.rotation.y = 0.0
	Input.action_press(&"move_right")
	arena._start_dodge()
	Input.action_release(&"move_right")
	assert_almost_eq(hero_capsule.rotation.y, 0.0, 0.0001)
	arena._update_hero_animation()
	assert_eq(hero_player.current_animation, &"mixamo/Standing Dodge Right")

	# The enemy keeps tracking the hero through its own dodge — 0.5 s at 720°/s covers any start.
	arena._enemy_state = Arena.EnemyState.DODGE
	arena._enemy_dodge_elapsed = 0.0
	arena._enemy_dodge_direction = Vector3.LEFT
	arena._update_enemy_dodge(0.5)
	var to_hero: Vector3 = hero_capsule.global_position - enemy_capsule.global_position
	to_hero.y = 0.0
	assert_gt((-enemy_capsule.global_basis.z).normalized().dot(to_hero.normalized()), 0.999)


## `ig-r86`: a Mixamo swing is stance → windup → swing → stance in one clip, so handing the whole
## clip to a balance window authored for capsules ran the light attacks at 4x. The window belongs to
## the trimmed span, and a fresh play has to start at the trim rather than at the stance.
func test_trimmed_clip_stretches_only_its_swing_and_starts_at_the_trim() -> void:
	var arena: Arena = _instantiate_arena()
	var animation_player := arena.get_node("HeroCapsule/HeroAnimationPlayer") as AnimationPlayer
	var trim: Vector2 = Arena.CLIP_TRIMS[&"Attack_A"]
	assert_gt(trim.x, 0.0)
	# The trim end is the clip's length, because Godot has no trim API to express it any other way.
	assert_almost_eq(animation_player.get_animation(&"mixamo/Attack_A").length, trim.y, 0.0001)

	arena._attack_elapsed = 0.0
	arena._combo_index = 0
	arena._update_hero_animation()
	assert_eq(animation_player.current_animation, &"mixamo/Attack_A")
	assert_almost_eq(
		animation_player.get_playing_speed(),
		(trim.y - trim.x)
		/ (
			BALANCE.arena_light_attack_startup
			+ BALANCE.arena_light_attack_active
			+ BALANCE.arena_light_attack_recovery
		),
		0.001,
	)
	assert_almost_eq(animation_player.current_animation_position, trim.x, 0.0001)
