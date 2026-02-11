# Pā 596 — Architecture Specification

*Version 0.1 — February 2026*

---

## 1. Core Philosophy

### 1.1 Data-Driven Design

All game entities are defined by data, not code. Systems read from databases and apply logic. This enables:
- Moddability (change JSON, change behavior)
- Debugging (inspect data state, not code flow)
- Iteration (tweak values without recompiling)

**Principle:** If you can put it in a table, put it in a table.

### 1.2 Pure Functions Where Possible

Combat math, detection calculations, pathfinding queries — these are *pure functions*. Given the same inputs, they return the same outputs. No side effects, no hidden state.

**Example:** `CombatMath.calculate_hit_chance(attacker, target, range, conditions) -> float`

The function doesn't modify anything. It returns a number. The *caller* decides what to do with that number.

### 1.3 Tick-Based Simulation

All game time flows through a global tick system. One "tick" is the atomic unit of game time.

**Default:** 10 ticks per second at 1x speed

This enables:
- Speed control (2x = 20 ticks/sec, 0.5x = 5 ticks/sec)
- Clean pause (tick_rate = 0)
- Deterministic replay (record inputs, replay ticks)
- State inspection between ticks

**Rule:** Nothing happens "continuously." Everything happens "per tick."

### 1.4 Entities as Scene Nodes

Entities (squads, soldiers, hounds) are **Node2D children in the scene tree**, not manually drawn shapes. This gives us:
- Z-sorting for free
- Individual visibility toggling
- Godot's signal system per-entity
- Future sprite/animation/particle support
- Click detection via input events

**Custom `_draw()` is reserved for:**
- Terrain rendering (genuinely good for tile grids)
- Fog of war overlay
- Debug visualizations (paths, detection radii)

**Not for:** Entity sprites, health bars, selection highlights. Those live on the entity nodes.

### 1.5 Separation of Concerns

Inspired by Close Combat's folder structure:
- **DATA** layer: Pure information (what things *are*)
- **SYSTEMS** layer: Pure logic (how things *behave*)  
- **ENTITIES** layer: State + identity (instances in the world)
- **MANAGERS** layer: Orchestration (lifecycle, events, rendering)

A system should not know about rendering.  
A renderer should not know about combat math.  
An entity should not calculate its own hit chance.

---

## 2. Directory Structure

```
pa-596/
├── assets/                     # Graphics, audio, fonts
│   ├── sprites/
│   ├── tiles/
│   └── audio/
│
├── data/                       # JSON databases (NEW)
│   ├── base/                   # Core game data
│   │   ├── weapons.json
│   │   ├── soldiers.json
│   │   ├── squads.json
│   │   └── hostiles.json
│   ├── terrain/                # Terrain type definitions
│   │   └── terrain_types.json
│   └── effects/                # Status effects, environmental
│       └── effects.json
│
├── docs/                       # Design documents
│
├── resources/                  # Godot resources (.tres, textures)
│   └── terrain/
│
├── scenes/                     # Godot scenes
│   ├── main.tscn
│   ├── battle/                 # Battle-specific scenes (NEW)
│   └── editor/                 # Map editor scenes (NEW)
│
└── scripts/
    ├── autoloads/              # Global singletons (NEW)
    │   ├── game_state.gd
    │   ├── tick_manager.gd
    │   └── database.gd
    │
    ├── data/                   # Data classes (NEW)
    │   ├── weapon_stats.gd     # Parses weapons.json
    │   ├── soldier_template.gd # Parses soldiers.json  
    │   ├── squad_template.gd   # Parses squads.json
    │   └── hostile_template.gd # Parses hostiles.json
    │
    ├── systems/                # Pure logic systems (NEW)
    │   ├── combat_math.gd      # Hit/damage calculations
    │   ├── detection_system.gd # Detection logic (refactored)
    │   ├── terrain_query.gd    # LOS, cover, pathfinding queries
    │   └── morale_system.gd    # Morale calculations (future)
    │
    ├── ai/                     # AI behavior (NEW)
    │   ├── hound_brain.gd      # Hound state machine
    │   └── states/             # Individual state scripts
    │       ├── idle_state.gd
    │       ├── patrol_state.gd
    │       ├── stalk_state.gd
    │       ├── chase_state.gd
    │       └── attack_state.gd
    │
    ├── entities/               # Game objects (RENAMED from core)
    │   ├── squad.gd
    │   ├── soldier.gd
    │   ├── hound.gd
    │   └── projectile.gd       # (future)
    │
    ├── managers/               # Orchestration (NEW)
    │   ├── battle_manager.gd   # Entity lifecycle, tick distribution
    │   ├── render_manager.gd   # All drawing
    │   └── input_manager.gd    # All input handling
    │
    └── tools/                  # Editor tools (NEW)
        └── terrain_editor.gd
```

