extends GutTest
## ig-c9y.7: the ground blood: the fall event, the pool it lays, its cap and fade, that nothing of it carries
## over a reset or is saved, and the proof that none of it touches a battle (the view draws it; the sim never
## sees it).

const ZONE_PATH: String = "res://zones/defs/verdant_outskirts.tres"
const BATTLE_STEPS: int = 300
# The seeded fight: this hero starts nearly dead, so the fight really downs someone.
const WEAK_ARCHETYPE: String = "knight"
const WEAK_HP: float = 1.0

var _had_key: bool = false
# Variant: the gore key's saved value as the settings file held it, whatever its type (even a malformed one), so
# after_each puts back exactly what was there.
var _kept: Variant


## The one thing configure_live asks of its controller here: a snapshot to draw.
class LiveStub extends Node:
	@warning_ignore("unused_signal")
	signal battle_changed(order_id: String)

	var snapshot: Dictionary = {}


	func get_battle_snapshot(_order_id: String) -> Dictionary:
		return snapshot.duplicate(true)


func before_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	_had_key = config.has_section_key(Settings.SECTION, Settings.GORE_KEY)
	_kept = config.get_value(Settings.SECTION, Settings.GORE_KEY) if _had_key else null
	Settings.set_gore("full")


func after_each() -> void:
	var config: ConfigFile = Settings._loaded_config()
	if _had_key:
		config.set_value(Settings.SECTION, Settings.GORE_KEY, _kept)
	elif config.has_section_key(Settings.SECTION, Settings.GORE_KEY):
		config.erase_section_key(Settings.SECTION, Settings.GORE_KEY)
	config.save(Settings.SETTINGS_PATH)
	Settings._config = null


# --- 1. The event --------------------------------------------------------------------------------

func test_an_ally_going_down_or_dying_falls_once_with_its_body_place_and_tick() -> void:
	for life: String in ["downed", "dead"]:
		var before: Dictionary = _actor("a1", "ally", "knight")
		var after: Dictionary = _actor("a1", "ally", "knight", {"last_hit_tick": 7}, {"hp": 0.0, "life": life, "position": [3.0, 4.0]})
		var events: Array[Dictionary] = BattleVfx.events_between({"a1": before}, [after])
		assert_eq(_kinds(events).count("fall"), 1, "%s: exactly one fall" % life)
		var fall: Dictionary = _first(events, "fall")
		assert_eq(fall["body"], "flesh")
		assert_eq(fall["actor_id"], "a1")
		assert_eq(fall["position"], Vector3(3.0, 0.0, 4.0), "the after position")
		assert_eq(fall["tick"], 7, "it plays with the hit that felled it")


func test_a_fall_with_no_hit_still_falls_and_plays_at_the_render() -> void:
	var after: Dictionary = _actor("a1", "ally", "mage", {}, {"hp": 0.0, "life": "downed"})
	var events: Array[Dictionary] = BattleVfx.events_between({"a1": _actor("a1", "ally", "mage")}, [after])
	assert_eq(_kinds(events), ["fall"])
	assert_eq(events[0]["tick"], 1, "the last hit tick the snapshot already carried plays at once")


func test_nothing_else_falls() -> void:
	var alive: Dictionary = _actor("a1", "ally", "knight")
	var downed: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 0.0, "life": "downed"})
	var dead: Dictionary = _actor("a1", "ally", "knight", {}, {"hp": 0.0, "life": "dead"})
	assert_eq(BattleVfx.events_between({"a1": downed}, [dead]).size(), 0, "downed to dead: the pool is already there")
	assert_eq(BattleVfx.events_between({"a1": downed}, [downed]).size(), 0, "downed to downed")
	assert_eq(BattleVfx.events_between({"a1": downed}, [alive]).size(), 0, "a revive")
	assert_eq(BattleVfx.events_between({"a1": alive}, [alive]).size(), 0, "alive to alive")
	assert_eq(BattleVfx.events_between({}, [downed]).size(), 0, "no previous entry: a first render or a rebuilt view")
	assert_eq(BattleVfx.events_between({"a1": alive}, [downed]).size(), 1, "the control: the one fall")


