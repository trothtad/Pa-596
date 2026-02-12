# fire_control.gd
# Pure static functions for fire control decisions.
# No state, no side effects. Squad.gd calls these each tick.
#
# Doctrine controls how aggressively soldiers engage:
#   HOLD_FIRE  — never fire (stealth, ambush setup)
#   DEFENSIVE  — fire only at TRACKED targets in range (conservative)
#   AGGRESSIVE — fire at IDENTIFIED+ targets (standard combat)
#   AMBUSH     — like AGGRESSIVE but faster first shot
#
# The player sets doctrine per squad. Soldiers fire autonomously
# within doctrine constraints — Close Combat style.
class_name FireControl

enum Doctrine { HOLD_FIRE, DEFENSIVE, AGGRESSIVE, AMBUSH }

# Detection labels that qualify as "engageable" per doctrine
const ENGAGE_LABELS_DEFENSIVE: Array[String] = ["TRACKED"]
const ENGAGE_LABELS_AGGRESSIVE: Array[String] = ["IDENTIFIED", "TRACKED"]
const ENGAGE_LABELS_AMBUSH: Array[String] = ["IDENTIFIED", "TRACKED"]

# --- Core Functions ---

static func should_engage(
	doctrine: Doctrine,
	detection_label: String,
	distance_cells: int,
	weapon_max_range: int
) -> bool:
	"""Can this soldier engage a target given doctrine, detection, and range?"""
	if doctrine == Doctrine.HOLD_FIRE:
		return false

	# Range check first — no point checking doctrine if out of range
	if distance_cells > weapon_max_range:
		return false

	# Doctrine determines minimum detection level to engage
	var required_labels: Array[String]
	match doctrine:
		Doctrine.DEFENSIVE:
			required_labels = ENGAGE_LABELS_DEFENSIVE
		Doctrine.AGGRESSIVE, Doctrine.AMBUSH:
			required_labels = ENGAGE_LABELS_AGGRESSIVE
		_:
			return false

	return detection_label in required_labels

static func select_target(
	detected_hostiles: Dictionary,  # hostile_id → { pos, level, label, hostile }
	squad_grid: Vector2i,
	doctrine: Doctrine
) -> Dictionary:
	"""Pick the best target from detected hostiles. Returns { hostile, distance, detection_label } or empty dict.
	detected_hostiles comes from battle_map.detected_hostile_positions."""
	if doctrine == Doctrine.HOLD_FIRE:
		return {}

	var best: Dictionary = {}
	var best_distance := INF

	for hostile_id in detected_hostiles:
		var info: Dictionary = detected_hostiles[hostile_id]
		var label: String = info.get("label", "UNAWARE")
		var hostile = info.get("hostile")

		if hostile == null:
			continue

		# Skip dead hostiles
		if hostile.get("is_dead"):
			continue

		# Check if detection level meets doctrine requirements
		var engageable := false
		match doctrine:
			Doctrine.DEFENSIVE:
				engageable = label in ENGAGE_LABELS_DEFENSIVE
			Doctrine.AGGRESSIVE, Doctrine.AMBUSH:
				engageable = label in ENGAGE_LABELS_AGGRESSIVE

		if not engageable:
			continue

		# Distance from squad
		var hostile_grid: Vector2i = hostile.grid_pos
		var dist: float = squad_grid.distance_to(Vector2(hostile_grid))

		if dist < best_distance:
			best_distance = dist
			best = {
				"hostile": hostile,
				"distance": int(dist),
				"detection_label": label,
			}

	return best

static func get_fire_cooldown(doctrine: Doctrine, base_interval: float) -> float:
	"""Modify fire interval based on doctrine. Returns adjusted interval in seconds."""
	match doctrine:
		Doctrine.HOLD_FIRE:
			return INF  # never fire
		Doctrine.DEFENSIVE:
			return base_interval * 1.5  # conservative, slower fire
		Doctrine.AGGRESSIVE:
			return base_interval  # standard rate
		Doctrine.AMBUSH:
			return base_interval * 0.7  # snap-fire, faster initial engagement
	return base_interval

static func get_doctrine_name(doctrine: Doctrine) -> String:
	"""Human-readable name for UI display."""
	match doctrine:
		Doctrine.HOLD_FIRE: return "HOLD FIRE"
		Doctrine.DEFENSIVE: return "DEFENSIVE"
		Doctrine.AGGRESSIVE: return "AGGRESSIVE"
		Doctrine.AMBUSH: return "AMBUSH"
	return "UNKNOWN"
