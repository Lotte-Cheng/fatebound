extends RefCounted
class_name RuleEngine

var _config: Dictionary = {}
var _entity_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _state: Dictionary = {}
var _current_room_type := ""
var _current_context: Dictionary = {}
var _finished := false
var _finish_reason := ""

func setup(game_config: Dictionary, entities_config: Dictionary) -> void:
	_config = game_config.duplicate(true)
	_entity_by_id.clear()

	var entities: Array = entities_config.get("entities", [])
	for entity_variant in entities:
		var entity: Dictionary = entity_variant
		var entity_id: String = entity.get("id", "")
		if not entity_id.is_empty():
			_entity_by_id[entity_id] = entity

	_rng.seed = int(_config.get("random_seed", 1))
	_state = _config.get("initial_state", {}).duplicate(true)
	if not _state.has("inventory"):
		_state["inventory"] = {"keys": 0}
	_state["turn"] = 1

	_finished = false
	_finish_reason = ""

	var start_room: String = _config.get("room_state_machine", {}).get("start_room", "god_room")
	_enter_room(start_room)
	_clamp_state()

func get_state() -> Dictionary:
	return _state.duplicate(true)

func is_finished() -> bool:
	return _finished

func get_finish_reason() -> String:
	return _finish_reason

func get_turn_context() -> Dictionary:
	var room_cfg := _get_room_cfg(_current_room_type)
	return {
		"turn": int(_state.get("turn", 1)),
		"room_type": _current_room_type,
		"room_display_name": room_cfg.get("display_name", _current_room_type),
		"context": _current_context.duplicate(true)
	}

func process_turn(intent_json: Dictionary) -> Dictionary:
	if _finished:
		return {
			"finished": true,
			"finish_reason": _finish_reason,
			"error": "game_already_finished"
		}

	var turn_no := int(_state.get("turn", 1))
	var state_before: Dictionary = _state.duplicate(true)
	var room_before := _current_room_type
	var context_before: Dictionary = _current_context.duplicate(true)

	var result := {
		"turn": turn_no,
		"room_type": room_before,
		"room_context": context_before,
		"intent": intent_json.duplicate(true),
		"applied_effects": [],
		"events": [],
		"combat_outcome": "",
		"god_attitude": "",
		"secret_outcome": "",
		"finished": false,
		"finish_reason": ""
	}

	match room_before:
		"combat_room":
			_resolve_combat(intent_json, result)
		"god_room":
			_resolve_god(intent_json, result)
		"secret_room":
			_resolve_secret(intent_json, result)
		_:
			result["events"].append("未知房间：跳过结算")

	_clamp_state()
	_check_end_conditions(turn_no)

	if not _finished:
		var next_room: String = _roll_next_room(room_before)
		_enter_room(next_room)
		_state["turn"] = turn_no + 1
		result["next_room"] = next_room
	else:
		result["next_room"] = ""

	result["state_before"] = state_before
	result["state_after"] = _state.duplicate(true)
	result["finished"] = _finished
	result["finish_reason"] = _finish_reason
	return result

