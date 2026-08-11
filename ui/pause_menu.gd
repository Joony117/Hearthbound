extends CanvasLayer

@onready var _screen_shake: CheckButton = %ScreenShake


func _ready() -> void:
	_screen_shake.button_pressed = Settings.screen_shake_enabled()


func _on_resume_pressed() -> void:
	visible = false


func _on_menu_pressed() -> void:
	SceneRouter.go_to(SceneRouter.MAIN_MENU)


func _on_screen_shake_toggled(toggled_on: bool) -> void:
	Settings.set_screen_shake_enabled(toggled_on)
