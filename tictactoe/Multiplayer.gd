extends Node

# Multiplayer (WebSocket relay) singleton.
#
# Connects to a small relay server (see /relay_server) using Godot's built-in
# WebSocketPeer. The relay pairs two clients into a "room" identified by a
# short alphanumeric code; once paired, every message either side sends is
# forwarded verbatim to the other.
#
# Why a relay (and not e.g. ENet)? Two players on residential internet
# connections almost always sit behind NAT, which makes raw UDP painful.
# WebSockets ride on top of HTTPS, so any free hosting tier (Fly.io,
# Railway, Render) handles TLS, NAT, and reverse proxying for us. The
# total infrastructure footprint is one tiny Node.js process that does
# nothing but echo dictionaries between two sockets.
#
# This module preserves the public interface of the previous Steam-based
# Multiplayer autoload — same signal names, same method signatures — so
# Main.gd can stay unchanged.

signal hosting_started(lobby_id_str: String)
signal opponent_joined
signal join_succeeded
signal disconnected_from_lobby(reason: String)
signal message_received(data: Variant)
signal error_reported(msg: String)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# URL of your deployed relay server. Use wss:// (TLS) for any host that
# terminates HTTPS for you (Fly.io, Render, Railway, etc.). Use ws:// for
# local testing against `node server.js` on your own machine.
#
# The placeholder host below makes is_relay_configured() return false, which
# disables the Host/Join buttons until you point this at a real server.
const RELAY_URL := "wss://your-relay.example.com"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum ConnState { IDLE, CONNECTING, IN_ROOM_HOST, IN_ROOM_CLIENT }

var state: int = ConnState.IDLE
var room_code: String = ""
var is_host: bool = false

var _ws: WebSocketPeer = null
var _socket_open: bool = false
# What we want to do once the socket finishes opening: either "create" (host
# a room) or {"join": "<code>"} (join an existing room). Cleared after sent.
var _pending_action: Dictionary = {}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func _ready() -> void:
	# We only run _process while a socket is actually open. Idle is free.
	set_process(false)

# Returns true once the relay URL has been pointed at a real server.
# Main.gd uses this to gate the Host/Join buttons and surface a helpful
# message when it's still pointing at the placeholder.
func is_plugin_available() -> bool:
	return is_relay_configured()

func is_relay_configured() -> bool:
	# Crude but effective: any host containing "example.com" is the placeholder.
	return RELAY_URL != "" and not RELAY_URL.contains("example.com")

func is_connected_in_lobby() -> bool:
	return state == ConnState.IN_ROOM_HOST or state == ConnState.IN_ROOM_CLIENT

# Open a new room on the relay. Emits hosting_started(code) once the relay
# replies with the assigned room code, then opponent_joined() when a second
# client connects.
func host() -> void:
	if not is_relay_configured():
		error_reported.emit("Relay URL not configured. Edit RELAY_URL in Multiplayer.gd.")
		return
	if _ws != null:
		error_reported.emit("Already connected.")
		return
	_pending_action = {"type": "create"}
	_open_socket()

# Join an existing room by its code (case-insensitive). Emits join_succeeded()
# when the relay accepts the join.
func join(code_str: String) -> void:
	if not is_relay_configured():
		error_reported.emit("Relay URL not configured. Edit RELAY_URL in Multiplayer.gd.")
		return
	if _ws != null:
		error_reported.emit("Already connected.")
		return
	var cleaned := code_str.strip_edges().to_upper()
	if cleaned == "":
		error_reported.emit("Paste a room code first.")
		return
	_pending_action = {"type": "join", "code": cleaned}
	_open_socket()

# Disconnect from the relay (and the opponent, if any). Safe to call when
# already disconnected.
func leave() -> void:
	if _ws == null:
		_reset_state()
		return
	# Polite "I'm leaving" so the other side gets a clean disconnect message
	# instead of waiting for the socket close to register.
	if is_connected_in_lobby():
		_send_envelope({"type": "leave"})
	_ws.close()
	# Don't tear state down here — let _process see STATE_CLOSED and emit
	# disconnected_from_lobby once, so we go through a single code path.

# Send a JSON-serializable game message (e.g. {"t": "click", "i": 4}) to the
# opponent. No-op when not in a room.
func send(data: Variant) -> void:
	if not is_connected_in_lobby():
		return
	_send_envelope({"type": "msg", "data": data})

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _open_socket() -> void:
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(RELAY_URL)
	if err != OK:
		error_reported.emit("Connection failed (error %d)." % err)
		_ws = null
		_pending_action = {}
		return
	_socket_open = false
	state = ConnState.CONNECTING
	set_process(true)

func _send_envelope(envelope: Dictionary) -> void:
	if _ws == null:
		return
	_ws.send_text(JSON.stringify(envelope))

func _process(_delta: float) -> void:
	if _ws == null:
		set_process(false)
		return
	_ws.poll()
	var ready_state := _ws.get_ready_state()
	match ready_state:
		WebSocketPeer.STATE_OPEN:
			# First time we see STATE_OPEN, send the queued create/join.
			if not _socket_open:
				_socket_open = true
				if not _pending_action.is_empty():
					_send_envelope(_pending_action)
					_pending_action = {}
			while _ws.get_available_packet_count() > 0:
				var bytes: PackedByteArray = _ws.get_packet()
				_handle_packet(bytes.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			# Build the user-facing reason string. -1 / empty on most graceful
			# closes; surface those as "Disconnected." instead of cryptic codes.
			var msg: String
			if reason != "":
				msg = reason
			elif code != -1 and code != 1000 and code != 1005:
				msg = "Connection closed (code %d)." % code
			else:
				msg = "Disconnected."
			set_process(false)
			_reset_state()
			disconnected_from_lobby.emit(msg)

func _handle_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var t := str(parsed.get("type", ""))
	match t:
		"created":
			# Relay assigned us a room code and we're now waiting for a peer.
			room_code = str(parsed.get("code", ""))
			is_host = true
			state = ConnState.IN_ROOM_HOST
			hosting_started.emit(room_code)
		"joined":
			# We successfully joined an existing room.
			room_code = str(parsed.get("code", ""))
			is_host = false
			state = ConnState.IN_ROOM_CLIENT
			join_succeeded.emit()
		"opponent_joined":
			# Host-side notification that a second client entered our room.
			opponent_joined.emit()
		"msg":
			# A relayed game message from the opponent. Pass through verbatim.
			message_received.emit(parsed.get("data"))
		"opponent_left":
			# The relay tells us our peer dropped. Stay connected to the relay
			# (in case they reconnect), but surface the disconnect.
			disconnected_from_lobby.emit("Opponent left the room.")
			# Close the socket too — once a peer is gone, this room is dead;
			# the relay also tears the room down on its end.
			if _ws != null:
				_ws.close()
		"error":
			error_reported.emit(str(parsed.get("message", "Relay error.")))

func _reset_state() -> void:
	_ws = null
	_socket_open = false
	state = ConnState.IDLE
	room_code = ""
	is_host = false
	_pending_action = {}
