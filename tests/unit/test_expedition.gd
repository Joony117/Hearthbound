extends GutTest

const ERROR_MARGIN: float = 0.0001
const HERO_POWER: float = 212.0
const HERO_MAX_HP: float = 280.0
const HUB_SCRIPT: GDScript = preload("res://hub/hub.gd")
const BALANCE: BalanceTable = preload("res://balance.tres")


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_zero_power_wave_sequence_completes_with_hero_alive() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	seed(1)

	var outcome := expedition.resolve(team, _make_zone(0, 1.0, 2))

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_true(GameSession.roster.has(hero))
	assert_eq(expedition.waves_resolved, 3)
	assert_almost_eq(expedition.current_hp[hero], HERO_MAX_HP, ERROR_MARGIN)


func test_completed_expedition_credits_zone_stone_reward() -> void:
	var hero: Hero = _add_knight()
	var team: Array[Hero] = [hero]
	var zone: ZoneDefinition = _make_zone(0, 1.0, 1)
	zone.stone_reward = 25
	var stones_before: int = GameSession.stones
	seed(1)

	var outcome: StringName = Expedition.new().resolve(team, zone)

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_eq(GameSession.stones, stones_before + zone.stone_reward)


func test_retreated_expedition_credits_no_stones() -> void:
	var hero: Hero = _add_knight()
	hero.level = 9
	var team: Array[Hero] = [hero]
	var r: float = 0.9
	var definition: HeroDefinition = Hero.definition_for(hero.def_id)
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [hero.level]
	var hero_power: float = Hero.compute_team_power(team, definitions, levels, preload("res://balance.tres"))
	var recommended_power: int = int(hero_power * r / (float(team.size()) / 5.0 * 0.5))
	var zone: ZoneDefinition = _make_zone(recommended_power, 0.5, 3)
	zone.stone_reward = 75
	var stones_before: int = GameSession.stones
	_seed_for_rolls_above(r, 3)

	var outcome: StringName = Expedition.new().resolve(team, zone)

	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_eq(GameSession.stones, stones_before)
	assert_eq(hero.xp, 12)
	# A retreat is still a resolved expedition, so it costs a turn (docs/SYSTEMS.md, Turns).
	assert_eq(GameSession.turns, 1)


func test_retreated_expedition_teaches_a_trait_after_xp_reaches_the_cap() -> void:
	var trainee: Hero = _add_knight("Trainee")
	trainee.level = 9
	trainee.xp = 88
	var instructor: Hero = Hero.new("Instructor", 1)
	instructor.def_id = &"rogue"
	GameSession.add_hero(instructor)
	var team: Array[Hero] = [trainee, instructor]
	var r: float = 0.9
	var trainee_definition: HeroDefinition = Hero.definition_for(trainee.def_id)
	var instructor_definition: HeroDefinition = Hero.definition_for(instructor.def_id)
	var definitions: Array[HeroDefinition] = [trainee_definition, instructor_definition]
	var levels: Array[int] = [trainee.level, instructor.level]
	var hero_power: float = Hero.compute_team_power(team, definitions, levels, BALANCE)
	var recommended_power: int = int(hero_power * r / (float(team.size()) / 5.0 * 0.5))
	var zone: ZoneDefinition = _make_zone(recommended_power, 0.5, 3)
	_seed_for_rolls_above(r, 3)

	var outcome: StringName = Expedition.new().resolve(team, zone)

	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_eq(trainee.level, BALANCE.level_caps[trainee.rank])
	assert_eq(trainee.xp, 0)
	assert_eq(trainee.taught_traits, [&"knight_shield_drill"])


func test_defeated_expedition_credits_no_stones() -> void:
	var hero: Hero = _add_knight()
	var team: Array[Hero] = [hero]
	var zone: ZoneDefinition = _make_zone(1_000_000, 1.0, 1)
	zone.stone_reward = 200
	var stones_before: int = GameSession.stones
	seed(1)

	var outcome: StringName = Expedition.new().resolve(team, zone)

	assert_eq(outcome, Expedition.OUTCOME_DEFEATED)
	assert_eq(GameSession.stones, stones_before)


