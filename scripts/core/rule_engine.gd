extends RefCounted
class_name FateRuleEngine

var _gods_by_id: Dictionary = {}
var _rewards_by_id: Dictionary = {}
var _curses_by_id: Dictionary = {}
var _rooms_cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func setup(gods_config: Dictionary, rewards_config: Dictionary, curses_config: Dictionary, rooms_config: Dictionary) -> void:
	_gods_by_id.clear()
	_rewards_by_id.clear()
	_curses_by_id.clear()
	_rooms_cfg = rooms_config.duplicate(true)

	for god_variant in gods_config.get("gods", []):
		var god: Dictionary = god_variant
		_gods_by_id[god.get("id", "")] = god

	for reward_variant in rewards_config.get("rewards", []):
		var reward: Dictionary = reward_variant
		_rewards_by_id[reward.get("id", "")] = reward

	for curse_variant in curses_config.get("curses", []):
		var curse: Dictionary = curse_variant
		_curses_by_id[curse.get("id", "")] = curse

	_rng.seed = int(_rooms_cfg.get("seed", 1))

func reset_seed(seed: int) -> void:
	_rng.seed = seed

func resolve(player_state: Dictionary, room_context: Dictionary, intent_json: Dictionary) -> Dictionary:
	var room_type: String = String(room_context.get("type", "god_room"))
	var room_id: String = String(room_context.get("id", ""))
	var god_id: String = String(room_context.get("god_id", "solune"))
	var god_cfg: Dictionary = _gods_by_id.get(god_id, {})
	var stance: String = _extract_stance(intent_json)

	var notes: Array[String] = []
	var tags: Array = room_context.get("tags", []).duplicate()
	var effect_stack: Array = []
	var pending_to_add: Array = []
	var combat_log: Array[String] = []
	var used_key_count := 0
	var reward_rolls := int(room_context.get("reward_rolls", 1))
	var curse_rolls := int(room_context.get("curse_rolls", 1))

	var low_risk: bool = String(intent_json.get("risk_preference", "mid")) == "low"
	if room_type == "secret_room":
		var secret_result: Dictionary = _resolve_secret_room(player_state, room_context)
		reward_rolls = int(secret_result.get("reward_rolls", reward_rolls))
		curse_rolls = int(secret_result.get("curse_rolls", curse_rolls))
		used_key_count = int(secret_result.get("used_key_count", 0))
		notes.append_array(secret_result.get("notes", []))
		effect_stack.append_array(secret_result.get("effect_stack", []))
		tags.append_array(secret_result.get("tags", []))
	if room_type == "combat_room":
		var combat_result: Dictionary = {}
		if room_context.has("runtime_combat_result"):
			combat_result = room_context.get("runtime_combat_result", {})
		else:
			combat_result = _resolve_combat_room(player_state, room_context)
		reward_rolls = int(combat_result.get("reward_rolls", reward_rolls))
		curse_rolls = int(combat_result.get("curse_rolls", curse_rolls))
		effect_stack.append_array(combat_result.get("effect_stack", []))
		combat_log.append_array(combat_result.get("combat_log", []))
		notes.append_array(combat_result.get("notes", []))
		tags.append_array(combat_result.get("tags", []))

	var stance_modifier := _get_stance_modifier(god_cfg, stance)
	var pool_debug := {
		"room_type": room_type,
		"god_id": god_id,
		"stance": stance,
		"reward_pool_source": "god.reward_pool",
		"curse_pool_source": "god.curse_pool",
		"reward_roll_mult": 1.0,
		"curse_roll_mult": 1.0
	}

	if room_type == "god_room":
		var reward_mult := float(stance_modifier.get("reward_roll_mult", 1.0))
		var curse_mult := float(stance_modifier.get("curse_roll_mult", 1.0))
		reward_rolls = maxi(0, int(ceil(float(reward_rolls) * reward_mult)))
		curse_rolls = maxi(0, int(ceil(float(curse_rolls) * curse_mult)))
		pool_debug["reward_roll_mult"] = reward_mult
		pool_debug["curse_roll_mult"] = curse_mult

		var corruption_bonus := int(stance_modifier.get("corruption_delta_bonus", 0))
		if corruption_bonus != 0:
			effect_stack.append(_make_effect_entry(
				"room",
				"stance_corruption_bonus",
				"姿态代价：Corruption %+d" % corruption_bonus,
				{"corruption": corruption_bonus}
			))

	if low_risk:
		curse_rolls = maxi(0, curse_rolls - 1)
		notes.append("low_risk 生效：curse_rolls -1")
		tags.append("low_risk")

	var max_curse_severity := 99
	if low_risk:
		max_curse_severity = 1

	var reward_pool: Array = god_cfg.get("reward_pool", [])
	var curse_pool: Array = god_cfg.get("curse_pool", [])
	if room_type == "god_room":
		var reward_pool_by_stance: Dictionary = god_cfg.get("reward_pool_by_stance", {})
		var curse_pool_by_stance: Dictionary = god_cfg.get("curse_pool_by_stance", {})
		if reward_pool_by_stance.has(stance):
			reward_pool = reward_pool_by_stance.get(stance, reward_pool)
			pool_debug["reward_pool_source"] = "god.reward_pool_by_stance.%s" % stance
		if curse_pool_by_stance.has(stance):
			curse_pool = curse_pool_by_stance.get(stance, curse_pool)
			pool_debug["curse_pool_source"] = "god.curse_pool_by_stance.%s" % stance

	var reward_tag_bias: Dictionary = {}
	var curse_tag_bias: Dictionary = {}
	if room_type == "god_room":
		reward_tag_bias = stance_modifier.get("reward_tag_bias", {})
		curse_tag_bias = stance_modifier.get("curse_tag_bias", {})

	var reward_ids: Array = _roll_ids(reward_pool, reward_rolls, _rewards_by_id, 99, false, false, reward_tag_bias)
	var curse_ids: Array = _roll_ids(curse_pool, curse_rolls, _curses_by_id, max_curse_severity, intent_json.get("constraints", []).has("no_hp_cost"), intent_json.get("constraints", []).has("no_corruption"), curse_tag_bias)

	if room_type == "god_room":
		for forced_id_variant in stance_modifier.get("forced_curse_ids", []):
			var forced_id: String = String(forced_id_variant)
			if _curses_by_id.has(forced_id) and not curse_ids.has(forced_id):
				curse_ids.append(forced_id)
				notes.append("姿态附加诅咒：%s" % forced_id)

	for reward_id_variant in reward_ids:
		var reward_id: String = String(reward_id_variant)
		var reward_cfg: Dictionary = _rewards_by_id.get(reward_id, {})
		effect_stack.append(_make_effect_entry(
			"reward",
			reward_id,
			reward_cfg.get("label", reward_id),
			reward_cfg.get("effects", {})
		))

	var curse_instances: Array = []
	for curse_id_variant in curse_ids:
		var curse_id: String = String(curse_id_variant)
		var curse_cfg: Dictionary = _curses_by_id.get(curse_id, {})
		if curse_cfg.is_empty():
			continue
		# Backward compatibility: old curse config without trigger defaults to after_room.
		var trigger: String = String(curse_cfg.get("trigger", "after_room"))
		var instance := {
			"curse_id": curse_id,
			"label": curse_cfg.get("label", curse_id),
			"trigger": trigger,
			"condition": curse_cfg.get("condition", {}),
			"effect": _extract_effect(curse_cfg),
			"tags": curse_cfg.get("tags", []),
			"source_room_id": room_id,
			"remaining_duration": int(curse_cfg.get("remaining_duration", 1))
		}
		curse_instances.append(instance)
		if trigger == "immediate":
			effect_stack.append(_make_effect_entry(
				"curse",
				curse_id,
				curse_cfg.get("label", curse_id),
				_extract_effect(curse_cfg)
			))
		else:
			pending_to_add.append(instance)

	var delta_preview := _sum_effect_stack(effect_stack)
	var debt_preview: Array = []
	for debt_variant in pending_to_add:
		var debt: Dictionary = debt_variant
		debt_preview.append({
			"curse_id": debt.get("curse_id", ""),
			"trigger": debt.get("trigger", ""),
			"condition": debt.get("condition", {})
		})

	return {
		"room_id": room_id,
		"room_type": room_type,
		"god_id": god_id,
		"stance": stance,
		"reward_ids": reward_ids,
		"curse_ids": curse_ids,
		"curse_instances": curse_instances,
		"pending_effects_to_add": pending_to_add,
		"pending_effects_preview": debt_preview,
		"delta_preview": delta_preview,
		"effect_stack": effect_stack,
		"combat_log": combat_log,
		"used_key_count": used_key_count,
		"notes": notes,
		"tags": tags,
		"pool_debug": pool_debug,
		"narrative_seed": {
			"god_id": god_id,
			"tone": intent_json.get("tone", "calm"),
			"stance": stance,
			"tags": tags
		}
	}

