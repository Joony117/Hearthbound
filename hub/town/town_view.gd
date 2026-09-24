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
	TownRules.MINE: preload("res://hub/town/buildings/mine.tscn"),
	TownRules.FARM: preload("res://hub/town/buildings/farm.tscn"),
}

const PICK_DISTANCE: float = 200.0
## Every building scene puts its Pick body on this layer alone, so other bodies (the avatar) never block a pick.
const PICK_LAYER: int = 2
## Where a new body stands, in town space: the open ground in front of the Training Hall.
const BODY_SPAWN: Vector3 = Vector3(0.0, 0.0, 5.0)
## Close enough to a building's centre to count as there. A body stopped on a corner of a 3 m
## building stands 2.12 + 0.4 (its radius) = 2.52 m out, so this covers every approach.
const ARRIVE_RADIUS: float = 2.8
## Where a bonded partner stands without a House: beside the spawn, outside TownPartner.REARM_DISTANCE
## so the greeting waits for the player to walk over.
const PARTNER_SPAWN_OFFSET: Vector3 = Vector3(4.0, 0.0, -3.0)
## In front of its House, clear of the 4.5 m pick box.
const PARTNER_DOOR_OFFSET: Vector3 = Vector3(0.0, 0.0, 2.8)
## A walker this close to a WorkSpot stands at it.
const AT_SPOT: float = 0.05

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
## Keepers' and workers' figures by hero id (ig-6m2.6.1); show_walkers keeps them in step with hub.gd.
var walkers: Dictionary[String, TownWalker] = {}
## The walk graph (ig-6m2.6, the walkable area): one point per map hex centre, its id the hex's index
## in map_hexes, joined to its six neighbours. A hex with a building is disabled.
var _graph := AStar2D.new()
var _hexes: Array[Vector2i] = []
var _hex_ids: Dictionary[Vector2i, int] = {}
## Hex -> the id of the building on it.
var _occupied: Dictionary[Vector2i, String] = {}
var _walkers_shown: bool = false
## The hero who just stopped being the body and where it stood (town space), for the next show_walkers.
var _stepped_out: Dictionary = {}


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
		_graph.add_point(index, _flat(TownRules.hex_to_world(hexes[index])))
		_graph.set_point_disabled(index, _occupied.has(hexes[index]))
		_hex_ids[hexes[index]] = index
	_hexes = hexes
	for index: int in hexes.size():
		for step: Vector2i in TownRules.AXIAL_DIRECTIONS:
			var next: int = _hex_ids.get(hexes[index] + step, -1)
			if next > index:
				_graph.connect_points(index, next)
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
		_stepped_out = {"hero_id": body.hero_id, "at": to_local(standing)}
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
	var walk: Rect2 = walk_bounds()
	var corner: Vector3 = to_global(Vector3(walk.position.x, 0.0, walk.position.y))
	body.bounds = Rect2(Vector2(corner.x, corner.z), walk.size)
	add_child(body)
	body.global_position = standing
	body.camera.make_current()
	body.arrived.connect(building_selected.emit)


## Where the body may stand, as town-space x/z: the map's hex centres grown by one hex, so it reaches
## every hex a building or a partner can stand on (ig-6m2.9). Corners past the hex map are harmless ground.
static func walk_bounds() -> Rect2:
	var rect := Rect2()
	for hex: Vector2i in TownRules.map_hexes(BALANCE):
		var at: Vector3 = TownRules.hex_to_world(hex)
		rect = rect.expand(Vector2(at.x, at.z))
	return rect.grow(TownRules.HEX_SIZE)


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
	_update_graph(buildings)


