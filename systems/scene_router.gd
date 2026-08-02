extends Node
## The only thing that changes the main scene. Autoload.
## See docs/ARCHITECTURE.md rule 5 - no change_scene_to_file() anywhere else.

const MAIN_MENU := "res://ui/main_menu.tscn"
const HUB := "res://hub/hub.tscn"


func go_to(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Scene change to %s failed: %s" % [scene_path, error_string(err)])
