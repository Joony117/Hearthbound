class_name BattleView
extends Node3D

signal leave_requested(order_id: String)

const FIELD_COLOR: Color = Color("263a32")
const FIELD_GRID: Color = Color("34463b")
const FIELD_LINE: Color = Color("687959")
const ENVIRONMENT_COLOR: Color = Color("18251f")
const UI_INK: Color = Color("101917")
const UI_BRASS: Color = Color("b28b45")
const ALLY_COLOR: Color = Color("a8c9a8")
const ENEMY_COLOR: Color = Color("e87b68")
const BALANCE: BalanceTable = preload("res://balance.tres")
const GAME_THEME: Theme = preload("res://ui/game_theme.tres")
const PAN_SPEED: float = 14.0
const CAMERA_MIN_SIZE: float = 20.0
const CAMERA_MAX_SIZE: float = 100.0
const BATTLE_PULSE_SECONDS: float = 0.25
const DRAG_THRESHOLD_SQUARED: float = 64.0
const SQUAD_DOUBLE_TAP_SECONDS: float = 0.35
const STANDARD_CAMERA_SIZE: float = 36.0
## ig-vl1.5: how tall a wall draws, a little over a unit.
const WALL_VIEW_HEIGHT: float = 1.4
# Wave-clear slow-mo is view-only: unit lerps, tweens and particles slow; the sim never does.
const SLOW_MO_SCALE: float = 0.25
const SLOW_MO_SECONDS: float = 0.8
# PROVISIONAL (ig-iml): camera shake feel. The owner felt it on 2026-09-24: too intense, so the
# offset was cut by 75% (0.03 to 0.0075). Settled by: the next play-test.
# Trauma per event is BattleVfx.shake_for; it decays in view time and squares into an offset.
const SHAKE_DECAY_PER_SECOND: float = 2.2
const SHAKE_MAX_OFFSET_FRACTION: float = 0.0075
const SHAKE_FREQUENCY: float = 24.0
# ig-rog: the victory banner's engraved plate.
const VICTORY_BACKDROP: Color = Color(0.0, 0.0, 0.0, 0.6)
const VICTORY_PLATE: Color = Color("2b1d10")
const VICTORY_INNER: Color = Color("3a2716")
const VICTORY_GOLD: Color = Color("d4a93c")
const VICTORY_LETTERS: Color = Color("f5dc8e")
const VICTORY_INK: Color = Color("1e1206")
const VICTORY_DONE_LINE: String = "Rewards are in. See them in town."

@onready var _camera_rig: Node3D = %CameraRig
@onready var _camera: Camera3D = %Camera3D
@onready var _units_root: Node3D = %Units
@onready var _ground: MeshInstance3D = %Ground
@onready var _hud: Control = %HUD
@onready var _header_label: Label = %HeaderLabel
@onready var _status_label: Label = %StatusLabel
@onready var _pause_button: Button = %PauseButton
@onready var _exit_button: Button = %ExitButton
@onready var _squad_row: HBoxContainer = %SquadRow
@onready var _command_status: Label = %CommandStatus
@onready var _selected_panel: PanelContainer = %SelectedPanel
@onready var _selected_label: Label = %SelectedLabel
@onready var _skills_row: VBoxContainer = %SkillsRow
@onready var _supply_label: Label = %SupplyLabel
@onready var _stance_picker: OptionButton = %StancePicker
@onready var _auto_battle: CheckButton = %AutoBattle
@onready var _help_panel: PanelContainer = %HelpPanel
@onready var _selection_box: ColorRect = %SelectionBox

var _mode: String = ""
var _order_id: String = ""
var _controller: Node
var _practice_state: BattleState
var _snapshot: Dictionary = {}
var _unit_views: Dictionary[String, BattleUnitView] = {}
var _objective_views: Dictionary[String, Node3D] = {}
var _field_views: Dictionary[String, MeshInstance3D] = {}
var _selected_ids: Array[String] = []
var _practice_names: Dictionary[String, String] = {}
var _squad_structure_key: String = ""
var _selected_ability_button: Button
## One draught button per supply kind (BattleState.SUPPLY_KINDS).
var _item_buttons: Dictionary[String, Button] = {}
var _selected_ability_auto: CheckButton
var _selected_auto_heal: CheckButton
var _selected_auto_revive: CheckButton
var _command_mode: String = ""
var _targeting_kind: String = ""
var _targeting_masterwork: bool = false
## ig-gy0.6: the hero the player pilots ("" for none). Live, GameSession holds the table and the snapshot says
## it ("piloted"); practice, this is the truth and goes onto its own state before each advance. Cleared on leave.
var _piloted_id: String = ""
## ig-gy0.8: the camera rig follows the piloted hero's view (F toggles). On when a pilot is taken, off when it is given
## back; only meaningful while _piloted_id is set (_following).
var _follow_pilot: bool = false
## The area skill waiting for a right-click on the ground or a unit.
var _pilot_aim_skill: String = ""
var _pilot_bar: PanelContainer
var _pilot_slots: HBoxContainer
var _pilot_buttons: Array[Button] = []
var _pilot_bar_key: String = ""
var _take_control_button: Button
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _camera_bounds: float = 20.0
var _camera_zone_id: String = ""
var _grid_lines: Array[MeshInstance3D] = []
var _vfx: BattleVfx
var _previous_actors: Dictionary = {}
var _last_rendered_tick: int = -1
var _slow_mo_remaining: float = 0.0
# Events from a multi-tick render wait here for their own tick: {"due": real seconds, "event": Dictionary}.
var _pending_events: Array[Dictionary] = []
var _shake_trauma: float = 0.0
var _shake_clock: float = 0.0
var _view_time_scale: float = 1.0
var _last_living_enemy_ids: Array[String] = []
var _snapshot_elapsed: float = 0.0
# ig-7sn.19: a battle_changed render since the poll's last turn. The poll then skips its own: a second render of
# the same battle would only re-set every unit and play their waiting hit reactions early.
var _changed_since_poll: bool = false
var _last_squad_key: int = -1
var _last_squad_time: float = -1.0
var _pause_requested: bool = false
var _battle_ended: bool = false
var _practice_command_error: String = ""
var _owns_router_payload: bool = false
var _router_payload_kind: String = ""
var _router_payload_order_id: String = ""
var _router_payload_zone_id: String = ""
## ig-rog: the victory banner over the whole view, and its countdown line and OK. View state only.
var _victory_banner: ColorRect
var _victory_line: Label
var _victory_ok: Button
## The ids of this order's expedition reports when the view was bound: a report not in it is a run
## that finished while the view watched. Repeat orders keep one order id, so the id tells runs apart.
var _reports_at_open: Dictionary = {}


func configure_live(order_id: String, controller: Node) -> void:
	assert(not order_id.is_empty())
	assert(controller != null)
	if _mode == "live" and (_order_id != order_id or _controller != controller):
		_release_live_binding()
	_battle_ended = false
	_previous_actors.clear()
	_last_rendered_tick = -1
	_reset_slow_mo()
	_mode = "live"
	_order_id = order_id
	_controller = controller
	_reports_at_open.clear()
	for report: Dictionary in _order_reports():
		_reports_at_open[str(report.get("id", ""))] = true
	if _victory_banner != null:
		_victory_banner.visible = false
	if is_inside_tree():
		_connect_live_signal()
		_refresh_live_snapshot()


func configure_practice(team: Array[Hero], zone: ZoneDefinition) -> void:
	assert(not team.is_empty() and team.size() <= 5)
	assert(zone != null)
	if _mode == "live":
		_release_live_binding()
	_battle_ended = false
	_previous_actors.clear()
	_last_rendered_tick = -1
	_reset_slow_mo()
	_mode = "practice"
	_order_id = "practice"
	var snapshots: Array[Dictionary] = []
	var hero_ids: Array[String] = []
	for hero: Hero in team:
		assert(hero != null)
		var definition: HeroDefinition = Hero.definition_for(hero.def_id)
		assert(definition != null)
		var stats: Dictionary[StringName, float] = Hero.compute_final_stats(
			hero,
			definition,
			BALANCE,
			Hero.level_for(hero, BALANCE),
		)
		snapshots.append({
			"hero_id": hero.instance_id,
			"archetype": str(hero.def_id),
			"hp": stats[Hero.STAT_HP],
			"atk": stats[Hero.STAT_ATK],
			"defense": stats[Hero.STAT_DEF],
			"speed": stats[Hero.STAT_SPD],
			"crit_rate": stats[Hero.STAT_CRIT_RATE],
			"crit_damage": stats[Hero.STAT_CRIT_DMG],
		})
		hero_ids.append(hero.instance_id)
		_practice_names[hero.instance_id] = hero.hero_name
	var squads: Array[Dictionary] = [{"id": "practice-1", "name": "Practice Team", "hero_ids": hero_ids, "stance": "stay_together", "guard_target_id": ""}]
	_practice_state = BattleSimulation.create_run(
		"practice",
		snapshots,
		zone,
		squads,
		{"auto_battle": true, "default_stance": "stay_together", "auto_heal": true, "auto_revive": true, "heal_below": 0.35, "reserve_last_revival": false, "retreat_when_supplies_empty": false},
		{},
		randi(),
		"practice",
	)
	_camera_bounds = _bounds_for_zone(str(zone.zone_id))
	_render_snapshot(_practice_state.to_dict())


