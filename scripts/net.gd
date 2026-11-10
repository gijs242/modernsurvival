extends Node
## Networking front-end (autoload `Net`). Wraps Godot's high-level multiplayer with ENet.
## Modes: "sp" (offline singleplayer), "host" (listen server), "client", "dedicated".

signal connected
signal failed(msg: String)
signal disconnected

var mode := ""
var player_name := "Soldier"
var map_id := "mall"             # "mall" or "yard"; the server tells joining clients which one
var difficulty := "regular"     # "recruit" / "regular" / "veteran"; chosen by the host
var port := Defs.DEFAULT_PORT
var args := {}

# ---- LAN discovery / server browser
## Servers broadcast a small status packet to BROWSE_PORT on the LAN every couple of seconds and answer
## "MSURV?" queries on (game port + 1), so the menu can list LAN games and ping recently joined servers.
const BROWSE_PORT := 7779
const MAGIC := "MSURV"
var _beacon: PacketPeerUDP        # server: answers queries, sends broadcasts
var _beacon_t := 0.0
var _browse: PacketPeerUDP        # client menu: listens for broadcasts and replies
var servers := {}                 # "ip:port" -> {info..., "seen": msec, "lan": bool}


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
	if args.has("difficulty"):
		difficulty = str(args.difficulty)
	# clients learn the map from the server before building the level
	multiplayer.peer_connected.connect(func(id):
		var ep := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if ep and ep.get_peer(id):
			ep.get_peer(id).set_timeout(32, 30000, 60000)   # tolerate long level loads without dropping
		if multiplayer.is_server() and ep:
			_server_info.rpc_id(id, map_id, difficulty))
	multiplayer.connection_failed.connect(func(): failed.emit("Could not connect to server"); _reset())
	multiplayer.server_disconnected.connect(func(): disconnected.emit(); _reset())


@rpc("authority", "call_remote", "reliable")
func _server_info(m: String, d := "regular") -> void:
	map_id = m
	difficulty = d
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
	_start_beacon()
	return OK


# ------------------------------------------------------------------ discovery: server side
func _start_beacon() -> void:
	_stop_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	if _beacon.bind(port + 1) != OK:
		push_warning("LAN discovery: could not bind UDP %d (queries disabled, broadcasts still sent)" % (port + 1))


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


func _status() -> Dictionary:
	var g = get_tree().root.get_node_or_null("Main/Game")
	var n := 0
	var w := 0
	var hostname := player_name
	if g:
		n = g.P.size()
		w = g.wave
		for p in g.P.values():
			if p.id == 1:
				hostname = p.name
	if is_dedicated():
		hostname = str(args.get("server_name", "Dedicated server"))
	return {"m": MAGIC, "n": hostname, "map": map_id, "d": difficulty, "p": n, "max": Defs.MAX_PLAYERS, "port": port, "w": w}


func _process(dt: float) -> void:
	if _beacon:
		# answer queries
		while _beacon.get_available_packet_count() > 0:
			var pkt := _beacon.get_packet().get_string_from_utf8()
			var ip := _beacon.get_packet_ip()
			var from_port := _beacon.get_packet_port()
			if pkt.begins_with(MAGIC + "?") and ip != "":
				_beacon.set_dest_address(ip, from_port)
				_beacon.put_packet(JSON.stringify(_status()).to_utf8_buffer())
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 2.0
			var data := JSON.stringify(_status()).to_utf8_buffer()
			for dest in ["255.255.255.255", "127.0.0.1"]:
				_beacon.set_dest_address(dest, BROWSE_PORT)
				_beacon.put_packet(data)
	if _browse:
		while _browse.get_available_packet_count() > 0:
			var raw := _browse.get_packet().get_string_from_utf8()
			var ip := _browse.get_packet_ip()
			var info = JSON.parse_string(raw)
			if ip in IP.get_local_addresses():
				ip = "127.0.0.1"             # same machine: one entry, however it reached us
			if info is Dictionary and info.get("m", "") == MAGIC:
				var key := "%s:%d" % [ip, int(info.get("port", Defs.DEFAULT_PORT))]
				info["ip"] = ip
				info["seen"] = Time.get_ticks_msec()
				servers[key] = info
		for k in servers.keys():
			if Time.get_ticks_msec() - int(servers[k].seen) > 6500:
				servers.erase(k)


# ------------------------------------------------------------------ discovery: client side
func start_browsing() -> void:
	if _browse:
		return
	_browse = PacketPeerUDP.new()
	if _browse.bind(BROWSE_PORT) != OK:
		_browse.bind(0)               # another copy already listens here: we can still query servers directly
	servers.clear()


func stop_browsing() -> void:
	if _browse:
		_browse.close()
		_browse = null


## Ask a server (e.g. one you joined before) for its status; the answer shows up in `servers`.
func query(address: String, p: int) -> void:
	if _browse == null or address == "":
		return
	var ip := address if address.is_valid_ip_address() else IP.resolve_hostname(address, IP.TYPE_IPV4)
	if ip == "":
		return
	_browse.set_dest_address(ip, p + 1)
	_browse.put_packet((MAGIC + "?").to_utf8_buffer())


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
	_stop_beacon()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