---

## 3. Database Definitions

### 3.1 Weapons Database (`data/base/weapons.json`)

```json
{
  "lee_enfield": {
    "display_name": "Lee-Enfield No.4 Mk I",
    "type": "rifle",
    "caliber": "7.7mm",
    "magazine_size": 10,
    "rate_of_fire": 0.5,
    "base_accuracy": 0.7,
    "effective_range": 500,
    "maximum_range": 800,
    "damage": {
      "base": 45,
      "penetration": 12
    },
    "noise_radius": 200,
    "weight_kg": 4.1
  },
  "sten_mkii": {
    "display_name": "Sten Mk II",
    "type": "smg",
    "caliber": "9mm",
    "magazine_size": 32,
    "rate_of_fire": 8.3,
    "base_accuracy": 0.4,
    "effective_range": 100,
    "maximum_range": 200,
    "damage": {
      "base": 28,
      "penetration": 6
    },
    "noise_radius": 150,
    "weight_kg": 3.2
  },
  "bren_lmg": {
    "display_name": "Bren Light Machine Gun",
    "type": "lmg",
    "caliber": "7.7mm",
    "magazine_size": 30,
    "rate_of_fire": 8.3,
    "base_accuracy": 0.55,
    "effective_range": 600,
    "maximum_range": 1000,
    "damage": {
      "base": 48,
      "penetration": 14
    },
    "noise_radius": 250,
    "suppression_factor": 1.5,
    "weight_kg": 10.0,
    "requires_setup": true
  }
}
```

### 3.2 Soldiers Database (`data/base/soldiers.json`)

```json
{
  "rifleman_base": {
    "display_name": "Rifleman",
    "role": "rifleman",
    "primary_weapon": "lee_enfield",
    "secondary_weapon": null,
    "grenades": 2,
    "base_stats": {
      "marksmanship": 50,
      "fitness": 50,
      "morale": 50,
      "experience": 0
    },
    "detection_profile": {
      "visual_signature": 1.0,
      "thermal_signature": 1.0,
      "noise_signature": 1.0,
      "seismic_signature": 0.3
    }
  },
  "nco_base": {
    "display_name": "Corporal",
    "role": "nco",
    "primary_weapon": "sten_mkii",
    "secondary_weapon": null,
    "grenades": 2,
    "base_stats": {
      "marksmanship": 55,
      "fitness": 55,
      "morale": 60,
      "experience": 20,
      "leadership": 40
    },
    "detection_profile": {
      "visual_signature": 1.0,
      "thermal_signature": 1.0,
      "noise_signature": 1.2,
      "seismic_signature": 0.3
    }
  },
  "gunner_base": {
    "display_name": "Gunner",
    "role": "support",
    "primary_weapon": "bren_lmg",
    "secondary_weapon": "webley_revolver",
    "grenades": 1,
    "base_stats": {
      "marksmanship": 50,
      "fitness": 60,
      "morale": 50,
      "experience": 10
    },
    "detection_profile": {
      "visual_signature": 1.2,
      "thermal_signature": 1.0,
      "noise_signature": 1.0,
      "seismic_signature": 0.4
    }
  }
}
```

### 3.3 Squads Database (`data/base/squads.json`)

