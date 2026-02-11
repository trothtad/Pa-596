extends Node
## The heartbeat of the simulation.
## All game systems connect to TickManager.tick and process their logic
## per tick, not per frame. This enables speed control, clean pause,
## and deterministic replay.

signal tick(tick_number: int)
signal speed_changed(new_speed: float)

const BASE_TICKS_PER_SECOND := 10

var current_tick: int = 0
var game_speed: float = 1.0
var paused: bool = false

var _tick_accumulator: float = 0.0

func _process(delta: float) -> void:
	if paused:
		return

	_tick_accumulator += delta * game_speed * BASE_TICKS_PER_SECOND

	while _tick_accumulator >= 1.0:
		_tick_accumulator -= 1.0
		current_tick += 1
		tick.emit(current_tick)

func set_speed(speed: float) -> void:
	game_speed = clampf(speed, 0.0, 4.0)
	speed_changed.emit(game_speed)

func pause() -> void:
	paused = true

func unpause() -> void:
	paused = false

func toggle_pause() -> void:
	paused = not paused
