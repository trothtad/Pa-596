# squad.gd
# A squad of individual soldiers who move together
# The squad is the command unit - orders go to the squad, not individuals
# Click any soldier, select the squad leader
extends Node2D

const PathfinderClass = preload("res://scripts/systems/pathfinder.gd")
const SoldierClass = preload("res://scripts/entities/soldier.gd")
const DetectionClass = preload("res://scripts/systems/detection.gd")
const CombatResolverScript = preload("res://scripts/systems/combat_resolver.gd")

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
var formation_spread := 64.0  # pixels - how far troops spread from leader (roughly one cell)
var cohesion_range := 120.0    # pixels - max distance before "separated"

# Combat
var combat_target: Node2D = null  # current target (hound etc), set by engagement logic
var resolver = CombatResolverScript.new()  # combat math instance
var current_doctrine: int = FireControl.Doctrine.DEFENSIVE  # FUTURE: moves to entity blackboard
var squad_is_firing := false  # true if any soldier fired this tick  # FUTURE: moves to faction blackboard

# Reference to battle map
var battle_map: Node2D = null

signal unit_selected(unit: Node2D)
signal unit_moved(unit: Node2D, from: Vector2i, to: Vector2i)
signal unit_arrived(unit: Node2D)

func _ready() -> void:
	_snap_soldiers_to_grid()
	TickManager.tick.connect(_on_tick)

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
			var angle = (float(i) / soldiers.size()) * TAU + randf_range(-0.9, 0.9)
			var dist = formation_spread * randf_range(0.1, 1.0)
			s.world_pos = center + Vector2(cos(angle), sin(angle)) * dist
	
	position = center

func _process(delta: float) -> void:
	if not battle_map:
		return
	if is_wiped():
		queue_redraw()
		return

	# Leader follows A* path
	if is_moving and move_path.size() > 0:
		_process_leader_movement(delta)
	
	# Troops steer toward positions near leader
	_process_troop_movement(delta)
	
	# Tick down fire timers each frame (smooth countdown, resolution on tick)
	for s in soldiers:
		if s.fire_timer > 0 and not s.is_reloading:
			s.fire_timer -= delta

	# Reload management — timer only ticks while stationary (can't reload on the run)
	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue
		if s.is_reloading and not s.is_moving:
			s.reload_timer -= delta
			if s.reload_timer <= 0.0:
				s.is_reloading = false
				s.ammo_current = s.weapon.ammo_capacity
				s.fire_timer = 0.0
				print("🔄 %s — RELOADED (%d rounds)" % [s.soldier_name, s.ammo_current])
		elif s.ammo_current <= 0 and s.weapon != null and not s.is_reloading:
			# Start reload
			s.is_reloading = true
			s.reload_timer = s.weapon.reload_time
	
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

# --- Tick-Based Combat & Composure ---

func _on_tick(_tick_number: int) -> void:
	"""All combat logic runs at fixed tick rate (10Hz at 1x speed), not per frame."""
	if not battle_map:
		return
	if is_wiped():
		return
	var tick_delta := 1.0 / TickManager.BASE_TICKS_PER_SECOND

	# Casualties first — deaths from hound melee are applied in _process(),
	# so we catch and report them here before any other logic runs.
	_process_casualties()

	# Order matters: incoming fire → composure update → fire control
	# Pressure applied first, then recovery/floor, then shooting
	_process_incoming_fire(tick_delta)
	_process_composure_tick(tick_delta)
	_process_combat_tick(tick_delta)