```json
{
  "british_rifle_section": {
    "display_name": "Rifle Section",
    "nation": "uk",
    "composition": [
      {"template": "nco_base", "count": 1, "is_leader": true},
      {"template": "gunner_base", "count": 1},
      {"template": "rifleman_base", "count": 6}
    ],
    "formation": {
      "default": "line",
      "spacing": 32
    },
    "base_morale": 60,
    "training_level": "regular"
  },
  "british_scout_section": {
    "display_name": "Scout Section",
    "nation": "uk",
    "composition": [
      {"template": "nco_base", "count": 1, "is_leader": true},
      {"template": "rifleman_base", "count": 3}
    ],
    "formation": {
      "default": "wedge",
      "spacing": 48
    },
    "base_morale": 70,
    "training_level": "veteran",
    "special_rules": ["stealth_bonus"]
  }
}
```

### 3.4 Hostiles Database (`data/base/hostiles.json`)

```json
{
  "hound_alpha": {
    "display_name": "Hellhound",
    "class": "hound",
    "subtype": "hellhound",
    "stats": {
      "max_health": 4,
      "armor": 0,
      "speed": 80,
      "charge_speed": 160
    },
    "detection": {
      "sight_range": 300,
      "hearing_range": 200,
      "seismic_range": 150,
      "smell_range": 100
    },
    "attack": {
      "melee_damage": 35,
      "melee_range": 32,
      "attack_cooldown": 1.5
    },
    "behavior": {
      "aggression": 0.7,
      "pack_tendency": 0.8,
      "flee_threshold": 0.25
    },
    "detection_profile": {
      "visual_signature": 1.5,
      "thermal_signature": 2.0,
      "noise_signature": 0.5,
      "seismic_signature": 0.8
    }
  },
  "headman": {
    "display_name": "headman",
    "class": "hound",
    "subtype": "headman",
    "stats": {
      "max_health": 3,
      "armor": 1,
      "speed": 120,
      "charge_speed": 200
    },
    "detection": {
      "sight_range": 150,
      "hearing_range": 400,
      "seismic_range": 50,
      "smell_range": 300
    },
    "attack": {
      "melee_damage": 100,
      "melee_range": 24,
      "attack_cooldown": 3.0,
      "special": "decapitate"
    },
    "behavior": {
      "aggression": 0.5,
      "pack_tendency": 0.1,
      "flee_threshold": 0.5,
      "prefers_isolated": true
    },
    "detection_profile": {
      "visual_signature": 0.6,
      "thermal_signature": 0.8,
      "noise_signature": 0.1,
      "seismic_signature": 0.2
    }
  }
}
```

### 3.5 Terrain Types (`data/terrain/terrain_types.json`)

```json
{
  "open": {
    "display_name": "Open Ground",
    "movement_cost": 1.0,
    "cover_value": 0,
    "concealment": 0,
    "blocks_los": false,
    "passable": true,
    "color": "#4a7c30"
  },
  "road": {
    "display_name": "Road",
    "movement_cost": 0.7,
    "cover_value": 0,
    "concealment": 0,
    "blocks_los": false,
    "passable": true,
    "color": "#8b7355"
  },
  "rough": {
    "display_name": "Rough Ground",
    "movement_cost": 1.5,
    "cover_value": 1,
    "concealment": 0.2,
    "blocks_los": false,
    "passable": true,
    "color": "#6b5344"
  },
  "forest": {
    "display_name": "Forest",
    "movement_cost": 2.0,
    "cover_value": 2,
    "concealment": 0.6,
    "blocks_los": false,
    "los_penalty": 0.5,
    "passable": true,
    "color": "#2d5016"
  },
  "building": {
    "display_name": "Building",
    "movement_cost": 999,
    "cover_value": 4,
    "concealment": 1.0,
    "blocks_los": true,
    "passable": false,
    "color": "#555555"
  },
  "water": {
    "display_name": "Water",
    "movement_cost": 999,
    "cover_value": 0,
    "concealment": 0,
    "blocks_los": false,
    "passable": false,
    "passable_amphibious": true,
    "color": "#3366aa"
  },
  "rubble": {
    "inherits": "rough",
    "display_name": "Rubble",
    "cover_value": 2,
    "concealment": 0.3,
    "color": "#666655",
    "_comment": "Destroyed buildings become this"
  },
  "crater": {
    "inherits": "rough",
    "display_name": "Shell Crater",
    "movement_cost": 1.8,
    "cover_value": 3,
    "concealment": 0.4,
    "color": "#4a4a3a",
    "_comment": "Artillery/explosion damage creates this"
  }
}
```

