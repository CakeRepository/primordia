extends SceneTree
## Headless 3D smoke test (solo play): godot --headless -s res://scripts/test_main3d.gd

func _k(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _init() -> void:
	var m: Node = load("res://scenes/main3d.tscn").instantiate()
	m.config = {"mode": "solo", "seed": 31337, "player_name": "Tester"}
	root.add_child(m)
	await process_frame
	var s: Session = m.session
	var w: World = m.world
	var me: World.Creature = s.my_creature()
	var ok: bool = me != null and me.owner != 0 and me.driver == 1 and w.creatures.size() >= 75
	ok = ok and w.planet.seed == 31337 and s.names.get(1) == "Tester"
	print("start: %s, pop %d, food %d, player gen %d" % [w.planet.name, w.creatures.size(), w.foods.size(), me.gen])

	# walk forward through the real input path
	var start := me.pos
	Input.parse_input_event(_k(KEY_W))
	for _i in 60:
		await process_frame
	var up := _k(KEY_W)
	up.pressed = false
	Input.parse_input_event(up)
	var moved := me.pos.distance_to(start)
	print("walked %.1f units%s" % [moved, (" (blocked: %s)" % s.my_blocked) if s.my_blocked != "" else ""])
	ok = ok and (moved > 5.0 or s.my_blocked != "")
	ok = ok and m.model.get_child_count() > 0
	ok = ok and m.planet.bodies.visible_instance_count + m.planet.spiky.visible_instance_count > 0
	ok = ok and m.planet.food_mm.visible_instance_count > 0

	# lay an offspring
	var owner := me.owner
	var line := w.lineage_count(owner)
	s.my_creature().e = 500.0
	m._key(_k(KEY_R))
	ok = ok and w.lineage_count(owner) == line + 1

	# edit the germline in the gene lab
	m._key(_k(KEY_TAB))
	ok = ok and m.lab_open
	m._key(_k(KEY_RIGHT))
	m._key(_k(KEY_G))
	ok = ok and s.charges == Session.MAX_CHARGES - 1
	m._key(_k(KEY_TAB))
	ok = ok and not m.lab_open

	# die: control passes to the nearest descendant, whose DNA becomes the germline
	var old := s.my_creature()
	old.e = -1.0
	w.step()
	var heir := s.my_creature()
	ok = ok and heir != null and heir != old and heir.owner == owner and s.germline == heir.dna
	print("after death: player gen %d, cause '%s'" % [heir.gen if heir else -1, old.cause])

	# the whole line dies: game over, Enter starts a new lineage
	for c in w.creatures:
		if c.owner == owner:
			c.e = -1.0
	w.step()
	ok = ok and s.my_creature() == null and s.game_over
	m._key(_k(KEY_ENTER))
	ok = ok and s.my_creature() != null and not s.game_over
	await process_frame

	# a warming climate raises the 3D sea; a meteor aimed at the player is announced and lands
	w.temp = 0.8
	w.meteor_at(s.my_creature().pos, 20)
	ok = ok and m._messages.any(func(msg): return "red zone" in msg[0])
	for _i in 30:
		await process_frame
	print("sea surface at %.2f m, %d flashes, %d craters" % [m.planet.water_y(), m.planet._flashes.size(), w.craters.size()])
	ok = ok and m.planet.water_y() > 0.5 and m.planet._water.position.y > 0.5
	ok = ok and m.planet._flashes.size() > 0 and w.craters.size() > 0

	# only the server's own player may change the speed; solo is the server
	m._key(_k(KEY_3))
	ok = ok and s.speed == 4
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
