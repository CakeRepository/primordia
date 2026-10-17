class_name World
extends Node2D
## The living planet: terrain, food, predators and creatures. Port of the web prototype.
## The planet itself (terrain, palette, physics, genetic code) comes from a PlanetGen seed.

const WW := 2400.0
const WH := 1500.0
const GW := 120
const GH := 75
const CS := 20.0
const SEA := 0.46 # reference sea level; in dynamic worlds the real one (sea_level) moves with the climate
const SEA_SWING := 0.25 # sea-level change per unit of temperature away from the planet's baseline
const FC := 60.0
const FW := 40
const FH := 25
const MAX_POP := 600
const LIFESPAN := 3500 # ticks
const METEOR_R := 240.0
const METEOR_WARN := 240 # ticks between a meteor being sighted and its impact
const CRATER_LIFE := 1200 # ticks for scorched ground to recover
const SCORCH := Color(0.12, 0.09, 0.08)
const ERAS := [
	{"name": "Ice age", "temp": -0.28},
	{"name": "Cold era", "temp": -0.14},
	{"name": "Temperate era", "temp": 0.0},
	{"name": "Warm era", "temp": 0.14},
	{"name": "Hothouse", "temp": 0.28},
]

class Creature:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var e := 45.0
	var age := 0
	var dna := ""
	var g := {}
	var gen := 1
	var r := 6.0
	var block := 0
	var wa := 0.0
	var dead := false
	var cause := "" # how it died, phrased to follow "You ..."
	var id := 0 # unique within this world (used to sync creatures over the network)
	var owner := 0 # lineage id of the player whose line this is; 0 = wild
	var driver := 0 # peer id of the player playing this creature right now; 0 = AI
	var dna_id := 0 # network id of its DNA string (server side)

class Food:
	var pos := Vector2.ZERO
	var aq := false
	var dead := false

class Predator:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var stun := 0
	var aq := false
	var wa := 0.0

var rng := RandomNumberGenerator.new()
var planet: PlanetGen = null # set before adding to the tree to choose the world; random otherwise
var elev := PackedFloat32Array()
var moist := PackedFloat32Array()
var base_t := PackedFloat32Array()
var terrain_tex: ImageTexture
var land_frac := 0.5
var terrain_version := 0 # bumped whenever the ground itself is regenerated

var creatures: Array[Creature] = []
var foods: Array[Food] = []
var preds: Array[Predator] = []
var grid: Array = []
var n_land := 0
var n_sea := 0

var tick := 0
var running := false
var mut_boost := 0
var selected: Creature = null
var craters: Array = [] # [Vector2, radius, alpha]

# Player levers
var temp := 0.5
var food := 0.6
var pred := 0.3
var mut := 0.35

var species := 0
var history: Array = []

# Planet dynamics (3D worlds): climate eras move temperature and sea level, and natural
# disasters strike. Off in the top-down view, where the player sets the climate by hand.
var dynamic := false
var climate_base := 0.5 # the planet's resting temperature
var era := 2
var era_left := 0 # ticks until the next era
var sea_level := SEA
var incoming: Array = [] # [Vector2 pos, ticks left]: meteors on their way down
var _painted_temp := -1.0
var _painted_craters := 0

# Players (3D mode). Each plays one creature that lives by the same rules as everything else,
# but moves by input and only reproduces when asked. Keyed by peer id.
var players := {} # peer -> Creature
var inputs := {} # peer -> wanted heading, length <= 1
var blocked := {} # peer -> why the last move was refused ("" if it was not)
var next_id := 1

signal extinct
signal charge_tick
signal terrain_changed
signal player_died(peer: int, old: Creature, heir: Creature) # heir is null when the lineage has ended
signal planet_event(text: String)
signal meteor_incoming(pos: Vector2)
signal meteor_impact(pos: Vector2, killed: int)


