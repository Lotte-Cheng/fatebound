extends RefCounted
class_name AIStub

var _config: Dictionary = {}

func setup(config: Dictionary) -> void:
	_config = config.duplicate(true)

func parse_intent(player_text: String, turn_context: Dictionary) -> Dictionary:
	var normalized_text := player_text.strip_edges().to_lower()
	var intent_rules: Array = _config.get("intent_rules", [])
	var default_intent: String = _config.get("default_intent", "questioning")

	var best_intent := default_intent
	var best_score := 0
	var matched_tokens: Array[String] = []

	for rule in intent_rules:
		var intent_id: String = rule.get("intent", "")
		if intent_id.is_empty():
			continue
		var keywords: Array = rule.get("keywords", [])
		var score := 0
		var local_matches: Array[String] = []
		for token_variant in keywords:
			var token: String = String(token_variant).to_lower()
			if token.is_empty():
				continue
			if normalized_text.find(token) != -1:
				score += 1
				local_matches.append(token)

		if score > best_score:
			best_score = score
			best_intent = intent_id
			matched_tokens = local_matches

	var confidence := 0.20
	if best_score > 0:
		confidence = min(0.95, 0.40 + 0.15 * float(best_score))

	return {
		"intent": best_intent,
		"confidence": confidence,
		"raw_text": player_text,
		"matched_tokens": matched_tokens,
		"room_hint": turn_context.get("room_type", "")
	}

func generate_narrative(player_text: String, turn_context: Dictionary, intent_json: Dictionary, turn_result: Dictionary) -> String:
	var room_type: String = turn_context.get("room_type", "fallback")
	var values := {
		"player_text": player_text,
		"intent": intent_json.get("intent", "questioning"),
		"outcome_cn": _combat_outcome_to_cn(turn_result.get("combat_outcome", "")),
		"attitude_id": turn_result.get("god_attitude", "neutral"),
		"secret_outcome_cn": _secret_outcome_to_cn(turn_result.get("secret_outcome", "")),
		"effect_summary": _effect_summary(turn_result),
		"encounter_name": _find_encounter_name(turn_context),
		"entity_name": _find_entity_name(turn_context)
	}

	var template := _pick_template(room_type, "%s|%s|%s" % [player_text, room_type, values["intent"]])
	return template.format(values)

func _pick_template(room_type: String, seed_text: String) -> String:
	var templates_map: Dictionary = _config.get("narrative_templates", {})
	var templates: Array = templates_map.get(room_type, templates_map.get("fallback", ["{player_text}"]))
	if templates.is_empty():
		return "{player_text}"
	var raw_hash: int = int(hash(seed_text))
	var index: int = int(abs(raw_hash)) % templates.size()
	return String(templates[index])

func _effect_summary(turn_result: Dictionary) -> String:
	var effects: Array = turn_result.get("applied_effects", [])
	if effects.is_empty():
		return "本回合无数值变化。"

	var labels: Array[String] = []
	for item in effects:
		var label: String = item.get("label", "")
		if label.is_empty():
			var stat: String = item.get("stat", item.get("item", "effect"))
			var delta: int = int(item.get("delta", 0))
			label = "%s %+d" % [stat, delta]
		labels.append(label)

	return "变化：%s。" % "；".join(labels)

func _find_encounter_name(turn_context: Dictionary) -> String:
	var room_data: Dictionary = turn_context.get("context", {})
	var encounter: Dictionary = room_data.get("encounter", {})
	return encounter.get("name", "未知敌人")

func _find_entity_name(turn_context: Dictionary) -> String:
	var room_data: Dictionary = turn_context.get("context", {})
	return room_data.get("entity_name", "未知存在")

func _combat_outcome_to_cn(outcome: String) -> String:
	match outcome:
		"win":
			return "胜利"
		"lose":
			return "失利"
		"draw":
			return "僵持"
		_:
			return "未定"

func _secret_outcome_to_cn(outcome: String) -> String:
	match outcome:
		"unlocked":
			return "成功开启"
		"locked":
			return "钥匙不足"
		_:
			return "未知"
