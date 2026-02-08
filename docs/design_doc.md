# Game Design Document: Pā 596

## 1. Concept Overview

**Title (Working):** Pā 596

**Genre:** Tactical real-time strategy with persistent campaign layer

**Core Fantasy:** You are a desperate postwar commander, tasked with stopping unstoppable things using fragile, overmatched units and precious tech. Every decision costs blood and morale.

**Inspirations:** Close Combat, XCOM, Combat Mission, Cold War conspiracy horror, Alastair Reynolds-style grounded sci-fi

---

## 2. Core Gameplay Loop

### Campaign Layer:
- Turn based
- Move battlegroups on strategic map (rest, force march, dig in, scout, resupply)
- Assign intel and off-map assets (spy planes, artillery netting, drone mines)
- Monitor kaiju movements and possible contact zones
- Political and resource pressures,  (nations defect, supply scarce)

### Battle Layer:

- Real time
- Two phases, setup and combat. Setup is the pre-battle phase where you place your units and objectives in your setup area.
- Setup units and objectives (not always kill: rescue civilians, evacuate scientists, lure kaiju, recover samples)
- Units act on initiative, player can guide behavior
- Emphasis on patience, line of sight, suppression, unit degradation
- Post-battle map persists — dead vehicles, shell holes, fallen buildings stay

---

## 3. Key Systems

### Unit Morale & Trauma
Soldiers who survive encounters with monsters may refuse orders, panic, or become unreliable (but sometimes gain "monster-hardened" bonuses)

### Degradation
Vehicles can lose optics, engine power, tracks, weapons — requiring field repair or retreat

### Ammo & Logistics
Vital to keep formation supplied. Unready units may go into battle half-prepared

### Kaiju Mechanics:
- **Types:** Taniwha-class (small), Menace-class (medium), Cataclysm-class (campaign-level)
- **Abilities:** Heat pulses, bioplasma spray, EMP screech, psychic field disruption, etc.
- **Movement:** Directed by terrain, sound, and environmental manipulation

---

## 4. Mission Types

- Defense
- Delay and distract
- Extraction or escort
- Trap laying / lure missions
- Covert observation
- Civilian control or pacification
- Strategic kill (snipe a Menace-class using a nuclear/experimental weapon)

---

## 5. Aesthetic & Tone

**Visual Style:** Gritty realism. Late 50s/early 60s military hardware with subtle sci-fi flourishes

**Audio:** Sparse music. Emphasis on environmental audio: Geiger clicks, wind, distant screams, radio chatter

**Tone:** Bureaucratic horror, Cold War paranoia, stoic military journals, grim gallows humor

---

## 6. Tech & Prototyping Goals

### Short Term:
- Learn basic game structure: entity components, input, AI behavior trees, pathfinding
- Create a simple top-down tactical prototype in Godot

### Needed Systems:
- Grid or zone-based terrain with line of sight
- Morale and initiative AI
- Persistent terrain damage and destruction
- Timeline-based campaign map with branching consequences

---

## 7. Development Scope (MVP)

- One region with escalating incursion
- 4–5 human unit types
- 1–2 kaiju types with different behaviors
- Basic campaign layer with resupply and mission selection
- Post-mission reports and trauma modeling
