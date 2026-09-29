class_name Settings
extends RefCounted
## Display preferences the player controls, kept out of the save file on purpose.
##
## These are not game state, and `GameSession.to_dict()` is this repo's first-listed risky boundary
## (see CLAUDE.md) - routing a display toggle through it would buy a mandatory save round-trip
## verification for a value no game rule reads. Not an autoload either: static access needs no node,
## so the three-autoload cap in docs/ARCHITECTURE.md is untouched.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "combat"
const SCREEN_SHAKE_KEY: String = "screen_shake"
## How much a hit on bone or flesh throws in the battle view (ig-c9y.1): off adds nothing.
const GORE_KEY: String = "gore"
const GORE_LEVELS: Array[String] = ["off", "low", "full"]
const DEFAULT_GORE: String = "full"
const DISPLAY_SECTION: String = "display"
const WINDOW_SIZE_KEY: String = "window_size"
const FULLSCREEN: String = "fullscreen"
const DEFAULT_WINDOW_SIZE: String = "1920x1080"
## The 16:9 window sizes on offer, smallest first. The game still draws at 1280x720 and
## canvas_items stretches it (project.godot), so a size only changes the window.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

static var _config: ConfigFile
## The title bar and borders, last seen while windowed: a fullscreen window has none to measure.
static var _frame: Vector2i = Vector2i.ZERO


static func screen_shake_enabled() -> bool:
	var value: Variant = _loaded_config().get_value(SECTION, SCREEN_SHAKE_KEY, true)
	# A hand-edited settings file can put anything under the key. Anything that is not a bool means
	# the default, rather than a cast that turns "maybe" into false.
	if value is bool:
		return value as bool
	return true


static func set_screen_shake_enabled(enabled: bool) -> void:
	var config: ConfigFile = _loaded_config()
	config.set_value(SECTION, SCREEN_SHAKE_KEY, enabled)
	var save_error: Error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_error("Could not write %s: %s" % [SETTINGS_PATH, error_string(save_error)])


## One of GORE_LEVELS. Anything else in the file, a non-string included, means the default.
static func gore() -> String:
	var value: Variant = _loaded_config().get_value(SECTION, GORE_KEY, DEFAULT_GORE)
	if value is String and GORE_LEVELS.has(value):
		return value
	return DEFAULT_GORE


static func set_gore(level: String) -> void:
	var config: ConfigFile = _loaded_config()
	config.set_value(SECTION, GORE_KEY, level)
	var save_error: Error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_error("Could not write %s: %s" % [SETTINGS_PATH, error_string(save_error)])


## "1920x1080"-style or FULLSCREEN. Anything else in the file means the default.
static func window_size() -> String:
	var value: Variant = _loaded_config().get_value(DISPLAY_SECTION, WINDOW_SIZE_KEY, DEFAULT_WINDOW_SIZE)
	# Compared as text, so "01280x720" is not a size either.
	if value is String and (value == FULLSCREEN or (WINDOW_SIZES.has(size_of(value)) and size_name(size_of(value)) == value)):
		return value
	return DEFAULT_WINDOW_SIZE


static func set_window_size(choice: String) -> void:
	var config: ConfigFile = _loaded_config()
	config.set_value(DISPLAY_SECTION, WINDOW_SIZE_KEY, choice)
	var save_error: Error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_error("Could not write %s: %s" % [SETTINGS_PATH, error_string(save_error)])


static func size_name(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


## "1920x1080" -> Vector2i(1920, 1080); anything else -> Vector2i.ZERO.
static func size_of(choice: String) -> Vector2i:
	var parts: PackedStringArray = choice.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


## The window sizes that fit inside usable (a screen's usable area), smallest first.
static func window_sizes_for(usable: Vector2i) -> Array[String]:
	var names: Array[String] = []
	for size: Vector2i in WINDOW_SIZES:
		if size.x <= usable.x and size.y <= usable.y:
			names.append(size_name(size))
	return names


## What choice becomes on a screen that fits only fits: itself if it fits (or is FULLSCREEN),
## else the largest size that fits, else the smallest size there is.
static func effective_window_size(choice: String, fits: Array[String]) -> String:
	if choice == FULLSCREEN or fits.has(choice):
		return choice
	return fits.back() if not fits.is_empty() else size_name(WINDOW_SIZES[0])


static func window_mode_for(choice: String) -> DisplayServer.WindowMode:
	return DisplayServer.WINDOW_MODE_FULLSCREEN if choice == FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED


## The sizes that fit the screen the window is on, title bar and borders included.
static func window_sizes_here() -> Array[String]:
	var screen: int = DisplayServer.window_get_current_screen()
	return window_sizes_for(DisplayServer.screen_get_usable_rect(screen).size - _window_frame())


## What the window is now: FULLSCREEN, or its size. Headless has no window, so the saved choice.
static func window_size_now() -> String:
	if DisplayServer.get_name() == "headless":
		return window_size()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return FULLSCREEN
	return size_name(DisplayServer.window_get_size())


static func _window_frame() -> Vector2i:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_frame = DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	return _frame


## Sets the window to choice: fullscreen, or windowed at that size (or the largest that fits),
## centred in the usable area. Returns what it set. Headless has no window, so there it sets
## nothing and returns choice.
static func apply_window_size(choice: String) -> String:
	if DisplayServer.get_name() == "headless":
		return choice
	_window_frame()  # Measured while still windowed (it starts windowed), before fullscreen hides it.
	DisplayServer.window_set_mode(window_mode_for(choice))
	if choice == FULLSCREEN:
		return choice
	# Fullscreen turns the borderless flag on and leaving it does not turn it off. Windowed first,
	# too, so the fit check below counts the title bar a fullscreen window does not have.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var chosen: String = effective_window_size(choice, window_sizes_here())
	var size: Vector2i = size_of(chosen)
	DisplayServer.window_set_size(size)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Centre the outer frame (title bar included), then offset to where the client area sits in it.
	var outer: Vector2i = DisplayServer.window_get_size_with_decorations()
	var inset: Vector2i = DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
	DisplayServer.window_set_position(usable.position + ((usable.size - outer) / 2).max(Vector2i.ZERO) + inset)
	return chosen


## A missing or unreadable file is the first-run case, not an error: `ConfigFile.load()` leaves the
## object empty and every `get_value()` falls through to its default.
static func _loaded_config() -> ConfigFile:
	if _config != null:
		return _config
	_config = ConfigFile.new()
	_config.load(SETTINGS_PATH)
	return _config