## A place or a move changes which hexes hold a building: the graph follows, anyone on a hex that
## just got one steps onto free ground, and every figure re-plans from where it stands.
func _update_graph(buildings: Array[Dictionary]) -> void:
	var occupied: Dictionary[Vector2i, String] = {}
	for building: Dictionary in buildings:
		occupied[Vector2i(building["q"], building["r"])] = building["id"]
	if occupied == _occupied:
		return
	var fresh: Array[Vector2i] = []
	for hex: Vector2i in occupied:
		if _occupied.get(hex, "") != occupied[hex]:
			fresh.append(hex)
	_occupied = occupied
	for index: int in _hexes.size():
		_graph.set_point_disabled(index, _occupied.has(_hexes[index]))
	if body != null:
		var standing: Vector3 = to_local(body.global_position)
		if TownRules.world_to_hex(standing) in fresh:
			body.global_position = to_global(free_point(standing))
	for walker: TownWalker in walkers.values():
		# A station that is gone frees its figure on the next show_walkers.
		if _placed.has(str(walker.station)):
			_plan(walker, false)


## Draws each of heroes (hub.gd's keepers and workers in town) walking between its House door and its
## station's WorkSpot, and frees the figures of heroes no longer listed. It reads hero.station and
## hero.home only. A hero whose station and House are unchanged keeps its figure and its walk, so the
## 0.25 s pulse changes nothing. A new figure starts at work on the first show, where the body stood
## for the hero who just stepped out of it, and otherwise at the TownGate, walking in.
func show_walkers(heroes: Array[Hero]) -> void:
	var wanted: Dictionary[String, bool] = {}
	for hero: Hero in heroes:
		if not _placed.has(str(hero.station)):
			continue
		wanted[hero.instance_id] = true
		var walker: TownWalker = walkers.get(hero.instance_id)
		if walker != null and walker.station == hero.station and walker.home == hero.home:
			continue
		if walker == null:
			walker = TownWalker.create(hero)
			add_child(walker)
			walkers[hero.instance_id] = walker
			if _stepped_out.get("hero_id", "") == hero.instance_id:
				walker.position = _stepped_out["at"]
			elif _placed.has("TownGate"):
				walker.position = work_spot(&"TownGate")
		walker.station = hero.station
		walker.home = hero.home
		walker.heading_home = false
		_plan(walker, not _walkers_shown)
	for id: String in walkers.keys():
		if not wanted.has(id):
			remove_child(walkers[id])
			walkers[id].queue_free()
			walkers.erase(id)
	_walkers_shown = true
	_stepped_out = {}


## Gives walker its House <-> work loop and sends it from where it stands to where it is heading. No
## House, or no route either way: no loop, it goes to its work spot and works. first: already at work,
## a random way into its shift, so a reload neither streams everyone in nor sends them home together.
func _plan(walker: TownWalker, first: bool) -> void:
	var spot: Vector3 = work_spot(walker.station)
	walker.work_yaw = _yaw(spot, _placed[str(walker.station)].position)
	var house: StringName = walker.home if _placed.has(str(walker.home)) else Hero.NO_HOME
	var to_work := PackedVector3Array()
	var to_home := PackedVector3Array()
	if house != Hero.NO_HOME:
		walker.rest_yaw = _yaw(_placed[str(house)].position, work_spot(house))
		to_work = route(house, walker.station)
		to_home = route(walker.station, house)
	walker.set_loop(to_work, to_home)
	if not walker.has_loop():
		walker.heading_home = false
	if first:
		walker.work_at(spot, walker.rng.randf() * TownWalker.WORK_SECONDS)
		return
	var target: StringName = house if walker.heading_home else walker.station
	if not walker.is_walking() and walker.position.distance_to(work_spot(target)) < AT_SPOT:
		return
	var lead: PackedVector3Array = _lead(walker, target)
	if lead.is_empty():
		walker.work_at(spot, TownWalker.WORK_SECONDS)
	else:
		walker.walk(lead, TownWalker.REST if walker.heading_home else TownWalker.WORK)


