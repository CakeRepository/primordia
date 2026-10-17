extends Node3D
## The 3D game. You play one creature on a planet that keeps evolving around you. Your body
## is built from your DNA; you eat, dodge predators and lay offspring, and when you die you
## carry on as your nearest descendant. The gene lab (Tab) edits your germline, the DNA your
## offspring inherit, so edits show up a generation later alongside natural mutations.

const MAX_CHARGES := 12
const HELP := "WASD move   Right-drag look   Wheel zoom   R lay offspring   Tab gene lab   1/2/3 speed   P pause"

var world: World
var planet: Planet3D
var model: CreatureModel
var cam: Camera3D

var germline := ""
var charges := MAX_CHARGES
var cursor := 0
var lab_open := false
var speed := 1
var status := "Edits change your germline: the DNA your offspring inherit."
var game_over := false

var yaw := 0.7
var pitch := 0.45
var zoom := 1.0
var _model_dna := ""
var _focus := Vector3.ZERO # what the camera looks at; stays put after your line ends
var _cam_placed := false
var _messages: Array = [] # [text, seconds left]

var stats_label: Label
var vitals_label: Label
var energy_bar: ProgressBar
var age_bar: ProgressBar
var prompt_label: Label
var log_label: Label
var lab_panel: PanelContainer
var lab_text: RichTextLabel


func _ready() -> void:
	world = World.new()
	world.visible = false # its 2D drawing is for the top-down view only
	add_child(world)
	planet = Planet3D.new()
	add_child(planet)
	planet.setup(world)
	model = CreatureModel.new()
	add_child(model)
	cam = Camera3D.new()
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	world.player_died.connect(_on_player_died)
	world.extinct.connect(_on_extinct)
	world.charge_tick.connect(func(): charges = mini(MAX_CHARGES, charges + 1))
	_build_hud()
	_start(Genome.founder(world.rng))


func _start(dna: String) -> void:
	germline = dna
	cursor = 0
	game_over = false
	_cam_placed = false
	world.populate(dna)
	_say("You hatch on a living planet. Eat, stay alive, and press R to lay offspring.")


func _on_player_died(old: World.Creature, heir: World.Creature) -> void:
	if heir == null:
		game_over = true
		_say("You %s. Your lineage has ended. Press Enter to start a new one." % old.cause)
		return
	germline = heir.dna
	cursor = clampi(cursor, 0, germline.length() - 1)
	_say("You %s. You live on as your descendant, generation %d." % [old.cause, heir.gen])


func _on_extinct() -> void:
	game_over = true
	_say("All life on the planet is gone. Press Enter to seed it again.")


func _say(text: String) -> void:
	_messages.append([text, 7.0])
	if _messages.size() > 4:
		_messages.pop_front()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	world.player_dir = _move_input() if world.player != null and not lab_open else Vector2.ZERO
	if world.running:
		for _i in speed:
			world.step()
	var p := world.player
	planet.update_life(p)
	model.visible = p != null
	if p != null:
		if p.dna != _model_dna:
			_model_dna = p.dna
			model.build(p.g, p.r * Planet3D.S)
		model.position = planet.rest_point(p.pos, model.stand)
		model.animate(p.vel, delta * speed)
		_focus = model.position
	_update_camera(delta)
	_update_hud(delta)


## WASD (or arrows) relative to the camera, as a heading in sim space.
func _move_input() -> Vector2:
	var f := float(_held(KEY_W, KEY_UP)) - float(_held(KEY_S, KEY_DOWN))
	var s := float(_held(KEY_D, KEY_RIGHT)) - float(_held(KEY_A, KEY_LEFT))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return (forward * f + right * s).limit_length(1.0)


func _held(a: Key, b: Key) -> bool:
	return Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b)


func _update_camera(delta: float) -> void:
	var reach := model.rad if world.player != null else 1.0
	var target := _focus + Vector3(0.0, reach * 0.6, 0.0)
	var dist := (3.0 + reach * 7.0) * zoom
	var want := target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var ground := maxf(planet.ground_y(Vector2(want.x, want.z) / Planet3D.S), 0.0)
	want.y = maxf(want.y, ground + 0.6) # never dip under the terrain or the sea
	if _cam_placed:
		cam.position = cam.position.lerp(want, 1.0 - exp(-delta * 10.0))
	else:
		cam.position = want
		_cam_placed = true
	if cam.position.distance_squared_to(target) > 0.0001:
		cam.look_at(target, Vector3.UP)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, 0.05, 1.35)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom / 1.12, 0.35, 4.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.12, 0.35, 4.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	if k.keycode == KEY_TAB or (k.keycode == KEY_ESCAPE and lab_open):
		lab_open = not lab_open
		lab_panel.visible = lab_open
		return
	if lab_open and _lab_key(k):
		return
	match k.keycode:
		KEY_R:
			_reproduce()
		KEY_ENTER, KEY_KP_ENTER:
			if game_over:
				_start(germline)
		KEY_1:
			speed = 1
		KEY_2:
			speed = 2
		KEY_3:
			speed = 4
		KEY_P:
			speed = 0 if speed > 0 else 1


