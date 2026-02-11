# terrain_overlay.gd
# Renders terrain cells with elevation shading and fog of war.
# Child Node2D of BattleMap — drawn below entities and debug overlays.
extends Node2D

# Reference to the parent battle_map for data access
var battle_manager: Node2D = null

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

func _draw() -> void:
	if not battle_manager or not battle_manager.terrain:
		return

	var terrain: TerrainData = battle_manager.terrain
	var cell_size: int = battle_manager.CELL_SIZE
	var fog_enabled: bool = battle_manager.fog_enabled
	var fog_visible: Dictionary = battle_manager.fog_visible
	var fog_explored: Dictionary = battle_manager.fog_explored

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

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			draw_rect(rect, base_color)
