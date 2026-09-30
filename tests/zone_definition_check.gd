extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var exit_code: int = _check_zone("Verdant Outskirts", "res://zones/defs/verdant_outskirts.tres", 900, 5, 0.5, 0.9, 1.1, "F–C parts, light Summon Stones", 25, 24, "Available from start")
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_zone("Ashfall Reaches", "res://zones/defs/ashfall_reaches.tres", 4800, 6, 0.5, 1.0, 1.2, "C–A parts, moderate Summon Stones, first A+ drops", 75, 72, "Clear Verdant Outskirts")
	if exit_code != 0:
		quit(exit_code)
		return
	exit_code = _check_zone("Sundered Vault", "res://zones/defs/sundered_vault.tres", 11500, 7, 0.6, 1.1, 1.3, "S–SSS parts, heavy Summon Stones, best A+ drop rate", 200, 192, "Clear Ashfall Reaches")
	if exit_code == 0:
		print("PASS: all fields of all three zones match SYSTEMS.md.")
	quit(exit_code)


func _check_zone(zone_name: String, resource_path: String, expected_recommended_power: int, expected_trash_wave_count: int, expected_start_fraction: float, expected_end_fraction: float, expected_boss_fraction: float, expected_loot_emphasis: String, expected_stone_reward: int, expected_xp_reward: int, expected_unlock_condition: String) -> int:
	var zone: ZoneDefinition = load(resource_path) as ZoneDefinition
	if zone == null:
		return _fail("%s resource load" % zone_name, "ZoneDefinition", "null")
	if zone.display_name != zone_name:
		return _fail("%s display_name" % zone_name, zone_name, zone.display_name)
	if zone.recommended_power != expected_recommended_power:
		return _fail("%s recommended_power" % zone_name, str(expected_recommended_power), str(zone.recommended_power))
	if zone.trash_wave_count != expected_trash_wave_count:
		return _fail("%s trash_wave_count" % zone_name, str(expected_trash_wave_count), str(zone.trash_wave_count))
	if zone.trash_wave_start_fraction != expected_start_fraction:
		return _fail("%s trash_wave_start_fraction" % zone_name, str(expected_start_fraction), str(zone.trash_wave_start_fraction))
	if zone.trash_wave_end_fraction != expected_end_fraction:
		return _fail("%s trash_wave_end_fraction" % zone_name, str(expected_end_fraction), str(zone.trash_wave_end_fraction))
	if zone.boss_fraction != expected_boss_fraction:
		return _fail("%s boss_fraction" % zone_name, str(expected_boss_fraction), str(zone.boss_fraction))
	if zone.loot_emphasis != expected_loot_emphasis:
		return _fail("%s loot_emphasis" % zone_name, expected_loot_emphasis, zone.loot_emphasis)
	if zone.stone_reward != expected_stone_reward:
		return _fail("%s stone_reward" % zone_name, str(expected_stone_reward), str(zone.stone_reward))
	if zone.xp_reward != expected_xp_reward:
		return _fail("%s xp_reward" % zone_name, str(expected_xp_reward), str(zone.xp_reward))
	if zone.unlock_condition != expected_unlock_condition:
		return _fail("%s unlock_condition" % zone_name, expected_unlock_condition, zone.unlock_condition)
	if zone.skill_book_drop_chance < 0.0 or zone.skill_book_drop_chance > 1.0:
		return _fail("%s skill_book_drop_chance" % zone_name, "0 to 1", str(zone.skill_book_drop_chance))
	return 0


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
