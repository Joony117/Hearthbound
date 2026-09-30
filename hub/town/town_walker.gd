class_name TownWalker
extends Node3D

## A hero in town. A keeper or worker walks from its House door to its work spot and back
## (ig-6m2.6.1); a hero with no station wanders the streets and lingers (ig-6m2.6.2). A view only:
## TownView plans its routes over the hex walk graph and hands them in. It never reads GameSession
## and nothing it does is saved; its randomness is its own RNG. While it is the body's bonded partner
## it greets the body (SYSTEMS.md § Bonds and dreams): when the body comes within MEET_DISTANCE it
## stops, faces it, plays Interact once and shows its line, then walks on; it greets again only after
## the body has gone back past REARM_DISTANCE.

## Presentation numbers (ARCHITECTURE § The town is the interface), not balance rows.
const WALK_SPEED: float = 2.5
const WORK_SECONDS: float = 20.0
const HOME_SECONDS: float = 8.0
## How long a wanderer stays where a trip ends before it picks the next.
const LINGER_SECONDS: float = 6.0
## A House boxed in by both diagonal neighbours still leaves a spot 2.67 m from its door.
const MEET_DISTANCE: float = 3.0
const REARM_DISTANCE: float = 4.5
## The line shows this long, and the walk waits for it.
const LINE_SECONDS: float = 4.0
## A meeting (meet) that the two figures have not come together for in this long is dropped.
const MEETING_SECONDS: float = 30.0
## How near a figure comes to the one it meets before it speaks: a keeper stands at its work spot, and the
## nearest free ground to a hall is 3.84 m away, so MEET_DISTANCE would never be reached.
const CHAT_DISTANCE: float = 4.5
const MODEL_SCALE: float = TownHero.MODEL_SCALE
## The clip played at work, by the station's building type. A station missing here plays
## DEFAULT_WORK_CLIP, so a later workplace never breaks a figure; its slice adds its row.
const WORK_CLIPS: Dictionary[StringName, StringName] = {
	&"Forge": &"Hammering",
	TownRules.LUMBERMILL: &"Chopping",
	TownRules.MINE: &"Pickaxing",
	TownRules.FARM: &"Digging",
	&"Apothecary": &"Working_A",
	&"TrainingHall": &"Push_Ups",
	&"Sanctum": &"Sit_Floor_Idle",
	&"Reliquary": &"Working_C",
}
const DEFAULT_WORK_CLIP: StringName = &"Working_A"
const WALK: StringName = &"walk"
const WORK: StringName = &"work"
const REST: StringName = &"rest"
## A wanderer at the end of a trip.
const LINGER: StringName = &"linger"

var hero_id: String = ""
var station: StringName = Hero.NO_STATION
var home: StringName = Hero.NO_HOME
## WALK, WORK (at the spot), REST (at the House door) or LINGER (a wanderer between trips).
var activity: StringName = WORK
## Walking home or resting there; otherwise walking to work or working.
var heading_home: bool = false
## Seeded from the hero's id: never the global RNG, which summoning draws from.
var rng := RandomNumberGenerator.new()
## Facing while working (towards the building) and while resting (out from the House), as yaw.
var work_yaw: float = 0.0
var rest_yaw: float = 0.0
## A wanderer's next trip, called when a linger ends (TownView binds it); empty for none.
var planner: Callable
## Wanderer trips so far; TownView sends every HOME_EVERY-th one to the House door.
var trips: int = 0
## The body it greets while it is the partner, else null (follow()).
var greet: Node3D
## What it says on meeting the body, as Lines facts ({} for nothing). Facts that differ start its
## lines over from their first pick.
var facts: Dictionary = {}:
	set(value):
		if value != facts:
			_meetings = 0
		facts = value
## How many times it has greeted the body, for tests.
var greetings: int = 0
## How many meetings it has had with another figure (meet), for tests.
var chats: int = 0
## Greetings since facts last changed: the next Lines pick. Never saved.
var _meetings: int = 0
var _last_line: String = ""
var _path := PackedVector3Array()
var _then: StringName = WORK
var _left: float = 0.0
var _to_work := PackedVector3Array()
var _to_home := PackedVector3Array()
var _linger_clip: StringName = &"Idle_B"
## NAN keeps the facing it walked in with.
var _linger_yaw: float = NAN
var _clip: StringName = &""
var _following: bool = false
var _armed: bool = true
## The figure it walks to or waits for (meet), its line ({} for none) and the seconds left to reach it.
var _chat_with: Node3D
var _chat_facts: Dictionary = {}
var _chat_left: float = 0.0
var _line_left: float = 0.0
var _pause_left: float = 0.0
var _model: Node3D
var _animator: AnimationPlayer
var _label: Label3D
var _sign: Label3D


