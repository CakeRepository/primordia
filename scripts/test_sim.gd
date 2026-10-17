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
	# extinction stops the world and clears the species count
	w.creatures.clear()
	w.step()
	ok = ok and not w.running and w.species == 0

	# A living planet: an ice age cools it and drops the sea, exposing land.
	var lp := World.new()
	root.add_child(lp)
	await process_frame
	lp.populate(Genome.founder(lp.rng))
	var land0 := lp.land_frac
	var events := []
	lp.planet_event.connect(func(t): events.append(t))
	lp.set_era(0)
	for i in 2500:
		lp.step()
	print("ice age: temp %.2f, sea %+.3f, land %.2f -> %.2f, pop %d" % [
		lp.temp, lp.sea_level - World.SEA, land0, lp.land_frac, lp.creatures.size()])
	ok = ok and lp.temp < 0.35 and lp.sea_level < World.SEA - 0.02 and lp.land_frac > land0 and events.size() > 0
	# A meteor lands where it was sighted, after its warning time.
	var target: Vector2 = lp.creatures[0].pos
	var near_of := func(): return lp.creatures.filter(func(c): return c.pos.distance_to(target) < World.METEOR_R * 0.5).size()
	var near_before: int = near_of.call()
	var craters0 := lp.craters.size()
	lp.meteor_at(target, 10)
	for i in 9:
		lp.step()
	ok = ok and lp.craters.size() == craters0
	lp.step()
	var near_after: int = near_of.call()
	print("meteor: %d creatures near the impact before, %d after" % [near_before, near_after])
	ok = ok and lp.craters.size() == craters0 + 1 and near_after * 2 <= near_before + 1
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
