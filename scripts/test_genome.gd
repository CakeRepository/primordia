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
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
