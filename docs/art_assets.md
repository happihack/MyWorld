# What the game draws — the asset inventory (2026-10-15)

For the move off the alpha models and the art-direction workshop. Everything the player sees, where it comes from in the code, and what any replacement has to respect. Companion to `game_bible.md` §28 (the visual style guide) and `README.md` ("The look").

## 0. The short version

- **There are no model files.** `assets/models/` is empty. Every 3D thing in the box is built in GDScript when the game starts, from boxes, rings, fans and limbs with flat-shaded vertex colours, and merged into one mesh per chunk. Nothing in the world has a texture.
- **Files on disk:** 3 fonts, 14 emote SVGs, 2 splash pictures, 11 shaders and 3 shader includes, 0 audio files (every sound is synthesised in `scripts/audio/sound_synth.gd`), and 1 stray wood-grain photo (§2.12).
- **So "replacing the models" is one of two jobs:** new procedural shapes in the same template system, or an import path for meshes made outside (Blender, Blockbench …) that lands them in the same one-material-per-chunk pipeline. §3 and §4 weigh them.

## 1. The rules any new art has to keep (read from the code)

| Rule | Where | Why it matters |
|---|---|---|
| 1 tile = 1 world unit; a height level = 0.4 units; a 64–128 tile box | `WorldConfig`, bible §8.1 | Everything is sized in tiles |
| A grown person is 0.5 units tall, drawn on purpose larger than a hut doorway (0.30): "figures on a game board" | `PersonMeshLibrary.ADULT_HEIGHT`, `BUILD` 1.12 | People are what the player looks for |
| A hut is ~0.94 tall on a 1-tile footprint; every building is 1×1 today (2×2 is open decision D2 of the buildings plan) | `PropData.PICK_BODY` | Picking uses these bodies, not colliders: new shapes must roughly fit them |
| **All props share one material** (`prop.gdshader`), merged per chunk into one mesh | `PropMesher`, `PropMeshLibrary.Template` | One draw call per chunk; the budget is < 250 draw calls on a low-end phone |
| Prop vertex data: `COLOR.rgb` = colour, **`COLOR.a` = wind sway weight** (0 trunk, 1 leaf tops), **UV.x = glow** (0 none, 1 window/door lit at night, 2 flame), **UV.y = leaf** (1 shed in winter, 0.6 turns colour, 0.2 evergreen) | `Template.glow`, `Template.leaf`, `_prepare()` | Seasons, night windows, snow on tops and the touch wobble all run in the shader on this data |
| **One palette**: `Palette` (`scripts/rendering/palette.gd`) names every world colour; the libraries alias it, the terrain palette's defaults and the box read it; `docs/wiab_palette.gpl` is the same list for Blender (test_palette keeps it current) | `Palette`, `tests/tools/palette_gpl.gd` | New art paints from these colours and nothing else; add a colour to the palette, not to a library |
| Living props get a per-prop brightness tint; built things do not | `PropMesher._tint` | |
| Terrain: stepped blocks, top and side colour per terrain type from a palette resource, tile brightness variation, corner ambient occlusion, cloud shadows, wetness, season tint, snow | `data/configuration/terrain_palette.tres`, `terrain.gdshader` | |
| Water: one quad per wet tile; vertex colour carries depth and shore (not colour); shallow/deep/foam colours, ripples, ice, "blood" | `WaterMesher`, `water.gdshader` | |
| People: **one body mesh for everyone**, no skeleton; `COLOR.rgb` is a mask (r cloth, g skin, b hair), `COLOR.a` shade, UV = limb id; walk, stoop, seated and treading-water poses are vertex-shader motion | `person.gdshader`, `person_motion.gdshaderinc` | Any new figure must carry the same masks and limb ids, or the motion system is rewritten |
| Animals: one mesh per species `shape`, flat species colour, no sway | `AnimalMeshLibrary` | |
| Renderers: Mobile, with Compatibility (OpenGL) fallback; shaders must run on both | bible D-02 | |
| Prop meshing cost: 21 ms a chunk on a PC, ~100 on the phone (2026-10-14) | `PropMeshLibrary._prepare` | Triangle counts per template matter |

## 2. The inventory, by what the player sees

