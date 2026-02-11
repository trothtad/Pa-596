class_name TerrainQuery
## Terrain query utilities — pathfinding, LOS, cover queries.
## Will absorb logic from pathfinder.gd and battle_map.gd's LOS methods
## during Phase 2 extraction.
##
## Planned API:
## static func find_path(terrain: TerrainData, from: Vector2i, to: Vector2i) -> Array[Vector2i]
## static func calculate_los(terrain: TerrainData, from: Vector2i, max_range: int) -> Array[Vector2i]
## static func check_los_between(terrain: TerrainData, from: Vector2i, to: Vector2i) -> bool
## static func get_cover_value(terrain: TerrainData, pos: Vector2i) -> int
## static func get_concealment(terrain: TerrainData, pos: Vector2i) -> float
## static func get_movement_cost(terrain: TerrainData, pos: Vector2i) -> float
