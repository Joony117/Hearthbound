extends Node
## The only thing that changes the main scene. Autoload.
## See docs/ARCHITECTURE.md rule 5 - no change_scene_to_file() anywhere else.

const MAIN_MENU := "res://ui/main_menu.tscn"
const HUB := "res://hub/hub.tscn"
const ARENA := "res://combat/arena/arena.tscn"

var arena_team: Array[Hero] = []
var arena_wave: Wave
var pending_arena_result: CombatResult


func prepare_arena(team: Array[Hero], wave: Wave) -> void:
	assert(team.size() == 1)
	assert(team[0] != null)
	assert(wave != null)
	arena_team = team.duplicate()
	arena_wave = wave
	pending_arena_result = null


func clear_arena_payload() -> void:
	arena_team.clear()
	arena_wave = null


func store_arena_result(result: CombatResult) -> void:
	assert(result != null)
	pending_arena_result = result


func take_arena_result() -> CombatResult:
	var result: CombatResult = pending_arena_result
	pending_arena_result = null
	return result


func reset_arena_transition_state() -> void:
	clear_arena_payload()
	pending_arena_result = null


func go_to(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Scene change to %s failed: %s" % [scene_path, error_string(err)])
