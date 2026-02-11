# terrain_editor.gd
# Handles terrain painting, elevation editing, test map generation, save/load.
# Extracted from battle_map.gd to keep the battle manager focused on combat.
extends RefCounted

signal terrain_changed()

enum BrushMode { NONE, TERRAIN, ELEVATION }

var terrain: TerrainData = null

# Brush state
var brush_mode: int = BrushMode.NONE
var paint_mode := false  # true when brush_mode != NONE
var paint_terrain := "open"
var elevation_delta := 1

# Terrain type mapping for painting
var terrain_types := ["open", "road", "rough", "water", "building", "impassable"]
var current_terrain_index := 0

func _init(p_terrain: TerrainData) -> void:
	terrain = p_terrain

# === INPUT HANDLING ===
# Returns true if the event was consumed by the editor

func handle_left_click(pos: Vector2i) -> bool:
	if not terrain.is_valid_cell(pos):
		return false
	if brush_mode == BrushMode.TERRAIN:
		paint_cell(pos)
		return true
	elif brush_mode == BrushMode.ELEVATION:
		paint_elevation(pos, 1)
		return true
	return false

func handle_right_click(pos: Vector2i) -> bool:
	if brush_mode == BrushMode.TERRAIN:
		# Cycle terrain type
		current_terrain_index = (current_terrain_index + 1) % terrain_types.size()
		paint_terrain = terrain_types[current_terrain_index]
		print("TERRAIN BRUSH: %s" % paint_terrain)
		return true
	elif brush_mode == BrushMode.ELEVATION:
		# Right-click lowers elevation
		if terrain.is_valid_cell(pos):
			paint_elevation(pos, -1)
		return true
	return false

func handle_key(keycode: int, hover_pos: Vector2i) -> bool:
	match keycode:
		KEY_P:
			cycle_brush_mode()
			return true
		KEY_0:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 0)
				return true
		KEY_1:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 1)
				return true
			else:
				select_terrain(0)
				return true
		KEY_2:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 2)
				return true
			else:
				select_terrain(1)
				return true
		KEY_3:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 3)
				return true
			else:
				select_terrain(2)
				return true
		KEY_4:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 4)
				return true
			else:
				select_terrain(3)
				return true
		KEY_5:
			if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hover_pos):
				set_elevation(hover_pos, 5)
				return true
			else:
				select_terrain(4)
				return true
		KEY_6:
			select_terrain(5)
			return true
		KEY_F2:
			save_map()
			return true
		KEY_F3:
			load_map()
			return true
	return false

func handle_drag(pos: Vector2i) -> void:
	if brush_mode == BrushMode.NONE:
		return
	if not terrain.is_valid_cell(pos):
		return
	if brush_mode == BrushMode.TERRAIN:
		paint_cell(pos)
	elif brush_mode == BrushMode.ELEVATION:
		paint_elevation(pos, 1)

# === BRUSH MODE ===

func cycle_brush_mode() -> void:
	"""Cycle: NONE -> TERRAIN -> ELEVATION -> NONE"""
	brush_mode = (brush_mode + 1) % 3
	paint_mode = (brush_mode != BrushMode.NONE)

	match brush_mode:
		BrushMode.NONE:
			print("=== BRUSH OFF ===")
		BrushMode.TERRAIN:
			print("=== TERRAIN BRUSH: %s === (1-6 select type, RClick cycle)" % paint_terrain)
		BrushMode.ELEVATION:
			print("=== ELEVATION BRUSH === (LClick raise, RClick lower, 0-5 set directly)")

func select_terrain(index: int) -> void:
	if index < terrain_types.size():
		current_terrain_index = index
		paint_terrain = terrain_types[index]
		if brush_mode == BrushMode.TERRAIN:
			print("TERRAIN BRUSH: %s" % paint_terrain)
		else:
			print("Selected: %s" % paint_terrain)

# === PAINTING ===