## The walk from where walker stands to target's WorkSpot. At a building's WorkSpot it leaves through
## that building's approach hexes. Anywhere else on a building's hex (built over), or at a spot whose
## approach hexes are all taken, it first steps onto the nearest free ground.
func _lead(walker: TownWalker, target: StringName) -> PackedVector3Array:
	var at: Vector3 = walker.position
	var on: String = _occupied.get(TownRules.world_to_hex(at), "")
	if on == "":
		return route(at, target)
	if at.distance_to(work_spot(StringName(on))) < AT_SPOT:
		var out: PackedVector3Array = route(StringName(on), target)
		if not out.is_empty():
			return out
	# ponytail: a snap, not a walk, so a hero stepping out of the body beside a building jumps a few
	# metres; walk it off the hex if the jump shows in play.
	walker.position = free_point(at)
	return route(walker.position, target)


## The walk between two ends, in town space, or none (empty). An end is a placed building's id (its
## WorkSpot, reached only through its approach hexes) or a point on free ground (through its hex's
## centre). Between them it runs through free hex centres, so no leg crosses a building.
func route(from: Variant, to: Variant) -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_length: float = INF
	for start: Vector2i in _entries(from):
		for finish: Vector2i in _entries(to):
			var path := PackedVector3Array([_end_point(from)])
			for point: Vector2 in _graph.get_point_path(_hex_ids[start], _hex_ids[finish]):
				path.append(Vector3(point.x, 0.0, point.y))
			if path.size() == 1:
				continue
			path.append(_end_point(to))
			var length: float = 0.0
			for index: int in range(1, path.size()):
				length += path[index - 1].distance_to(path[index])
			if length < best_length:
				best = path
				best_length = length
	return best


## The centre of the free map hex nearest near (town space); ties go to the earlier hex in map_hexes.
func free_point(near: Vector3) -> Vector3:
	var best: Vector3 = near
	var best_distance: float = INF
	for hex: Vector2i in _hexes:
		if _occupied.has(hex):
			continue
		var centre: Vector3 = TownRules.hex_to_world(hex)
		var distance: float = _flat(centre).distance_squared_to(_flat(near))
		if distance < best_distance:
			best = centre
			best_distance = distance
	return best


## A placed building's WorkSpot marker, in town space.
func work_spot(id: StringName) -> Vector3:
	var building: Node3D = _placed[str(id)]
	return building.transform * (building.get_node("WorkSpot") as Node3D).position


## The two map neighbours of a placed building's hex nearest its WorkSpot, taken or not: the only way
## in or out of it. Ties go to the earlier hex in map_hexes.
func approach_hexes(id: StringName) -> Array[Vector2i]:
	var hex: Vector2i = TownRules.world_to_hex(_placed[str(id)].position)
	var spot: Vector2 = _flat(work_spot(id))
	var near: Array[Vector2i] = []
	for step: Vector2i in TownRules.AXIAL_DIRECTIONS:
		if _hex_ids.has(hex + step):
			near.append(hex + step)
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var to_a: float = spot.distance_to(_flat(TownRules.hex_to_world(a)))
		var to_b: float = spot.distance_to(_flat(TownRules.hex_to_world(b)))
		return to_a < to_b - 0.001 or (absf(to_a - to_b) <= 0.001 and _hex_ids[a] < _hex_ids[b]))
	near.resize(mini(2, near.size()))
	return near


## The hexes an end is entered from: a building's free approach hexes, or a free point's own hex.
func _entries(end: Variant) -> Array[Vector2i]:
	var entries: Array[Vector2i] = []
	if end is Vector3:
		var hex: Vector2i = TownRules.world_to_hex(end as Vector3)
		if _hex_ids.has(hex) and not _occupied.has(hex):
			entries.append(hex)
		return entries
	if not _placed.has(str(end)):
		return entries
	for hex: Vector2i in approach_hexes(StringName(end)):
		if not _occupied.has(hex):
			entries.append(hex)
	return entries


func _end_point(end: Variant) -> Vector3:
	return end as Vector3 if end is Vector3 else work_spot(StringName(end))


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


## The yaw that faces from towards to.
static func _yaw(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


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
