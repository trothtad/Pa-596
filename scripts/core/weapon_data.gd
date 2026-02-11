# weapon_data.gd
# Describes a weapon type: fire rate, accuracy profile, penetration
# This is a data class, not a node. Create instances for each weapon type.
# Usage: var wd = preload(...).new()  then wd.lee_enfield() etc.
extends RefCounted

var weapon_name := "Unknown"
var rpm := 10.0            # rounds per minute (Lee Enfield ~10 aimed)
var base_accuracy := 65    # base hit chance at optimal range (d100 roll-under)
var pen := 1               # penetration tier: 0=pistol, 1=rifle, 2=AT weapon, 3=heavy AT
var ammo_capacity := 10    # magazine/clip size
var noise_radius := 15     # detection radius in cells when fired

# Range profile (in cells, 1 cell = ~4m)
var optimal_range := 8     # ~32m - no range penalty inside this
var max_range := 40        # ~160m - can't fire beyond this

func _init(p_name: String = "Unknown") -> void:
	weapon_name = p_name

func get_fire_interval() -> float:
	"""Seconds between shots."""
	return 60.0 / rpm

func get_range_modifier(distance_cells: int) -> int:
	"""Returns accuracy modifier (negative) based on range."""
	if distance_cells <= optimal_range:
		return 0
	if distance_cells > max_range:
		return -100  # can't fire
	var range_fraction := float(distance_cells - optimal_range) / float(max_range - optimal_range)
	return int(-50.0 * range_fraction)

# --- Factory methods ---
# These return NEW WeaponData instances configured for each weapon type.
# Call on any instance: var rifle = WeaponData.new().lee_enfield()
# Or via preloaded script: var WD = preload(...); var rifle = WD.new().lee_enfield()

func lee_enfield() -> RefCounted:
	var w = get_script().new("Lee-Enfield No.4")
	w.rpm = 10.0
	w.base_accuracy = 65
	w.pen = 1
	w.ammo_capacity = 10
	w.noise_radius = 15
	w.optimal_range = 10   # ~40m
	w.max_range = 50       # ~200m
	return w

func bren_gun() -> RefCounted:
	var w = get_script().new("Bren Gun")
	w.rpm = 30.0
	w.base_accuracy = 50
	w.pen = 1
	w.ammo_capacity = 30
	w.noise_radius = 18
	w.optimal_range = 8
	w.max_range = 40
	return w

func sten_gun() -> RefCounted:
	var w = get_script().new("Sten Mk.V")
	w.rpm = 40.0
	w.base_accuracy = 40
	w.pen = 0
	w.ammo_capacity = 32
	w.noise_radius = 12
	w.optimal_range = 4
	w.max_range = 15
	return w