func test_a_skeleton_dying_stays_a_hit_and_a_death_with_no_fall() -> void:
	var before: Dictionary = _actor("e1", "enemy", "knight", {}, {"hp": 5.0})
	var after: Dictionary = _actor("e1", "enemy", "knight", {"last_hit_tick": 8}, {"hp": 0.0, "life": "dead"})
	assert_eq(_kinds(BattleVfx.events_between({"e1": before}, [after])), ["hit", "death"])


# --- 2. The pool ---------------------------------------------------------------------------------

func test_a_flesh_fall_at_full_lays_one_pool_at_its_place_in_the_pools_container() -> void:
	var vfx: BattleVfx = _vfx()
	vfx.spawn(_fall(Vector3(2.0, 0.0, -3.0)))
	var pools: Node = vfx.get_node_or_null("Pools")
	assert_not_null(pools, "the container is made on the first pool")
	assert_eq(pools.get_child_count(), 1)
	assert_eq(vfx.get_child_count(), 1, "the container is the vfx's one child")
	var pool: MeshInstance3D = pools.get_child(0) as MeshInstance3D
	assert_eq(pool.position.x, 2.0)
	assert_eq(pool.position.z, -3.0)
	assert_almost_eq(pool.position.y, BattleVfx.POOL_HEIGHT, 0.0001, "on the ground, under the crit ring's 0.08")
	assert_eq(pool.material_override, BattleVfx._effect_material, "the shared effect material")
	assert_eq((pool.get_instance_shader_parameter(&"tint") as Color).r, BattleVfx.BLOOD_COLOR.r, "blood red")


func test_a_pool_grows_then_stays_its_size() -> void:
	var vfx: BattleVfx = _vfx()
	vfx.spawn(_fall(Vector3.ZERO))
	var pool: MeshInstance3D = _pools(vfx).get_child(0) as MeshInstance3D
	assert_almost_eq(pool.scale.x, BattleVfx.POOL_START_SCALE, 0.001, "it starts small")
	vfx.set_time_scale(20.0)
	await wait_seconds(BattleVfx.POOL_GROW_SECONDS / 20.0 + 0.5)
	assert_eq(pool.scale, Vector3.ONE, "grown, and held (this pool's hold is far longer than the wait)")


func test_a_bones_fall_lays_none() -> void:
	var vfx: BattleVfx = _vfx()
	var event: Dictionary = _fall(Vector3.ZERO)
	event["body"] = "bones"
	vfx.spawn(event)
	assert_eq(vfx.get_child_count(), 0)
	event.erase("body")
	vfx.spawn(event)
	assert_eq(vfx.get_child_count(), 0, "an event that names no body")


func test_gore_off_lays_none_and_adds_no_child_at_all() -> void:
	Settings.set_gore("off")
	var vfx: BattleVfx = _vfx()
	vfx.spawn(_fall(Vector3.ZERO))
	assert_eq(vfx.get_child_count(), 0)
	assert_null(vfx.get_node_or_null("Pools"))
	assert_eq(vfx._pools_live.size(), 0)


