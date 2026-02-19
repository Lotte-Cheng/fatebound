extends Node2D

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const DUNGEON_PATH := "res://data/dungeon_layout.json"

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 14.0
const BULLET_RADIUS := 4.0
const PLAYER_SPEED := 260.0
const BULLET_SPEED := 760.0
const ENEMY_BULLET_SPEED := 340.0
const TOUCH_HIT_INTERVAL := 0.35
const ENEMY_SPAWN_PADDING := ENEMY_RADIUS + 12.0
const ENEMY_MIN_PLAYER_DIST := 170.0
const ENEMY_MIN_ENEMY_DIST := ENEMY_RADIUS * 2.6
const ENEMY_SPAWN_ATTEMPTS := 28
const STATUE_INTERACT_RADIUS := 96.0

@onready var _hud_panel: PanelContainer = $CanvasLayer/HudPanel
@onready var _stats_label: Label = $CanvasLayer/HudPanel/VBox/StatsLabel
@onready var _room_label: Label = $CanvasLayer/HudPanel/VBox/RoomLabel
@onready var _hint_label: Label = $CanvasLayer/HudPanel/VBox/HintLabel
@onready var _marker_legend_label: Label = $CanvasLayer/HudPanel/VBox/MarkerLegendLabel
@onready var _pray_button: Button = $CanvasLayer/HudPanel/VBox/PrayButton
@onready var _prayer_panel: VBoxContainer = $CanvasLayer/HudPanel/VBox/PrayerPanel
@onready var _prayer_request_input: LineEdit = $CanvasLayer/HudPanel/VBox/PrayerPanel/PrayerRequestInput
@onready var _auto_request_button: Button = $CanvasLayer/HudPanel/VBox/PrayerPanel/PrayerButtonRow/AutoRequestButton
@onready var _ask_statue_button: Button = $CanvasLayer/HudPanel/VBox/PrayerPanel/PrayerButtonRow/AskStatueButton
@onready var _bless_option_a: Button = $CanvasLayer/HudPanel/VBox/PrayerPanel/BlessOptionA
@onready var _bless_option_b: Button = $CanvasLayer/HudPanel/VBox/PrayerPanel/BlessOptionB
@onready var _bless_option_c: Button = $CanvasLayer/HudPanel/VBox/PrayerPanel/BlessOptionC
@onready var _deity_response_output: RichTextLabel = $CanvasLayer/HudPanel/VBox/PrayerPanel/DeityResponseOutput
@onready var _restart_button: Button = $CanvasLayer/HudPanel/VBox/RestartButton
@onready var _minimap_grid: GridContainer = $CanvasLayer/HudPanel/VBox/MinimapGrid
@onready var _adjacent_preview_label: Label = $CanvasLayer/HudPanel/VBox/AdjacentPreviewLabel
@onready var _log_output: RichTextLabel = $CanvasLayer/HudPanel/VBox/LogOutput

var _rng := RandomNumberGenerator.new()

var _rooms_by_id: Dictionary = {}
var _room_ids_by_coord: Dictionary = {}
var _current_room_id := ""
var _start_room_id := ""
var _map_cols := 3
var _map_rows := 3
var _minimap_cells: Dictionary = {}

var _player_state: Dictionary = {}
var _player_pos := Vector2.ZERO
var _bullets: Array[Dictionary] = []
var _enemy_projectiles: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []

var _visited: Dictionary = {}
var _cleared: Dictionary = {}
var _prayed: Dictionary = {}
var _chest_opened: Dictionary = {}
var _unlocked_edges: Dictionary = {}
var _locked_edges: Dictionary = {}

var _logs: Array[String] = []
var _shoot_cooldown := 0.0
var _touch_hit_cooldown := 0.0
var _door_cooldown := 0.0
var _game_over := false
var _victory := false
var _debug_font: Font = null

func _ready() -> void:
	_setup_ui_font()
	_pray_button.pressed.connect(_on_pray_pressed)
	_auto_request_button.pressed.connect(_on_auto_request_pressed)
	_ask_statue_button.pressed.connect(_on_ask_statue_pressed)
	_bless_option_a.pressed.connect(func() -> void: _on_bless_option_pressed(0))
	_bless_option_b.pressed.connect(func() -> void: _on_bless_option_pressed(1))
	_bless_option_c.pressed.connect(func() -> void: _on_bless_option_pressed(2))
	_restart_button.pressed.connect(_on_restart_pressed)
	_boot_new_run()

