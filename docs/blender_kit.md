# Modelling for the box — the Blender kit

For the hero shapes made outside the code (the art decisions of 2026-10-15, `art_assets.md` §5: the person body, the huts, the boats, the box). Everything else stays a function in the mesh libraries. The importer is `scripts/rendering/model_import.gd` (`ModelImport`); the reference files are in `docs/blender_kit/`.

## 1. Set up Blender once

1. **Units and scale:** 1 Blender unit = 1 tile. Leave Unit Scale at 1.0 (metric is fine; think of a metre as a tile).
2. **The palette:** Edit → Preferences → Add-ons → enable *Import Palettes*. In Vertex Paint, open the Color Palette panel and import `docs/wiab_palette.gpl`. Paint only from it. The names are the game's (`BARK`, `THATCH`, `DAUB_DARK` …); `art_assets.md` §1 and `scripts/rendering/palette.gd` say what each is for.
3. **Open a reference:** File → Import → glTF 2.0 → `docs/blender_kit/hut_thatch.glb` (or any other). It lands at the game's scale, with its vertex colours and its materials named as the game reads them. Model next to it.

## 2. The rules of a shape

| Rule | Why |
|---|---|
| **Origin at the base, centred**: the floor of a hut, the roots of a tree, the feet of a person sit at y = 0, x = z = 0 | The game places the base on the tile |
| **Sizes**: a tile is 1 × 1; a hut about 0.94 tall; a tree 1.3–1.75; a grown person 0.5 tall (oversized on purpose, bible §28.4); a loose object's radius is in `LooseObject` | Picking uses these bodies, not colliders |
| **Y is up, the face of a person looks along +X**, its left is +Z | glTF export with +Y up (Blender's default) comes out right |
| **Flat shading, triangles**: no smooth normals, no subdivision; the importer recomputes face normals | The look (bible §28) and the per-chunk merge |
| **Vertex colour only, no textures, no UVs**: one colour attribute (any name), painted from the palette | One material for every prop on the phone |
| **Triangle budget**: see §4 | ~100 ms a chunk of meshing on the phone today |
| **One object or several**: all mesh objects in the file are merged; their transforms are applied | |

## 3. Materials carry the behaviour

The prop shader reads wind sway, night glow and leaf behaviour from the vertices. A modeller never paints those: the importer sets them from the **names of the materials** on each face. Assign a material per behaviour (its colour does not matter when vertex colours are painted; without vertex colours a material's base colour is used).

| Material name contains | Effect |
|---|---|
| `sway` | Sways in the wind, more the higher it is (0 at the model's base, 1 at its top). Tree crowns, grass, a banner |
| `window` or `glow` | Lit at night (windows, doorways, lamps) |
| `flame` | Always lit (a fire) |
| `leaf` | A leaf: turns colour in autumn, falls in winter |
| `turns` | Only turns colour (bushes, grass) |
| `needle` or `evergreen` | Hardly changes (conifers) |
| anything else | Rigid, unlit, unchanging: walls, stone, bark |

Names combine: `leaf_sway` is a broadleaf crown, `needle_sway` a conifer's, `window_glow` a hut window. Blender's `.001` suffixes are fine. A vertex colour **alpha** below 1 overrides `sway` with that exact weight, for when a hand-painted sway is wanted.

**The person body** (`assets/models/person/body.glb`) is different: its vertex colours are **masks**, not colours. Paint pure red where cloth goes, pure green for skin, pure blue for hair, black for the eyes; the alpha is a shade (the game uses 1.0 for the tunic, 0.82 for sleeves and hem, 0.55 for trousers). The limbs are materials named `leg_l`, `leg_r`, `arm_l`, `arm_r`; the game swings them from the top of each limb's mesh to its far end. Everything else is `body`. Keep the proportions of `person_body.glb`: the carried things, the ring, the shadow and the touch are placed for them.

## 4. Triangle budgets

What the procedural shapes cost today, and the most a modelled replacement should (about twice, checked on the Note20 before it ships):

| Shape | Today | Budget |
|---|---|---|
| Person body | 162 | 300 |
| Hut | 56 | 120 |
| Tree (broadleaf / conifer) | 73 / 46 | 150 |
| Rock, bush | 15 / 50 | 40 / 100 |
| Storehouse, workshop, well | 140 / 84 / 168 | 250 |
| Campfire | 101 | 150 |
| Boat | (own mesh) | 150 |
| Animal | 60–150 | 150 |
| A loose object | 10–24 | 40 |
| A resource pile | 120 | 150 |

Many of a kind stand in one chunk (a wood of 40 trees, a village of 12 huts), so a hut at 500 triangles is a village at 6,000.

## 5. Export and drop in

1. File → Export → glTF 2.0: format **glTF Binary (.glb)**, Include: Selected Objects (or the whole file if it holds one shape), Transform: +Y Up (default), Data → Mesh: **Vertex Colors on**, Normals on, UVs off, Apply Modifiers on; Materials: Export; no animation, no cameras, no lights.
2. Name the file for what it replaces and put it here:
   - a prop: `assets/models/props/<kind>_<variant>.glb` — `hut_0.glb` is the thatched hut, `hut_1.glb` the reed one, `hut_2.glb` the hide one; `tree_0.glb` … `tree_3.glb`; kinds are `PropData.Kind` in lower case (`record_stone_1.glb`).
   - a loose object: `assets/models/loose/<kind>_<variant>.glb` (`LooseObject.Kind`: `log_0.glb`, `boulder_1.glb`).
   - the person: `assets/models/person/body.glb`.
3. Open the project in the editor once (or run `godot --headless --path . --import`) so the file is imported, then run the game. The file replaces the procedural shape of that kind and variant; everything else in the game is unchanged. Remove the file to get the procedural shape back.
4. Check it in the game on the phone: at night (the glow), in autumn (the leaves), in a gust (the sway), and the frame rate with a village of them.

## 6. The reference files

`docs/blender_kit/` holds the game's own shapes, written by `godot --headless --path . -s res://tests/tools/model_kit.gd`: `hut_thatch`, `hut_reeds`, `hut_hides`, `tree_broadleaf`, `tree_conifer`, `campfire`, `storehouse`, `rock`, `bush` and `person_body`, each with its materials named by the rules above, its colours from the palette and its origin at the base. They are the models to measure against, and the proof the round trip works: `tests/unit/test_model_import.gd` writes them (through `tests/tools/model_kit_lib.gd`) and reads them back.
