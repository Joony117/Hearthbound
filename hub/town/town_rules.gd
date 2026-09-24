class_name TownRules
extends RefCounted
## The town builder's rules as pure functions (DECISIONS.md 2026-09-23, the town builder, item 7):
## hex math, whether a hex is free, what placing costs, and what a tick makes. GameSession calls
## these and refuses there; the town view only draws the result. Nothing here touches the roster.
##
## Hexes are pointy-top axial (q, r) Vector2i. A placed building is {id, type, q, r}: id and type
## are Strings, q and r ints, exactly as saved.

## Hexagon pack models are staged at x3.0 (ig-wgj.3's measurement).
const MODEL_SCALE: float = 3.0
## hex_grass.gltf measured from its accessor bounds: pointy-top, 2.0 across the flats, 2.3094 from
## point to point, top face at y 0 and 1.0 deep. At x3.0 a tile is 6 m across the flats, so this
## centre-to-corner size is 3.4641 m.
const HEX_SIZE: float = 1.1547 * MODEL_SCALE
const HOUSE: StringName = &"House"
const LUMBERMILL: StringName = &"Lumbermill"
const TYPES: Array[StringName] = [HOUSE, LUMBERMILL]
## Types that make a resource. The Mine and the Farm join when their slices add them.
const PRODUCERS: Array[StringName] = [LUMBERMILL]
## The seven authored halls in hub/town/town.tscn stand on these hexes, which are never free.
## Slice 2 (ig-6m2.2) moves them into the placed list.
const HALL_HEXES: Dictionary[StringName, Vector2i] = {
	&"SummoningCircle": Vector2i(-2, 0),
	&"Forge": Vector2i(-1, 0),
	&"TrainingHall": Vector2i(0, 0),
	&"Sanctum": Vector2i(1, 0),
	&"Reliquary": Vector2i(2, 0),
	&"TownGate": Vector2i(0, -2),
	&"Apothecary": Vector2i(2, -2),
}


static func hex_to_world(hex: Vector2i) -> Vector3:
	return Vector3(HEX_SIZE * sqrt(3.0) * (hex.x + hex.y / 2.0), 0.0, HEX_SIZE * 1.5 * hex.y)


## The hex under a town-space point (y ignored), by cube rounding.
static func world_to_hex(point: Vector3) -> Vector2i:
	var q: float = (sqrt(3.0) / 3.0 * point.x - point.z / 3.0) / HEX_SIZE
	var r: float = (2.0 / 3.0 * point.z) / HEX_SIZE
	var s: float = -q - r
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)
	if absf(rq - q) > absf(rr - r) and absf(rq - q) > absf(rs - s):
		rq = -rr - rs
	elif absf(rr - r) > absf(rs - s):
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func ring_distance(hex: Vector2i) -> int:
	return (absi(hex.x) + absi(hex.y) + absi(hex.x + hex.y)) / 2


static func map_hexes(balance: BalanceTable) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	var radius: int = balance.town_map_radius
	for q: int in range(-radius, radius + 1):
		for r: int in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			hexes.append(Vector2i(q, r))
	return hexes


## Wood a type costs to place; -1 for a type this slice does not know. The first of each producer
## is free (SYSTEMS.md § The first of each producer is free), so the town can never lock itself out.
static func wood_cost(type: StringName, buildings: Array[Dictionary], balance: BalanceTable) -> int:
	if type in PRODUCERS and not buildings.any(func(building: Dictionary) -> bool: return building["type"] == String(type)):
		return 0
	match type:
		HOUSE:
			return balance.house_wood_cost
		LUMBERMILL:
			return balance.lumbermill_wood_cost
	return -1


## Worker slots a type offers; 0 for a building that is not a workplace.
static func worker_slots(type: StringName, balance: BalanceTable) -> int:
	return balance.lumbermill_worker_slots if type == LUMBERMILL else 0


static func new_id(type: StringName, number: int) -> String:
	return "%s_%d" % [type, number]


## The type a placed id names ("Lumbermill_3" -> Lumbermill), or &"" for anything else, halls included.
## The number must be exactly what new_id writes: positive, no sign, no leading zero.
static func type_of(id: StringName) -> StringName:
	var text := String(id)
	var type := StringName(text.get_slice("_", 0))
	var number: String = text.get_slice("_", 1)
	if type not in TYPES or text.get_slice_count("_") != 2 or not number.is_valid_int() or str(number.to_int()) != number or number.to_int() < 1:
		return &""
	return type


static func is_workplace_id(id: StringName) -> bool:
	return worker_slots(type_of(id), preload("res://balance.tres")) > 0


## Why a building cannot go on hex; "" when the hex is free.
static func hex_refusal(hex: Vector2i, buildings: Array[Dictionary], balance: BalanceTable) -> String:
	if ring_distance(hex) > balance.town_map_radius:
		return "That hex is off the map."
	for hall: StringName in HALL_HEXES:
		if HALL_HEXES[hall] == hex:
			return "The %s stands there." % String(hall).capitalize()
	for building: Dictionary in buildings:
		if Vector2i(building["q"], building["r"]) == hex:
			return "%s stands there." % String(building["id"]).capitalize()
	return ""


## The exact plan place_building applies: {valid, reason, cost, id}.
static func place_plan(type: StringName, hex: Vector2i, buildings: Array[Dictionary], wood: float, next_id: int, balance: BalanceTable) -> Dictionary:
	var cost: int = wood_cost(type, buildings, balance)
	var plan: Dictionary = {"valid": false, "reason": "", "cost": maxi(cost, 0), "id": new_id(type, next_id)}
	if cost < 0:
		plan["reason"] = "Nothing called '%s' can be built." % type
		return plan
	plan["reason"] = hex_refusal(hex, buildings, balance)
	if plan["reason"] == "" and wood < cost:
		plan["reason"] = "A %s costs %d wood; you have %d." % [type, cost, floori(wood)]
	plan["valid"] = plan["reason"] == ""
	return plan


## Wood made over delta_seconds by this many Lumbermill workers who are home.
static func wood_made(workers_home: int, delta_seconds: float, balance: BalanceTable) -> float:
	return balance.wood_per_worker_minute * workers_home * delta_seconds / 60.0
