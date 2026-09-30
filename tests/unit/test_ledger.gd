extends GutTest

## ig-m6o.1: the Ledger (DECISIONS.md 2026-09-24 "The Ledger"; SYSTEMS.md § The Ledger).

const BALANCE: BalanceTable = preload("res://balance.tres")
const Session = preload("res://systems/game_session.gd")

var _originals: Dictionary = {}


func before_all() -> void:
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		if FileAccess.file_exists(path):
			_originals[path] = FileAccess.get_file_as_bytes(path)


func after_all() -> void:
	SaveService.load_blocked = false
	GameSession.set("_save_deferred_depth", 0)
	for path: String in [SaveService.SAVE_PATH, SaveService.LEDGER_PATH]:
		if _originals.has(path):
			FileAccess.open(path, FileAccess.WRITE).store_buffer(_originals[path])
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func before_each() -> void:
	GameSession.set("_save_deferred_depth", 1)
	SaveService.load_blocked = false
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set("_save_deferred_depth", 0)


func test_each_writer_records_one_event_and_the_ledger_survives_a_disk_reload_byte_identical() -> void:
	GameSession.stones = 1000
	GameSession.essence = 100000
	var keeper := _hero("Keeper", "knight")
	var fodder := _hero("Fodder", "knight")
	assert_true(GameSession.summon_hero(keeper, BALANCE))
	assert_true(GameSession.summon_hero(fodder, BALANCE))
	assert_true(GameSession.rank_up_hero(keeper, BALANCE))
	assert_true(GameSession.sacrifice_hero(fodder, keeper, BALANCE))

	assert_eq(_kinds(), ["summoned", "summoned", "ranked_up", "died"])
	assert_eq(GameSession.ledger.map(func(record: Dictionary) -> int: return record["seq"]), [1, 2, 3, 4])
	assert_eq(GameSession.ledger_next_seq, 5)
	assert_eq(_without_time(GameSession.ledger[0]), {"seq": 1, "kind": "summoned", "hero": keeper.instance_id, "name": "Keeper", "rank": 0, "archetype": "knight"})
	assert_eq(_without_time(GameSession.ledger[2]), {"seq": 3, "kind": "ranked_up", "hero": keeper.instance_id, "from": 0, "to": 1, "via": "essence"})
	assert_eq(_without_time(GameSession.ledger[3]), {"seq": 4, "kind": "died", "hero": fodder.instance_id, "name": "Fodder", "rank": 0, "cause": "sacrifice", "by": keeper.instance_id}, "one died record, by = the keeper")

	var before: String = JSON.stringify(GameSession.ledger)
	var first_text: String = _disk_save()
	assert_false(first_text.contains("\"ledger\":"), "the main save keeps only the mark")
	assert_string_contains(first_text, "\"ledger_next_seq\":5")
	var first_lines: String = FileAccess.get_file_as_string(SaveService.LEDGER_PATH)
	assert_eq(first_lines.split("\n").size(), 5, "four lines, each ending in a newline")
	assert_string_contains(first_lines.split("\n")[3], "\"seq\":4,", "one compact record per line")
	assert_false(first_lines.contains("\t"), "not indented")
	assert_true(_disk_load())
	assert_eq(JSON.stringify(GameSession.ledger), before, "ints stay ints after the reload")
	assert_eq(GameSession.ledger_next_seq, 5)
	_disk_save()
	assert_eq(FileAccess.get_file_as_string(SaveService.LEDGER_PATH), first_lines, "the next save writes the same ledger bytes")

	assert_true(GameSession.summon_hero(_hero("Later", "mage"), BALANCE))
	assert_eq(int(GameSession.ledger.back()["seq"]), 5, "seq is never reused")


func test_a_legacy_save_without_ledger_keys_loads_empty_and_reads_arrived_before_the_records() -> void:
	var old := _hero("Old Timer", "rogue")
	GameSession.roster.append(old)
	var payload: Dictionary = GameSession.to_dict()
	payload.erase("ledger")
	payload.erase("ledger_next_seq")
	payload["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(payload)
	assert_true(_disk_load(), SaveService.load_block_reason)
	assert_eq(GameSession.ledger, [] as Array[Dictionary])
	assert_eq(GameSession.ledger_next_seq, 1)
	assert_not_null(GameSession.hero_by_id(old.instance_id))
	assert_eq(Ledger.history_lines(GameSession.ledger, old.instance_id, {}, BALANCE.rank_names, 10), ["Arrived before the records begin."] as Array[String])

	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"Forge")
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	assert_string_ends_with((hub.get_node("%HeroDetail") as Label).text, "History:\nArrived before the records begin.")


## A real fight from the ig-gy0.1 checkpoint: saved and reloaded through disk mid-fight, after its
## first moments. The settle writes one battle record whose moments and kills match an
## uninterrupted run of the same state, and whose team names the downed heroes too.
func test_a_mid_fight_disk_reload_keeps_moments_and_the_settle_writes_one_battle_record() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle_checkpoint_pre_skills.json")) as Dictionary
	fixture["saved_at_unix"] = Time.get_unix_time_from_system() + 3600.0
	_write_save(fixture)
	assert_true(_disk_load(), SaveService.load_block_reason)
	var order_id: String = str(GameSession.expedition_orders[0]["id"])
	var hero_ids: Array = GameSession.expedition_orders[0]["hero_ids"]
	var uninterrupted := BattleState.from_dict(GameSession.expedition_orders[0]["battle"] as Dictionary)
	var expected: BattleOutcome = BattleSimulation.advance(uninterrupted, uninterrupted.max_seconds)
	assert_false(expected.moments.is_empty())

	var moments: Array = []
	for step: int in 100:
		GameSession.tick_expeditions(1.0)
		moments = GameSession.get_battle_snapshot(order_id).get("moments", [])
		if not moments.is_empty():
			break
	assert_false(moments.is_empty(), "the fight reached its first moment")
	assert_eq(str(GameSession.get_battle_snapshot(order_id)["status"]), "active", "and is still going")
	var saved_moments: String = JSON.stringify(moments)
	assert_true(_disk_load_after_save())
	# Read from disk, before the catch-up re-serializes the battle: its numbers are JSON floats.
	assert_eq(JSON.parse_string(JSON.stringify(GameSession.get_battle_snapshot(order_id)["moments"])), JSON.parse_string(saved_moments), "moments survive the mid-fight reload")
	_land_catch_ups()
	assert_eq(GameSession.ledger, [] as Array[Dictionary], "nothing is written before the settle")

	for step: int in 400:
		if GameSession.expedition_orders.is_empty():
			break
		GameSession.tick_expeditions(1.0)
	assert_true(GameSession.expedition_orders.is_empty(), "the order settled")
	assert_eq(_kinds(), ["battle"], "exactly one battle record")
	var record: Dictionary = GameSession.ledger[0]
	assert_eq(record["order"], order_id)
	assert_eq(record["battle_kind"], "normal")
	assert_eq(record["result"], expected.status)
	assert_eq(record["team"], hero_ids, "everyone who fought")
	for moment: Dictionary in expected.moments:
		if moment["what"] == "downed":
			assert_true(str(moment["by"]).begins_with("enemy:"), "a downed hero names the enemy")
			assert_true(str(moment["hero"]) in record["team"], "a downed hero is still in the team")
	assert_eq(JSON.stringify(record["moments"]), JSON.stringify(expected.moments), "the killer and rescuer ids of the uninterrupted run")
	assert_eq(record["kills"], expected.kills)