func _process_incoming_fire(delta: float) -> void:
	"""Apply composure pressure from nearby threats.
	Hound proximity terror is the Phase A stand-in for incoming fire.
	Closer = more terrifying. FUTURE: incoming gunfire suppression added here."""
	if not battle_map:
		return

	# Terror range bands (in cells)
	const TERROR_CLOSE := 3      # massive pressure — right on top of you
	const TERROR_MEDIUM := 6     # moderate pressure — closing fast
	const TERROR_FAR := 10       # mild unease — something's out there

	# Pressure amounts (composure points/sec)
	const PRESSURE_CLOSE := 15.0   # 4 seconds from STEADY to BROKEN at close range
	const PRESSURE_MEDIUM := 4.0  # noticeable but manageable
	const PRESSURE_FAR := 1.0      # creeping dread

	for hostile in battle_map.hostiles:
		if hostile.get("is_dead"):
			continue

		var hostile_grid: Vector2i = hostile.grid_pos
		var dist: float = grid_pos.distance_to(Vector2(hostile_grid))

		# Only apply terror if hound is detected (you can't fear what you don't know about)
		var hostile_id: int = hostile.get_instance_id()
		var is_known := false
		if battle_map.detected_hostile_positions.has(hostile_id):
			var info: Dictionary = battle_map.detected_hostile_positions[hostile_id]
			var label: String = info.get("label", "UNAWARE")
			# Need at least DETECTED to feel terror (you sense something is there)
			is_known = label in ["DETECTED", "IDENTIFIED", "TRACKED"]

		if not is_known:
			continue

		# Determine pressure based on distance
		var pressure := 0.0
		if dist <= TERROR_CLOSE:
			pressure = PRESSURE_CLOSE
		elif dist <= TERROR_MEDIUM:
			# Linear interpolation between close and medium
			var t: float = (dist - TERROR_CLOSE) / (TERROR_MEDIUM - TERROR_CLOSE)
			pressure = lerpf(PRESSURE_CLOSE, PRESSURE_MEDIUM, t)
		elif dist <= TERROR_FAR:
			var t: float = (dist - TERROR_MEDIUM) / (TERROR_FAR - TERROR_MEDIUM)
			pressure = lerpf(PRESSURE_MEDIUM, PRESSURE_FAR, t)
		else:
			continue  # too far to feel terror

		# Apply pressure to each living soldier (reduced by terrain cover)
		for s in soldiers:
			if s.state == SoldierClass.State.DEAD:
				continue

			# Already BROKEN — no point hammering further, they're done
			if s.get_composure_level() == ComposureSystem.Level.BROKEN:
				s.under_fire = true
				s.under_fire_timer = 1.0
				continue

			# Cover reduces terror: soldiers in buildings feel safer
			var soldier_pressure: float = pressure
			var soldier_grid: Vector2i = s.get_grid_pos(battle_map.CELL_SIZE)
			if battle_map.terrain.is_valid_cell(soldier_grid):
				var cover_val: int = battle_map.terrain.get_cell_property(soldier_grid, "cover")
				match cover_val:
					1: soldier_pressure *= 0.7   # light cover: 30% reduction
					2: soldier_pressure *= 0.4   # heavy cover: 60% reduction

			s.composure_value = ComposureSystem.apply_pressure(
				s.composure_value, soldier_pressure, delta
			)
			s.under_fire = true
			s.under_fire_timer = 1.0  # 1 second window

func _process_composure_tick(delta: float) -> void:
	"""Update composure for all soldiers. Recovery when safe, decay of under_fire timers.
	BROKEN soldiers cannot recover while any hostile is still detected."""
	# Check if any hostile is currently known (for BROKEN recovery lockout)
	var threats_detected : bool = not battle_map.detected_hostile_positions.is_empty()

	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue

		# Decay under_fire timer
		if s.under_fire:
			s.under_fire_timer -= delta
			if s.under_fire_timer <= 0:
				s.under_fire = false
				s.under_fire_timer = 0.0

		# BROKEN soldiers can't recover while threats are detected
		# They've lost it — only safety lets them pull themselves together
		var current_level: int = s.get_composure_level()
		if current_level == ComposureSystem.Level.BROKEN and threats_detected:
			# Still locked in BROKEN state — no recovery
			pass
		else:
			# Recovery (slow when under fire, faster when safe)
			s.composure_value = ComposureSystem.apply_recovery(
				s.composure_value, s.under_fire, delta
			)

		# Detect level transitions and log them
		var new_level: int = s.get_composure_level()
		if new_level != s.last_composure_level:
			var old_name: String = ComposureSystem.get_level_name(s.last_composure_level)
			var new_name: String = ComposureSystem.get_level_name(new_level)
			if new_level < s.last_composure_level:
				# Degrading
				print("😰 %s %s — %s → %s" % [squad_name, s.soldier_name, old_name, new_name])
			else:
				# Recovering
				print("😌 %s %s — %s → %s" % [squad_name, s.soldier_name, old_name, new_name])
			s.last_composure_level = new_level

	# Sergeant-as-floor: leader's level is the minimum for all soldiers
	if leader and leader.state != SoldierClass.State.DEAD:
		for s in soldiers:
			if s == leader or s.state == SoldierClass.State.DEAD:
				continue
			s.composure_value = ComposureSystem.apply_sergeant_floor(
				s.composure_value, leader.composure_value
			)