### 2.1 The box and the stage (`BoxFrame`, `WorldLighting`, `DayNight`)
- Wooden plinth with a molding, a low rim, brass corner posts and top rails, near-invisible glass panes; the lid (seen swinging open at every opening). Colours: wood 0.37/0.25/0.16, brass 0.80/0.63/0.32.
- The tabletop under the box (`table.gdshader`), a vignette (`vignette.gdshader`), the dark blue background (0.11/0.14/0.19).
- One sun (warm), sky ambient (cool), the day/night cycle (rose → sky → amber → deep blue), the campfire's glow, windows lit at dusk, oil lamps by doors (M16.3), fireflies on the lid screen.

### 2.2 Terrain and water
- 11 terrain types, each a top and a side colour: grass (lush → sparse by vegetation), dirt, sand, rock, snow, farmland, road, riverbed, mud, ash, paved.
- Grass tufts on lush grass tiles (40% of them), merged with the props.
- Water: shallow 0.40/0.74/0.86, deep 0.13/0.40/0.68, foam, ripples, frozen ice, red for the blood disaster.

### 2.3 Nature (`PropMeshLibrary`)
| Thing | Variants / looks |
|---|---|
| Trees | 2 broadleaf (0.42×1.55, 0.36×1.30), 2 conifers (0.34×1.75, 0.29×1.45); each with a stump look when felled |
| Rocks | 2 |
| Berry bushes | 2, each full / sparse / bare |
| Mushrooms | 2 colours (brown, red), each 3 / 1 / none |
| Wild roots | 2, growing / dug |
| Crops | sown, sprout, growing, ripe, stubble, failed; sprout / growing / ripe dry |
| Orchard (W1) | young / grown / bearing |

### 2.4 Buildings (prop kinds, `data/buildings/*.tres`)
Hut (3 roofs by culture: thatch, reeds, hides) · campfire (lit, cold) · building site (stakes, frame) · storehouse (3 looks by culture: log store, turf root cellar, stone-ringed pit) · granary · seed store · smokehouse · drying rack · well · workshop · woodshed · kiln (pots beside it) · herb rack · herb garden · quarry (blocks, rubble, tripod) · net rack · fish trap (in the water) · landing (jetty) · bridge (posts, beams, deck; plus piles down to the bed) · record stone (plain, tallied) · stone circle · shrine · border stones · grave · cemetery (fenced, up to N headstones) · ruin.

That is 26 kinds, about 40 templates.

### 2.5 Boats (`BoatsView`, their own meshes, drawn 1.7× the landing's old picture)
Raft of logs · dugout canoe · plank boat · boat with mast and sail. Crew sit in them (seated pose).

### 2.6 Loose objects (`LooseObjectsView`, MultiMesh per shape)
Pebble ×2 · rock ×2 · boulder ×2 · log · fruit (berry, nut) · seed · strange object (dark, glinting) · **piles** of 19 resources: wood (a stack of logs), stone (a heap), tools / spears / bows / nets (tools laid together), and a heap on a mat in a colour each for berries, meat, fish, grain, water, clay, herbs, mushrooms, roots, nuts, hide, preserved food, fruit. A soft blob shadow under anything lifted.

### 2.7 People (`PersonMeshLibrary`, `PeopleView`, `PersonView`)
- One body: two legs, a tunic wider at the hem, two arms with skin hands, a head with a hair cap and two eyes. Tens of triangles.
- Told apart by: height (children grow, elders shrink and stoop), build, skin (6), hair (5, grey for elders), cloth (6 undyed; 6 dyed once the settlement weaves).
- Carried: staff, basket, axe, hoe, spear, scroll, fishing rod, bow (by trade, or what they took up to hunt or fight). Loads: logs on the shoulder, a stone held low, an armful in a cloth.
- Poses in the shader: walk, stand and turn, stoop, seated (boats), treading water, a scuffle, an embrace, kneeling, waving; the body gives under a touch.
- Selection: a ring and an outline (`person_outline.gdshader`); a soft shadow.
- 14 emote badges above heads (`assets/ui/emotes/*.svg`): exclaim, question, pray, speech, note, dots, recognize, angry, sad, love, hurt, ill, hungry, tired.

### 2.8 Animals (`AnimalMeshLibrary`, `data/species/*.tres`)
Deer · rabbit · fox · bear · wolf · mountain lion · wild boar — blocky bodies, one species colour each. Fish have no mesh (rings and jumps on the water). Birds: 7, each two flat dark triangles on a shader lap around the box (known issue KI-5: shards up close). Smoke: 14 particles over the fire.

