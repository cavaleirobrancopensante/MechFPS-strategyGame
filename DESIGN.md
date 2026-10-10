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
- Aliens, survivors, the parked mech, crates and beacons are small 3D
  models (built from lit ellipsoids and boxes in `model_art.gd`) that are
  pre-rendered from 8 directions with walk frames. The game shows the
  view that matches the angle you see each one from, so creatures turn,
  show their sides and backs, and the mech shows its hatch from behind.
  Each casts a perspective shadow on the ground and bobs as it walks.
- Sprites are cut off by whatever terrain is in front of them.
- Not possible with this trick: bridges, or rooms stacked on rooms.
- The minimap is simply the grid drawn from above.
- No 3D models, no image files: all sprites and sounds are generated
  in code, so the project stays tiny and easy to edit on a phone.

## Look (3.4)
Still the 2.5D column renderer, but drawn to look as real as it can:
- **Textured surfaces**, generated at start-up (`scripts/battle/surfaces.gd`):
  concrete with slab joints and rain streaks, brick, rusty corrugated
  metal, riveted steel plates, alien flesh with veins, rubble, layered
  earth; ground types per zone (gravel, wet asphalt with puddles, snow,
  grass and mud, quarry dust, concrete slabs, alien creep). Each wall
  column samples the texture at full detail; wall bases get grime.
- **Light**: every zone has a sun (or moon) direction, colour and height
  plus sky ambient; walls are lit by which way they face, roofs and ground
  by the sun's height, sprites by both. Contact shadows where walls meet
  the ground.
- **Atmosphere**: per-pixel distance haze (`world_fog.gdshader`), sky
  gradient, sun glow, two layers of drifting cloud, hazy horizon.
- **Models** are shaded with wrapped light, sky/ground ambient, surface
  mottling and contact darkening, and drawn with smooth filtering; trees
  are built from dozens of leaf and needle clumps.
- **Effects**: textured fireballs, smoke puffs, muzzle flames, cockpit
  glass grime, gunmetal shading.
- **Film pass** (`post.gdshader`): bloom, contrast and per-zone colour
  grade, vignette, slight lens fringing and grain. The HUD sits above it.
- Graphics setting: Low skips the film pass and uses fewer columns.

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

## On foot
- Tap **EXIT MECH** (under the minimap) to climb out of the back of the
  mech. The mech stays parked where you left it, shown on the minimap.
- The pilot is small and quick: walk, or push the stick all the way to
  run. Armed with a carbine (no rockets). 40 HP, no armour, so be careful.
- The mech is wide and can't fit through one-square gaps. Bunkers (with
  one-square doors) and tight alleys hide **salvage caches** (+40 credits,
  +1 salvage each), shown as yellow squares on the minimap.
- To get back in, walk to the mech's **back** and tap **CLIMB IN**.
- Aliens hunt the pilot, not the empty mech. If the pilot dies the
  mission is lost and the recovery crew brings everyone home.

## Music
- 20 songs, each composed and synthesised in code: drums, bass, pad,
  arpeggio and a lead melody (motif → repeat → resolve → higher B part,
  then loop). Each song has its own tempo, scale, chord progression,
  drum style, bass style and lead sound.
- Player bar at the top of every screen: ◀◀ previous, tap the title for
  the song list, ▶▶ next, ❚❚ pause. It remembers your song and plays each
  one twice before moving to the next.
- Songs are composed in the background the first time (about a second
  each on a PC, a few seconds on a phone), then cached on the device.
- Song list lives in `scripts/music/music.gd` (`SONGS`); edit a line to
  change a song's tempo, scale, chords or instruments. After editing,
  bump `CACHE_VERSION` so the cached audio is rebuilt.

## Main menu
- **Survival** (first button): endless waves on a random zone, infinite
  ammunition, a stock Brigid, repair drones patch 15% between waves.
  Waves grow bigger and every third wave the swarm gets tougher. Your best
  wave is saved. Just for fun: it never touches the campaign.
- **Continue / New Game / Load Game:** three campaign save slots (the game
  saves itself after every change). Load Game can also delete a slot.
- **Settings:** music and effects volume, look sensitivity, graphics
  (Low/Medium/High = 120/160/200 screen columns), control hints.
- **Quit.**
- In battle, the MENU button (top-left, or Esc) pauses: Resume, Settings,
  Abort mission / End run, Quit to main menu. The game also pauses when
  the phone sends it to the background.
- At the Rock, ☰ (top-left) opens Resume, Settings, Save & quit.