func _ready() -> void:
	_build_battlefield()
	_build_hud()
	_bind_hud()
	if _mode.is_empty():
		if not SceneRouter.battle_order_id.is_empty():
			_router_payload_kind = "live"
			_router_payload_order_id = SceneRouter.battle_order_id
			_owns_router_payload = true
			configure_live(SceneRouter.battle_order_id, GameSession)
		elif not SceneRouter.practice_team.is_empty() and SceneRouter.practice_zone != null:
			_router_payload_kind = "practice"
			_router_payload_order_id = ""
			_router_payload_zone_id = str(SceneRouter.practice_zone.zone_id)
			_router_payload_order_id = ",".join(_practice_payload_hero_ids(SceneRouter.practice_team))
			_owns_router_payload = true
			configure_practice(SceneRouter.practice_team, SceneRouter.practice_zone)
		else:
			_battle_ended = true
			_header_label.text = "Battle unavailable"
			_status_label.text = "No battle was prepared. Return to the hub."
			_exit_button.text = "Return to hub"
			for control: Node in _hud.find_children("*", "BaseButton", true, false):
				var button: BaseButton = control as BaseButton
				button.disabled = button != _exit_button
			return
	if _mode == "live":
		_connect_live_signal()
		_refresh_live_snapshot()
	elif _mode == "practice" and _practice_state != null:
		_render_snapshot(_practice_state.to_dict())


func _process(delta: float) -> void:
	_update_camera_pan(delta)
	_follow_pilot_camera()
	_update_drag_box()
	if _slow_mo_remaining > 0.0:
		_slow_mo_remaining -= delta
		if _slow_mo_remaining <= 0.0:
			_set_view_time_scale(1.0)
	_play_due_events(delta)
	_update_shake(delta)
	if _mode == "practice" and _practice_state != null:
		if not _pause_requested:
			_practice_state.piloted_id = _piloted_id
			BattleSimulation.advance(_practice_state, delta)
			_render_snapshot(_practice_state.to_dict())
	elif _mode == "live":
		_snapshot_elapsed += delta
		if _snapshot_elapsed >= BATTLE_PULSE_SECONDS:
			_snapshot_elapsed = 0.0
			if not _changed_since_poll:
				_refresh_live_snapshot()
			_changed_since_poll = false
	_sync_selected_visuals()


func _unhandled_input(event: InputEvent) -> void:
	# The banner covers a won battle: OK is the only way on.
	if _victory_banner.visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and not _has_editable_focus():
			_handle_key_press(key_event)
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion and _dragging:
		_drag_current = (event as InputEventMouseMotion).position


func _handle_key_press(event: InputEventKey) -> void:
	if _battle_ended:
		return
	if event.is_action_pressed("rts_pause", false, true):
		_set_paused(not _is_paused())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rts_attack_move", false, true):
		_command_mode = "attack_move"
		_command_status.text = "Attack-move: right-click a point or target"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rts_guard", false, true):
		_command_mode = "guard"
		_command_status.text = "Guard: right-click an ally or position"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rts_hold", false, true):
		_send_command({"kind": "hold", "actor_ids": _selected_ids.duplicate()})
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rts_retreat", false, true):
		_send_command({"kind": "retreat", "actor_ids": _selected_ids.duplicate()})
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rts_pilot", false, true):
		_on_take_control_pressed()
		get_viewport().set_input_as_handled()
		return
	if not _piloted_id.is_empty() and event.is_action_pressed("rts_follow_pilot", false, true):
		_follow_pilot = not _follow_pilot
		if _command_line_idle():
			_command_status.text = _follow_status()
		get_viewport().set_input_as_handled()
		return
	for squad_index: int in range(10):
		if event.is_action_pressed("rts_squad_%d" % ((squad_index + 1) % 10), false, true):
			# ig-gy0.6: 1-0 fire the piloted hero's first ten skills while it is piloted, else select squads.
			if _piloted_id.is_empty():
				_select_squad(squad_index)
			else:
				_fire_pilot_slot(squad_index)
			get_viewport().set_input_as_handled()
			return


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera.size = maxf(CAMERA_MIN_SIZE, _camera.size / 1.1)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera.size = minf(CAMERA_MAX_SIZE, _camera.size * 1.1)
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			_drag_current = event.position
		else:
			if _dragging:
				_select_at_mouse(event.position, Input.is_action_pressed("rts_additive_select"))
			_dragging = false
			_selection_box.visible = false
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_context_command(event.position)


func _select_at_mouse(screen_point: Vector2, additive: bool) -> void:
	var selection_rect := Rect2(_drag_start, _drag_current - _drag_start).abs()
	var is_box: bool = selection_rect.size.length_squared() >= DRAG_THRESHOLD_SQUARED
	var newly_selected: Array[String] = []
	if is_box:
		for unit: BattleUnitView in _unit_views.values():
			if unit.faction != "ally" or unit.life != "alive" or _camera.is_position_behind(unit.global_position):
				continue
			if selection_rect.has_point(_camera.unproject_position(unit.global_position)):
				newly_selected.append(unit.actor_id)
	else:
		var clicked: BattleUnitView = _unit_at_screen(screen_point, 30.0)
		if clicked != null and clicked.faction == "ally" and clicked.life == "alive":
			newly_selected.append(clicked.actor_id)
	if not additive:
		_selected_ids.clear()
	for actor_id: String in newly_selected:
		if actor_id not in _selected_ids:
			_selected_ids.append(actor_id)
	_refresh_selection_presentation()


func _issue_context_command(screen_point: Vector2) -> void:
	if _battle_ended:
		return
	# ig-gy0.6: an area skill of the pilot's bar waits for this click, whatever is selected.
	if not _pilot_aim_skill.is_empty() and not _piloted_id.is_empty():
		var aim_click: BattleUnitView = _unit_at_screen(screen_point, 30.0)
		var aim_point: Vector2 = _ground_point(screen_point)
		var aimed: Dictionary = {"kind": "use_skill", "actor_ids": [_piloted_id], "skill_id": _pilot_aim_skill}
		if aim_click != null:
			aimed["target_id"] = aim_click.actor_id
		else:
			aimed["point"] = [aim_point.x, aim_point.y]
		_pilot_aim_skill = ""
		_send_command(aimed)
		return
	if _selected_ids.is_empty():
		return
	var point: Vector2 = _ground_point(screen_point)
	var clicked: BattleUnitView = _unit_at_screen(screen_point, 30.0)
	if not _targeting_kind.is_empty():
		var targeted: Dictionary = {"kind": _targeting_kind, "actor_ids": [_selected_ids[0]]}
		if _targeting_masterwork:
			targeted["masterwork"] = true
		if clicked != null:
			targeted["target_id"] = clicked.actor_id
		else:
			targeted["point"] = [point.x, point.y]
		_send_command(targeted)
		_targeting_kind = ""
		return
	var command: Dictionary = {"kind": "move", "actor_ids": _selected_ids.duplicate(), "point": [point.x, point.y]}
	if _command_mode == "attack_move":
		command["kind"] = "attack_move"
		if clicked != null and clicked.faction == "enemy":
			command["target_id"] = clicked.actor_id
	elif _command_mode == "guard":
		command["kind"] = "guard"
		if clicked != null:
			command["target_id"] = clicked.actor_id
		_command_mode = ""
	elif clicked != null and clicked.faction == "enemy":
		command["kind"] = "attack"
		command["target_id"] = clicked.actor_id
	elif clicked != null and clicked.faction == "ally" and clicked.life == "alive":
		command["kind"] = "guard"
		command["target_id"] = clicked.actor_id
	elif clicked != null and clicked.faction == "ally" and clicked.life == "downed":
		command["kind"] = "carry"
		command["target_id"] = clicked.actor_id
	if _command_mode == "attack_move":
		_command_mode = ""
	_send_command(command)


func _unit_at_screen(screen_point: Vector2, radius: float) -> BattleUnitView:
	var closest: BattleUnitView
	var closest_distance: float = radius * radius
	for unit: BattleUnitView in _unit_views.values():
		var targetable_life: bool = unit.life == BattleActor.LIFE_ALIVE or (unit.faction == "ally" and unit.life == BattleActor.LIFE_DOWNED)
		if not targetable_life or not unit.visible or not unit.is_visible_in_tree() or _camera.is_position_behind(unit.global_position):
			continue
		var distance: float = _camera.unproject_position(unit.global_position).distance_squared_to(screen_point)
		if distance < closest_distance:
			closest = unit
			closest_distance = distance
	return closest


