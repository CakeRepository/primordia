class_name Genome
extends RefCounted
## DNA string <-> phenotype. Genes start at ATG and end at a stop codon.
## Each codon maps to an amino acid (standard genetic code); each amino acid
## adds a small fixed vector to the body traits. Ported from the web prototype.

const CODE := "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
const BASES := ["A", "T", "G", "C"]
const KEYS := ["size", "speed", "sense", "spikes", "camo", "temp", "metab", "diet", "aqua"]
const LABELS := {
	"size": "Size", "speed": "Speed", "sense": "Senses", "spikes": "Spikes", "camo": "Camouflage",
	"temp": "Heat tolerance", "metab": "Metabolism", "diet": "Carnivory", "aqua": "Aquatic",
}
const BIAS := {"spikes": -2.0, "camo": -1.0, "diet": -3.0, "aqua": -3.0}
const START_IDX := 35 # ATG
const MAX_LEN := 1200

# Effect vectors: size, speed, sense, spikes, camo, temp, metab, diet, aqua, limbs, hue
const EFF := {
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
				var aa := CODE[idx]
				if aa == "*":
					break
				var e: Array = EFF[aa]
				for k in 11:
					sum[k] += e[k]
			i = j
		else:
			i += 1
	var g := {"genes": genes, "len": n}
	for k in 9:
		var key: String = KEYS[k]
		g[key] = 0.5 + 0.5 * tanh((sum[k] + BIAS.get(key, 0.0)) * 0.3)
	var count := clampi(roundi(2.0 + sum[9]), 0, 12)
	var limbs: Array = []
	for q in count:
		var f := fposmod(absf(sin(q * 12.9 + sum[9] * 3.0) * 43758.0), 1.0)
		limbs.append(Vector2(float(q) / count * TAU + 0.3 * sin(q * 1.7 + sum[10]), 0.3 + 0.7 * f))
	g["limbs"] = limbs
	g["hue"] = fposmod(200.0 + sum[10] * 45.0, 360.0)
	if _cache.size() > 6000:
		_cache.clear()
	_cache[dna] = g
	return g


static func random_base(rng: RandomNumberGenerator) -> String:
	return BASES[rng.randi() % 4]


static func random_gene(rng: RandomNumberGenerator, codons: int) -> String:
	var s := "ATG"
	for _i in codons:
		var c := ""
		while true:
			c = random_base(rng) + random_base(rng) + random_base(rng)
			var idx := codon_index(c, 0)
			if idx >= 0 and CODE[idx] != "*" and c != "ATG":
				break
		s += c
	return s + ["TAA", "TAG", "TGA"][rng.randi() % 3]


static func junk(rng: RandomNumberGenerator, n: int) -> String:
	var s := ""
	for _i in n:
		s += random_base(rng)
	return s.replace("ATG", "ACG")


## A viable land founder: moderate traits, no spikes, herbivore, land dweller.
static func founder(rng: RandomNumberGenerator) -> String:
	for _t in 20000:
		var s := junk(rng, 5)
		for _i in 6:
			s += random_gene(rng, 7) + junk(rng, 4)
		var g := decode(s)
		if g["size"] > .25 and g["size"] < .75 and g["speed"] > .25 and g["speed"] < .75 \
				and g["sense"] > .25 and g["sense"] < .75 and g["spikes"] < .45 and g["diet"] < .35 \
				and g["aqua"] < .3 and g["temp"] > .25 and g["temp"] < .75 \
				and g["metab"] > .25 and g["metab"] < .75 and g["limbs"].size() >= 1:
			return s
	return junk(rng, 5) + random_gene(rng, 7) + random_gene(rng, 7)


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
