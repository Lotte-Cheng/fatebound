extends RefCounted
class_name FateRuleEngineTest

const DataLoaderScript = preload("res://scripts/data_loader.gd")
const RuleEngineScript = preload("res://scripts/core/rule_engine.gd")

func run_all() -> Dictionary:
	var messages: Array[String] = []
	var cfg := _load_config_bundle()
	if cfg.is_empty():
		return {"ok": false, "messages": ["[FAIL] data load failed"]}

	var result_det := _test_determinism(cfg)
	if not result_det.get("ok", false):
		return result_det
	messages.append("[PASS] Determinism: %s" % result_det.get("signature", ""))

	var result_stance := _test_stance_bias(cfg)
	if not result_stance.get("ok", false):
		return result_stance
	messages.append("[PASS] Stance bias: %s" % result_stance.get("summary", ""))

	var result_combat := _test_combat_threshold(cfg)
	if not result_combat.get("ok", false):
		return result_combat
	messages.append("[PASS] Combat threshold: %s" % result_combat.get("summary", ""))

	var result_debt := _test_delayed_curse_trigger(cfg)
	if not result_debt.get("ok", false):
		return result_debt
	messages.append("[PASS] Delayed curse trigger: %s" % result_debt.get("summary", ""))

	messages.append("[PASS] FateRuleEngine v2 tests finished.")
	return {"ok": true, "messages": messages}

func _load_config_bundle() -> Dictionary:
	var gods := DataLoaderScript.load_json("res://data/gods.json")
	var rewards := DataLoaderScript.load_json("res://data/rewards.json")
	var curses := DataLoaderScript.load_json("res://data/curses.json")
	var rooms := DataLoaderScript.load_json("res://data/rooms.json")
	if gods.is_empty() or rewards.is_empty() or curses.is_empty() or rooms.is_empty():
		return {}
	return {
		"gods": gods,
		"rewards": rewards,
		"curses": curses,
		"rooms": rooms
	}

func _new_engine(cfg: Dictionary) -> FateRuleEngine:
	var engine := RuleEngineScript.new()
	engine.setup(
		cfg.get("gods", {}),
		cfg.get("rewards", {}),
		cfg.get("curses", {}),
		cfg.get("rooms", {})
	)
	return engine

func _build_intent(stance: String, risk: String = "mid", constraints: Array = ["none"]) -> Dictionary:
	return {
		"wish_type": "combat_boost",
		"tone": "calm",
		"risk_preference": risk,
		"constraints": constraints.duplicate(),
		"target": "",
		"stance": stance
	}

func _test_determinism(cfg: Dictionary) -> Dictionary:
	var first := _simulate_signature(cfg, ["pact", "pact", "restraint"])
	var second := _simulate_signature(cfg, ["pact", "pact", "restraint"])
	if first != second:
		return {
			"ok": false,
			"messages": [
				"[FAIL] Determinism mismatch",
				"first=%s" % first,
				"second=%s" % second
			]
		}
	return {"ok": true, "messages": [], "signature": first}

func _simulate_signature(cfg: Dictionary, stance_plan: Array) -> String:
	var engine := _new_engine(cfg)
	var rooms_cfg: Dictionary = cfg.get("rooms", {})
	var route: Array = rooms_cfg.get("demo_rooms", [])
	var player_state: Dictionary = rooms_cfg.get("initial_state", {}).duplicate(true)
	if not player_state.has("pending_effects"):
		player_state["pending_effects"] = []

	var parts: Array[String] = []
	for i in range(mini(3, route.size())):
		player_state["turn"] = i + 1
		var room: Dictionary = route[i]
		var stance := "restraint"
		if i < stance_plan.size():
			stance = String(stance_plan[i])
		var intent := _build_intent(stance, "mid", ["none"])
		var resolution: Dictionary = engine.resolve(player_state, room, intent)
		var applied: Dictionary = engine.apply_resolution(player_state, resolution)
		player_state = applied.get("state", player_state)
		parts.append("%s:%s:%s:%s:%s" % [
			room.get("id", "?"),
			stance,
			JSON.stringify(resolution.get("reward_ids", []), "", false),
			JSON.stringify(resolution.get("curse_ids", []), "", false),
			JSON.stringify(player_state.get("pending_effects", []), "", false)
		])

	return "%s => hp:%d atk:%d def:%d corruption:%d fate:%d keys:%d debts:%d" % [
		" | ".join(parts),
		int(player_state.get("hp", 0)),
		int(player_state.get("atk", 0)),
		int(player_state.get("def", 0)),
		int(player_state.get("corruption", 0)),
		int(player_state.get("fate", 0)),
		int(player_state.get("keys", 0)),
		(player_state.get("pending_effects", []) as Array).size()
	]

