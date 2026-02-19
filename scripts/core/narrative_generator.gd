extends RefCounted
class_name NarrativeGenerator

func generate_narrative(god_cfg: Dictionary, resolution: Dictionary, player_text: String) -> String:
	var god_name: String = god_cfg.get("name", resolution.get("god_id", "未知存在"))
	var persona: String = god_cfg.get("persona", "")
	var style: String = god_cfg.get("speech_style", "")
	var stance: String = String(resolution.get("stance", "restraint"))
	var reward_ids: Array = resolution.get("reward_ids", [])
	var curse_ids: Array = resolution.get("curse_ids", [])
	var notes: Array = resolution.get("notes", [])
	var delta_preview: Dictionary = resolution.get("delta_preview", {})
	var debts: Array = resolution.get("pending_effects_preview", [])

	var reward_text := "无"
	if not reward_ids.is_empty():
		reward_text = ", ".join(reward_ids)
	var curse_text := "无"
	if not curse_ids.is_empty():
		curse_text = ", ".join(curse_ids)

	var note_text := ""
	if not notes.is_empty():
		note_text = "附注：%s。" % "；".join(notes)
	var debt_text := "无"
	if not debts.is_empty():
		debt_text = JSON.stringify(debts, "", false)

	return "%s之言：你方才说“%s”。\n人格：%s（%s）。姿态：%s。\n规则已裁定：奖励[%s]，诅咒[%s]，挂载债务[%s]。\n状态变化请仅以 resolution.delta_preview 为准：%s。%s" % [
		god_name,
		player_text,
		persona,
		style,
		stance,
		reward_text,
		curse_text,
		debt_text,
		JSON.stringify(delta_preview),
		note_text
	]
