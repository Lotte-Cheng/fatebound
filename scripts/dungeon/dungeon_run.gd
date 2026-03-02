extends Node2D

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const DUNGEON_PATH := "res://data/dungeon_layout.json"
const SPAWN_PROFILES_PATH := "res://data/spawn_profiles.json"
const BUILD_NODES_PATH := "res://data/build_nodes.json"
const SPAWN_GLOBAL_TUNING_CSV_PATH := "res://data/csv/spawn_global_tuning.csv"
const SPAWN_PROFILES_CSV_PATH := "res://data/csv/spawn_profiles.csv"
const BUILD_SLOT_LIMITS_CSV_PATH := "res://data/csv/build_nodes_slot_limits.csv"
const BUILD_PROGRESSION_CSV_PATH := "res://data/csv/build_nodes_progression.csv"
const BUILD_SYNERGIES_CSV_PATH := "res://data/csv/build_nodes_synergy_rules.csv"
const BUILD_NODES_CSV_PATH := "res://data/csv/build_nodes_nodes.csv"

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
const XP_ORB_RADIUS := 7.0
const BASE_SHOT_COOLDOWN := 0.2
const LEVELUP_OPTION_COUNT := 3
const TUTORIAL_MOVE_DISTANCE := 110.0
const TUTORIAL_SHOTS_REQUIRED := 3
const GUIDE_ARROW_LENGTH := 56.0
const GUIDE_ARROW_HEAD := 14.0
const GUIDE_ARROW_WOBBLE := 10.0

@onready var _hud_panel: PanelContainer = $CanvasLayer/HudPanel
@onready var _stats_label: Label = $CanvasLayer/HudPanel/VBox/StatsLabel
@onready var _xp_bar: ProgressBar = $CanvasLayer/HudPanel/VBox/XpBar
@onready var _xp_bar_label: Label = $CanvasLayer/HudPanel/VBox/XpBarLabel
@onready var _build_state_label: Label = $CanvasLayer/HudPanel/VBox/BuildStateLabel
@onready var _synergy_state_label: Label = $CanvasLayer/HudPanel/VBox/SynergyStateLabel
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
@onready var _levelup_panel: VBoxContainer = $CanvasLayer/HudPanel/VBox/LevelUpPanel
@onready var _levelup_title_label: Label = $CanvasLayer/HudPanel/VBox/LevelUpPanel/LevelUpTitle
@onready var _build_option_a: Button = $CanvasLayer/HudPanel/VBox/LevelUpPanel/BuildOptionA
@onready var _build_option_b: Button = $CanvasLayer/HudPanel/VBox/LevelUpPanel/BuildOptionB
@onready var _build_option_c: Button = $CanvasLayer/HudPanel/VBox/LevelUpPanel/BuildOptionC
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
var _spawn_profiles: Dictionary = {}
var _spawn_global_tuning := {}
var _build_nodes_catalog: Array[Dictionary] = []
var _build_slot_limits := {}
var _build_progression_cfg := {}
var _build_synergy_rules: Array[Dictionary] = []

var _player_state: Dictionary = {}
var _player_pos := Vector2.ZERO
var _bullets: Array[Dictionary] = []
var _enemy_projectiles: Array[Dictionary] = []
var _xp_orbs: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []
var _battle_is_survival := false
var _battle_timer_total := 0.0
var _battle_timer_remaining := 0.0
var _battle_spawn_profile: Dictionary = {}
var _battle_spawn_cd := 0.0
var _battle_next_elite_index := 0
var _battle_timeout_announced := false
var _battle_spawn_total_limit := 0
var _battle_spawned_total := 0
var _battle_spawn_finished := false
var _run_level := 1
var _run_xp := 0
var _run_xp_to_next := 6
var _build_modifiers := {
	"fire_rate_mult": 1.0,
	"projectile_bonus": 0,
	"move_speed_bonus": 0.0,
	"damage_reduction": 0,
	"bullet_damage_bonus": 0
}
var _owned_build_stacks: Dictionary = {}
var _owned_slot_counts: Dictionary = {}
var _owned_build_tags: Dictionary = {}
var _active_synergy_ids: Dictionary = {}
var _build_budget_total := 0
var _build_budget_spent := 0
var _levelup_pending := false
var _levelup_options: Array[Dictionary] = []
var _levelup_blocked_reasons: Dictionary = {}
var _levelup_blocker_hint := ""
var _tutorial_spawn_pos := Vector2.ZERO
var _tutorial_move_done := false
var _tutorial_shots_fired := 0
var _tutorial_kills := 0
var _tutorial_step_announced := -1

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
	_build_option_a.pressed.connect(func() -> void: _on_build_option_pressed(0))
	_build_option_b.pressed.connect(func() -> void: _on_build_option_pressed(1))
	_build_option_c.pressed.connect(func() -> void: _on_build_option_pressed(2))
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
	_xp_orbs.clear()
	_enemies.clear()
	_logs.clear()
	_deity_response_output.text = ""
	_levelup_options.clear()
	_levelup_blocked_reasons.clear()
	_levelup_blocker_hint = ""
	_levelup_pending = false
	_reset_battle_room_runtime()
	_reset_tutorial_runtime()
	_load_runtime_configs()
	_reset_build_runtime()

	_map_cols = int((cfg.get("grid", {}) as Dictionary).get("cols", 3))
	_map_rows = int((cfg.get("grid", {}) as Dictionary).get("rows", 3))
	_start_room_id = String(cfg.get("start_room_id", ""))
	_player_state = (cfg.get("initial_state", {}) as Dictionary).duplicate(true)
	# Fate is deprecated in the action-loop prototype. Keep field absent to avoid UI/log noise.
	_player_state.erase("fate")
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

func _load_runtime_configs() -> void:
	var spawn_cfg: Dictionary = _load_spawn_config()
	_spawn_global_tuning = _default_spawn_tuning()
	var tuning_cfg: Dictionary = spawn_cfg.get("global_tuning", {})
	for key_variant in tuning_cfg.keys():
		var key := String(key_variant)
		_spawn_global_tuning[key] = tuning_cfg.get(key)
	_spawn_profiles = (spawn_cfg.get("profiles", {}) as Dictionary).duplicate(true)
	if _spawn_profiles.is_empty():
		_spawn_profiles["battle_default"] = _default_spawn_profile()

	var build_cfg: Dictionary = _load_build_config()
	_build_slot_limits = _default_build_slot_limits()
	var slot_limits_cfg: Dictionary = build_cfg.get("slot_limits", {})
	for slot_variant in slot_limits_cfg.keys():
		var slot := String(slot_variant)
		_build_slot_limits[slot] = maxi(0, int(slot_limits_cfg.get(slot, 0)))
	_build_progression_cfg = _default_build_progression_cfg()
	var progression_cfg: Dictionary = build_cfg.get("build_progression", {})
	for key_variant in progression_cfg.keys():
		var key := String(key_variant)
		_build_progression_cfg[key] = progression_cfg.get(key)

	_build_synergy_rules.clear()
	for rule_variant in build_cfg.get("synergy_rules", []):
		var rule: Dictionary = rule_variant
		var rule_id := String(rule.get("id", ""))
		if rule_id.is_empty():
			continue
		_build_synergy_rules.append(rule)
	if _build_synergy_rules.is_empty():
		_build_synergy_rules = _default_build_synergy_rules()

	_build_nodes_catalog.clear()
	for node_variant in build_cfg.get("nodes", []):
		var node: Dictionary = node_variant
		if String(node.get("id", "")).is_empty():
			continue
		_build_nodes_catalog.append(node)
	if _build_nodes_catalog.is_empty():
		_build_nodes_catalog = _default_build_nodes()

