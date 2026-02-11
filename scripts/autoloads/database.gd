extends Node
## Central access point for all JSON data.
## Loads and validates all database files on startup. Systems query
## this autoload for entity definitions instead of hardcoding values.

var weapons: Dictionary = {}
var soldiers: Dictionary = {}
var squads: Dictionary = {}
var hostiles: Dictionary = {}
var terrain_types: Dictionary = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	weapons = _load_validated("res://data/base/weapons.json")
	soldiers = _load_validated("res://data/base/soldiers.json")
	squads = _load_validated("res://data/base/squads.json")
	hostiles = _load_validated("res://data/base/hostiles.json")
	terrain_types = _load_validated("res://data/terrain/terrain_types.json")
	terrain_types = _resolve_inheritance(terrain_types)

func _load_validated(data_path: String) -> Dictionary:
	var schema_path := data_path.replace(".json", ".schema.json")
	var schema := {}

	# Schema is optional but recommended
	if FileAccess.file_exists(schema_path):
		schema = _load_json(schema_path)
	else:
		push_warning("No schema found for %s (expected %s)" % [data_path, schema_path])

	return _load_json(data_path, schema)

func _load_json(path: String, schema: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Database file not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var error := json.parse(file.get_as_text())

	if error != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	var data: Dictionary = json.data

	# Validate against schema if provided
	if not schema.is_empty():
		_validate_schema(path, data, schema)

	return data

func _validate_schema(path: String, data: Dictionary, schema: Dictionary) -> void:
	for entry_id in data:
		var entry: Dictionary = data[entry_id]
		for required_key in schema.get("required", []):
			if not entry.has(required_key):
				push_error("SCHEMA ERROR in %s: '%s' missing required key '%s'" % [path, entry_id, required_key])
		for key in entry:
			if schema.has("known_keys") and key not in schema.known_keys:
				push_warning("SCHEMA WARNING in %s: '%s' has unknown key '%s' (typo?)" % [path, entry_id, key])

func _resolve_inheritance(data: Dictionary) -> Dictionary:
	var resolved := {}
	for type_id in data:
		var entry: Dictionary = data[type_id].duplicate(true)
		if entry.has("inherits"):
			var parent_id: String = entry["inherits"]
			if data.has(parent_id):
				var parent: Dictionary = data[parent_id].duplicate(true)
				parent.merge(entry, true)  # child overrides parent
				parent.erase("inherits")
				entry = parent
			else:
				push_error("INHERITANCE ERROR: '%s' inherits from unknown type '%s'" % [type_id, parent_id])
		resolved[type_id] = entry
	return resolved

# === LOOKUP FUNCTIONS ===

func get_weapon(weapon_id: String) -> Dictionary:
	return weapons.get(weapon_id, {})

func get_soldier_template(template_id: String) -> Dictionary:
	return soldiers.get(template_id, {})

func get_squad_template(template_id: String) -> Dictionary:
	return squads.get(template_id, {})

func get_hostile_template(template_id: String) -> Dictionary:
	return hostiles.get(template_id, {})

func get_terrain_type(type_id: String) -> Dictionary:
	return terrain_types.get(type_id, terrain_types.get("open", {}))
