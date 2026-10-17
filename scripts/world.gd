class_name World
extends Node2D
## The living planet: terrain, food, predators and creatures. Port of the web prototype.

const WW := 2400.0
const WH := 1500.0
const GW := 120
const GH := 75
const CS := 20.0
const SEA := 0.46
const FC := 60.0
const FW := 40
const FH := 25
const MAX_POP := 600

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
var elev := PackedFloat32Array()
var moist := PackedFloat32Array()
var base_t := PackedFloat32Array()
var terrain_tex: ImageTexture
var land_frac := 0.5

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

signal extinct
signal charge_tick


func _ready() -> void:
	rng.randomize()
	grid.resize(FW * FH)
	for i in grid.size():
		grid[i] = []
	gen_world()


# ---------------------------------------------------------------- terrain

func gen_world() -> void:
	var n0 := FastNoiseLite.new()
	n0.seed = rng.randi()
	n0.frequency = 0.012
	n0.fractal_octaves = 4
	var n1 := FastNoiseLite.new()
	n1.seed = rng.randi()
	n1.frequency = 0.02
	n1.fractal_octaves = 3
	elev.resize(GW * GH)
	moist.resize(GW * GH)
	base_t.resize(GW * GH)
	var land := 0
	for j in GH:
		for i in GW:
			var k := j * GW + i
			var u := float(i) / GW
			var v := float(j) / GH
			var e := (n0.get_noise_2d(i, j) + 1.0) * 0.5
			e = (e - 0.5) * 1.5 + 0.5
			var edge := pow(maxf(absf(u - 0.5), absf(v - 0.5)) * 2.0, 3.0)
			elev[k] = e - edge * 0.28
			moist[k] = clampf((n1.get_noise_2d(i, j) + 1.0) * 0.5, 0.0, 1.0)
			base_t[k] = clampf(0.12 + 0.78 * (1.0 - absf(v - 0.5) * 2.0) - maxf(0.0, elev[k] - SEA) * 0.5, 0.0, 1.0)
			if elev[k] >= SEA:
				land += 1
	land_frac = clampf(float(land) / (GW * GH), 0.15, 0.85)
	paint_terrain()


func paint_terrain() -> void:
	var img := Image.create(GW, GH, false, Image.FORMAT_RGB8)
	var shift := temp - 0.5
	for k in GW * GH:
		var e := elev[k]
		var m := moist[k]
		var tl := clampf(base_t[k] + shift, 0.0, 1.0)
		var c: Color
		if e < SEA:
			var d := clampf((SEA - e) / 0.25, 0.0, 1.0)
			c = Color8(int(22 - d * 14), int(82 - d * 44), int(108 - d * 38))
			if tl < 0.12:
				c = c.lerp(Color8(200, 215, 220), 0.35)
		elif e < SEA + 0.025:
			c = Color8(120, 112, 80)
		elif e > 0.78:
			c = Color8(200, 210, 214) if tl < 0.35 else Color8(95, 100, 104)
		elif tl < 0.22:
			c = Color8(190, 205, 210)
		elif tl < 0.4:
			c = Color8(70, 92, 88)
		elif m > 0.58 and tl > 0.35:
			c = Color8(28, 82, 48)
		elif m < 0.34 and tl > 0.55:
			c = Color8(146, 118, 66)
		else:
			c = Color8(52, 100, 56)
		img.set_pixel(k % GW, k / GW, c)
	if terrain_tex == null:
		terrain_tex = ImageTexture.create_from_image(img)
	else:
		terrain_tex.update(img)


func cell_of(p: Vector2) -> int:
	var cx := clampi(int(p.x / CS), 0, GW - 1)
	var cy := clampi(int(p.y / CS), 0, GH - 1)
	return cy * GW + cx


func is_wet(p: Vector2) -> bool:
	return elev[cell_of(p)] < SEA


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
	creatures.append(c)
	return c


func release(dna: String) -> void:
	creatures.clear()
	foods.clear()
	preds.clear()
	history.clear()
	tick = 0
	selected = null
	for _i in 60:
		spawn(dna, rand_point(false))
	running = true


func drop(dna: String, pos: Vector2) -> void:
	for _i in 8:
		var p := pos + Vector2(rng.randfn(0, 14), rng.randfn(0, 14))
		spawn(dna, Vector2(clampf(p.x, 0, WW), clampf(p.y, 0, WH)), 55.0)


