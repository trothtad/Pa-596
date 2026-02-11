# hound.gd
# Hound-class kaiju — the first hostile entity in Pā 596
# A predator on the map. Simple state machine, terrifying implications.
extends Node2D

const PathfinderClass = preload("res://scripts/core/pathfinder.gd")
const DetectionClass = preload("res://scripts/core/detection.gd")

# --- State Machine ---
enum State { IDLE, PATROL, STALK, CHASE, ATTACK, SEARCH }
var state: int = State.PATROL

# Identity
var entity_name := "Hound"

# Position
var grid_pos := Vector2i(30, 15)
var world_pos := Vector2.ZERO

# Movement
var walk_speed := 100.0   # patrol speed (px/s)
var stalk_speed := 60.0   # cautious approach
var run_speed := 200.0    # full chase
var move_path: Array[Vector2i] = []
var path_index := 0
var is_moving := false

# Patrol
var patrol_waypoints: Array[Vector2i] = []
var current_waypoint_index := 0
var idle_timer := 0.0
var idle_duration := 2.0  # seconds to pause at each waypoint

# Detection — what the Hound knows about targets
var observer_profile = null   # DetectionClass.DetectionProfile
var target_profile = null     # how detectable the Hound is
var detection_states: Dictionary = {}  # target_id -> DetectionState
var current_target = null     # the squad we're hunting (Node2D ref)
var last_known_target_pos := Vector2i(-1, -1)

# Search behavior
var search_timer := 0.0
var search_duration := 8.0   # seconds to search before giving up
var search_radius := 5       # cells to wander around last known pos

# Terrain interaction — Hounds mostly ignore terrain
var terrain_cost_override := {
	"open": 1.0,
	"road": 1.0,
	"rough": 0.9,      # barely slowed
	"water": 0.7,       # will cross
	"building": 0.5,    # can enter, slowed
	"impassable": INF,  # even Hounds respect cliffs
}

# Visual
var hound_color := Color(0.8, 0.15, 0.1)  # angry red
var hound_size := 7.0
var sight_range := 10  # for fog of war purposes

# Combat stats
var armor := 0           # 0=no armor (basic Hound). Rifle can penetrate.
var hp_max := 4          # penetrating hits to kill
var hp_current := 4
var is_dead := false

# Reference
var battle_map: Node2D = null
var pathfinder = null

signal entity_moved(entity: Node2D, from: Vector2i, to: Vector2i)
signal entity_state_changed(entity: Node2D, old_state: int, new_state: int)
signal entity_killed(entity: Node2D)

func _ready() -> void:
	# Set up detection profiles
	observer_profile = DetectionClass.make_hound_observer()
	target_profile = DetectionClass.make_hound_target()

func setup(p_name: String, p_grid_pos: Vector2i, p_waypoints: Array[Vector2i]) -> void:
	entity_name = p_name
	grid_pos = p_grid_pos
	patrol_waypoints = p_waypoints
	
	if battle_map:
		world_pos = battle_map.grid_to_world(grid_pos)
		position = world_pos
		# Hound gets its own pathfinder (could share, but may want different costs later)
		pathfinder = PathfinderClass.new(battle_map.terrain)