**Note on Inheritance:** Terrain types can inherit from a base type using the `inherits` key. The loader merges the parent's properties with the child's overrides. This enables persistent battlefield damage without hand-authoring every damage state:
- Building → Rubble
- Open → Crater
- Forest → Burning Forest → Scorched Ground

---

## 4. System Specifications

### 4.1 Tick Manager (`scripts/autoloads/tick_manager.gd`)

The heartbeat of the simulation.

```gdscript
extends Node

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
```

**Usage:** All game systems connect to `TickManager.tick` and process their logic per tick, not per frame.

### 4.2 Database Manager (`scripts/autoloads/database.gd`)

Central access point for all JSON data.

```gdscript
extends Node

var weapons: Dictionary = {}
var soldiers: Dictionary = {}
var squads: Dictionary = {}
var hostiles: Dictionary = {}
var terrain_types: Dictionary = {}

func _ready() -> void:
    _load_all()

func _load_all() -> void:
    weapons = _load_json("res://data/base/weapons.json")
    soldiers = _load_json("res://data/base/soldiers.json")
    squads = _load_json("res://data/base/squads.json")
    hostiles = _load_json("res://data/base/hostiles.json")
    terrain_types = _load_json("res://data/terrain/terrain_types.json")

func _load_json(path: String, schema: Dictionary = {}) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Database file not found: " + path)
        return {}
    
    var file := FileAccess.open(path, FileAccess.READ)
    var json := JSON.new()
    var error := json.parse(file.get_as_text())
    
    if error != OK:
        push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
        return {}
    
    var data: Dictionary = json.data
    
    # Validate against schema if provided
    if not schema.is_empty():
        _validate_schema(path, data, schema)
    
    return data

func _validate_schema(path: String, data: Dictionary, schema: Dictionary) -> void:
    for entry_id in data:
        var entry: Dictionary = data[entry_id]
        for required_key in schema.get("required", []):
            if not entry.has(required_key):
                push_error("SCHEMA ERROR in %s: '%s' missing required key '%s'" % [path, entry_id, required_key])
        for key in entry:
            if schema.has("known_keys") and key not in schema.known_keys:
                push_warning("SCHEMA WARNING in %s: '%s' has unknown key '%s' (typo?)" % [path, entry_id, key])

# === LOOKUP FUNCTIONS ===

func get_weapon(weapon_id: String) -> Dictionary:
    return weapons.get(weapon_id, {})

func get_soldier_template(template_id: String) -> Dictionary:
    return soldiers.get(template_id, {})

func get_squad_template(template_id: String) -> Dictionary:
    return squads.get(template_id, {})

func get_hostile_template(template_id: String) -> Dictionary:
    return hostiles.get(template_id, {})

func get_terrain_type(type_id: String) -> Dictionary:
    return terrain_types.get(type_id, terrain_types.get("open", {}))
```

### 4.3 Combat Math (`scripts/systems/combat_math.gd`)

Pure functions. No state. No side effects.

```gdscript
class_name CombatMath

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
```

### 4.4 Detection System (`scripts/systems/detection_system.gd`)

Refactored from existing `detection.gd`. Pure logic, no entity references.

```gdscript
class_name DetectionSystem

enum AwarenessLevel { UNAWARE, SUSPECTED, DETECTED, IDENTIFIED, TRACKED }

const AWARENESS_THRESHOLDS := {
    AwarenessLevel.SUSPECTED: 0.2,
    AwarenessLevel.DETECTED: 0.4,
    AwarenessLevel.IDENTIFIED: 0.6,
    AwarenessLevel.TRACKED: 0.8
}

# Hysteresis buffer to prevent state thrashing
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
```

### 4.5 AI System — Hound Brain (`scripts/ai/hound_brain.gd`)

State machine with transition cooldowns to prevent thrashing.

