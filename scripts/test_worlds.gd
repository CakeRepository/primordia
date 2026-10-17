extends SceneTree
## Headless checks for generated worlds: godot --headless -s res://scripts/test_worlds.gd
## Same seed -> identical planet (servers only share the seed); different seeds -> different
## planets; and every sampled world can sustain life.

func _fingerprint(p: PlanetGen) -> String:
	var h := 0.0
	for k in range(0, p.elev.size(), 37):
		h += p.elev[k] * (k + 1) + p.moist[k] + p.base_t[k]
	p.apply_biochemistry()
	return "%s|%.6f|%s|%s|%s|%s" % [p.name, h, p.palette["plain"].to_html(), Genome.code, str(Genome.eff["K"]), p.describe()]


func _init() -> void:
	var ok := true
	var t0 := Time.get_ticks_msec()
	var a := _fingerprint(PlanetGen.new(777))
	var b := _fingerprint(PlanetGen.new(777))
	var c := _fingerprint(PlanetGen.new(778))
	print("planet build: %d ms each" % ((Time.get_ticks_msec() - t0) / 3))
	ok = ok and a == b and a != c
	print("same seed identical: %s, different seeds differ: %s" % [str(a == b), str(a != c)])

	for s in [1, 2, 3, 4, 5, 6]:
		var w := World.new()
		w.planet = PlanetGen.new(s)
		root.add_child(w)
		await process_frame
		w.rng.seed = s
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var viable := Genome.find_founder(probe, 3000) != ""
		w.populate(Genome.founder(w.rng))
		for _i in 1500:
			w.step()
		var pl := w.planet
		print("seed %d %-16s %-40s land %.2f  founder %s  pop %d  species %d" % [
			s, pl.name, pl.describe(), w.land_frac, "ok" if viable else "NONE", w.creatures.size(), w.species])
		ok = ok and viable and w.land_frac > 0.15 and w.land_frac < 0.75 and w.creatures.size() >= 30
		w.queue_free()
		await process_frame
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
