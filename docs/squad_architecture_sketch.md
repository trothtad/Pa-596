# Squad Architecture Sketch
## Rubber-Banded Individuals in Pā 596

### The Close Combat Model

In Close Combat, a "squad" is a collection of individual soldiers who:
- Move as a group toward a shared waypoint
- Each have their own position, state, weapon, and morale
- Stay roughly together through cohesion forces (the "rubber band")
- Can become separated by suppression, panic, wounds, or terrain
- Might refuse orders if morale breaks

The squad is the command unit — you give orders to the squad, not to individuals.
But the individuals are what make it *feel* real. One guy breaks and runs. The MG 
gunner goes down and suddenly the squad's suppressive capability evaporates. The 
medic is 30 meters behind because he stopped to help a wounded man.

### Proposed Architecture

```
Squad (Node2D)
├── squad_data: SquadData resource
│   ├── squad_name: String
│   ├── squad_type: String (rifle, mg, mortar, scout, etc.)
│   ├── morale: float (0-100)
│   ├── cohesion: float (how tight they're holding together)
│   ├── suppression: float (incoming fire pressure)
│   ├── orders: current command state
│   └── stance: enum (advance, hold, retreat, rout)
│
├── soldiers: Array[Soldier]
│   └── Soldier (sub-node or data object)
│       ├── name: String
│       ├── position: Vector2 (actual world position, not grid)
│       ├── state: enum (moving, firing, prone, pinned, wounded, dead, panicked)
│       ├── weapon: WeaponData
│       ├── morale_modifier: float (personal bravery/cowardice)
│       ├── fatigue: float
│       └── wound_state: int (0=fine, 1=light, 2=serious, 3=critical)
│
└── (visual children rendered per-soldier)
```

### Key Design Decisions

#### 1. Sub-Grid Positioning

This is the big one. The grid is for terrain — cells have elevation, cover, movement
cost. But soldiers don't snap to grid cells. They exist at floating-point positions
*within* the grid, and they check the cell they're standing in for terrain effects.

This means a squad of 8 soldiers might span 2-3 cells when spread out, or cluster
in a single cell when tight. This has real tactical implications:
- A mortar round hitting one cell might catch 3 guys or 1
- Area-of-effect weapons care about actual positions
- Cover is per-cell, so soldiers in the same squad might have different cover

#### 2. The Rubber Band

Each soldier has a "desired position" relative to the squad's target waypoint.
The formation defines these offsets — a line, a wedge, a column, a cluster.

Each frame, each soldier moves toward their desired position, BUT:
- Movement is capped by their speed and terrain
- They pathfind individually (simplified — they don't need full A*, just 
  "move toward target, avoid impassable")
- If they're suppressed or pinned, they stop moving toward formation
- If they're panicking, they move AWAY from the threat instead
- If their personal morale breaks, they might rout independently

The "rubber band" is just: each soldier tries to stay near their formation
position, with a force that increases with distance. If the distance exceeds
a threshold (say, 5 cells), the soldier is "separated" and behaves 
independently until they can rejoin.

#### 3. Morale Cascade

This is where Pā 596 gets its character. Morale isn't just a squad number.

Squad morale is the AVERAGE of individual morale modifiers, plus situational 
factors (suppression, casualties, nearby friendly units, leadership). But 
individual soldiers can break before the squad does.

When a soldier breaks:
- Nearby soldiers see it and take a morale hit
- If enough soldiers break, the whole squad's average drops
- This can cascade — one panicked soldier can unravel a squad
- BUT: a high-morale NCO can stabilize, providing a morale floor for 
  soldiers within their "command radius"

This gives you the Close Combat experience: the squad is holding the line, 
taking fire, everyone's stressed. Private Williams breaks and runs. Corporal
Singh shouts at him but now the MG team is wavering. Singh steadies them 
(leadership check) but Williams is gone, sprinting for the rear.

#### 4. Weapons as Squad Capability

Each soldier carries a weapon. The squad's combat capability is emergent from
its composition:
- 6 riflemen + 1 BAR gunner + 1 NCO = standard rifle squad
- Lose the BAR gunner = dramatically reduced suppressive fire
- Lose the NCO = morale floor drops, squad becomes fragile

