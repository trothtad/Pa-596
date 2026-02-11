# battle_map.gd
# Renders the terrain grid and handles mouse interaction
# This is the visual heart of the tactical layer
extends Node2D

const PathfinderClass = preload("res://scripts/core/pathfinder.gd")
const SoldierClass = preload("res://scripts/core/soldier.gd")
const HoundClass = preload("res://scripts/core/hound.gd")
const DetectionClass = preload("res://scripts/core/detection.gd")

# Grid settings
const CELL_SIZE := 32  # pixels per cell
const DEFAULT_WIDTH := 40
const DEFAULT_HEIGHT := 30

# Terrain type colors - deliberately ugly placeholder palette
# We'll know it works BECAUSE it's ugly
const TERRAIN_COLORS := {
	"open": Color(0.45, 0.55, 0.35),      # Olive drab - open ground
	"road": Color(0.55, 0.50, 0.40),       # Dusty tan - roads
	"rough": Color(0.35, 0.40, 0.25),      # Dark green - rough/bush
	"water": Color(0.25, 0.35, 0.55),      # Steel blue - water
	"building": Color(0.50, 0.45, 0.40),   # Concrete grey-brown
	"impassable": Color(0.30, 0.30, 0.30), # Dark grey - cliffs etc
}

# Elevation shading - darken low, lighten high
const ELEVATION_SHADE := 0.06  # per elevation level above/below baseline

# The data
var terrain: TerrainData = null

# Grid overlay visibility
var show_grid := true
var show_elevation := false
var show_cover := false

# Mouse tracking
var hovered_cell := Vector2i(-1, -1)
var selected_cell := Vector2i(-1, -1)

# LOS visualization
var los_visible_cells: Array[Vector2i] = []
var los_origin := Vector2i(-1, -1)
var show_los := false

# Units
var units: Array[Node2D] = []
var selected_unit: Node2D = null
var pathfinder = null  # PathfinderClass instance
var preview_path: Array[Vector2i] = []  # path preview on hover

# Hostiles
var hostiles: Array[Node2D] = []

# Squad detection of hostiles
var squad_detection_states: Dictionary = {}  # hostile_id -> DetectionState
var squad_observer_profile = null
var detected_hostile_positions: Dictionary = {}  # hostile_id -> {pos, level, label}

# Fog of war
var fog_enabled := true
var fog_visible: Dictionary = {}   # cells ANY unit can currently see
var fog_explored: Dictionary = {}  # cells that have EVER been seen

# Brush system
enum BrushMode { NONE, TERRAIN, ELEVATION }
var brush_mode: int = BrushMode.NONE
var paint_mode := false  # kept for compatibility - true when brush_mode != NONE
var paint_terrain := "open"
var elevation_delta := 1  # +1 to raise, -1 to lower

# Terrain type mapping for painting (cycle through these)
var terrain_types := ["open", "road", "rough", "water", "building", "impassable"]
var current_terrain_index := 0

signal cell_selected(pos: Vector2i)
signal cell_hovered(pos: Vector2i)