func _ready() -> void:
	rng.randomize()
	grid.resize(FW * FH)
	for i in grid.size():
		grid[i] = []
	if planet == null:
		gen_world()
	else:
		use_planet(planet)


# ---------------------------------------------------------------- terrain

## A brand-new random planet under the current population.
func gen_world() -> void:
	use_planet(PlanetGen.new(rng.randi()))


func use_planet(p: PlanetGen) -> void:
	planet = p
	p.apply_biochemistry()
	elev = p.elev
	moist = p.moist
	base_t = p.base_t
	climate_base = p.climate
	terrain_version += 1
	_measure_land()
	paint_terrain()


func paint_terrain() -> void:
	var img := Image.create(GW, GH, false, Image.FORMAT_RGB8)
	for k in GW * GH:
		img.set_pixel(k % GW, k / GW, terrain_color(k))
	if terrain_tex == null:
		terrain_tex = ImageTexture.create_from_image(img)
	else:
		terrain_tex.update(img)
	terrain_changed.emit()


## Colour of cell k under the current climate and sea level, with meteor scorch on top.
func terrain_color(k: int) -> Color:
	var c := _biome_color(k)
	if craters.is_empty():
		return c
	var at := Vector2((k % GW + 0.5) * CS, (k / GW + 0.5) * CS)
	for cr in craters:
		var d: float = at.distance_to(cr[0])
		if d < cr[1]:
			c = c.lerp(SCORCH, cr[2] * 0.8 * (1.0 - 0.5 * d / cr[1]))
	return c


## Biome colour of cell k: ocean, coast, snow, forest, desert...
func _biome_color(k: int) -> Color:
	var e := elev[k]
	var m := moist[k]
	var tl := clampf(base_t[k] + temp - 0.5, 0.0, 1.0)
	var pal := planet.palette
	if e < sea_level:
		var d := clampf((sea_level - e) / 0.25, 0.0, 1.0)
		var c: Color = pal["shallow"].lerp(pal["deep"], d)
		return c.lerp(pal["ice_sea"], 0.35) if tl < 0.12 else c
	if e < sea_level + 0.025:
		return pal["coast"]
	if e > 0.78:
		return pal["snow"] if tl < 0.35 else pal["rock"]
	if tl < 0.22:
		return pal["frost"]
	if tl < 0.4:
		return pal["tundra"]
	if m > 0.58 and tl > 0.35:
		return pal["jungle"]
	if m < 0.34 and tl > 0.55:
		return pal["desert"]
	return pal["plain"]


## Elevation anywhere, bilinearly interpolated between cell centres (for smooth 3D ground).
func elev_at(p: Vector2) -> float:
	var u := clampf(p.x / CS - 0.5, 0.0, GW - 1.001)
	var v := clampf(p.y / CS - 0.5, 0.0, GH - 1.001)
	var i := int(u)
	var j := int(v)
	var k := j * GW + i
	var top := lerpf(elev[k], elev[k + 1], u - i)
	var bottom := lerpf(elev[k + GW], elev[k + GW + 1], u - i)
	return lerpf(top, bottom, v - j)


func cell_of(p: Vector2) -> int:
	var cx := clampi(int(p.x / CS), 0, GW - 1)
	var cy := clampi(int(p.y / CS), 0, GH - 1)
	return cy * GW + cx


func is_wet(p: Vector2) -> bool:
	return elev[cell_of(p)] < sea_level


func _measure_land() -> void:
	var land := 0
	for e in elev:
		if e >= sea_level:
			land += 1
	land_frac = clampf(float(land) / (GW * GH), 0.15, 0.85)


func temp_at(p: Vector2) -> float:
	return clampf(base_t[cell_of(p)] + (temp - 0.5) + 0.08 * sin(tick / 1200.0), 0.0, 1.0)


func rand_point(wet: bool) -> Vector2:
	for _t in 200:
		var p := Vector2(rng.randf() * WW, rng.randf() * WH)
		if is_wet(p) == wet:
			return p
	return Vector2(WW / 2, WH / 2)


