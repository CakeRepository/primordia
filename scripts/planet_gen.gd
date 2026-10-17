class_name PlanetGen
extends RefCounted
## Everything about a world that follows from its seed: name, terrain, biome palette, sky,
## star and moons, physical constants, creature body style and the biochemistry (genetic
## code and amino-acid effects). Deterministic: a server only shares the seed and every
## client builds the same alien planet.

const STARS := [
	["red dwarf", Color(1.0, 0.55, 0.35), 0.9],
	["orange star", Color(1.0, 0.75, 0.5), 1.0],
	["yellow star", Color(1.0, 0.95, 0.85), 1.1],
	["white star", Color(0.96, 0.97, 1.0), 1.2],
	["blue giant", Color(0.7, 0.8, 1.0), 1.35],
]
const SYLLABLES := ["ka", "ve", "lo", "thi", "zu", "ra", "mo", "xe", "qua", "ny", "sel", "dra", "or", "um",
	"ith", "bel", "cor", "fen", "gal", "ix", "jor", "pha", "rhu", "syl", "tor", "ul", "vex", "wyn", "yor", "zan"]
const SUFFIXES := ["", "", "", " II", " IV", " VII", " Prime", " b", " c"]

var seed := 0
var name := ""

# terrain (World grid, GW x GH cells)
var elev := PackedFloat32Array()
var moist := PackedFloat32Array()
var base_t := PackedFloat32Array()
var tidally_locked := false # one face always toward the star: hot to cold runs east to west

# look
var palette := {} # biome -> Color
var water := Color()
var food_land := Color()
var food_sea := Color()
var predator := Color()
var sky_top := Color()
var sky_horizon := Color()
var star_name := ""
var star_color := Color()
var star_energy := 1.0
var sun_angles := Vector2() # pitch, yaw in degrees
var moons: Array = [] # [{"dir": Vector3, "size": float, "color": Color}]
var body_shape := Vector3.ONE # how this world's creatures are proportioned

# physics and life
var gravity := 1.0 # scales the energy cost of size and movement
var radiation := 1.0 # scales the mutation rate
var fertility := 1.0 # scales how fast food grows
var climate := 0.5 # resting temperature
var relief := 40.0 # metres of height per unit of elevation in 3D
var biochem_seed := 0


func _init(s: int) -> void:
	seed = s
	var r := RandomNumberGenerator.new()
	r.seed = s
	name = _make_name(r)
	_make_terrain(r)
	_make_look(r)
	gravity = r.randf_range(0.75, 1.3)
	radiation = r.randf_range(0.6, 1.7)
	fertility = r.randf_range(0.8, 1.3)
	climate = r.randf_range(0.4, 0.6)
	relief = r.randf_range(25.0, 60.0)
	body_shape = Vector3(r.randf_range(0.8, 1.2), r.randf_range(0.6, 1.2), r.randf_range(0.9, 1.5))
	_pick_biochemistry(r.randi())


## Make this world's genetic code the active one (Genome is global: one world at a time).
func apply_biochemistry() -> void:
	Genome.use_biochemistry(biochem_seed)


## Re-roll the biochemistry until a viable land founder exists, so every world is playable.
func _pick_biochemistry(base: int) -> void:
	for attempt in 40:
		biochem_seed = base + attempt
		Genome.use_biochemistry(biochem_seed)
		var probe := RandomNumberGenerator.new()
		probe.seed = biochem_seed
		if Genome.find_founder(probe, 3000) != "":
			return


static func _make_name(r: RandomNumberGenerator) -> String:
	var n := ""
	for i in r.randi_range(2, 3):
		n += SYLLABLES[r.randi() % SYLLABLES.size()]
		if i == 0 and r.randf() < 0.2:
			n += "'"
	return n.capitalize().replace(" ", "") + SUFFIXES[r.randi() % SUFFIXES.size()]


# ---------------------------------------------------------------- terrain

