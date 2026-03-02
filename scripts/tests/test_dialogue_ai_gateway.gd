extends SceneTree

const IntentParserScript = preload("res://scripts/core/intent_parser.gd")
const NarrativeGeneratorScript = preload("res://scripts/core/narrative_generator.gd")
const DialogueAIGatewayScript = preload("res://scripts/ai/dialogue_ai_gateway.gd")

func _init() -> void:
	var intent_parser = IntentParserScript.new()
	var narrative_generator = NarrativeGeneratorScript.new()
	var gateway = DialogueAIGatewayScript.new()
	root.add_child(gateway)

	var cfg := {
		"provider": "openai",
		"api_key_env": "OPENAI_API_KEY_SHOULD_NOT_EXIST",
		"chat_completions_url": "https://api.openai.com/v1/chat/completions",
		"model": "gpt-4.1-mini",
		"timeout_sec": 2
	}
	gateway.setup(cfg, intent_parser, narrative_generator, 1234)

	var intent_rsp: Dictionary = await gateway.parse_intent("请赐我钥匙并让我活下去", {"retry_count": 0})
	if not bool(intent_rsp.get("ok", false)):
		push_error("[FAIL] parse_intent returned not ok")
		quit(1)
		return
	if bool(intent_rsp.get("fallback_used", true)):
		push_error("[FAIL] expected fallback_used=false because intent parser is local")
		quit(1)
		return
	if String(intent_rsp.get("provider", "")) != "stub":
		push_error("[FAIL] expected provider=stub after fallback")
		quit(1)
		return

	var resolution := {
		"god_id": "solune",
		"stance": "restraint",
		"reward_ids": ["boon_oath_guard"],
		"curse_ids": [],
		"delta_preview": {"def": 1},
		"pending_effects_preview": []
	}
	var narrative_rsp: Dictionary = await gateway.generate_narrative({
		"name": "索露恩",
		"persona": "誓约与晨光",
		"speech_style": "庄重"
	}, resolution, "请给我防护", [])
	if String(narrative_rsp.get("text", "")).strip_edges().is_empty():
		push_error("[FAIL] narrative text is empty")
		quit(1)
		return

	var suggestions: Array[String] = gateway.suggest_requests(
		{"name": "索露恩", "favored_requests": ["守护"]},
		{"hp": 8, "keys": 0},
		{
			"suggestion_templates": {
				"restraint": ["我愿克制祈求，请赐我稳妥守护。"],
				"pact": ["我愿交易部分代价，换取当前最需要的增益。"],
				"blasphemy": ["我现在就要更高收益，代价由我承担。"]
			}
		},
		3,
		"restraint"
	)
	if suggestions.is_empty():
		push_error("[FAIL] suggestions should not be empty")
		quit(1)
		return

	print("[PASS] DialogueAIGateway fallback and suggestion test finished.")
	quit(0)
