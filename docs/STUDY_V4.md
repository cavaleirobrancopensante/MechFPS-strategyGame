# Study for version 4: real things, real gear, a world that never sleeps

This is the plan for the next big round of changes. It is too much for one
update, so it ends with a roadmap of five updates and the decisions that
are yours to make before work starts.

## 1. What was asked

1. **Realistic objects.** The backgrounds are fine. The things you look at
   and play with should look real: aliens, Brigid, the guns, people, the
   Chest, crates, beacons. They have to be redrawn from scratch.
2. **Much more mech customisation.** Many more weapons and ways to deal
   damage.
3. **The same on foot:** more guns and gear for the pilot.
4. **Jetpack on foot, jets on the mech,** both running on limited fuel.
5. **The harvest crew are people from the base.** They can die, and their
   deaths cost the Rock.
6. **No zone is ever clean.** Finishing the objective doesn't stop the
   swarm. Monsters keep roaming, so you have to babysit the crew.

## 2. Where we are now

- **Objects are tiny 3D models made of balls and boxes,** shaded by a
  hand-written renderer at start-up into small pictures (48–96 pixels):
  8 view directions with 1–4 frames each. That is why they look like toys.
  Ball-and-box shapes can't show joints, armour plates or faces, and four
  frames can't make a convincing walk.
- **The guns and cockpit are flat 2D shapes** drawn every frame.
- **The mech has fixed weapons:** twin autocannons and a rocket pod.
  The only upgrades are stat bumps from the Lab.
- **Destroy missions end the fight:** killing the last hive makes every
  alien collapse, and no new aliens arrive after the objective.
- **The harvest crew are three volunteers who never die.** Nothing hunts
  them.

## 3. Pillar 1: realistic objects

### Options

| Option | How it works | Look | Cost |
|---|---|---|---|
| A. Push the hand-made renderer | More shapes, textures and frames in the current code | Better, but still clay-like | Slow to build on a phone (seconds per model) |
| **B. Bake sprites with Godot's own 3D renderer** (recommended) | Build each model from proper 3D meshes and materials, light it in an off-screen 3D scene, and photograph it from 8 directions and many animation frames into textures | Real lighting, glossy chitin, metal reflections, soft shadow inside the model, smooth animation | Fast: the graphics card does the work. One rewrite of the model code. |
| C. Import ready-made models (.glb) | Download free models or make them in Blender, then bake them like B | As good as the source models | Hard to do from a phone; free sets rarely match our creatures |

**Recommendation: B, with C allowed later for single objects.** The world
keeps its fake-3D engine (the backgrounds already look good). Every object
becomes a "photograph" of a real 3D model, taken when a battle loads:

- **Lit for each zone.** The bake uses that zone's sun direction and
  colour, so a brute at dawn is lit orange from the side and at noon from
  above.
- **Higher resolution:** 128 px on High, 96 on Medium, 64 on Low.
- **Real animation:** models get skeletons (simple bones moved by code),
  so a crawler can have an 8-frame scuttle, a lunge, a hit flinch and a
  death roll.
- **Cached to the phone's storage,** like the music, so each zone is only
  baked once.

### What gets redrawn

