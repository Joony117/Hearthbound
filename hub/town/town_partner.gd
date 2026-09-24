class_name TownPartner
extends Node3D

## The walking hero's bonded partner, standing in town (SYSTEMS.md § Bonds and dreams, slice 1). A
## view only: hub.gd picks the partner and the line, TownView places it. It idles, no walking. When
## the body comes within MEET_DISTANCE it turns to face it, plays Interact once and shows the line
## above its head; it greets again only after the body has gone back past REARM_DISTANCE.

## A House boxed in by both diagonal neighbours still leaves a spot 2.67 m from its door.
const MEET_DISTANCE: float = 3.0
const REARM_DISTANCE: float = 4.5
const LINE_SECONDS: float = 4.0
const MODEL_SCALE: float = TownHero.MODEL_SCALE

var hero_id: String = ""
var line: String = ""
## The walking body it greets; TownView sets it through follow().
var body: Node3D
## How many times it has greeted, for tests.
var greetings: int = 0
var _model: Node3D
var _animator: AnimationPlayer
var _label: Label3D
var _armed: bool = true
var _line_left: float = 0.0


static func create(hero: Hero) -> TownPartner:
	var partner := TownPartner.new()
	partner.name = "TownPartner"
	partner.hero_id = hero.instance_id
	var archetype: String = "knight" if hero.def_id == Hero.NO_ARCHETYPE_DEF_ID else str(hero.def_id)
	partner._model = HeroModel.build("ally", archetype)
	partner._model.scale = Vector3.ONE * MODEL_SCALE
	partner.add_child(partner._model)
	partner._animator = partner._model.get_node("AnimationPlayer") as AnimationPlayer
	partner._label = Label3D.new()
	partner._label.name = "Line"
	partner._label.pixel_size = 0.008
	partner._label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	partner._label.position.y = 2.1
	partner._label.visible = false
	partner.add_child(partner._label)
	return partner


func _ready() -> void:
	_animator.play("Idle_A")


func _process(delta: float) -> void:
	if _line_left > 0.0:
		_line_left -= delta
		_label.visible = _line_left > 0.0
	if not is_instance_valid(body):
		return
	var distance: float = Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
	if _armed and distance <= MEET_DISTANCE:
		_greet()
	elif not _armed and distance >= REARM_DISTANCE:
		_armed = true


## Greets walker from now on; a new walker gets its own first greeting.
func follow(walker: Node3D) -> void:
	if walker != body:
		body = walker
		_armed = true


func is_showing_line() -> bool:
	return _label.visible


func _greet() -> void:
	_armed = false
	greetings += 1
	var to_body: Vector3 = body.global_position - global_position
	_model.rotation.y = atan2(to_body.x, to_body.z)
	_animator.play("Interact")
	_animator.queue("Idle_A")
	_label.text = line
	_label.visible = true
	_line_left = LINE_SECONDS
