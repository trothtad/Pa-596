# squad.gd
# A squad of individual soldiers who move together
# The squad is the command unit - orders go to the squad, not individuals
# Click any soldier, select the squad leader
extends Node2D

const PathfinderClass = preload("res://scripts/core/pathfinder.gd")
const SoldierClass = preload("res://scripts/core/soldier.gd")
const DetectionClass = preload("res://scripts/core/detection.gd")
const CombatResolverScript = preload("res://scripts/core/combat_resolver.gd")

# Squad identity
var squad_name := "Squad"
var squad_type := "rifle"  # rifle, mg, scout, etc.

# Soldiers
var soldiers: Array = []  # Array of Soldier
var leader = null  # SoldierClass instance

# The leader's grid position (used by battle_map for LOS, fog, etc.)
var grid_pos := Vector2i(5, 5)

# Movement - leader follows A* path, troops rubber-band to leader
var move_path: Array[Vector2i] = []
var is_moving := false
var path_index := 0
var target_pos := Vector2i(5, 5)

# Squad properties
var sight_range := 12
var selected := false

# Rubber band settings
var formation_spread := 32.0  # pixels - how far troops spread from leader (roughly one cell)
var cohesion_range := 80.0    # pixels - max distance before "separated"

# Combat
var combat_target: Node2D = null  # current target (hound etc), set by engagement logic
var resolver = CombatResolverScript.new()  # combat math instance

# Reference to battle map
var battle_map: Node2D = null

signal unit_selected(unit: Node2D)
signal unit_moved(unit: Node2D, from: Vector2i, to: Vector2i)
signal unit_arrived(unit: Node2D)

func _ready() -> void:
	_snap_soldiers_to_grid()

func setup(p_name: String, p_grid_pos: Vector2i, p_soldiers: Array) -> void:
	"""Initialize squad with name, position, and soldier list."""
	squad_name = p_name
	grid_pos = p_grid_pos
	soldiers = p_soldiers
	
	# Find the leader
	for s in soldiers:
		if s.role == "leader":
			leader = s
			break
	
	if not leader and soldiers.size() > 0:
		leader = soldiers[0]
		leader.role = "leader"
	
	_snap_soldiers_to_grid()

func _snap_soldiers_to_grid() -> void:
	"""Place all soldiers at initial positions around grid_pos."""
	if not battle_map:
		return
	var center = battle_map.grid_to_world(grid_pos)
	
	# Scatter troops loosely around center
	for i in range(soldiers.size()):
		var s = soldiers[i]
		if s.role == "leader":
			s.world_pos = center
		else:
			# Offset troops in a rough cluster behind/around leader
			var angle = (float(i) / soldiers.size()) * TAU + randf_range(-0.3, 0.3)
			var dist = formation_spread * randf_range(0.5, 1.0)
			s.world_pos = center + Vector2(cos(angle), sin(angle)) * dist
	
	position = center

func _process(delta: float) -> void:
	if not battle_map:
		return
	
	# Leader follows A* path
	if is_moving and move_path.size() > 0:
		_process_leader_movement(delta)
	
	# Troops steer toward positions near leader
	_process_troop_movement(delta)
	
	# Combat — soldiers fire at target if able
	_process_combat(delta)
	
	# Update squad grid_pos from leader
	var old_grid = grid_pos
	grid_pos = leader.get_grid_pos(battle_map.CELL_SIZE)
	if grid_pos != old_grid:
		unit_moved.emit(self, old_grid, grid_pos)
	
	# Update node position to leader (for camera/selection purposes)
	position = leader.world_pos
	
	queue_redraw()

func _process_leader_movement(delta: float) -> void:
	if path_index >= move_path.size():
		_finish_movement()
		return
	
	var next_cell = move_path[path_index]
	var target_world = battle_map.grid_to_world(next_cell)
	var direction = target_world - leader.world_pos
	var distance = direction.length()
	
	# Terrain cost
	var move_cost: float = 1.0
	move_cost = battle_map.terrain.get_cell_property(next_cell, "movement_cost")
	move_cost = maxf(move_cost, 0.1)
	
	var effective_speed = leader.move_speed / move_cost
	var step = effective_speed * delta
	
	if step >= distance:
		leader.world_pos = target_world
		grid_pos = next_cell
		path_index += 1
		leader.is_moving = path_index < move_path.size()
		
		if path_index >= move_path.size():
			_finish_movement()
	else:
		leader.world_pos += direction.normalized() * step
		leader.is_moving = true