func test_each_resolved_outcome_advances_the_turn_counter_by_one() -> void:
	var completed_hero: Hero = _add_knight()
	seed(1)
	assert_eq(Expedition.new().resolve([completed_hero], _make_zone(0, 1.0, 1)), Expedition.OUTCOME_COMPLETED)
	assert_eq(GameSession.turns, 1)

	var defeated_hero: Hero = _add_knight("Doomed")
	seed(1)
	assert_eq(
		Expedition.new().resolve([defeated_hero], _make_zone(1_000_000, 1.0, 1)),
		Expedition.OUTCOME_DEFEATED,
	)
	assert_eq(GameSession.turns, 2)


func test_hub_turn_readout_updates_without_leaving_the_scene() -> void:
	GameSession.turns = 3
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var turns_label: Label = hub.get_node("%Turns") as Label

	assert_eq(turns_label.text, "Turn 3")
	GameSession.advance_turn(BALANCE)
	assert_eq(turns_label.text, "Turn 4")


func test_invalid_team_does_not_advance_the_turn_counter() -> void:
	var hero := Hero.new("Ghost", 0)
	hero.def_id = &"not_an_archetype"
	GameSession.add_hero(hero)

	assert_eq(
		Expedition.new().resolve([hero], _make_zone(0, 1.0, 1)),
		Expedition.OUTCOME_INVALID_TEAM,
	)
	assert_push_error("Missing HeroDefinition")
	assert_eq(GameSession.turns, 0)


## The tick lands before the wave loop, so a cache from a death on this expedition reads
## turns_elapsed == 0 at an immediate recovery rather than -1 (docs/SYSTEMS.md, Turns).
func test_a_death_stamps_the_cache_with_the_turn_its_own_expedition_became() -> void:
	var hero: Hero = _add_knight("Doomed")
	var item := Item.new(&"ring", 3)
	GameSession.add_item(item)
	GameSession.equip_item(hero, item)
	GameSession.turns = 4
	seed(1)

	assert_eq(
		Expedition.new().resolve([hero], _make_zone(1_000_000, 1.0, 1)),
		Expedition.OUTCOME_DEFEATED,
	)
	assert_eq(GameSession.turns, 5)
	assert_eq(GameSession.lost_caches.size(), 1)
	assert_eq(GameSession.lost_caches[0].turn_lost, 5)


func test_last_hero_death_below_pull_cost_restores_one_pull() -> void:
	var hero: Hero = _add_knight()
	GameSession.stones = BALANCE.summon_pull_cost - 1

	GameSession.kill_hero(hero, &"test_zone", BALANCE)

	assert_eq(GameSession.stones, BALANCE.summon_pull_cost)


func test_last_hero_death_at_pull_cost_preserves_stones() -> void:
	var hero: Hero = _add_knight()
	GameSession.stones = BALANCE.summon_pull_cost

	GameSession.kill_hero(hero, &"test_zone", BALANCE)

	assert_eq(GameSession.stones, BALANCE.summon_pull_cost)


func test_hero_death_with_survivor_does_not_restore_stones() -> void:
	var hero: Hero = _add_knight()
	_add_knight("Survivor")
	GameSession.stones = 0

	GameSession.kill_hero(hero, &"test_zone", BALANCE)

	assert_eq(GameSession.stones, 0)


func test_training_hall_level_five_rounds_exact_xp_rewards() -> void:
	GameSession.building_levels[2] = 5
	var defeated_hero := Hero.new("Defeated Knight", 7)
	defeated_hero.def_id = &"knight"
	GameSession.add_hero(defeated_hero)
	seed(1)

	var outcome: StringName = Expedition.new().resolve(
		[defeated_hero],
		_make_zone(1_000_000, 1.0, 1),
	)

	assert_eq(outcome, Expedition.OUTCOME_DEFEATED)
	assert_eq(_earned_xp(defeated_hero), 7)
	var completion_waves_xp: int = _completed_xp_with_reward(0)
	assert_eq(completion_waves_xp, 14)
	assert_eq(_completed_xp_with_reward(24) - completion_waves_xp, 42)
	assert_eq(_completed_xp_with_reward(72) - completion_waves_xp, 126)
	assert_eq(_completed_xp_with_reward(192) - completion_waves_xp, 336)
	GameSession.from_dict({"roster": []})


func test_credit_team_xp_grants_every_hero_and_emits_once() -> void:
	var first := Hero.new("First", 7)
	var second := Hero.new("Second", 7)
	var team: Array[Hero] = [first, second]
	watch_signals(GameSession)

	GameSession.credit_team_xp(team, 7, preload("res://balance.tres"))

	assert_eq(first.xp, 7)
	assert_eq(second.xp, 7)
	assert_signal_emit_count(GameSession, "roster_changed", 1)


