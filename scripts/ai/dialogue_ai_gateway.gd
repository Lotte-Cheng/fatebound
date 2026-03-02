extends Node
class_name DialogueAIGateway

var _config: Dictionary = {}
var _intent_parser
var _narrative_generator
var _rng := RandomNumberGenerator.new()
var _deity_prompt_dir := "res://data/prompts"
var _deity_prompt_cache: Dictionary = {}

func setup(config: Dictionary, intent_parser, narrative_generator, seed: int = 1) -> void:
	_config = config.duplicate(true)
	_intent_parser = intent_parser
	_narrative_generator = narrative_generator
	_rng.seed = seed
	_deity_prompt_dir = String(_config.get("deity_prompt_dir", "res://data/prompts")).trim_suffix("/")
	_deity_prompt_cache.clear()

func provider_name() -> String:
	return String(_config.get("provider", "stub")).to_lower()

func parse_intent(player_text: String, context: Dictionary = {}) -> Dictionary:
	var local_intent: Dictionary = _intent_parser.parse_intent(player_text)
	return {
		"ok": true,
		"provider": "stub",
		"fallback_used": false,
		"warnings": [],
		"intent": local_intent
	}

func generate_narrative(god_cfg: Dictionary, resolution: Dictionary, player_text: String, recent_dialogue: Array = []) -> Dictionary:
	var preferred_provider := provider_name()
	var fallback_text: String = _narrative_generator.generate_narrative(god_cfg, resolution, player_text)
	var safe_fallback := _sanitize_narrative_text(fallback_text, god_cfg, resolution, player_text)
	var warnings: Array[String] = []
	var god_id := String(god_cfg.get("id", ""))
	var deity_prompt := _load_deity_prompt(god_id)

	if preferred_provider == "openai":
		var online := await _generate_narrative_openai(god_cfg, resolution, player_text, recent_dialogue, deity_prompt)
		if bool(online.get("ok", false)):
			var text := _sanitize_narrative_text(String(online.get("text", "")), god_cfg, resolution, player_text)
			if _narrative_whitelist_passes(text):
				return {
					"ok": true,
					"provider": "openai",
					"fallback_used": false,
					"warnings": warnings,
					"text": text
				}
			warnings.append("openai narrative rejected by whitelist")
		else:
			warnings.append("openai narrative failed: %s" % String(online.get("error", "unknown")))

	return {
		"ok": true,
		"provider": "stub",
		"fallback_used": preferred_provider == "openai",
		"warnings": warnings,
		"text": safe_fallback
	}

func suggest_requests(god_cfg: Dictionary, player_state: Dictionary, dialogue_cfg: Dictionary, count: int, preferred_stance: String) -> Array[String]:
	var templates_variant: Variant = dialogue_cfg.get("suggestion_templates", [])
	var candidates: Array[String] = []
	var god_name := String(god_cfg.get("name", "神明"))
	var favored: Array = god_cfg.get("favored_requests", [])

	if typeof(templates_variant) == TYPE_ARRAY:
		for text_variant in templates_variant:
			var text := String(text_variant).strip_edges()
			if text.is_empty() or candidates.has(text):
				continue
			candidates.append(text)
	elif typeof(templates_variant) == TYPE_DICTIONARY:
		var templates_cfg: Dictionary = templates_variant
		var stance_order := [preferred_stance, "restraint", "pact", "blasphemy"]
		for stance_variant in stance_order:
			var stance := String(stance_variant)
			if not templates_cfg.has(stance):
				continue
			for text_variant in templates_cfg.get(stance, []):
				var text := String(text_variant).strip_edges()
				if text.is_empty() or candidates.has(text):
					continue
				candidates.append(text)

	if candidates.is_empty():
		candidates = [
			"请给我当前最需要的生存能力。",
			"我愿承担一部分代价，换取稳定收益。",
			"若风险可控，请赐我更强战力。"
		]

	var hp := int(player_state.get("hp", 0))
	var keys := int(player_state.get("keys", 0))
	if hp <= 10:
		candidates.insert(0, "%s，我生命垂危，请优先赐予治疗与防护。" % god_name)
	if keys <= 0:
		candidates.insert(0, "%s，我缺少钥匙，请给我开启封印道路的机会。" % god_name)
	if not favored.is_empty():
		candidates.insert(0, "%s，我愿以%s为誓，请回应我的请求。" % [god_name, String(favored[0])])

	var result: Array[String] = []
	for text in candidates:
		if result.has(text):
			continue
		result.append(text)
		if result.size() >= maxi(1, count):
			break
	return result

