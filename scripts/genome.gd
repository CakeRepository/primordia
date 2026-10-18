class_name Genome
extends RefCounted
## DNA string <-> phenotype. Genes start at ATG and end at a stop codon.
## Each codon maps to an amino acid; each amino acid adds a small fixed vector to the body
## traits. Earth's genetic code is the default; every alien world installs its own
## (use_biochemistry), so the same DNA builds a different body on a different planet.

const EARTH_CODE := "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
const AMINO := "ACDEFGHIKLMNPQRSTVWY"
const BASES := ["A", "T", "G", "C"]
const KEYS := ["size", "speed", "sense", "spikes", "camo", "temp", "metab", "diet", "aqua"]
const LABELS := {
	"size": "Size", "speed": "Speed", "sense": "Senses", "spikes": "Spikes", "camo": "Camouflage",
	"temp": "Heat tolerance", "metab": "Metabolism", "diet": "Carnivory", "aqua": "Aquatic",
}
const BIAS := {"spikes": -2.0, "camo": -1.0, "diet": -3.0, "aqua": -3.0}
const START_IDX := 35 # ATG
const MAX_LEN := 1200
const OFF_TARGET := 0.08 # chance that a CRISPR edit also hits a random base

# Effect vectors: size, speed, sense, spikes, camo, temp, metab, diet, aqua, limbs, hue
const EARTH_EFF := {
	"F": [0.9417, 0.6394, 0, 0, 0, 0, 0, 0, 0, 0, -0.4707],
	"L": [0, 0.5913, 0, 0, -0.455, 0, 0, 0, 0, 0, 0.5584],
	"S": [0, 0, 0, 0, 0, 0, 0, -0.7358, 0, 0, 0.5427],
	"Y": [0, 0, 0, 0.9861, 0, 0, 0.9874, 0, 0, 0, 0],
	"C": [0, 0, 0, 0, -0.4116, 0, 0, -0.456, 0, 0, 0],
	"W": [0, 0, 0, 0.4361, 0, 0.568, 0, 0, -0.7205, 0, 0],
	"P": [0, 0, 0, 0.4926, 0, 0, 0, 0, -0.6804, -0.4832, 0],
	"H": [0, 0, 0, 0, 0, 0.7494, 0, 0, 0, -0.8623, 0.7986],
	"Q": [0, 0, -0.4744, 0, 0, 0, -0.8016, 0, 0, 0, 0],
	"R": [0, 0, 0.9729, 0, 0, 0, 0, 0.5964, 0, 0, -0.5183],
	"I": [0, 0, 0, 0, 0.63, -0.8406, 0, 0, -0.9272, 0, 0],
	"M": [0.8019, 0, 0, 0, 0, 0.4493, 0, 0, 0, 0.9018, 0],
	"T": [-0.8794, 0, 0.651, 0, 0, 0, 0, 0, 0, 0, -0.5737],
	"N": [-0.9635, 0, 0, 0, 0, 0.4789, 0, 0, 0, 0, 0],
	"K": [0, 0, 0, 0.4743, 0, 0.6072, 0, 0, 0, -0.7755, 0],
	"V": [0, 0, 0, 0.8633, 0, 0, 0, 0, 0.4429, -0.55, 0],
	"A": [0.5457, 0, 0, 0.6473, 0, 0, 0, 0, 0, 0, -0.4627],
	"D": [0, 0.8756, -0.8085, 0, 0, 0, 0.5888, 0, 0, 0, 0],
	"E": [0, -0.9082, 0, 0, 0, 0.7614, 0, 0, 0, 0, 0],
	"G": [0, 0, 0.8219, 0, 0, 0, 0.5459, 0, 0, 0.8908, 0]
}

static var code := EARTH_CODE # the active world's genetic code
static var eff: Dictionary = EARTH_EFF # the active world's amino-acid effects
static var hue_base := 200.0
static var _cache := {}
static var _base_index := {"T": 0, "C": 1, "A": 2, "G": 3}


