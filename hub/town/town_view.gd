class_name TownView
extends Node3D

## The 3D town as the hub's menu. A left click on a building names it; hub.gd decides what opens.
## It never touches panels or GameSession. The GUI stops clicks on panels before they get here.

signal building_selected(building_id: StringName)

const PICK_DISTANCE: float = 200.0
## town.tscn puts every building's Pick body on this layer alone, so other bodies (the avatar) never block a pick.
const PICK_LAYER: int = 2


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var building_id: StringName = building_at(click.position)
	if building_id != &"":
		get_viewport().set_input_as_handled()
		building_selected.emit(building_id)


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
