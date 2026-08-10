class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)
signal enemy_defeated

const BALANCE: BalanceTable = preload("res://balance.tres")

enum HitStopOutcome {
	NONE,
	DEFEAT_ENEMY,
	HIT_HERO,
	PARRY_HERO,
}

@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _hero_capsule: CharacterBody3D = %HeroCapsule
@onready var _spring_arm: SpringArm3D = %SpringArm3D
@onready var _attack_hitbox: Area3D = %AttackHitbox
@onready var _enemy_capsule: CharacterBody3D = %EnemyCapsule
@onready var _enemy_attack_hitbox: Area3D = %EnemyAttackHitbox

var _attack_elapsed: float = -1.0
var _attack_active: bool = false
var _attack_hit: bool = false
var _attack_direction: Vector3 = Vector3.FORWARD
var _dodge_elapsed: float = -1.0
var _dodge_cooldown_remaining: float = 0.0
var _parry_elapsed: float = -1.0
var _parry_succeeded: bool = false
var _parry_cooldown_remaining: float = 0.0
var _hit_stun_remaining: float = 0.0
var _hit_stop_remaining: float = 0.0
var _hit_stop_outcome: int = HitStopOutcome.NONE
var _enemy_attack_elapsed: float = -1.0
var _enemy_attack_active: bool = false
var _enemy_attack_hit: bool = false
var _enemy_attack_cooldown_remaining: float = 0.0
var _enemy_stagger_remaining: float = 0.0


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)
	_spring_arm.spring_length = BALANCE.arena_camera_spring_length
	_spring_arm.add_excluded_object(_hero_capsule.get_rid())
	_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	_enemy_attack_hitbox.body_entered.connect(_on_enemy_attack_hitbox_body_entered)
	var shape_node: CollisionShape3D = _attack_hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var attack_shape: BoxShape3D = shape_node.shape.duplicate() as BoxShape3D
	assert(attack_shape != null)
	attack_shape.size.z = BALANCE.arena_light_attack_reach
	shape_node.shape = attack_shape
	shape_node.position.z = -BALANCE.arena_light_attack_reach * 0.5
	var enemy_shape_node: CollisionShape3D = _enemy_attack_hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var enemy_attack_shape: BoxShape3D = enemy_shape_node.shape.duplicate() as BoxShape3D
	assert(enemy_attack_shape != null)
	enemy_attack_shape.size.z = BALANCE.arena_enemy_attack_reach
	enemy_shape_node.shape = enemy_attack_shape
	enemy_shape_node.position.z = -BALANCE.arena_enemy_attack_reach * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if _hit_stop_remaining > 0.0:
		_update_hit_stop(delta)
	else:
		_update_enemy(delta)
		_update_dodge_cooldown(delta)
		_update_parry_cooldown(delta)
		if _hit_stun_remaining > 0.0:
			_update_hit_stun(delta)
		elif _dodge_elapsed >= 0.0:
			_update_dodge(delta)
		elif _parry_elapsed >= 0.0:
			_update_parry(delta)
		elif _attack_elapsed >= 0.0:
			_update_attack(delta)
		else:
			_update_locomotion(delta)
	_hero_capsule.move_and_slide()
	_camera_pivot.global_position = _hero_capsule.global_position + Vector3.UP


func _update_locomotion(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction: Vector3 = _camera_relative_direction(input_direction)
	var speed: float = BALANCE.arena_sprint_speed if Input.is_action_pressed(&"sprint") else BALANCE.arena_move_speed
	var target_velocity := Vector2(move_direction.x, move_direction.z) * speed
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	var rate: float = BALANCE.arena_acceleration if input_direction != Vector2.ZERO else BALANCE.arena_deceleration
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, rate * delta)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y

	_turn_hero(delta)