## Zones (themes)
Every mission picks a zone look from its seed, so no two drops look the
same: sky, light, fog, wall colours, weather, the shape of the map and
the scenery. Defined in `scripts/battle/themes.gd`.
| Zone | Layout | Weather | Scenery |
|---|---|---|---|
| Coastal Ruins · Dawn | ruins | clear | rocks, crystals, barrels |
| Drowned City · Night Rain | town: street grid, tall blocks, lit windows | rain | wrecked cars |
| Sunlit Quarry · Noon | quarry: deep pits, high ground | dust | rocks, cars |
| Snowbound Village · Overcast | village: small houses, fences | snow | pine trees |
| Bog Forest · Dusk Mist | forest: few buildings, dense trees | fireflies | trees, pines |
| Industrial Docks · Smog | industrial: big sheds, containers | ash | barrels, cars |
| Infested Zone · Alien Night | ruins overgrown by alien growth | spores | crystals |

Brigid walks through scenery: cars crumple, trees fall, and barrels
explode (and hurt nearby aliens). Rockets wreck them too.

## Campaign loop
See [STORY.md](STORY.md) for the world, the characters and the story.
1. **Missions tab:** pick an operation (story missions are marked ★). Each
   costs dropship fuel; Coast Patrol is always free.
2. **Air drop:** the Gannet drops Brigid into the zone, loaded with as much
   ammunition as she can carry from the stockpile.
3. **The job:** one of six mission types (below).
4. **Extraction:** a green flare marks the landing zone. Get Brigid
   there (the pilot must be inside) and hold it while the Gannet lands.
5. **Night at the Rock:** loot comes home, buildings produce, the crew
   talks, a new day starts with new operations.

## The Chest, salvage and biomass
Everything you bring home has to be put in **the Chest**: Mags's cargo
walker, a hazard-striped box on four legs that trots after Brigid and
waits beside her when you climb out. Whatever is in the Chest when the
Gannet lifts you out comes home. Whatever isn't is lost.
- **Scrap and circuits:** climb out and open salvage caches by hand, or
  pick up the scrap left by cars Brigid crushes. You carry one load at a
  time in both hands (no shooting while your hands are full), and walk it
  back to the Chest. You can drop a load and come back for it.
  Ammo crates load straight into your guns.
- **Biomass:** alien bodies stay where they fall. Put on the hazmat suit
  (it hangs on the Chest), kneel at a carcass and cut it open: two seconds
  with forceps and scalpel, and you have a glowing jar of biomass. Carry
  it to the Chest. Bigger aliens give more (crawler 2, brute 6, hive 12,
  Brood Mother 40). Jars stack: keep cutting and carry up to 6 jars back
  in one trip. Take the suit off at the Chest when you're done.
- **The harvest team:** three volunteers ride inside the Chest. When it
  stands still and nothing hostile is within about 10 m, they climb out in
  hazmat suits, cut the nearest carcasses (4 seconds each, a green bar shows
  progress) and carry the biomass back. If aliens come close they drop
  everything and run for the Chest. You can cut alongside them.
- **People:** survivors you find follow you, Half-Life style, until they
  reach the Chest, where they strap in on the roof. Rockets can still kill
  them on the way.
- **Cargo** (retrieve missions) is carried to the Chest the same way.
- The context button under EXIT MECH changes as needed: PUT ON / TAKE OFF
  HAZMAT, HARVEST BIOMASS, DROP (keyboard: C).
- In Survival there is no Chest; bodies are cleared after every wave.

## Mission types
| Type | Job |
|---|---|
| Destroy | Kill every hive. The song stops and the rest of the Swarm collapses. |
| Rescue | Find survivors hiding in bunkers (on foot) and lead them to the Chest. |
| Retrieve | Carry fuel canisters, data cores or supply crates to the Chest. |
| Survive | Hold out against waves until the Gannet can land. |
| Scout | Stand by relay beacons until they come online. |
| Boss | The Brood Mother and its guard hives. |

Sometimes a stray survivor is hiding even when nobody called for help.

## Resources (no money)
| Resource | Comes from | Used for |
|---|---|---|
| People | Rescues | Working base modules (they need beds) |
| Scrap | Salvage crane, caches, mission rewards | Building, repairs, ammo, research |
| Circuits | Circuit shop, caches, scouting/retrieval | Building, rockets, research |
| Biomass | Harvested from alien carcasses in the hazmat suit | Research, bioreactor fuel |
| Fuel | Bioreactor, rewards | Every dropship flight |
| Shells / Rockets / Rounds | Ammo factory, ammo crates | Cannon, rocket pod, carbine |