func test_forecasts_write_nothing() -> void:
	var team: Array[Hero] = [_hero("Scout", "knight")]
	team[0].rank = 7
	team[0].level = 80
	GameSession.roster.append(team[0])
	var zone: ZoneDefinition = ZoneDefinition.definition_for(&"verdant_outskirts")
	var squads: Array[Dictionary] = [{"id": "s", "name": "S", "hero_ids": [team[0].instance_id], "stance": "stay_together", "guard_target_id": ""}]
	var snapshots: Array[Dictionary] = GameSession._team_snapshots(team, squads)
	BattleSimulation.forecast("forecast", snapshots, zone, squads, {}, {"healing": 0, "revival": 0}, 7)
	ExpeditionOrders.safety_forecast(team, zone, BALANCE)
	assert_eq(GameSession.ledger, [] as Array[Dictionary])
	assert_eq(GameSession.ledger_next_seq, 1)


func test_eviction_is_tiered_oldest_first_and_seq_is_never_reused() -> void:
	var ledger: Array[Dictionary] = []
	var next_seq: int = 1
	var routine: Dictionary = {"result": "victory", "moments": [], "team": ["h"]}
	var eventful: Dictionary = {"result": "victory", "moments": [{"tick": 1, "what": "downed", "hero": "h", "by": "enemy:rogue"}], "team": ["h"]}
	for entry: Array in [["died", {}], ["summoned", {}], ["ranked_up", {}], ["battle", eventful], ["battle", routine], ["battle", routine]]:
		next_seq = Ledger.append(ledger, next_seq, 0, entry[0], entry[1])
		Ledger.evict(ledger, Ledger.tiers(ledger), 6)
	var evicted: Array[String] = []
	for pass_index: int in 6:
		var before: Array = ledger.map(func(record: Dictionary) -> int: return record["seq"])
		next_seq = Ledger.append(ledger, next_seq, 0, "died", {})
		Ledger.evict(ledger, Ledger.tiers(ledger), 6)
		var gone: Array = before.filter(func(seq: int) -> bool: return not ledger.any(func(record: Dictionary) -> bool: return record["seq"] == seq))
		assert_eq(gone.size(), 1)
		evicted.append("%s#%d" % [["", "died", "summoned", "ranked_up", "battle", "battle", "battle"][gone[0]], gone[0]])
	assert_eq(evicted, ["battle#5", "battle#6", "battle#4", "ranked_up#3", "summoned#2", "died#1"] as Array[String], "routine battles, other battles, ranked_up, summoned, died last")
	assert_eq(ledger.map(func(record: Dictionary) -> int: return record["seq"]), [7, 8, 9, 10, 11, 12])
	assert_eq(next_seq, 13)


## ig-m6o.2.2.4: encounters go first, then routine battles, then the other battles and any kind not listed.
func test_tiers_put_encounters_first_and_an_unlisted_kind_with_the_battles() -> void:
	var routine: Dictionary = {"kind": "battle", "result": "victory", "moments": [], "team": ["h"]}
	var hard: Dictionary = {"kind": "battle", "result": "retreated", "moments": [], "team": ["h"]}
	var records: Array[Dictionary] = [{"kind": "encounter"}, routine, hard, {"kind": "meal"}, {"kind": "ranked_up"}, {"kind": "summoned"}, {"kind": "died"}]
	assert_eq(Ledger.tiers(records), [0, 1, 2, 2, 3, 4, 5] as Array[int], "encounter, routine, battle, unknown, ranked_up, summoned, died")
	assert_eq(Ledger.TIER_BY_KIND.size() + 1, 6, "evict scans tiers 0 to 5")


func test_eviction_takes_encounters_before_routine_battles_oldest_first() -> void:
	var ledger: Array[Dictionary] = []
	var next_seq: int = 1
	var routine: Dictionary = {"result": "victory", "moments": [], "team": ["h"]}
	var hard: Dictionary = {"result": "retreated", "moments": [], "team": ["h"]}
	for entry: Array in [["died", {}], ["encounter", {"heroes": ["a", "b"]}], ["battle", routine], ["encounter", {"heroes": ["a", "b"]}], ["battle", hard], ["battle", routine]]:
		next_seq = Ledger.append(ledger, next_seq, 0, entry[0], entry[1])
	var evicted: Array[Dictionary] = Ledger.evict(ledger, Ledger.tiers(ledger), 3)
	assert_eq(evicted.map(func(record: Dictionary) -> int: return record["seq"]), [2, 4, 3], "both encounters, oldest first, then the oldest routine battle")
	assert_eq(ledger.map(func(record: Dictionary) -> int: return record["seq"]), [1, 5, 6])