static func codon_index(dna: String, i: int) -> int:
	if i < 0 or i + 3 > dna.length():
		return -1
	var a = _base_index.get(dna[i], -1)
	var b = _base_index.get(dna[i + 1], -1)
	var c = _base_index.get(dna[i + 2], -1)
	if a < 0 or b < 0 or c < 0:
		return -1
	return a * 16 + b * 4 + c


static func radius(g: Dictionary) -> float:
	return 3.0 + g["size"] * 7.0


static func decode(dna: String) -> Dictionary:
	if _cache.has(dna):
		return _cache[dna]
	var sum := PackedFloat64Array()
	sum.resize(11)
	var genes := 0
	var i := 0
	var n := dna.length()
	while i <= n - 3:
		if codon_index(dna, i) == START_IDX:
			genes += 1
			var j := i
			while j <= n - 3:
				var idx := codon_index(dna, j)
				j += 3
				if idx < 0:
					continue
				var aa := code[idx]
				if aa == "*":
					break
				var e: Array = eff[aa]
				for k in 11:
					sum[k] += e[k]
			i = j
		else:
			i += 1
	var g := {"genes": genes, "len": n}
	for k in 9:
		var key: String = KEYS[k]
		g[key] = 0.5 + 0.5 * tanh((sum[k] + BIAS.get(key, 0.0)) * 0.3)
	var count := clampi(roundi(sum[9]), 0, 12) # an empty genome is a limbless blob
	var limbs: Array = []
	for q in count:
		var f := fposmod(absf(sin(q * 12.9 + sum[9] * 3.0) * 43758.0), 1.0)
		limbs.append(Vector2(float(q) / count * TAU + 0.3 * sin(q * 1.7 + sum[10]), 0.3 + 0.7 * f))
	g["limbs"] = limbs
	g["hue"] = fposmod(hue_base + sum[10] * 45.0, 360.0)
	if _cache.size() > 6000:
		_cache.clear()
	_cache[dna] = g
	return g


## Limbless bodies float: they drift anywhere, over water or land, but slowly.
static func floats(g: Dictionary) -> bool:
	return g["limbs"].size() == 0


static func is_dna(s: String) -> bool:
	for ch in s:
		if not ch in BASES:
			return false
	return true


static func random_base(rng: RandomNumberGenerator) -> String:
	return BASES[rng.randi() % 4]


static func random_gene(rng: RandomNumberGenerator, codons: int) -> String:
	var s := "ATG"
	for _i in codons:
		var c := ""
		while true:
			c = random_base(rng) + random_base(rng) + random_base(rng)
			var idx := codon_index(c, 0)
			if idx >= 0 and code[idx] != "*" and c != "ATG":
				break
		s += c
	return s + ["TAA", "TAG", "TGA"][rng.randi() % 3]


static func junk(rng: RandomNumberGenerator, n: int) -> String:
	var s := ""
	for _i in n:
		s += random_base(rng)
	return s.replace("ATG", "ACG")


## A viable land founder: moderate traits, no spikes, herbivore, land dweller.
## Two genes: every gene's start codon adds a Met (size, heat tolerance, limbs), so with
## more genes the traits saturate and almost no candidate passes the filter.
static func founder(rng: RandomNumberGenerator) -> String:
	var s := find_founder(rng, 20000)
	return s if s != "" else junk(rng, 5) + random_gene(rng, 7) + random_gene(rng, 7)


## Search for a founder that passes the viability filter; "" if none turned up in `tries`.
static func find_founder(rng: RandomNumberGenerator, tries: int) -> String:
	for _t in tries:
		var s := junk(rng, 5)
		for _i in 2:
			s += random_gene(rng, 7) + junk(rng, 4)
		var g := decode(s)
		if g["size"] > .25 and g["size"] < .75 and g["speed"] > .25 and g["speed"] < .75 \
				and g["sense"] > .25 and g["sense"] < .75 and g["spikes"] < .45 and g["diet"] < .35 \
				and g["aqua"] < .3 and g["temp"] > .25 and g["temp"] < .75 \
				and g["metab"] > .25 and g["metab"] < .75 and g["limbs"].size() >= 1:
			return s
	return ""