static func create(hero: Hero) -> TownWalker:
	var walker := TownWalker.new()
	walker.name = "Walker_%s" % hero.instance_id
	walker.hero_id = hero.instance_id
	walker.rng.seed = hash(hero.instance_id)
	var archetype: String = "knight" if hero.def_id == Hero.NO_ARCHETYPE_DEF_ID else str(hero.def_id)
	walker._model = HeroModel.build("ally", archetype)
	walker._model.scale = Vector3.ONE * MODEL_SCALE
	walker.add_child(walker._model)
	walker._animator = walker._model.get_node("AnimationPlayer") as AnimationPlayer
	# The click target (ig-6m2.6.2), the body's size, on the walker pick layer alone.
	var pick := StaticBody3D.new()
	pick.name = "Pick"
	pick.collision_layer = TownView.WALKER_PICK_LAYER
	pick.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.9
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	pick.add_child(shape)
	walker.add_child(pick)
	walker._label = Label3D.new()
	walker._label.name = "Line"
	walker._label.pixel_size = 0.008
	walker._label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	walker._label.position.y = 2.1
	walker._label.visible = false
	walker.add_child(walker._label)
	walker._sign = TownHero.sign_label()
	walker.add_child(walker._sign)
	return walker


## Shows "♥ <partner>" over its head, or nothing for "". Hidden while its meeting line shows.
func set_sign(text: String) -> void:
	_sign.text = text
	_sign.visible = not text.is_empty() and not _label.visible


static func work_clip(station_id: StringName) -> StringName:
	var type: StringName = TownRules.type_of(station_id)
	return WORK_CLIPS.get(station_id if type == &"" else type, DEFAULT_WORK_CLIP)


func _process(delta: float) -> void:
	step(delta)


## The House → work and work → House routes; empty ones mean no loop (it only works).
func set_loop(to_work: PackedVector3Array, to_home: PackedVector3Array) -> void:
	_to_work = to_work
	_to_home = to_home


func has_loop() -> bool:
	return not _to_work.is_empty() and not _to_home.is_empty()


## Walks path, then works (then = WORK) or rests (REST) at its end.
func walk(path: PackedVector3Array, then: StringName) -> void:
	_path = path.duplicate()
	_then = then
	heading_home = then == REST
	activity = WALK
	_play(&"Walking_A")


## A wanderer's trip: walks path, then lingers playing clip, facing yaw (NAN: as it walked in).
func wander(path: PackedVector3Array, clip_name: StringName, yaw: float) -> void:
	_linger_clip = clip_name
	_linger_yaw = yaw
	walk(path, LINGER)


## Stands at spot lingering, seconds_left before its next trip.
func linger_at(spot: Vector3, clip_name: StringName, yaw: float, seconds_left: float) -> void:
	position = spot
	_path.clear()
	_linger_clip = clip_name
	_linger_yaw = yaw
	_settle(LINGER, seconds_left)


## Greets target from now on, or no one (null). The first body it follows greets it only once the
## body has come from past REARM_DISTANCE, so a load beside it never fires the greeting at once; a
## body it switches to gets its own first greeting.
func follow(target: Node3D) -> void:
	if target == null:
		greet = null
		_following = false
		return
	if target != greet:
		_armed = _following or _flat_distance(target) >= REARM_DISTANCE
		greet = target
		_following = true


## A one-shot meeting with other (ig-m6o.2.2.4): when other comes within CHAT_DISTANCE it faces it, plays
## Interact once and says a line of facts ({} for none: the one who waited says nothing), then clears itself.
## It is armed at once and never goes through follow(): two neighbours at one House door start nearer than
## REARM_DISTANCE, and follow() would never fire. It leaves greet, facts and _meetings alone, so the
## partner's next greeting is the one it would have said anyway. Not reached in MEETING_SECONDS: dropped.
## While it waits, a linger does not end.
func meet(other: Node3D, meeting_facts: Dictionary) -> void:
	_chat_with = other
	_chat_facts = meeting_facts
	_chat_left = MEETING_SECONDS


func is_meeting() -> bool:
	return _chat_with != null


func is_showing_line() -> bool:
	return _label.visible


## The clip it plays (or plays again after a greeting).
func clip() -> StringName:
	return _clip


func facing() -> float:
	return _model.rotation.y


