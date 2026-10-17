class_name Traits
extends RefCounted
## Genomes in human terms: which features a body has, its body plan, what a mutation would
## change, and random starting "origins". Everything here is read off the decoded phenotype,
## and each description says what the simulation really does with that trait.

# feature id -> [name, origin card title, what it does]
const INFO := {
	"mouth": ["Mouth", "Biter", "Bites and eats smaller creatures it catches. Plants give it less energy."],
	"legs": ["Legs", "Crawler", "Walks fast on land, but can no longer float over water."],
	"spikes": ["Spikes", "Urchin", "Predators and biters often fail to eat it."],
	"flagellum": ["Flagellum", "Darter", "Moves fast. Speed burns energy."],
	"eyes": ["Eyes", "Watcher", "Spots food and danger from much farther away."],
	"camo": ["Camouflage", "Shade", "Predators only notice it up close."],
	"gills": ["Gills", "Swimmer", "With limbs, lives in water: eats sea food and is safe from land predators, but dies on land."],
	"amphibious": ["Amphibious skin", "Amphibian", "With limbs, it can live in water and on land."],
	"big": ["Big body", "Giant", "Too big for most biters to eat, but costs more energy to run."],
	"tiny": ["Tiny body", "Mite", "Cheap to run, but easy prey for biters."],
	"heat": ["Heat-loving", "Ember", "Thrives in hot places; cold drains it."],
	"cold": ["Cold-loving", "Frost", "Thrives in cold places; heat drains it."],
	"fast_metab": ["Fast metabolism", "Burner", "Quicker, but hungrier."],
	"slow_metab": ["Slow metabolism", "Sleeper", "Slower, but needs less food."],
}
const STATS := [["size", "Size"], ["speed", "Speed"], ["sense", "Senses"], ["spikes", "Defense"],
	["camo", "Camouflage"], ["diet", "Carnivory"], ["metab", "Metabolism"], ["temp", "Heat tolerance"]]
# Aquatic traits change nothing while a body floats, so origins (all blobs) do not count them.
const ORIGIN_IGNORES := ["gills", "amphibious"]


static func features(g: Dictionary) -> Array[String]:
	var f: Array[String] = []
	if g["diet"] > 0.5:
		f.append("mouth")
	if g["limbs"].size() >= 1:
		f.append("legs")
	if g["spikes"] > 0.45:
		f.append("spikes")
	if g["speed"] > 0.65:
		f.append("flagellum")
	if g["sense"] > 0.68:
		f.append("eyes")
	if g["camo"] > 0.6:
		f.append("camo")
	if g["aqua"] > 0.65:
		f.append("gills")
	elif g["aqua"] > 0.35:
		f.append("amphibious")
	if g["size"] > 0.7:
		f.append("big")
	elif g["size"] < 0.3:
		f.append("tiny")
	if g["temp"] > 0.7:
		f.append("heat")
	elif g["temp"] < 0.3:
		f.append("cold")
	if g["metab"] > 0.7:
		f.append("fast_metab")
	elif g["metab"] < 0.3:
		f.append("slow_metab")
	return f


static func feature_names(g: Dictionary) -> String:
	var names: Array = features(g).map(func(f): return INFO[f][0])
	return ", ".join(names) if not names.is_empty() else "none yet"


## How the body gets around, from its limbs and how aquatic it is.
static func body_plan(g: Dictionary) -> String:
	var limbs: int = g["limbs"].size()
	if limbs == 0:
		return "Floater"
	if g["aqua"] > 0.65:
		return "Swimmer"
	if g["aqua"] > 0.35:
		return "Amphibian"
	return "Crawler" if limbs == 1 else "Walker"


static func body_plan_text(g: Dictionary) -> String:
	match body_plan(g):
		"Floater":
			return "drifts anywhere over water and land, slowly"
		"Swimmer":
			return "lives in water"
		"Amphibian":
			return "lives in water and on land"
		"Crawler":
			return "one limb: walks on land"
	return "%d legs: walks on land" % g["limbs"].size()


## Plain-language summary of what changes from body a to body b ("" if nothing visible does).
static func describe_change(a: Dictionary, b: Dictionary) -> String:
	var bits: Array[String] = []
	var fa := features(a)
	var fb := features(b)
	for f in fb:
		if not f in fa:
			bits.append("gains %s" % INFO[f][0])
	for f in fa:
		if not f in fb:
			bits.append("loses %s" % INFO[f][0])
	var dl: int = b["limbs"].size() - a["limbs"].size()
	if dl != 0:
		bits.append("%+d limb%s" % [dl, "" if absi(dl) == 1 else "s"])
	if body_plan(a) != body_plan(b):
		bits.append("becomes a %s" % body_plan(b))
	var deltas: Array = []
	for st in STATS:
		var d: float = b[st[0]] - a[st[0]]
		if absf(d) >= 0.03:
			deltas.append([absf(d), "%s %+d%%" % [st[1], roundi(d * 100.0)]])
	deltas.sort_custom(func(x, y): return x[0] > y[0])
	for i in mini(3, deltas.size()):
		bits.append(deltas[i][1])
	return ", ".join(bits)


## Up to `n` random single mutations of `dna` that visibly change the body, as
## {"m": mutation, "dna": result, "text": summary}. They are real DNA changes; the summary is
## just what they happen to do.
static func mutation_options(dna: String, rng: RandomNumberGenerator, n := 3) -> Array:
	var g0 := Genome.decode(dna)
	var out: Array = []
	var seen := {}
	for _t in 400:
		var m := Genome.random_mutation(dna, rng)
		var d := Genome.apply_mutation(dna, m)
		if d == "":
			continue
		var text := describe_change(g0, Genome.decode(d))
		if text == "" or seen.has(text):
			continue
		seen[text] = true
		out.append({"m": m, "dna": d, "text": text})
		if out.size() >= n:
			break
	return out


# ---------------------------------------------------------------- origins

## The one feature of a valid starting genome, or "": a single short gene whose body is a
## floating blob with exactly one feature (or a blob that has grown legs).
static func origin_feature(dna: String) -> String:
	if dna.length() > 64 or not Genome.is_dna(dna):
		return ""
	var g := Genome.decode(dna)
	if g["genes"] != 1:
		return ""
	var f := features(g).filter(func(x): return not x in ORIGIN_IGNORES)
	return f[0] if f.size() == 1 else ""


## `n` random origins with different features. Each is a random one-gene genome; which
## features turn up depends on what this world's genetic code makes likely.
static func origins(rng: RandomNumberGenerator, n := 3) -> Array[String]:
	var by_feature := {}
	for _t in 3000:
		var dna := Genome.junk(rng, 4) + Genome.random_gene(rng, 2 + rng.randi() % 5) + Genome.junk(rng, 4)
		var f := origin_feature(dna)
		if f != "" and not by_feature.has(f):
			by_feature[f] = dna
			if by_feature.size() >= 8:
				break
	var keys: Array = by_feature.keys()
	for i in range(keys.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = keys[i]
		keys[i] = keys[j]
		keys[j] = t
	var out: Array[String] = []
	for i in mini(n, keys.size()):
		out.append(by_feature[keys[i]])
	return out


static func origin_title(dna: String) -> String:
	var f := origin_feature(dna)
	return "Blob" if f == "" else INFO[f][1]
