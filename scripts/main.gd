extends Node2D
## Camera, input and HUD. Everything is built in code so the scene file stays trivial.

const MAX_CHARGES := 12

var world: World
var cam: Camera2D
var lab_dna := ""
var lab_orig := ""
var cursor := 0
var charges := MAX_CHARGES
var released := false
var drop_mode := false
var speed := 1
var status := "Move with the arrow keys. A/T/G/C replace a base, Shift+key inserts after it, Delete cuts it."

var _drag_start := Vector2.ZERO
var _dragging := false
var _pressed := false
var _frame := 0

var stats_label: Label
var lab_text: RichTextLabel
var info_label: Label
var level_labels := {}


func _ready() -> void:
	world = World.new()
	add_child(world)
	cam = Camera2D.new()
	add_child(cam)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(World.WW)
	cam.limit_bottom = int(World.WH)
	cam.position = Vector2(World.WW, World.WH) / 2.0
	var vp := get_viewport_rect().size
	var z := maxf(vp.x / World.WW, vp.y / World.WH)
	cam.zoom = Vector2(z, z)
	lab_dna = Genome.founder(world.rng)
	lab_orig = lab_dna
	world.extinct.connect(_on_extinct)
	world.charge_tick.connect(func(): charges = mini(MAX_CHARGES, charges + 1))
	_build_hud()
	_refresh()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	stats_label = Label.new()
	stats_label.position = Vector2(14, 10)
	layer.add_child(stats_label)

	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -270
	right.offset_right = -10
	right.offset_top = 10
	layer.add_child(right)
	var box := VBoxContainer.new()
	right.add_child(box)
	var title := Label.new()
	title.text = "YOUR LEVERS"
	box.add_child(title)
	_slider(box, "temp", "Climate", 0.5, 0.0, 1.0)
	_slider(box, "food", "Food supply", 0.6, 0.05, 1.0)
	_slider(box, "pred", "Predators", 0.3, 0.0, 1.0)
	_slider(box, "mut", "Mutation rate", 0.35, 0.05, 1.0)
	_button(box, "Meteor strike", func(): world.meteor())
	_button(box, "Mutagen storm", func(): world.storm())
	_button(box, "Wild seed", func(): world.wild_seed())
	_button(box, "New world", func(): world.gen_world(); world.foods.clear())
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(240, 0)
	box.add_child(info_label)

	var lab := PanelContainer.new()
	lab.anchor_top = 1.0
	lab.anchor_bottom = 1.0
	lab.anchor_right = 1.0
	lab.offset_left = 10
	lab.offset_right = -10
	lab.offset_top = -250
	lab.offset_bottom = -10
	layer.add_child(lab)
	lab_text = RichTextLabel.new()
	lab_text.bbcode_enabled = true
	lab_text.scroll_active = false
	lab_text.fit_content = false
	lab_text.custom_minimum_size = Vector2(0, 230)
	lab.add_child(lab_text)


func _slider(parent: Control, key: String, title: String, v: float, lo: float, hi: float) -> void:
	var l := Label.new()
	parent.add_child(l)
	level_labels[key] = [l, title]
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = v
	s.custom_minimum_size = Vector2(240, 18)
	s.value_changed.connect(func(x: float): _set_level(key, x))
	parent.add_child(s)
	_set_level(key, v)


func _set_level(key: String, v: float) -> void:
	world.set(key, v)
	var entry: Array = level_labels[key]
	entry[0].text = "%s  %d%%" % [entry[1], roundi(v * 100.0)]
	if key == "temp":
		world.paint_terrain()


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_extinct() -> void:
	released = false
	status = "Extinction. Edit the DNA and press Enter to try again."


# ---------------------------------------------------------------- lab

func _edit(kind: String, b := "") -> void:
	if charges < 1:
		status = "No Cas9 charges left. They refill slowly."
		return
	var p := cursor
	var d := lab_dna
	match kind:
		"rep":
			d = d.substr(0, p) + b + d.substr(p + 1)
		"ins":
			d = d.substr(0, p + 1) + b + d.substr(p + 1)
			cursor = p + 1
		"del":
			if d.length() <= 30:
				status = "Genome too short to cut."
				return
			d = d.substr(0, p) + d.substr(p + 1)
			cursor = mini(p, d.length() - 1)
	charges -= 1
	status = "Edit made."
	if world.rng.randf() < 0.08:
		var q := world.rng.randi() % d.length()
		var nb := Genome.random_base(world.rng)
		while nb == d[q]:
			nb = Genome.random_base(world.rng)
		d = d.substr(0, q) + nb + d.substr(q + 1)
		status = "Off-target cut at base %d." % (q + 1)
	lab_dna = d