## Stands at spot working, seconds_left before it heads home (if it has a loop).
func work_at(spot: Vector3, seconds_left: float) -> void:
	position = spot
	_path.clear()
	_settle(WORK, seconds_left)


func is_walking() -> bool:
	return activity == WALK


## Where it is going, or where it stands when it is not walking.
func destination() -> Vector3:
	return _path[_path.size() - 1] if activity == WALK and not _path.is_empty() else position


func step(delta: float) -> void:
	if _line_left > 0.0:
		_line_left -= delta
		_label.visible = _line_left > 0.0
		_sign.visible = not _label.visible and not _sign.text.is_empty()
	if _chat_with != null:
		_chat_left -= delta
		if _chat_left <= 0.0 or not is_instance_valid(_chat_with) or not _chat_with.is_inside_tree():
			_chat_with = null
		elif _flat_distance(_chat_with) <= CHAT_DISTANCE:
			_chat()
			return
	# Before the pause, so a body it switches to mid-greeting still gets its own.
	if _following and is_instance_valid(greet):
		var distance: float = _flat_distance(greet)
		if _armed and distance <= MEET_DISTANCE:
			_greet()
			return
		if not _armed and distance >= REARM_DISTANCE:
			_armed = true
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left > 0.0:
			return
		_resume()
	match activity:
		WALK:
			var move: float = WALK_SPEED * delta
			while move > 0.0 and not _path.is_empty():
				var to: Vector3 = _path[0] - position
				var distance: float = to.length()
				if distance <= move:
					position = _path[0]
					_path.remove_at(0)
					move -= distance
				else:
					position += to / distance * move
					_model.rotation.y = atan2(to.x, to.z)
					move = 0.0
			if _path.is_empty():
				_settle(_then, {WORK: WORK_SECONDS, REST: HOME_SECONDS, LINGER: LINGER_SECONDS}[_then])
		WORK:
			if has_loop():
				_left -= delta
				if _left <= 0.0:
					walk(_to_home, REST)
		REST:
			_left -= delta
			if _left <= 0.0 and has_loop():
				walk(_to_work, WORK)
		LINGER:
			_left -= delta
			if _left <= 0.0 and _chat_with == null and planner.is_valid():
				planner.call()


func _settle(what: StringName, seconds: float) -> void:
	activity = what
	heading_home = what == REST
	_left = seconds
	_face()
	_play({WORK: work_clip(station), REST: &"Idle_A", LINGER: _linger_clip}[what])


func _face() -> void:
	match activity:
		WORK:
			_model.rotation.y = work_yaw
		REST:
			_model.rotation.y = rest_yaw
		LINGER:
			if not is_nan(_linger_yaw):
				_model.rotation.y = _linger_yaw


func _greet() -> void:
	_armed = false
	greetings += 1
	var said: String = Lines.line(facts, _meetings)
	_meetings += 1
	# New facts start over at a pick that may be the line it just said.
	if said == _last_line and Lines.candidates(facts).size() > 1:
		said = Lines.line(facts, _meetings)
		_meetings += 1
	_last_line = said
	_face_and_say(greet, said)


## Its meeting with another figure has come: it stops where it is (a walk to the other ends here), says its
## line (none for the one who waited) and holds like a greeting, then goes back to its own plan.
func _chat() -> void:
	var other: Node3D = _chat_with
	var said: String = Lines.line(_chat_facts, 0)
	_chat_with = null
	_chat_facts = {}
	chats += 1
	if activity == WALK:
		_path.clear()
	_face_and_say(other, said)


## Faces target, plays Interact once, and holds the walk for LINE_SECONDS, with said over its head ("" shows none).
func _face_and_say(target: Node3D, said: String) -> void:
	var to_target: Vector3 = target.global_position - global_position
	_model.rotation.y = atan2(to_target.x, to_target.z)
	_animator.play(&"Interact")
	_animator.queue(&"Idle_A")
	_label.text = said
	_label.visible = not said.is_empty()
	_sign.visible = not _label.visible and not _sign.text.is_empty()
	_line_left = LINE_SECONDS if not said.is_empty() else 0.0
	_pause_left = LINE_SECONDS


## After a greeting: back to what it was doing, facing as it did.
func _resume() -> void:
	if activity != WALK:
		_face()
	var again: StringName = _clip
	_clip = &""
	_play(again)


func _flat_distance(target: Node3D) -> float:
	return Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()


func _play(clip_name: StringName) -> void:
	if _clip == clip_name:
		return
	_clip = clip_name
	_animator.play(clip_name, 0.15)
	# Interact plays once; a stall user then stands.
	if clip_name == &"Interact":
		_animator.queue(&"Idle_B")