func _load_spawn_config() -> Dictionary:
	var cfg: Dictionary = DataLoaderScript.load_json(SPAWN_PROFILES_PATH)
	if cfg.is_empty():
		cfg = {"global_tuning": {}, "profiles": {}}

	var tuning_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(SPAWN_GLOBAL_TUNING_CSV_PATH)
	if not tuning_rows.is_empty():
		var tuning := {}
		for row_variant in tuning_rows:
			var row: Dictionary = row_variant
			var key := String(row.get("key", ""))
			if key.is_empty():
				continue
			tuning[key] = _csv_parse_scalar(String(row.get("value", "")))
		cfg["global_tuning"] = tuning

	var profile_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(SPAWN_PROFILES_CSV_PATH)
	if not profile_rows.is_empty():
		var profiles := {}
		for row_variant in profile_rows:
			var row: Dictionary = row_variant
			var profile_id := String(row.get("id", ""))
			if profile_id.is_empty():
				continue
			var profile := {
				"spawn_interval": _csv_float(row, "spawn_interval", 1.2),
				"min_interval": _csv_float(row, "min_interval", 0.55),
				"ramp_per_sec": _csv_float(row, "ramp_per_sec", 0.01),
				"max_enemies": _csv_int(row, "max_enemies", 16),
				"enemy_hp_mult": _csv_float(row, "enemy_hp_mult", 1.0),
				"enemy_atk_mult": _csv_float(row, "enemy_atk_mult", 1.0),
				"enemy_speed_mult": _csv_float(row, "enemy_speed_mult", 1.0),
				"xp_per_kill": _csv_int(row, "xp_per_kill", 1),
				"elite_hp_mult": _csv_float(row, "elite_hp_mult", 2.2),
				"elite_xp": _csv_int(row, "elite_xp", 3),
				"mix": _csv_json_array(String(row.get("mix_json", "[]"))),
				"elite_spawn_at_sec": _csv_json_array(String(row.get("elite_spawn_at_sec_json", "[]")))
			}
			if profile.get("mix", []).is_empty():
				profile["mix"] = [{"kind": "chaser", "weight": 100}]
			profiles[profile_id] = profile
		cfg["profiles"] = profiles

	return cfg

func _load_build_config() -> Dictionary:
	var cfg: Dictionary = DataLoaderScript.load_json(BUILD_NODES_PATH)
	if cfg.is_empty():
		cfg = {"slot_limits": {}, "build_progression": {}, "synergy_rules": [], "nodes": []}

	var slot_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(BUILD_SLOT_LIMITS_CSV_PATH)
	if not slot_rows.is_empty():
		var slot_limits := {}
		for row_variant in slot_rows:
			var row: Dictionary = row_variant
			var slot := String(row.get("slot", ""))
			if slot.is_empty():
				continue
			slot_limits[slot] = _csv_int(row, "limit", 0)
		cfg["slot_limits"] = slot_limits

	var progression_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(BUILD_PROGRESSION_CSV_PATH)
	if not progression_rows.is_empty():
		var progression := {}
		for row_variant in progression_rows:
			var row: Dictionary = row_variant
			var key := String(row.get("key", ""))
			if key.is_empty():
				continue
			progression[key] = _csv_parse_scalar(String(row.get("value", "")))
		cfg["build_progression"] = progression

	var synergy_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(BUILD_SYNERGIES_CSV_PATH)
	if not synergy_rows.is_empty():
		var rules: Array[Dictionary] = []
		for row_variant in synergy_rows:
			var row: Dictionary = row_variant
			var rule_id := String(row.get("id", ""))
			if rule_id.is_empty():
				continue
			rules.append({
				"id": rule_id,
				"label": String(row.get("label", rule_id)),
				"required_tags": _csv_split_list(String(row.get("required_tags", ""))),
				"effect": _csv_json_dict(String(row.get("effect_json", "{}")))
			})
		cfg["synergy_rules"] = rules

	var node_rows: Array[Dictionary] = DataLoaderScript.load_csv_rows(BUILD_NODES_CSV_PATH)
	if not node_rows.is_empty():
		var nodes: Array[Dictionary] = []
		for row_variant in node_rows:
			var row: Dictionary = row_variant
			var node_id := String(row.get("id", ""))
			if node_id.is_empty():
				continue
			var node := {
				"id": node_id,
				"label": String(row.get("label", node_id)),
				"description": String(row.get("description", "")),
				"slot": String(row.get("slot", "passive")),
				"tags": _csv_split_list(String(row.get("tags", ""))),
				"required_tags": _csv_split_list(String(row.get("required_tags", ""))),
				"tier_cost": _csv_int(row, "tier_cost", 1),
				"weight": _csv_float(row, "weight", 1.0),
				"max_stack": _csv_int(row, "max_stack", 1),
				"effect": _csv_json_dict(String(row.get("effect_json", "{}")))
			}
			nodes.append(node)
		cfg["nodes"] = nodes

	return cfg

func _csv_int(row: Dictionary, key: String, fallback: int) -> int:
	var raw := String(row.get(key, ""))
	return int(raw) if raw.is_valid_int() else fallback

func _csv_float(row: Dictionary, key: String, fallback: float) -> float:
	var raw := String(row.get(key, ""))
	return float(raw) if raw.is_valid_float() else fallback

func _csv_split_list(raw: String) -> Array[String]:
	var text := raw.strip_edges()
	if text.is_empty():
		return []
	var out: Array[String] = []
	for item_variant in text.split("|", false):
		var item := String(item_variant).strip_edges()
		if item.is_empty():
			continue
		out.append(item)
	return out

func _csv_json_dict(raw: String) -> Dictionary:
	var value: Variant = _csv_json_value(raw, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}

func _csv_json_array(raw: String) -> Array:
	var value: Variant = _csv_json_value(raw, [])
	return value if typeof(value) == TYPE_ARRAY else []

func _csv_json_value(raw: String, fallback: Variant) -> Variant:
	var text := raw.strip_edges()
	if text.is_empty():
		return fallback
	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("CSV JSON parse failed: %s" % text)
		return fallback
	return parser.data

func _csv_parse_scalar(raw: String) -> Variant:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	var lower := text.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	return text

func _default_spawn_profile() -> Dictionary:
	return {
		"spawn_interval": 1.2,
		"min_interval": 0.55,
		"ramp_per_sec": 0.01,
		"max_enemies": 16,
		"mix": [
			{"kind": "chaser", "weight": 70},
			{"kind": "shooter", "weight": 30}
		],
		"elite_spawn_at_sec": [38]
	}

func _default_spawn_tuning() -> Dictionary:
	return {
		"spawn_interval_scale": 1.0,
		"enemy_hp_scale": 1.0,
		"enemy_atk_scale": 1.0,
		"enemy_speed_scale": 1.0,
		"xp_gain_scale": 1.0,
		"xp_orb_pickup_radius": 22.0,
		"xp_orb_magnet_radius": 168.0,
		"xp_orb_magnet_speed": 420.0,
		"xp_orb_lifetime_sec": 24.0,
		"xp_orb_drift_damp": 5.0,
		"late_wave_start_sec": 24.0,
		"late_wave_spawn_rate_mult": 1.35,
		"late_wave_max_enemies_bonus": 12
	}

func _default_build_slot_limits() -> Dictionary:
	return {
		"weapon": 2,
		"passive": 3,
		"godsend": 2,
		"debt": 2
	}

func _default_build_progression_cfg() -> Dictionary:
	return {
		"base_budget": 1,
		"budget_gain_per_level": 1,
		"max_unspent_budget": 4
	}

func _default_build_synergy_rules() -> Array[Dictionary]:
	return [
		{
			"id": "fallback_synergy_projectile",
			"label": "弹幕协同",
			"required_tags": ["projectile", "precision"],
			"effect": {"bullet_damage_bonus": 1}
		},
		{
			"id": "fallback_synergy_guard",
			"label": "守护协同",
			"required_tags": ["guard", "oath"],
			"effect": {"def": 1}
		}
	]

func _default_build_nodes() -> Array[Dictionary]:
	return [
		{
			"id": "fallback_damage",
			"label": "战意注入",
			"description": "攻击 +1",
			"slot": "weapon",
			"tags": ["power", "projectile"],
			"weight": 1.0,
			"max_stack": 3,
			"effect": {"atk": 1}
		},
		{
			"id": "fallback_guard",
			"label": "守护注入",
			"description": "防御 +1",
			"slot": "passive",
			"tags": ["guard", "oath"],
			"weight": 1.0,
			"max_stack": 3,
			"effect": {"def": 1}
		},
		{
			"id": "fallback_life",
			"label": "命脉注入",
			"description": "生命 +4",
			"slot": "godsend",
			"tags": ["blessing", "ritual"],
			"weight": 1.0,
			"max_stack": 2,
			"effect": {"hp": 4}
		}
	]

