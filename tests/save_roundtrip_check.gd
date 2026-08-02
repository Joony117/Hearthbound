extends SceneTree

const FIRST_HERO_NAME := "Roundtrip Aster"
const FIRST_HERO_RANK := 2
const SECOND_HERO_NAME := "Roundtrip Brann"
const SECOND_HERO_RANK := 6
const PREEXISTING_HERO_NAME := "Preexisting Cyra"
const PREEXISTING_HERO_RANK := 4

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
		print("PASS: save round-trip loaded pre-existing data, preserved two heroes, persisted permadeath, wrote save version %d, and restored the original save." % _save_version)
	quit(exit_code)


func _run() -> int:
	var fixture_code: int = _write_preexisting_fixture()
	if fixture_code != 0:
		return fixture_code
	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("pre-existing disk reload", "load_game() == true", "load_game() == false")
	if _roster().size() != 1:
		return _fail("hero count after pre-existing disk reload", "1", str(_roster().size()))
	if not _has_hero(PREEXISTING_HERO_NAME, PREEXISTING_HERO_RANK):
		return _fail("pre-existing hero identity after disk reload", "%s:%d" % [PREEXISTING_HERO_NAME, PREEXISTING_HERO_RANK], _roster_summary())

	_roster().clear()
	_game_session.call("add_hero", Hero.new(FIRST_HERO_NAME, FIRST_HERO_RANK))
	_game_session.call("add_hero", Hero.new(SECOND_HERO_NAME, SECOND_HERO_RANK))
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

	var doomed_hero: Hero = _find_hero(FIRST_HERO_NAME, FIRST_HERO_RANK)
	if doomed_hero == null:
		return _fail("hero selected for permadeath", "%s:%d" % [FIRST_HERO_NAME, FIRST_HERO_RANK], _roster_summary())
	_game_session.call("kill_hero", doomed_hero)
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
		"roster": [Hero.new(PREEXISTING_HERO_NAME, PREEXISTING_HERO_RANK).to_dict()],
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


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
