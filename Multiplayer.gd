extends Node

# Multiplayer (Steam) singleton.
#
# Wraps the GodotSteam plugin (https://github.com/GodotSteam/GodotSteam) to
# provide a simple host/join lobby flow and a reliable message channel for
# the Tic Tac Toe game. The plugin is OPTIONAL: if it isn't installed the
# game still runs fine in local-only mode; this node just reports that
# multiplayer is unavailable.
#
# Communication uses Steam lobbies and Steam's lobby chat messages as a
# reliable string transport. Game messages are JSON-encoded dictionaries.
#
# All Steam API calls go through dynamic dispatch (via
# Engine.get_singleton("Steam")) so that this file still parses and runs
# even when the plugin binaries aren't present.

signal hosting_started(lobby_id_str: String)
signal opponent_joined
signal join_succeeded
signal disconnected_from_lobby(reason: String)
signal message_received(data: Variant)
signal error_reported(msg: String)

enum ConnState { IDLE, HOSTING_WAITING, IN_LOBBY_HOST, CONNECTING, IN_LOBBY_CLIENT }

# Steam constants (copied from the Steamworks SDK so we don't depend on
# the plugin being present at parse time).
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_TYPE_PUBLIC := 2
const LOBBY_ENTER_SUCCESS := 1
const CHAT_MEMBER_STATE_ENTERED := 0x0001
const CHAT_MEMBER_STATE_LEFT := 0x0002
const CHAT_MEMBER_STATE_DISCONNECTED := 0x0004
const CHAT_MEMBER_STATE_KICKED := 0x0008
const CHAT_MEMBER_STATE_BANNED := 0x0010

var state: int = ConnState.IDLE
var lobby_id: int = 0
var my_steam_id: int = 0
var opponent_id: int = 0
var is_host: bool = false

var _steam: Object = null
var _initialized: bool = false
var _signals_wired: bool = false

func _ready() -> void:
	set_process(false)

func is_plugin_available() -> bool:
	return Engine.has_singleton("Steam")

func is_connected_in_lobby() -> bool:
	return state == ConnState.IN_LOBBY_HOST or state == ConnState.IN_LOBBY_CLIENT

# Lazily fetch the Steam singleton if the plugin is installed.
func _get_steam() -> Object:
	if _steam != null:
		return _steam
	if not Engine.has_singleton("Steam"):
		return null
	_steam = Engine.get_singleton("Steam")
	return _steam

# Initialize the Steam client. Safe to call repeatedly — it's a no-op
# after the first successful init. Returns "" on success or an error string
# describing what went wrong.
func initialize() -> String:
	if _initialized:
		return ""
	var s: Object = _get_steam()
	if s == null:
		return "GodotSteam plugin is not installed. See SETUP_STEAM.md."
	# The init method name has varied between GodotSteam versions. Try the
	# newer one first, then fall back.
	var result: Variant = null
	if s.has_method("steamInitEx"):
		result = s.steamInitEx(false, 480)
	elif s.has_method("steamInit"):
		result = s.steamInit()
	else:
		return "Unsupported GodotSteam version: no steamInit method."
	var ok := _init_result_ok(result)
	if not ok.success:
		return "Steam init failed: " + ok.message
	_initialized = true
	if s.has_method("getSteamID"):
		my_steam_id = int(s.getSteamID())
	_wire_signals(s)
	set_process(true)
	return ""

# Normalize the various return shapes of steamInit[Ex] across versions.
func _init_result_ok(result: Variant) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY:
		var status := int(result.get("status", 1))
		var verbal := str(result.get("verbal", ""))
		return {"success": status == 0, "message": verbal}
	if typeof(result) == TYPE_INT:
		return {"success": int(result) == 0, "message": "code %d" % int(result)}
	if typeof(result) == TYPE_BOOL:
		return {"success": bool(result), "message": ""}
	# If the method didn't return anything explicit, assume it worked —
	# Steam will error out later via signals if it actually failed.
	return {"success": true, "message": ""}

func _wire_signals(s: Object) -> void:
	if _signals_wired:
		return
	s.connect("lobby_created", _on_lobby_created)
	s.connect("lobby_joined", _on_lobby_joined)
	s.connect("lobby_chat_update", _on_lobby_chat_update)
	s.connect("lobby_message", _on_lobby_message)
	_signals_wired = true

func _process(_delta: float) -> void:
	var s: Object = _get_steam()
	if s == null:
		return
	# Pump Steam callbacks every frame. Some plugin builds pump
	# automatically, others don't — calling it twice is harmless.
	if s.has_method("run_callbacks"):
		s.run_callbacks()
	elif s.has_method("runCallbacks"):
		s.runCallbacks()

