extends SceneTree
## End-to-end multiplayer test with real processes: godot --headless --path . -s res://scripts/test_net.gd
## 1. Host: this process hosts a world on the LAN; a second game process joins it from the
##    command line as "Bot", plays a creature, and leaves when killed.
## 2. Dedicated: a headless server process runs seed 4242. This process finds it on the LAN,
##    joins, checks it built the very same planet from the seed, walks, edits its germline over
##    the network, and sees a second remote player arrive.

const GAME := "res://scenes/main3d.tscn"

var _procs: Array[int] = []


func _spawn(args: Array) -> int:
	var all: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "6000", "--"]
	var pid := OS.create_process(OS.get_executable_path(), all + args)
	_procs.append(pid)
	return pid


func _wait(cond: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _press(m: Node, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	m._key(e)


func _init() -> void:
	var ok := true
	var port := 24600 + randi() % 800

	# ------------------------------------------------ 1. host on the LAN, a second process joins
	var host: Node = load(GAME).instantiate()
	host.config = {"mode": "host", "seed": 999, "port": port, "player_name": "Host"}
	root.add_child(host)
	await process_frame
	ok = ok and host.session.is_server and host.world != null and host.session.my_creature() != null
	var bot := _spawn(["--join", "127.0.0.1:%d" % port, "--name", "Bot"])
	var joined: bool = await _wait(func(): return host.session.names.size() == 2, 40.0)
	var bot_peer := 0
	for peer in host.session.names:
		if peer != 1:
			bot_peer = peer
	print("host: bot joined=%s, players %s, bot plays a creature=%s" % [
		joined, host.session.names.values(), host.world.players.has(bot_peer)])
	ok = ok and joined and host.world.players.has(bot_peer)
	var bot_owner: int = host.world.players[bot_peer].owner if host.world.players.has(bot_peer) else -1
	OS.kill(bot)
	var left: bool = await _wait(func(): return host.session.names.size() == 1, 20.0)
	var lives_on: bool = host.world.lineage_count(bot_owner) > 0
	print("host: bot left=%s, its lineage lives on as wild creatures=%s" % [left, lives_on])
	ok = ok and left and not host.world.players.has(bot_peer) and lives_on
	host.session.shutdown()
	host.queue_free()
	await process_frame
	await process_frame

	# ------------------------------------------------ 2. dedicated server, discovered on the LAN
	var lan := Lan.new()
	root.add_child(lan)
	var listening := lan.listen()
	_spawn(["--server", "--port", str(port + 1), "--seed", "4242", "--name", "E2E server"])
	var found := false
	if listening:
		found = await _wait(func(): return lan.servers.values().any(func(s): return int(s["seed"]) == 4242 and int(s["port"]) == port + 1), 40.0)
	print("LAN discovery: listening=%s, found the dedicated server=%s" % [listening, found])
	ok = ok and (found or not listening)

	var cl: Node = load(GAME).instantiate()
	cl.config = {"mode": "join", "address": "127.0.0.1", "port": port + 1, "player_name": "Tester"}
	root.add_child(cl)
	var ready: bool = await _wait(func(): return cl.world != null and cl.session.my_creature() != null, 40.0)
	ok = ok and ready
	if ready:
		var expected := PlanetGen.new(4242)
		print("client: joined %s, planet %s (seed %d), %d creatures mirrored" % [
			cl.session.server_name, cl.world.planet.name, cl.world.planet.seed, cl.world.creatures.size()])
		ok = ok and cl.world.planet.seed == 4242 and cl.world.planet.name == expected.name and cl.world.creatures.size() > 40
		ok = ok and cl.session.server_name == "E2E server"

		# walk: input goes to the server, the new position comes back in snapshots
		var start: Vector2 = cl.session.my_creature().pos
		_key(KEY_W, true)
		var moved: bool = await _wait(func():
			var c: World.Creature = cl.session.my_creature()
			return c != null and (c.pos.distance_to(start) > 20.0 or cl.session.my_blocked != ""), 15.0)
		_key(KEY_W, false)
		print("client: walked=%s (%s)" % [moved, cl.session.my_blocked if cl.session.my_blocked != "" else "moved"])
		ok = ok and moved

		# gene lab edit: a round trip to the server
		_press(cl, KEY_TAB)
		_press(cl, KEY_RIGHT)
		_press(cl, KEY_G)
		var edited: bool = await _wait(func(): return cl.session.charges == Session.MAX_CHARGES - 1, 10.0)
		_press(cl, KEY_TAB)
		print("client: germline edit confirmed by the server=%s (%s)" % [edited, cl.session.status])
		ok = ok and edited

		# a second player arrives and shows up, name tag and all
		_spawn(["--join", "127.0.0.1:%d" % (port + 1), "--name", "Bot2"])
		var seen: bool = await _wait(func():
			return cl.session.names.values().has("Bot2") and cl._tags.size() > 0, 40.0)
		print("client: sees Bot2=%s, players %s" % [seen, cl.session.names.values()])
		ok = ok and seen

	for pid in _procs:
		OS.kill(pid)
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