func test_credit_team_xp_grants_the_capped_trainees_stage_trait() -> void:
	var trainee: Hero = _add_knight("Trainee")
	trainee.level = BALANCE.level_caps[trainee.rank]
	var instructor: Hero = Hero.new("Instructor", 1)
	instructor.def_id = &"rogue"
	GameSession.add_hero(instructor)

	GameSession.credit_team_xp([trainee, instructor], 0, BALANCE)

	assert_eq(trainee.taught_traits, [&"knight_shield_drill"])


func test_credit_team_xp_grants_survivor_after_another_fielded_hero_dies() -> void:
	var trainee: Hero = _add_knight("Surviving Trainee")
	trainee.level = BALANCE.level_caps[trainee.rank]
	var instructor: Hero = Hero.new("Instructor", 1)
	instructor.def_id = &"rogue"
	GameSession.add_hero(instructor)
	var doomed: Hero = _add_knight("Doomed")
	GameSession.kill_hero(doomed, &"test_zone", BALANCE)

	GameSession.credit_team_xp([trainee, instructor, doomed], 0, BALANCE)

	assert_eq(trainee.taught_traits, [&"knight_shield_drill"])
	assert_false(GameSession.roster.has(doomed))
	assert_true(doomed.taught_traits.is_empty())


func test_credit_team_xp_does_not_grant_to_a_removed_hero_or_exhausted_rank() -> void:
	var removed: Hero = _add_knight("Removed")
	removed.level = BALANCE.level_caps[removed.rank]
	var instructor: Hero = Hero.new("Instructor", 4)
	instructor.def_id = &"rogue"
	GameSession.add_hero(instructor)
	GameSession.kill_hero(removed, &"test_zone", BALANCE)
	var exhausted: Hero = Hero.new("Exhausted", 3)
	exhausted.def_id = &"knight"
	exhausted.level = BALANCE.level_caps[exhausted.rank]
	GameSession.add_hero(exhausted)

	GameSession.credit_team_xp([removed, instructor, exhausted], 0, BALANCE)

	assert_true(removed.taught_traits.is_empty())
	assert_true(exhausted.taught_traits.is_empty())


func test_credit_team_xp_never_regrants_a_claimed_stage() -> void:
	var trainee: Hero = _add_knight("Claimed")
	trainee.level = BALANCE.level_caps[trainee.rank]
	trainee.taught_traits = [&"knight_shield_drill"]
	var instructor: Hero = Hero.new("Instructor", 1)
	instructor.def_id = &"rogue"
	GameSession.add_hero(instructor)

	GameSession.credit_team_xp([trainee, instructor], 0, BALANCE)

	assert_eq(trainee.taught_traits, [&"knight_shield_drill"])


func test_five_hero_expedition_completes_and_records_zone_clear() -> void:
	var team: Array[Hero] = []
	for hero_index: int in 5:
		team.append(_add_knight("Knight %d" % hero_index))
	var enemy_power: int = 100
	var zone: ZoneDefinition = _make_zone(enemy_power, 1.0, 2)
	var expedition := Expedition.new()
	var r: float = float(enemy_power) / (HERO_POWER * team.size())
	var balance: BalanceTable = preload("res://balance.tres")
	var per_wave_damage: float = HERO_MAX_HP * balance.wave_damage_coefficient * r * r * r
	_seed_for_rolls_above(r, 3)

	var outcome: StringName = expedition.resolve(team, zone)

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_eq(GameSession.roster.size(), 5)
	assert_true(GameSession.cleared_zone_ids.has(zone.zone_id))
	for hero: Hero in team:
		assert_almost_eq(
			expedition.current_hp[hero],
			HERO_MAX_HP - per_wave_damage * 3.0,
			ERROR_MARGIN,
		)
		assert_lt(expedition.current_hp[hero], HERO_MAX_HP)


