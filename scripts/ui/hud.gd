extends PanelContainer
class_name HUDPanel

@onready var _stats_label: Label = $VBox/StatsLabel
@onready var _meta_label: Label = $VBox/MetaLabel
@onready var _debt_meta_label: Label = $VBox/DebtMetaLabel

func set_state(state: Dictionary, turn_no: int, room_index: int, room_total: int) -> void:
	_stats_label.text = "HP %d | ATK %d | DEF %d | Corruption %d | Fate %d | Keys %d" % [
		int(state.get("hp", 0)),
		int(state.get("atk", 0)),
		int(state.get("def", 0)),
		int(state.get("corruption", 0)),
		int(state.get("fate", 0)),
		int(state.get("keys", 0))
	]
	_meta_label.text = "Turn %d | Room %d/%d" % [turn_no, room_index + 1, room_total]

	var pending: Array = state.get("pending_effects", [])
	var triggers: Array[String] = []
	for item_variant in pending:
		var item: Dictionary = item_variant
		triggers.append(String(item.get("trigger", "?")))
	_debt_meta_label.text = "挂载债务：%d | 触发点：%s" % [
		pending.size(),
		", ".join(triggers)
	]