## ig-m6o.2.2.4 (the save round trip): an encounter is one more Ledger record, so it needs no key in the main save.
func test_encounters_survive_a_disk_reload_as_whole_ints_and_make_the_same_bond_as_a_rebuild() -> void:
	var one: String = "hero:ada"
	var other: String = "hero:bea"
	for _meeting: int in 8:
		GameSession._record("encounter", {"heroes": [one, other], "place": "House_1", "why": "neighbours"})
	GameSession._record("battle", {"order": "order:1", "zone": "verdant_outskirts", "team": [one, other], "result": "victory", "moments": []})
	var before: String = JSON.stringify(GameSession.ledger)
	assert_false(_disk_save().contains("encounter"), "no new key in the main save")
	assert_eq(FileAccess.get_file_as_string(SaveService.LEDGER_PATH).count("\"kind\":\"encounter\""), 8, "eight lines of the side file")
	assert_true(_disk_load())
	assert_eq(JSON.stringify(GameSession.ledger), before, "ints stay ints")
	var pairs: Dictionary = GameSession.bond_index()
	assert_eq(pairs, Bonds.index(GameSession.ledger, BALANCE), "the kept index is a rebuild")
	var bond: Dictionary = Bonds.bond_from(pairs, one, {one: true, other: true}, BALANCE)
	assert_eq([bond["partner"], bond["fact"]["kind"], bond["fact"]["place"]], [other, "met", "House_1"], "eight chats and a quiet battle: the pair fact is the chat")


## Ruling 6 of ig-m6o.2.2.4: at the cap an encounter is the first record to go, and a load in between changes
## nothing. GameSession's cap is folded in when it compiles, so the ledger is padded to the real one.
func test_encounters_are_evicted_first_at_the_cap_through_a_disk_reload_and_the_kept_index_follows() -> void:
	var cap: int = BALANCE.ledger_max_records
	for seq: int in range(1, cap - 2):
		Ledger.append(GameSession.ledger, seq, 0, "summoned", {"hero": "filler:%d" % seq, "name": "F", "rank": 0})
	GameSession.ledger_next_seq = cap - 2
	for _meeting: int in 3:
		GameSession._record("encounter", {"heroes": ["hero:ada", "hero:bea"], "place": "House_1", "why": "neighbours"})
	assert_eq(GameSession.ledger.size(), cap)
	_disk_save()
	assert_true(_disk_load())
	assert_eq(GameSession.ledger.size(), cap)
	GameSession.bond_index()
	for step: int in 3:
		GameSession._record("summoned", {"hero": "new:%d" % step, "name": "N", "rank": 0})
		assert_eq(GameSession.ledger.size(), cap)
		assert_eq(_kinds().count("encounter"), 2 - step, "one encounter goes for each new record")
	assert_eq(GameSession.ledger[0]["hero"], "filler:1", "no other record went")
	assert_eq(_nonempty(GameSession.bond_index()), _nonempty(Bonds.index(GameSession.ledger, BALANCE)), "the kept index followed each eviction")
	var kept: String = JSON.stringify(GameSession.ledger)
	assert_false(_disk_save().contains("encounter"))
	assert_true(_disk_load())
	assert_eq(JSON.stringify(GameSession.ledger), kept, "the load leaves the ledger as it was")
	assert_eq(FileAccess.get_file_as_string(SaveService.LEDGER_PATH).count("\"kind\":\"encounter\""), 0, "the load cut the side file")
	assert_eq(_nonempty(GameSession.bond_index()), _nonempty(Bonds.index(GameSession.ledger, BALANCE)))


func test_a_hand_edited_encounter_and_a_torn_last_line_load_and_count_nothing() -> void:
	var one: String = "hero:ada"
	var other: String = "hero:bea"
	for _meeting: int in 2:
		GameSession._record("encounter", {"heroes": [one, other], "place": "House_1", "why": "neighbours"})
	_disk_save()
	var lines: PackedStringArray = FileAccess.get_file_as_string(SaveService.LEDGER_PATH).split("\n")
	lines[1] = lines[1].replace("[\"hero:ada\",\"hero:bea\"]", "[\"hero:ada\"]")
	var file := FileAccess.open(SaveService.LEDGER_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "{\"seq\":3,\"ti")
	file.close()
	assert_true(_disk_load())
	assert_eq(GameSession.ledger.size(), 2, "the torn last line is gone and the edited record stays")
	var pairs: Dictionary = Bonds.index(GameSession.ledger, BALANCE)
	assert_eq(int(pairs[one][other]["points"]), BALANCE.bond_points_encounter, "the edited one counted nothing")
	assert_eq(GameSession.bond_index(), pairs)


func test_history_lines_collapse_routine_wins_and_name_killers_and_rescuers() -> void:
	var ledger: Array[Dictionary] = []
	var next_seq: int = Ledger.append(ledger, 1, 0, "summoned", {"hero": "h:a", "name": "Aldric", "rank": 0, "archetype": "knight"})
	for index: int in 3:
		next_seq = Ledger.append(ledger, next_seq, 0, "battle", {"order": "o%d" % index, "zone": "verdant_outskirts", "battle_kind": "normal", "result": "victory", "team": ["h:a", "h:b"], "kills": {}, "moments": []})
	next_seq = Ledger.append(ledger, next_seq, 0, "battle", {"order": "o9", "zone": "verdant_outskirts", "battle_kind": "normal", "result": "victory", "team": ["h:a", "h:b"], "kills": {"h:a": 2}, "moments": [
		{"tick": 5, "what": "downed", "hero": "h:b", "by": "enemy:rogue"},
		{"tick": 9, "what": "revived", "hero": "h:b", "by": "h:a"},
	]})
	next_seq = Ledger.append(ledger, next_seq, 0, "ranked_up", {"hero": "h:a", "from": 0, "to": 1, "via": "essence"})
	var zone_name: String = ZoneDefinition.definition_for(&"verdant_outskirts").display_name
	var names: Dictionary = {"h:b": "Bo"}
	assert_eq(Ledger.history_lines(ledger, "h:a", names, BALANCE.rank_names, 10), [
		"Ranked up from F to D.",
		"Won a battle at %s; revived Bo." % zone_name,
		"Won 3 battles at %s." % zone_name,
		"Summoned at F rank.",
	] as Array[String])
	assert_eq(Ledger.history_lines(ledger, "h:b", {"h:a": "Aldric"}, BALANCE.rank_names, 2), [
		"Won a battle at %s; downed by an enemy Rogue; revived by Aldric." % zone_name,
		"Won 3 battles at %s." % zone_name,
	] as Array[String], "at most max_lines, and no arrival line past it")