func _test_stance_bias(cfg: Dictionary) -> Dictionary:
	var rooms_cfg: Dictionary = cfg.get("rooms", {})
	var room: Dictionary = (rooms_cfg.get("demo_rooms", []) as Array)[0]

	var restraint_engine := _new_engine(cfg)
	var restraint_state: Dictionary = rooms_cfg.get("initial_state", {}).duplicate(true)
	restraint_state["turn"] = 1
	var restraint_res := restraint_engine.resolve(restraint_state, room, _build_intent("restraint", "low", ["low_risk"]))

	var blasphemy_engine := _new_engine(cfg)
	var blasphemy_state: Dictionary = rooms_cfg.get("initial_state", {}).duplicate(true)
	blasphemy_state["turn"] = 1
	var blasphemy_res := blasphemy_engine.resolve(blasphemy_state, room, _build_intent("blasphemy", "high", ["none"]))

	var restraint_curse_count := (restraint_res.get("curse_ids", []) as Array).size()
	var blasphemy_curse_count := (blasphemy_res.get("curse_ids", []) as Array).size()
	var restraint_reward_count := (restraint_res.get("reward_ids", []) as Array).size()
	var blasphemy_reward_count := (blasphemy_res.get("reward_ids", []) as Array).size()
	var restraint_corruption := int((restraint_res.get("delta_preview", {}) as Dictionary).get("corruption", 0))
	var blasphemy_corruption := int((blasphemy_res.get("delta_preview", {}) as Dictionary).get("corruption", 0))

	if blasphemy_reward_count < restraint_reward_count:
		return {"ok": false, "messages": ["[FAIL] blasphemy reward count is not higher/equal than restraint"]}
	if blasphemy_curse_count <= restraint_curse_count and blasphemy_corruption <= restraint_corruption:
		return {"ok": false, "messages": ["[FAIL] blasphemy risk is not higher than restraint"]}

	return {
		"ok": true,
		"messages": [],
		"summary": "restraint(reward=%d curse=%d corruption=%d) vs blasphemy(reward=%d curse=%d corruption=%d)" % [
			restraint_reward_count,
			restraint_curse_count,
			restraint_corruption,
			blasphemy_reward_count,
			blasphemy_curse_count,
			blasphemy_corruption
		]
	}

func _test_combat_threshold(cfg: Dictionary) -> Dictionary:
	var rooms_cfg: Dictionary = cfg.get("rooms", {})
	var route: Array = rooms_cfg.get("demo_rooms", [])
	var combat_room: Dictionary = route[1]
	var player_state: Dictionary = rooms_cfg.get("initial_state", {}).duplicate(true)
	player_state["turn"] = 2

	var engine := _new_engine(cfg)
	var resolution: Dictionary = engine.resolve(player_state, combat_room, _build_intent("restraint", "mid", ["none"]))
	var combat_log: Array = resolution.get("combat_log", [])
	var delta: Dictionary = resolution.get("delta_preview", {})

	var has_atk_penalty := false
	var has_def_penalty := false
	for line_variant in combat_log:
		var line: String = String(line_variant)
		if line.find("atk 不达标") != -1:
			has_atk_penalty = true
		if line.find("def 不达标") != -1:
			has_def_penalty = true

	if not has_atk_penalty or not has_def_penalty:
		return {
			"ok": false,
			"messages": [
				"[FAIL] combat threshold penalties not found in log",
				"log=%s" % JSON.stringify(combat_log, "", false)
			]
		}
	if int(delta.get("hp", 0)) >= 0:
		return {"ok": false, "messages": ["[FAIL] combat delta has no HP loss despite threshold miss"]}

	return {
		"ok": true,
		"messages": [],
		"summary": "hp_delta=%d log=%s" % [int(delta.get("hp", 0)), JSON.stringify(combat_log, "", false)]
	}

func _test_delayed_curse_trigger(cfg: Dictionary) -> Dictionary:
	var rooms_cfg: Dictionary = cfg.get("rooms", {})
	var route: Array = rooms_cfg.get("demo_rooms", [])
	var god_room: Dictionary = route[0]
	var combat_room: Dictionary = route[1]
	var player_state: Dictionary = rooms_cfg.get("initial_state", {}).duplicate(true)
	if not player_state.has("pending_effects"):
		player_state["pending_effects"] = []

	var engine := _new_engine(cfg)

	player_state["turn"] = 1
	var res1: Dictionary = engine.resolve(player_state, god_room, _build_intent("pact", "mid", ["none"]))
	var app1: Dictionary = engine.apply_resolution(player_state, res1)
	player_state = app1.get("state", player_state)

	var has_pact_debt := false
	for debt_variant in player_state.get("pending_effects", []):
		var debt: Dictionary = debt_variant
		if String(debt.get("curse_id", "")) == "curse_pact_debt":
			has_pact_debt = true
			break
	if not has_pact_debt:
		return {"ok": false, "messages": ["[FAIL] pact debt was not mounted into pending_effects"]}

	player_state["turn"] = 2
	var res2: Dictionary = engine.resolve(player_state, combat_room, _build_intent("pact", "mid", ["none"]))
	var app2: Dictionary = engine.apply_resolution(player_state, res2)
	var triggered: Array = app2.get("triggered_reports", [])

	var triggered_pact_debt := false
	for report_variant in triggered:
		var report: Dictionary = report_variant
		if String(report.get("curse_id", "")) == "curse_pact_debt" and String(report.get("trigger", "")) == "on_combat_start":
			triggered_pact_debt = true
			break
	if not triggered_pact_debt:
		return {
			"ok": false,
			"messages": [
				"[FAIL] pact debt did not trigger on combat start",
				"triggered=%s" % JSON.stringify(triggered, "", false)
			]
		}

	return {
		"ok": true,
		"messages": [],
		"summary": JSON.stringify(triggered, "", false)
	}