func test_cleared_zones_round_trip_old_save_and_linear_unlock_chain() -> void:
	assert_true(HUB_SCRIPT.is_zone_unlocked(&"verdant_outskirts", GameSession.cleared_zone_ids))
	assert_false(HUB_SCRIPT.is_zone_unlocked(&"ashfall_reaches", GameSession.cleared_zone_ids))
	assert_false(HUB_SCRIPT.is_zone_unlocked(&"sundered_vault", GameSession.cleared_zone_ids))

	GameSession.mark_zone_cleared(&"verdant_outskirts")
	assert_true(HUB_SCRIPT.is_zone_unlocked(&"ashfall_reaches", GameSession.cleared_zone_ids))
	assert_false(HUB_SCRIPT.is_zone_unlocked(&"sundered_vault", GameSession.cleared_zone_ids))
	GameSession.mark_zone_cleared(&"ashfall_reaches")
	assert_true(HUB_SCRIPT.is_zone_unlocked(&"sundered_vault", GameSession.cleared_zone_ids))
	var saved: Dictionary = GameSession.to_dict()

	GameSession.from_dict({"roster": []})
	assert_true(GameSession.cleared_zone_ids.is_empty())
	assert_true(HUB_SCRIPT.is_zone_unlocked(&"verdant_outskirts", GameSession.cleared_zone_ids))
	assert_false(HUB_SCRIPT.is_zone_unlocked(&"ashfall_reaches", GameSession.cleared_zone_ids))
	assert_false(HUB_SCRIPT.is_zone_unlocked(&"sundered_vault", GameSession.cleared_zone_ids))

	GameSession.from_dict(saved)
	assert_true(GameSession.cleared_zone_ids.has(&"verdant_outskirts"))
	assert_true(GameSession.cleared_zone_ids.has(&"ashfall_reaches"))
	assert_true(HUB_SCRIPT.is_zone_unlocked(&"sundered_vault", GameSession.cleared_zone_ids))


func test_hub_scene_multi_select_zone_locks_and_five_hero_cap() -> void:
	for hero_index: int in 6:
		_add_knight("Knight %d" % hero_index)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var zone_option: OptionButton = hub.get_node("%ZoneOption") as OptionButton
	var expedition_button: Button = hub.get_node("UI/Root/Bottom/Buttons/Expedition") as Button
	var status: Label = hub.get_node("%Status") as Label

	assert_eq(roster_list.select_mode, ItemList.SELECT_MULTI)
	assert_eq(zone_option.item_count, 3)
	assert_false(zone_option.is_item_disabled(0))
	assert_true(zone_option.is_item_disabled(1))
	assert_true(zone_option.is_item_disabled(2))
	for item_index: int in roster_list.item_count:
		roster_list.select(item_index, false)
	expedition_button.pressed.emit()
	assert_eq(status.text, "Select no more than 5 heroes.")
	assert_eq(GameSession.roster.size(), 6)
	assert_true(GameSession.cleared_zone_ids.is_empty())

	GameSession.mark_zone_cleared(&"verdant_outskirts")
	assert_false(zone_option.is_item_disabled(1))
	assert_true(zone_option.is_item_disabled(2))
	GameSession.mark_zone_cleared(&"ashfall_reaches")
	assert_false(zone_option.is_item_disabled(2))


func test_zone_selection_uses_metadata_after_option_reorder() -> void:
	_add_knight()
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var zone_option: OptionButton = hub.get_node("%ZoneOption") as OptionButton
	var expedition_button: Button = hub.get_node("UI/Root/Bottom/Buttons/Expedition") as Button
	var status: Label = hub.get_node("%Status") as Label
	var ashfall_zone: ZoneDefinition = zone_option.get_item_metadata(1) as ZoneDefinition
	assert_not_null(ashfall_zone)
	var sundered_zone: ZoneDefinition = _make_zone(100, 1.0, 1)
	sundered_zone.zone_id = &"sundered_vault"
	sundered_zone.display_name = "Sundered Vault"
	zone_option.set_item_text(1, sundered_zone.display_name)
	zone_option.set_item_metadata(1, sundered_zone)
	zone_option.set_item_text(2, ashfall_zone.display_name)
	zone_option.set_item_metadata(2, ashfall_zone)
	GameSession.mark_zone_cleared(&"verdant_outskirts")
	GameSession.mark_zone_cleared(&"ashfall_reaches")
	zone_option.select(1)
	roster_list.select(0)
	var selected_zone: ZoneDefinition = zone_option.get_item_metadata(zone_option.selected) as ZoneDefinition

	assert_not_null(selected_zone)
	assert_same(selected_zone, sundered_zone)
	assert_eq(zone_option.get_item_text(zone_option.selected), selected_zone.display_name)
	_seed_for_rolls_above(20.0 / HERO_POWER, 2)
	expedition_button.pressed.emit()
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()
	assert_eq(status.text, "1-hero team cleared Sundered Vault. Found F Legs.")


