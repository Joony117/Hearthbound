extends GutTest

## ig-7sn.18 (the threading ADR, item 7): each live battle's advance runs as a BattleJob.run_battle job and
## lands on a later frame, only while its order still holds the battle Dictionary it was sent from. ACC 3f
## (the frames a job may land on) is test_battle_session's _drive_frames and test_periodic_save_frame.

const Compare = preload("res://tests/unit/compare.gd")
const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const FRAME: float = 1.0 / 60.0

var _originals: Dictionary = {}
## The frames _frame ran since before_each.
var _frames: int = 0


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
	_frames = 0


func after_each() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH))
	_reset_clocks()
	GameSession.set("_checkpoint_save_failed", false)
	GameSession.set("_checkpoint_error", "")
	GameSession.from_dict({"roster": []})
	GameSession.set_process(true)


## ACC 3a: over 600 frames the jobs leave the battle where the main thread's advance by the same steps
## leaves it (_advance_battle's, which tick_expeditions runs), to the bit, with one decode. Every frame's
## time is advanced, owed or out in a job.
func test_jobs_leave_a_battle_where_the_main_thread_would() -> void:
	var order_id: String = _dispatch_live()
	var start: Dictionary = GameSession.expedition_orders[0]["battle"]
	var given: float = _accounted(order_id)
	var decodes: int = GameSession.pulse_decodes_active
	var advances: int = GameSession.pulse_battle_advances
	var steps: Array[float] = []
	var job: BattleJob = null
	for ignored_frame: int in 600:
		_frame()
		var entry: Dictionary = GameSession._battle_advances.get(order_id, {})
		if not entry.is_empty() and not is_same(entry["job"], job):
			job = entry["job"]
			steps.append(float(entry["seconds"]))
	if GameSession._battle_advances.has(order_id):
		steps.resize(steps.size() - 1)  # The last job is still out.
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(str(battle["status"]), "active", "setup: still fighting")
	assert_gt(steps.size(), 30, "the jobs advanced it")
	assert_eq(GameSession.pulse_battle_advances - advances, steps.size(), "each job but the one out landed")
	var replay := BattleState.from_dict(start)
	for seconds: float in steps:
		BattleSimulation.advance(replay, minf(seconds, maxf(replay.max_seconds - replay.elapsed_seconds, 0.0)))
	assert_eq(Compare.first_difference(battle, replay.to_dict()), "", "as the main thread's advance by the same steps")
	assert_eq(GameSession.pulse_decodes_active - decodes, 1, "decoded once, for the first job: each landing keeps its state")
	assert_almost_eq(_accounted(order_id) - given, _frames * FRAME, 0.0001, "every frame's time is advanced, owed or out")


## ACC 3b: a command while a job is out applies to the battle as it last landed. The job is dropped and its
## seconds owed again; the battle sends again from the commanded Dictionary, and catches up.
func test_a_command_while_a_job_is_out_drops_it_and_the_battle_catches_up() -> void:
	var order_id: String = _dispatch_live()
	var given: float = _accounted(order_id)
	var entry: Dictionary = _second_job(order_id)
	var landed: Dictionary = entry["battle"]
	var result: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_SET_ITEM_AUTO, "value": {"auto_heal": false, "auto_revive": true}})
	assert_true(bool(result["accepted"]), str(result))
	var commanded: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(float(commanded["elapsed_seconds"]), float(landed["elapsed_seconds"]), "the command applies to the landed battle")
	assert_gt(int(commanded["command_sequence"]), int(landed["command_sequence"]))
	var advances: int = GameSession.pulse_battle_advances
	var frames: int = _frames
	var resent: Dictionary = _until_sent(order_id, entry["job"])
	assert_true((entry["job"] as BattleJob).cancelled, "the job is dropped")
	assert_eq(GameSession.pulse_battle_advances, advances, "and nothing of it lands")
	assert_true(is_same(resent["battle"], commanded), "the battle sends again from the commanded Dictionary")
	assert_almost_eq(float(resent["seconds"]), float(entry["seconds"]) + (_frames - frames) * FRAME, 0.000001, "for the job's seconds and the frames' since")
	_until_landed()
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(int(battle["command_sequence"]), int(commanded["command_sequence"]), "the landing carries the command")
	assert_almost_eq(_accounted(order_id) - given, _frames * FRAME, 0.0001, "and the battle has caught up")


