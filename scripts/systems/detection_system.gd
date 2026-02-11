class_name DetectionSystem
## Pure functions for detection calculations. No state, no side effects.
## Both sides (squads detecting hounds, hounds detecting squads) use
## these same functions with different profiles.

enum AwarenessLevel { UNAWARE, SUSPECTED, DETECTED, IDENTIFIED, TRACKED }

const AWARENESS_THRESHOLDS := {
	AwarenessLevel.SUSPECTED: 0.2,
	AwarenessLevel.DETECTED: 0.4,
	AwarenessLevel.IDENTIFIED: 0.6,
	AwarenessLevel.TRACKED: 0.8
}

# Hysteresis buffer to prevent state thrashing at thresholds
const HYSTERESIS_BUFFER := 0.05

# === DETECTION VALUE CALCULATION ===

static func calculate_detection_gain(
	observer_profile: Dictionary,  # sight_range, hearing_range, etc.
	target_profile: Dictionary,    # visual_signature, noise_signature, etc.
	distance: float,
	has_los: bool,
	target_moving: bool,
	terrain_concealment: float,
	delta_ticks: int = 1
) -> float:
	var total_gain := 0.0

	# Visual detection (requires LOS)
	if has_los:
		var sight_range: float = observer_profile.get("sight_range", 300)
		var visual_sig: float = target_profile.get("visual_signature", 1.0)

		if distance < sight_range:
			var visual_factor := (1.0 - distance / sight_range) * visual_sig
			visual_factor *= (1.0 - terrain_concealment)
			if target_moving:
				visual_factor *= 1.5  # Movement easier to spot
			total_gain += visual_factor * 0.1

	# Auditory detection (no LOS required)
	var hearing_range: float = observer_profile.get("hearing_range", 200)
	var noise_sig: float = target_profile.get("noise_signature", 1.0)

	if distance < hearing_range and target_moving:
		var audio_factor := (1.0 - distance / hearing_range) * noise_sig
		total_gain += audio_factor * 0.05

	# Seismic detection (for large entities)
	var seismic_range: float = observer_profile.get("seismic_range", 0)
	var seismic_sig: float = target_profile.get("seismic_signature", 0)

	if seismic_range > 0 and seismic_sig > 0 and distance < seismic_range:
		var seismic_factor := (1.0 - distance / seismic_range) * seismic_sig
		if target_moving:
			seismic_factor *= 2.0
		total_gain += seismic_factor * 0.08

	return total_gain * delta_ticks

static func calculate_detection_decay(
	current_value: float,
	delta_ticks: int = 1
) -> float:
	# Decay rate: lose 2% per tick when not detecting
	return current_value * pow(0.98, delta_ticks)

# === AWARENESS LEVEL ===

static func get_awareness_level(
	detection_value: float,
	previous_level: AwarenessLevel
) -> AwarenessLevel:
	# Check from highest to lowest, with hysteresis
	for level in [AwarenessLevel.TRACKED, AwarenessLevel.IDENTIFIED,
				  AwarenessLevel.DETECTED, AwarenessLevel.SUSPECTED]:
		var threshold: float = AWARENESS_THRESHOLDS[level]

		# If we're already at or above this level, use lower threshold (hysteresis)
		if previous_level >= level:
			if detection_value >= threshold - HYSTERESIS_BUFFER:
				return level
		else:
			# Rising: need to exceed threshold
			if detection_value >= threshold:
				return level

	return AwarenessLevel.UNAWARE
