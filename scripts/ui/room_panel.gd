extends PanelContainer
class_name RoomPanel

signal next_room_requested

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _detail_label: Label = $VBox/DetailLabel
@onready var _progress_label: Label = $VBox/ProgressLabel
@onready var _next_button: Button = $VBox/NextButton

func _ready() -> void:
	_next_button.pressed.connect(_on_next_pressed)

func set_room(room_data: Dictionary, room_index: int, room_total: int, resolved: bool, can_advance: bool) -> void:
	_title_label.text = "当前房间：%s" % room_data.get("display_name", room_data.get("id", "未知房间"))
	var room_type: String = String(room_data.get("type", "unknown"))
	var detail_lines: Array[String] = [
		"类型：%s | God: %s | 规则标签：%s" % [
			room_type,
			room_data.get("god_id", "none"),
			", ".join(room_data.get("tags", []))
		]
	]

	if room_type == "combat_room":
		detail_lines.append("阈值：ATK>=%d DEF>=%d | Corruption阈值=%d Fate阈值=%d" % [
			int(room_data.get("min_atk", 0)),
			int(room_data.get("min_def", 0)),
			int(room_data.get("corruption_threshold", 999)),
			int(room_data.get("fate_threshold", 999))
		])
		detail_lines.append("敌人：HP %d ATK %d DEF %d | 胜利掉钥匙 %+d" % [
			int(room_data.get("enemy_hp", 0)),
			int(room_data.get("enemy_atk", 0)),
			int(room_data.get("enemy_def", 0)),
			int(room_data.get("key_drop_on_win", 0))
		])
	elif room_type == "secret_room":
		detail_lines.append("密室门槛：需要神之钥匙 x%d" % int(room_data.get("requires_keys", 1)))
	elif room_type == "god_room":
		detail_lines.append("祈求姿态影响 reward/curse 抽取权重与债务强度。")

	_detail_label.text = "\n".join(detail_lines)
	_progress_label.text = "进度：%d/%d | 当前房间已结算：%s" % [
		room_index + 1,
		room_total,
		"是" if resolved else "否"
	]
	_next_button.disabled = not can_advance

func set_next_button_text(value: String) -> void:
	_next_button.text = value

func _on_next_pressed() -> void:
	emit_signal("next_room_requested")
