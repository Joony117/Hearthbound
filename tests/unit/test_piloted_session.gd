extends GutTest

## ig-gy0.6: the pilot table in GameSession (boundary #1, the save round trip). Piloting is view state: it rides each
## watched advance, rides a rollback as the pause does, and is never saved; the weaponskill set for the next swing is
## saved with the battle. Modeled on test_battle_advance_jobs.

const LOADOUT: Dictionary = {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}
const FRAME: float = 1.0 / 60.0
const LOCK_REFUSAL: String = "Another ability was just used; the ability lock holds."

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


## ACC 3: the pilot rides every job the frames send (before it goes out), through _owe_battles and
## _land_battle_advance; a change drops the job that was out and owes its seconds again, so the battle keeps its time.
func test_the_pilot_rides_each_job_sent_and_a_change_drops_the_one_out() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	var first: Dictionary = _until_sent(order_id)
	assert_eq((first["state"] as BattleState).piloted_id, "", "nobody piloted: the AI's")
	_until_landed()
	var second: Dictionary = _until_sent(order_id, first["job"])
	var accounted: float = _accounted(order_id)
	GameSession.set_battle_piloted(order_id, ally)
	assert_true((second["job"] as BattleJob).cancelled, "the job out was sent for the old pilot: dropped")
	assert_false(GameSession._battle_advances.has(order_id))
	assert_almost_eq(_accounted(order_id), accounted, 0.000001, "its seconds are owed again: the battle keeps its time")
	assert_eq(GameSession.get_battle_snapshot(order_id)["piloted"], ally)

	var third: Dictionary = _until_sent(order_id, second["job"])
	assert_eq((third["state"] as BattleState).piloted_id, ally, "the next job takes the pilot")
	GameSession.set_battle_piloted(order_id, ally)
	assert_false((third["job"] as BattleJob).cancelled, "the same pilot again changes nothing")
	_until_landed()
	var kept: Array = GameSession._battle_states.get(order_id, [])
	assert_true(kept.size() == 2 and (kept[1] as BattleState).piloted_id == ally, "the landing kept the state that was piloted")

	var fourth: Dictionary = _until_sent(order_id, third["job"])
	GameSession.set_battle_piloted(order_id, "")
	assert_true((fourth["job"] as BattleJob).cancelled, "handing the hero back drops the job too")
	assert_eq(GameSession.get_battle_snapshot(order_id)["piloted"], "")
	var fifth: Dictionary = _until_sent(order_id, fourth["job"])
	assert_eq((fifth["state"] as BattleState).piloted_id, "", "and the next job is the AI's")

	GameSession.set_battle_piloted("order:none", ally)
	assert_false(GameSession._piloted_battle_actors.has("order:none"), "an order that does not exist holds no pilot")


## The main thread's advance (tick_expeditions) takes the pilot too.
func test_the_main_thread_advance_takes_the_pilot() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	GameSession.set_battle_piloted(order_id, ally)
	GameSession.tick_expeditions(0.5)
	assert_eq((GameSession._battle_states[order_id][1] as BattleState).piloted_id, ally)
	GameSession.set_battle_piloted(order_id, "")
	GameSession.tick_expeditions(0.5)
	assert_eq((GameSession._battle_states[order_id][1] as BattleState).piloted_id, "")


## ACC 3 + boundary #1: a real save written while piloting holds no pilot flag anywhere, and a load leaves
## nobody piloted (the offline catch-up after it is a fresh state, never piloted).
func test_a_checkpoint_written_while_piloting_has_no_pilot_and_a_reload_leaves_nobody_piloted() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	var first: Dictionary = _until_sent(order_id)
	_until_landed()
	GameSession.set_battle_piloted(order_id, ally)
	assert_true(SaveService.save(), SaveService.last_write_error)
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	assert_false(text.contains("piloted"), "no pilot key in the save file")
	var saved: Dictionary = _read_save()
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(saved)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.get_battle_snapshot(order_id)["piloted"], "", "a reload leaves no hero piloted")
	assert_true(GameSession._piloted_battle_actors.is_empty())
	var resent: Dictionary = _until_sent(order_id, first["job"])
	assert_eq((resent["state"] as BattleState).piloted_id, "", "and the frames after it are the AI's")


