class_name CombatMath
## Pure functions for combat calculations. No state, no side effects.
## Given the same inputs, returns the same outputs. The caller decides
## what to do with the results.

# === HIT CALCULATION ===

static func calculate_hit_chance(
	attacker_skill: int,
	weapon_accuracy: float,
	range_m: float,
	effective_range: float,
	target_cover: int,
	target_moving: bool,
	attacker_moving: bool,
	suppression: float = 0.0
) -> float:
	# Base chance from skill (0-100 -> 0.0-1.0)
	var base := attacker_skill / 100.0

	# Weapon accuracy multiplier
	base *= weapon_accuracy

	# Range penalty (linear falloff past effective range)
	if range_m > effective_range:
		var overshoot := (range_m - effective_range) / effective_range
		base *= maxf(0.1, 1.0 - overshoot * 0.5)

	# Cover penalty (-10% per cover level)
	base -= target_cover * 0.10

	# Movement penalties
	if target_moving:
		base *= 0.7
	if attacker_moving:
		base *= 0.5

	# Suppression penalty
	base *= (1.0 - suppression * 0.5)

	return clampf(base, 0.001, 0.90)  # Always 0.1% floor, 90% ceiling

# === DAMAGE CALCULATION ===

static func calculate_damage(
	base_damage: int,
	penetration: int,
	target_armor: int,
	range_m: float,
	maximum_range: float
) -> int:
	# Armor reduces damage
	var effective_pen := penetration - target_armor
	var armor_mult := clampf(0.5 + effective_pen * 0.1, 0.1, 1.5)

	# Range falloff (damage drops at extreme range)
	var range_mult := 1.0
	if range_m > maximum_range * 0.7:
		range_mult = lerpf(1.0, 0.5, (range_m - maximum_range * 0.7) / (maximum_range * 0.3))

	return int(base_damage * armor_mult * range_mult)

# === UTILITY ===

static func roll_d100() -> int:
	return randi_range(1, 100)

static func roll_hit(hit_chance: float) -> bool:
	return randf() < hit_chance