func _ready() -> void:
	# Create default terrain
	terrain = TerrainData.new(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	_generate_test_terrain()
	
	# Create pathfinder
	pathfinder = PathfinderClass.new(terrain)
	
	# Connect to GameState debug toggles
	GameState.debug_setting_changed.connect(_on_debug_setting_changed)
	
	# Tell GameState we have terrain
	GameState.current_terrain = terrain
	
	# Set up squad detection
	squad_observer_profile = DetectionClass.make_human_squad_observer()
	
	# Spawn entities
	_spawn_test_squad()
	_spawn_test_hound()
	
	print("BattleMap: %dx%d grid initialized" % [terrain.width, terrain.height])
	print("  Left click - select unit / move unit / select cell")
	print("  Right click - cycle terrain type (paint mode)")
	print("  P - toggle paint mode")
	print("  L - toggle LOS from selected cell")
	print("  1-6 - select terrain type directly")

func _spawn_test_squad() -> void:
	var squad_script = load("res://scripts/core/squad.gd")
	var squad = Node2D.new()
	squad.set_script(squad_script)
	squad.battle_map = self
	
	# Create four soldiers: one leader, three troops
	var soldier_list = [
		SoldierClass.new("Cpl. Singh", "leader"),
		SoldierClass.new("Pte. Williams", "trooper"),
		SoldierClass.new("Pte. Heke", "trooper"),
		SoldierClass.new("Pte. Marsh", "trooper"),
	]
	
	# Issue weapons — everyone gets a Lee-Enfield for now
	var WeaponFactory = load("res://scripts/core/weapon_data.gd").new()
	for s in soldier_list:
		s.assign_weapon(WeaponFactory.lee_enfield())
	
	add_child(squad)
	squad.setup("Scout Team Alpha", Vector2i(5, 10), soldier_list)
	units.append(squad)
	
	# Connect signals
	squad.unit_moved.connect(_on_unit_moved)
	squad.unit_arrived.connect(_on_unit_arrived)
	
	print("Deployed: %s at (%d, %d)" % [squad.squad_name, squad.grid_pos.x, squad.grid_pos.y])
	print(squad.get_soldier_names())
	print("  Click any soldier to select squad. Click terrain to move.")
	
	# Initial fog calculation
	recalculate_fog()

func _spawn_test_hound() -> void:
	var hound_script = load("res://scripts/core/hound.gd")
	var hound = Node2D.new()
	hound.set_script(hound_script)
	hound.battle_map = self
	
	# Patrol route on the far side of the map
	var waypoints: Array[Vector2i] = [
		Vector2i(30, 5),
		Vector2i(35, 15),
		Vector2i(30, 25),
		Vector2i(25, 15),
	]
	
	add_child(hound)
	hound.setup("Hound Alpha", Vector2i(30, 15), waypoints)
	hostiles.append(hound)
	
	# Connect signals
	hound.entity_moved.connect(_on_hostile_moved)
	hound.entity_state_changed.connect(_on_hostile_state_changed)
	
	print("\n⚠ HOSTILE DEPLOYED: %s at (%d, %d)" % [hound.entity_name, hound.grid_pos.x, hound.grid_pos.y])
	print("  Patrol route: %s" % str(waypoints))

func _generate_test_terrain() -> void:
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

func _process(delta: float) -> void:
	# Track mouse position for hover
	var mouse_pos := get_local_mouse_position()
	var new_hover := world_to_grid(mouse_pos)
	
	if new_hover != hovered_cell:
		hovered_cell = new_hover
		cell_hovered.emit(hovered_cell)
		
		# Update path preview if unit selected
		if selected_unit and brush_mode == BrushMode.NONE and terrain.is_valid_cell(hovered_cell):
			if not selected_unit.is_moving:
				preview_path = pathfinder.find_path(selected_unit.grid_pos, hovered_cell)
			else:
				preview_path.clear()
		else:
			preview_path.clear()
		
		queue_redraw()
	
	# Squad detection of hostiles
	_process_squad_detection(delta)
	_update_hostile_visibility()
	
	# Brush drag painting
	if brush_mode != BrushMode.NONE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if terrain.is_valid_cell(hovered_cell):
			if brush_mode == BrushMode.TERRAIN:
				_paint_cell(hovered_cell)
			elif brush_mode == BrushMode.ELEVATION:
				_paint_elevation(hovered_cell, 1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var grid_pos := world_to_grid(get_local_mouse_position())
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if terrain.is_valid_cell(grid_pos):
				if brush_mode == BrushMode.TERRAIN:
					_paint_cell(grid_pos)
				elif brush_mode == BrushMode.ELEVATION:
					_paint_elevation(grid_pos, 1)
				else:
					_handle_left_click(grid_pos)
				queue_redraw()
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if brush_mode == BrushMode.TERRAIN:
				# Cycle terrain type
				current_terrain_index = (current_terrain_index + 1) % terrain_types.size()
				paint_terrain = terrain_types[current_terrain_index]
				print("TERRAIN BRUSH: %s" % paint_terrain)
			elif brush_mode == BrushMode.ELEVATION:
				# Right-click lowers elevation
				if terrain.is_valid_cell(grid_pos):
					_paint_elevation(grid_pos, -1)
					queue_redraw()
			else:
				# Deselect unit
				if selected_unit:
					selected_unit.deselect()
					selected_unit = null
					preview_path.clear()
					clear_los()
					queue_redraw()
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				_cycle_brush_mode()
			KEY_F:
				toggle_fog()
			KEY_L:
				# Toggle LOS from selected cell or unit
				if show_los:
					clear_los()
				elif selected_unit:
					update_los_from(selected_unit.grid_pos)
				elif terrain.is_valid_cell(selected_cell):
					update_los_from(selected_cell)
			KEY_0:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 0)
			KEY_1:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 1)
				else:
					_select_terrain(0)
			KEY_2:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 2)
				else:
					_select_terrain(1)
			KEY_3:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 3)
				else:
					_select_terrain(2)
			KEY_4:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 4)
				else:
					_select_terrain(3)
			KEY_5:
				if brush_mode == BrushMode.ELEVATION and terrain.is_valid_cell(hovered_cell):
					_set_elevation(hovered_cell, 5)
				else:
					_select_terrain(4)
			KEY_6: _select_terrain(5)
			KEY_F2:
				_save_map()
			KEY_F3:
				_load_map()

