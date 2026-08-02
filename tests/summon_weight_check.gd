extends SceneTree

const EXPECTED_WEIGHTS: Array[int] = [4000, 2700, 1700, 1000, 450, 120, 28, 2]
const EXPECTED_TOTAL: int = 10000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var counts: Array[int] = []
	counts.resize(EXPECTED_WEIGHTS.size())
	counts.fill(0)
	for ticket: int in EXPECTED_TOTAL:
		var rank: int = Summon.rank_for_ticket(ticket, EXPECTED_WEIGHTS, EXPECTED_TOTAL)
		if rank < 0 or rank >= counts.size():
			quit(_fail("ticket mapping", "rank in range", str(rank)))
			return
		counts[rank] += 1

	for rank: int in EXPECTED_WEIGHTS.size():
		if counts[rank] != EXPECTED_WEIGHTS[rank]:
			quit(_fail("rank %d ticket count" % rank, str(EXPECTED_WEIGHTS[rank]), str(counts[rank])))
			return
	if Summon.rank_for_ticket(EXPECTED_TOTAL, EXPECTED_WEIGHTS, EXPECTED_TOTAL) != -1:
		quit(_fail("out-of-range ticket failure", "-1", "resolved rank"))
		return
	if Summon.rank_for_ticket(0, EXPECTED_WEIGHTS, EXPECTED_TOTAL - 1) != -1:
		quit(_fail("inconsistent weight total failure", "-1", "resolved rank"))
		return
	print("PASS: every summon ticket maps to its authored rank weight, and invalid mappings fail loudly.")
	quit(0)


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
