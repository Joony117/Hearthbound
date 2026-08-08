extends GutTest

const HERO_NAME := "Refusal Aster"
const HERO_RANK := 3
const ITEM_DEF_ID := &"ring"
const ITEM_RANK := 2
const ITEM_ENHANCE_LEVEL := 4
const PARTS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const STONES := 987
const CLEARED_ZONE_ID := &"verdant_outskirts"

var _original_save_existed: bool = false
var _original_save_bytes: PackedByteArray


func before_all() -> void:
	_original_save_existed = FileAccess.file_exists(SaveService.SAVE_PATH)
	if not _original_save_existed:
		return
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return
	_original_save_bytes = save_file.get_buffer(save_file.get_length())
	save_file.close()


func after_all() -> void:
	_remove_file_if_exists(SaveService.CORRUPT_PATH)
	_remove_temp_path()
	if not _original_save_existed:
		_remove_file_if_exists(SaveService.SAVE_PATH)
		return
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(_original_save_bytes)
	save_file.close()

	save_file = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return
	var restored_bytes: PackedByteArray = save_file.get_buffer(save_file.get_length())
	save_file.close()
	assert_eq(restored_bytes, _original_save_bytes)


func before_each() -> void:
	GameSession.from_dict({"roster": []})
	_remove_file_if_exists(SaveService.CORRUPT_PATH)
	_remove_temp_path()


func test_failed_temp_write_preserves_existing_save() -> void:
	var original_bytes := "previous save".to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, original_bytes)
	var make_directory_error: Error = DirAccess.make_dir_absolute(SaveService.TMP_PATH)
	assert_eq(make_directory_error, OK)

	SaveService.save()

	assert_push_error("Save failed")
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), original_bytes)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)


## Clearing the session in-memory autosaves over the file we are about to load, so the good bytes
## are captured first and restored after. This also pins the interlock the staged write introduced:
## load_game() -> from_dict() -> roster_changed -> save() renames over the path load_game() is
## reading, which fails outright if that read handle is still open.
func test_stale_temp_file_is_ignored_then_replaced() -> void:
	_set_distinctive_state()
	SaveService.save()
	var good_save_bytes := _read_file_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write_save(SaveService.SAVE_PATH, good_save_bytes)
	_write_save(SaveService.TMP_PATH, "stale".to_utf8_buffer())

	assert_true(SaveService.load_game())
	_assert_distinctive_state()
	SaveService.save()
	assert_false(FileAccess.file_exists(SaveService.TMP_PATH))
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), good_save_bytes)


func test_save_replaces_temp_file_with_session_state() -> void:
	_set_distinctive_state()
	SaveService.save()

	assert_false(FileAccess.file_exists(SaveService.TMP_PATH))
	# Save files are untrusted JSON, so their parser result remains Variant until shape-checked.
	var parsed: Variant = JSON.parse_string(_read_file_bytes(SaveService.SAVE_PATH).get_string_from_utf8())
	assert_true(parsed is Dictionary)
	var saved_state: Dictionary = parsed as Dictionary
	# JSON decodes every number as a float, the shape Item.int_field() absorbs on the way back in.
	assert_eq(int(saved_state.get("stones")), STONES)
	assert_eq(saved_state.get("cleared_zone_ids"), [str(CLEARED_ZONE_ID)])


