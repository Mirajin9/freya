extends RefCounted
## JSON file I/O only. Callers own schemas, validation and world restoration.
## Write beside the destination and rename after a successful flush, preserving
## the previous checkpoint if opening or writing the temporary file fails.

const MAX_READ_BYTES: int = 2_000_000

func read(path: String, max_bytes: int = MAX_READ_BYTES) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return _failure(error_string(FileAccess.get_open_error()))
	if file.get_length() > max_bytes:
		file.close()
		return _failure("Save file exceeds the size limit.")
	var text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return _failure("Save file contains invalid JSON.")
	var value: Variant = parser.data
	if not value is Dictionary:
		return _failure("Save file must contain a JSON object.")
	return {"ok": true, "data": value, "error": ""}

func write(path: String, value: Dictionary, indent: String = "") -> Dictionary:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return _failure(error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(value, indent))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _failure(error_string(write_error))
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path)
	)
	if rename_error != OK:
		return _failure(error_string(rename_error))
	return {"ok": true, "error": ""}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