func _process_troop_movement(delta: float) -> void:
	"""Each troop steers toward a position near the leader."""
	var troop_index := 0
	for i in range(soldiers.size()):
		var s = soldiers[i]
		if s == leader:
			continue
		if s.state == SoldierClass.State.DEAD:
			continue
		
		# Desired position: offset from leader
		# Troops cluster behind/around leader in a loose group
		troop_index += 1
		var angle = (float(troop_index) / 3.0) * TAU * 0.8 + PI  # mostly behind
		var spread = formation_spread
		
		# If leader is moving, troops trail slightly
		if leader.is_moving:
			spread *= 1.3
		
		var desired = leader.world_pos + Vector2(cos(angle), sin(angle)) * spread + s.formation_offset
		
		# Comfortable range — if close enough, don't bother moving
		var dist_to_desired = s.world_pos.distance_to(desired)
		if dist_to_desired < 12.0 and not leader.is_moving:
			# Close enough and squad is stationary — relax
			s.is_moving = false
			continue
		
		s.steer_toward(desired, delta, battle_map.terrain, battle_map.CELL_SIZE)

func _process_combat(delta: float) -> void:
	"""Each soldier ticks fire timer, acquires targets, resolves shots."""
	if not battle_map:
		return
	
	# Target acquisition — find an IDENTIFIED hostile
	if combat_target == null or (combat_target.has_method("get_instance_id") and combat_target.get("is_dead")):
		combat_target = _find_combat_target()
	if combat_target == null:
		return
	
	var target_grid: Vector2i = combat_target.grid_pos
	var target_armor: int = combat_target.get("armor") if combat_target.get("armor") != null else 0
	var target_moving: bool = combat_target.get("is_moving") if combat_target.get("is_moving") != null else false
	
	# Get cover at target position
	var cover_val: int = battle_map.terrain.get_cell_property(target_grid, "cover")
	var cover_mod := 0
	match cover_val:
		1: cover_mod = resolver.COVER_LIGHT
		2: cover_mod = resolver.COVER_HEAVY
	
	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue
		if s.weapon == null:
			continue
		if s.composure >= 3:  # broken — won't fire
			continue
		
		# Tick fire timer
		s.fire_timer -= delta
		if s.fire_timer > 0:
			continue
		
		# Can't fire while moving
		if s.is_moving:
			continue
		
		# Out of ammo?
		if s.ammo_current <= 0:
			continue
		
		# Range check
		var shooter_grid = s.get_grid_pos(battle_map.CELL_SIZE)
		var distance = int(shooter_grid.distance_to(Vector2(target_grid)))
		if distance > s.weapon.max_range:
			# Reset timer but don't fire — check again next interval
			s.fire_timer = s.weapon.get_fire_interval() * 0.5  # check again sooner
			continue
		
		# LOS check from this soldier's position
		var visible_cells = battle_map.calculate_los_from(shooter_grid, s.weapon.max_range)
		if target_grid not in visible_cells:
			s.fire_timer = s.weapon.get_fire_interval() * 0.5
			continue
		
		# FIRE!
		var suppressed = s.suppression > 0.3
		var fatigue_mod = int(-s.fatigue * 0.15)  # 0 to -15
		
		var result = resolver.resolve_full_shot(
			s.weapon,
			s.accuracy,
			distance,
			cover_mod,
			target_moving,
			target_armor,
			false,  # target is NOT a soldier (it's a kaiju)
			false,  # shooter not moving (checked above)
			s.composure,
			suppressed,
			fatigue_mod
		)
		
		# Apply results
		s.ammo_current -= 1
		s.fire_timer = s.weapon.get_fire_interval()
		
		# Log the shot
		if result["hit"]:
			if result["penetrated"]:
				print("🟢 %s HITS %s at %dm (%d%%) — PENETRATES" % [
					s.soldier_name, combat_target.entity_name,
					distance * 4, result["hit_chance"]])
				# Damage the target
				if combat_target.has_method("take_hit"):
					combat_target.take_hit(1)
			else:
				print("🟡 %s HITS %s at %dm (%d%%) — NO PEN (armor %d)" % [
					s.soldier_name, combat_target.entity_name,
					distance * 4, result["hit_chance"], target_armor])
		else:
			print("⚪ %s misses %s at %dm (%d%%)" % [
				s.soldier_name, combat_target.entity_name,
				distance * 4, result["hit_chance"]])
		
		# Ammo warning
		if s.ammo_current == 0:
			print("⚠ %s — MAGAZINE EMPTY" % s.soldier_name)

