extends Control


func _on_play_pressed() -> void:
	SceneRouter.go_to(SceneRouter.HUB)


func _on_quit_pressed() -> void:
	get_tree().quit()