# ---------------------------------------------------------------- creatures

func spawn(dna: String, pos: Vector2, energy := 45.0, gen := 1) -> Creature:
	var c := Creature.new()
	c.pos = pos
	c.dna = dna
	c.g = Genome.decode(dna)
	c.r = Genome.radius(c.g)
	c.e = energy
	c.gen = gen
	c.id = next_id
	next_id += 1
	creatures.append(c)
	return c


func _reset() -> void:
	creatures.clear()
	foods.clear()
	preds.clear()
	history.clear()
	n_land = 0
	n_sea = 0
	tick = 0
	species = 0
	selected = null
	players.clear()
	inputs.clear()
	blocked.clear()
	incoming.clear()
	craters.clear()
	dynamic = false
	sea_level = SEA


func release(dna: String) -> void:
	_reset()
	for _i in 60:
		spawn(dna, rand_point(false))
	running = true


## A living planet for players to join (3D mode): native species that each start from their
## own founder genome. Everything evolves under the same rules from here on.
func populate(natives := 4, per_species := 15) -> void:
	_reset()
	for _s in natives:
		var dna := Genome.founder(rng)
		var home := rand_point(false)
		for _i in per_species:
			spawn(dna, near_land(home, 80.0))
	dynamic = true
	era = 2
	era_left = rng.randi_range(2000, 4000)
	temp = climate_base
	sea_level = SEA
	_reshape_coasts()
	for _i in 300:
		_grow_food()
	_count_species()
	running = true


## Peer `peer` starts playing lineage `owner`. If that lineage still has living members (the
## player left and came back), they take over one of them; otherwise a new line
## starts from `dna`, with a few wild kin of the same kind around it.
func join(peer: int, owner: int, dna: String, kin := 14) -> Creature:
	var c := _heir_of(owner, Vector2(WW, WH) / 2.0)
	if c == null:
		c = spawn(dna, rand_point(false))
		c.owner = owner
		for _i in kin:
			spawn(dna, near_land(c.pos, 60.0))
	c.driver = peer
	players[peer] = c
	running = true
	return c


## The player stops playing. Their creatures carry on under AI and stay their lineage.
func leave(peer: int) -> void:
	if players.has(peer):
		players[peer].driver = 0
	players.erase(peer)
	inputs.erase(peer)
	blocked.erase(peer)


## A random land point around p, or p itself if none turns up.
func near_land(p: Vector2, spread: float) -> Vector2:
	for _t in 30:
		var q := (p + Vector2(rng.randfn(0, spread), rng.randfn(0, spread))).clamp(Vector2.ZERO, Vector2(WW, WH))
		if not is_wet(q):
			return q
	return p


func drop(dna: String, pos: Vector2) -> void:
	for _i in 8:
		var p := pos + Vector2(rng.randfn(0, 14), rng.randfn(0, 14))
		spawn(dna, Vector2(clampf(p.x, 0, WW), clampf(p.y, 0, WH)), 55.0)


func meteor() -> void:
	_impact(Vector2(rng.randf() * WW, rng.randf() * WH))


## A meteor is sighted now and lands at p after `warn` ticks.
func meteor_at(p: Vector2, warn := METEOR_WARN) -> void:
	incoming.append([p, warn])
	meteor_incoming.emit(p)


func _impact(p: Vector2) -> void:
	craters.append([p, METEOR_R, 1.0])
	var killed := 0
	for c in creatures:
		if not c.dead and c.pos.distance_to(p) <= METEOR_R and rng.randf() >= 0.08:
			c.dead = true
			c.cause = "were hit by a meteor"
			killed += 1
	creatures = creatures.filter(func(c: Creature): return not c.dead)
	foods = foods.filter(func(f: Food): return f.pos.distance_to(p) > METEOR_R)
	if selected != null and selected.dead:
		selected = null
	_reshape_coasts()
	meteor_impact.emit(p, killed)


