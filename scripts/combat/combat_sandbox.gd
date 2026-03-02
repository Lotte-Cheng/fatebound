extends Node2D

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const ROOMS_PATH := "res://data/rooms.json"
const MAIN_SCENE_PATH := "res://scenes/Main.tscn"

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 16.0
const BULLET_RADIUS := 4.0
const MIN_EFFECT_KEYS := ["hp", "atk", "def", "corruption", "keys"]

signal combat_finished(report: Dictionary)

@onready var _stats_label: Label = $CanvasLayer/HUDPanel/VBox/StatsLabel
@onready var _threshold_label: Label = $CanvasLayer/HUDPanel/VBox/ThresholdLabel
@onready var _result_label: Label = $CanvasLayer/HUDPanel/VBox/ResultLabel
@onready var _log_output: RichTextLabel = $CanvasLayer/HUDPanel/VBox/LogOutput
@onready var _reset_button: Button = $CanvasLayer/HUDPanel/VBox/ButtonRow/ResetButton
@onready var _back_button: Button = $CanvasLayer/HUDPanel/VBox/ButtonRow/BackButton
@onready var _hud_panel: PanelContainer = $CanvasLayer/HUDPanel

var _room_cfg: Dictionary = {}
var _player_state: Dictionary = {}
var _initial_state: Dictionary = {}
var _embedded_mode := false

var _player_pos := Vector2.ZERO
var _enemy_pos := Vector2.ZERO
var _enemy_hp := 0
var _enemy_atk := 0
var _enemy_def := 0
var _enemy_attack_cd := 0.0

var _min_atk := 0
var _min_def := 0
var _corruption_threshold := 999
var _key_drop_on_win := 0

var _atk_penalty_damage := 0
var _def_penalty_damage := 0
var _enemy_bonus_attack := 0

var _shoot_cooldown := 0.0
var _shoot_interval := 0.22

var _logs: Array[String] = []
var _bullets: Array[Dictionary] = []
var _battle_over := false
var _battle_result := ""
var _result_emitted := false

func _ready() -> void:
	_setup_ui_font()
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	if _room_cfg.is_empty() or _player_state.is_empty():
		_load_first_combat_room()
	_initial_state = _player_state.duplicate(true)
	_back_button.visible = not _embedded_mode
	_start_battle()

func setup_for_room(room_cfg: Dictionary, player_state: Dictionary, options: Dictionary = {}) -> void:
	_room_cfg = room_cfg.duplicate(true)
	_player_state = player_state.duplicate(true)
	_initial_state = _player_state.duplicate(true)
	_embedded_mode = bool(options.get("embedded", true))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.keycode == KEY_R:
			_start_battle()
			return

	if _battle_over:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_try_fire(mouse_event.position)

func _process(delta: float) -> void:
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	if _battle_over:
		_update_hud()
		queue_redraw()
		return

	_move_player(delta)
	_update_bullets(delta)
	_update_enemy(delta)
	_check_battle_end()
	_update_hud()
	queue_redraw()

func _draw() -> void:
	if _player_state.is_empty():
		return
	draw_circle(_player_pos, PLAYER_RADIUS, Color(0.2, 0.9, 0.5))

	if _enemy_hp > 0:
		draw_circle(_enemy_pos, ENEMY_RADIUS, Color(0.95, 0.25, 0.25))

	for bullet_variant in _bullets:
		var bullet: Dictionary = bullet_variant
		draw_circle(bullet.get("pos", Vector2.ZERO), BULLET_RADIUS, Color(1.0, 0.9, 0.3))

func _load_first_combat_room() -> void:
	var rooms_cfg: Dictionary = DataLoaderScript.load_json(ROOMS_PATH)
	_player_state = rooms_cfg.get("initial_state", {}).duplicate(true)
	_room_cfg = {}

	for room_variant in rooms_cfg.get("demo_rooms", []):
		var room: Dictionary = room_variant
		if String(room.get("type", "")) == "combat_room":
			_room_cfg = room.duplicate(true)
			break

	if _room_cfg.is_empty():
		push_error("CombatSandbox: combat_room not found in rooms.json")

func _start_battle() -> void:
	_player_state = _initial_state.duplicate(true)
	_logs.clear()
	_bullets.clear()
	_battle_over = false
	_battle_result = ""
	_result_emitted = false
	_result_label.text = "战斗进行中..."

	_player_pos = get_viewport_rect().size * Vector2(0.25, 0.5)
	_enemy_pos = get_viewport_rect().size * Vector2(0.72, 0.5)
	_enemy_hp = int(_room_cfg.get("enemy_hp", 6))
	_enemy_atk = int(_room_cfg.get("enemy_atk", 3))
	_enemy_def = int(_room_cfg.get("enemy_def", 1))
	_enemy_attack_cd = 0.0

	_min_atk = int(_room_cfg.get("min_atk", 0))
	_min_def = int(_room_cfg.get("min_def", 0))
	_corruption_threshold = int(_room_cfg.get("corruption_threshold", 999))
	_key_drop_on_win = int(_room_cfg.get("key_drop_on_win", 0))

	_atk_penalty_damage = 0
	_def_penalty_damage = 0
	_enemy_bonus_attack = 0
	_shoot_cooldown = 0.0
	_shoot_interval = 0.22

	_apply_threshold_modifiers()
	_refresh_log_text()

