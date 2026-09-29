extends CanvasLayer

@onready var _screen_shake: CheckButton = %ScreenShake
@onready var _gore: OptionButton = %Gore
@onready var _window_size: OptionButton = %WindowSize


func _ready() -> void:
	# Not `button_pressed =`: the assignment emits `toggled`, and the pause menu is a static child of
	# hub.tscn, so every hub load wrote the setting straight back to user://settings.cfg.
	_screen_shake.set_pressed_no_signal(Settings.screen_shake_enabled())
	# Off, Low and Full, the stored one ticked. select() emits nothing, so filling never writes it back.
	for level: String in Settings.GORE_LEVELS:
		_gore.add_item(level.capitalize())
		_gore.set_item_metadata(_gore.item_count - 1, level)
	_gore.select(Settings.GORE_LEVELS.find(Settings.gore()))
	_fill_window_sizes()
	# Filled again each time it opens: the window may have moved to a smaller screen since.
	visibility_changed.connect(func() -> void: if visible: _fill_window_sizes())


## Only the sizes that fit this screen, plus Fullscreen, with what the window is now ticked (none
## if a monitor move left it at a size that no longer fits). select() emits nothing, so filling it
## never writes the setting back.
func _fill_window_sizes() -> void:
	var fits: Array[String] = Settings.window_sizes_here()
	var current: String = Settings.window_size_now()
	var choices: Array[String] = fits.duplicate()
	choices.append(Settings.FULLSCREEN)
	_window_size.clear()
	var ticked: int = -1
	for choice: String in choices:
		_window_size.add_item("Fullscreen" if choice == Settings.FULLSCREEN else choice)
		_window_size.set_item_metadata(_window_size.item_count - 1, choice)
		if choice == current:
			ticked = _window_size.item_count - 1
	# Not left to add_item(), which ticks the first item it adds.
	_window_size.select(ticked)


func _on_resume_pressed() -> void:
	visible = false


func _on_menu_pressed() -> void:
	SceneRouter.go_to(SceneRouter.MAIN_MENU)


func _on_screen_shake_toggled(toggled_on: bool) -> void:
	Settings.set_screen_shake_enabled(toggled_on)


func _on_gore_item_selected(index: int) -> void:
	Settings.set_gore(str(_gore.get_item_metadata(index)))


func _on_window_size_item_selected(index: int) -> void:
	var choice: String = str(_window_size.get_item_metadata(index))
	# Saves what was really set, so the picker and the file never disagree with the window.
	Settings.set_window_size(Settings.apply_window_size(choice))
	_fill_window_sizes()