## ACC 3c: a pause while a job is out drops the job. The battle doesn't move while paused and is owed
## nothing, and the dropped job is still waited on (Godot frees a task only then).
func test_a_pause_drops_the_job_and_the_battle_holds_still() -> void:
	var order_id: String = _dispatch_live()
	var entry: Dictionary = _second_job(order_id)
	var job: BattleJob = entry["job"]
	var advances: int = GameSession.pulse_battle_advances
	GameSession.set_battle_paused(order_id, true)
	assert_false(GameSession._battle_advances.has(order_id), "the job is dropped")
	assert_true(job.cancelled, "and told to stop")
	_finish(job)
	for ignored_frame: int in 60:
		_frame()
	assert_true(is_same(GameSession.expedition_orders[0]["battle"], entry["battle"]), "the battle doesn't move")
	assert_eq(GameSession.pulse_battle_advances, advances, "nothing lands")
	assert_false(GameSession._battle_owed.has(order_id), "a paused battle is owed nothing")
	assert_false(GameSession._battle_jobs.has(job), "a pulse waited on the dropped job")


## ACC 3d, 5: a real save taken with a job out holds the battle as it last landed, and no new key. load_game
## cancels the job and nothing of it lands; the frames resume from the reloaded battle.
func test_a_save_holds_the_landed_battle_and_a_load_cancels_the_job() -> void:
	var order_id: String = _dispatch_live()
	assert_true(SaveService.save(), SaveService.last_write_error)
	var dispatched: Dictionary = _read_save()
	var entry: Dictionary = _second_job(order_id)
	var job: BattleJob = entry["job"]
	var landed: Dictionary = entry["battle"]
	assert_true(SaveService.save(), SaveService.last_write_error)
	var saved: Dictionary = _read_save()
	# Compared as SaveService writes it: a float32 Vector2 part, written in full, reads back a bit or two off.
	assert_eq(Compare.first_difference(saved["expedition_orders"][0]["battle"], Compare.json_round_trip(landed)), "", "the save holds the battle as it last landed")
	assert_eq(_sorted_keys(saved), _sorted_keys(dispatched), "no new key")
	assert_eq(_sorted_keys(saved["expedition_orders"][0]), _sorted_keys(dispatched["expedition_orders"][0]), "none on the order")
	# Reloaded through disk with no time away: time away would owe a catch-up, which stops the battle's clock.
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(saved)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_true(job.cancelled, "the load cancelled the job")
	assert_false(GameSession._battle_jobs.has(job), "and waited on it")
	assert_true(GameSession._battle_advances.is_empty(), "the job table is empty")
	var reloaded: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(Compare.first_difference(reloaded, Compare.json_round_trip(saved)["expedition_orders"][0]["battle"]), "", "the battle reloads as saved")
	var advances: int = GameSession.pulse_battle_advances
	var resent: Dictionary = _until_sent(order_id)
	assert_eq(GameSession.pulse_battle_advances, advances, "nothing of the cancelled job lands")
	assert_true(is_same(resent["battle"], reloaded), "the frames resume from the reloaded battle")
	_until_landed()
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_almost_eq(float(battle["elapsed_seconds"]) + float(battle["tick_remainder"]), float(landed["elapsed_seconds"]) + float(landed["tick_remainder"]) + float(resent["seconds"]), 0.0001, "by the seconds sent")