func apply_resolution(player_state: Dictionary, resolution: Dictionary) -> Dictionary:
	var state := player_state.duplicate(true)
	if not state.has("pending_effects"):
		state["pending_effects"] = []
	if not state.has("turn"):
		state["turn"] = 1

	var logs: Array[String] = []
	var triggered_reports: Array = []
	var context := {
		"room_type": String(resolution.get("room_type", "")),
		"room_id": String(resolution.get("room_id", "")),
		"stance": String(resolution.get("stance", "restraint"))
	}
	var skip_events: Array = resolution.get("skip_events", [])

	if context.get("room_type", "") == "combat_room" and not skip_events.has("on_combat_start"):
		_trigger_pending_effects(state, "on_combat_start", context, logs, triggered_reports)
	if context.get("room_type", "") == "secret_room" and not skip_events.has("on_enter_secret_room"):
		_trigger_pending_effects(state, "on_enter_secret_room", context, logs, triggered_reports)

	for entry_variant in resolution.get("effect_stack", []):
		var entry: Dictionary = entry_variant
		_apply_effect_to_state(state, _extract_effect(entry), "%s(%s)" % [entry.get("source", "effect"), entry.get("label", "-")], logs)

	var pending_effects: Array = state.get("pending_effects", [])
	for pending_variant in resolution.get("pending_effects_to_add", []):
		var pending: Dictionary = (pending_variant as Dictionary).duplicate(true)
		pending["added_turn"] = int(state.get("turn", 1))
		pending_effects.append(pending)
		logs.append("挂载债务：%s，触发=%s" % [pending.get("label", pending.get("curse_id", "curse")), pending.get("trigger", "after_room")])
	state["pending_effects"] = pending_effects

	if int(resolution.get("used_key_count", 0)) > 0 and not skip_events.has("on_use_key"):
		_trigger_pending_effects(state, "on_use_key", context, logs, triggered_reports)
	if context.get("room_type", "") == "combat_room" and not skip_events.has("on_combat_end"):
		_trigger_pending_effects(state, "on_combat_end", context, logs, triggered_reports)
	if not skip_events.has("after_room"):
		_trigger_pending_effects(state, "after_room", context, logs, triggered_reports)

	_clamp_state(state)

	return {
		"state": state,
		"logs": logs,
		"triggered_reports": triggered_reports
	}