func test_roster_refresh_does_not_select_survivors_after_selected_heroes_die() -> void:
	var hero_a: Hero = _add_knight("A")
	var hero_b: Hero = _add_knight("B")
	var hero_c: Hero = _add_knight("C")
	var hero_d: Hero = _add_knight("D")
	var hero_e: Hero = _add_knight("E")
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var zone_option: OptionButton = hub.get_node("%ZoneOption") as OptionButton
	var expedition_button: Button = hub.get_node("UI/Root/Bottom/Buttons/Expedition") as Button
	var lethal_zone: ZoneDefinition = _make_zone(1_000_000, 1.0, 1)
	lethal_zone.zone_id = &"verdant_outskirts"
	lethal_zone.display_name = "Lethal Zone"
	zone_option.set_item_text(0, lethal_zone.display_name)
	zone_option.set_item_metadata(0, lethal_zone)
	roster_list.select(1, false)
	roster_list.select(3, false)
	seed(1)

	expedition_button.pressed.emit()
	# The press only asks. A misclicked expedition must not be able to kill anyone.
	assert_eq(GameSession.roster.size(), 5)
	(hub.get_node("%ConfirmDialog") as ConfirmationDialog).confirmed.emit()

	assert_eq(GameSession.roster.size(), 3)
	assert_true(GameSession.roster.has(hero_a))
	assert_false(GameSession.roster.has(hero_b))
	assert_true(GameSession.roster.has(hero_c))
	assert_false(GameSession.roster.has(hero_d))
	assert_true(GameSession.roster.has(hero_e))
	assert_true(roster_list.get_selected_items().is_empty())


func test_overwhelming_wave_kills_once_and_shrinks_roster_once() -> void:
	var hero := _add_knight()
	var other := _add_knight("Other")
	var before_size := GameSession.roster.size()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	seed(1)

	var outcome := expedition.resolve(
		team,
		_make_zone(1_000_000, 1.0, 1),
	)

	assert_eq(outcome, Expedition.OUTCOME_DEFEATED)
	assert_eq(GameSession.roster.size(), before_size - 1)
	assert_false(GameSession.roster.has(hero))
	assert_true(GameSession.roster.has(other))
	assert_eq(expedition.waves_resolved, 1)


func test_hero_without_archetype_is_refused_without_permadeath() -> void:
	var hero := Hero.new("Legacy Hero", 0)
	hero.def_id = Hero.NO_ARCHETYPE_DEF_ID
	GameSession.add_hero(hero)
	var before_size: int = GameSession.roster.size()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]

	var outcome := expedition.resolve(team, _make_zone(1_000_000, 1.0, 1))

	assert_push_error("Missing HeroDefinition for def_id")
	assert_eq(outcome, Expedition.OUTCOME_INVALID_TEAM)
	assert_eq(expedition.waves_resolved, 0)
	assert_eq(GameSession.roster.size(), before_size)
	assert_true(GameSession.roster.has(hero))


func test_retreat_at_twenty_five_percent_stops_before_later_waves() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	var team_size_factor := float(team.size()) / 5.0
	var r := 0.9
	var recommended_power := int(HERO_POWER * r / (team_size_factor * 0.5))
	var balance: BalanceTable = preload("res://balance.tres")
	var wave_damage_coefficient: float = balance.wave_damage_coefficient
	var per_wave_damage_fraction := wave_damage_coefficient * r * r * r
	_seed_for_rolls_above(r, 3)

	var outcome := expedition.resolve(
		team,
		_make_zone(recommended_power, 0.5, 3),
	)

	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_eq(expedition.waves_resolved, 3)
	assert_almost_eq(
		expedition.current_hp[hero],
		HERO_MAX_HP * (1.0 - 3.0 * per_wave_damage_fraction),
		ERROR_MARGIN,
	)
	assert_true(GameSession.roster.has(hero))


func test_damage_carries_forward_across_two_waves() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	var enemy_power := 848
	var team_size_factor := float(team.size()) / 5.0
	var r := (float(enemy_power) * team_size_factor) / HERO_POWER
	var balance: BalanceTable = preload("res://balance.tres")
	var wave_damage_coefficient: float = balance.wave_damage_coefficient
	var per_wave_damage: float = HERO_MAX_HP * clamp(wave_damage_coefficient * r * r * r, 0.0, 1.0)
	_seed_for_rolls_above(r, 2)

	var outcome := expedition.resolve(
		team,
		_make_zone(enemy_power, 1.0, 1),
	)

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_eq(expedition.waves_resolved, 2)
	assert_almost_eq(
		expedition.current_hp[hero],
		HERO_MAX_HP - per_wave_damage * 2.0,
		ERROR_MARGIN,
	)
	assert_lt(expedition.current_hp[hero], HERO_MAX_HP - per_wave_damage)


