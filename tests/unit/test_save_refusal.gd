extends GutTest

## ig-6pm: save() refuses to write a file this build's own load would refuse. A refusal touches
## neither save.json nor ledger.jsonl, and the player's last save still loads.

const REASON: String = "Invalid stranded incident checkpoint: Battle hero squad_id must match squad membership."
const REFUSED: String = "Save refused: this game state would not load (%s). Your last save is safe; restart to return to it."

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
	_reset_checkpoint()


func after_each() -> void:
	_reset_checkpoint()
	GameSession.from_dict({"roster": []})
	GameSession.set_process(true)


func test_an_action_on_a_state_that_would_not_load_is_refused_and_rolled_back() -> void:
	var hero: Hero = _add_hero("Mira")
	var stranded: Hero = _add_hero("Stranded")
	var kept: Dictionary = _good_save()
	_add_bad_incident(stranded)
	assert_false(GameSession.set_hero_favorite(hero, true))
	assert_push_error("Save refused")
	assert_eq(GameSession.last_action_error, REFUSED % REASON)
	assert_false(GameSession.hero_by_id(hero.instance_id).favorite, "rolled back")
	_assert_files_unchanged(kept)
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_false(GameSession.hero_by_id(hero.instance_id).favorite)
	assert_eq(GameSession.stranded_incidents.size(), 0, "the last good save")


func test_a_refused_commit_leaves_the_ledger_without_an_orphan_line() -> void:
	var hero: Hero = _add_hero("Mira")
	var stranded: Hero = _add_hero("Stranded")
	GameSession._record("ranked_up", {"hero": hero.instance_id, "from": 0, "to": 1, "via": "essence"})
	var kept: Dictionary = _good_save()
	assert_true(kept[SaveService.LEDGER_PATH] is PackedByteArray and not (kept[SaveService.LEDGER_PATH] as PackedByteArray).is_empty(), "the ledger has a line to keep")
	var ledger_size: int = GameSession.ledger.size()
	_add_bad_incident(stranded)
	assert_false(GameSession._commit_profile_mutation(func() -> void: GameSession._record("ranked_up", {"hero": hero.instance_id, "from": 1, "to": 2, "via": "essence"})))
	assert_push_error("Save refused")
	assert_eq(GameSession.ledger.size(), ledger_size, "rolled back in memory")
	_assert_files_unchanged(kept)
	# The refusal advanced no ledger bookkeeping: the next good save writes every line, none skipped.
	GameSession.stranded_incidents.clear()
	assert_true(GameSession._commit_profile_mutation(func() -> void: GameSession._record("ranked_up", {"hero": hero.instance_id, "from": 1, "to": 2, "via": "essence"})), GameSession.last_action_error)
	assert_eq(GameSession.ledger.size(), ledger_size + 1)
	var seqs: Array = GameSession.ledger.map(func(record: Dictionary) -> int: return int(record["seq"]))
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
	assert_eq(GameSession.ledger.map(func(record: Dictionary) -> int: return int(record["seq"])), seqs, "every line reloads from disk")


