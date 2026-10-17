extends SceneTree
## Headless checks: godot --headless -s res://scripts/test_genome.gd

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ok := true
	# ATG GCC TAA -> one gene, one amino acid (M, A) then stop
	var g := Genome.decode("ATGGCCTAA")
	ok = ok and g["genes"] == 1
	# no start codon -> no genes
	ok = ok and Genome.decode("CCCCCCCCC")["genes"] == 0
	var dna := Genome.founder(rng)
	var f := Genome.decode(dna)
	print("founder len=%d genes=%d limbs=%d aqua=%.2f" % [f["len"], f["genes"], f["limbs"].size(), f["aqua"]])
	ok = ok and f["genes"] >= 1 and f["aqua"] < 0.35
	# founder() must find a candidate that passes its own filter, not fall back
	for k in ["size", "speed", "sense", "temp", "metab"]:
		ok = ok and f[k] > 0.25 and f[k] < 0.75
	ok = ok and f["spikes"] < 0.45 and f["diet"] < 0.35
	var m := dna
	for _i in 200:
		m = Genome.mutate(m, 1.0, rng)
	ok = ok and m != dna and m.length() >= 30
	print("mutated len=%d genes=%d" % [m.length(), Genome.decode(m)["genes"]])
	# an empty genome is a limbless blob, and limbless bodies float
	ok = ok and Genome.floats(Genome.decode("CCCCCCCCC"))
	# mutations are data: applied exactly, and anything that is not one valid change is refused
	var opts := Traits.mutation_options(dna, rng)
	ok = ok and opts.size() == 3
	for o in opts:
		ok = ok and Genome.apply_mutation(dna, o["m"]) == o["dna"] and o["text"] != ""
	print("mutation options: ", opts.map(func(o): return o["text"]))
	ok = ok and Genome.apply_mutation(dna, {"op": "ins", "pos": 0, "bases": "AXA"}) == ""
	ok = ok and Genome.apply_mutation(dna, {"op": "del", "pos": 0, "len": 9}) == ""
	ok = ok and Genome.apply_mutation(dna, {"op": "sub", "pos": 9999, "bases": "A"}) == ""
	# origins on an alien world: random one-gene blobs with exactly one feature, all different
	Genome.use_biochemistry(1234)
	var origins := Traits.origins(rng, 3)
	var feats := origins.map(func(d): return Traits.origin_feature(d))
	print("origins: ", feats, " ", origins.map(func(d): return Traits.body_plan(Genome.decode(d))))
	ok = ok and origins.size() == 3 and not "" in feats and feats[0] != feats[1] and feats[1] != feats[2] and feats[0] != feats[2]
	for d in origins:
		var og := Genome.decode(d)
		ok = ok and og["genes"] == 1 and (Genome.floats(og) or Traits.origin_feature(d) == "legs")
	ok = ok and Traits.origin_feature(dna) == "" # a two-gene founder is not a starting blob
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