func _handle_left_click(grid_pos: Vector2i) -> void:
	# Check if clicking on a unit
	var clicked_unit := _get_unit_at(grid_pos)
	
	if clicked_unit:
		# Select / deselect unit
		if selected_unit and selected_unit != clicked_unit:
			selected_unit.deselect()
		selected_unit = clicked_unit
		selected_unit.select()
		update_los_from(selected_unit.grid_pos)
		print("Selected: %s" % selected_unit.get_info())
	elif selected_unit and not selected_unit.is_moving:
		# Move selected unit to clicked cell
		var path = pathfinder.find_path(selected_unit.grid_pos, grid_pos)
		if path.size() > 0:
			var name = selected_unit.squad_name if selected_unit.has_method("contains_point") else selected_unit.unit_name
			print("Moving %s -> (%d,%d), %d steps" % [
				name, grid_pos.x, grid_pos.y, path.size()
			])
			selected_unit.move_to(path)
			preview_path.clear()
		else:
			print("No path to (%d,%d)" % [grid_pos.x, grid_pos.y])
	else:
		# Just select the cell
		selected_cell = grid_pos
		cell_selected.emit(grid_pos)
		_print_cell_info(grid_pos)

func _get_unit_at(grid_pos: Vector2i) -> Node2D:
	"""Check if clicking near any soldier in any squad. Returns the squad."""
	var click_world = grid_to_world(grid_pos)
	for unit in units:
		# Squad-aware: check if click is near any soldier
		if unit.has_method("contains_point"):
			if unit.contains_point(click_world):
				return unit
		# Fallback for old-style units
		elif unit.grid_pos == grid_pos:
			return unit
	return null

func _on_unit_moved(unit: Node2D, _from: Vector2i, to: Vector2i) -> void:
	# Recalculate fog every time any unit moves
	recalculate_fog()
	# Update LOS overlay if this unit is selected
	if unit == selected_unit and show_los:
		update_los_from(to)

func _on_unit_arrived(unit: Node2D) -> void:
	var name = unit.squad_name if unit.has_method("contains_point") else unit.unit_name
	print("%s arrived at (%d,%d)" % [name, unit.grid_pos.x, unit.grid_pos.y])
	_print_cell_info(unit.grid_pos)

func _on_hostile_moved(_entity: Node2D, _from: Vector2i, _to: Vector2i) -> void:
	pass  # Could trigger effects later

func _on_hostile_state_changed(entity: Node2D, _old_state: int, _new_state: int) -> void:
	# Log state changes — useful for debugging AI
	if entity.has_method("get_state_name"):
		pass  # Already printed by hound.gd itself

