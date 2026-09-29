extends GutTest
## ig-c9y.1: the gore setting, the body type, the hit event's cues, the spray a hit throws, and the proof
## that none of it touches a battle (the view draws it; the sim never sees it).

const ZONE_PATH: String = "res://zones/defs/verdant_outskirts.tres"
const BATTLE_STEPS: int = 300

var _had_key: bool = false
var _kept: Variant


func before_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	_had_key = config.has_section_key(Settings.SECTION, Settings.GORE_KEY)
	_kept = config.get_value(Settings.SECTION, Settings.GORE_KEY) if _had_key else null


func after_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	if _had_key:
		config.set_value(Settings.SECTION, Settings.GORE_KEY, _kept)
	elif config.has_section_key(Settings.SECTION, Settings.GORE_KEY):
		config.erase_section_key(Settings.SECTION, Settings.GORE_KEY)
	config.save(Settings.SETTINGS_PATH)
	Settings._config = null


# --- 1. Settings ---------------------------------------------------------------------------------

func test_each_gore_level_round_trips_through_disk() -> void:
	for level: String in ["off", "low", "full"]:
		Settings.set_gore(level)
		Settings._config = null
		assert_eq(Settings.gore(), level)


func test_a_missing_or_bad_gore_value_reads_full() -> void:
	if Settings._loaded_config().has_section_key(Settings.SECTION, Settings.GORE_KEY):
		Settings._loaded_config().erase_section_key(Settings.SECTION, Settings.GORE_KEY)
	assert_eq(Settings.gore(), "full", "a missing key")
	for bad: Variant in ["extreme", 2, "", "Off", true]:
		Settings._loaded_config().set_value(Settings.SECTION, Settings.GORE_KEY, bad)
		assert_eq(Settings.gore(), "full", "bad value %s" % str(bad))


func test_the_picker_lists_off_low_full_and_ticks_the_stored_one() -> void:
	Settings.set_gore("low")
	Settings._config = null
	var picker: OptionButton = _menu_picker()
	assert_eq(picker.item_count, 3)
	for index: int in 3:
		assert_eq(picker.get_item_metadata(index), ["off", "low", "full"][index])
	assert_eq(picker.get_item_metadata(picker.selected), "low")
	assert_eq(picker.get_item_text(picker.selected), "Low")


func test_opening_the_menu_with_a_bad_value_ticks_full_and_writes_nothing_back() -> void:
	Settings._loaded_config().set_value(Settings.SECTION, Settings.GORE_KEY, "extreme")
	Settings._loaded_config().save(Settings.SETTINGS_PATH)
	Settings._config = null
	var picker: OptionButton = _menu_picker()
	assert_eq(picker.get_item_metadata(picker.selected), "full")
	var fresh := ConfigFile.new()
	assert_eq(fresh.load(Settings.SETTINGS_PATH), OK)
	assert_eq(fresh.get_value(Settings.SECTION, Settings.GORE_KEY), "extreme", "the file is untouched")


func test_picking_an_item_saves_its_level() -> void:
	var picker: OptionButton = _menu_picker()
	for index: int in [0, 1, 2, 0]:
		picker.select(index)
		picker.item_selected.emit(index)
		Settings._config = null
		assert_eq(Settings.gore(), picker.get_item_metadata(index), "item %d" % index)


# --- 2. Body type --------------------------------------------------------------------------------

func test_every_enemy_look_is_bones_and_every_ally_look_is_flesh() -> void:
	for archetype: String in HeroModel.ENEMY_LOOKS:
		assert_eq(HeroModel.body_type("enemy", archetype), "bones", "enemy %s" % archetype)
	for archetype: String in HeroModel.ALLY_LOOKS:
		assert_eq(HeroModel.body_type("ally", archetype), "flesh", "ally %s" % archetype)
	assert_eq(HeroModel.body_type("enemy", "no_such_archetype"), "bones", "an unknown enemy is drawn as the skeleton knight")
	assert_eq(HeroModel.body_type("ally", "no_such_archetype"), "flesh", "an unknown ally is drawn as the knight")


# --- 3. The hit event's cues ---------------------------------------------------------------------

func test_the_hit_direction_is_the_normalized_hit_from() -> void:
	var event: Dictionary = _hit_event({"last_hit_tick": 4, "hit_from": [3.0, 4.0]}, {"hp": 90.0})
	assert_almost_eq(event["direction"] as Vector3, Vector3(0.6, 0.0, 0.8), Vector3.ONE * 0.00001)