func _ground_point(screen_point: Vector2) -> Vector2:
	var origin: Vector3 = _camera.project_ray_origin(screen_point)
	var direction: Vector3 = _camera.project_ray_normal(screen_point)
	# Plane.intersects_ray is Variant by API and may return null when the ray misses the ground plane.
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if intersection is Vector3:
		var point: Vector3 = intersection as Vector3
		return Vector2(clampf(point.x, -_camera_bounds, _camera_bounds), clampf(point.z, -_camera_bounds, _camera_bounds))
	return Vector2.ZERO


func _send_command(command: Dictionary) -> void:
	if _battle_ended:
		return
	# Command actor_ids is decoded from the UI/domain dictionary boundary.
	var raw_actor_ids: Variant = command.get("actor_ids", [])
	if not raw_actor_ids is Array:
		_command_status.text = "Battle command requires actor IDs"
		return
	if (raw_actor_ids as Array).is_empty():
		return
	if _mode == "practice" and _practice_state != null:
		var practice_result: Dictionary = BattleSimulation.issue_command(_practice_state, command)
		_show_command_result(practice_result)
		_render_snapshot(_practice_state.to_dict())
		return
	if _mode == "live" and _controller != null:
		# Node.callv returns Variant because the phase-B GameSession autoload methods are not yet compiled in this phase.
		var live_result: Variant = _controller.call("issue_battle_command", _order_id, command)
		if live_result is Dictionary:
			_show_command_result(live_result as Dictionary)
		else:
			_command_status.text = "Battle command service is unavailable"


func _show_command_result(result: Dictionary) -> void:
	if bool(result.get("accepted", false)):
		_practice_command_error = ""
		_command_status.text = ""
		return
	var rejection: String = str(result.get("error", ""))
	if _mode == "practice":
		_practice_command_error = rejection
	_command_status.text = rejection


func _connect_live_signal() -> void:
	if _controller == null or not _controller.has_signal("battle_changed"):
		return
	var callback := Callable(self, "_on_battle_changed")
	if not _controller.is_connected("battle_changed", callback):
		_controller.connect("battle_changed", callback)


func _on_battle_changed(order_id: String) -> void:
	if order_id == _order_id:
		_refresh_live_snapshot()
		_changed_since_poll = true


func _refresh_live_snapshot() -> void:
	if _controller == null:
		return
	# Node.call returns Variant until phase-B GameSession supplies the concrete autoload API.
	var snapshot_value: Variant = _controller.call("get_battle_snapshot", _order_id)
	if snapshot_value is Dictionary and not (snapshot_value as Dictionary).is_empty():
		_render_snapshot(snapshot_value as Dictionary)
	else:
		_mark_battle_ended()
	_update_victory_banner()


## ig-rog: VICTORY over the whole view once this watched normal order shows a win: a Victory
## snapshot, or a victory report new since the view was bound. A win with no route time left completes
## the order in its own pulse, so the view sees only the aftermath and the report. No banner for a win
## the view saw neither way; it stays until OK.
func _update_victory_banner() -> void:
	if _mode != "live" or _snapshot.is_empty() or str(_snapshot.get("kind", "normal")) != "normal":
		return
	var reported: bool = _has_new_victory_report()
	var winning: bool = not _battle_ended and str(_snapshot.get("status", "")) == "victory"
	if not (reported or winning or _victory_banner.visible):
		return
	var route_remaining: float = float(_snapshot.get("route_remaining_seconds", 0.0))
	_victory_line.text = "Heading home · rewards in %s" % _format_time(route_remaining) if winning and not reported and route_remaining > 0.0 else VICTORY_DONE_LINE
	if not _victory_banner.visible:
		_victory_banner.visible = true
		_victory_ok.grab_focus()


func _has_new_victory_report() -> bool:
	for report: Dictionary in _order_reports():
		if str(report.get("outcome", "")) == "victory" and not _reports_at_open.has(str(report.get("id", ""))):
			return true
	return false


## This order's expedition reports, oldest first; [] for a controller that keeps none.
func _order_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var all_reports: Variant = _controller.get("expedition_reports") if _controller != null else null
	if all_reports is Array:
		for report: Variant in all_reports as Array:
			if report is Dictionary and str((report as Dictionary).get("order_id", "")) == _order_id:
				reports.append(report as Dictionary)
	return reports


## Keeps the Dictionary it's handed, uncopied (ig-7sn.19): every caller hands over one it never touches again.
func _render_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if not is_inside_tree():
		return
	var zone_id: String = str(_snapshot.get("zone_id", ""))
	if zone_id != _camera_zone_id:
		_camera_zone_id = zone_id
		_camera_bounds = _bounds_for_zone(zone_id)
		_camera.size = _camera_size_for_zone(zone_id)
		_resize_ground()
	var team_name: String = str(_snapshot.get("team_name", "Battle"))
	var zone_name: String = zone_id.replace("_", " ").capitalize()
	_header_label.text = "%s   ·   %s" % [team_name.left(18), zone_name.left(18)]
	_header_label.tooltip_text = "%s — %s" % [team_name, zone_name]
	var route_remaining: float = float(_snapshot.get("route_remaining_seconds", 0.0))
	var status: String = str(_snapshot.get("status", "active")).capitalize()
	if _mode == "practice":
		_status_label.text = "Practice · %s" % status
	elif str(_snapshot.get("kind", "normal")) == "rescue":
		_status_label.text = "Rescue · %s" % status
	elif status == "Victory" and route_remaining > 0.0:
		_status_label.text = "Victory! Heading home · rewards in %s" % _format_time(route_remaining)
	elif str(_snapshot.get("phase", "")) == "checking":
		_status_label.text = "%s   ·   Checking the next run" % status
	elif bool(_snapshot.get("catching_up", false)):
		_status_label.text = "%s   ·   Catching up" % status
	else:
		_status_label.text = "%s   ·   Route minimum %s" % [status, _format_time(route_remaining)]
	# The snapshot's pilot first: the idle line below reads it.
	_piloted_id = str(_snapshot.get("piloted", _piloted_id))
	var checkpoint_error: String = str(_snapshot.get("checkpoint_error", ""))
	var command_error: String = str(_snapshot.get("last_command_error", ""))
	if _command_line_idle():
		_command_status.text = _follow_status()
	elif not checkpoint_error.is_empty():
		_command_status.text = "Checkpoint failed: %s" % checkpoint_error
	elif not command_error.is_empty():
		_command_status.text = command_error
	elif _mode == "practice" and not _practice_command_error.is_empty():
		_command_status.text = _practice_command_error
	_supply_label.text = BattleState.supplies_text(_snapshot.get("supplies_remaining", {}) as Dictionary)
	_pause_requested = bool(_snapshot.get("paused", _pause_requested))
	_pause_button.text = "Resume" if _is_paused() else "Pause"
	_auto_battle.set_pressed_no_signal(bool((_snapshot.get("policies", {}) as Dictionary).get("auto_battle", true)))
	_update_squad_row()
	_update_selected_panel()
	_update_unit_views()
	_update_objective_views()
	_update_field_views()
	_update_pilot_bar()
	# ig-gy0.6: a pilot that fell or left the fight is given back to the AI. Last, so a re-render it causes has
	# nothing left to do.
	if not _piloted_id.is_empty() and _actor_data(_piloted_id).get("life", "") != BattleActor.LIFE_ALIVE:
		_set_piloted("")


func _mark_battle_ended() -> void:
	# ig-gy0.6: the fight is over, so the hero goes back as on leaving (the hotbar goes, the session's entry is cleared).
	_set_piloted("")
	_battle_ended = true
	_status_label.text = "Battle ended · Return to hub for results"
	_command_status.text = ""
	_pause_button.disabled = true
	_auto_battle.disabled = true
	for control: Node in _hud.find_children("*", "BaseButton", true, false):
		var button: BaseButton = control as BaseButton
		button.disabled = button != _exit_button and button != _victory_ok
	_exit_button.text = "Return to hub"


