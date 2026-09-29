extends GutTest

## ig-7sn.10 (fix 2, ACC 5): the 15 s periodic save runs on the frame after the pulse that made it due,
## never beside _pulse or a battle advance. On its frame each live battle is still owed the frame's time.
## ig-7sn.18 (ACC 3f): an advance is a job's landing now; _frame lets every job out finish first.
## A transaction still saves inside itself, and a failed save still rolls it back.

const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const FRAME: float = 1.0 / 60.0

var _originals: Dictionary = {}


func before_all() -> void:
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		if FileAccess.file_exists(path):
			_originals[path] = FileAccess.get_file_as_bytes(path)


func after_all() -> void:
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		if _originals.has(path):
			FileAccess.open(path, FileAccess.WRITE).store_buffer(_originals[path])
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	GameSession.from_dict({"roster": []})
	_reset_clocks()


func after_each() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH))
	_reset_clocks()
	GameSession.set("_checkpoint_save_failed", false)
	GameSession.set("_checkpoint_error", "")
	GameSession.from_dict({"roster": []})
	GameSession.set_process(true)


## Frames at 60 fps across the 15 s line with three battles live: each call runs the pulse, the save or one
## advance, never two of them. The save runs on the call right after the pulse that crossed the line.
func test_the_periodic_save_gets_a_frame_of_its_own() -> void:
	_dispatch(3)
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.3)
	var calls: Array[Dictionary] = []
	for frame: int in 60:
		calls.append(_frame(FRAME))
	var saves: Array[int] = []
	var pulses: int = 0
	var advances: int = 0
	for index: int in calls.size():
		var record: Dictionary = calls[index]
		assert_true(int(record["advanced"]) <= 1, "call %d advances at most one battle" % index)
		if bool(record["pulse"]):
			pulses += 1
			assert_eq(int(record["advanced"]), 0, "call %d: the pulse's frame advances none" % index)
		advances += int(record["advanced"])
		if bool(record["saved"]):
			saves.append(index)
	assert_eq(saves.size(), 1, "one periodic save in the second")
	assert_gt(pulses, 2, "the pulses ran")
	assert_gt(advances, 3, "the battles advanced")
	var save_call: Dictionary = calls[saves[0]]
	assert_false(bool(save_call["pulse"]), "not on a pulse's frame")
	assert_eq(int(save_call["advanced"]), 0, "no battle advances on the save's frame")
	assert_true(bool(calls[saves[0] - 1]["pulse"]), "the pulse just before it made the save due")
	assert_true(bool(calls[saves[0] - 1]["due"]), "and left it due")
	assert_false(bool(save_call["due"]), "the save's frame clears it")
	# On the save's frame, every live battle is still owed the frame's time.
	var before: Dictionary = save_call["owed_before"]
	var after: Dictionary = save_call["owed_after"]
	assert_eq(after.size(), 3, "every live battle is owed")
	for order_id: String in after:
		assert_almost_eq(float(after[order_id]), float(before.get(order_id, 0.0)) + FRAME, 0.000001, "%s is owed the save frame's delta" % order_id)
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_almost_eq(float(on_disk["saved_at_unix"]), GameSession.saved_at_unix, 0.001, "the file is the save's")


## Below 4 fps every frame is a pulse's: the due save runs at the start of the next frame, then that
## frame's pulse. ig-7sn.18 (Sol): no battle lands there; it is owed the frame and lands on the next.
func test_below_4_fps_the_due_save_runs_before_the_next_pulse() -> void:
	_dispatch(1)
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	var crossing: Dictionary = _frame(0.3)
	assert_true(bool(crossing["pulse"]), "a pulse's frame")
	assert_false(bool(crossing["saved"]), "the crossing pulse only makes the save due")
	assert_true(bool(crossing["due"]))
	assert_eq(GameSession._battle_advances.size(), 1, "the crossing frame sent a job")
	var next: Dictionary = _frame(0.3)
	assert_true(bool(next["saved"]), "the next frame saves")
	assert_true(bool(next["pulse"]), "and runs its pulse after")
	assert_false(bool(next["due"]))
	assert_eq(int(next["advanced"]), 0, "no battle lands on the save's frame")
	assert_almost_eq(float((next["owed_after"] as Dictionary).values()[0]), 0.3, 0.000001, "it is owed the save's frame")
	assert_eq(int(_frame(0.3)["advanced"]), 1, "the frame after lands it")


## A blocked load never tries the due save.
func test_a_blocked_load_never_runs_the_due_save() -> void:
	_dispatch(1)
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	_frame(0.25)
	assert_true(bool(GameSession.get("_periodic_save_due")))
	var saved_at: float = GameSession.saved_at_unix
	SaveService.load_blocked = true
	GameSession._process(FRAME)
	assert_eq(GameSession.saved_at_unix, saved_at, "no save while the load is blocked")
	SaveService.load_blocked = false