func _process_combat_tick(delta: float) -> void:
	"""Fire control and shot resolution, runs each tick."""
	if not battle_map:
		return

	squad_is_firing = false  # reset each tick, set true if anyone fires

	# Target selection via FireControl — respects doctrine
	var target_info: Dictionary = FireControl.select_target(
		battle_map.detected_hostile_positions,
		grid_pos,
		current_doctrine
	)

	if target_info.is_empty():
		combat_target = null
		return

	combat_target = target_info.get("hostile")
	if combat_target == null:
		return

	var target_grid: Vector2i = combat_target.grid_pos
	var target_armor: int = combat_target.get("armor") if combat_target.get("armor") != null else 0
	var target_moving: bool = combat_target.get("is_moving") if combat_target.get("is_moving") != null else false
	var detection_label: String = target_info.get("detection_label", "UNAWARE")

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

		# Composure check — broken soldiers can't fire
		var composure_level: int = s.get_composure_level()
		if not ComposureSystem.can_fire(composure_level):
			continue

		# Fire timer not ready (timer decrements in _process per frame)
		if s.fire_timer > 0:
			continue

		# Can't fire while moving
		if s.is_moving:
			continue

		# Out of ammo or currently reloading
		if s.ammo_current <= 0 or s.is_reloading:
			continue

		# Range and doctrine check
		var shooter_grid: Vector2i = s.get_grid_pos(battle_map.CELL_SIZE)
		var distance: int = int(shooter_grid.distance_to(Vector2(target_grid)))

		if not FireControl.should_engage(current_doctrine, detection_label, distance, s.weapon.max_range):
			s.fire_timer = s.weapon.get_fire_interval() * 0.5  # check again sooner
			continue

		# LOS check from this soldier's position
		var visible_cells: Array[Vector2i] = battle_map.calculate_los_from(shooter_grid, s.weapon.max_range)
		if target_grid not in visible_cells:
			s.fire_timer = s.weapon.get_fire_interval() * 0.5
			continue

		# FIRE!
		var suppressed: bool = s.suppression > 0.3
		var fatigue_mod: int = int(-s.fatigue * 0.15) + s.get_wound_accuracy_modifier()  # fatigue + wound penalty

		var result: Dictionary = resolver.resolve_full_shot(
			s.weapon,
			s.accuracy,
			distance,
			cover_mod,
			target_moving,
			target_armor,
			false,  # target is NOT a soldier (it's a kaiju)
			false,  # shooter not moving (checked above)
			ComposureSystem.to_legacy_composure(composure_level),
			suppressed,
			fatigue_mod
		)

		# Apply results
		s.ammo_current -= 1
		# Fire rate adjusted by composure and doctrine
		var base_interval: float = s.weapon.get_fire_interval()
		var composure_rate: float = ComposureSystem.get_fire_rate_modifier(composure_level)
		s.fire_timer = FireControl.get_fire_cooldown(current_doctrine, base_interval) * composure_rate

		squad_is_firing = true

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

		# Ammo warnings
		if s.weapon.ammo_capacity > 0:
			var ammo_pct: float = float(s.ammo_current) / float(s.weapon.ammo_capacity)
			if ammo_pct <= 0.25 and ammo_pct + (1.0 / float(s.weapon.ammo_capacity)) > 0.25:
				# Just crossed the 25% threshold
				print("⚠ %s — LOW AMMO (%d/%d)" % [
					s.soldier_name, s.ammo_current, s.weapon.ammo_capacity])

		# FUTURE: apply result["suppression_generated"] to target if target_is_soldier
		# Currently shooting at kaiju — they don't take suppression

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

func get_ammo_status() -> String:
	"""Squad ammo summary for UI. Returns e.g. '32/50 rounds (64%)'."""
	var total_current := 0
	var total_capacity := 0
	for s in soldiers:
		if s.state == SoldierClass.State.DEAD:
			continue
		if s.weapon == null:
			continue
		total_current += s.ammo_current
		total_capacity += s.weapon.ammo_capacity
	if total_capacity == 0:
		return "No ammo"
	var pct: int = int(float(total_current) / float(total_capacity) * 100.0)
	return "%d/%d rounds (%d%%)" % [total_current, total_capacity, pct]

# --- Casualty Handling ---

func is_wiped() -> bool:
	"""True when every soldier is dead. Squad stops all activity."""
	return _count_living() == 0

func _count_living() -> int:
	var count := 0
	for s in soldiers:
		if s.state != SoldierClass.State.DEAD:
			count += 1
	return count

func _process_casualties() -> void:
	"""Detect newly-wounded or newly-dead soldiers and trigger effects."""
	for s in soldiers:
		# New wound on a living soldier — composure shock
		if s.wound_state > 0 and not s.wound_notified and s.state != SoldierClass.State.DEAD:
			s.wound_notified = true
			s.composure_value -= 15.0 * s.wound_state
			s.composure_value = maxf(s.composure_value, 0.0)

		# Death — report and handle leadership
		if s.state == SoldierClass.State.DEAD and not s.death_handled:
			s.death_handled = true
			_on_soldier_died(s)

func _on_soldier_died(dead_soldier) -> void:
	"""React to a soldier's death: report, promote leader if needed, check for wipe."""
	var alive := _count_living()

	if alive == 0:
		print("☠ %s — WIPED OUT" % squad_name)
		return

	var was_leader := (dead_soldier == leader)
	print("💀 %s — %s KIA (%d/%d remaining)" % [
		squad_name, dead_soldier.soldier_name, alive, soldiers.size()
	])

	# Composure shock — watching a squadmate die is devastating.
	# Losing the NCO is worse (panic can cascade quickly without leadership).
	var shock := 40.0 if was_leader else 20.0
	for s in soldiers:
		if s.state != SoldierClass.State.DEAD:
			s.composure_value = ComposureSystem.apply_pressure(s.composure_value, shock, 1.0)

	# If the leader went down, promote the first living soldier
	if was_leader:
		for candidate in soldiers:
			if candidate.state != SoldierClass.State.DEAD:
				leader = candidate
				leader.role = "leader"
				print("⬆ %s — %s promoted to squad leader" % [
					squad_name, leader.soldier_name
				])
				break

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
