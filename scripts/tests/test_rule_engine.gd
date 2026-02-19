extends RefCounted
class_name RuleEngineTest

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const RuleEngineScript = preload("res://scripts/rule_engine.gd")
const AIStubScript = preload("res://scripts/ai_stub.gd")

const ACTION_SCRIPT := [
	"我向神明祈祷并宣誓。",
	"我要攻击前方敌人。",
	"我先防御，观察环境。",
	"告诉我真相与线索。",
	"给我更多奖励和钥匙。",
	"我会欺骗你。"
]

func run_all() -> Dictionary:
	var messages: Array[String] = []
	var result_a := _run_once()
	var result_b := _run_once()

	if not result_a.get("ok", false):
		messages.append_array(result_a.get("messages", []))
		return {"ok": false, "messages": messages}
	if not result_b.get("ok", false):
		messages.append_array(result_b.get("messages", []))
		return {"ok": false, "messages": messages}

	var sig_a: String = result_a.get("signature", "")
	var sig_b: String = result_b.get("signature", "")
	if sig_a != sig_b:
		messages.append("[FAIL] Determinism mismatch: %s != %s" % [sig_a, sig_b])
		return {"ok": false, "messages": messages}

	messages.append("[PASS] Deterministic signature: %s" % sig_a)
	messages.append("[PASS] Room coverage: %s" % ", ".join(result_a.get("room_coverage", [])))
	return {"ok": true, "messages": messages}

func _run_once() -> Dictionary:
	var messages: Array[String] = []
	var game_cfg := DataLoaderScript.load_json("res://data/game_config.json")
	var entities_cfg := DataLoaderScript.load_json("res://data/entities.json")
	var ai_cfg := DataLoaderScript.load_json("res://data/ai_stub.json")
	if game_cfg.is_empty() or entities_cfg.is_empty() or ai_cfg.is_empty():
		messages.append("[FAIL] JSON data load failed")
		return {"ok": false, "messages": messages}

	var engine = RuleEngineScript.new()
	engine.setup(game_cfg, entities_cfg)
	var ai = AIStubScript.new()
	ai.setup(ai_cfg)

	var seen_rooms := {}
	for i in range(18):
		if engine.is_finished():
			break
		var ctx := engine.get_turn_context()
		var room_type: String = ctx.get("room_type", "")
		seen_rooms[room_type] = true

		var text: String = ACTION_SCRIPT[i % ACTION_SCRIPT.size()]
		var intent := ai.parse_intent(text, ctx)
		var turn := engine.process_turn(intent)
		var after: Dictionary = turn.get("state_after", {})
		if int(after.get("hp", 0)) < 0:
			messages.append("[FAIL] HP below 0")
			return {"ok": false, "messages": messages}
		if int(after.get("corruption", 0)) < 0:
			messages.append("[FAIL] Corruption below 0")
			return {"ok": false, "messages": messages}

	var final_state := engine.get_state()
	var inventory: Dictionary = final_state.get("inventory", {})
	var signature := "%d|%d|%d|%d|%d|%d|%s" % [
		int(final_state.get("hp", 0)),
		int(final_state.get("atk", 0)),
		int(final_state.get("def", 0)),
		int(final_state.get("corruption", 0)),
		int(final_state.get("fate", 0)),
		int(inventory.get("keys", 0)),
		engine.get_finish_reason()
	]

	var room_coverage: Array[String] = []
	for room_type in ["combat_room", "god_room", "secret_room"]:
		if seen_rooms.has(room_type):
			room_coverage.append(room_type)
	if room_coverage.size() < 3:
		messages.append("[FAIL] Room coverage incomplete: %s" % ", ".join(room_coverage))
		return {
			"ok": false,
			"messages": messages,
			"signature": signature,
			"room_coverage": room_coverage
		}

	return {
		"ok": true,
		"messages": messages,
		"signature": signature,
		"room_coverage": room_coverage
	}
