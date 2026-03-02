extends Control

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const DialogueAIGatewayScript = preload("res://scripts/ai/dialogue_ai_gateway.gd")
const IntentParserScript = preload("res://scripts/core/intent_parser.gd")
const NarrativeGeneratorScript = preload("res://scripts/core/narrative_generator.gd")
const AI_PROVIDER_PATH := "res://data/ai_provider.json"

@onready var _provider_label: Label = $Margin/VBox/ConfigPanel/ConfigVBox/ProviderLabel
@onready var _model_label: Label = $Margin/VBox/ConfigPanel/ConfigVBox/ModelLabel
@onready var _endpoint_label: Label = $Margin/VBox/ConfigPanel/ConfigVBox/EndpointLabel
@onready var _key_label: Label = $Margin/VBox/ConfigPanel/ConfigVBox/KeyLabel
@onready var _input_line: LineEdit = $Margin/VBox/InputRow/PromptInput
@onready var _test_button: Button = $Margin/VBox/InputRow/TestButton
@onready var _status_label: Label = $Margin/VBox/StatusLabel
@onready var _loading_label: Label = $Margin/VBox/LoadingLabel
@onready var _output_box: RichTextLabel = $Margin/VBox/OutputBox

var _ai_cfg: Dictionary = {}
var _gateway: DialogueAIGateway = null
var _testing := false
var _loading_elapsed := 0.0

func _ready() -> void:
	_setup_ui_font()
	_test_button.pressed.connect(_on_test_button_pressed)
	_reload_provider_config()
	_render_config_summary()
	_status_label.text = "等待检测。点击【检测 OpenAI API】。"
	_loading_label.visible = false

func _process(delta: float) -> void:
	if not _testing:
		return
	_loading_elapsed += delta
	var phase := int(floor(_loading_elapsed * 5.0)) % 4
	_loading_label.text = "检测中%s" % ".".repeat(phase)

func _reload_provider_config() -> void:
	_ai_cfg = DataLoaderScript.load_json(AI_PROVIDER_PATH)
	if _ai_cfg.is_empty():
		_ai_cfg = {
			"provider": "openai",
			"api_key_env": "OPENAI_API_KEY",
			"chat_completions_url": "https://api.openai.com/v1/chat/completions",
			"model": "gpt-4.1-mini",
			"timeout_sec": 12,
			"deity_prompt_dir": "res://data/prompts"
		}

func _render_config_summary() -> void:
	var provider := String(_ai_cfg.get("provider", "stub"))
	var model := String(_ai_cfg.get("model", ""))
	var endpoint := String(_ai_cfg.get("chat_completions_url", ""))
	var key_env := String(_ai_cfg.get("api_key_env", "OPENAI_API_KEY"))
	var key := OS.get_environment(key_env).strip_edges()
	_provider_label.text = "Provider: %s（检测会强制使用 openai）" % provider
	_model_label.text = "Model: %s" % model
	_endpoint_label.text = "Endpoint: %s" % endpoint
	_key_label.text = "Key: %s（%s）" % [key_env, "已设置" if not key.is_empty() else "未设置"]

func _set_testing_state(value: bool) -> void:
	_testing = value
	_test_button.disabled = value
	_input_line.editable = not value
	_loading_elapsed = 0.0
	_loading_label.visible = value
	if not value:
		_loading_label.text = ""

func _on_test_button_pressed() -> void:
	if _testing:
		return
	_reload_provider_config()
	_render_config_summary()
	_output_box.text = ""
	_set_testing_state(true)
	_status_label.text = "开始检测 OpenAI API..."

	var report: Dictionary = await _run_openai_probe()
	_set_testing_state(false)

	var ok := bool(report.get("ok", false))
	if ok:
		_status_label.text = "检测通过：OpenAI API 可用。"
	else:
		_status_label.text = "检测失败：%s" % String(report.get("error", "unknown"))

	_output_box.text = _build_report_text(report)

func _run_openai_probe() -> Dictionary:
	var forced_cfg := _ai_cfg.duplicate(true)
	forced_cfg["provider"] = "openai"
	var key_env := String(forced_cfg.get("api_key_env", "OPENAI_API_KEY"))
	var key := OS.get_environment(key_env).strip_edges()
	if key.is_empty():
		return {
			"ok": false,
			"error": "missing_api_key",
			"details": "环境变量 %s 未设置。" % key_env
		}

	if _gateway != null and is_instance_valid(_gateway):
		_gateway.queue_free()
	_gateway = DialogueAIGatewayScript.new()
	add_child(_gateway)
	_gateway.setup(forced_cfg, IntentParserScript.new(), NarrativeGeneratorScript.new(), int(Time.get_unix_time_from_system()))

	var user_prompt := _input_line.text.strip_edges()
	if user_prompt.is_empty():
		user_prompt = "索露恩神像，请回应我。"

	var god_cfg := {
		"id": "solune",
		"name": "索露恩",
		"persona": "誓约与晨光之神",
		"speech_style": "庄重、温和、判词明确"
	}
	var resolution := {
		"reward_ids": ["boon_oath_guard"],
		"curse_ids": [],
		"pending_effects_preview": []
	}

	var rsp: Dictionary = await _gateway.generate_narrative(god_cfg, resolution, user_prompt, [])
	var provider := String(rsp.get("provider", ""))
	var fallback_used := bool(rsp.get("fallback_used", true))
	var warnings: Array = rsp.get("warnings", [])
	var text := String(rsp.get("text", "")).strip_edges()

	if provider == "openai" and not fallback_used and not text.is_empty():
		return {
			"ok": true,
			"provider": provider,
			"fallback_used": fallback_used,
			"text": text,
			"warnings": warnings
		}

	return {
		"ok": false,
		"error": "openai_unavailable_or_fallback",
		"provider": provider,
		"fallback_used": fallback_used,
		"text": text,
		"warnings": warnings
	}

func _build_report_text(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("=== OpenAI API 检测报告 ===")
	lines.append("ok: %s" % String(report.get("ok", false)))
	lines.append("provider: %s" % String(report.get("provider", "-")))
	lines.append("fallback_used: %s" % String(report.get("fallback_used", false)))
	if report.has("error"):
		lines.append("error: %s" % String(report.get("error", "")))
	if report.has("details"):
		lines.append("details: %s" % String(report.get("details", "")))
	var warnings: Array = report.get("warnings", [])
	if not warnings.is_empty():
		lines.append("warnings:")
		for warning_variant in warnings:
			lines.append("- %s" % String(warning_variant))
	lines.append("")
	lines.append("deity_response:")
	lines.append(String(report.get("text", "(empty)")))
	return "\n".join(lines)

func _setup_ui_font() -> void:
	var font_file: FontFile = _find_cjk_font()
	if font_file == null:
		push_warning("AIApiProbe: No CJK font found, Chinese text may not render correctly.")
		return
	var ui_theme := Theme.new()
	ui_theme.default_font = font_file
	ui_theme.default_font_size = 18
	theme = ui_theme
	ThemeDB.fallback_font = font_file
	ThemeDB.fallback_font_size = 18

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
