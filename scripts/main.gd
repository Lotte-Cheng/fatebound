extends Control

const GAME_CONFIG_PATH := "res://data/game_config.json"
const ENTITIES_PATH := "res://data/entities.json"
const AI_CONFIG_PATH := "res://data/ai_stub.json"
const DataLoaderScript = preload("res://scripts/data_loader.gd")
const RuleEngineScript = preload("res://scripts/rule_engine.gd")
const AIStubScript = preload("res://scripts/ai_stub.gd")

@onready var _room_label: Label = $RootMargin/RootVBox/RoomLabel
@onready var _room_detail_label: Label = $RootMargin/RootVBox/RoomDetailLabel
@onready var _state_label: Label = $RootMargin/RootVBox/StateLabel
@onready var _intent_json: RichTextLabel = $RootMargin/RootVBox/IntentBox/IntentVBox/IntentJson
@onready var _narrative_label: RichTextLabel = $RootMargin/RootVBox/NarrativeBox/NarrativeVBox/NarrativeLabel
@onready var _log_label: RichTextLabel = $RootMargin/RootVBox/LogBox/LogVBox/LogLabel
@onready var _action_input: LineEdit = $RootMargin/RootVBox/InputRow/ActionInput
@onready var _submit_button: Button = $RootMargin/RootVBox/InputRow/SubmitButton

var _rule_engine
var _ai_stub

func _ready() -> void:
	_setup_ui_font()
	_submit_button.pressed.connect(_on_submit_pressed)
	_action_input.text_submitted.connect(_on_action_input_text_submitted)
	_boot_game()

func _boot_game() -> void:
	var game_config: Dictionary = DataLoaderScript.load_json(GAME_CONFIG_PATH)
	var entities_config: Dictionary = DataLoaderScript.load_json(ENTITIES_PATH)
	var ai_config: Dictionary = DataLoaderScript.load_json(AI_CONFIG_PATH)

	if game_config.is_empty() or entities_config.is_empty() or ai_config.is_empty():
		_show_boot_error("数据加载失败，请检查 res://data/*.json")
		return

	_rule_engine = RuleEngineScript.new()
	_rule_engine.setup(game_config, entities_config)

	_ai_stub = AIStubScript.new()
	_ai_stub.setup(ai_config)

	_log_label.clear()
	_append_log("Fatebound Whitebox MVP 已启动。")
	_append_log("输入一句话并提交：AI 只会解析意图 JSON + 生成叙事文本。")

	_intent_json.text = "{}"
	_narrative_label.text = "等待你的行动..."
	_render_state()
	_render_turn_context()
	_action_input.grab_focus()

func _show_boot_error(message: String) -> void:
	_submit_button.disabled = true
	_action_input.editable = false
	_room_label.text = "启动失败"
	_room_detail_label.text = message
	_state_label.text = ""
	_intent_json.text = "{}"
	_narrative_label.text = ""
	_log_label.text = message

func _on_action_input_text_submitted(_new_text: String) -> void:
	_on_submit_pressed()

func _on_submit_pressed() -> void:
	if _rule_engine == null or _ai_stub == null:
		return
	if _rule_engine.is_finished():
		return

	var player_text: String = _action_input.text.strip_edges()
	if player_text.is_empty():
		player_text = "我保持沉默，观察局势。"

	var context_before: Dictionary = _rule_engine.get_turn_context()
	var intent_json: Dictionary = _ai_stub.parse_intent(player_text, context_before)
	_intent_json.text = JSON.stringify(intent_json, "\t")

	var turn_result: Dictionary = _rule_engine.process_turn(intent_json)
	var narrative: String = _ai_stub.generate_narrative(player_text, context_before, intent_json, turn_result)
	_narrative_label.text = narrative

	_append_turn_log(context_before, player_text, intent_json, turn_result)
	_render_state()
	_render_turn_context()
	_action_input.clear()
	_action_input.grab_focus()

	if bool(turn_result.get("finished", false)):
		_submit_button.disabled = true
		_action_input.editable = false
		_append_log("游戏结束：%s" % turn_result.get("finish_reason", "未知"))

