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

### Project Layout

```
pa-596/
├── scripts/
│   ├── main.gd                    # Camera, mode switching, HUD (scene root)
│   ├── autoloads/                 # Global singletons
│   │   ├── game_state.gd          # Mode, debug toggles
│   │   ├── terrain_manager.gd     # Coordinate conversion, debug colors
│   │   ├── tick_manager.gd        # 10Hz simulation heartbeat, speed control
│   │   └── database.gd            # JSON loader with schema validation
│   ├── data/                      # Data classes (RefCounted)
│   │   ├── terrain_data.gd        # TerrainData Resource — cell properties, LOS
│   │   └── weapon_data.gd         # Weapon stats — factory methods + from_json()
│   ├── entities/                  # Game entities (Node2D or RefCounted)
│   │   ├── squad.gd               # Squad node — rubber-band formation, A* movement
│   │   ├── soldier.gd             # Soldier data (RefCounted) — position, state
│   │   ├── hound.gd               # Hound AI — 6-state machine, detection-driven
│   │   └── unit.gd                # LEGACY — superseded by squad.gd
│   ├── systems/                   # Logic systems
│   │   ├── detection.gd           # Detection system — sight/hearing/seismic
│   │   ├── pathfinder.gd          # A* pathfinding (8-dir, terrain-cost-aware)
│   │   ├── combat_resolver.gd     # Shot resolution — hit/miss, wounds
│   │   ├── composure_system.gd    # Pure static — 5-tier composure model
│   │   ├── fire_control.gd        # Pure static — doctrine-gated fire control
│   │   ├── combat_math.gd         # Pure static functions (not yet wired in)
│   │   ├── detection_system.gd    # Pure static functions (not yet wired in)
│   │   └── terrain_query.gd       # Placeholder (not yet wired in)
│   ├── managers/                  # Orchestration + rendering
│   │   ├── battle_map.gd          # Data, input, detection, fog, entity spawning
│   │   ├── terrain_overlay.gd     # Terrain cell rendering + fog darkening
│   │   └── debug_overlay.gd       # Grid, LOS, detection markers, path preview
│   └── tools/                     # Editor tools
│       └── terrain_editor.gd      # Brush painting, elevation, save/load
├── data/                          # JSON databases
│   ├── base/                      # weapons, soldiers, squads, hostiles + schemas
│   └── terrain/                   # terrain_types.json + schema
├── scenes/
│   └── main.tscn                  # Main scene (Main > BattleMap + Camera2D + UI)
├── docs/
│   ├── ARCHITECTURE.md            # Canonical architecture spec
│   ├── devlog.md                  # Development log
│   └── ...                        # Design sketches, lore
├── project.godot
└── CLAUDE.md                      # You are here
```

### Autoloads (registered in project.godot)

- `GameState` → `scripts/autoloads/game_state.gd`
- `TerrainManager` → `scripts/autoloads/terrain_manager.gd`
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
| Composure system | ✅ Working | 5-tier model (BROKEN→CONFIDENT), sergeant-as-floor, terror pressure |
| Fire control | ✅ Working | 4 doctrines (HOLD_FIRE/DEFENSIVE/AGGRESSIVE/AMBUSH), tick-based |
| Hound proximity terror | ✅ Working | Distance-based composure pressure, cover reduces terror |
| Ammo tracking | ✅ Working | Low ammo warnings, empty mag detection |
| Weapon data | ✅ Working | Lee-Enfield, Bren, Sten factory methods |
| Save/Load terrain | ✅ Working | JSON serialization, F2/F3 keys |

---

## What's NOT Built Yet (in priority order)

### Phase A.5: "Things Bite Back" — THE CURRENT PRIORITY

The hound reaches your squad and... nothing happens. Soldiers run out of ammo and... never reload. A soldier is "wounded" but fights at full effectiveness. These are the gaps that break immersion. Fix them.

**Commit-level breakdown (small bites, each one testable):**

