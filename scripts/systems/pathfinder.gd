# pathfinder.gd
# A* pathfinding over TerrainData
# Respects movement costs, impassable terrain, and water
extends RefCounted

var terrain: TerrainData

# Neighbor offsets (8-directional)
const NEIGHBORS := [
	Vector2i(0, -1),   # N
	Vector2i(1, -1),   # NE
	Vector2i(1, 0),    # E
	Vector2i(1, 1),    # SE
	Vector2i(0, 1),    # S
	Vector2i(-1, 1),   # SW
	Vector2i(-1, 0),   # W
	Vector2i(-1, -1),  # NW
]

const DIAGONAL_COST := 1.414

func _init(terrain_data: TerrainData) -> void:
	terrain = terrain_data

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	"""Find shortest path from start to end using A*."""
	if not terrain.is_valid_cell(from) or not terrain.is_valid_cell(to):
		return []
	
	if terrain.get_cell_property(to, "is_impassable"):
		return []
	
	# A* setup
	var open_set := {}  # pos -> true
	var came_from := {} # pos -> pos
	var g_score := {}   # pos -> float (cost from start)
	var f_score := {}   # pos -> float (estimated total cost)
	
	open_set[from] = true
	g_score[from] = 0.0
	f_score[from] = _heuristic(from, to)
	
	var max_iterations := terrain.width * terrain.height  # safety valve
	var iterations := 0
	
	while open_set.size() > 0 and iterations < max_iterations:
		iterations += 1
		
		# Find node in open set with lowest f_score
		var current = _get_lowest_f(open_set, f_score)
		
		if current == to:
			return _reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		# Check all neighbors
		for offset in NEIGHBORS:
			var neighbor = current + offset
			
			if not terrain.is_valid_cell(neighbor):
				continue
			
			if terrain.get_cell_property(neighbor, "is_impassable"):
				continue
			
			# Calculate movement cost
			var move_cost: float = terrain.get_cell_property(neighbor, "movement_cost")
			var is_diagonal = (offset.x != 0 and offset.y != 0)
			var step_cost = move_cost * (DIAGONAL_COST if is_diagonal else 1.0)
			
			# Water penalty (passable but slow unless specifically handled)
			if terrain.get_cell_property(neighbor, "is_water"):
				step_cost *= 2.0
			
			# Elevation change cost
			var current_elev: int = terrain.get_cell_property(current, "elevation")
			var neighbor_elev: int = terrain.get_cell_property(neighbor, "elevation")
			var elev_diff = absi(neighbor_elev - current_elev)
			if elev_diff > 0:
				step_cost += elev_diff * 0.5
			
			var tentative_g = g_score.get(current, INF) + step_cost
			
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, to)
				
				if not open_set.has(neighbor):
					open_set[neighbor] = true
	
	# No path found
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	"""Chebyshev distance - good for 8-directional movement."""
	var dx := absf(a.x - b.x)
	var dy := absf(a.y - b.y)
	return maxf(dx, dy) + (DIAGONAL_COST - 1.0) * minf(dx, dy)

func _get_lowest_f(open_set: Dictionary, f_score: Dictionary) -> Vector2i:
	"""Get the node with lowest f_score from open set."""
	var best_pos := Vector2i.ZERO
	var best_score := INF
	
	for pos in open_set:
		var score: float = f_score.get(pos, INF)
		if score < best_score:
			best_score = score
			best_pos = pos
	
	return best_pos

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	"""Trace back the path from end to start."""
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	# Remove the starting position (unit is already there)
	if path.size() > 0:
		path.remove_at(0)
	return path
