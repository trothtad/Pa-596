# main.gd
# Main scene controller for Pā 596
# Handles camera, mode switching, and scene management
extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var mode_label: Label = $UI/ModeLabel
@onready var info_label: Label = $UI/InfoLabel
@onready var battle_map: Node2D = $BattleMap

# Camera settings
const CAMERA_SPEED = 500.0
const ZOOM_SPEED = 0.1
const MIN_ZOOM = 0.25
const MAX_ZOOM = 3.0

func _ready() -> void:
	GameState.mode_changed.connect(_on_mode_changed)
	battle_map.cell_hovered.connect(_on_cell_hovered)
	battle_map.cell_selected.connect(_on_cell_selected)
	
	# Start camera roughly centered on the map
	var map_center := Vector2(
		battle_map.terrain.width * battle_map.CELL_SIZE * 0.5,
		battle_map.terrain.height * battle_map.CELL_SIZE * 0.5
	)
	camera.position = map_center
	camera.zoom = Vector2(1.5, 1.5)
	
	print("=================================")
	print("  Pā 596 - Prototype Build")
	print("  Every decision costs blood")
	print("  and morale.")
	print("=================================")
	print("")
	print("Controls:")
	print("  WASD    - Pan camera")
	print("  Scroll  - Zoom")
	print("  G       - Toggle grid")
	print("  Click   - Select cell")
	print("  P       - Toggle paint mode")
	print("  RClick  - Cycle terrain type")
	print("  1-6     - Select terrain directly")
	print("  F2/F3   - Save/Load map")
	print("")

func _process(delta: float) -> void:
	_handle_camera_input(delta)

func _input(event: InputEvent) -> void:
	# Zoom handling
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-ZOOM_SPEED)
	
	# Mode switching and debug toggles
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				GameState.set_mode(GameState.Mode.EDITOR)
			KEY_B:
				GameState.set_mode(GameState.Mode.BATTLE)
			KEY_ESCAPE:
				GameState.set_mode(GameState.Mode.MENU)
			KEY_G:
				GameState.toggle_debug("grid")
			KEY_V:
				GameState.toggle_debug("elevation")
			KEY_C:
				GameState.toggle_debug("cover")

func _handle_camera_input(delta: float) -> void:
	var move_dir := Vector2.ZERO
	
	if Input.is_action_pressed("camera_pan_up"):
		move_dir.y -= 1
	if Input.is_action_pressed("camera_pan_down"):
		move_dir.y += 1
	if Input.is_action_pressed("camera_pan_left"):
		move_dir.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		move_dir.x += 1
	
	if move_dir != Vector2.ZERO:
		var adjusted_speed := CAMERA_SPEED / camera.zoom.x
		camera.position += move_dir.normalized() * adjusted_speed * delta

func _zoom_camera(amount: float) -> void:
	var new_zoom := camera.zoom.x + amount
	new_zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(new_zoom, new_zoom)

func _on_mode_changed(new_mode: GameState.Mode) -> void:
	var mode_names := ["MENU", "BATTLE", "EDITOR", "CAMPAIGN"]
	mode_label.text = "Mode: " + mode_names[new_mode]

func _on_cell_hovered(pos: Vector2i) -> void:
	if not battle_map.terrain.is_valid_cell(pos):
		info_label.text = ""
		return
	
	var cell = battle_map.terrain.get_cell(pos)
	var terrain_type: String = cell.get("terrain_type", "open")
	var elev: int = cell.get("elevation", 1)
	var cover: int = cell.get("cover", 0)
	var move_cost: float = cell.get("movement_cost", 1.0)
	var cover_names = ["None", "Light", "Heavy"]
	
	var paint_info := ""
	if battle_map.brush_mode == battle_map.BrushMode.TERRAIN:
		paint_info = "  |  TERRAIN BRUSH: %s" % battle_map.paint_terrain
	elif battle_map.brush_mode == battle_map.BrushMode.ELEVATION:
		paint_info = "  |  ELEVATION BRUSH (L:raise R:lower)"
	
	info_label.text = "(%d, %d) %s  Elev:%d  Cover:%s  Move:%.1f%s" % [
		pos.x, pos.y, terrain_type.to_upper(), elev, cover_names[cover], move_cost, paint_info
	]

func _on_cell_selected(_pos: Vector2i) -> void:
	pass  # Could open detail panel later
