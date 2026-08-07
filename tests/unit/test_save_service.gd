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
	if not _original_save_existed:
		if FileAccess.file_exists(SaveService.SAVE_PATH):
			var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.SAVE_PATH))
			assert_eq(remove_error, OK)
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


func test_non_dictionary_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_string("[1, 2, 3]")
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save file is corrupt")
	_assert_distinctive_state()


func test_newer_version_save_is_refused_without_resetting_game_session() -> void:
	_set_distinctive_state()
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	save_file.store_string('{"version": %d}' % (SaveService.SAVE_VERSION + 1))
	save_file.close()

	assert_false(SaveService.load_game())
	assert_push_error("Save is from a newer build")
	_assert_distinctive_state()


func test_missing_save_is_refused_without_error() -> void:
	if FileAccess.file_exists(SaveService.SAVE_PATH):
		var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.SAVE_PATH))
		assert_eq(remove_error, OK)

	assert_false(SaveService.load_game())
	assert_push_error_count(0)


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