func apply_event(player_state: Dictionary, event_name: String, context: Dictionary = {}) -> Dictionary:
	var state := player_state.duplicate(true)
	if not state.has("pending_effects"):
		state["pending_effects"] = []
	if not state.has("turn"):
		state["turn"] = 1

	var logs: Array[String] = []
	var triggered_reports: Array = []
	var event_context := {
		"room_type": String(context.get("room_type", "")),
		"room_id": String(context.get("room_id", "")),
		"stance": String(context.get("stance", "restraint"))
	}
	_trigger_pending_effects(state, event_name, event_context, logs, triggered_reports)
	_clamp_state(state)

	return {
		"state": state,
		"logs": logs,
		"triggered_reports": triggered_reports
	}

func get_god_config(god_id: String) -> Dictionary:
	return _gods_by_id.get(god_id, {})

func _resolve_combat_room(player_state: Dictionary, room_context: Dictionary) -> Dictionary:
	var combat_log: Array[String] = []
	var notes: Array[String] = []
	var tags: Array = []
	var effect_stack: Array = []

	var enemy_hp := int(room_context.get("enemy_hp", 6))
	var enemy_atk := int(room_context.get("enemy_atk", 3))
	var enemy_def := int(room_context.get("enemy_def", 1))
	var min_atk := int(room_context.get("min_atk", 0))
	var min_def := int(room_context.get("min_def", 0))
	var corruption_threshold := int(room_context.get("corruption_threshold", 999))

	var player_atk := int(player_state.get("atk", 0))
	var player_def := int(player_state.get("def", 0))
	var player_corruption := int(player_state.get("corruption", 0))
	var player_hp := int(player_state.get("hp", 0))

	combat_log.append("战斗阈值：min_atk=%d min_def=%d corruption_threshold=%d" % [min_atk, min_def, corruption_threshold])
	combat_log.append("敌人参数：enemy_hp=%d enemy_atk=%d enemy_def=%d" % [enemy_hp, enemy_atk, enemy_def])
	combat_log.append("玩家参数：atk=%d def=%d corruption=%d hp=%d" % [player_atk, player_def, player_corruption, player_hp])

	var effective_enemy_atk := enemy_atk
	if player_corruption >= corruption_threshold:
		effective_enemy_atk += 1
		combat_log.append("corruption 超阈：敌人强化 enemy_atk +1")
		tags.append("enemy_empowered")

	var per_hit_damage := maxi(1, player_atk - enemy_def)
	var rounds := int(ceil(float(enemy_hp) / float(maxi(per_hit_damage, 1))))
	var extra_damage := 0

	if player_atk < min_atk:
		rounds += 1
		extra_damage += 1
		combat_log.append("atk 不达标：额外 +1 回合并追加伤害 +1")
		notes.append("战斗吃亏原因：ATK 未达到门槛")
		tags.append("atk_below_threshold")

	var damage_per_round := maxi(1, effective_enemy_atk - player_def)
	if player_def < min_def:
		damage_per_round += 1
		combat_log.append("def 不达标：每回合额外受伤 +1")
		notes.append("战斗吃亏原因：DEF 未达到门槛")
		tags.append("def_below_threshold")

	var total_damage_to_player := damage_per_round * rounds + extra_damage
	if total_damage_to_player > 0:
		effect_stack.append(_make_effect_entry("room", "combat_damage", "战斗伤害", {"hp": -total_damage_to_player}))

	var reward_rolls := int(room_context.get("reward_rolls", 1))
	var curse_rolls := int(room_context.get("curse_rolls", 1))

	if total_damage_to_player >= player_hp:
		curse_rolls += 1
		reward_rolls = maxi(0, reward_rolls - 1)
		combat_log.append("战斗结局：濒死/失败，curse_rolls +1")
		notes.append("战斗失败：受伤过重")
		tags.append("combat_loss")
	else:
		var key_drop := int(room_context.get("key_drop_on_win", 0))
		if key_drop > 0:
			effect_stack.append(_make_effect_entry("room", "combat_key_drop", "战斗战利品", {"keys": key_drop}))
		combat_log.append("战斗结局：胜利，获得 Keys %+d" % key_drop)
		notes.append("战斗胜利：可为后续密室做准备")
		tags.append("combat_win")

	return {
		"reward_rolls": reward_rolls,
		"curse_rolls": curse_rolls,
		"effect_stack": effect_stack,
		"combat_log": combat_log,
		"notes": notes,
		"tags": tags
	}

