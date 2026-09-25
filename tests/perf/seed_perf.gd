extends SceneTree

## ig-7sn.2: seeds the performance baseline's save into whatever APPDATA Godot runs under. Run it
## only on a fresh throwaway APPDATA, never the owner's. Its user:// must hold perf_throwaway.txt, or
## both scripts refuse:
##   T="$(mktemp -d)"; mkdir -p "$T/Godot/app_userdata/Infinite Gacha"; touch "$T/Godot/app_userdata/Infinite Gacha/perf_throwaway.txt"
##   APPDATA="$(cygpath -w "$T")" ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless -s res://tests/perf/seed_perf.gd
## 100 heroes; the Ledger at its 10,000-record cap; every zone open; and the fullest town 100 heroes
## make: every hall keeper, 76 workers in 38 workplaces with a house each, the body, and the rest
## free to wander. perf_baseline.gd refuses a save without the marker this writes.

const BALANCE: BalanceTable = preload("res://balance.tres")
const MARKER: String = "user://perf_seed.txt"
const ARCHETYPES: Array[StringName] = [&"knight", &"mage", &"ranger", &"cleric", &"rogue"]
const WORKERS: int = 76


func _initialize() -> void:
	# Never the owner's profile. Guessing it by path spelling misses aliases and links, so a throwaway
	# opts in instead: perf_throwaway.txt in user:// itself, the folder every save here goes to.
	if not FileAccess.file_exists("user://perf_throwaway.txt"):
		_refuse("No perf_throwaway.txt in %s; refusing. Run only on a throwaway APPDATA that has it." % ProjectSettings.globalize_path("user://"))
		return
	# Checked here, before the autoloads join the tree: GameSession._ready loads any save it finds
	# (and an offline catch-up saves it), so only a user:// with no game in it gets this far.
	for path: String in ["user://save.json", "user://ledger.jsonl", MARKER]:
		if FileAccess.file_exists(path):
			_refuse("%s already exists; seed only a fresh throwaway APPDATA." % ProjectSettings.globalize_path(path))
			return
	create_timer(600.0).timeout.connect(quit.bind(1))
	process_frame.connect(_seed, CONNECT_ONE_SHOT)


## Frees the autoloads before they enter the tree, so none of them loads or saves this APPDATA.
func _refuse(reason: String) -> void:
	var session_ready: bool = root.get_node("GameSession").is_node_ready()
	for child: Node in root.get_children():
		root.remove_child(child)
		child.free()
	push_error("%s (GameSession ready: %s)" % [reason, session_ready])
	quit(1)


func _seed() -> void:
	var session: Node = root.get_node("GameSession")
	if not session.roster.is_empty() or not session.ledger.is_empty() or FileAccess.file_exists(MARKER):
		push_error("This APPDATA already has a game; refusing to seed over it.")
		quit(1)
		return
	session.set("_save_deferred_depth", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids: Array[String] = []
	for index: int in 100:
		var hero := Hero.new("Perf %d" % index, 1 + index % 7)
		hero.def_id = ARCHETYPES[index % ARCHETYPES.size()]
		hero.level = 60 + index % 21
		session.add_hero(hero)
		ids.append(hero.instance_id)
	for zone_id: StringName in [&"verdant_outskirts", &"ashfall_reaches", &"sundered_vault", &"fallen_citadel", &"frontier_march"]:
		session.mark_zone_cleared(zone_id)
	_town(session, ids)
	# The Ledger last, so the town's mutations above stay cheap. The mix of test_bonds' read cost:
	# 6 in 10 routine wins, the rest hard with a revive, 1 in 10 a rescue; 5-hero teams.
	for index: int in BALANCE.ledger_max_records:
		var team: Array[String] = []
		while team.size() < 5:
			var id: String = ids[rng.randi_range(0, ids.size() - 1)]
			if not team.has(id):
				team.append(id)
		var fields: Dictionary = {"order": "perf:%d" % index, "zone": "verdant_outskirts", "battle_kind": "expedition", "result": "victory", "team": team, "kills": {}, "moments": []}
		var roll: int = rng.randi_range(0, 9)
		if roll >= 6:
			fields["result"] = "retreated"
			fields["moments"] = [{"tick": 10, "what": "downed", "hero": team[0], "by": "enemy:goblin"}, {"tick": 20, "what": "revived", "hero": team[0], "by": team[1]}]
		if roll == 9:
			fields.merge({"battle_kind": "rescue", "rescued": [team[2]], "rescuers": [team[3]]}, true)
		session._record("battle", fields)
	session.set("_save_deferred_depth", 0)
	if not root.get_node("SaveService").save():
		push_error("Seed save failed: " + root.get_node("SaveService").last_write_error)
		quit(1)
		return
	var line: String = "SEEDED %d heroes, %d records, %d buildings at %s" % [session.roster.size(), session.ledger.size(), session.town_buildings.size(), ProjectSettings.globalize_path("user://")]
	var marker := FileAccess.open(MARKER, FileAccess.WRITE)
	marker.store_line(line)
	marker.close()
	print(line)
	quit(0)


## Every hall keeper, WORKERS workers (2 per workplace) each with a house, and one body.
func _town(session: Node, ids: Array[String]) -> void:
	session.town_resources["wood"] = 1000000.0
	session.town_resources["food"] = 1000000.0
	var free_hexes: Array[Vector2i] = []
	var taken: Dictionary = {}
	for building: Dictionary in session.town_buildings:
		taken[Vector2i(int(building["q"]), int(building["r"]))] = true
	for q: int in range(-BALANCE.town_map_radius, BALANCE.town_map_radius + 1):
		for r: int in range(-BALANCE.town_map_radius, BALANCE.town_map_radius + 1):
			var hex := Vector2i(q, r)
			if TownRules.ring_distance(hex) <= BALANCE.town_map_radius and not taken.has(hex):
				free_hexes.append(hex)
	free_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return TownRules.ring_distance(a) < TownRules.ring_distance(b))
	var workplaces: Array[StringName] = [TownRules.LUMBERMILL, TownRules.MINE, TownRules.FARM]
	for index: int in WORKERS + int(WORKERS / 2.0):
		var type: StringName = TownRules.HOUSE if index < WORKERS else workplaces[index % 3]
		_check(session, session.place_building(type, free_hexes[index]), "place %s" % type)
	for building: Dictionary in session.town_buildings:
		building.erase("build_remaining")
	var houses: Array[StringName] = []
	var places: Array[StringName] = []
	for building: Dictionary in session.town_buildings:
		var type: StringName = TownRules.type_of(StringName(str(building["id"])))
		if type == TownRules.HOUSE:
			houses.append(StringName(str(building["id"])))
		elif type in workplaces:
			places.append(StringName(str(building["id"])))
	var next: int = 0
	for index: int in WORKERS:
		var hero: Hero = session.hero_by_id(ids[next])
		next += 1
		_check(session, session.assign_home(hero, houses[index]), "home")
		_check(session, session.station_hero(hero, places[int(index / 2.0)]), "work")
	for hall: StringName in TownRules.HALL_HEXES:
		var hall_id: StringName = StringName(str(session.town_building(hall).get("id", hall)))
		if Hero.is_staffable(hall_id):
			_check(session, session.station_hero(session.hero_by_id(ids[next]), hall_id), "keep %s" % hall_id)
			next += 1
	session.embody_hero(ids[next])
	print("town: %d houses, %d workplaces, %d keepers, body %s" % [houses.size(), places.size(), next - WORKERS, ids[next]])


func _check(session: Node, ok: bool, what: String) -> void:
	if not ok:
		push_error("%s failed: %s" % [what, session.last_action_error])