func test_authored_damage_coefficient_and_verdant_full_clear_hp() -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	assert_eq(balance.wave_damage_coefficient, 0.35)

	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	var verdant_outskirts: ZoneDefinition = preload("res://zones/defs/verdant_outskirts.tres")
	_seed_for_rolls_above(
		198.0 / HERO_POWER,
		6,
		[90.0 / HERO_POWER, 108.0 / HERO_POWER, 126.0 / HERO_POWER, 144.0 / HERO_POWER, 162.0 / HERO_POWER, 198.0 / HERO_POWER],
	)

	var outcome := expedition.resolve(team, verdant_outskirts)

	assert_eq(outcome, Expedition.OUTCOME_COMPLETED)
	assert_almost_eq(expedition.current_hp[hero], 84.69183285531011, ERROR_MARGIN)


func test_won_wave_uses_cubic_damage_fraction() -> void:
	var hero := Hero.new("Knight", 0)
	hero.def_id = &"knight"
	hero.level = 10
	var team: Array[Hero] = [hero]
	var enemy_power := 100.0
	var team_size_factor := float(team.size()) / 5.0
	var r := (enemy_power * team_size_factor) / HERO_POWER
	var balance: BalanceTable = preload("res://balance.tres")
	var wave_damage_coefficient: float = balance.wave_damage_coefficient
	_seed_for_rolls_above(r, 1)

	var result := QuickResolve.resolve(team, Wave.new(enemy_power))
	var expected_hp: float = HERO_MAX_HP * (1.0 - clamp(wave_damage_coefficient * r * r * r, 0.0, 1.0))

	assert_true(result.dead_heroes.is_empty())
	assert_almost_eq(result.hp_after[hero], expected_hp, ERROR_MARGIN)


func test_lost_wave_at_or_above_team_power_kills_from_full_hp() -> void:
	var hero := Hero.new("Cleric", 0)
	hero.def_id = &"cleric"
	hero.level = 10
	var team: Array[Hero] = [hero]
	var definition: HeroDefinition = preload("res://heroes/defs/cleric.tres")
	var balance: BalanceTable = preload("res://balance.tres")
	var definitions: Array[HeroDefinition] = [definition]
	var levels: Array[int] = [balance.level_caps[hero.rank]]
	var team_power := Hero.compute_team_power(team, definitions, levels, balance)
	var wave := Wave.new(990.0)

	assert_almost_eq(team_power, 187.0, ERROR_MARGIN)
	assert_almost_eq(wave.enemy_power * 0.2, 198.0, ERROR_MARGIN)
	seed(1)
	var result := QuickResolve.resolve(team, wave)

	assert_true(result.dead_heroes.has(hero))
	assert_false(result.survivors.has(hero))
	assert_almost_eq(result.hp_after[hero], 0.0, ERROR_MARGIN)


func test_graduated_loss_sequence_can_reach_retreat() -> void:
	var hero := _add_knight()
	var expedition := Expedition.new()
	var team: Array[Hero] = [hero]
	var verdant_outskirts: ZoneDefinition = preload("res://zones/defs/verdant_outskirts.tres")
	var thresholds: Array[float] = [
		90.0 / HERO_POWER,
		108.0 / HERO_POWER,
		126.0 / HERO_POWER,
		144.0 / HERO_POWER,
		162.0 / HERO_POWER,
	]
	_seed_for_rolls_above(thresholds[0], 5, thresholds, [false, true, true, true, false])

	var outcome := expedition.resolve(team, verdant_outskirts)

	assert_eq(outcome, Expedition.OUTCOME_RETREATED)
	assert_eq(expedition.waves_resolved, 5)
	assert_gt(expedition.current_hp[hero], 0.0)
	assert_lte(expedition.current_hp[hero] / HERO_MAX_HP, Expedition.RETREAT_THRESHOLD)
	assert_true(GameSession.roster.has(hero))


