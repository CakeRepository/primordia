extends Node
## How this run of the game was started (autoload "Launch"). The menu fills it in; the command
## line can too, which is how people run servers:
##   godot --headless --path . -- --server [--port 24565] [--seed 42] [--name "My world"] [--world mine]
##   godot --path . -- --join 192.168.1.20[:24565] [--name Alice]
##   godot --path . -- --host [--port 24565] [--seed 42] [--name Alice]
##   godot --path . -- --solo [--seed 42]

const DEFAULT_PORT := Session.DEFAULT_PORT

var mode := "solo" # solo | host | join | dedicated
var seed := 0 # 0 = a random world
var port := DEFAULT_PORT
var address := "127.0.0.1"
var player_name := "Player"
var server_name := ""
var world_name := "" # dedicated servers: load and keep saving this world
var from_cli := false # started straight into a game from the command line


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var next: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--server", "--dedicated":
				mode = "dedicated"
				from_cli = true
			"--host":
				mode = "host"
				from_cli = true
			"--solo":
				mode = "solo"
				from_cli = true
			"--join":
				mode = "join"
				from_cli = true
				set_address(next)
				i += 1
			"--port":
				port = clampi(next.to_int(), 1, 65535)
				i += 1
			"--seed":
				seed = next.to_int()
				i += 1
			"--world":
				world_name = next
				i += 1
			"--name":
				player_name = next
				server_name = next
				i += 1
		i += 1


## "host" or "host:port".
func set_address(text: String) -> void:
	var t := text.strip_edges()
	if t.contains(":"):
		address = t.get_slice(":", 0)
		port = clampi(t.get_slice(":", 1).to_int(), 1, 65535)
	elif t != "":
		address = t


## A seed typed by a person: a number is used as is, any other text is hashed, blank is random.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return t.to_int()
	return t.hash()