func meteor() -> void:
	var p := Vector2(rng.randf() * WW, rng.randf() * WH)
	var r := 240.0
	craters.append([p, r, 1.0])
	creatures = creatures.filter(func(c: Creature): return c.pos.distance_to(p) > r or rng.randf() < 0.08)
	foods = foods.filter(func(f: Food): return f.pos.distance_to(p) > r)
	if selected != null and not creatures.has(selected):
		selected = null


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
	var cap := 300.0 + food * 1100.0
	for _n in 4:
		var p := Vector2(rng.randf() * WW, rng.randf() * WH)
		var k := cell_of(p)
		var wet := elev[k] < SEA
		var fert := 0.5 if wet else 0.2 + moist[k] * 0.9
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
	var want_p := roundi(pred * 8.0)
	while preds.size() < want_p:
		var q := Predator.new()
		q.aq = rng.randf() < 0.4
		q.pos = rand_point(q.aq)
		preds.append(q)
	while preds.size() > want_p:
		preds.pop_back()
	var rate := mut * (4.0 if mut_boost > 0 else 1.0)
	if mut_boost > 0:
		mut_boost -= 1
	for b in grid:
		b.clear()
	for f in foods:
		grid[grid_index(f.pos)].append(f)
	var born: Array[Creature] = []
	for c in creatures:
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
	if tick % 25 == 0:
		_sample()
	if tick % 60 == 0:
		_count_species()
	if running and creatures.is_empty():
		running = false
		extinct.emit()


func _step_creature(c: Creature, rate: float, born: Array[Creature]) -> void:
	var g := c.g
	var r := c.r
	var sense: float = 30.0 + g["sense"] * 110.0
	var limbs: int = g["limbs"].size()
	var vmax: float = (0.6 + g["speed"] * 1.8 + limbs * 0.07) * (0.8 + g["metab"] * 0.4)
	var target := Vector2.ZERO
	var has_target := false
	var best := 1e9
	var flee := Vector2.ZERO
	var fleeing := false
	var prey: Creature = null
	for p in preds:
		var d := p.pos.distance_squared_to(c.pos)
		var s := sense * 0.85
		if d < s * s and d < best:
			best = d
			flee = c.pos - p.pos
			fleeing = true
	if c.block > 0:
		c.block -= 1
	if fleeing:
		target = c.pos + flee
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
	var dir := Vector2.ZERO
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
	if out or lethal_next:
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
			c.e += (26.0 + prey.r * 4.0) * (0.3 + g["diet"])
	var t := temp_at(c.pos)
	c.e -= 0.5 * (0.025 + r * r * 0.0009 + vmax * vmax * 0.007) * (0.6 + g["metab"] * 0.8) \
		+ absf(g["temp"] - t) * 0.07 + limbs * 0.002 + g["len"] * 0.00003 + stress(g, wet)
	c.age += 1
	if c.e <= 0.0 or c.age > 3500:
		c.dead = true
	if not c.dead and c.e > 65.0 + r * 2.0 and creatures.size() + born.size() < MAX_POP:
		c.e /= 2.0
		var kid := Creature.new()
		kid.dna = Genome.mutate(c.dna, rate, rng)
		kid.g = Genome.decode(kid.dna)
		kid.r = Genome.radius(kid.g)
		kid.pos = c.pos + Vector2(rng.randfn(0, 6), rng.randfn(0, 6))
		kid.e = c.e
		kid.gen = c.gen + 1
		born.append(kid)


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
			elif tgt.g["spikes"] > 0.3:
				p.stun = 70
	else:
		p.wa += rng.randfn(0.0, 0.1)
		dir = Vector2.from_angle(p.wa) * 0.5
	p.vel += (dir * 1.7 - p.vel) * 0.1
	var nxt := p.pos + p.vel * 8.0
	if nxt.x < 0 or nxt.y < 0 or nxt.x > WW or nxt.y > WH or is_wet(nxt) != p.aq:
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
	for i in range(craters.size() - 1, -1, -1):
		var k = craters[i]
		draw_circle(k[0], k[1], Color(1, 0.36, 0.45, k[2] * 0.35))
		k[2] -= 0.01
		if k[2] <= 0.0:
			craters.remove_at(i)
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