func _process_squad_detection(delta: float) -> void:
	"""Run detection FROM squads TOWARD hostiles."""
	if units.size() == 0 or hostiles.size() == 0:
		return
	
	for hostile in hostiles:
		var hostile_id = hostile.get_instance_id()
		if not squad_detection_states.has(hostile_id):
			squad_detection_states[hostile_id] = DetectionClass.DetectionState.new()
		
		var det_state = squad_detection_states[hostile_id]
		var best_gain := -1.0
		
		# Each squad tries to detect — use the best result
		for unit in units:
			var distance = unit.grid_pos.distance_to(Vector2(hostile.grid_pos))
			
			# Check LOS from this squad to the hostile
			var has_los = false
			if distance <= squad_observer_profile.sight_range:
				var visible = calculate_los_from(unit.grid_pos, int(squad_observer_profile.sight_range))
				has_los = hostile.grid_pos in visible
			
			var in_concealment = false
			if terrain.is_valid_cell(hostile.grid_pos):
				in_concealment = terrain.get_cell_property(hostile.grid_pos, "concealment")
			
			var hostile_target_profile = hostile.target_profile if hostile.target_profile else DetectionClass.make_hound_target()
			
			var gain = DetectionClass.calculate_detection_tick(
				unit.grid_pos,
				squad_observer_profile,
				hostile.grid_pos,
				hostile_target_profile,
				hostile.is_moving,
				false,  # hostiles don't fire (yet)
				has_los,
				in_concealment,
				distance,
				delta
			)
			best_gain = maxf(best_gain, gain)
		
		det_state.detection_level = clampf(det_state.detection_level + best_gain, 0.0, 1.0)
		
		if det_state.detection_level > 0.01:
			det_state.last_known_pos = hostile.grid_pos
		
		# Update display info
		if det_state.detection_level >= DetectionClass.THRESHOLD_SUSPECTED:
			detected_hostile_positions[hostile_id] = {
				"pos": det_state.last_known_pos,
				"level": det_state.detection_level,
				"label": det_state.get_awareness_label(),
				"hostile": hostile,
			}
		else:
			detected_hostile_positions.erase(hostile_id)

func _update_hostile_visibility() -> void:
	"""Show/hide hostile nodes based on squad detection level."""
	for hostile in hostiles:
		var hostile_id = hostile.get_instance_id()
		if squad_detection_states.has(hostile_id):
			var det = squad_detection_states[hostile_id]
			# Only show the actual entity when IDENTIFIED or better
			hostile.visible = det.detection_level >= DetectionClass.THRESHOLD_IDENTIFIED
		else:
			hostile.visible = false

func _cycle_brush_mode() -> void:
	"""Cycle: NONE -> TERRAIN -> ELEVATION -> NONE"""
	brush_mode = (brush_mode + 1) % 3
	paint_mode = (brush_mode != BrushMode.NONE)
	
	# Deselect unit when entering any brush mode
	if paint_mode and selected_unit:
		selected_unit.deselect()
		selected_unit = null
		preview_path.clear()
		clear_los()
	
	match brush_mode:
		BrushMode.NONE:
			print("=== BRUSH OFF ===")
		BrushMode.TERRAIN:
			print("=== TERRAIN BRUSH: %s === (1-6 select type, RClick cycle)" % paint_terrain)
		BrushMode.ELEVATION:
			print("=== ELEVATION BRUSH === (LClick raise, RClick lower, 0-5 set directly)")

func _select_terrain(index: int) -> void:
	if index < terrain_types.size():
		current_terrain_index = index
		paint_terrain = terrain_types[index]
		if brush_mode == BrushMode.TERRAIN:
			print("TERRAIN BRUSH: %s" % paint_terrain)
		else:
			print("Selected: %s" % paint_terrain)

func _paint_elevation(pos: Vector2i, delta: int) -> void:
	"""Raise or lower elevation at pos by delta."""
	var current_elev: int = terrain.get_cell_property(pos, "elevation")
	var new_elev := clampi(current_elev + delta, 0, 5)
	if new_elev != current_elev:
		terrain.set_cell_property(pos, "elevation", new_elev)
		queue_redraw()

func _set_elevation(pos: Vector2i, value: int) -> void:
	"""Set elevation at pos to an absolute value."""
	var clamped := clampi(value, 0, 5)
	terrain.set_cell_property(pos, "elevation", clamped)
	queue_redraw()

