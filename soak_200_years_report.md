# Six worlds, 200 years each — soak report

*Run 2026-10-08 → 10-09. Six new worlds, one of each of the new lands, each lived 200 game years with the world stepped as the game steps it (`advance_systems`, not the soak's own list), with a chronicle every ten years. Code: `7d50db3` plus the soak's reporting; Broad Valley and Forest Vale re-run with the guard against the planning loop (below).*

---

## 1. The short version

- **People live, love, die and remember.** Every world that lasted ran 9–12 generations, told 15–33 stories, named 100+ important people, kept its harvest and bridge festivals for two centuries, and had leaders come, die, step down and be overthrown.
- **Knowledge races ahead, then hits the ceiling.** Four of six worlds learned every technology the game has (18 of 18 that can be learned) — some by year 40–50 — and then had nothing left to learn for 150 years.
- **Everything else stalls.** No world got past the **age of settling**; several fell back to **primitive** for decades with 100 people alive. Science never began (stage 0 everywhere). Not one shrine was built. Storehouses were all but absent. Mining doesn't exist.
- **Population is a lottery of land.** From 0 (Lake Country starved out by year 99) to 131 (Open Plains, healthy, 4 villages). Starvation was the first cause of death in two worlds.
- **A crash was found and fixed.** Two worlds broke at years 96 and 117 on an engine "stack underflow": a storytelling loop. Fixed at the root, with a guard behind it (section 6).

**Verdict:** the *life* of the villagers works and makes stories. The *progress* of a civilization does not happen in 200 years — not because the villagers fail, but because four specific gates in the code are closed or nearly so (section 5). Opening them is the work that would make a 200-year world visibly grow up.

---

## 2. The six worlds at a glance

| World (seed) | Result | People at 200 (peak) | Born / died | Starved | Settlements | Highest tier | Age at 200 | Technologies | Myths / faiths | Wars |
|---|---|---|---|---|---|---|---|---|---|---|
| **Open Plains** (4242) | passed | **131** (141) | 385 / 375 | **7** | 4 | 4 villages | settling | 18 (all) | 8 myths, 4 founders, 2 schisms | 0 |
| **Highlands** (2026) | 3 problems* | **107** (111) | 374 / 403 | 124 | 4 | 1 village | primitive | 18 (all) | 4 myths, 3 founders | 1 |
| **Broad Valley** (7) | passed | 40 (60) | 162 / 212 | 38 | 4 | hamlets | settling | 18 (all) | 6 myths, 3 founders | 1 |
| **Forest Vale** (12345) | 6 problems* | 33 (56) | 142 / 217 | **77** | 3 (+1 empty) | hamlets | settling | 15 | none | **9** (20 dead) |
| **River Bluffs** (31337) | 3 problems* | 26 (43) | 99 / 151 | 9 | 3 (+1 empty) | hamlets | primitive | 14 | 5 myths, 5 founders | 1 |
| **Lake Country** (99) | **died out, year 99** | 0 (24) | 34 / 74 | **56** | — | — | — | 11 | none | 0 |

\* The "problems" are people weak with hunger on the last day, and once (River Bluffs, year 49) someone standing inside a building that had just fallen to ruin.

**Deaths, all six:** old age 746 · starvation 311 · illness 315 · war 30 · mauled by predators 22 · accident 8.

---

## 3. Progress, area by area

### 3.1 Settlements and buildings
- **Splitting comes too early.** Every world had a second settlement by year 2–22 (most by year 10). Groups keep leaving to found camps, so settlements stay at 10–25 people. Only Open Plains grew **villages** (from year 70, four of them by year 100); Highlands had one at times; the rest stayed hamlets and camps for 200 years.
- **First settlements get abandoned.** In River Bluffs (from year 30), Forest Vale (year 160) and Lake Country (year 50) the founding village was left empty, its fire out.
- **What gets built** (year 200): huts (6–26), bridges (16–29 tiles of crossing), cemeteries (4–5), landings (3–5), border stones after wars. Occasionally one workshop, kiln, herb rack, record stone, woodshed.
- **What doesn't:** **storehouses** (0–1 in every world — Open Plains fed 131 people from one), **shrines (0 everywhere)**, **stone circles (0)**, **wells (0)**.

### 3.2 Technology
- **Fast early, then the ceiling.** Tools (year 1–2), rafts (2), weaving (3–8), pottery (3–8), nets (5–9), canoes (3–15), archery (5–39), lamps (4–16), medicine (9–23), writing (21–73), astronomy (22–34), mathematics (15–74), plank boats and sails (40–166).
- **All 18 learnable technologies** were known in Open Plains, Highlands and Broad Valley; then nothing for 100–150 years. The chain stops at engineering/sail: copper, bronze, iron, mechanics, printing, the scientific method and everything after are switched off.
- **Natural philosophy — the door to science — was never discovered**, in any world, though its conditions (writing + astronomy, 12 people) were met for over a century in four. Its chance (0.2% a day) should have come up; something else in its conditions is not being met — needs a look.

### 3.3 Mining
- **None — it isn't in the game.** Copper, bronze and iron working wait for ore and mining (as decided for weapons). Every world stayed in stone, wood and hide.

### 3.4 Religion and belief
- **Myths form** in four worlds (the storm and the flood, mostly "a benevolent deity", sometimes "a spirit"), with 3–5 **founders** who speak for them; Open Plains had **two schisms**.
- **Traditions are the strongest thread:** the harvest and bridge festivals kept for 200 years in every settlement; storm vigils and high-water rites added along the way.
- **No shrine was ever built.** A shrine waits for a myth "many" of one settlement hold — with beliefs spread across small hamlets, never.
- Forest Vale and Lake Country formed **no myths at all**.

### 3.5 Science and the mysteries
- **Science: stage 0 in every world, no hypotheses, no anomalies recorded.** (It needs natural philosophy — 3.2 — and a scientist.)
- **The box's mysteries do advance by themselves:** explorers find the edge, the smooth wall, ruins and strange things — 3/3 clues on several mysteries in most worlds. Nobody is there to study them.

### 3.6 Strife
- **Tension runs very high** between many pairs of settlements (1.00 — the maximum — in Open Plains and Highlands), mostly from hunger near neighbours.
- **But war is rare:** 0–1 wars in five worlds. **Forest Vale** was the exception: **9 wars, 20 dead**, raids, quarrels that led to leaders, and peace stones on four borders.
- Leaders turn over a lot: 28–33 die in office per world, 8–11 are replaced, 2–3 overthrown (Broad Valley, River Bluffs).

### 3.7 Food and population
- **Food is the real story of these worlds.** The tales they tell are mostly hunger: "The Hungry Winter of Year 137 caused the stores running empty and led to the death of Yeiyen."
- **Open Plains** (wide, flat, rich) barely starved (7 in 200 years). **Highlands** grew big but lost 124 to hunger. **Forest Vale** and **Lake Country** starved most — little open land for fields and bushes.
- **Lake Country died out.** Its first village emptied in year 48 as two groups left; the two small camps could not keep their huts and stores standing, starved (56 of 74 deaths), and the last person died in year 99.

---

## 4. How the story unfolded — one world told: Highlands (seed 2026)

- **Years 1–10.** A band of 11 settles by the river; tools on the first day; Gelwam and Eishele are both hamlets of a dozen by year 10.
- **Years 20–30.** Steiki leaves with a group and founds a camp (Ginein); a fourth, Lishim, follows. Writing at year 21, mathematics at 15 — this valley learns fast. Rafts, canoes, nets.
- **Year 36.** *The berries ran out, a hungry season followed, and Stagi died* — the first of the hunger stories this world will tell for 160 years.
- **Years 40–50.** Plank boats and sails (40–41); archery (39). Eighteen technologies — everything there is — by year 50. 72 people.
- **Years 51–56.** The Hungry Winter of Year 51 kills Veikan; Geinem dies in the hunger of Year 56.
- **Year 69.** The Great Storm raises the river; Sin drowns. The age falls to **primitive** — the last storehouse is gone — and stays there for 130 years.
- **Year 90.** The Great Drought: the river falls low, and Liweina dies.
- **Year 97.** A faith is founded around the thunderstorm deity — 26 believe in it by the end; three founders speak for the sky.
- **Years 100–200.** Around a hundred people in four settlements; Ginein and later Eishele grow into villages; a war is fought and border stones are set; 11 generations; 23 stories told; the hungry winters keep coming (Year 137: Yeiyen). Nothing more to learn, no shrine for the deity they believe in, no science.

**Other worlds, in a line each:**
- **Open Plains:** the Great Storm of Year 9 drives a group out to found a camp; four villages by year 100; two schisms; the gentlest world — 268 of 375 died of old age.
- **Broad Valley:** Kabre and Piza fall out (Year 23) and Kabre's side founds a camp; the berries run out in Year 146 and Louki goes to war with Heneinpe.
- **Forest Vale:** the Hungry Winter of Year 45 sets Miska against Adith's camp; the Raid on Numu (Year 47) begins nine wars over the century.
- **River Bluffs:** the first village is empty by year 30; three small settlements hold on for 170 years; the War of Honeka and Gocha (Year 182) brings Pegara to lead.
- **Lake Country:** a slow start, a split, two camps that could not hold — gone by Year 99.

---

## 5. Why progress stalls — the four gates

The game's ages go **primitive → settling → farming → villages → towns → civilization → science → …**, each needing the one before.

1. **The storehouse gate.** *Settling* needs a hut and a **storehouse** standing. A storehouse is built only when the stores overflow or food spoils — which a settlement that is always a little hungry never sees. So a world of 100 people can read *primitive*. **Fix idea:** build the first storehouse when a settlement has a few households (or once farming starts), not on surplus.
2. **The farming gate.** *Farming* needs a settlement whose **fields feed half** of what it brings in. Fields never reach that share for long (foraging, fishing and hunting dominate), so *villages* (which needs farming first) never comes — even where four villages stand. **Fix idea:** lower the share (a third?), or count a sustained harvest instead.
3. **The splitting gate.** Groups leave so early and so often that settlements stay small (*village* needs 30+ and specialists). **Fix idea:** leave only when a settlement is crowded or quarrelling *and* is a village; or let camps that fail rejoin.
4. **The knowledge ceiling.** Natural philosophy never comes (a bug to find), the scientific method onward are switched off, and the metals wait for mining. **Fix idea:** find why natural philosophy isn't rolled; then switch on the next steps (scientific method; mining → copper) so the 150 empty years have something to reach for.

And two that hold back belief and wonder:
- **Shrines** need "many" believers in one settlement — make it a share of the settlement (or any founder) instead.
- **Science** needs natural philosophy (gate 4) — once that comes, the mysteries they keep finding get studied.

---

## 6. The crash found on the way

- **What:** two worlds (Forest Vale, year 96; Broad Valley, year 117) filled their logs with "Stack underflow (Engine Bug)" and stopped advancing. The logs grew by gigabytes an hour; the runs were stopped before they filled the disk and re-run.
- **Why:** someone went to listen to a story by the fire when nobody was telling one. Their listening ended "done" in the same instant, so they chose to listen again — round and round in one moment, deeper and deeper, until the engine's call stack broke. It was the same thing behind the year-61 crash seen on 10-08 — and very likely behind occasional freezes on the phone.
- **Fixed** (not yet committed): listening when no story is told now *fails* (and is put aside a while); and a guard stops anyone finishing more than 8 plans in one moment. In the re-runs the guard stepped in ~2,500 times in Forest Vale alone — every time a storytelling loop that would otherwise have crashed — and both worlds then ran their full 200 years.

---

## 7. Recommended next steps (in order)

1. **Commit the storytelling fix and guard** (with the menu feedback) — it prevents crashes and freezes.
2. **Open the storehouse and farming gates** (5.1, 5.2) — small changes, and every world would move through settling → farming → villages.
3. **Find why natural philosophy is never learned** (5.4) — it unlocks science and the mysteries line.
4. **Curb early splitting** (5.3) — fewer, bigger settlements: towns, specialists, and less starvation.
5. **Make shrines reachable** (5.5).
6. **Food balance per land** — Lake Country and Forest Vale need more food sources (fish, forest foraging); hunger is half the deaths in some worlds.
7. **Then** switch on the next technologies and mining, so the second century has somewhere to go.
8. **Re-run this soak** after 2–4 to see the ages actually advance.

*Data: `C:\Users\dreyer\.claude\jobs\287d5e0d\tmp\y200_*.log` (the chronicles), `analysis.txt`, `y200_facts.json`.*
