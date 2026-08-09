class_name Arena
extends Node3D

signal scene_change_requested(scene_path: String)


func _ready() -> void:
	scene_change_requested.connect(SceneRouter.go_to)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	scene_change_requested.emit(SceneRouter.HUB)