func _make_terrain(r: RandomNumberGenerator) -> void:
	# Re-roll the shape until the planet has a sensible share of land.
	for _attempt in 12:
		var n0 := FastNoiseLite.new()
		n0.seed = r.randi()
		n0.noise_type = [FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.TYPE_PERLIN, FastNoiseLite.TYPE_VALUE_CUBIC][r.randi() % 3]
		n0.frequency = r.randf_range(0.009, 0.02)
		n0.fractal_octaves = r.randi_range(3, 6)
		n0.fractal_type = [FastNoiseLite.FRACTAL_FBM, FastNoiseLite.FRACTAL_FBM, FastNoiseLite.FRACTAL_RIDGED][r.randi() % 3]
		if r.randf() < 0.5:
			n0.domain_warp_enabled = true
			n0.domain_warp_amplitude = r.randf_range(10.0, 40.0)
			n0.domain_warp_frequency = r.randf_range(0.01, 0.04)
		var n1 := FastNoiseLite.new()
		n1.seed = r.randi()
		n1.frequency = r.randf_range(0.015, 0.03)
		n1.fractal_octaves = 3
		var contrast := r.randf_range(1.2, 1.9)
		var edge_drop := r.randf_range(0.15, 0.4) # how much the map edges sink: islands vs continents
		var shift := r.randf_range(-0.06, 0.06) # wetter or drier world
		tidally_locked = r.randf() < 0.2
		var gw := World.GW
		var gh := World.GH
		elev.resize(gw * gh)
		moist.resize(gw * gh)
		base_t.resize(gw * gh)
		var land := 0
		for j in gh:
			for i in gw:
				var k := j * gw + i
				var u := float(i) / gw
				var v := float(j) / gh
				var e := (n0.get_noise_2d(i, j) + 1.0) * 0.5
				e = (e - 0.5) * contrast + 0.5
				var edge := pow(maxf(absf(u - 0.5), absf(v - 0.5)) * 2.0, 3.0)
				elev[k] = e - edge * edge_drop + shift
				moist[k] = clampf((n1.get_noise_2d(i, j) + 1.0) * 0.5, 0.0, 1.0)
				# warm at the equator, or on the side facing the star for a locked world
				var warmth := 1.0 - u if tidally_locked else 1.0 - absf(v - 0.5) * 2.0
				base_t[k] = clampf(0.12 + 0.78 * warmth - maxf(0.0, elev[k] - World.SEA) * 0.5, 0.0, 1.0)
				if elev[k] >= World.SEA:
					land += 1
		var frac := float(land) / (gw * gh)
		if frac > 0.22 and frac < 0.68:
			return


# ---------------------------------------------------------------- look

func _make_look(r: RandomNumberGenerator) -> void:
	var veg := r.randf() # hue of plant life
	var veg_s := r.randf_range(0.35, 0.85)
	var plain := Color.from_hsv(veg, veg_s, r.randf_range(0.36, 0.5))
	var mineral := r.randf()
	var desert := Color.from_hsv(mineral, r.randf_range(0.3, 0.6), r.randf_range(0.5, 0.66))
	var ice := Color.from_hsv(r.randf(), r.randf_range(0.04, 0.3), r.randf_range(0.76, 0.9))
	var sea := r.randf()
	var shallow := Color.from_hsv(sea, r.randf_range(0.55, 0.9), r.randf_range(0.34, 0.5))
	palette = {
		"plain": plain,
		"jungle": Color.from_hsv(fposmod(veg + r.randf_range(-0.06, 0.06), 1.0), minf(1.0, veg_s + 0.1), plain.v * 0.62),
		"tundra": Color.from_hsv(fposmod(veg + r.randf_range(-0.1, 0.1), 1.0), veg_s * 0.35, r.randf_range(0.32, 0.42)),
		"desert": desert,
		"coast": Color.from_hsv(fposmod(mineral + 0.03, 1.0), desert.s * 0.7, desert.v * 0.85),
		"rock": Color.from_hsv(r.randf(), r.randf_range(0.05, 0.25), r.randf_range(0.3, 0.42)),
		"frost": ice,
		"snow": ice.lightened(0.15),
		"shallow": shallow,
		"deep": Color.from_hsv(fposmod(sea + r.randf_range(-0.05, 0.05), 1.0), minf(1.0, shallow.s + 0.1), shallow.v * 0.4),
		"ice_sea": ice,
	}
	water = Color(Color.from_hsv(sea, shallow.s * 0.8, minf(1.0, shallow.v * 1.15)), r.randf_range(0.55, 0.8))
	food_land = Color.from_hsv(fposmod(veg + 0.04, 1.0), minf(1.0, veg_s + 0.15), 0.85)
	food_sea = Color.from_hsv(fposmod(sea + 0.08, 1.0), 0.5, 0.95)
	predator = Color.from_hsv(fposmod(r.randf_range(-0.05, 0.08), 1.0), 0.8, 0.95)
	var sky := r.randf()
	sky_top = Color.from_hsv(sky, r.randf_range(0.4, 0.8), r.randf_range(0.35, 0.7))
	sky_horizon = Color.from_hsv(fposmod(sky + r.randf_range(-0.1, 0.1), 1.0), r.randf_range(0.15, 0.4), r.randf_range(0.7, 0.9))
	var star: Array = STARS[r.randi() % STARS.size()]
	star_name = star[0]
	star_color = star[1]
	star_energy = star[2]
	sun_angles = Vector2(r.randf_range(-70.0, -30.0), r.randf_range(0.0, 360.0))
	var count: int = [0, 1, 1, 2, 2, 3][r.randi() % 6]
	for _m in count:
		var az := r.randf() * TAU
		var el := deg_to_rad(r.randf_range(6.0, 28.0)) # low enough to rise over the horizon in view
		moons.append({
			"dir": Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)),
			"size": r.randf_range(18.0, 70.0),
			"color": Color.from_hsv(r.randf(), r.randf_range(0.0, 0.35), r.randf_range(0.6, 0.95)),
		})


## Short description for the HUD and server listings.
func describe() -> String:
	var bits := [star_name]
	if moons.size() > 0:
		bits.append("%d moon%s" % [moons.size(), "" if moons.size() == 1 else "s"])
	if tidally_locked:
		bits.append("tidally locked")
	bits.append("%.2fg" % gravity)
	return ", ".join(bits)
