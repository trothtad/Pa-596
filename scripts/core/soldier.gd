# soldier.gd
# An individual soldier within a squad
# Lightweight data + position + simple steering
extends RefCounted

# Identity
var soldier_name := "Unknown"
var role := "trooper"  # "leader" or "trooper"

# World position (float, sub-grid)
var world_pos := Vector2.ZERO
var desired_pos := Vector2.ZERO  # where they want to be (formation offset)

# Movement
var move_speed := 80.0  # pixels per second, base
var is_moving := false

# State
enum State { IDLE, MOVING, PRONE, PINNED, WOUNDED, DEAD, PANICKED }
var state: int = State.IDLE

# Properties
var morale_modifier := 0.0  # personal bravery offset (-10 to +10)
var fatigue := 0.0
var wound_state := 0  # 0=fine, 1=light, 2=serious, 3=critical

# Combat
var weapon = null               # WeaponData instance, assigned at spawn
var accuracy := 65             # base accuracy (d100 roll-under)
var ammo_current := 10         # current ammo (set from weapon on assign)
var fire_timer := 0.0          # seconds until next shot (counts down)
var suppression := 0.0         # 0.0 = calm, 1.0 = fully suppressed
var composure := 0             # 0=steady, 1=shaken, 2=panicked, 3=broken

# Formation offset (set once at spawn, persistent)
var formation_offset := Vector2.ZERO

# Visual
var soldier_color := Color(0.85, 0.75, 0.45)  # khaki default
var dot_size := 4.0

func assign_weapon(w) -> void:  # w is a WeaponData instance
	weapon = w
	ammo_current = w.ammo_capacity
	fire_timer = randf_range(0.0, w.get_fire_interval())  # stagger initial shots

func _init(p_name: String = "Unknown", p_role: String = "trooper") -> void:
	soldier_name = p_name
	role = p_role
	if role == "leader":
		soldier_color = Color(0.9, 0.85, 0.5)  # slightly brighter
		dot_size = 5.0
	# Each soldier gets a persistent random formation jitter
	formation_offset = Vector2(randf_range(-8, 8), randf_range(-8, 8))

func steer_toward(target: Vector2, delta: float, terrain: TerrainData = null, cell_size: int = 32) -> void:
	"""Steer toward desired position, avoiding bad terrain."""
	if state == State.DEAD or state == State.PINNED:
		return
	
	desired_pos = target
	var direction = desired_pos - world_pos
	var distance = direction.length()
	
	if distance < 2.0:
		is_moving = false
		return
	
	is_moving = true
	var speed = move_speed
	
	if terrain:
		# Check what cell we're currently in
		var current_grid = Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))
		var current_cost: float = 1.0
		if terrain.is_valid_cell(current_grid):
			current_cost = terrain.get_cell_property(current_grid, "movement_cost")
			speed = speed / maxf(current_cost, 0.1)
		
		# Check what cell the direct path would take us into
		var step_pos = world_pos + direction.normalized() * minf(speed * delta, distance)
		var next_grid = Vector2i(int(step_pos.x / cell_size), int(step_pos.y / cell_size))
		
		if next_grid != current_grid and terrain.is_valid_cell(next_grid):
			var next_cost: float = terrain.get_cell_property(next_grid, "movement_cost")
			var next_impassable: bool = terrain.get_cell_property(next_grid, "is_impassable")
			var next_water: bool = terrain.get_cell_property(next_grid, "is_water")
			
			# Avoid impassable and water entirely, avoid expensive terrain
			if next_impassable or next_water or next_cost > current_cost * 2.0:
				# Try lateral directions: 45 and 90 degrees either side
				var base_dir = direction.normalized()
				var best_dir = Vector2.ZERO
				var best_cost_found = INF
				
				for angle_offset in [0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
					var test_dir = base_dir.rotated(angle_offset)
					var test_pos = world_pos + test_dir * float(cell_size)
					var test_grid = Vector2i(int(test_pos.x / cell_size), int(test_pos.y / cell_size))
					
					if terrain.is_valid_cell(test_grid):
						var test_cost: float = terrain.get_cell_property(test_grid, "movement_cost")
						var test_impassable: bool = terrain.get_cell_property(test_grid, "is_impassable")
						var test_water: bool = terrain.get_cell_property(test_grid, "is_water")
						
						if not test_impassable and not test_water and test_cost < best_cost_found:
							best_cost_found = test_cost
							best_dir = test_dir
					
				if best_dir != Vector2.ZERO:
					direction = best_dir * distance  # redirect
				else:
					# No good options, just stop
					is_moving = false
					return
	
	var step = speed * delta
	if step >= distance:
		world_pos = desired_pos
		is_moving = false
	else:
		world_pos += direction.normalized() * step

func get_grid_pos(cell_size: int = 32) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))
