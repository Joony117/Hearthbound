extends SceneTree

const FIRST_HERO_NAME := "Roundtrip Aster"
const FIRST_HERO_RANK := 2
const FIRST_HERO_DEF_ID := &"rogue"
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
const SACRIFICE_FODDER_NAME := "Roundtrip Fodder"
const SACRIFICE_FODDER_RANK := 1
const SACRIFICE_ESSENCE := 75
const SACRIFICE_RESONANCE := 1

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
		print("PASS: legacy and malformed def_id compatibility, both new-format def_ids, roster, essence, resonance, parts, part conversion, buildings, enhanced equipment, permadeath, save version %d, and byte-identical restoration passed." % _save_version)
	quit(exit_code)


func _run() -> int:
	var legacy_code: int = _check_legacy_save()
	if legacy_code != 0:
		return legacy_code
	var malformed_code: int = _check_malformed_def_id()
	if malformed_code != 0:
		return malformed_code
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
	var buildings_code: int = _check_buildings_round_trip()
	if buildings_code != 0:
		return buildings_code
	return _check_permadeath_and_version()


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
	if _essence() != 0:
		return _fail("essence after pre-existing disk reload", "0", str(_essence()))
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
	_parts()[0] = 20
	if not _game_session.call("upgrade_building", 0, BalanceTable.new()):
		return _fail("building upgrade before disk reload", "upgrade_building() == true", "upgrade_building() == false")
	_save_service.call("save")

	var save_file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if save_file == null:
		return _fail("building levels raw save file open", "readable", error_string(FileAccess.get_open_error()))
	# JSON parsing returns Variant because malformed or unexpected disk data has no static type.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
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
		var expected_level: int = 1 if building_index == 0 else 0
		if int(raw_building_levels_array[building_index]) != expected_level:
			return _fail("raw save JSON building level at index %d" % building_index, str(expected_level), str(raw_building_levels_array[building_index]))

	building_levels.fill(0)
	if not _save_service.call("load_game"):
		return _fail("building levels disk reload", "load_game() == true", "load_game() == false")
	for building_index: int in building_levels.size():
		var expected_level: int = 1 if building_index == 0 else 0
		if building_levels[building_index] != expected_level:
			return _fail("building level after disk reload at index %d" % building_index, str(expected_level), str(building_levels[building_index]))
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


func _check_permadeath_and_version() -> int:
	var doomed_hero: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if doomed_hero == null:
		return _fail("hero selected for permadeath", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	var doomed_item := Item.new(DOOMED_ITEM_DEF_ID, DOOMED_ITEM_RANK)
	_game_session.call("add_item", doomed_item)
	_game_session.call("equip_item", doomed_hero, doomed_item)
	_game_session.call("kill_hero", doomed_hero, &"save_roundtrip")
	_save_service.call("save")

	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("post-permadeath disk reload", "load_game() == true", "load_game() == false")
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
	if parsed is not Dictionary:
		return _fail("raw save JSON top level", "Dictionary", type_string(typeof(parsed)))
	var payload: Dictionary = parsed as Dictionary
	if not payload.has("version"):
		return _fail("raw save JSON version key", "present", "missing")
	if payload.get("version") != _save_version:
		return _fail("raw save JSON version value", str(_save_version), str(payload.get("version")))

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


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
