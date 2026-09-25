extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")
const AUTHORED_WEIGHTS: Array[int] = [4000, 2700, 1700, 1000, 450, 120, 28, 2]


func before_each() -> void:
	GameSession.from_dict({"roster": []})


func test_summon_hero_spends_stones_adds_hero_and_emits_once() -> void:
	var hero := Hero.new("Paid Hero", 0)
	watch_signals(GameSession)

	assert_true(GameSession.summon_hero(hero, BALANCE))
	assert_eq(GameSession.stones, 200)
	assert_eq(GameSession.roster.size(), 1)
	assert_same(GameSession.roster[0], hero)
	assert_signal_emit_count(GameSession, "roster_changed", 1)


func test_summon_hero_is_atomic_when_stones_are_short() -> void:
	GameSession.stones = 40
	var hero := Hero.new("Unpaid Hero", 0)
	watch_signals(GameSession)

	assert_false(GameSession.summon_hero(hero, BALANCE))
	assert_eq(GameSession.stones, 40)
	assert_true(GameSession.roster.is_empty())
	assert_signal_emit_count(GameSession, "roster_changed", 0)


func test_hub_shows_stones_disables_summon_and_names_shortfall() -> void:
	GameSession.stones = 40
	var hub_scene: PackedScene = load("res://hub/hub.tscn") as PackedScene
	assert_not_null(hub_scene)
	var hub: Node3D = hub_scene.instantiate() as Node3D
	add_child_autofree(hub)
	var summon_button: Button = hub.get_node("%Summon") as Button
	var stones_label: Label = hub.get_node("%Stones") as Label
	var status: Label = hub.get_node("%Status") as Label

	assert_true(summon_button.disabled)
	assert_eq(stones_label.text, "Summon Stones: 40")
	summon_button.pressed.emit()
	assert_eq(status.text, "Need 100 Summon Stones, have 40.")
	assert_eq(GameSession.stones, 40)
	assert_true(GameSession.roster.is_empty())

	GameSession.credit_stones(BALANCE.summon_pull_cost - GameSession.stones)
	assert_false(summon_button.disabled)
	assert_eq(stones_label.text, "Summon Stones: 100")
	summon_button.pressed.emit()
	assert_eq(GameSession.stones, 0)
	assert_eq(GameSession.roster.size(), 1)
	assert_true(summon_button.disabled)


func test_level_zero_preserves_authored_weights_and_ticket_results() -> void:
	var weights: Array[int] = Summon.weights_for_circle_level(0, BALANCE.summon_weights)
	assert_eq(weights, AUTHORED_WEIGHTS)

	var authored_total: int = _total_weight(AUTHORED_WEIGHTS)
	var computed_total: int = _total_weight(weights)
	var authored_counts: Array[int] = _empty_rank_counts()
	var computed_counts: Array[int] = _empty_rank_counts()
	seed(12_345)
	for _sample: int in 5_000:
		var ticket: int = randi() % authored_total
		var authored_rank: int = Summon.rank_for_ticket(ticket, AUTHORED_WEIGHTS, authored_total)
		var computed_rank: int = Summon.rank_for_ticket(ticket, weights, computed_total)
		authored_counts[authored_rank] += 1
		computed_counts[computed_rank] += 1
	assert_eq(computed_counts, authored_counts)


func test_cap_shifts_mass_to_high_ranks_and_preserves_block_proportions() -> void:
	var level_zero_weights: Array[int] = Summon.weights_for_circle_level(0, BALANCE.summon_weights)
	var cap_weights: Array[int] = Summon.weights_for_circle_level(
		BALANCE.summoning_circle_level_cap,
		BALANCE.summon_weights,
	)
	assert_gt(_block_proportion(cap_weights, 4), _block_proportion(level_zero_weights, 4))
	for weight: int in cap_weights:
		assert_gt(weight, 0)

	var multiplier: float = 1.0 + BALANCE.summoning_circle_multiplier_per_level * float(BALANCE.summoning_circle_level_cap)
	var denominator: float = 9400.0 + multiplier * 600.0
	_assert_block_is_proportional(cap_weights, 0, 4, 1.0, denominator)
	_assert_block_is_proportional(cap_weights, 4, 8, multiplier, denominator)


func test_every_class_ticket_gives_casters_one_in_a_hundred() -> void:
	var weights: Array[int] = BALANCE.summon_archetype_weights
	assert_eq(weights.size(), Summon.ARCHETYPE_DEF_IDS.size(), "one weight per archetype, in order")
	var total: int = _total_weight(weights)
	assert_eq(total, 300)
	var counts: Dictionary = {}
	for ticket: int in total:
		var def_id: String = Summon.ARCHETYPE_DEF_IDS[Summon.rank_for_ticket(ticket, weights, total)]
		counts[def_id] = int(counts.get(def_id, 0)) + 1
	assert_eq(counts, {"knight": 98, "rogue": 98, "ranger": 98, "mage": 3, "cleric": 3})


func test_roll_never_mutates_authored_weights() -> void:
	Summon.roll()
	Summon.roll(BALANCE.summoning_circle_level_cap)
	Summon.roll(BALANCE.summoning_circle_level_cap)
	assert_eq(BALANCE.summon_weights, AUTHORED_WEIGHTS)


func _total_weight(weights: Array[int]) -> int:
	var total: int = 0
	for weight: int in weights:
		total += weight
	return total


func _empty_rank_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(AUTHORED_WEIGHTS.size())
	counts.fill(0)
	return counts


func _block_proportion(weights: Array[int], start_index: int) -> float:
	var block_total: int = 0
	for rank: int in range(start_index, weights.size()):
		block_total += weights[rank]
	return float(block_total) / float(_total_weight(weights))


func _assert_block_is_proportional(
	weights: Array[int],
	start_index: int,
	end_index: int,
	multiplier: float,
	denominator: float,
) -> void:
	for rank: int in range(start_index, end_index):
		var expected_weight: float = float(AUTHORED_WEIGHTS[rank]) * multiplier * 10000.0 / denominator
		assert_almost_eq(float(weights[rank]), expected_weight, 0.5001)
