class_name TownView
extends Node3D

## The 3D town as the hub's menu. A left click on a building names it; hub.gd decides what opens.
## It never touches panels or GameSession. The GUI stops clicks on panels before they get here.
## With an embodied hero, a click walks the hero to the building and names it on arrival.

signal building_selected(building_id: StringName)
## While placing, a left click names the hex under it instead of a building. hub.gd places or refuses.
signal hex_selected(hex: Vector2i)

const BALANCE: BalanceTable = preload("res://balance.tres")
const HEX_TILE: PackedScene = preload("res://hub/town/models/hexagon/hex_grass.gltf")
## One scene per building type: Model, Label, Pick (a StaticBody3D on PICK_LAYER) and WorkSpot
## (a Marker3D where a keeper or worker will stand, ig-wgj.7).
const SCENES: Dictionary[StringName, PackedScene] = {
	&"SummoningCircle": preload("res://hub/town/buildings/summoning_circle.tscn"),
	&"Forge": preload("res://hub/town/buildings/forge.tscn"),
	&"TrainingHall": preload("res://hub/town/buildings/training_hall.tscn"),
	&"Sanctum": preload("res://hub/town/buildings/sanctum.tscn"),
	&"Reliquary": preload("res://hub/town/buildings/reliquary.tscn"),
	&"TownGate": preload("res://hub/town/buildings/town_gate.tscn"),
	&"Apothecary": preload("res://hub/town/buildings/apothecary.tscn"),
	TownRules.HOUSE: preload("res://hub/town/buildings/house.tscn"),
	TownRules.LUMBERMILL: preload("res://hub/town/buildings/lumbermill.tscn"),
}

const PICK_DISTANCE: float = 200.0
## Every building scene puts its Pick body on this layer alone, so other bodies (the avatar) never block a pick.
const PICK_LAYER: int = 2
## Where a new body stands, in town space: the open ground in front of the Training Hall.
const BODY_SPAWN: Vector3 = Vector3(0.0, 0.0, 5.0)
## Close enough to a building's centre to count as there. A body stopped on a corner of a 3 m
## building stands 2.12 + 0.4 (its radius) = 2.52 m out, so this covers every approach.
const ARRIVE_RADIUS: float = 2.8
## The body walks a 48 m square around the town's origin, keeping its 0.4 m radius inside it.
const WALK_HALF_EXTENT: float = 23.6
## Where a bonded partner stands without a House: beside the spawn, outside TownPartner.REARM_DISTANCE
## so the greeting waits for the player to walk over.
const PARTNER_SPAWN_OFFSET: Vector3 = Vector3(4.0, 0.0, -3.0)
## In front of its House, clear of the 4.5 m pick box.
const PARTNER_DOOR_OFFSET: Vector3 = Vector3(0.0, 0.0, 2.8)

## The embodied hero, or null when the town is seen from the overview camera.
var body: TownHero
## The body's bonded partner standing in town, or null.
var partner: TownPartner
## False while a building or the pause menu is open: no building click counts, and the body
## neither walks nor zooms.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if body != null:
			body.controls_enabled = value
## The building type being placed, or &"" when a click picks buildings.
var placing: StringName = &""
var _overview_camera: Camera3D
## Building id (halls included) -> its node, a direct child named by id so building_at and walk_to find it.
var _placed: Dictionary[String, Node3D] = {}


func _ready() -> void:
	var tile: Node = HEX_TILE.instantiate()
	var tile_mesh: Mesh = (tile.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh
	tile.free()
	var hexes: Array[Vector2i] = TownRules.map_hexes(BALANCE)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tile_mesh
	multimesh.instance_count = hexes.size()
	for index: int in hexes.size():
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * TownRules.MODEL_SCALE), TownRules.hex_to_world(hexes[index])))
	var ground := MultiMeshInstance3D.new()
	ground.name = "HexGround"
	ground.multimesh = multimesh
	add_child(ground)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not input_enabled:
		return
	if placing != &"":
		var hit: Variant = ground_point(click.position)
		if hit != null:
			get_viewport().set_input_as_handled()
			hex_selected.emit(TownRules.world_to_hex(hit as Vector3))
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


## Stands hero in town as the body's bonded partner, saying line on meeting; null (or no body)
## removes it. hub.gd picks who and what; the same hero again keeps its figure, so a refresh does
## not replay the greeting. It stands at its House if it has one, else beside the spawn.
func show_partner(hero: Hero, line: String) -> void:
	if partner != null and (hero == null or body == null or partner.hero_id != hero.instance_id):
		remove_child(partner)
		partner.queue_free()
		partner = null
	if hero == null or body == null:
		return
	if partner == null:
		partner = TownPartner.create(hero)
		add_child(partner)
	partner.line = line
	partner.follow(body)
	var house: Node3D = _placed.get(str(hero.home))
	partner.position = house.position + PARTNER_DOOR_OFFSET if house != null else BODY_SPAWN + PARTNER_SPAWN_OFFSET


## Spawns what is new in buildings (GameSession.town_buildings), stands each on its hex (a move) and
## frees what is gone. It only draws.
func show_buildings(buildings: Array[Dictionary]) -> void:
	var wanted: Dictionary[String, bool] = {}
	for building: Dictionary in buildings:
		var id: String = building["id"]
		wanted[id] = true
		var at: Vector3 = TownRules.hex_to_world(Vector2i(building["q"], building["r"]))
		if not _placed.has(id):
			_placed[id] = _spawn_building(id, StringName(building["type"]), at)
		_placed[id].position = at
	for id: String in _placed.keys():
		if not wanted.has(id):
			_placed[id].queue_free()
			_placed.erase(id)


## Positioned before it enters the tree, so its pick body registers where it stands: a pick in the
## same frame would miss a body moved after (its transform reaches physics only at the frame's end).
func _spawn_building(id: String, type: StringName, at: Vector3) -> Node3D:
	var node := SCENES[type].instantiate() as Node3D
	node.name = id
	node.position = at
	(node.get_node("Label") as Label3D).text = id.capitalize()
	add_child(node)
	return node


## Where the ray under screen_position meets the ground, in town space; null when it never does.
func ground_point(screen_position: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	return null if hit == null else to_local(hit as Vector3)


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
