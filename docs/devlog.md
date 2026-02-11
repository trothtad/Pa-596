# Pā 596 - Development Log

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
