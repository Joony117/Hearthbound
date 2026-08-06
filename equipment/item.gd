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


func _init(p_def_id: StringName = NO_EQUIPMENT_DEF_ID, p_rank: int = 0) -> void:
	def_id = p_def_id
	rank = p_rank


func rank_label(balance: BalanceTable) -> String:
	return balance.rank_names[clampi(rank, 0, balance.rank_names.size() - 1)]


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
	return {"def_id": str(def_id), "rank": rank, "enhance_level": enhance_level}


static func from_dict(data: Dictionary) -> Item:
	var item := Item.new(NO_EQUIPMENT_DEF_ID, _int_field(data, "rank", 0))
	item.enhance_level = _int_field(data, "enhance_level", 0)
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


static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
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
	push_error("Invalid item %s: expected an integer, got '%s'." % [key, value])
	return fallback
