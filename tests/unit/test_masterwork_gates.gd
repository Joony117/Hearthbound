extends GutTest

# ig-wgj.12: +13 to +15 at the Forge and the SS->SSS rank-up need a master (a passion, skill 5) who
# keeps that building and is home. Both gates live in the mutators (SYSTEMS.md § Keepers and professions).

const BALANCE: BalanceTable = preload("res://balance.tres")
const MASTER_XP: float = 300.0 * 60.0
const SKILL_4_XP: float = 200.0 * 60.0
const SS: int = 6
const RITES_REFUSAL: String = "SS->SSS needs a born master priest working here."


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.building_levels[1] = 5


func after_each() -> void:
	GameSession.set_process(true)


func test_plus_13_is_refused_without_a_home_master_smith() -> void:
	var item: Item = _item_at(12)
	assert_false(GameSession.enhance_item(item, BALANCE), "no keeper")
	var smith: Hero = _keeper("Mira", &"Forge", [&"rites", &"drill"], &"smithing", MASTER_XP)
	assert_false(GameSession.enhance_item(item, BALANCE), "skill 5 without the passion")
	smith.passions = [&"smithing", &"drill"] as Array[StringName]
	smith.profession_xp[&"smithing"] = SKILL_4_XP
	assert_false(GameSession.enhance_item(item, BALANCE), "the passion below skill 5")
	smith.profession_xp[&"smithing"] = MASTER_XP
	_send_away(smith)
	assert_false(GameSession.enhance_item(item, BALANCE), "the master away")
	assert_eq(item.enhance_level, 12)
	assert_eq(GameSession.parts[item.rank], 999, "a refusal spends nothing")
	assert_eq(GameSession.enhance_cap(BALANCE), 12)
	_come_home()
	assert_eq(GameSession.enhance_cap(BALANCE), 15)
	assert_true(GameSession.enhance_item(item, BALANCE), "the master home")
	assert_eq(item.enhance_level, 13)


func test_gear_past_12_keeps_its_level_when_the_master_leaves_and_through_a_save() -> void:
	var smith: Hero = _keeper("Mira", &"Forge", [&"smithing", &"drill"], &"smithing", MASTER_XP)
	var item: Item = _item_at(13)
	assert_true(GameSession.enhance_item(item, BALANCE))
	assert_eq(item.enhance_level, 14)
	assert_true(GameSession.unstation_hero(smith), GameSession.last_action_error)
	assert_eq(item.enhance_level, 14)
	assert_false(GameSession.enhance_item(item, BALANCE), "no further without the master")
	var band: Array[Item] = [_item_at(13), item, _item_at(15)]
	_disk_round_trip()
	for kept: Item in band:
		var loaded: Item = GameSession.item_by_id(kept.instance_id)
		assert_eq(loaded.enhance_level, kept.enhance_level, "clamped_enhance_level still trusts +15")
		assert_eq(Item.clamped_enhance_level(loaded, BALANCE), kept.enhance_level)


func test_bulk_enhance_obeys_the_same_cap_and_goes_stale_when_the_master_leaves() -> void:
	var item: Item = _item_at(11)
	var budget: Array[int] = [0, 0, 0, 999, 0, 0, 0, 0]
	var plan: Dictionary = GameSession.preview_bulk_enhance([item.instance_id] as Array[String], 15, budget)
	assert_eq(int(plan["parameters"]["target_level"]), 12, "the target stops at the floor")
	assert_eq(int(plan["entries"][0]["after_level"]), 12)
	var smith: Hero = _keeper("Mira", &"Forge", [&"smithing", &"drill"], &"smithing", MASTER_XP)
	plan = GameSession.preview_bulk_enhance([item.instance_id] as Array[String], 15, budget)
	assert_eq(int(plan["entries"][0]["after_level"]), 15, "a master home opens the band")
	_send_away(smith)
	assert_false(GameSession.commit_bulk_plan(plan), "a preview never offers what the settle refuses")
	assert_eq(item.enhance_level, 11)
	_come_home()
	assert_true(GameSession.commit_bulk_plan(plan), GameSession.last_action_error)
	assert_eq(item.enhance_level, 15)


func test_ss_to_sss_is_refused_without_a_home_master_priest_and_spends_nothing() -> void:
	var target: Hero = _hero_at(SS, "Target")
	_expect_refused(target, "no keeper")
	var priest: Hero = _keeper("Sera", &"Sanctum", [&"smithing", &"drill"], &"rites", MASTER_XP)
	_expect_refused(target, "skill 5 without the passion")
	priest.passions = [&"rites", &"drill"] as Array[StringName]
	priest.profession_xp[&"rites"] = SKILL_4_XP
	_expect_refused(target, "the passion below skill 5")
	priest.profession_xp[&"rites"] = MASTER_XP
	_send_away(priest)
	_expect_refused(target, "the master away")
	_come_home()
	assert_true(GameSession.rank_up_hero(target, BALANCE), GameSession.last_action_error)
	assert_eq(target.rank, SS + 1)
	assert_eq(GameSession.essence, 100000 - BALANCE.rank_up_essence_costs[SS])


func test_the_master_priest_may_rank_up_itself() -> void:
	var priest: Hero = _keeper("Sera", &"Sanctum", [&"rites", &"drill"], &"rites", MASTER_XP)
	priest.rank = SS
	GameSession.essence = 100000
	assert_true(GameSession.rank_up_hero(priest, BALANCE), GameSession.last_action_error)
	assert_eq(priest.rank, SS + 1)


