class_name Session
extends Node
## Runs a world and the players in it, like a Minecraft server. Solo play, "host on LAN" and the
## headless dedicated server all run the same server code here; solo simply has no network
## peers. A joining client receives only the world seed, builds the identical alien planet
## itself, then mirrors live state (creatures, food, climate, meteors) from compressed
## snapshots. The local player's actions call the server code directly when this process is
## the server, and go over RPC when it is a client.
##
## The node must sit at the same path on server and clients (/root/Main3D/Session).

const VERSION := 1
const DEFAULT_PORT := 24565
const TICK_RATE := 60.0 # sim ticks per second at 1x
const SNAPSHOT_RATE := 15.0 # snapshots per second per client
const FOOD_EVERY := 3 # food goes out in every third snapshot
const MAX_PLAYERS := 16
const MAX_CHARGES := 12
const MAX_STEPS_PER_FRAME := 8
const DEFAULT_STATUS := "Edits change your germline: the DNA your offspring inherit."

signal world_ready
signal said(text: String)
signal meteor_seen(pos: Vector2)
signal impacted(pos: Vector2, killed: int)
signal died(cause: String, heir_gen: int) # heir_gen < 0: the lineage has ended
signal reborn
signal lab_changed
signal roster_changed
signal disconnected(reason: String)

var world: World
var is_server := false
var has_local_player := true
var me := 1 # this process's peer id; the server's own player is always 1
var speed := 1
var server_name := ""
var names := {} # peer -> player name, everyone in the world

# The local player's own state (the server keeps the authoritative copy in _players).
var germline := ""
var charges := MAX_CHARGES
var status := DEFAULT_STATUS
var cursor_hint := -1 # where an edit left the lab cursor
var game_over := false
var my_id := 0 # id of the creature this player is playing (0 = none)
var my_line := 0 # living members of this player's lineage
var my_blocked := ""

# server
var _players := {} # peer -> {name, owner, germline, charges, status}
var _owners := {} # player name -> lineage id, stable for the life of the world
var _next_owner := 1
var _known := {} # peer -> {dna id: true} for clients that said hello
var _dna_ids := {} # dna string -> id
var _dna_next := 1
var _acc := 0.0
var _snap_acc := 0.0
var _snap_n := 0
var _server_id := ""

# client
var _dna_table := {} # dna id -> dna string
var _mirror := {} # creature id -> World.Creature
var _targets := {} # creature id -> latest server position
var _pred_pool: Array[World.Predator] = []
var _food_pool: Array[World.Food] = []
var _painted_temp := -1.0
var _painted_craters := -1.0


# ---------------------------------------------------------------- starting

func start_solo(seed: int, player_name: String) -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(seed, player_name, true)


func start_host(seed: int, player_name: String, port: int) -> Error:
	var err := _listen(port)
	if err == OK:
		_start_server(seed, player_name, true)
		server_name = "%s's world" % player_name
		_announce(port)
	return err


func start_dedicated(seed: int, port: int, title: String) -> Error:
	var err := _listen(port)
	if err == OK:
		_start_server(seed, "", false)
		server_name = title if title != "" else "Primordia server"
		_announce(port)
	return err


func start_client(address: String, port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func():
		me = multiplayer.get_unique_id()
		_quick_timeout(1)
		_hello.rpc_id(1, player_name, VERSION))
	multiplayer.connection_failed.connect(func(): disconnected.emit("Could not reach %s:%d." % [address, port]))
	multiplayer.server_disconnected.connect(func(): disconnected.emit("The server closed the connection."))
	return OK


func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _listen(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_quick_timeout)
	return err