func _parse_intent_openai(player_text: String, context: Dictionary) -> Dictionary:
	var schema: Dictionary = _config.get("intent_schema", {})
	var prompt_ctx := JSON.stringify(context, "", false)
	var messages: Array = [
		{
			"role": "system",
			"content": "You are an intent parser. Return strict JSON only."
		},
		{
			"role": "user",
			"content": "Context: %s\nPlayer text: %s\nReturn intent JSON." % [prompt_ctx, player_text]
		}
	]

	var retries := maxi(0, int(context.get("retry_count", int(_config.get("openai_retry_count", 1)))))
	for i in range(retries + 1):
		var rsp := await _chat_completion(messages, float(_config.get("temperature_intent", 0.0)), schema)
		if not bool(rsp.get("ok", false)):
			continue
		var content := String(rsp.get("content", ""))
		var parsed := _parse_json_like_text(content)
		if parsed.is_empty():
			continue
		var validation: Dictionary = _intent_parser.validate_schema(parsed)
		if bool(validation.get("ok", false)):
			parsed["schema_fallback"] = false
			parsed["schema_errors"] = []
			parsed["raw_text"] = player_text
			return {"ok": true, "intent": parsed}
	return {"ok": false, "error": "invalid_or_unavailable_openai_intent"}

func _generate_narrative_openai(god_cfg: Dictionary, resolution: Dictionary, player_text: String, recent_dialogue: Array, deity_prompt: String) -> Dictionary:
	var system_prompt := _build_narrative_system_prompt(god_cfg, deity_prompt)
	var outcome_summary := _build_outcome_summary(resolution)
	var recent_lines := _build_recent_dialogue_lines(recent_dialogue, 4)
	var messages: Array = [
		{
			"role": "system",
			"content": system_prompt
		},
		{
			"role": "user",
			"content": "Player says: %s\nRecent dialogue:\n%s\nOutcome tone (do not expose mechanics): %s\nReply as deity only." % [
				player_text,
				recent_lines,
				outcome_summary
			]
		}
	]
	var rsp := await _chat_completion(messages, float(_config.get("temperature_narrative", 0.6)), {})
	if not bool(rsp.get("ok", false)):
		return rsp
	var content := String(rsp.get("content", "")).strip_edges()
	if content.is_empty():
		return {"ok": false, "error": "empty_narrative"}
	return {"ok": true, "text": content}

func _build_narrative_system_prompt(god_cfg: Dictionary, deity_prompt: String) -> String:
	var god_name := String(god_cfg.get("name", "神明"))
	var persona := String(god_cfg.get("persona", ""))
	var style := String(god_cfg.get("speech_style", ""))
	var lines: Array[String] = [
		"You are roleplaying a deity in a game dialogue.",
		"Reply in Chinese, 2-4 short sentences, in-character.",
		"Do not output JSON.",
		"Hard rule: never invent gameplay effects or stat changes.",
		"Never mention reward/curse/rules/JSON/delta/ids/logs/numbers.",
		"Only produce immersive in-character dialogue."
	]
	if not deity_prompt.is_empty():
		lines.append("Deity Prompt:\n%s" % deity_prompt)
	else:
		lines.append("Deity: %s | Persona: %s | Style: %s" % [god_name, persona, style])
	return "\n".join(lines)

func _build_outcome_summary(resolution: Dictionary) -> String:
	var reward_count := int((resolution.get("reward_ids", []) as Array).size())
	var curse_count := int((resolution.get("curse_ids", []) as Array).size())
	var debt_count := int((resolution.get("pending_effects_preview", []) as Array).size())
	if reward_count > curse_count and debt_count == 0:
		return "favorable"
	if curse_count > reward_count or debt_count > 0:
		return "ominous"
	return "neutral"

func _build_recent_dialogue_lines(recent_dialogue: Array, limit: int) -> String:
	if recent_dialogue.is_empty():
		return "(empty)"
	var start := maxi(0, recent_dialogue.size() - maxi(1, limit))
	var lines: Array[String] = []
	for i in range(start, recent_dialogue.size()):
		var row: Dictionary = recent_dialogue[i]
		var req := String(row.get("request", "")).strip_edges()
		if not req.is_empty():
			lines.append("- 玩家: %s" % req)
	return "\n".join(lines) if not lines.is_empty() else "(empty)"

func _load_deity_prompt(god_id: String) -> String:
	var cache_key := god_id if not god_id.is_empty() else "__default__"
	if _deity_prompt_cache.has(cache_key):
		return String(_deity_prompt_cache.get(cache_key, ""))

	var text := ""
	if not god_id.is_empty():
		text = _read_prompt_file("%s/%s.prompt.txt" % [_deity_prompt_dir, god_id])
	if text.is_empty():
		text = _read_prompt_file("%s/default.prompt.txt" % _deity_prompt_dir)
	_deity_prompt_cache[cache_key] = text
	return text

