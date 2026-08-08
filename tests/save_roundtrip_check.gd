extends SceneTree

const FIRST_HERO_NAME := "Roundtrip Aster"
const FIRST_HERO_RANK := 2
const FIRST_HERO_DEF_ID := &"rogue"
const FIRST_HERO_LEVEL := 4
const FIRST_HERO_XP := 17
const SECOND_HERO_NAME := "Roundtrip Brann"
const SECOND_HERO_RANK := 6
const SECOND_HERO_DEF_ID := &"cleric"
const PREEXISTING_HERO_NAME := "Preexisting Cyra"
const PREEXISTING_HERO_RANK := 4
const MALFORMED_HERO_NAME := "Malformed Dain"
const MALFORMED_HERO_RANK := 5
const DOOMED_ITEM_DEF_ID := &"ring"
const DOOMED_ITEM_RANK := 3
const SALVAGED_ITEM_RANK := 5
const ENHANCED_ITEM_DEF_ID := &"head"
const ENHANCED_ITEM_RANK := 4
const ENHANCED_ITEM_LEVEL := 3
const INVENTORY_ITEM_DEF_ID := &"necklace"
const INVENTORY_ITEM_RANK := 5
const INVENTORY_ITEM_LEVEL := 7
const FIRST_CLEARED_ZONE_ID := &"verdant_outskirts"
const SECOND_CLEARED_ZONE_ID := &"ashfall_reaches"
const SACRIFICE_FODDER_NAME := "Roundtrip Fodder"
const SACRIFICE_FODDER_RANK := 1
const SACRIFICE_ESSENCE := 75
const SACRIFICE_RESONANCE := 1
const STONE_HERO_NAME := "Roundtrip Stone Hero"
const STONE_REWARD := 75
const PROGRESS_HERO_NAME := "Untrusted Progress Hero"
const TURNS_AT_DEATH := 7
const RECOVERED_ITEM_DEF_ID := &"recovery_round_trip"
const EXPIRED_ITEM_DEF_ID := &"expired_round_trip"

var _game_session: Node
var _save_service: Node
var _save_path: String
var _save_version: int
var _original_save_existed: bool
var _original_save_bytes: PackedByteArray


func _init() -> void:
	call_deferred("_run_after_autoloads")


func _run_after_autoloads() -> void:
	_game_session = root.get_node_or_null("GameSession")
	if _game_session == null:
		quit(_fail("GameSession autoload", "present", "missing"))
		return
	_save_service = root.get_node_or_null("SaveService")
	if _save_service == null:
		quit(_fail("SaveService autoload", "present", "missing"))
		return
	var save_script: Script = _save_service.get_script()
	var save_constants: Dictionary = save_script.get_script_constant_map()
	if not save_constants.has("SAVE_PATH"):
		quit(_fail("SaveService.SAVE_PATH constant", "present", "missing"))
		return
	if not save_constants.has("SAVE_VERSION"):
		quit(_fail("SaveService.SAVE_VERSION constant", "present", "missing"))
		return
	_save_path = str(save_constants["SAVE_PATH"])
	_save_version = int(save_constants["SAVE_VERSION"])

	var backup_code: int = _backup_save()
	if backup_code != 0:
		quit(backup_code)
		return
	var exit_code: int = _run()
	var restore_code: int = _restore_save()
	if restore_code != 0:
		exit_code = restore_code
	if exit_code == 0:
		print("PASS: legacy and malformed def_id compatibility, hero level/XP disk round-trip and untrusted shapes, both new-format def_ids, roster, essence, resonance, Summon Stones deduction/reward/untrusted shapes, parts, part conversion, buildings, Forge salvage yield, enhanced equipment, inventory, cleared zones, permadeath, turn counter, lost-cache turn_lost, recovery and expiry, save version %d, and byte-identical restoration passed." % _save_version)
	quit(exit_code)


func _run() -> int:
	var legacy_code: int = _check_legacy_save()
	if legacy_code != 0:
		return legacy_code
	var malformed_code: int = _check_malformed_def_id()
	if malformed_code != 0:
		return malformed_code
	var untrusted_stones_code: int = _check_untrusted_stones()
	if untrusted_stones_code != 0:
		return untrusted_stones_code
	var untrusted_progress_code: int = _check_untrusted_hero_progress()
	if untrusted_progress_code != 0:
		return untrusted_progress_code
	var stones_round_trip_code: int = _check_stones_round_trip()
	if stones_round_trip_code != 0:
		return stones_round_trip_code
	var round_trip_code: int = _check_new_format_round_trip()
	if round_trip_code != 0:
		return round_trip_code
	var sacrifice_code: int = _check_sacrifice_round_trip()
	if sacrifice_code != 0:
		return sacrifice_code
	var parts_code: int = _check_parts_round_trip()
	if parts_code != 0:
		return parts_code
	var enhanced_equipment_code: int = _check_enhanced_equipment_round_trip()
	if enhanced_equipment_code != 0:
		return enhanced_equipment_code
	var inventory_code: int = _check_inventory_round_trip()
	if inventory_code != 0:
		return inventory_code
	var cleared_zones_code: int = _check_cleared_zones_round_trip()
	if cleared_zones_code != 0:
		return cleared_zones_code
	var buildings_code: int = _check_buildings_round_trip()
	if buildings_code != 0:
		return buildings_code
	var permadeath_code: int = _check_permadeath_and_version()
	if permadeath_code != 0:
		return permadeath_code
	var roster_wipe_code: int = _check_roster_wipe_floor_round_trip()
	if roster_wipe_code != 0:
		return roster_wipe_code
	return _check_recovery_round_trip()