func _render_state() -> void:
	if _rule_engine == null:
		return
	var state: Dictionary = _rule_engine.get_state()
	var inventory: Dictionary = state.get("inventory", {})
	_state_label.text = "HP %d | ATK %d | DEF %d | Corruption %d | Keys %d" % [
		int(state.get("hp", 0)),
		int(state.get("atk", 0)),
		int(state.get("def", 0)),
		int(state.get("corruption", 0)),
		int(inventory.get("keys", 0))
	]

func _render_turn_context() -> void:
	if _rule_engine == null:
		return
	var context: Dictionary = _rule_engine.get_turn_context()
	var turn_no: int = int(context.get("turn", 1))
	var room_display: String = String(context.get("room_display_name", context.get("room_type", "未知房间")))
	_room_label.text = "回合 %d | 当前房间：%s" % [turn_no, room_display]

	var room_type: String = String(context.get("room_type", ""))
	var room_data: Dictionary = context.get("context", {})
	match room_type:
		"combat_room":
			var encounter: Dictionary = room_data.get("encounter", {})
			_room_detail_label.text = "遭遇敌人：%s（ATK %d / DEF %d）" % [
				encounter.get("name", "未知敌人"),
				int(encounter.get("atk", 0)),
				int(encounter.get("def", 0))
			]
		"god_room":
			_room_detail_label.text = "%s（%s）\n%s" % [
				room_data.get("entity_name", "未知存在"),
				room_data.get("entity_role", "unknown"),
				room_data.get("entity_persona", "")
			]
		"secret_room":
			_room_detail_label.text = "密室需要钥匙才能开启。"
		_:
			_room_detail_label.text = ""

func _append_turn_log(context_before: Dictionary, player_text: String, intent_json: Dictionary, turn_result: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("[回合 %d] %s" % [
		int(turn_result.get("turn", 0)),
		String(context_before.get("room_display_name", context_before.get("room_type", "房间")))
	])
	lines.append("输入：%s" % player_text)
	lines.append("意图：%s" % intent_json.get("intent", "questioning"))

	var events: Array = turn_result.get("events", [])
	if not events.is_empty():
		lines.append("事件：%s" % " | ".join(events))

	var effects: Array = turn_result.get("applied_effects", [])
	if effects.is_empty():
		lines.append("效果：无")
	else:
		var effect_labels: Array[String] = []
		for effect in effects:
			effect_labels.append(String(effect.get("label", "effect")))
		lines.append("效果：%s" % "；".join(effect_labels))

	if String(turn_result.get("next_room", "")).is_empty():
		lines.append("下一房间：-")
	else:
		lines.append("下一房间：%s" % turn_result.get("next_room", ""))

	_append_log("\n".join(lines))

func _append_log(message: String) -> void:
	if _log_label.text.is_empty():
		_log_label.text = message
	else:
		_log_label.text += "\n\n" + message

func _setup_ui_font() -> void:
	var font_file: FontFile = _find_cjk_font()
	if font_file == null:
		push_warning("No CJK system font found, Chinese text may not render correctly.")
		return

	var ui_theme := Theme.new()
	ui_theme.default_font = font_file
	ui_theme.default_font_size = 20
	theme = ui_theme
	ThemeDB.fallback_font = font_file
	ThemeDB.fallback_font_size = 20

func _find_cjk_font() -> FontFile:
	var cjk_font: FontFile = null
	var latin_font: FontFile = null
	var common_paths: Array[String] = [
		"res://assets/fonts/NotoSansSC-Regular.ttf",
		"res://assets/fonts/SourceHanSansSC-Regular.otf",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
		"/System/Library/Fonts/Supplemental/NISC18030.ttf",
		"/System/Library/Fonts/Supplemental/Arial.ttf",
		"/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/PingFangUI.ttc",
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

	var names: Array[String] = [
		"Arial Unicode MS",
		"PingFang SC",
		"Hiragino Sans GB",
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Noto Sans",
		"Arial"
	]
	for font_name in names:
		var path: String = OS.get_system_font_path(font_name)
		var font_file: FontFile = _load_font_from_path(path)
		if font_file == null:
			continue
		var has_cjk := font_file.has_char("命".unicode_at(0))
		var has_latin := font_file.has_char("A".unicode_at(0))
		if has_cjk and has_latin:
			return font_file
		if has_cjk and cjk_font == null:
			cjk_font = font_file
		if has_latin and latin_font == null:
			latin_font = font_file

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