func _resolve_secret_room(player_state: Dictionary, room_context: Dictionary) -> Dictionary:
	var notes: Array[String] = []
	var tags: Array = []
	var effect_stack: Array = []
	var used_key_count := 0
	var reward_rolls := int(room_context.get("locked_reward_rolls", 0))
	var curse_rolls := int(room_context.get("locked_curse_rolls", 1))

	var required_keys := int(room_context.get("requires_keys", 1))
	var current_keys := int(player_state.get("keys", 0))
	if current_keys >= required_keys:
		reward_rolls = int(room_context.get("unlock_reward_rolls", 2))
		curse_rolls = int(room_context.get("unlock_curse_rolls", 0))
		used_key_count = required_keys
		effect_stack.append(_make_effect_entry("room", "secret_unlock_key_cost", "密室开锁消耗", {"keys": -required_keys}))
		notes.append("密室开启：消耗神之钥匙 x%d" % required_keys)
	else:
		notes.append("需要神之钥匙")
		tags.append("secret_locked")

	return {
		"reward_rolls": reward_rolls,
		"curse_rolls": curse_rolls,
		"used_key_count": used_key_count,
		"effect_stack": effect_stack,
		"notes": notes,
		"tags": tags
	}

func _roll_ids(
		pool: Array,
		count: int,
		effect_map: Dictionary,
		max_severity: int,
		deny_hp_loss: bool,
		deny_corruption_gain: bool,
		tag_bias: Dictionary
	) -> Array:
	var result: Array = []
	if count <= 0:
		return result

	var candidates: Array = []
	for entry_variant in pool:
		var entry: Dictionary = entry_variant
		var effect_id: String = entry.get("id", "")
		if effect_id.is_empty() or not effect_map.has(effect_id):
			continue
		var effect_cfg: Dictionary = effect_map[effect_id]
		if int(effect_cfg.get("severity", 1)) > max_severity:
			continue
		var effect_dict := _extract_effect(effect_cfg)
		if deny_hp_loss and int(effect_dict.get("hp", 0)) < 0:
			continue
		if deny_corruption_gain and int(effect_dict.get("corruption", 0)) > 0:
			continue

		var weight := maxf(0.0, float(entry.get("weight", 1.0)))
		for tag_variant in effect_cfg.get("tags", []):
			var tag: String = String(tag_variant)
			if tag_bias.has(tag):
				weight *= maxf(0.0, float(tag_bias.get(tag, 1.0)))
		if weight > 0.0:
			var candidate := entry.duplicate(true)
			candidate["weight"] = weight
			candidates.append(candidate)

	if candidates.is_empty():
		return result

	for _i in range(count):
		var picked_id := _pick_weighted_id(candidates)
		if picked_id.is_empty():
			break
		result.append(picked_id)
	return result

