extends RefCounted
class_name NarrativeGenerator

func generate_narrative(god_cfg: Dictionary, resolution: Dictionary, player_text: String) -> String:
	var god_name: String = String(god_cfg.get("name", resolution.get("god_id", "未知存在")))
	var persona: String = String(god_cfg.get("persona", ""))
	var style: String = String(god_cfg.get("speech_style", ""))
	var reward_ids: Array = resolution.get("reward_ids", [])
	var curse_ids: Array = resolution.get("curse_ids", [])
	var debts: Array = resolution.get("pending_effects_preview", [])
	var player_line := player_text.strip_edges()
	if player_line.is_empty():
		player_line = "……"

	var mood := "neutral"
	if reward_ids.size() > curse_ids.size():
		mood = "favorable"
	elif curse_ids.size() > reward_ids.size() or not debts.is_empty():
		mood = "ominous"

	return _build_in_character_line(god_name, persona, style, player_line, mood)

func _build_in_character_line(god_name: String, persona: String, style: String, player_line: String, mood: String) -> String:
	var lower_persona := persona.to_lower()
	var lower_style := style.to_lower()
	var key := "%s %s %s" % [god_name, lower_persona, lower_style]
	if key.find("索露恩") != -1 or key.find("oath") != -1 or key.find("晨光") != -1:
		if mood == "favorable":
			return "索露恩垂目而语：你的话已被晨光见证。守住承诺，路会在你脚下亮起。"
		if mood == "ominous":
			return "索露恩低声道：我听见了你的渴望，但誓言从不只取不还。谨记分寸，再向前一步。"
		return "索露恩缓声道：你的请求已入誓约之环。保持克制，我会继续注视你。"
	if key.find("萨洛斯") != -1 or key.find("战争") != -1 or key.find("war") != -1:
		if mood == "favorable":
			return "萨洛斯嗤笑：不错，你终于像个战士在说话。别回头，拿行动证明你的决意。"
		if mood == "ominous":
			return "萨洛斯冷哼：你想要更多，就别怕伤痕。战场从不宽恕犹豫者。"
		return "萨洛斯短促回应：我听见了。下一步，用你的冲锋来回答我。"
	if key.find("妮拉") != -1 or key.find("奥秘") != -1 or key.find("mystic") != -1:
		if mood == "favorable":
			return "妮拉轻声道：你的问题接近了门锁本身。沿着这道缝隙走，你会看见更深的答案。"
		if mood == "ominous":
			return "妮拉低语：你触碰到了真相，也触碰到了阴影。记住，知道得越多，代价越清晰。"
		return "妮拉回应：我听见你的提问。别急着索取结论，先学会辨认代价的轮廓。"
	if key.find("邪灵") != -1 or key.find("低语") != -1 or key.find("abyss") != -1:
		if mood == "favorable":
			return "低语邪灵贴耳轻笑：很好，这才像交易。继续靠近，我会让你看见更甜的回报。"
		if mood == "ominous":
			return "低语邪灵呢喃：你已经伸手了，就别装作无辜。愿望会回应你，账也会回应你。"
		return "低语邪灵低声道：你的声音我收下了。再说一遍你真正不敢承认的渴望。"
	if mood == "favorable":
		return "%s回应：我听见了你的请求。继续前行，别让此刻的决意冷却。" % god_name
	if mood == "ominous":
		return "%s低语：你的愿望已被听见，但任何渴望都不会毫无回声。谨慎前行。" % god_name
	return "%s回应：你说的话我记下了。下一句，会决定你将面对什么。" % god_name
