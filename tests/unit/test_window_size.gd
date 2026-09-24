extends GutTest
## ig-qoz: the window-size setting (systems/settings.gd) and the pause-menu picker.

var _had_key: bool = false
var _kept: Variant


func before_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	_had_key = config.has_section_key(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY)
	_kept = config.get_value(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY) if _had_key else null


func after_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	if not _had_key:
		if config.has_section_key(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY):
			config.erase_section_key(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY)
	else:
		config.set_value(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY, _kept)
	config.save(Settings.SETTINGS_PATH)


func test_the_window_size_round_trips_through_disk_and_a_bad_value_is_the_default() -> void:
	for choice: String in ["2560x1440", Settings.FULLSCREEN, "1280x720"]:
		Settings.set_window_size(choice)
		Settings._config = null
		assert_eq(Settings.window_size(), choice)
	for bad: Variant in ["1024x768", "big", "1920x", "01280x720", "1920x1080 ", "1920X1080", 1920, true]:
		Settings._loaded_config().set_value(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY, bad)
		assert_eq(Settings.window_size(), "1920x1080", "bad value %s" % str(bad))
	Settings._loaded_config().erase_section_key(Settings.DISPLAY_SECTION, Settings.WINDOW_SIZE_KEY)
	assert_eq(Settings.window_size(), "1920x1080", "a missing key is the default")


func test_only_the_sizes_that_fit_are_listed() -> void:
	assert_eq(Settings.window_sizes_for(Vector2i(1920, 1080)), ["1280x720", "1600x900", "1920x1080"] as Array[String])
	assert_false(Settings.window_sizes_for(Vector2i(1920, 1080)).has("2560x1440"))
	assert_eq(Settings.window_sizes_for(Vector2i(3840, 2160)).size(), 5)
	# A 1080p screen minus its taskbar.
	assert_eq(Settings.window_sizes_for(Vector2i(1920, 1040)), ["1280x720", "1600x900"] as Array[String])
	assert_eq(Settings.window_sizes_for(Vector2i(1000, 600)), [] as Array[String])


func test_a_size_that_does_not_fit_becomes_the_largest_that_does() -> void:
	var fits: Array[String] = Settings.window_sizes_for(Vector2i(1920, 1040))
	assert_eq(Settings.effective_window_size("1920x1080", fits), "1600x900")
	assert_eq(Settings.effective_window_size("1280x720", fits), "1280x720")
	assert_eq(Settings.effective_window_size(Settings.FULLSCREEN, fits), Settings.FULLSCREEN)
	assert_eq(Settings.effective_window_size("1920x1080", [] as Array[String]), "1280x720")


func test_fullscreen_maps_to_fullscreen_mode() -> void:
	assert_eq(Settings.window_mode_for(Settings.FULLSCREEN), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(Settings.window_mode_for("1920x1080"), DisplayServer.WINDOW_MODE_WINDOWED)


func test_the_picker_lists_fullscreen_and_picking_saves_without_a_window() -> void:
	var pause_menu: CanvasLayer = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child_autofree(pause_menu)
	var picker: OptionButton = pause_menu.get_node("%WindowSize") as OptionButton
	var last: int = picker.item_count - 1
	# Headless lists no sizes and the saved 1920x1080 is not Fullscreen: nothing is ticked.
	assert_eq(picker.selected, -1, "no first item ticked by default")
	assert_eq(picker.get_item_text(last), "Fullscreen")
	assert_eq(picker.get_item_metadata(last), Settings.FULLSCREEN)

	# Headless: apply is a no-op, so this only proves the connection and the save.
	picker.select(last)
	picker.item_selected.emit(last)
	Settings._config = null
	assert_eq(Settings.window_size(), Settings.FULLSCREEN)
	assert_eq(DisplayServer.get_name(), "headless")


func test_the_picker_fills_again_when_the_menu_opens() -> void:
	var pause_menu: CanvasLayer = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child_autofree(pause_menu)
	var picker: OptionButton = pause_menu.get_node("%WindowSize") as OptionButton
	var count: int = picker.item_count
	picker.add_item("stale")
	pause_menu.visible = true
	assert_eq(picker.item_count, count, "reopening drops the stale list")