## Fresh terrain under the current population. Predators are respawned so none are left
## stranded in the wrong biome, where they could never move again.
func new_world() -> void:
	gen_world()
	foods.clear()
	preds.clear()


func storm() -> void:
	mut_boost = 600


func wild_seed() -> void:
	if creatures.is_empty():
		return
	for _i in 8:
		var p: Creature = creatures[rng.randi() % creatures.size()]
		spawn(Genome.mutate(Genome.mutate(p.dna, 3.0, rng), 3.0, rng), p.pos + Vector2(rng.randfn(0, 20), rng.randfn(0, 20)), 60.0, p.gen + 1)


func pick(pos: Vector2, max_dist: float) -> Creature:
	var best := max_dist * max_dist
	var found: Creature = null
	for c in creatures:
		var d := c.pos.distance_squared_to(pos)
		if d < best:
			best = d
			found = c
	return found


func too_wet(g: Dictionary, wet: bool) -> bool:
	return g["aqua"] < 0.35 if wet else g["aqua"] > 0.65


func stress(g: Dictionary, wet: bool) -> float:
	if wet:
		return 1.2 if g["aqua"] < 0.35 else (0.03 if g["aqua"] < 0.65 else 0.0)
	return 1.2 if g["aqua"] > 0.65 else (0.03 if g["aqua"] > 0.35 else 0.0)


func can_eat(g: Dictionary, f: Food) -> bool:
	return g["aqua"] > 0.35 if f.aq else g["aqua"] < 0.65


func grid_index(p: Vector2) -> int:
	return clampi(int(p.y / FC), 0, FH - 1) * FW + clampi(int(p.x / FC), 0, FW - 1)


# ---------------------------------------------------------------- simulation

func step() -> void:
	tick += 1
	if tick % 500 == 0:
		charge_tick.emit()
	if dynamic:
		_update_planet()
	_advance_meteors()
	_grow_food()
	var want_p := roundi(pred * 8.0)
	while preds.size() < want_p:
		var q := Predator.new()
		q.aq = rng.randf() < 0.4
		q.pos = rand_point(q.aq)
		preds.append(q)
	while preds.size() > want_p:
		preds.pop_back()
	var rate := mutation_rate()
	if mut_boost > 0:
		mut_boost -= 1
	for b in grid:
		b.clear()
	for f in foods:
		grid[grid_index(f.pos)].append(f)
	var born: Array[Creature] = []
	for c in creatures:
		if not c.dead: # eaten by a carnivore earlier this tick
			_step_creature(c, rate, born)
	creatures.append_array(born)
	for q in preds:
		_step_predator(q)
	foods = foods.filter(func(f: Food): return not f.dead)
	n_land = 0
	n_sea = 0
	for f in foods:
		if f.aq:
			n_sea += 1
		else:
			n_land += 1
	creatures = creatures.filter(func(c: Creature): return not c.dead)
	if selected != null and not creatures.has(selected):
		selected = null
	for peer in players.keys():
		var old: Creature = players[peer]
		if old.dead:
			var heir := _heir_of(old.owner, old.pos)
			if heir == null:
				players.erase(peer)
			else:
				heir.driver = peer
				players[peer] = heir
			player_died.emit(peer, old, heir)
	if tick % 120 == 0 and (absf(temp - _painted_temp) > 0.01 or craters.size() + _painted_craters > 0):
		_reshape_coasts()
	if tick % 25 == 0:
		_sample()
	if tick % 60 == 0:
		_count_species()
	if running and creatures.is_empty():
		running = false
		species = 0
		extinct.emit()


# ---------------------------------------------------------------- planet dynamics