## A failed periodic save starts the stall on its own frame; the retry, a pulse's 15 s later, also runs on
## the frame after that pulse and ends it.
func test_the_checkpoint_retry_also_runs_on_the_frame_after_its_pulse() -> void:
	_dispatch(1)
	assert_true(SaveService.save(), SaveService.last_write_error)
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	_frame(0.25)
	assert_false(bool(GameSession.get("_checkpoint_save_failed")), "the pulse did not save")
	_frame(FRAME)
	assert_push_error("Save failed")
	assert_true(bool(GameSession.get("_checkpoint_save_failed")), "the save's frame failed")
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	var pulse: Dictionary = _frame(0.25)
	assert_false(bool(pulse["saved"]), "the retry's pulse only makes it due")
	assert_true(bool(GameSession.get("_checkpoint_save_failed")))
	var retry: Dictionary = _frame(FRAME)
	assert_true(bool(retry["saved"]), "the retry saves on the next frame")
	assert_false(bool(GameSession.get("_checkpoint_save_failed")), "and ends the stall")


## A transaction still saves inside itself, even with the periodic save due, and a failed save still
## rolls it back.
func test_a_transaction_still_saves_inside_itself_and_rolls_back_on_a_failed_save() -> void:
	_dispatch(1)
	var idle := Hero.new("Idle", 0)
	idle.def_id = &"knight"
	GameSession.add_hero(idle)
	assert_true(SaveService.save(), SaveService.last_write_error)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	_frame(0.25)
	assert_true(bool(GameSession.get("_periodic_save_due")))
	var saved_at: float = GameSession.saved_at_unix
	assert_true(GameSession.set_hero_favorite(idle, true), GameSession.last_action_error)
	assert_ne(GameSession.saved_at_unix, saved_at, "the action saved inside itself")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	var favorite: bool = false
	for hero: Dictionary in on_disk["roster"]:
		if str(hero["instance_id"]) == idle.instance_id:
			favorite = bool(hero["favorite"])
	assert_true(favorite, "the file has the favorite before the next frame")
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	assert_false(GameSession.set_hero_favorite(idle, false))
	assert_push_error("Save failed")
	assert_true(GameSession.hero_by_id(idle.instance_id).favorite, "rolled back")


## Dispatches count one-Knight orders to verdant_outskirts; returns the heroes.
func _dispatch(count: int) -> Array[Hero]:
	var heroes: Array[Hero] = []
	for index: int in count:
		var hero := Hero.new("Runner %d" % index, 7)
		hero.def_id = &"knight"
		hero.level = 80
		GameSession.add_hero(hero)
		heroes.append(hero)
		var preset_id: String = GameSession.save_team_preset("", "Runners %d" % index, [hero.instance_id], "verdant_outskirts")
		assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 99, {}, LOADOUT), "", GameSession.last_action_error)
	return heroes


## One _process call and what it did: the pulse ran (its accumulator reset), a save landed (saved_at moved),
## how many battles advanced (their Dictionary replaced), the save still due after it, and each battle's
## owed time before and after.
func _frame(delta: float) -> Dictionary:
	var battles: Dictionary = {}
	for order: Dictionary in GameSession.expedition_orders:
		battles[order["id"]] = order.get("battle")
	var saved_at: float = GameSession.saved_at_unix
	var owed_before: Dictionary = (GameSession.get("_battle_owed") as Dictionary).duplicate()
	_finish_advance_jobs()
	GameSession._process(delta)
	var advanced: int = 0
	for order: Dictionary in GameSession.expedition_orders:
		if battles.has(order["id"]) and not is_same(battles[order["id"]], order.get("battle")):
			advanced += 1
	return {
		"pulse": float(GameSession.get("_expedition_pulse_accumulator")) == 0.0,
		"saved": GameSession.saved_at_unix != saved_at,
		"advanced": advanced,
		"due": bool(GameSession.get("_periodic_save_due")),
		"owed_before": owed_before,
		"owed_after": (GameSession.get("_battle_owed") as Dictionary).duplicate(),
	}


## ig-7sn.18: waits until every advance job out has finished, so the next frame can land it. The game waits
## on a job only when it lands; a frame here runs what a real one would once its job is in.
func _finish_advance_jobs() -> void:
	for entry: Dictionary in GameSession._battle_advances.values():
		var job: BattleJob = entry["job"]
		while GameSession._battle_jobs.has(job) and not WorkerThreadPool.is_task_completed(job.task_id):
			OS.delay_usec(100)


func _reset_clocks() -> void:
	GameSession.set("_periodic_save_accumulator", 0.0)
	GameSession.set("_expedition_pulse_accumulator", 0.0)
	GameSession.set("_periodic_save_due", false)
