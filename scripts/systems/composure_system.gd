# composure_system.gd
# Pure static functions for composure calculations.
# No state, no side effects. Callers apply results to soldier data.
#
# Composure is a float 0-100. Higher = calmer.
# Thresholds divide it into 5 tiers that drive behavior:
#   BROKEN (< 20)    — won't fire, may flee
#   BREAKING (< 40)  — severely impaired
#   SHAKEN (< 60)    — noticeably worse
#   STEADY (< 80)    — normal combat effectiveness
#   CONFIDENT (>= 80) — slight bonus
#
# The sergeant-as-floor mechanic: a soldier's composure level
# can't drop below the leader's level. The NCO holds the line.
class_name ComposureSystem

enum Level { BROKEN, BREAKING, SHAKEN, STEADY, CONFIDENT }

# Threshold boundaries (composure_value must be >= threshold to reach level)
const THRESHOLD_BREAKING := 20.0
const THRESHOLD_SHAKEN := 40.0
const THRESHOLD_STEADY := 60.0
const THRESHOLD_CONFIDENT := 80.0

# Recovery and pressure rates
const BASE_RECOVERY_RATE := 2.0   # points/sec when not under fire
const UNDER_FIRE_RECOVERY := 0.5  # much slower recovery under fire

# --- Core Functions ---

static func get_level(composure_value: float) -> Level:
	"""Map a composure float (0-100) to a discrete Level."""
	if composure_value >= THRESHOLD_CONFIDENT:
		return Level.CONFIDENT
	elif composure_value >= THRESHOLD_STEADY:
		return Level.STEADY
	elif composure_value >= THRESHOLD_SHAKEN:
		return Level.SHAKEN
	elif composure_value >= THRESHOLD_BREAKING:
		return Level.BREAKING
	else:
		return Level.BROKEN

static func get_level_name(level: Level) -> String:
	"""Human-readable name for a composure level."""
	match level:
		Level.BROKEN: return "BROKEN"
		Level.BREAKING: return "BREAKING"
		Level.SHAKEN: return "SHAKEN"
		Level.STEADY: return "STEADY"
		Level.CONFIDENT: return "CONFIDENT"
	return "UNKNOWN"

# --- Composure Changes ---

static func apply_pressure(current: float, pressure: float, delta: float) -> float:
	"""Reduce composure by pressure * delta. Returns new value, clamped to 0."""
	return maxf(current - pressure * delta, 0.0)

static func apply_recovery(current: float, under_fire: bool, delta: float) -> float:
	"""Recover composure over time. Slower when under fire. Capped at 100."""
	var rate := UNDER_FIRE_RECOVERY if under_fire else BASE_RECOVERY_RATE
	return minf(current + rate * delta, 100.0)

static func apply_sergeant_floor(soldier_value: float, leader_value: float) -> float:
	"""A soldier's composure level can't drop below the leader's level.
	The NCO holds the line — their presence sets the minimum tier.
	Returns the soldier's composure, potentially raised to the leader's tier floor."""
	var leader_level: Level = get_level(leader_value)
	var soldier_level: Level = get_level(soldier_value)

	# If soldier is already at or above leader's level, no change
	if soldier_level >= leader_level:
		return soldier_value

	# Raise soldier to the floor of the leader's tier
	var floor_value: float = _get_tier_floor(leader_level)
	return maxf(soldier_value, floor_value)

# --- Combat Modifiers ---

static func get_accuracy_modifier(level: Level) -> int:
	"""d100 modifier for hit chance. Passed to combat_resolver."""
	match level:
		Level.BROKEN: return -50    # shouldn't be firing, but just in case
		Level.BREAKING: return -30
		Level.SHAKEN: return -15
		Level.STEADY: return 0
		Level.CONFIDENT: return 5
	return 0

static func get_fire_rate_modifier(level: Level) -> float:
	"""Multiplier on fire interval. >1.0 = slower, <1.0 = faster."""
	match level:
		Level.BROKEN: return 99.0   # effectively can't fire
		Level.BREAKING: return 2.0  # very slow, hesitant
		Level.SHAKEN: return 1.4    # noticeably slower
		Level.STEADY: return 1.0    # baseline
		Level.CONFIDENT: return 0.9 # slightly faster
	return 1.0

static func can_fire(level: Level) -> bool:
	"""Can a soldier at this composure level fire their weapon?"""
	return level != Level.BROKEN

# --- Legacy Bridge ---
# combat_resolver.gd uses int composure: 0=steady, 1=shaken, 2=panicked
# This maps our Level enum to that system without rewriting the resolver.

static func to_legacy_composure(level: Level) -> int:
	"""Map Level to combat_resolver's int system (0=steady, 1=shaken, 2=panicked)."""
	match level:
		Level.CONFIDENT, Level.STEADY:
			return 0  # steady
		Level.SHAKEN:
			return 1  # shaken
		Level.BREAKING, Level.BROKEN:
			return 2  # panicked
	return 0

# --- Internal ---

static func _get_tier_floor(level: Level) -> float:
	"""Get the minimum composure_value for a given tier."""
	match level:
		Level.BROKEN: return 0.0
		Level.BREAKING: return THRESHOLD_BREAKING
		Level.SHAKEN: return THRESHOLD_SHAKEN
		Level.STEADY: return THRESHOLD_STEADY
		Level.CONFIDENT: return THRESHOLD_CONFIDENT
	return 0.0
