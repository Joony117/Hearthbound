class_name TownView
extends Node3D

## The 3D town as the hub's menu. A left click on a building names it; hub.gd decides what opens.
## It never touches panels or GameSession. The GUI stops clicks on panels before they get here.
## With an embodied hero, a click walks the hero to the building and names it on arrival.

signal building_selected(building_id: StringName)

const PICK_DISTANCE: float = 200.0
## town.tscn puts every building's Pick body on this layer alone, so other bodies (the avatar) never block a pick.
const PICK_LAYER: int = 2
## Where a new body stands, in town space: the open ground in front of the Training Hall.
const BODY_SPAWN: Vector3 = Vector3(0.0, 0.0, 5.0)
## Close enough to a building's centre to count as there. A body stopped on a corner of a 3 m
## building stands 2.12 + 0.4 (its radius) = 2.52 m out, so this covers every approach.
const ARRIVE_RADIUS: float = 2.8
## hub.tscn's Ground is a 48 m square at the town's origin; the body keeps its 0.4 m radius on it.
const WALK_HALF_EXTENT: float = 23.6

## The embodied hero, or null when the town is seen from the overview camera.
var body: TownHero
## False while a building or the pause menu is open: no building click counts, and the body
## neither walks nor zooms.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if body != null:
			body.controls_enabled = value
var _overview_camera: Camera3D


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not input_enabled:
		return
	var building_id: StringName = building_at(click.position)
	if building_id == &"":
		return
	get_viewport().set_input_as_handled()
	if body == null:
		building_selected.emit(building_id)
	else:
		body.walk_to((get_node(NodePath(building_id)) as Node3D).global_position, ARRIVE_RADIUS, building_id)


## Shows this hero walking the town with its follow camera, or none (null) for the overview.
## The same hero again is a no-op, so roster refreshes do not reset where it stands.
func embody(hero: Hero) -> void:
	if body != null and hero != null and body.hero_id == hero.instance_id:
		return
	var standing: Vector3 = to_global(BODY_SPAWN)
	if body != null:
		standing = body.global_position
		remove_child(body)
		body.queue_free()
		body = null
	elif hero != null:
		_overview_camera = get_viewport().get_camera_3d()
	if hero == null:
		if is_instance_valid(_overview_camera):
			_overview_camera.make_current()
		return
	body = TownHero.create(hero)
	body.controls_enabled = input_enabled
	var corner: Vector3 = to_global(Vector3(-WALK_HALF_EXTENT, 0.0, -WALK_HALF_EXTENT))
	body.bounds = Rect2(corner.x, corner.z, WALK_HALF_EXTENT * 2.0, WALK_HALF_EXTENT * 2.0)
	add_child(body)
	body.global_position = standing
	body.camera.make_current()
	body.arrived.connect(building_selected.emit)


## A building's id is its node name; its pick body is a direct child of it. Only the town's own
## bodies count, so nothing else in the world can name a building.
func building_at(screen_position: Vector2) -> StringName:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return &""
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_position) * PICK_DISTANCE, PICK_LAYER)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not is_ancestor_of(hit["collider"] as Node):
		return &""
	return (hit["collider"] as Node).get_parent().name