func test_a_hit_with_no_hit_from_flies_backward_from_the_facing() -> void:
	var event: Dictionary = _hit_event({"last_hit_tick": 4}, {"hp": 90.0, "facing": [1.0, 0.0]})
	assert_almost_eq(event["direction"] as Vector3, Vector3(-1.0, 0.0, 0.0), Vector3.ONE * 0.00001)


func test_a_hit_is_heavy_from_a_quarter_of_max_hp() -> void:
	assert_true(_hit_event({"last_hit_tick": 4}, {"hp": 75.0})["heavy"], "100 to 75")
	assert_false(_hit_event({"last_hit_tick": 4}, {"hp": 76.0})["heavy"], "100 to 76")


func test_the_hit_names_its_body() -> void:
	assert_eq(_hit_event({"last_hit_tick": 4}, {"hp": 90.0}, "enemy")["body"], "bones")
	assert_eq(_hit_event({"last_hit_tick": 4}, {"hp": 90.0}, "ally")["body"], "flesh")


# --- 4. Spawn ------------------------------------------------------------------------------------

func test_gore_off_spawns_exactly_what_an_event_without_the_cues_spawns() -> void:
	Settings.set_gore("off")
	for critical: bool in [false, true]:
		for body: String in ["bones", "flesh"]:
			var plain: Dictionary = _spawn_event(body, 12, critical)
			plain.erase("body")
			plain.erase("direction")
			plain.erase("heavy")
			var with_cues: Dictionary = _spawn_event(body, 12, critical)
			with_cues["heavy"] = true
			assert_eq(_signature(_spawn(with_cues)), _signature(_spawn(plain)), "%s crit %s" % [body, critical])


func test_full_bones_throws_dust_and_splinters_along_the_direction() -> void:
	Settings.set_gore("full")
	var event: Dictionary = _spawn_event("bones", 12)
	var effect: Node = _spawn(event)
	var gore: Array[CPUParticles3D] = _gore(effect)
	assert_eq(gore.size(), 2)
	assert_eq(gore[0].amount, BattleVfx.GORE_DUST_COUNT)
	assert_eq(gore[1].amount, BattleVfx.GORE_SPLINTER_COUNT)
	assert_eq([gore[0].amount, gore[1].amount], [12, 4])
	for particles: CPUParticles3D in gore:
		assert_eq(particles.color, BattleVfx.BONE_COLOR)
		assert_eq(particles.direction, event["direction"])
		assert_eq(particles.spread, BattleVfx.GORE_SPREAD)
		assert_eq(particles.lifetime, BattleVfx.GORE_SECONDS)
	assert_same(gore[1].mesh, BattleVfx._splinter)
	assert_true(gore[0].mesh is BoxMesh, "the dust is the shared box speck")


func test_full_flesh_throws_one_blood_spray() -> void:
	Settings.set_gore("full")
	var event: Dictionary = _spawn_event("flesh", 12)
	var gore: Array[CPUParticles3D] = _gore(_spawn(event))
	assert_eq(gore.size(), 1)
	assert_eq(gore[0].color, BattleVfx.BLOOD_COLOR)
	assert_eq(gore[0].amount, 14)
	assert_same(gore[0].mesh, BattleVfx._droplet)
	assert_eq(gore[0].direction, event["direction"])
	assert_eq(gore[0].spread, BattleVfx.GORE_SPREAD)
	assert_eq(gore[0].lifetime, BattleVfx.GORE_SECONDS)


func test_a_hit_with_no_damage_throws_nothing() -> void:
	Settings.set_gore("full")
	for body: String in ["bones", "flesh"]:
		var bare: Dictionary = _spawn_event(body, 0)
		var plain: Dictionary = bare.duplicate()
		plain.erase("body")
		var effect: Node = _spawn(bare)
		assert_eq(_gore(effect).size(), 0, body)
		assert_eq(_signature(effect), _signature(_spawn(plain)), body)


func test_low_halves_and_crit_or_heavy_doubles_the_counts() -> void:
	var cases: Array[Array] = [
		# [level, critical, heavy, bones dust, bones splinters, blood]
		["full", false, false, 12, 4, 14],
		["low", false, false, 6, 2, 7],
		["full", true, false, 24, 8, 28],
		["full", false, true, 24, 8, 28],
		["full", true, true, 24, 8, 28],
		["low", true, false, 12, 4, 14],
		["low", false, true, 12, 4, 14],
	]
	for row: Array in cases:
		Settings.set_gore(row[0])
		var bones: Dictionary = _spawn_event("bones", 12, row[1])
		bones["heavy"] = row[2]
		var bone_gore: Array[CPUParticles3D] = _gore(_spawn(bones))
		assert_eq([bone_gore[0].amount, bone_gore[1].amount], [row[3], row[4]], "bones %s" % [row])
		var flesh: Dictionary = _spawn_event("flesh", 12, row[1])
		flesh["heavy"] = row[2]
		assert_eq(_gore(_spawn(flesh))[0].amount, row[5], "flesh %s" % [row])


