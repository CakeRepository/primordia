extends Node3D
## The 3D game view. You play one creature on a living alien planet: your body is built from
## your DNA; you eat, dodge predators and lay offspring, and when you die you carry on as your
## nearest descendant. The gene lab (Tab) edits your germline, the DNA your offspring inherit.
## A Session runs the world (in this process for solo, host and dedicated server; elsewhere for
## a client); this node draws it and handles input and the HUD. A dedicated server builds no view.

const HELP := "WASD move   Right-drag look   Wheel zoom   R lay offspring   Tab evolve   1/2/3 speed   P pause   Esc leave"
const MENU_SCENE := "res://scenes/menu.tscn"

var session: Session
var world: World # session.world once it exists
var planet: Planet3D
var model: CreatureModel
var cam: Camera3D

## Overrides for the Launch autoload (tests and tools): mode, seed, port, address, player_name, server_name.
var config := {}
var world_seed := 0 # shortcut for config["seed"]
var dedicated := false

var cursor := 0
var lab_open := false
var lab_bases := false # the gene lab shows raw bases (advanced) instead of evolve options
var yaw := 0.7
var pitch := 0.45
var zoom := 1.0
var _model_dna := ""
var _focus := Vector3.ZERO # what the camera looks at; stays put while you have no body
var _cam_placed := false
var _messages: Array = [] # [text, seconds left]
var _shake := 0.0
var _leaving := false # the "leave this world?" prompt is up
var _lost := "" # why the connection to the server ended
var _tags := {} # peer -> Label3D over other players' creatures
var _status_t := 0.0
var _rng := RandomNumberGenerator.new()
var _options: Array = [] # mutation options shown in the evolve view
var _options_for := "" # the germline those options were made for
var _plan := "" # body plan of the creature you play, for milestone messages
var _auto_origin := false # pick the first origin without asking (headless bots and tests)
var picker: Control
var _picker_title: Label
var _reroll_button: Button
var _choices: Array[String] = []
var _cards: Array = [] # per card: [CreatureModel, Camera3D, title Label, RichTextLabel, PanelContainer]
var _rerolls := 3

var stats_label: Label
var climate_label: Label
var vitals_label: Label
var energy_bar: ProgressBar
var age_bar: ProgressBar
var prompt_label: Label
var log_label: Label
var center_label: Label
var lab_panel: PanelContainer
var lab_text: RichTextLabel


func _ready() -> void:
	if world_seed != 0:
		config["seed"] = world_seed
	var mode: String = _cfg("mode", "solo")
	dedicated = mode == "dedicated"
	if dedicated or DisplayServer.get_name() == "headless":
		Engine.max_fps = 60 # nothing to draw: do not spin the CPU
	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.world_ready.connect(_on_world_ready)
	session.said.connect(_say)
	session.meteor_seen.connect(_on_meteor_seen)
	session.impacted.connect(_on_impact)
	session.died.connect(_on_died)
	_rng.randomize()
	_auto_origin = _cfg("auto_origin", DisplayServer.get_name() == "headless")
	session.origin_needed.connect(_on_origin_needed)
	session.reborn.connect(func():
		_cam_placed = false
		_plan = ""
		_rerolls = 3
		if picker != null:
			picker.visible = false)
	session.lab_changed.connect(func():
		if session.germline != _options_for:
			_refresh_options()
		if session.cursor_hint >= 0:
			cursor = session.cursor_hint
		cursor = clampi(cursor, 0, maxi(0, session.germline.length() - 1)))
	session.disconnected.connect(func(reason):
		_lost = reason
		_say(reason))
	if not dedicated:
		_build_hud()
	var seed: int = _cfg("seed", 0)
	var port: int = _cfg("port", Session.DEFAULT_PORT)
	var who: String = _cfg("player_name", "Player")
	var err := OK
	match mode:
		"dedicated":
			err = session.start_dedicated(seed, port, _cfg("server_name", ""), _cfg("world_name", ""))
			if err == OK:
				var pl := session.world.planet
				print("[server] %s on port %d. Planet %s (seed %d): %s." % [session.server_name, port, pl.name, pl.seed, pl.describe()])
				if session.save_path == "":
					print("[server] This world is not saved. Start with --world NAME to keep it.")
				else:
					print("[server] %s world %s (%s), saved every minute and on exit." % [
						"Resumed" if session.world.tick > 0 else "New", _cfg("world_name", ""), ProjectSettings.globalize_path(session.save_path)])
				print("[server] Players join with: godot --path . -- --join <this machine's address>:%d" % port)
		"host":
			err = session.start_host(seed, who, port)
		"join":
			err = session.start_client(_cfg("address", "127.0.0.1"), port, who)
			if err == OK:
				_say("Connecting to %s:%d..." % [_cfg("address", "127.0.0.1"), port])
		_:
			session.start_solo(seed, who)
	if err != OK:
		var why := "Could not open port %d (%s). Is another server running there?" % [port, error_string(err)] \
			if mode != "join" else "Could not start a connection (%s)." % error_string(err)
		push_error(why)
		_lost = why
		_say(why)
		if dedicated:
			get_tree().quit(1)


