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

static var _config: ConfigFile


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


## A missing or unreadable file is the first-run case, not an error: `ConfigFile.load()` leaves the
## object empty and every `get_value()` falls through to its default.
static func _loaded_config() -> ConfigFile:
	if _config != null:
		return _config
	_config = ConfigFile.new()
	_config.load(SETTINGS_PATH)
	return _config