func test_a_zero_direction_falls_back_to_up() -> void:
	Settings.set_gore("full")
	for body: String in ["bones", "flesh"]:
		var event: Dictionary = _spawn_event(body, 12)
		event["direction"] = Vector3.ZERO
		for particles: CPUParticles3D in _gore(_spawn(event)):
			assert_eq(particles.direction, Vector3.UP, body)


func test_a_spawn_adds_one_child_to_the_vfx() -> void:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	for level: String in ["off", "low", "full"]:
		Settings.set_gore(level)
		for body: String in ["bones", "flesh"]:
			var before: int = vfx.get_child_count()
			vfx.spawn(_spawn_event(body, 12, true))
			assert_eq(vfx.get_child_count(), before + 1, "%s %s" % [level, body])


func test_the_spray_ends_before_the_shortest_damage_effect_is_reaped() -> void:
	assert_lt(BattleVfx.GORE_SECONDS, 0.7)


func test_the_shared_meshes_use_the_shared_speck_material() -> void:
	assert_not_null(BattleVfx._speck_material)
	assert_same(BattleVfx._splinter.material, BattleVfx._speck_material)
	assert_same(BattleVfx._droplet.material, BattleVfx._speck_material)


func test_the_vfx_never_touches_the_global_random_seed() -> void:
	var source: String = FileAccess.get_file_as_string("res://combat/battle/battle_vfx.gd")
	assert_false(source.is_empty(), "the source was read")
	assert_false("seed(" in source)
	assert_false("randomize(" in source)


# --- 5. Gore does not change a battle ------------------------------------------------------------

func test_gore_leaves_a_seeded_battle_exactly_as_it_was() -> void:
	var team: Array[Hero] = []
	for def_id: StringName in [&"knight", &"ranger", &"mage", &"rogue"]:
		var hero := Hero.new(String(def_id), 0)
		hero.def_id = def_id
		team.append(hero)
	var zone: ZoneDefinition = load(ZONE_PATH) as ZoneDefinition
	assert_not_null(zone)
	var first: BattleView = _practice_view(team, zone)
	var start: Dictionary = first._practice_state.to_dict()
	first.free()

	var runs: Dictionary = {}
	for label: String in ["off", "off again", "full"]:
		runs[label] = await _play(team, zone, start, "full" if label == "full" else "off")
	assert_false(runs["off"]["gore"], "no gore is seen with it off")
	assert_false(runs["off again"]["gore"], "no gore is seen with it off")
	assert_true(runs["full"]["gore"], "the full run really threw gore")
	assert_true(runs["off"]["state"] == runs["off again"]["state"], "the control: two off runs agree")
	assert_true(runs["off"]["state"] == runs["full"]["state"], "the final state is the same with gore on")
	assert_true(runs["off"]["outcome"] == runs["full"]["outcome"], "the outcome is the same with gore on")
	assert_true(runs["off"]["state"] != start_json(start), "the battle really moved")


# --- 6a. Cost ------------------------------------------------------------------------------------

## Not a gate (CODING_RULES § Performance): 30 skeleton hits, all crits, in one diff.
func test_cost_of_a_worst_burst_of_crits_on_skeletons() -> void:
	var previous: Dictionary = {}
	var actors: Array = []
	for index: int in 30:
		var id: String = "e%d" % index
		var position: Array = [float(index % 6), float(index / 6)]
		previous[id] = _actor(id, "enemy", "knight", {"last_crit_tick": 0}, {"position": position})
		actors.append(_actor(id, "enemy", "knight", {"last_hit_tick": 4, "last_crit_tick": 4}, {"hp": 70.0, "position": position}))
	var best: Dictionary = {}
	var worst: Dictionary = {}
	for level: String in ["off", "full"]:
		Settings.set_gore(level)
		var runs: Array[int] = []
		for _run: int in 7:
			var vfx := BattleVfx.new()
			add_child(vfx)
			var started: int = Time.get_ticks_usec()
			var events: Array[Dictionary] = BattleVfx.events_between(previous, actors)
			for event: Dictionary in events:
				vfx.spawn(event)
			runs.append(Time.get_ticks_usec() - started)
			assert_eq(events.size(), 30)
			assert_eq(vfx.get_child_count(), 30)
			vfx.free()
		best[level] = runs.min() / 1000.0
		worst[level] = runs.max() / 1000.0
	gut.p("GORE WORST BURST: 30 crit hits, off best %.3f worst %.3f ms; full best %.3f worst %.3f ms of 7" % [best["off"], worst["off"], best["full"], worst["full"]])


