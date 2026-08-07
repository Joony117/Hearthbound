extends GutTest

const BALANCE: BalanceTable = preload("res://balance.tres")
const AUTHORED_WEIGHTS: Array[int] = [4000, 2700, 1700, 1000, 450, 120, 28, 2]


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
