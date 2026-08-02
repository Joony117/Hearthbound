extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var balance: BalanceTable = load("res://balance.tres") as BalanceTable
	if balance == null:
		quit(_fail("balance resource load", "BalanceTable", "null"))
		return
	var exit_code: int = _check_values(balance)
	if exit_code == 0:
		print("PASS: balance table representative values match SYSTEMS.md.")
	quit(exit_code)


func _check_values(balance: BalanceTable) -> int:
	if balance.stat_multipliers[7] != 8.17:
		return _fail("SSS stat multiplier", "8.17", str(balance.stat_multipliers[7]))
	if balance.essence_bases[0] != 10:
		return _fail("F essence base", "10", str(balance.essence_bases[0]))
	if balance.essence_bases[7] != 6500:
		return _fail("SSS essence base", "6500", str(balance.essence_bases[7]))
	if balance.rank_up_essence_costs[6] != 16000:
		return _fail("SS to SSS essence cost", "16000", str(balance.rank_up_essence_costs[6]))
	if balance.summon_weights[7] != 2:
		return _fail("SSS summon weight", "2", str(balance.summon_weights[7]))
	return 0


func _fail(check_name: String, expected: String, actual: String) -> int:
	print("FAIL: %s | expected: %s | actual: %s" % [check_name, expected, actual])
	return 1