func test_team_size_scaling_keeps_loss_damage_in_parity() -> void:
	var solo_hero := Hero.new("Solo Knight", 0)
	solo_hero.def_id = &"knight"
	solo_hero.level = 10
	var solo_team: Array[Hero] = [solo_hero]
	var full_team: Array[Hero] = []
	for index: int in 5:
		var hero := Hero.new("Knight %d" % index, 0)
		hero.def_id = &"knight"
		hero.level = 10
		full_team.append(hero)
	var enemy_power := 990.0
	var r := 198.0 / HERO_POWER
	var balance: BalanceTable = preload("res://balance.tres")
	var expected_hp: float = HERO_MAX_HP * (
		1.0 - clamp(balance.wave_loss_damage_coefficient * r * r * r, 0.0, 1.0)
	)
	var loss_seed := _seed_for_rolls_above(r, 1, [r], [false])

	seed(loss_seed)
	var solo_result := QuickResolve.resolve(solo_team, Wave.new(enemy_power))
	seed(loss_seed)
	var full_result := QuickResolve.resolve(full_team, Wave.new(enemy_power))

	assert_true(solo_result.survivors.has(solo_hero))
	assert_almost_eq(solo_result.hp_after[solo_hero], expected_hp, ERROR_MARGIN)
	for hero: Hero in full_team:
		assert_true(full_result.survivors.has(hero))
		assert_almost_eq(solo_result.hp_after[solo_hero], full_result.hp_after[hero], ERROR_MARGIN)


func test_team_size_scaling_keeps_solo_and_full_team_rolls_in_parity() -> void:
	var solo_hero := Hero.new("Solo Knight", 0)
	solo_hero.def_id = &"knight"
	solo_hero.level = 10
	var solo_team: Array[Hero] = [solo_hero]
	var full_team: Array[Hero] = []
	for index: int in 5:
		var hero := Hero.new("Knight %d" % index, 0)
		hero.def_id = &"knight"
		hero.level = 10
		full_team.append(hero)
	var enemy_power := HERO_POWER * 2.5
	var balance: BalanceTable = preload("res://balance.tres")
	var r := 0.5
	var saw_win: bool = false
	var saw_loss: bool = false

	for rng_seed: int in range(1, 11):
		seed(rng_seed)
		var roll := randf()
		var expected_win := roll > 0.5
		seed(rng_seed)
		var solo_result := QuickResolve.resolve(solo_team, Wave.new(enemy_power))
		seed(rng_seed)
		var full_result := QuickResolve.resolve(full_team, Wave.new(enemy_power))
		var damage_coefficient: float = (
			balance.wave_damage_coefficient
			if expected_win
			else balance.wave_loss_damage_coefficient
		)
		var expected_hp := HERO_MAX_HP * (1.0 - damage_coefficient * r * r * r)

		assert_almost_eq(solo_result.hp_after[solo_hero], expected_hp, ERROR_MARGIN)
		for hero: Hero in full_team:
			assert_almost_eq(full_result.hp_after[hero], expected_hp, ERROR_MARGIN)
			assert_almost_eq(solo_result.hp_after[solo_hero], full_result.hp_after[hero], ERROR_MARGIN)
		saw_win = saw_win or expected_win
		saw_loss = saw_loss or not expected_win

	assert_true(saw_win)
	assert_true(saw_loss)


func test_hero_detail_reads_selected_hero_and_clears_on_multi_select() -> void:
	var balance: BalanceTable = preload("res://balance.tres")
	var hero := _add_knight()
	hero.level = 3
	hero.xp = 12
	var definition: HeroDefinition = Hero.definition_for(hero.def_id)
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var hero_detail: Label = hub.get_node("%HeroDetail") as Label

	assert_eq(hero_detail.text, "", "Nothing selected shows nothing.")

	roster_list.select(0)
	# select() does not emit; the [connection] block in hub.tscn is what drives the refresh.
	roster_list.multi_selected.emit(0, true)
	var before_stats := Hero.compute_final_stats(hero, definition, balance, Hero.level_for(hero, balance))
	var before_def: String = "DEF: %d" % roundi(before_stats[Hero.STAT_DEF])
	assert_string_contains(hero_detail.text, before_def)
	assert_string_contains(hero_detail.text, "Level: 3 (12/40 XP)")
	assert_string_contains(hero_detail.text, "Resonance: 0")
	assert_string_contains(hero_detail.text, "Traits: none")

	# roster_changed is the only refresh path equip, rank-up and sacrifice all go through.
	hero.resonance = 1
	hero.level = 10
	hero.xp = 0
	GameSession.roster_changed.emit()
	var after_stats := Hero.compute_final_stats(hero, definition, balance, Hero.level_for(hero, balance))
	assert_string_contains(hero_detail.text, "DEF: %d" % roundi(after_stats[Hero.STAT_DEF]))
	assert_string_contains(hero_detail.text, "Resonance: 1")
	assert_string_contains(hero_detail.text, "Bulwark")
	assert_string_contains(hero_detail.text, "Lv 10 (max)")
	assert_false(
		hero_detail.text.contains(before_def),
		"A resonance trait must move the displayed stat, not just the trait line.",
	)

	_add_knight("Knight 2")
	roster_list.select(0)
	roster_list.select(1, false)
	roster_list.multi_selected.emit(1, true)
	assert_eq(hero_detail.text, "", "Two heroes selected leaves no stale numbers.")