## Notice a vanished peer within seconds instead of ENet's default of up to half a minute.
func _quick_timeout(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.get_peer(peer_id) != null:
		enet.get_peer(peer_id).set_timeout(32, 2000, 6000)


func _start_server(seed: int, player_name: String, local: bool) -> void:
	is_server = true
	has_local_player = local
	me = 1
	_server_id = str(randi())
	world = _make_world(seed if seed != 0 else randi())
	world.populate()
	world.planet_event.connect(func(t): _emit_all("msg", [t]))
	world.meteor_incoming.connect(func(p): _emit_all("meteor", [p]))
	world.meteor_impact.connect(func(p, k): _emit_all("impact", [p, k]))
	world.player_died.connect(_on_player_died)
	world.charge_tick.connect(_on_charge_tick)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	if local:
		_add_player(1, player_name)
	world_ready.emit()


func _make_world(seed: int) -> World:
	var w := World.new()
	w.visible = false # the 2D drawing is for the top-down view only
	w.planet = PlanetGen.new(seed)
	add_child(w)
	return w


func _announce(port: int) -> void:
	var lan := Lan.new()
	add_child(lan)
	lan.announce(func(): return {
		"game": Lan.GAME, "v": VERSION, "id": _server_id, "name": server_name, "port": port,
		"players": _players.size(), "planet": world.planet.name, "seed": world.planet.seed})


# ---------------------------------------------------------------- local player API

## The creature this process's player is playing, or null.
func my_creature() -> World.Creature:
	if world == null:
		return null
	if is_server:
		return world.players.get(me)
	return _mirror.get(my_id)


func send_input(dir: Vector2) -> void:
	if is_server:
		world.inputs[me] = dir.limit_length(1.0)
	elif world != null:
		_steer.rpc_id(1, dir)


func reproduce() -> void:
	_act_here_or_remote("reproduce", [])


func edit(kind: String, cursor: int, base: String) -> void:
	_act_here_or_remote("edit", [kind, cursor, base])


func restart() -> void:
	_act_here_or_remote("restart", [])


## Only the server's own player (solo or host) can change the speed: it is everyone's clock.
func set_speed(s: int) -> bool:
	if is_server and has_local_player:
		speed = s
		return true
	return false


func _act_here_or_remote(action: String, args: Array) -> void:
	if is_server:
		_do(me, action, args)
	else:
		_act.rpc_id(1, action, args)


# ---------------------------------------------------------------- RPC: client -> server

@rpc("any_peer", "reliable")
func _hello(player_name: String, version: int) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_event.rpc_id(peer, "msg", ["This server runs a different version of Primordia (%d, you have %d)." % [VERSION, version]])
		get_tree().create_timer(1.0).timeout.connect(func(): multiplayer.multiplayer_peer.disconnect_peer(peer))
		return
	_welcome.rpc_id(peer, world.planet.seed, {"name": server_name, "speed": speed})
	_known[peer] = {}
	_add_player(peer, player_name)


@rpc("any_peer", "unreliable_ordered")
func _steer(dir: Vector2) -> void:
	if is_server and _players.has(multiplayer.get_remote_sender_id()):
		world.inputs[multiplayer.get_remote_sender_id()] = dir.limit_length(1.0)


@rpc("any_peer", "reliable")
func _act(action: String, args: Array) -> void:
	if is_server:
		_do(multiplayer.get_remote_sender_id(), action, args)


# ---------------------------------------------------------------- server

func _add_player(peer: int, player_name: String) -> void:
	var n := player_name.strip_edges().left(24)
	if n == "":
		n = "Player %d" % (_players.size() + 1)
	while names.values().has(n):
		n += "'"
	if not _owners.has(n):
		_owners[n] = _next_owner
		_next_owner += 1
	var owner: int = _owners[n]
	var resumed := world.lineage_count(owner) > 0 # they played here before and their line lives on
	var c := world.join(peer, owner, Genome.founder(world.rng))
	_players[peer] = {"name": n, "owner": owner, "germline": c.dna, "charges": MAX_CHARGES, "status": DEFAULT_STATUS}
	names[peer] = n
	_send_lab(peer, 0)
	_send_roster()
	if resumed:
		_emit_to(peer, "msg", ["Welcome back. You return as your descendant, generation %d." % c.gen])
	else:
		_emit_to(peer, "msg", ["You hatch on %s. Eat, stay alive, and press R to lay offspring." % world.planet.name])
	_emit_all("msg", ["%s joined the world." % n], peer)
	if not has_local_player or peer != 1:
		print("[server] %s joined (%d player%s)" % [n, _players.size(), "" if _players.size() == 1 else "s"])


func _on_peer_left(peer: int) -> void:
	if not _players.has(peer):
		return
	var n: String = _players[peer]["name"]
	world.leave(peer)
	_players.erase(peer)
	_known.erase(peer)
	names.erase(peer)
	_send_roster()
	_emit_all("msg", ["%s left. Their creatures live on without them." % n])
	print("[server] %s left (%d player%s)" % [n, _players.size(), "" if _players.size() == 1 else "s"])


func _do(peer: int, action: String, args: Array) -> void:
	if not _players.has(peer):
		return
	var st: Dictionary = _players[peer]
	match action:
		"reproduce":
			var p: World.Creature = world.players.get(peer)
			if p == null:
				return
			var kid := world.player_reproduce(peer, st["germline"])
			if kid == null:
				_emit_to(peer, "msg", ["Not enough energy to lay offspring yet (%d of %d). Eat more." % [int(p.e), int(world.breed_energy(p)) + 1]])
			else:
				_emit_to(peer, "msg", ["You laid an offspring. It carries your germline, generation %d." % kid.gen])
		"edit":
			# Arguments come from the network: check them before use.
			if args.size() != 3 or typeof(args[0]) != TYPE_STRING or typeof(args[1]) != TYPE_INT or typeof(args[2]) != TYPE_STRING:
				return
			var kind: String = args[0]
			var base: String = args[2]
			if not kind in ["rep", "ins", "del"] or (kind != "del" and not base in ["A", "T", "G", "C"]):
				return
			var dna: String = st["germline"]
			var cursor := clampi(args[1], 0, dna.length() - 1)
			if st["charges"] < 1:
				st["status"] = "No Cas9 charges left. They refill slowly."
				_send_lab(peer, cursor)
				return
			var r := Genome.edit(dna, kind, cursor, base, world.rng)
			st["status"] = r["msg"]
			if r["done"]:
				st["charges"] -= 1
				st["germline"] = r["dna"]
				cursor = r["cursor"]
			_send_lab(peer, cursor)
		"restart":
			if world.players.has(peer):
				return
			var c := world.join(peer, st["owner"], st["germline"])
			st["germline"] = c.dna
			_send_lab(peer, 0)
			_emit_to(peer, "reborn", [])
			_emit_to(peer, "msg", ["A new lineage hatches on %s." % world.planet.name])


func _on_player_died(peer: int, old: World.Creature, heir: World.Creature) -> void:
	if heir != null and _players.has(peer):
		_players[peer]["germline"] = heir.dna
		_send_lab(peer, -1)
	_emit_to(peer, "died", [old.cause, heir.gen if heir != null else -1])


func _on_charge_tick() -> void:
	for peer in _players:
		_players[peer]["charges"] = mini(MAX_CHARGES, _players[peer]["charges"] + 1)
		_send_lab(peer, -1)


func _send_lab(peer: int, cursor: int) -> void:
	var st: Dictionary = _players[peer]
	if peer == me and has_local_player:
		_apply_lab(st["germline"], st["charges"], st["status"], cursor)
	else:
		_lab.rpc_id(peer, st["germline"], st["charges"], st["status"], cursor)


func _send_roster() -> void:
	_roster.rpc(names)
	roster_changed.emit()


## Deliver an event to everyone (except `skip`), including the server's own player.
func _emit_all(kind: String, args: Array, skip := 0) -> void:
	for peer in _players:
		if peer != skip:
			_emit_to(peer, kind, args)


func _emit_to(peer: int, kind: String, args: Array) -> void:
	if peer == me and has_local_player:
		_handle_event(kind, args)
	elif _players.has(peer):
		_event.rpc_id(peer, kind, args)


func _process(delta: float) -> void:
	if world == null:
		return
	if not is_server:
		_interpolate(delta)
		return
	_acc = minf(_acc + delta * TICK_RATE * speed, MAX_STEPS_PER_FRAME)
	while _acc >= 1.0:
		_acc -= 1.0
		if world.running:
			world.step()
	if has_local_player:
		var c: World.Creature = world.players.get(me)
		my_id = c.id if c != null else 0
		my_line = world.lineage_count(_players[me]["owner"]) if _players.has(me) else 0
		my_blocked = world.blocked.get(me, "")
	_snap_acc += delta
	if _snap_acc >= 1.0 / SNAPSHOT_RATE and not _known.is_empty():
		_snap_acc = 0.0
		_send_snapshots()
	if world.tick % 3000 == 0 and world.tick > 0:
		_prune_dna()


# ---------------------------------------------------------------- snapshots

func _send_snapshots() -> void:
	_snap_n += 1
	var common := _encode_common(_snap_n % FOOD_EVERY == 0)
	for peer in _known:
		_send_new_dna(peer)
		var data := common + _encode_tail(peer)
		_snapshot.rpc_id(peer, data.compress(FileAccess.COMPRESSION_ZSTD), data.size())


func _dna_id(dna: String) -> int:
	if not _dna_ids.has(dna):
		_dna_ids[dna] = _dna_next
		_dna_next += 1
	return _dna_ids[dna]


## Forget DNA no creature carries any more (ids are never reused).
func _prune_dna() -> void:
	var live := {}
	for c in world.creatures:
		live[c.dna] = true
	for dna in _dna_ids.keys():
		if not live.has(dna):
			_dna_ids.erase(dna)


func _send_new_dna(peer: int) -> void:
	var known: Dictionary = _known[peer]
	var defs := {}
	for c in world.creatures:
		if not known.has(c.dna_id):
			known[c.dna_id] = true
			defs[c.dna_id] = c.dna
	if not defs.is_empty():
		_dna.rpc_id(peer, defs)


static func _put_pos(b: StreamPeerBuffer, p: Vector2) -> void:
	b.put_u16(clampi(roundi(p.x / World.WW * 65535.0), 0, 65535))
	b.put_u16(clampi(roundi(p.y / World.WH * 65535.0), 0, 65535))


static func _get_pos(b: StreamPeerBuffer) -> Vector2:
	var x := b.get_u16() / 65535.0 * World.WW
	return Vector2(x, b.get_u16() / 65535.0 * World.WH)


static func _angle8(v: Vector2) -> int:
	return posmod(roundi(v.angle() / TAU * 256.0), 256)


func _encode_common(with_food: bool) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(world.tick)
	b.put_float(world.temp)
	b.put_float(world.sea_level)
	b.put_u8(world.era)
	b.put_u16(world.species)
	b.put_u8(speed)
	b.put_u8(1 if world.running else 0)
	b.put_u8(world.incoming.size())
	for m in world.incoming:
		_put_pos(b, m[0])
		b.put_u16(m[1])
	b.put_u8(world.craters.size())
	for c in world.craters:
		_put_pos(b, c[0])
		b.put_u8(clampi(int(c[2] * 255.0), 0, 255))
	b.put_u8(world.preds.size())
	for p in world.preds:
		_put_pos(b, p.pos)
		b.put_u8(_angle8(p.vel))
		b.put_u8((1 if p.stun > 0 else 0) | (2 if p.aq else 0))
	b.put_u16(world.creatures.size())
	for c in world.creatures:
		if c.dna_id == 0:
			c.dna_id = _dna_id(c.dna)
		b.put_u32(c.id)
		_put_pos(b, c.pos)
		b.put_u8(_angle8(c.vel))
		b.put_u8(clampi(int(c.vel.length() * 60.0), 0, 255))
		b.put_u32(c.dna_id)
		b.put_u32(c.driver)
	b.put_u8(1 if with_food else 0)
	if with_food:
		b.put_u16(world.foods.size())
		for f in world.foods:
			b.put_u16(clampi(roundi(f.pos.x / World.WW * 65535.0), 0, 65535))
			b.put_u16(clampi(roundi(f.pos.y / World.WH * 32767.0), 0, 32767) | (32768 if f.aq else 0))
	return b.data_array


func _encode_tail(peer: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var c: World.Creature = world.players.get(peer)
	b.put_u32(c.id if c != null else 0)
	b.put_float(c.e if c != null else 0.0)
	b.put_u16(c.age if c != null else 0)
	b.put_u16(c.gen if c != null else 0)
	b.put_u16(world.lineage_count(_players[peer]["owner"]) if _players.has(peer) else 0)
	b.put_utf8_string(world.blocked.get(peer, ""))
	return b.data_array


# ---------------------------------------------------------------- RPC: server -> client

@rpc("authority", "reliable")
func _welcome(seed: int, info: Dictionary) -> void:
	server_name = info.get("name", "")
	speed = info.get("speed", 1)
	world = _make_world(seed)
	world_ready.emit()


@rpc("authority", "reliable")
func _dna(defs: Dictionary) -> void:
	_dna_table.merge(defs, true)


@rpc("authority", "reliable")
func _lab(g: String, ch: int, st: String, cursor: int) -> void:
	_apply_lab(g, ch, st, cursor)


@rpc("authority", "reliable")
func _roster(n: Dictionary) -> void:
	names = n
	roster_changed.emit()


@rpc("authority", "reliable")
func _event(kind: String, args: Array) -> void:
	_handle_event(kind, args)


func _apply_lab(g: String, ch: int, st: String, cursor: int) -> void:
	germline = g
	charges = ch
	status = st
	cursor_hint = cursor
	lab_changed.emit()


func _handle_event(kind: String, args: Array) -> void:
	match kind:
		"msg":
			said.emit(args[0])
		"meteor":
			meteor_seen.emit(args[0])
		"impact":
			impacted.emit(args[0], args[1])
		"died":
			if args[1] < 0:
				game_over = true
			died.emit(args[0], args[1])
		"reborn":
			game_over = false
			reborn.emit()


# Reliable on its own channel: snapshots are bigger than one packet, and a lost fragment
# would drop the whole snapshot.
@rpc("authority", "reliable", "call_remote", 1)
func _snapshot(data: PackedByteArray, size: int) -> void:
	if world == null:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data.decompress(size, FileAccess.COMPRESSION_ZSTD)
	world.tick = b.get_u32()
	world.temp = b.get_float()
	world.sea_level = b.get_float()
	world.era = b.get_u8()
	world.species = b.get_u16()
	speed = b.get_u8()
	world.running = b.get_u8() == 1
	world.incoming.clear()
	for _i in b.get_u8():
		var p := _get_pos(b)
		world.incoming.append([p, b.get_u16()])
	var craters: Array = []
	for _i in b.get_u8():
		var p := _get_pos(b)
		craters.append([p, World.METEOR_R, b.get_u8() / 255.0])
	world.craters = craters
	var preds: Array[World.Predator] = []
	for i in b.get_u8():
		if i >= _pred_pool.size():
			_pred_pool.append(World.Predator.new())
		var q := _pred_pool[i]
		q.pos = _get_pos(b)
		q.vel = Vector2.from_angle(b.get_u8() / 256.0 * TAU)
		var flags := b.get_u8()
		q.stun = 1 if flags & 1 else 0
		q.aq = flags & 2 != 0
		preds.append(q)
	world.preds = preds
	var seen := {}
	var list: Array[World.Creature] = []
	for _i in b.get_u16():
		var id := b.get_u32()
		var p := _get_pos(b)
		var heading := b.get_u8() / 256.0 * TAU
		var spd := b.get_u8() / 60.0
		var dna_id := b.get_u32()
		var driver := b.get_u32()
		var c: World.Creature = _mirror.get(id)
		if c == null:
			if not _dna_table.has(dna_id):
				continue # its DNA is still on the way; it shows up next snapshot
			c = World.Creature.new()
			c.id = id
			c.dna = _dna_table[dna_id]
			c.g = Genome.decode(c.dna)
			c.r = Genome.radius(c.g)
			c.pos = p
		c.vel = Vector2.from_angle(heading) * spd
		c.driver = driver
		_targets[id] = p
		seen[id] = c
		list.append(c)
	_mirror = seen
	world.creatures = list
	if b.get_u8() == 1:
		var foods: Array[World.Food] = []
		for i in b.get_u16():
			if i >= _food_pool.size():
				_food_pool.append(World.Food.new())
			var f := _food_pool[i]
			var x := b.get_u16()
			var y := b.get_u16()
			f.pos = Vector2(x / 65535.0 * World.WW, (y & 32767) / 32767.0 * World.WH)
			f.aq = y & 32768 != 0
			foods.append(f)
		world.foods = foods
	my_id = b.get_u32()
	var mine: World.Creature = _mirror.get(my_id)
	var e := b.get_float()
	var age := b.get_u16()
	var gen := b.get_u16()
	if mine != null:
		mine.e = e
		mine.age = age
		mine.gen = gen
	my_line = b.get_u16()
	my_blocked = b.get_utf8_string()
	# Recolour the terrain when the climate or the craters have moved on.
	var crater_sum := 0.0
	for cr in world.craters:
		crater_sum += cr[2]
	if absf(world.temp - _painted_temp) > 0.01 or absf(crater_sum - _painted_craters) > 0.15:
		_painted_temp = world.temp
		_painted_craters = crater_sum
		world.paint_terrain()


## Ease mirrored creatures toward their latest server positions between snapshots.
func _interpolate(delta: float) -> void:
	var k := 1.0 - exp(-delta * 12.0)
	for c in world.creatures:
		var t: Vector2 = _targets.get(c.id, c.pos)
		c.pos = t if c.pos.distance_squared_to(t) > 3600.0 else c.pos.lerp(t, k)
