# detection.gd
# Sense-agnostic detection system for Pā 596
# 
# Detection is not "can you see it." Detection is "how much stimulus 
# is this thing generating, and how good are your sensors?"
#
# A motionless Hound in tall grass inside your LOS? Maybe invisible.
# A Leviathan behind a mountain? You feel the ground shake.
#
# Everything that can detect or be detected has a DetectionProfile.
# The system accumulates detection_level per observer-target pair.
extends RefCounted

# Detection thresholds — what each level means
# 0.0  = UNAWARE       — no idea anything is there  
# 0.25 = SUSPECTED     — heard something, not sure what
# 0.50 = DETECTED      — something is definitely there, rough bearing
# 0.75 = IDENTIFIED    — know what it is, approximate position
# 1.0  = TRACKED       — exact position, real-time updates
const THRESHOLD_SUSPECTED := 0.25
const THRESHOLD_DETECTED := 0.50
const THRESHOLD_IDENTIFIED := 0.75
const THRESHOLD_TRACKED := 1.0

# --- Detection Profile ---
# Attached to anything that can detect things (observers)
# AND anything that can be detected (targets)
# Most entities are both.

class DetectionProfile:
	# -- As observer (how good are my senses) --
	var sight_range := 12.0       # cells — max visual detection range
	var sight_rate := 0.15        # detection gained per tick on visual contact
	var sight_motion_bonus := 0.1 # extra rate if target is moving
	var hearing_range := 16.0     # cells — max audio detection range
	var hearing_rate := 0.05      # detection gained per tick from noise
	var seismic_range := 0.0      # cells — feel ground vibrations (0 = disabled)
	var seismic_rate := 0.0       # detection gained per tick from vibrations
	
	# -- As target (how detectable am I) --
	var visual_signature := 1.0     # how visible (0 = invisible, 1 = normal, 2+ = huge)
	var noise_moving := 1.0         # noise when moving (0 = silent, 1 = normal)
	var noise_stationary := 0.1     # noise when still (breathing, gear rattle)
	var noise_firing := 5.0         # noise spike when shooting
	var seismic_signature := 0.0    # ground vibration (0 for humans, huge for kaiju)
	var concealment_bonus := 0.0    # reduction to visual detection (set by terrain)
	
	func _init() -> void:
		pass


# --- Detection State ---
# One per observer-target pair. Tracks accumulated awareness.

class DetectionState:
	var detection_level := 0.0     # 0.0 to 1.0
	var last_known_pos := Vector2i(-1, -1)  # where we last detected them
	var last_seen_time := 0.0      # game time of last detection tick
	var primary_sense := ""        # what sense is driving detection ("sight", "hearing", "seismic")
	var is_in_los := false         # currently have line of sight?
	
	func get_awareness_label() -> String:
		if detection_level >= THRESHOLD_TRACKED:
			return "TRACKED"
		elif detection_level >= THRESHOLD_IDENTIFIED:
			return "IDENTIFIED"
		elif detection_level >= THRESHOLD_DETECTED:
			return "DETECTED"
		elif detection_level >= THRESHOLD_SUSPECTED:
			return "SUSPECTED"
		else:
			return "UNAWARE"
	
	func _init() -> void:
		pass


# --- Core Detection Calculation ---

