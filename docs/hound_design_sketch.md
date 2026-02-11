# The Hound: Enemy AI Design Sketch
## From Single Predator to Full Threat Ecology

### What Is a Hound?

In Pā 596's fiction, a Hound-class is the smallest category of kaiju 
threat. Dog-sized to horse-sized. Fast, predatory, pack-capable but 
often encountered solo as scouts or stragglers. Think less "Godzilla" 
and more "Jurassic Park velociraptors if they were made of wrong."

Mechanically, a Hound is our first non-player entity. It's the 
simplest possible opponent that still creates genuine tactical tension.

### Why Hound First?

1. **One entity, not a squad.** No rubber-banding, no cohesion, no 
   formation. Just one thing moving on the map. Simplest possible 
   starting point.
   
2. **Asymmetric.** It doesn't use cover, doesn't suppress, doesn't 
   have morale. It has completely different rules from your soldiers.
   This is more interesting than mirror-match AI and more true to the 
   game's fiction.

3. **Forces us to build detection.** Right now fog of war is one-sided.
   The Hound needs to detect your squad AND your squad needs to detect 
   the Hound. This is the foundation of all future AI.

4. **Forces us to build threat response.** When your squad sees a Hound,
   what happens? Morale pressure. When the Hound reaches your squad, 
   what happens? Casualties. These systems serve everything downstream.

5. **Creates the core emotional loop.** Scout forward → see something 
   in the fog → oh shit → decide whether to fight or withdraw. That's 
   the game. That's the whole game, at its beating heart.

---

### Behavior Model: State Machine

The Hound has five states. Simple, readable, extensible.

```
    ┌──────────┐
    │  IDLE    │ ← Waiting at a location, alert
    └────┬─────┘
         │ hears/smells something
    ┌────▼─────┐
    │ PATROL   │ ← Moving between waypoints
    └────┬─────┘
         │ detects prey
    ┌────▼─────┐
    │ STALK    │ ← Moving toward detected prey, cautious
    └────┬─────┘
         │ close enough / prey spotted clearly
    ┌────▼─────┐
    │ CHASE    │ ← Full speed pursuit
    └────┬─────┘
         │ reaches prey / loses prey
    ┌────▼─────┐         ┌──────────┐
    │ ATTACK   │         │ SEARCH   │ ← Lost prey, circling last known pos
    └──────────┘         └──────────┘
```

#### IDLE
- Stationary at a map position
- Periodically "scans" surroundings (detection check)
- Transition: detect stimulus → PATROL toward it, or pre-set patrol route

#### PATROL  
- Moves between waypoints at walking speed
- Waypoints can be pre-placed (designed encounters) or procedural
- Detection checks each tick — wider cone in direction of travel
- Transition: detect prey → STALK

#### STALK
- Moves toward last known prey position at cautious speed (~60% max)
- Tries to approach from cover/concealment if available (later, not MVP)
- Stops periodically to "listen" (detection check with bonus)
- Transition: confirmed visual on prey → CHASE
- Transition: reaches last known position, no prey → SEARCH

