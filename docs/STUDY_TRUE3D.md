# Study: true 3D versus the fake 3D we have now

## 1. What we have today

The battle view is a **2.5D column renderer**, the trick used by Doom and
Comanche:

- The map is a grid of cells, each with one height.
- For each screen column (120–200 per frame), a ray walks the grid and
  draws wall slices and roof tops.
- Aliens, people and props are flat pictures that always face you.
  - They are photographed from 8 directions at start-up from real 3D
    models (`baker.gd`, `models3d.gd`).
  - The game picks the picture that matches the angle you see them from.
- Fog, sky, clouds, the ground plane and a film shader are layered on top.

**This already uses Godot's 3D engine,** but only to take the photographs.
The models in `models3d.gd` (aliens, Brigid, the Chest, people, props) are
real 3D models today. That matters a lot for the cost of switching (section 5).

## 2. What true 3D would mean

The battle becomes a real Godot 3D scene:

- **The map** is turned into a 3D mesh from the same grid. Walls, roofs and
  terrain are real geometry with textures.
- **Everything is a live 3D model** standing in the world: aliens, Brigid,
  people, props. The same models we photograph now.
- **A Camera3D** sits in the cockpit (or the pilot's eyes).
- **The engine handles the rest:** lights, shadows, sky, fog, glow,
  particles, and hiding what is behind what.
- **The game rules don't change:** movement on the grid, heights, the flow
  field the aliens use, missions, the Chest, the crew, saves.

## 3. What we gain

| Area | Gain |
|---|---|
| **Look** | Aliens turn smoothly instead of snapping between 8 views. Real shadows: aliens, walls and Brigid cast them on the ground and on each other. Real lights at night: muzzle flashes, flares, explosions, Brigid's lamps, lit windows that light the street. Proper perspective on everything, close up and far away. |
| **Animation** | Smooth movement at any speed: walks, lunges, flinches, deaths, wings, tentacles. No more 6-frame loops. Corpses can fall in physics (ragdoll-like) instead of being a stored picture. |
| **Level shapes** | Things a one-height-per-cell grid can't do: bridges, overhangs, tunnels, rooms under rooms, multi-floor buildings with stairs, arches, the inside of the bunkers, a hangar you walk into. |
| **Verticality** | Jets and the jetpack (1.7) become natural: true flying, rooftops, looking straight down at aliens below, flyers above you. Today, looking far up or down distorts the view (the fake renderer can only tilt so far). |
| **Aiming and hits** | The engine's ray casts tell exactly what a shot hits. That removes the hand-written column clipping we use now, and the small errors where shots and visible sprites don't quite match. |
| **Effects** | 3D particles for smoke, sparks, rain splashes, snow and spores; decals for scorch marks and acid; a real dynamic sky. |
| **Cameras** | Free cameras become possible: a third-person view of Brigid, kill-cams, the drop and pickup as real flights, and the base (the Rock) as a 3D place. |
| **Workshop (1.8)** | Every part you bolt onto Brigid shows up on the real model straight away. With baked pictures, each combination of parts would need new photographs. |
| **No bake wait** | No "Preparing models…" step and no picture cache on the phone (about 30 MB less storage). |
| **Simpler code over time** | The column renderer, the per-column clipping and the sprite sorting (about 1,500 lines) go away. Godot does that work. |

## 4. What we lose or risk

| Area | Loss or risk |
|---|---|
| **Phone speed** | The biggest risk. The fake renderer's cost barely grows with what's on screen. True 3D cost grows with every model, light and shadow. Mid-range phones run Godot 3D well with care. Older phones may need Low settings: no shadows, fewer lights, shorter view distance, lower resolution. |
| **Draw calls** | Each alien model is built from 20–60 parts. 30 aliens on screen could mean over 1,000 draws, too many for a phone. Fix: merge each model into one mesh at load time, and share materials. This is required work, not optional. |
| **Renderer limits on phones** | The phone-friendly renderer (Compatibility) has no screen-space ambient occlusion, no global illumination and no volumetric fog. It does have shadows, fog, glow, tone mapping, particles and lights (with limits on how many lights each object receives). The richer Mobile renderer needs Vulkan and isn't safe on every phone. |
| **Retro charm** | The current look is crisp and readable on a small screen. 3D can look muddier at phone resolution if it isn't art-directed: busy shadows, small detail lost. |
| **Grid feel** | Levels may look more "blocky 3D" until walls get bevels, trims, rubble piles and props to break up the cubes. That's extra art work. |
| **Work and churn** | A large rewrite of the battle scene's drawing, effects and aiming. The game keeps working the whole time if we build it next to the old renderer (section 6), but new features slow down while it's done. |
| **Battery and heat** | Real 3D works the phone's graphics chip harder. Long sessions get warmer and drain faster. |
| **Testing** | I can test logic and take screenshots here, but only your phone tells the real frame rate. Each step needs a phone check. |

## 5. What carries over

| Part | Carries over? |
|---|---|
| Game rules, missions, Chest, crew, waves, survival, saves, base, menus, music, sounds | Yes, unchanged |
| Map generation (`level_map.gd`) | Yes. It is turned into a mesh instead of ray-cast. |
| 3D models (`models3d.gd`, people and guns in `baker.gd`) | Yes. They are already Godot 3D models; we place them in the world instead of photographing them. |
| Animation poses (people skeleton, alien walk phases) | Yes. Called every frame instead of 6–8 times at bake. |
| Zone themes (sun, colours, fog, weather) | Yes. They map onto Godot's Environment and lights. |
| Surface textures (`surfaces.gd`) | Yes. They become the materials on walls and ground. |
| HUD, gunsight, touch controls | Yes, unchanged on top |
| First-person guns and arms | Yes. They can become real 3D models in front of the camera instead of pictures. |
| Column renderer, sprite clipping, billboard sorting, sky/ground drawing, weather drawing | **Replaced** |

## 6. How we'd do it safely

1. **Prototype first (one update).**
   - Build `battle3d` alongside the current battle, using the same
     battle logic.
   - It draws only the map, the sky and lighting, and the aliens as live
     models.
   - A switch in Settings, "Renderer: Classic / 3D (beta)", lets you
     compare both on your phone.
   - Merge models into single meshes from day one.
2. **Measure on your phone** at Low, Medium and High, with 30 aliens on
   screen. If the frame rate holds, continue; if not, we've learnt it
   cheaply and keep the classic renderer.
3. **Bring it up to the same features:**
   - effects, weather, corpses, the Chest, the crew, survivors;
   - the guns in 3D in front of the camera;
   - night lights.
4. **Use what only 3D can do:** interiors, multi-floor buildings,
   bridges, real jet flight, third-person view, the Rock in 3D.
5. **Retire the classic renderer** once 3D is better everywhere, or keep
   it as the Low option for old phones.

Rough size:
- the prototype is one medium update;
- reaching the same features is one large update;
- the 3D-only features come gradually after that.

## 7. How this fits the roadmap

| Option | Order | Effect |
|---|---|---|
| **A. 3D now** (recommended if your phone handles the prototype) | 1.6 prototype + measure → 1.7 same features in 3D → then Never Clean, jets, Workshop, pilot loadout, all built in 3D | Jets, rooftops and the Workshop are built once, the 3D way. |
| B. 3D later | Never Clean, jets and Workshop on the fake renderer first, then 3D | Features arrive sooner, but jets and the Workshop get redone for 3D. |
| C. Stay fake 3D | Keep improving the current engine | Lightest on the phone; no interiors, bridges or true flight; the 8-direction look stays. |

## 8. Recommendation

**Do the prototype next (Option A, step 1)** and decide with real numbers
from your phone. The case for 3D is strong:
- the models already exist in 3D;
- the next features (jets, rooftops, the Workshop) are exactly the things
  true 3D does well and fake 3D does awkwardly.

The only real unknown is speed on your phone, and the prototype answers it
in one update without throwing anything away.

## 9. Decisions for you

1. **Prototype true 3D next (as 1.6),** pushing Never Clean back by one
   update? Or keep the current order?
2. If 3D wins: **keep the classic renderer as a Low option** for old
   phones, or remove it to keep the code simple?
3. Should true 3D also **bring a third-person camera** for Brigid (useful
   with jets and the Workshop), or stay cockpit-only?