static func calculate_detection_tick(
	observer_pos: Vector2i,
	observer_profile: DetectionProfile,
	target_pos: Vector2i, 
	target_profile: DetectionProfile,
	target_is_moving: bool,
	target_is_firing: bool,
	has_los: bool,
	target_in_concealment: bool,
	distance_cells: float,
	delta: float
) -> float:
	"""Calculate how much detection_level changes this tick.
	Returns the delta to ADD to current detection_level.
	Can be positive (building detection) or negative (losing it)."""
	
	var gain := 0.0
	
	# --- SIGHT ---
	if has_los and distance_cells <= observer_profile.sight_range:
		var sight_gain = observer_profile.sight_rate
		
		# Moving targets are easier to see
		if target_is_moving:
			sight_gain += observer_profile.sight_motion_bonus
		
		# Target's visual signature (big things are more visible)
		sight_gain *= target_profile.visual_signature
		
		# Concealment reduces visual detection
		if target_in_concealment:
			sight_gain *= 0.3  # 70% reduction
		
		# Distance falloff — harder to see things far away
		var range_factor = 1.0 - (distance_cells / observer_profile.sight_range)
		range_factor = maxf(range_factor, 0.1)
		sight_gain *= range_factor
		
		gain = maxf(gain, sight_gain)
	
	# --- HEARING ---
	if distance_cells <= observer_profile.hearing_range:
		var noise = target_profile.noise_stationary
		if target_is_moving:
			noise = target_profile.noise_moving
		if target_is_firing:
			noise = maxf(noise, target_profile.noise_firing)
		
		var hearing_gain = observer_profile.hearing_rate * noise
		
		# Distance falloff — sound drops off
		var range_factor = 1.0 - (distance_cells / observer_profile.hearing_range)
		range_factor = maxf(range_factor, 0.05)
		hearing_gain *= range_factor
		
		# Hearing doesn't need LOS — can hear through walls
		# But walls do muffle: if no LOS, reduce hearing
		if not has_los:
			hearing_gain *= 0.5
		
		gain = maxf(gain, hearing_gain)
	
	# --- SEISMIC ---
	if observer_profile.seismic_range > 0 and target_profile.seismic_signature > 0:
		if distance_cells <= observer_profile.seismic_range:
			var seismic_gain = observer_profile.seismic_rate * target_profile.seismic_signature
			
			# Seismic ignores LOS entirely — goes through everything
			var range_factor = 1.0 - (distance_cells / observer_profile.seismic_range)
			range_factor = maxf(range_factor, 0.1)
			seismic_gain *= range_factor
			
			gain = maxf(gain, seismic_gain)
	
	# Scale by delta time
	gain *= delta
	
	# --- DECAY ---
	# If no stimulus at all, detection decays
	if gain < 0.001:
		var decay = 0.05 * delta  # lose 5% per second with no stimulus
		return -decay
	
	return gain


# --- Convenience: build profiles for known entity types ---

static func make_human_squad_observer() -> DetectionProfile:
	"""Standard human squad detection profile (as observer)."""
	var p = DetectionProfile.new()
	p.sight_range = 12.0
	p.sight_rate = 0.15
	p.sight_motion_bonus = 0.1
	p.hearing_range = 10.0
	p.hearing_rate = 0.04
	p.seismic_range = 3.0       # can feel very close heavy impacts
	p.seismic_rate = 0.1
	return p

static func make_human_squad_target() -> DetectionProfile:
	"""Standard human squad profile (as target — how detectable they are)."""
	var p = DetectionProfile.new()
	p.visual_signature = 1.0
	p.noise_moving = 1.0
	p.noise_stationary = 0.1
	p.noise_firing = 5.0
	p.seismic_signature = 0.0   # humans don't shake the ground
	return p

static func make_hound_observer() -> DetectionProfile:
	"""Hound detection profile (as observer — predator senses)."""
	var p = DetectionProfile.new()
	p.sight_range = 10.0        # decent but not amazing eyesight
	p.sight_rate = 0.12
	p.sight_motion_bonus = 0.15 # very motion-sensitive
	p.hearing_range = 20.0      # excellent hearing
	p.hearing_rate = 0.08
	p.seismic_range = 5.0       # feels footsteps nearby
	p.seismic_rate = 0.05
	return p

static func make_hound_target() -> DetectionProfile:
	"""Hound profile (as target — how detectable it is)."""
	var p = DetectionProfile.new()
	p.visual_signature = 0.8    # smaller than human squad, harder to spot
	p.noise_moving = 0.6        # quieter than humans when moving
	p.noise_stationary = 0.05   # very quiet when still
	p.noise_firing = 0.0        # doesn't shoot
	p.seismic_signature = 0.2   # light footfalls
	return p