func _update_planet() -> void:
	era_left -= 1
	if era_left <= 0:
		_next_era()
	var target := clampf(climate_base + ERAS[era]["temp"], 0.0, 1.0)
	temp += (target - temp) * 0.0008
	sea_level = SEA + (temp - climate_base) * SEA_SWING
	if rng.randf() < 1.0 / 9000.0:
		meteor_at(Vector2(rng.randf() * WW, rng.randf() * WH))
	if mut_boost == 0 and rng.randf() < 1.0 / 15000.0:
		storm()
		planet_event.emit("A solar storm floods the planet with radiation. Mutation rates soar for a while.")


## Eras drift one or two steps colder or warmer and last one to two lifetimes.
func _next_era() -> void:
	var old := era
	var jump := 1 if rng.randf() < 0.75 else 2
	var dir := 1 if rng.randf() < 0.5 else -1
	if old + dir * jump < 0 or old + dir * jump >= ERAS.size():
		dir = -dir
	set_era(clampi(old + dir * jump, 0, ERAS.size() - 1))


func set_era(i: int) -> void:
	var warmer := i > era
	era = i
	era_left = rng.randi_range(3000, 6000)
	planet_event.emit("%s begins. The climate is %s and the seas are %s." % [
		ERAS[era]["name"], "warming" if warmer else "cooling", "rising" if warmer else "falling"])


func _advance_meteors() -> void:
	for i in range(incoming.size() - 1, -1, -1):
		incoming[i][1] -= 1
		if incoming[i][1] <= 0:
			var p: Vector2 = incoming[i][0]
			incoming.remove_at(i)
			_impact(p)
	for i in range(craters.size() - 1, -1, -1):
		craters[i][2] -= 1.0 / CRATER_LIFE
		if craters[i][2] <= 0.0:
			craters.remove_at(i)


## The climate or the ground changed: recolour the terrain, re-measure the land and clear food
## the sea has swallowed or left high and dry.
func _reshape_coasts() -> void:
	_painted_temp = temp
	_painted_craters = craters.size()
	_measure_land()
	foods = foods.filter(func(f: Food): return is_wet(f.pos) == f.aq)
	paint_terrain()


func _grow_food() -> void:
	var cap := 300.0 + food * 1100.0
	for _n in 4:
		var p := Vector2(rng.randf() * WW, rng.randf() * WH)
		var k := cell_of(p)
		var wet := elev[k] < sea_level
		# frozen ground grows little
		var fert := 0.5 if wet else (0.2 + moist[k] * 0.9) * clampf((base_t[k] + temp - 0.6) * 4.0, 0.05, 1.0)
		fert *= planet.fertility
		var limit := cap * ((1.0 - land_frac) if wet else land_frac)
		if (n_sea if wet else n_land) >= limit:
			continue
		if rng.randf() < fert:
			var f := Food.new()
			f.pos = p
			f.aq = wet
			foods.append(f)
			if wet:
				n_sea += 1
			else:
				n_land += 1


func mutation_rate() -> float:
	return mut * planet.radiation * (4.0 if mut_boost > 0 else 1.0)


func breed_energy(c: Creature) -> float:
	return 65.0 + c.r * 2.0


## A player lays an offspring on demand. It inherits `germline` (the gene lab DNA, which
## starts as the player's own) with fresh mutations, so lab edits show up a generation later.
func player_reproduce(peer: int, germline: String) -> Creature:
	var c: Creature = players.get(peer)
	if c == null or c.e <= breed_energy(c):
		return null
	var kid := _offspring(c, germline, mutation_rate())
	creatures.append(kid)
	return kid


func lineage_count(owner: int) -> int:
	var n := 0
	for c in creatures:
		if c.owner == owner and owner != 0 and not c.dead:
			n += 1
	return n


## A player's successor: the living member of lineage `owner` nearest to `near` that nobody
## is playing, or null when the line has ended.
func _heir_of(owner: int, near: Vector2) -> Creature:
	if owner == 0:
		return null
	var best := INF
	var heir: Creature = null
	for c in creatures:
		if c.owner == owner and not c.dead and c.driver == 0:
			var d := c.pos.distance_squared_to(near)
			if d < best:
				best = d
				heir = c
	return heir