func test_a_pool_takes_no_effect_slot_and_effects_take_no_pool_slot() -> void:
	var vfx: BattleVfx = _vfx()
	for _index: int in BattleVfx.MAX_LIVE_EFFECTS:
		vfx.spawn({"kind": "landing", "position": Vector3.ZERO})
	assert_eq(vfx.get_child_count(), BattleVfx.MAX_LIVE_EFFECTS, "40 one-shots live")
	vfx.spawn(_fall(Vector3.ONE))
	assert_eq(_pool_count(vfx), 1, "a fall still lays its pool")
	vfx.spawn({"kind": "landing", "position": Vector3.ZERO})
	assert_eq(vfx.get_child_count(), BattleVfx.MAX_LIVE_EFFECTS + 1, "the cap still holds at 40 effects, the container not counted")

	var other: BattleVfx = _vfx()
	other.spawn(_fall(Vector3.ZERO))
	other.spawn({"kind": "hit", "position": Vector3.ZERO, "damage": 5, "body": "flesh", "faction": "ally"})
	assert_eq(other.get_child_count(), 2, "with a pool live, a hit still spawns")
	for _index: int in BattleVfx.MAX_LIVE_EFFECTS:
		other.spawn({"kind": "landing", "position": Vector3.ZERO})
	assert_eq(other.get_child_count(), BattleVfx.MAX_LIVE_EFFECTS + 1)


func test_the_pool_uses_no_random_number() -> void:
	var source: String = FileAccess.get_file_as_string("res://combat/battle/battle_vfx.gd")
	var start: int = source.find("func _pool(")
	var finish: int = source.find("func clear_pools(")
	assert_gt(start, 0)
	assert_gt(finish, start)
	var body: String = source.substr(start, finish - start)
	assert_false("rand" in body, "the pool draws nothing at random")


# --- 3. The cap and the fade ---------------------------------------------------------------------

func test_past_the_full_cap_the_oldest_pool_fades_early_and_frees() -> void:
	var vfx: BattleVfx = _vfx()
	var cap: int = BattleVfx.POOL_CAP_FULL
	for index: int in cap + 1:
		vfx.spawn(_fall(Vector3(float(index), 0.0, 0.0)))
		assert_lte(vfx._pools_live.size(), cap, "never more than the cap not fading")
	var pools: Node = _pools(vfx)
	var oldest: Node = pools.get_child(0)
	assert_eq(oldest.position.x, 0.0, "the first one laid")
	assert_false(oldest in vfx._pools_live, "the oldest is fading")
	assert_eq(vfx._pools_live.size(), cap)
	assert_eq(pools.get_child_count(), cap + 1, "it is still there while it fades")
	# The fade must fade: stretch it to 2 s of real time and read the pool's alpha in the middle. A fade that only
	# waited (an interval of the same length) would leave it at its full alpha until it vanished.
	var scale: float = 0.25
	vfx.set_time_scale(scale)
	var fade_real: float = BattleVfx.POOL_EARLY_FADE_SECONDS / scale
	await wait_seconds(fade_real / 2.0)
	var alpha: float = ((oldest as MeshInstance3D).get_instance_shader_parameter(&"tint") as Color).a
	assert_gt(alpha, 0.0, "part way through its fade it is not gone yet")
	assert_lt(alpha, BattleVfx.POOL_COLOR.a, "and it has started to fade")
	await wait_seconds(fade_real / 2.0 + 0.5)
	assert_false(is_instance_valid(oldest), "and gone")
	assert_eq(pools.get_child_count(), cap, "the rest held")
	assert_eq(pools.get_child(0).position.x, 1.0, "the next oldest is now the oldest")
	assert_eq(vfx._pools_live.size(), cap)


func test_low_holds_fewer_pools_and_a_shorter_time_than_full() -> void:
	assert_lt(BattleVfx.POOL_CAP_LOW, BattleVfx.POOL_CAP_FULL)
	assert_lt(BattleVfx.POOL_HOLD_SECONDS_LOW, BattleVfx.POOL_HOLD_SECONDS_FULL)
	Settings.set_gore("low")
	var vfx: BattleVfx = _vfx()
	for index: int in BattleVfx.POOL_CAP_LOW + 1:
		vfx.spawn(_fall(Vector3(float(index), 0.0, 0.0)))
	assert_eq(vfx._pools_live.size(), BattleVfx.POOL_CAP_LOW, "Low's cap holds")
	Settings.set_gore("full")
	var full: BattleVfx = _vfx()
	for index: int in BattleVfx.POOL_CAP_LOW + 1:
		full.spawn(_fall(Vector3(float(index), 0.0, 0.0)))
	assert_eq(full._pools_live.size(), BattleVfx.POOL_CAP_LOW + 1, "the same falls at Full all stay")


