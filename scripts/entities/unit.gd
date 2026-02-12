# unit.gd
# A single tactical unit on the battle map
# The first brave soul to walk this grid
extends Node2D

# Grid position
var grid_pos := Vector2i(5, 5)
var target_pos := Vector2i(5, 5)

# Movement
var move_path: Array[Vector2i] = []
var is_moving := false
var move_speed := 100.0  # pixels per second
var move_progress := 0.0
var path_index := 0

# Unit properties
var unit_name := "Scout Team Alpha"
var sight_range := 12
var selected := false

# Visual
var unit_color := Color(0.85, 0.75, 0.45)  # Khaki - proper military
var unit_size := 10.0  # radius in pixels

# Reference to battle map (set by parent)
var battle_map: Node2D = null

signal unit_selected(unit: Node2D)
signal unit_moved(unit: Node2D, from: Vector2i, to: Vector2i)
signal unit_arrived(unit: Node2D)

func _ready() -> void:
	# Snap to grid position
	_update_visual_position()

func _process(delta: float) -> void:
	if is_moving and move_path.size() > 0:
		_process_movement(delta)

func _process_movement(delta: float) -> void:
	if path_index >= move_path.size():
		_finish_movement()
		return
	
	var next_cell := move_path[path_index]
	var target_world := _grid_to_world(next_cell)
	var current_world := position
	
	var direction := (target_world - current_world)
	var distance := direction.length()
	
	# Get movement cost for this cell (slower through rough terrain)
	var move_cost: float = 1.0
	if battle_map:
		move_cost = battle_map.terrain.get_cell_property(next_cell, "movement_cost")
		move_cost = maxf(move_cost, 0.1)  # don't divide by zero
	
	var effective_speed := move_speed / move_cost
	var step := effective_speed * delta
	
	if step >= distance:
		# Arrived at this cell
		var old_pos := grid_pos
		grid_pos = next_cell
		position = target_world
		path_index += 1
		unit_moved.emit(self, old_pos, grid_pos)
		
		if path_index >= move_path.size():
			_finish_movement()
	else:
		# Still moving
		position += direction.normalized() * step

func _finish_movement() -> void:
	is_moving = false
	move_path.clear()
	path_index = 0
	_update_visual_position()
	unit_arrived.emit(self)
	
	# Update LOS from new position
	if selected and battle_map:
		battle_map.update_los_from(grid_pos)

func move_to(path: Array[Vector2i]) -> void:
	"""Start moving along a path."""
	if path.size() == 0:
		return
	move_path = path
	path_index = 0
	is_moving = true
	target_pos = path[path.size() - 1]

func select() -> void:
	selected = true
	unit_selected.emit(self)
	queue_redraw()

func deselect() -> void:
	selected = false
	queue_redraw()

func _update_visual_position() -> void:
	position = _grid_to_world(grid_pos)

func _grid_to_world(pos: Vector2i) -> Vector2:
	if battle_map:
		return battle_map.grid_to_world(pos)
	# Fallback
	return Vector2(pos.x * 32 + 16, pos.y * 32 + 16)

func _draw() -> void:
	# Unit body - filled circle
	draw_circle(Vector2.ZERO, unit_size, unit_color)
	
	# Dark outline
	draw_arc(Vector2.ZERO, unit_size, 0, TAU, 32, Color(0.2, 0.2, 0.15), 2.0)
	
	# Selection indicator
	if selected:
		draw_arc(Vector2.ZERO, unit_size + 4, 0, TAU, 32, Color(0.2, 0.8, 1.0, 0.8), 2.0)
		draw_arc(Vector2.ZERO, unit_size + 6, 0, TAU, 32, Color(0.2, 0.8, 1.0, 0.3), 1.0)
	
	# Direction indicator (small notch showing facing)
	# For now just a dot at top
	draw_circle(Vector2(0, -unit_size * 0.5), 2.0, Color(0.2, 0.2, 0.15))
	
	# Draw path preview if moving
	if move_path.size() > 0 and is_moving:
		for i in range(path_index, move_path.size()):
			var cell_world := _grid_to_world(move_path[i]) - position  # relative to unit
			draw_circle(cell_world, 3.0, Color(0.2, 0.8, 1.0, 0.4))

func get_info() -> String:
	return "%s @ (%d,%d)" % [unit_name, grid_pos.x, grid_pos.y]