### 2.9 Effects (`WorldEffects`, `WeatherFx`, `ToolFx`, `DisasterFx`)
Dust puffs, rings on water, dark splash rings of the player's rain, warm motes off a touched person, ruin motes, a splash, sparks; rain and snow (`rain.gdshader`), fog, lightning, the wind in the trees, falling leaves, snow lying; the player's cloud and its rain column, a gust's dust; the quake's jolt and dust, the eclipse, the whirlwind's funnel, falling stars.

### 2.10 2D and UI (all in code but the fonts and pictures)
- Fonts: Caveat Brush, Patrick Hand, Kalam (`assets/fonts/`, SIL OFL).
- `HandDraw`: chalk circles, boxes, paper with tape and ruled lines, hatching, blots. `HandIcons`: 26 icons as SVG path strings rasterised on demand.
- `assets/splash/mascot_sheet.png` 2304×2048 (67 frames of 256 px, 9 a row; the lid uses rows 0–2); `assets/splash/title_background.jpg` 1600×900 (a capture of a world; the lid's opening). An optional `splash.png` is honoured if present.
- `icon.svg` (the app icon; Android launcher icon too).

### 2.11 Audio
No files. 14 synthesised ids (thud, plip, rustle, click, knock, crackle, hum, chirp ×3, ui_open, ui_tap, ui_close, wind). Drop a file named after an id in `assets/audio/sfx/` to replace one.

### 2.12 Stray file in the working tree
`assets/textures/6862d6667d2ae084e1826d43_865741817_PS52204-5.jpg` is an **AVIF** picture (2000×2667, a wood-grain photo) with a `.jpg` name; Godot 4.7 cannot import it (`valid=false` in its `.import`). Nothing references it. If it is meant for the lid or the table, convert it to JPG/PNG, give it a name, and it needs a use in code (the lid is painted by `HandDraw` today, the table is a shader).

## 3. The size of the job

| Group | Today | Soon wanted by the plan |
|---|---|---|
| Nature props | 7 kinds, ~25 templates | biome variants (M32: desert, frozen, swamp, volcanic …) |
| Buildings | 26 kinds, ~40 templates | W2: kiln's potter, carpenter's shop, mason's yard, quern → mill, bakery, weaver's hut, tailor · W3: village square, meeting house, festival ground, school hut, archive (2×2 from here, D2) · W4: pen, coop, barn, stable · W5: temple, chief's house, council hall, healer's hut, palisade, watchtower · W6: market, meal hall, watermill / windmill, mine, forge, library, infirmary |
| Boats | 4 | sails driven by wind (FB7), a second landing |
| Loose objects and piles | 12 + 19 | W2: pots, planks, cut stone, flour, bread, fibre, cloth, clothing · W4: milk, eggs, wool, manure · W6: ore, charcoal, metal, metal tools |
| People | 1 body, 8 accessories, 3 loads, 4 palettes | clothing as a thing (W2 tailor), era dress, uniforms (bible §28.4) |
| Animals | 7 | W4: goat, sheep, chicken, cattle |
| World shaders | terrain, water, prop, person, person outline, bird, rain, ring, table, vignette | |

## 4. Three directions to workshop

**A. Painted miniature, same pipeline.** Keep the procedural templates and the one-material rule; raise the craft: a master palette of ~24 colours used everywhere (today each library carries its own constants), consistent bevels and proportions, slightly richer silhouettes where it counts (huts, trees, people), one small shared palette/grain texture if any. Cheapest; no new tools; nothing changes for Josh's content waves (a building stays "one function in `PropMeshLibrary`").

**B. A low-poly kit made outside.** Model in Blender/Blockbench, bake vertex colours, export glTF; add an importer that turns a glTF mesh into a `Template` (vertex colour alpha → sway, a second colour layer or UV2 → glow and leaf). Unlocks an outside artist and a real kit (people, animals, buildings with character); the one-material rule and the per-chunk merge stay, so performance holds. Middle cost: the importer (~a session), then per asset; the person body is the hard one (masks and limb ids for the shader).

**C. The card diorama.** Make the world match the hand-drawn UI: everything looks cut from card and painted in gouache. Mostly a shader pass on the meshes that exist: a toon light ramp, a pale cut edge on silhouettes (the outline shader, widened), a paper-grain overlay, posterised shadows, a bolder palette. Strongest identity, least mesh work; can be done in days and judged on the phone. Combines with A or B.

**Suggested path:** C's shader pass first (it changes the game's look the most for the least, and tells us whether the current silhouettes are the problem or only the shading), the shared palette from A alongside, then B only for hero assets (people, huts, boats, the box itself) once the look is settled.