## Base modules (St. Columba's Rock)
Six build sites. Each module needs crew; output scales with how many of
its jobs are filled, and bigger (upgraded) modules need more hands.
| Module | Does |
|---|---|
| Salvage Crane | Scrap every night |
| Ammo Factory | Scrap → shells, rockets (also circuits) or rounds; pick the focus |
| Bioreactor | Biomass → fuel |
| Circuit Shop | Scrap → circuits |
| Bunkhouse | Beds (people without a bed can't work) |
| Radio Mast | One more operation on the board |

The crew also scavenges 2 scrap a night by hand, so you're never fully stuck.

## Destructible terrain
Rockets knock ruins, low walls and alien growth down to rubble (tougher
walls take several hits); rubble is low enough to walk over. Bunker
walls and the map edge can't be broken. Rockets also kill nearby
survivors, destroy cargo and caches, and reset beacons.

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

- **Carbine (on foot):** single shots, carbine rounds.

Ammunition is limited: Brigid carries what the stockpile can give, up to
her rack capacity (shells, rockets, rounds). Unused ammo comes home.
Ammo crates in salvage caches top you up mid-mission.

Red corner brackets appear when the crosshair is on an alien.

## Aliens
| Alien | Behaviour |
|---|---|
| Crawler | Fast, weak, swarms you in melee. |
| Spitter | Keeps distance, circles, spits acid. |
| Brute | Slow, huge HP, heavy melee hits. From Operation 2. |
| Flyer | Wasp-like. Flies over walls at rooftop height, circles, then dives at the cockpit and climbs away. Look up! Its shadow on the ground gives it away. |
| Burrower | Tunnels under everything as a moving mound of dirt (a pulsing ring on the minimap). Bullets can't reach it; rockets hurt it and blast it out. Bursts out of the ground next to you, fights, and digs back down if you run. |
| Hive | Stationary spawner. Destroy them all to win. |

Aliens sleep until they see you, then chase you around walls using a
flow field (pathfinding toward the player).

## Controls
- **Phone:** left thumb anywhere on the left side = walking joystick;
  drag on the right side to turn and look up/down; hold FIRE (sliding on
  it also aims); tap RKT for rockets; EXIT MECH / CLIMB IN under the minimap.
  On foot the RKT button becomes JUMP.
- **Keyboard (testing):** WASD walk/strafe, arrows or Q/E turn,
  T/G or PageUp/PageDown look up/down, Space fire, R or F rockets,
  X exit/board, Shift run on foot, J jump, C context action.

## The Rock's screen
See [docs/UI_STUDY.md](docs/UI_STUDY.md) for the study behind it. Resource
chips along the top, one tab's content in the middle, the crew's chatter
in a radio strip, and four big tabs at the bottom: **Missions** (cards
coloured by type, briefing on the right, LAUNCH always visible),
**Base** (tap a numbered site on the drawing of the Rock to manage it),
**Brigid** (armour and ammunition) and **Lab** (research). Tabs show
hints like "3 idle" or "! repair".

## Roadmap
- **3.4:** graphics overhaul for a realistic look (textures, sun lighting, haze, clouds, better models and effects, film pass).
- **3.3:** jump on foot (and the pilot now climbs any step Brigid can); the harvest team; stack up to 6 biomass jars; the carbine's left hand grips the barrel.
- **3.2:** alien bodies stay; the Chest (cargo walker) that everything must be carried to; hazmat suit and biomass harvesting; survivors follow you to the Chest.
- **3.1:** two new aliens: the Flyer and the Burrower.
- **3.0:** main menu (Survival, Continue, New Game, Load Game with 3 slots,
  Settings, Quit), pause menu in battle, endless Survival mode with infinite
  ammo, redesigned base screen, seven zone themes with weather, map layouts
  and scenery (trees, wrecked cars, explosive barrels).
- **2.1:** solid-looking sprites: 3D-modelled, 8-direction views, walk
  cycles, ground shadows.
- **2.0:** story campaign (12 missions, 3 acts, cast of 6), the Rock as a
  base with modules, people as crew, resources instead of money, limited
  ammunition and an ammo factory, air drops and dropship extraction,
  six mission types including wave survival, destructible terrain.
- **1.4:** 20-song generated soundtrack and a music player bar.
- **1.3:** climb out of the mech and explore on foot with a carbine; wider
  mech that can't fit one-square gaps; bunkers and salvage caches.
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
- `scripts/battle/model_art.gd`: tiny 3D model renderer and the models.
- `scripts/battle/alien_art.gd`: flat painted sprites (rocks, crystals, dropship).
- `scripts/battle/themes.gd`: zone looks (colours, weather, layout, scenery).
- `scripts/menu/menu.gd`: main menu, save slots.
- `scripts/settings.gd`: settings and the settings panel (autoload).
- `scripts/base/base.gd`: the Rock: missions, base sites and people, Brigid, lab.
- `scripts/base/rock_scene.gd`: animated drawing of the Rock with tappable sites.
- `scripts/story.gd`: all the writing: cast, missions, radio, chatter.
- `scripts/game_state.gd`: resources, ammo, modules, crew, research, operations, save (autoload).
- `scripts/sfx.gd`: generated sound effects (autoload).
- `scripts/music/composer.gd`: song composer and synthesiser.
- `scripts/music/music.gd`: song list, player bar and caching (autoload).
- `scripts/mech_diagram.gd`: mech damage diagram.