func _on_origin_needed() -> void:
	if _auto_origin:
		var options := Traits.origins(_rng, 1)
		if not options.is_empty():
			session.choose_origin(options[0])
	# otherwise _process opens the picker once the planet is on screen


func _refresh_options() -> void:
	_options_for = session.germline
	_options = Traits.mutation_options(session.germline, _rng) if session.germline != "" else []


func _cfg(key: String, default: Variant) -> Variant:
	if config.has(key):
		return config[key]
	var launch := get_node_or_null("/root/Launch")
	return launch.get(key) if launch != null and key in launch else default


func _on_world_ready() -> void:
	world = session.world
	if dedicated:
		return
	planet = Planet3D.new()
	add_child(planet)
	planet.setup(world)
	model = CreatureModel.new()
	add_child(model)
	cam = Camera3D.new()
	cam.far = 900.0
	add_child(cam)
	cam.current = true


func _on_died(cause: String, heir_gen: int) -> void:
	if heir_gen < 0:
		_say("You %s. Your lineage has ended. Press Enter to start a new one." % cause)
	else:
		_say("You %s. You live on as your descendant, generation %d." % [cause, heir_gen])


func _on_meteor_seen(p: Vector2) -> void:
	var me := session.my_creature()
	if me == null:
		_say("A meteor streaks across the sky.")
		return
	var d := p - me.pos
	var metres := d.length() * Planet3D.S
	if metres < World.METEOR_R * Planet3D.S:
		_say("A meteor is coming down right on top of you! Get out of the red zone!")
	else:
		_say("A meteor is falling %d m to the %s." % [int(metres), _compass(d)])


func _on_impact(p: Vector2, killed: int) -> void:
	if planet != null:
		planet.flash(p)
	var me := session.my_creature()
	if me != null and me.pos.distance_to(p) < World.METEOR_R * 4.0:
		_shake = 1.0
	if killed > 0:
		_say("Impact! %d creatures died in the blast." % killed)


## Compass direction of a sim-space offset (north is -y, i.e. -Z in 3D).
static func _compass(d: Vector2) -> String:
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[posmod(roundi(d.angle() / (TAU / 8.0)), 8)]


func _say(text: String) -> void:
	if dedicated:
		print("[server] ", text)
		return
	_messages.append([text, 7.0])
	if _messages.size() > 4:
		_messages.pop_front()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if dedicated:
		_status_t += delta
		if _status_t >= 60.0 and world != null:
			_status_t = 0.0
			print("[server] %s: population %d, %d species, %s, %d player%s" % [world.planet.name,
				world.creatures.size(), world.species, World.ERAS[world.era]["name"], session.names.size(),
				"" if session.names.size() == 1 else "s"])
		return
	if world == null:
		_update_hud(delta)
		return
	var p := session.my_creature()
	if session.needs_origin and not _auto_origin and not picker.visible:
		_open_picker()
	if picker.visible:
		for i in _cards.size(): # sway, but keep the face (eyes, mouth) toward the viewer
			_cards[i][0].rotation.y = PI + sin(Time.get_ticks_msec() * 0.0008 + i) * 0.8
			_cards[i][0].animate(Vector2.ZERO, delta)
	session.send_input(_move_input() if p != null and not lab_open and not _leaving else Vector2.ZERO)
	planet.update_life(p)
	model.visible = p != null
	if p != null:
		if p.dna != _model_dna:
			_model_dna = p.dna
			model.build(p.g, p.r * Planet3D.S, world.planet.body_shape)
		model.position = planet.creature_point(p.pos, model.stand, model.floating)
		var plan := Traits.body_plan(p.g)
		if _plan != "" and plan != _plan:
			_say("Your line has become a %s (%s)." % [plan, Traits.body_plan_text(p.g)])
		_plan = plan
		model.animate(p.vel, delta * session.speed)
		_focus = model.position
	planet.update_planet(delta)
	_update_tags()
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
	var reach := model.rad if session.my_creature() != null else 1.0
	var target := _focus + Vector3(0.0, reach * 0.6, 0.0)
	var dist := (3.0 + reach * 7.0) * zoom
	var want := target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	# Rise until the line of sight clears every hill between the camera and the player
	# (and never dip under the terrain or the sea).
	for i in range(1, 9):
		var f := i / 8.0
		var at := target.lerp(want, f)
		var ground := maxf(planet.ground_y(Vector2(at.x, at.z) / Planet3D.S), planet.water_y()) + 0.6
		if ground > target.y + (want.y - target.y) * f:
			want.y = target.y + (ground - target.y) / f
	if _cam_placed:
		cam.position = cam.position.lerp(want, 1.0 - exp(-delta * 10.0))
	else:
		cam.position = want
		_cam_placed = true
	if cam.position.distance_squared_to(target) > 0.0001:
		cam.look_at(target, Vector3.UP)
	if _shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
		_shake = maxf(0.0, _shake - delta * 1.5)


