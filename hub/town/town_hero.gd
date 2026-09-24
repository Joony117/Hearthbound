class_name TownHero
extends CharacterBody3D

## The embodied hero walking the town: WASD or arrows move it, a clicked building draws it there.
## It carries its own follow camera. A view only: GameSession says who it is, hub.gd what opens.

## Reached its building (or gave up on it); TownView turns this into building_selected.
signal arrived(building_id: StringName)

const SPEED: float = 4.0
const MODEL_SCALE: float = 0.75
## Behind and above the hero; the camera looks at its chest.
const CAMERA_OFFSET: Vector3 = Vector3(0.0, 5.0, 7.0)
const CAMERA_LOOK_HEIGHT: float = 1.0
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.1
## ponytail: no pathfinding (navmesh is a non-goal). A walk that stops closing in this long ends
## where it is and still arrives, so a building in the straight line cannot trap the click.
const STUCK_SECONDS: float = 0.5
## Screen-space input: x right, y down (towards the camera).
const MOVE_KEYS: Dictionary[Key, Vector2] = {
	KEY_W: Vector2.UP, KEY_UP: Vector2.UP,
	KEY_S: Vector2.DOWN, KEY_DOWN: Vector2.DOWN,
	KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT,
	KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT,
}
const ARROW_KEYS: Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

var hero_id: String = ""
## Off while a building or the pause menu is open: keys and wheel do nothing and a walk is dropped.
var controls_enabled: bool = true:
	set(value):
		controls_enabled = value
		if not value:
			stop()
var zoom: float = 1.0
## Where the body may stand, as global x/z; no area means anywhere.
var bounds: Rect2 = Rect2()
var camera: Camera3D
var _model: Node3D
var _animator: AnimationPlayer
var _target: Vector3
var _stop_radius: float = 0.0
## The building a click walk heads for; &"" when not walking to one.
var _walk_building: StringName = &""
var _stuck_seconds: float = 0.0
var _sign: Label3D


static func create(hero: Hero) -> TownHero:
	var body := TownHero.new()
	body.name = "TownHero"
	body.hero_id = hero.instance_id
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# It bumps into buildings but is on no layer itself, so it never blocks a building pick.
	body.collision_layer = 0
	body.collision_mask = TownView.PICK_LAYER
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.9
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	body.add_child(shape)
	# A hero with no archetype is drawn as the knight; a truly unknown one warns in HeroModel.
	var archetype: String = "knight" if hero.def_id == Hero.NO_ARCHETYPE_DEF_ID else str(hero.def_id)
	body._model = HeroModel.build("ally", archetype)
	body._model.scale = Vector3.ONE * MODEL_SCALE
	body.add_child(body._model)
	body._animator = body._model.get_node("AnimationPlayer") as AnimationPlayer
	body.camera = Camera3D.new()
	body.camera.name = "FollowCamera"
	body.add_child(body.camera)
	body._place_camera()
	body._sign = sign_label()
	body.add_child(body._sign)
	return body


## The partner sign over a figure's head, "♥ Mara" (ig-m6o.2.2.1): hidden until it has text. Where a
## walker's meeting line shows, so the walker hides it while the line is up.
static func sign_label() -> Label3D:
	var label := Label3D.new()
	label.name = "Sign"
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.8, 0.85)
	label.position.y = 2.1
	label.visible = false
	return label


## Shows "♥ <partner>" over the body, or nothing for "".
func set_sign(text: String) -> void:
	_sign.text = text
	_sign.visible = not text.is_empty()


func _ready() -> void:
	_animator.play("Idle_A")


## Arrows steer the body, so the GUI must not also move focus with them: a later Enter or Space
## would press whatever button the walk left focused. Movement polls Input, which already has them.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if controls_enabled and key != null and key.physical_keycode in ARROW_KEYS:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if not controls_enabled or wheel == null or not wheel.pressed:
		return
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_zoom(zoom - ZOOM_STEP)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_zoom(zoom + ZOOM_STEP)
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var direction: Vector3 = _key_direction()
	if direction != Vector3.ZERO:
		# Steering by hand drops a click walk: the panel only opens on arrival.
		_walk_building = &""
	elif _walk_building != &"":
		direction = _walk_direction()
	velocity = direction * SPEED
	var before: float = _distance_to_target()
	move_and_slide()
	if bounds.has_area():
		global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
		global_position.z = clampf(global_position.z, bounds.position.y, bounds.end.y)
	if _walk_building != &"":
		_stuck_seconds = _stuck_seconds + delta if before - _distance_to_target() < SPEED * delta * 0.1 else 0.0
		if _stuck_seconds >= STUCK_SECONDS:
			_arrive()
	_animate(direction)


## Walks in a straight line until within stop_radius of target, then emits arrived(building_id).
func walk_to(target: Vector3, stop_radius: float, building_id: StringName) -> void:
	_target = target
	_stop_radius = stop_radius
	_walk_building = building_id
	_stuck_seconds = 0.0


func stop() -> void:
	_walk_building = &""
	velocity = Vector3.ZERO
	if _animator != null:
		_animate(Vector3.ZERO)


func is_walking() -> bool:
	return _walk_building != &""


func set_zoom(value: float) -> void:
	zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_place_camera()


func _place_camera() -> void:
	var offset: Vector3 = CAMERA_OFFSET * zoom
	camera.transform = Transform3D(Basis.looking_at(Vector3.UP * CAMERA_LOOK_HEIGHT - offset), offset)


## Camera-relative, so W is always away from the camera.
func _key_direction() -> Vector3:
	if not controls_enabled:
		return Vector3.ZERO
	var input := Vector2.ZERO
	for key: Key in MOVE_KEYS:
		if Input.is_physical_key_pressed(key):
			input += MOVE_KEYS[key]
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var right: Vector3 = Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var back: Vector3 = Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	return (right * input.x + back * input.y).normalized()


func _walk_direction() -> Vector3:
	var to_target: Vector3 = _target - global_position
	to_target.y = 0.0
	if to_target.length() <= _stop_radius:
		_arrive()
		return Vector3.ZERO
	return to_target.normalized()


func _distance_to_target() -> float:
	return Vector2(_target.x - global_position.x, _target.z - global_position.z).length()


func _arrive() -> void:
	var building_id: StringName = _walk_building
	_walk_building = &""
	arrived.emit(building_id)


func _animate(direction: Vector3) -> void:
	if direction != Vector3.ZERO:
		_model.rotation.y = atan2(direction.x, direction.z)
	var clip: StringName = &"Walking_A" if direction != Vector3.ZERO else &"Idle_A"
	if _animator.current_animation != clip:
		_animator.play(clip, 0.15)