## ig-7sn.15: a refused save rolls the profile back through from_dict, but the battles keep the time
## they are owed.
func test_a_refused_save_keeps_the_battles_owed_time() -> void:
	var hero: Hero = _add_hero("Runner")
	var stranded: Hero = _add_hero("Stranded")
	var preset_id: String = GameSession.save_team_preset("", "Runners", [hero.instance_id], "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}), "", GameSession.last_action_error)
	var kept: Dictionary = _good_save()
	GameSession._process(0.1)
	var owed: Dictionary = GameSession._battle_owed.duplicate()
	assert_eq(owed.size(), 1, "the battle is owed time")
	_add_bad_incident(stranded)
	assert_false(GameSession.set_hero_favorite(hero, true))
	assert_push_error("Save refused")
	assert_eq(GameSession._battle_owed, owed, "kept through the rollback")
	_assert_files_unchanged(kept)


func test_a_periodic_save_is_refused_and_marks_the_checkpoint_failed() -> void:
	var hero: Hero = _add_hero("Runner")
	var stranded: Hero = _add_hero("Stranded")
	var preset_id: String = GameSession.save_team_preset("", "Runners", [hero.instance_id], "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}), "", GameSession.last_action_error)
	var kept: Dictionary = _good_save()
	_add_bad_incident(stranded)
	GameSession._process(GameSession.PERIODIC_SAVE_SECONDS + 0.1)
	GameSession._process(0.01)  # ig-7sn.10: the periodic save runs on the frame after its pulse.
	assert_push_error("Save refused")
	assert_true(bool(GameSession.get("_checkpoint_save_failed")))
	assert_eq(str(GameSession.get("_checkpoint_error")), REFUSED % REASON)
	_assert_files_unchanged(kept)


func test_a_signal_save_is_refused() -> void:
	var stranded: Hero = _add_hero("Stranded")
	var kept: Dictionary = _good_save()
	_add_bad_incident(stranded)
	GameSession.roster_changed.emit()
	assert_push_error("Save refused")
	_assert_files_unchanged(kept)


# Checked on the text, not the dict: a NaN does not survive JSON, so load would refuse it.
func test_a_non_finite_number_is_refused() -> void:
	_add_hero("Mira")
	var kept: Dictionary = _good_save()
	GameSession.recovery_clock_seconds = NAN
	assert_false(SaveService.save())
	assert_push_error("Save refused")
	# The engine warns about a NaN in JSON.stringify once per process, so this test may or may not see it.
	for error: Variant in get_errors():
		if error.contains_text("NaN"):
			error.handled = true
	assert_string_contains(SaveService.last_write_error, "Save refused: this game state would not load (")
	_assert_files_unchanged(kept)


## ig-7sn.10 ACC 3: the check runs on the exact text written, compact since ig-7sn.10. A NaN actor
## position does not survive the text, so load would refuse it: refused, and no file changes.
func test_a_nan_actor_position_is_refused_and_writes_no_file() -> void:
	var hero: Hero = _add_hero("Runner")
	var preset_id: String = GameSession.save_team_preset("", "Runners", [hero.instance_id], "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}), "", GameSession.last_action_error)
	var kept: Dictionary = _good_save()
	var battle: Dictionary = (GameSession.expedition_orders[0]["battle"] as Dictionary).duplicate(true)
	((battle["actors"] as Array)[0] as Dictionary)["position"] = [NAN, 0.0]
	GameSession.expedition_orders[0]["battle"] = battle
	assert_false(SaveService.save())
	assert_push_error("Save refused")
	for error: Variant in get_errors():
		if error.contains_text("NaN"):
			error.handled = true
	assert_string_contains(SaveService.last_write_error, "Save refused: this game state would not load (")
	_assert_files_unchanged(kept)


## Prints the cost for the bead: save() on a large profile, best of 7, and the check alone (the
## parse, repair and validate save() now runs on its own text). The bound is loose on purpose.
func test_the_check_costs_little_on_a_large_profile() -> void:
	GameSession.set("_save_deferred_depth", 1)
	for index: int in 300:
		_add_hero("Hero %d" % index)
	for index: int in 2000:
		GameSession.add_item(Item.new(&"ring", index % 7))
	GameSession.set("_save_deferred_depth", 0)
	var preset_id: String = GameSession.save_team_preset("", "Runners", [GameSession.roster[0].instance_id], "verdant_outskirts")
	assert_ne(GameSession.dispatch_force([preset_id], "verdant_outskirts", 1, {}, {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}), "", GameSession.last_action_error)
	var save_usec: int = 1 << 62
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		assert_true(SaveService.save(), SaveService.last_write_error)
		save_usec = mini(save_usec, Time.get_ticks_usec() - started)
	var text: String = FileAccess.get_file_as_string(SaveService.SAVE_PATH)
	var check_usec: int = 1 << 62
	for _run: int in 7:
		var started: int = Time.get_ticks_usec()
		var parsed: Dictionary = JSON.parse_string(text) as Dictionary
		GameSession.repair_rescue_timestamps(parsed)
		assert_eq(GameSession.validate_saved_state(parsed, SaveService.SAVE_VERSION), "")
		check_usec = mini(check_usec, Time.get_ticks_usec() - started)
	gut.p("SAVE CHECK: %d heroes, %d items, save.json %d bytes, save() best of 7 %.2f ms, the check alone %.2f ms" % [GameSession.roster.size(), GameSession.inventory.size(), text.length(), save_usec / 1000.0, check_usec / 1000.0])
	assert_lt(save_usec, 5000000)


func _reset_checkpoint() -> void:
	GameSession.set("_checkpoint_save_failed", false)
	GameSession.set("_checkpoint_error", "")
	GameSession.set("_periodic_save_accumulator", 0.0)
	GameSession.set("_expedition_pulse_accumulator", 0.0)


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 0)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	return hero


## Saves the good state for real and returns both files' bytes, or null for a file that is not there.
func _good_save() -> Dictionary:
	assert_true(SaveService.save(), SaveService.last_write_error)
	var kept: Dictionary = {}
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		kept[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return kept


func _assert_files_unchanged(kept: Dictionary) -> void:
	for path: String in kept:
		var now: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		assert_eq(now, kept[path], path + " is byte-identical, or still missing")
	for path: String in [SaveService.TMP_PATH, SaveService.LEDGER_TMP_PATH]:
		assert_false(FileAccess.file_exists(path), path + " is not left behind")


## In memory only: an incident whose stranded ally keeps a squad_id no squad lists, which load refuses.
func _add_bad_incident(stranded: Hero) -> void:
	var zone: ZoneDefinition = load("res://zones/defs/verdant_outskirts.tres") as ZoneDefinition
	var stats: Dictionary[StringName, float] = Hero.compute_final_stats(stranded, Hero.definition_for(stranded.def_id), preload("res://balance.tres"), 0)
	var state: BattleState = BattleSimulation.create_run("source", [{
		"hero_id": stranded.instance_id,
		"archetype": str(stranded.def_id),
		"hp": stats[Hero.STAT_HP],
		"atk": stats[Hero.STAT_ATK],
		"defense": stats[Hero.STAT_DEF],
		"speed": stats[Hero.STAT_SPD],
		"crit_rate": stats[Hero.STAT_CRIT_RATE],
		"crit_damage": stats[Hero.STAT_CRIT_DMG],
		"squad_id": "source-squad",
	}], zone, [{"id": "source-squad", "name": "Source", "hero_ids": [stranded.instance_id], "stance": "stay_together", "guard_target_id": ""}], {}, {}, 544)
	state.actors[0].life = BattleActor.LIFE_DOWNED
	state.actors[0].hp = 0.0
	var snapshot: Dictionary = GameSession._incident_snapshot(state, [stranded.instance_id] as Array[String])
	(snapshot["actors"] as Array)[0]["squad_id"] = "source-squad"
	GameSession.stranded_incidents.append({"id": "incident-bad", "source_order_id": "source", "zone_id": "verdant_outskirts", "hero_ids": [stranded.instance_id], "battle_snapshot": snapshot, "created_recovery_seconds": GameSession.rescue_clock_seconds, "paused": true, "expiry_pending": false, "active_rescue_order_id": ""})
