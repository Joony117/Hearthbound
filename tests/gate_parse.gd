extends SceneTree

## ig-rd9: tests/import_gate.ps1 runs this with every standalone script under tests/ (the ones GUT
## doesn't run) after "--". It load()s each once the autoloads exist: --check-only compiles before
## they do, so it reports "Identifier not found: GameSession" on tests/stages/stage_play.gd. A parse
## or compile error prints SCRIPT ERROR / ERROR: with the file, which the gate greps; the exit code
## is the count of scripts that failed to load.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: int = 0
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	for path: String in paths:
		# A script that fails to parse still loads as a Script object; only can_instantiate says so.
		var script: Script = load(path) as Script
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("ERROR: gate_parse: %s failed to load" % path)
	print("gate_parse: %d scripts, %d failed" % [paths.size(), failed])
	quit(failed)
