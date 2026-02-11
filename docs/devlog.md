# Pā 596 - Development Log

## Session: 2026-02-12

### What happened
- Completed Phase 2 (Extraction) — split battle_map.gd from ~880 lines to 511 lines
- 4 commits, each self-contained and non-breaking:
  1. Extracted terrain editor → `scripts/tools/terrain_editor.gd` (270 lines)
     - Brush painting, elevation editing, test map generation, save/load
     - RefCounted helper with signal-based terrain_changed notification
     - main.gd updated to read brush state through terrain_editor
  2. Added child node structure (TerrainOverlay, Entities, DebugOverlay)
     - Squad and Hound now spawn under Entities node for z-ordering
  3. Extracted terrain rendering → `scripts/core/terrain_overlay.gd` (56 lines)
     - Terrain cell colors, elevation shading, fog of war darkening
  4. Extracted debug rendering → `scripts/core/debug_overlay.gd` (204 lines)
     - Grid, LOS overlay, elevation/cover overlays, detection markers, path preview, hover, selection
     - battle_map.gd now has ZERO _draw() code
     - All queue_redraw() replaced with request_redraw() helper

### Architecture state
- Scene tree structure: BattleMap → TerrainOverlay → Entities → DebugOverlay
- battle_map.gd handles: data, input, detection orchestration, fog logic, entity spawning
- Rendering fully delegated to child Node2D nodes with their own _draw()
- Old systems still run the game; new Phase 1 systems still not wired in
- Scale mismatch still present (4m/cell in code, 1m/cell in JSON databases)

### What's next
- Run the game to verify Phase 2 extraction didn't break anything
- Phase 3: Entity Refactor — wire Database lookups, extract HoundBrain, connect TickManager
- Or: start wiring Phase 1 systems (CombatMath, DetectionSystem) into existing code

### Known issues
- Existing harmless warnings unchanged
- UID files for new scripts (terrain_overlay, debug_overlay, terrain_editor) will be generated on first Godot run
- battle_map.gd still at 511 lines — further extraction possible (input handling, detection processing) but not urgent

---

## Session: 2026-02-11

### What happened
- Synced all uncommitted work from main repo into worktree, committed in 6 logical groups
- Rewrote CLAUDE.md to incorporate ARCHITECTURE.md as canonical target architecture
- Completed Phase 1 (Foundation) of the architecture migration:
  - Created `data/` folder structure with JSON databases and schemas
  - Added weapons, soldiers, squads, hostiles, and terrain type definitions
  - Terrain types support inheritance (rubble inherits rough, crater inherits rough)
  - Added `TickManager` autoload (10 ticks/sec, speed control, pause)
  - Added `Database` autoload (JSON loader with schema validation and inheritance resolution)
  - Added `CombatMath` pure function system (static hit chance + damage calculations)
  - Added `DetectionSystem` pure function system (static detection gain/decay with hysteresis)
  - Added `TerrainQuery` placeholder (API stub for Phase 2 extraction)

### Architecture state
- Old systems (`combat_resolver.gd`, `detection.gd`, `weapon_data.gd`) still run the game
- New systems (`CombatMath`, `DetectionSystem`, `Database`) exist alongside but aren't wired in
- `TickManager` registered as autoload, emitting ticks, but nothing connects to it yet
- Scale mismatch noted: JSON databases use 1m = 1 cell, current code uses 4m/cell

### What's next
- Phase 2: Extraction — split battle_map.gd into render_manager, input_manager, battle_manager, terrain_editor
- Or alternatively, start wiring new systems into existing code incrementally
- Run the game to verify no startup errors from new autoloads

### Known issues
- Existing harmless warnings unchanged
- `data/effects/` directory removed (no content yet, will recreate when effects system is built)
- UID files for new scripts will be generated on first Godot editor/run

---

## Session: 2026-02-10

### What happened
- Fixed `_delta` → `delta` bug in battle_map.gd `_process()` that prevented project from running
- Full codebase audit: read every file, documented current state
- Created CLAUDE.md project brief for Claude Code and future instances
- Updated this devlog (finally)

### Current state (as of this session)
The prototype is substantially further than the devlog previously indicated. Between Feb 8 and now, another Claude instance built:
- Squad system with rubber-band formation movement (squad.gd, soldier.gd)
- Individual soldiers as RefCounted data objects with steering behaviors
- Hound-class AI with 6-state machine (IDLE/PATROL/STALK/CHASE/ATTACK/SEARCH)
- Sense-agnostic detection system (sight/hearing/seismic channels)
- Bidirectional detection (squads detect hounds, hounds detect squads)
- Detection-driven hound visibility (hidden until IDENTIFIED threshold)
- Visual detection markers (pulsing rings at different awareness levels)
- Path preview on hover when unit selected
- Fog of war (explored vs currently visible)
- Elevation brush mode, terrain brush mode improvements
- Squad architecture sketch doc and hound design sketch doc

### Architecture guide
A comprehensive Pa_596_Architecture_Guide.md was drafted in a planning session covering all systems through Phase F. It exists as a planning document but hasn't been committed to the repo yet. Key decisions from that session:
- Real-time battle layer (Close Combat style, not turn-based)
- Grid calculations with float rendering (1 cell = 32px = ~4m)
- Data-driven architecture (systems read/write shared data, don't call each other)
- Fatigue as check-based (not point pool)
- Composure (battle) vs Cohesion (campaign) two-tier morale
- Sergeant-as-floor for squad composure

### What's next
- Phase A: "Squads Shoot Things" — basic combat resolution, cover, suppression, composure, ammo
- Clean up harmless warnings (shadowed variables, unused parameters)
- Git commit this session's changes

### Known issues
- Harmless warnings: shadowed `visible`/`name` variables, unused parameters in detection.gd
- unit.gd is legacy code, superseded by squad.gd
- Devlog was not maintained between Feb 8 and Feb 10 (multiple sessions of work undocumented)

---

## Session: 2026-02-08

### What happened
- Consolidated project structure (removed duplicate project.godot and empty scene)
- Wired up project.godot: main scene, autoloads (GameState, TerrainManager), WASD input mapping
- Added `terrain_type` field to TerrainData.DEFAULT_CELL
- Created `battle_map.gd` — the visual terrain renderer
  - Custom _draw() based rendering (colored squares, no TileSet needed yet)
  - 6 terrain types: open, road, rough, water, building, impassable
  - Elevation shading (darker = lower, lighter = higher)
  - Grid overlay toggle (G key)
  - Mouse hover highlighting + cell selection
  - Paint mode (P to toggle, right-click or 1-6 to pick terrain type, click/drag to paint)
  - Procedural test map: sinusoidal road, north-south river, building clusters, rough patches
  - F2/F3 save/load (uses TerrainData's JSON serialization)
- Rewrote `main.gd` with camera controls, mode switching, cell info HUD
- Rebuilt `scenes/main.tscn` with BattleMap node and bottom-center info label
- Confirmed Godot MCP tools work: can launch editor, run project, read debug output, stop

### Grid size discussion
- Red noted that for the real game, a finer grid would help hide the tile-based nature
- Current: 32px cells, 40x30 grid. Can shrink cells later for more tactical granularity

### What's next
- LOS visualization (click a cell, see what it can see)
- First prototype unit on the map
- Git init (oops)

### Known issues
- Harmless warning: `cell_updated` signal declared but unused in TerrainManager
- Harmless warning: unused `_pos` parameter in `_on_cell_selected()`