## Name tags over the creatures other players are playing.
func _update_tags() -> void:
	var live := {}
	for c in world.creatures:
		if c.driver != 0 and c.driver != session.me:
			live[c.driver] = c
	for peer in _tags.keys():
		if not live.has(peer):
			_tags[peer].queue_free()
			_tags.erase(peer)
	for peer in live:
		if not _tags.has(peer):
			var tag := Label3D.new()
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.font_size = 48
			tag.outline_size = 12
			tag.pixel_size = 0.01
			add_child(tag)
			_tags[peer] = tag
		var c: World.Creature = live[peer]
		_tags[peer].text = session.names.get(peer, "?")
		_tags[peer].position = planet.creature_point(c.pos, c.r * Planet3D.S, Genome.floats(c.g)) + Vector3.UP * (c.r * Planet3D.S * 2.0 + 0.8)


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
	if dedicated:
		return
	if _lost != "" or _leaving:
		if k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_leave()
		elif k.keycode == KEY_ESCAPE and _lost == "":
			_leaving = false
		return
	if picker != null and picker.visible:
		match k.keycode:
			KEY_1, KEY_2, KEY_3:
				_pick(k.keycode - KEY_1)
			KEY_R:
				_reroll()
			KEY_ESCAPE:
				_leaving = true
		return
	if k.keycode == KEY_TAB or (k.keycode == KEY_ESCAPE and lab_open):
		lab_open = not lab_open
		lab_panel.visible = lab_open
		if lab_open:
			_refresh_options()
		return
	if lab_open and _lab_key(k):
		return
	match k.keycode:
		KEY_ESCAPE:
			_leaving = true
		KEY_R:
			session.reproduce()
		KEY_1, KEY_2, KEY_3, KEY_P:
			var s: int = {KEY_1: 1, KEY_2: 2, KEY_3: 4}.get(k.keycode, 0 if session.speed > 0 else 1)
			if not session.set_speed(s):
				_say("Only the host can change the speed: it is everyone's clock.")


## Gene lab keys while it is open. Returns false for keys it does not use.
func _lab_key(k: InputEventKey) -> bool:
	if k.keycode == KEY_B:
		lab_bases = not lab_bases
		return true
	if not lab_bases: # evolve view: pick one of three real mutations, described in plain words
		match k.keycode:
			KEY_1, KEY_2, KEY_3:
				var i := k.keycode - KEY_1
				if i < _options.size():
					session.mutate(_options[i]["m"])
			KEY_R:
				_refresh_options()
			_:
				return false
		return true
	match k.keycode:
		KEY_LEFT:
			cursor -= 10 if k.shift_pressed else 1
		KEY_RIGHT:
			cursor += 10 if k.shift_pressed else 1
		KEY_DELETE, KEY_BACKSPACE:
			session.edit("del", cursor, "")
		KEY_A, KEY_T, KEY_G, KEY_C:
			session.edit("ins" if k.shift_pressed else "rep", cursor, OS.get_keycode_string(k.keycode))
		_:
			return false
	cursor = clampi(cursor, 0, maxi(0, session.germline.length() - 1))
	return true