func _apply_threshold_modifiers() -> void:
	var player_atk := int(_player_state.get("atk", 0))
	var player_def := int(_player_state.get("def", 0))
	var player_corruption := int(_player_state.get("corruption", 0))

	_append_log("战斗阈值：min_atk=%d min_def=%d corruption_threshold=%d" % [
		_min_atk, _min_def, _corruption_threshold
	])
	_append_log("敌人：hp=%d atk=%d def=%d" % [_enemy_hp, _enemy_atk, _enemy_def])
	_append_log("玩家：hp=%d atk=%d def=%d corruption=%d keys=%d" % [
		int(_player_state.get("hp", 0)),
		player_atk,
		player_def,
		player_corruption,
		int(_player_state.get("keys", 0))
	])

	if player_atk < _min_atk:
		_atk_penalty_damage = 1
		_shoot_interval = 0.34
		_apply_damage_to_player(1, "ATK 未达标，开场受创")
		_append_log("ATK 未达标：子弹伤害 -1，攻速下降")

	if player_def < _min_def:
		_def_penalty_damage = 1
		_append_log("DEF 未达标：敌人每次命中额外伤害 +1")

	if player_corruption >= _corruption_threshold:
		_enemy_bonus_attack = 1
		_append_log("Corruption 超阈：敌人强化，ATK +1")

func _move_player(delta: float) -> void:
	var axis := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		axis.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		axis.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		axis.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		axis.y += 1.0
	axis = axis.normalized()

	# Fallback to InputMap actions when available.
	if axis == Vector2.ZERO:
		axis = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	var speed := 240.0
	_player_pos += axis * speed * delta
	_player_pos = _player_pos.clamp(Vector2(24, 24), get_viewport_rect().size - Vector2(24, 24))

func _try_fire(target_pos: Vector2) -> void:
	if _shoot_cooldown > 0.0:
		return
	_shoot_cooldown = _shoot_interval

	var dir := (target_pos - _player_pos).normalized()
	if dir == Vector2.ZERO:
		return
	var player_atk := int(_player_state.get("atk", 0))
	var damage := maxi(1, player_atk - _enemy_def - _atk_penalty_damage)

	_bullets.append({
		"pos": _player_pos,
		"vel": dir * 760.0,
		"ttl": 1.0,
		"damage": damage
	})