func test_a_full_pool_frees_within_its_scaled_life() -> void:
	var vfx: BattleVfx = _vfx()
	vfx.spawn(_fall(Vector3.ZERO))
	var pool: Node = _pools(vfx).get_child(0)
	var scale: float = 60.0
	vfx.set_time_scale(scale)
	var life: float = BattleVfx.POOL_GROW_SECONDS + BattleVfx.POOL_HOLD_SECONDS_FULL + BattleVfx.POOL_FADE_SECONDS
	await wait_seconds(life / scale + 0.5)
	assert_false(is_instance_valid(pool), "grow + hold + fade, scaled, plus the margin")
	assert_eq(vfx._pools_live.size(), 0)


func test_a_low_pool_frees_before_a_full_one_laid_at_the_same_time() -> void:
	var vfx: BattleVfx = _vfx()
	Settings.set_gore("low")
	vfx.spawn(_fall(Vector3.ZERO))
	Settings.set_gore("full")
	vfx.spawn(_fall(Vector3.ONE))
	var low: Node = _pools(vfx).get_child(0)
	var full: Node = _pools(vfx).get_child(1)
	var scale: float = 8.0
	vfx.set_time_scale(scale)
	var low_life: float = (BattleVfx.POOL_GROW_SECONDS + BattleVfx.POOL_HOLD_SECONDS_LOW + BattleVfx.POOL_FADE_SECONDS) / scale
	var full_life: float = (BattleVfx.POOL_GROW_SECONDS + BattleVfx.POOL_HOLD_SECONDS_FULL + BattleVfx.POOL_FADE_SECONDS) / scale
	assert_gt(full_life - low_life, 1.4, "the two lives are far enough apart to read on real time")
	await wait_seconds(low_life + 0.7)
	assert_false(is_instance_valid(low), "the Low pool is gone")
	assert_true(is_instance_valid(full), "the Full one is not")
	await wait_seconds(full_life - low_life)
	assert_false(is_instance_valid(full), "then it goes too")


# --- 4. Nothing carries over ---------------------------------------------------------------------

func test_a_reset_empties_the_pools_container() -> void:
	var vfx: BattleVfx = _vfx()
	for index: int in 3:
		vfx.spawn(_fall(Vector3(float(index), 0.0, 0.0)))
	assert_eq(_pool_count(vfx), 3)
	vfx.clear_pools()
	assert_eq(_pool_count(vfx), 0)
	assert_eq(vfx.get_child_count(), 0, "at once, no container left to count")
	assert_eq(vfx._pools_live.size(), 0)
	vfx.spawn(_fall(Vector3.ZERO))
	assert_eq(_pool_count(vfx), 1, "and it lays again")
	await wait_seconds(0.2)


func test_a_new_battle_or_a_retry_starts_with_no_blood() -> void:
	var team: Array[Hero] = _team()
	var zone: ZoneDefinition = load(ZONE_PATH) as ZoneDefinition
	var view: BattleView = _practice_view(team, zone)
	var start: Dictionary = view._practice_state.to_dict()
	view._vfx.spawn(_fall(Vector3.ZERO))
	assert_eq(_pool_count(view._vfx), 1)
	view.configure_practice(team, zone)
	assert_eq(_pool_count(view._vfx), 0, "configure_practice")

	view._vfx.spawn(_fall(Vector3.ZERO))
	var controller := LiveStub.new()
	controller.snapshot = start
	add_child_autofree(controller)
	view.configure_live("battle-2", controller)
	assert_eq(_pool_count(view._vfx), 0, "configure_live")

	# A real fall through the view, then the retried run whose tick goes back.
	view._render_snapshot(start.duplicate(true))
	var down: Dictionary = _fallen(start, 5)
	view._render_snapshot(down)
	view._play_due_events(5.0)
	assert_eq(_pool_count(view._vfx), 1, "the fall reached the view's vfx as one pool")
	view._render_snapshot(_with_tick(start, 0))
	assert_eq(_pool_count(view._vfx), 0, "the tick went back: a retry")
	await wait_process_frames(1)