func _reset_battle_room_runtime() -> void:
	_battle_is_survival = false
	_battle_timer_total = 0.0
	_battle_timer_remaining = 0.0
	_battle_spawn_profile.clear()
	_battle_spawn_cd = 0.0
	_battle_next_elite_index = 0
	_battle_timeout_announced = false
	_battle_spawn_total_limit = 0
	_battle_spawned_total = 0
	_battle_spawn_finished = false

func _reset_build_runtime() -> void:
	_run_level = 1
	_run_xp = 0
	_run_xp_to_next = 6
	_owned_build_stacks.clear()
	_owned_slot_counts.clear()
	_owned_build_tags.clear()
	_active_synergy_ids.clear()
	if _build_slot_limits.is_empty():
		_build_slot_limits = _default_build_slot_limits()
	if _build_progression_cfg.is_empty():
		_build_progression_cfg = _default_build_progression_cfg()
	_build_budget_total = maxi(1, int(_build_progression_cfg.get("base_budget", 1)))
	_build_budget_spent = 0
	_build_modifiers = {
		"fire_rate_mult": 1.0,
		"projectile_bonus": 0,
		"move_speed_bonus": 0.0,
		"damage_reduction": 0,
		"bullet_damage_bonus": 0
	}

func _reset_tutorial_runtime() -> void:
	_tutorial_spawn_pos = Vector2.ZERO
	_tutorial_move_done = false
	_tutorial_shots_fired = 0
	_tutorial_kills = 0
	_tutorial_step_announced = -1

func _process(delta: float) -> void:
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_touch_hit_cooldown = maxf(0.0, _touch_hit_cooldown - delta)
	_door_cooldown = maxf(0.0, _door_cooldown - delta)

	if _game_over:
		_update_ui()
		queue_redraw()
		return

	if _levelup_pending:
		_update_ui()
		queue_redraw()
		return

	_move_player(delta)
	_update_bullets(delta)
	_update_enemy_projectiles(delta)
	_update_xp_orbs(delta)
	_update_enemies(delta)
	_update_survival_room(delta)
	_sync_tutorial_step_log()

	if _should_clear_current_room() and not bool(_cleared.get(_current_room_id, false)):
		_on_room_cleared()

	_try_room_transition()
	_update_ui()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if _levelup_pending and event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_1:
				_on_build_option_pressed(0)
				return
			if key_event.keycode == KEY_2:
				_on_build_option_pressed(1)
				return
			if key_event.keycode == KEY_3:
				_on_build_option_pressed(2)
				return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _game_over and not _is_game_input_locked():
			_try_fire(mb.position)

func _draw() -> void:
	var rect := _play_rect()
	draw_rect(rect, Color(0.09, 0.09, 0.12), true)
	draw_rect(rect, Color(0.4, 0.4, 0.45), false, 2.0)

	var room := _current_room()
	var room_cleared := bool(_cleared.get(_current_room_id, false))
	_draw_world_text(rect.position + Vector2(8, 20), "房间:%s" % String(room.get("type", "unknown")), Color(0.82, 0.86, 0.92))
	if _is_tutorial_active():
		_draw_tutorial_world_guidance(rect)
	if _battle_is_survival and not room_cleared:
		_draw_world_text(rect.position + Vector2(8, 40), "生存倒计时: %.1fs" % _battle_timer_remaining, Color(0.96, 0.84, 0.42))
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
	for orb_variant in _xp_orbs:
		var orb: Dictionary = orb_variant
		var orb_xp := int(orb.get("xp", 1))
		var orb_color := Color(0.45, 0.92, 1.0) if orb_xp <= 2 else Color(0.95, 0.9, 0.3)
		draw_circle(orb.get("pos", Vector2.ZERO), XP_ORB_RADIUS + minf(2.5, float(orb_xp) * 0.35), orb_color)

	for enemy_variant in _enemies:
		var enemy: Dictionary = enemy_variant
		var color := Color(0.92, 0.28, 0.28)
		var marker := "怪"
		if bool(enemy.get("elite", false)):
			color = Color(0.9, 0.22, 0.74)
			marker = "精"
		if String(enemy.get("kind", "chaser")) == "shooter":
			color = Color(0.95, 0.55, 0.3)
			marker = "远"
			if bool(enemy.get("elite", false)):
				color = Color(0.95, 0.45, 0.8)
				marker = "精远"
		draw_circle(enemy.get("pos", Vector2.ZERO), ENEMY_RADIUS, color)
		_draw_world_text(enemy.get("pos", Vector2.ZERO) + Vector2(-9, -18), marker, Color(1.0, 1.0, 1.0))

	draw_circle(_player_pos, PLAYER_RADIUS, Color(0.25, 0.9, 0.52))
	_draw_world_text(_player_pos + Vector2(-10, -18), "你", Color(0.85, 1.0, 0.88))

func _move_player(delta: float) -> void:
	if _is_game_input_locked():
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

	var speed := PLAYER_SPEED + float(_build_modifiers.get("move_speed_bonus", 0.0))
	_player_pos += axis * speed * delta
	var rect := _play_rect()
	_player_pos.x = clampf(_player_pos.x, rect.position.x + PLAYER_RADIUS, rect.end.x - PLAYER_RADIUS)
	_player_pos.y = clampf(_player_pos.y, rect.position.y + PLAYER_RADIUS, rect.end.y - PLAYER_RADIUS)
	if _is_tutorial_active() and not _tutorial_move_done:
		_tutorial_move_done = _player_pos.distance_to(_tutorial_spawn_pos) >= TUTORIAL_MOVE_DISTANCE

