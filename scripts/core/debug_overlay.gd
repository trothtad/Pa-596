# debug_overlay.gd
# Renders debug/UI overlays: grid, LOS, elevation, cover, detection markers,
# path preview, hover highlight, selection highlight.
# Child Node2D of BattleMap — drawn above entities.
extends Node2D

const DetectionClass = preload("res://scripts/core/detection.gd")

# Reference to the parent battle_map for data access
var battle_manager: Node2D = null

func _draw() -> void:
	if not battle_manager or not battle_manager.terrain:
		return

	if battle_manager.show_los:
		_draw_los_overlay()
	if battle_manager.show_grid:
		_draw_grid()
	if battle_manager.show_elevation:
		_draw_elevation_overlay()
	if battle_manager.show_cover:
		_draw_cover_overlay()
	_draw_detection_markers()
	if battle_manager.preview_path.size() > 0:
		_draw_path_preview()
	_draw_hover()
	_draw_selection()

func _draw_los_overlay() -> void:
	var terrain: TerrainData = battle_manager.terrain
	var cell_size: int = battle_manager.CELL_SIZE
	var los_origin: Vector2i = battle_manager.los_origin
	var los_visible_cells: Array[Vector2i] = battle_manager.los_visible_cells

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

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))

			if visible_set.has(pos):
				# Visible - subtle green tint
				draw_rect(rect, Color(0.2, 0.8, 0.2, 0.12))
			else:
				# Not visible - fogged red
				draw_rect(rect, Color(0.6, 0.1, 0.1, 0.25))

	# Highlight the origin cell
	var origin_rect := Rect2(
		Vector2(los_origin.x * cell_size, los_origin.y * cell_size),
		Vector2(cell_size, cell_size)
	)
	draw_rect(origin_rect, Color(0.2, 0.8, 1.0, 0.4))

func _draw_detection_markers() -> void:
	"""Draw indicators for detected but not fully visible hostiles."""
	var cell_size: int = battle_manager.CELL_SIZE

	for hostile_id in battle_manager.detected_hostile_positions:
		var info = battle_manager.detected_hostile_positions[hostile_id]
		var pos: Vector2i = info["pos"]
		var level: float = info["level"]
		var _label: String = info["label"]

		var center = Vector2(pos.x * cell_size + cell_size * 0.5, pos.y * cell_size + cell_size * 0.5)

		if level < DetectionClass.THRESHOLD_DETECTED:
			# SUSPECTED — vague threat indicator, large fuzzy area
			var pulse = sin(Time.get_ticks_msec() * 0.003) * 0.15 + 0.25
			draw_arc(center, cell_size * 3, 0, TAU, 24, Color(0.9, 0.3, 0.1, pulse), 2.0)
			# Question mark area
			draw_circle(center, 4.0, Color(0.9, 0.3, 0.1, pulse + 0.1))

		elif level < DetectionClass.THRESHOLD_IDENTIFIED:
			# DETECTED — tighter indicator, something is definitely there
			var pulse = sin(Time.get_ticks_msec() * 0.005) * 0.1 + 0.4
			draw_arc(center, cell_size * 1.5, 0, TAU, 20, Color(0.9, 0.2, 0.05, pulse), 2.5)
			draw_circle(center, 5.0, Color(0.9, 0.2, 0.05, pulse))

		elif level < DetectionClass.THRESHOLD_TRACKED:
			# IDENTIFIED — we know what it is, position approximate
			# The hound node is visible at this point, but add a tracking ring
			draw_arc(center, cell_size * 0.8, 0, TAU, 16, Color(1.0, 0.1, 0.0, 0.5), 2.0)

		else:
			# TRACKED — tight ring on exact position
			draw_arc(center, cell_size * 0.6, 0, TAU, 16, Color(1.0, 0.0, 0.0, 0.7), 2.0)

