extends GutTest

## ig-m6o.2.2.3: quirks. One habit per hero, rolled from the id like passions but with its own hash. The
## disk round trips are in test_save_service.gd, the panel in test_hub_controls.gd, the partner's
## lines in test_lines.gd and test_bonds.gd.

const IDS: Array[StringName] = [
	&"hums", &"counts_steps", &"collects_pebbles", &"names_weapon", &"early_riser", &"whittles", &"bad_puns",
	&"sweet_tooth", &"lucky_charm", &"hates_wet_boots", &"sketches", &"tidies", &"cloud_names", &"afraid_of_moths",
]


func test_the_fourteen_quirks_keep_their_order() -> void:
	assert_eq(Hero.QUIRKS.keys(), IDS)


func test_a_quirk_is_one_known_id_stable_per_instance_id() -> void:
	var hero := Hero.new("Born", 0)
	assert_eq(hero.quirks.size(), 1)
	assert_true(Hero.QUIRKS.has(hero.quirks[0]), str(hero.quirks))
	assert_eq(Hero.quirks_for(hero.instance_id), hero.quirks)
	assert_eq(Hero.quirks_for(hero.instance_id), Hero.quirks_for(hero.instance_id))


# Golden values: md5 must give the same quirk on every run and machine, or a legacy hero with no saved
# quirk would change it on each load.
func test_the_roll_is_the_same_on_every_run() -> void:
	assert_eq(Hero.quirks_for("0123456789abcdef0123456789abcdef"), [&"hates_wet_boots"] as Array[StringName])
	assert_eq(Hero.quirks_for("ffffffffffffffffffffffffffffffff"), [&"sketches"] as Array[StringName])


# Fixed ids, not Hero.new: the counts are the same on every run. About 71 of 1000 each.
func test_every_quirk_turns_up_over_a_thousand_ids() -> void:
	var counts: Dictionary = {}
	for quirk: StringName in Hero.QUIRKS:
		counts[quirk] = 0
	for index: int in 1000:
		counts[Hero.quirks_for("quirk-test:%d" % index)[0]] += 1
	for quirk: StringName in counts:
		assert_between(counts[quirk] as int, 36, 107, "%s share" % quirk)


# passions hash the id with String.hash(); a djb2 salt for the quirk would tie each quirk to a passion
# (7 of the 14 for each first passion). md5 does not.
func test_the_quirk_is_not_tied_to_the_first_passion() -> void:
	var seen: Dictionary = {}
	for index: int in 1000:
		var id: String = "quirk-test:%d" % index
		var first: StringName = Hero.passions_for(id)[0]
		if not seen.has(first):
			seen[first] = {}
		(seen[first] as Dictionary)[Hero.quirks_for(id)[0]] = true
	assert_eq(seen.size(), Hero.ALL_PROFESSIONS.size())
	for first: StringName in seen:
		assert_gte((seen[first] as Dictionary).size(), 12, "%s sees at least 12 of the 14 quirks" % first)


func test_a_new_hero_draws_nothing_from_the_global_rng() -> void:
	seed(4242)
	var expected: Array[int] = [randi(), randi(), randi()]
	seed(4242)
	for index: int in 10:
		Hero.quirks_for(Hero.new("Rolled", 0).instance_id)
	assert_eq([randi(), randi(), randi()] as Array[int], expected)


func test_a_quirk_survives_to_dict_and_back_even_through_json() -> void:
	var hero := Hero.new("Quirky", 0)
	# Not the rolled one, so a load that re-derived would show.
	hero.quirks = [&"hums" if hero.quirks[0] != &"hums" else &"tidies"]
	var data: Dictionary = hero.to_dict()
	assert_eq(data["quirks"], [str(hero.quirks[0])])
	assert_eq(Hero.from_dict(data).quirks, hero.quirks)
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(data))
	assert_eq(Hero.from_dict(through_json).quirks, hero.quirks)
	assert_push_warning_count(0)


func test_a_legacy_hero_with_no_quirks_key_derives_from_the_saved_id_and_keeps_it() -> void:
	var data: Dictionary = Hero.new("Old", 0).to_dict()
	data["instance_id"] = "0123456789abcdef0123456789abcdef"
	data.erase("quirks")
	var reloaded := Hero.from_dict(data)
	assert_eq(reloaded.quirks, [&"hates_wet_boots"] as Array[StringName], "from the saved id, not the one Hero.new drew")
	assert_eq(Hero.from_dict(data).quirks, reloaded.quirks, "the same on every load")
	assert_eq(reloaded.to_dict()["quirks"], ["hates_wet_boots"], "and the next save writes it")
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_an_invalid_quirks_key_warns_and_re_derives() -> void:
	var data: Dictionary = Hero.new("Odd", 0).to_dict()
	var loads: int = 0
	# Variant: a hand-edited or corrupt save can hold any type here.
	for bad: Variant in [[], ["hums", "sketches"], ["juggling"], [3], "hums", null]:
		data["quirks"] = bad
		assert_eq(Hero.from_dict(data).quirks, Hero.quirks_for(data["instance_id"]), str(bad))
		assert_push_warning("Invalid hero quirks")
		loads += 1
		# After the match above: a count assert marks warnings handled, so it goes second.
		assert_push_warning_count(loads, "exactly one warning for %s" % str(bad))


func test_every_quirk_has_its_three_lines_and_every_quirk_kind_is_a_quirk() -> void:
	for quirk: StringName in Hero.QUIRKS:
		assert_eq((Lines.BANK.get("quirk:%s" % quirk, []) as Array).size(), 3, str(quirk))
	for kind: String in Lines.BANK:
		if kind.begins_with("quirk:"):
			assert_true(Hero.QUIRKS.has(StringName(kind.trim_prefix("quirk:"))), "%s is a quirk" % kind)