func _resolve_combat(intent_json: Dictionary, result: Dictionary) -> void:
	var room_cfg := _get_room_cfg("combat_room")
	var encounter: Dictionary = _current_context.get("encounter", {})
	if encounter.is_empty():
		result["events"].append("战斗房缺少遭遇配置")
		return

	var intent_id: String = intent_json.get("intent", "questioning")
	var intent_profiles: Dictionary = room_cfg.get("intent_profiles", {})
	var profile: Dictionary = intent_profiles.get(intent_id, intent_profiles.get("questioning", {}))

	var player_atk_roll := int(_state.get("atk", 0)) + int(profile.get("player_attack_bonus", 0)) + _rng.randi_range(1, 6)
	var player_def_roll := int(_state.get("def", 0)) + int(profile.get("player_def_bonus", 0))
	var enemy_atk_roll := int(encounter.get("atk", 0)) + _rng.randi_range(1, 6)
	var enemy_def := int(encounter.get("def", 0))

	var damage_to_enemy := maxi(0, player_atk_roll - enemy_def)
	var damage_to_player := maxi(0, enemy_atk_roll - player_def_roll)

	if damage_to_player > 0:
		_apply_stat_delta("hp", -damage_to_player, "遭受反击：HP %d" % -damage_to_player, result, "combat_damage")

	if int(profile.get("fate_delta", 0)) != 0:
		_apply_stat_delta("fate", int(profile.get("fate_delta", 0)), "战斗意图影响命运", result, "combat_profile")
	if int(profile.get("corruption_delta", 0)) != 0:
		_apply_stat_delta("corruption", int(profile.get("corruption_delta", 0)), "战斗意图影响腐化", result, "combat_profile")

	var outcome := "draw"
	if damage_to_enemy > damage_to_player:
		outcome = "win"
	elif damage_to_enemy < damage_to_player:
		outcome = "lose"
	result["combat_outcome"] = outcome
	result["events"].append("战斗结果：%s（对敌伤害 %d / 受到伤害 %d）" % [outcome, damage_to_enemy, damage_to_player])

	var resolution: Dictionary = room_cfg.get("resolution", {}).get(outcome, {})
	_apply_resolution_deltas(resolution, result, "combat_resolution")

	var reward_rolls := int(resolution.get("reward_rolls", 0))
	var curse_rolls := int(resolution.get("curse_rolls", 0))
	_apply_pool(room_cfg.get("reward_pool", []), reward_rolls, result, "combat_reward")
	_apply_pool(room_cfg.get("curse_pool", []), curse_rolls, result, "combat_curse")

	var key_drop_chance := float(resolution.get("key_drop_chance", 0.0))
	if key_drop_chance > 0.0 and _rng.randf() < key_drop_chance:
		_apply_inventory_delta("keys", 1, "击败敌人掉落钥匙：Keys +1", result, "combat_drop")

func _resolve_god(intent_json: Dictionary, result: Dictionary) -> void:
	var room_cfg := _get_room_cfg("god_room")
	var entity_id: String = _current_context.get("entity_id", "")
	if not _entity_by_id.has(entity_id):
		result["events"].append("神明房缺少实体配置")
		return

	var entity: Dictionary = _entity_by_id[entity_id]
	var intent_id: String = intent_json.get("intent", "questioning")
	var bias := int(entity.get("intent_bias", {}).get(intent_id, 0))

	var attitude: Dictionary = _pick_attitude(room_cfg.get("attitude_table", []), bias)
	var attitude_id: String = attitude.get("id", "neutral")
	result["god_attitude"] = attitude_id
	result["events"].append("神意倾向：%s（bias=%d）" % [attitude_id, bias])

	_apply_resolution_deltas(attitude, result, "god_attitude")

	var reward_rolls := int(attitude.get("reward_rolls", 0))
	var curse_rolls := int(attitude.get("curse_rolls", 0))
	_apply_pool(entity.get("reward_pool", []), reward_rolls, result, "god_reward")
	_apply_pool(entity.get("curse_pool", []), curse_rolls, result, "god_curse")

func _resolve_secret(intent_json: Dictionary, result: Dictionary) -> void:
	var room_cfg := _get_room_cfg("secret_room")
	var required_item: String = room_cfg.get("requires_item", "keys")
	var inventory: Dictionary = _state.get("inventory", {})
	var item_count := int(inventory.get(required_item, 0))

	if item_count > 0:
		result["secret_outcome"] = "unlocked"
		var unlock_resolution: Dictionary = room_cfg.get("unlock_resolution", {})
		var consume_count := int(unlock_resolution.get("consume_item", 0))
		if consume_count > 0:
			_apply_inventory_delta(required_item, -consume_count, "消耗钥匙：%s %d" % [required_item.capitalize(), -consume_count], result, "secret_unlock")

		_apply_resolution_deltas(unlock_resolution, result, "secret_unlock")
		_apply_pool(room_cfg.get("reward_pool", []), int(unlock_resolution.get("reward_rolls", 0)), result, "secret_reward")
		_apply_pool(room_cfg.get("curse_pool", []), int(unlock_resolution.get("curse_rolls", 0)), result, "secret_curse")
		result["events"].append("密室开启成功")
	else:
		result["secret_outcome"] = "locked"
		var locked_resolution: Dictionary = room_cfg.get("locked_resolution", {})
		_apply_resolution_deltas(locked_resolution, result, "secret_locked")
		_apply_pool(room_cfg.get("reward_pool", []), int(locked_resolution.get("reward_rolls", 0)), result, "secret_reward")
		_apply_pool(room_cfg.get("curse_pool", []), int(locked_resolution.get("curse_rolls", 0)), result, "secret_curse")
		result["events"].append("钥匙不足，密室未开启")

