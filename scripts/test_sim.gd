extends SceneTree
## Headless smoke test: godot --headless -s res://scripts/test_sim.gd

func _init() -> void:
	var w := World.new()
	root.add_child(w)
	await process_frame
	w.release(Genome.founder(w.rng))
	for i in 3000:
		w.step()
		if i % 500 == 0:
			print("tick %d pop %d food %d species %d" % [w.tick, w.creatures.size(), w.foods.size(), w.species])
	var ok := w.creatures.size() > 20
	print("final pop %d gen %d" % [w.creatures.size(), w.max_generation()])
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