func _boot_new_run() -> void:
	var cfg: Dictionary = DataLoaderScript.load_json(DUNGEON_PATH)
	if cfg.is_empty():
		push_error("DungeonRun: load dungeon_layout.json failed")
		return

	_rng.seed = int(cfg.get("seed", 1))
	_rooms_by_id.clear()
	_room_ids_by_coord.clear()
	_visited.clear()
	_cleared.clear()
	_prayed.clear()
	_chest_opened.clear()
	_unlocked_edges.clear()
	_locked_edges.clear()
	_bullets.clear()
	_enemy_projectiles.clear()
	_enemies.clear()
	_logs.clear()
	_deity_response_output.text = ""

	_map_cols = int((cfg.get("grid", {}) as Dictionary).get("cols", 3))
	_map_rows = int((cfg.get("grid", {}) as Dictionary).get("rows", 3))
	_start_room_id = String(cfg.get("start_room_id", ""))
	_player_state = (cfg.get("initial_state", {}) as Dictionary).duplicate(true)
	_player_state["hp"] = maxi(1, int(_player_state.get("hp", 20)))

	for room_variant in cfg.get("rooms", []):
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		if room_id.is_empty():
			continue
		_rooms_by_id[room_id] = room
		_room_ids_by_coord[_coord_key(int(room.get("x", 0)), int(room.get("y", 0)))] = room_id

	# Build edge-level lock map so locked passages are consistent in both directions.
	for room_id_variant in _rooms_by_id.keys():
		var room_id: String = String(room_id_variant)
		var room_data: Dictionary = _rooms_by_id[room_id]
		for exit_variant in room_data.get("exits", []):
			var exit_cfg: Dictionary = exit_variant
			if bool(exit_cfg.get("requires_key", false)):
				var to_room: String = String(exit_cfg.get("to", ""))
				if not to_room.is_empty():
					_locked_edges[_edge_key(room_id, to_room)] = true

	if not _rooms_by_id.has(_start_room_id):
		_start_room_id = String(_rooms_by_id.keys()[0]) if not _rooms_by_id.is_empty() else ""
	if _start_room_id.is_empty():
		push_error("DungeonRun: no rooms defined")
		return

	_build_minimap()
	_enter_room(_start_room_id, "")
	_append_log("新一轮开始：清理房间、选择路径、寻找钥匙并开启宝库。")
	_game_over = false
	_victory = false
	_shoot_cooldown = 0.0
	_touch_hit_cooldown = 0.0
	_door_cooldown = 0.0
	_update_ui()
	queue_redraw()

func _process(delta: float) -> void:
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_touch_hit_cooldown = maxf(0.0, _touch_hit_cooldown - delta)
	_door_cooldown = maxf(0.0, _door_cooldown - delta)

	if _game_over:
		_update_ui()
		queue_redraw()
		return

	_move_player(delta)
	_update_bullets(delta)
	_update_enemy_projectiles(delta)
	_update_enemies(delta)

	if _enemies.is_empty() and not bool(_cleared.get(_current_room_id, false)):
		_on_room_cleared()

	_try_room_transition()
	_update_ui()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _game_over and not _is_prayer_input_active():
			_try_fire(mb.position)