```gdscript
class_name HoundBrain
extends RefCounted

enum State { IDLE, PATROL, SEARCH, STALK, CHASE, ATTACK, FLEE }

const STATE_COOLDOWNS := {
    State.IDLE: 5,      # 0.5 seconds at 10 ticks/sec
    State.PATROL: 10,
    State.SEARCH: 20,
    State.STALK: 10,
    State.CHASE: 5,
    State.ATTACK: 0,    # No cooldown on attack
    State.FLEE: 30
}

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var state_timer: int = 0
var cooldown_timer: int = 0

var target_entity_id: int = -1    # Entity ID, not Node reference (avoids dangling refs)
var target_position: Vector2 = Vector2.ZERO
var detection_value: float = 0.0

# Called by BattleManager each tick
func process_tick(hound: Node2D, context: Dictionary) -> Dictionary:
    state_timer += 1
    
    if cooldown_timer > 0:
        cooldown_timer -= 1
    
    # Update detection from context
    detection_value = context.get("highest_detection", 0.0)
    target_entity = context.get("detected_target", null)
    
    # Evaluate state transitions
    var new_state := _evaluate_transitions(hound, context)
    
    if new_state != current_state and cooldown_timer <= 0:
        _transition_to(new_state)
    
    # Execute current state behavior
    return _execute_state(hound, context)

func _evaluate_transitions(hound: Node2D, context: Dictionary) -> State:
    var health_ratio: float = context.get("health_ratio", 1.0)
    var distance_to_target: float = context.get("distance_to_target", INF)
    var attack_range: float = context.get("attack_range", 32.0)
    
    # Flee check (highest priority)
    if health_ratio < context.get("flee_threshold", 0.25):
        return State.FLEE
    
    # Attack check
    if target_entity and distance_to_target <= attack_range:
        return State.ATTACK
    
    # Detection-based transitions
    match current_state:
        State.IDLE, State.PATROL:
            if detection_value >= 0.6:
                return State.CHASE
            elif detection_value >= 0.3:
                return State.STALK
            elif detection_value >= 0.1:
                return State.SEARCH
            elif current_state == State.IDLE and state_timer > 50:
                return State.PATROL
        
        State.SEARCH:
            if detection_value >= 0.5:
                return State.STALK
            elif detection_value < 0.05 and state_timer > 100:
                return State.PATROL
        
        State.STALK:
            if detection_value >= 0.7:
                return State.CHASE
            elif detection_value < 0.2:
                return State.SEARCH
        
        State.CHASE:
            if detection_value < 0.4:
                return State.SEARCH
        
        State.ATTACK:
            if distance_to_target > attack_range * 1.5:
                return State.CHASE
        
        State.FLEE:
            if health_ratio > 0.4 and state_timer > 100:
                return State.SEARCH
    
    return current_state

func _transition_to(new_state: State) -> void:
    previous_state = current_state
    current_state = new_state
    state_timer = 0
    cooldown_timer = STATE_COOLDOWNS.get(new_state, 10)

func _execute_state(hound: Node2D, context: Dictionary) -> Dictionary:
    # Returns action dictionary for entity to execute
    match current_state:
        State.IDLE:
            return {"action": "none"}
        
        State.PATROL:
            return {"action": "move_to", "target": _get_patrol_point(hound, context)}
        
        State.SEARCH:
            return {"action": "move_to", "target": _get_search_point(context)}
        
        State.STALK:
            return {"action": "move_toward", "target": target_entity, "speed_mult": 0.5}
        
        State.CHASE:
            return {"action": "move_toward", "target": target_entity, "speed_mult": 1.5}
        
        State.ATTACK:
            return {"action": "attack", "target": target_entity}
        
        State.FLEE:
            return {"action": "flee_from", "target": target_entity}
    
    return {"action": "none"}

func _get_patrol_point(hound: Node2D, context: Dictionary) -> Vector2:
    var waypoints: Array = context.get("patrol_waypoints", [])
    if waypoints.is_empty():
        return hound.global_position + Vector2(randf_range(-200, 200), randf_range(-200, 200))
    # Cycle through waypoints
    var idx: int = (state_timer / 50) % waypoints.size()
    return waypoints[idx]

func _get_search_point(context: Dictionary) -> Vector2:
    var last_known: Vector2 = context.get("last_known_position", Vector2.ZERO)
    if last_known != Vector2.ZERO:
        return last_known + Vector2(randf_range(-100, 100), randf_range(-100, 100))
    return Vector2.ZERO
```

