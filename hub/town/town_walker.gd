class_name TownWalker
extends Node3D

## A keeper or worker in town, drawn walking from its House door to its work spot and back
## (ig-6m2.6.1). A view only: TownView plans its routes over the hex walk graph and hands them in.
## It never reads GameSession and nothing it does is saved; its randomness is its own RNG.

## Presentation numbers (ARCHITECTURE § The town is the interface), not balance rows.
const WALK_SPEED: float = 2.5
const WORK_SECONDS: float = 20.0
const HOME_SECONDS: float = 8.0
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

var hero_id: String = ""
var station: StringName = Hero.NO_STATION
var home: StringName = Hero.NO_HOME
## WALK, WORK (at the spot) or REST (at the House door).
var activity: StringName = WORK
## Walking home or resting there; otherwise walking to work or working.
var heading_home: bool = false
## Seeded from the hero's id: never the global RNG, which summoning draws from.
var rng := RandomNumberGenerator.new()
## Facing while working (towards the building) and while resting (out from the House), as yaw.
var work_yaw: float = 0.0
var rest_yaw: float = 0.0
var _path := PackedVector3Array()
var _then: StringName = WORK
var _left: float = 0.0
var _to_work := PackedVector3Array()
var _to_home := PackedVector3Array()
var _model: Node3D
var _animator: AnimationPlayer


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
	return walker


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
				_settle(_then, WORK_SECONDS if _then == WORK else HOME_SECONDS)
		WORK:
			if has_loop():
				_left -= delta
				if _left <= 0.0:
					walk(_to_home, REST)
		REST:
			_left -= delta
			if _left <= 0.0 and has_loop():
				walk(_to_work, WORK)


func _settle(what: StringName, seconds: float) -> void:
	activity = what
	heading_home = what == REST
	_left = seconds
	_model.rotation.y = work_yaw if what == WORK else rest_yaw
	_play(work_clip(station) if what == WORK else &"Idle_A")


func _play(clip: StringName) -> void:
	if _animator.current_animation != clip:
		_animator.play(clip, 0.15)