func _draw() -> void:
	var rect := _play_rect()
	draw_rect(rect, Color(0.09, 0.09, 0.12), true)
	draw_rect(rect, Color(0.4, 0.4, 0.45), false, 2.0)

	var room := _current_room()
	var room_cleared := bool(_cleared.get(_current_room_id, false))
	_draw_world_text(rect.position + Vector2(8, 20), "房间:%s" % String(room.get("type", "unknown")), Color(0.82, 0.86, 0.92))
	for exit_variant in room.get("exits", []):
		var exit_cfg: Dictionary = exit_variant
		var door_rect := _door_rect(String(exit_cfg.get("dir", "")))
		var to_room: String = String(exit_cfg.get("to", ""))
		var edge_key := _edge_key(_current_room_id, to_room)
		var requires_key := bool(_locked_edges.get(edge_key, false))
		var locked := requires_key and not bool(_unlocked_edges.get(edge_key, false))
		var color := Color(0.28, 0.28, 0.3)
		if room_cleared:
			color = Color(0.25, 0.6, 0.3) if not locked else Color(0.8, 0.45, 0.1)
		draw_rect(door_rect, color, true)
		var marker_text := "锁" if locked else "门"
		if requires_key:
			marker_text += "K"
		_draw_world_text(door_rect.get_center() + Vector2(-12, 5), marker_text, Color(0.98, 0.98, 0.98))

	if String(room.get("type", "")) == "prayer":
		var statue_pos := _statue_world_pos()
		draw_circle(statue_pos, 18.0, Color(0.45, 0.72, 1.0))
		draw_arc(statue_pos, STATUE_INTERACT_RADIUS, 0.0, TAU, 48, Color(0.45, 0.72, 1.0, 0.2), 2.0)
		_draw_world_text(statue_pos + Vector2(-22, -24), "神像", Color(0.82, 0.92, 1.0))
	if String(room.get("type", "")) == "chest" and not bool(_chest_opened.get(_current_room_id, false)):
		var chest_pos := rect.get_center() + Vector2(0.0, -40.0)
		draw_rect(Rect2(chest_pos - Vector2(12, 10), Vector2(24, 20)), Color(0.95, 0.82, 0.26), true)
		_draw_world_text(chest_pos + Vector2(-20, -18), "宝箱", Color(1.0, 0.92, 0.4))
	elif int(room.get("key_reward", 0)) > 0 and not room_cleared:
		_draw_world_text(rect.get_center() + Vector2(-28, -26), "钥匙奖励+%d" % int(room.get("key_reward", 0)), Color(1.0, 0.92, 0.35))

	for bullet_variant in _bullets:
		var bullet: Dictionary = bullet_variant
		draw_circle(bullet.get("pos", Vector2.ZERO), BULLET_RADIUS, Color(1.0, 0.95, 0.35))
	for shot_variant in _enemy_projectiles:
		var shot: Dictionary = shot_variant
		draw_circle(shot.get("pos", Vector2.ZERO), BULLET_RADIUS + 1.0, Color(1.0, 0.42, 0.42))

	for enemy_variant in _enemies:
		var enemy: Dictionary = enemy_variant
		var color := Color(0.92, 0.28, 0.28)
		var marker := "怪"
		if String(enemy.get("kind", "chaser")) == "shooter":
			color = Color(0.95, 0.55, 0.3)
			marker = "远"
		draw_circle(enemy.get("pos", Vector2.ZERO), ENEMY_RADIUS, color)
		_draw_world_text(enemy.get("pos", Vector2.ZERO) + Vector2(-9, -18), marker, Color(1.0, 1.0, 1.0))

	draw_circle(_player_pos, PLAYER_RADIUS, Color(0.25, 0.9, 0.52))
	_draw_world_text(_player_pos + Vector2(-10, -18), "你", Color(0.85, 1.0, 0.88))

func _move_player(delta: float) -> void:
	if _is_prayer_input_active():
		return
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

	_player_pos += axis * PLAYER_SPEED * delta
	var rect := _play_rect()
	_player_pos.x = clampf(_player_pos.x, rect.position.x + PLAYER_RADIUS, rect.end.x - PLAYER_RADIUS)
	_player_pos.y = clampf(_player_pos.y, rect.position.y + PLAYER_RADIUS, rect.end.y - PLAYER_RADIUS)