func _update_unit_views() -> void:
	# Serialized actor dictionaries are validated by BattleState before production snapshots are returned.
	var raw_actors: Variant = _snapshot.get("actors", [])
	if not raw_actors is Array:
		return
	var tick: int = int(_snapshot.get("tick", 0))
	var first_tick: int = _last_rendered_tick + 1
	if tick < _last_rendered_tick:
		first_tick = tick
		# A retried run restarts at tick 0 under the same order id and reuses its enemy ids; drop every view so nothing carries over.
		for stale: BattleUnitView in _unit_views.values():
			_units_root.remove_child(stale)
			stale.queue_free()
		_unit_views.clear()
		_previous_actors.clear()
		_reset_slow_mo()
	_last_rendered_tick = tick
	# Live renders land every pulse carrying several ticks; practice renders every frame, a tick at a time.
	# Either way units play the new ticks back over the interval until the next render, one render behind.
	var glide: float = BALANCE.battle_tick_seconds if _mode == "practice" else BATTLE_PULSE_SECONDS
	var step: float = tick_step(tick - first_tick + 1, glide)
	var visible_ids: Array[String] = []
	var next_actors: Dictionary = {}
	var living_enemy_ids: Array[String] = []
	for raw_actor: Variant in raw_actors as Array:
		if not raw_actor is Dictionary:
			continue
		var actor: Dictionary = raw_actor as Dictionary
		var actor_id: String = str(actor.get("id", ""))
		if actor_id.is_empty():
			continue
		visible_ids.append(actor_id)
		next_actors[actor_id] = actor
		if str(actor.get("faction", "")) == "enemy" and str(actor.get("life", "")) == "alive":
			living_enemy_ids.append(actor_id)
		var unit: BattleUnitView = _unit_views.get(actor_id) as BattleUnitView
		if unit == null:
			unit = BattleUnitView.new()
			unit.name = "Unit_%s" % actor_id.validate_node_name()
			unit.set_actor(actor, actor_id in _selected_ids, glide)
			unit.set_time_scale(_view_time_scale)
			unit.body_landed.connect(_on_unit_body_landed)
			_units_root.add_child(unit)
			_unit_views[actor_id] = unit
		else:
			var effects: Variant = actor.get("effect_state", {})
			var hit_tick: int = int((effects as Dictionary).get("last_hit_tick", first_tick)) if effects is Dictionary else first_tick
			unit.set_actor(actor, actor_id in _selected_ids, glide, tick_delay(hit_tick, first_tick, step))
	for actor_id: String in _unit_views.keys():
		if actor_id not in visible_ids:
			_unit_views[actor_id].queue_free()
			_unit_views.erase(actor_id)
	var last_death_delay: float = 0.0
	for event: Dictionary in BattleVfx.events_between(_previous_actors, raw_actors as Array):
		var delay: float = tick_delay(int(event.get("tick", first_tick)), first_tick, step)
		if str(event.get("kind", "")) == "death":
			last_death_delay = maxf(last_death_delay, delay)
		_schedule_event(event, delay)
	# Compare ids, not counts: a standard zone spawns the next wave in the same tick the last enemy dies.
	var wave_cleared: bool = not _last_living_enemy_ids.is_empty()
	for enemy_id: String in _last_living_enemy_ids:
		if enemy_id in living_enemy_ids:
			wave_cleared = false
			break
	if wave_cleared:
		_schedule_event({"kind": "slow_mo"}, last_death_delay)
	_last_living_enemy_ids = living_enemy_ids
	# References to the actor dicts inside _snapshot, which nothing may write to: _render_snapshot keeps the Dictionary
	# it's handed, and every caller hands over one it never touches again.
	_previous_actors = next_actors


## Real seconds between consecutive ticks when a render covering tick_count ticks plays back over glide
## seconds: one sim tick each, squeezed only when a hitch delivers more ticks than fit.
static func tick_step(tick_count: int, glide: float) -> float:
	return minf(BALANCE.battle_tick_seconds, glide / float(maxi(tick_count, 1)))


## Real seconds after the render at which something that happened on tick plays; a tick older
## than this render (a reaction carried on an unchanged timestamp) plays at once.
static func tick_delay(tick: int, first_tick: int, step: float) -> float:
	return maxf(0.0, float(tick - first_tick) * step)


func _schedule_event(event: Dictionary, delay: float) -> void:
	if delay <= 0.0:
		_play_event(event)
	else:
		_pending_events.append({"due": delay, "event": event})


func _play_due_events(delta: float) -> void:
	var due: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for pending: Dictionary in _pending_events:
		pending["due"] = float(pending["due"]) - delta
		if float(pending["due"]) <= 0.0:
			due.append(pending)
		else:
			waiting.append(pending)
	_pending_events = waiting
	for pending: Dictionary in due:
		_play_event(pending["event"] as Dictionary)


func _play_event(event: Dictionary) -> void:
	var kind: String = str(event.get("kind", ""))
	if kind == "slow_mo":
		_slow_mo_remaining = SLOW_MO_SECONDS
		_set_view_time_scale(SLOW_MO_SCALE)
		return
	_vfx.spawn(event)
	_shake_trauma = minf(1.0, _shake_trauma + BattleVfx.shake_for(event))
	var unit: BattleUnitView = _unit_views.get(str(event.get("actor_id", ""))) as BattleUnitView
	if unit == null:
		return
	match kind:
		"hit":
			if bool(event.get("critical", false)):
				unit.hit_stop()
		"basic_attack":
			if not bool(event.get("projectile", false)):
				unit.lunge(event.get("target_position", unit.target_position) as Vector3)
			# Accepted (review F5): a crit from anyone on this attacker's target freezes it too.
			if bool(event.get("critical", false)):
				unit.hit_stop()


func _set_view_time_scale(value: float) -> void:
	_view_time_scale = value
	for unit: BattleUnitView in _unit_views.values():
		unit.set_time_scale(value)
	if _vfx != null:
		_vfx.set_time_scale(value)


func _on_unit_body_landed(at: Vector3) -> void:
	if _vfx != null:
		_vfx.spawn({"kind": "landing", "position": at})


# The offset rides on h/v_offset, so camera panning and zone framing never fight it.
# Runs in view time, so slow-mo slows the shake, and a paused battle holds still.
func _update_shake(delta: float) -> void:
	if _is_paused():
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	var scaled: float = delta * _view_time_scale
	_shake_trauma = maxf(0.0, _shake_trauma - SHAKE_DECAY_PER_SECOND * scaled)
	_shake_clock += scaled
	var amplitude: float = _camera.size * SHAKE_MAX_OFFSET_FRACTION * _shake_trauma * _shake_trauma
	_camera.h_offset = amplitude * sin(_shake_clock * SHAKE_FREQUENCY * TAU)
	_camera.v_offset = amplitude * sin(_shake_clock * SHAKE_FREQUENCY * 1.37 * TAU + 1.0)


# Also drops queued events: they belong to the run or view being reset.
func _reset_slow_mo() -> void:
	_pending_events.clear()
	_shake_trauma = 0.0
	_slow_mo_remaining = 0.0
	_last_living_enemy_ids.clear()
	# ig-c9y.7: a new battle, a retry or a new view shows no blood from the last one; null before _ready builds it.
	if _vfx != null:
		_vfx.clear_pools()
	_set_view_time_scale(1.0)


func _update_objective_views() -> void:
	var objective_state: Dictionary = _snapshot.get("objective_state", {})
	# objective_state is a serialized domain dictionary; marker fields are narrowed on this view edge.
	var raw_markers: Variant = objective_state.get("markers", [])
	if not raw_markers is Array:
		return
	var seen_ids: Array[String] = []
	for raw_marker: Variant in raw_markers as Array:
		if not raw_marker is Dictionary:
			continue
		var marker: Dictionary = raw_marker as Dictionary
		var marker_id: String = str(marker.get("id", ""))
		if marker_id.is_empty():
			continue
		seen_ids.append(marker_id)
		var marker_node: Node3D = _objective_views.get(marker_id) as Node3D
		if marker_node == null:
			marker_node = _make_objective_marker(marker_id)
			_objective_views[marker_id] = marker_node
			%Objectives.add_child(marker_node)
		var point: Vector2 = _array_vector2(marker.get("position", [0.0, 0.0]))
		marker_node.position = Vector3(point.x, 0.05, point.y)
		marker_node.visible = true
		var radius: float = maxf(float(marker.get("radius", 1.0)), 0.5)
		var ring: MeshInstance3D = marker_node.get_node("Ring") as MeshInstance3D
		var ring_mesh: TorusMesh = ring.mesh as TorusMesh
		ring_mesh.inner_radius = radius * 0.87
		ring_mesh.outer_radius = radius
		var color: Color = Color("737d73") if bool(marker.get("complete", false)) or not bool(marker.get("active", true)) else UI_BRASS if str(marker.get("kind", "")) == "exit" else Color("d1b56e")
		(ring.material_override as StandardMaterial3D).albedo_color = color
		var label: Label3D = marker_node.get_node("Label") as Label3D
		var marker_label: String = str(marker.get("label", marker.get("kind", "Objective")))
		var progress: float = clampf(float(marker.get("progress", 0.0)), 0.0, 1.0)
		label.text = "%s %d%%" % [marker_label, roundi(progress * 100.0)] if str(marker.get("kind", "")) != "exit" and bool(marker.get("active", true)) and not bool(marker.get("complete", false)) else marker_label
		label.modulate = color
	for marker_id: String in _objective_views.keys():
		if marker_id not in seen_ids:
			_objective_views[marker_id].queue_free()
			_objective_views.erase(marker_id)