func test_a_view_whose_first_render_already_has_a_downed_hero_lays_no_pool() -> void:
	var team: Array[Hero] = _team()
	var zone: ZoneDefinition = load(ZONE_PATH) as ZoneDefinition
	var view: BattleView = _practice_view(team, zone)
	var start: Dictionary = view._practice_state.to_dict()
	# What a view rebuilt on a mid-battle load has: nothing seen yet (the same start configure_* make).
	view._previous_actors.clear()
	view._last_rendered_tick = -1
	var down: Dictionary = _fallen(start, 0)
	view._render_snapshot(down)
	view._play_due_events(5.0)
	assert_eq(_pool_count(view._vfx), 0, "a hero already down when the view opens (a mid-battle load) is not a fall")


func test_the_pools_add_no_key_to_settings() -> void:
	var before: PackedStringArray = Settings._loaded_config().get_section_keys(Settings.SECTION)
	var vfx: BattleVfx = _vfx()
	for index: int in 5:
		vfx.spawn(_fall(Vector3(float(index), 0.0, 0.0)))
	assert_eq(Settings._loaded_config().get_section_keys(Settings.SECTION), before)
	var source: String = FileAccess.get_file_as_string("res://combat/battle/battle_vfx.gd")
	assert_false("SaveService" in source, "the vfx never touches the save")


# --- 5. Blood does not change a battle -----------------------------------------------------------

func test_ground_blood_leaves_a_seeded_battle_exactly_as_it_was() -> void:
	var team: Array[Hero] = _team()
	var zone: ZoneDefinition = load(ZONE_PATH) as ZoneDefinition
	var first: BattleView = _practice_view(team, zone)
	var start: Dictionary = first._practice_state.to_dict()
	first.free()
	for actor: Dictionary in start["actors"]:
		if actor["faction"] == "ally" and actor["archetype"] == WEAK_ARCHETYPE:
			actor["hp"] = WEAK_HP

	var runs: Dictionary = {}
	for label: String in ["off", "off again", "full"]:
		runs[label] = await _play(team, zone, start, "full" if label == "full" else "off")
	assert_eq(runs["off"]["pools"], 0, "no pool is laid with it off")
	assert_eq(runs["off again"]["pools"], 0, "no pool is laid with it off")
	assert_gt(runs["full"]["pools"], 0, "the full run really laid a pool: someone went down")
	assert_true(runs["off"]["state"] == runs["off again"]["state"], "the control: two off runs agree")
	assert_true(runs["off"]["state"] == runs["full"]["state"], "the final state is the same with blood on")
	assert_true(runs["off"]["outcome"] == runs["full"]["outcome"], "the outcome is the same with blood on")
	assert_true(runs["off"]["state"] != JSON.stringify(start, "", true), "the battle really moved")


# --- 6. Cost -------------------------------------------------------------------------------------