func _try_fire(target_pos: Vector2) -> void:
	if _shoot_cooldown > 0.0:
		return
	_shoot_cooldown = 0.2

	var dir := (target_pos - _player_pos).normalized()
	if dir == Vector2.ZERO:
		return
	var damage := maxi(1, int(_player_state.get("atk", 1)))
	_bullets.append({
		"pos": _player_pos,
		"vel": dir * BULLET_SPEED,
		"ttl": 1.1,
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

		var hit := false
		for i in range(_enemies.size()):
			var enemy: Dictionary = _enemies[i]
			if pos.distance_to(enemy.get("pos", Vector2.ZERO)) <= ENEMY_RADIUS + BULLET_RADIUS:
				var hp := int(enemy.get("hp", 1)) - int(bullet.get("damage", 1))
				enemy["hp"] = hp
				_enemies[i] = enemy
				hit = true
				if hp <= 0:
					_enemies.remove_at(i)
				break
		if hit:
			continue

		if ttl > 0.0 and _play_rect().has_point(pos):
			alive.append(bullet)
	_bullets = alive

func _update_enemy_projectiles(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for shot_variant in _enemy_projectiles:
		var shot: Dictionary = shot_variant
		var pos: Vector2 = shot.get("pos", Vector2.ZERO) + shot.get("vel", Vector2.ZERO) * delta
		var ttl := float(shot.get("ttl", 0.0)) - delta
		shot["pos"] = pos
		shot["ttl"] = ttl

		if pos.distance_to(_player_pos) <= PLAYER_RADIUS + BULLET_RADIUS + 1.0:
			_apply_damage_to_player(int(shot.get("damage", 1)), "被远程命中")
			continue
		if ttl > 0.0 and _play_rect().has_point(pos):
			alive.append(shot)
	_enemy_projectiles = alive

func _update_enemies(delta: float) -> void:
	var updated: Array[Dictionary] = []
	for enemy_variant in _enemies:
		var enemy: Dictionary = enemy_variant
		var pos: Vector2 = enemy.get("pos", Vector2.ZERO)
		var kind := String(enemy.get("kind", "chaser"))
		var speed := float(enemy.get("speed", 100.0))
		var atk := int(enemy.get("atk", 2))
		var shoot_cd := float(enemy.get("shoot_cd", 0.0))
		var to_player := _player_pos - pos
		var dist := maxf(0.001, to_player.length())
		var dir := to_player / dist

		if kind == "shooter":
			if dist > 220.0:
				pos += dir * speed * delta
			elif dist < 145.0:
				pos -= dir * speed * 0.8 * delta

			shoot_cd -= delta
			if shoot_cd <= 0.0:
				shoot_cd = 1.2
				_enemy_projectiles.append({
					"pos": pos,
					"vel": dir * ENEMY_BULLET_SPEED,
					"ttl": 1.6,
					"damage": atk
				})
		else:
			pos += dir * speed * delta

		pos = _clamp_in_play_rect(pos, ENEMY_RADIUS)

		if pos.distance_to(_player_pos) <= PLAYER_RADIUS + ENEMY_RADIUS + 2.0 and _touch_hit_cooldown <= 0.0:
			_touch_hit_cooldown = TOUCH_HIT_INTERVAL
			_apply_damage_to_player(atk, "被近战命中")

		enemy["pos"] = pos
		enemy["shoot_cd"] = shoot_cd
		updated.append(enemy)
	_enemies = updated

func _try_room_transition() -> void:
	if _door_cooldown > 0.0:
		return
	if not _enemies.is_empty():
		return

	var room := _current_room()
	for exit_variant in room.get("exits", []):
		var exit_cfg: Dictionary = exit_variant
		var door_rect := _door_rect(String(exit_cfg.get("dir", "")))
		if not door_rect.has_point(_player_pos):
			continue

		var target_room_id := String(exit_cfg.get("to", ""))
		var edge := _edge_key(_current_room_id, target_room_id)
		var requires_key := bool(_locked_edges.get(edge, false))
		if requires_key and not bool(_unlocked_edges.get(edge, false)):
			if int(_player_state.get("keys", 0)) <= 0:
				_append_log("该路径被神锁封印：需要钥匙。")
				_door_cooldown = 0.35
				return
			_player_state["keys"] = int(_player_state.get("keys", 0)) - 1
			_unlocked_edges[edge] = true
			_append_log("消耗 1 把钥匙，解锁了通往 %s 的封印路径。" % target_room_id)

		_enter_room(target_room_id, _opposite_dir(String(exit_cfg.get("dir", ""))))
		_door_cooldown = 0.35
		return

func _enter_room(room_id: String, spawn_from_dir: String) -> void:
	if not _rooms_by_id.has(room_id):
		return
	_current_room_id = room_id
	_visited[room_id] = true
	_prayer_request_input.clear()
	_deity_response_output.text = ""
	_place_player(spawn_from_dir)
	_spawn_room_entities()
	_update_minimap()
	_append_log("进入房间：%s" % String(_current_room().get("name", room_id)))

func _spawn_room_entities() -> void:
	_bullets.clear()
	_enemy_projectiles.clear()
	_enemies.clear()

	var room := _current_room()
	if bool(_cleared.get(_current_room_id, false)):
		return

	var enemy_count := int(room.get("enemy_count", 0))
	var enemy_types: Array = room.get("enemy_types", [])
	var spawned_positions: Array = []
	for i in range(enemy_count):
		var kind := "chaser"
		if i < enemy_types.size():
			kind = String(enemy_types[i])
		var pos := _sample_enemy_spawn(spawned_positions)
		spawned_positions.append(pos)
		var enemy := {
			"pos": pos,
			"kind": kind,
			"hp": 4 if kind == "chaser" else 3,
			"atk": 2 if kind == "chaser" else 1,
			"speed": 105.0 if kind == "chaser" else 85.0,
			"shoot_cd": 0.8 + _rng.randf() * 0.5
		}
		_enemies.append(enemy)

	if enemy_count == 0:
		_on_room_cleared()

func _sample_enemy_spawn(existing_positions: Array) -> Vector2:
	var best_pos := _random_point_in_play_rect(ENEMY_SPAWN_PADDING)
	var best_score := -1.0
	for _i in range(ENEMY_SPAWN_ATTEMPTS):
		var candidate := _random_point_in_play_rect(ENEMY_SPAWN_PADDING)
		var dist_player := candidate.distance_to(_player_pos)
		var min_enemy_dist := INF
		for pos_variant in existing_positions:
			var other_pos: Vector2 = pos_variant
			min_enemy_dist = minf(min_enemy_dist, candidate.distance_to(other_pos))
		if existing_positions.is_empty():
			min_enemy_dist = 99999.0

		if dist_player >= ENEMY_MIN_PLAYER_DIST and min_enemy_dist >= ENEMY_MIN_ENEMY_DIST:
			return candidate

		var player_score := dist_player / ENEMY_MIN_PLAYER_DIST
		var enemy_score := min_enemy_dist / ENEMY_MIN_ENEMY_DIST
		var score := minf(player_score, enemy_score)
		if score > best_score:
			best_score = score
			best_pos = candidate
	return best_pos

func _on_room_cleared() -> void:
	if bool(_cleared.get(_current_room_id, false)):
		return
	_cleared[_current_room_id] = true

	var room := _current_room()
	var key_reward := int(room.get("key_reward", 0))
	if key_reward > 0:
		var before_keys := int(_player_state.get("keys", 0))
		_player_state["keys"] = before_keys + key_reward
		_append_log("战利品：钥匙 %+d（%d -> %d）" % [key_reward, before_keys, int(_player_state.get("keys", 0))])

	if String(room.get("type", "")) == "chest" and not bool(_chest_opened.get(_current_room_id, false)):
		_chest_opened[_current_room_id] = true
		var reward: Dictionary = room.get("big_reward", {})
		_apply_effect(reward, "开启大宝箱")

	_append_log("房间已清空：可通过门选择下一条路径。")
	if String(room.get("type", "")) == "prayer" and not bool(_prayed.get(_current_room_id, false)):
		_append_log("这是祈福房：靠近神像后可输入请求并祈祷。")

	if _current_room_id == "r22":
		_victory = true
		_game_over = true
		_append_log("你清空了终局斗场，成功完成本轮地牢。")

func _on_pray_pressed() -> void:
	if not _can_pray_current_room():
		return
	_on_auto_request_pressed()
	_on_ask_statue_pressed()

func _on_auto_request_pressed() -> void:
	if not _can_pray_current_room():
		return
	_prayer_request_input.text = _generate_auto_request()

func _on_ask_statue_pressed() -> void:
	if not _can_pray_current_room():
		return
	var request_text := _prayer_request_input.text.strip_edges()
	if request_text.is_empty():
		request_text = _generate_auto_request()
		_prayer_request_input.text = request_text
	var idx := _choose_blessing_index_by_request(request_text)
	_apply_prayer_choice(idx, request_text)

func _on_bless_option_pressed(index: int) -> void:
	if not _can_pray_current_room():
		return
	var pool := _current_prayer_pool()
	if index < 0 or index >= pool.size():
		return
	var blessing: Dictionary = pool[index]
	var request_text := _prayer_request_input.text.strip_edges()
	if request_text.is_empty():
		request_text = "请赐予我%s。" % String(blessing.get("label", "祝福"))
		_prayer_request_input.text = request_text
	_apply_prayer_choice(index, request_text)

func _apply_prayer_choice(index: int, request_text: String) -> void:
	var pool := _current_prayer_pool()
	if index < 0 or index >= pool.size():
		return
	var blessing: Dictionary = pool[index]
	var room := _current_room()
	_apply_effect(blessing.get("effect", {}), "祈祷：%s" % String(blessing.get("label", "未知赐福")))
	_prayed[_current_room_id] = true

	var deity_name := String(room.get("deity_name", "无名神像"))
	var response := _build_deity_response(deity_name, request_text, blessing)
	_deity_response_output.text = response
	_append_log(response)

func _current_prayer_pool() -> Array:
	var room := _current_room()
	return room.get("prayer_pool", [])

func _generate_auto_request() -> String:
	var hp := int(_player_state.get("hp", 0))
	var keys := int(_player_state.get("keys", 0))
	var atk := int(_player_state.get("atk", 0))
	var def := int(_player_state.get("def", 0))
	if hp <= 12:
		return "神像，请让我活下去，赐我生命。"
	if keys <= 0:
		return "神像，请赐我钥匙以打开封印之门。"
	if atk <= def:
		return "神像，请赐予我更强的力量。"
	return "神像，请赐我稳固防护与命运加护。"

func _choose_blessing_index_by_request(request_text: String) -> int:
	var text := request_text.to_lower()
	var pool := _current_prayer_pool()
	if pool.is_empty():
		return -1
	var preferred_key := ""
	if text.find("力量") != -1 or text.find("攻击") != -1 or text.find("伤害") != -1:
		preferred_key = "atk"
	elif text.find("防") != -1 or text.find("护") != -1 or text.find("盾") != -1:
		preferred_key = "def"
	elif text.find("命运") != -1 or text.find("fate") != -1:
		preferred_key = "fate"
	elif text.find("钥匙") != -1 or text.find("锁") != -1 or text.find("门") != -1:
		preferred_key = "keys"
	elif text.find("生命") != -1 or text.find("治疗") != -1 or text.find("血") != -1:
		preferred_key = "hp"
	elif text.find("净化") != -1 or text.find("腐化") != -1:
		preferred_key = "corruption"

	if preferred_key.is_empty():
		return _rng.randi_range(0, pool.size() - 1)

	for i in range(pool.size()):
		var blessing: Dictionary = pool[i]
		var effect: Dictionary = blessing.get("effect", {})
		if effect.has(preferred_key):
			return i
	return _rng.randi_range(0, pool.size() - 1)

func _build_deity_response(deity_name: String, request_text: String, blessing: Dictionary) -> String:
	var label := String(blessing.get("label", "未知赐福"))
	var summary := _effect_summary(blessing.get("effect", {}))
	return "%s回应：你祈求“%s”。吾已裁定【%s】。%s" % [
		deity_name,
		request_text,
		label,
		summary
	]

func _effect_summary(effect: Dictionary) -> String:
	if effect.is_empty():
		return "未产生数值变化。"
	var parts: Array[String] = []
	for key_variant in effect.keys():
		var key := String(key_variant)
		var delta := int(effect.get(key, 0))
		var sign := "+" if delta >= 0 else ""
		parts.append("%s%s%d" % [key, sign, delta])
	return "效果：" + "，".join(parts)

func _refresh_prayer_panel() -> void:
	var can_pray := _can_pray_current_room()
	_prayer_panel.visible = can_pray
	if not can_pray:
		return

	var room := _current_room()
	var deity_name := String(room.get("deity_name", "祝福神像"))
	var title_label: Label = _prayer_panel.get_node("PrayerTitle")
	title_label.text = "%s" % deity_name

	var pool := _current_prayer_pool()
	var buttons := [_bless_option_a, _bless_option_b, _bless_option_c]
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		if i < pool.size():
			var blessing: Dictionary = pool[i]
			btn.visible = true
			btn.text = "%s（%s）" % [
				String(blessing.get("label", "祝福")),
				_effect_summary(blessing.get("effect", {}))
			]
		else:
			btn.visible = false

	if _deity_response_output.text.is_empty():
		_deity_response_output.text = "神像静默，等待你的请求。"

func _apply_effect(effect: Dictionary, reason: String) -> void:
	if effect.is_empty():
		return
	for key_variant in effect.keys():
		var key: String = String(key_variant)
		var delta := int(effect.get(key, 0))
		var before := int(_player_state.get(key, 0))
		var after := before + delta
		if key == "hp":
			after = clampi(after, 0, 60)
		elif key == "atk":
			after = maxi(0, after)
		elif key == "def":
			after = maxi(0, after)
		elif key == "keys":
			after = maxi(0, after)
		elif key == "corruption":
			after = clampi(after, 0, 30)
		_player_state[key] = after
		_append_log("%s：%s %d -> %d (%+d)" % [reason, key, before, after, delta])

func _apply_damage_to_player(base_damage: int, reason: String) -> void:
	var defense := int(_player_state.get("def", 0))
	var final_damage := maxi(1, base_damage - defense)
	var hp_before := int(_player_state.get("hp", 0))
	var hp_after := maxi(0, hp_before - final_damage)
	_player_state["hp"] = hp_after
	if hp_after <= 0 and not _game_over:
		_game_over = true
		_victory = false
	_append_log("%s：HP %d -> %d (-%d)" % [reason, hp_before, hp_after, final_damage])

func _update_ui() -> void:
	var room := _current_room()
	_stats_label.text = "HP %d | ATK %d | DEF %d | Keys %d | Corruption %d | Fate %d" % [
		int(_player_state.get("hp", 0)),
		int(_player_state.get("atk", 0)),
		int(_player_state.get("def", 0)),
		int(_player_state.get("keys", 0)),
		int(_player_state.get("corruption", 0)),
		int(_player_state.get("fate", 0))
	]
	_room_label.text = "房间 %s（%s） | 敌人剩余 %d | 已清空 %s" % [
		String(room.get("name", _current_room_id)),
		String(room.get("type", "")),
		_enemies.size(),
		"是" if bool(_cleared.get(_current_room_id, false)) else "否"
	]

	var hint := "WASD移动，左键射击，清房后穿门选路。"
	if _game_over:
		hint = "胜利完成地牢。" if _victory else "你已倒下。点击【重开本局】继续。"
	elif not _enemies.is_empty():
		hint = "当前房间战斗中：清空敌人后门才可通行。"
	elif _is_prayer_input_active():
		hint = "正在向神像输入请求：角色移动已冻结。"
	elif _can_pray_room_base():
		if _is_near_statue():
			hint = "已靠近神像：可输入请求并祈祷。"
		else:
			hint = "祈福房已清怪：靠近神像后才能请求。"
	else:
		hint = "房间已清空：移动到门口可前往下一个房间。"
	_hint_label.text = hint

	_marker_legend_label.text = "标识：怪(追击) | 远(远程) | 门(可通行) | 锁K(双向锁) | 神像(祈福) | 宝箱(大奖励)"
	_adjacent_preview_label.text = _build_adjacent_preview_text()
	_pray_button.visible = _can_pray_current_room()
	_refresh_prayer_panel()
	_update_minimap()
	_log_output.text = "\n".join(_logs)

func _can_pray_current_room() -> bool:
	return _can_pray_room_base() and _is_near_statue()

func _can_pray_room_base() -> bool:
	if _game_over:
		return false
	var room := _current_room()
	return String(room.get("type", "")) == "prayer" \
		and bool(_cleared.get(_current_room_id, false)) \
		and not bool(_prayed.get(_current_room_id, false))

func _is_near_statue() -> bool:
	var room := _current_room()
	if String(room.get("type", "")) != "prayer":
		return false
	return _player_pos.distance_to(_statue_world_pos()) <= STATUE_INTERACT_RADIUS

func _statue_world_pos() -> Vector2:
	return _play_rect().get_center()

func _is_prayer_input_active() -> bool:
	return _prayer_panel.visible and _prayer_request_input.has_focus()

func _build_minimap() -> void:
	for child in _minimap_grid.get_children():
		child.queue_free()
	_minimap_cells.clear()

	_minimap_grid.columns = maxi(1, _map_cols)
	for y in range(_map_rows):
		for x in range(_map_cols):
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(22, 22)
			cell.color = Color(0.12, 0.12, 0.12)
			_minimap_grid.add_child(cell)

			var room_id := String(_room_ids_by_coord.get(_coord_key(x, y), ""))
			if not room_id.is_empty():
				_minimap_cells[room_id] = cell

func _update_minimap() -> void:
	var adjacent := _adjacent_room_ids()
	for room_id_variant in _minimap_cells.keys():
		var room_id: String = String(room_id_variant)
		var cell: ColorRect = _minimap_cells[room_id]
		var discovered := bool(_visited.get(room_id, false))
		var cleared := bool(_cleared.get(room_id, false))
		if not discovered:
			cell.color = Color(0.16, 0.16, 0.16)
		elif cleared:
			cell.color = Color(0.23, 0.65, 0.38)
		else:
			cell.color = Color(0.52, 0.52, 0.56)

		if not discovered and adjacent.has(room_id):
			cell.color = _preview_color_for_room(room_id)

		if room_id == _current_room_id:
			cell.color = Color(0.96, 0.82, 0.34)

func _current_room() -> Dictionary:
	return _rooms_by_id.get(_current_room_id, {})

func _adjacent_room_ids() -> Dictionary:
	var result := {}
	var room := _current_room()
	for exit_variant in room.get("exits", []):
		var exit_cfg: Dictionary = exit_variant
		var to_room: String = String(exit_cfg.get("to", ""))
		if not to_room.is_empty():
			result[to_room] = true
	return result

func _preview_color_for_room(room_id: String) -> Color:
	var room: Dictionary = _rooms_by_id.get(room_id, {})
	var room_type := String(room.get("type", "battle"))
	match room_type:
		"prayer":
			return Color(0.28, 0.44, 0.62)
		"chest":
			return Color(0.58, 0.48, 0.2)
		"start":
			return Color(0.36, 0.36, 0.4)
		_:
			return Color(0.46, 0.28, 0.28)

func _build_adjacent_preview_text() -> String:
	var room := _current_room()
	var parts: Array[String] = []
	for exit_variant in room.get("exits", []):
		var exit_cfg: Dictionary = exit_variant
		var dir := String(exit_cfg.get("dir", "?"))
		var to_room: String = String(exit_cfg.get("to", ""))
		var target: Dictionary = _rooms_by_id.get(to_room, {})
		if target.is_empty():
			continue

		var edge := _edge_key(_current_room_id, to_room)
		var needs_key := bool(_locked_edges.get(edge, false)) and not bool(_unlocked_edges.get(edge, false))
		var lock_text := "锁门" if needs_key else "通路"
		var type_text := _room_type_display(String(target.get("type", "battle")))
		var enemy_text := "怪%d" % int(target.get("enemy_count", 0))
		var extra := ""
		if String(target.get("type", "")) == "chest":
			extra = " | 大宝箱"
		elif String(target.get("type", "")) == "prayer":
			extra = " | 神像"
		elif int(target.get("key_reward", 0)) > 0:
			extra = " | 钥匙+%d" % int(target.get("key_reward", 0))
		parts.append("%s:%s %s %s%s" % [dir, type_text, enemy_text, lock_text, extra])

	if parts.is_empty():
		return "无相邻房间"
	return "\n".join(parts)

func _room_type_display(room_type: String) -> String:
	match room_type:
		"start":
			return "起始"
		"prayer":
			return "祈福"
		"chest":
			return "宝库"
		"battle":
			return "战斗"
		_:
			return room_type

func _play_rect() -> Rect2:
	var viewport := get_viewport_rect().size
	return Rect2(370.0, 20.0, viewport.x - 390.0, viewport.y - 40.0)

func _door_rect(dir: String) -> Rect2:
	var rect := _play_rect()
	var door_w := 96.0
	var door_h := 22.0
	match dir:
		"up":
			return Rect2(rect.get_center().x - door_w * 0.5, rect.position.y - 1.0, door_w, door_h)
		"down":
			return Rect2(rect.get_center().x - door_w * 0.5, rect.end.y - door_h + 1.0, door_w, door_h)
		"left":
			return Rect2(rect.position.x - 1.0, rect.get_center().y - door_w * 0.5, door_h, door_w)
		"right":
			return Rect2(rect.end.x - door_h + 1.0, rect.get_center().y - door_w * 0.5, door_h, door_w)
		_:
			return Rect2(rect.get_center() - Vector2(10, 10), Vector2(20, 20))

func _place_player(spawn_from_dir: String) -> void:
	var rect := _play_rect()
	match spawn_from_dir:
		"left":
			_player_pos = Vector2(rect.position.x + 30.0, rect.get_center().y)
		"right":
			_player_pos = Vector2(rect.end.x - 30.0, rect.get_center().y)
		"up":
			_player_pos = Vector2(rect.get_center().x, rect.position.y + 30.0)
		"down":
			_player_pos = Vector2(rect.get_center().x, rect.end.y - 30.0)
		_:
			_player_pos = rect.get_center()

func _edge_key(a: String, b: String) -> String:
	if a <= b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]

func _opposite_dir(dir: String) -> String:
	match dir:
		"up":
			return "down"
		"down":
			return "up"
		"left":
			return "right"
		"right":
			return "left"
		_:
			return ""

func _coord_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func _random_point_in_play_rect(padding: float) -> Vector2:
	var rect := _play_rect()
	return Vector2(
		_rng.randf_range(rect.position.x + padding, rect.end.x - padding),
		_rng.randf_range(rect.position.y + padding, rect.end.y - padding)
	)

func _clamp_in_play_rect(pos: Vector2, radius: float) -> Vector2:
	var rect := _play_rect()
	return Vector2(
		clampf(pos.x, rect.position.x + radius, rect.end.x - radius),
		clampf(pos.y, rect.position.y + radius, rect.end.y - radius)
	)

func _draw_world_text(pos: Vector2, text: String, color: Color) -> void:
	if _debug_font == null:
		return
	draw_string(_debug_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)

func _append_log(line: String) -> void:
	_logs.append(line)
	if _logs.size() > 80:
		_logs.remove_at(0)

func _on_restart_pressed() -> void:
	_boot_new_run()

func _setup_ui_font() -> void:
	var font_file: FontFile = _find_cjk_font()
	if font_file == null:
		push_warning("DungeonRun: No CJK font found, Chinese text may not render correctly.")
		_debug_font = ThemeDB.fallback_font
		return

	var ui_theme := Theme.new()
	ui_theme.default_font = font_file
	ui_theme.default_font_size = 18
	_hud_panel.theme = ui_theme
	ThemeDB.fallback_font = font_file
	ThemeDB.fallback_font_size = 18
	_debug_font = font_file

func _find_cjk_font() -> FontFile:
	var font_paths: Array[String] = [
		"res://assets/fonts/HiraginoSansGB.ttc",
		"res://assets/fonts/NotoSansSC-Regular.ttf",
		"res://assets/fonts/SourceHanSansSC-Regular.otf",
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
	]
	for path in font_paths:
		var font_file := _load_font_from_path(path)
		if font_file == null:
			continue
		if font_file.has_char("命".unicode_at(0)) and font_file.has_char("A".unicode_at(0)):
			return font_file
	return null

func _load_font_from_path(path: String) -> FontFile:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		var res := ResourceLoader.load(path)
		if res is FontFile:
			return res
	if not FileAccess.file_exists(path):
		return null
	var font_file := FontFile.new()
	var err := font_file.load_dynamic_font(path)
	if err != OK:
		return null
	return font_file
