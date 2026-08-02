extends SceneTree

var _game_session: Node
var _save_service: Node
var _save_path: String
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
	_save_path = str(save_constants["SAVE_PATH"])

	var backup_code: int = _backup_save()
	if backup_code != 0:
		quit(backup_code)
		return
	var exit_code: int = _run()
	var restore_code: int = _restore_save()
	if restore_code != 0:
		exit_code = restore_code
	if exit_code == 0:
		print("PASS: summoned archetype def_id survives save/load and resolves to its HeroDefinition.")
	quit(exit_code)


func _run() -> int:
	_roster().clear()
	var summoned: Hero = Summon.roll()
	if summoned.def_id == Hero.NO_ARCHETYPE_DEF_ID:
		return _fail("summoned def_id", "non-empty", "empty")
	var definition_before: HeroDefinition = Summon.definition_for(summoned.def_id)
	if definition_before == null:
		return _fail("summoned HeroDefinition", "resolvable", "missing")
	var expected_def_id: StringName = summoned.def_id
	var expected_display_name: String = definition_before.display_name
	_game_session.call("add_hero", summoned)
	_save_service.call("save")

	_roster().clear()
	if not _save_service.call("load_game"):
		return _fail("disk reload", "load_game() == true", "load_game() == false")
	if _roster().size() != 1:
		return _fail("hero count after reload", "1", str(_roster().size()))
	var reloaded: Hero = _roster()[0]
	if reloaded.def_id != expected_def_id:
		return _fail("reloaded def_id", str(expected_def_id), str(reloaded.def_id))
	var definition_after: HeroDefinition = Summon.definition_for(reloaded.def_id)
	if definition_after == null:
		return _fail("reloaded HeroDefinition", "resolvable", "missing")
	if definition_after.display_name != expected_display_name:
		return _fail("reloaded HeroDefinition display_name", expected_display_name, definition_after.display_name)
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
	return 0


func _roster() -> Array[Hero]:
	return _game_session.get("roster")


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