| Group | Models | Animations |
|---|---|---|
| Aliens | crawler, spitter, brute, flyer, burrower (+ under-ground mound), hive, Brood Mother | idle, walk/fly/dig, attack, hit, death, carcass, harvested carcass |
| Brigid (seen from outside when you're on foot) | a modular body that shows the parts and weapons you fitted (section 7) | idle, walk, jets firing, damaged states |
| The Chest | hazard-striped cargo walker with harness, suit hook and doors that open | walk, crew climbing in and out |
| People | survivors, harvest crew in hazmat suits, the pilot (seen in cutscenes) | idle, walk, run, cower, kneel and cut, carry, wounded, death |
| Things | caches, cargo, beacons, barrels, cars, trees, scrap piles, biomass jars | open, glow, fall |

**First-person views are baked too:** Brigid's arms and every weapon, and
the pilot's hands and guns. Each gets a few recoil and reload frames, so
the guns you look at all the time finally look solid.

### Memory budget

The textures have to fit on a phone. At 96 px, an object with 8 directions
and 8 frames is about 2.4 MB. Twenty kinds of object comes to about 50 MB.
On Low (64 px) that drops to about 22 MB. Only the objects a zone actually
uses are baked.

## 4. Pillar 2: the world never sleeps

- **A threat director,** like the one in Left 4 Dead, decides when and
  where aliens arrive, all mission long:
  - Roamers wander in from the map edges in small groups.
  - The pressure rises with noise (gunfire, explosions, Brigid's jets)
    and with time spent in the zone.
  - Quiet stretches come after big fights, so there are windows to
    harvest, but they never last.
- **The objective changes the mood, not the danger.**
  - Killing a hive still drops the aliens tied to *that* hive, but
    roamers keep coming.
  - After the objective, the director turns up the pressure ("the swarm
    noticed"), so staying to harvest is a real gamble.
- **Aliens pick targets:** the pilot on foot, the crew, survivors, Brigid,
  and the Chest itself. Crawlers go for the weakest thing near them.
  Spitters snipe people in the open.
- **Warnings:** a tremor on the minimap and a radio call ("movement to the
  north") a few seconds before each group arrives.
- **Survival mode** stays as it is: endless numbered waves.

## 5. Pillar 3: the harvest crew

- **Drawn from the Rock's people.** At the base, a new job, *Chest crew*,
  takes 0 to 4 people. They fly with you, so they don't work at the base
  that day.
- **They have names and a little character.** Each one has:
  - a skill: cutting speed, carrying, or first aid;
  - a nerve value: how fast they run home when aliens come.
- **They can die.**
  - Health is shown over their heads.
  - A wounded crew member limps back to the Chest and can be patched up
    with a medkit.
  - A dead one is gone for good: one fewer person at the Rock, a line in
    the night report, and the crew talking about it.
- **You give simple orders** from a small radial menu:
  - **Stay in the Chest**
  - **Harvest near the Chest**
  - **Follow me**
  - **Get back in**
- **The Chest has armour.** It can be hurt, and it can be upgraded at the
  base with armour plates, a turret, more seats and a winch.

## 6. Pillar 4: jets, jetpack and fuel

The engine can already handle height: the drop camera flies above the
city, and rooftops are real surfaces. So flying and landing on roofs are
possible.

| | Brigid's jump jets | Pilot's jetpack |
|---|---|---|
| Control | Hold JETS: lift and hover; release to glide down | Hold JUMP: lift; tap in the air to dash |
| Tank | Jet fuel, loaded from the Rock's Fuel at launch (costs Fuel like the dropship) | Small canister, refilled at the Chest |
| Burn | Fast. A full tank is about 8 seconds of thrust | About 4 seconds of thrust |
| Refill in the field | Fuel canisters in caches; no slow recharge (so fuel matters) | At the Chest, from Brigid's tank |
| Landing | Heavy landings shake and hurt the legs if you fall from high up | Rolls are safe below about 3 m; above that the pilot is hurt |
| Gameplay | Climb onto roofs to snipe, jump gaps, escape a swarm | Reach rooftop caches and upper floors, cross gaps |

New research: bigger tanks, efficient burners, a hover module.

## 7. Pillar 5: Brigid's workshop

### Hardpoints

| Slot | Count | Examples |
|---|---|---|
| Arms | 2 | autocannon, rotary minigun, flak shotgun, railgun, laser, flamethrower, tesla arc, power fist / drill |
| Shoulders | 2 | rocket pod, missile rack (lock-on), mortar, grenade launcher, smoke launcher, flare launcher |
| Back | 1 | jump jets, shield projector, extra fuel tank, ammo racks, harvest drone |
| Legs | 1 type | scout legs (fast, light), standard, heavy treads (slow, tough, stable), digger legs (stomp) |
| Core | 1 | reactor size: powers energy weapons and shields; heat sinks |
| Cockpit | 2 modules | radar, seismic scanner (sees burrowers), thermal vision, targeting computer |

**Budgets keep choices meaningful:**
- **Weight** affects speed and jet fuel use.
- **Power** comes from the reactor and runs energy weapons and the shield.
- **Heat** builds up from lasers and the flamethrower. Too much heat slows
  the mech or shuts it down.

### Ways to deal damage

| Type | Good against | Bad against | Also |
|---|---|---|---|
| Kinetic (cannons, minigun, shotgun) | crawlers, flyers | brutes' armour | cheap ammo |
| Explosive (rockets, mortar, grenades) | hives, groups | burrowers underground (only splash) | destroys walls, kills survivors and crew nearby |
| Fire (flamethrower) | swarms, alien growth walls | hives | burns organic walls away; burnt carcasses give no biomass |
| Energy (laser, railgun) | brutes, the Brood Mother | — | uses power and heat, no ammo; railgun pierces through a line |
| Electric (tesla) | chains between packed aliens | single big targets | stuns |
| Melee (fist, drill, stomp) | anything close | — | free; drill bores through rubble |

Aliens get resistances (brutes armoured, flyers fragile, hives fire-proof),
so a mix of weapons matters.

**Where parts come from:** the Lab researches each part, the Workshop (a
new base building) makes it from scrap, circuits and biomass, and story
missions unlock prototypes.

**The Brigid tab becomes the Workshop:**
- a picture of the mech with tappable slots;
- a list of the parts that fit the selected slot, with their stats;
- the weight, power and heat bars.

## 8. Pillar 6: the pilot's loadout

| Slot | Options |
|---|---|
| Main gun | carbine, shotgun, SMG, marksman rifle, mini-flamer |
| Sidearm | pistol, flare gun |
| Throwables | frag grenades, incendiary, stun, sticky charges (open bunkers) |
| Tool | plasma cutter (doors, rubble), medkit, scanner, grapple |
| Suit | field armour, hazmat (now an armour type: slower, protects from acid and toxins), light suit |
| Back | jetpack, extra pockets (carry two loads), med pack |

## 9. The economy

- **Fuel** gets three uses: the dropship, Brigid's jets and the pilot's
  jetpack. That makes the Bioreactor important.
- **New ammo types** need the Ammo Factory to have lines (rockets, shells,
  slugs, fuel gel, cells) that you choose between.
- **People** matter more: crew who die are a real loss, and survivors who
  reach the Chest are the way to grow.
- **The Lab tree grows into branches:** weapons, mobility, protection,
  harvesting, and crew.

## 10. Phone controls

The screen is already busy, so new actions must not just add buttons.

- **Fire buttons follow the loadout.** Primary fire fires the arms;
  secondary fire fires the shoulders. Swipe on a fire button to cycle
  weapons.
- **JETS sits under the movement thumb:** swipe the movement stick up,
  hold to fly.
- **A crew/gear button** opens a radial menu: crew orders, grenades, tools.
- **Settings:** left-handed layout, button size and opacity.

## 11. Roadmap

| Update | Name | Contents | Size |
|---|---|---|---|
| **4.0** | New Flesh | Bake system (Godot 3D → sprites, cached); redo all aliens, Brigid, Chest, people and props; first-person guns baked | Large |
| **4.1** | Never Clean | Threat director, roamers, alien targeting of crew, survivors and Chest; crew from the base with names, health and death; crew orders; Chest armour | Medium |
| **4.2** | Up and Over | Mech jump jets and pilot jetpack with fuel; rooftops; landing damage; fuel economy | Medium |
| **4.3** | The Workshop | Hardpoints, 15+ mech parts, weight/power/heat, damage types and resistances, Workshop building and tab | Large |
| **4.4** | Boots on the Ground | Pilot loadout: guns, grenades, tools, suits | Medium |

Why this order:
- **New art first,** so every new weapon and part is made the new way
  once, not redrawn later.
- **The living world next,** because it changes how every mission feels,
  and it's a moderate amount of work.
- **Jets before the workshop,** because the jets become one of the back
  slots.

## 12. Decisions needed from you

1. **Art method:** bake with Godot's 3D renderer (recommended), or keep
   improving the current hand-made renderer?
2. **Should crew deaths be permanent with names and faces** (more weight),
   or just a people count that goes down (simpler)?
3. **How many weapons can Brigid fire at once:** two groups (arms and
   shoulders, recommended), or one weapon at a time with switching?
4. **Should jet fuel come from the Rock's Fuel** (one resource, harder
   choices, recommended), or be its own resource?
5. **How harsh should the threat director be after the objective?** A slow
   build that rewards a quick harvest (recommended), or an immediate rush
   that says "leave now"?