## Deaths after the stranding battle carry its order id: by abandon, by expiry and by a partly
## failed rescue, each across a real disk save and reload.
func test_abandon_carries_battle_order_across_a_disk_reload() -> void:
	var source: Dictionary = _stranded_incident("abandon")
	assert_true(_disk_load_after_save())
	assert_true(GameSession.abandon_stranded(str(GameSession.stranded_incidents[0]["id"])), GameSession.last_action_error)
	_assert_expedition_death(source["hero_id"], source["order_id"])
	assert_eq(_battle_records(source["order_id"]).size(), 1, "the stranding battle's record exists")
	assert_true(_disk_load_after_save())
	_assert_expedition_death(source["hero_id"], source["order_id"])


func test_expiry_carries_battle_order_across_a_disk_reload() -> void:
	var source: Dictionary = _stranded_incident("expiry")
	assert_true(_disk_load_after_save())
	var incident: Dictionary = GameSession.stranded_incidents[0]
	incident["paused"] = false
	incident["created_recovery_seconds"] = 0.0
	GameSession.rescue_clock_seconds = (BALANCE.recovery_base_duration_seconds + BALANCE.recovery_duration_seconds_per_level * 10.0) * BALANCE.battle_pace + 1.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.stranded_incidents.is_empty())
	_assert_expedition_death(source["hero_id"], source["order_id"])
	assert_true(_disk_load_after_save())
	_assert_expedition_death(source["hero_id"], source["order_id"])


func test_a_partly_failed_rescue_carries_the_original_battle_order_and_records_its_rescue() -> void:
	var first: Dictionary = _add_one("first")
	var second: Dictionary = _add_one("second")
	var pair_preset: String = GameSession.save_team_preset("", "pair", [first["hero_id"], second["hero_id"]], "verdant_outskirts")
	var order_id: String = GameSession.dispatch_force([pair_preset], "verdant_outskirts", 1, {}, _zero_loadout())
	assert_ne(order_id, "", GameSession.last_action_error)
	_fail_all_allies(order_id)
	GameSession.tick_expeditions(0.1)
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	var rescuer: Dictionary = _add_one("rescuer")
	var rescue_order_id: String = GameSession.dispatch_rescue(incident_id, rescuer["preset_id"], _zero_loadout())
	assert_ne(rescue_order_id, "", GameSession.last_action_error)
	assert_true(_disk_load_after_save())
	GameSession.stranded_incidents[0]["expiry_pending"] = true
	var rescue_order: Dictionary = GameSession.expedition_orders[0]
	var battle: Dictionary = rescue_order["battle"] as Dictionary
	for actor: Dictionary in battle["actors"] as Array[Dictionary]:
		if str(actor["hero_id"]) == first["hero_id"]:
			actor["life"] = BattleActor.LIFE_EXTRACTED
			actor["hp"] = maxf(float(actor["hp"]), 1.0)
	battle["status"] = "timeout"
	battle["extracted_ids"] = [first["hero_id"]]
	battle["downed_ever_ids"] = [first["hero_id"], second["hero_id"]]
	rescue_order["phase"] = "returning"
	rescue_order["remaining_seconds"] = 0.0
	GameSession.tick_expeditions(0.1)

	assert_not_null(GameSession.hero_by_id(first["hero_id"]), "carried home")
	_assert_expedition_death(second["hero_id"], order_id)
	var rescue: Array[Dictionary] = _battle_records(rescue_order_id)
	assert_eq(rescue.size(), 1)
	assert_eq(rescue[0]["battle_kind"], "rescue")
	assert_eq(rescue[0]["rescued"], [first["hero_id"]])
	assert_eq(_sorted(rescue[0]["team"]), _sorted([first["hero_id"], second["hero_id"], rescuer["hero_id"]]), "every ally in the fight, the stranded heroes included")
	assert_eq(rescue[0]["rescuers"], [rescuer["hero_id"]], "only the rescue order's heroes")
	assert_true(_disk_load_after_save())
	_assert_expedition_death(second["hero_id"], order_id)
	assert_eq(_battle_records(rescue_order_id)[0]["rescued"], [first["hero_id"]])
	assert_eq(_battle_records(rescue_order_id)[0]["rescuers"], [rescuer["hero_id"]])
	var zone_name: String = ZoneDefinition.definition_for(&"verdant_outskirts").display_name
	var names: Dictionary = {first["hero_id"]: "First", second["hero_id"]: "Second", rescuer["hero_id"]: "Rescuer"}
	var first_line: String = Ledger.history_lines(GameSession.ledger, first["hero_id"], names, BALANCE.rank_names, 10)[0]
	assert_eq(first_line, "Rescued from %s by Rescuer." % zone_name, "the rescued hero names only the rescuer")
	assert_true(Ledger.history_lines(GameSession.ledger, second["hero_id"], names, BALANCE.rank_names, 10)[1].begins_with("Was there when First was rescued at %s" % zone_name), "the stranded witness")
	assert_true(Ledger.history_lines(GameSession.ledger, rescuer["hero_id"], names, BALANCE.rank_names, 10)[0].begins_with("Rescued First at %s" % zone_name), "the rescuer")


func test_a_rescue_record_without_rescuers_reads_neutral() -> void:
	var ledger: Array[Dictionary] = []
	Ledger.append(ledger, 1, 0, "battle", {"order": "o1", "zone": "verdant_outskirts", "battle_kind": "rescue", "result": "timeout", "team": ["h:a", "h:b", "h:c"], "kills": {}, "moments": [], "rescued": ["h:a"]})
	var zone_name: String = ZoneDefinition.definition_for(&"verdant_outskirts").display_name
	var names: Dictionary = {"h:a": "Ann", "h:b": "Bo", "h:c": "Cy"}
	assert_eq(Ledger.history_lines(ledger, "h:a", names, BALANCE.rank_names, 1), ["Rescued from %s." % zone_name] as Array[String])
	assert_eq(Ledger.history_lines(ledger, "h:c", names, BALANCE.rank_names, 1), ["Was there when Ann was rescued at %s." % zone_name] as Array[String], "no one is named a rescuer")


## A failed rescue strands its rescuer into the same incident. That rescuer's later death names
## the RESCUE order, whose record lists them; the original hero still names the source order.
## Checked for abandon and for expiry, across disk reloads.
func test_a_rescuer_stranded_by_a_failed_rescue_links_to_the_rescue_when_abandoned() -> void:
	var links: Dictionary = _strand_a_rescuer("abandon")
	assert_true(GameSession.abandon_stranded(str(GameSession.stranded_incidents[0]["id"])), GameSession.last_action_error)
	_assert_rescuer_links(links)
	assert_true(_disk_load_after_save())
	_assert_rescuer_links(links)


