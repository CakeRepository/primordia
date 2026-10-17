class_name Lan
extends Node
## LAN server discovery, like Minecraft's "Open to LAN". A server broadcasts a small JSON
## beacon once a second; the join menu listens and lists what it hears.

const PORT := 24566
const GAME := "primordia"

var servers := {} # server id -> beacon dictionary plus "address" and "seen" (msec)

var _udp: PacketPeerUDP
var _beacon: Callable # server side: returns the beacon dictionary
var _t := 0.0


## Start broadcasting. `beacon` is called each time and returns what to announce.
func announce(beacon: Callable) -> void:
	_beacon = beacon
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)


## Start listening for beacons. False if the port is taken (another listener on this machine).
func listen() -> bool:
	_udp = PacketPeerUDP.new()
	return _udp.bind(PORT) == OK


func _process(delta: float) -> void:
	if _udp == null:
		return
	if _beacon.is_valid():
		_t += delta
		if _t >= 1.0:
			_t = 0.0
			var msg := JSON.stringify(_beacon.call()).to_utf8_buffer()
			# Broadcast for the LAN, plus loopback for a client on this same machine.
			for addr in ["255.255.255.255", "127.0.0.1"]:
				_udp.set_dest_address(addr, PORT)
				_udp.put_packet(msg)
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var info = JSON.parse_string(pkt.get_string_from_utf8())
		if info is Dictionary and info.get("game") == GAME and info.has("id") and info.has("port"):
			info["address"] = ip
			info["seen"] = Time.get_ticks_msec()
			servers[str(info["id"])] = info
	for id in servers.keys():
		if Time.get_ticks_msec() - servers[id]["seen"] > 5000:
			servers.erase(id)


func _exit_tree() -> void:
	if _udp != null:
		_udp.close()