Weapon data:
```
WeaponData
├── name: String ("M1 Garand", "BAR", "Bren Gun")
├── type: enum (rifle, smg, lmg, hmg, launcher, sidearm)
├── rate_of_fire: float (rounds per second when firing)
├── accuracy_base: float (0-1, modified by range, cover, suppression)
├── range_effective: float (in grid units)
├── range_max: float
├── suppression_value: float (how much incoming fire suppresses)
├── ammo_current: int
├── ammo_max: int
└── reload_time: float
```

#### 5. Movement Speeds

At Close Combat scale (~8px/meter), with our 32px cells (~4 meters per cell):
- Walking: ~1.5 m/s = ~12 px/s (one cell every ~2.7 seconds)
- Running: ~4 m/s = ~32 px/s (one cell per second)  
- Sprinting: ~7 m/s = ~56 px/s (fast but exhausting, exposed)
- Crawling: ~0.5 m/s = ~4 px/s (slow but minimal exposure)
- Prone movement: ~0.3 m/s = ~2.4 px/s

These are SLOW. That's the point. Time has weight. Crossing 10 cells of open
ground at a run takes 10 seconds. Under fire, that's an eternity. Walking is 
27 seconds. Crawling is nearly a minute.

The player FEELS this. They learn to value cover, to use terrain, to suppress 
before moving. Not because a tooltip told them to, but because they watched 
Private Williams get shot 6 seconds into a 10-second sprint.

#### 6. Vehicle Integration (Later)

Vehicles are conceptually similar: a "squad" of one, with crew as "soldiers."
The vehicle has armor, systems that can be damaged, crew that can be wounded
or killed. A tank with a dead driver isn't destroyed — it's immobilized. A 
tank with a dead gunner can still move but can't fight.

This uses the same architecture. The "rubber band" just doesn't apply because
the crew is inside the vehicle.

### Implementation Order (Suggested)

1. **Soldier as data object** — position, state, basic properties
2. **Squad as container** — holds soldiers, has formation, receives orders
3. **Formation movement** — soldiers move toward formation positions
4. **Rubber band physics** — cohesion force, separation threshold
5. **Individual rendering** — small dots/shapes per soldier, not just one circle
6. **Morale basics** — squad morale affects willingness to advance
7. **Suppression** — incoming fire pins soldiers, slows movement
8. **Weapons & firing** — soldiers shoot at things, ammo depletes
9. **Casualties** — soldiers can be hit, wounded, killed
10. **Morale cascade** — individual breaks affect squad, leadership stabilizes

Steps 1-5 get you visible rubber-banded squads.
Steps 6-7 make it *feel* like Close Combat.
Steps 8-10 make it a game.

### What This Means for Kaiju

The monster doesn't care about your formation. A Hound-class charging through
your squad scatters individuals physically — the rubber band snaps, soldiers 
go flying, morale craters. A Taniwha-class stepping on your position just 
removes soldiers from existence.

The kaiju interaction with the squad system is:
- Physical displacement (charge, stomp, throw)
- Terror morale effects (scaling with monster class)
- Environmental destruction (the cover you were using is now rubble)
- Sound-based suppression (roars, screams, subsonic)

The squad system doesn't need to know about kaiju specifically. It just 
responds to: damage, displacement, morale pressure, cover destruction.
The kaiju system *applies* those things.

### Open Questions

- How detailed should individual pathfinding be? Full A* per soldier is 
  expensive with 8+ soldiers per squad and multiple squads. Simplified 
  steering behaviors might be enough.
- Should soldiers have persistent names/personalities? (I think yes — 
  it's what makes casualties hurt)
- How much randomness in morale? Close Combat has famously unpredictable 
  morale. Sometimes elite troops break instantly; sometimes conscripts 
  hold to the last man. This feels right for kaiju horror.
- Formation types: how many do we need for MVP? Line and cluster might 
  be enough. Column for road movement. Wedge for advance.

---

*"The squad is a fiction we tell ourselves. In the field, there are only 
individuals choosing, moment by moment, whether to stay or run."*
*— Major Catherine Hale, NZDF After-Action Report, Pā 596*
