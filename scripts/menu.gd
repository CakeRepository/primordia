extends Control
## Title screen, Minecraft-style: play a world alone, host one on the LAN for friends, or join
## a server (LAN servers are found automatically). Started from the command line with --server,
## --host, --join or --solo, it goes straight into the game instead.

const GAME_SCENE := "res://scenes/main3d.tscn"
const SANDBOX_SCENE := "res://scenes/main.tscn"
const SETTINGS := "user://settings.cfg"

var name_edit: LineEdit
var seed_edit: LineEdit
var port_edit: LineEdit
var address_edit: LineEdit
var server_list: ItemList
var note: Label
var lan: Lan
var launch: Node # the Launch autoload (created here when running without autoloads, e.g. in tools)
var _listed: Array = [] # server ids, in list order
var _refresh_t := 0.0


func _ready() -> void:
	launch = get_node_or_null("/root/Launch")
	if launch == null:
		launch = load("res://scripts/launch.gd").new()
		launch.name = "Launch"
		get_tree().root.add_child.call_deferred(launch)
	if launch.from_cli:
		launch.from_cli = false # back here after leaving a game means: show the menu
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	_build()
	_load_settings()
	lan = Lan.new()
	add_child(lan)
	if not lan.listen():
		note.text = "LAN discovery is unavailable (port %d is in use); you can still join by address." % Lan.PORT


func _process(delta: float) -> void:
	_refresh_t += delta
	if lan == null or _refresh_t < 0.5:
		return
	_refresh_t = 0.0
	var ids: Array = lan.servers.keys()
	ids.sort()
	if ids == _listed:
		return
	_listed = ids
	server_list.clear()
	for id in ids:
		var s: Dictionary = lan.servers[id]
		server_list.add_item("%s   %s (seed %d)   %d player%s   %s:%d" % [s.get("name", "?"), s.get("planet", "?"),
			int(s.get("seed", 0)), int(s.get("players", 0)), "" if int(s.get("players", 0)) == 1 else "s",
			s["address"], int(s["port"])])
	if ids.is_empty():
		server_list.add_item("Looking for worlds on your network...")
		server_list.set_item_disabled(0, true)


# ---------------------------------------------------------------- actions

func _play(mode: String) -> void:
	launch.mode = mode
	launch.player_name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Player"
	launch.seed = launch.parse_seed(seed_edit.text)
	launch.port = clampi(port_edit.text.to_int(), 1, 65535) if port_edit.text.is_valid_int() else Session.DEFAULT_PORT
	if mode == "join":
		var target := address_edit.text.strip_edges()
		if target == "":
			note.text = "Pick a world from the list or type an address to join."
			return
		launch.set_address(target)
	_save_settings()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_server_selected(i: int) -> void:
	if i < _listed.size():
		var s: Dictionary = lan.servers.get(_listed[i], {})
		if not s.is_empty():
			address_edit.text = "%s:%d" % [s["address"], int(s["port"])]


func _on_server_activated(i: int) -> void:
	_on_server_selected(i)
	if address_edit.text != "":
		_play("join")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		name_edit.text = cfg.get_value("player", "name", "")
		address_edit.text = cfg.get_value("join", "address", "")
		port_edit.text = str(cfg.get_value("host", "port", Session.DEFAULT_PORT))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", name_edit.text.strip_edges())
	cfg.set_value("join", "address", address_edit.text.strip_edges())
	cfg.set_value("host", "port", port_edit.text.to_int() if port_edit.text.is_valid_int() else Session.DEFAULT_PORT)
	cfg.save(SETTINGS)


# ---------------------------------------------------------------- layout

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(660, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title := Label.new()
	title.text = "PRIMORDIA"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _text(col, "Evolve a creature on a living alien world. Every seed is a different planet.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)

	name_edit = _field(_row(col, "Your name"), "Player")

	_heading(col, "New world")
	seed_edit = _field(_row(col, "World seed"), "random (or type any number or word)")
	var buttons := _row(col, "")
	_button(buttons, "Play solo", func(): _play("solo"))
	_button(buttons, "Host on LAN", func(): _play("host"))
	_text(buttons, "  port")
	port_edit = _field(buttons, str(Session.DEFAULT_PORT))
	port_edit.custom_minimum_size = Vector2(90, 0)
	port_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	port_edit.text = str(Session.DEFAULT_PORT)

	_heading(col, "Join a world")
	server_list = ItemList.new()
	server_list.custom_minimum_size = Vector2(0, 120)
	server_list.item_selected.connect(_on_server_selected)
	server_list.item_activated.connect(_on_server_activated)
	server_list.add_item("Looking for worlds on your network...")
	server_list.set_item_disabled(0, true)
	col.add_child(server_list)
	var join_row := _row(col, "Address")
	address_edit = _field(join_row, "address or address:port")
	address_edit.text_submitted.connect(func(_t): _play("join"))
	_button(join_row, "Join", func(): _play("join"))

	note = _text(col, "")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1.0, 0.8, 0.6)
	var hint := _text(col, "Run a dedicated server:  godot --headless --path . -- --server --port %d --seed 42" % Session.DEFAULT_PORT)
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.55)
	var bottom := _row(col, "")
	_button(bottom, "Top-down sandbox", func(): get_tree().change_scene_to_file(SANDBOX_SCENE))
	_button(bottom, "Quit", func(): get_tree().quit())


func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	if title != "":
		var l := _text(row, title)
		l.custom_minimum_size = Vector2(110, 0)
	return row


func _field(parent: Control, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _text(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _heading(parent: Control, text: String) -> void:
	var l := _text(parent, text)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color("6df2c2"))