# ---------------------------------------------------------------- origin picker

func _open_picker() -> void:
	_choices = Traits.origins(_rng, 3)
	for i in _cards.size():
		var card: Array = _cards[i]
		card[4].visible = i < _choices.size()
		if i >= _choices.size():
			continue
		var dna := _choices[i]
		var g := Genome.decode(dna)
		var f := Traits.origin_feature(dna)
		var r := Genome.radius(g) * Planet3D.S
		card[0].build(g, r, world.planet.body_shape, false)
		# the same camera for every card, so a Giant really looks bigger than a Mite
		card[1].position = Vector3(0.0, 0.6, 2.7)
		card[1].look_at(Vector3(0.0, 0.1, 0.0), Vector3.UP)
		card[2].text = "%d. %s" % [i + 1, Traits.INFO[f][1]]
		var t := "[b]%s:[/b] %s\n[b]%s:[/b] %s\n\n[table=2]" % [Traits.INFO[f][0], Traits.INFO[f][2], Traits.body_plan(g), Traits.body_plan_text(g)]
		for st in [["size", "Size"], ["speed", "Speed"], ["sense", "Senses"], ["spikes", "Defense"], ["camo", "Camouflage"]]:
			var n := roundi(g[st[0]] * 10.0)
			t += "[cell]%s   [/cell][cell]%s[color=#ffffff40]%s[/color][/cell]" % [st[1], "█".repeat(n), "░".repeat(10 - n)]
		card[3].text = t + "[/table]"
	_picker_title.text = ("Your lineage has ended. " if session.game_over else "") + "Choose how your lineage begins"
	_reroll_button.text = "Three new options (R): %d left" % _rerolls
	_reroll_button.disabled = _rerolls <= 0
	picker.visible = true


func _pick(i: int) -> void:
	if i >= 0 and i < _choices.size():
		picker.visible = false
		session.choose_origin(_choices[i])


func _reroll() -> void:
	if _rerolls > 0:
		_rerolls -= 1
		_open_picker()


func _build_picker(root: Control) -> void:
	picker = Control.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.visible = false
	root.add_child(picker)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	_picker_title = Label.new()
	_picker_title.add_theme_font_size_override("font_size", 30)
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_picker_title)
	var sub := Label.new()
	sub.text = "Three random genomes. Each is a simple blob with one feature; everything else your line will have to evolve."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.75)
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in 3:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(320, 0)
		row.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var view_box := SubViewportContainer.new()
		view_box.stretch = true
		view_box.custom_minimum_size = Vector2(300, 190)
		box.add_child(view_box)
		var view := SubViewport.new()
		view.own_world_3d = true # the preview has its own little stage, apart from the planet
		view.transparent_bg = true
		view_box.add_child(view)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		view.add_child(sun)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
		view.add_child(env)
		var preview := CreatureModel.new()
		view.add_child(preview)
		var cam := Camera3D.new()
		view.add_child(cam)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color("6df2c2"))
		box.add_child(title)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.custom_minimum_size = Vector2(300, 170)
		box.add_child(text)
		var choose := Button.new()
		choose.text = "Begin as this (%d)" % (i + 1)
		choose.pressed.connect(_pick.bind(i))
		box.add_child(choose)
		_cards.append([preview, cam, title, text, panel])
	_reroll_button = Button.new()
	_reroll_button.pressed.connect(_reroll)
	col.add_child(_reroll_button)


func _leave() -> void:
	session.shutdown()
	get_tree().change_scene_to_file(MENU_SCENE)


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
	climate_label = Label.new()
	climate_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	climate_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	climate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	climate_label.offset_right = -14
	climate_label.offset_top = 10
	root.add_child(climate_label)
	vitals_label = _label(root, Vector2(14, 36))
	energy_bar = _bar(root, Vector2(14, 64), "Energy", Color("6df2a0"))
	age_bar = _bar(root, Vector2(14, 88), "Age", Color("f2c36d"))

	log_label = Label.new()
	log_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	log_label.offset_top = 120
	root.add_child(log_label)

	center_label = Label.new()
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_label.add_theme_font_size_override("font_size", 24)
	root.add_child(center_label)

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
	_build_picker(root) # built after, so it keeps catching clicks


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