func test_non_dictionary_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var corrupt_save_bytes := "[1, 2, 3]".to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(corrupt_save_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	assert_false(FileAccess.file_exists(SaveService.SAVE_PATH))
	assert_true(FileAccess.file_exists(SaveService.CORRUPT_PATH))
	assert_eq(_read_file_bytes(SaveService.CORRUPT_PATH), corrupt_save_bytes)
	_assert_distinctive_state()
	assert_ne(SaveService.take_load_notice(), "")
	assert_eq(SaveService.take_load_notice(), "")


func test_roster_change_after_corrupt_refusal_writes_a_new_save() -> void:
	var corrupt_save_bytes := "[1, 2, 3]".to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(corrupt_save_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	GameSession.add_hero(Hero.new(HERO_NAME, HERO_RANK))

	save_file = FileAccess.open(SaveService.SAVE_PATH, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return
	# Save files are untrusted JSON, so their parser result remains Variant until shape-checked.
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	assert_true(parsed is Dictionary)
	assert_eq(_read_file_bytes(SaveService.CORRUPT_PATH), corrupt_save_bytes)
	# SaveService outlives every test in this process, so an unread notice leaks into the next one.
	assert_ne(SaveService.take_load_notice(), "")


## A second corruption before the player has dealt with the first: the newer bad file replaces the
## older one rather than failing the rename, and still earns its own notice (docs/SYSTEMS.md).
func test_a_second_corrupt_save_overwrites_the_first_one_moved_aside() -> void:
	_write_save(SaveService.CORRUPT_PATH, "stale".to_utf8_buffer())
	var corrupt_save_bytes := "[4, 5, 6]".to_utf8_buffer()
	_write_save(SaveService.SAVE_PATH, corrupt_save_bytes)

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	assert_eq(_read_file_bytes(SaveService.CORRUPT_PATH), corrupt_save_bytes)
	assert_ne(SaveService.take_load_notice(), "")


func test_newer_version_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var newer_version_bytes := ('{"version": %d}' % (SaveService.SAVE_VERSION + 1)).to_utf8_buffer()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(newer_version_bytes)
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save is from a newer build")
	_assert_distinctive_state()
	assert_false(FileAccess.file_exists(SaveService.CORRUPT_PATH))
	assert_eq(_read_file_bytes(SaveService.SAVE_PATH), newer_version_bytes)


func test_missing_save_is_refused_without_error() -> void:
	_remove_file_if_exists(SaveService.SAVE_PATH)

	assert_false(SaveService.load_game())
	assert_push_error_count(0)


func _remove_file_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(remove_error, OK)


func _remove_temp_path() -> void:
	if FileAccess.file_exists(SaveService.TMP_PATH):
		_remove_file_if_exists(SaveService.TMP_PATH)
		return
	if DirAccess.dir_exists_absolute(SaveService.TMP_PATH):
		var remove_error: Error = DirAccess.remove_absolute(SaveService.TMP_PATH)
		assert_eq(remove_error, OK)


func _write_save(path: String, bytes: PackedByteArray) -> void:
	var save_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_buffer(bytes)
	save_file.close()


func _read_file_bytes(path: String) -> PackedByteArray:
	var save_file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(save_file)
	if save_file == null:
		return PackedByteArray()
	var bytes := save_file.get_buffer(save_file.get_length())
	save_file.close()
	return bytes


func _set_distinctive_state() -> void:
	var hero := Hero.new(HERO_NAME, HERO_RANK)
	hero.def_id = &"rogue"
	GameSession.add_hero(hero)
	var item := Item.new(ITEM_DEF_ID, ITEM_RANK)
	item.enhance_level = ITEM_ENHANCE_LEVEL
	GameSession.add_item(item)
	GameSession.parts = PARTS.duplicate()
	GameSession.stones = STONES
	GameSession.mark_zone_cleared(CLEARED_ZONE_ID)


func _assert_distinctive_state() -> void:
	assert_eq(GameSession.roster.size(), 1)
	var hero: Hero = GameSession.roster[0]
	assert_eq(hero.hero_name, HERO_NAME)
	assert_eq(hero.rank, HERO_RANK)
	assert_eq(hero.def_id, &"rogue")
	assert_eq(GameSession.inventory.size(), 1)
	var item: Item = GameSession.inventory[0]
	assert_eq(item.def_id, ITEM_DEF_ID)
	assert_eq(item.rank, ITEM_RANK)
	assert_eq(item.enhance_level, ITEM_ENHANCE_LEVEL)
	assert_eq(GameSession.parts, PARTS)
	assert_eq(GameSession.stones, STONES)
	assert_true(GameSession.cleared_zone_ids.has(CLEARED_ZONE_ID))
