class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)
signal enemy_defeated

const BALANCE: BalanceTable = preload("res://balance.tres")

@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _hero_capsule: CharacterBody3D = %HeroCapsule
@onready var _spring_arm: SpringArm3D = %SpringArm3D
@onready var _attack_hitbox: Area3D = %AttackHitbox
@onready var _enemy_capsule: CharacterBody3D = %EnemyCapsule

var _attack_elapsed: float = -1.0
var _attack_active: bool = false
var _attack_hit: bool = false
var _attack_direction: Vector3 = Vector3.FORWARD
var _hit_stop_remaining: float = 0.0


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)
	_spring_arm.spring_length = BALANCE.arena_camera_spring_length
	_spring_arm.add_excluded_object(_hero_capsule.get_rid())
	_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	var shape_node: CollisionShape3D = _attack_hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var attack_shape: BoxShape3D = shape_node.shape.duplicate() as BoxShape3D
	assert(attack_shape != null)
	attack_shape.size.z = BALANCE.arena_light_attack_reach
	shape_node.shape = attack_shape
	shape_node.position.z = -BALANCE.arena_light_attack_reach * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if _hit_stop_remaining > 0.0:
		_update_hit_stop(delta)
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

	if move_direction != Vector3.ZERO:
		_turn_hero(move_direction, delta)


func _update_attack(delta: float) -> void:
	_attack_elapsed += delta
	var active_end: float = BALANCE.arena_light_attack_startup + BALANCE.arena_light_attack_active
	var recovery_end: float = active_end + BALANCE.arena_light_attack_recovery

	if _attack_elapsed < BALANCE.arena_light_attack_startup:
		var input_direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		var move_direction: Vector3 = _camera_relative_direction(input_direction)
		if move_direction != Vector3.ZERO:
			_turn_hero(move_direction, delta)
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


func _update_hit_stop(delta: float) -> void:
	_stop_horizontal()
	_hit_stop_remaining = maxf(0.0, _hit_stop_remaining - delta)
	if _hit_stop_remaining > 0.0:
		return
	if is_instance_valid(_enemy_capsule):
		_enemy_capsule.queue_free()
		enemy_defeated.emit()


func _start_attack() -> void:
	if _attack_elapsed >= 0.0:
		return
	_attack_elapsed = 0.0
	_attack_active = false
	_attack_hit = false
	_stop_horizontal()


func _turn_hero(move_direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-move_direction.x, -move_direction.z)
	_hero_capsule.rotation.y = rotate_toward(
		_hero_capsule.rotation.y,
		target_yaw,
		deg_to_rad(BALANCE.arena_turn_speed_degrees) * delta,
	)


func _stop_horizontal() -> void:
	_hero_capsule.velocity.x = 0.0
	_hero_capsule.velocity.z = 0.0


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body != _enemy_capsule or not _attack_active or _attack_hit:
		return
	_attack_hit = true
	_hit_stop_remaining = BALANCE.arena_light_attack_hit_stop
	_attack_hitbox.set_deferred("monitoring", false)


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
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_change_requested.emit(SceneRouter.HUB)