func _pick_weighted_id(candidates: Array) -> String:
	if candidates.is_empty():
		return ""
	var total := 0.0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		total += maxf(0.0, float(candidate.get("weight", 1.0)))
	if total <= 0.0:
		return String((candidates[0] as Dictionary).get("id", ""))

	var ticket := _rng.randf() * total
	var running := 0.0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant
		running += maxf(0.0, float(candidate.get("weight", 1.0)))
		if ticket <= running:
			return String(candidate.get("id", ""))
	return String((candidates[-1] as Dictionary).get("id", ""))

func _make_effect_entry(source: String, effect_id: String, label: String, effect: Dictionary) -> Dictionary:
	return {
		"source": source,
		"id": effect_id,
		"label": label,
		"effect": effect.duplicate(true)
	}

func _sum_effect_stack(effect_stack: Array) -> Dictionary:
	var delta := {
		"hp": 0,
		"atk": 0,
		"def": 0,
		"corruption": 0,
		"keys": 0
	}
	for entry_variant in effect_stack:
		var entry: Dictionary = entry_variant
		var effect: Dictionary = _extract_effect(entry)
		for key in effect.keys():
			if not delta.has(key):
				delta[key] = 0
			delta[key] = int(delta.get(key, 0)) + int(effect.get(key, 0))
	return delta