### 4.6 Blackboard Pattern for AI Context

Instead of assembling a fresh context dictionary every tick, maintain a persistent **blackboard** per entity that systems write to and AI reads from.

```gdscript
# Owned by BattleManager, keyed by entity_id
var blackboards: Dictionary = {}  # {entity_id: Blackboard}

class Blackboard:
    extends RefCounted
    
    # Detection system writes:
    var highest_detection: float = 0.0
    var detected_target_id: int = -1  # Entity ID, not Node reference
    var last_known_position: Vector2 = Vector2.ZERO
    
    # Combat system writes:
    var under_fire: bool = false
    var last_damage_tick: int = -1
    var threat_bearing: float = 0.0  # Degrees
    
    # Self-assessment:
    var health_ratio: float = 1.0
    var ammo_ratio: float = 1.0
    
    # Spatial:
    var nearest_cover_position: Vector2 = Vector2.ZERO
    var distance_to_target: float = INF
```

**Benefits:**
- Systems write facts without knowing who reads them
- AI reads facts without knowing who wrote them
- Contract is explicit (these fields exist, these types)
- Persists between ticks (no re-computation of stable facts)
- Easy to inspect for debugging ("what does hound_alpha believe?")

### 4.7 Event Logging (Replay Foundation)

The tick-based design naturally supports deterministic replay. Emit structured events from BattleManager:

```gdscript
signal battle_event(event: Dictionary)

# Example events:
# {tick: 347, type: "shot_fired", attacker_id: 1, target_id: 5, weapon: "lee_enfield", hit: true}
# {tick: 348, type: "damage_dealt", target_id: 5, amount: 45, source_id: 1}
# {tick: 348, type: "entity_killed", entity_id: 5, killer_id: 1}
# {tick: 350, type: "detection_changed", observer_id: 5, target_id: 1, old_level: "UNAWARE", new_level: "DETECTED"}
# {tick: 412, type: "state_changed", entity_id: 5, old_state: "PATROL", new_state: "STALK"}
```

**Uses:**
- Battle replay (record events, replay on tick playback)
- After-action reports (feed event log to LLM for narrative generation)
- Debugging ("what happened on tick 347?")
- Statistics (shots fired, accuracy, kills per soldier)

---

## 5. Entity Specifications

### 5.1 Squad Entity (`scripts/entities/squad.gd`)

Manages a group of soldiers. Queries databases, doesn't store definitions.

**Key Changes from Current:**
- Remove embedded weapon/soldier data
- Query `Database.get_weapon()` when needed
- Store only instance state (positions, health, ammo counts)
- Connect to `TickManager.tick` for updates

**Instance Data (what Squad stores):**
```gdscript
var entity_id: int                # Unique ID for blackboard/event references
var squad_id: String              # Template ID for lookup
var soldiers: Array[Soldier]      # Active soldier instances
var leader_index: int             # Index into soldiers array (not direct ref)
var formation_type: String        # Current formation
var current_morale: float         # Runtime morale
var suppression: float            # Current suppression level
# NOTE: Ammo is tracked per-soldier, not per-squad
# Squad provides aggregation for UI: get_total_ammo() -> Dictionary
```

**Data Lookups (what Squad queries):**
```gdscript
func get_template() -> Dictionary:
    return Database.get_squad_template(squad_id)

func get_weapon_stats(weapon_id: String) -> Dictionary:
    return Database.get_weapon(weapon_id)
```

### 5.2 Soldier Entity (`scripts/entities/soldier.gd`)

Individual combatant. Minimal state.

**Instance Data:**
```gdscript
var template_id: String           # For lookups
var soldier_name: String          # Generated or assigned
var current_health: int
var position_offset: Vector2      # Offset from squad leader
var current_ammo: int
var status_effects: Array[String] # ["suppressed", "wounded", etc.]
var kill_count: int               # For emergent narrative
```

### 5.3 Hound Entity (`scripts/entities/hound.gd`)

Hostile creature. Contains brain reference but behavior logic lives in `HoundBrain`.