func test_a_rescuer_stranded_by_a_failed_rescue_links_to_the_rescue_when_the_window_expires() -> void:
	var links: Dictionary = _strand_a_rescuer("expire")
	var incident: Dictionary = GameSession.stranded_incidents[0]
	incident["paused"] = false
	incident["created_recovery_seconds"] = 0.0
	GameSession.rescue_clock_seconds = (BALANCE.recovery_base_duration_seconds + BALANCE.recovery_duration_seconds_per_level * 10.0) * BALANCE.battle_pace + 1.0
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.stranded_incidents.is_empty())
	_assert_rescuer_links(links)
	assert_true(_disk_load_after_save())
	_assert_rescuer_links(links)


func test_incident_battle_orders_is_validated_when_present() -> void:
	_strand_a_rescuer("validate")
	var saved: Dictionary = _json(GameSession.to_dict())
	assert_eq(Session.validate_saved_state(saved, 3), "")
	for bad: Variant in [[], {"hero:x": 5}, {"hero:x": ""}]:
		var broken: Dictionary = saved.duplicate(true)
		(broken["stranded_incidents"] as Array)[0]["battle_orders"] = bad
		assert_string_contains(Session.validate_saved_state(broken, 3), "battle_orders", str(bad))
	(saved["stranded_incidents"] as Array)[0].erase("battle_orders")
	assert_eq(Session.validate_saved_state(saved, 3), "", "a legacy incident has no key")


## A total wipe captures its incident when the fight ends, before the order settles. Live code runs
## the capture and the settle inside one commit (_advance_time_in_memory), and a save holding the
## window is refused (a normal order with an incident_id), so the window is forced here in memory.
## An abandon inside it still names the order, and the settle that follows writes the record it
## points at, with the dead hero in its team. Both survive a disk reload.
func test_abandoning_a_total_wipe_before_its_order_settles_still_carries_battle_order() -> void:
	var hero: Dictionary = _add_one("wipe")
	var order_id: String = GameSession.dispatch_force([hero["preset_id"]], "verdant_outskirts", 1, {}, _zero_loadout())
	_fail_all_allies(order_id)
	var order: Dictionary = GameSession.expedition_orders[0]
	GameSession._capture_stranded_incident(order, BattleState.from_dict(order["battle"] as Dictionary))
	assert_eq(GameSession.expedition_orders.size(), 1, "not settled yet")
	assert_string_contains(Session.validate_saved_state(_json(GameSession.to_dict()), 3), "incident reference", "the window is never saved")
	assert_true(GameSession.abandon_stranded(str(GameSession.stranded_incidents[0]["id"])), GameSession.last_action_error)
	assert_eq(_battle_records(order_id).size(), 0, "the stranding battle has no record yet")
	_assert_expedition_death(hero["hero_id"], order_id)
	GameSession.tick_expeditions(0.1)
	assert_true(GameSession.expedition_orders.is_empty())
	var records: Array[Dictionary] = _battle_records(order_id)
	assert_eq(records.size(), 1)
	assert_eq(records[0]["team"], [hero["hero_id"]], "the dead hero fought in it")
	assert_lt(int(_died(hero["hero_id"])["seq"]), int(records[0]["seq"]), "the death settled first")
	assert_true(_disk_load_after_save())
	_assert_expedition_death(hero["hero_id"], order_id)
	assert_eq(_battle_records(order_id).size(), 1)


## Rule 8 and item 5: kill_hero is the only died writer and GameSession the only Ledger writer;
## combat/ never touches the Ledger.
func test_kill_hero_is_the_only_died_writer_and_combat_never_touches_the_ledger() -> void:
	var writers: Dictionary = {}
	for path: String in _scripts("res://"):
		var text: String = FileAccess.get_file_as_string(path)
		if path.begins_with("res://combat/"):
			assert_false(text.contains("Ledger.") or text.contains(".ledger"), "%s stays out of the Ledger" % path)
		for needle: String in ["Ledger.append(", "_record(\"died\""]:
			if text.contains(needle) and not path.begins_with("res://tests/"):
				writers[needle] = writers.get(needle, []) + [path]
	assert_eq(writers.get("Ledger.append("), ["res://systems/game_session.gd"])
	assert_eq(writers.get("_record(\"died\""), ["res://systems/game_session.gd"])
	var session: String = FileAccess.get_file_as_string("res://systems/game_session.gd")
	assert_eq(session.count("_record(\"died\""), 1)
	var kill_start: int = session.find("func kill_hero(")
	assert_true(session.find("_record(\"died\"") > kill_start and session.find("_record(\"died\"") < session.find("\nfunc ", kill_start + 1), "inside kill_hero")


## SYSTEMS.md § The Ledger (PROVISIONAL): a full ledger of five-hero battle records, saved for
## real. The time and size are printed for the bead; the bound is loose on purpose.
func test_a_full_ledger_saves_in_reasonable_time() -> void:
	var team: Array = ["hero:a", "hero:b", "hero:c", "hero:d", "hero:e"]
	for index: int in BALANCE.ledger_max_records + 1:
		GameSession._record("battle", {"order": "order:%d" % index, "zone": "verdant_outskirts", "battle_kind": "normal", "result": "victory", "team": team, "kills": {"hero:a": 3, "hero:b": 2}, "moments": [] if index % 4 != 0 else [{"tick": 120, "what": "downed", "hero": "hero:c", "by": "enemy:rogue"}, {"tick": 180, "what": "revived", "hero": "hero:c", "by": "hero:a"}]})
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_eq(int(GameSession.ledger.back()["seq"]), BALANCE.ledger_max_records + 1)
	# ig-m6o.9: the first save after a from_dict writes the side file whole, once. After that a commit
	# appends only its own line, and a save with nothing new writes no ledger bytes.
	var started: int = Time.get_ticks_msec()
	var text: String = _disk_save()
	var save_msec: int = Time.get_ticks_msec() - started
	GameSession.set("_save_deferred_depth", 0)
	var started_usec: int = Time.get_ticks_usec()
	assert_true(GameSession._commit_profile_mutation(func() -> void: GameSession._record("ranked_up", {"hero": "hero:a", "from": 0, "to": 1, "via": "essence"})))
	var commit_usec: int = Time.get_ticks_usec() - started_usec
	started_usec = Time.get_ticks_usec()
	assert_true(SaveService.save())
	var periodic_usec: int = Time.get_ticks_usec() - started_usec
	GameSession.set("_save_deferred_depth", 1)
	started = Time.get_ticks_msec()
	assert_true(_disk_load())
	var load_msec: int = Time.get_ticks_msec() - started
	gut.p("LEDGER CAP: %d records, first save %d ms, commit %.2f ms, periodic save %.2f ms, load %d ms, main save %d bytes, side file %d bytes" % [GameSession.ledger.size(), save_msec, commit_usec / 1000.0, periodic_usec / 1000.0, load_msec, text.length(), FileAccess.get_file_as_bytes(SaveService.LEDGER_PATH).size()])
	assert_eq(GameSession.ledger.size(), BALANCE.ledger_max_records)
	assert_lt(save_msec, 5000)


