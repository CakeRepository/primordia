# Primordia

You are a creature on a living 3D planet. Your body is built from your DNA. Eat, dodge predators and lay
offspring; when you die you carry on as your nearest descendant, and real mutations (substitutions,
insertions, deletions, duplicated segments) take your line somewhere you did not plan. Around you, native
species evolve under the same rules. A CRISPR-style gene lab lets you edit your germline, the DNA your
offspring inherit.

Every world is generated from a single seed and is alien in its own way: terrain shape, biome colours, sky,
star type, moons, gravity, radiation, fertility, how creatures are proportioned, and even the genetic code. The
same DNA builds a different body on a different planet. The HUD shows the planet's name and seed; the same seed
always gives the same world.

Godot 4.3+ (GDScript). The design was prototyped as a single-page web sandbox first; this repo is the real game.

## Run

1. Install Godot 4.3 or newer (standard build, not .NET).
2. `godot --path .` (or open `project.godot` in the editor and press F5).

The original top-down god view (levers, meteors, release your DNA onto the map) still runs with
`godot --path . res://scenes/main.tscn`.

## Controls (3D)

| Input | Action |
| --- | --- |
| WASD / arrow keys | Move, relative to the camera |
| Right-drag / mouse wheel | Orbit / zoom the camera |
| R | Lay an offspring (needs a full energy bar; halves your energy) |
| Tab | Open or close the gene lab |
| Arrows, A/T/G/C, Shift+A/T/G/C, Delete (gene lab open) | Move, replace a base, insert after it, cut it (1 Cas9 charge each) |
| Enter | Start a new lineage after yours has ended |
| 1 / 2 / 3, P | Speed 1x / 2x / 4x, pause |

You live about a minute at 1x. Food is eaten on contact; carnivores also bite smaller creatures they touch.

The planet changes too. Climate eras (ice age to hothouse) last one to two lifetimes; temperature drifts toward
each era's target, the sea falls or rises with it (about 2.4 m either way, enough to open or drown land bridges),
snow spreads or retreats, and cold ground grows less food. Meteors are sighted a few seconds before they land
(a red column marks the blast zone) and scorch the ground for a while; solar storms raise mutation rates.
Gene lab edits apply to offspring you lay afterwards, and every edit has an 8% chance of an off-target
mutation. Charges refill slowly while the world runs.

## Controls (top-down view)

| Input | Action |
| --- | --- |
| Arrow keys (Shift = 10 bases) | Move the cursor in the gene lab |
| A / T / G / C | Replace the base under the cursor (1 Cas9 charge) |
| Shift + A/T/G/C | Insert a base after the cursor |
| Delete | Cut the base under the cursor |
| Enter | Release your DNA onto the planet; afterwards toggles drop mode (2 charges per drop) |
| Click a creature | Inspect it. `L` loads its DNA into the lab, `W` writes the lab DNA back |
| Drag / mouse wheel | Pan / zoom |
| 1 / 2 / 3, P | Speed 1x / 2x / 4x, pause |

## How it works

- `scripts/genome.gd`: DNA string to phenotype. Genes start at `ATG` and end at a stop codon. Codons map to amino
  acids and each amino acid adds a fixed effect vector (size, speed, senses, spikes, camouflage, heat tolerance,
  metabolism, carnivory, aquatic, limb count, hue). Earth's code is the default; `use_biochemistry(seed)` installs
  an alien one (start and stop codons are kept, everything else is reassigned). Also founder generation, mutation
  and CRISPR edits.
- `scripts/planet_gen.gd`: everything that follows from a world seed (name, terrain, palette, sky, star, moons,
  gravity, radiation, fertility, climate, relief, body proportions, biochemistry). Deterministic, and re-rolls
  until the world has a sensible share of land and a viable founder.
- `scripts/world.gd`: the simulation, in 2D sim coordinates: terrain (ocean, coast, forest, desert, snow), food,
  land and sea predators, creatures, species clustering. The player is an ordinary creature that moves by input
  and reproduces on demand; when it dies, control passes to the nearest member of its lineage.
- `scripts/planet3d.gd`: draws the sim in 3D. Sim `(x, y)` maps to `(x * 0.1, height, y * 0.1)` metres on a
  heightfield built from the same elevation grid. Creatures, food and predators are MultiMeshes.
- `scripts/creature_model.gd`: the player's body, built from its genome (eyes, legs, spikes, jaws, fins).
- `scripts/main3d.gd`: the 3D game: input, third-person camera, HUD and the germline gene lab.
- `scripts/main.gd`: the top-down view: camera, input and HUD, all built in code.
- `scripts/gene_lab.gd`: gene lab text (DNA strip and trait bars) shared by both HUDs.

## Tests (headless)

```
godot --headless --path . --import
godot --headless --path . -s res://scripts/test_genome.gd
godot --headless --path . -s res://scripts/test_sim.gd
godot --headless --path . -s res://scripts/test_main.gd
godot --headless --path . -s res://scripts/test_main3d.gd
godot --headless --path . -s res://scripts/test_worlds.gd
```

## Known gaps and next steps

- Other creatures are simple MultiMesh shapes (body, legs, optional spikes); only the player gets a full model.
- Aquatic and carnivorous lineages can evolve but no native species starts as one.
- Speed: about 100 ticks/s at 600 creatures, so 4x is the practical ceiling. Candidates: spatial hashing for
  creature-vs-creature checks, moving the sim to a thread, or a GDExtension.
- Gene lab is keyboard driven and text based; the web prototype's codon and amino-acid view is not ported yet.
- No protein or cell stage before the planet, no sexual reproduction, no save/load of DNA, no web export preset.