func _read_prompt_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()

func _chat_completion(messages: Array, temperature: float, json_schema: Dictionary) -> Dictionary:
	var api_key_env := String(_config.get("api_key_env", "OPENAI_API_KEY"))
	var api_key := OS.get_environment(api_key_env).strip_edges()
	if api_key.is_empty():
		return {"ok": false, "error": "missing_api_key_env:%s" % api_key_env}

	var url := String(_config.get("chat_completions_url", "https://api.openai.com/v1/chat/completions"))
	var req := HTTPRequest.new()
	req.timeout = maxi(5, int(_config.get("timeout_sec", 12)))
	add_child(req)

	var payload := {
		"model": String(_config.get("model", "gpt-4.1-mini")),
		"messages": messages,
		"temperature": temperature
	}
	if not json_schema.is_empty():
		payload["response_format"] = {
			"type": "json_schema",
			"json_schema": {
				"name": "intent_output",
				"strict": true,
				"schema": json_schema
			}
		}

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key
	]
	var err := req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "request_start_failed:%d" % err}

	var completed: Array = await req.request_completed
	req.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "request_completed_payload_invalid"}

	var http_code := int(completed[1])
	var body_bytes: PackedByteArray = completed[3]
	var body_text := body_bytes.get_string_from_utf8()
	if http_code < 200 or http_code >= 300:
		return {"ok": false, "error": "http_%d:%s" % [http_code, body_text.left(300)]}

	var parser := JSON.new()
	if parser.parse(body_text) != OK:
		return {"ok": false, "error": "json_parse_failed"}
	var rsp: Dictionary = parser.data
	var choices: Array = rsp.get("choices", [])
	if choices.is_empty():
		return {"ok": false, "error": "empty_choices"}

	var message: Dictionary = (choices[0] as Dictionary).get("message", {})
	var content := _extract_message_content(message.get("content", ""))
	if content.is_empty():
		return {"ok": false, "error": "empty_content"}

	return {
		"ok": true,
		"content": content
	}

func _extract_message_content(content_variant: Variant) -> String:
	if typeof(content_variant) == TYPE_STRING:
		return String(content_variant).strip_edges()
	if typeof(content_variant) == TYPE_ARRAY:
		var parts: Array[String] = []
		for part_variant in content_variant:
			var part: Dictionary = part_variant
			if String(part.get("type", "")) == "text":
				parts.append(String(part.get("text", "")))
		return "\n".join(parts).strip_edges()
	return ""

func _parse_json_like_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		return parser.data

	var start := text.find("{")
	var finish := text.rfind("}")
	if start == -1 or finish <= start:
		return {}
	var candidate := text.substr(start, finish - start + 1)
	if parser.parse(candidate) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		return parser.data
	return {}

func _narrative_whitelist_passes(text: String) -> bool:
	var lowered := text.to_lower()
	var banned_tokens := [
		"hp+", "hp-", "atk+", "atk-", "def+", "def-", "keys+", "keys-", "corruption+", "corruption-",
		"reward", "curse", "delta_preview", "pending_effect", "json", "规则已裁定", "意图json", "规则结算"
	]
	for token in banned_tokens:
		if lowered.find(token) != -1:
			return false
	var regex := RegEx.new()
	var err := regex.compile("(hp|atk|def|keys|corruption|reward|curse|json|规则|结算|delta|pending)\\s*[:：]?\\s*[+\\-]?\\d*")
	if err != OK:
		return true
	if regex.search(lowered) != null:
		return false
	var num_regex := RegEx.new()
	if num_regex.compile("\\d") == OK and num_regex.search(text) != null:
		return false
	return true

func _sanitize_narrative_text(text: String, god_cfg: Dictionary, resolution: Dictionary, player_text: String) -> String:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return _narrative_generator.generate_narrative(god_cfg, resolution, player_text)
	var lines: PackedStringArray = cleaned.split("\n", false)
	var kept: Array[String] = []
	for line_variant in lines:
		var line := String(line_variant).strip_edges()
		if line.is_empty():
			continue
		var lowered := line.to_lower()
		if lowered.find("json") != -1 or lowered.find("reward") != -1 or lowered.find("curse") != -1:
			continue
		if line.find("规则") != -1 or line.find("结算") != -1 or line.find("delta") != -1 or line.find("pending") != -1:
			continue
		kept.append(line)
	cleaned = " ".join(kept).strip_edges()
	if not _narrative_whitelist_passes(cleaned):
		return _narrative_generator.generate_narrative(god_cfg, resolution, player_text)
	return cleaned