## G2: the pilot table rides a rollback as the pause does. A command whose save fails is refused and the hero stays
## piloted; a command that lands keeps it; a profile read (load, reset) clears it.
func test_the_pilot_survives_a_failed_save_and_a_landed_command_and_a_profile_read_clears_it() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	GameSession.set_battle_piloted(order_id, ally)
	var hold: Dictionary = {"kind": BattleSimulation.COMMAND_HOLD, "actor_ids": [ally]}
	assert_true(bool(GameSession.issue_battle_command(order_id, hold)["accepted"]))
	assert_eq(GameSession.get_battle_snapshot(order_id)["piloted"], ally, "a command that lands keeps the pilot")
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	var refused: Dictionary = GameSession.issue_battle_command(order_id, hold)
	assert_push_error("Save failed")
	assert_false(bool(refused["accepted"]), "the save failed: the command is refused")
	assert_eq(GameSession.get_battle_snapshot(order_id)["piloted"], ally, "and the hero stays piloted")
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.TMP_PATH)), OK)
	GameSession.from_dict(GameSession.to_dict())
	assert_true(GameSession._piloted_battle_actors.is_empty(), "a profile read clears it")


## F2: settlement removes the order and leaves its pilot entry; handing the hero back for a finished order erases it,
## with no job to drop and nobody told. Run on the real GameSession, through the real settlement of the run.
func test_a_finished_orders_pilot_entry_is_erased_when_the_hero_is_handed_back() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	GameSession.set_battle_piloted(order_id, ally)
	var battle: Dictionary = (GameSession.expedition_orders[0]["battle"] as Dictionary).duplicate(true)
	battle["status"] = "victory"
	GameSession.expedition_orders[0]["battle"] = battle
	GameSession.expedition_orders[0]["remaining_seconds"] = 0.0
	for ignored_pulse: int in 40:
		if GameSession._order_index(order_id) < 0:
			break
		GameSession.tick_expeditions(0.25)
	assert_lt(GameSession._order_index(order_id), 0, "setup: the run settled and its order is gone")
	assert_eq(GameSession.expedition_reports.size(), 1, "setup: by the real settlement")
	assert_true(GameSession._piloted_battle_actors.has(order_id), "setup: settlement leaves the entry")
	watch_signals(GameSession)
	GameSession.set_battle_piloted(order_id, "")
	assert_false(GameSession._piloted_battle_actors.has(order_id), "handed back: the entry is gone")
	assert_signal_not_emitted(GameSession, "battle_changed", "nobody to tell")
	GameSession.set_battle_piloted(order_id, ally)
	assert_false(GameSession._piloted_battle_actors.has(order_id), "and a gone order still cannot take a pilot")


