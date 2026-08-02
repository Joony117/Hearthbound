extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var exit_code: int = _check_definition("res://equipment/defs/head.tres", EquipmentDefinition.Slot.HEAD, "Head", EquipmentDefinition.PrimaryStat.HP)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/chest.tres", EquipmentDefinition.Slot.CHEST, "Chest", EquipmentDefinition.PrimaryStat.DEF)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/legs.tres", EquipmentDefinition.Slot.LEGS, "Legs", EquipmentDefinition.PrimaryStat.HP)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/gloves.tres", EquipmentDefinition.Slot.GLOVES, "Gloves", EquipmentDefinition.PrimaryStat.ATK)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/boots.tres", EquipmentDefinition.Slot.BOOTS, "Boots", EquipmentDefinition.PrimaryStat.SPD)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/main_hand.tres", EquipmentDefinition.Slot.MAIN_HAND, "Main Hand", EquipmentDefinition.PrimaryStat.ATK)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/off_hand.tres", EquipmentDefinition.Slot.OFF_HAND, "Off Hand", EquipmentDefinition.PrimaryStat.DEF)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/necklace.tres", EquipmentDefinition.Slot.NECKLACE, "Necklace", EquipmentDefinition.PrimaryStat.CRIT_RATE)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/ring.tres", EquipmentDefinition.Slot.RING, "Ring", EquipmentDefinition.PrimaryStat.CRIT_DMG)
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_definition("res://equipment/defs/belt.tres", EquipmentDefinition.Slot.BELT, "Belt", EquipmentDefinition.PrimaryStat.SPD)
	if exit_code == 0:
		print("PASS: all fields of all ten equipment definitions match SYSTEMS.md.")
	quit(exit_code)


func _check_definition(resource_path: String, expected_slot: EquipmentDefinition.Slot, expected_display_name: String, expected_primary_stat: EquipmentDefinition.PrimaryStat) -> int:
	var definition: EquipmentDefinition = load(resource_path) as EquipmentDefinition
	if definition == null:
		return _fail("%s resource load" % resource_path, "EquipmentDefinition", "null")
	if definition.slot != expected_slot:
		return _fail("%s slot" % expected_display_name, str(expected_slot), str(definition.slot))
	if definition.display_name != expected_display_name:
		return _fail("%s display_name" % expected_display_name, expected_display_name, definition.display_name)
	if definition.primary_stat != expected_primary_stat:
		return _fail("%s primary_stat" % expected_display_name, str(expected_primary_stat), str(definition.primary_stat))
	return 0


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
