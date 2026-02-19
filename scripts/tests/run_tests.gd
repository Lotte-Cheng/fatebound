extends SceneTree

func _init() -> void:
	var suite_script = preload("res://scripts/tests/test_fate_rule_engine.gd")
	var suite = suite_script.new()
	var report := suite.run_all()
	for line_variant in report.get("messages", []):
		print(line_variant)
	quit(0 if report.get("ok", false) else 1)