## ACC 3e: a failed periodic save while a job is out drops the job and owes its seconds again. No battle
## moves during the stall, nor is it owed the stall's time; after the retry it sends again from the
## Dictionary it last landed, for all it is owed.
func test_a_save_stall_drops_the_job_and_owes_its_seconds_again() -> void:
	var order_id: String = _dispatch_live()
	var entry: Dictionary = _second_job(order_id)
	var job: BattleJob = entry["job"]
	var owed: float = float(GameSession._battle_owed.get(order_id, 0.0))
	GameSession.set("_periodic_save_due", true)
	GameSession.set("_expedition_pulse_accumulator", 0.0)
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	_frame()
	assert_push_error("Save failed")
	assert_true(GameSession._checkpoint_save_failed, "the stall began")
	assert_false(GameSession._battle_advances.has(order_id), "the job is dropped")
	assert_true(job.cancelled)
	var stalled: float = float(GameSession._battle_owed.get(order_id, 0.0))
	assert_almost_eq(stalled, owed + FRAME + float(entry["seconds"]), 0.000001, "its seconds are owed again, beside the save frame's")
	var advances: int = GameSession.pulse_battle_advances
	for ignored_frame: int in 60:
		_frame()
	assert_true(is_same(GameSession.expedition_orders[0]["battle"], entry["battle"]), "no battle moves during the stall")
	assert_eq(GameSession.pulse_battle_advances, advances, "nothing lands")
	assert_eq(float(GameSession._battle_owed.get(order_id, 0.0)), stalled, "nor is it owed the stall's time")
	assert_false(GameSession._battle_jobs.has(job), "a stalled pulse waited on the dropped job")
	# The retry runs on the frame after the pulse that makes it due.
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	for ignored_frame: int in 60:
		if not GameSession._checkpoint_save_failed:
			break
		_frame()
	assert_false(GameSession._checkpoint_save_failed, "the retry ended the stall")
	var frames: int = _frames
	var resent: Dictionary = _until_sent(order_id)
	assert_true(is_same(resent["battle"], entry["battle"]), "it sends again from the Dictionary it last landed")
	assert_almost_eq(float(resent["seconds"]), stalled + (_frames - frames) * FRAME, 0.000001, "for all it is owed")


## ACC 3g: a landing keeps [battle, state], as the main thread's advance does, so the next job decodes
## nothing. A dropped job's state is thrown away: after a pause and an un-pause while a job is out, the next
## job starts from the Dictionary that last landed, decoded, and nothing of the dropped job lands.
func test_a_landing_keeps_its_state_and_a_dropped_one_is_thrown_away() -> void:
	var order_id: String = _dispatch_live()
	var first: Dictionary = _until_sent(order_id)
	_until_landed()
	var kept: Array = GameSession._battle_states.get(order_id, [])
	assert_true(kept.size() == 2 and is_same(kept[0], GameSession.expedition_orders[0]["battle"]), "the landing keeps the Dictionary it landed")
	assert_true(kept.size() == 2 and is_same(kept[1], first["state"]), "beside the state the job advanced")
	var decodes: int = GameSession.pulse_decodes_active
	var entry: Dictionary = _until_sent(order_id, first["job"])
	assert_eq(GameSession.pulse_decodes_active, decodes, "the next job takes the kept state")
	GameSession.set_battle_paused(order_id, true)
	GameSession.set_battle_paused(order_id, false)
	var advances: int = GameSession.pulse_battle_advances
	var resent: Dictionary = _until_sent(order_id, entry["job"])
	assert_eq(GameSession.pulse_battle_advances, advances, "nothing of the dropped job lands")
	assert_true(is_same(resent["battle"], entry["battle"]), "the next job starts from the Dictionary that last landed")
	assert_eq(GameSession.pulse_decodes_active, decodes + 1, "decoded: the dropped job's state is thrown away")
	_until_landed()
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	var landed: Dictionary = entry["battle"]
	assert_almost_eq(float(battle["elapsed_seconds"]) + float(battle["tick_remainder"]), float(landed["elapsed_seconds"]) + float(landed["tick_remainder"]) + float(resent["seconds"]), 0.0001, "it advanced from there by the seconds sent")