**Instance Data:**
```gdscript
var entity_id: int                # Unique ID for blackboard/event references
var template_id: String
var hound_name: String            # "Hound Alpha", etc.
var current_health: int
var brain: HoundBrain             # State machine
var patrol_waypoints: Array[Vector2]
# NOTE: Detection states live in BattleManager's detection_map, not on entity
# This avoids dangling references and centralizes detection data
```

---

## 6. Manager Specifications

### 6.1 Battle Manager (`scripts/managers/battle_manager.gd`)

The conductor. Orchestrates systems, entities, and state flow.

**Honest Assessment:** This will be the largest, most complex file in the codebase. The "pure systems" pattern means BattleManager handles all the orchestration — fetching data from entities, calling system functions, writing results back, emitting events. Plan for 400-600 lines. If it exceeds 800, consider splitting into sub-managers (DetectionOrchestrator, CombatOrchestrator).

**Responsibilities:**
- Entity lifecycle (spawn, despawn, track)
- Distribute tick events to entities
- Maintain spatial index for queries
- Coordinate detection updates between entities
- Handle combat resolution requests

```gdscript
extends Node

signal entity_spawned(entity_id: int)
signal entity_killed(entity_id: int, killer_id: int)
signal combat_resolved(attacker_id: int, target_id: int, result: Dictionary)
signal battle_event(event: Dictionary)  # For replay/logging

# Entity registry (ID -> Node2D)
var _next_entity_id: int = 1
var entities: Dictionary = {}         # {entity_id: Node2D}
var squads: Array[int] = []           # Entity IDs of squads
var hostiles: Array[int] = []         # Entity IDs of hostiles

# Centralized state (not stored on entities)
var blackboards: Dictionary = {}      # {entity_id: Blackboard}
var detection_map: Dictionary = {}    # {observer_id: {target_id: {value, level}}}

func _ready() -> void:
    TickManager.tick.connect(_on_tick)

func _on_tick(tick_number: int) -> void:
    _update_detection()
    _update_ai()
    _update_movement()
    _process_combat_queue()

func spawn_squad(template_id: String, position: Vector2) -> Node2D:
    # Create from template, add to tracking
    pass

func spawn_hostile(template_id: String, position: Vector2) -> Node2D:
    pass

func request_combat(attacker: Node2D, target: Node2D, weapon_id: String) -> void:
    # Queue combat for resolution this tick
    pass
```

### 6.2 Render Manager (`scripts/managers/render_manager.gd`)

Terrain and overlay rendering only. Entity visuals live on entity nodes themselves.

**Responsibilities (custom `_draw()`):**
- Terrain tile grid
- Fog of war overlay
- Path preview lines
- Debug visualizations (detection radii, LOS lines)

**NOT Responsibilities (handled by entity nodes):**
- Entity sprites (Sprite2D on Squad/Hound nodes)
- Health bars (child ProgressBar or custom draw on entity)
- Selection highlights (entity handles own selection state)
- Detection indicators (child node or shader on entity)

```gdscript
extends Node2D

@export var terrain_data: TerrainData

var path_preview: Array[Vector2] = []
var debug_los_lines: Array = []  # [{from: Vector2, to: Vector2, blocked: bool}]

func _draw() -> void:
    _draw_terrain()
    _draw_fog_of_war()
    _draw_path_preview()
    if GameState.debug_mode:
        _draw_debug_overlays()
```

### 6.3 Input Manager (`scripts/managers/input_manager.gd`)

Input only. Translates input to commands.

**Responsibilities:**
- Mouse click handling
- Keyboard shortcuts
- Selection box
- Context menu triggers
- Camera control inputs

```gdscript
extends Node

signal cell_clicked(cell: Vector2i, button: int)
signal cell_hovered(cell: Vector2i)
signal unit_selected(unit: Node2D)
signal move_ordered(unit: Node2D, destination: Vector2)
signal attack_ordered(attacker: Node2D, target: Node2D)

func _input(event: InputEvent) -> void:
    # Translate raw input to semantic signals
    pass
```

---

## 7. Migration Path

### Phase 1: Foundation (Non-Breaking)
1. Create `data/` folder structure
2. Create JSON database files
3. Add `TickManager` autoload
4. Add `Database` autoload
5. Create `scripts/systems/` with pure function modules

