# combat_resolver.gd
# Pure functions for resolving combat. No side effects.
# Call these from squad/hound systems and apply results there.
# Usage: var resolver = preload(...).new()  then resolver.resolve_full_shot(...)
extends RefCounted

# --- Constants ---

const MIN_HIT_CHANCE := 5    # always a small chance
const MAX_HIT_CHANCE := 95   # never guaranteed

# Cover modifiers (negative = harder to hit)
const COVER_NONE := 0
const COVER_LIGHT := -20      # bushes, low wall, thin wood
const COVER_HEAVY := -40      # solid wall, trench, thick stone

# State modifiers
const MOD_TARGET_MOVING := -15
const MOD_SHOOTER_SHAKEN := -15
const MOD_SHOOTER_PANICKED := -30
const MOD_SHOOTER_SUPPRESSED := -20
const MOD_SHOOTER_MOVING := -40  # snap shot, awful

# Wound roll thresholds (d100, roll on penetrating hit vs soldiers)
const WOUND_LIGHT_MAX := 30       # 01-30
const WOUND_SERIOUS_MAX := 65     # 31-65
const WOUND_CRITICAL_MAX := 90    # 66-90
# 91-100 = killed

# --- Shot resolution ---

func calculate_hit_chance(
	base_accuracy: int,
	range_modifier: int,
	cover_modifier: int,
	target_moving: bool,
	shooter_moving: bool,
	shooter_composure: int,  # 0=steady, 1=shaken, 2=panicked
	shooter_suppressed: bool,
	fatigue_modifier: int    # 0 to -15 typically
) -> int:
	"""Calculate final hit chance. Returns clamped d100 target number."""
	var chance := base_accuracy + range_modifier + cover_modifier + fatigue_modifier
	
	if target_moving:
		chance += MOD_TARGET_MOVING
	if shooter_moving:
		chance += MOD_SHOOTER_MOVING
	if shooter_suppressed:
		chance += MOD_SHOOTER_SUPPRESSED
	
	match shooter_composure:
		1: chance += MOD_SHOOTER_SHAKEN
		2: chance += MOD_SHOOTER_PANICKED
	
	return clampi(chance, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

func resolve_shot(hit_chance: int) -> bool:
	"""Roll d100 against hit_chance. Returns true if hit."""
	var roll := randi_range(1, 100)
	return roll <= hit_chance

func check_penetration(weapon_pen: int, target_armor: int) -> bool:
	"""Can this weapon penetrate this armor?
	pen >= armor: always penetrates
	pen == armor - 1: 70% chance (marginal)
	pen < armor - 1: no penetration"""
	if weapon_pen >= target_armor:
		return true
	if weapon_pen == target_armor - 1:
		return randi_range(1, 100) <= 70
	return false

func roll_wound_severity() -> int:
	"""Roll wound severity on a penetrating hit vs a soldier.
	Returns: 1=light, 2=serious, 3=critical, 4=killed"""
	var roll := randi_range(1, 100)
	if roll <= WOUND_LIGHT_MAX:
		return 1
	elif roll <= WOUND_SERIOUS_MAX:
		return 2
	elif roll <= WOUND_CRITICAL_MAX:
		return 3
	else:
		return 4

# --- Full shot sequence (convenience) ---

func resolve_full_shot(
	weapon,  # WeaponData instance
	base_accuracy: int,
	distance_cells: int,
	cover_modifier: int,
	target_moving: bool,
	target_armor: int,
	target_is_soldier: bool,
	shooter_moving: bool,
	shooter_composure: int,
	shooter_suppressed: bool,
	fatigue_modifier: int
) -> Dictionary:
	"""Resolve a complete shot. Returns result dictionary."""
	var result := {
		"can_fire": true,
		"hit": false,
		"hit_chance": 0,
		"penetrated": false,
		"wound": 0,
		"suppression_generated": 0.0,
	}
	
	# Range check
	if distance_cells > weapon.max_range:
		result["can_fire"] = false
		return result
	
	# Calculate and roll to hit
	var range_mod: int = weapon.get_range_modifier(distance_cells)
	var hit_chance := calculate_hit_chance(
		base_accuracy, range_mod, cover_modifier,
		target_moving, shooter_moving,
		shooter_composure, shooter_suppressed, fatigue_modifier
	)
	result["hit_chance"] = hit_chance
	
	var hit := resolve_shot(hit_chance)
	result["hit"] = hit
	
	if hit:
		var penetrated := check_penetration(weapon.pen, target_armor)
		result["penetrated"] = penetrated
		
		if penetrated and target_is_soldier:
			result["wound"] = roll_wound_severity()
		
		result["suppression_generated"] = 0.15 if target_is_soldier else 0.05
	else:
		# Miss generates suppression vs soldiers only (kaiju don't flinch)
		result["suppression_generated"] = 0.08 if target_is_soldier else 0.0
	
	return result
