extends Node

signal player_list_changed
signal connection_succeeded
signal connection_failed(reason: String)
signal game_found(info: Dictionary)
signal relay_ready
signal rooms_listed(rooms: Array)

const GAME_PORT      := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS    := 4
# Set to your deployed relay URL (e.g. "wss://hellbreaker-relay.onrender.com").
# Leave empty to disable relay and use LAN-direct mode only.
const RELAY_URL      := "wss://hellbreaker-relay.tomko.dk"

# Base-62 alphabet — encodes a full IPv4 address into exactly 6 chars
const _B62 := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

var local_name:    String = ""
var room_code:     String = ""
var local_ip:      String = ""
var friendly_fire: bool   = false
# peer_id (int) → { "name": String }
var players: Dictionary = {}

var _is_hosting  := false
var _broadcaster : PacketPeerUDP     # desktop-only LAN discovery
var _listener    : PacketPeerUDP
var _bcast_timer := 0.0
var _is_web      := false
var _relay_peer  : RelayPeer = null  # kept alive while relay session active


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Host / Join ───────────────────────────────────────────────────────────────

func host_game(player_name: String) -> Error:
	local_name = player_name
	local_ip   = _get_lan_ip()
	room_code  = _ip_to_code(local_ip)

	var ws  := WebSocketMultiplayerPeer.new()
	var err := ws.create_server(GAME_PORT)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = ws
	_is_hosting = true
	players[1]  = {name = player_name}
	player_list_changed.emit()

	if not _is_web:
		_start_broadcast()
	return OK