func _try_fire(target_pos: Vector2) -> void:
	if _shoot_cooldown > 0.0:
		return

	var dir := (target_pos - _player_pos).normalized()
	if dir == Vector2.ZERO:
		return
	var fire_rate_mult := maxf(0.35, float(_build_modifiers.get("fire_rate_mult", 1.0)))
	_shoot_cooldown = maxf(0.06, BASE_SHOT_COOLDOWN / fire_rate_mult)
	if _is_tutorial_active() and _tutorial_move_done and _tutorial_shots_fired < TUTORIAL_SHOTS_REQUIRED:
		_tutorial_shots_fired += 1

	var damage := maxi(1, int(_player_state.get("atk", 1)) + int(_build_modifiers.get("bullet_damage_bonus", 0)))
	var projectile_count := maxi(1, 1 + int(_build_modifiers.get("projectile_bonus", 0)))
	var center := (projectile_count - 1) * 0.5
	var spread_step := deg_to_rad(10.0)
	for i in range(projectile_count):
		var angle_offset := (float(i) - center) * spread_step
		var shot_dir := dir.rotated(angle_offset)
		_bullets.append({
			"pos": _player_pos,
			"vel": shot_dir * BULLET_SPEED,
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
					_on_enemy_defeated(enemy)
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

func _update_xp_orbs(delta: float) -> void:
	if _xp_orbs.is_empty():
		return
	var alive: Array[Dictionary] = []
	var pickup_radius := float(_spawn_global_tuning.get("xp_orb_pickup_radius", 22.0))
	var magnet_radius := float(_spawn_global_tuning.get("xp_orb_magnet_radius", 168.0))
	var magnet_speed := float(_spawn_global_tuning.get("xp_orb_magnet_speed", 420.0))
	var drift_damp := float(_spawn_global_tuning.get("xp_orb_drift_damp", 5.0))
	for orb_variant in _xp_orbs:
		var orb: Dictionary = orb_variant
		var pos: Vector2 = orb.get("pos", Vector2.ZERO)
		var vel: Vector2 = orb.get("vel", Vector2.ZERO)
		var ttl := float(orb.get("ttl", 0.0)) - delta
		if ttl <= 0.0:
			continue

		var dist := pos.distance_to(_player_pos)
		if dist <= pickup_radius + PLAYER_RADIUS:
			_add_run_xp(int(orb.get("xp", 1)))
			continue

		if dist <= magnet_radius:
			var pull_dir := (_player_pos - pos).normalized()
			vel = vel.lerp(pull_dir * magnet_speed, clampf(delta * 8.0, 0.0, 1.0))
		else:
			vel = vel.lerp(Vector2.ZERO, clampf(delta * drift_damp, 0.0, 1.0))

		pos += vel * delta
		orb["pos"] = _clamp_in_play_rect(pos, XP_ORB_RADIUS)
		orb["vel"] = vel
		orb["ttl"] = ttl
		alive.append(orb)
	_xp_orbs = alive

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
	if not bool(_cleared.get(_current_room_id, false)):
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
	_levelup_options.clear()
	_levelup_blocked_reasons.clear()
	_levelup_blocker_hint = ""
	_levelup_pending = false
	_reset_battle_room_runtime()
	_place_player(spawn_from_dir)
	if _is_tutorial_upgrade_room() and not bool(_cleared.get(_current_room_id, false)):
		_tutorial_spawn_pos = _player_pos
		_tutorial_move_done = false
		_tutorial_shots_fired = 0
		_tutorial_kills = 0
		_tutorial_step_announced = -1
		_append_log("教学开始：1) WASD移动离开光圈 2) 左键开火3次 3) 击败怪物升级 4) 选择1个构筑。")
	else:
		_reset_tutorial_runtime()
	_spawn_room_entities()
	_update_minimap()
	_append_log("进入房间：%s" % String(_current_room().get("name", room_id)))

func _spawn_room_entities() -> void:
	_bullets.clear()
	_enemy_projectiles.clear()
	_xp_orbs.clear()
	_enemies.clear()

	var room := _current_room()
	if bool(_cleared.get(_current_room_id, false)):
		return

	if String(room.get("type", "")) == "battle":
		_start_battle_room_runtime(room)
		var initial_count := int(room.get("enemy_count", 2))
		if _battle_spawn_total_limit > 0:
			initial_count = mini(initial_count, _battle_spawn_total_limit)
		var enemy_types: Array = room.get("enemy_types", [])
		for i in range(initial_count):
			var kind := ""
			if i < enemy_types.size():
				kind = String(enemy_types[i])
			if kind.is_empty():
				kind = _pick_enemy_kind(_battle_spawn_profile)
			if not _spawn_enemy(kind, false):
				break
		return

	var enemy_count := int(room.get("enemy_count", 0))
	var enemy_types: Array = room.get("enemy_types", [])
	for i in range(enemy_count):
		var kind := "chaser"
		if i < enemy_types.size():
			kind = String(enemy_types[i])
		_spawn_enemy(kind, false)

	if enemy_count == 0:
		_on_room_cleared()

func _start_battle_room_runtime(room: Dictionary) -> void:
	_battle_is_survival = true
	_battle_timer_total = maxf(20.0, float(room.get("room_timer_sec", 50.0)))
	_battle_timer_remaining = _battle_timer_total
	_battle_timeout_announced = false
	_battle_next_elite_index = 0
	_battle_spawn_total_limit = maxi(1, int(room.get("spawn_total_limit", 26)))
	_battle_spawned_total = 0
	_battle_spawn_finished = false
	var profile_id := String(room.get("spawn_profile_id", "battle_default"))
	_battle_spawn_profile = (_spawn_profiles.get(profile_id, _default_spawn_profile()) as Dictionary).duplicate(true)
	if room.has("enemy_hp_mult"):
		_battle_spawn_profile["enemy_hp_mult"] = float(room.get("enemy_hp_mult", 1.0))
	if room.has("enemy_atk_mult"):
		_battle_spawn_profile["enemy_atk_mult"] = float(room.get("enemy_atk_mult", 1.0))
	if room.has("enemy_speed_mult"):
		_battle_spawn_profile["enemy_speed_mult"] = float(room.get("enemy_speed_mult", 1.0))
	if room.has("elite_hp_mult"):
		_battle_spawn_profile["elite_hp_mult"] = float(room.get("elite_hp_mult", 2.2))
	if room.has("elite_xp"):
		_battle_spawn_profile["elite_xp"] = int(room.get("elite_xp", 3))
	_battle_spawn_cd = 0.35

func _update_survival_room(delta: float) -> void:
	if not _battle_is_survival:
		return
	if bool(_cleared.get(_current_room_id, false)):
		return
	if _battle_spawn_finished:
		return
	if _is_tutorial_active() and not _is_tutorial_spawn_unlocked():
		return

	_battle_timer_remaining = maxf(0.0, _battle_timer_remaining - delta)
	if _battle_timer_remaining <= 0.0:
		if not _battle_timeout_announced:
			_battle_timeout_announced = true
			_append_log("生存倒计时结束：清理剩余敌人后可离开本房间。")
		_battle_spawn_finished = true
		return

	_battle_spawn_cd -= delta
	var loop_guard := 0
	while _battle_spawn_cd <= 0.0 and loop_guard < 8:
		_spawn_survival_enemy()
		_battle_spawn_cd += _current_spawn_interval()
		loop_guard += 1

func _spawn_survival_enemy() -> void:
	if _battle_spawn_total_limit > 0 and _battle_spawned_total >= _battle_spawn_total_limit:
		_battle_spawn_finished = true
		return
	var elapsed := _battle_timer_total - _battle_timer_remaining
	var max_enemies := int(_battle_spawn_profile.get("max_enemies", 16))
	var late_start := float(_spawn_global_tuning.get("late_wave_start_sec", 24.0))
	var late_bonus_total := int(_spawn_global_tuning.get("late_wave_max_enemies_bonus", 12))
	if late_bonus_total > 0 and elapsed > late_start:
		var remain_span := maxf(1.0, _battle_timer_total - late_start)
		var ratio := clampf((elapsed - late_start) / remain_span, 0.0, 1.0)
		max_enemies += int(round(float(late_bonus_total) * ratio))
	if _enemies.size() >= max_enemies:
		return

	var elite_schedule: Array = _battle_spawn_profile.get("elite_spawn_at_sec", [])
	var spawn_elite := false
	if _battle_next_elite_index < elite_schedule.size():
		if elapsed >= float(elite_schedule[_battle_next_elite_index]):
			spawn_elite = true
			_battle_next_elite_index += 1

	var kind := _pick_enemy_kind(_battle_spawn_profile)
	_spawn_enemy(kind, spawn_elite)

func _pick_enemy_kind(profile: Dictionary) -> String:
	var mix: Array = profile.get("mix", [])
	if mix.is_empty():
		return "chaser"

	var total := 0.0
	for item_variant in mix:
		var item: Dictionary = item_variant
		total += maxf(0.01, float(item.get("weight", 1.0)))

	var roll := _rng.randf_range(0.0, total)
	var cursor := 0.0
	for item_variant in mix:
		var item: Dictionary = item_variant
		cursor += maxf(0.01, float(item.get("weight", 1.0)))
		if roll <= cursor:
			return String(item.get("kind", "chaser"))
	return String((mix.back() as Dictionary).get("kind", "chaser"))

func _current_spawn_interval() -> float:
	var base := float(_battle_spawn_profile.get("spawn_interval", 1.2))
	var min_interval := float(_battle_spawn_profile.get("min_interval", 0.55))
	var ramp := float(_battle_spawn_profile.get("ramp_per_sec", 0.01))
	var interval_scale := clampf(float(_spawn_global_tuning.get("spawn_interval_scale", 1.0)), 0.2, 3.0)
	base *= interval_scale
	min_interval *= interval_scale
	var elapsed := _battle_timer_total - _battle_timer_remaining
	var interval := maxf(min_interval, base - elapsed * ramp)
	var late_start := float(_spawn_global_tuning.get("late_wave_start_sec", 24.0))
	var late_mult := maxf(1.0, float(_spawn_global_tuning.get("late_wave_spawn_rate_mult", 1.35)))
	if elapsed > late_start:
		var late_floor := min_interval * 0.45
		interval = maxf(late_floor, interval / late_mult)
	return interval

func _spawn_enemy(kind: String, elite: bool) -> bool:
	if _battle_is_survival and _battle_spawn_total_limit > 0 and _battle_spawned_total >= _battle_spawn_total_limit:
		_battle_spawn_finished = true
		return false
	var pos := _sample_enemy_spawn(_enemy_positions())
	var hp := 4 if kind == "chaser" else 3
	var atk := 2 if kind == "chaser" else 1
	var speed := 105.0 if kind == "chaser" else 85.0
	var hp_mult := float(_battle_spawn_profile.get("enemy_hp_mult", 1.0))
	var atk_mult := float(_battle_spawn_profile.get("enemy_atk_mult", 1.0))
	var speed_mult := float(_battle_spawn_profile.get("enemy_speed_mult", 1.0))
	hp_mult *= float(_spawn_global_tuning.get("enemy_hp_scale", 1.0))
	atk_mult *= float(_spawn_global_tuning.get("enemy_atk_scale", 1.0))
	speed_mult *= float(_spawn_global_tuning.get("enemy_speed_scale", 1.0))
	hp = maxi(1, int(round(float(hp) * hp_mult)))
	atk = maxi(1, int(round(float(atk) * atk_mult)))
	speed *= speed_mult
	var xp := maxi(1, int(round(float(_battle_spawn_profile.get("xp_per_kill", 1)) * float(_spawn_global_tuning.get("xp_gain_scale", 1.0)))))
	if elite:
		hp = maxi(1, int(round(float(hp) * float(_battle_spawn_profile.get("elite_hp_mult", 2.2)))))
		atk += 1
		speed *= 1.08
		xp = maxi(2, int(round(float(_battle_spawn_profile.get("elite_xp", 3)) * float(_spawn_global_tuning.get("xp_gain_scale", 1.0)))))

	var enemy := {
		"pos": pos,
		"kind": kind,
		"hp": hp,
		"atk": atk,
		"speed": speed,
		"shoot_cd": 0.8 + _rng.randf() * 0.5,
		"xp": xp,
		"elite": elite
	}
	_enemies.append(enemy)
	if _battle_is_survival:
		_battle_spawned_total += 1
		if _battle_spawn_total_limit > 0 and _battle_spawned_total >= _battle_spawn_total_limit:
			_battle_spawn_finished = true
			_append_log("本房间刷怪达到上限：%d。清空余怪即可结束。" % _battle_spawn_total_limit)
	return true

func _enemy_positions() -> Array:
	var points: Array = []
	for enemy_variant in _enemies:
		var enemy: Dictionary = enemy_variant
		points.append(enemy.get("pos", Vector2.ZERO))
	return points

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

func _should_clear_current_room() -> bool:
	if bool(_cleared.get(_current_room_id, false)):
		return false
	if not _enemies.is_empty():
		return false
	if _battle_is_survival:
		return _battle_spawn_finished or _battle_timer_remaining <= 0.0
	return true

func _on_enemy_defeated(enemy: Dictionary) -> void:
	if _is_tutorial_active():
		_tutorial_kills += 1
	var xp_gain := int(enemy.get("xp", 1))
	if xp_gain <= 0:
		return
	_drop_xp_orbs(enemy.get("pos", Vector2.ZERO), xp_gain, bool(enemy.get("elite", false)))

func _drop_xp_orbs(origin: Vector2, xp_gain: int, elite: bool) -> void:
	var orb_count := 1
	if elite:
		orb_count = mini(3, maxi(2, int(ceil(float(xp_gain) * 0.5))))
	var remaining := xp_gain
	for i in range(orb_count):
		var splits_left := orb_count - i
		var value := maxi(1, int(round(float(remaining) / float(splits_left))))
		remaining -= value
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(45.0, 110.0)
		_xp_orbs.append({
			"pos": origin,
			"vel": Vector2.RIGHT.rotated(angle) * speed,
			"ttl": float(_spawn_global_tuning.get("xp_orb_lifetime_sec", 24.0)),
			"xp": value
		})

func _add_run_xp(xp_gain: int) -> void:
	_run_xp += xp_gain
	while _run_xp >= _run_xp_to_next:
		_run_xp -= _run_xp_to_next
		_run_level += 1
		_run_xp_to_next = maxi(8, int(round(float(_run_xp_to_next) * 1.35)))
		_grant_build_budget_on_levelup()
		_offer_levelup_choices()

func _grant_build_budget_on_levelup() -> void:
	var gain := maxi(0, int(_build_progression_cfg.get("budget_gain_per_level", 1)))
	var max_unspent := maxi(1, int(_build_progression_cfg.get("max_unspent_budget", 4)))
	_build_budget_total += gain
	if _build_budget_remaining() > max_unspent:
		_build_budget_total = _build_budget_spent + max_unspent

func _offer_levelup_choices() -> void:
	var options: Array[Dictionary] = []
	var blocked_reasons := {}
	var room := _current_room()
	var fixed_ids: Array = room.get("fixed_build_options", [])
	if not fixed_ids.is_empty():
		options = _roll_build_options_from_ids(fixed_ids)
		if not options.is_empty():
			_append_log("教学升级：本房间提供固定构筑选项。")
	if options.size() < LEVELUP_OPTION_COUNT:
		var extra := _roll_build_options(LEVELUP_OPTION_COUNT * 2)
		for node in extra:
			var node_id := String(node.get("id", ""))
			if _has_node_in_options(options, node_id):
				continue
			options.append(node)
			if options.size() >= LEVELUP_OPTION_COUNT:
				break
	if options.size() < LEVELUP_OPTION_COUNT:
		var exclude_ids := {}
		for option_node_variant in options:
			var option_node: Dictionary = option_node_variant
			var option_id := String(option_node.get("id", ""))
			if not option_id.is_empty():
				exclude_ids[option_id] = true
		var blocked_entries := _collect_blocked_build_options(LEVELUP_OPTION_COUNT - options.size(), exclude_ids)
		for entry_variant in blocked_entries:
			var entry: Dictionary = entry_variant
			var blocked_node: Dictionary = entry.get("node", {})
			if blocked_node.is_empty():
				continue
			options.append(blocked_node)
			blocked_reasons[options.size() - 1] = String(entry.get("reason", "当前不可选"))
	if options.is_empty():
		_append_log("当前可选构筑已耗尽（槽位/预算/前置标签或叠层达到限制）。")
		return
	_levelup_options = options
	_levelup_blocked_reasons = blocked_reasons
	_levelup_blocker_hint = _build_levelup_blocker_hint()
	_levelup_pending = true
	_append_log("等级提升 Lv.%d：请选择 1 个构筑（按 1/2/3 或点击按钮）。" % _run_level)

func _roll_build_options(count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for node in _build_nodes_catalog:
		var node_id := String(node.get("id", ""))
		if node_id.is_empty():
			continue
		if not _can_pick_node(node):
			continue
		var max_stack := maxi(1, int(node.get("max_stack", 1)))
		var owned_stack := int(_owned_build_stacks.get(node_id, 0))
		if owned_stack >= max_stack:
			continue
		pool.append(node)
	if pool.is_empty():
		return []

	var picked: Array[Dictionary] = []
	while picked.size() < count and not pool.is_empty():
		var idx := _weighted_node_index(pool)
		if idx < 0:
			idx = _rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked

func _weighted_node_index(pool: Array[Dictionary]) -> int:
	var total := 0.0
	for node in pool:
		total += maxf(0.01, float(node.get("weight", 1.0)) * _build_pick_weight(node))
	if total <= 0.0:
		return -1
	var roll := _rng.randf_range(0.0, total)
	var cursor := 0.0
	for i in range(pool.size()):
		cursor += maxf(0.01, float(pool[i].get("weight", 1.0)) * _build_pick_weight(pool[i]))
		if roll <= cursor:
			return i
	return pool.size() - 1

func _roll_build_options_from_ids(ids: Array) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for id_variant in ids:
		var node_id := String(id_variant)
		if node_id.is_empty():
			continue
		var node := _build_node_by_id(node_id)
		if node.is_empty():
			continue
		if not _can_pick_node(node):
			continue
		var max_stack := maxi(1, int(node.get("max_stack", 1)))
		var owned_stack := int(_owned_build_stacks.get(node_id, 0))
		if owned_stack >= max_stack:
			continue
		options.append(node)
		if options.size() >= LEVELUP_OPTION_COUNT:
			break
	return options

func _build_node_by_id(node_id: String) -> Dictionary:
	for node_variant in _build_nodes_catalog:
		var node: Dictionary = node_variant
		if String(node.get("id", "")) == node_id:
			return node
	return {}

func _has_node_in_options(options: Array[Dictionary], node_id: String) -> bool:
	for node_variant in options:
		var node: Dictionary = node_variant
		if String(node.get("id", "")) == node_id:
			return true
	return false

func _node_slot(node: Dictionary) -> String:
	var slot := String(node.get("slot", "passive"))
	if slot.is_empty():
		slot = "passive"
	return slot

func _can_pick_node_by_slot(node: Dictionary) -> bool:
	var slot := _node_slot(node)
	var limit := int(_build_slot_limits.get(slot, 99))
	if limit <= 0:
		return false
	var owned := int(_owned_slot_counts.get(slot, 0))
	return owned < limit

func _node_tier_cost(node: Dictionary) -> int:
	return maxi(1, int(node.get("tier_cost", 1)))

func _build_budget_remaining() -> int:
	return maxi(0, _build_budget_total - _build_budget_spent)

func _has_required_tags(node: Dictionary) -> bool:
	var required_tags: Array = node.get("required_tags", [])
	for tag_variant in required_tags:
		var tag := String(tag_variant)
		if int(_owned_build_tags.get(tag, 0)) <= 0:
			return false
	return true

func _can_pick_node(node: Dictionary) -> bool:
	if not _can_pick_node_by_slot(node):
		return false
	if _node_stack_full(node):
		return false
	if _node_tier_cost(node) > _build_budget_remaining():
		return false
	if not _has_required_tags(node):
		return false
	return true

func _node_stack_full(node: Dictionary) -> bool:
	var node_id := String(node.get("id", ""))
	if node_id.is_empty():
		return false
	var max_stack := maxi(1, int(node.get("max_stack", 1)))
	var owned_stack := int(_owned_build_stacks.get(node_id, 0))
	return owned_stack >= max_stack

func _node_missing_required_tags(node: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var required_tags: Array = node.get("required_tags", [])
	for tag_variant in required_tags:
		var tag := String(tag_variant)
		if int(_owned_build_tags.get(tag, 0)) <= 0:
			missing.append(tag)
	return missing

func _node_block_reason(node: Dictionary) -> String:
	if _node_stack_full(node):
		return "叠层已满"
	if not _can_pick_node_by_slot(node):
		var slot := _node_slot(node)
		return "%s槽位已满(%d/%d)" % [
			slot,
			int(_owned_slot_counts.get(slot, 0)),
			int(_build_slot_limits.get(slot, 0))
		]
	var cost := _node_tier_cost(node)
	var remaining := _build_budget_remaining()
	if cost > remaining:
		return "预算不足(%d>%d)" % [cost, remaining]
	var missing := _node_missing_required_tags(node)
	if not missing.is_empty():
		return "缺少标签:%s" % "/".join(missing)
	return ""

func _collect_blocked_build_options(count: int, exclude_ids: Dictionary) -> Array[Dictionary]:
	if count <= 0:
		return []
	var pool: Array[Dictionary] = []
	for node_variant in _build_nodes_catalog:
		var node: Dictionary = node_variant
		var node_id := String(node.get("id", ""))
		if node_id.is_empty() or bool(exclude_ids.get(node_id, false)):
			continue
		var reason := _node_block_reason(node)
		if reason.is_empty():
			continue
		pool.append({"node": node, "reason": reason})
	if pool.is_empty():
		return []
	var result: Array[Dictionary] = []
	while result.size() < count and not pool.is_empty():
		var idx := _rng.randi_range(0, pool.size() - 1)
		result.append(pool[idx])
		pool.remove_at(idx)
	return result

func _build_levelup_blocker_hint() -> String:
	if _levelup_blocked_reasons.is_empty():
		return "本轮候选均可选。"
	var unique_reasons := {}
	for reason_variant in _levelup_blocked_reasons.values():
		var reason := String(reason_variant)
		if reason.is_empty():
			continue
		unique_reasons[reason] = true
	var parts: Array[String] = []
	for reason_variant in unique_reasons.keys():
		parts.append(String(reason_variant))
	parts.sort()
	return "受限原因：" + "；".join(parts)

func _build_pick_weight(node: Dictionary) -> float:
	var weight := 1.0
	var tags: Array = node.get("tags", [])
	for tag_variant in tags:
		var tag := String(tag_variant)
		if _owned_build_tags.has(tag):
			weight *= 1.28
	var slot := _node_slot(node)
	if int(_owned_slot_counts.get(slot, 0)) <= 0:
		weight *= 1.08
	return clampf(weight, 0.4, 3.5)

func _on_build_option_pressed(index: int) -> void:
	if not _levelup_pending:
		return
	if index < 0 or index >= _levelup_options.size():
		return
	if _levelup_blocked_reasons.has(index):
		_append_log("该构筑当前不可选：%s" % String(_levelup_blocked_reasons.get(index, "受限")))
		return
	var node := _levelup_options[index]
	_apply_build_node(node)
	_levelup_options.clear()
	_levelup_blocked_reasons.clear()
	_levelup_blocker_hint = ""
	_levelup_pending = false

func _apply_build_node(node: Dictionary) -> void:
	var node_id := String(node.get("id", ""))
	if node_id.is_empty():
		return
	var cost := _node_tier_cost(node)
	if cost > _build_budget_remaining():
		_append_log("构筑预算不足：需要%d，当前剩余%d。" % [cost, _build_budget_remaining()])
		return
	_owned_build_stacks[node_id] = int(_owned_build_stacks.get(node_id, 0)) + 1
	var slot := _node_slot(node)
	_owned_slot_counts[slot] = int(_owned_slot_counts.get(slot, 0)) + 1
	_build_budget_spent += cost
	_register_node_tags(node.get("tags", []))

	var label := String(node.get("label", node_id))
	var tags_text := ", ".join(node.get("tags", []))
	if tags_text.is_empty():
		tags_text = "-"
	_append_log("构筑获得：%s（槽位:%s | 标签:%s | 消耗预算:%d）" % [label, slot, tags_text, cost])
	_apply_build_effect_bundle(node.get("effect", {}), "构筑：%s" % label)
	_try_activate_build_synergies()

func _apply_build_effect_bundle(effect: Dictionary, reason: String) -> void:
	if effect.is_empty():
		return
	var direct_effect := {}
	var modifier_logs: Array[String] = []
	for key_variant in effect.keys():
		var key := String(key_variant)
		match key:
			"fire_rate_mult":
				var before_fire := float(_build_modifiers.get("fire_rate_mult", 1.0))
				_build_modifiers["fire_rate_mult"] = maxf(0.35, before_fire + float(effect.get(key, 0.0)))
				modifier_logs.append("fire_rate_mult %.2f -> %.2f" % [before_fire, float(_build_modifiers.get("fire_rate_mult", 1.0))])
			"projectile_bonus":
				var before_projectile := int(_build_modifiers.get("projectile_bonus", 0))
				_build_modifiers["projectile_bonus"] = before_projectile + int(effect.get(key, 0))
				modifier_logs.append("projectile_bonus %d -> %d" % [before_projectile, int(_build_modifiers.get("projectile_bonus", 0))])
			"move_speed_bonus":
				var before_speed := float(_build_modifiers.get("move_speed_bonus", 0.0))
				_build_modifiers["move_speed_bonus"] = before_speed + float(effect.get(key, 0.0))
				modifier_logs.append("move_speed_bonus %.1f -> %.1f" % [before_speed, float(_build_modifiers.get("move_speed_bonus", 0.0))])
			"damage_reduction":
				var before_reduction := int(_build_modifiers.get("damage_reduction", 0))
				_build_modifiers["damage_reduction"] = before_reduction + int(effect.get(key, 0))
				modifier_logs.append("damage_reduction %d -> %d" % [before_reduction, int(_build_modifiers.get("damage_reduction", 0))])
			"bullet_damage_bonus":
				var before_damage := int(_build_modifiers.get("bullet_damage_bonus", 0))
				_build_modifiers["bullet_damage_bonus"] = before_damage + int(effect.get(key, 0))
				modifier_logs.append("bullet_damage_bonus %d -> %d" % [before_damage, int(_build_modifiers.get("bullet_damage_bonus", 0))])
			_:
				direct_effect[key] = effect.get(key)
	if not modifier_logs.is_empty():
		_append_log("%s：战斗修正 %s" % [reason, "；".join(modifier_logs)])
	if not direct_effect.is_empty():
		_apply_effect(direct_effect, reason)

func _register_node_tags(tags: Array) -> void:
	for tag_variant in tags:
		var tag := String(tag_variant)
		if tag.is_empty():
			continue
		_owned_build_tags[tag] = int(_owned_build_tags.get(tag, 0)) + 1

func _try_activate_build_synergies() -> void:
	for rule_variant in _build_synergy_rules:
		var rule: Dictionary = rule_variant
		var rule_id := String(rule.get("id", ""))
		if rule_id.is_empty() or bool(_active_synergy_ids.get(rule_id, false)):
			continue
		var required_tags: Array = rule.get("required_tags", [])
		if required_tags.is_empty():
			continue
		var all_hit := true
		for tag_variant in required_tags:
			var req_tag := String(tag_variant)
			if int(_owned_build_tags.get(req_tag, 0)) <= 0:
				all_hit = false
				break
		if not all_hit:
			continue
		_active_synergy_ids[rule_id] = true
		var label := String(rule.get("label", rule_id))
		_append_log("构筑协同激活：%s（需求:%s）" % [label, ", ".join(required_tags)])
		_apply_build_effect_bundle(rule.get("effect", {}), "协同：%s" % label)

func _on_room_cleared() -> void:
	if bool(_cleared.get(_current_room_id, false)):
		return
	_cleared[_current_room_id] = true
	_reset_battle_room_runtime()

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
	return "神像，请赐我稳固防护。"

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
		if key == "fate":
			continue
		var delta := int(effect.get(key, 0))
		var sign := "+" if delta >= 0 else ""
		parts.append("%s%s%d" % [key, sign, delta])
	if parts.is_empty():
		return "未产生数值变化。"
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
		if key == "fate":
			continue
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
	var reduction := int(_build_modifiers.get("damage_reduction", 0))
	var final_damage := maxi(1, base_damage - defense - reduction)
	var hp_before := int(_player_state.get("hp", 0))
	var hp_after := maxi(0, hp_before - final_damage)
	_player_state["hp"] = hp_after
	if hp_after <= 0 and not _game_over:
		_game_over = true
		_victory = false
	_append_log("%s：HP %d -> %d (-%d)" % [reason, hp_before, hp_after, final_damage])

func _update_ui() -> void:
	var room := _current_room()
	var core_stats := "HP %d | ATK %d | DEF %d | Keys %d | Corruption %d | Lv %d XP %d/%d" % [
		int(_player_state.get("hp", 0)),
		int(_player_state.get("atk", 0)),
		int(_player_state.get("def", 0)),
		int(_player_state.get("keys", 0)),
		int(_player_state.get("corruption", 0)),
		_run_level,
		_run_xp,
		_run_xp_to_next
	]
	_stats_label.text = core_stats
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = maxf(1.0, float(_run_xp_to_next))
	_xp_bar.value = clampf(float(_run_xp), 0.0, _xp_bar.max_value)
	_xp_bar_label.text = "经验条：%d / %d" % [_run_xp, _run_xp_to_next]
	_build_state_label.text = _build_compact_summary()
	_synergy_state_label.text = _build_synergy_summary()
	var room_type := String(room.get("type", ""))
	var room_cleared := bool(_cleared.get(_current_room_id, false))
	if room_type == "battle" and _battle_is_survival and not room_cleared:
		var cap_text := "%d/%d" % [_battle_spawned_total, _battle_spawn_total_limit]
		_room_label.text = "房间 %s（生存战） | 倒计时 %.1fs | 敌人 %d | 刷怪 %s" % [
			String(room.get("name", _current_room_id)),
			_battle_timer_remaining,
			_enemies.size(),
			cap_text
		]
		if _is_tutorial_active():
			_room_label.text += " | 教学 %d/4" % min(_tutorial_step_index() + 1, 4)
	else:
		_room_label.text = "房间 %s（%s） | 敌人剩余 %d | 已清空 %s" % [
			String(room.get("name", _current_room_id)),
			room_type,
			_enemies.size(),
			"是" if room_cleared else "否"
		]

	var hint := "WASD移动，左键射击，清房后穿门选路。"
	if _game_over:
		hint = "胜利完成地牢。" if _victory else "你已倒下。点击【重开本局】继续。"
	elif _levelup_pending:
		hint = "升级中：请从 3 个构筑中选择 1 个（按 1/2/3 或点击按钮）。"
	elif _is_tutorial_active():
		hint = _tutorial_hint_text()
	elif room_type == "battle" and _battle_is_survival and not room_cleared:
		if _battle_spawn_finished:
			hint = "刷怪已完成：清空余怪后即可通关本房间。"
		else:
			hint = "生存战进行中：坚持并清怪，刷满上限后结束。"
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
	if _is_tutorial_active():
		var hint_arrow := ">> " if (int(Time.get_ticks_msec() / 280) % 2) == 0 else "   "
		hint = hint_arrow + hint
	_hint_label.text = hint
	if _is_tutorial_active():
		var pulse := 0.82 + 0.18 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012))
		_hint_label.modulate = Color(1.0, 1.0, 0.92 + pulse * 0.08, 1.0)
	else:
		_hint_label.modulate = Color(1, 1, 1, 1)

	_marker_legend_label.text = "标识：怪(追击) | 远(远程) | 蓝球(XP) | 门(可通行) | 锁K(双向锁) | 神像(祈福) | 宝箱(大奖励)"
	_adjacent_preview_label.text = _build_adjacent_preview_text()
	_pray_button.visible = _can_pray_current_room()
	_refresh_prayer_panel()
	_refresh_levelup_panel()
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

func _is_game_input_locked() -> bool:
	return _is_prayer_input_active() or _levelup_pending

func _is_tutorial_upgrade_room() -> bool:
	var room := _current_room()
	return String(room.get("type", "")) == "battle" and bool(room.get("tutorial_upgrade", false))

func _is_tutorial_active() -> bool:
	return _is_tutorial_upgrade_room() and not bool(_cleared.get(_current_room_id, false))

func _is_tutorial_spawn_unlocked() -> bool:
	return not _is_tutorial_active() or (_tutorial_move_done and _tutorial_shots_fired >= TUTORIAL_SHOTS_REQUIRED)

func _tutorial_step_index() -> int:
	if not _is_tutorial_active():
		return -1
	if not _tutorial_move_done:
		return 0
	if _tutorial_shots_fired < TUTORIAL_SHOTS_REQUIRED:
		return 1
	if _levelup_pending:
		return 3
	if _run_level <= 1:
		return 2
	return 4

func _tutorial_hint_text() -> String:
	var step := _tutorial_step_index()
	match step:
		0:
			var moved := int(_player_pos.distance_to(_tutorial_spawn_pos))
			return "教学1/4：先移动。按WASD离开出生光圈（%d/%d）。" % [moved, int(TUTORIAL_MOVE_DISTANCE)]
		1:
			return "教学2/4：左键开火演示（%d/%d）。完成后开始刷怪。" % [_tutorial_shots_fired, TUTORIAL_SHOTS_REQUIRED]
		2:
			var remain := maxi(0, _run_xp_to_next - _run_xp)
			return "教学3/4：击败怪物并拾取经验晶体（XP %d/%d，已击败%d，预计还需%d只）。" % [_run_xp, _run_xp_to_next, _tutorial_kills, remain]
		3:
			return "教学4/4：从固定构筑中选1个（按1/2/3或点击按钮）。"
		4:
			return "教学完成：继续清怪并前往下一房间。"
		_:
			return "教学房进行中。"

func _sync_tutorial_step_log() -> void:
	if not _is_tutorial_active():
		return
	var step := _tutorial_step_index()
	if step == _tutorial_step_announced:
		return
	_tutorial_step_announced = step
	match step:
		0:
			_append_log("教学1/4：按WASD移动，离开出生光圈。")
		1:
			_append_log("教学2/4：按左键开火3次，完成后开始刷怪。")
		2:
			_append_log("教学3/4：击败怪物并拾取经验晶体，升到Lv2。")
		3:
			_append_log("教学4/4：请选择一个构筑升级。")
		4:
			_append_log("教学完成：通关本房间后前往下一关。")

func _draw_tutorial_world_guidance(rect: Rect2) -> void:
	var step := _tutorial_step_index()
	_draw_world_text(rect.position + Vector2(8, 60), "新手教学 %d/4" % min(step + 1, 4), Color(0.6, 0.86, 1.0))
	match step:
		0:
			draw_arc(_tutorial_spawn_pos, TUTORIAL_MOVE_DISTANCE, 0.0, TAU, 48, Color(0.6, 0.86, 1.0, 0.8), 2.0)
			_draw_world_text(_tutorial_spawn_pos + Vector2(-86, -26), "离开光圈：WASD移动", Color(0.65, 0.9, 1.0))
			_draw_guide_arrow(_tutorial_spawn_pos + Vector2(-TUTORIAL_MOVE_DISTANCE * 0.75, 0), Vector2(1.0, 0.0), Color(0.65, 0.9, 1.0), "先移动")
		1:
			_draw_world_text(rect.position + Vector2(8, 82), "左键开火 %d/%d（完成后开始刷怪）" % [_tutorial_shots_fired, TUTORIAL_SHOTS_REQUIRED], Color(1.0, 0.92, 0.45))
			_draw_guide_arrow(_player_pos + Vector2(38, -22), Vector2(-1.0, 0.3), Color(1.0, 0.92, 0.45), "左键开火")
		2:
			var remain := maxi(0, _run_xp_to_next - _run_xp)
			_draw_world_text(rect.position + Vector2(8, 82), "击败并拾取经验晶体：XP %d/%d，剩余约%d只" % [_run_xp, _run_xp_to_next, remain], Color(0.85, 1.0, 0.55))
			var enemy_target := _first_enemy_pos_or_center()
			_draw_guide_arrow(enemy_target + Vector2(0, -24), Vector2(0.0, 1.0), Color(0.85, 1.0, 0.55), "优先清怪")
		3:
			_draw_world_text(rect.position + Vector2(8, 82), "请立刻选择构筑（1/2/3）", Color(1.0, 0.85, 0.48))
		4:
			_draw_world_text(rect.position + Vector2(8, 82), "教学已完成，清怪后通过门继续。", Color(0.72, 1.0, 0.72))

func _draw_guide_arrow(tip: Vector2, direction: Vector2, color: Color, label: String = "") -> void:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		return
	var side := Vector2(-dir.y, dir.x)
	var phase := sin(float(Time.get_ticks_msec()) * 0.01)
	var wobble := dir * (phase * GUIDE_ARROW_WOBBLE)
	var animated_tip := tip + wobble
	var tail := animated_tip - dir * GUIDE_ARROW_LENGTH
	var head_a := animated_tip - dir * GUIDE_ARROW_HEAD + side * (GUIDE_ARROW_HEAD * 0.55)
	var head_b := animated_tip - dir * GUIDE_ARROW_HEAD - side * (GUIDE_ARROW_HEAD * 0.55)
	draw_line(tail, animated_tip, color, 3.0)
	draw_colored_polygon(PackedVector2Array([animated_tip, head_a, head_b]), color)
	if not label.is_empty():
		_draw_world_text(tail + Vector2(-6, -6), label, color)

func _first_enemy_pos_or_center() -> Vector2:
	if not _enemies.is_empty():
		var enemy: Dictionary = _enemies[0]
		return enemy.get("pos", _play_rect().get_center())
	return _play_rect().get_center()

func _build_compact_summary() -> String:
	var order := ["weapon", "passive", "godsend", "debt"]
	var labels := {"weapon": "武", "passive": "被", "godsend": "赐", "debt": "债"}
	var slot_parts: Array[String] = []
	for slot_variant in order:
		var slot := String(slot_variant)
		var owned := int(_owned_slot_counts.get(slot, 0))
		var limit := int(_build_slot_limits.get(slot, 0))
		slot_parts.append("%s%d/%d" % [String(labels.get(slot, slot)), owned, limit])
	var top_tags := _top_build_tags(3)
	var tag_text := "-"
	if not top_tags.is_empty():
		tag_text = ", ".join(top_tags)
	return "构筑槽[%s] | 预算%d | 标签[%s] | 协同%d" % [
		" ".join(slot_parts),
		_build_budget_remaining(),
		tag_text,
		_active_synergy_ids.size()
	]

func _build_synergy_summary() -> String:
	if _active_synergy_ids.is_empty():
		return "协同状态：无"
	var labels: Array[String] = []
	for rule_variant in _build_synergy_rules:
		var rule: Dictionary = rule_variant
		var rule_id := String(rule.get("id", ""))
		if not bool(_active_synergy_ids.get(rule_id, false)):
			continue
		labels.append(String(rule.get("label", rule_id)))
	if labels.is_empty():
		return "协同状态：%d个已激活" % _active_synergy_ids.size()
	return "协同状态：%s" % ", ".join(labels)

func _top_build_tags(limit: int) -> Array[String]:
	var items: Array[Dictionary] = []
	for tag_variant in _owned_build_tags.keys():
		var tag := String(tag_variant)
		items.append({"tag": tag, "count": int(_owned_build_tags.get(tag, 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("count", 0)) == int(b.get("count", 0)):
			return String(a.get("tag", "")) < String(b.get("tag", ""))
		return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	var result: Array[String] = []
	for i in range(mini(limit, items.size())):
		result.append("%s×%d" % [String(items[i].get("tag", "")), int(items[i].get("count", 0))])
	return result

func _refresh_levelup_panel() -> void:
	_levelup_panel.visible = _levelup_pending
	if not _levelup_pending:
		_levelup_title_label.text = "升级选择（3选1）"
		_levelup_panel.modulate = Color(1, 1, 1, 1)
		return
	_levelup_title_label.text = "升级选择（3选1）\n%s\n%s" % [_build_compact_summary(), _levelup_blocker_hint]
	if _is_tutorial_active():
		var panel_pulse := 0.78 + 0.22 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.014))
		_levelup_panel.modulate = Color(1.0, 1.0, 1.0, panel_pulse)
	else:
		_levelup_panel.modulate = Color(1, 1, 1, 1)
	var buttons := [_build_option_a, _build_option_b, _build_option_c]
	var arrow_prefix := ">> " if (int(Time.get_ticks_msec() / 260) % 2) == 0 else " > "
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		if i < _levelup_options.size():
			var node: Dictionary = _levelup_options[i]
			btn.visible = true
			var prefix := arrow_prefix if _is_tutorial_active() else ""
			var slot := _node_slot(node)
			var tags: Array = node.get("tags", [])
			var tags_text := ""
			if not tags.is_empty():
				tags_text = " | " + "/".join(tags)
			var req_tags: Array = node.get("required_tags", [])
			var req_text := ""
			if not req_tags.is_empty():
				req_text = " | 前置:" + "/".join(req_tags)
			var disabled_reason := String(_levelup_blocked_reasons.get(i, ""))
			var disabled_text := ""
			if not disabled_reason.is_empty():
				disabled_text = " | 不可选:" + disabled_reason
			btn.text = "%s%d) [%s|费%d] %s - %s%s%s%s" % [
				prefix,
				i + 1,
				slot,
				_node_tier_cost(node),
				String(node.get("label", "构筑")),
				String(node.get("description", "")),
				tags_text,
				req_text,
				disabled_text
			]
			btn.disabled = not disabled_reason.is_empty()
			btn.modulate = Color(0.62, 0.62, 0.62, 1.0) if btn.disabled else Color(1, 1, 1, 1)
		else:
			btn.visible = false
			btn.disabled = false
			btn.modulate = Color(1, 1, 1, 1)

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
	var hud_rect := _hud_panel.get_global_rect()
	var left := hud_rect.position.x + hud_rect.size.x + 20.0
	if hud_rect.size.x < 120.0:
		left = 370.0
	var top := 20.0
	var right_margin := 20.0
	var bottom_margin := 20.0
	var width := maxf(320.0, viewport.x - left - right_margin)
	var height := maxf(220.0, viewport.y - top - bottom_margin)
	return Rect2(left, top, width, height)

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