func _apply_resolution_deltas(resolution: Dictionary, result: Dictionary, source: String) -> void:
	if int(resolution.get("fate_delta", 0)) != 0:
		_apply_stat_delta("fate", int(resolution.get("fate_delta", 0)), "命运变化", result, source)
	if int(resolution.get("corruption_delta", 0)) != 0:
		_apply_stat_delta("corruption", int(resolution.get("corruption_delta", 0)), "腐化变化", result, source)
	if int(resolution.get("hp_delta", 0)) != 0:
		_apply_stat_delta("hp", int(resolution.get("hp_delta", 0)), "生命变化", result, source)
	if int(resolution.get("atk_delta", 0)) != 0:
		_apply_stat_delta("atk", int(resolution.get("atk_delta", 0)), "攻击变化", result, source)
	if int(resolution.get("def_delta", 0)) != 0:
		_apply_stat_delta("def", int(resolution.get("def_delta", 0)), "防御变化", result, source)

func _apply_pool(pool: Array, rolls: int, result: Dictionary, source: String) -> void:
	if rolls <= 0:
		return
	for _i in range(rolls):
		var picked: Dictionary = _pick_pool_item(pool)
		if picked.is_empty():
			continue
		_apply_effect(picked, result, source)

func _pick_pool_item(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}

	var total_weight := 0.0
	for item_variant in pool:
		var item: Dictionary = item_variant
		total_weight += maxf(0.0, float(item.get("weight", 1.0)))

	if total_weight <= 0.0:
		return pool[0]

	var ticket := _rng.randf() * total_weight
	var running := 0.0
	for item_variant in pool:
		var item: Dictionary = item_variant
		running += maxf(0.0, float(item.get("weight", 1.0)))
		if ticket <= running:
			return item
	return pool[-1]

func _apply_effect(effect: Dictionary, result: Dictionary, source: String) -> void:
	var effect_type: String = effect.get("type", "")
	var label: String = effect.get("label", "")
	var effect_id: String = effect.get("id", "")

	match effect_type:
		"stat":
			_apply_stat_delta(
				effect.get("stat", ""),
				int(effect.get("delta", 0)),
				label,
				result,
				source,
				effect_id
			)
		"inventory":
			_apply_inventory_delta(
				effect.get("item", "keys"),
				int(effect.get("delta", 0)),
				label,
				result,
				source,
				effect_id
			)
		_:
			result["events"].append("忽略未知效果类型：%s" % effect_type)

func _apply_stat_delta(
		stat: String,
		delta: int,
		label: String,
		result: Dictionary,
		source: String,
		effect_id: String = ""
	) -> void:
	if stat.is_empty() or delta == 0:
		return
	if not _state.has(stat):
		_state[stat] = 0
	_state[stat] = int(_state.get(stat, 0)) + delta

	result["applied_effects"].append({
		"source": source,
		"effect_id": effect_id,
		"type": "stat",
		"stat": stat,
		"delta": delta,
		"label": label if not label.is_empty() else "%s %+d" % [stat, delta]
	})

func _apply_inventory_delta(
		item: String,
		delta: int,
		label: String,
		result: Dictionary,
		source: String,
		effect_id: String = ""
	) -> void:
	if item.is_empty() or delta == 0:
		return
	var inventory: Dictionary = _state.get("inventory", {})
	inventory[item] = int(inventory.get(item, 0)) + delta
	_state["inventory"] = inventory

	result["applied_effects"].append({
		"source": source,
		"effect_id": effect_id,
		"type": "inventory",
		"item": item,
		"delta": delta,
		"label": label if not label.is_empty() else "%s %+d" % [item, delta]
	})

