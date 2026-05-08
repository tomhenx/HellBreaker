class_name RelayPeer
extends MultiplayerPeerExtension

## Bridges Godot's MultiplayerAPI to relay_server.py over WebSocket.
## Protocol:
##   Client → Relay : [target:4 LE][payload...]
##   Relay → Client : [source:4 LE][payload...]   (data)
##                    [0xFF][type:1][peer_id:4 LE] (system, 6 bytes)

signal peer_info(data: Dictionary)

const SYS_MAGIC   := 0xFF
const SYS_ADDED   := 0
const SYS_REMOVED := 1
const SYS_MY_ID   := 2

var _ws             := WebSocketPeer.new()
var _is_host        := false
var _room_code      := ""
var _my_id          := 0
var _target         := 0
var _sent_handshake := false
var _conn_status    := MultiplayerPeer.CONNECTION_DISCONNECTED

var _in_queue:     Array      = []   # Array of {data: PackedByteArray, source: int}
var _known_peers:  Dictionary = {}   # pid → true, tracks announced peers


var _public_room: bool   = true
var _host_name:   String = ""


func open(url: String, is_host: bool, room_code: String = "", public_room: bool = true, host_name: String = "") -> Error:
	_is_host        = is_host
	_room_code      = room_code.to_upper().strip_edges()
	_public_room    = public_room
	_host_name      = host_name
	_conn_status    = MultiplayerPeer.CONNECTION_CONNECTING
	_sent_handshake = false
	_in_queue.clear()
	_known_peers.clear()
	_my_id = 0
	var err := _ws.connect_to_url(url)
	if err != OK:
		_conn_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	return err


# ── Polling ───────────────────────────────────────────────────────────────────

func _poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		print("[RelayPeer] WebSocket closed. Code: ", _ws.get_close_code(), " Reason: ", _ws.get_close_reason())
		_conn_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if not _sent_handshake:
		_sent_handshake = true
		var msg: Dictionary
		if _is_host:
			msg = {"role": "host", "public": _public_room, "name": _host_name}
		else:
			msg = {"role": "client", "code": _room_code}
		_ws.send_text(JSON.stringify(msg))
	while _ws.get_available_packet_count() > 0:
		var raw  := _ws.get_packet()
		var text := _ws.was_string_packet()
		_handle_packet(raw, text)


func _handle_packet(raw: PackedByteArray, is_text: bool) -> void:
	if is_text:
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			var d := parsed as Dictionary
			peer_info.emit(d)
			if d.get("type") == "error":
				_conn_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return
	if raw.size() < 1:
		return
	# System packet: [0xFF][type:1][peer_id:4LE] = 6 bytes
	if raw[0] == SYS_MAGIC:
		if raw.size() >= 6:
			_handle_sys(int(raw[1]), raw.decode_s32(2))
		return
	# Data packet: [source:4LE][payload...]
	if raw.size() >= 4:
		var source := raw.decode_u32(0) as int
		# Defensive: register peer immediately if their data arrives before SYS_ADDED
		if source > 0 and not _known_peers.has(source):
			_known_peers[source] = true
			peer_connected.emit(source)
		_in_queue.append({"data": raw.slice(4), "source": source})


func _handle_sys(type: int, pid: int) -> void:
	match type:
		SYS_MY_ID:
			_my_id = pid
			_conn_status = MultiplayerPeer.CONNECTION_CONNECTED
		SYS_ADDED:
			if not _known_peers.has(pid):
				_known_peers[pid] = true
				peer_connected.emit(pid)
		SYS_REMOVED:
			_known_peers.erase(pid)
			peer_disconnected.emit(pid)


# ── MultiplayerPeerExtension overrides ───────────────────────────────────────

func _close() -> void:
	_ws.close()
	_conn_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
	pass


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_packet_peer() -> int:
	if _in_queue.is_empty():
		return 0
	return int((_in_queue[0] as Dictionary).get("source", 0))


func _get_available_packet_count() -> int:
	return _in_queue.size()


func _get_packet_script() -> PackedByteArray:
	if _in_queue.is_empty():
		return PackedByteArray()
	var pkt  := _in_queue.pop_front() as Dictionary
	var data : Variant = pkt.get("data")
	return data as PackedByteArray if data is PackedByteArray else PackedByteArray()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var hdr := PackedByteArray()
	hdr.resize(4)
	hdr.encode_u32(0, max(0, _target))
	return _ws.send(hdr + buffer)


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _conn_status as MultiplayerPeer.ConnectionStatus


func _get_unique_id() -> int:
	return _my_id


func _is_server() -> bool:
	return _my_id == 1


func _is_server_relay_supported() -> bool:
	return false


func _get_max_packet_size() -> int:
	return 65536


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_transfer_channel(_ch: int) -> void:
	pass


func _set_transfer_mode(_mode: MultiplayerPeer.TransferMode) -> void:
	pass


func _set_refuse_new_connections(_enable: bool) -> void:
	pass