func _paint_cell(pos: Vector2i) -> void:
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
	
	queue_redraw()

func _print_cell_info(pos: Vector2i) -> void:
	var cell = terrain.get_cell(pos)
	var terrain_type: String = cell.get("terrain_type", "open")
	var elev: int = cell.get("elevation", 1)
	var cover: int = cell.get("cover", 0)
	var move_cost: float = cell.get("movement_cost", 1.0)
	var los_block: bool = cell.get("blocks_los", false)
	
	var cover_names = ["None", "Light", "Heavy"]
	print("Cell (%d, %d): %s | Elev %d | Cover: %s | Move: %.1f | LOS block: %s" % [
		pos.x, pos.y, terrain_type, elev, cover_names[cover], move_cost, los_block
	])

# --- LOS Calculation ---

func calculate_los_from(origin: Vector2i, max_range: int = 15) -> Array[Vector2i]:
	"""Calculate all cells visible from origin within range."""
	var visible: Array[Vector2i] = []
	var checked := {}  # avoid duplicate checks
	
	# Check every cell within range
	for x in range(maxi(0, origin.x - max_range), mini(terrain.width, origin.x + max_range + 1)):
		for y in range(maxi(0, origin.y - max_range), mini(terrain.height, origin.y + max_range + 1)):
			var target := Vector2i(x, y)
			if target == origin:
				visible.append(target)
				continue
			
			# Distance check (circular range)
			var dist := origin.distance_to(Vector2(target))
			if dist > max_range:
				continue
			
			# Elevation advantage extends effective range slightly
			var origin_elev: int = terrain.get_cell_property(origin, "elevation")
			var target_elev: int = terrain.get_cell_property(target, "elevation")
			
			# Trace line and check for blockers
			if _check_los_line(origin, target, origin_elev):
				visible.append(target)
	
	return visible

func _check_los_line(from: Vector2i, to: Vector2i, viewer_elev: int) -> bool:
	"""Check if LOS exists along a line, accounting for elevation."""
	var line := terrain._get_line_cells(from, to)
	
	for i in range(1, line.size() - 1):  # skip origin and target
		var cell_pos := line[i]
		if not terrain.is_valid_cell(cell_pos):
			return false
		
		# Hard LOS blockers (buildings, cliffs)
		if terrain.blocks_line_of_sight(cell_pos):
			# But high ground can see over some things
			var blocker_elev: int = terrain.get_cell_property(cell_pos, "elevation")
			if viewer_elev <= blocker_elev + 1:
				return false
			# Viewer is significantly higher - can see over
		
		# Elevation blocking: terrain higher than viewer blocks LOS
		var cell_elev: int = terrain.get_cell_property(cell_pos, "elevation")
		if cell_elev > viewer_elev + 2:
			return false
	
	return true

func update_los_from(pos: Vector2i) -> void:
	"""Recalculate and display LOS from a position."""
	los_origin = pos
	los_visible_cells = calculate_los_from(pos)
	show_los = true
	queue_redraw()

func clear_los() -> void:
	los_visible_cells.clear()
	los_origin = Vector2i(-1, -1)
	show_los = false
	queue_redraw()

# --- Fog of War ---

func recalculate_fog() -> void:
	"""Recalculate combined visibility from all friendly units."""
	if not fog_enabled:
		return
	fog_visible.clear()
	for unit in units:
		var visible = calculate_los_from(unit.grid_pos, unit.sight_range)
		for cell in visible:
			fog_visible[cell] = true
			fog_explored[cell] = true
	queue_redraw()

func toggle_fog() -> void:
	fog_enabled = not fog_enabled
	if fog_enabled:
		recalculate_fog()
	print("Fog of war: %s" % ("ON" if fog_enabled else "OFF"))
	queue_redraw()

# --- Drawing ---

func _draw() -> void:
	_draw_terrain()
	if show_los:
		_draw_los_overlay()
	if show_grid:
		_draw_grid()
	if show_elevation:
		_draw_elevation_overlay()
	if show_cover:
		_draw_cover_overlay()
	_draw_detection_markers()
	if preview_path.size() > 0:
		_draw_path_preview()
	_draw_hover()
	_draw_selection()