func _process(delta: float) -> void:
	if not battle_map:
		return
	if is_dead:
		return
	
	# Run detection against all known squads
	_run_detection(delta)
	
	# State machine
	match state:
		State.IDLE:
			_process_idle(delta)
		State.PATROL:
			_process_patrol(delta)
		State.STALK:
			_process_stalk(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.SEARCH:
			_process_search(delta)
	
	# Update grid pos
	var old_grid = grid_pos
	grid_pos = Vector2i(int(world_pos.x / battle_map.CELL_SIZE), int(world_pos.y / battle_map.CELL_SIZE))
	if grid_pos != old_grid:
		entity_moved.emit(self, old_grid, grid_pos)
	
	position = world_pos
	queue_redraw()

# --- Detection ---

func _run_detection(delta: float) -> void:
	"""Check all squads, build/decay detection levels."""
	for unit in battle_map.units:
		if not unit.has_method("contains_point"):
			continue  # skip non-squads
		
		var unit_id = unit.get_instance_id()
		if not detection_states.has(unit_id):
			detection_states[unit_id] = DetectionClass.DetectionState.new()
		
		var det_state = detection_states[unit_id]
		var target_grid = unit.grid_pos
		var distance = grid_pos.distance_to(Vector2(target_grid))
		
		# Check LOS using battle_map's system
		var has_los = false
		if distance <= observer_profile.sight_range:
			var visible = battle_map.calculate_los_from(grid_pos, int(observer_profile.sight_range))
			has_los = target_grid in visible
		
		det_state.is_in_los = has_los
		
		# Is the target in concealment?
		var in_concealment = false
		if battle_map.terrain.is_valid_cell(target_grid):
			in_concealment = battle_map.terrain.get_cell_property(target_grid, "concealment")
		
		# Get target's detection profile (how detectable the squad is)
		var squad_target_profile = DetectionClass.make_human_squad_target()
		
		# Calculate detection change
		var det_delta = DetectionClass.calculate_detection_tick(
			grid_pos,
			observer_profile,
			target_grid,
			squad_target_profile,
			unit.is_moving,
			false,  # is_firing — not implemented yet
			has_los,
			in_concealment,
			distance,
			delta
		)
		
		det_state.detection_level = clampf(det_state.detection_level + det_delta, 0.0, 1.0)
		
		if det_state.detection_level > 0.01:
			det_state.last_known_pos = target_grid
		
		# State transitions based on detection
		_evaluate_detection_transitions(unit, det_state)

func _evaluate_detection_transitions(target: Node2D, det_state) -> void:
	"""Decide whether to change state based on detection levels."""
	var level = det_state.detection_level
	
	match state:
		State.IDLE, State.PATROL:
			if level >= DetectionClass.THRESHOLD_DETECTED:
				_change_state(State.STALK)
				current_target = target
				last_known_target_pos = det_state.last_known_pos
				_path_to(last_known_target_pos, stalk_speed)
		
		State.STALK:
			if level >= DetectionClass.THRESHOLD_TRACKED:
				_change_state(State.CHASE)
				current_target = target
			elif level < DetectionClass.THRESHOLD_SUSPECTED:
				# Lost them
				_change_state(State.SEARCH)
				search_timer = 0.0
		
		State.CHASE:
			if level < DetectionClass.THRESHOLD_DETECTED:
				# Lost them during chase
				_change_state(State.SEARCH)
				search_timer = 0.0
		
		State.SEARCH:
			if level >= DetectionClass.THRESHOLD_DETECTED:
				_change_state(State.STALK)
				current_target = target
				last_known_target_pos = det_state.last_known_pos
				_path_to(last_known_target_pos, stalk_speed)

# --- State Processors ---

func _process_idle(delta: float) -> void:
	idle_timer += delta
	if idle_timer >= idle_duration:
		idle_timer = 0.0
		_change_state(State.PATROL)
		_advance_patrol()

func _process_patrol(delta: float) -> void:
	if move_path.size() == 0:
		# Arrived at waypoint, pause
		_change_state(State.IDLE)
		return
	_follow_path(delta, walk_speed)

func _process_stalk(delta: float) -> void:
	# Update path toward last known position periodically
	if current_target:
		var target_id = current_target.get_instance_id()
		if detection_states.has(target_id):
			var det = detection_states[target_id]
			if det.detection_level >= DetectionClass.THRESHOLD_DETECTED:
				last_known_target_pos = det.last_known_pos
	
	if move_path.size() == 0:
		# Reached last known position — if we can see them, chase. Otherwise search.
		if current_target:
			var target_id = current_target.get_instance_id()
			if detection_states.has(target_id):
				if detection_states[target_id].detection_level >= DetectionClass.THRESHOLD_TRACKED:
					_change_state(State.CHASE)
					return
		_change_state(State.SEARCH)
		search_timer = 0.0
		return
	
	_follow_path(delta, stalk_speed)

func _process_chase(delta: float) -> void:
	if not current_target:
		_change_state(State.SEARCH)
		search_timer = 0.0
		return
	
	# Chase directly — repath frequently toward actual target position
	var target_pos = current_target.grid_pos
	var dist = grid_pos.distance_to(Vector2(target_pos))
	
	# Repath every ~0.5 seconds worth of movement 
	if move_path.size() == 0 or path_index >= move_path.size() - 1:
		_path_to(target_pos, run_speed)
	
	# Close enough to attack?
	if dist <= 1.5:
		_change_state(State.ATTACK)
		return
	
	_follow_path(delta, run_speed)

func _process_attack(_delta: float) -> void:
	# Placeholder — we'll build this when we add combat
	# For now, just print something terrifying and go back to chase
	if current_target:
		var dist = grid_pos.distance_to(Vector2(current_target.grid_pos))
		if dist > 2.0:
			# Target moved away, pursue
			_change_state(State.CHASE)

func _process_search(delta: float) -> void:
	search_timer += delta
	
	if search_timer >= search_duration:
		# Give up, go back to patrol
		_change_state(State.PATROL)
		current_target = null
		_advance_patrol()
		return
	
	# Wander near last known position
	if move_path.size() == 0:
		var wander_target = last_known_target_pos + Vector2i(
			randi_range(-search_radius, search_radius),
			randi_range(-search_radius, search_radius)
		)
		wander_target.x = clampi(wander_target.x, 0, battle_map.terrain.width - 1)
		wander_target.y = clampi(wander_target.y, 0, battle_map.terrain.height - 1)
		_path_to(wander_target, walk_speed)
	
	_follow_path(delta, walk_speed)

# --- Movement Helpers ---

func _follow_path(delta: float, speed: float) -> void:
	if path_index >= move_path.size():
		move_path.clear()
		path_index = 0
		is_moving = false
		return
	
	is_moving = true
	var next_cell = move_path[path_index]
	var target_world = battle_map.grid_to_world(next_cell)
	var direction = target_world - world_pos
	var distance = direction.length()
	
	# Hound terrain cost (lighter than human)
	var cell_terrain: String = battle_map.terrain.get_cell_property(next_cell, "terrain_type")
	var cost: float = terrain_cost_override.get(cell_terrain, 1.0)
	var effective_speed = speed / maxf(cost, 0.1)
	
	var step = effective_speed * delta
	if step >= distance:
		world_pos = target_world
		path_index += 1
		if path_index >= move_path.size():
			move_path.clear()
			path_index = 0
			is_moving = false
	else:
		world_pos += direction.normalized() * step

func _path_to(target: Vector2i, _speed: float) -> void:
	if not pathfinder:
		return
	move_path = pathfinder.find_path(grid_pos, target)
	path_index = 0

func _advance_patrol() -> void:
	if patrol_waypoints.size() == 0:
		return
	current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
	_path_to(patrol_waypoints[current_waypoint_index], walk_speed)

func _change_state(new_state: int) -> void:
	var old_state = state
	state = new_state
	entity_state_changed.emit(self, old_state, new_state)
	
	var state_names = ["IDLE", "PATROL", "STALK", "CHASE", "ATTACK", "SEARCH"]
	print("%s: %s → %s" % [entity_name, state_names[old_state], state_names[new_state]])

# --- Combat ---

func take_hit(damage: int) -> void:
	"""Receive a penetrating hit. Subtract HP, check for death."""
	hp_current -= damage
	print("  ⬛ %s takes %d damage — HP: %d/%d" % [entity_name, damage, hp_current, hp_max])
	
	if hp_current <= 0:
		_die()

func _die() -> void:
	"""The Hound is dead."""
	is_dead = true
	is_moving = false
	move_path.clear()
	hound_color = Color(0.3, 0.15, 0.1, 0.5)  # darken, fade
	print("\n☠ %s — KILLED" % entity_name)
	print("  The thing shudders and goes still.")
	entity_killed.emit(self)
	queue_redraw()

# --- Drawing ---

func _draw() -> void:
	# Dead hound — just a dark smear
	if is_dead:
		draw_circle(Vector2.ZERO, hound_size * 0.8, Color(0.25, 0.1, 0.05, 0.4))
		return
	
	# Hound body — menacing red dot
	draw_circle(Vector2.ZERO, hound_size, hound_color)
	draw_arc(Vector2.ZERO, hound_size, 0, TAU, 16, Color(0.4, 0.05, 0.0), 2.0)
	
	# State indicator
	var state_color := Color.WHITE
	match state:
		State.IDLE:
			state_color = Color(0.5, 0.5, 0.5, 0.6)
		State.PATROL:
			state_color = Color(0.8, 0.6, 0.1, 0.6)
		State.STALK:
			state_color = Color(0.8, 0.4, 0.0, 0.8)
		State.CHASE:
			state_color = Color(1.0, 0.1, 0.0, 0.9)
		State.ATTACK:
			state_color = Color(1.0, 0.0, 0.0, 1.0)
		State.SEARCH:
			state_color = Color(0.6, 0.3, 0.6, 0.7)
	
	# Small state ring
	draw_arc(Vector2.ZERO, hound_size + 3, 0, TAU, 16, state_color, 1.5)

func get_info() -> String:
	var state_names = ["IDLE", "PATROL", "STALK", "CHASE", "ATTACK", "SEARCH"]
	return "%s [%s] @ (%d,%d)" % [entity_name, state_names[state], grid_pos.x, grid_pos.y]

func get_state_name() -> String:
	var state_names = ["IDLE", "PATROL", "STALK", "CHASE", "ATTACK", "SEARCH"]
	return state_names[state]