## ig-vl1.4: a ring per live zone, read from the checkpoint only (DECISIONS.md 2026-09-25, "Casters shape
## the field", item 9): frost for a zone on opponents, warm for one on allies. ig-vl1.5: a wall draws by its
## kind, from its own keys and never its skill: a frost box over its segment, length x thickness.
func _update_field_views() -> void:
	var raw_fields: Variant = _snapshot.get("field_objects", [])
	if not raw_fields is Array:
		raw_fields = []
	var seen_ids: Array[String] = []
	for raw_field: Variant in raw_fields as Array:
		if not raw_field is Dictionary:
			continue
		var field: Dictionary = raw_field as Dictionary
		var field_id: String = str(field.get("id", ""))
		var is_wall: bool = str(field.get("kind", "")) == "wall"
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(str(field.get("skill_id", ""))) as AbilityDefinition
		if field_id.is_empty() or (skill == null and not is_wall):
			continue
		seen_ids.append(field_id)
		var shape: MeshInstance3D = _field_views.get(field_id) as MeshInstance3D
		if shape == null:
			shape = MeshInstance3D.new()
			shape.name = "Field_%s" % field_id.validate_node_name()
			shape.material_override = _new_material(Color.WHITE)
			_field_views[field_id] = shape
			%Objectives.add_child(shape)
		# Set every render: a retried run reuses its ids, maybe for the other kind.
		if is_wall:
			var start: Vector2 = _array_vector2(field.get("start", [0.0, 0.0]))
			var finish: Vector2 = _array_vector2(field.get("end", [0.0, 0.0]))
			if not shape.mesh is BoxMesh:
				shape.mesh = BoxMesh.new()
			(shape.mesh as BoxMesh).size = Vector3(maxf(start.distance_to(finish), 0.1), WALL_VIEW_HEIGHT, maxf(float(field.get("thickness", 1.0)), 0.1))
			(shape.material_override as StandardMaterial3D).albedo_color = Color("b8dcf2")
			var middle: Vector2 = (start + finish) * 0.5
			shape.position = Vector3(middle.x, WALL_VIEW_HEIGHT * 0.5, middle.y)
			# The box's x runs along the segment; sim y is the view's z.
			shape.rotation = Vector3(0.0, atan2(-(finish.y - start.y), finish.x - start.x), 0.0)
			continue
		if not shape.mesh is TorusMesh:
			shape.mesh = TorusMesh.new()
		var radius: float = maxf(float(field.get("radius", 1.0)), 0.5)
		(shape.mesh as TorusMesh).inner_radius = radius * 0.93
		(shape.mesh as TorusMesh).outer_radius = radius
		var on_opponents: bool = str(BattleSimulation._effect_of(skill, "zone").get("side", "")) == "opponents"
		(shape.material_override as StandardMaterial3D).albedo_color = Color("8fc4e8") if on_opponents else Color("e8c77a")
		var center: Vector2 = _array_vector2(field.get("center", [0.0, 0.0]))
		shape.position = Vector3(center.x, 0.04, center.y)
		shape.rotation = Vector3.ZERO
	for field_id: String in _field_views.keys():
		if field_id not in seen_ids:
			_field_views[field_id].queue_free()
			_field_views.erase(field_id)


