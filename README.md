# Primordia

You start as a strand of DNA. Edit it CRISPR-style, release it onto a living planet, and watch real mutations
(substitutions, insertions, deletions, duplicated segments) take it somewhere you did not plan.

Godot 4.3+ (GDScript). The design was prototyped as a single-page web sandbox first; this repo is the real game.

## Run

1. Install Godot 4.3 or newer (standard build, not .NET).
2. `godot --path .` (or open `project.godot` in the editor and press F5).

## Controls

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

Every edit has an 8% chance of an off-target mutation. Charges refill slowly while the world runs.

## How it works

- `scripts/genome.gd`: DNA string to phenotype. Genes start at `ATG` and end at a stop codon. Codons map to amino
  acids with the standard genetic code and each amino acid adds a fixed effect vector (size, speed, senses, spikes,
  camouflage, heat tolerance, metabolism, carnivory, aquatic, limb count, hue). Also founder generation and mutation.
- `scripts/world.gd`: terrain (ocean, coast, forest, desert, snow), food, land and sea predators, creature simulation,
  species clustering and drawing.
- `scripts/main.gd`: camera, input and HUD, all built in code.

## Tests (headless)

```
godot --headless --path . --import
godot --headless --path . -s res://scripts/test_genome.gd
godot --headless --path . -s res://scripts/test_sim.gd
godot --headless --path . -s res://scripts/test_main.gd
```

## Known gaps and next steps

- Speed: about 100 ticks/s at 600 creatures, so 4x is the practical ceiling. Candidates: spatial hashing for
  creature-vs-creature checks, moving the sim to a thread, or a GDExtension.
- Gene lab is keyboard driven and text based; the web prototype's codon and amino-acid view is not ported yet.
- No protein or cell stage before the planet, no sexual reproduction, no save/load of DNA, no web export preset.