func _update_bullets(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for bullet_variant in _bullets:
		var bullet: Dictionary = bullet_variant
		var pos: Vector2 = bullet.get("pos", Vector2.ZERO) + bullet.get("vel", Vector2.ZERO) * delta
		var ttl := float(bullet.get("ttl", 0.0)) - delta
		bullet["pos"] = pos
		bullet["ttl"] = ttl

		if _enemy_hp > 0 and pos.distance_to(_enemy_pos) <= ENEMY_RADIUS + BULLET_RADIUS:
			var dmg := int(bullet.get("damage", 1))
			_enemy_hp = maxi(0, _enemy_hp - dmg)
			_append_log("命中敌人：-%d HP（敌人剩余 %d）" % [dmg, _enemy_hp])
			continue

		if ttl > 0.0 and _inside_viewport(pos):
			alive.append(bullet)
	_bullets = alive

func _update_enemy(delta: float) -> void:
	if _enemy_hp <= 0:
		return

	var dir := (_player_pos - _enemy_pos).normalized()
	_enemy_pos += dir * 110.0 * delta
	_enemy_pos = _enemy_pos.clamp(Vector2(24, 24), get_viewport_rect().size - Vector2(24, 24))

	_enemy_attack_cd = maxf(0.0, _enemy_attack_cd - delta)
	if _enemy_pos.distance_to(_player_pos) <= PLAYER_RADIUS + ENEMY_RADIUS + 4.0 and _enemy_attack_cd <= 0.0:
		_enemy_attack_cd = 0.8
		var incoming := maxi(1, (_enemy_atk + _enemy_bonus_attack) - int(_player_state.get("def", 0)) + _def_penalty_damage)
		_apply_damage_to_player(incoming, "敌人近战命中")

func _apply_damage_to_player(amount: int, reason: String) -> void:
	if amount <= 0:
		return

	var before := int(_player_state.get("hp", 0))
	var after := maxi(0, before - amount)
	_player_state["hp"] = after
	_append_log("%s：HP %d -> %d (-%d)" % [reason, before, after, amount])

func _check_battle_end() -> void:
	if _battle_over:
		return
	if int(_player_state.get("hp", 0)) <= 0:
		_battle_over = true
		_battle_result = "失败：你倒下了。"
		_result_label.text = _battle_result
		_emit_embedded_result()
		return
	if _enemy_hp <= 0:
		_battle_over = true
		var key_gain := _key_drop_on_win
		if key_gain > 0:
			var before_keys := int(_player_state.get("keys", 0))
			var after_keys := before_keys + key_gain
			_player_state["keys"] = after_keys
			_append_log("战斗胜利掉落：Keys %d -> %d (+%d)" % [before_keys, after_keys, key_gain])
		_battle_result = "胜利：敌人已清除。"
		_result_label.text = _battle_result
		_emit_embedded_result()

func _update_hud() -> void:
	_stats_label.text = "玩家 HP %d | ATK %d | DEF %d | Corruption %d | Keys %d || 敌人 HP %d ATK %d DEF %d" % [
		int(_player_state.get("hp", 0)),
		int(_player_state.get("atk", 0)),
		int(_player_state.get("def", 0)),
		int(_player_state.get("corruption", 0)),
		int(_player_state.get("keys", 0)),
		_enemy_hp,
		_enemy_atk + _enemy_bonus_attack,
		_enemy_def
	]
	_threshold_label.text = "阈值判定：ATK>=%d DEF>=%d Corruption<%d" % [
		_min_atk,
		_min_def,
		_corruption_threshold
	]
	if _battle_over:
		_result_label.text = _battle_result + "（R 重置）"

func _append_log(line: String) -> void:
	_logs.append(line)
	if _logs.size() > 60:
		_logs.remove_at(0)
	_refresh_log_text()

func _refresh_log_text() -> void:
	_log_output.text = "\n".join(_logs)

func _inside_viewport(pos: Vector2) -> bool:
	var size: Vector2 = get_viewport_rect().size
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= size.x and pos.y <= size.y

func _on_reset_pressed() -> void:
	_start_battle()

func _on_back_pressed() -> void:
	if _embedded_mode:
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _emit_embedded_result() -> void:
	if not _embedded_mode:
		return
	if _result_emitted:
		return
	_result_emitted = true
	emit_signal("combat_finished", _build_combat_report())

func _build_combat_report() -> Dictionary:
	var delta := _build_delta_from_state_change(_initial_state, _player_state)
	var effect_stack: Array = []
	if not delta.is_empty():
		effect_stack.append({
			"source": "room",
			"id": "runtime_combat_delta",
			"label": "实时战斗结算",
			"effect": delta
		})

	var reward_rolls := int(_room_cfg.get("reward_rolls", 1))
	var curse_rolls := int(_room_cfg.get("curse_rolls", 1))
	var notes: Array[String] = []
	var tags: Array = ["runtime_combat"]
	if String(_battle_result).find("失败") != -1:
		reward_rolls = 0
		curse_rolls += 1
		notes.append("实时战斗失败：奖励归零，诅咒额外 +1")
		tags.append("combat_loss")
	else:
		notes.append("实时战斗胜利：按房间基础 reward/curse 继续规则抽取")
		tags.append("combat_win")

	return {
		"battle_result": _battle_result,
		"runtime_combat_result": {
			"reward_rolls": reward_rolls,
			"curse_rolls": curse_rolls,
			"effect_stack": effect_stack,
			"combat_log": _logs.duplicate(),
			"notes": notes,
			"tags": tags
		}
	}

func _build_delta_from_state_change(before_state: Dictionary, after_state: Dictionary) -> Dictionary:
	var delta := {}
	for key_variant in MIN_EFFECT_KEYS:
		var key: String = key_variant
		var before_v := int(before_state.get(key, 0))
		var after_v := int(after_state.get(key, 0))
		var diff := after_v - before_v
		if diff != 0:
			delta[key] = diff
	return delta

func _setup_ui_font() -> void:
	var font_file: FontFile = _find_cjk_font()
	if font_file == null:
		push_warning("CombatSandbox: No CJK font found, Chinese text may not render.")
		return

	var ui_theme := Theme.new()
	ui_theme.default_font = font_file
	ui_theme.default_font_size = 18
	_hud_panel.theme = ui_theme

func _find_cjk_font() -> FontFile:
	var common_paths: Array[String] = [
		"res://assets/fonts/HiraginoSansGB.ttc",
		"res://assets/fonts/NotoSansSC-Regular.ttf",
		"res://assets/fonts/SourceHanSansSC-Regular.otf",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
	]
	for path in common_paths:
		var file_font: FontFile = _load_font_from_path(path)
		if file_font == null:
			continue
		if file_font.has_char("命".unicode_at(0)) and file_font.has_char("A".unicode_at(0)):
			return file_font
	return null

func _load_font_from_path(path: String) -> FontFile:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var font_file := FontFile.new()
	var err := font_file.load_dynamic_font(path)
	if err != OK:
		return null
	return font_file