## ACC 3g (ig-7sn.16 ACC 6): a battle a job ends is kept too, so turning it home and settling it decode
## nothing, as the pulse's counters count.
func test_a_battle_a_job_ends_turns_home_and_settles_with_no_decode() -> void:
	var order_id: String = _dispatch_live()
	var order: Dictionary = GameSession.expedition_orders[0]
	var short: Dictionary = (order["battle"] as Dictionary).duplicate(true)
	short["max_seconds"] = float(short["elapsed_seconds"]) + 0.5
	order["battle"] = short
	order["remaining_seconds"] = 1.0
	for ignored_frame: int in 240:
		if str((GameSession.expedition_orders[0]["battle"] as Dictionary)["status"]) != "active":
			break
		_frame()
	var ended: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(str(ended["status"]), "timeout", "a job ended the battle")
	var kept: Array = GameSession._battle_states.get(order_id, [])
	assert_true(kept.size() == 2 and is_same(kept[0], ended), "the landing kept the ended battle's state")
	var active_decodes: int = GameSession.pulse_decodes_active
	var idle_decodes: int = GameSession.pulse_decodes_idle
	for ignored_frame: int in 240:
		if GameSession.expedition_orders.is_empty():
			break
		_frame()
	assert_true(GameSession.expedition_orders.is_empty(), "turned home and settled")
	assert_eq(GameSession.expedition_reports.size(), 1, "one report")
	assert_eq(GameSession.pulse_decodes_active, active_decodes, "no active decode")
	assert_eq(GameSession.pulse_decodes_idle, idle_decodes, "no idle decode")


## One level-0 Knight to verdant_outskirts for one run: its battle stays live for minutes.
func _dispatch_live() -> String:
	var hero := Hero.new("Jobber", 0)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var preset_id: String = GameSession.save_team_preset("", "Jobbers", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	return order_id


## One 60 fps frame, once every job out has finished (the game waits on a job only when it lands).
func _frame() -> void:
	_finish_advance_jobs()
	GameSession._process(FRAME)
	_frames += 1


## ig-7sn.18: waits until every advance job out has finished, so the next frame can land it. The game waits
## on a job only when it lands; a frame here runs what a real one would once its job is in.
func _finish_advance_jobs() -> void:
	for entry: Dictionary in GameSession._battle_advances.values():
		_finish(entry["job"])


## Waits until job's task has finished, while the game still holds it (a released one has).
func _finish(job: BattleJob) -> void:
	while GameSession._battle_jobs.has(job) and not WorkerThreadPool.is_task_completed(job.task_id):
		OS.delay_usec(100)


## Runs frames until order_id has a job out other than job; returns its entry.
func _until_sent(order_id: String, job: BattleJob = null) -> Dictionary:
	for ignored_frame: int in 120:
		var entry: Dictionary = GameSession._battle_advances.get(order_id, {})
		if not entry.is_empty() and not is_same(entry["job"], job):
			return entry
		_frame()
	fail_test("no job was sent for %s" % order_id)
	return {}


## Runs frames until a battle lands.
func _until_landed() -> void:
	var advances: int = GameSession.pulse_battle_advances
	for ignored_frame: int in 120:
		_frame()
		if GameSession.pulse_battle_advances > advances:
			return
	fail_test("no job landed")


## Lands order_id's first job, then runs frames until the next is out; returns its entry, whose battle is
## a landing's.
func _second_job(order_id: String) -> Dictionary:
	var first: Dictionary = _until_sent(order_id)
	_until_landed()
	return _until_sent(order_id, first["job"])


## The seconds order_id's battle has been given: advanced (elapsed and the tick remainder), owed, and out
## in a job.
func _accounted(order_id: String) -> float:
	var battle: Dictionary = GameSession.expedition_orders[GameSession._order_index(order_id)]["battle"]
	var out: Dictionary = GameSession._battle_advances.get(order_id, {})
	return float(battle["elapsed_seconds"]) + float(battle["tick_remainder"]) + float(GameSession._battle_owed.get(order_id, 0.0)) + float(out.get("seconds", 0.0))


func _sorted_keys(data: Dictionary) -> Array:
	var keys: Array = data.keys()
	keys.sort()
	return keys


func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary


func _write_save(data: Dictionary) -> void:
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	# Full precision, as SaveService writes (ig-85w): the reloaded battle must match the landed one to the bit.
	save_file.store_string(JSON.stringify(data, "\t", true, true))
	save_file.close()


func _reset_clocks() -> void:
	GameSession.set("_periodic_save_accumulator", 0.0)
	GameSession.set("_expedition_pulse_accumulator", 0.0)
	GameSession.set("_periodic_save_due", false)