func _check_legacy_save() -> int:
	var fixture_code: int = _write_preexisting_fixture()
	if fixture_code != 0:
		return fixture_code
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("pre-existing disk reload", "load_game() == true", "load_game() == false")
	if _roster().size() != 1:
		return _fail("hero count after pre-existing disk reload", "1", str(_roster().size()))
	var legacy_hero: Hero = _find_hero(PREEXISTING_HERO_NAME, PREEXISTING_HERO_RANK)
	if legacy_hero == null:
		return _fail("pre-existing hero identity after disk reload", "%s:%d" % [PREEXISTING_HERO_NAME, PREEXISTING_HERO_RANK], _roster_summary())
	if legacy_hero.def_id != &"":
		return _fail("legacy hero default def_id", "empty", str(legacy_hero.def_id))
	if legacy_hero.resonance != 0:
		return _fail("legacy hero default resonance", "0", str(legacy_hero.resonance))
	if legacy_hero.level != 0 or legacy_hero.xp != 0:
		return _fail("legacy hero default level/XP", "0/0", "%d/%d" % [legacy_hero.level, legacy_hero.xp])
	if _essence() != 0:
		return _fail("essence after pre-existing disk reload", "0", str(_essence()))
	if _stones() != 300:
		return _fail("stones after pre-existing disk reload", "300", str(_stones()))
	return 0


func _check_untrusted_stones() -> int:
	var fixture_code: int = _write_stones_fixture(null)
	if fixture_code != 0:
		return fixture_code
	_game_session.set("stones", 0)
	if not _save_service.call("load_game"):
		return _fail("null stones disk reload", "load_game() == true", "load_game() == false")
	if _stones() != 300:
		return _fail("null stones fallback", "300", str(_stones()))

	fixture_code = _write_stones_fixture(300.0)
	if fixture_code != 0:
		return fixture_code
	_game_session.set("stones", 0)
	if not _save_service.call("load_game"):
		return _fail("float stones disk reload", "load_game() == true", "load_game() == false")
	if _stones() != 300:
		return _fail("integral float stones decode", "300", str(_stones()))
	return 0


func _check_untrusted_hero_progress() -> int:
	var check_code: int = _check_hero_progress_fixture(null, 7, 0, 7, "null level")
	if check_code != 0:
		return check_code
	check_code = _check_hero_progress_fixture("bad", 7, 0, 7, "wrong-typed level")
	if check_code != 0:
		return check_code
	check_code = _check_hero_progress_fixture(3, null, 3, 0, "null XP")
	if check_code != 0:
		return check_code
	return _check_hero_progress_fixture(3, "bad", 3, 0, "wrong-typed XP")


# Variant parameters are required to author explicit JSON null and wrong-typed trust-boundary values.
func _check_hero_progress_fixture(raw_level: Variant, raw_xp: Variant, expected_level: int, expected_xp: int, label: String) -> int:
	var fixture_code: int = _write_hero_progress_fixture(raw_level, raw_xp)
	if fixture_code != 0:
		return fixture_code
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("%s disk reload" % label, "load_game() == true", "load_game() == false")
	var hero: Hero = _find_hero(PROGRESS_HERO_NAME, 0)
	if hero == null:
		return _fail("%s hero" % label, PROGRESS_HERO_NAME, _roster_summary())
	if hero.level != expected_level or hero.xp != expected_xp:
		return _fail("%s fallback" % label, "%d/%d" % [expected_level, expected_xp], "%d/%d" % [hero.level, hero.xp])
	return 0


func _check_stones_round_trip() -> int:
	_game_session.call("from_dict", {"roster": []})
	var balance: BalanceTable = load("res://balance.tres") as BalanceTable
	if balance == null:
		return _fail("stone balance table load", "BalanceTable", "null")
	var hero := Hero.new(STONE_HERO_NAME, 0)
	if not _game_session.call("summon_hero", hero, balance):
		return _fail("stone deduction before disk reload", "summon_hero() == true", "summon_hero() == false")
	_save_service.call("save")

	_game_session.set("stones", 0)
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("stone deduction disk reload", "load_game() == true", "load_game() == false")
	if _stones() != 200:
		return _fail("stones after paid summon disk reload", "200", str(_stones()))
	if _find_hero(STONE_HERO_NAME, 0) == null:
		return _fail("paid summon hero after disk reload", STONE_HERO_NAME, _roster_summary())

	_game_session.call("credit_stones", STONE_REWARD)
	_save_service.call("save")
	_game_session.set("stones", 0)
	if not _save_service.call("load_game"):
		return _fail("stone reward disk reload", "load_game() == true", "load_game() == false")
	if _stones() != 200 + STONE_REWARD:
		return _fail("stones after reward disk reload", str(200 + STONE_REWARD), str(_stones()))
	return 0


