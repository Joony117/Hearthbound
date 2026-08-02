extends CanvasLayer


func _on_resume_pressed() -> void:
	visible = false


func _on_menu_pressed() -> void:
	SceneRouter.go_to(SceneRouter.MAIN_MENU)
