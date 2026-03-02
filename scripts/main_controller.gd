extends Control

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const RuleEngineScript = preload("res://scripts/core/rule_engine.gd")
const IntentParserScript = preload("res://scripts/core/intent_parser.gd")
const NarrativeGeneratorScript = preload("res://scripts/core/narrative_generator.gd")

const GODS_PATH := "res://data/gods.json"
const REWARDS_PATH := "res://data/rewards.json"
const CURSES_PATH := "res://data/curses.json"
const ROOMS_PATH := "res://data/rooms.json"

@onready var _hud: HUDPanel = $RootMargin/RootVBox/ContentSplit/TopPanel/HUD
@onready var _room_panel: RoomPanel = $RootMargin/RootVBox/ContentSplit/TopPanel/RoomPanel
@onready var _dialog_panel: DialogPanel = $RootMargin/RootVBox/ContentSplit/DialogPanel

var _engine
var _intent_parser
var _narrative_generator

var _rooms_cfg: Dictionary = {}
var _room_sequence: Array = []
var _room_index := 0
var _turn_no := 1
var _room_resolved := false
var _game_over := false
var _player_state: Dictionary = {}

func _ready() -> void:
	_setup_ui_font()
	_room_panel.next_room_requested.connect(_on_next_room_requested)
	_dialog_panel.send_requested.connect(_on_send_requested)
	_boot()

func _boot() -> void:
	var gods_cfg: Dictionary = DataLoaderScript.load_json(GODS_PATH)
	var rewards_cfg: Dictionary = DataLoaderScript.load_json(REWARDS_PATH)
	var curses_cfg: Dictionary = DataLoaderScript.load_json(CURSES_PATH)
	_rooms_cfg = DataLoaderScript.load_json(ROOMS_PATH)

	if gods_cfg.is_empty() or rewards_cfg.is_empty() or curses_cfg.is_empty() or _rooms_cfg.is_empty():
		_dialog_panel.append_log("启动失败：JSON 数据加载不完整。")
		_dialog_panel.set_interaction_enabled(false)
		return

	_engine = RuleEngineScript.new()
	_engine.setup(gods_cfg, rewards_cfg, curses_cfg, _rooms_cfg)
	_intent_parser = IntentParserScript.new()
	_narrative_generator = NarrativeGeneratorScript.new()

	_player_state = _rooms_cfg.get("initial_state", {}).duplicate(true)
	if not _player_state.has("pending_effects"):
		_player_state["pending_effects"] = []
	_player_state["turn"] = 1
	_room_sequence = _rooms_cfg.get("demo_rooms", []).duplicate(true)
	_room_index = 0
	_turn_no = 1
	_room_resolved = false
	_game_over = false

	_dialog_panel.set_intent_json({})
	_dialog_panel.set_resolution_json({})
	_dialog_panel.set_narrative("等待输入一句话后结算。")
	_dialog_panel.set_pending_effects(_player_state.get("pending_effects", []))
	_dialog_panel.append_log("MVP 启动：按房间推进。每房先输入一句话进行结算，再点“进入下一房间”。")

	_render_all()
	_dialog_panel.clear_input()

func _on_send_requested(player_text: String) -> void:
	if _game_over:
		_dialog_panel.append_log("远征已结束，无法继续结算。")
		return
	if _room_sequence.is_empty():
		return
	if _room_resolved:
		_dialog_panel.append_log("当前房间已结算，请点击“进入下一房间”。")
		return

	var normalized_text := player_text
	if normalized_text.is_empty():
		normalized_text = "我谨慎前行，先求生存。"

	var intent_json: Dictionary = _intent_parser.parse_intent(normalized_text)
	intent_json["stance"] = _dialog_panel.get_selected_stance()
	_dialog_panel.set_intent_json(intent_json)
	_player_state["turn"] = _turn_no

	var room_context: Dictionary = _current_room()
	var resolution: Dictionary = _engine.resolve(_player_state, room_context, intent_json)
	_dialog_panel.set_resolution_json(resolution)

	var applied: Dictionary = _engine.apply_resolution(_player_state, resolution)
	_player_state = applied.get("state", _player_state)
	_dialog_panel.set_pending_effects(_player_state.get("pending_effects", []))

	var god_cfg: Dictionary = _engine.get_god_config(resolution.get("god_id", ""))
	var narrative: String = _narrative_generator.generate_narrative(god_cfg, resolution, normalized_text)
	_dialog_panel.set_narrative(narrative)

	_dialog_panel.append_log(_build_turn_log(room_context, normalized_text, intent_json, resolution, applied))
	_room_resolved = true

	if int(_player_state.get("hp", 0)) <= 0:
		_finish_run("你在第 %d 房倒下。%s" % [_room_index + 1, _build_ending_text()])

	_render_all()
	_dialog_panel.clear_input()

func _on_next_room_requested() -> void:
	if _game_over:
		_dialog_panel.append_log("结局已确定：%s" % _build_ending_text())
		return

	if not _room_resolved:
		_dialog_panel.append_log("当前房间未结算，已按白盒调试模式跳过。")

	if _is_last_room():
		_finish_run(_build_ending_text())
		return

	_room_index += 1
	_turn_no += 1
	_player_state["turn"] = _turn_no
	_room_resolved = false
	_dialog_panel.set_intent_json({})
	_dialog_panel.set_resolution_json({})
	_dialog_panel.set_narrative("已进入下一房间，等待你的输入。")
	_dialog_panel.set_pending_effects(_player_state.get("pending_effects", []))
	_dialog_panel.append_log("进入下一房间：%s" % _current_room().get("display_name", "未知房间"))
	_render_all()