# Create a friends-only lobby and wait for a second player. Emits
# `hosting_started(lobby_id_str)` when the lobby is ready.
func host() -> void:
	var err := initialize()
	if err != "":
		error_reported.emit(err)
		return
	var s: Object = _get_steam()
	s.createLobby(LOBBY_TYPE_FRIENDS_ONLY, 2)
	state = ConnState.HOSTING_WAITING

# Join an existing lobby by its numeric Steam lobby ID (as a string).
func join(lobby_id_str: String) -> void:
	var err := initialize()
	if err != "":
		error_reported.emit(err)
		return
	var cleaned := lobby_id_str.strip_edges()
	if cleaned == "":
		error_reported.emit("Paste a lobby ID first.")
		return
	if not cleaned.is_valid_int():
		error_reported.emit("Lobby ID must be numeric.")
		return
	var parsed := cleaned.to_int()
	if parsed == 0:
		error_reported.emit("Invalid lobby ID.")
		return
	var s: Object = _get_steam()
	s.joinLobby(parsed)
	state = ConnState.CONNECTING

# Leave the current lobby, if any.
func leave() -> void:
	var s: Object = _get_steam()
	if s != null and lobby_id != 0 and s.has_method("leaveLobby"):
		s.leaveLobby(lobby_id)
	var was_connected := is_connected_in_lobby() or state == ConnState.HOSTING_WAITING
	lobby_id = 0
	opponent_id = 0
	is_host = false
	state = ConnState.IDLE
	if was_connected:
		disconnected_from_lobby.emit("Left lobby")

# Send a JSON-serializable dictionary to the other player. No-op if not
# currently in a lobby.
func send(data: Variant) -> void:
	if not is_connected_in_lobby():
		return
	var s: Object = _get_steam()
	if s == null:
		return
	var payload := JSON.stringify(data)
	s.sendLobbyChatMsg(lobby_id, payload)

# ---------------------------------------------------------------------------
# Steam signal callbacks
# ---------------------------------------------------------------------------

func _on_lobby_created(connect_result: Variant, new_lobby_id: Variant) -> void:
	if int(connect_result) != 1:
		error_reported.emit("Failed to create Steam lobby (code %s)." % str(connect_result))
		state = ConnState.IDLE
		return
	lobby_id = int(new_lobby_id)
	is_host = true
	state = ConnState.IN_LOBBY_HOST
	hosting_started.emit(str(lobby_id))

func _on_lobby_joined(joined_lobby_id: Variant, _perms: Variant, _locked: Variant, response: Variant) -> void:
	if int(response) != LOBBY_ENTER_SUCCESS:
		error_reported.emit("Failed to join lobby (code %s)." % str(response))
		state = ConnState.IDLE
		return
	lobby_id = int(joined_lobby_id)
	var s: Object = _get_steam()
	if s != null and s.has_method("getLobbyOwner"):
		opponent_id = int(s.getLobbyOwner(lobby_id))
	is_host = false
	state = ConnState.IN_LOBBY_CLIENT
	join_succeeded.emit()

func _on_lobby_chat_update(the_lobby: Variant, changed_id: Variant, _maker_id: Variant, chat_state: Variant) -> void:
	if int(the_lobby) != lobby_id:
		return
	var cs := int(chat_state)
	var changed := int(changed_id)
	if cs & CHAT_MEMBER_STATE_ENTERED:
		# Someone joined. For the host, that's the opponent arriving.
		if is_host and changed != my_steam_id:
			opponent_id = changed
			opponent_joined.emit()
	elif cs & (CHAT_MEMBER_STATE_LEFT | CHAT_MEMBER_STATE_DISCONNECTED | CHAT_MEMBER_STATE_KICKED | CHAT_MEMBER_STATE_BANNED):
		if changed != my_steam_id:
			disconnected_from_lobby.emit("Opponent left the lobby.")
			lobby_id = 0
			opponent_id = 0
			is_host = false
			state = ConnState.IDLE

func _on_lobby_message(the_lobby: Variant, user: Variant, message: Variant, _chat_type: Variant) -> void:
	if int(the_lobby) != lobby_id:
		return
	# Ignore echo of our own messages (Steam sometimes delivers them).
	if int(user) == my_steam_id:
		return
	var text: String
	if message is PackedByteArray:
		text = (message as PackedByteArray).get_string_from_utf8()
	else:
		text = str(message)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return
	message_received.emit(parsed)