# --- helpers -------------------------------------------------------------------------------------

func _menu_picker() -> OptionButton:
	var pause_menu: CanvasLayer = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child_autofree(pause_menu)
	return pause_menu.get_node("%Gore") as OptionButton


func _practice_view(team: Array[Hero], zone: ZoneDefinition) -> BattleView:
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child(view)
	# Only this test's calls advance it.
	view.set_process(false)
	view.configure_practice(team, zone)
	return view


## One 30-second practice battle from the same start, a frame between steps so the particles run as in play.
func _play(team: Array[Hero], zone: ZoneDefinition, start: Dictionary, level: String) -> Dictionary:
	Settings.set_gore(level)
	var view: BattleView = _practice_view(team, zone)
	view._practice_state = BattleState.from_dict(start.duplicate(true))
	var saw_gore: bool = false
	for _step: int in BATTLE_STEPS:
		view._process(0.1)
		await get_tree().process_frame
		if not saw_gore:
			saw_gore = _has_gore(view)
	var result: Dictionary = {
		"state": JSON.stringify(view._practice_state.to_dict(), "", true),
		"outcome": JSON.stringify(BattleSimulation.snapshot_outcome(view._practice_state).to_dict(), "", true),
		"gore": saw_gore,
	}
	view.queue_free()
	await get_tree().process_frame
	return result


func start_json(start: Dictionary) -> String:
	return JSON.stringify(start, "", true)


func _has_gore(view: Node) -> bool:
	for node: Node in view.find_children("*", "CPUParticles3D", true, false):
		var color: Color = (node as CPUParticles3D).color
		if color == BattleVfx.BONE_COLOR or color == BattleVfx.BLOOD_COLOR:
			return true
	return false


func _hit_event(effects: Dictionary, fields: Dictionary, faction: String = "enemy") -> Dictionary:
	var before: Dictionary = _actor("t1", faction, "knight")
	var after: Dictionary = _actor("t1", faction, "knight", effects, fields)
	return _first(BattleVfx.events_between({"t1": before}, [after]), "hit")


## A hit event as events_between builds it, with the cues (direction is the flat +z the spray is thrown along).
func _spawn_event(body: String, damage: int, critical: bool = false) -> Dictionary:
	return {"kind": "hit", "faction": "enemy" if body == "bones" else "ally", "position": Vector3(1.0, 0.0, 2.0),
		"damage": damage, "critical": critical, "body": body, "direction": Vector3(0.0, 0.0, 1.0), "heavy": false}


## Spawns into a fresh vfx and returns the effect node it added, the one child.
func _spawn(event: Dictionary) -> Node:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	vfx.spawn(event)
	assert_eq(vfx.get_child_count(), 1, "one new child per spawn")
	return vfx.get_child(0)


func _gore(effect: Node) -> Array[CPUParticles3D]:
	var found: Array[CPUParticles3D] = []
	for child: Node in effect.get_children():
		if child is CPUParticles3D and ((child as CPUParticles3D).color == BattleVfx.BONE_COLOR or (child as CPUParticles3D).color == BattleVfx.BLOOD_COLOR):
			found.append(child as CPUParticles3D)
	return found


## Class of each child of the effect, in order.
func _signature(effect: Node) -> Array:
	return effect.get_children().map(func(child: Node) -> String: return child.get_class())


func _actor(id: String, faction: String, archetype: String, effects: Dictionary = {}, fields: Dictionary = {}) -> Dictionary:
	var effect_state: Dictionary = {"last_hit_tick": 1, "last_skill_tick": 1, "attack_target_id": "", "telegraph_kind": "", "stun_remaining": 0.0}
	effect_state.merge(effects, true)
	var actor: Dictionary = {"id": id, "faction": faction, "archetype": archetype, "life": "alive", "hp": 100.0, "max_hp": 100.0, "attack_cooldown": 0.0, "position": [0.0, 0.0], "facing": [1.0, 0.0], "effect_state": effect_state}
	actor.merge(fields, true)
	return actor


func _first(events: Array[Dictionary], kind: String) -> Dictionary:
	for event: Dictionary in events:
		if event["kind"] == kind:
			return event
	fail_test("no %s event in %s" % [kind, events])
	return {}
