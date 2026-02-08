# game_state.gd
# Global game state singleton for Pā 596
# Autoloaded - access via GameState anywhere
extends Node

# Current game mode
enum Mode { MENU, BATTLE, EDITOR, CAMPAIGN }
var current_mode: Mode = Mode.MENU

# Current battle map data
var current_terrain: TerrainData = null
var current_map_path: String = ""

# Debug settings
var debug_show_grid: bool = true
var debug_show_los: bool = false
var debug_show_cover: bool = false
var debug_show_elevation: bool = false

# Signals
signal mode_changed(new_mode: Mode)
signal terrain_loaded(terrain: TerrainData)
signal debug_setting_changed(setting: String, value: bool)

func _ready() -> void:
	print("Pā 596 - GameState initialized")
	print("Every decision costs blood and morale.")

func set_mode(new_mode: Mode) -> void:
	current_mode = new_mode
	mode_changed.emit(new_mode)

func load_terrain(path: String) -> Error:
	"""Load terrain data from file."""
	current_terrain = TerrainData.new()
	var error = current_terrain.load_from_file(path)
	if error == OK:
		current_map_path = path
		terrain_loaded.emit(current_terrain)
	return error

func new_terrain(width: int = 50, height: int = 50) -> void:
	"""Create new blank terrain."""
	current_terrain = TerrainData.new(width, height)
	current_map_path = ""
	terrain_loaded.emit(current_terrain)

func toggle_debug(setting: String) -> void:
	"""Toggle a debug visualization setting."""
	match setting:
		"grid":
			debug_show_grid = not debug_show_grid
			debug_setting_changed.emit("grid", debug_show_grid)
		"los":
			debug_show_los = not debug_show_los
			debug_setting_changed.emit("los", debug_show_los)
		"cover":
			debug_show_cover = not debug_show_cover
			debug_setting_changed.emit("cover", debug_show_cover)
		"elevation":
			debug_show_elevation = not debug_show_elevation
			debug_setting_changed.emit("elevation", debug_show_elevation)
