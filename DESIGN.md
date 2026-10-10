# Hive Breakers — Design Doc (working title)

## Pitch
You command a lone combat mech defending a ruined Earth from an alien
invasion. Between missions you run the hangar: repair, salvage alien
tech, upgrade. In battle you sit in the cockpit and stomp through
alien-infested ruins in first person, destroying the hives that spawn
the swarm.

## The 3D trick (why it's 2D under the hood)
- The battlefield is a 2D grid map where every cell has a kind and a
  height: ground, rolling hills, craters, raised platforms, stairs, low
  cover walls, and ruins of different heights.
- Every frame the cockpit view walks one ray per screen column through
  the grid, near to far, drawing each cell's front face and top surface
  only where nothing nearer already covers the screen. That is how you
  can see over low walls, look down from platforms and into craters.
- Looking up/down slides the view (y-shearing, like Doom/Duke Nukem 3D).
- Aliens, props, rockets and explosions are flat sprites scaled by
  distance and cut off by whatever terrain is in front of them.
- Not possible with this trick: bridges, or rooms stacked on rooms.
- The minimap is simply the grid drawn from above.
- No 3D models, no image files: all sprites and sounds are generated
  in code, so the project stays tiny and easy to edit on a phone.

## Terrain
| Feature | Height | Notes |
|---|---|---|
| Hills | 0 to 0.75 in 0.25 terraces | Always walkable. |
| Craters | -0.5 ring, -1.0 floor | Walk in and out. |
| Platforms | 1.0 to 2.5 | Reached by a staircase of 0.5 steps. |
| Low walls | ~0.95 above ground | Block walking and hide crawlers; shoot over them. |
| Ruins / bulkheads | 2.4 to 4.2, ragged tops | Block everything. |

The mech climbs ledges up to 0.6 high and can drop off anything (heavy
landing shake). Aliens follow the same rules: they path around ledges
and only bite you when they're on your level.

## Core loop
1. **Hangar:** read the mission, repair damaged parts, buy upgrades.
2. **Battle:** find and destroy every hive. Hives keep spawning aliens
   while you're near, so push forward.
3. **Result:** credits and salvage come back, damage carries over.
   Destroying all hives severs the hive mind and kills every alien left.

## Mech parts (destructible)
| Part | Effect when damaged / destroyed |
|---|---|
| Torso | Destroyed = mission lost. Cockpit glass cracks as it weakens. |
| Left arm | Left autocannon stops firing. |
| Right arm | Right autocannon stops firing. |
| Legs | Walk speed drops (down to 40% when destroyed). |

Hits are directional: attacks from the left hit the left arm more, from
behind hit the legs, from the front hit the torso.

## Weapons
- **Twin autocannons:** hold FIRE. Arms alternate shots. Each shot goes exactly
  where the crosshair points (small spread). Look down to hit crawlers.
  Missed shots hit the ground, a wall, or fly into the sky.
- **Rocket pod:** splash damage, reload timer. Flies along the crosshair line:
  aim low to blast the ground in front of a swarm.

Red corner brackets appear when the crosshair is on an alien.

## Aliens
| Alien | Behaviour |
|---|---|
| Crawler | Fast, weak, swarms you in melee. |
| Spitter | Keeps distance, circles, spits acid. |
| Brute | Slow, huge HP, heavy melee hits. From Operation 2. |
| Hive | Stationary spawner. Destroy them all to win. |

Aliens sleep until they see you, then chase you around walls using a
flow field (pathfinding toward the player).

## Hangar economy
- Credits: kills, hives, victory bonus. Spent on repairs and upgrades.
- Salvage: hives, brutes, victory. Needed for upgrades.
- Upgrades: Autocannon Calibre, Armor Plating, Leg Servos, Rocket Pod.
- Losing: the recovery crew brings the wreck home (torso patched to 30%).
- Retreat button: leave early, keep kill rewards, damage carries over.

## Controls
- **Phone:** left thumb anywhere on the left side = walking joystick;
  drag on the right side to turn and look up/down; hold FIRE (sliding on
  it also aims); tap RKT for rockets.
- **Keyboard (testing):** WASD walk/strafe, arrows or Q/E turn,
  T/G or PageUp/PageDown look up/down, Space fire, R or F rockets.

## Roadmap
- **1.2:** terrain with heights: hills, craters, platforms with stairs,
  low cover walls, ruins of varied height; elevation readout under the minimap.
- **1.1:** look up/down, shots and rockets go where the crosshair points.
- **1.0a:** cockpit raycaster, minimap, 3 alien types +
  hives, destructible parts, rockets, hangar repairs and upgrades, save.
- **Next ideas:**
  - Mission types: defend a convoy, escape before the timer, boss hive queen.
  - World map / campaign layer: choose which region to liberate.
  - More weapons: flamethrower arm, railgun, shield.
  - Mech chassis choice (light/heavy), pilot names and traits.
  - Floor textures, doors, destructible walls.
  - Real pixel-art sprites and music to replace the generated ones.

## Files
- `scripts/battle/battle.gd`: raycaster, combat, HUD, touch input.
- `scripts/battle/level_map.gd`: grid map generation, raycasting, pathfinding.
- `scripts/battle/alien_art.gd`: procedurally painted sprites.
- `scripts/hangar.gd`: hangar UI.
- `scripts/game_state.gd`: campaign data, upgrades, save/load (autoload).
- `scripts/sfx.gd`: generated sound effects (autoload).
- `scripts/mech_diagram.gd`: mech damage diagram.
