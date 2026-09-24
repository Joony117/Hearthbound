extends GutTest

const BALANCE_PATH: String = "res://balance.tres"


# Godot drops a .tres row whose property no longer exists on the script, without an error, and the
# script's default takes its place. A rename done in balance_table.gd alone would ship that way.
func test_every_row_in_balance_tres_is_a_balance_table_property() -> void:
	var names: Dictionary = {}
	for property: Dictionary in (load(BALANCE_PATH) as BalanceTable).get_property_list():
		names[property["name"]] = true
	var in_resource: bool = false
	var rows: int = 0
	for line: String in FileAccess.get_file_as_string(BALANCE_PATH).split("\n"):
		if line.begins_with("["):
			in_resource = line.begins_with("[resource")
			continue
		if not in_resource or not " = " in line:
			continue
		var key: String = line.get_slice(" = ", 0).strip_edges()
		rows += 1
		assert_true(names.has(key), "balance.tres row '%s' has no BalanceTable property" % key)
	assert_gt(rows, 50, "the rows were read")
