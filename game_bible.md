# MY WORLD IN A BOX — GAME BIBLE

> **Status:** Living document · v1.0 · 2026-09-30
> **Sources:** `my_world.txt` (full specification, §1–§107 + implementation instructions) and `my_world_plan.txt` (milestone roadmap M0–M35, priority stack, vertical slice).
> **Companion:** `implementation_phases.md` (the build plan, phase by phase).
> **Engine:** Godot 4.7.2 · GDScript · Android-first · touch-first · offline-first.
> **Working title:** *My World in a Box* (short form: *World in a Box*, abbreviation **WIAB**). Dev application ID: `com.happihack.worldinabox`.

This bible is the **single source of truth** for what the game *is*. When code, tickets or conversations disagree with it, either the bible is updated deliberately or the code is changed. Every system description here is written so that a developer (human or Claude) starting a fresh session can build the right thing without re-reading the original spec.

Sections marked **[CANON]** are settled. Sections marked **[PROPOSED]** are design decisions made while writing this bible to fill gaps or resolve tensions in the sources; they are recommended defaults and can be overridden. All of them are collected in the **Decisions Log (§32)**.

---

## TABLE OF CONTENTS

1. The One-Sentence Game
2. Vision & Player Fantasy
3. Design Pillars
4. The Ten Commandments of Development
5. The Experience Arc (Toy → Relationship)
6. Core Loops (30 seconds · session · days · months)
7. The Box — Setting, Lore & Developer Canon
8. The World — Space, Terrain, Chunks, Growth
9. Time — Clock, Calendar, Speeds, Offline
10. Environment — Weather, Seasons, Water, Soil, Vegetation
11. Resources & Materials
12. Animals
13. The Inhabitants — Data, Traits, Needs, Behaviour
14. The Interpretation System (signature mechanic)
15. Memory, Stories & Myth
16. Relationships, Families, Life & Death
17. Settlements, Buildings & Economy
18. Knowledge & Technology
19. Culture, Belief & Language
20. Science, Anomalies & Box Research
21. History, Events & the Story Engine
22. Civilization Arc (Phases 1–11) & Endgame
23. The Player — Powers, Tools, Gestures, Sensors
24. Consequences, Not Morality — The Player Relationship Model
25. Discovery, Mysteries & Surprise
26. UX — First Launch, Tutorial, HUD, Menus, Cards, Notifications
27. Statistics, Player History & Achievements
28. Visual Style Guide
29. Audio & Haptics
30. Accessibility
31. Technical Architecture Canon
32. Decisions Log
33. Tunables Master Table
34. Glossary
35. Open Questions

---

## 1. THE ONE-SENTENCE GAME

**You own a mysterious box with a tiny living civilization inside; you cannot command them, only touch, tilt, shake and weather their world — and over generations they notice you, argue about what you are, and eventually discover the box.**

The question the game must constantly provoke:

> **"I wonder what happens if I do this?"**

The question the game must provoke on every return:

> **"What happened to my world while I was gone?"**

The long-term destination:

> **THE WORLD IS WATCHING BACK.**

The first goal (and the one everything else depends on):

> **Make five tiny people living in a tiny world feel alive.**

---

## 2. VISION & PLAYER FANTASY

### 2.1 What the player is

The player is an **unknown force** outside a physical box. Not a god, not a mayor, not a general. The game never names the player's role; inhabitants name it for themselves, differently, and may be wrong.

### 2.2 What the player feels

| Moment | Feeling | Source |
|---|---|---|
| First 10 seconds | "This is a tiny world." | Diorama visuals, ambient motion, a box frame |
| First minute | "This world is actually alive." | Someone walking home, smoke, birds — things the player didn't cause |
| First touch | "They noticed me." | A person reacts individually to a tap |
| ~~First tilt~~ (dropped, D-15) | "I'm physically affecting this world." | *(Now carried by the touch tools: water disturbed, rain from a clear sky, a gust, a rock carried and dropped.)* |
| First return | "What happened while I was gone?" | *While You Were Gone* summary + one intriguing hook |
| Days in | "That person remembers what I did." | Memories resurface in behaviour and text |
| Weeks in | "They've made a story out of me." | Myths, names, rituals built around the player's interventions |
| Months in | "They're studying me." | Scientists correlate anomalies with the player's habits |
| Endgame | "They know about the box. They're trying to talk to me." | Box Theory, symbols, communication |

### 2.3 What this game is NOT

- **Not a city builder.** The player never places buildings or assigns jobs.
- **Not a god game with a mana bar.** There is no currency for interventions (see D-08).
- **Not a scripted narrative.** Stories are emergent from systems (§21).
- **Not a scoreboard.** Statistics exist for reflection and discovery, never ranking.
- **Not a timer/chore game.** No energy, no "come back in 2 hours", no login rewards.
- **Not a fake prototype.** Even the smallest build runs on the real, persistent, chunked, data-driven architecture.

---

## 3. DESIGN PILLARS [CANON]

1. **Interact, don't command.** Every player action is a *stimulus* the world interprets, never an order. The same action on different inhabitants must produce different results.
2. **Alive when not looking.** There are always small things happening. The player frequently notices something they did not cause. The world progresses while the app is closed.
3. **Consequences, not scores.** Experimentation is never punished; it produces consequences that persist in memory, culture and history. No good/evil meter.
4. **Emergence over authorship.** Build systems that create stories, beliefs, important people, eras and mysteries; do not write them by hand.
5. **Curiosity is the reward.** The player should always have an unanswered question. Reveal slowly. Don't explain everything.
6. **Tiny sessions, deep time.** Satisfying in 30 seconds; rewarding across hundreds of hours.
7. **Touch-native, phone-physical.** Touch, tilt, shake and rotation are first-class verbs, and the game remains fully playable without motion controls.
8. **Built to grow.** Chunked world, data-driven content, tiered simulation, versioned saves — from day one.

### 3.1 Development Priority Stack [CANON — from plan]

When choosing what to build or fix next, the higher tier wins:

| Tier | Question |
|---|---|
| 1 FUN | Does the interaction feel good? |
| 2 LIFE | Does the world feel alive without the player? |
| 3 CONSEQUENCES | Do player actions create interesting changes? |
| 4 PEOPLE | Do individual inhabitants feel meaningful? |
| 5 SIMULATION | Do systems interact naturally? |
| 6 HISTORY | Do consequences persist? |
| 7 CIVILIZATION | Does society evolve? |
| 8 MYSTERY | Does the world begin asking questions? |
| 9 SCALE | Can the world survive thousands of simulated events? |
| 10 CONTENT | Add breadth only after the foundation is strong. |

---

## 4. THE TEN COMMANDMENTS OF DEVELOPMENT [CANON]

Distilled from spec §99–§104, §101, "Implementation Instructions" and plan "Critical Rule":

1. **Never build everything at once.** Small milestones; if one is too big, **split it again**.
2. **Always runnable.** Every step ends in a buildable, runnable, testable state.
3. **Error-first.** On any parser/build/runtime error: stop features, find exact file + line + cause, apply the smallest reliable fix, rebuild, validate.
4. **Never assume generated code works.** Run it. Use real error output; never guess.
5. **Make it feel good before moving on.** "Technically works" is not an exit criterion.
6. **No fake prototypes.** The foundation must truly support persistent world, people, history, relationships, simulation, world changes, save/load, scalable chunks and mobile input — even when tiny.
7. **No placeholder mechanics that force a core rewrite later.** Placeholder *art* is fine; placeholder *architecture* is not.
8. **Data over magic numbers.** Tunables live in configuration resources (§33).
9. **Godot 4.7.2 only.** No Godot 3 APIs. Verify any uncertain API against the 4.7 docs before using it.
10. **Report honestly.** Every milestone ends with the completion report (Implemented · Files Changed · Tested · Android Test · Performance · Known Issues · Next Milestone). Never silently skip failed tests.

---

## 5. THE EXPERIENCE ARC [CANON]

The game should feel like, in order:

**A toy → a simulation → a civilization → a history → a mystery → a relationship between the player and an entire living world.**

This arc is also the development order (see `implementation_phases.md`) and the order in which features are revealed to the player. Development "builds" map onto it:

| Build | Player-facing promise | Roadmap milestones |
|---|---|---|
| 01 | A beautiful miniature world | M0–M1 |
| 02 | A world you can touch | M2 |
| 03 | A world you can physically disturb | M3 |
| 04 | A world containing people | M4 |
| 05 | People who notice you | M5 |
| 06 | People who remember you | M5–M6, M11 |
| 07 | People who have families | M10 |
| 08 | Families that create history | M11 |
| 09 | History that creates civilization | M12–M17 |
| 10 | Civilization that creates science | M16–M18 |
| 11 | Science that investigates you | M18, M28 |
| 12 | Civilization discovers the box | M29 |
| 13 | Civilization tries to communicate with you | M30 |
| 14 | **The world is watching back** | M31 |

---

## 6. CORE LOOPS

### 6.1 The first playable loop (must be fun before any civilization system)

```
SEE (tiny world) → TOUCH (world reacts) → MOVE (camera explores) → INTERACT (something happens)
→ OBSERVE (something unexpected happens) → WONDER ("what if I…?") → EXPERIMENT (world changes) → …
```

### 6.2 The reward loop (retention without artificial timers)

```
INTERACT → CAUSE CHANGE → OBSERVE CONSEQUENCES → DISCOVER SOMETHING → LEARN ABOUT THE WORLD
→ BECOME CURIOUS → RETURN → INTERACT AGAIN
```

Design test for every feature: *which arrow of this loop does it strengthen?* If none, it waits.

### 6.3 Loop by session length

| Session | What the player does | What the game must provide |
|---|---|---|
| **30 seconds** | Inspect someone, touch a person, move a rock, make rain, read a new event, glance at stats, close | Instant load to the live world (<3 s warm), one-tap access to the latest news, no mandatory dialogs |
| **2–5 minutes** | Follow a person, try an experiment, read *While You Were Gone*, check a family | Something new since last visit; a hook ("Something strange happened near the eastern mountains.") |
| **30+ minutes** | Explore regions, follow a full day, investigate mysteries, reshape terrain, study statistics, watch construction and discoveries | Depth: timelines, family trees, statistics, mysteries with multi-step clues |
| **Days** | Return several times a day | Offline progression, meaningful events, world events ("Migration season has begun.") |
| **Months** | Watch eras, generations, science, the Box arc | Slow civilization arc, rare revelations |

---

## 7. THE BOX — SETTING, LORE & DEVELOPER CANON

### 7.1 What the player sees [CANON]

A physical box — the kind of object you'd find in an attic or a museum drawer — with a living miniature world inside: terrain, water, trees, animals, a tiny settlement, weather. The frame of the box is always part of the scene; it grounds the "tabletop diorama / terrarium / mysterious artifact" feeling.

### 7.2 What the game tells the player [CANON]

Almost nothing. The first line of text the player ever sees is:

> *"Something lives inside."*

No backstory is given. The player learns about the box the same way the inhabitants do: by experimenting.

### 7.3 Developer canon (never stated outright) [PROPOSED]

A bible needs a consistent hidden truth so that clues and mysteries never contradict each other. Designers may change this, but clues must always be derived from a single canon.