func _make_objective_marker(marker_id: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = "Objective_%s" % marker_id.validate_node_name()
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = TorusMesh.new()
	ring.material_override = _new_material(Color("d1b56e"))
	marker.add_child(ring)
	var label := Label3D.new()
	label.name = "Label"
	label.position = Vector3(0.0, 1.8, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.025
	label.outline_size = 8
	label.text = marker_id
	marker.add_child(label)
	return marker


func _update_squad_row() -> void:
	# The live snapshot is serialized; validate the squads collection before rendering buttons.
	var raw_squads: Variant = _snapshot.get("squads", [])
	if not raw_squads is Array:
		return
	var squads: Array = raw_squads as Array
	var key_parts: PackedStringArray = []
	for squad_value: Variant in squads:
		if squad_value is Dictionary:
			var squad_data: Dictionary = squad_value as Dictionary
			key_parts.append("%s:%s:%s" % [str(squad_data.get("id", "")), str(squad_data.get("name", "")), str(squad_data.get("hero_ids", []))])
	var new_key: String = "|".join(key_parts)
	if new_key == _squad_structure_key:
		for existing_index: int in mini(_squad_row.get_child_count(), squads.size()):
			var existing_button: Button = _squad_row.get_child(existing_index) as Button
			var existing_squad: Dictionary = squads[existing_index] as Dictionary
			existing_button.add_theme_color_override("font_color", UI_BRASS if str(existing_squad.get("id", "")) in _selected_squad_ids() else Color.WHITE)
		return
	_squad_structure_key = new_key
	for child: Node in _squad_row.get_children():
		_squad_row.remove_child(child)
		child.queue_free()
	for squad_index: int in mini(squads.size(), 10):
		if not squads[squad_index] is Dictionary:
			continue
		var squad: Dictionary = squads[squad_index] as Dictionary
		var squad_id: String = str(squad.get("id", ""))
		var button := Button.new()
		var squad_name: String = str(squad.get("name", "Squad"))
		button.text = "%d  %s\n%d heroes" % [((squad_index + 1) % 10), squad_name.left(13), (squad.get("hero_ids", []) as Array).size()]
		button.custom_minimum_size = Vector2(110.0, 54.0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_squad_button_pressed.bind(squad_index))
		_squad_row.add_child(button)
		button.add_theme_color_override("font_color", UI_BRASS if squad_id in _selected_squad_ids() else Color.WHITE)


func _selected_squad_ids() -> Array[String]:
	var result: Array[String] = []
	# Serialized snapshot entries are narrowed to dictionaries and arrays before use.
	for squad_value: Variant in _snapshot.get("squads", []) as Array:
		if not squad_value is Dictionary:
			continue
		var squad: Dictionary = squad_value as Dictionary
		var raw_ids: Variant = squad.get("hero_ids", [])
		if not raw_ids is Array:
			continue
		# JSON-compatible squad hero IDs remain Variant until verified as String.
		for hero_id_value: Variant in raw_ids as Array:
			if hero_id_value is String and str(hero_id_value) in _selected_ids:
				result.append(str(squad.get("id", "")))
				break
	return result


func _update_selected_panel() -> void:
	_selected_panel.visible = not _selected_ids.is_empty()
	_selected_label.text = "Selected %d" % _selected_ids.size()
	if _selected_ids.is_empty():
		return
	var actors: Array = _snapshot.get("actors", []) as Array
	var selected_actor: Dictionary = {}
	for actor: Variant in actors:
		if actor is Dictionary and str((actor as Dictionary).get("id", "")) == _selected_ids[0]:
			selected_actor = actor as Dictionary
			break
	if selected_actor.is_empty():
		_selected_label.text = "Selected hero unavailable"
		_selected_ability_button.disabled = true
		for button: Button in _item_buttons.values():
			button.disabled = true
		return
	var archetype: String = str(selected_actor.get("archetype", "Hero"))
	var hero_id: String = str(selected_actor.get("hero_id", ""))
	var hero_name: String = _practice_names.get(hero_id, archetype.capitalize())
	if _mode == "live" and not hero_id.is_empty():
		var live_hero_value: Variant = _controller.call("hero_by_id", hero_id)
		var live_hero: Hero = live_hero_value as Hero
		if live_hero != null:
			hero_name = live_hero.hero_name
	# The signature: the first ability on the actor's list not set to Off, the one a manual cast fires.
	var ability_definition: AbilityDefinition = null
	var ability_auto: bool = true
	for entry: Variant in selected_actor.get("skills", []) as Array:
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(str((entry as Dictionary).get("id", ""))) as AbilityDefinition
		if skill != null and skill.is_ability() and str((entry as Dictionary).get("mode", "auto")) != "off":
			ability_definition = skill
			ability_auto = str((entry as Dictionary).get("mode", "auto")) == "auto"
			break
	var ability_name: String = ability_definition.display_name if ability_definition != null else "Signature"
	var ability_cooldown: float = float((selected_actor.get("skill_cooldowns", {}) as Dictionary).get(str(ability_definition.skill_id), 0.0)) if ability_definition != null else 0.0
	var item_cooldown: float = float(selected_actor.get("item_cooldown", 0.0))
	_selected_label.text = "%s · %s · HP %.0f / %.0f" % [hero_name, archetype.capitalize(), float(selected_actor.get("hp", 0.0)), float(selected_actor.get("max_hp", 0.0))]
	_selected_label.clip_text = true
	_selected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selected_label.tooltip_text = _selected_label.text
	var available: bool = str(selected_actor.get("life", "alive")) == "alive"
	_selected_ability_button.text = "%s%s" % [ability_name, " · %.1fs" % ability_cooldown if ability_cooldown > 0.0 else ""]
	_selected_ability_button.disabled = not available or ability_cooldown > 0.0
	_selected_ability_button.tooltip_text = "Use %s" % ability_name if ability_cooldown <= 0.0 else "%s available in %.1f seconds" % [ability_name, ability_cooldown]
	var supplies: Dictionary = _snapshot.get("supplies_remaining", {}) as Dictionary
	for supply_kind: String in _item_buttons:
		var button: Button = _item_buttons[supply_kind]
		button.disabled = not available or item_cooldown > 0.0 or int(supplies.get(supply_kind, 0)) <= 0
		button.tooltip_text = "Item cooldown %.1f seconds" % item_cooldown if item_cooldown > 0.0 else "Use a %s draught" % BattleState.supply_name(supply_kind).to_lower()
	_selected_ability_auto.set_pressed_no_signal(ability_auto)
	var policies: Dictionary = _snapshot.get("policies", {}) as Dictionary
	_selected_auto_heal.set_pressed_no_signal(bool(policies.get("auto_heal", true)))
	_selected_auto_revive.set_pressed_no_signal(bool(policies.get("auto_revive", true)))


func _command_button(parent: Control, label: String, kind: String, masterwork: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(_on_selected_command_pressed.bind(kind, masterwork))
	parent.add_child(button)
	return button


func _on_selected_command_pressed(kind: String, masterwork: bool = false) -> void:
	if kind == "ability" or kind == "item_healing" or kind == "item_revival":
		_targeting_kind = kind
		_targeting_masterwork = masterwork
		_command_status.text = "Right-click a valid target or position"
		return
	_send_command({"kind": kind, "actor_ids": [_selected_ids[0]]})


func _on_ability_auto_toggled(enabled: bool) -> void:
	_send_command({"kind": "set_ability_auto", "actor_ids": [_selected_ids[0]], "value": enabled})


func _on_auto_heal_toggled(enabled: bool) -> void:
	var policies: Dictionary = _snapshot.get("policies", {}) as Dictionary
	_send_command({"kind": "set_item_auto", "actor_ids": [_selected_ids[0]], "value": {"auto_heal": enabled, "auto_revive": bool(policies.get("auto_revive", true))}})


func _on_auto_revive_toggled(enabled: bool) -> void:
	var policies: Dictionary = _snapshot.get("policies", {}) as Dictionary
	_send_command({"kind": "set_item_auto", "actor_ids": [_selected_ids[0]], "value": {"auto_heal": bool(policies.get("auto_heal", true)), "auto_revive": enabled}})


func _on_stance_selected(index: int) -> void:
	var stances: Array[String] = ["advance", "stay_together", "defend", "protect"]
	_send_command({"kind": "set_stance", "actor_ids": _selected_ids.duplicate(), "value": stances[index]})


func _on_squad_button_pressed(squad_index: int) -> void:
	_select_squad(squad_index)


func _select_squad(squad_index: int) -> void:
	var squads: Array = _snapshot.get("squads", []) as Array
	if squad_index < 0 or squad_index >= squads.size() or not squads[squad_index] is Dictionary:
		return
	var squad: Dictionary = squads[squad_index] as Dictionary
	# Snapshot JSON keeps hero_ids dynamically typed until the Array check below.
	var raw_ids: Variant = squad.get("hero_ids", [])
	if not raw_ids is Array:
		return
	_selected_ids.clear()
	for actor: Variant in _snapshot.get("actors", []) as Array:
		if actor is Dictionary:
			var actor_dictionary: Dictionary = actor as Dictionary
			if str(actor_dictionary.get("hero_id", "")) in raw_ids and str(actor_dictionary.get("life", "")) == "alive":
				_selected_ids.append(str(actor_dictionary.get("id", "")))
	var now: float = Time.get_ticks_msec() / 1000.0
	if _last_squad_key == squad_index and now - _last_squad_time <= SQUAD_DOUBLE_TAP_SECONDS:
		_focus_selection()
	_last_squad_key = squad_index
	_last_squad_time = now
	_refresh_selection_presentation()


func _focus_selection() -> void:
	# ig-gy0.8: the follow owns the rig; the squad is still selected, only the camera move is skipped.
	if _following():
		return
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for actor_id: String in _selected_ids:
		if _unit_views.has(actor_id):
			total += _unit_views[actor_id].global_position
			count += 1
	if count > 0:
		_camera_rig.global_position = Vector3(total.x / float(count), 0.0, total.z / float(count))


func _sync_selected_visuals() -> void:
	for actor_id: String in _unit_views:
		_unit_views[actor_id].set_selected(actor_id in _selected_ids)


func _update_camera_pan(delta: float) -> void:
	if _has_editable_focus() or _victory_banner.visible or _following():
		return
	var input: Vector2 = Input.get_vector("rts_pan_left", "rts_pan_right", "rts_pan_forward", "rts_pan_back")
	if Input.is_action_pressed("rts_additive_select") and Input.is_action_pressed("rts_pan_left"):
		input.x = maxf(input.x, 0.0)
	if input == Vector2.ZERO:
		return
	_camera_rig.global_position = _bounded(_camera_rig.global_position + Vector3(input.x, 0.0, input.y) * PAN_SPEED * delta)


## point on the ground plane, kept inside the zone's camera bounds.
func _bounded(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -_camera_bounds, _camera_bounds), 0.0, clampf(point.z, -_camera_bounds, _camera_bounds))


## Whether the camera follows the pilot now: follow is on and a hero is piloted (a snapshot can clear the pilot without
## _set_piloted, and a stale flag must not lock the pan).
func _following() -> bool:
	return _follow_pilot and not _piloted_id.is_empty()


## ig-gy0.8: the rig takes the pilot view's x and z, with no lerp: the unit view already glides between snapshots.
# ponytail: this reads the pilot view's previous-frame spot (the parent's _process runs before the unit's glide,
# battle_unit_view.gd:294), so the rig trails one frame while the hero glides. If the owner sees a wobble, give unit
# views an earlier process_priority.
func _follow_pilot_camera() -> void:
	if _following() and _unit_views.has(_piloted_id):
		_camera_rig.global_position = _bounded(_unit_views[_piloted_id].global_position)


## Whether nothing owns the command line: no checkpoint or command error, no command mode, targeting or armed aim. The
## follow status is written only then (render, F and _set_piloted all ask here).
func _command_line_idle() -> bool:
	return (
		str(_snapshot.get("checkpoint_error", "")).is_empty()
		and str(_snapshot.get("last_command_error", "")).is_empty()
		and (_mode != "practice" or _practice_command_error.is_empty())
		and _command_mode.is_empty()
		and _targeting_kind.is_empty()
		and _pilot_aim_skill.is_empty()
	)


## The command line when nothing else is asked of the player: blank, or while piloting whether the camera follows.
func _follow_status() -> String:
	if _piloted_id.is_empty():
		return ""
	return "Follow on (F)" if _follow_pilot else "Follow off (F)"


func _has_editable_focus() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox or focus is TextEdit or focus is CodeEdit


func _update_drag_box() -> void:
	if not _dragging:
		return
	var drag_distance: float = _drag_start.distance_squared_to(_drag_current)
	if drag_distance < DRAG_THRESHOLD_SQUARED:
		return
	_selection_box.visible = true
	_selection_box.position = Vector2(minf(_drag_start.x, _drag_current.x), minf(_drag_start.y, _drag_current.y))
	_selection_box.size = Vector2(absf(_drag_start.x - _drag_current.x), absf(_drag_start.y - _drag_current.y))


func _set_paused(paused: bool) -> void:
	if _battle_ended:
		return
	_pause_requested = paused
	if _mode == "live" and _controller != null:
		_controller.call("set_battle_paused", _order_id, paused)
	_pause_button.text = "Resume" if paused else "Pause"


func _is_paused() -> bool:
	return _pause_requested


func _bind_hud() -> void:
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_exit_button.pressed.connect(_on_exit_button_pressed)
	_stance_picker.item_selected.connect(_on_stance_selected)
	_help_panel.visible = false


func _on_pause_button_pressed() -> void:
	_set_paused(not _is_paused())


func _on_exit_button_pressed() -> void:
	leave_requested.emit(_order_id)
	_release_live_binding()
	SceneRouter.go_to(SceneRouter.HUB)


func _exit_tree() -> void:
	_release_live_binding()


func _release_live_binding() -> void:
	if _mode == "live" and _controller != null:
		if _pause_requested:
			_controller.call("set_battle_paused", _order_id, false)
		_pause_requested = false
		# ig-gy0.6: piloting is view state; leaving the view gives the hero back.
		if not _piloted_id.is_empty():
			_controller.call("set_battle_piloted", _order_id, "")
		var callback := Callable(self, "_on_battle_changed")
		if _controller.has_signal("battle_changed") and _controller.is_connected("battle_changed", callback):
			_controller.disconnect("battle_changed", callback)
	_piloted_id = ""
	_follow_pilot = false
	_clear_owned_router_payload()


func _clear_owned_router_payload() -> void:
	if not _owns_router_payload:
		return
	var matches_owned_payload: bool = false
	if _router_payload_kind == "live":
		matches_owned_payload = SceneRouter.battle_order_id == _router_payload_order_id
	elif _router_payload_kind == "practice":
		matches_owned_payload = SceneRouter.battle_order_id.is_empty() and SceneRouter.practice_zone != null and str(SceneRouter.practice_zone.zone_id) == _router_payload_zone_id and ",".join(_practice_payload_hero_ids(SceneRouter.practice_team)) == _router_payload_order_id
	if matches_owned_payload:
		SceneRouter.clear_battle_payload()
	_owns_router_payload = false
	_router_payload_kind = ""
	_router_payload_order_id = ""
	_router_payload_zone_id = ""


func _practice_payload_hero_ids(team: Array[Hero]) -> Array[String]:
	var hero_ids: Array[String] = []
	for hero: Hero in team:
		hero_ids.append(hero.instance_id)
	return hero_ids


func _bounds_for_zone(zone_id: String) -> float:
	if zone_id == "fallen_citadel":
		return 35.0
	if zone_id == "frontier_march":
		return 50.0
	return 20.0


func _camera_size_for_zone(zone_id: String) -> float:
	if zone_id == "fallen_citadel":
		return 44.0
	if zone_id == "frontier_march":
		return 60.0
	return STANDARD_CAMERA_SIZE


func _format_time(seconds: float) -> String:
	var total_seconds: int = maxi(0, ceili(seconds))
	return "%02d:%02d" % [floori(float(total_seconds) / 60.0), posmod(total_seconds, 60)]


func _build_battlefield() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "BattleWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = ENVIRONMENT_COLOR
	world_environment.environment = environment
	add_child(world_environment)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = FIELD_COLOR
	ground_material.roughness = 1.0
	_ground.material_override = ground_material
	var zone_id: String = str(_snapshot.get("zone_id", ""))
	_camera_zone_id = zone_id
	_camera_bounds = _bounds_for_zone(zone_id)
	_camera_rig.position = Vector3(0.0, 0.0, -2.0)
	_camera.position = Vector3(0.0, 32.0, 24.0)
	_camera.look_at(_camera_rig.global_position, Vector3.UP)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _camera_size_for_zone(zone_id)
	_resize_ground()
	_add_boundary_lines()
	_vfx = BattleVfx.new()
	_vfx.name = "BattleVfx"
	add_child(_vfx)


func _resize_ground() -> void:
	var plane: PlaneMesh = _ground.mesh as PlaneMesh
	if plane != null:
		plane.size = Vector2(_camera_bounds * 4.0, _camera_bounds * 4.0)
	for side: int in 4:
		var line: MeshInstance3D = get_node_or_null("Boundary_%d" % side) as MeshInstance3D
		if line == null:
			continue
		var box: BoxMesh = line.mesh as BoxMesh
		box.size = Vector3(_camera_bounds * 2.0, 0.08, 0.12) if side < 2 else Vector3(0.12, 0.08, _camera_bounds * 2.0)
		line.position = Vector3(0.0, 0.04, -_camera_bounds if side == 0 else _camera_bounds if side == 1 else 0.0)
		if side >= 2:
			line.position.x = -_camera_bounds if side == 2 else _camera_bounds
	_update_grid_lines()


func _add_boundary_lines() -> void:
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = FIELD_LINE
	for side: int in 4:
		var line := MeshInstance3D.new()
		line.name = "Boundary_%d" % side
		var box := BoxMesh.new()
		box.size = Vector3(_camera_bounds * 2.0, 0.08, 0.12) if side < 2 else Vector3(0.12, 0.08, _camera_bounds * 2.0)
		line.mesh = box
		line.material_override = line_material
		line.position = Vector3(0.0, 0.04, -_camera_bounds if side == 0 else _camera_bounds if side == 1 else 0.0)
		if side >= 2:
			line.position.x = -_camera_bounds if side == 2 else _camera_bounds
		add_child(line)
	_resize_ground()
	_create_grid_lines()
	_update_grid_lines()


func _create_grid_lines() -> void:
	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = FIELD_GRID
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for axis_index: int in 2:
		for step_index: int in range(-20, 21):
			var grid_line := MeshInstance3D.new()
			grid_line.name = "Grid_%d_%d" % [axis_index, step_index]
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			grid_line.mesh = box
			grid_line.material_override = grid_material
			grid_line.position.y = 0.012
			add_child(grid_line)
			_grid_lines.append(grid_line)


func _update_grid_lines() -> void:
	if _grid_lines.is_empty():
		return
	var apron: float = _camera_bounds * 2.0
	var line_index: int = 0
	for axis_index: int in 2:
		for step_index: int in range(-20, 21):
			var grid_line: MeshInstance3D = _grid_lines[line_index]
			var box: BoxMesh = grid_line.mesh as BoxMesh
			var coordinate: float = float(step_index * 5)
			box.size = Vector3(apron * 2.0, 0.012, 0.018) if axis_index == 0 else Vector3(0.018, 0.012, apron * 2.0)
			grid_line.position.x = coordinate if axis_index == 1 else 0.0
			grid_line.position.z = coordinate if axis_index == 0 else 0.0
			line_index += 1


func _refresh_selection_presentation() -> void:
	_update_selected_panel()
	_update_pilot_bar()
	_sync_selected_visuals()


func _build_hud() -> void:
	_hud.theme = GAME_THEME
	var top_bar: PanelContainer = %TopBar
	top_bar.add_theme_stylebox_override("panel", _style(UI_INK, UI_BRASS))
	var bottom_panel: PanelContainer = %CommandPanel
	bottom_panel.add_theme_stylebox_override("panel", _style(UI_INK, UI_BRASS))
	_selected_panel.add_theme_stylebox_override("panel", _style(UI_INK, UI_BRASS))
	_help_panel.add_theme_stylebox_override("panel", _style(UI_INK, UI_BRASS))
	%PauseButton.add_theme_color_override("font_color", UI_BRASS)
	%ExitButton.add_theme_color_override("font_color", ENEMY_COLOR)
	for stance: String in ["advance", "stay_together", "defend", "protect"]:
		_stance_picker.add_item(stance.replace("_", " ").capitalize())
	_build_selected_controls()
	%HelpButton.pressed.connect(func() -> void: _help_panel.visible = not _help_panel.visible)
	%AutoBattle.toggled.connect(_on_auto_battle_toggled)
	%AttackMoveButton.pressed.connect(_on_attack_move_button_pressed)
	_build_pilot_bar()
	# ig-0oj: a clicked button would keep focus, and Space (rts_pause, also ui_accept) would press it again.
	# The squad row's buttons come later and get the same line; the victory OK keeps its focus.
	for control: Node in _hud.find_children("*", "BaseButton", true, false):
		(control as BaseButton).focus_mode = Control.FOCUS_NONE
	_build_victory_banner()


## A dim backdrop that takes every click, and an engraved plate in the middle: a gold frame around an
## inset frame, VICTORY in big raised letters, the countdown line and OK (the Exit path home).
func _build_victory_banner() -> void:
	_victory_banner = ColorRect.new()
	_victory_banner.name = "VictoryBanner"
	_victory_banner.color = VICTORY_BACKDROP
	_victory_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_victory_banner.visible = false
	_hud.add_child(_victory_banner)
	_victory_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var plate := PanelContainer.new()
	plate.name = "Plate"
	plate.anchor_left = 0.25
	plate.anchor_right = 0.75
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	var frame: StyleBoxFlat = _plate_style(VICTORY_PLATE, VICTORY_GOLD, 6, 14, 10.0)
	frame.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	frame.shadow_size = 18
	frame.shadow_offset = Vector2(0.0, 6.0)
	plate.add_theme_stylebox_override("panel", frame)
	_victory_banner.add_child(plate)
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", _plate_style(VICTORY_INNER, VICTORY_GOLD.darkened(0.35), 2, 8, 24.0))
	plate.add_child(inset)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	inset.add_child(rows)
	var title := Label.new()
	title.name = "VictoryTitle"
	title.text = "VICTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", VICTORY_LETTERS)
	title.add_theme_color_override("font_outline_color", VICTORY_INK)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	rows.add_child(title)
	_victory_line = Label.new()
	_victory_line.name = "VictoryLine"
	_victory_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_victory_line.add_theme_font_size_override("font_size", 24)
	_victory_line.add_theme_color_override("font_color", VICTORY_LETTERS.lightened(0.3))
	_victory_line.add_theme_color_override("font_outline_color", VICTORY_INK)
	_victory_line.add_theme_constant_override("outline_size", 4)
	rows.add_child(_victory_line)
	_victory_ok = Button.new()
	_victory_ok.name = "VictoryOk"
	_victory_ok.text = "OK"
	_victory_ok.custom_minimum_size = Vector2(160.0, 52.0)
	_victory_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_victory_ok.add_theme_font_size_override("font_size", 24)
	_victory_ok.add_theme_color_override("font_color", VICTORY_LETTERS)
	_victory_ok.pressed.connect(_on_exit_button_pressed)
	# Focus stays on OK: Tab and the arrows never reach the buttons under the backdrop.
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_victory_ok.set_focus_neighbor(side, ^".")
	_victory_ok.focus_next = ^"."
	_victory_ok.focus_previous = ^"."
	rows.add_child(_victory_ok)


func _plate_style(fill: Color, border: Color, border_width: int, radius: int, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


func _build_selected_controls() -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	_skills_row.add_child(actions)
	_selected_ability_button = _command_button(actions, "Skill", "ability")
	_selected_ability_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for supply_kind: String in BattleState.SUPPLY_KINDS:
		var regular: String = supply_kind.trim_suffix(BattleState.MASTERWORK_SUFFIX)
		var masterwork: bool = regular != supply_kind
		var label: String = ("Heal" if regular == "healing" else "Revive") + ("+" if masterwork else "")
		var button: Button = _command_button(actions, label, "item_" + regular, masterwork)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_item_buttons[supply_kind] = button
	var policies := HBoxContainer.new()
	policies.add_theme_constant_override("separation", 2)
	_skills_row.add_child(policies)
	_selected_ability_auto = CheckButton.new()
	_selected_ability_auto.text = "Skill Auto"
	_selected_ability_auto.toggled.connect(_on_ability_auto_toggled)
	policies.add_child(_selected_ability_auto)
	_selected_auto_heal = CheckButton.new()
	_selected_auto_heal.text = "Auto Heal"
	_selected_auto_heal.toggled.connect(_on_auto_heal_toggled)
	policies.add_child(_selected_auto_heal)
	_selected_auto_revive = CheckButton.new()
	_selected_auto_revive.text = "Auto Revive"
	_selected_auto_revive.toggled.connect(_on_auto_revive_toggled)
	policies.add_child(_selected_auto_revive)




func _on_auto_battle_toggled(enabled: bool) -> void:
	_send_command({"kind": "set_auto_battle", "actor_ids": _all_living_ally_ids(), "value": enabled})


func _on_attack_move_button_pressed() -> void:
	_command_mode = "attack_move"
	_command_status.text = "Attack-move: right-click a point or target"


## ig-gy0.6: the Take Control button and the hotbar of the piloted hero. The bar sits above the command status,
## its buttons take no focus (Space still pauses after a click), and it shows only while a pilot is alive.
func _build_pilot_bar() -> void:
	_take_control_button = Button.new()
	_take_control_button.name = "TakeControlButton"
	_take_control_button.text = "Take Control (T)"
	_take_control_button.pressed.connect(_on_take_control_pressed)
	%AttackMoveButton.get_parent().add_child(_take_control_button)
	_pilot_bar = PanelContainer.new()
	_pilot_bar.name = "PilotBar"
	_pilot_bar.visible = false
	_pilot_bar.anchor_left = 0.5
	_pilot_bar.anchor_right = 0.5
	_pilot_bar.anchor_top = 1.0
	_pilot_bar.anchor_bottom = 1.0
	_pilot_bar.offset_left = -360.0
	_pilot_bar.offset_right = 360.0
	_pilot_bar.offset_top = -272.0
	_pilot_bar.offset_bottom = -210.0
	_pilot_bar.add_theme_stylebox_override("panel", _style(UI_INK, UI_BRASS))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pilot_bar.add_child(scroll)
	_pilot_slots = HBoxContainer.new()
	_pilot_slots.add_theme_constant_override("separation", 4)
	scroll.add_child(_pilot_slots)
	_hud.add_child(_pilot_bar)


## The pick is the first living ally selected. Pressing it again (or with nobody else picked) gives the pilot
## back to the AI; picking another switches. The pilot becomes the only selection, so right-clicks order it.
func _on_take_control_pressed() -> void:
	if _battle_ended:
		return
	var pick: String = ""
	for actor_id: String in _selected_ids:
		var data: Dictionary = _actor_data(actor_id)
		if str(data.get("faction", "")) == "ally" and str(data.get("life", "")) == BattleActor.LIFE_ALIVE:
			pick = actor_id
			break
	if not _piloted_id.is_empty() and (pick.is_empty() or pick == _piloted_id):
		_set_piloted("")
	elif pick.is_empty():
		_command_status.text = "Select a hero to take control of"
	else:
		_selected_ids.clear()
		_selected_ids.append(pick)
		_set_piloted(pick)
		_refresh_selection_presentation()


func _set_piloted(actor_id: String) -> void:
	if _piloted_id == actor_id:
		return
	_piloted_id = actor_id
	_follow_pilot = not actor_id.is_empty()
	_pilot_aim_skill = ""
	if _mode == "live" and _controller != null:
		_controller.call("set_battle_piloted", _order_id, actor_id)
	elif _mode == "practice" and _practice_state != null:
		_practice_state.piloted_id = actor_id
	_update_pilot_bar()
	# A paused practice renders nothing, so the idle line is refreshed here (after the aim is cleared).
	if _command_line_idle():
		_command_status.text = _follow_status()


func _actor_data(actor_id: String) -> Dictionary:
	for raw_actor: Variant in _snapshot.get("actors", []) as Array:
		if raw_actor is Dictionary and str((raw_actor as Dictionary).get("id", "")) == actor_id:
			return raw_actor as Dictionary
	return {}


## The hotbar's skills in bar order: everything the pilot can fire (abilities and weaponskills, Off ones too).
func _pilot_skills(pilot: Dictionary) -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for raw_entry: Variant in pilot.get("skills", []) as Array:
		var skill: AbilityDefinition = BattleSimulation.ABILITIES.get(str((raw_entry as Dictionary).get("id", ""))) as AbilityDefinition
		if skill != null and skill.kind != "passive":
			result.append(skill)
	return result


func _update_pilot_bar() -> void:
	if _pilot_bar == null:
		return
	_take_control_button.text = "Release Control (T)" if not _piloted_id.is_empty() else "Take Control (T)"
	var pilot: Dictionary = _actor_data(_piloted_id) if not _piloted_id.is_empty() else {}
	_pilot_bar.visible = not pilot.is_empty() and not _battle_ended
	if not _pilot_bar.visible:
		return
	var skills: Array[AbilityDefinition] = _pilot_skills(pilot)
	var key_parts: PackedStringArray = [_piloted_id]
	for skill: AbilityDefinition in skills:
		key_parts.append(str(skill.skill_id))
	var structure_key: String = "|".join(key_parts)
	if structure_key != _pilot_bar_key:
		_pilot_bar_key = structure_key
		for child: Node in _pilot_slots.get_children():
			_pilot_slots.remove_child(child)
			child.queue_free()
		_pilot_buttons.clear()
		for slot: int in skills.size():
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(118.0, 46.0)
			button.pressed.connect(_fire_pilot_slot.bind(slot))
			_pilot_slots.add_child(button)
			_pilot_buttons.append(button)
	var cooldowns: Dictionary = pilot.get("skill_cooldowns", {}) as Dictionary
	var next_swing: String = str((pilot.get("effect_state", {}) as Dictionary).get("next_swing_skill", ""))
	for slot: int in skills.size():
		var skill: AbilityDefinition = skills[slot]
		var cooldown: float = float(cooldowns.get(str(skill.skill_id), 0.0))
		var key_label: String = "%d  " % ((slot + 1) % 10) if slot < 10 else ""
		var detail: String = "%.1fs" % cooldown if cooldown > 0.0 else "next swing" if str(skill.skill_id) == next_swing else ""
		_pilot_buttons[slot].text = "%s%s\n%s" % [key_label, skill.display_name, detail]
		_pilot_buttons[slot].disabled = cooldown > 0.0
		_pilot_buttons[slot].tooltip_text = skill.display_name


func _fire_pilot_slot(slot: int) -> void:
	var skills: Array[AbilityDefinition] = _pilot_skills(_actor_data(_piloted_id))
	if slot >= 0 and slot < skills.size():
		_fire_pilot_skill(skills[slot])


## An area skill waits for a right-click (the ground point, or the unit clicked); any other fires now and the
## simulation aims it as a chain step aims.
func _fire_pilot_skill(skill: AbilityDefinition) -> void:
	if _battle_ended or _piloted_id.is_empty():
		return
	if _needs_ground_click(skill):
		_pilot_aim_skill = str(skill.skill_id)
		_command_status.text = "%s: right-click a point or target" % skill.display_name
		return
	_pilot_aim_skill = ""
	_send_command({"kind": "use_skill", "actor_ids": [_piloted_id], "skill_id": str(skill.skill_id)})


static func _needs_ground_click(skill: AbilityDefinition) -> bool:
	if skill.kind != "ability" or skill.self_centered:
		return false
	return not BattleSimulation._effect_of(skill, "zone").is_empty() \
			or not BattleSimulation._effect_of(skill, "wall").is_empty() \
			or str(BattleSimulation._effect_of(skill, "damage").get("area", "")) == "circle"


func _all_living_ally_ids() -> Array[String]:
	var actor_ids: Array[String] = []
	for raw_actor: Variant in _snapshot.get("actors", []) as Array:
		if raw_actor is Dictionary:
			var actor: Dictionary = raw_actor as Dictionary
			if str(actor.get("faction", "")) == "ally" and str(actor.get("life", "")) == "alive":
				actor_ids.append(str(actor.get("id", "")))
	return actor_ids


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _array_vector2(value: Variant) -> Vector2:
	# Objective positions cross the serialized snapshot boundary as two-number arrays.
	if value is Array and (value as Array).size() == 2:
		var point: Array = value as Array
		return Vector2(float(point[0]), float(point[1]))
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO


func _new_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