func _update_attack(delta: float) -> void:
	_attack_elapsed += delta
	var active_end: float = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	var recovery_end: float = active_end + BALANCE.arena_light_attack_recovery

	if _attack_elapsed < BALANCE.arena_light_attack_startup:
		_turn_hero(delta)
		_stop_horizontal()
		return

	if _attack_elapsed < active_end:
		if not _attack_active:
			_attack_active = true
			_attack_direction = -_hero_capsule.global_basis.z.normalized()
			_attack_hitbox.monitoring = true
		var attack_speed: float = BALANCE.arena_light_attack_displacement / BALANCE.arena_light_attack_active
		_hero_capsule.velocity.x = _attack_direction.x * attack_speed
		_hero_capsule.velocity.z = _attack_direction.z * attack_speed
		return

	if _attack_active:
		_attack_active = false
		_attack_hitbox.monitoring = false
	_stop_horizontal()
	if _attack_elapsed >= recovery_end:
		_attack_elapsed = -1.0


func _update_dodge(delta: float) -> void:
	_dodge_elapsed += delta
	if _dodge_elapsed >= BALANCE.arena_dodge_duration:
		_dodge_elapsed = -1.0
		_dodge_cooldown_remaining = BALANCE.arena_dodge_cooldown
		_stop_horizontal()
		return
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(
		Vector2.ZERO,
		BALANCE.arena_dodge_speed / BALANCE.arena_dodge_duration * delta,
	)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y


func _update_dodge_cooldown(delta: float) -> void:
	if _dodge_elapsed < 0.0:
		_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)


func _update_parry_cooldown(delta: float) -> void:
	if _parry_elapsed < 0.0:
		_parry_cooldown_remaining = maxf(0.0, _parry_cooldown_remaining - delta)


func _update_parry(delta: float) -> void:
	_parry_elapsed += delta
	var recovery: float = BALANCE.arena_parry_success_recovery if _parry_succeeded else BALANCE.arena_parry_whiff_recovery
	if _parry_elapsed >= BALANCE.arena_parry_startup + BALANCE.arena_parry_active_window + recovery:
		if _parry_succeeded:
			_parry_cooldown_remaining = BALANCE.arena_parry_cooldown
		_parry_elapsed = -1.0
		_parry_succeeded = false
		_stop_horizontal()


func _update_hit_stun(delta: float) -> void:
	_hit_stun_remaining = maxf(0.0, _hit_stun_remaining - delta)
	var horizontal_velocity := Vector2(_hero_capsule.velocity.x, _hero_capsule.velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, BALANCE.arena_deceleration * delta)
	_hero_capsule.velocity.x = horizontal_velocity.x
	_hero_capsule.velocity.z = horizontal_velocity.y


func _update_hit_stop(delta: float) -> void:
	_stop_horizontal()
	_hit_stop_remaining = maxf(0.0, _hit_stop_remaining - delta)
	if _hit_stop_remaining > 0.0:
		return
	if _hit_stop_outcome == HitStopOutcome.DEFEAT_ENEMY and is_instance_valid(_enemy_capsule):
		_enemy_capsule.queue_free()
		enemy_defeated.emit()
	elif _hit_stop_outcome == HitStopOutcome.HIT_HERO:
		_cancel_player_action_for_hit()
		var knockback_direction: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
		knockback_direction.y = 0.0
		assert(knockback_direction != Vector3.ZERO)
		knockback_direction = knockback_direction.normalized()
		_hero_capsule.velocity.x = knockback_direction.x * BALANCE.arena_enemy_knockback_speed
		_hero_capsule.velocity.z = knockback_direction.z * BALANCE.arena_enemy_knockback_speed
		_hit_stun_remaining = BALANCE.arena_enemy_hit_stun
	elif _hit_stop_outcome == HitStopOutcome.PARRY_HERO:
		_enemy_attack_elapsed = -1.0
		_enemy_attack_active = false
		_enemy_attack_hitbox.monitoring = false
		_enemy_stagger_remaining = BALANCE.arena_parry_enemy_stagger
	_hit_stop_outcome = HitStopOutcome.NONE


