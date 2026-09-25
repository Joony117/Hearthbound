extends RefCounted
## Compare helpers the persistence tests share (ig-eek). Not a test_ file, so GUT never runs it.


## As SaveService writes it (ig-85w): full precision.
static func json_round_trip(profile: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(profile, "", true, true)) as Dictionary


## Where got first differs from want, or "". An int and a float compare by value, so a reload's 43.0 is
## 43 (JSON has no ints, so one past 2^53 could not survive the save anyway). Two floats must match to
## the last bit, -0.0 included; two ints exactly.
static func first_difference(got: Variant, want: Variant, path: String = "") -> String:
	if (got is int or got is float) and (want is int or want is float):
		var same: bool = float(got) == float(want)
		if got is float and want is float:
			same = PackedFloat64Array([got]).to_byte_array() == PackedFloat64Array([want]).to_byte_array()
		elif got is int and want is int:
			same = got == want
		return "" if same else "%s: %s, not %s" % [path, var_to_str(got), var_to_str(want)]
	if got is Dictionary and want is Dictionary:
		if (got as Dictionary).size() != (want as Dictionary).size():
			return "%s: keys %s, not %s" % [path, (got as Dictionary).keys(), (want as Dictionary).keys()]
		for key: Variant in want:
			if not (got as Dictionary).has(key):
				return "%s.%s: missing" % [path, key]
			var inner: String = first_difference(got[key], want[key], "%s.%s" % [path, key])
			if not inner.is_empty():
				return inner
		return ""
	if got is Array and want is Array:
		if (got as Array).size() != (want as Array).size():
			return "%s: %d items, not %d" % [path, (got as Array).size(), (want as Array).size()]
		for index: int in (want as Array).size():
			var inner: String = first_difference(got[index], want[index], "%s[%d]" % [path, index])
			if not inner.is_empty():
				return inner
		return ""
	return "" if typeof(got) == typeof(want) and got == want else "%s: %s, not %s" % [path, var_to_str(got), var_to_str(want)]


## Rows of [exact facts, float, float, ...]: the facts must match, the floats to 1e-6. The save writes
## full precision, but a reload lands within 1 ulp, not bit for bit (Godot's parser misrounds some
## 17-digit numbers, ig-85w).
static func mismatch(got: Array, want: Array) -> String:
	if got.size() != want.size():
		return "%d actors, not %d" % [got.size(), want.size()]
	for index: int in want.size():
		if got[index][0] != want[index][0]:
			return "%s, not %s" % [got[index][0], want[index][0]]
		for field: int in range(1, want[index].size()):
			if absf(float(got[index][field]) - float(want[index][field])) > 0.000001:
				return "%s field %d: %f, not %f" % [want[index][0], field, got[index][field], want[index][field]]
	return ""