## ig-8hj: a summon whose save fails rolls back stones, roster and Ledger, and the hub shows only
## the reason, never the pull (locking the save must not be a peek-and-re-roll). Then the next pull,
## with the save working, shows and lands on disk.
func test_a_summon_whose_save_fails_shows_only_the_reason_and_memory_and_disk_agree() -> void:
	GameSession.stones = BALANCE.summon_pull_cost * 2
	GameSession.roster.append(_hero("Keeper", "knight"))
	_disk_save()
	var before: String = _profile()
	var hub: Node3D = _hub()
	hub._open(&"SummoningCircle")
	var status: Label = hub.get_node("%Status") as Label
	var summon: Button = hub.get_node("%Summon") as Button
	_with_failing_save(summon.pressed.emit)
	assert_string_starts_with(status.text, "Save failed")
	assert_eq(status.text, GameSession.last_action_error)
	assert_eq(_profile(), before, "stones, roster and Ledger rolled back")
	hub._open(&"Forge")
	assert_eq((hub.get_node("%RosterList") as ItemList).item_count, 1, "the pull never shows")
	hub._open(&"SummoningCircle")
	assert_true(_disk_load())
	assert_eq(_profile(), before, "the disk agrees")
	# The side file rewritten whole (the first save after a from_dict) keeps the record past the
	# mark until the next save; the load drops it.
	SaveService.set("_ledger_synced", false)
	_with_failing_save(summon.pressed.emit)
	assert_eq(_profile(), before)
	assert_true(_disk_load())
	assert_eq(_profile(), before, "the disk agrees after a whole rewrite too")

	GameSession.set("_save_deferred_depth", 0)
	summon.pressed.emit()
	GameSession.set("_save_deferred_depth", 1)
	assert_string_starts_with(status.text, "Summoned ")
	var after: String = _profile()
	assert_true(_disk_load())
	assert_eq(_profile(), after, "the pull that showed is on disk")
	assert_eq(GameSession.roster.size(), 2)
	assert_eq(GameSession.stones, BALANCE.summon_pull_cost)
	assert_eq(_kinds(), ["summoned"])


## ig-8hj: the same for a rank-up; the retry after the rollback uses the rebuilt roster.
func test_a_rank_up_whose_save_fails_shows_the_reason_and_memory_and_disk_agree() -> void:
	var keeper := _hero("Keeper", "knight")
	GameSession.roster.append(keeper)
	GameSession.essence = Hero.compute_rank_up_cost(keeper, BALANCE)
	_disk_save()
	var before: String = _profile()
	var hub: Node3D = _hub()
	hub._open(&"Sanctum")
	var status: Label = hub.get_node("%Status") as Label
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	var rank_up: Button = hub.get_node("%RankUp") as Button
	_with_failing_save(rank_up.pressed.emit)
	assert_string_starts_with(status.text, "Save failed")
	assert_eq(status.text, GameSession.last_action_error)
	assert_eq(_profile(), before, "rank, essence and Ledger rolled back")
	assert_true(_disk_load())
	assert_eq(_profile(), before, "the disk agrees")
	assert_false(GameSession.rank_up_hero(keeper, BALANCE), "the pre-reload Hero is no longer on the roster")
	assert_eq(GameSession.last_action_error, "That hero is not on the roster.")
	assert_eq(_profile(), before, "a stale Hero charges nothing")

	roster_list.select(0)
	roster_list.multi_selected.emit(0, true)
	GameSession.set("_save_deferred_depth", 0)
	rank_up.pressed.emit()
	GameSession.set("_save_deferred_depth", 1)
	assert_string_starts_with(status.text, "Ranked Keeper up")
	assert_true(_disk_load())
	assert_eq(GameSession.hero_by_id(keeper.instance_id).rank, 1, "the rank-up that showed is on disk")
	assert_eq(GameSession.essence, 0)
	assert_eq(_kinds(), ["ranked_up"])


## ig-8hj, boundary #3: each death path runs inside _commit_profile_mutation, so a failed save
## leaves the hero alive in memory and on disk. Each test then lets the same step run with the save
## working and sees the hero die, so it is a real death path.
func test_an_abandon_whose_save_fails_leaves_the_hero_alive_on_disk() -> void:
	var source: Dictionary = _stranded_incident("abandon")
	_disk_save()
	var incident_id: String = str(GameSession.stranded_incidents[0]["id"])
	assert_false(_with_failing_save(GameSession.abandon_stranded.bind(incident_id)))
	assert_string_starts_with(GameSession.last_action_error, "Save failed")
	_assert_alive(source["hero_id"])
	assert_true(GameSession.abandon_stranded(incident_id), GameSession.last_action_error)
	assert_null(GameSession.hero_by_id(source["hero_id"]), "the control: abandon kills")
	assert_true(_disk_load())
	_assert_alive(source["hero_id"])


func test_a_live_expiry_whose_save_fails_leaves_the_hero_alive_on_disk() -> void:
	var source: Dictionary = _stranded_incident("expiry")
	_disk_save()
	_expire(GameSession.stranded_incidents[0])
	_with_failing_save(GameSession.tick_expeditions.bind(0.1))
	_assert_alive(source["hero_id"])
	GameSession.tick_expeditions(0.1)
	assert_null(GameSession.hero_by_id(source["hero_id"]), "the control: the expiry kills")
	assert_true(_disk_load())
	_assert_alive(source["hero_id"])