## The most urgent thing the player should know about their surroundings, or "".
func _warning(p: World.Creature) -> String:
	if session.my_blocked != "":
		return session.my_blocked
	for m in world.incoming:
		if p.pos.distance_to(m[0]) < World.METEOR_R:
			return "Meteor incoming! Get out of the red zone!"
	if world.too_wet(p.g, world.is_wet(p.pos)):
		return "You are drowning! Get to land." if p.g["aqua"] < 0.35 else "You are drying out! Get to water."
	var mismatch: float = p.g["temp"] - world.temp_at(p.pos)
	if mismatch > 0.3:
		return "It is too cold here for your body."
	if mismatch < -0.3:
		return "It is too hot here for your body."
	return ""


func _update_hud(delta: float) -> void:
	for m in _messages:
		m[1] -= delta
	_messages = _messages.filter(func(m): return m[1] > 0.0)
	log_label.text = "\n".join(_messages.map(func(m): return m[0]))
	if _lost != "":
		center_label.text = "%s\nPress Enter to return to the menu." % _lost
	elif _leaving:
		center_label.text = "Leave this world?\nEnter to leave, Esc to stay."
	elif world == null:
		center_label.text = "Waiting for the server..."
	else:
		center_label.text = ""
	var p: World.Creature = session.my_creature() if world != null else null
	(energy_bar.get_parent() as Control).visible = p != null
	(age_bar.get_parent() as Control).visible = p != null
	if world == null:
		stats_label.text = ""
		climate_label.text = ""
		vitals_label.text = ""
		prompt_label.text = ""
		return
	var online := "" if session.names.size() <= 1 else "   %d players" % session.names.size()
	stats_label.text = "Population %d   Species %d   World age %.1f kyr   %s%s" % [
		world.creatures.size(), world.species, world.tick / 100.0,
		"Paused" if session.speed == 0 else "Speed %dx" % session.speed, online]
	var trend := clampf(world.climate_base + World.ERAS[world.era]["temp"], 0.0, 1.0) - world.temp
	climate_label.text = "%s%s  (seed %d)\n%s\n%s%s\n%d °C   sea level %+.1f m" % [
		session.server_name + ": " if session.server_name != "" else "", world.planet.name, world.planet.seed,
		world.planet.describe(), World.ERAS[world.era]["name"],
		"  (cooling)" if trend < -0.02 else ("  (warming)" if trend > 0.02 else ""),
		roundi(-20.0 + world.temp * 70.0), (world.sea_level - World.SEA) * planet.relief]
	if p != null:
		var need := world.breed_energy(p)
		vitals_label.text = "You: generation %d   %s   %d of your line alive" % [p.gen, Traits.body_plan(p.g), session.my_line]
		energy_bar.max_value = need
		energy_bar.value = p.e
		age_bar.max_value = World.LIFESPAN
		age_bar.value = p.age
		prompt_label.text = _warning(p)
		if prompt_label.text == "" and p.e > need:
			prompt_label.text = "R  lay an offspring"
	else:
		vitals_label.text = "Your lineage has ended." if session.game_over else ""
		prompt_label.text = ""
	if lab_open:
		lab_text.text = _lab_text()


func _lab_text() -> String:
	if session.germline == "":
		return "Choose how your lineage begins first."
	if lab_bases:
		var header := "[b]GENE LAB[/b]  your germline, base by base  |  base %d of %d  |  %d / %d Cas9 charges  |  B: back to evolve" % [
			cursor + 1, session.germline.length(), session.charges, Session.MAX_CHARGES]
		return GeneLab.render(session.germline, cursor, maxi(20, int(lab_text.size.x / 11.0)), header, session.status)
	var g := Genome.decode(session.germline)
	var t := "[b]EVOLVE[/b]  your germline: what your offspring will be  |  %d / %d Cas9 charges\n" % [session.charges, Session.MAX_CHARGES]
	t += "Body plan: [b]%s[/b] (%s).   Features: %s\n" % [Traits.body_plan(g), Traits.body_plan_text(g), Traits.feature_names(g)]
	for i in _options.size():
		t += "[color=#6df2c2][%d][/color]  %s\n" % [i + 1, _options[i]["text"]]
	if _options.is_empty():
		t += "No mutation with a visible effect turned up. Press R to look again.\n"
	t += "[color=#9fb]1/2/3[/color] apply one (1 charge)    [color=#9fb]R[/color] other options    [color=#9fb]B[/color] edit bases by hand    [color=#9fb]Tab[/color] close\n"
	return t + "[color=#7fa39d]%s[/color]" % session.status