**Questions for the workshop**
1. Who makes meshes: Jacob in Blender, an outside artist, or Claude in code?
2. Textures at all, or vertex colour only? (One atlas is cheap; per-object textures are not.)
3. Is the hand-drawn UI the anchor for the world's look, or should the world stay "clean toy" against a hand-made box?
4. People stay oversized game pieces?
5. The lowest phone we care about (shadows already cost ~25% close up on the Note20; see plan Appendix 7 item 3).
6. The box itself: wood and brass display case as now, or something more "attic artefact" (the wood-grain photo hints at this).

## 5. Decisions (2026-10-15, Jacob and Josh, workshop page https://claude.ai/artifact/XXjBqxtuvF7Y8XbnbDUgBo)

| # | Question | Decision |
|---|---|---|
| 1 | Who makes meshes | **Claude in code and Jacob in Blender.** Procedural by default; Jacob models the shapes a function cannot carry (the person body, the hut family, boats, the box) in Blender, brought in through a glTF-to-`Template` importer that keeps the vertex rules of §1. No outside artist. |
| 2 | Textures | **Vertex colour only.** The one-material-per-chunk rule stays. |
| 3 | The anchor | **A clean low-poly toy inside a hand-made box.** The world is not made to match the chalk-and-paper UI; the UI, lid and box are the hand-made frame. Direction **A** leads; C's card look is not taken for the world. |
| 4 | People | **Oversized, but a new body.** Keep 0.5 tall; redraw the body in code with more character (head, hands, hair). The colour masks and limb ids stay so the shader poses keep working. |
| 5 | Lowest phone | **The Note20.** Everything A adds must hold its frame rate there. |
| 6 | The box | **An attic artefact.** Worn wood, paper labels, tape, scuffs, in place of the brass display case. |

**The work this sets up (A, in order):**
1. ~~One master palette in one place~~ **Done 2026-10-15:** `Palette`, 36 base colours and their shades; `PropMeshLibrary`, `PersonMeshLibrary`, `AnimalMeshLibrary`, `BoxFrame` and `TerrainPalette`'s defaults (terrain and water) alias it; `docs/wiab_palette.gpl` for Blender, regenerated by `tests/tools/palette_gpl.gd` and checked by `test_palette`. Near-duplicates merged (thatch and wicker were the same colour under two names; bark and dead-crop soil were one colour, now told apart). The species' colours stay in `data/species/*.tres`.
2. ~~The importer and the Blender conventions~~ **Done 2026-10-15:** `ModelImport` (`scripts/rendering/model_import.gd`) turns a glTF into a `Template` (flat-shaded, de-indexed, colours linear→sRGB; sway, glow and leaf from the **material names**: `sway`, `window`/`glow`, `flame`, `leaf`/`turns`/`needle`; a painted vertex alpha wins as sway); the person body from `leg_l`/`leg_r`/`arm_l`/`arm_r` materials and mask colours. Files in `assets/models/props/<kind>_<variant>.glb`, `assets/models/loose/`, `assets/models/person/body.glb` replace the procedural shapes. The conventions, budgets and export steps: `docs/blender_kit.md`; the reference `.glb` files of the game's own hut, trees, campfire, storehouse, rock, bush and person body: `docs/blender_kit/` (written by `tests/tools/model_kit.gd`; `test_model_import` round-trips them).
3. **In progress** (trees and bushes done 2026-10-15, judged with `tests/tools/prop_lineup.gd`). Silhouette pass on what the eye lands on: huts and the building family, the four trees, the person body (decision 4), then boats and animals. In code where a function carries it, from Blender where it does not; same vertex rules; triangle counts checked against the Note20.
4. The box as an attic artefact: `BoxFrame` and the lid (`HandDraw`), the table shader; the stray wood-grain AVIF converted and used, or redrawn in code.
5. Judge on both phones after each step; the phone check is part of "done" (doc conventions).