func _draw_path_preview() -> void:
	var cell_size: int = battle_manager.CELL_SIZE
	var preview_path: Array[Vector2i] = battle_manager.preview_path

	# Draw dotted path from unit to mouse hover
	for i in range(preview_path.size()):
		var cell := preview_path[i]
		var center := Vector2(
			cell.x * cell_size + cell_size * 0.5,
			cell.y * cell_size + cell_size * 0.5
		)
		# Fade from bright to dim along path
		var alpha := lerpf(0.6, 0.2, float(i) / maxf(preview_path.size(), 1))
		draw_circle(center, 4.0, Color(0.3, 0.85, 1.0, alpha))

	# Draw connecting lines
	if preview_path.size() > 1:
		var start: Vector2 = battle_manager.grid_to_world(battle_manager.selected_unit.grid_pos) if battle_manager.selected_unit else battle_manager.grid_to_world(preview_path[0])
		for i in range(preview_path.size()):
			var end: Vector2 = battle_manager.grid_to_world(preview_path[i])
			draw_line(start, end, Color(0.3, 0.85, 1.0, 0.15), 1.5)
			start = end

	# Path length indicator at the end
	if preview_path.size() > 0:
		var last := preview_path[preview_path.size() - 1]
		var last_center := Vector2(
			last.x * cell_size + cell_size * 0.5,
			last.y * cell_size + cell_size * 0.5
		)
		# End marker - slightly larger
		draw_circle(last_center, 6.0, Color(0.3, 0.85, 1.0, 0.4))
		draw_arc(last_center, 6.0, 0, TAU, 16, Color(0.3, 0.85, 1.0, 0.6), 1.5)

func _draw_grid() -> void:
	var terrain: TerrainData = battle_manager.terrain
	var cell_size: int = battle_manager.CELL_SIZE
	var grid_color := Color(0.0, 0.0, 0.0, 0.15)
	var map_width := terrain.width * cell_size
	var map_height := terrain.height * cell_size

	# Vertical lines
	for x in range(terrain.width + 1):
		var from := Vector2(x * cell_size, 0)
		var to := Vector2(x * cell_size, map_height)
		draw_line(from, to, grid_color, 1.0)

	# Horizontal lines
	for y in range(terrain.height + 1):
		var from := Vector2(0, y * cell_size)
		var to := Vector2(map_width, y * cell_size)
		draw_line(from, to, grid_color, 1.0)

func _draw_elevation_overlay() -> void:
	var terrain: TerrainData = battle_manager.terrain
	var cell_size: int = battle_manager.CELL_SIZE

	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			var elev: int = terrain.get_cell_property(pos, "elevation")
			if elev != 1:  # Only show non-baseline
				var color := TerrainManager.get_elevation_color(elev)
				var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
				draw_rect(rect, color)

func _draw_cover_overlay() -> void:
	var terrain: TerrainData = battle_manager.terrain
	var cell_size: int = battle_manager.CELL_SIZE

	for x in range(terrain.width):
		for y in range(terrain.height):
			var pos := Vector2i(x, y)
			var cover: int = terrain.get_cell_property(pos, "cover")
			if cover > 0:
				var color := TerrainManager.get_cover_color(cover)
				var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
				draw_rect(rect, color)

func _draw_hover() -> void:
	var cell_size: int = battle_manager.CELL_SIZE
	var hovered_cell: Vector2i = battle_manager.hovered_cell

	if battle_manager.terrain.is_valid_cell(hovered_cell):
		var rect := Rect2(
			Vector2(hovered_cell.x * cell_size, hovered_cell.y * cell_size),
			Vector2(cell_size, cell_size)
		)
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.2))
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.5), false, 2.0)

func _draw_selection() -> void:
	var cell_size: int = battle_manager.CELL_SIZE
	var selected_cell: Vector2i = battle_manager.selected_cell

	if battle_manager.terrain.is_valid_cell(selected_cell):
		var rect := Rect2(
			Vector2(selected_cell.x * cell_size, selected_cell.y * cell_size),
			Vector2(cell_size, cell_size)
		)
		draw_rect(rect, Color(1.0, 0.9, 0.3, 0.3))
		draw_rect(rect, Color(1.0, 0.9, 0.3, 0.8), false, 2.0)