func test_every_other_rank_up_needs_no_priest() -> void:
	GameSession.essence = 100000
	var hero: Hero = _hero_at(0, "Climber")
	for rank: int in SS:
		assert_true(GameSession.rank_up_hero(hero, BALANCE), "rank %d: %s" % [rank, GameSession.last_action_error])
		assert_eq(hero.rank, rank + 1)
	assert_eq(hero.rank, SS)
	_expect_refused(hero, "the last step still needs one")


func test_an_sss_hero_loads_as_sss_with_no_priest() -> void:
	var hero: Hero = _hero_at(SS + 1, "Ascended")
	_disk_round_trip()
	assert_eq(GameSession.hero_by_id(hero.instance_id).rank, SS + 1)
	assert_push_warning_count(0)


func test_the_hub_says_why_each_gate_is_closed() -> void:
	_item_at(12)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	hub._open(&"Forge")
	var note: String = "Masterwork (+13 to +15) needs a born smith at skill 5 working here."
	assert_eq((hub.get_node("%ForgeLevel") as Label).tooltip_text, note)
	assert_eq((hub.get_node("%Enhance") as Button).tooltip_text, note)
	assert_eq((hub.get_node("%RankUp") as Button).tooltip_text, RITES_REFUSAL)
	_open_enhance(hub, 12, note)
	var smith: Hero = _keeper("Mira", &"Forge", [&"smithing", &"drill"], &"smithing", MASTER_XP)
	var priest: Hero = _keeper("Sera", &"Sanctum", [&"rites", &"drill"], &"rites", MASTER_XP)
	assert_eq((hub.get_node("%ForgeLevel") as Label).tooltip_text, "")
	assert_eq((hub.get_node("%Enhance") as Button).tooltip_text, "")
	assert_eq((hub.get_node("%RankUp") as Button).tooltip_text, "")
	_open_enhance(hub, 15, "")
	_send_away(smith)
	_send_away(priest)
	GameSession.expeditions_changed.emit()
	assert_eq((hub.get_node("%ForgeLevel") as Label).tooltip_text, note, "the master left")
	assert_eq((hub.get_node("%RankUp") as Button).tooltip_text, RITES_REFUSAL, "the master left")
	_open_enhance(hub, 12, note)
	_come_home()
	GameSession.building_levels[1] = 4
	GameSession.roster_changed.emit()
	assert_eq((hub.get_node("%ForgeLevel") as Label).tooltip_text, "", "a Forge below level 5 is not held by the gate")


## Presses Enhance on the one inventory item: the dialog's target max and the note in its preview.
func _open_enhance(hub: Node3D, target_max: int, note: String) -> void:
	var inventory: ItemList = hub.get_node("%InventoryList") as ItemList
	inventory.select(0)
	inventory.multi_selected.emit(0, true)
	(hub.get_node("%Enhance") as Button).pressed.emit()
	assert_eq(int((hub.get_node("%EnhanceTargetLevel") as SpinBox).max_value), target_max)
	var preview: String = (hub.get_node("%EnhancePreview") as RichTextLabel).text
	if note.is_empty():
		assert_false(preview.contains("Masterwork"), preview)
	else:
		assert_true(preview.begins_with(note), preview)
	(hub.get_node("%EnhanceDialog") as ConfirmationDialog).hide()


func _expect_refused(hero: Hero, why: String) -> void:
	GameSession.essence = 100000
	var rank: int = hero.rank
	assert_false(GameSession.rank_up_hero(hero, BALANCE), why)
	assert_eq(GameSession.last_action_error, RITES_REFUSAL, why)
	assert_eq(hero.rank, rank, why)
	assert_eq(GameSession.essence, 100000, why + ": no Essence spent")


func _keeper(hero_name: String, building: StringName, passions: Array, profession: StringName, xp: float) -> Hero:
	var hero: Hero = _hero_at(0, hero_name)
	hero.passions.assign(passions)
	hero.profession_xp[profession] = xp
	assert_true(GameSession.station_hero(hero, building), GameSession.last_action_error)
	return hero


func _hero_at(rank: int, hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, rank)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	return hero


func _item_at(level: int) -> Item:
	var item := Item.new(&"ring", 3)
	item.enhance_level = level
	GameSession.add_item(item)
	GameSession.parts[item.rank] = 999
	return item


## In memory only: a route order holding the hero makes it busy (is_hero_busy). Never saved: save() refuses it.
func _send_away(hero: Hero) -> void:
	GameSession.expedition_orders.append({
		"id": "away-" + hero.instance_id,
		"team_name": "Away",
		"hero_ids": [hero.instance_id],
		"zone_id": "verdant_outskirts",
		"initial_duration_seconds": 99999.0,
		"remaining_seconds": 99999.0,
		"runs_completed": 0,
		"total_runs": 1,
		"stop_requested": false,
	})


func _come_home() -> void:
	for index: int in range(GameSession.expedition_orders.size() - 1, -1, -1):
		if str(GameSession.expedition_orders[index]["id"]).begins_with("away-"):
			GameSession.expedition_orders.remove_at(index)


func _disk_round_trip() -> void:
	assert_true(SaveService.save())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_true(SaveService.load_game(), SaveService.load_block_reason)
