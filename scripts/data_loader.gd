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

static func load_csv_rows(path: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CSV open failed: %s" % path)
		return []
	if file.eof_reached():
		return []
	var headers: PackedStringArray = file.get_csv_line()
	if headers.is_empty():
		return []
	headers[0] = headers[0].trim_prefix("\ufeff")
	for i in range(headers.size()):
		headers[i] = String(headers[i]).strip_edges()
	var rows: Array[Dictionary] = []
	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.is_empty():
			continue
		if cols.size() == 1 and String(cols[0]).strip_edges().is_empty():
			continue
		var row := {}
		for i in range(headers.size()):
			var key := String(headers[i])
			if key.is_empty():
				continue
			row[key] = String(cols[i]).strip_edges() if i < cols.size() else ""
		rows.append(row)
	return rows
