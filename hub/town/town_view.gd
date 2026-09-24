class_name TownView
extends Node3D

## The 3D town as the hub's menu. A left click on a building names it, and one on a hero in town
## names the hero; hub.gd decides what opens. It never touches panels or GameSession. The GUI stops
## clicks on panels before they get here. With an embodied hero, a click on a building walks the hero
## there and names it on arrival; a click on a hero names it at once.

signal building_selected(building_id: StringName)
## A left click on a walker (ig-6m2.6.2): keepers, workers, wanderers and the partner alike.
signal hero_selected(hero_id: String)
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
## A building under construction shows these in its Model's place, a quarter of its build time each
## (SYSTEMS.md § Stone and construction), as a "Stage" child at the hexagon scale.
const STAGES: Array[PackedScene] = [
	preload("res://hub/town/models/hexagon/building_scaffolding.gltf"),
	preload("res://hub/town/models/hexagon/building_stage_A.gltf"),
	preload("res://hub/town/models/hexagon/building_stage_B.gltf"),
	preload("res://hub/town/models/hexagon/building_stage_C.gltf"),
]

const PICK_DISTANCE: float = 200.0
## Every building scene puts its Pick body on this layer alone, so other bodies (the avatar) never block a pick.
const PICK_LAYER: int = 2
## Every walker's pick body is on this layer alone (layer 3, as a mask bit like PICK_LAYER). One ray
## looks at both, so a walker standing in front of its building takes the click. The body is on none.
const WALKER_PICK_LAYER: int = 4
## Wanderers shown at once; keepers, workers and the partner always show on top of it.
## ⚠️ PROVISIONAL — measured on one RTX 4090 only: 830 fps average at 16 wanderers, 23 figures
## (ig-6m2.6.2 notes) · Settled by: the same run on weaker hardware or a fuller town.
const AMBIENT_HERO_CAP: int = 16
## A wanderer with a House ends every HOME_EVERY-th trip at its door.
const HOME_EVERY: int = 4
## Where a new body stands, in town space: the open ground in front of the Training Hall.
const BODY_SPAWN: Vector3 = Vector3(0.0, 0.0, 5.0)
## Close enough to a building's centre to count as there. A body stopped on a corner of a 3 m
## building stands 2.12 + 0.4 (its radius) = 2.52 m out, so this covers every approach.
const ARRIVE_RADIUS: float = 2.8
## A walker this close to a WorkSpot stands at it.
const AT_SPOT: float = 0.05
## The overview camera (ig-6m2.8.1). Presentation only: tune by screenshot. hub.tscn sets the start
## framing and the pitch; these only bound how far the player moves it.
const OVERVIEW_HEIGHT_MIN: float = 4.5
const OVERVIEW_HEIGHT_MAX: float = 27.0
## Metres a second at the start height (9 m); faster higher up, so a screen crosses in the same time.
const OVERVIEW_PAN_SPEED: float = 20.0
## Each wheel step moves this share of the distance to the focus.
const OVERVIEW_ZOOM_STEP: float = 0.1
## Multiplies the shared atlas on the ground only, towards a natural green.
const GRASS_TINT: Color = Color(0.72, 0.85, 0.62)

## The embodied hero, or null when the town is seen from the overview camera.
var body: TownHero
## True from a right press over bare town to its release: only such a drag grabs the ground.
var _grabbing: bool = false
## The body's bonded partner's walker, or null (no body, no partner, or not shown).
var partner: TownWalker:
	get:
		return walkers.get(_partner_id) if body != null else null
## False while a building or the pause menu is open: no building click counts, and the body
## neither walks nor zooms.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		_grabbing = false
		if body != null:
			body.controls_enabled = value
## The building type being placed, or &"" when a click picks buildings.
var placing: StringName = &""
var _overview_camera: Camera3D
## Building id (halls included) -> its node, a direct child named by id so building_at and walk_to find it.
var _placed: Dictionary[String, Node3D] = {}
## Every in-town hero's figure by hero id: keepers and workers (ig-6m2.6.1), wanderers up to the cap
## and the partner (ig-6m2.6.2). show_walkers keeps them in step with hub.gd.
var walkers: Dictionary[String, TownWalker] = {}
## The walk graph (ig-6m2.6, the walkable area): one point per map hex centre, its id the hex's index
## in map_hexes, joined to its six neighbours. A hex with a building is disabled.
var _graph := AStar2D.new()
var _hexes: Array[Vector2i] = []
var _hex_ids: Dictionary[Vector2i, int] = {}
## Hex -> the id of the building on it.
var _occupied: Dictionary[Vector2i, String] = {}
## Where wanderers go: the free hexes that touch a building (the streets, not the empty map edge).
var _streets: Array[Vector2i] = []
## A hall's free approach hex -> the hall: a wanderer there uses its stall.
var _stalls: Dictionary[Vector2i, String] = {}
var _partner_id: String = ""
var _partner_line: String = ""
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
	var grass := tile_mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	grass.albedo_color = GRASS_TINT
	ground.material_override = grass
	add_child(ground)