func _offspring(c: Creature, dna: String, rate: float) -> Creature:
	c.e /= 2.0
	var kid := Creature.new()
	kid.dna = Genome.mutate(dna, rate, rng)
	kid.g = Genome.decode(kid.dna)
	kid.r = Genome.radius(kid.g)
	kid.pos = c.pos + Vector2(rng.randfn(0, 6), rng.randfn(0, 6))
	kid.e = c.e
	kid.gen = c.gen + 1
	kid.owner = c.owner
	kid.id = next_id
	next_id += 1
	return kid


## Nearest creature the player could bite right now (carnivores only).
func _touching_prey(c: Creature) -> Creature:
	var best := INF
	var found: Creature = null
	for o in creatures:
		if o == c or o.dead or o.r * 1.25 > c.r:
			continue
		var d := o.pos.distance_squared_to(c.pos)
		var rr := c.r + o.r
		if d < rr * rr and d < best:
			best = d
			found = o
	return found


func _step_creature(c: Creature, rate: float, born: Array[Creature]) -> void:
	var g := c.g
	var r := c.r
	var limbs: int = g["limbs"].size()
	var vmax: float = (0.6 + g["speed"] * 1.8 + limbs * 0.07) * (0.8 + g["metab"] * 0.4)
	var is_player := c.driver != 0
	var dir := Vector2.ZERO
	var prey: Creature = null
	if is_player:
		dir = (inputs.get(c.driver, Vector2.ZERO) as Vector2).limit_length(1.0)
		if g["diet"] > 0.5:
			prey = _touching_prey(c)
	else:
		var sense: float = 30.0 + g["sense"] * 110.0
		var target := Vector2.ZERO
		var has_target := false
		var best := 1e9
		var flee := Vector2.ZERO
		var fleeing := false
		for p in preds:
			var d := p.pos.distance_squared_to(c.pos)
			var s := sense * 0.85
			if d < s * s and d < best:
				best = d
				flee = c.pos - p.pos
				fleeing = true
		if c.block > 0:
			c.block -= 1
		var stranded := too_wet(g, is_wet(c.pos))
		if fleeing:
			target = c.pos + flee
			has_target = true
		elif stranded and _escape_dir(c, g, sense) != Vector2.ZERO:
			target = c.pos + _escape_dir(c, g, sense) * sense
			has_target = true
		elif c.block == 0:
			best = sense * sense
			var cx0 := clampi(int((c.pos.x - sense) / FC), 0, FW - 1)
			var cx1 := clampi(int((c.pos.x + sense) / FC), 0, FW - 1)
			var cy0 := clampi(int((c.pos.y - sense) / FC), 0, FH - 1)
			var cy1 := clampi(int((c.pos.y + sense) / FC), 0, FH - 1)
			for gy in range(cy0, cy1 + 1):
				for gx in range(cx0, cx1 + 1):
					for f: Food in grid[gy * FW + gx]:
						if f.dead or not can_eat(g, f):
							continue
						var d := f.pos.distance_squared_to(c.pos)
						if d < best:
							best = d
							target = f.pos
							has_target = true
			if g["diet"] > 0.5:
				for o in creatures:
					if o == c or o.dead or o.r * 1.25 > r:
						continue
					var d := o.pos.distance_squared_to(c.pos)
					if d < best:
						best = d
						target = o.pos
						has_target = true
						prey = o
		if has_target:
			dir = (target - c.pos).normalized()
		else:
			c.wa += rng.randfn(0.0, 0.15)
			dir = Vector2.from_angle(c.wa) * 0.5
	c.vel += (dir * vmax - c.vel) * 0.12
	var nxt := c.pos + c.vel * 8.0
	var out := nxt.x < 0 or nxt.y < 0 or nxt.x > WW or nxt.y > WH
	var lethal_next := false
	if not out:
		lethal_next = too_wet(g, is_wet(nxt)) and not too_wet(g, is_wet(c.pos))
	if is_player:
		var why := ""
		if out:
			why = "The edge of the world."
		elif lethal_next:
			why = "Your body can't survive in water." if g["aqua"] < 0.35 else "Your body can't survive on land."
		blocked[c.driver] = why
	if out or lethal_next:
		if is_player:
			c.vel = Vector2.ZERO
		else:
			c.vel *= -0.5
			c.wa += PI * (0.5 + rng.randf() * 0.5)
			c.block = 25
	else:
		c.pos = Vector2(clampf(c.pos.x + c.vel.x, 0, WW), clampf(c.pos.y + c.vel.y, 0, WH))
	var wet := is_wet(c.pos)
	for f: Food in grid[grid_index(c.pos)]:
		if f.dead or not can_eat(g, f):
			continue
		var rr := r + 3.0
		if f.pos.distance_squared_to(c.pos) < rr * rr:
			c.e += 60.0 * (1.0 - g["diet"] * 0.75)
			f.dead = true
			break
	if g["diet"] > 0.5 and prey != null and not prey.dead:
		var rr := r + prey.r
		if prey.pos.distance_squared_to(c.pos) < rr * rr and rng.randf() < 0.8 - prey.g["spikes"] * 0.6:
			prey.dead = true
			prey.cause = "were eaten by a carnivore"
			c.e += (26.0 + prey.r * 4.0) * (0.3 + g["diet"])
	var t := temp_at(c.pos)
	c.e -= 0.5 * (0.025 + (r * r * 0.0009 + vmax * vmax * 0.007) * planet.gravity) * (0.6 + g["metab"] * 0.8) \
		+ absf(g["temp"] - t) * 0.07 + limbs * 0.002 + g["len"] * 0.00003 + stress(g, wet)
	c.age += 1
	if c.e <= 0.0:
		c.dead = true
		c.cause = "ran out of energy"
	elif c.age > LIFESPAN:
		c.dead = true
		c.cause = "died of old age"
	if not is_player and not c.dead and c.e > breed_energy(c) and creatures.size() + born.size() < MAX_POP:
		born.append(_offspring(c, c.dna, rate))