func test_hub_roster_rank_filter_hides_selection_and_expedition_refuses_it() -> void:
	var low_rank_hero: Hero = _add_knight("Low Rank")
	low_rank_hero.rank = 1
	var high_rank_hero: Hero = _add_knight("High Rank")
	high_rank_hero.rank = 3
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var roster_list: ItemList = hub.get_node("%RosterList") as ItemList
	var rank_filter: OptionButton = hub.get_node("%RosterRankFilter") as OptionButton
	var expedition_button: Button = hub.get_node("UI/Root/Bottom/Buttons/Expedition") as Button
	var status: Label = hub.get_node("%Status") as Label

	roster_list.select(0)
	rank_filter.select(4)
	rank_filter.item_selected.emit(4)
	assert_eq(roster_list.item_count, 1)
	assert_eq(roster_list.get_item_metadata(0), high_rank_hero)
	assert_eq(roster_list.get_selected_items(), PackedInt32Array())
	expedition_button.pressed.emit()
	assert_eq(status.text, "Select a hero first.")

	rank_filter.select(0)
	rank_filter.item_selected.emit(0)
	assert_eq(roster_list.item_count, 2)
	assert_eq(roster_list.get_item_metadata(0), low_rank_hero)
	assert_eq(roster_list.get_item_metadata(1), high_rank_hero)


func _add_knight(hero_name: String = "Knight") -> Hero:
	var hero := Hero.new(hero_name, 0)
	hero.def_id = &"knight"
	hero.level = 10
	GameSession.add_hero(hero)
	return hero


func _completed_xp_with_reward(xp_reward: int) -> int:
	GameSession.from_dict({"roster": []})
	GameSession.building_levels[2] = 5
	var hero := Hero.new("Reward Knight", 7)
	hero.def_id = &"knight"
	GameSession.add_hero(hero)
	var zone: ZoneDefinition = _make_zone(0, 1.0, 1)
	zone.xp_reward = xp_reward
	seed(1)
	assert_eq(Expedition.new().resolve([hero], zone), Expedition.OUTCOME_COMPLETED)
	return _earned_xp(hero)


func _earned_xp(hero: Hero) -> int:
	var total: int = hero.xp
	for level: int in hero.level:
		total += Hero.xp_to_next_level(level, preload("res://balance.tres"))
	return total


func _make_zone(recommended_power: int, fraction: float, trash_wave_count: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = &"test_zone"
	zone.recommended_power = recommended_power
	zone.trash_wave_count = trash_wave_count
	zone.trash_wave_start_fraction = fraction
	zone.trash_wave_end_fraction = fraction
	zone.boss_fraction = fraction
	return zone


func _seed_for_rolls_above(
	minimum_roll: float,
	wave_count: int,
	per_wave_minimum_rolls: Array[float] = [],
	per_wave_expected_wins: Array[bool] = [],
) -> int:
	assert(per_wave_minimum_rolls.is_empty() or per_wave_minimum_rolls.size() == wave_count)
	assert(per_wave_expected_wins.is_empty() or per_wave_expected_wins.size() == wave_count)
	for candidate: int in range(10000):
		seed(candidate)
		var matched: bool = true
		for wave_index: int in wave_count:
			var roll := randf()
			randi()
			var required_roll := minimum_roll
			if not per_wave_minimum_rolls.is_empty():
				required_roll = per_wave_minimum_rolls[wave_index]
			var expected_win := true
			if not per_wave_expected_wins.is_empty():
				expected_win = per_wave_expected_wins[wave_index]
			if (roll > required_roll) != expected_win:
				matched = false
		if matched:
			seed(candidate)
			return candidate
	fail_test("No deterministic seed produced the required win/loss sequence.")
	return -1