## Not a gate (CODING_RULES § Performance): 50 heroes going down in one diff. The falls alone: a killing hit's own
## effects are ig-c9y.1's cost, and would fill the effect cap here.
func test_cost_of_fifty_falls_in_one_diff() -> void:
	var previous: Dictionary = {}
	var actors: Array = []
	for index: int in 50:
		var id: String = "a%d" % index
		@warning_ignore("integer_division")
		var position: Array = [float(index % 10), float(index / 10)]
		previous[id] = _actor(id, "ally", "knight", {}, {"position": position})
		actors.append(_actor(id, "ally", "knight", {}, {"hp": 0.0, "life": "downed", "position": position}))
	var best: Dictionary = {}
	var worst: Dictionary = {}
	var peak: int = 0
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
			assert_eq(events.size(), 50, "50 falls and nothing else")
			if level == "full":
				peak = maxi(peak, vfx._pools_live.size())
				assert_eq(vfx._pools_live.size(), BattleVfx.POOL_CAP_FULL, "the peak is the Full cap")
			else:
				assert_eq(vfx.get_child_count(), 0, "off adds no child")
			vfx.free()
		best[level] = runs.min() / 1000.0
		worst[level] = runs.max() / 1000.0
	assert_eq(peak, BattleVfx.POOL_CAP_FULL)
	gut.p("GORE POOLS: 50 falls in one diff, off best %.3f worst %.3f ms; full best %.3f worst %.3f ms of 7; peak live pools %d (cap %d)" % [best["off"], worst["off"], best["full"], worst["full"], peak, BattleVfx.POOL_CAP_FULL])


# --- helpers -------------------------------------------------------------------------------------

func _vfx() -> BattleVfx:
	var vfx := BattleVfx.new()
	add_child_autofree(vfx)
	return vfx


func _pools(vfx: BattleVfx) -> Node:
	var pools: Node = vfx.get_node_or_null("Pools")
	assert_not_null(pools, "the Pools container exists")
	return pools


## Pools standing in the vfx, fading ones too; 0 when there is no container.
func _pool_count(vfx: BattleVfx) -> int:
	var pools: Node = vfx.get_node_or_null("Pools")
	return 0 if pools == null else pools.get_child_count()


func _fall(at: Vector3) -> Dictionary:
	return {"kind": "fall", "actor_id": "a1", "faction": "ally", "position": at, "body": "flesh", "tick": 1}


func _team() -> Array[Hero]:
	var team: Array[Hero] = []
	for def_id: StringName in [&"knight", &"ranger", &"mage", &"rogue"]:
		var hero := Hero.new(String(def_id), 0)
		hero.def_id = def_id
		team.append(hero)
	return team


func _practice_view(team: Array[Hero], zone: ZoneDefinition) -> BattleView:
	var view: BattleView = (load("res://combat/battle/battle_view.tscn") as PackedScene).instantiate() as BattleView
	add_child_autofree(view)
	# Only this test's calls advance it.
	view.set_process(false)
	view.configure_practice(team, zone)
	return view


## The snapshot at tick, with the first ally down where it stood and the killing hit on that tick.
func _fallen(snapshot: Dictionary, tick: int) -> Dictionary:
	var down: Dictionary = _with_tick(snapshot, tick)
	for actor: Dictionary in down["actors"]:
		if actor["faction"] == "ally":
			actor["life"] = "downed"
			actor["hp"] = 0.0
			(actor["effect_state"] as Dictionary)["last_hit_tick"] = tick
			break
	return down


func _with_tick(snapshot: Dictionary, tick: int) -> Dictionary:
	var copy: Dictionary = snapshot.duplicate(true)
	copy["tick"] = tick
	return copy


## One 30-second practice battle from the same start, a frame between steps so the effects run as in play.
func _play(team: Array[Hero], zone: ZoneDefinition, start: Dictionary, level: String) -> Dictionary:
	Settings.set_gore(level)
	var view: BattleView = _practice_view(team, zone)
	view._practice_state = BattleState.from_dict(start.duplicate(true))
	var most: int = 0
	for _step: int in BATTLE_STEPS:
		view._process(0.1)
		await get_tree().process_frame
		most = maxi(most, _pool_count(view._vfx))
	var result: Dictionary = {
		"state": JSON.stringify(view._practice_state.to_dict(), "", true),
		"outcome": JSON.stringify(BattleSimulation.snapshot_outcome(view._practice_state).to_dict(), "", true),
		"pools": most,
	}
	view.queue_free()
	await get_tree().process_frame
	return result


func _kinds(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return str(event["kind"]))


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