func _process(delta: float) -> void:
	if body != null or not input_enabled:
		return
	var input := Vector2.ZERO
	for key: Key in TownHero.MOVE_KEYS:
		if Input.is_physical_key_pressed(key):
			input += TownHero.MOVE_KEYS[key]
	var camera: Camera3D = get_viewport().get_camera_3d()
	if input == Vector2.ZERO or camera == null:
		return
	var right: Vector3 = Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var back: Vector3 = Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	var height: float = camera.global_position.y - global_position.y
	pan_overview((right * input.x + back * input.y).normalized() * OVERVIEW_PAN_SPEED * height / 9.0 * delta)


## Arrows pan the overview, so the GUI must not also move focus with them (as TownHero does for
## the body). _process polls Input, which already has them.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if body == null and input_enabled and key != null and key.physical_keycode in TownHero.ARROW_KEYS:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if body == null and input_enabled and _overview_input(event):
		get_viewport().set_input_as_handled()
		return
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
	var picked: Node = _pick(click.position)
	if picked is TownWalker:
		get_viewport().set_input_as_handled()
		hero_selected.emit((picked as TownWalker).hero_id)
		return
	var building_id: StringName = building_at(click.position)
	if building_id == &"":
		return
	get_viewport().set_input_as_handled()
	if body == null:
		building_selected.emit(building_id)
	else:
		body.walk_to((get_node(NodePath(building_id)) as Node3D).global_position, ARRIVE_RADIUS, building_id)


