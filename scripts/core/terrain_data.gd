# terrain_data.gd
# Core terrain property storage for Pā 596
# Stores tactical properties separate from visual representation
extends Resource
class_name TerrainData

# Map dimensions
@export var width: int = 50
@export var height: int = 50

# Cell data storage - key: Vector2i, value: Dictionary
var cells: Dictionary = {}

# Default cell properties
const DEFAULT_CELL = {
	"terrain_type": "open",   # Visual/logical type: open, road, rough, water, building, impassable
	"elevation": 1,           # 0-5, where 1 is ground level
	"blocks_los": false,      # Complete LOS block (buildings, cliffs)
	"cover": 0,               # 0=none, 1=light (-20%), 2=heavy (-50%)
	"concealment": false,     # Hidden at distance (bushes, tall grass)
	"movement_cost": 1.0,     # Multiplier: <1 = road, >1 = rough
	"is_water": false,        # Affects certain unit types
	"is_destructible": false, # Can be damaged
	"is_flammable": false,    # Can catch fire
	"is_impassable": false,   # Cannot traverse
	"damage_state": 0,        # 0=intact, 1=damaged, 2=destroyed
}

# Cover type enum for clarity
enum Cover { NONE = 0, LIGHT = 1, HEAVY = 2 }

# --- Core Methods ---

func _init(w: int = 50, h: int = 50) -> void:
	width = w
	height = h
	cells = {}

func get_cell(pos: Vector2i) -> Dictionary:
	"""Get properties for a cell. Returns default if not set."""
	if cells.has(pos):
		return cells[pos]
	return DEFAULT_CELL.duplicate()

func set_cell(pos: Vector2i, properties: Dictionary) -> void:
	"""Set all properties for a cell."""
	if is_valid_cell(pos):
		cells[pos] = properties

func set_cell_property(pos: Vector2i, property: String, value) -> void:
	"""Set a single property for a cell."""
	if not is_valid_cell(pos):
		return
	if not cells.has(pos):
		cells[pos] = DEFAULT_CELL.duplicate()
	cells[pos][property] = value

func get_cell_property(pos: Vector2i, property: String):
	"""Get a single property from a cell."""
	var cell = get_cell(pos)
	return cell.get(property, null)

func is_valid_cell(pos: Vector2i) -> bool:
	"""Check if coordinates are within map bounds."""
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func clear() -> void:
	"""Reset all cells to default."""
	cells = {}

func resize(new_width: int, new_height: int) -> void:
	"""Resize the map, preserving existing data within bounds."""
	var old_cells = cells.duplicate()
	cells = {}
	width = new_width
	height = new_height
	for pos in old_cells:
		if is_valid_cell(pos):
			cells[pos] = old_cells[pos]

# --- LOS and Combat Queries ---

func blocks_line_of_sight(pos: Vector2i) -> bool:
	"""Check if this cell completely blocks LOS."""
	return get_cell_property(pos, "blocks_los")

func get_cover_value(pos: Vector2i) -> int:
	"""Get the cover value at this position."""
	return get_cell_property(pos, "cover")

func get_movement_cost(pos: Vector2i) -> float:
	"""Get movement cost multiplier."""
	if get_cell_property(pos, "is_impassable"):
		return INF
	return get_cell_property(pos, "movement_cost")

func get_elevation(pos: Vector2i) -> int:
	"""Get elevation at this position."""
	return get_cell_property(pos, "elevation")

func can_see(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	"""Basic LOS check - returns true if line of sight exists.
	   This is a simplified version. Full implementation needs Bresenham."""
	# TODO: Implement proper Bresenham line with elevation checks
	var line = _get_line_cells(from_pos, to_pos)
	for cell_pos in line:
		if cell_pos == from_pos or cell_pos == to_pos:
			continue
		if blocks_line_of_sight(cell_pos):
			return false
	return true

func _get_line_cells(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	"""Get all cells along a line (Bresenham's algorithm)."""
	var result: Array[Vector2i] = []
	var x0 = from_pos.x
	var y0 = from_pos.y
	var x1 = to_pos.x
	var y1 = to_pos.y
	
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	
	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	
	return result

# --- Serialization ---

func to_dict() -> Dictionary:
	"""Convert to dictionary for saving."""
	var cell_data = {}
	for pos in cells:
		# Store as string key for JSON compatibility
		var key = "%d,%d" % [pos.x, pos.y]
		cell_data[key] = cells[pos]
	
	return {
		"width": width,
		"height": height,
		"cells": cell_data
	}

func from_dict(data: Dictionary) -> void:
	"""Load from dictionary."""
	width = data.get("width", 50)
	height = data.get("height", 50)
	cells = {}
	
	var cell_data = data.get("cells", {})
	for key in cell_data:
		var parts = key.split(",")
		if parts.size() == 2:
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			cells[pos] = cell_data[key]

func save_to_file(path: String) -> Error:
	"""Save terrain data to a JSON file."""
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return OK

func load_from_file(path: String) -> Error:
	"""Load terrain data from a JSON file."""
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return error
	from_dict(json.data)
	return OK