func _draw_terrain() -> void:
	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			var cell = terrain.get_cell(pos)
			var terrain_type: String = cell.get("terrain_type", "open")
			var base_color: Color = TERRAIN_COLORS.get(terrain_type, TERRAIN_COLORS["open"])
			
			# Shade by elevation
			var elev: int = cell.get("elevation", 1)
			var shade := (elev - 1) * ELEVATION_SHADE
			base_color = base_color.lightened(shade) if shade > 0 else base_color.darkened(-shade)
			
			# Fog of war darkening
			if fog_enabled:
				if not fog_explored.has(pos):
					# Never seen - nearly black
					base_color = base_color.darkened(0.85)
				elif not fog_visible.has(pos):
					# Previously seen but not currently visible - dim
					base_color = base_color.darkened(0.5)
				# else: currently visible - full color
			
			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, base_color)

func _draw_los_overlay() -> void:
	if los_origin == Vector2i(-1, -1):
		return
	
	# Build a set for fast lookup
	var visible_set := {}
	for cell in los_visible_cells:
		visible_set[cell] = true
	
	# Draw range circle area
	var max_range := 15
	for x in range(maxi(0, los_origin.x - max_range), mini(terrain.width, los_origin.x + max_range + 1)):
		for y in range(maxi(0, los_origin.y - max_range), mini(terrain.height, los_origin.y + max_range + 1)):
			var pos := Vector2i(x, y)
			var dist := los_origin.distance_to(Vector2(pos))
			if dist > max_range:
				continue
			
			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			
			if visible_set.has(pos):
				# Visible - subtle green tint
				draw_rect(rect, Color(0.2, 0.8, 0.2, 0.12))
			else:
				# Not visible - fogged red
				draw_rect(rect, Color(0.6, 0.1, 0.1, 0.25))
	
	# Highlight the origin cell
	var origin_rect := Rect2(
		Vector2(los_origin.x * CELL_SIZE, los_origin.y * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)
	draw_rect(origin_rect, Color(0.2, 0.8, 1.0, 0.4))

func _draw_detection_markers() -> void:
	"""Draw indicators for detected but not fully visible hostiles."""
	for hostile_id in detected_hostile_positions:
		var info = detected_hostile_positions[hostile_id]
		var pos: Vector2i = info["pos"]
		var level: float = info["level"]
		var label: String = info["label"]
		
		var center = Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5, pos.y * CELL_SIZE + CELL_SIZE * 0.5)
		
		if level < DetectionClass.THRESHOLD_DETECTED:
			# SUSPECTED — vague threat indicator, large fuzzy area
			var pulse = sin(Time.get_ticks_msec() * 0.003) * 0.15 + 0.25
			draw_arc(center, CELL_SIZE * 3, 0, TAU, 24, Color(0.9, 0.3, 0.1, pulse), 2.0)
			# Question mark area
			draw_circle(center, 4.0, Color(0.9, 0.3, 0.1, pulse + 0.1))
		
		elif level < DetectionClass.THRESHOLD_IDENTIFIED:
			# DETECTED — tighter indicator, something is definitely there
			var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.1 + 0.4
			draw_arc(center, CELL_SIZE * 1.5, 0, TAU, 20, Color(0.9, 0.2, 0.05, pulse), 2.5)
			draw_circle(center, 5.0, Color(0.9, 0.2, 0.05, pulse))
		
		elif level < DetectionClass.THRESHOLD_TRACKED:
			# IDENTIFIED — we know what it is, position approximate
			# The hound node is visible at this point, but add a tracking ring
			draw_arc(center, CELL_SIZE * 0.8, 0, TAU, 16, Color(1.0, 0.1, 0.0, 0.5), 2.0)
		
		else:
			# TRACKED — tight ring on exact position
			draw_arc(center, CELL_SIZE * 0.6, 0, TAU, 16, Color(1.0, 0.0, 0.0, 0.7), 2.0)

