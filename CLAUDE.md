# CLAUDE.md — Project Brief for Pā 596

## What Is This?

Pā 596 is a **tactical real-time strategy game** with a persistent campaign layer. Cold War era, kaiju horror. You command desperate, overmatched military units against unstoppable monsters. Close Combat meets XCOM meets bureaucratic cosmic horror.

**This is a learning project.** The developer (Red) is learning Godot and game development. Build incrementally, test constantly, keep it simple. Prefer working ugly code over elegant broken code.

---

## Tech Stack

- **Engine:** Godot 4.4 (GDScript, not C#)
- **Rendering:** Custom `_draw()` on Node2D (transitioning to entity scene nodes — see Architecture)
- **Architecture:** Data-driven. See `docs/ARCHITECTURE.md` for the canonical specification.
- **Version Control:** Git, pushed to GitHub

---

## Project Structure

### Current Layout (everything in scripts/core/)

```
pa-596/
├── scripts/core/              # All game scripts (current)
│   ├── terrain_data.gd        # TerrainData Resource — cell properties, LOS, serialization
│   ├── battle_map.gd          # Renderer, input, fog of war, detection, squad/hound spawning
│   ├── main.gd                # Camera, mode switching, HUD
│   ├── game_state.gd          # Autoload — mode, debug toggles
│   ├── terrain_manager.gd     # Autoload — coordinate conversion, debug colors
│   ├── pathfinder.gd          # A* pathfinding (8-dir, terrain-cost-aware)
│   ├── squad.gd               # Squad node — rubber-band formation, A* leader movement
│   ├── soldier.gd             # Soldier data (RefCounted) — position, state, steering
│   ├── hound.gd               # Hound AI — 6-state machine, detection-driven
│   ├── detection.gd           # Detection system — sight/hearing/seismic channels
│   ├── combat_resolver.gd     # Shot resolution — hit/miss, penetration, wounds
│   ├── weapon_data.gd         # Weapon stats — factory methods for Lee-Enfield, Bren, Sten
│   └── unit.gd                # LEGACY — superseded by squad.gd
├── scenes/
│   └── main.tscn              # Main scene (Main > BattleMap + Camera2D + UI)
├── docs/
│   ├── ARCHITECTURE.md        # *** CANONICAL ARCHITECTURE SPEC ***
│   ├── squad_architecture_sketch.md
│   ├── hound_design_sketch.md
│   ├── Pa_596_Lore_Compilation.txt
│   ├── devlog.md              # Development log
│   └── OUTDATED/              # Superseded planning docs
├── assets/                    # Graphics, audio, fonts
├── resources/                 # Godot resources (.tres, textures)
├── project.godot
└── CLAUDE.md                  # You are here
```

### Target Layout (from ARCHITECTURE.md)

The codebase is migrating to this structure. See Migration Roadmap below.

```
pa-596/
├── data/                       # JSON databases
│   ├── base/                   # weapons.json, soldiers.json, squads.json, hostiles.json
│   ├── terrain/                # terrain_types.json
│   └── effects/                # Status effects (future)
├── maps/                       # Per-map folders (image + terrain.json + meta.json)
├── scripts/
│   ├── autoloads/              # game_state, tick_manager, database
│   ├── data/                   # Data parser classes
│   ├── systems/                # Pure logic (combat_math, detection_system, terrain_query)
│   ├── ai/                     # HoundBrain + state scripts
│   ├── entities/               # squad, soldier, hound
│   ├── managers/               # battle_manager, render_manager, input_manager
│   └── tools/                  # terrain_editor
├── scenes/
│   ├── battle/                 # Battle-specific scenes
│   └── editor/                 # Map editor scenes
└── ...
```

### Autoloads (registered in project.godot)

Current:
- `GameState` → `scripts/core/game_state.gd`
- `TerrainManager` → `scripts/core/terrain_manager.gd`

Adding (Phase 1):
- `TickManager` → `scripts/autoloads/tick_manager.gd`
- `Database` → `scripts/autoloads/database.gd`

---

## Architecture Decisions

### Established (implemented in current code)

**Grid-Based Calculations, Float Rendering**
- **1 cell = 32px = ~4 meters** (8px/meter scale, like Close Combat)
- All terrain lookups, pathfinding, LOS use integer grid coordinates (`Vector2i`)
- Units render at float positions within the grid (smooth movement, formation offsets)
- Map is 40x30 cells = 1280x960px = ~160m x 120m
- **Note:** ARCHITECTURE.md targets 1m = 1 cell. Current code stays at 4m/cell until Phase 3 reconciliation.

**Real-Time Battle Layer**
- **Real-time** tactics, NOT turn-based, NOT pause-and-play
- Orders take real time to execute. Slowness is intentional. Time has weight.
- Setup phase (before combat) will be turn-based, but battle is continuous.

**Data-Driven Systems**
- Systems communicate through shared data on soldier/squad objects, not direct method calls
- Soldier is a RefCounted data object (not a Node) — lightweight, no scene tree overhead
- Squad is a Node2D that owns soldiers and handles rendering + input
- Simpler is better. Data objects over inheritance. Pure functions where possible.

**Detection Is Not Binary**
- Detection accumulates per observer-target pair (0.0 to 1.0)
- Thresholds: SUSPECTED (0.25) → DETECTED (0.50) → IDENTIFIED (0.75) → TRACKED (1.0)
- Multiple sense channels: sight (needs LOS), hearing (through walls), seismic (for big kaiju)
- Both sides use the same system with different profiles

**The Rubber Band (Squad Movement)**
- Squad leader pathfinds on A*, troops steer toward formation positions near leader
- Individual soldiers have persistent random formation offsets
- Soldiers avoid impassable/water terrain via simple steering (not full A* per soldier)
- If leader moves, troops follow. Troops that fall behind catch up. Close Combat behavior.

### Target Architecture (from ARCHITECTURE.md — being implemented)

**Tick-Based Simulation**
- 10 ticks/sec at 1x speed. Nothing happens "continuously" — everything happens "per tick."
- Enables speed control (2x = 20 ticks/sec), clean pause (tick_rate = 0), deterministic replay.

**Entities as Scene Nodes**
- Entities (squads, soldiers, hounds) are Node2D children in the scene tree, not manually drawn shapes.
- Z-sorting, per-entity visibility, Godot signals, future sprite support, click detection.
- Base terrain is a static image (Sprite2D). TerrainData grid is invisible logic only.
- Custom `_draw()` reserved for: fog of war overlay, damage overlays, path previews, debug viz.

**JSON Databases with Schema Validation**
- All entity definitions live in `data/` as JSON. Systems query `Database` autoload for lookups.
- Schema files validate required fields and warn on unknown keys (typo detection).
- Terrain types support inheritance (`rubble` inherits from `rough`).

**Pure Function Systems**
- `CombatMath`, `DetectionSystem`, `TerrainQuery` are `class_name` with static functions.
- No state, no side effects. Given same inputs, same outputs. Callers decide what to do with results.
- Replaces current RefCounted instances (`CombatResolver`, `DetectionProfile`).

**Two-Tier Blackboards**
- Entity Blackboard: per-entity state (my health, my target, am I suppressed).
- Faction Blackboard: shared intel (known enemy positions, alert level, suppression zones).
- Systems write facts without knowing who reads them. AI reads facts without knowing who wrote them.

**Tick Phase Order**
All systems follow this order each tick to prevent mid-tick read of half-updated state:
1. SENSE — Detection, spatial queries write to blackboards
2. THINK — AI reads blackboards, decides actions, queues commands
3. ACT — Movement executes, attacks resolve
4. CLEANUP — Dead entities removed, stale blackboard data scrubbed

**Entity IDs Everywhere**
- No direct Node references in persistent state. `entity_id: int` used in blackboards, detection maps, event logs.
- Lookup via `BattleManager.get_entity(id)` returns null if dead. Callers handle gracefully.
- Belt and suspenders: lookup catches stale refs immediately, cleanup scrubs on entity death.

---

## What's Built and Working

| System | Status | Notes |
|--------|--------|-------|
| TerrainData | ✅ Working | Cell properties, Bresenham LOS, serialization |
| BattleMap renderer | ✅ Working | Custom _draw(), 6 terrain types, elevation shading |
| Terrain painting | ✅ Working | Brush modes (terrain/elevation), keyboard shortcuts |
| A* Pathfinding | ✅ Working | 8-dir, terrain cost, elevation, water avoidance |
| Camera & input | ✅ Working | WASD pan, scroll zoom, mode switching |
| Fog of war | ✅ Working | Per-unit visibility, explored vs visible |
| LOS visualization | ✅ Working | Toggle with L key, green/red overlay |
| Squad movement | ✅ Working | Leader A*, rubber-band troops, path preview |
| Soldier data | ✅ Working | Name, role, position, state enum, steering |
| Hound AI | ✅ Working | 6-state machine, patrol waypoints, detection-driven |
| Detection system | ✅ Working | Bidirectional, sight/hearing/seismic, visual markers |
| Hound visibility | ✅ Working | Hidden until squad detection reaches IDENTIFIED |
| Combat resolver | ✅ Working | Per-soldier shot resolution, hit/miss, penetration, wounds |
| Weapon data | ✅ Working | Lee-Enfield, Bren, Sten factory methods |
| Save/Load terrain | ✅ Working | JSON serialization, F2/F3 keys |

---

## Migration Roadmap

The codebase is transitioning from the current monolithic layout to the architecture described in `docs/ARCHITECTURE.md`. Each phase is non-breaking — old and new systems coexist until the old ones are replaced.

### Phase 1: Foundation (current priority)
1. Create `data/` folder structure with JSON databases and schemas
2. Add `TickManager` autoload (tick-based simulation heartbeat)
3. Add `Database` autoload (central JSON loader with schema validation)
4. Create `scripts/systems/` with pure function modules (`CombatMath`, `DetectionSystem`, `TerrainQuery`)

### Phase 2: Extraction
1. Extract terrain editor from `battle_map.gd` → `tools/terrain_editor.gd`
2. Extract rendering → `managers/render_manager.gd`
3. Extract input → `managers/input_manager.gd`
4. What remains becomes `managers/battle_manager.gd`

### Phase 3: Entity Refactor
1. Refactor `squad.gd` to query `Database` instead of storing weapon/soldier definitions
2. Refactor `hound.gd` to use `HoundBrain` (extracted state machine)
3. Connect all entities to `TickManager`
4. Reconcile scale (current 4m/cell → target 1m/cell)

### Phase 4: Cleanup
1. Move `scripts/core/` contents to appropriate new folders
2. Delete empty `scripts/core/`
3. Update scene references

---

## Code Conventions

### GDScript Style
- Use typed variables where practical: `var x: int = 5`, `var path: Array[Vector2i] = []`
- Use `const` for constants, `enum` for state machines
- Prefix unused parameters with underscore: `func _on_thing(_event):`
- Comments should explain *why*, not *what*

### Naming
- Files: `snake_case.gd`
- Classes/Resources: `PascalCase`
- Functions/variables: `snake_case`
- Constants/enums: `UPPER_SNAKE` / `PascalCase`
- Signals: `past_tense_verb` (e.g., `unit_moved`, `cell_selected`)

### Architecture Patterns
- **New systems** should be pure static functions (`class_name` + `static func`) where possible
- **Signals** for event notification (unit moved, state changed, etc.)
- **Autoloads** only for truly global state (GameState, TerrainManager, TickManager, Database)
- **RefCounted** for data objects that don't need the scene tree (Soldier, DetectionProfile)
- **Node2D** for things that render or need _process (Squad, Hound, BattleMap)

### Adding New Properties
When a new system needs data on soldiers/squads:
1. Add the field to the relevant data object (soldier.gd, squad.gd)
2. Set a sensible default
3. The new system reads/writes that field
4. Don't restructure existing data objects — extend them

---

## Design Philosophy (READ THIS)

### The Game's Soul
- **Humans are always outmatched.** Victory is survival, delay, or pyrrhic.
- **Time has weight.** Crossing open ground takes real seconds. Decisions can't be undone.
- **Units degrade, they don't level up.** Trauma, exhaustion, equipment failure.
- **Bureaucratic horror.** Dry reports concealing terrible realities. Not jump scares.
- **No power fantasy.** This is not about becoming godlike. It's about desperate competence.

### Active But Dumb > Clever But Passive
Kaiju AI should be *relentless*, not *optimal*. A Hound that charges in and gets shredded by prepared fire is more fun than one that perfectly kites at max range. Monsters are forces of nature with preferences, not chess engines. Strong approach drives should override self-preservation.

### Ludonarrative Coherence
Every mechanic should tell the story. If a system doesn't support the theme, cut it or change it. When in doubt, ask: "Would this feel true to a desperate 1950s military commander?"

### The Brian Johnson Rule
Do NOT write like brian_johnsons_johnson_slop.txt (it's in docs/ as a negative example). No overwrought pseudo-scientific prose. No "her mechanoreceptors generated a current." Be direct. Be clear. Be grim when appropriate, funny when earned.

---

## Important Context for Code Changes

### battle_map.gd is being SPLIT
`battle_map.gd` (~850 lines) currently handles rendering, input, detection orchestration, fog of war, terrain painting, and squad/hound spawning. Phase 2 will split it into `render_manager.gd`, `input_manager.gd`, `battle_manager.gd`, and `terrain_editor.gd`. Don't add major new features to it — plan for the split.

### Detection is bidirectional
Both squads→hostiles AND hostiles→squads use the detection system. Changes to detection.gd affect both sides. The hound runs its own detection in hound.gd; the squad side runs in battle_map.gd's `_process_squad_detection()`.

### Soldiers are data, squads are nodes
Soldier.gd extends RefCounted — no _process, no _draw, no signals. Squad reads soldier data and renders for them. Per-soldier behavior (firing) goes in squad.gd or a new system that squad calls.

### Dual systems during migration
After Phase 1, old and new systems coexist:
- `weapon_data.gd` (factory methods) AND `data/base/weapons.json` (Database lookups)
- `combat_resolver.gd` (RefCounted instance) AND `CombatMath` (static pure functions)
- `detection.gd` (DetectionProfile class) AND `DetectionSystem` (static pure functions)

The old code runs the game. The new code is available but not wired in. Phase 2-3 progressively replaces old with new.

### The Pathfinder is shared but copyable
battle_map.gd creates one pathfinder. The hound creates its own. Both reference the same TerrainData. Create new Pathfinder instances pointing at the same TerrainData as needed.

### unit.gd is legacy
Superseded by squad.gd. Don't build on it.

---

## Known Warnings (Harmless)

- `cell_updated` signal declared but unused in TerrainManager
- `observer_pos` and `target_pos` unused in `calculate_detection_tick()` (reserved for directional detection)
- Various `visible` / `name` local variables shadow Node built-in properties
- `checked` dict declared but unused in `calculate_los_from()`
- `target_elev` declared but unused in `calculate_los_from()` (reserved for elevation LOS)

---

## Reference Documents

| Document | Purpose |
|----------|---------|
| `docs/ARCHITECTURE.md` | Canonical architecture spec — full system designs, migration path |
| `docs/squad_architecture_sketch.md` | Squad design rationale — Close Combat rubber-band model |
| `docs/hound_design_sketch.md` | Hound AI design — threat ecology, state machine rationale |
| `docs/Pa_596_Lore_Compilation.txt` | Setting, lore, Cold War kaiju horror background |
| `docs/devlog.md` | Development log — session notes and progress |
| `docs/OUTDATED/` | Superseded planning documents, kept for reference |

---

## Devlog

**UPDATE THE DEVLOG AFTER EVERY SIGNIFICANT SESSION.** File: `docs/devlog.md`

Include: what was built, decisions made, what's next, known issues. This is how different Claude instances (and Red) maintain continuity across sessions.

---

## Quick Reference: Running the Project

- **Run:** Open in Godot 4.4, press F5 (or use Godot MCP: `run_project`)
- **Controls:** WASD pan, scroll zoom, click to select/move, P for paint mode, G grid, L LOS, F fog, F2/F3 save/load
- **Debug output:** Hound state changes print to console. Unit movements print to console.

---

*"Remember — officially, we don't exist. Unofficially, we're all that stands between civilisation and... well, you'll find out soon enough."*
*— Brigadier Thornycroft*