## The wheel zooms and a right drag grabs the ground; true when event was one of them. Both start
## only over bare town: a wheel or a right press over any control (even a PASS gap) arrives here too.
func _overview_input(event: InputEvent) -> bool:
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_RIGHT:
		_grabbing = press.pressed and get_viewport().gui_get_hovered_control() == null
		return true
	var drag := event as InputEventMouseMotion
	if drag != null and _grabbing and (drag.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		var before: Variant = ground_point(drag.position - drag.relative)
		var now: Variant = ground_point(drag.position)
		if before != null and now != null:
			pan_overview((before as Vector3) - (now as Vector3))
		return true
	var wheel := press
	# A wheel over any control still arrives here (mouse_force_pass_scroll_events), so it zooms only
	# over bare town: the UI root ignores the mouse there, so nothing is hovered.
	if wheel == null or not wheel.pressed or get_viewport().gui_get_hovered_control() != null:
		return false
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_overview(1)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_overview(-1)
	else:
		return false
	return true


## Moves the overview camera by offset on the ground (town space, x and z only). No-op with a body.
func pan_overview(offset: Vector3) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if body != null or camera == null:
		return
	camera.global_position += global_basis * Vector3(offset.x, 0.0, offset.z)
	_clamp_overview(camera)


## Moves the overview camera along its view direction, OVERVIEW_ZOOM_STEP of the way to the focus a
## step; positive steps zoom in. No-op with a body.
func zoom_overview(steps: int) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if body != null or camera == null:
		return
	var forward: Vector3 = -camera.global_basis.z
	for step: int in absi(steps):
		var focus: Vector3 = _focus(camera)
		camera.global_position += forward * camera.global_position.distance_to(focus) * OVERVIEW_ZOOM_STEP * signi(steps)
	_clamp_overview(camera)


## Where the camera looks at the ground, in global space. The pitch always looks down.
func _focus(camera: Camera3D) -> Vector3:
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(camera.global_position, -camera.global_basis.z)
	return camera.global_position if hit == null else hit as Vector3


## Height within the bounds (sliding along the view, so the focus stays), then the focus within the
## map extent of the town origin (sliding on the ground, so the height stays).
func _clamp_overview(camera: Camera3D) -> void:
	var forward: Vector3 = -camera.global_basis.z
	var height: float = camera.global_position.y - global_position.y
	var bounded: float = clampf(height, OVERVIEW_HEIGHT_MIN, OVERVIEW_HEIGHT_MAX)
	if bounded != height and forward.y < 0.0:
		camera.global_position += forward * (height - bounded) / -forward.y
	var focus: Vector3 = to_local(_focus(camera))
	var flat := Vector2(focus.x, focus.z)
	var extent: float = BALANCE.town_map_radius * TownRules.HEX_SIZE * sqrt(3.0)
	if flat.length() > extent:
		var back: Vector2 = flat.limit_length(extent) - flat
		camera.global_position += global_basis * Vector3(back.x, 0.0, back.y)


## Shows this hero walking the town with its follow camera, or none (null) for the overview.
## The same hero again is a no-op, so roster refreshes do not reset where it stands.
func embody(hero: Hero) -> void:
	if body != null and hero != null and body.hero_id == hero.instance_id:
		return
	_grabbing = false
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


## Makes hero the body's bonded partner, saying line on meeting; null (or no body) makes no one.
## hub.gd picks who and what, and lists the partner in show_walkers like anyone in town: its own
## walker greets, and walks, works or wanders by its role. The same hero again keeps its greeting
## state, so a refresh does not replay it.
func show_partner(hero: Hero, line: String) -> void:
	var id: String = "" if hero == null or body == null else hero.instance_id
	if id != _partner_id and walkers.has(_partner_id):
		walkers[_partner_id].follow(null)
	_partner_id = id
	_partner_line = line
	_attach_partner()


func _attach_partner() -> void:
	var walker: TownWalker = walkers.get(_partner_id)
	if walker != null:
		walker.line = _partner_line
		walker.follow(body)


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
		_show_stage(_placed[id], building)
	for id: String in _placed.keys():
		if not wanted.has(id):
			_placed[id].queue_free()
			_placed.erase(id)
	_update_graph(buildings)


## The stage model for how much of building is built, or its own Model once it is finished. Runs on
## every pulse, so it swaps the Stage node only when the stage changes.
func _show_stage(node: Node3D, building: Dictionary) -> void:
	var stage: int = -1
	if building.has("build_remaining"):
		var done: float = 1.0 - float(building["build_remaining"]) / TownRules.build_seconds(StringName(building["type"]), BALANCE)
		stage = clampi(floori(done * STAGES.size()), 0, STAGES.size() - 1)
	var shown: Node3D = node.get_node_or_null("Stage") as Node3D
	if (-1 if shown == null else int(shown.get_meta(&"stage"))) == stage:
		return
	if shown != null:
		node.remove_child(shown)
		shown.queue_free()
	(node.get_node("Model") as Node3D).visible = stage < 0
	if stage < 0:
		return
	var model := STAGES[stage].instantiate() as Node3D
	model.name = "Stage"
	model.scale = Vector3.ONE * TownRules.MODEL_SCALE
	model.set_meta(&"stage", stage)
	node.add_child(model)


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
	_streets.clear()
	for hex: Vector2i in _hexes:
		if _occupied.has(hex):
			continue
		for step: Vector2i in TownRules.AXIAL_DIRECTIONS:
			if _occupied.has(hex + step):
				_streets.append(hex)
				break
	_stalls.clear()
	for id: String in _occupied.values():
		if TownRules.type_of(StringName(id)) != &"":
			continue
		for hex: Vector2i in approach_hexes(StringName(id)):
			if not _occupied.has(hex) and not _stalls.has(hex):
				_stalls[hex] = id
	if body != null:
		var standing: Vector3 = to_local(body.global_position)
		if TownRules.world_to_hex(standing) in fresh:
			body.global_position = to_global(free_point(standing))
	for walker: TownWalker in walkers.values():
		# A station that is gone frees its figure on the next show_walkers.
		if _placed.has(str(walker.station)):
			_plan(walker, false)
		elif walker.station == Hero.NO_STATION:
			_wander(walker, false)


## Draws heroes (hub.gd's in-town heroes, in pick order) and frees the figures of heroes no longer
## listed. A hero whose station is placed walks between its House door and the station's WorkSpot;
## any other wanders, the first AMBIENT_HERO_CAP of them in list order, and the partner always. It
## reads hero.station and hero.home only. A hero whose station and House are unchanged keeps its
## figure and its walk, so the 0.25 s pulse changes nothing. A new figure starts at work (or on a
## street) on the first show, where the body stood for the hero who just stepped out of it, and
## otherwise at the TownGate, walking in. A hero whose role changes re-plans from where it stands.
func show_walkers(heroes: Array[Hero]) -> void:
	var wanted: Dictionary[String, bool] = {}
	var wanderers: int = 0
	for hero: Hero in heroes:
		var works: bool = _placed.has(str(hero.station))
		if not works and hero.instance_id != _partner_id:
			if wanderers >= AMBIENT_HERO_CAP:
				continue
			wanderers += 1
		wanted[hero.instance_id] = true
		var station: StringName = hero.station if works else Hero.NO_STATION
		var walker: TownWalker = walkers.get(hero.instance_id)
		if walker != null and walker.station == station and walker.home == hero.home:
			continue
		if walker == null:
			walker = TownWalker.create(hero)
			walker.planner = _wander.bind(walker, false)
			add_child(walker)
			walkers[hero.instance_id] = walker
			if _stepped_out.get("hero_id", "") == hero.instance_id:
				walker.position = _stepped_out["at"]
			elif _placed.has("TownGate"):
				walker.position = work_spot(&"TownGate")
		walker.station = station
		walker.home = hero.home
		walker.heading_home = false
		if works:
			_plan(walker, not _walkers_shown)
		else:
			_wander(walker, not _walkers_shown and _stepped_out.get("hero_id", "") != hero.instance_id)
	for id: String in walkers.keys():
		if not wanted.has(id):
			remove_child(walkers[id])
			walkers[id].queue_free()
			walkers.erase(id)
	_walkers_shown = true
	_stepped_out = {}
	_attach_partner()


## A wanderer's next trip from where it stands: to a street hex its RNG picks, where it uses the stall
## (a hall's approach hex: it faces the hall and plays Interact) or stands (Idle_B); every HOME_EVERY-th
## trip ends at its House door instead (Idle_A). first: already out on a street, a random way into its
## linger. No street, or no way there: it stands where it is and tries again after a linger.
func _wander(walker: TownWalker, first: bool) -> void:
	walker.trips += 1
	if not first and _placed.has(str(walker.home)) and walker.trips % HOME_EVERY == 0:
		var home_lead: PackedVector3Array = _lead(walker, walker.home)
		if not home_lead.is_empty():
			walker.wander(home_lead, &"Idle_A", _yaw(_placed[str(walker.home)].position, work_spot(walker.home)))
			return
	if _streets.is_empty():
		walker.linger_at(walker.position, &"Idle_B", NAN, TownWalker.LINGER_SECONDS)
		return
	var hex: Vector2i = _streets[walker.rng.randi() % _streets.size()]
	var at: Vector3 = TownRules.hex_to_world(hex)
	var hall: String = _stalls.get(hex, "")
	var clip: StringName = &"Interact" if hall != "" else &"Idle_B"
	var yaw: float = _yaw(at, _placed[hall].position) if hall != "" else NAN
	if first:
		walker.linger_at(at, clip, yaw, walker.rng.randf() * TownWalker.LINGER_SECONDS)
		return
	var lead: PackedVector3Array = _lead(walker, at)
	if lead.is_empty():
		walker.linger_at(walker.position, &"Idle_B", NAN, TownWalker.LINGER_SECONDS)
	else:
		walker.wander(lead, clip, yaw)


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


## The walk from where walker stands to target (a building's WorkSpot, or a point on free ground). At a
## building's WorkSpot it leaves through that building's approach hexes. Anywhere else on a building's
## hex (built over), or at a spot whose approach hexes are all taken, it first steps onto the nearest
## free ground.
func _lead(walker: TownWalker, target: Variant) -> PackedVector3Array:
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


## The building a click at screen_position names, or &"" (nothing, or a walker in front of it). A
## building's id is its node name.
func building_at(screen_position: Vector2) -> StringName:
	var picked: Node = _pick(screen_position)
	return &"" if picked == null or picked is TownWalker else StringName(picked.name)


## What a click at screen_position lands on: the nearest building or walker under it (the owner of the
## pick body, which is a direct child of it), or null. One ray over both pick layers. Only the town's
## own bodies count, so nothing else in the world can name one.
func _pick(screen_position: Vector2) -> Node:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_position) * PICK_DISTANCE, PICK_LAYER | WALKER_PICK_LAYER)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not is_ancestor_of(hit["collider"] as Node):
		return null
	return (hit["collider"] as Node).get_parent()