1. **The box is an artifact of unknown origin.** It is one of many. It was made, not grown. Its interior physics are subtly "maintained" (e.g., water never fully leaves; the walls are perfectly flat; the sky has a ceiling).
2. **The box was inhabited before.** Ruins, buried artifacts and impossible materials are the remains of **earlier civilizations** that lived in this box before the current one. (Optional meta-feature: ruins of the player's own previous worlds can seed later worlds — see §25.4.)
3. **The walls are the Edge.** The world's physical boundary is the box wall. Explorers eventually reach it. It is smooth, cool, perfectly straight and unscalable — the first "impossible geometry".
4. **The lid is the Sky's Ceiling.** At high altitude (towers, observatories, balloons in late eras), the sky shows faint structure — a seam, a reflection, a vast shadow when the player's hand passes over.
5. **The Box Unfolds.** When the civilization presses against the edge of its known box, the box can **unfold** — new panels (chunk rings) open and the walls move outward. For inhabitants this is a world-changing event ("The Edge Moved") and key evidence for Box Theory. For architecture it is how the world grows from 64×64 to 512×512. See D-05.
6. **Other boxes exist.** Late evidence (signals, a second seam, "impossible" materials that match nothing in this box) points to a Second Box. This leaves room for Additional Boxes (M33) without committing to a specific cosmology.
7. **The Creator Question remains open.** The game never answers where the box came from. It only lets the inhabitants ask.

### 7.4 Diegetic mapping of player verbs [CANON]

| Player does | Inside the box it is… |
|---|---|
| Tap / touch | A pressure from nowhere, a warmth, a shadow, a "touch of the presence" |
| Drag an object | An object moving by itself |
| ~~Tilt the phone~~ (dropped, D-15) | — |
| Shake the phone (on hold, D-15) | Tremors, earthquakes |
| Rain / wind tools | Weather appearing from a clear sky, wind without source |
| Pinch / pan / follow | *Nothing* — the camera is invisible to inhabitants (the player's gaze is undetectable… until late-game science finds ways to infer it; see §20.6) |

---

## 8. THE WORLD — SPACE, TERRAIN, CHUNKS, GROWTH

### 8.1 Spatial units [CANON]

| Unit | Definition |
|---|---|
| **Tile** | 1 × 1 world unit on the XZ plane; the atomic cell for terrain, water, soil, vegetation, occupancy |
| **Height level** | Integer 0–15 per tile (stepped "diorama block" look); 1 level = 0.4 world units vertical (tunable; 0.25 looked too flat in M1.3) |
| **Chunk** | 16 × 16 tiles; the unit of storage, streaming, meshing, simulation-tiering and saving |
| **World coordinates** | `Vector2i` tile coordinates, may be negative; chunk coordinate = floor(tile / 16) |
| **Region** | A named cluster of chunks (valley, mountains, coast) derived from terrain + inhabitant naming (§19.5) |

Coordinates are always converted through one utility (`WorldCoords`) — never hand-rolled division — so that negative coordinates floor correctly.

### 8.2 World sizes [CANON]

- **Initial world:** 64 × 64 tiles (4 × 4 chunks). Vertical slice may use 32 × 32.
- **Architecture must support:** 128², 256², 512² and larger via chunk streaming.
- **Never** load the whole world into memory unnecessarily; only actively simulate what needs simulating.

### 8.3 Per-tile layers [CANON]

Stored per chunk as packed arrays (`PackedByteArray`, `PackedFloat32Array`, `PackedInt32Array`) of length 256, *not* as per-tile objects:

| Layer | Type | Meaning |
|---|---|---|
| `height` | u8 | Terrain height level 0–15 |
| `terrain` | u8 | Terrain type id (grass, dirt, sand, rock, snow, farmland, road, riverbed, mud, ash…) |
| `water` | f32 | Water depth above terrain (world units) |
| `moisture` | u8 | Soil moisture 0–255 |
| `fertility` | u8 | Soil fertility 0–255 |
| `vegetation` | u8 | Ground cover density 0–255 (grass → bush) |
| `traffic` | u8 | Foot-traffic accumulator; decays; drives desire paths → roads |
| `temperature_offset` | i8 | Local microclimate (altitude, water proximity) |
| `flags` | i32 bitfield | `SEEN_BY_PLAYER`, `EXPLORED_BY_CIV`, `MAPPED_BY_CIV`, `MODIFIED`, `OCCUPIED`, `BLOCKED`, `SACRED`, `RUIN`, `EDGE`… |

Entities (people, animals, objects, buildings, resource nodes) are **not** stored in tile arrays; they live in registries and are found via a **spatial index** (chunk-bucketed hash).

### 8.4 Procedural generation [CANON]

- A single **world seed** (64-bit int, displayed as a copyable string in Advanced Settings) drives everything via named RNG streams (`seed ⊕ hash("terrain")`, `seed ⊕ hash("resources")`, …) so systems are independently deterministic.
- The seed controls: terrain, resources, climate, initial ecosystem, starting settlement, environmental conditions, seeded mysteries.
- **Chunks are generated deterministically on demand** from the seed; only *modifications* are stored (sparse storage for untouched regions). A chunk that has never been modified can be discarded and regenerated identically.

### 8.5 Starting templates [CANON list, PROPOSED parameters]

Every world starts from one of six **start templates**, chosen by seed (or by the player in Advanced New World):

| Template | Shape | Starting tension |
|---|---|---|
| River Valley (default for first world) | Hills on two sides, river through the middle | Floods; rich soil |
| Island | Land in a sea basin | Limited wood/stone; storms |
| Mountain Basin | Ring of high ground, lake in the center | Cold; isolation; ore |
| Forest Clearing | Dense forest, small open glade | Wood abundant; little farmland |
| Coastal Plain | Flat land along one wall-side sea | Wind, storms, fishing |
| Desert Oasis | Dry land, one spring + pond | Water scarcity; heat |

**Rule:** The starting civilization has *enough to survive but not necessarily thrive* — validated by world-gen tests (minimum water within N tiles, minimum food sources, minimum buildable tiles, path connectivity).

### 8.6 World growth — the Box Unfolds [PROPOSED, D-05]

- A world is created with a **box size** (initially 64²). The walls sit at the box bounds.
- The generator can deterministically produce terrain beyond the current walls.
- When civilization pressure reaches the edge (explorers repeatedly reach the wall, population density high, a settlement founded near the edge) *and* the world is below max size, the box may **unfold**: a ring of chunks is added, walls animate outward, and a major historical event is recorded.
- This satisfies "do not hard-code a tiny map", keeps the box physically present, and gives the Box Theory arc its most dramatic evidence.
- Sandbox/Advanced New World can also start with a larger box.

### 8.7 Fog of knowledge [CANON]

Three independent layers:

1. **Player-seen** — tiles the camera has shown (player can always physically explore, even before the civilization knows an area).
2. **Civ-explored** — tiles any inhabitant has visited or seen.
3. **Civ-mapped** — tiles recorded in the civilization's maps (requires cartography knowledge; oral knowledge decays, written maps persist).

The minimap and Regions menu show civ knowledge distinctly from player knowledge. Unknown areas are rendered dimmed/desaturated, never black, so the diorama stays beautiful.

---

## 9. TIME — CLOCK, CALENDAR, SPEEDS, OFFLINE

### 9.1 Clock [PROPOSED defaults, D-04]

| Quantity | Default | Reasoning |
|---|---|---|
| Real seconds per game minute @ Normal | 0.5 s | A full day ≈ **12 real minutes** — short enough to watch a whole day in follow mode (OBSERVER achievement) |
| Days per season | 6 | |
| Seasons per year | 4 (Spring, Summer, Autumn, Winter) | |
| Days per year | 24 | A year ≈ **4.8 real hours** @ Normal |
| Human adulthood | 16 years | ≈ 3.2 real days |
| Life expectancy (early era) | ~45–55 years (high child mortality), rising with medicine to 70+ | A generation ≈ 4 real days; 5 generations (GENERATION achievement) ≈ 3–4 weeks of real time with offline progression |

All of these live in `data/configuration/time_config.tres`. Designers tune pacing here, not in code.

### 9.2 Simulation speeds [CANON]

| Speed | Multiplier | Notes |
|---|---|---|
| Pause | 0× | UI, camera and inspection still work; the world is frozen (ambient visual loops may keep playing subtly) |
| Normal | 1× | Default |
| Fast | 4× | |
| Very Fast | 16× | Automatically lowers simulation detail tiers (§31.6) to hold frame rate |

### 9.3 Ticks and cadences [CANON]

Simulation and rendering are **independently throttled**:

| Cadence | What runs |
|---|---|
| Every frame | Camera, input, visual interpolation of Tier 3–4 entities, particles |
| Sim tick (1 game minute) | Needs decay, action progress for active agents, clock |
| Staggered AI think | Tier 4: every tick · Tier 3: every 2–4 ticks · Tier 2: every ~15 ticks |
| Water step | Fixed 10 Hz for active chunks with a per-frame time budget |
| Game hour | Economy flows, weather transitions, Tier 1 aggregate sim, stats sampling |
| Game day | Aging checks, births/deaths rolls, planning (settlement), knowledge accrual, Tier 0 |
| Season / Year | Season effects, era evaluation, culture consolidation, history summaries |

### 9.4 Offline progression [CANON concept, PROPOSED caps, D-09]

- On close/background: save immediately.
- On resume/launch: elapsed = `now − last_saved_unix_time` (clamped to ≥ 0; clock tampering ignored).
- Elapsed real time is converted to game time at Normal speed **up to 24 real hours**, then with diminishing returns up to a hard cap of **72 real-hour equivalents** (tunable). A player who leaves for a month returns to an older world, not a dead one.
- Offline time is simulated with the **abstract simulator** (§31.8), in day-steps, producing real named births, deaths, constructions, discoveries and events — not just numbers.
- Result is presented as **WHILE YOU WERE GONE** (§26.8).

---

## 10. ENVIRONMENT — WEATHER, SEASONS, WATER, SOIL, VEGETATION

### 10.1 Weather [CANON states]

States: `CLEAR`, `CLOUDY`, `RAIN`, `HEAVY_RAIN`, `STORM`, `WIND`, `SNOW`, `FOG`, plus long-running **conditions** `DROUGHT`, `HEAT_WAVE`, `COLD_SNAP`.

- Weather is a **Markov chain per season**, with transition probabilities in `data/configuration/weather_*.tres`, modulated by climate (from seed/template) and by recent player interventions.
- Weather is global for the initial box; the architecture supports **regional weather cells** (per region) for larger worlds.
- Weather affects: soil moisture, water levels, crops, animal behaviour, people's activities (shelter-seeking, lower work output), mood, disease, fire spread, travel speed, audio, lighting.
- Conditions are detected, not rolled: a **drought** is declared when rainfall over the last N days is below a threshold and moisture falls; it then becomes an event with causal links.

### 10.2 Seasons [CANON]

| Season | Agriculture | Environment | Society |
|---|---|---|---|
| Spring | Planting; growth starts | Rain more likely; animals mate; flowers | Festivals of beginnings may emerge |
| Summer | Growth; crops ripen | Heat; drought risk; long days | Outdoor work; travel |
| Autumn | **Harvest** | Leaves colour and fall; storms | Storage; harvest traditions |
| Winter | Little or no agriculture | Cold; snow; frozen shallow water | Indoor life; consumption of stores; hardship |

The civilization adapts: planting timing, storage building, firewood gathering and seasonal rituals emerge from the needs model, not scripts.

### 10.3 Water [CANON]

A **lightweight cellular heightfield simulation**, not fluid physics.

- Each tile has `water` depth. Each water step, water flows to lower neighbours proportional to the difference in `terrain_height + water_depth`, plus a **gravity bias vector** from box tilt (§23.5).
- **Sources:** springs (seeded), river inflow points, rain (per-tile add), player water tool. **Sinks:** evaporation (temperature/wind dependent), soil absorption (raises moisture), box-edge drains are *not* allowed — water in a box stays in the box, which is itself a clue.
- **Emergent features:** rivers (persistent flow paths), lakes (accumulation basins), floods (overflow onto settled tiles), puddles after rain, drying riverbeds in drought.
- **Water affects:** crops (moisture), settlements (floods damage buildings, drown), wildlife (drinking spots), transportation (fords, later bridges), disease (stagnant water + crowding), erosion (slow height reduction on high-flow tiles, rare, recorded as terrain modification).
- Only active chunks run the fine-grained step; sleeping chunks keep a settled equilibrium and update in coarse steps.

### 10.4 Soil & vegetation [CANON]

- **Moisture** (from rain/water), **fertility** (depleted by farming, restored by fallow/flood silt/later fertilizer tech).
- **Vegetation** spreads to adjacent suitable tiles, dies in drought/cold, is cleared by building and farming, regrows on abandoned land. Forest coverage is a derived statistic.
- Trees are entities (resource nodes) with growth stages; they spawn saplings.

### 10.5 Disasters [CANON]

| Disaster | Natural trigger | Player trigger | Effects |
|---|---|---|---|
| Earthquake | Rare seeded tremor | Strong/Extreme shake, EARTH tool | Scatter objects, damage buildings, injuries, terrain micro-changes, fear, myths |
| Flood | Heavy rain + low terrain | Water tool, tilt pooling | Crop loss, building damage, drowning risk, silt fertility |
| Drought | Weather condition | Suppress rain (late tool), heat | Crop failure → food shortage → migration chains |
| Wildfire | Lightning in dry season, hearth accidents | Late tool, lightning | Forest loss, buildings burned, regrowth |
| Storm | Weather | Rain+Wind tools combined | Damage, injuries, fear |
| Meteor | Very rare natural event (sky object) | Major intervention (late) | Crater, impossible material deposit, massive myth |

---

## 11. RESOURCES & MATERIALS [CANON]

Resources **exist physically** in the world and must be **physically gathered** by people.

| Resource | Where it exists | Gathered by | Used for | Era |
|---|---|---|---|---|
| Food (berries, game, fish, grain, vegetables) | Bushes, animals, water, farms | Foragers, hunters, fishers, farmers | Eating, trade | Early |
| Water | Rivers, lakes, springs, wells | Everyone | Drinking, farming, pottery | Early |
| Wood | Trees | Woodcutters | Building, fire, tools | Early |
| Stone | Rocks, outcrops | Gatherers, masons | Building, tools | Early |
| Clay | Riverbanks, wet soil | Potters | Pottery, bricks | Early–Mid |
| Herbs | Specific vegetation | Herbalists | Medicine | Early–Mid |
| Copper | Ore deposits | Miners | Metalworking | Mid |
| Iron | Ore deposits | Miners | Tools, engineering | Mid |
| Coal | Deposits | Miners | Industry | Late |
| Rare minerals | Deep/rare deposits, meteor sites | Miners | Advanced science | Late |
| **Impossible material** | Ruins, box seams, meteor sites | Anyone who finds it | Mystery chain, Box research | Mystery |

Rules:
- Resource **nodes** (tree, rock, ore vein, berry bush) have quantity and regrowth; depleting them changes the landscape.
- Gathered resources become **resource piles / carried items** — physical entities that can be dropped, stored, stolen by floods, **and moved by the player**. Moving a resource pile is a gentle intervention with real economic consequences.
- **Stockpiles** are physical: storage buildings hold item counts; the settlement's "wealth" is the sum of what is physically stored.

---

## 12. ANIMALS [CANON]

Animals have **simple autonomous behaviour** as small state machines driven by species data.

- **Behaviours:** grazing, hunting, fleeing, mating, migrating, sleeping, drinking, nesting.
- **Starter species (vertical slice):** birds (ambient flocks), deer-like grazers, rabbits/small grazers, fish (in water, mostly aggregate), one small predator (fox/wolf-like), later domesticated animals (goats/chickens) via agriculture tech.
- **Populations respond to the environment:** food availability, water, season, hunting pressure, habitat loss. When a chunk is not active, species populations are **aggregate counts per chunk** with birth/death/migration rates; individuals are materialized when the chunk becomes active.
- Animals react to the player too (calming tool, fear of shakes), and people may interpret unusual animal behaviour as omens.
- Species are data resources (`data/species/*.tres`): diet, habitat, speed, herd size, fear, reproduction rate, products (meat, hide, eggs), domesticable flag.

---

## 13. THE INHABITANTS — DATA, TRAITS, NEEDS, BEHAVIOUR

### 13.1 Inhabitants are data, not node trees [CANON]

Never create a heavyweight Godot Node per person. A person is a `PersonData` object (RefCounted) in a `PersonRegistry`. Only people that need to be drawn get a **pooled view proxy** (§31.7).

**PersonData (canonical fields):**

| Field | Type | Notes |
|---|---|---|
| `id` | int | Persistent, never reused |
| `given_name`, `family_name` | String | Generated from the culture's phonology (§19.5) |
| `birth_tick` | int | Age derived from clock; never store "age" as the truth |
| `sex`, `life_stage` | enum | CHILD / ADOLESCENT / ADULT / ELDER |
| `health` | float 0–1 | Plus `injuries: Array`, `conditions: Array` (disease, pregnancy) |
| `traits` | PackedFloat32Array | One value −1…+1 per trait axis (§13.2) |
| `needs` | PackedFloat32Array | One value 0…1 per need (§13.3) |
| `mood`, `stress` | float | Derived each think from needs + recent memories |
| `occupation_id` | StringName | Data-driven occupation |
| `skills` | Dictionary | occupation/skill → level |
| `household_id`, `home_building_id`, `workplace_id`, `settlement_id` | int | |
| `parents`, `children`, `partner_id` | ints | Lineage persists after death |
| `relationships` | handled by `RelationshipStore` | Sparse, capped (§16.1) |
| `memory_ids` | Array[int] | Into `MemoryStore` (§15) |
| `beliefs` | PackedFloat32Array | Interpretation weights (§14.3) |
| `knowledge` | Dictionary | Known concepts, vocabulary, techniques |
| `goals` | Array | Current long-term goals (build home, find partner, learn craft, investigate anomaly) |
| `current_action` | ActionState | Serializable current step (§13.4) |
| `position`, `sub_tile_offset`, `facing` | Vector2i / Vector2 / float | |
| `sim_tier` | int | Runtime only (not saved) |
| `significance` | float | Historical importance accumulator (§21.5) |
| `flags` | int | `MARKED_IMPORTANT`, `FOLLOWED`, `TOUCHED_BY_PLAYER`, `QUARANTINED`… |
| `appearance` | Dictionary | Body type, palette, accessory ids (§28.4) |

### 13.2 Personality traits [CANON]

Traits are **bipolar axes** (−1…+1), which covers the spec's list compactly and allows gradients:

| Axis (−1 ↔ +1) | Spec traits covered |
|---|---|
| Cautious ↔ Curious | cautious, curious |
| Fearful ↔ Brave | fearful, brave |
| Selfish ↔ Generous | selfish, generous |
| Introverted ↔ Social | introverted, social |
| Lazy ↔ Ambitious | lazy, ambitious |
| Skeptical ↔ Spiritual | skeptical, spiritual |
| Peaceful ↔ Aggressive | peaceful, aggressive |
| Trusting ↔ Suspicious | suspicious (and loyalty proxy) |
| Homebound ↔ Adventurous | adventurous |
| — Intelligence (0…1) | intelligent |
| — Creativity (0…1) | creative |
| — Loyalty (0…1) | loyal |

- Children inherit trait means from both parents + mutation noise + upbringing drift (experiences nudge traits slowly — a child touched often by the player may grow more spiritual or more curious).
- Traits feed decision scoring, reactions, interpretation, social compatibility and occupation choice.
- **Controlled randomness:** all choices use weighted sampling with a per-person "temperature" (creative/impulsive people are less predictable). Never pure argmax; never pure random.

### 13.3 Needs [CANON]

| Need | Decays from | Satisfied by |
|---|---|---|
| Hunger | Time, work | Eating food |
| Thirst | Time, heat | Drinking water |
| Sleep (energy) | Time awake, work | Sleeping (home best) |
| Safety | Danger, disasters, predators, anomalies (for fearful people) | Shelter, company, calm |
| Shelter / warmth | Weather, cold, no home | Home, fire, clothing |
| Socialization | Time alone (scaled by social trait) | Conversation, shared meals, festivals |
| Purpose | Idleness (scaled by ambition) | Work, crafting, learning |
| Family | Separation from family | Time with household |
| Curiosity | Monotony (scaled by curiosity) | Exploring, investigating anomalies, learning |
| Wealth | (Later eras) | Possessions, trade |
| Status | (Later eras) | Respect, roles, achievements |
| Spiritual fulfillment | Time (scaled by spirituality) | Prayer, ritual, sacred places |

Needs decay rates and weights per life stage are data (`data/configuration/needs_config.tres`). Later-era needs (wealth, status) activate as the civilization's economy/culture unlocks them.

### 13.4 Decision making — Utility AI + action plans [CANON approach]

People must **never simply wander randomly**. They pursue goals.

1. **Evaluate** (on think ticks, staggered): score candidate **activities** (Eat, Drink, Sleep, Work, Socialize, GoHome, Explore, Investigate, Pray, Play, Build, Gather, Farm, Flee, SeekShelter, Care-for-child, Attend-event…) with utility curves over needs, traits, schedule, time of day, weather, settlement jobs and nearby stimuli.
2. **Select** via weighted sampling among the top candidates (controlled randomness), with **hysteresis** so people don't flip-flop mid-task.
3. **Plan** a short sequence of **steps**: `WalkTo(target) → Perform(action, duration) → …` (e.g., hungry: *HOME → FOOD STORE → EAT → WORK*).
4. **Execute** step by step; each step is a small serializable struct (so saves mid-action restore exactly).
5. **Interrupt** on high-salience stimuli (player touch, earthquake, predator, fire), via the Perception system (§14).

The chosen activity and its reason are visible on the person card ("Going home — tired") and in the debug AI inspector ("scores: Eat 0.71, Work 0.64, …").

### 13.5 Schedules & routines [CANON]

Each occupation × life stage has a **routine template** (data), e.g.:

```
06:00 wake · 07:00 breakfast · 08:00 work · 12:00 lunch/talk to neighbour · 13:00 work
17:00 social / market · 19:00 family dinner · 21:00 sleep
```

Routines are *soft*: they bias utility scores by time of day rather than forcing actions. A curious farmer may skip work to investigate a strange rock; a lazy one may nap. Seasons shift routines (harvest days are long; winter days start late).

### 13.6 Occupations [CANON approach]

Data-driven (`data/occupations/*.tres`), unlocked by conditions (tech, buildings, resources). Early: forager, farmer, woodcutter, gatherer, hunter, fisher, builder, child, elder/storyteller, caregiver. Mid: potter, smith, miner, trader, priest/shaman, healer, scribe, teacher, leader. Late: scientist, engineer, astronomer, historian, factory worker, researcher, box researcher. People choose occupations by settlement need × skill × traits; occupations can change.

### 13.7 Movement & pathfinding [CANON approach]

- Tile-grid pathfinding (`AStarGrid2D`) with costs for slope, water depth, vegetation, roads (cheaper), buildings (blocked).
- Paths are requested through a **path service** with a per-frame budget and a cache; long-distance paths across chunks use a coarse chunk-level graph then refine (added in the scale milestone).
- Walking speed depends on age, health, load, terrain, weather.
- Foot traffic accumulates on tiles → desire paths → roads (§17.4).

---

## 14. THE INTERPRETATION SYSTEM (SIGNATURE MECHANIC) [CANON]

> "If the player touches a person, that person should not simply receive a command. The interaction is interpreted."

This is the game's most important mechanic. Everything the player does passes through one pipeline:

```
PLAYER INTERVENTION ─► STIMULUS ─► PERCEPTION ─► INTERPRETATION ─► EMOTION ─► REACTION ─► MEMORY ─► BELIEF UPDATE
                           │                                                     │
                           └────────► ANOMALY ARCHIVE (science)  ◄───── TELLING OTHERS (gossip)
```

### 14.1 Stimulus

Every player intervention (and many natural events) emits a `Stimulus`:

| Field | Example |
|---|---|
| `type` | `TOUCH`, `OBJECT_MOVED`, `OBJECT_APPEARED`, `RAIN_FROM_CLEAR_SKY`, `SOURCELESS_WIND`, `WORLD_TILT`, `TREMOR`, `WATER_DISTURBED`, `LIGHT_ANOMALY`, `NATURAL_STORM`… |
| `origin` | `PLAYER` / `NATURE` / `PERSON` (hidden from inhabitants) |
| `anomalous` | Does it violate expectations given the civilization's knowledge? (Rain from a clear sky: yes. Rain from clouds: no.) |
| `position`, `radius`, `intensity`, `tick` | |
| `target_id` | For direct contact (touch) |

### 14.2 Perception

Each nearby person (radius scaled by intensity) computes **salience** = intensity × proximity × attention (sleeping, busy, distracted lower it) × anomaly factor. Below threshold: unnoticed (but may be noticed later as a consequence — "someone found the rock"). Direct touch is always perceived.

### 14.3 Interpretation

Possible interpretations (spec §19):

| Interpretation | Requirements / boosts |
|---|---|
| `NATURAL_PHENOMENON` | Default for skeptics and non-anomalous events |
| `SPIRIT` | Spiritual; local/small stimuli; animistic culture |
| `DEITY` | Spiritual; large or beneficial stimuli; existing deity myth in culture |
| `ANCESTOR` | Requires remembered deaths; boosted near graves or after a family death |
| `EXPERIMENT` | Requires scientific method knowledge; "someone is testing us" |
| `UNKNOWN_INTELLIGENCE` | Curious + intelligent; repeated patterned stimuli |
| `MULTIPLE_ENTITIES` | Conflicting experiences (help and harm) in memory |
| `HALLUCINATION` | Skeptical; lone witness; low intensity; tired/sick witness |
| `PHYSICS` | Requires natural philosophy; "an undiscovered force" |

Scoring per candidate:

```
score = culture_prior[settlement]                  # what "people like me" believe
      + Σ trait_weight[trait] · trait_value        # personality
      + evidence_from_own_memories                 # confirmation bias
      + social_influence(trusted relations)        # what my friends/family/leader believe
      + context_bonus (prayed recently? relative died? rain during drought?)
      + knowledge_gate (−∞ if concept unknown)
      + noise (temperature from traits)
choice = weighted_sample(softmax(scores / temperature))
```

The **same action on different inhabitants produces different results** by construction. Children have weak priors and high curiosity (fascination); religious leaders have strong DEITY priors (signs); scientists have PHYSICS/EXPERIMENT access (investigation).

### 14.4 Emotion & reaction

From interpretation + traits + intensity, compute **fear**, **curiosity**, **awe**, **joy**, **annoyance**. Then choose a **reaction** from data tables:

| Reaction | Typically when |
|---|---|
| Look toward the touch / look around | Low intensity, any |
| Become curious / investigate | Curious, low fear |
| Freeze | Fearful, surprise |
| Run | Fearful, high intensity |
| Yell | Fearful or aggressive |
| Laugh / wave | Children, joyful, trusting |
| Pray | Spiritual + DEITY/SPIRIT/ANCESTOR |
| Dismiss / ignore | Skeptic + NATURAL/HALLUCINATION |
| Tell someone | Social; strong emotion (creates secondhand memory in listener) |
| Report to leader | Loyal; community-level anomaly |
| Interpret as weather | NATURAL + weather-like stimuli |
| Remember the event | Always, if salience high enough (§15) |

Reactions are visible: small animations (turn, jump, run, kneel, wave), **emote icons** above heads (❗ ❓ 🙏 💬 ♪), and a line on the person card.

### 14.5 Repetition changes everything

Familiarity with a phenomenon changes future reactions: first touch → fear or wonder; tenth touch → expectation, ritual, dependence, annoyance or a scientific log entry. "What happens if I touch the same person repeatedly?" must have a rich answer: the person may become a local prophet, a skeptic may become a believer (or vice versa), a child may grow up to be the first scientist to study the phenomenon.

### 14.6 The single choke point

**All player interventions must go through `InteractionManager.apply_intervention()`**, which (1) validates, (2) applies physical effects via the owning system, (3) emits the stimulus, (4) appends to **Player History** and **player statistics**, and (5) records an **anomaly** if inhabitants could observe it. No tool may change world state directly. This is what later makes science, myth and communication possible.

---

## 15. MEMORY, STORIES & MYTH [CANON]

### 15.1 Memory types

| Type | Owner | Example |
|---|---|---|
| **Personal** | A person | "At age 23, Mara felt the mysterious presence touch her." |
| **Family** | A household/lineage; passed parent → child | "Grandmother Mara was touched by the Presence at the river." |
| **Cultural** | A settlement/culture pool | "The river spirit touches the chosen." |
| **Historical** | The civilization (event log) | "Year 3: First recorded Touch." |
| **Mythological** | Culture; distorted over retellings | "In the First Days, the Great Hand lifted Mara to the sky." |

### 15.2 Memory record

`Memory { id, owner_kind, owner_id, kind, subject_type, stimulus_id?, event_id?, tick, location, interpretation, emotions, intensity, importance, source (DIRECT | TOLD_BY(id) | INHERITED | TAUGHT | WRITTEN), fidelity (1.0 direct → decays per retelling), text_key, text_params }`

- **Text is generated from templates** keyed by `subject_type × interpretation`, e.g. DEITY → "felt the hand of the Sky", NATURAL → "felt a strange pressure — probably the wind", HALLUCINATION → "thought something touched her, but decided she was tired".
- **Importance** = intensity × emotional weight × personal relevance × novelty. Low-importance memories decay and are forgotten; each person holds at most N (default 32) personal memories; compaction keeps the most important, merging repetitive ones ("was touched by the Presence 14 times").
- Memories **affect later behaviour**: fear of a location, seeking a sacred spot, avoiding the river after a flood, trusting/distrusting the phenomenon, occupation choice (a child who witnessed a miracle may become a priest; one who studied a strange rock may become a scientist).

### 15.3 Transmission

- **Gossip:** during socialization, people share their most important recent memories. The listener gets a secondhand memory (`fidelity × 0.85`, possibly re-interpreted by *their* traits).
- **Family stories:** parents pass top memories to children during childhood (bedtime stories — visible at 20:00 in follow mode).
- **Cultural pool:** when N people in a settlement hold memories of the same subject, the pool gains/strengthens a cultural memory.
- **Writing** (tech) makes memories persistent: written records do not decay and can be re-read by scholars centuries later — a key difference between oral and literate eras.

### 15.4 Myth formation

Each retelling can **mutate** (probability scales with the teller's creativity and inversely with literacy): intensity exaggerates, time shifts to "the first days", location moves to a landmark, the actor is **personified** and named. When a cluster of cultural memories about the same stimulus type is attributed to one kind of agent, a **Myth** entity forms:

> Repeated player-created rain during droughts → **"The Rainbringer"** (in one culture) or **"The Weeping Sky"** (in another) or "a recurring atmospheric anomaly" (in a scientific culture).

Myths have: name (vocabulary word + epithet gloss), attributes (bringer of rain, toucher of the chosen), sentiment (benevolent/fearsome/capricious), believer count, sacred locations, associated rituals (§19.3). Myths can split, merge, be debunked, or be rediscovered by historians who propose "new explanations for the Great Flood".

---

## 16. RELATIONSHIPS, FAMILIES, LIFE & DEATH [CANON]

### 16.1 Relationships

Sparse store keyed by ordered pair `(a, b)`; each person keeps at most ~30 tracked relationships (strangers pruned first).

`Relationship { familiarity 0–1, affinity −1…+1, trust −1…+1, respect, kind_flags: ACQUAINTANCE | FRIEND | RIVAL | ENEMY | PARTNER | SPOUSE | PARENT | CHILD | SIBLING | EMPLOYER | EMPLOYEE | LEADER | FOLLOWER, last_interaction_tick, history (small ring of notable shared events) }`

- **Evolves:** strangers → acquaintances (proximity, work together) → friends (positive interactions, trait compatibility) → rivals/enemies (conflicts, competition, betrayal, differing beliefs) → reconciliation (shared disaster survival, mediation, time).
- Social interactions (conversation, help, gift, argument, fight, flirtation, teaching) are events that modify values and may create memories.
- Families can break apart (separation, feuds, migration of one branch).

### 16.2 Lifecycle

| Stage | Behaviour |
|---|---|
| Birth | Requires partners, household food security, housing; event + memories for parents; child named by culture/family conventions (may be named after important ancestors — legacy!) |
| Childhood | Play, learn from parents/elders, inherit stories and vocabulary; fascinated by anomalies |
| Adolescence | Apprenticeship; occupation leaning; first strong beliefs |
| Adulthood | Work, partnership, parenting, leadership, invention |
| Elder | Reduced work, storytelling, teaching; carries cultural memory |
| Death | Old age, illness, injury, starvation, disaster, conflict, accident |

- **Inheritance:** home, possessions, role (maybe), and **family memories** pass to heirs.
- **Family trees** are always reconstructible from `parents`/`children` ids, including the dead (archive).

### 16.3 Death creates history

Death never simply removes an entity. The person moves from the live registry to the **HistoricalPerson archive** (compact record):

`name, birth/death year, age, cause, family links, occupation(s), accomplishments (events they were principal in), top memories, significance, burial location`

Graves are physical, tappable places: each settlement lays its dead in **one cemetery**, a fenced plot near its fire whose card lists everyone who lies there (each can be read in turn). A person who lived 80 years, founded a village and was touched by the Presence 20 times may become a **historical figure** and later a **myth**.

---

## 17. SETTLEMENTS, BUILDINGS & ECONOMY

### 17.1 Settlements [CANON]

A `Settlement` is an emergent aggregate: members, households, buildings, stockpiles, job board, cultural pool, leader(s), name (generated by inhabitants' language), founding event, specialization, territory (claimed tiles/chunks).

Settlement tiers (derived): Camp → Hamlet → Village → Town → City. New settlements are founded by **migration** (overcrowding, scarcity, conflict, exploration, disaster) — the founding family's leader becomes a historically significant founder.

### 17.2 Buildings emerge from needs [CANON]

The player never places buildings. A **SettlementPlanner** evaluates needs each game day and proposes **projects**:

| Need signal | Project |
|---|---|
| Households without home / exposure to weather | Shelter → Hut → House |
| Food spoilage, stock overflow, winter coming | Storage |
| Water far from homes, drought | Well |
| Fertile land + agriculture knowledge | Farm plots |
| Crafting demand + tech | Workshop |
| Trade volume | Market |
| Strong shared beliefs / myth sacred site | Shrine → Temple |
| Literacy + children | School |
| Leadership institutions | Hall / Government building |
| Industrial tech | Factory |
| Science knowledge | Laboratory → Research center, Observatory |
| Box research | Edge station, Signal structures (endgame) |

Projects are sited by scoring tiles (proximity, flatness, flood risk from memory!, sacredness, road access). Builders **physically fetch materials** and construction progresses visibly (scaffold → frame → complete). Buildings are data (`data/buildings/*.tres`): footprint, materials, capacity, tech requirement, function tags, era visual variants.

**Era groups:** *Early* — shelters, huts, farms, wells, storage. *Later* — workshops, markets, temples, schools, government buildings, factories, laboratories. *Eventually* — research centers, observatories, advanced laboratories.

### 17.3 Economy [CANON]

- **Production** by work actions on nodes/buildings; **consumption** by needs and construction; **storage** physical.
- A settlement-level **Job Board** posts tasks (gather wood ×20, build well, harvest field 3, carry food to storage) scored into individuals' utility evaluation — people *choose* jobs; nobody is assigned.
- **Specialization** emerges from local resources and skills (farming town, mining town, fishing town).
- **Trade** between settlements: traders/caravans carry surpluses along roads; abstracted when out of view.
- **Inequality** is derived (distribution of stored wealth/housing quality across households).

### 17.4 Roads [CANON]

Roads emerge: foot traffic increments a tile's `traffic`; above thresholds the terrain becomes a dirt path → road (with construction tech) → paved. Bridges are projects triggered by frequent river crossings ("Construction of the first bridge has begun.").

### 17.5 Governance & conflict [PROPOSED detail]

- **Leaders emerge** by respect/status/relationships (elder, founder, priest, strongest), later by institutions (council, chief, elected, dynastic) derived from culture values.
- **Political groups/factions** form around beliefs (e.g., Believers of the Rainbringer vs Skeptics) or interests (farmers vs miners).
- **Conflict** between settlements: disputes over resources/territory → raids → war (abstracted battles with casualties, heroes and survivors recorded) → borders → possibly new culture. Wars are rare, costly, and a primary source of history.

---

## 18. KNOWLEDGE & TECHNOLOGY [CANON]

### 18.1 Technology arises from conditions

Never "Year 50 = Iron". A technology becomes a **discovery opportunity** when:

```
resource availability  +  knowledge (domain points)  +  population  +  specialists  (+ prerequisite techs, buildings)
      = discovery opportunity → daily chance → a specific person discovers it (inventor)
```

- **Knowledge domains:** Nature, Craft, Agriculture, Construction, Medicine, Mathematics, Astronomy, Language/Record, Social, **Anomaly** (knowledge about the unexplained).
- Knowledge points accrue from work, curiosity, teaching, observation, failure (a crop failure teaches agriculture), and **player interventions** (a rock the player placed may be the first flint discovered; rain from a clear sky feeds Anomaly knowledge).
- Knowledge is **held by people**: oral knowledge can be **lost** when holders die without students; writing and schools preserve it.

### 18.2 Technology chain (data-driven, `data/technologies/*.tres`)

```
Fire → Foraging tools → Agriculture → Animal husbandry → Pottery → Weaving
     → Copper working → Writing → Mathematics → Bronze/Iron metalworking → Engineering (roads, bridges, aqueducts)
     → Astronomy → Medicine → Natural philosophy → Scientific method
     → Printing → Mechanics → Industrialization → Electricity → Chemistry
     → Computing → Advanced Science → Box Theory (research line) → Communication (research line)
```

Each `TechnologyDef`: `id, name, domain, prerequisites, required_resources_known, knowledge_threshold, min_population, specialist_occupation, required_buildings, base_daily_chance, unlocks (buildings, occupations, actions, interpretations, vocabulary, visuals), era_weight`.

### 18.2a Fishing and boats [CANON — owner's request, 2026-10-05; built in M19.5]

Fish have been in the water since M7.4 (one stock for the box) but nobody fished. Fishing comes first, then boats as a line of their own in the technology chain, each step letting the fishers go further and bring back more:

| Step | What it is | Comes from (conditions, not dates) | What it changes |
|---|---|---|---|
| **Fishing** (no technology) | A **fisher** (occupation) fishes from the bank with a line or a fish trap | Water near home with fish in it | Fish into the stores (it keeps a day or two); a second food that does not come from the land — and goes on in winter (through a hole in the ice, more slowly) |
| **Raft** (technology) | Logs lashed together, poled along | Toolmaking + wood + someone who fishes | Fishers fish from a raft on deeper water: more fish; the raft lies at a landing on the bank |
| **Dugout canoe** | A trunk hollowed out | Raft + toolmaking skill + years of fishing (knowledge) | Faster, further, more carried; fishing down the river; a canoe can carry goods to a settlement downriver (trade) |
| **Nets** | Woven nets | Weaving + a fisher | A catch several times a line's |
| **Plank boat** | Boards on a frame | Canoe + engineering (or metal tools) | Bigger catches, crossing wide water without a bridge, trade along the water |
| **Sail** | Cloth on a mast | Plank boat + weaving | The far shore; sea fishing where the box has a sea (Coastal Plain) |

Each step is **visible** (§18.3): a raft, then a canoe, then a boat at the landing and out on the water with someone in it; nets drying on racks by the shore. Fish run out where they are taken too hard (the stock refills in days), so a fishing settlement learns to spread out — and a bad fishing year is a story.
### 18.3 Visible change

Every tech must visibly change something: new buildings, tools in hands, clothing, light at night (fire → oil lamps → electric lights), roads, sounds, occupations, vocabulary, statistics, how people *interpret* the player.

---

## 19. CULTURE, BELIEF & LANGUAGE

### 19.1 Culture profile [CANON]

Each settlement (and larger culture groups) has a profile derived from its members and history:
`values (e.g., tradition↔innovation, collectivism↔individualism, piety↔skepticism), dominant interpretations of the Presence, myths, traditions, rituals, holidays, architecture style, clothing palette, music style, art motifs, lexicon, taboos, sacred places`.

### 19.2 Emergence rule

Culture emerges from **repeated shared experiences**. A tradition forms when an event type recurs with emotional weight and shared interpretation; it can fade when conditions change.

### 19.3 Traditions, rituals, holidays

| Source | Example emergent result |
|---|---|
| Player makes rain during droughts, repeatedly | "Rain dance" ritual at drought onset; the Rainbringer festival |
| Earthquakes after the harvest | Offering stones placed on hills in autumn |
| The player often touches children | "Blessing of the Young" ceremony |
| A great flood | Annual "Day of High Water" remembrance; homes built on high ground (architecture) |
| First bridge | Bridge festival |
| Player rarely intervenes | Self-reliance values; skeptic culture; faster innovation |

**Player actions can become traditions** — this is a core promise.

### 19.4 Religion & belief [CANON]

No predefined religion. Beliefs emerge from experiences via the interpretation system. Multiple beliefs coexist; religions can be founded (by a significant person — "religious founder" is an important-person category), schism, spread by migration and trade, and decline under scientific scrutiny or revive after miracles.

### 19.5 Language — structured vocabulary [CANON]

No natural-language AI. A **Concept registry** (objects, events, player interactions, locations, people, disasters, discoveries) and a **culture Lexicon**:

- Each culture has a **phonology** (syllable inventory, seeded) used to generate names and words.
- A concept gets a **word** when it is encountered often enough to need one (frequency threshold in the cultural pool).
- Words are **inherited** by children, **borrowed** through trade/migration, and **drift** between separated settlements.
- The UI shows words with **glosses**: *"Velun (the Rainbringer)"*, *"the Edge"* for the box wall.
- Place names come from the lexicon + landmarks: "Northwatch", "River Town", generated as `[lexicon word]` or translated gloss.

---

## 20. SCIENCE, ANOMALIES & BOX RESEARCH

### 20.1 The anomaly archive [CANON]

Every observable player intervention (and rare natural oddities) is recorded as an **Anomaly** in the civilization's archive — *only to the degree inhabitants witnessed it*. Before writing, the archive is oral (memories); after writing, it is persistent records.

### 20.2 Scientists investigate [CANON]

Once natural philosophy exists, **scientists** (and before them, curious individuals) pick unexplained anomalies to investigate: strange weather, player interactions, earthquakes, unexplained objects, world boundaries, gravitational anomalies (tilts), recurring patterns.

Investigation = travel to site, observe, record, compare with archive, run **correlation checks**:

| Correlation (in-world) | What it secretly reveals |
|---|---|
| Anomalies cluster at certain times of day | **The player's real play schedule** ("The phenomena occur mostly in the evening") |
| ~~Tilts always affect the entire world at once~~ (dropped, D-15) | ~~A single external force~~ — now: several independent patterns, each held with confidence (M18) |
| Rain from clear skies after droughts | A responsive agent |
| Objects move only where people are watching | The observer "looks" where it acts |
| Water always flows back; nothing leaves the Edge | Enclosure |

These generate notifications like: *"Scientists noticed a strange correlation between rainfall and your interactions."*

### 20.3 Box research track [CANON milestones, PROPOSED order]

1. **Anomaly noticed** — first recorded unexplained event.
2. **Pattern** — a scholar proposes the anomalies are connected.
3. **External force hypothesis** — independent patterns, held with confidence, point to a single force outside the world (tilts dropped, D-15).
4. **Edge expeditions** — explorers reach and study the wall; impossible geometry.
5. **The Sky's Ceiling** — high observations reveal structure above.
6. **The Edge Moved** — observed during a box unfolding (if it happens).
7. **THE BOX THEORY** — major historical event; society debates (believers, skeptics, religious reframings).
8. **The Observer** — conclusion that an intelligence is interacting.
9. **Communication attempts** (§22.4).
10. **The Outside / The Second Box / The Creator Question** — post-endgame revelations.

### 20.4 Science vs faith

Scientific and religious interpretations compete. Neither is "right" by design; the player's behaviour shifts the balance (predictable, patterned behaviour aids science; capricious, dramatic behaviour feeds myth).

### 20.5 Rules

- Never reveal the whole mystery. Each stage should take a long time and depend on real conditions (knowledge, literacy, explorers, observations).
- Scientific breakthroughs have named discoverers who become important people.

### 20.6 Inferring the player's gaze (late, optional) [PROPOSED]

With advanced science, inhabitants may notice that anomalies occur more where "the light is watched" (camera focus). This lets late-game communication respond to *where the player looks*. Must be subtle and optional.

---

## 21. HISTORY, EVENTS & THE STORY ENGINE

### 21.1 Events [CANON]

A `WorldEvent` is a persistent record:

`{ id, type, tick, position?, region_id?, settlement_id?, participants[], causes[] (event ids), effects, significance, visibility (who knows), text_key, text_params, tags }`

Event types include: births, deaths, marriages, discoveries, accidents, disasters, conflicts, inventions, festivals, migrations, construction, scientific breakthroughs, player interventions, myths formed, eras, box revelations.

### 21.2 Causality is recorded at creation time [CANON — critical architecture]

Whenever a system creates an event *because of* another event or condition, it passes the cause ids:

```
drought(e41) → crop_failure(e44, causes=[e41]) → food_shortage(e45, causes=[e44])
→ migration(e52, causes=[e45]) → founding "Northwatch"(e53, causes=[e52])
```

This makes the story engine possible without guessing.

### 21.3 Story engine [CANON]

Periodically (yearly and on major events) the story engine walks the causal graph, finds **chains** with high cumulative significance, and produces **readable summaries** from templates:

> "The Great Drought of Year 83 caused the northern migration and eventually contributed to the River War."
>
> "The Great Drought triggered the northern migration, which eventually led to the founding of Northwatch."

It also **names** events and eras ("The Great Drought", "The Age of Copper", "The Years of the Leaning World") using significance and the lexicon.

### 21.4 Timeline [CANON]

A vertical, scrollable timeline grouped by year and era; every event is tappable and **centers the camera on where it happened** when possible (or on its participants' graves/descendants if the site is gone). Filters: major events, discoveries, wars, disasters, people, eras, player.

### 21.5 Important people [CANON]

Nobody is predefined as important. **Significance** accrues from events a person is a principal in, weighted by event significance and **firsts** (first scientist, first engineer, first to reach the Edge, founder, inventor, artist, religious founder, revolutionary, disaster survivor, great leader, famous explorer). Above a threshold → Important People list, remembered by descendants, sometimes mythologized.

### 21.6 Legacy [CANON]

A person may invent something, found a city, create a religion, lead a war, discover a resource, save people, cause a disaster or develop a theory. Descendants remember them (family memories), children are named after them, statues/shrines may be built, and their name appears in history summaries.

---

## 22. CIVILIZATION ARC & ENDGAME

### 22.1 Broad phases (derived, never timed) [CANON]

| # | Phase | Entered when (default rule, tunable) | Feels like |
|---|---|---|---|
| 1 | Primitive survival | World start | Foraging band, fire, shelters |
| 2 | Settlement | First permanent homes + storage | A hamlet with routines |
| 3 | Agriculture | Agriculture tech + farms feeding ≥50% | Fields, seasons matter |
| 4 | Villages | ≥1 village tier settlement, specialization | Workshops, first shrine, roads |
| 5 | Cities | Town/City tier + writing | Markets, temples, government |
| 6 | Civilization | Multiple settlements linked by trade/politics | Culture, wars, eras |
| 7 | Scientific development | Scientific method + scientists | Investigations, anomaly science |
| 8 | Industrialization | Industrial techs | Factories, smoke, new sounds, pollution |
| 9 | Advanced civilization | Electricity/computing | Lights at night, labs, observatories |
| 10 | Box investigation | Box research milestones 4–7 | Edge stations, Box Theory debate |
| 11 | Understanding the external world | Observer + communication | Messages, experiments on the player |

**Do not rush.** The player should feel like they are watching history unfold.

### 22.2 No win screen [CANON]

The ultimate goal is **discovery**. Endgame discoveries (Revelations): **THE BOX**, **THE OUTSIDE**, **THE OBSERVER**, **THE SECOND BOX**, **THE CREATOR QUESTION**. The game continues after all of them.

### 22.3 Post-endgame [CANON]

After the box is discovered, the world becomes stranger: scientists attempt communication; deliberate experiments on the world to provoke the player; people try to attract attention; structures built *for the player*; messages; mathematical patterns; attempts to predict the player's behaviour; disagreement about the player's existence.

> Open the game → **NEW DISCOVERY** — *"Someone has left a message."* → zoom in → a giant symbol built outside the city.

### 22.4 Player communication [CANON concept, PROPOSED protocol]

Only after the simulation foundation is stable. Mechanisms: **tap patterns**, **arranged objects**, **environmental signals** (rain, light, tilt), later **simple text/voice**.

Proposed emergent protocol:
1. Inhabitants build a **count** (e.g., three stone circles).
2. If the player responds with a matching pattern (three taps, three rocks) near it, researchers record a **response**.
3. They escalate: yes/no conventions (tap once = yes?), counting sequences, primes, symbols from their lexicon.
4. The civilization maintains a **Communication Log** the player can read, showing what they *think* the player said.
Voice/text input only as an optional, clearly-permissioned late feature (microphone permission requested only on activation, §31.12).

---

## 23. THE PLAYER — POWERS, TOOLS, GESTURES, SENSORS

### 23.1 Gestures [CANON]

| Gesture | Default meaning | Notes |
|---|---|---|
| **Tap** | Interact with what's under the finger (context-dependent by tool) | Generous hit radius; entity priority (§23.3) |
| **Long press** (≥450 ms, within slop) | Open contextual interaction menu | Haptic tick on open |
| **One-finger drag** | Pan camera (HAND tool on empty ground); drag object if grabbing | 10 dp slop before drag starts |
| **Pinch** | Zoom around the pinch focal point | Min/max zoom clamped, soft rubber-band |
| **Two-finger drag** | Alternate pan; optional twist = rotate view (yaw) | |
| **Double tap** | Context: on entity → focus; on empty → zoom in step | |
| **Swipe** (fast drag) | Context: swipe through water (ripples/push), push loose objects, swipe across terrain to inspect, swipe timeline | Distinguished from pan by velocity + tool |
| ~~**Tilt**~~ | Dropped (D-15) | — |
| **Shake** | Tremor/earthquake by intensity class — on hold (D-15), with the disasters | Cooldowns |
| **Rotate phone** | Portrait ↔ landscape layout; (later, optional) gyroscope twist → swirling wind | |

Everything must be usable by touch alone. Desktop development uses **mouse emulation** (left = touch, wheel = pinch, right-drag = two-finger, keyboard = virtual tilt/shake) but the game never assumes a mouse.

### 23.2 Tool bar [CANON]

A compact bottom (portrait) / side (landscape) bar. Tools are **revealed progressively** as the player discovers them, never all at once.

| Tool | Actions | Intervention class |
|---|---|---|
| **HAND** (default) | Touch, inspect, move/grab objects, pan | Gentle |
| **OBSERVE** | Study: shows extra info overlays (needs, paths, moods), no stimulus emitted | None (invisible to inhabitants) |
| **WATER** | Scoop/pour, disturb, redirect by dragging a channel | Gentle → Moderate |
| **RAIN** | Hold to rain on an area (duration = amount) | Gentle → Moderate (heavy/long = flood risk) |
| **WIND** | Swipe to create gust in a direction | Moderate |
| **EARTH** | Press to raise/lower terrain a step, disturb ground; strong press = quake | Moderate → Major |
| **OBJECT** | Drop an object (pebble, seed, food, strange object) | Gentle |
| *(later)* **SUN/TEMP** | Warm/cool an area (change temperature) | Moderate |

Each tool has **clear visual feedback** (cursor glyph, area preview ring, particles) and a distinct sound.

### 23.3 Picking priority [CANON]

People are tiny. Tapping must feel precise:
1. Ray from camera → tile under finger.
2. Query the spatial index within a **touch radius** (~24 dp in screen space, converted to world units at current zoom).
3. Priority: **person > animal > loose object > resource node (tree/rock) > building > water/fire > tile/terrain**.
4. Among same priority, nearest to the ray wins; slight **magnetism** to the currently followed/selected entity.

### 23.4 Interventions by severity [CANON]

| Gentle | Moderate | Major |
|---|---|---|
| Touch, move small object, provide food, move a resource, create light rain, calm an animal | Move rocks, redirect water, create wind, change temperature, relocate resources | Earthquake, flood, drought, wildfire, meteor, major storm |

- **The game never punishes experimentation; it generates consequences.**
- **No currency / mana / energy.** Major interventions require **deliberate input** (a sustained gesture, strong shake, or a confirm hold) to prevent accidents, and **short physical cooldowns** (seconds) so one motion can't destroy the simulation. See D-08.
- **Optional protective setting:** "Gentle hands" — disables Major interventions (default ON for the first session, OFF once the player discovers EARTH).

### 23.5 Tilt [DROPPED 2026-10-04, D-15]

> **Dropped** (owner's decision): tilting the phone does not move the world. What follows is kept for the record only. Water pooling, sloshing and "the Leaning" come about without it, or not at all.


- Read smoothed gravity (`Input.get_gravity()` preferred; fall back to low-passed `Input.get_accelerometer()`), subtract the **calibrated baseline**, apply **dead zone** (default 4°), clamp (default 25°), smooth (low-pass).
- Visual: the **whole box** rotates slightly with the device (the camera stays with the viewer), selling the physicality.
- Simulation: tilt produces a **gravity bias vector** fed to water flow and loose-object sliding; people stumble, grab things, look up; anomaly recorded ("the Leaning").
- Sustained tilt pools water on the low side → potential flood (a Moderate/Major consequence, deliberately caused).

### 23.6 Shake [ON HOLD, D-15]

> **On hold**: a violent shake causing an earthquake is still wanted, to be designed together with the other disasters (not yet planned). The pipeline and table below are the earlier design, kept as a starting point.


Not raw spikes. Pipeline: linear acceleration (accelerometer − gravity) → high-pass → magnitude → peak detection → **direction reversal counting** within a window (default 600 ms) → classify by peak magnitude + reversals + duration:

| Class | Effect | Cooldown (default) |
|---|---|---|
| LIGHT | Leaves rustle, pebbles jiggle, birds scatter | 1.5 s |
| MEDIUM | Loose objects scatter, people stumble, small fear | 5 s |
| STRONG | Earthquake (minor): damage chance, injuries possible | 20 s |
| EXTREME | Earthquake (major): buildings collapse, terrain changes, historical event | 60 s (and requires Gentle hands OFF) |

### 23.7 Sensor settings & calibration [ON HOLD, D-15]

> With tilting dropped, only what a shake would need is kept in mind here (shake sensitivity, enable/disable); calibration served tilt.


Settings: tilt sensitivity, shake sensitivity, rotation sensitivity, enable/disable motion controls, recalibrate, reduced motion.
Calibration flow: *"Place your phone flat."* → *"Hold still."* (samples ~1.5 s, rejects if variance too high) → *"Calibration complete."* Also supports calibrating in the current comfortable holding angle ("Use current angle as level").
Devices without gyroscope/accelerometer: tools and features degrade gracefully (tilt/shake hidden; touch equivalents: two-finger "tilt drag" gesture and EARTH tool).

---

## 24. CONSEQUENCES, NOT MORALITY — THE PLAYER RELATIONSHIP MODEL [CANON]

There is **no GOOD GOD / EVIL GOD** meter. Instead the world keeps derived, per-group measurements of how it relates to the player (all derived from memories, beliefs and events — not incremented counters):

| Measure | Derived from |
|---|---|
| **Awareness** | Share of people with any direct/indirect memory of anomalies |
| **Interpretation mix** | Distribution of beliefs (divine, spirit, ancestor, natural, scientific…) |
| **Trust** | Valence of outcomes attributed to the Presence (help vs harm) |
| **Fear** | Emotional weight of fearful anomaly memories |
| **Curiosity / scientific interest** | Investigations, anomaly knowledge |
| **Dependence** | How often crises were resolved by interventions → reduced self-reliance |
| **Independence** | Crises solved without help → innovation bonus, self-reliant values |
| **Divine belief / scientific belief** | Belief shares |
| **Intervention frequency** | Player history rate |

Consequence patterns:
- **Repeated help → dependence.** A village that always gets rain may never dig wells — and suffers when the player stops.
- **Repeated disasters → fear.** Appeasement rituals, fearful architecture, migration away from "cursed" places.
- **Rare intervention → independence.** Faster innovation, skeptic cultures, rich self-made history.
- **Selective help** ("save one village but not another") → jealousy, divergent religions, conflict ("the chosen people").

These are shown in PLAYER → Influence/Reputation as descriptions and trends, not scores.

---

## 25. DISCOVERY, MYSTERIES & SURPRISE

### 25.1 Discovery system [CANON]

Two kinds of discovery, tracked separately:
- **Player discoveries** — things the *player* has found or witnessed (a species, a ruin, a hidden spring, a first event, a mechanic). Recorded in PLAYER → Discoveries.
- **Civilization discoveries** — things the *inhabitants* have discovered (resources, species, locations, technologies, historical facts, artifacts, people, environmental patterns, mysteries, player-related phenomena).

Discovery must feel rewarding: a distinct sound + medium haptic, a card with an illustration/icon, a line in history, and (where sensible) a camera "locate" button.

### 25.2 Seeded mysteries [CANON list, PROPOSED details]

Placed at world generation (deterministic from seed) but dormant until relevant:

| Mystery | Physical form | Unfolds when |
|---|---|---|
| Strange artifact | Buried object with impossible material | Mining/digging/erosion/earthquake exposes it |
| Unexplained ruins | Overgrown foundations older than the civilization | Explorers reach them; historians later date them |
| Ancient structure | Standing stones aligned to box axes | Astronomy reveals alignment with the Edge |
| Recurring anomaly | A spot where water always pools uphill, or a "humming" stone | Scientists log it repeatedly |
| Missing civilization | Ruins + artifacts + inscriptions in an unknown lexicon | Writing + scholars attempt translation |
| Impossible material | Seams of perfectly smooth material (box substrate) | Deep mining, Edge studies |
| Strange terrain pattern | Grid-straight lines visible only from height | Towers/observatories/cartography |

**Do not explain everything immediately.** Each mystery is a multi-step clue chain.

### 25.3 Surprise rule [CANON]

The world should occasionally present something the player didn't expect — especially after absence: a new structure, a scientific discovery, a migration, a new religion, someone investigating the player's interventions. A **Surprise Director** (lightweight) ensures that if nothing notable happened for a long stretch, it raises the chance of natural events (migration season, meteor shower, festival, experiment) — *never* fabricating fake events.

### 25.4 Previous worlds (optional meta) [PROPOSED]

When a player starts a New World, a compact "echo" of the old world (a few names, a symbol, a ruin template) can be seeded into the new box as ruins of a previous civilization. This turns "reset" into lore and supports "evidence of previous civilizations" (M31). Must be opt-out.

---

## 26. UX — FIRST LAUNCH, TUTORIAL, HUD, MENUS, CARDS, NOTIFICATIONS

### 26.1 First launch [CANON]

Magical; no menus, no account, no permission prompts.

1. Black → soft ambience fades in → a closed box on a surface.
2. The lid opens (or the camera descends into the open box) → a small world: a tiny settlement, a few inhabitants, water, trees, birds, quiet ambience, movement, life.
3. The camera settles on **a person walking**.
4. A subtle prompt: ***"Something lives inside."***
5. The player touches → **the person notices**.
No lengthy tutorial. Mechanics are taught through interaction.

### 26.2 The first 10 minutes (progressive discovery) [CANON order]

1. Pan camera → 2. Tap person → 3. Inspect person → 4. Follow person → 5. Discover another inhabitant → 6. Touch world → 7. Tilt phone → 8. See environmental response → 9. Open statistics → 10. Discover first historical event → 11. Observe civilization activity → 12. Discover the first mystery.

### 26.3 Contextual hints [CANON copy style]

Hints appear only when relevant and only until the player performs the action once (tracked in `ftue_state`):

| Trigger | Hint |
|---|---|
| 5 s idle on first launch | "Drag to explore." |
| After first pan, a person on screen | "Try touching someone." |
| After first touch | "Hold to learn more." |
| After opening person card | "Follow them to see their day." |
| ~~After motion detected (motion enabled)~~ | ~~"Something changed when you moved the world."~~ (dropped with tilting, D-15) |
| ~~After ~3 minutes, motion enabled~~ | ~~"Try tilting the box."~~ (dropped, D-15) |
| First event logged | (the ☰ icon glows softly once) |
| First discovery | "Something is buried here…" (diegetic, not instructional) |

Tone: quiet, short, curious. Never exclamation-heavy, never "Great job!".

### 26.4 HUD (minimal) [CANON]

- **Top-left:** ☰ hamburger.
- **Top-right:** clock/date/season glyph + speed control (tap to cycle, long-press for all).
- **Top-center (transient):** notification toasts.
- **Bottom:** tool bar (portrait) / right edge (landscape).
- **Bottom-right corner:** minimap (collapsible) + **Home** button.
- **Contextual:** person card (bottom sheet), locate button, follow banner ("Following Mara · ✕").
All touch targets **≥ 48 dp** (min 44). Nothing opaque covers more of the world than necessary.

### 26.5 Hamburger menu [CANON structure]

A sliding panel (not full-screen on landscape tablets), sections collapsible:

- **WORLD:** Map · World Overview · Regions · Weather · Environment · Resources
- **PEOPLE:** Population · Families · Individuals · Occupations · Relationships · Important People
- **CIVILIZATION:** Settlements · Buildings · Economy · Agriculture · Technology · Culture · Government · Beliefs · Science
- **HISTORY:** Timeline · Major Events · Discoveries · Wars · Disasters · Important People · Historical Eras
- **PLAYER:** Interaction History · Influence · Reputation · Discoveries · Statistics · Box Knowledge · Achievements
- **SETTINGS:** Audio · Haptics · Motion (sensors, calibration) · Graphics · Simulation Speed · Accessibility · Notifications · Save (Continue/Backup/Restore/New World/Reset) · Advanced (seed, copy seed) · Debug (only with debug flag)

Entries for systems not yet unlocked are **hidden**, not greyed (progressive reveal; the menu grows with the world).

### 26.6 Cards & panels [CANON]

**Person card** (bottom sheet, draggable to full): portrait glyph, name, age, occupation, current activity + reason, mood, needs bars, traits (top 3 as words), family (tappable), recent memory, "Today" timeline (follow log). Actions: Observe · Follow · Focus Camera · Learn About · Interact (Touch / Give Gift / Disturb) · Mark Important · View Family · View Memories.

Other targets: **Tree** (Observe · Touch · Shake · Inspect · Remove) · **Water** (Observe · Disturb · Redirect · Drop Object) · **Building** (Inspect · Observe Occupants · Follow Construction · View History) · **Animal** (Observe · Follow · Calm · Touch) · **Rock/object** (Inspect · Move · Touch) · **Grave** (Read · View Family) · **Ruin/artifact** (Inspect · Discoveries).

### 26.7 Notifications [CANON]

- Feel like **discoveries, not chores**. Good: *"Someone has discovered a new use for copper."* Bad: *"Come back in 2 hours!"*
- Prioritize meaningful events; **never spam**: priority score, max ~3 toasts/minute, merge similar ("3 children were born in River Town"), silence during follow mode except high priority.
- Each notification can have a **Locate** action.
- Examples: *"Someone discovered copper." · "A child was born in River Town." · "Three families migrated north." · "A major fire has started." · "Construction of the first bridge has begun." · "A historian has proposed a new explanation for the Great Flood."*
- Android system (push) notifications: **off by default**, opt-in, only for rare major world events, never for engagement nagging.

### 26.8 WHILE YOU WERE GONE [CANON]

Shown on return after meaningful absence (default > 10 real minutes):

```
WHILE YOU WERE GONE
  12 births · 4 deaths · 1 new settlement · 2 discoveries
  1 major storm · 3 buildings completed · 1 unusual scientific observation

  "Something strange happened near the eastern mountains."   [ Locate ]
```

Rules: counts first, then **one intriguing hook** (the highest-curiosity event, phrased vaguely, with Locate). Tapping any line opens its details. Dismissable with one tap.

### 26.9 World events (daily engagement without login rewards) [CANON]

Natural, simulation-driven events the player may join or ignore: *"Rare meteor shower tonight." · "Migration season has begun." · "Scientists are attempting an experiment." · "The harvest festival starts at dusk."*

---

## 27. STATISTICS, PLAYER HISTORY & ACHIEVEMENTS

### 27.1 Statistics [CANON]

**Always derived from simulation data** (sampled into time series by a `StatsRecorder` each game hour/day), never static numbers.

| Category | Stats |
|---|---|
| Population | total, births, deaths, average age, growth, density, children/adults/elderly, migration, age distribution |
| Health | average health, disease, injuries, nutrition, lifespan |
| Economy | food, water, wood, stone, metal, tools, trade, production, consumption |
| Civilization | technology, literacy, scientific knowledge, construction, agriculture, engineering |
| Society | happiness, fear, trust, social cohesion, inequality, conflict, cooperation |
| Environment | temperature, rainfall, water levels, forest coverage, soil quality, wildlife, pollution |
| Player relationship | influence, awareness, trust, fear, divine belief, scientific belief, intervention frequency |

Progressive reveal: start with population, food, weather; unlock more as systems activate. Graphs (sparklines + expandable line charts) where helpful; never overwhelm.

### 27.2 Player history [CANON]

A log of significant interventions with year stamps — "YEAR 3 touched first inhabitant · YEAR 7 created first rain · YEAR 11 caused first earthquake · YEAR 19 moved a boulder · YEAR 31 saved a settlement from drought". The last line is *derived* (the story engine links interventions to outcomes).

### 27.3 Player statistics [CANON]

Total interactions, people touched, objects moved, rain events, disasters caused, disasters prevented, resources manipulated, discoveries, hours observed, civilizations reached, generations witnessed. For reflection, not score.

### 27.4 Achievements (optional, reward interesting behaviour, never grinding) [CANON + PROPOSED extras]

| Achievement | Condition |
|---|---|
| FIRST CONTACT | Interact with your first inhabitant |
| RAINMAKER | Cause rain |
| CHAOS | Cause a major disaster |
| OBSERVER | Watch one person for an entire day |
| GENERATION | Witness a family reach its fifth generation |
| THE HISTORIAN | Discover 100 historical events |
| THE SCIENTIST | Allow civilization to discover a major player-related phenomenon |
| THE BOX | Unlock the first evidence that the world is enclosed |
| *(proposed)* REMEMBERED | A person you touched is remembered by their grandchild |
| *(proposed)* NAMED | The civilization gives you a name |
| *(proposed)* HANDS OFF | Let a settlement survive a disaster without help |
| *(proposed)* THE MESSAGE | Receive the first deliberate message |
| *(proposed)* REPLY | Have your response recognized |

Local only (offline-first); platform achievement integration is a future option.

### 27.5 Sandbox mode [CANON, later]

Separate world type (flagged in save; never mixed with normal progression): unlimited resources, weather control, disaster control, population manipulation, time control, technology unlocks.

---

## 28. VISUAL STYLE GUIDE

### 28.1 Direction [CANON]

A **stylized living diorama**: tabletop miniature, terrarium, mysterious artifact. Priorities: **readability, charm, personality, clean silhouettes, clear interactions, good performance**. Avoid visual complexity. The player must identify **person, building, animal, resource, event** at a glance.

### 28.2 Rendering approach [CANON, D-01 confirmed]

- **3D, low-poly, stepped-tile terrain** (each tile a block at its height level with bevelled edges — reads as "miniature world made of blocks/cork"), perspective camera with narrow FOV (~30–35°) at 45–60° pitch for a tilt-shift miniature feel.
- **Vertex colours + one shared palette texture**; few materials; no per-object textures early.
- **Box frame:** wooden/brass walls around the world bounds with visible thickness; a subtle glass lid reflection optional. The frame is always on screen at wide zoom.
- **Lighting:** one directional sun (moves with time of day), ambient from sky colour, soft fake shadows (blob shadows for small entities; real shadows only for the sun on terrain/buildings at medium+ settings).
- **Miniature cues:** gentle depth fade/vignette (fake tilt-shift on low settings; real DOF only on high), warm saturated palette, slight "toy" specular.
- **Ambient motion:** swaying tree shader, water surface shader (scrolling normal + shoreline foam), cloud shadows, birds (MultiMesh), chimney smoke (GPU particles with low counts), fireflies at night.

### 28.3 Colour & readability [CANON]

- People: saturated clothing colours against muted terrain.
- Buildings: warm neutrals; era-specific accent colours.
- Resources: distinct shapes first, colour second (colourblind-safe).
- Events: icons with shapes (not colour only).

### 28.4 People visuals [CANON]

Simple enough for mobile (tens of triangles; no skeletons in early phases — vertex-shader bob/lean animation), distinguishable via **body type** (height/width scale), **clothing colour** (culture palette), **accessories** (hat, basket, tool, staff), **occupation props**, **age** (children smaller, elders stooped + grey). Selected/followed people get a subtle ring and outline. Later civilizations gain more visual complexity (clothing styles, uniforms).

### 28.5 UI style [CANON]

An **elegant scientific observation device mixed with a miniature-world interface**: instrument-like thin lines, brass/ink accents, cards, sliding panels, contextual overlays, icons *with labels*, charts, timelines, expandable sections. No giant opaque menus.

---

## 29. AUDIO & HAPTICS

### 29.1 Audio [CANON]

Environmental layers: wind, rain, water, birds, insects, fire, civilization ambience (voices, tools), construction, distant activity. **Audio becomes richer as the civilization develops** (layers unlock with population, buildings, era). Distance/zoom-based mixing: zoomed in = individual sounds; zoomed out = the whole box's murmur. Settings: master, ambience, effects, UI; mute.

### 29.2 Haptics [CANON]

| Strength | When |
|---|---|
| Light | Tap, successful selection, tool change |
| Medium | Discovery, meaningful interaction (person reacts), long-press open |
| Strong | Earthquake, major event |

Never overuse (rate-limited). Toggle in settings; respect system settings. Implemented through one `Haptics` service using `Input.vibrate_handheld(duration_ms, amplitude)` (verify signature in 4.7 docs); requires the Android `VIBRATE` permission only.

---

## 30. ACCESSIBILITY [CANON]

- Scalable UI and text size options (UI scale 80–150%).
- Colourblind-friendly indicators (shapes + labels, not colour alone; palette tested for deuteranopia/protanopia/tritanopia).
- Haptic toggle; audio toggles per bus.
- **Reduced motion:** disables camera shake, box wobble, large particle bursts; slows transitions.
- Sensor control toggle — **the game remains fully playable without motion controls** (touch alternatives for tilt/shake).
- High-contrast UI mode where practical.
- Portrait and landscape; one-handed reach considered for portrait.

---

## 31. TECHNICAL ARCHITECTURE CANON

### 31.1 Platform & language [CANON]

Godot **4.7.2**, GDScript (typed), Android-first, touch-first, offline-first, no mandatory account/internet, persistent saves. **GDExtension (C++)** only if profiling proves a GDScript hot loop (candidates: water step, pathfinding at scale) cannot meet budget — decision recorded in the Decisions Log when/if made. Architecture must allow future multiplayer/cloud features without rewrite (clean serialization, id-based references, command-style interventions).

### 31.2 Architectural principles [CANON]

1. **Simulation is data; views are disposable.** World state lives in plain data objects (RefCounted classes + packed arrays). Nodes render and receive input. The simulation must run **headless** (for tests, soak runs and offline progression).
2. **One owner per piece of state.** Each system owns its data and exposes query methods; other systems never mutate it directly.
3. **Signals for major events** (decoupling), direct method calls for queries, no per-entity signals.
4. **All player interventions through one choke point** (§14.6).
5. **Everything serializable** via `to_dict()` / `from_dict()` with plain Variants (no Object serialization).
6. **Ids, not references**, across systems and in saves. Stale ids resolve to `null` safely.
7. **Tunables in resources**, never magic numbers.
8. **Budgets everywhere:** every per-frame system has a time budget and can defer work.

### 31.3 Scene & object ownership [PROPOSED, D-06]

```
Boot (scene) ── loads settings, decides Title/Continue ──► Main (scene)
Main
├── WorldSession (Node)            ← owns ALL world state for the current world; freed on New World/Reset
│   ├── GameClock
│   ├── SimulationManager          ← tick scheduler, tier manager, budgets
│   ├── WorldData                  ← chunks, tile layers, generator, spatial index (RefCounted inside)
│   ├── Systems (Node children)    ← Environment, Water, Weather, People, AI, Social, Economy, Settlement,
│   │                                 Technology, Culture, Science, History/EventLog, StoryEngine, Animals, LooseObjects
│   └── InteractionManager         ← the intervention choke point, PlayerHistory
├── WorldView (Node3D)             ← BoxFrame, ChunkViews, PropRenderers (MultiMesh), EntityViewPool, Weather FX, Camera rig
└── UIRoot (CanvasLayer)           ← HUD, ToolBar, Cards, Hamburger menu, Toasts, WhileYouWereGone, Debug overlay
```

`WorldSession` is **not** an autoload so that New World / Reset / tests can create and destroy worlds cleanly.

### 31.4 Autoloads (services only, justified) [PROPOSED]

| Autoload | Responsibility | Why global |
|---|---|---|
| `Log` | Structured logging, categories, ring buffer, file sink | Used everywhere |
| `Config` | Loads tunable resources, exposes typed accessors | Read everywhere |
| `EventBus` | Global signals (§31.5) | Decoupling |
| `Settings` | Player settings (audio, haptics, motion, accessibility, graphics), persisted separately from worlds | UI + services |
| `SaveManager` | Slots, atomic writes, backups, migration, lifecycle saves | Must survive session swaps |
| `SensorManager` | Filtered tilt, shake classification, calibration | Hardware singleton |
| `AudioManager` | Ambience layers, SFX pooling | Persistent across scenes |
| `Haptics` | Vibration patterns, rate limiting, toggle | Hardware singleton |
| `NotificationManager` | Priority queue, rate limit, merge, toasts | UI-wide |

The plan's WorldManager / SimulationManager / TimeManager / InteractionManager / UIManager exist as **nodes inside `WorldSession` / `UIRoot`** rather than autoloads. **No giant singleton.**

### 31.5 Signal catalogue (EventBus) [CANON core + PROPOSED extras]

`world_changed`, `world_loaded`, `world_unloaded`, `chunk_loaded`, `chunk_unloaded`, `person_born`, `person_died`, `person_selected`, `person_followed`, `entity_selected`, `discovery_found`, `technology_discovered`, `weather_changed`, `season_changed`, `day_started`, `year_started`, `major_event_occurred`, `intervention_applied`, `stimulus_emitted`, `save_started`, `save_completed`, `save_failed`, `load_failed`, `notification_created`, `tool_changed`, `sim_speed_changed`, `app_paused`, `app_resumed`.

### 31.6 Simulation tiers [CANON]

| Tier | Name | Who | Update |
|---|---|---|---|
| 4 | Player Focus | Selected/followed entity | Every tick; full perception; per-frame visuals |
| 3 | Active | In/near camera view, loaded chunks | AI think every 2–4 ticks (staggered); needs every tick; smooth movement |
| 2 | Regional | Loaded chunks off-screen | AI every ~15 ticks; movement advanced in coarse steps along paths |
| 1 | Abstract | Unloaded chunks / other settlements | Statistical sim per game hour (needs satisfied from stock, work output rates) |
| 0 | Dormant | Far/idle | Daily bookkeeping only (aging, rare events) |

Promotion/demotion is hysteretic; state is always consistent so an entity can move between tiers at any time. Caps (tunable): Tier 3 ≤ 64 entities (low-end 32); Tier 4 = 1–2.

### 31.7 Rendering architecture [CANON]

- **Chunk views:** one terrain mesh per chunk (rebuilt on modification), one water mesh per chunk (vertex heights updated from water layer at low frequency).
- **Props:** `MultiMeshInstance3D` per prop type per chunk (trees, rocks, grass tufts, crops).
- **People/animals:** pooled lightweight view nodes for Tier 3–4 (a `MeshInstance3D` + tiny script), or `MultiMesh` with per-instance colour/custom data for crowds at far zoom. Views bind to an entity id and interpolate its data.
- **LOD:** far zoom hides small props and switches people to dots/instanced markers.
- **Visibility:** chunk views outside the camera frustum + margin are unloaded/pooled.
- **Physics engine:** minimal; picking uses math raycasts against the height grid + spatial index, not colliders on every entity.

### 31.8 Offline & abstract simulator [CANON]

A deterministic `OfflineSimulator` advances the world in **day-steps** using Tier-1 rules for everyone: demographics (per-person daily birth/death probabilities — producing real named people and obituaries), resource flows, construction progress, weather sampling (Markov), knowledge accrual & discovery rolls, migration/founding checks, notable event generation with causes. Output: updated world + a `ReturnSummary`. The same simulator powers **Very Fast** catch-up and headless soak tests.

### 31.9 Save system [CANON requirements, PROPOSED format, D-07]

- **Save everything:** seed, world state, terrain modifications, chunks (modified only), entities, people, families, relationships, memories, civilization, technology, discoveries, history, player interactions, settings (separate file).
- **Format:** a container file per world: header `{magic "WIAB", save_version, created_unix, saved_unix, game_tick, payload_sha256, payload_size}` + ZSTD-compressed `var_to_bytes()` of a plain Dictionary (`full_objects=false`). Large worlds may split chunks into per-chunk files later without changing the header contract.
- **Atomic procedure:** serialize → write `world.sav.tmp` → flush/close → reopen & verify checksum + parse → rotate `world.sav` → `world.sav.bak1` (→ `bak2`) → rename tmp → `world.sav`. **Never overwrite the only valid save before verifying the new one.**
- **Load:** verify header & checksum → migrate (`SAVE_VERSION` n → n+1 chain) → validate & repair (drop dangling ids, quarantine invalid entities) → build world. On failure: try `bak1`, then `bak2`, then offer New World (never crash).
- **When:** autosave every 2 real minutes (tunable), on `NOTIFICATION_APPLICATION_PAUSED` / focus out / `WM_CLOSE_REQUEST`, after major events, manual save.
- **UI:** Continue · New World · Backup (manual copy to `backups/`) · Restore · Reset World (requires confirmation: hold-to-confirm + typed/two-step).
- `SAVE_VERSION = 1` at first release of the save format; every schema change increments it and adds a migration + test fixture.

### 31.10 Logging [CANON]

Categories: `WORLD, PLAYER, AI, SAVE, LOAD, SENSOR, UI, PERFORMANCE, ERROR` (+ `SIM, ENV, HISTORY` proposed). Levels: TRACE/DEBUG/INFO/WARN/ERROR. Debug builds verbose; release builds WARN+ only (`OS.is_debug_build()`). Ring buffer (last ~500 lines) viewable in the debug panel and dumped to `user://logs/` on errors for bug reports.

### 31.11 Crash resilience [CANON]

Must survive: invalid save data, missing/deleted entity, malformed relationship, missing chunk, unexpected sensor values (NaN, spikes), invalid coordinates. GDScript has no exceptions, so: **guard clauses + validation at system boundaries**, safe lookups returning `null`, **entity quarantine** (an entity failing validation is removed from simulation, logged with context, kept in the save's `quarantine` section for debugging), periodic **invariant checker** in debug builds. **Never let one bad NPC destroy the simulation.**

### 31.12 Android specifics [CANON]

- Package: `com.happihack.worldinabox` (release), `com.happihack.worldinabox.dev` (debug, installable side-by-side).
- Permissions: **VIBRATE only**. No internet permission unless a future opt-in feature needs it. Microphone only if voice communication is added, requested at activation.
- Lifecycle: handle `NOTIFICATION_APPLICATION_PAUSED/RESUMED`, `NOTIFICATION_APPLICATION_FOCUS_OUT/IN`, `NOTIFICATION_WM_GO_BACK_REQUEST` (back button closes panels, then asks to leave). Save on pause; stop sensors; reduce/stop rendering (`OS.low_processor_usage_mode` while paused UI); never assume the OS keeps the app alive.
- Battery: sensors polled only when motion controls enabled, app focused and world visible; no high-frequency sim when unnecessary; frame-rate cap option (30/60).
- Renderer: Mobile renderer with OpenGL (Compatibility) fallback enabled; shaders written to work in both (D-02).

### 31.13 Testing [CANON]

Automated tests (headless, `godot --headless`): world generation (deterministic seed, valid terrain, valid resources), save (save, load, migration, corruption detection), population (birth, aging, death), relationships (creation, change), resources (gathering, consumption, production), weather (transitions, effects), events (creation, persistence), camera (pan, zoom, bounds), touch (tap, long press, drag) — plus proposed: interpretation variety, memory decay, story chains, offline determinism, invariants after N-year soak. Test runner choice: D-03.

### 31.14 Performance targets [CANON]

60 FPS on reasonably modern Android; graceful degradation to 30 FPS on low-end. Simulation and rendering independently throttled. Never run the whole civilization at max detail. Budgets in §33.

### 31.15 Future AI layer [CANON]

Data structures (events with causes, memories with structured params, lexicon) are designed so an **optional** AI layer could later summarize history, generate names/stories/dialogue, interpret actions and generate civilization theories. **The core game never depends on external AI or the internet.**

---

## 32. DECISIONS LOG

| ID | Decision | Status | Rationale | Alternatives |
|---|---|---|---|---|
| D-01 | **3D low-poly stepped-tile diorama** rendering | **CONFIRMED 2026-09-30** | Box frame, sun movement, tilt of the whole box and a "miniature" look are far more convincing in 3D; MultiMesh keeps it cheap | 2D isometric TileMap (cheaper art pipeline, weaker tilt/box illusion) |
| D-02 | Mobile renderer + OpenGL fallback; shaders compatible with Compatibility | PROPOSED | Broad device support | Compatibility-only (max reach, fewer effects) |
| D-03 | Minimal **in-house headless test runner** (`tests/run_tests.gd`), GUT/gdUnit4 optional later | PROPOSED | Zero addon-version risk on 4.7.2 | GUT, gdUnit4 |
| D-04 | Day = 12 real min @1×; 24 days/year | PROPOSED | Watchable days + visible generations within weeks | Longer days (more realism, slower history) |
| D-05 | World grows by **the Box Unfolding** | PROPOSED | Reconciles "box" with "world grows"; great Box Theory evidence | Bigger box from start with fog only |
| D-06 | World state owned by non-autoload `WorldSession` | PROPOSED | Clean new world/reset/testing | Plan's autoload WorldManager |
| D-07 | Single-file ZSTD container + header checksum; atomic rotate with 2 backups | PROPOSED | Simple, robust, verifiable | JSON (debuggable, large), per-chunk files (later) |
| D-08 | **No intervention currency**; deliberate gestures + short physical cooldowns + "Gentle hands" option | PROPOSED | Plan forbids energy systems; still protects the sim | Influence points |
| D-09 | Offline: full rate up to 24 h, diminishing to 72 h cap | PROPOSED | Rewards returning, prevents unrecognizable worlds | Uncapped; fixed cap |
| D-10 | `AStarGrid2D` tile pathfinding + later chunk-level hierarchy | PROPOSED | Built-in, fast, fits grid | NavigationServer (overkill for tiles) |
| D-11 | Traits as bipolar axes | PROPOSED | Compact, gradient personalities covering all spec traits | Boolean trait tags |
| D-12 | Save skeleton + debug overlay + test runner from **M0**, hardened later (M22/M23) | CANON-ADJUSTMENT | Vertical slice needs save/load; debugging needed from day 1 | Build at M22/M23 as listed |
| D-13 | Chunked data model from **M1**; streaming at M13 | CANON-ADJUSTMENT | Spec demands chunk architecture from the start | Flat array now, refactor later (forbidden: core rewrite) |
| D-15 | **Tilting dropped.** The phone's tilt does not move the world. **Shake → earthquake is kept as an idea, on hold**, to be designed with the disasters (several are planned; not yet designed). | **CONFIRMED 2026-10-04 (owner)** | People hold their phones at all angles; tilting flips the screen between portrait and landscape and fights the player's grip — too hard to make feel right | Tilt as a toggleable option (rejected: same problems when on) |
| D-14 | Event causality (`causes[]`) recorded from the **first** event system (M7) | CANON-ADJUSTMENT | Story engine (M19) depends on it | Infer causes later (unreliable) |

---

## 33. TUNABLES MASTER TABLE (defaults; live in `data/configuration/`)

| File | Key | Default |
|---|---|---|
| `time_config.tres` | real_seconds_per_game_minute | 0.5 |
| | days_per_season / seasons_per_year | 6 / 4 |
| | speed_multipliers | [0, 1, 4, 16] |
| | offline_full_rate_hours / offline_cap_hours | 24 / 72 |
| | wywg_min_absence_minutes | 10 |
| `world_config.tres` | chunk_size | 16 |
| | initial_world_tiles | 64 (slice: 32) |
| | max_world_tiles | 512 |
| | height_levels / height_step | 16 / 0.4 |
| `sim_config.tres` | tier3_cap (high/low device) | 64 / 32 |
| | ai_think_interval_ticks (T4/T3/T2) | 1 / 3 / 15 |
| | water_step_hz / water_budget_ms | 10 / 1.5 |
| | sim_budget_ms_per_frame | 4.0 |
| `people_config.tres` | starting_population | 8–11 (owner, 2026-10-05; was 6–8) |
| | adulthood_age / elder_age | 16 / 50 |
| | max_personal_memories / max_relationships | 32 / 30 |
| | gossip_fidelity_factor | 0.85 |
| `needs_config.tres` | decay per game hour per need | per-need table |
| `interaction_config.tres` | long_press_ms / drag_slop_dp / touch_radius_dp | 450 / 10 / 24 |
| | double_tap_ms | 300 |
| `sensor_config.tres` | tilt_dead_zone_deg / tilt_max_deg / tilt_lowpass_alpha | 4 / 25 / 0.15 |
| | shake_window_ms / shake_min_reversals | 600 / 2 |
| | shake thresholds (m/s² light/med/strong/extreme) | 6 / 11 / 17 / 24 (tune on devices) |
| | shake cooldowns s | 1.5 / 5 / 20 / 60 |
| `save_config.tres` | autosave_interval_s / backup_count | 120 / 2 |
| `notify_config.tres` | max_toasts_per_minute / merge_window_s | 3 / 20 |
| `haptics_config.tres` | light/medium/strong (ms, amplitude) | (10, 0.3) / (25, 0.6) / (70, 1.0) |
| `perf_config.tres` | target_fps high/low | 60 / 30 |
| | frame budget ms | 16.6 / 33.3 |
| | memory budget (low-end) | < 350 MB |
| | draw calls budget (low-end) | < 250 |
| | cold start to live world | < 6 s (low-end), < 3 s warm |
| | save time (slice / 1k people) | < 50 ms / < 300 ms |

---

## 34. GLOSSARY

| Term | Meaning |
|---|---|
| **The Box** | The physical container of the world; its walls are the Edge, its lid the Sky's Ceiling |
| **The Presence** | Neutral in-game term for the player's effects before any culture names it |
| **Intervention** | Any player action that changes the world (always via InteractionManager) |
| **Stimulus** | The perceivable signal an intervention/event emits |
| **Anomaly** | A stimulus that violates the civilization's expectations; archived for science |
| **Interpretation** | How a person explains a stimulus (deity, spirit, physics, …) |
| **Tier** | Simulation detail level of an entity (0–4) |
| **Chunk** | 16×16 tile block; unit of storage/streaming |
| **Unfolding** | The box expanding its walls (world growth) |
| **Revelation** | An endgame discovery (The Box, The Outside, The Observer, The Second Box, The Creator Question) |
| **Significance** | Historical importance score of events and people |
| **WYWG** | *While You Were Gone* summary |
| **FTUE** | First-time user experience |
| **VS** | Vertical slice |
| **Gentle hands** | Setting that disables major interventions |

---

## 35. OPEN QUESTIONS (resolve as the project matures)

1. ~~D-01 confirmation~~ — **resolved: 3D** (2026-09-30).
2. **Monetization/business model:** not specified by the sources. Must never introduce energy/timers/manipulative notifications. Premium or cosmetic-only boxes are compatible with the pillars.
3. **Multiple civilizations per box:** the spec implies cultures diverge ("another civilization might interpret rain differently"). Start with one founding culture that diverges via migration; decide later whether separate founding peoples are seeded.
4. **World size default after unfolding:** how often and how large (tie to performance results from M21).
5. **Real-time vs pausing offline progression** for players who want a "frozen" world — offer a setting ("World rests while I'm away")?
6. **Voice/text communication (M30):** whether to ever ship, given permission and scope costs.
7. **Cloud/multiplayer:** architecture allows it; no feature planned. Possible "box visits" or seed sharing later.
8. **Localization:** all player-facing text goes through `tr()` and templates from day one; languages TBD.
9. **Additional boxes (M33):** separate saves vs one "shelf" of boxes with cross-box evidence (Second Box revelation).
10. **Previous-world echoes (§25.4):** ship or keep as a lore idea.

---

*End of Game Bible v1.0. Update the version and changelog below when canon changes.*

### Changelog
- **v1.0 (2026-09-30):** Initial bible consolidated from `my_world.txt` and `my_world_plan.txt`; proposed decisions D-01…D-14.
- **v1.1 (2026-09-30):** D-01 confirmed — 3D stepped-tile diorama. M0.1 complete.
- **v1.2 (2026-09-30):** Height step 0.25 → 0.4 world units per level (decided from M1.3 renders).
