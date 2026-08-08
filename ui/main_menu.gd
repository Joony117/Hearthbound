extends Control

@onready var _save_notice: Label = %SaveNotice


func _ready() -> void:
	var notice := SaveService.take_load_notice()
	_save_notice.text = notice
	_save_notice.visible = not notice.is_empty()


func _on_play_pressed() -> void:
	SceneRouter.go_to(SceneRouter.HUB)


func _on_quit_pressed() -> void:
	get_tree().quit()