func _update_enemy(delta: float) -> void:
	if not is_instance_valid(_enemy_capsule):
		return
	if _enemy_stagger_remaining > 0.0:
		_enemy_stagger_remaining = maxf(0.0, _enemy_stagger_remaining - delta)
		if _enemy_stagger_remaining <= 0.0:
			_enemy_attack_cooldown_remaining = BALANCE.arena_enemy_attack_cooldown
		return
	if _enemy_attack_elapsed < 0.0:
		_turn_enemy(delta)
		_enemy_attack_cooldown_remaining = maxf(0.0, _enemy_attack_cooldown_remaining - delta)
		var offset: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
		offset.y = 0.0
		if (
			_enemy_attack_cooldown_remaining <= 0.0
			and offset.length() <= BALANCE.arena_enemy_attack_trigger_range
		):
			_enemy_attack_elapsed = 0.0
			_enemy_attack_active = false
			_enemy_attack_hit = false
		return

	_enemy_attack_elapsed += delta
	var active_end: float = BALANCE.arena_enemy_attack_startup + BALANCE.arena_enemy_attack_active
	var recovery_end: float = active_end + BALANCE.arena_enemy_attack_recovery
	if _enemy_attack_elapsed < BALANCE.arena_enemy_attack_startup:
		_turn_enemy(delta)
		return
	if _enemy_attack_elapsed < active_end:
		if not _enemy_attack_active:
			_enemy_attack_active = true
			_enemy_attack_hitbox.monitoring = true
		return
	if _enemy_attack_active:
		_enemy_attack_active = false
		_enemy_attack_hitbox.monitoring = false
	if _enemy_attack_elapsed >= recovery_end:
		_enemy_attack_elapsed = -1.0
		_enemy_attack_cooldown_remaining = BALANCE.arena_enemy_attack_cooldown


func _start_attack() -> void:
	if (
		_attack_elapsed >= 0.0
		or _dodge_elapsed >= 0.0
		or (_parry_elapsed >= 0.0 and not _parry_succeeded)
		or _hit_stun_remaining > 0.0
		or _hit_stop_remaining > 0.0
	):
		return
	if _parry_elapsed >= 0.0:
		_parry_elapsed = -1.0
		_parry_succeeded = false
		_parry_cooldown_remaining = BALANCE.arena_parry_cooldown
	_attack_elapsed = 0.0
	_attack_active = false
	_attack_hit = false
	_stop_horizontal()


func _start_dodge() -> void:
	if (
		_dodge_elapsed >= 0.0
		or _parry_elapsed >= 0.0
		or _hit_stun_remaining > 0.0
		or _hit_stop_remaining > 0.0
	):
		return
	var attack_recovery_start: float = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	if _attack_elapsed >= 0.0 and _attack_elapsed < attack_recovery_start:
		return
	var input_direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input_direction == Vector2.ZERO:
		if _parry_cooldown_remaining <= 0.0:
			_start_parry()
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if _attack_elapsed >= 0.0:
		_attack_elapsed = -1.0
		_attack_active = false
		_attack_hitbox.monitoring = false
	var dodge_direction: Vector3 = _camera_relative_direction(input_direction)
	_dodge_elapsed = 0.0
	_hero_capsule.velocity.x = dodge_direction.x * BALANCE.arena_dodge_speed
	_hero_capsule.velocity.z = dodge_direction.z * BALANCE.arena_dodge_speed


func _start_parry() -> void:
	if _attack_elapsed >= 0.0:
		_attack_elapsed = -1.0
		_attack_active = false
		_attack_hitbox.monitoring = false
	_parry_elapsed = 0.0
	_parry_succeeded = false
	_stop_horizontal()