func _render_all() -> void:
	if _room_sequence.is_empty():
		return
	_hud.set_state(_player_state, _turn_no, _room_index, _room_sequence.size())
	_room_panel.set_room(_current_room(), _room_index, _room_sequence.size(), _room_resolved, not _game_over)
	_dialog_panel.set_pending_effects(_player_state.get("pending_effects", []))
	if _is_last_room() and _room_resolved and not _game_over:
		_room_panel.set_next_button_text("查看结局")
	elif _game_over:
		_room_panel.set_next_button_text("远征结束")
	else:
		_room_panel.set_next_button_text("进入下一房间")

func _finish_run(reason: String) -> void:
	_game_over = true
	_dialog_panel.set_interaction_enabled(false)
	_dialog_panel.append_log("远征结束：%s" % reason)
	_render_all()

func _build_turn_log(room: Dictionary, text: String, intent_json: Dictionary, resolution: Dictionary, applied: Dictionary) -> String:
	var rewards: Array = resolution.get("reward_ids", [])
	var curses: Array = resolution.get("curse_ids", [])
	var notes: Array = resolution.get("notes", [])
	var apply_logs: Array = applied.get("logs", [])
	var triggered: Array = applied.get("triggered_reports", [])
	var combat_log: Array = resolution.get("combat_log", [])
	var pool_debug: Dictionary = resolution.get("pool_debug", {})
	var pending: Array = _player_state.get("pending_effects", [])

	return "[Room %d - %s]\n输入：%s\nstance=%s wish=%s tone=%s risk=%s\nreward_ids=%s\ncurse_ids=%s\npool_debug=%s\ncombat_log=%s\nnotes=%s\ntriggered=%s\npending=%s\napply=%s\nstate=%s" % [
		_room_index + 1,
		room.get("display_name", room.get("id", "?")),
		text,
		intent_json.get("stance", "restraint"),
		intent_json.get("wish_type", "knowledge"),
		intent_json.get("tone", "calm"),
		intent_json.get("risk_preference", "mid"),
		JSON.stringify(rewards, "", false),
		JSON.stringify(curses, "", false),
		JSON.stringify(pool_debug, "", false),
		JSON.stringify(combat_log, "", false),
		JSON.stringify(notes, "", false),
		JSON.stringify(triggered, "", false),
		JSON.stringify(pending, "", false),
		JSON.stringify(apply_logs, "", false),
		JSON.stringify(_player_state, "", false)
	]

func _build_ending_text() -> String:
	if int(_player_state.get("hp", 0)) <= 0:
		return "结局：殒落。你未能走出低语回廊。"

	var corruption := int(_player_state.get("corruption", 0))
	var hp := int(_player_state.get("hp", 0))
	var keys := int(_player_state.get("keys", 0))
	if corruption >= 8:
		return "结局：堕蚀同化。你被邪灵契约反噬。"
	if hp >= 20 and corruption <= 3 and keys >= 1:
		return "结局：誓约归还。你带着神钥与秩序离开。"
	return "结局：代价平衡。你带着伤痕与答案离开。"

func _current_room() -> Dictionary:
	if _room_sequence.is_empty():
		return {}
	return _room_sequence[_room_index]

func _is_last_room() -> bool:
	return _room_index >= _room_sequence.size() - 1

func _setup_ui_font() -> void:
	var ui_font: FontFile = _find_cjk_font()
	if ui_font == null:
		push_warning("No CJK system font found, Chinese text may not render correctly.")
		return

	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 20
	theme = ui_theme
	ThemeDB.fallback_font = ui_font
	ThemeDB.fallback_font_size = 20

func _find_cjk_font() -> FontFile:
	var cjk_font: FontFile = null
	var latin_font: FontFile = null
	var common_paths: Array[String] = [
		"res://assets/fonts/HiraginoSansGB.ttc",
		"res://assets/fonts/NotoSansSC-Regular.ttf",
		"res://assets/fonts/SourceHanSansSC-Regular.otf",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
		"/System/Library/Fonts/Supplemental/NISC18030.ttf",
		"/System/Library/Fonts/Supplemental/Arial.ttf",
		"/System/Library/Fonts/STHeiti Light.ttc",
		"/System/Library/Fonts/Songti.ttc",
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/arial.ttf",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
		"/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
	]
	for path in common_paths:
		var file_font: FontFile = _load_font_from_path(path)
		if file_font == null:
			continue
		var has_cjk := file_font.has_char("命".unicode_at(0))
		var has_latin := file_font.has_char("A".unicode_at(0))
		if has_cjk and has_latin:
			return file_font
		if has_cjk and cjk_font == null:
			cjk_font = file_font
		if has_latin and latin_font == null:
			latin_font = file_font

	if cjk_font != null:
		if latin_font != null:
			cjk_font.set_fallbacks([latin_font])
		return cjk_font
	return null

func _load_font_from_path(path: String) -> FontFile:
	if path.is_empty():
		return null
	if not FileAccess.file_exists(path):
		return null

	var font_file := FontFile.new()
	var err := font_file.load_dynamic_font(path)
	if err != OK:
		return null
	return font_file