func paint_cell(pos: Vector2i) -> void:
	terrain.set_cell_property(pos, "terrain_type", paint_terrain)

	# Set associated properties based on terrain type
	match paint_terrain:
		"open":
			terrain.set_cell_property(pos, "movement_cost", 1.0)
			terrain.set_cell_property(pos, "blocks_los", false)
			terrain.set_cell_property(pos, "cover", 0)
			terrain.set_cell_property(pos, "is_water", false)
			terrain.set_cell_property(pos, "is_impassable", false)
		"road":
			terrain.set_cell_property(pos, "movement_cost", 0.5)
			terrain.set_cell_property(pos, "blocks_los", false)
			terrain.set_cell_property(pos, "cover", 0)
		"rough":
			terrain.set_cell_property(pos, "movement_cost", 1.5)
			terrain.set_cell_property(pos, "concealment", true)
			terrain.set_cell_property(pos, "cover", 1)
		"water":
			terrain.set_cell_property(pos, "movement_cost", 3.0)
			terrain.set_cell_property(pos, "is_water", true)
			terrain.set_cell_property(pos, "elevation", 0)
		"building":
			terrain.set_cell_property(pos, "blocks_los", true)
			terrain.set_cell_property(pos, "cover", 2)
			terrain.set_cell_property(pos, "is_destructible", true)
		"impassable":
			terrain.set_cell_property(pos, "is_impassable", true)
			terrain.set_cell_property(pos, "blocks_los", true)
			terrain.set_cell_property(pos, "movement_cost", INF)

	terrain_changed.emit()

func paint_elevation(pos: Vector2i, delta: int) -> void:
	"""Raise or lower elevation at pos by delta."""
	var current_elev: int = terrain.get_cell_property(pos, "elevation")
	var new_elev := clampi(current_elev + delta, 0, 5)
	if new_elev != current_elev:
		terrain.set_cell_property(pos, "elevation", new_elev)
		terrain_changed.emit()

func set_elevation(pos: Vector2i, value: int) -> void:
	"""Set elevation at pos to an absolute value."""
	var clamped := clampi(value, 0, 5)
	terrain.set_cell_property(pos, "elevation", clamped)
	terrain_changed.emit()

# === TEST MAP GENERATION ===

func generate_test_terrain() -> void:
	"""Seed the map with some variety so it's not a flat void."""
	# Base everything as open ground
	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			terrain.set_cell_property(pos, "terrain_type", "open")

			# Some random elevation variation
			var elev := 1
			var noise_val := sin(x * 0.3) * cos(y * 0.4) + sin(x * 0.1 + y * 0.2)
			if noise_val > 0.8:
				elev = 3
			elif noise_val > 0.3:
				elev = 2
			elif noise_val < -0.8:
				elev = 0
			terrain.set_cell_property(pos, "elevation", elev)

	# A road running roughly east-west
	for x in range(terrain.width):
		var road_y := int(terrain.height * 0.4 + sin(x * 0.2) * 2)
		for dy in range(-1, 1):
			var pos := Vector2i(x, clampi(road_y + dy, 0, terrain.height - 1))
			terrain.set_cell_property(pos, "terrain_type", "road")
			terrain.set_cell_property(pos, "movement_cost", 0.5)
			terrain.set_cell_property(pos, "elevation", 1)

	# A river/stream
	for y in range(terrain.height):
		var river_x := int(terrain.width * 0.6 + sin(y * 0.3) * 3)
		var pos := Vector2i(clampi(river_x, 0, terrain.width - 1), y)
		terrain.set_cell_property(pos, "terrain_type", "water")
		terrain.set_cell_property(pos, "is_water", true)
		terrain.set_cell_property(pos, "movement_cost", 3.0)
		terrain.set_cell_property(pos, "elevation", 0)

	# A few buildings
	var building_spots := [Vector2i(10, 8), Vector2i(12, 8), Vector2i(10, 10),
						   Vector2i(25, 20), Vector2i(26, 20), Vector2i(25, 21)]
	for pos in building_spots:
		if terrain.is_valid_cell(pos):
			terrain.set_cell_property(pos, "terrain_type", "building")
			terrain.set_cell_property(pos, "blocks_los", true)
			terrain.set_cell_property(pos, "cover", 2)
			terrain.set_cell_property(pos, "is_destructible", true)

	# Some rough terrain patches
	for i in range(30):
		var rx := randi_range(0, terrain.width - 1)
		var ry := randi_range(0, terrain.height - 1)
		var pos := Vector2i(rx, ry)
		var cell = terrain.get_cell(pos)
		if cell.get("terrain_type", "open") == "open":
			terrain.set_cell_property(pos, "terrain_type", "rough")
			terrain.set_cell_property(pos, "movement_cost", 1.5)
			terrain.set_cell_property(pos, "concealment", true)
			terrain.set_cell_property(pos, "cover", 1)

# === SAVE / LOAD ===

func save_map() -> void:
	var path := "user://test_map.json"
	var err := terrain.save_to_file(path)
	if err == OK:
		print("Map saved to %s" % path)
	else:
		print("Failed to save map: %s" % error_string(err))

func load_map() -> void:
	var path := "user://test_map.json"
	var err := terrain.load_from_file(path)
	if err == OK:
		print("Map loaded from %s" % path)
		terrain_changed.emit()
	else:
		print("No saved map found (or load failed)")
