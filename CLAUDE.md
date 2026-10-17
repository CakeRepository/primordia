# Primordia (Godot 4.3, GDScript)

Evolution game: the player is a creature on a 3D planet, built from its DNA. It evolves across generations
(you continue as your descendant) while native species evolve around it. A CRISPR-style gene lab edits the germline.

- Run: `godot --path .`
- Verify changes with the headless tests listed in README.md (all of them must print PASS).
- Worlds come from `PlanetGen` seeds. `Genome`'s genetic code is global (one world per process), so build a
  world through `World.planet`/`use_planet`, which installs its biochemistry.
- Genome decoding lives in `scripts/genome.gd`, the simulation in `scripts/world.gd` (2D sim coordinates, also used
  headless). The 3D game is `scripts/main3d.gd` + `scripts/planet3d.gd` (rendering) + `scripts/creature_model.gd`;
  the older top-down view is `scripts/main.gd` (`scenes/main.tscn`).
- Keep 3D rendering and input out of `world.gd`, so the sim stays testable headless.
- Keep gameplay rules in the data (DNA, EFF table) rather than special cases, so outcomes stay open-ended.
- Do not commit `.godot/`.
