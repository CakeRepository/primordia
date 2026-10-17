# Primordia (Godot 4.3, GDScript)

Evolution game: the player edits a DNA string (CRISPR-style) and releases it onto a simulated planet.

- Run: `godot --path .`
- Verify changes with the headless tests listed in README.md (all three must print PASS).
- Genome decoding lives in `scripts/genome.gd`, the simulation in `scripts/world.gd`, input and HUD in `scripts/main.gd`.
- Keep gameplay rules in the data (DNA, EFF table) rather than special cases, so outcomes stay open-ended.
- Do not commit `.godot/`.