func _find_combat_target() -> Node2D:
	"""Find the best hostile to engage. Must be IDENTIFIED or better."""
	if not battle_map:
		return null
	
	var best_target: Node2D = null
	var best_distance := INF
	
	for hostile in battle_map.hostiles:
		var hostile_id = hostile.get_instance_id()
		
		# Must be detected to IDENTIFIED level
		if battle_map.squad_detection_states.has(hostile_id):
			var det = battle_map.squad_detection_states[hostile_id]
			if det.detection_level < DetectionClass.THRESHOLD_IDENTIFIED:
				continue
		else:
			continue
		
		# Skip dead hostiles
		if hostile.get("is_dead"):
			continue
		
		# Pick closest
		var dist = grid_pos.distance_to(Vector2(hostile.grid_pos))
		if dist < best_distance:
			best_distance = dist
			best_target = hostile
	
	return best_target

func _finish_movement() -> void:
	is_moving = false
	move_path.clear()
	path_index = 0
	leader.is_moving = false
	unit_arrived.emit(self)

func move_to(path: Array[Vector2i]) -> void:
	"""Start moving along a path. Leader pathfinds, troops follow."""
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

func contains_point(world_point: Vector2, click_radius: float = 16.0) -> bool:
	"""Check if a world point is near any soldier in this squad."""
	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue
		if s.world_pos.distance_to(world_point) < click_radius:
			return true
	return false

func get_info() -> String:
	var alive = 0
	for s in soldiers:
		if s.state != SoldierClass.State.DEAD:
			alive += 1
	return "%s [%d/%d] @ (%d,%d)" % [squad_name, alive, soldiers.size(), grid_pos.x, grid_pos.y]

func get_soldier_names() -> String:
	var names = []
	for s in soldiers:
		var prefix = "★" if s.role == "leader" else "-"
		names.append("%s %s" % [prefix, s.soldier_name])
	return "\n".join(names)

# --- Drawing ---

func _draw() -> void:
	# Draw each soldier as a dot, relative to our position (which is leader.world_pos)
	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue
		
		var local_pos = s.world_pos - position  # relative to node
		
		# Soldier dot
		draw_circle(local_pos, s.dot_size, s.soldier_color)
		
		# Dark outline
		draw_arc(local_pos, s.dot_size, 0, TAU, 16, Color(0.2, 0.2, 0.15), 1.5)
		
		# Leader gets a small diamond shape on top
		if s == leader:
			var d = s.dot_size * 0.6
			var points = PackedVector2Array([
				local_pos + Vector2(0, -d),
				local_pos + Vector2(d, 0),
				local_pos + Vector2(0, d),
				local_pos + Vector2(-d, 0),
			])
			draw_colored_polygon(points, Color(0.2, 0.2, 0.15, 0.6))
	
	# Selection ring around the whole squad
	if selected:
		# Find bounding extent of soldiers
		var center = Vector2.ZERO
		var max_dist = 0.0
		var count = 0
		for s in soldiers:
			if s.state == SoldierClass.State.DEAD:
				continue
			var local_pos = s.world_pos - position
			center += local_pos
			count += 1
		
		if count > 0:
			center /= count
			for s in soldiers:
				if s.state == SoldierClass.State.DEAD:
					continue
				var dist = (s.world_pos - position).distance_to(center)
				max_dist = maxf(max_dist, dist)
			
			var ring_radius = max_dist + 12.0
			draw_arc(center, ring_radius, 0, TAU, 32, Color(0.2, 0.8, 1.0, 0.6), 2.0)
			draw_arc(center, ring_radius + 2, 0, TAU, 32, Color(0.2, 0.8, 1.0, 0.2), 1.0)
