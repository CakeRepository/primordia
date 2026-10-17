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
	var ok: bool = m.released and m.world.tick > 100
	# sliders must not take keyboard focus, or they swallow the gene lab's arrow keys
	for s in m.find_children("*", "HSlider", true, false):
		ok = ok and (s as HSlider).focus_mode == Control.FOCUS_NONE
	# dragging past the map edge must not build up a hidden camera offset
	var cam: Camera2D = m.cam
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-5000, 0)
	m._pressed = true
	m._dragging = true
	m._unhandled_input(drag)
	m._pressed = false
	var half: Vector2 = m.get_viewport_rect().size / cam.zoom / 2.0
	ok = ok and cam.position.x <= World.WW - half.x + 0.01
	print("cam after drag %s (max x %.1f)" % [cam.position, World.WW - half.x])
	# the levers column and the gene lab must not overlap
	var panels := []
	for c in m.find_children("*", "PanelContainer", true, false):
		panels.append((c as Control).get_global_rect())
	ok = ok and panels.size() == 2 and not panels[0].intersects(panels[1])
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
