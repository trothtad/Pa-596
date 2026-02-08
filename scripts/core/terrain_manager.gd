# terrain_manager.gd
# Manages synchronization between TerrainData and visual TileMap
# Autoloaded - access via TerrainManager anywhere
extends Node

# Reference to the active battle map TileMap (set by BattleMap scene)
var battle_map: TileMap = null

# Terrain visualization colors (for debug overlays)
const ELEVATION_COLORS = [
	Color(0.2, 0.2, 0.5, 0.5),  # 0: Low/water - blue
	Color(0.3, 0.5, 0.3, 0.3),  # 1: Ground - green (subtle)
	Color(0.5, 0.5, 0.3, 0.5),  # 2: Raised - tan
	Color(0.6, 0.5, 0.4, 0.5),  # 3: Hill - brown
	Color(0.7, 0.6, 0.5, 0.5),  # 4: High - light brown
	Color(0.8, 0.8, 0.8, 0.5),  # 5: Peak - grey
]

const COVER_COLORS = [
	Color(0.0, 0.0, 0.0, 0.0),  # None - transparent
	Color(1.0, 1.0, 0.0, 0.3),  # Light - yellow
	Color(0.0, 1.0, 0.0, 0.4),  # Heavy - green
]

signal cell_updated(pos: Vector2i)
signal map_registered(tilemap: TileMap)

func register_battle_map(tilemap: TileMap) -> void:
	"""Register the active TileMap for terrain sync."""
	battle_map = tilemap
	map_registered.emit(tilemap)
	print("TerrainManager: BattleMap registered")

func unregister_battle_map() -> void:
	"""Unregister the active TileMap."""
	battle_map = null

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world position to grid coordinates."""
	if battle_map:
		return battle_map.local_to_map(battle_map.to_local(world_pos))
	return Vector2i.ZERO

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid coordinates to world position (center of cell)."""
	if battle_map:
		return battle_map.to_global(battle_map.map_to_local(grid_pos))
	return Vector2.ZERO

func get_cell_size() -> Vector2i:
	"""Get the size of a single grid cell."""
	if battle_map:
		return battle_map.tile_set.tile_size if battle_map.tile_set else Vector2i(32, 32)
	return Vector2i(32, 32)

func get_elevation_color(elevation: int) -> Color:
	"""Get the debug color for an elevation value."""
	elevation = clampi(elevation, 0, 5)
	return ELEVATION_COLORS[elevation]

func get_cover_color(cover: int) -> Color:
	"""Get the debug color for a cover value."""
	cover = clampi(cover, 0, 2)
	return COVER_COLORS[cover]