func _lab_bbcode() -> String:
	var colors := {"A": "6df2c2", "T": "ff8f5a", "G": "6ab7ff", "C": "f2d36d"}
	var lo := maxi(0, cursor - 70)
	var hi := mini(lab_dna.length(), cursor + 70)
	var s := "[b]GENE LAB[/b]  base %d of %d  |  %d / %d Cas9 charges\n" % [cursor + 1, lab_dna.length(), charges, MAX_CHARGES]
	for i in range(lo, hi):
		var ch := lab_dna[i]
		var t := "[color=#%s]%s[/color]" % [colors[ch], ch]
		if i == cursor:
			t = "[bgcolor=#ffffff][color=#000000]%s[/color][/bgcolor]" % ch
		s += t
	s += "\n"
	var g := Genome.decode(lab_dna)
	for k in Genome.KEYS:
		var n := roundi(g[k] * 20.0)
		s += "%-15s %s%s\n" % [Genome.LABELS[k], "█".repeat(n), "░".repeat(20 - n)]
	var hab := "lives in water" if g["aqua"] > 0.65 else ("amphibious" if g["aqua"] > 0.35 else "lives on land")
	s += "%d genes, %d limbs, %s\n[color=#7fa39d]%s[/color]" % [g["genes"], g["limbs"].size(), hab, status]
	return s


func _refresh() -> void:
	lab_text.text = _lab_bbcode()
	stats_label.text = "Population %d   Species %d   Generation %d   Age %.1f kyr   Speed %dx%s" % [
		world.creatures.size(), world.species, world.max_generation(), world.tick / 100.0, speed,
		"   [DROP MODE: click map]" if drop_mode else ""]
	var s := ""
	if world.selected != null:
		var c := world.selected
		s = "Selected creature\nGeneration %d, %d genes, %d bases, energy %d\n" % [c.gen, c.g["genes"], c.dna.length(), int(c.e)]
		for k in Genome.KEYS:
			s += "%s %d%%\n" % [Genome.LABELS[k], roundi(c.g[k] * 100.0)]
		s += "L loads it into the lab, W writes the lab DNA back."
	else:
		s = "Click a creature to inspect it.\nEnter releases your DNA (first time) or toggles drop mode.\nDrag to pan, wheel to zoom, 1/2/3 speed, P pause."
	info_label.text = s


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_drag_start = mb.position
			elif _pressed:
				_pressed = false
				if not _dragging:
					_click()
	elif event is InputEventMouseMotion and _pressed:
		var mm := event as InputEventMouseMotion
		if _dragging or mm.position.distance_to(_drag_start) > 5.0:
			_dragging = true
			cam.position -= mm.relative / cam.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _zoom(f: float) -> void:
	var vp := get_viewport_rect().size
	var mz := maxf(vp.x / World.WW, vp.y / World.WH)
	var z := clampf(cam.zoom.x * f, mz, 5.0)
	cam.zoom = Vector2(z, z)


func _click() -> void:
	var pos := get_global_mouse_position()
	if drop_mode and released:
		if charges < 2:
			status = "Not enough charges to drop copies."
			return
		charges -= 2
		world.drop(lab_dna, pos)
		return
	world.selected = world.pick(pos, 34.0 / cam.zoom.x)


func _key(e: InputEvent) -> void:
	var k := e as InputEventKey
	match k.keycode:
		KEY_LEFT:
			cursor = maxi(0, cursor - (10 if k.shift_pressed else 1))
		KEY_RIGHT:
			cursor = mini(lab_dna.length() - 1, cursor + (10 if k.shift_pressed else 1))
		KEY_DELETE, KEY_BACKSPACE:
			_edit("del")
		KEY_A, KEY_T, KEY_G, KEY_C:
			var b := OS.get_keycode_string(k.keycode)
			_edit("ins" if k.shift_pressed else "rep", b)
		KEY_ENTER, KEY_KP_ENTER:
			if not released:
				released = true
				world.release(lab_dna)
				lab_orig = lab_dna
				status = "Released. Enter again toggles drop mode (2 charges per drop)."
			else:
				drop_mode = not drop_mode
		KEY_ESCAPE:
			drop_mode = false
		KEY_L:
			if world.selected != null:
				lab_dna = world.selected.dna
				cursor = 0
				status = "Loaded the selected creature's DNA."
		KEY_W:
			if world.selected != null:
				world.selected.dna = lab_dna
				world.selected.g = Genome.decode(lab_dna)
				world.selected.r = Genome.radius(world.selected.g)
				status = "Wrote the lab DNA into the selected creature."
		KEY_1:
			speed = 1
		KEY_2:
			speed = 2
		KEY_3:
			speed = 4
		KEY_P:
			speed = 0
	cursor = clampi(cursor, 0, maxi(0, lab_dna.length() - 1))


func _process(_delta: float) -> void:
	if world.running:
		for _i in speed:
			world.step()
	_frame += 1
	if _frame % 6 == 0:
		_refresh()