func _cancel_player_action_for_hit() -> void:
	if _dodge_elapsed >= 0.0:
		_dodge_cooldown_remaining = BALANCE.arena_dodge_cooldown
	_dodge_elapsed = -1.0
	_parry_elapsed = -1.0
	_parry_succeeded = false
	_attack_elapsed = -1.0
	_attack_active = false
	_attack_hitbox.monitoring = false


func _turn_hero(delta: float) -> void:
	var target_yaw: float = _camera_pivot.global_rotation.y
	_hero_capsule.rotation.y = rotate_toward(
		_hero_capsule.rotation.y,
		target_yaw,
		deg_to_rad(BALANCE.arena_turn_speed_degrees) * delta,
	)


func _turn_enemy(delta: float) -> void:
	var move_direction: Vector3 = _hero_capsule.global_position - _enemy_capsule.global_position
	move_direction.y = 0.0
	if move_direction == Vector3.ZERO:
		return
	move_direction = move_direction.normalized()
	var target_yaw := atan2(-move_direction.x, -move_direction.z)
	_enemy_capsule.rotation.y = rotate_toward(
		_enemy_capsule.rotation.y,
		target_yaw,
		deg_to_rad(BALANCE.arena_enemy_turn_speed_degrees) * delta,
	)


func _stop_horizontal() -> void:
	_hero_capsule.velocity.x = 0.0
	_hero_capsule.velocity.z = 0.0


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body != _enemy_capsule or not _attack_active or _attack_hit or _hit_stop_remaining > 0.0:
		return
	_attack_hit = true
	_hit_stop_remaining = BALANCE.arena_light_attack_hit_stop
	_hit_stop_outcome = HitStopOutcome.DEFEAT_ENEMY
	_attack_hitbox.set_deferred("monitoring", false)


func _on_enemy_attack_hitbox_body_entered(body: Node3D) -> void:
	if (
		body != _hero_capsule
		or not _enemy_attack_active
		or _enemy_attack_hit
		or _hit_stop_remaining > 0.0
		or _hero_has_iframes()
	):
		return
	_enemy_attack_hit = true
	if _hero_has_active_parry():
		_parry_succeeded = true
		_hit_stop_remaining = BALANCE.arena_parry_hit_stop
		_hit_stop_outcome = HitStopOutcome.PARRY_HERO
	else:
		_hit_stop_remaining = BALANCE.arena_enemy_attack_hit_stop
		_hit_stop_outcome = HitStopOutcome.HIT_HERO
	_enemy_attack_hitbox.set_deferred("monitoring", false)


func _hero_has_iframes() -> bool:
	return _dodge_elapsed >= 0.0 and _dodge_elapsed < BALANCE.arena_dodge_iframe_duration


func _hero_has_active_parry() -> bool:
	return (
		_parry_elapsed >= BALANCE.arena_parry_startup
		and _parry_elapsed < BALANCE.arena_parry_startup + BALANCE.arena_parry_active_window
	)


func _camera_relative_direction(input_direction: Vector2) -> Vector3:
	if input_direction == Vector2.ZERO:
		return Vector3.ZERO
	var camera_forward := -_camera_pivot.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := _camera_pivot.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	return (camera_right * input_direction.x - camera_forward * input_direction.y).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		_camera_pivot.rotation.y = wrapf(
			_camera_pivot.rotation.y - mouse_motion.screen_relative.x * BALANCE.arena_mouse_sensitivity,
			-PI,
			PI,
		)
		_camera_pivot.rotation.x = clampf(
			_camera_pivot.rotation.x - mouse_motion.screen_relative.y * BALANCE.arena_mouse_sensitivity,
			-deg_to_rad(BALANCE.arena_camera_pitch_down_degrees),
			deg_to_rad(BALANCE.arena_camera_pitch_up_degrees),
		)
		return
	if event.is_action_pressed(&"attack"):
		get_viewport().set_input_as_handled()
		_start_attack()
		return
	if event.is_action_pressed(&"dodge"):
		get_viewport().set_input_as_handled()
		_start_dodge()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_change_requested.emit(SceneRouter.HUB)
