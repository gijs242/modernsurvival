class_name GameState
extends Node3D
## Game session, part 1 of 5: shared state and small helpers. The chain is
## GameState -> GameCombat -> GameWaves -> GameSync -> Game (game.gd); each file only uses what is below it.

signal game_over(stats: Array, wave: int)
var is_server := false
var local_id := 1
var quality := 2
var map: GameMap
var fx: Effects
var hud: Hud
var players_root: Node3D
var enemies_root: Node3D
var objects_root: Node3D
var player_nodes := {}       # peer id -> Player
var enemies := {}            # id -> Enemy
var dying := {}              # id -> Enemy killed this tick (server), consumed by the kill event
var me := {}                 # my state from the latest snapshot
var snap := {}               # latest snapshot
var time := 0.0
# ---- server state
var P := {}                  # peer id -> state dict
var wave := 0
var cleared := 0
var diff: Dictionary = Defs.DIFFICULTY.regular
var diff_id := "regular"
var special := ""            # special wave type: "", "night", "smoke", "rushers", "snipers"
var modifiers: Array = []    # endless-mode modifiers: "armored", "volatile"
var state := "inter"
var timer := 15.0
var spawn_queue: Array = []
var spawn_t := 0.0
var next_id := 1
var projectiles := {}        # id -> {k, pos, vel, fuse, owner}
var mines := {}
var turrets := {}
var drones := {}
var strikes: Array = []
var helis := {}              # id -> enemy transport helicopter
var glass_broken := {}       # map glass pane id -> true
var lights_out := {}         # map light id -> true
var power := true            # mall lights on (night waves cut it)
var wave_t := 0.0
var cut_at := -1.0           # seconds into the wave when the power goes (night waves, some late waves)
var lasers := {}             # client: enemy id -> {pid, t, node}
var nade_cd := 0.0           # global spacing between enemy grenades
var nades_thrown := 0
var approach := -1           # index into map.spawns the next wave mostly comes from (announced by a convoy)
var convoy_sent := false
var events: Array = []
var snap_t := 0.0
var _snap_n := 0
# ---- client-side visuals for objects
var obj_nodes := {}
## This player's own numbers for the end-of-run summary (client side: shots and hits are only known here).
var local_stats := {}
## Alive players / enemy list, built once per physics tick (every enemy asks for them every tick).
var _alive_cache: Array = []
var _alive_frame := -1
var _enemy_list: Array = []
var _enemy_frame := -1


func reset_local_stats() -> void:
	local_stats = {"shots": 0, "hits": 0, "kills_w": {}, "best_combo": 0, "start": Time.get_ticks_msec()}          # "kind:id" -> Node3D


func ev(e: Dictionary) -> void:
	events.append(e)


func _unlocked(item: Dictionary) -> bool:
	return cleared >= item.after


func enemy_list() -> Array:
	var f := Engine.get_physics_frames()
	if f != _enemy_frame:
		_enemy_frame = f
		_enemy_list = enemies.values()
	return _enemy_list


func _alive_players() -> Array:
	var f := Engine.get_physics_frames()
	if f == _alive_frame:
		return _alive_cache
	_alive_frame = f
	var out := []
	for id in P:
		var p: Dictionary = P[id]
		if not p.dead and not p.downed:
			out.append(p)
	_alive_cache = out
	return out


func _add_projectile(k: String, o: Vector3, v: Vector3, fuse: float, owner: int) -> void:
	projectiles[next_id] = {"k": k, "pos": o, "vel": v, "fuse": fuse, "owner": owner}
	next_id += 1


func _add_strike(center: Vector3, ang: float, delay: float, owner: int, count: int, spacing: float) -> void:
	strikes.append({"pos": center, "ang": ang, "t": delay, "n": 0, "count": count, "spacing": spacing, "gap": 0.0, "owner": owner})
	ev({"t": "strike_mark", "pos": center, "ang": ang, "delay": delay, "len": count * spacing})


## How far enemies can see a player (reduced in smoke waves).
func sight_range() -> float:
	return 22.0 if special == "smoke" else 70.0


func _blocked(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Defs.L_WORLD)
	return not space.intersect_ray(q).is_empty()


## Remote peers that have finished loading the map and joined (only they receive game traffic;
## sending to a peer still building the level breaks Godot's RPC path cache for that node).
func _remote_joined() -> Array:
	var out := []
	var peers := multiplayer.get_peers()
	for id in P:
		if id != local_id and id in peers:
			out.append(id)
	return out


func _pname(id: int) -> String:
	for ps in snap.get("players", []):
		if ps.id == id:
			return ps.n
	return "Soldier"