func test_a_failed_rescue_whose_save_fails_leaves_the_heroes_alive_on_disk() -> void:
	var doomed: Array[String] = _doomed_rescue("rescue")
	_with_failing_save(GameSession.tick_expeditions.bind(0.1))
	for hero_id: String in doomed:
		_assert_alive(hero_id)
	GameSession.tick_expeditions(0.1)
	for hero_id: String in doomed:
		assert_null(GameSession.hero_by_id(hero_id), "the control: the failed rescue kills")
	assert_true(_disk_load())
	for hero_id: String in doomed:
		_assert_alive(hero_id)


func test_an_offline_catch_up_whose_save_fails_leaves_the_heroes_alive_on_disk() -> void:
	var doomed: Array[String] = _doomed_rescue("offline")
	var now: float = GameSession.saved_at_unix + 1.0
	_with_failing_save(GameSession.apply_offline_expedition_progress.bind(now))
	for hero_id: String in doomed:
		_assert_alive(hero_id)
	GameSession.apply_offline_expedition_progress(now)
	for hero_id: String in doomed:
		assert_null(GameSession.hero_by_id(hero_id), "the control: the catch-up kills")
	assert_true(_disk_load())
	for hero_id: String in doomed:
		_assert_alive(hero_id)


## ig-7sn.9: the hub keeps each hero's History lines until the ledger or the roster's names change;
## what it keeps equals a fresh read after a new record, a sacrifice, and a rename with no record.
func test_the_kept_history_equals_a_fresh_read_after_a_record_and_a_sacrifice() -> void:
	var ada: Hero = _hero("Ada", "knight")
	var bea: Hero = _hero("Bea", "knight")
	var cal: Hero = _hero("Cal", "knight")
	GameSession.add_hero(ada)
	GameSession.add_hero(bea)
	GameSession.add_hero(cal)
	var hub: Node3D = _hub()
	hub._open(&"Forge")
	var fresh: Callable = func() -> Array[String]:
		return Ledger.history_lines(GameSession.ledger, ada.instance_id, hub._roster_names(), BALANCE.rank_names, 10)
	assert_eq(hub._history_lines(ada), fresh.call())
	var before: Array[String] = hub._history_lines(ada)
	GameSession._record("battle", {"order": "order:kept", "zone": "verdant_outskirts", "team": [ada.instance_id, bea.instance_id], "result": "retreated", "moments": []})
	assert_ne(hub._history_lines(ada), before, "the new record shows")
	assert_eq(hub._history_lines(ada), fresh.call(), "after a new record")
	assert_true(GameSession.sacrifice_hero(bea, ada, BALANCE), GameSession.last_action_error)
	assert_eq(hub._history_lines(ada), fresh.call(), "after a sacrifice")
	cal.hero_name = "Cass"
	GameSession._record("battle", {"order": "order:cal", "zone": "verdant_outskirts", "team": [ada.instance_id, cal.instance_id], "result": "retreated", "moments": [{"tick": 1, "what": "revived", "hero": ada.instance_id, "by": cal.instance_id}]})
	assert_string_contains("\n".join(hub._history_lines(ada)), "revived by Cass")
	cal.hero_name = "Cato"
	assert_string_contains("\n".join(hub._history_lines(ada)), "revived by Cato", "a rename writes no record, and still reads again")
	assert_eq(hub._history_lines(ada), fresh.call(), "after a rename")


## Runs action with the save forced to fail (a folder where the staged save goes) and returns its
## result. Saves are live only inside it.
func _with_failing_save(action: Callable) -> Variant:
	assert_eq(DirAccess.make_dir_absolute(SaveService.TMP_PATH), OK)
	GameSession.set("_save_deferred_depth", 0)
	var result: Variant = action.call()
	GameSession.set("_save_deferred_depth", 1)
	assert_eq(DirAccess.remove_absolute(SaveService.TMP_PATH), OK)
	assert_push_error("Save failed")
	return result


## The profile as saved, plus the Ledger, which the main save keeps out.
func _profile() -> String:
	var data: Dictionary = GameSession.to_dict()
	data.erase("saved_at_unix")
	return JSON.stringify(data) + JSON.stringify(GameSession.ledger)


func _assert_alive(hero_id: String) -> void:
	assert_not_null(GameSession.hero_by_id(hero_id), "%s is alive" % hero_id)
	assert_eq(_died(hero_id), {}, "no died record for %s" % hero_id)


func _expire(incident: Dictionary) -> void:
	incident["paused"] = false
	incident["created_recovery_seconds"] = 0.0
	GameSession.rescue_clock_seconds = (BALANCE.recovery_base_duration_seconds + BALANCE.recovery_duration_seconds_per_level * 10.0) * BALANCE.battle_pace + 1.0


## A stranded hero and a rescue in flight, saved to disk like that. Then, in memory only, the
## window runs out and the rescue fails, so the next settle kills both. Returns their ids.
func _doomed_rescue(prefix: String) -> Array[String]:
	var source: Dictionary = _stranded_incident(prefix + "_source")
	var rescuer: Dictionary = _add_one(prefix + "_rescuer")
	var rescue_order_id: String = GameSession.dispatch_rescue(str(GameSession.stranded_incidents[0]["id"]), rescuer["preset_id"], _zero_loadout())
	assert_ne(rescue_order_id, "", GameSession.last_action_error)
	_disk_save()
	GameSession.stranded_incidents[0]["expiry_pending"] = true
	_fail_all_allies(rescue_order_id)
	return [source["hero_id"], rescuer["hero_id"]] as Array[String]


func _hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub


