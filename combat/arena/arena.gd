class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)

const BALANCE: BalanceTable = preload("res://balance.tres")

@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _hero_capsule: CharacterBody3D = %HeroCapsule
@onready var _spring_arm: SpringArm3D = %SpringArm3D


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)
	_spring_arm.spring_length = BALANCE.arena_camera_spring_length
	_spring_arm.add_excluded_object(_hero_capsule.get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
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
		var target_yaw := atan2(-move_direction.x, -move_direction.z)
		_hero_capsule.rotation.y = rotate_toward(
			_hero_capsule.rotation.y,
			target_yaw,
			deg_to_rad(BALANCE.arena_turn_speed_degrees) * delta,
		)
	_hero_capsule.move_and_slide()
	_camera_pivot.global_position = _hero_capsule.global_position + Vector3.UP


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
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_change_requested.emit(SceneRouter.HUB)
