extends Control

@onready var _save_notice: Label = %SaveNotice
@onready var _play: Button = %Play


func _ready() -> void:
	var notice := SaveService.take_load_notice()
	if SaveService.load_blocked:
		notice = SaveService.load_block_reason
		_play.disabled = true
		_play.tooltip_text = SaveService.load_block_reason
	_save_notice.text = notice
	_save_notice.visible = not notice.is_empty()


func _on_play_pressed() -> void:
	if SaveService.load_blocked:
		_save_notice.text = SaveService.load_block_reason
		_save_notice.visible = true
		return
	SceneRouter.go_to(SceneRouter.HUB)


func _on_quit_pressed() -> void:
	get_tree().quit()