func _check_sacrifice_round_trip() -> int:
	var target: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if target == null:
		return _fail("sacrifice target", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	var fodder := Hero.new(SACRIFICE_FODDER_NAME, SACRIFICE_FODDER_RANK)
	fodder.def_id = target.def_id
	_game_session.call("add_hero", fodder)
	if not _game_session.call("sacrifice_hero", fodder, target, BalanceTable.new()):
		return _fail("sacrifice before disk reload", "sacrifice_hero() == true", "sacrifice_hero() == false")
	_save_service.call("save")

	_game_session.set("essence", 0)
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("sacrifice disk reload", "load_game() == true", "load_game() == false")
	if _essence() != SACRIFICE_ESSENCE:
		return _fail("essence after sacrifice disk reload", str(SACRIFICE_ESSENCE), str(_essence()))
	var reloaded_target: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if reloaded_target == null:
		return _fail("sacrifice target after disk reload", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	if reloaded_target.resonance != SACRIFICE_RESONANCE:
		return _fail("resonance after sacrifice disk reload", str(SACRIFICE_RESONANCE), str(reloaded_target.resonance))
	if _find_hero(SACRIFICE_FODDER_NAME, SACRIFICE_FODDER_RANK) != null:
		return _fail("sacrificed fodder after disk reload", "absent", _roster_summary())
	return 0


func _check_malformed_def_id() -> int:
	var fixture_code: int = _write_malformed_fixture()
	if fixture_code != 0:
		return fixture_code
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("malformed def_id disk reload", "load_game() == true", "load_game() == false")
	if _roster().size() != 1:
		return _fail("hero count after malformed def_id reload", "1", str(_roster().size()))
	var malformed_hero: Hero = _find_hero(MALFORMED_HERO_NAME, MALFORMED_HERO_RANK)
	if malformed_hero == null:
		return _fail("malformed def_id hero identity", "%s:%d" % [MALFORMED_HERO_NAME, MALFORMED_HERO_RANK], _roster_summary())
	if malformed_hero.def_id != &"":
		return _fail("malformed hero fallback def_id", "empty", str(malformed_hero.def_id))
	return 0


func _check_new_format_round_trip() -> int:
	_roster().clear()
	var first_hero := Hero.new(FIRST_HERO_NAME, FIRST_HERO_RANK)
	first_hero.def_id = FIRST_HERO_DEF_ID
	first_hero.level = FIRST_HERO_LEVEL
	first_hero.xp = FIRST_HERO_XP
	var second_hero := Hero.new(SECOND_HERO_NAME, SECOND_HERO_RANK)
	second_hero.def_id = SECOND_HERO_DEF_ID
	_game_session.call("add_hero", first_hero)
	_game_session.call("add_hero", second_hero)
	_save_service.call("save")

	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("first disk reload", "load_game() == true", "load_game() == false")
	if _roster().size() != 2:
		return _fail("hero count after first disk reload", "2", str(_roster().size()))
	if not _has_hero(FIRST_HERO_NAME, FIRST_HERO_RANK):
		return _fail("first hero identity after disk reload", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	if not _has_hero(SECOND_HERO_NAME, SECOND_HERO_RANK):
		return _fail("second hero identity after disk reload", "%s:%d" % [SECOND_HERO_NAME, SECOND_HERO_RANK], _roster_summary())
	var loaded_first_hero: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if loaded_first_hero == null:
		return _fail("first hero selected for def_id check", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	if loaded_first_hero.def_id != FIRST_HERO_DEF_ID:
		return _fail("new-format hero def_id after disk reload", str(FIRST_HERO_DEF_ID), str(loaded_first_hero.def_id))
	if loaded_first_hero.level != FIRST_HERO_LEVEL or loaded_first_hero.xp != FIRST_HERO_XP:
		return _fail("new-format hero level/XP after disk reload", "%d/%d" % [FIRST_HERO_LEVEL, FIRST_HERO_XP], "%d/%d" % [loaded_first_hero.level, loaded_first_hero.xp])
	var loaded_second_hero: Hero = _find_hero(SECOND_HERO_NAME, SECOND_HERO_RANK)
	if loaded_second_hero == null:
		return _fail("second hero selected for def_id check", "%s:%d" % [SECOND_HERO_NAME, SECOND_HERO_RANK], _roster_summary())
	if loaded_second_hero.def_id != SECOND_HERO_DEF_ID:
		return _fail("second new-format hero def_id after disk reload", str(SECOND_HERO_DEF_ID), str(loaded_second_hero.def_id))
	return 0


func _check_parts_round_trip() -> int:
	var salvaged_item := Item.new(DOOMED_ITEM_DEF_ID, SALVAGED_ITEM_RANK)
	var balance := BalanceTable.new()
	_game_session.call("add_item", salvaged_item)
	_game_session.call("salvage_item", salvaged_item, balance)
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("parts raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	# Every read of the save file closes immediately, here and in the six checks below. Since P2-20
	# save() stages to a temp file and renames it over this path, and Windows will not replace a
	# file that still has an open handle - a reader held open across any later autosave fails it.
	save_file.close()
	if parsed is not Dictionary:
		return _fail("parts raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	# Save-file fields remain Variant until their types are validated.
	var raw_parts: Variant = (parsed as Dictionary).get("parts")
	if raw_parts is not Array:
		return _fail("raw save JSON parts shape", "Array", type_string(typeof(raw_parts)))
	var raw_parts_array: Array = raw_parts as Array
	if raw_parts_array.size() != _parts().size():
		return _fail("raw save JSON parts rank count", str(_parts().size()), str(raw_parts_array.size()))
	for rank_index: int in _parts().size():
		var raw_expected: int = 3 if rank_index == SALVAGED_ITEM_RANK else 0
		if int(raw_parts_array[rank_index]) != raw_expected:
			return _fail("raw save JSON parts at rank %d" % rank_index, str(raw_expected), str(raw_parts_array[rank_index]))

	_parts().fill(0)
	if not _save_service.call("load_game"):
		return _fail("parts disk reload", "load_game() == true", "load_game() == false")
	for rank_index: int in _parts().size():
		var loaded_expected: int = 3 if rank_index == SALVAGED_ITEM_RANK else 0
		if _parts()[rank_index] != loaded_expected:
			return _fail("parts after disk reload at rank %d" % rank_index, str(loaded_expected), str(_parts()[rank_index]))

	if not _game_session.call("convert_parts", SALVAGED_ITEM_RANK):
		return _fail("part conversion", "convert_parts() == true", "convert_parts() == false")
	# Do not save explicitly: conversion must persist through roster_changed's autosave.
	save_file = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("converted parts raw save file open", "readable", error_string(FileAccess.get_open_error()))
	parsed = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("converted parts raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	raw_parts = (parsed as Dictionary).get("parts")
	if raw_parts is not Array:
		return _fail("converted raw save JSON parts shape", "Array", type_string(typeof(raw_parts)))
	raw_parts_array = raw_parts as Array
	if raw_parts_array.size() != _parts().size():
		return _fail("converted raw save JSON parts rank count", str(_parts().size()), str(raw_parts_array.size()))
	for rank_index: int in _parts().size():
		var converted_raw_expected: int = 1 if rank_index == SALVAGED_ITEM_RANK + 1 else 0
		if int(raw_parts_array[rank_index]) != converted_raw_expected:
			return _fail("converted raw save JSON parts at rank %d" % rank_index, str(converted_raw_expected), str(raw_parts_array[rank_index]))

	_parts().fill(0)
	if not _save_service.call("load_game"):
		return _fail("converted parts disk reload", "load_game() == true", "load_game() == false")
	for rank_index: int in _parts().size():
		var converted_loaded_expected: int = 1 if rank_index == SALVAGED_ITEM_RANK + 1 else 0
		if _parts()[rank_index] != converted_loaded_expected:
			return _fail("converted parts after disk reload at rank %d" % rank_index, str(converted_loaded_expected), str(_parts()[rank_index]))
	return 0


func _check_buildings_round_trip() -> int:
	var building_levels: Array[int] = _game_session.get("building_levels")
	building_levels.fill(0)
	_parts().fill(0)
	_parts()[0] = 60
	_parts()[1] = 30
	# Three buildings at two different levels, one of them the array's **last** index, so a save
	# that persists only the first index — or collapses the array to one value, or truncates its
	# tail — fails here rather than passing on an all-zero remainder.
	var expected_levels: Array[int] = [0, 2, 1, 0, 1]
	var balance := BalanceTable.new()
	if not _game_session.call("upgrade_building", 1, balance):
		return _fail("first Forge upgrade before disk reload", "upgrade_building() == true", "upgrade_building() == false")
	if not _game_session.call("upgrade_building", 1, balance):
		return _fail("second Forge upgrade before disk reload", "upgrade_building() == true", "upgrade_building() == false")
	if not _game_session.call("upgrade_building", 2, balance):
		return _fail("Training Hall upgrade before disk reload", "upgrade_building() == true", "upgrade_building() == false")
	if not _game_session.call("upgrade_building", 4, balance):
		return _fail("Reliquary upgrade before disk reload", "upgrade_building() == true", "upgrade_building() == false")
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("building levels raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("building levels raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	# Save-file fields remain Variant until their types are validated.
	var raw_building_levels: Variant = (parsed as Dictionary).get("building_levels")
	if raw_building_levels is not Array:
		return _fail("raw save JSON building levels shape", "Array", type_string(typeof(raw_building_levels)))
	var raw_building_levels_array: Array = raw_building_levels as Array
	if raw_building_levels_array.size() != building_levels.size():
		return _fail("raw save JSON building level count", str(building_levels.size()), str(raw_building_levels_array.size()))
	for building_index: int in building_levels.size():
		var expected_level: int = expected_levels[building_index]
		if int(raw_building_levels_array[building_index]) != expected_level:
			return _fail("raw save JSON building level at index %d" % building_index, str(expected_level), str(raw_building_levels_array[building_index]))

	building_levels.fill(0)
	_parts().fill(0)
	if not _save_service.call("load_game"):
		return _fail("building levels disk reload", "load_game() == true", "load_game() == false")
	for building_index: int in building_levels.size():
		var expected_level: int = expected_levels[building_index]
		if building_levels[building_index] != expected_level:
			return _fail("building level after disk reload at index %d" % building_index, str(expected_level), str(building_levels[building_index]))
	var salvaged_item := Item.new(DOOMED_ITEM_DEF_ID, SALVAGED_ITEM_RANK)
	_game_session.call("add_item", salvaged_item)
	_game_session.call("salvage_item", salvaged_item, balance)
	if _parts()[SALVAGED_ITEM_RANK] != 4:
		return _fail("Forge-bonused salvage after disk reload", "4", str(_parts()[SALVAGED_ITEM_RANK]))
	return 0


func _check_enhanced_equipment_round_trip() -> int:
	var hero: Hero = _find_hero(SECOND_HERO_NAME, SECOND_HERO_RANK)
	if hero == null:
		return _fail("hero selected for enhanced equipment", "%s:%d" % [SECOND_HERO_NAME, SECOND_HERO_RANK], _roster_summary())
	var item := Item.new(ENHANCED_ITEM_DEF_ID, ENHANCED_ITEM_RANK)
	item.enhance_level = ENHANCED_ITEM_LEVEL
	var definition: EquipmentDefinition = Item.definition_for(item.def_id)
	if definition == null:
		return _fail("enhanced equipment definition", str(ENHANCED_ITEM_DEF_ID), "missing")
	_game_session.call("add_item", item)
	_game_session.call("equip_item", hero, item)
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("enhanced equipment raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("enhanced equipment raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	# Save-file fields remain Variant until their types are validated.
	var raw_roster: Variant = (parsed as Dictionary).get("roster")
	if raw_roster is not Array:
		return _fail("enhanced equipment raw save roster shape", "Array", type_string(typeof(raw_roster)))
	var raw_enhance_level: int = -1
	for raw_hero: Variant in raw_roster as Array:
		if raw_hero is not Dictionary:
			continue
		var hero_entry: Dictionary = raw_hero as Dictionary
		if str(hero_entry.get("name")) != SECOND_HERO_NAME:
			continue
		# Save-file fields remain Variant until their types are validated.
		var raw_equipped: Variant = hero_entry.get("equipped")
		if raw_equipped is not Array:
			return _fail("enhanced equipment raw save equipped shape", "Array", type_string(typeof(raw_equipped)))
		for raw_equipped_entry: Variant in raw_equipped as Array:
			if raw_equipped_entry is not Dictionary:
				continue
			# Save-file fields remain Variant until their types are validated.
			var raw_item: Variant = (raw_equipped_entry as Dictionary).get("item")
			if raw_item is Dictionary and str((raw_item as Dictionary).get("def_id")) == str(ENHANCED_ITEM_DEF_ID):
				raw_enhance_level = int((raw_item as Dictionary).get("enhance_level", -1))
	if raw_enhance_level != ENHANCED_ITEM_LEVEL:
		return _fail("enhanced equipment level in raw save JSON", str(ENHANCED_ITEM_LEVEL), str(raw_enhance_level))

	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("enhanced equipment disk reload", "load_game() == true", "load_game() == false")
	var reloaded_hero: Hero = _find_hero(SECOND_HERO_NAME, SECOND_HERO_RANK)
	if reloaded_hero == null:
		return _fail("enhanced equipment hero after disk reload", "%s:%d" % [SECOND_HERO_NAME, SECOND_HERO_RANK], _roster_summary())
	if not reloaded_hero.equipped.has(definition.slot):
		return _fail("enhanced equipment slot after disk reload", str(definition.slot), "missing")
	var reloaded_item: Item = reloaded_hero.equipped[definition.slot]
	if reloaded_item.enhance_level != ENHANCED_ITEM_LEVEL:
		return _fail("enhanced equipment level after disk reload", str(ENHANCED_ITEM_LEVEL), str(reloaded_item.enhance_level))
	return 0


func _check_inventory_round_trip() -> int:
	var item := Item.new(INVENTORY_ITEM_DEF_ID, INVENTORY_ITEM_RANK)
	item.enhance_level = INVENTORY_ITEM_LEVEL
	_game_session.call("add_item", item)
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("inventory raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("inventory raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	# Save-file fields remain Variant until their types are validated.
	var raw_inventory: Variant = (parsed as Dictionary).get("inventory")
	if raw_inventory is not Array:
		return _fail("inventory raw save JSON shape", "Array", type_string(typeof(raw_inventory)))
	var raw_inventory_array: Array = raw_inventory as Array
	if raw_inventory_array.size() != 1:
		return _fail("inventory raw save item count", "1", str(raw_inventory_array.size()))
	if raw_inventory_array[0] is not Dictionary:
		return _fail("inventory raw save item shape", "Dictionary", type_string(typeof(raw_inventory_array[0])))
	var raw_item: Dictionary = raw_inventory_array[0] as Dictionary
	if str(raw_item.get("def_id")) != str(INVENTORY_ITEM_DEF_ID):
		return _fail("inventory def_id in raw save JSON", str(INVENTORY_ITEM_DEF_ID), str(raw_item.get("def_id")))
	if int(raw_item.get("rank", -1)) != INVENTORY_ITEM_RANK:
		return _fail("inventory rank in raw save JSON", str(INVENTORY_ITEM_RANK), str(raw_item.get("rank")))
	if int(raw_item.get("enhance_level", -1)) != INVENTORY_ITEM_LEVEL:
		return _fail("inventory enhance level in raw save JSON", str(INVENTORY_ITEM_LEVEL), str(raw_item.get("enhance_level")))

	var inventory: Array[Item] = _game_session.get("inventory")
	inventory.clear()
	if not _save_service.call("load_game"):
		return _fail("inventory disk reload", "load_game() == true", "load_game() == false")
	if inventory.size() != 1:
		return _fail("inventory item count after disk reload", "1", str(inventory.size()))
	var reloaded_item: Item = inventory[0]
	if reloaded_item.def_id != INVENTORY_ITEM_DEF_ID:
		return _fail("inventory def_id after disk reload", str(INVENTORY_ITEM_DEF_ID), str(reloaded_item.def_id))
	if reloaded_item.rank != INVENTORY_ITEM_RANK:
		return _fail("inventory rank after disk reload", str(INVENTORY_ITEM_RANK), str(reloaded_item.rank))
	if reloaded_item.enhance_level != INVENTORY_ITEM_LEVEL:
		return _fail("inventory enhance level after disk reload", str(INVENTORY_ITEM_LEVEL), str(reloaded_item.enhance_level))
	return 0


func _check_cleared_zones_round_trip() -> int:
	_game_session.call("mark_zone_cleared", FIRST_CLEARED_ZONE_ID)
	_game_session.call("mark_zone_cleared", SECOND_CLEARED_ZONE_ID)
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("cleared zones raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("cleared zones raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	# Save-file fields remain Variant until their types are validated.
	var raw_cleared_zone_ids: Variant = (parsed as Dictionary).get("cleared_zone_ids")
	if raw_cleared_zone_ids is not Array:
		return _fail("cleared zones raw save JSON shape", "Array", type_string(typeof(raw_cleared_zone_ids)))
	var has_first_zone: bool = false
	var has_second_zone: bool = false
	for raw_zone_id: Variant in raw_cleared_zone_ids as Array:
		if raw_zone_id is not String:
			return _fail("cleared zone ID in raw save JSON type", "String", type_string(typeof(raw_zone_id)))
		if raw_zone_id == str(FIRST_CLEARED_ZONE_ID):
			has_first_zone = true
		if raw_zone_id == str(SECOND_CLEARED_ZONE_ID):
			has_second_zone = true
	if not has_first_zone:
		return _fail("first cleared zone in raw save JSON", str(FIRST_CLEARED_ZONE_ID), "missing")
	if not has_second_zone:
		return _fail("second cleared zone in raw save JSON", str(SECOND_CLEARED_ZONE_ID), "missing")

	var cleared_zone_ids: Dictionary[StringName, bool] = _game_session.get("cleared_zone_ids")
	cleared_zone_ids.clear()
	if not _save_service.call("load_game"):
		return _fail("cleared zones disk reload", "load_game() == true", "load_game() == false")
	if not cleared_zone_ids.has(FIRST_CLEARED_ZONE_ID):
		return _fail("first cleared zone after disk reload", str(FIRST_CLEARED_ZONE_ID), "missing")
	if not cleared_zone_ids.has(SECOND_CLEARED_ZONE_ID):
		return _fail("second cleared zone after disk reload", str(SECOND_CLEARED_ZONE_ID), "missing")
	return 0


func _check_permadeath_and_version() -> int:
	var doomed_hero: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if doomed_hero == null:
		return _fail("hero selected for permadeath", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	var doomed_item := Item.new(DOOMED_ITEM_DEF_ID, DOOMED_ITEM_RANK)
	_game_session.call("add_item", doomed_item)
	_game_session.call("equip_item", doomed_hero, doomed_item)
	# Non-zero so a turn_lost that silently defaults to 0 fails here instead of passing by accident.
	_game_session.set("turns", TURNS_AT_DEATH)
	_game_session.call("kill_hero", doomed_hero, &"save_roundtrip", preload("res://balance.tres"))
	_save_service.call("save")

	_roster().clear()
	_game_session.set("turns", 0)
	if not _save_service.call("load_game"):
		return _fail("post-permadeath disk reload", "load_game() == true", "load_game() == false")
	if _game_session.get("turns") != TURNS_AT_DEATH:
		return _fail("turn counter after disk reload", str(TURNS_AT_DEATH), str(_game_session.get("turns")))
	if _roster().size() != 1:
		return _fail("hero count after permadeath disk reload", "1", str(_roster().size()))
	if _has_hero(FIRST_HERO_NAME, FIRST_HERO_RANK):
		return _fail("permanently killed hero after disk reload", "absent", _roster_summary())
	if not _has_hero(SECOND_HERO_NAME, SECOND_HERO_RANK):
		return _fail("surviving hero after permadeath disk reload", "%s:%d" % [SECOND_HERO_NAME, SECOND_HERO_RANK], _roster_summary())
	var lost_caches: Array[LostCache] = _game_session.get("lost_caches")
	if lost_caches.size() != 1:
		return _fail("lost cache count after permadeath disk reload", "1", str(lost_caches.size()))
	var lost_cache: LostCache = lost_caches[0]
	if lost_cache.hero_name != FIRST_HERO_NAME:
		return _fail("lost cache hero name after disk reload", FIRST_HERO_NAME, lost_cache.hero_name)
	if lost_cache.zone_id != &"save_roundtrip":
		return _fail("lost cache zone ID after disk reload", "save_roundtrip", str(lost_cache.zone_id))
	if lost_cache.turn_lost != TURNS_AT_DEATH:
		return _fail("lost cache turn_lost after disk reload", str(TURNS_AT_DEATH), str(lost_cache.turn_lost))
	if lost_cache.items.size() != 1:
		return _fail("lost cache item count after disk reload", "1", str(lost_cache.items.size()))
	var lost_item: Item = lost_cache.items[0]
	if lost_item.def_id != DOOMED_ITEM_DEF_ID:
		return _fail("lost cache item def_id after disk reload", str(DOOMED_ITEM_DEF_ID), str(lost_item.def_id))
	if lost_item.rank != DOOMED_ITEM_RANK:
		return _fail("lost cache item rank after disk reload", str(DOOMED_ITEM_RANK), str(lost_item.rank))

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if parsed is not Dictionary:
		return _fail("raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	var payload: Dictionary = parsed as Dictionary
	if not payload.has("version"):
		return _fail("raw save JSON version key", "present", "missing")
	if payload.get("version") != _save_version:
		return _fail("raw save JSON version value", str(_save_version), str(payload.get("version")))
	if not payload.has("turns"):
		return _fail("raw save JSON turns key", "present", "missing")
	if int(payload.get("turns")) != TURNS_AT_DEATH:
		return _fail("raw save JSON turns value", str(TURNS_AT_DEATH), str(payload.get("turns")))

	return 0


func _check_roster_wipe_floor_round_trip() -> int:
	var balance: BalanceTable = load("res://balance.tres") as BalanceTable
	if balance == null:
		return _fail("roster-wipe balance table load", "BalanceTable", "null")
	_game_session.call("from_dict", {"roster": [], "stones": balance.summon_pull_cost - 1})
	var doomed_hero := Hero.new("Roster Wipe Hero", 0)
	_game_session.call("add_hero", doomed_hero)
	_game_session.call("kill_hero", doomed_hero, &"roster_wipe", balance)

	_game_session.set("stones", 0)
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("roster-wipe floor disk reload", "load_game() == true", "load_game() == false")
	if _stones() != balance.summon_pull_cost:
		return _fail("roster-wipe floor after disk reload", str(balance.summon_pull_cost), str(_stones()))
	if not _roster().is_empty():
		return _fail("roster-wipe floor roster after disk reload", "empty", _roster_summary())
	return 0


func _check_recovery_round_trip() -> int:
	var balance: BalanceTable = load("res://balance.tres") as BalanceTable
	if balance == null:
		return _fail("recovery balance table load", "BalanceTable", "null")
	var rescuer := Hero.new("Roundtrip Rescuer", 7)
	rescuer.def_id = &"knight"
	rescuer.level = balance.level_caps[7]
	_game_session.call("add_hero", rescuer)
	_game_session.set("turns", 15)
	var recovered_cache := LostCache.new("Recovered Hero", &"verdant_outskirts", 15)
	var recovered_item := Item.new(RECOVERED_ITEM_DEF_ID, 7)
	recovered_item.enhance_level = 13
	recovered_cache.items.append(recovered_item)
	var expired_cache := LostCache.new("Expired Hero", &"verdant_outskirts", 0)
	expired_cache.items.append(Item.new(EXPIRED_ITEM_DEF_ID, 7))
	var lost_caches: Array[LostCache] = _game_session.get("lost_caches")
	lost_caches.append(recovered_cache)
	lost_caches.append(expired_cache)
	var team: Array[Hero] = [rescuer]
	var outcome: StringName = _game_session.call("recover_cache", recovered_cache, team, balance)
	if outcome != &"completed":
		return _fail("recovery before disk reload", "completed", str(outcome))
	var inventory: Array[Item] = _game_session.get("inventory")
	if not inventory.has(recovered_item):
		return _fail("recovered item before disk reload", str(RECOVERED_ITEM_DEF_ID), "missing")
	if lost_caches.has(recovered_cache):
		return _fail("recovered cache before disk reload", "absent", "present")
	if lost_caches.has(expired_cache):
		return _fail("expired cache before disk reload", "absent", "present")
	_save_service.call("save")

	inventory.clear()
	lost_caches.clear()
	_game_session.set("turns", 0)
	if not _save_service.call("load_game"):
		return _fail("recovery disk reload", "load_game() == true", "load_game() == false")
	if not lost_caches.is_empty():
		return _fail("recovered and expired caches after disk reload", "empty", str(lost_caches.size()))
	var reloaded_recovered_item: Item = null
	# Counted, not just found: recover_cache appends each item to inventory without clearing
	# cache.items, so the same Item is briefly reachable from two places. Presence alone would
	# pass with a duplicate on disk.
	var recovered_item_count: int = 0
	for item: Item in inventory:
		if item.def_id == RECOVERED_ITEM_DEF_ID:
			reloaded_recovered_item = item
			recovered_item_count += 1
		if item.def_id == EXPIRED_ITEM_DEF_ID:
			return _fail("expired cache item after disk reload", "absent", "present")
	if reloaded_recovered_item == null:
		return _fail("recovered item after disk reload", str(RECOVERED_ITEM_DEF_ID), "missing")
	if recovered_item_count != 1:
		return _fail("recovered item copies after disk reload", "1", str(recovered_item_count))
	inventory.erase(reloaded_recovered_item)
	_save_service.call("save")
	return 0


func _backup_save() -> int:
	_original_save_existed = FileAccess.file_exists(_save_path)
	if not _original_save_existed:
		return 0
	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("original save backup", "readable", error_string(FileAccess.get_open_error()))
	_original_save_bytes = save_file.get_buffer(save_file.get_length())
	save_file.close()
	return 0


func _restore_save() -> int:
	if not _original_save_existed:
		if FileAccess.file_exists(_save_path):
			var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
			if remove_error != OK:
				return _fail("original save restoration", "file absent", error_string(remove_error))
		return 0

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if save_file == null:
		return _fail("original save restoration", "writable", error_string(FileAccess.get_open_error()))
	save_file.store_buffer(_original_save_bytes)
	save_file.close()

	save_file = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("restored save verification", "readable", error_string(FileAccess.get_open_error()))
	var restored_bytes: PackedByteArray = save_file.get_buffer(save_file.get_length())
	save_file.close()
	if restored_bytes != _original_save_bytes:
		return _fail("restored save verification", "byte-identical", "different bytes")
	return 0


func _write_preexisting_fixture() -> int:
	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if save_file == null:
		return _fail("pre-existing fixture write", "writable", error_string(FileAccess.get_open_error()))
	var fixture: Dictionary = {
		"roster": [{"name": PREEXISTING_HERO_NAME, "rank": PREEXISTING_HERO_RANK}],
		"version": _save_version,
	}
	save_file.store_string(JSON.stringify(fixture, "\t"))
	save_file.close()
	return 0


func _write_malformed_fixture() -> int:
	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if save_file == null:
		return _fail("malformed def_id fixture write", "writable", error_string(FileAccess.get_open_error()))
	var fixture: Dictionary = {
		"roster": [{"name": MALFORMED_HERO_NAME, "rank": MALFORMED_HERO_RANK, "def_id": null}],
		"version": _save_version,
	}
	save_file.store_string(JSON.stringify(fixture, "\t"))
	save_file.close()
	return 0


func _write_stones_fixture(raw_stones: Variant) -> int:
	# Variant is required to author the explicit null and JSON-float trust-boundary fixtures.
	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if save_file == null:
		return _fail("untrusted stones fixture write", "writable", error_string(FileAccess.get_open_error()))
	var fixture: Dictionary = {
		"roster": [],
		"stones": raw_stones,
		"version": _save_version,
	}
	save_file.store_string(JSON.stringify(fixture, "\t"))
	save_file.close()
	return 0


# Variant parameters are required to author explicit JSON null and wrong-typed trust-boundary values.
func _write_hero_progress_fixture(raw_level: Variant, raw_xp: Variant) -> int:
	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if save_file == null:
		return _fail("untrusted hero progress fixture write", "writable", error_string(FileAccess.get_open_error()))
	var fixture: Dictionary = {
		"roster": [{"name": PROGRESS_HERO_NAME, "rank": 0, "level": raw_level, "xp": raw_xp}],
		"version": _save_version,
	}
	save_file.store_string(JSON.stringify(fixture, "\t"))
	save_file.close()
	return 0


func _find_hero(hero_name: String, rank: int) -> Hero:
	for hero: Hero in _roster():
		if hero.hero_name == hero_name and hero.rank == rank:
			return hero
	return null


func _has_hero(hero_name: String, rank: int) -> bool:
	return _find_hero(hero_name, rank) != null


func _roster_summary() -> String:
	var entries: PackedStringArray = []
	for hero: Hero in _roster():
		entries.append("%s:%d" % [hero.hero_name, hero.rank])
	return "[%s]" % ", ".join(entries)


func _roster() -> Array[Hero]:
	return _game_session.get("roster")


func _parts() -> Array[int]:
	return _game_session.get("parts")


func _essence() -> int:
	return _game_session.get("essence")


func _stones() -> int:
	return _game_session.get("stones")


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