## Source hero stranded, then a rescue that strands its rescuer too; saved and reloaded twice.
func _strand_a_rescuer(prefix: String) -> Dictionary:
	var source: Dictionary = _stranded_incident(prefix + "_source")
	var rescuer: Dictionary = _add_one(prefix + "_rescuer")
	var rescue_order_id: String = GameSession.dispatch_rescue(str(GameSession.stranded_incidents[0]["id"]), rescuer["preset_id"], _zero_loadout())
	assert_ne(rescue_order_id, "", GameSession.last_action_error)
	assert_true(_disk_load_after_save())
	_fail_all_allies(rescue_order_id)
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_eq(_sorted(GameSession.stranded_incidents[0]["hero_ids"]), _sorted([source["hero_id"], rescuer["hero_id"]]))
	assert_eq(GameSession.stranded_incidents[0]["battle_orders"], {rescuer["hero_id"]: rescue_order_id}, "only the exception")
	var rescue: Array[Dictionary] = _battle_records(rescue_order_id)
	assert_eq(rescue.size(), 1)
	assert_eq(_sorted(rescue[0]["team"]), _sorted([source["hero_id"], rescuer["hero_id"]]), "the stranded hero witnessed the rescue")
	assert_eq(rescue[0]["rescued"], [])
	var stranded_line: String = "Stranded at %s" % ZoneDefinition.definition_for(StringName(str(rescue[0]["zone"]))).display_name
	assert_true(Ledger.history_lines(GameSession.ledger, rescuer["hero_id"], {}, BALANCE.rank_names, 1)[0].begins_with(stranded_line), "a total failure reads as its result, not as a rescue")
	assert_true(_disk_load_after_save())
	assert_eq(GameSession.stranded_incidents[0]["battle_orders"], {rescuer["hero_id"]: rescue_order_id}, "survives the reload")
	return {"source_hero": source["hero_id"], "source_order": source["order_id"], "rescuer": rescuer["hero_id"], "rescue_order": rescue_order_id}


func _assert_rescuer_links(links: Dictionary) -> void:
	_assert_expedition_death(links["source_hero"], links["source_order"])
	_assert_expedition_death(links["rescuer"], links["rescue_order"])
	assert_true(links["rescuer"] in _battle_records(links["rescue_order"])[0]["team"], "the linked record lists the rescuer")
	assert_true(links["source_hero"] in _battle_records(links["source_order"])[0]["team"])


func _sorted(values: Array) -> Array:
	var copy: Array = values.duplicate()
	copy.sort()
	return copy


func _stranded_incident(prefix: String) -> Dictionary:
	var hero: Dictionary = _add_one(prefix)
	var order_id: String = GameSession.dispatch_force([hero["preset_id"]], "verdant_outskirts", 1, {}, _zero_loadout())
	_fail_all_allies(order_id)
	GameSession.tick_expeditions(0.1)
	assert_eq(GameSession.stranded_incidents.size(), 1)
	assert_eq(str(GameSession.stranded_incidents[0]["source_order_id"]), order_id)
	return {"hero_id": hero["hero_id"], "order_id": order_id}


func _assert_expedition_death(hero_id: String, order_id: String) -> void:
	assert_null(GameSession.hero_by_id(hero_id))
	var died: Dictionary = _died(hero_id)
	assert_eq(died.get("cause"), "expedition")
	assert_eq(died.get("zone"), "verdant_outskirts")
	assert_eq(died.get("battle_order"), order_id)
	assert_eq(GameSession.ledger.filter(func(record: Dictionary) -> bool: return record["kind"] == "died" and record["hero"] == hero_id).size(), 1, "one died record")


func _died(hero_id: String) -> Dictionary:
	for record: Dictionary in GameSession.ledger:
		if record["kind"] == "died" and record["hero"] == hero_id:
			return record
	return {}


func _battle_records(order_id: String) -> Array[Dictionary]:
	return GameSession.ledger.filter(func(record: Dictionary) -> bool: return record["kind"] == "battle" and record["order"] == order_id)


func _add_one(prefix: String) -> Dictionary:
	var hero := _hero(prefix.capitalize(), "knight")
	hero.rank = 7
	hero.level = 80
	GameSession.roster.append(hero)
	return {"hero_id": hero.instance_id, "preset_id": GameSession.save_team_preset("", prefix, [hero.instance_id], "verdant_outskirts")}


func _hero(hero_name: String, archetype: String) -> Hero:
	var hero := Hero.new(hero_name, 0)
	hero.def_id = StringName(archetype)
	hero.instance_id = "hero:%s" % hero_name.to_lower()
	return hero


func _fail_all_allies(order_id: String) -> void:
	for order: Dictionary in GameSession.expedition_orders:
		if str(order["id"]) != order_id:
			continue
		var battle: Dictionary = order["battle"] as Dictionary
		var downed_ids: Array[String] = []
		for actor: Dictionary in battle["actors"] as Array[Dictionary]:
			if str(actor["faction"]) == "ally":
				actor["life"] = BattleActor.LIFE_DOWNED
				actor["hp"] = 0.0
				downed_ids.append(str(actor["hero_id"]))
		battle["status"] = "stranded"
		battle["downed_ever_ids"] = downed_ids
		battle["extracted_ids"] = []
		order["phase"] = "returning"


func _disk_save() -> String:
	GameSession.set("_save_deferred_depth", 0)
	var saved: bool = SaveService.save()
	GameSession.set("_save_deferred_depth", 1)
	assert_true(saved, SaveService.last_write_error)
	return FileAccess.get_file_as_string(SaveService.SAVE_PATH)


func _disk_load() -> bool:
	var loaded: bool = SaveService.load_game()
	assert_false(SaveService.load_blocked, SaveService.load_block_reason)
	return loaded


func _disk_load_after_save() -> bool:
	_disk_save()
	return _disk_load()


func _write_save(payload: Dictionary) -> void:
	if FileAccess.file_exists(SaveService.LEDGER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.LEDGER_PATH))
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value)) as Dictionary


## A hero whose pairs were all evicted keeps an empty map in a kept index and has none in a rebuild (test_bonds does the same).
func _nonempty(pairs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hero_id: String in pairs:
		if not (pairs[hero_id] as Dictionary).is_empty():
			out[hero_id] = pairs[hero_id]
	return out


func _kinds() -> Array:
	return GameSession.ledger.map(func(record: Dictionary) -> String: return record["kind"])


func _without_time(record: Dictionary) -> Dictionary:
	var copy: Dictionary = record.duplicate(true)
	assert_true(copy.get("time") is int and int(copy["time"]) > 0)
	copy.erase("time")
	return copy


func _scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir_path):
		if not sub.begins_with(".") and sub not in ["addons", "tools", "export"]:
			found.append_array(_scripts(dir_path.path_join(sub)))
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found


func _zero_loadout() -> Dictionary:
	return {"healing": 0, "revival": 0, "keep_healing": 0, "keep_revival": 0}


## ig-7sn.12: a load owes its offline battle-seconds as catch_up_seconds, run as jobs after it. This
## sends them and lands the round (without advancing any battle).
func _land_catch_ups() -> void:
	GameSession._send_battle_checks()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not GameSession._battle_checks.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		GameSession._land_battle_checks()
	assert_true(GameSession._battle_checks.is_empty(), "the catch-up landed")