### Phase 2: Extraction (Gradual)
1. Extract terrain editor from `battle_map.gd` → `tools/terrain_editor.gd`
2. Extract rendering from `battle_map.gd` → `managers/render_manager.gd`
3. Extract input from `battle_map.gd` → `managers/input_manager.gd`
4. What remains becomes `managers/battle_manager.gd`

### Phase 3: Entity Refactor
1. Refactor `squad.gd` to query Database
2. Refactor `hound.gd` to use `HoundBrain`
3. Connect all entities to `TickManager`

### Phase 4: Cleanup
1. Move `scripts/core/` contents to appropriate new folders
2. Delete empty `scripts/core/`
3. Update scene references

---

## 8. Implementation Order

**Week 1: Data Layer**
- [ ] Create `data/` folder structure
- [ ] Write all JSON database files
- [ ] Create `Database` autoload
- [ ] Test JSON loading

**Week 2: Tick System**
- [ ] Create `TickManager` autoload  
- [ ] Add speed controls (pause, 1x, 2x, 4x)
- [ ] Connect existing systems to tick (test doesn't break anything)

**Week 3: System Extraction**
- [ ] Create `CombatMath` class (copy from `combat_resolver.gd`)
- [ ] Create `DetectionSystem` class (refactor from `detection.gd`)
- [ ] Add hysteresis to detection

**Week 4: AI Refactor**
- [ ] Create `HoundBrain` class
- [ ] Extract state machine from `hound.gd`
- [ ] Add state cooldowns
- [ ] Test thrashing is fixed

**Week 5: Manager Split**
- [ ] Create `BattleManager` (entity tracking, tick distribution)
- [ ] Create `RenderManager` (all drawing)
- [ ] Create `InputManager` (all input)
- [ ] Decompose `battle_map.gd`

**Week 6: Polish**
- [ ] Entity refactor to use Database lookups
- [ ] Folder reorganization
- [ ] Documentation update
- [ ] Playtest full loop

---

## Appendix A: Current File Mapping

| Current Location | New Location | Notes |
|-----------------|--------------|-------|
| `scripts/core/game_state.gd` | `scripts/autoloads/game_state.gd` | Keep minimal |
| `scripts/core/terrain_manager.gd` | `scripts/autoloads/terrain_manager.gd` | May merge with Database |
| `scripts/core/terrain_data.gd` | `scripts/data/terrain_data.gd` | Resource class, keep |
| `scripts/core/weapon_data.gd` | DELETE | Replaced by JSON + lookup |
| `scripts/core/combat_resolver.gd` | `scripts/systems/combat_math.gd` | Rename, keep logic |
| `scripts/core/detection.gd` | `scripts/systems/detection_system.gd` | Refactor, add hysteresis |
| `scripts/core/pathfinder.gd` | `scripts/systems/terrain_query.gd` | Merge with LOS queries |
| `scripts/core/squad.gd` | `scripts/entities/squad.gd` | Refactor to use Database |
| `scripts/core/soldier.gd` | `scripts/entities/soldier.gd` | Minimal changes |
| `scripts/core/hound.gd` | `scripts/entities/hound.gd` | Extract brain |
| `scripts/core/unit.gd` | DELETE | Unused? |
| `scripts/core/battle_map.gd` | SPLIT | → render_manager, input_manager, battle_manager |
| `scripts/core/main.gd` | `scripts/main.gd` | Scene script, minimal |

---

## Appendix B: Signal Flow

```
TickManager.tick
    ├── BattleManager._on_tick
    │   ├── _update_detection() 
    │   │   └── DetectionSystem.calculate_*() [pure]
    │   ├── _update_ai()
    │   │   └── HoundBrain.process_tick()
    │   ├── _update_movement()
    │   │   └── TerrainQuery.find_path() [pure]
    │   └── _process_combat_queue()
    │       └── CombatMath.calculate_*() [pure]
    │
    └── RenderManager.queue_redraw()

InputManager.move_ordered
    └── BattleManager.queue_move()

InputManager.attack_ordered
    └── BattleManager.request_combat()

BattleManager.entity_killed
    └── RenderManager.show_death_effect()
```

---

*"The map is not the territory, but a good map makes the territory navigable."*
