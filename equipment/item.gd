class_name Item
extends RefCounted
## Runtime equipment instance.
##
## Runtime state points at shared EquipmentDefinition data by def_id per ARCHITECTURE.md rule 3.

const NO_EQUIPMENT_DEF_ID: StringName = &""
const DEF_PATH_TEMPLATE: String = "res://equipment/defs/%s.tres"

var def_id: StringName
var rank: int
var enhance_level: int = 0
var instance_id: String
var favorite: bool = false


func _init(p_def_id: StringName = NO_EQUIPMENT_DEF_ID, p_rank: int = 0) -> void:
	def_id = p_def_id
	rank = p_rank
	instance_id = new_instance_id()


## Public because Hero uses the same serialized identity format without adding a utility layer.
static func new_instance_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


## Parts a salvage pays, per docs/SYSTEMS.md, Base buildings. roundi(), never int() - truncation
## makes the Forge bonus yield literally zero on an unenhanced drop, the commonest salvage there is.
static func compute_salvage_yield(item: Item, forge_level: int, balance: BalanceTable) -> int:
	var enhance_level: int = clamped_enhance_level(item, balance)
	var clamped_forge_level: int = clampi(forge_level, 0, balance.summoning_circle_level_cap)
	return roundi((3 + enhance_level) * (1.0 + balance.forge_salvage_yield_bonus * clamped_forge_level))


## The highest enhance_level a Forge at this level permits (docs/SYSTEMS.md, Enhancement). Level 0
## returns 0, so a fresh save cannot enhance at all until the Forge is built. This bounds *gaining*
## a level; clamped_enhance_level() bounds *trusting* one an item already carries, and the two are
## deliberately different numbers - see docs/TASKS-DONE.md P2-07d.
static func compute_enhance_cap(forge_level: int, balance: BalanceTable) -> int:
	var clamped_forge_level: int = clampi(forge_level, 0, balance.summoning_circle_level_cap)
	return mini(balance.forge_enhance_cap_max, clamped_forge_level * balance.forge_enhance_cap_per_level)


## Public for the same reason int_field() is: GameSession.enhance_item needs the clamped level to
## price the upgrade and to write the new one, and a save can carry any integer at all.
static func clamped_enhance_level(item: Item, balance: BalanceTable) -> int:
	return clampi(item.enhance_level, 0, balance.forge_enhance_cap_max)


static func compute_enhance_cost(item: Item, balance: BalanceTable) -> int:
	return compute_enhance_cost_for_level(clamped_enhance_level(item, balance), balance)


static func compute_enhance_cost_for_level(level: int, balance: BalanceTable) -> int:
	return 2 + clampi(level, 0, balance.forge_enhance_cap_max)


## The fraction one item contributes to its primary stat (docs/SYSTEMS.md, Primary stat magnitude).
## Hero.compute_final_stats feeds it into equip_pct for the eight non-crit slots and adds it flat for
## necklace/ring; the hub tooltip displays it. One function, so a displayed magnitude cannot drift
## from the one combat applies - the preview-disagrees-with-payout shape P2-07e and P2-12 both fix.
static func compute_stat_magnitude(item: Item, definition: EquipmentDefinition, balance: BalanceTable) -> float:
	var per_rank_table: Array[float] = (
		balance.equip_pct_per_rank
		if definition.primary_stat < EquipmentDefinition.PrimaryStat.CRIT_RATE
		else balance.equip_crit_pct_per_rank
	)
	var rank_index: int = clampi(item.rank, 0, per_rank_table.size() - 1)
	var enhance_multiplier: float = 1.0 + balance.enhance_pct_per_level * clamped_enhance_level(item, balance)
	return per_rank_table[rank_index] * enhance_multiplier


## Applies the deterministic part of Damaged; the caller owns the independent random roll.
static func apply_damaged(item: Item, balance: BalanceTable) -> void:
	var enhance_level: int = clamped_enhance_level(item, balance)
	if enhance_level > 0:
		item.enhance_level = floori(float(enhance_level) / 2.0)
	else:
		var rank: int = clampi(item.rank, 0, balance.rank_names.size() - 1)
		item.rank = maxi(rank - 1, 0) if rank > 0 else rank


static func definition_for(p_def_id: StringName) -> EquipmentDefinition:
	var path: String = DEF_PATH_TEMPLATE % str(p_def_id)
	if not ResourceLoader.exists(path):
		push_error("Missing EquipmentDefinition for def_id '%s' at %s." % [p_def_id, path])
		return null
	var definition: EquipmentDefinition = ResourceLoader.load(path) as EquipmentDefinition
	if definition == null:
		push_error("Resource for def_id '%s' is not an EquipmentDefinition: %s." % [p_def_id, path])
	return definition


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"favorite": favorite,
		"def_id": str(def_id),
		"rank": rank,
		"enhance_level": enhance_level,
	}


static func from_dict(data: Dictionary) -> Item:
	var item := Item.new(NO_EQUIPMENT_DEF_ID, int_field(data, "rank", 0))
	item.enhance_level = int_field(data, "enhance_level", 0)
	var raw_instance_id: Variant = data.get("instance_id")
	if raw_instance_id is String and not (raw_instance_id as String).is_empty():
		item.instance_id = raw_instance_id as String
	elif raw_instance_id != null:
		push_error("Invalid item instance_id: expected a non-empty String.")
	var raw_favorite: Variant = data.get("favorite")
	if raw_favorite is bool:
		item.favorite = raw_favorite as bool
	elif raw_favorite != null:
		push_error("Invalid item favorite: expected bool, got %s." % type_string(typeof(raw_favorite)))
	if not data.has("def_id"):
		# No save predates this field - Item ships with it. A missing key means a corrupt or
		# hand-edited entry, and empty keeps it inert rather than resolving to a wrong slot.
		return item
	# Save-file fields remain Variant until their types are validated.
	var raw_def_id: Variant = data["def_id"]
	if raw_def_id is String:
		item.def_id = StringName(raw_def_id as String)
	else:
		push_error("Invalid item def_id: expected String, got %s." % type_string(typeof(raw_def_id)))
	return item


## Scalar analogue of GameSession._array_field(): Dictionary.get()'s default only applies to a
## *missing* key, so an explicit "rank": null from a hand-edited save reaches int() and throws.
## Public because Hero.from_dict decodes the same untrusted shape; the project layout has no
## home for a save-decode util, and Hero already depends on Item.
static func int_field(data: Dictionary, key: String, fallback: int, subject: String = "item") -> int:
	# Save-file fields remain Variant until their types are validated.
	var value: Variant = data.get(key)
	if value == null:
		return fallback
	if value is int:
		return value as int
	if value is float:
		var float_value: float = value as float
		if is_finite(float_value) and float_value == floorf(float_value):
			return int(float_value)
	push_error("Invalid %s %s: expected an integer, got '%s'." % [subject, key, value])
	return fallback


static func float_field(data: Dictionary, key: String, fallback: float, subject: String = "item") -> float:
	# Save-file fields remain Variant until their types are validated.
	var value: Variant = data.get(key)
	if value == null:
		return fallback
	if value is int or value is float:
		var number: float = float(value)
		if is_finite(number):
			return number
	push_error("Invalid %s %s: expected a finite number, got '%s'." % [subject, key, value])
	return fallback