#### CHASE
- Full speed toward prey. Fastest movement state.
- Ignores most terrain penalties (Hounds don't care about rough ground)
- Reduced terrain avoidance — will crash through light obstacles
- Transition: reaches melee range → ATTACK
- Transition: prey out of detection range for X seconds → SEARCH

#### ATTACK
- In melee range of a soldier. Deals damage.
- Target selection: nearest soldier, or wounded soldier (predator logic)
- Each attack has a cooldown
- After killing or scattering a target, re-evaluate: CHASE next nearest, 
  or SEARCH if squad has fled detection range

#### SEARCH (recovery state)
- Circles around last known prey position
- Expanding spiral or random walk within radius
- Heightened detection — actively looking
- Transition: detect prey again → STALK
- Transition: timer expires with no detection → PATROL (returns to route)

---

### Detection Model

This is the system that grows into everything. Both the Hound and the 
player's squads use the same detection framework, just with different 
parameters.

#### Detection is not binary.

An entity doesn't go from "unaware" to "full knowledge." There's a 
detection level that builds up:

```
0%  ────── UNAWARE
25% ────── SUSPECTED (heard something, might be nothing)  
50% ────── DETECTED (knows something is there, rough direction)
75% ────── IDENTIFIED (knows what it is and approximately where)
100% ───── TRACKED (exact position, real-time updates)
```

Detection level builds up based on:
- **Distance**: closer = faster detection
- **LOS**: direct line of sight = much faster
- **Noise**: moving soldiers are louder than stationary ones
  - Running > walking > stationary
  - Firing weapons = massive noise spike
- **Terrain**: concealment (rough, forest) slows visual detection
- **Elevation**: height advantage improves visual detection range

Detection level decays over time when stimulus is removed.

#### Hound Detection Profile

Hounds are predators. Their senses are different from humans:
- **Hearing**: Excellent. Detects noise at long range. Movement on 
  roads/gravel louder than grass.
- **Smell**: Good. Slow but persistent. Doesn't need LOS. Wind direction 
  matters (later, not MVP).
- **Sight**: Moderate. Better than human at night, worse in daylight. 
  Motion-sensitive — stationary prey is harder to spot.

```
HoundDetection:
  hearing_range: 20 cells (640px)
  hearing_rate: 5%/tick for moving targets, 1%/tick stationary
  sight_range: 12 cells (384px) — requires LOS
  sight_rate: 15%/tick if target moving, 5%/tick if stationary
  smell_range: 8 cells — ignores LOS, very slow
  smell_rate: 2%/tick
```

#### Squad Detection of Hound

Your soldiers can detect the Hound too. It's not invisible:
- **Sight**: Primary. Soldiers have good eyes but limited range.
- **Hearing**: Hounds make noise. Growling, movement, etc. 
  Louder when running, quieter when stalking.
- **Detection threshold for alarm**: When any soldier in a squad 
  reaches 50% detection of a Hound, the squad enters "alert" state.
  At 75%, they identify what it is. At 100%, they're tracking it.

This creates the fog-of-war-within-fog-of-war: your squad might be 
in a visible cell but not yet aware of the Hound. The Hound might 
know roughly where you are before you know it exists.

---

### Movement Profile

The Hound moves differently from soldiers:

```
HoundMovement:
  walk_speed: 100 px/s (faster than soldiers walking)
  stalk_speed: 60 px/s  
  run_speed: 200 px/s (much faster than soldiers sprinting)
  
  # Terrain modifiers (multiplied against base speed)
  open: 1.0
  road: 1.0      # doesn't prefer roads like humans
  rough: 0.9     # barely affected
  water_shallow: 0.7  # will cross water
  building: 0.5  # can enter but slowed — doesn't fit well
  impassable: blocked  # even Hounds can't walk through cliffs
```

Key difference: Hounds mostly ignore terrain cost. Rough ground that 
slows your soldiers to a crawl barely affects a Hound. Water that's a 
serious obstacle for humans is a minor inconvenience. This means your 
soldiers can't outrun a Hound in the open. They need terrain that 
*specifically* slows or blocks the Hound — buildings, narrow passages, 
elevation — or they need to kill it.

### Pathfinding

The Hound uses the same A* as squads for PATROL (it's navigating to 
waypoints along reasonable routes). But in CHASE mode, it switches to 
direct-pursuit: recalculate path to prey position every N frames. This 
is expensive but only happens during active chases, and there's only one 
Hound (for now).

STALK uses A* to the last known position.
SEARCH uses random walk within a radius — no pathfinding needed.

---

### Implementation Order

This is how we build it incrementally, testing at each step:

#### Phase 1: Dumb Hound (Movement Only)
- Hound entity on the map: a red dot
- PATROL state only: walks between 2-3 waypoints
- Uses A* pathfinding like squads
- Visible through fog of war (no detection yet — you can always see it)
- **Test**: Can we see a hostile entity moving on the map? Does it 
  navigate terrain? Does the fog of war reveal/hide it?

#### Phase 2: Detection
- Hound gets IDLE → PATROL → STALK → CHASE state machine
- Detection system: Hound builds detection level on nearby squads
- Squad builds detection level on Hound  
- Hound only visible when squad detection reaches threshold
- **Test**: Does the Hound spot the squad? Does it transition from 
  patrol to stalk to chase? Can the squad see the Hound approaching?
  Can you evade by staying still / using concealment?

#### Phase 3: Consequences  
- ATTACK state: Hound reaches a soldier and... something happens
- MVP: soldier takes damage/becomes wounded. Simple HP reduction.
- Morale impact: squad seeing a comrade attacked takes morale hit
- Hound can be driven off by... we haven't built weapons yet. So:
  - Temporary: squad "fights back" automatically when Hound attacks
  - Hound takes damage from proximity to squad (abstracted combat)
  - Or: Hound always kills one soldier then flees (hit-and-run predator)
- **Test**: Does the Hound reaching the squad feel dangerous? Do you 
  care about avoiding it? Does losing a soldier (Williams is dead, the 
  squad is now 3/4) have emotional weight?

#### Phase 4: Weapons (separate system, built after Hound works)
- Soldiers get weapons with range, accuracy, rate of fire
- Fire commands: squad fires at detected targets
- Hound takes damage from gunfire
- Hound takes suppression (slows, flinches, might break off chase)
- **Test**: Can you shoot the Hound? Does concentrated fire drive it 
  off? Is there a moment where you choose between firing (revealing 
  your position to other threats) and staying hidden?

#### Phase 5: Ecology (multiple threats)
- Multiple Hounds, potentially as a pack
- Pack behavior: if one detects prey, nearby Hounds converge
- Different Hound variants (faster, tougher, different detection)
- Spawn system: Hounds enter from map edges or from "dens"
- **Test**: Does the map feel dangerous? Is scouting ahead valuable?
  Are there moments of genuine tactical decision-making?

---

### How This Grows Into OpFor

The Hound state machine (IDLE → PATROL → STALK → CHASE → ATTACK) is 
actually a general-purpose AI framework. A human enemy squad would use 
the same states with different parameters:

```
Hound:   fast, aggressive, short stalk, direct chase
Human:   slower, cautious, long stalk, uses cover, shoots before melee

Hound:   hearing-primary detection, motion-sensitive
Human:   sight-primary detection, position-sensitive

Hound:   ignores terrain for movement
Human:   uses terrain for cover and concealment

Hound:   attacks by reaching melee range
Human:   attacks by reaching firing range and opening fire
```

So building the Hound well means building the AI framework well. The 
specific parameters and behaviors change, but the architecture is the 
same. Detection, state transitions, threat response — all reusable.

Similarly, bigger kaiju classes use the same framework:

```
Hound:    5 states, simple transitions, solo predator
Taniwha:  same states but ATTACK destroys terrain, area damage
Leviathan: same states but detection range enormous, shakes ground
           (seismic detection for the player: "something big is moving")
```

---

### What We Build First

Phase 1. A red dot that walks between waypoints. That's it. Once we can 
see it moving on the map, navigating terrain, appearing and disappearing 
in the fog of war, we have our foundation.

Then we make it hunt.

---

*"The first one they sent out didn't even have a radio. They gave 
Corporal Singh a flare gun and said 'fire it if you see something.' 
He fired it. Nobody came."*
*— Major Catherine Hale, NZDF After-Action Report, Pā 596*
