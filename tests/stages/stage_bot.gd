extends SceneTree

## ig-eek: the stage bot, run by hand, never from tests/unit. It builds the Early stage save:
##   APPDATA="$(cygpath -w "$(mktemp -d)")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/stages/stage_bot.gd -- --seed=1
## A -s script compiles before the autoloads exist, and so would every class it names, so the play
## (stage_play.gd) is loaded only once they do.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var play: RefCounted = load("res://tests/stages/stage_play.gd").new()
	quit(int(play.call("run", OS.get_cmdline_user_args())))