## ACC 2 (tactical pause) + boundary #1: a paused battle takes a hand cast at once and the ability lock holds the
## next one until time runs; the weaponskill set for the next swing goes to the disk with the battle and comes back,
## and a checkpoint from before it (no key) loads.
func test_a_paused_battle_takes_a_hand_cast_at_once_and_the_swing_skill_survives_a_real_save_and_reload() -> void:
	var order_id: String = _dispatch_live()
	var ally: String = _ally_id(order_id)
	var enemy: String = _enemy_id(order_id)
	GameSession.set_battle_paused(order_id, true)
	var elapsed: float = float(GameSession.expedition_orders[0]["battle"]["elapsed_seconds"])
	var swing: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_USE_SKILL, "actor_ids": [ally], "skill_id": "knight_iron_cut", "target_id": enemy})
	assert_true(bool(swing["accepted"]), str(swing))
	var rally: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_USE_SKILL, "actor_ids": [ally], "skill_id": "knight_rally"})
	assert_true(bool(rally["accepted"]), str(rally))
	var battle: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(float(battle["elapsed_seconds"]), elapsed, "both at once: no battle time ran")
	assert_gt(float(_actor(battle, ally)["skill_cooldowns"]["knight_rally"]), 0.0, "the cast is on cooldown")
	assert_eq(_actor(battle, ally)["effect_state"]["next_swing_skill"], "knight_iron_cut")
	var second: String = _other_ability(_actor(battle, ally), "knight_rally")
	assert_ne(second, "", "setup: the bar has a second ability")
	var locked: Dictionary = GameSession.issue_battle_command(order_id, {"kind": BattleSimulation.COMMAND_USE_SKILL, "actor_ids": [ally], "skill_id": second, "target_id": enemy})
	assert_false(bool(locked["accepted"]))
	assert_eq(locked["error"], LOCK_REFUSAL, "the lock holds a second until battle time runs")

	# The weaponskill is in the file, and reads back off the disk.
	var saved: Dictionary = _read_save()
	var saved_battle: Dictionary = saved["expedition_orders"][0]["battle"]
	assert_eq(_actor(saved_battle, ally)["effect_state"]["next_swing_skill"], "knight_iron_cut", "saved with the battle")
	assert_false(FileAccess.get_file_as_string(SaveService.SAVE_PATH).contains("piloted"))
	saved["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(saved)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var reloaded: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_eq(_actor(reloaded, ally)["effect_state"]["next_swing_skill"], "knight_iron_cut", "and it came back")
	assert_eq(BattleSimulation.validate_snapshot(reloaded), "")
	var decoded: BattleState = BattleState.from_dict(reloaded)
	for actor: BattleActor in decoded.actors:
		if actor.id == ally:
			assert_eq(actor.effect_state["next_swing_skill"], "knight_iron_cut", "and it decodes onto the actor")

	# A checkpoint from before this build has no key: it loads.
	(_actor(saved_battle, ally)["effect_state"] as Dictionary).erase("next_swing_skill")
	_write_save(saved)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	var legacy: Dictionary = GameSession.expedition_orders[0]["battle"]
	assert_false((_actor(legacy, ally)["effect_state"] as Dictionary).has("next_swing_skill"))
	assert_eq(BattleSimulation.validate_snapshot(legacy), "")


## One level-0 Knight to verdant_outskirts for one run: its battle stays live for minutes.
func _dispatch_live() -> String:
	var hero := Hero.new("Pilot", 0)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var preset_id: String = GameSession.save_team_preset("", "Pilots", [hero.instance_id], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, LOADOUT)
	assert_ne(order_id, "", GameSession.last_action_error)
	return order_id


func _ally_id(order_id: String) -> String:
	return str(_first(order_id, "ally")["id"])


func _enemy_id(order_id: String) -> String:
	return str(_first(order_id, "enemy")["id"])


func _first(order_id: String, faction: String) -> Dictionary:
	var battle: Dictionary = GameSession.expedition_orders[GameSession._order_index(order_id)]["battle"]
	return (battle["actors"] as Array).filter(func(actor: Dictionary) -> bool: return actor["faction"] == faction and actor["life"] == "alive")[0]


func _actor(battle: Dictionary, actor_id: String) -> Dictionary:
	return (battle["actors"] as Array).filter(func(actor: Dictionary) -> bool: return actor["id"] == actor_id)[0]


## The first ability on the actor's bar that is not skip_id.
func _other_ability(actor: Dictionary, skip_id: String) -> String:
	for entry: Dictionary in actor["skills"]:
		var skill: AbilityDefinition = BattleSimulation.ABILITIES[entry["id"]]
		if skill.is_ability() and entry["id"] != skip_id:
			return str(entry["id"])
	return ""


## One 60 fps frame, once every job out has finished (the game waits on a job only when it lands).
func _frame() -> void:
	for entry: Dictionary in GameSession._battle_advances.values():
		_finish(entry["job"])
	GameSession._process(FRAME)


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


## The seconds order_id's battle has been given: advanced, owed, and out in a job.
func _accounted(order_id: String) -> float:
	var battle: Dictionary = GameSession.expedition_orders[GameSession._order_index(order_id)]["battle"]
	var out: Dictionary = GameSession._battle_advances.get(order_id, {})
	return float(battle["elapsed_seconds"]) + float(battle["tick_remainder"]) + float(GameSession._battle_owed.get(order_id, 0.0)) + float(out.get("seconds", 0.0))


func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary


func _write_save(data: Dictionary) -> void:
	var save_file: FileAccess = FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	assert_not_null(save_file)
	if save_file == null:
		return
	# Full precision, as SaveService writes (ig-85w).
	save_file.store_string(JSON.stringify(data, "\t", true, true))
	save_file.close()


func _reset_clocks() -> void:
	GameSession.set("_periodic_save_accumulator", 0.0)
	GameSession.set("_expedition_pulse_accumulator", 0.0)
	GameSession.set("_periodic_save_due", false)