## A heading toward habitable ground within reach, for a creature stranded by the sea.
func _escape_dir(c: Creature, g: Dictionary, reach: float) -> Vector2:
	for i in 8:
		var d := Vector2.from_angle(c.wa + i * TAU / 8.0)
		for s in [0.5, 1.0]:
			if not too_wet(g, is_wet(c.pos + d * reach * s)):
				return d
	return Vector2.ZERO


func _step_predator(p: Predator) -> void:
	if p.stun > 0:
		p.stun -= 1
		return
	var tgt: Creature = null
	var best := 1e9
	for c in creatures:
		if c.dead:
			continue
		var rg: float = 150.0 * (1.0 - c.g["camo"] * 0.7)
		var d := c.pos.distance_squared_to(p.pos)
		if d < rg * rg and d < best and ((c.g["aqua"] > 0.35) if p.aq else (c.g["aqua"] < 0.65)):
			best = d
			tgt = c
	var dir := Vector2.ZERO
	if tgt != null:
		dir = (tgt.pos - p.pos).normalized()
		if p.pos.distance_to(tgt.pos) < tgt.r + 9.0:
			if rng.randf() < 0.85 - tgt.g["spikes"] * 0.65:
				tgt.dead = true
				tgt.cause = "were caught by a predator"
			elif tgt.g["spikes"] > 0.3:
				p.stun = 70
	else:
		p.wa += rng.randfn(0.0, 0.1)
		dir = Vector2.from_angle(p.wa) * 0.5
	p.vel += (dir * 1.7 - p.vel) * 0.1
	var nxt := p.pos + p.vel * 8.0
	# Only refuse to leave its own biome, so one stranded by the sea can walk back out.
	if nxt.x < 0 or nxt.y < 0 or nxt.x > WW or nxt.y > WH or (is_wet(nxt) != p.aq and is_wet(p.pos) == p.aq):
		p.vel *= -0.5
		p.wa += PI * (0.5 + rng.randf() * 0.5)
	else:
		p.pos += p.vel