1. **Hound melee attack — damage a soldier**
   - File: `scripts/entities/hound.gd` → `_process_attack()` (line ~324, currently a placeholder)
   - What to do: When hound is in ATTACK state and within 1-2 cells of a squad, pick the closest soldier and deal damage on a cooldown timer (e.g. every 2 seconds)
   - Use `combat_resolver.roll_wound_severity()` to determine wound (1=light, 2=serious, 3=critical, 4=killed)
   - Set `soldier.wound_state` to the result
   - If wound == 4 (killed), set `soldier.state = State.DEAD`
   - Print a log: `"🔴 Hound attacks Cpl. Jones — SERIOUS WOUND"` or `"💀 ... — KILLED"`
   - Hound needs a reference to the squad's soldiers. It already has `current_target` (the squad Node2D). Access soldiers via `current_target.soldiers`

2. **Squad handles soldier death**
   - File: `scripts/entities/squad.gd`
   - What to do: Dead soldiers are already skipped in movement, combat, and composure loops (checks for `State.DEAD` exist everywhere)
   - Add: When a soldier dies, print casualty report `"💀 Squad Alpha — Cpl. Jones KIA (3/5 remaining)"`
   - Add: If the LEADER dies, promote the next living soldier to leader (update `leader` reference, change their `role` to "leader")
   - Add: If ALL soldiers dead, squad is wiped — print `"☠ Squad Alpha — WIPED OUT"`, stop processing (early return in `_on_tick` and `_process`)

3. **Wound effects on soldiers**
   - File: `scripts/entities/soldier.gd` (add helpers), `scripts/entities/squad.gd` (use them)
   - What to do: Add `func get_wound_accuracy_modifier() -> int` to soldier.gd:
     - `wound_state 0` → 0 (fine)
     - `wound_state 1` → -10 (light wound)
     - `wound_state 2` → -25 (serious)
     - `wound_state 3` → -40 (critical, barely functional)
   - Add `func get_wound_speed_modifier() -> float`:
     - `wound_state 0` → 1.0
     - `wound_state 1` → 0.85
     - `wound_state 2` → 0.5
     - `wound_state 3` → 0.2
   - In squad.gd `_process_combat_tick()`: pass wound accuracy modifier into `fatigue_mod` (or add it alongside)
   - In soldier.gd `steer_toward()`: multiply speed by wound speed modifier
   - Wounded soldiers also take a composure hit when first wounded: `composure_value -= 15.0 * wound_state`

4. **Casualty composure shock**
   - File: `scripts/entities/squad.gd`
   - What to do: When a squadmate dies, apply a one-time composure hit to all surviving soldiers
   - Suggested: `ComposureSystem.apply_pressure(s.composure_value, 20.0, 1.0)` for each survivor (one-shot, not per-tick)
   - If the LEADER dies, double the shock (40.0) — losing the NCO is devastating
   - This creates the cascade: hound kills one soldier → everyone's composure drops → they fire worse → hound kills another

5. **Reload mechanic**
   - File: `scripts/entities/squad.gd`, `scripts/entities/soldier.gd`
   - What to do: When `ammo_current == 0` and soldier is not moving, start a reload timer (e.g. 3 seconds for Lee-Enfield, 4 seconds for Bren)
   - Add to soldier.gd: `var is_reloading := false`, `var reload_timer := 0.0`
   - Add to weapon_data.gd: `var reload_time := 3.0` (add field, set in factory methods)
   - In squad.gd `_process()` (frame-based): tick `reload_timer` down like `fire_timer`
   - When reload completes: `ammo_current = weapon.ammo_capacity`, `is_reloading = false`, print `"🔄 Cpl. Jones — RELOADED"`
   - Reloading soldiers can't fire (check `is_reloading` in combat tick)

6. **Squad wipe detection and game state**
   - File: `scripts/entities/squad.gd`, `scripts/managers/battle_map.gd`
   - What to do: Add `func is_wiped() -> bool` to squad.gd — returns true if all soldiers are dead
   - In battle_map.gd: check `squad.is_wiped()` and handle gracefully (deselect, skip in detection loop, etc.)
   - Don't remove the squad node — keep it so the game can show a "your squad was destroyed" state

### Phase B: "Bodies Get Tired" (AFTER A.5)
7. Fatigue system (check-based, not point-pool)
8. Movement modes (rush/advance/cautious/crawl)
9. Recovery mechanics

### Phase C: "Before the Storm" (AFTER B)
10. Setup phase (turn-based unit placement before real-time)
11. Mission objectives (survive/evacuate/delay/kill)
12. Victory assessment and gradients

---

## Migration Roadmap