func join_game(player_name: String, code_or_ip: String) -> Error:
	local_name = player_name
	var ip     := _resolve_entry(code_or_ip)
	if ip.is_empty():
		return ERR_INVALID_PARAMETER

	var ws  := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [ip, GAME_PORT]
	var err := ws.create_client(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = ws
	return OK


func disconnect_all() -> void:
	_stop_broadcast()
	stop_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_relay_peer    = null
	players.clear()
	_is_hosting    = false
	local_name     = ""
	room_code      = ""
	local_ip       = ""
	friendly_fire  = false


func set_friendly_fire(enabled: bool) -> void:
	friendly_fire = enabled
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_friendly_fire.rpc(enabled)


@rpc("authority", "reliable")
func _sync_friendly_fire(enabled: bool) -> void:
	friendly_fire = enabled


# ── Relay (internet) ──────────────────────────────────────────────────────────

func host_game_relay(player_name: String, public_room: bool = true) -> Error:
	local_name  = player_name
	_relay_peer = RelayPeer.new()
	_relay_peer.peer_info.connect(_on_relay_info)
	print("[Relay] Connecting to: ", RELAY_URL)
	var err := _relay_peer.open(RELAY_URL, true, "", public_room, player_name)
	if err != OK:
		_relay_peer = null
		return err
	multiplayer.multiplayer_peer = _relay_peer
	_is_hosting = true
	players[1]  = {name = player_name}
	player_list_changed.emit()
	return OK


func join_game_relay(player_name: String, relay_code: String) -> Error:
	local_name  = player_name
	_relay_peer = RelayPeer.new()
	_relay_peer.peer_info.connect(_on_relay_info)
	var err := _relay_peer.open(RELAY_URL, false, relay_code)
	if err != OK:
		_relay_peer = null
		return err
	multiplayer.multiplayer_peer = _relay_peer
	return OK


func list_relay_rooms() -> void:
	if RELAY_URL.is_empty():
		rooms_listed.emit([])
		return
	_fetch_relay_rooms()


func _fetch_relay_rooms() -> void:
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(RELAY_URL) != OK:
		rooms_listed.emit([])
		return
	var sent := false
	for _i in range(100):
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not sent:
				ws.send_text(JSON.stringify({"role": "list"}))
				sent = true
			while ws.get_available_packet_count() > 0:
				var raw := ws.get_packet()
				if ws.was_string_packet():
					var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
					if parsed is Dictionary and (parsed as Dictionary).get("type") == "rooms":
						ws.close()
						rooms_listed.emit((parsed as Dictionary).get("rooms", []))
						return
		elif state == WebSocketPeer.STATE_CLOSED:
			break
		await get_tree().create_timer(0.05).timeout
	ws.close()
	rooms_listed.emit([])


func _on_relay_info(data: Dictionary) -> void:
	match data.get("type", ""):
		"room_code":
			room_code = data.get("code", "")
			relay_ready.emit()
		"error":
			var msg: String = data.get("msg", "Relay error")
			if not _is_hosting:
				connection_failed.emit(msg)


# ── LAN Discovery (desktop only) ──────────────────────────────────────────────

func start_discovery() -> void:
	if _is_web:
		return
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_discovery() -> void:
	if is_instance_valid(_listener):
		_listener.close()
	_listener = null


# ── _process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _is_hosting and is_instance_valid(_broadcaster):
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.5
			_send_announce()
	if is_instance_valid(_listener):
		_poll_listener()


# ── UDP Broadcast (desktop host → LAN) ───────────────────────────────────────

func _start_broadcast() -> void:
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.bind(0)
	_bcast_timer = 0.0


func _stop_broadcast() -> void:
	if is_instance_valid(_broadcaster):
		_broadcaster.close()
	_broadcaster = null
	_is_hosting = false


func _send_announce() -> void:
	var payload := JSON.stringify({
		"host":    local_name,
		"code":    room_code,
		"players": players.size(),
		"max":     MAX_PLAYERS
	})
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcaster.put_packet(payload.to_utf8_buffer())


func _poll_listener() -> void:
	while _listener.get_available_packet_count() > 0:
		var raw    := _listener.get_packet()
		var ip     := _listener.get_packet_ip()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			var info: Dictionary = parsed
			info["address"] = ip
			game_found.emit(info)


# ── Room Code ─────────────────────────────────────────────────────────────────

# Encode a dotted-quad IPv4 string into 6 base-62 characters.
func _ip_to_code(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return "000000"
	var n: int = (parts[0].to_int() << 24) \
			   | (parts[1].to_int() << 16) \
			   | (parts[2].to_int() <<  8) \
			   |  parts[3].to_int()
	var code := ""
	for _i in range(6):
		code = _B62[n % 62] + code
		n /= 62
	return code


# Decode 6 base-62 characters back to a dotted-quad IP.
func _code_to_ip(code: String) -> String:
	if code.length() != 6:
		return ""
	var n: int = 0
	for ch in code:
		var idx := _B62.find(ch)
		if idx < 0:
			return ""
		n = n * 62 + idx
	var a := (n >> 24) & 0xFF
	var b := (n >> 16) & 0xFF
	var c := (n >>  8) & 0xFF
	var d :=  n        & 0xFF
	return "%d.%d.%d.%d" % [a, b, c, d]


# Accept either a 6-char room code or a raw IP / ws:// URL.
func _resolve_entry(entry: String) -> String:
	var s := entry.strip_edges()
	if s.length() == 6 and not s.contains("."):
		return _code_to_ip(s)
	# strip ws:// prefix if someone pastes the URL
	if s.begins_with("ws://"):
		s = s.substr(5).split(":")[0]
	return s


# Pick the best LAN IP (prefer 192.168.x.x, then 10.x, then any non-loopback).
func _get_lan_ip() -> String:
	var addrs := IP.get_local_addresses()
	var best  := ""
	for addr: String in addrs:
		if addr.begins_with("127.") or addr.contains(":"):
			continue   # skip loopback and IPv6
		if addr.begins_with("192.168."):
			return addr
		if addr.begins_with("10.") or addr.begins_with("172."):
			best = addr
		elif best.is_empty():
			best = addr
	return best


# ── Multiplayer signals ───────────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()
	if multiplayer.is_server():
		_sync_player_list.rpc(players)


func _on_connected_to_server() -> void:
	register_player.rpc_id(1, local_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit("Connection refused or timed out.")


func _on_server_disconnected() -> void:
	disconnect_all()


# ── RPCs ──────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = {name = player_name}
	player_list_changed.emit()
	_sync_player_list.rpc(players)


@rpc("authority", "reliable")
func _sync_player_list(all_players: Dictionary) -> void:
	players = all_players
	player_list_changed.emit()