func _count_species() -> void:
	var reps: Array = []
	var counts: Array = []
	for c in creatures:
		var g := c.g
		var h: float = deg_to_rad(g["hue"]) * 2.0
		var v := [cos(h) * 0.5, sin(h) * 0.5, g["size"], g["diet"], g["spikes"] * 0.6, g["limbs"].size() / 12.0, g["aqua"]]
		var hit := -1
		for i in reps.size():
			var d := 0.0
			for k in 7:
				var t: float = v[k] - reps[i][k]
				d += t * t
			if d < 0.12:
				hit = i
				break
		if hit < 0:
			reps.append(v)
			counts.append(1)
		else:
			counts[hit] += 1
	species = 0
	for n in counts:
		if n >= 3:
			species += 1


func _sample() -> void:
	if creatures.is_empty():
		return
	var m := {"t": tick}
	for k in Genome.KEYS:
		var s := 0.0
		for c in creatures:
			s += c.g[k]
		m[k] = s / creatures.size()
	history.append(m)
	if history.size() > 400:
		history.pop_front()


func max_generation() -> int:
	var m := 0
	for c in creatures:
		m = maxi(m, c.gen)
	return m


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(terrain_tex, Rect2(0, 0, WW, WH), false)
	for k in craters:
		draw_circle(k[0], k[1], Color(1, 0.36, 0.45, k[2] * 0.35))
	var view := _view_rect()
	for f in foods:
		if view.has_point(f.pos):
			draw_rect(Rect2(f.pos - Vector2(1.5, 1.5), Vector2(3, 3)), Color("9be8ff") if f.aq else Color("a6f5b8"))
	for p in preds:
		if view.has_point(p.pos):
			var col := Color("7a3a44") if p.stun > 0 else Color("ff5d73")
			var a := p.vel.angle()
			draw_colored_polygon(PackedVector2Array([
				p.pos + Vector2.from_angle(a) * 11.0,
				p.pos + Vector2.from_angle(a + 2.5) * 9.0,
				p.pos + Vector2.from_angle(a - 2.5) * 9.0]), col)
	for c in creatures:
		if not view.has_point(c.pos):
			continue
		var g := c.g
		var col := Color.from_hsv(g["hue"] / 360.0, 0.7, 0.9 - g["diet"] * 0.2, 1.0 - g["camo"] * 0.55)
		for l: Vector2 in g["limbs"]:
			draw_line(c.pos, c.pos + Vector2.from_angle(l.x) * (c.r + l.y * c.r * 1.4), col, 1.5)
		var sp := roundi(g["spikes"] * 10.0)
		for i in sp:
			var a := float(i) / sp * TAU
			draw_line(c.pos + Vector2.from_angle(a) * c.r, c.pos + Vector2.from_angle(a) * (c.r + 4.0), col, 1.5)
		draw_circle(c.pos, c.r, col)
		if g["aqua"] > 0.5:
			draw_arc(c.pos, c.r + 1.5, 0.0, TAU, 20, Color(0.6, 0.9, 1.0, 0.9), 1.5)
		if g["diet"] > 0.5:
			draw_circle(c.pos, c.r * 0.35, Color(0.03, 0.06, 0.06, 0.8))
	if selected != null:
		draw_arc(selected.pos, selected.r + 9.0, 0.0, TAU, 28, Color.WHITE, 1.5)


func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(0, 0, WW, WH)
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size).grow(30.0)
