# CLAUDE.md — Project Brief for Pā 596

## What Is This?

Pā 596 is a **tactical real-time strategy game** with a persistent campaign layer. Cold War era, kaiju horror. You command desperate, overmatched military units against unstoppable monsters. Close Combat meets XCOM meets bureaucratic cosmic horror.

**This is a learning project.** The developer (Red) is learning Godot and game development. Build incrementally, test constantly, keep it simple. Prefer working ugly code over elegant broken code.

---

## Tech Stack

- **Engine:** Godot 4.4 (GDScript, not C#)
- **Rendering:** Custom `_draw()` on Node2D (no TileSet/TileMap nodes yet — colored rectangles)
- **Architecture:** Data-driven. Systems read/write shared data objects, don't call each other directly.
- **Version Control:** Git, pushed to GitHub

---

## Project Structure

```
pa-596/
├── scripts/core/          # All game scripts
│   ├── terrain_data.gd    # TerrainData Resource — cell property storage
│   ├── battle_map.gd      # Visual renderer, input handling, fog of war, detection display
│   ├── main.gd            # Camera, mode switching, HUD
│   ├── game_state.gd      # Autoload singleton — mode, debug toggles
│   ├── terrain_manager.gd # Autoload singleton — coordinate conversion, debug colors
│   ├── pathfinder.gd      # A* over TerrainData (8-directional, terrain-cost-aware)
│   ├── squad.gd           # Squad of soldiers — rubber-band formation, A* leader movement
│   ├── soldier.gd         # Individual soldier data + steering (RefCounted, not Node)
│   ├── unit.gd            # LEGACY single-dot unit (superseded by squad.gd, keep as reference)
│   ├── hound.gd           # Hound-class kaiju — state machine AI (IDLE/PATROL/STALK/CHASE/ATTACK/SEARCH)
│   └── detection.gd       # Sense-agnostic detection system (sight/hearing/seismic)
├── scenes/
│   └── main.tscn          # Main scene (Main > BattleMap + Camera2D + UI)
├── docs/                  # Design documents, lore, sketches
│   ├── design_doc.md
│   ├── Pa_596_Project_Plan.txt    # Master reference (lore, systems, campaign, everything)
│   ├── Pa_596_Lore_Compilation.txt
│   ├── squad_architecture_sketch.md
│   ├── hound_design_sketch.md
│   └── devlog.md          # Development log (NEEDS UPDATING)
├── project.godot          # Godot project config (autoloads, input map)
└── CLAUDE.md              # You are here
```

### Autoloads (registered in project.godot)
- `GameState` → `scripts/core/game_state.gd`
- `TerrainManager` → `scripts/core/terrain_manager.gd`

---

## Key Architecture Decisions (ALREADY MADE — don't revisit)

### Grid-Based Calculations, Float Rendering
- **1 cell = 32px = ~4 meters** (8px/meter scale, like Close Combat)
- All terrain lookups, pathfinding, LOS use integer grid coordinates (`Vector2i`)
- Units render at float positions within the grid (smooth movement, formation offsets)
- Map is 40×30 cells = 1280×960px = ~160m × 120m

### Real-Time Battle Layer
- This is a **real-time** tactics game, NOT turn-based, NOT pause-and-play
- Orders take real time to execute. Slowness is intentional. Time has weight.
- The setup phase (before combat) will be turn-based, but battle is continuous.

### Data-Driven Systems
- Systems communicate through shared data on soldier/squad objects, not direct method calls
- Soldier is a RefCounted data object (not a Node) — lightweight, no scene tree overhead
- Squad is a Node2D that owns soldiers and handles rendering + input
- Add fields to data objects as needed, don't break existing interfaces
- Simpler is better. Data objects over inheritance. Pure functions where possible.

### Detection Is Not Binary
- Detection accumulates per observer-target pair (0.0 to 1.0)
- Thresholds: SUSPECTED (0.25) → DETECTED (0.50) → IDENTIFIED (0.75) → TRACKED (1.0)
- Multiple sense channels: sight (needs LOS), hearing (through walls), seismic (for big kaiju)
- Both sides use the same system with different profiles

### The Rubber Band (Squad Movement)
- Squad leader pathfinds on A*, troops steer toward formation positions near leader
- Individual soldiers have persistent random formation offsets
- Soldiers avoid impassable/water terrain via simple steering (not full A* per soldier)
- If leader moves, troops follow. Troops that fall behind catch up. This is Close Combat behavior.

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
| Hound AI | ✅ Working | 6-state machine, patrol waypoints, detection-driven transitions |
| Detection system | ✅ Working | Bidirectional, sight/hearing/seismic, visual markers |
| Hound visibility | ✅ Working | Hound hidden until squad detection reaches IDENTIFIED |
| Save/Load terrain | ✅ Working | JSON serialization, F2/F3 keys |

## What's NOT Built Yet (in priority order)

### Phase A: "Squads Shoot Things" — THE CURRENT PRIORITY
1. **Basic combat resolution** — per-soldier firing, hit/miss, wounds
2. **Cover system** — terrain cover values exist but nothing uses them in combat
3. **Suppression** — incoming fire creates composure pressure
4. **Basic composure** — steady/shaken/panicked/broken states driving behavior
5. **Ammo tracking** — per-soldier ammo, running dry mid-fight

### Phase B: "Bodies Get Tired"
6. Fatigue system (check-based, not point-pool)
7. Movement modes (rush/advance/cautious/crawl)
8. Recovery mechanics
9. Wound effects on squad performance
10. Terrain damage (craters, rubble, fire)

### Phase C: "Before the Storm"
11. Setup phase (turn-based unit placement before real-time)
12. Mission objectives (survive/evacuate/delay/kill)
13. Victory assessment and gradients
14. Events logging
15. After-action report generation

### Phase D and beyond: Campaign layer, roster persistence, LLM integration

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
- **New systems** should read/write soldier or squad data, not call other systems directly
- **Signals** for event notification (unit moved, state changed, etc.)
- **Autoloads** only for truly global state (GameState, TerrainManager)
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

## Known Warnings (Harmless)

These exist in the current build and can be cleaned up but aren't bugs:
- `cell_updated` signal declared but unused in TerrainManager
- `observer_pos` and `target_pos` unused in `calculate_detection_tick()` (reserved for future directional detection)
- Various `visible` / `name` local variables shadow Node built-in properties
- `checked` dict declared but unused in `calculate_los_from()`
- `target_elev` declared but unused in `calculate_los_from()` (reserved for elevation LOS)

---

## Important Context for Code Changes

### Don't break the render loop
`battle_map.gd` is the visual heart. Its `_draw()` method renders everything. If you add visual elements, add them to `_draw()` or as child nodes. Don't create separate rendering that fights with the existing system.

### Detection is bidirectional
Both squads→hostiles AND hostiles→squads use the detection system. Changes to detection.gd affect both sides. The hound has its own detection running in hound.gd; the squad side runs in battle_map.gd's `_process_squad_detection()`.

### Soldiers are data, squads are nodes
Soldier.gd extends RefCounted — it has no _process, no _draw, no signals. The Squad reads soldier data and renders for them. If you need per-soldier behavior (like individual firing), it goes in squad.gd's _process or in a new system that the squad calls.

### The Pathfinder is shared but copyable
battle_map.gd creates one pathfinder. The hound creates its own (so it could have different terrain costs later). Both reference the same TerrainData. If you need pathfinding from a new system, create a new Pathfinder instance pointing at the same TerrainData.

### unit.gd is legacy
The old single-dot unit. Superseded by squad.gd. Don't build on it. It's kept as reference only.

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