static func use_earth_biochemistry() -> void:
	code = EARTH_CODE
	eff = EARTH_EFF
	hue_base = 200.0
	_cache.clear()


## Install an alien biochemistry generated from `seed`. ATG stays the start codon and
## TAA/TAG/TGA stay stops, so genes are found the same way on every world; every other codon
## is reassigned to an amino acid, and each amino acid gets its own random effect on the body.
static func use_biochemistry(seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	# 60 sense codons besides ATG: every amino acid but Met at least once, the rest random.
	var letters: Array = []
	for aa in AMINO:
		if aa != "M":
			letters.append(aa)
	while letters.size() < 60:
		letters.append(letters[r.randi() % 19])
	for i in range(letters.size() - 1, 0, -1): # Fisher-Yates with our own rng, so it is reproducible
		var j := r.randi() % (i + 1)
		var t = letters[i]
		letters[i] = letters[j]
		letters[j] = t
	var c := ""
	for i in 64:
		if EARTH_CODE[i] == "*":
			c += "*"
		elif i == START_IDX:
			c += "M"
		else:
			c += letters.pop_back()
	code = c
	# Each amino acid nudges two or three traits, like Earth's table but different on every world.
	var table := {}
	for aa in AMINO:
		var v: Array = []
		v.resize(11)
		v.fill(0.0)
		var picks: Array = range(11)
		for _n in r.randi_range(2, 3):
			var k: int = picks.pop_at(r.randi() % picks.size())
			v[k] = r.randf_range(0.4, 1.0) * (1.0 if r.randf() < 0.5 else -1.0)
		if aa == "M": # every gene starts with one, so keep it gentle
			for k in 11:
				v[k] *= 0.35
		table[aa] = v
	# Every trait must be pushable both ways, or some bodies could never evolve on this world.
	for k in 11:
		for dir in [1.0, -1.0]:
			var found := false
			for aa in table:
				found = found or table[aa][k] * dir > 0.0
			if not found:
				var aa: String = AMINO[r.randi() % AMINO.length()].replace("M", "A")
				table[aa][k] = r.randf_range(0.4, 1.0) * dir
	eff = table
	hue_base = r.randf() * 360.0
	_cache.clear()


## One CRISPR edit at base p: "rep" replaces it with b, "ins" inserts b after it, "del" cuts it.
## Returns {dna, cursor, msg, done}; when done is false the edit was refused and dna is unchanged.
static func edit(dna: String, kind: String, p: int, b: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := dna
	var cursor := p
	match kind:
		"rep":
			d = d.substr(0, p) + b + d.substr(p + 1)
		"ins":
			d = d.substr(0, p + 1) + b + d.substr(p + 1)
			cursor = p + 1
		"del":
			if d.length() <= 30:
				return {"dna": dna, "cursor": p, "msg": "Genome too short to cut.", "done": false}
			d = d.substr(0, p) + d.substr(p + 1)
			cursor = mini(p, d.length() - 1)
	var hit := off_target(d, rng)
	var msg := "Edit made." if hit[1] < 0 else "Off-target cut at base %d." % (hit[1] + 1)
	return {"dna": hit[0], "cursor": cursor, "msg": msg, "done": true}


## Every lab edit risks a stray substitution elsewhere. Returns [dna, position hit or -1].
static func off_target(dna: String, rng: RandomNumberGenerator) -> Array:
	if rng.randf() >= OFF_TARGET:
		return [dna, -1]
	var q := rng.randi() % dna.length()
	var nb := random_base(rng)
	while nb == dna[q]:
		nb = random_base(rng)
	return [dna.substr(0, q) + nb + dna.substr(q + 1), q]


## A single mutation as data, so a client can propose one and the server can check it:
## {"op": "sub"|"ins"|"del"|"dup", "pos": int, "bases": String (sub, ins), "len": int (del, dup)}.
## Returns the mutated DNA, or "" when `m` is not a valid single change to `dna`.
static func apply_mutation(dna: String, m: Dictionary) -> String:
	var n := dna.length()
	var p = m.get("pos")
	if typeof(p) != TYPE_INT or p < 0 or p >= n:
		return ""
	var b = m.get("bases", "")
	var l = m.get("len", 0)
	match m.get("op"):
		"sub":
			if typeof(b) == TYPE_STRING and b.length() == 1 and is_dna(b) and b != dna[p]:
				return dna.substr(0, p) + b + dna.substr(p + 1)
		"ins":
			if typeof(b) == TYPE_STRING and b.length() >= 1 and b.length() <= 30 and is_dna(b) and n + b.length() <= MAX_LEN:
				return dna.substr(0, p + 1) + b + dna.substr(p + 1)
		"del":
			if typeof(l) == TYPE_INT and l >= 1 and l <= 3 and p + l <= n and n - l >= 30:
				return dna.substr(0, p) + dna.substr(p + l)
		"dup":
			if typeof(l) == TYPE_INT and l >= 3 and l <= 30 and p + l <= n and n + l <= MAX_LEN:
				return dna.substr(0, p + l) + dna.substr(p, l) + dna.substr(p + l)
	return ""


## One random mutation of `dna`: mostly point changes, sometimes small insertions or deletions,
## a duplicated stretch, or a whole new gene.
static func random_mutation(dna: String, rng: RandomNumberGenerator) -> Dictionary:
	var n := dna.length()
	var p := rng.randi() % n
	var r := rng.randf()
	if r < 0.45:
		var b := random_base(rng)
		while b == dna[p]:
			b = random_base(rng)
		return {"op": "sub", "pos": p, "bases": b}
	if r < 0.6:
		var s := ""
		for _i in 1 + rng.randi() % 3:
			s += random_base(rng)
		return {"op": "ins", "pos": p, "bases": s}
	if r < 0.72:
		var l := 1 + rng.randi() % 3
		return {"op": "del", "pos": rng.randi() % maxi(1, n - l), "len": l}
	if r < 0.85:
		var l := mini(6 + rng.randi() % 25, n - 1)
		return {"op": "dup", "pos": rng.randi() % maxi(1, n - l), "len": l}
	return {"op": "ins", "pos": p, "bases": random_gene(rng, 2 + rng.randi() % 4)}


static func _poisson(rng: RandomNumberGenerator, l: float) -> int:
	var limit := exp(-l)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= rng.randf()
		if p <= limit:
			break
	return k - 1


## Copy with substitutions, insertions, deletions and segment duplications.
static func mutate(dna: String, rate: float, rng: RandomNumberGenerator) -> String:
	var n := _poisson(rng, rate * dna.length() * 0.0035)
	for _e in n:
		var length := dna.length()
		var p := rng.randi() % length
		var r := rng.randf()
		if r < 0.7:
			var b := random_base(rng)
			while b == dna[p]:
				b = random_base(rng)
			dna = dna.substr(0, p) + b + dna.substr(p + 1)
		elif r < 0.82:
			var s := ""
			for _i in 1 + rng.randi() % 3:
				s += random_base(rng)
			dna = dna.substr(0, p) + s + dna.substr(p)
		elif r < 0.94:
			if length > 40:
				dna = dna.substr(0, p) + dna.substr(p + 1 + rng.randi() % 3)
		else:
			var m := 6 + rng.randi() % 25
			if length < MAX_LEN:
				dna = dna.substr(0, p + m) + dna.substr(p, m) + dna.substr(p + m)
	return dna
