# battle_map.gd
# Renders the terrain grid and handles mouse interaction
# This is the visual heart of the tactical layer
extends Node2D

const PathfinderClass = preload("res://scripts/core/pathfinder.gd")
const SoldierClass = preload("res://scripts/core/soldier.gd")
const HoundClass = preload("res://scripts/core/hound.gd")
const DetectionClass = preload("res://scripts/core/detection.gd")
const TerrainEditorClass = preload("res://scripts/tools/terrain_editor.gd")

# Grid settings
const CELL_SIZE := 32  # pixels per cell
const DEFAULT_WIDTH := 40
const DEFAULT_HEIGHT := 30

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

# Terrain editor (extracted)
var terrain_editor = null

# Child node structure (scene tree IS the render manager)
var terrain_overlay: Node2D = null
var entities_node: Node2D = null
var debug_overlay: Node2D = null

signal cell_selected(pos: Vector2i)
signal cell_hovered(pos: Vector2i)

func _ready() -> void:
	# Create default terrain
	terrain = TerrainData.new(DEFAULT_WIDTH, DEFAULT_HEIGHT)

	# Create terrain editor and generate test map
	terrain_editor = TerrainEditorClass.new(terrain)
	terrain_editor.terrain_changed.connect(_on_terrain_changed)
	terrain_editor.generate_test_terrain()

	# Build child node structure for z-ordered rendering
	# Order matters: terrain below entities below debug overlays
	var TerrainOverlayScript = load("res://scripts/core/terrain_overlay.gd")
	terrain_overlay = Node2D.new()
	terrain_overlay.set_script(TerrainOverlayScript)
	terrain_overlay.name = "TerrainOverlay"
	terrain_overlay.battle_manager = self
	add_child(terrain_overlay)

	entities_node = Node2D.new()
	entities_node.name = "Entities"
	add_child(entities_node)

	var DebugOverlayScript = load("res://scripts/core/debug_overlay.gd")
	debug_overlay = Node2D.new()
	debug_overlay.set_script(DebugOverlayScript)
	debug_overlay.name = "DebugOverlay"
	debug_overlay.battle_manager = self
	add_child(debug_overlay)

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

	entities_node.add_child(squad)
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

	entities_node.add_child(hound)
	hound.setup("Hound Alpha", Vector2i(30, 15), waypoints)
	hostiles.append(hound)

	# Connect signals
	hound.entity_moved.connect(_on_hostile_moved)
	hound.entity_state_changed.connect(_on_hostile_state_changed)

	print("\n⚠ HOSTILE DEPLOYED: %s at (%d, %d)" % [hound.entity_name, hound.grid_pos.x, hound.grid_pos.y])
	print("  Patrol route: %s" % str(waypoints))

func _process(delta: float) -> void:
	# Track mouse position for hover
	var mouse_pos := get_local_mouse_position()
	var new_hover := world_to_grid(mouse_pos)

	if new_hover != hovered_cell:
		hovered_cell = new_hover
		cell_hovered.emit(hovered_cell)

		# Update path preview if unit selected
		if selected_unit and terrain_editor.brush_mode == TerrainEditorClass.BrushMode.NONE and terrain.is_valid_cell(hovered_cell):
			if not selected_unit.is_moving:
				preview_path = pathfinder.find_path(selected_unit.grid_pos, hovered_cell)
			else:
				preview_path.clear()
		else:
			preview_path.clear()

		request_redraw()

	# Squad detection of hostiles
	_process_squad_detection(delta)
	_update_hostile_visibility()

	# Brush drag painting
	if terrain_editor.brush_mode != TerrainEditorClass.BrushMode.NONE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if terrain.is_valid_cell(hovered_cell):
			terrain_editor.handle_drag(hovered_cell)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var grid_pos := world_to_grid(get_local_mouse_position())

		if event.button_index == MOUSE_BUTTON_LEFT:
			if terrain.is_valid_cell(grid_pos):
				# Let terrain editor try first
				if not terrain_editor.handle_left_click(grid_pos):
					_handle_left_click(grid_pos)
				request_redraw()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not terrain_editor.handle_right_click(grid_pos):
				# Deselect unit
				if selected_unit:
					selected_unit.deselect()
					selected_unit = null
					preview_path.clear()
					clear_los()
					request_redraw()

	if event is InputEventKey and event.pressed:
		# Let terrain editor handle keys first
		if terrain_editor.handle_key(event.keycode, hovered_cell):
			# Editor consumed the key — but check if brush mode changed
			# and we need to deselect unit
			if terrain_editor.paint_mode and selected_unit:
				selected_unit.deselect()
				selected_unit = null
				preview_path.clear()
				clear_los()
			request_redraw()
			return

		# Keys the battle map handles directly
		match event.keycode:
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

func _on_terrain_changed() -> void:
	request_redraw(true)

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

		# Update display info using hysteresis-aware awareness label
		var awareness := det_state.get_awareness_label()
		if awareness != "UNAWARE":
			detected_hostile_positions[hostile_id] = {
				"pos": det_state.last_known_pos,
				"level": det_state.detection_level,
				"label": awareness,
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
			var awareness := det.get_awareness_label()
			# Only show the actual entity when IDENTIFIED or better
			hostile.visible = awareness == "IDENTIFIED" or awareness == "TRACKED"
		else:
			hostile.visible = false

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
	request_redraw()

func clear_los() -> void:
	los_visible_cells.clear()
	los_origin = Vector2i(-1, -1)
	show_los = false
	request_redraw()

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
	request_redraw(true)

func toggle_fog() -> void:
	fog_enabled = not fog_enabled
	if fog_enabled:
		recalculate_fog()
	print("Fog of war: %s" % ("ON" if fog_enabled else "OFF"))
	request_redraw(true)

# --- Redraw helpers ---
# All rendering is handled by child nodes (TerrainOverlay, DebugOverlay).
# battle_map.gd has ZERO _draw() code.

func request_redraw(terrain_changed: bool = false) -> void:
	"""Trigger redraws on the appropriate overlay nodes."""
	debug_overlay.queue_redraw()
	if terrain_changed:
		terrain_overlay.queue_redraw()

# --- Coordinate conversion ---

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_SIZE), int(world_pos.y / CELL_SIZE))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5, grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5)

func _on_debug_setting_changed(setting: String, value: bool) -> void:
	match setting:
		"grid": show_grid = value
		"elevation": show_elevation = value
		"cover": show_cover = value
	request_redraw()
