class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)

const BALANCE: BalanceTable = preload("res://balance.tres")
const GROUND_PLANE := Plane(Vector3.UP, 0.0)

@onready var _camera: Camera3D = %Camera3D
@onready var _hero_capsule: CharacterBody3D = %HeroCapsule

var _aim_screen_position: Vector2


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)
	_aim_screen_position = get_viewport().get_mouse_position()


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction := Vector3(input_direction.x, 0.0, input_direction.y)
	_hero_capsule.velocity = move_direction * BALANCE.arena_move_speed
	_hero_capsule.move_and_slide()
	_aim_at_screen_position(_aim_screen_position)


func _aim_at_screen_position(screen_position: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	# Godot returns either the Vector3 hit point or null from Plane.intersects_ray().
	var intersection: Variant = GROUND_PLANE.intersects_ray(ray_origin, ray_direction)
	if not intersection is Vector3:
		return
	var aim_point: Vector3 = intersection
	aim_point.y = _hero_capsule.global_position.y
	if _hero_capsule.global_position.is_equal_approx(aim_point):
		return
	_hero_capsule.look_at(aim_point, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_screen_position = event.position
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	scene_change_requested.emit(SceneRouter.HUB)