func _apply_effect_to_state(state: Dictionary, effect: Dictionary, reason: String, logs: Array[String]) -> void:
	if effect.is_empty():
		logs.append("%s => no numeric delta" % reason)
		return
	for key in effect.keys():
		if String(key) == "fate":
			continue
		var delta := int(effect.get(key, 0))
		var before := int(state.get(key, 0))
		var after := before + delta
		state[key] = after
		logs.append("%s => %s: %d -> %d (%+d)" % [reason, key, before, after, delta])

func _trigger_pending_effects(state: Dictionary, event_name: String, context: Dictionary, logs: Array[String], triggered_reports: Array) -> void:
	var current_turn := int(state.get("turn", 1))
	var pending: Array = state.get("pending_effects", [])
	var remaining: Array = []

	for pending_variant in pending:
		var entry: Dictionary = pending_variant
		if String(entry.get("trigger", "after_room")) != event_name:
			remaining.append(entry)
			continue
		if int(entry.get("added_turn", -999)) >= current_turn:
			remaining.append(entry)
			continue
		if not _condition_matches(entry.get("condition", {}), state, context, event_name):
			remaining.append(entry)
			continue

		var effect: Dictionary = _extract_effect(entry)
		var reason := "触发延迟诅咒:%s(%s)" % [entry.get("label", entry.get("curse_id", "curse")), event_name]
		_apply_effect_to_state(state, effect, reason, logs)
		triggered_reports.append({
			"curse_id": entry.get("curse_id", ""),
			"trigger": event_name,
			"effect": effect,
			"reason": reason
		})

		var left := int(entry.get("remaining_duration", 1)) - 1
		if left > 0:
			entry["remaining_duration"] = left
			remaining.append(entry)

	state["pending_effects"] = remaining

func _condition_matches(condition: Dictionary, state: Dictionary, context: Dictionary, event_name: String) -> bool:
	if condition.is_empty():
		return true

	if condition.has("stance") and String(condition.get("stance", "")) != String(context.get("stance", "")):
		return false
	if condition.has("room_type") and String(condition.get("room_type", "")) != String(context.get("room_type", "")):
		return false
	if condition.has("event") and String(condition.get("event", "")) != event_name:
		return false

	if condition.has("stat"):
		var stat: String = String(condition.get("stat", ""))
		var op: String = String(condition.get("op", ">="))
		var value := int(condition.get("value", 0))
		var left := int(state.get(stat, 0))
		if not _compare_int(left, op, value):
			return false

	return true

func _compare_int(left: int, op: String, right: int) -> bool:
	match op:
		">":
			return left > right
		">=":
			return left >= right
		"<":
			return left < right
		"<=":
			return left <= right
		"!=":
			return left != right
		_:
			return left == right

func _extract_stance(intent_json: Dictionary) -> String:
	var stance := String(intent_json.get("stance", "restraint"))
	if stance not in ["restraint", "pact", "blasphemy"]:
		return "restraint"
	return stance

func _get_stance_modifier(god_cfg: Dictionary, stance: String) -> Dictionary:
	var modifiers: Dictionary = god_cfg.get("stance_modifiers", {})
	if modifiers.has(stance):
		return modifiers.get(stance, {})
	return {}

func _extract_effect(source: Dictionary) -> Dictionary:
	if source.has("effect"):
		return source.get("effect", {})
	return source.get("effects", {})

func _clamp_state(state: Dictionary) -> void:
	var limits: Dictionary = _rooms_cfg.get("state_limits", {})
	for key in ["hp", "atk", "def", "corruption", "keys"]:
		var lim: Dictionary = limits.get(key, {})
		if lim.is_empty():
			continue
		var min_v := int(lim.get("min", -99999))
		var max_v := int(lim.get("max", 99999))
		state[key] = mini(maxi(int(state.get(key, 0)), min_v), max_v)
