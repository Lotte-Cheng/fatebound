extends RefCounted
class_name DataLoader

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JSON file not found: %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		push_error("JSON parse failed (%s): %s at line %d" % [
			path,
			parser.get_error_message(),
			parser.get_error_line()
		])
		return {}

	if typeof(parser.data) != TYPE_DICTIONARY:
		push_error("JSON root must be an object: %s" % path)
		return {}

	return parser.data as Dictionary