func _enter_room(room_type: String) -> void:
	_current_room_type = room_type
	_current_context = {}

	var room_cfg := _get_room_cfg(room_type)
	match room_type:
		"combat_room":
			var encounters: Array = room_cfg.get("encounters", [])
			if not encounters.is_empty():
				var encounter: Dictionary = encounters[_rng.randi_range(0, encounters.size() - 1)]
				_current_context["encounter"] = encounter
		"god_room":
			var pool: Array = room_cfg.get("entity_pool", [])
			if not pool.is_empty():
				var entity_id: String = String(pool[_rng.randi_range(0, pool.size() - 1)])
				if _entity_by_id.has(entity_id):
					var entity: Dictionary = _entity_by_id[entity_id]
					_current_context = {
						"entity_id": entity_id,
						"entity_name": entity.get("name", entity_id),
						"entity_role": entity.get("role", "unknown"),
						"entity_persona": entity.get("persona", "")
					}
		"secret_room":
			_current_context = {
				"requires_item": room_cfg.get("requires_item", "keys")
			}
		_:
			_current_context = {}

func _roll_next_room(current_room: String) -> String:
	var transitions: Dictionary = _config.get("room_state_machine", {}).get("transitions", {})
	var options: Dictionary = transitions.get(current_room, {})
	if options.is_empty():
		return "god_room"

	var total_weight := 0.0
	for key_variant in options.keys():
		total_weight += maxf(0.0, float(options.get(key_variant, 0.0)))

	if total_weight <= 0.0:
		return String(options.keys()[0])

	var ticket := _rng.randf() * total_weight
	var running := 0.0
	for key_variant in options.keys():
		running += maxf(0.0, float(options.get(key_variant, 0.0)))
		if ticket <= running:
			return String(key_variant)
	return String(options.keys()[-1])

func _pick_attitude(attitude_table: Array, bias: int) -> Dictionary:
	for entry_variant in attitude_table:
		var entry: Dictionary = entry_variant
		if bias >= int(entry.get("min_bias", -999)):
			return entry
	return {
		"id": "neutral",
		"reward_rolls": 1,
		"curse_rolls": 1,
		"fate_delta": 0,
		"corruption_delta": 0
	}

func _check_end_conditions(completed_turn: int) -> void:
	if int(_state.get("hp", 0)) <= 0:
		_finished = true
		_finish_reason = "你倒下了，命线中断。"
		return

	if int(_state.get("corruption", 0)) >= int(_config.get("defeat_corruption", 999)):
		_finished = true
		_finish_reason = "腐化失控，邪灵吞没了你。"
		return

	if int(_state.get("fate", 0)) >= int(_config.get("victory_fate", 999)):
		_finished = true
		_finish_reason = "你完成了命运绑定，暂时压制了低语。"
		return

	if completed_turn >= int(_config.get("max_turns", 999)):
		_finished = true
		_finish_reason = "时限已到，本次远征结束。"
		return

func _clamp_state() -> void:
	var limits: Dictionary = _config.get("state_limits", {})
	for stat in ["hp", "atk", "def", "corruption", "fate"]:
		var range_cfg: Dictionary = limits.get(stat, {})
		if range_cfg.is_empty():
			continue
		var min_val := int(range_cfg.get("min", -99999))
		var max_val := int(range_cfg.get("max", 99999))
		var current := int(_state.get(stat, 0))
		_state[stat] = mini(maxi(current, min_val), max_val)

	var inv_limits: Dictionary = limits.get("inventory_keys", {})
	var min_key := int(inv_limits.get("min", 0))
	var max_key := int(inv_limits.get("max", 99))
	var inventory: Dictionary = _state.get("inventory", {})
	inventory["keys"] = mini(maxi(int(inventory.get("keys", 0)), min_key), max_key)
	_state["inventory"] = inventory

func _get_room_cfg(room_type: String) -> Dictionary:
	return _config.get("rooms", {}).get(room_type, {})
