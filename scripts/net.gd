extends Node
## Networking front-end (autoload `Net`). Wraps Godot's high-level multiplayer with ENet.
## Modes: "sp" (offline singleplayer), "host" (listen server), "client", "dedicated".

signal connected
signal failed(msg: String)
signal disconnected

var mode := ""
var player_name := "Soldier"
var port := Defs.DEFAULT_PORT
var args := {}


func _ready() -> void:
	# Parse user command line args (everything after `--`).
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i]
		if k.begins_with("--"):
			var key := k.substr(2)
			if i + 1 < a.size() and not String(a[i + 1]).begins_with("--"):
				args[key] = a[i + 1]
				i += 1
			else:
				args[key] = true
		i += 1
	if args.has("port"):
		port = int(args.port)
	if args.has("name"):
		player_name = str(args.name)
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func(): failed.emit("Could not connect to server"); _reset())
	multiplayer.server_disconnected.connect(func(): disconnected.emit(); _reset())


func is_dedicated() -> bool:
	return args.has("server") or DisplayServer.get_name() == "headless" and not args.has("autotest") and not args.has("join")


func start_sp() -> void:
	_reset()
	mode = "sp"


func host(p: int) -> int:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, Defs.MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "host"
	port = p
	return OK


func dedicated(p: int) -> int:
	var err := host(p)
	mode = "dedicated"
	return err


func join(address: String, p: int) -> int:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, p)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	return OK


func leave() -> void:
	_reset()


func _reset() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