The codebase is transitioning from the current monolithic layout to the architecture described in `docs/ARCHITECTURE.md`. Each phase is non-breaking — old and new systems coexist until the old ones are replaced.

### Phase 1: Foundation (current priority)
1. Create `data/` folder structure with JSON databases and schemas
2. Add `TickManager` autoload (tick-based simulation heartbeat)
3. Add `Database` autoload (central JSON loader with schema validation)
4. Create `scripts/systems/` with pure function modules (`CombatMath`, `DetectionSystem`, `TerrainQuery`)

### Phase 2: Extraction ✅
- Extracted terrain editor → `scripts/tools/terrain_editor.gd`
- Extracted rendering → `scripts/managers/terrain_overlay.gd` + `debug_overlay.gd`
- `battle_map.gd` retains data, input, detection orchestration, entity spawning

### Phase 3: Entity Refactor ✅
- Squad and Hound spawn from Database JSON templates
- Detection has hysteresis (prevents threshold oscillation)
- Detection runs on TickManager tick signal at 10Hz
- HoundBrain extraction deferred (future)
- Scale reconciliation deferred (future)

### Phase 4: File Reorganization ✅
- All files moved from `scripts/core/` to target directories
- `scripts/core/` deleted
- 22 path references updated across project

### Phase A: "Squads Shoot Things" ✅
- ComposureSystem: 5-tier model (BROKEN/BREAKING/SHAKEN/STEADY/CONFIDENT), float 0-100
- FireControl: 4 doctrines, doctrine-gated engagement, tick-based fire control
- Tick-based combat: detection → fire_control → combat_resolver pipeline on TickManager
- Hound proximity terror: distance-based composure pressure, cover reduces terror
- Firing noise detection feedback: squad_is_firing feeds into hound hearing channel
- Ammo tracking: low warnings, empty magazine handling
- Sergeant-as-floor: leader's composure level is minimum for squad
- BROKEN lockout: composure can't recover while threats are still detected
- Transition-only logging: composure prints only on level changes, not every tick

### Phase A.5: "Things Bite Back" (CURRENT PRIORITY)
Hound melee attacks, soldier wounding/death, squad casualty handling, reload.
See `## What's NOT Built Yet` below for detailed breakdown.

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

### battle_map.gd (`scripts/managers/battle_map.gd`)
The orchestration hub (~540 lines). Handles data, input, detection processing, fog of war, and DB-driven entity spawning. Rendering is delegated to child nodes: TerrainOverlay (terrain cells), DebugOverlay (grid, LOS, detection markers). Terrain painting is delegated to terrain_editor.gd.

### Detection is bidirectional
Both squads→hostiles AND hostiles→squads use the detection system. Changes to `scripts/systems/detection.gd` affect both sides. The hound runs its own detection in `scripts/entities/hound.gd`; the squad side runs in battle_map.gd's `_process_squad_detection()`. Detection runs on TickManager at 10Hz.

### Soldiers are data, squads are nodes
`scripts/entities/soldier.gd` extends RefCounted — no _process, no _draw, no signals. Squad reads soldier data and renders for them. Per-soldier behavior (firing) goes in squad.gd or a new system that squad calls.

### Combat pipeline (tick-based)
- Squad combat runs on TickManager at 10Hz. Tick order: incoming_fire → composure → combat.
- `fire_control.gd` (static) selects targets and gates engagement per doctrine
- `composure_system.gd` (static) manages 5-tier composure, bridges to combat_resolver via `to_legacy_composure()`
- `combat_resolver.gd` (RefCounted instance) resolves individual shots — unchanged, uses old int composure (0/1/2)
- `CombatMath` (static, not yet wired in) — eventual replacement for combat_resolver
- `detection.gd` (with hysteresis) AND `DetectionSystem` (static, not yet wired in)
- `weapon_data.gd` (factory methods + `from_json()`) — weapons loaded from JSON via Database
- Fields marked `# FUTURE: moves to entity/faction blackboard` are signposted for migration

### The Pathfinder is shared but copyable
battle_map.gd creates one pathfinder. The hound creates its own. Both reference the same TerrainData. Create new Pathfinder instances pointing at the same TerrainData as needed.

### unit.gd is legacy
In `scripts/entities/`. Superseded by squad.gd. Don't build on it.

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
