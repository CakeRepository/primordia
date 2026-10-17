extends SceneTree
## Headless UI smoke test: godot --headless -s res://scripts/test_main.gd

func _press(m: Node, code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	m._key(e)

func _init() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	_press(m, KEY_RIGHT)
	_press(m, KEY_A)
	_press(m, KEY_T, true)
	_press(m, KEY_DELETE)
	_press(m, KEY_ENTER)
	for i in 400:
		await process_frame
	m.world.selected = m.world.creatures[0] if m.world.creatures.size() > 0 else null
	_press(m, KEY_L)
	_press(m, KEY_W)
	_press(m, KEY_ENTER)
	m._click()
	m.world.meteor()
	m.world.storm()
	m.world.wild_seed()
	m._refresh()
	print("pop %d charges %d released %s" % [m.world.creatures.size(), m.charges, str(m.released)])
	print("PASS" if m.released and m.world.tick > 100 else "FAIL")
	quit(0)
