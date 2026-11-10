extends Node
## Networking front-end (autoload `Net`). Wraps Godot's high-level multiplayer with ENet.
## Modes: "sp" (offline singleplayer), "host" (listen server), "client", "dedicated".

signal connected
signal failed(msg: String)
signal disconnected

var mode := ""
var player_name := "Soldier"
var map_id := "liekeblom"        # "liekeblom" or "yard"; the server tells joining clients which one
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
	if args.has("map"):
		map_id = str(args.map)
	# clients learn the map from the server before building the level
	multiplayer.peer_connected.connect(func(id):
		var ep := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if ep and ep.get_peer(id):
			ep.get_peer(id).set_timeout(32, 30000, 60000)   # tolerate long level loads without dropping
		if multiplayer.is_server() and ep:
			_server_info.rpc_id(id, map_id))
	multiplayer.connection_failed.connect(func(): failed.emit("Could not connect to server"); _reset())
	multiplayer.server_disconnected.connect(func(): disconnected.emit(); _reset())


@rpc("authority", "call_remote", "reliable")
func _server_info(m: String) -> void:
	map_id = m
	connected.emit.call_deferred()      # build the level outside the network callback


func is_dedicated() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	var dev_mode := args.has("autotest") or args.has("selftest") or args.has("shots") or args.has("join")
	return args.has("server") or DisplayServer.get_name() == "headless" and not dev_mode


func start_sp() -> void:
	_reset()
	mode = "sp"


func host(p: int) -> int:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, Defs.MAX_PLAYERS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_ZSTD)
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
	peer.host.compress(ENetConnection.COMPRESS_ZSTD)
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