func _draw_path_preview() -> void:
	# Draw dotted path from unit to mouse hover
	for i in range(preview_path.size()):
		var cell := preview_path[i]
		var center := Vector2(
			cell.x * CELL_SIZE + CELL_SIZE * 0.5,
			cell.y * CELL_SIZE + CELL_SIZE * 0.5
		)
		# Fade from bright to dim along path
		var alpha := lerpf(0.6, 0.2, float(i) / maxf(preview_path.size(), 1))
		draw_circle(center, 4.0, Color(0.3, 0.85, 1.0, alpha))
	
	# Draw connecting lines
	if preview_path.size() > 1:
		var start := grid_to_world(selected_unit.grid_pos) if selected_unit else grid_to_world(preview_path[0])
		for i in range(preview_path.size()):
			var end := grid_to_world(preview_path[i])
			draw_line(start, end, Color(0.3, 0.85, 1.0, 0.15), 1.5)
			start = end
	
	# Path length indicator at the end
	if preview_path.size() > 0:
		var last := preview_path[preview_path.size() - 1]
		var last_center := Vector2(
			last.x * CELL_SIZE + CELL_SIZE * 0.5,
			last.y * CELL_SIZE + CELL_SIZE * 0.5
		)
		# End marker - slightly larger
		draw_circle(last_center, 6.0, Color(0.3, 0.85, 1.0, 0.4))
		draw_arc(last_center, 6.0, 0, TAU, 16, Color(0.3, 0.85, 1.0, 0.6), 1.5)

func _draw_grid() -> void:
	var grid_color := Color(0.0, 0.0, 0.0, 0.15)
	var map_width := terrain.width * CELL_SIZE
	var map_height := terrain.height * CELL_SIZE
	
	# Vertical lines
	for x in range(terrain.width + 1):
		var from := Vector2(x * CELL_SIZE, 0)
		var to := Vector2(x * CELL_SIZE, map_height)
		draw_line(from, to, grid_color, 1.0)
	
	# Horizontal lines
	for y in range(terrain.height + 1):
		var from := Vector2(0, y * CELL_SIZE)
		var to := Vector2(map_width, y * CELL_SIZE)
		draw_line(from, to, grid_color, 1.0)

func _draw_elevation_overlay() -> void:
	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			var elev: int = terrain.get_cell_property(pos, "elevation")
			if elev != 1:  # Only show non-baseline
				var color := TerrainManager.get_elevation_color(elev)
				var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
				draw_rect(rect, color)

func _draw_cover_overlay() -> void:
	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			var cover: int = terrain.get_cell_property(pos, "cover")
			if cover > 0:
				var color := TerrainManager.get_cover_color(cover)
				var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
				draw_rect(rect, color)

func _draw_hover() -> void:
	if terrain.is_valid_cell(hovered_cell):
		var rect := Rect2(
			Vector2(hovered_cell.x * CELL_SIZE, hovered_cell.y * CELL_SIZE),
			Vector2(CELL_SIZE, CELL_SIZE)
		)
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.2))
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.5), false, 2.0)

func _draw_selection() -> void:
	if terrain.is_valid_cell(selected_cell):
		var rect := Rect2(
			Vector2(selected_cell.x * CELL_SIZE, selected_cell.y * CELL_SIZE),
			Vector2(CELL_SIZE, CELL_SIZE)
		)
		draw_rect(rect, Color(1.0, 0.9, 0.3, 0.3))
		draw_rect(rect, Color(1.0, 0.9, 0.3, 0.8), false, 2.0)

# --- Coordinate conversion ---

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_SIZE), int(world_pos.y / CELL_SIZE))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5, grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5)

# --- Save/Load ---

func _save_map() -> void:
	var path := "user://test_map.json"
	var err := terrain.save_to_file(path)
	if err == OK:
		print("Map saved to %s" % path)
	else:
		print("Failed to save map: %s" % error_string(err))

func _load_map() -> void:
	var path := "user://test_map.json"
	var err := terrain.load_from_file(path)
	if err == OK:
		print("Map loaded from %s" % path)
		queue_redraw()
	else:
		print("No saved map found (or load failed)")

func _on_debug_setting_changed(setting: String, value: bool) -> void:
	match setting:
		"grid": show_grid = value
		"elevation": show_elevation = value
		"cover": show_cover = value
	queue_redraw()
