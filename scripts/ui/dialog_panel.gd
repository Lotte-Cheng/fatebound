extends PanelContainer
class_name DialogPanel

signal send_requested(player_text: String)

@onready var _restraint_btn: Button = $VBox/StanceRow/RestraintButton
@onready var _pact_btn: Button = $VBox/StanceRow/PactButton
@onready var _blasphemy_btn: Button = $VBox/StanceRow/BlasphemyButton
@onready var _selected_stance_label: Label = $VBox/StanceRow/SelectedStanceLabel

@onready var _input: LineEdit = $VBox/InputRow/ActionInput
@onready var _send_btn: Button = $VBox/InputRow/SendButton
@onready var _intent_output: RichTextLabel = $VBox/MainSplit/TopTabs/IntentTab/IntentOutput
@onready var _resolution_output: RichTextLabel = $VBox/MainSplit/TopTabs/ResolutionTab/ResolutionOutput
@onready var _narrative_output: RichTextLabel = $VBox/MainSplit/TopTabs/NarrativeTab/NarrativeOutput
@onready var _debt_output: RichTextLabel = $VBox/MainSplit/TopTabs/DebtTab/DebtOutput
@onready var _event_log: RichTextLabel = $VBox/MainSplit/LogSection/EventLog

var _selected_stance := "restraint"

func _ready() -> void:
	_send_btn.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(_on_text_submitted)
	_restraint_btn.pressed.connect(func() -> void: set_selected_stance("restraint"))
	_pact_btn.pressed.connect(func() -> void: set_selected_stance("pact"))
	_blasphemy_btn.pressed.connect(func() -> void: set_selected_stance("blasphemy"))
	set_selected_stance(_selected_stance)

func get_player_text() -> String:
	return _input.text.strip_edges()

func clear_input() -> void:
	_input.clear()
	_input.grab_focus()

func set_interaction_enabled(enabled: bool) -> void:
	_input.editable = enabled
	_send_btn.disabled = not enabled
	_restraint_btn.disabled = not enabled
	_pact_btn.disabled = not enabled
	_blasphemy_btn.disabled = not enabled

func get_selected_stance() -> String:
	return _selected_stance

func set_selected_stance(stance: String) -> void:
	if stance not in ["restraint", "pact", "blasphemy"]:
		stance = "restraint"
	_selected_stance = stance
	_restraint_btn.button_pressed = stance == "restraint"
	_pact_btn.button_pressed = stance == "pact"
	_blasphemy_btn.button_pressed = stance == "blasphemy"
	_selected_stance_label.text = "当前：%s" % stance

func set_intent_json(intent_json: Dictionary) -> void:
	_intent_output.text = JSON.stringify(intent_json, "\t")

func set_resolution_json(resolution_json: Dictionary) -> void:
	_resolution_output.text = JSON.stringify(resolution_json, "\t")

func set_narrative(text: String) -> void:
	_narrative_output.text = text

func set_pending_effects(pending_effects: Array) -> void:
	if pending_effects.is_empty():
		_debt_output.text = "[]"
		return
	_debt_output.text = JSON.stringify(pending_effects, "\t")

func append_log(text: String) -> void:
	if _event_log.text.is_empty():
		_event_log.text = text
	else:
		_event_log.text += "\n\n" + text

func _on_send_pressed() -> void:
	emit_signal("send_requested", get_player_text())

func _on_text_submitted(_new_text: String) -> void:
	emit_signal("send_requested", get_player_text())