## Gene lab keys while it is open. Returns false for keys it does not use.
func _lab_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_LEFT:
			cursor -= 10 if k.shift_pressed else 1
		KEY_RIGHT:
			cursor += 10 if k.shift_pressed else 1
		KEY_DELETE, KEY_BACKSPACE:
			_edit("del")
		KEY_A, KEY_T, KEY_G, KEY_C:
			_edit("ins" if k.shift_pressed else "rep", OS.get_keycode_string(k.keycode))
		_:
			return false
	cursor = clampi(cursor, 0, maxi(0, germline.length() - 1))
	return true


func _edit(kind: String, b := "") -> void:
	if charges < 1:
		status = "No Cas9 charges left. They refill slowly."
		return
	var r := Genome.edit(germline, kind, cursor, b, world.rng)
	status = r["msg"]
	if r["done"]:
		charges -= 1
		germline = r["dna"]
		cursor = r["cursor"]


func _reproduce() -> void:
	var p := world.player
	if p == null:
		return
	var kid := world.player_reproduce(germline)
	if kid == null:
		_say("Not enough energy to lay offspring yet (%d of %d). Eat more." % [int(p.e), int(world.breed_energy(p)) + 1])
	else:
		_say("You laid an offspring. It carries your germline, generation %d." % kid.gen)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new() # outlined text stays readable over sky, snow and water
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme.set_constant("outline_size", "Label", 5)
	root.theme = theme
	layer.add_child(root)

	stats_label = _label(root, Vector2(14, 10))
	vitals_label = _label(root, Vector2(14, 36))
	energy_bar = _bar(root, Vector2(14, 64), "Energy", Color("6df2a0"))
	age_bar = _bar(root, Vector2(14, 88), "Age", Color("f2c36d"))

	log_label = Label.new()
	log_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	log_label.offset_top = 120
	root.add_child(log_label)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_label.offset_bottom = -40
	prompt_label.add_theme_font_size_override("font_size", 20)
	root.add_child(prompt_label)

	var help := Label.new()
	help.text = HELP
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 14
	help.offset_bottom = -10
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	root.add_child(help)

	lab_panel = PanelContainer.new()
	lab_panel.anchor_left = 0.5
	lab_panel.anchor_right = 0.5
	lab_panel.anchor_top = 1.0
	lab_panel.anchor_bottom = 1.0
	lab_panel.offset_left = -500
	lab_panel.offset_right = 500
	lab_panel.offset_top = -320
	lab_panel.offset_bottom = -70
	lab_panel.visible = false
	root.add_child(lab_panel)
	lab_text = RichTextLabel.new()
	lab_text.bbcode_enabled = true
	lab_text.scroll_active = false
	lab_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab_panel.add_child(lab_text)

	# The HUD must not swallow mouse drags meant for the camera.
	for c in root.find_children("*", "Control", true, false):
		if c != lab_panel and c != lab_text:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(parent: Control, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, title: String, fill: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.position = pos
	parent.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	bar.add_theme_stylebox_override("fill", sb)
	row.add_child(bar)
	return bar


func _update_hud(delta: float) -> void:
	stats_label.text = "Population %d   Species %d   World age %.1f kyr   %s" % [
		world.creatures.size(), world.species, world.tick / 100.0, "Paused" if speed == 0 else "Speed %dx" % speed]
	var p := world.player
	(energy_bar.get_parent() as Control).visible = p != null
	(age_bar.get_parent() as Control).visible = p != null
	if p != null:
		var need := world.breed_energy(p)
		vitals_label.text = "You: generation %d   %d of your line alive" % [p.gen, world.lineage_count()]
		energy_bar.max_value = need
		energy_bar.value = p.e
		age_bar.max_value = World.LIFESPAN
		age_bar.value = p.age
		if world.player_blocked != "":
			prompt_label.text = world.player_blocked
		elif p.e > need:
			prompt_label.text = "R  lay an offspring"
		else:
			prompt_label.text = ""
	else:
		vitals_label.text = "Your lineage has ended." if game_over else ""
		prompt_label.text = "Enter  start a new lineage" if game_over else ""
	for m in _messages:
		m[1] -= delta
	_messages = _messages.filter(func(m): return m[1] > 0.0)
	log_label.text = "\n".join(_messages.map(func(m): return m[0]))
	if lab_open:
		var header := "[b]GENE LAB[/b]  your germline, the DNA your offspring inherit  |  base %d of %d  |  %d / %d Cas9 charges" % [
			cursor + 1, germline.length(), charges, MAX_CHARGES]
		lab_text.text = GeneLab.render(germline, cursor, maxi(20, int(lab_text.size.x / 11.0)), header, status)
