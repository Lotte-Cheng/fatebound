extends RefCounted
class_name IntentParser

const WISH_TYPES := ["combat_boost", "heal", "key_request", "knowledge", "curse_trade", "defy_god"]
const TONES := ["calm", "desperate", "arrogant", "pleading", "angry"]
const RISK_PREFS := ["low", "mid", "high"]

func parse_intent(player_text: String) -> Dictionary:
	var text := player_text.strip_edges().to_lower()
	if text.is_empty():
		text = "..."

	var intent := {
		"wish_type": _detect_wish_type(text),
		"tone": _detect_tone(text),
		"risk_preference": _detect_risk(text),
		"constraints": _detect_constraints(text),
		"target": _detect_target(text)
	}

	var validation := validate_schema(intent)
	if not validation.get("ok", false):
		intent = {
			"wish_type": "knowledge",
			"tone": "calm",
			"risk_preference": "low",
			"constraints": ["low_risk"],
			"target": ""
		}
		intent["schema_fallback"] = true
		intent["schema_errors"] = validation.get("errors", [])
	else:
		intent["schema_fallback"] = false
		intent["schema_errors"] = []

	intent["raw_text"] = player_text
	return intent

func validate_schema(intent_json: Dictionary) -> Dictionary:
	var errors: Array[String] = []

	if not intent_json.has("wish_type") or not WISH_TYPES.has(String(intent_json.get("wish_type", ""))):
		errors.append("wish_type invalid")
	if not intent_json.has("tone") or not TONES.has(String(intent_json.get("tone", ""))):
		errors.append("tone invalid")
	if not intent_json.has("risk_preference") or not RISK_PREFS.has(String(intent_json.get("risk_preference", ""))):
		errors.append("risk_preference invalid")
	if not intent_json.has("constraints") or typeof(intent_json.get("constraints")) != TYPE_ARRAY:
		errors.append("constraints must be array")
	if not intent_json.has("target"):
		errors.append("target missing")

	if intent_json.has("constraints") and typeof(intent_json.get("constraints")) == TYPE_ARRAY:
		for c in intent_json.get("constraints", []):
			if typeof(c) != TYPE_STRING:
				errors.append("constraint must be string")
				break

	return {
		"ok": errors.is_empty(),
		"errors": errors
	}

func _detect_wish_type(text: String) -> String:
	if _contains_any(text, ["力量", "伤害", "变强", "攻击", "战斗", "冲锋", "斩杀"]):
		return "combat_boost"
	if _contains_any(text, ["治疗", "恢复", "活下去", "救我", "回血"]):
		return "heal"
	if _contains_any(text, ["钥匙", "开门", "密室", "锁", "通行"]):
		return "key_request"
	if _contains_any(text, ["知识", "真相", "为什么", "如何", "线索", "答案"]):
		return "knowledge"
	if _contains_any(text, ["代价", "交易", "献祭", "交换", "随便拿"]):
		return "curse_trade"
	if _contains_any(text, ["忤逆", "不服", "反抗", "挑战神", "我自己决定"]):
		return "defy_god"
	return "knowledge"

func _detect_tone(text: String) -> String:
	if _contains_any(text, ["求你", "拜托", "恳请", "祈求"]):
		return "pleading"
	if _contains_any(text, ["快", "救命", "不然我就死", "马上"]):
		return "desperate"
	if _contains_any(text, ["命令", "我应得", "你必须", "立刻给我"]):
		return "arrogant"
	if _contains_any(text, ["愤怒", "怒", "滚开", "威胁"]):
		return "angry"
	return "calm"

func _detect_risk(text: String) -> String:
	if _contains_any(text, ["不惜代价", "随便代价", "献祭", "冒险", "all in", "梭哈"]):
		return "high"
	if _contains_any(text, ["稳一点", "安全", "低风险", "别受伤", "不要代价", "谨慎"]):
		return "low"
	return "mid"

func _detect_constraints(text: String) -> Array[String]:
	var constraints: Array[String] = []
	if _contains_any(text, ["稳", "安全", "低风险", "谨慎"]):
		constraints.append("low_risk")
	if _contains_any(text, ["不要掉血", "别扣血", "no hp"]):
		constraints.append("no_hp_cost")
	if _contains_any(text, ["不要腐化", "别涨腐化", "no corruption"]):
		constraints.append("no_corruption")
	if _contains_any(text, ["立刻", "马上", "现在"]):
		constraints.append("fast_power")
	if _contains_any(text, ["钥匙", "开门", "密室"]):
		constraints.append("need_key")

	if constraints.is_empty():
		constraints.append("none")
	return constraints

func _detect_target(text: String) -> String:
	if _contains_any(text, ["索露恩", "solune"]):
		return "solune"
	if _contains_any(text, ["萨洛斯", "tharos"]):
		return "tharos"
	if _contains_any(text, ["妮拉", "nyra"]):
		return "nyra"
	if _contains_any(text, ["邪灵", "低语", "murmur"]):
		return "murmur"
	return ""

func _contains_any(text: String, words: Array) -> bool:
	for word_variant in words:
		var word: String = String(word_variant).to_lower()
		if not word.is_empty() and text.find(word) != -1:
			return true
	return false
