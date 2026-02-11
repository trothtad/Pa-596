# Pā 596 - Project Status
## Last Updated: November 2025

---

## What Is This?

Cold War tactical strategy with kaiju. Close Combat meets XCOM meets Alastair Reynolds.
You are a desperate commander stopping unstoppable things with fragile, overmatched units.
Every decision costs blood and morale.

---

## Current State

### What Exists:
- **Project structure** - Godot 4.2 project scaffold with organized folders
- **TerrainData resource** - Core data structure for map properties (elevation, cover, LOS, movement costs)
- **GameState singleton** - Global state management and debug toggles
- **TerrainManager singleton** - Bridge between TerrainData and visual TileMap
- **Main scene** - Basic camera controls, mode switching framework
- **Design documents** - Full GDD, monster taxonomy, implementation plan

### What's Next (Phase 1.1 from the plan):
1. Create a TileMap with placeholder tiles
2. Hook up TerrainData to the TileMap visually
3. Add grid visualization overlay
4. Test placing tiles and seeing properties update

### What's Needed Before That Works:
- Placeholder tileset (even just colored squares: green/brown/grey/blue)
- BattleMap scene with TileMap node
- Grid drawing script

---

## Quick Reference

### Monster Classes:
- **Hound-class**: Squad-scale (dog to elk). Hellhounds, Rootworms, Dapper Dans, etc.
- **Taniwha-class**: Rhino to bus. Named by nation (UK: Rainbow codes, RU: WW2 battles, US: code+slang)
- **Menace-class**: Tank to small house. Named for Greek Titans. Chronos, Oceanus, Themis, etc.
- **Campaign-class**: Colossal. Greek letters. Alpha through Epsilon. Extinction-level.

### Key Systems (MVP):
- Unit morale & trauma
- Vehicle degradation
- Ammo & logistics
- Persistent battlefield damage
- Kaiju behavior (terrain, sound, environmental manipulation)

### Mission Types:
Defense, Delay, Extraction, Trap-laying, Observation, Civilian control, Strategic kill

---

## Campaign Arc (Planned):

1. **Goa** - Portuguese garrison + local militia. Improvisation. Learning what works.
2. **Mobile Force (Experimental)** - UK specialized anti-kaiju battalion. Professionalization.
3. **Pā 596** - Southern Alps defensive line. Doctrine mastery. Final stand.
4. **Dunwich** (epilogue) - The source. Maybe offensive for once.

---

## How to Resume Work:

1. Open Godot, open this project
2. Check this file for current state
3. Look at Phase 1 Implementation Plan for day-by-day tasks
4. Start with the smallest thing that moves forward
5. Commit often

---

## Notes for Future Claude:

Red has variable energy. The project advances in bursts. The planning documents are thorough
because that's how Red thinks - but execution happens when it happens.

The tone is: gritty realism, bureaucratic horror, Cold War paranoia, gallows humor.
Think sparse audio, Geiger clicks, distant screams, stoic military journals.

The core fantasy is not power - it's desperate competence against impossible odds.

---

## Files of Interest:

- `/docs/design_doc.md` - Full game design document
- `/docs/monster_taxonomy.md` - Complete kaiju classification
- `/docs/implementation_plan.md` - Phase-by-phase technical plan
- `/scripts/core/terrain_data.gd` - Core terrain system (start here for code)

---

*"We need you to finish dying. But in the right way. In a way that helps."*
*— Mayor Harlan Duchesne, Redemption*
