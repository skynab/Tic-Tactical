extends Control

# Generalized to an M x N (cols x rows) board with a configurable "k in a
# row" win length. Three grid modes are selectable from the UI:
#   - "3x3"  : 3x3 board, 3-in-a-row (classic).
#   - "4x4"  : 4x4 board, 4-in-a-row plus 2x2 squares and diamonds
#              (four matching marks surrounding a center cell).
#   - "MNK"  : user-chosen columns (M), rows (N), and line length (K).
#              Pure k-in-a-row (horizontal, vertical, or diagonal), matching
#              the m,n,k-game definition on Wikipedia.
#
# Those are what each mode *seeds*, not a fixed rule set. Win conditions are
# configurable shapes carrying point values — k-in-a-row, four corners, any N
# side squares, 2x2 squares, diamonds — built by GameLogic.build_patterns from
# `pattern_config`. Two round rules use them (see the WinMode enum): classic
# "first completed condition wins", or "first to N points wins", where each
# completed condition banks its points and play continues.
#
# Board is a flat array of length grid_cols * grid_rows, row-major.
# Cell index at column c, row r is `r * grid_cols + c`.
# 0 = empty, 1 = X, 2 = O.
const CellScript = preload("res://Cell.gd")

# Smallest window we'll shrink to when fitting the desktop. Below this the UI
# scales down to the point of being unusable, so it's better to let the window
# run off a truly tiny screen than to keep shrinking. Also used as the window's
# min_size so the user can't drag it smaller.
const MIN_WINDOW_SIZE := Vector2i(400, 500)

# Breathing space left around the window when shrinking it to fit the screen,
# on top of whatever the title bar and borders take.
const SCREEN_FIT_MARGIN := 24

# Use non-negative IDs so OptionButton.add_item(label, id) honors them.
# add_item treats id == -1 as "auto-assign based on item index", which
# silently breaks equality checks against get_selected_id().
enum GridMode { THREE = 3, FOUR = 4, MNK = 5 }

# "Arrow Bonus" mode — controls where (if anywhere) ★ bonus markers spawn
# at the start of each new game. OFF disables the feature entirely;
# CORNERS places a ★ on each of the four corner cells (the classic
# behavior); RANDOM gives every cell an independent 25% chance of being
# armed. Future modes (Center, Edges, …) slot in here.
enum BonusMode { OFF = 0, CORNERS = 1, RANDOM = 2 }

# How a round is decided.
#   FIRST  — classic: the first completed win condition ends the round
#            immediately, whatever it's worth.
#   POINTS — every completed win condition banks its point value and play
#            continues; the first player to reach `points_target` wins.
enum WinMode { FIRST = 0, POINTS = 1 }

var grid_cols := 3   # M
var grid_rows := 3   # N
var win_length := 3  # K
var grid_mode: int = GridMode.THREE
var board: Array = []
var current_player := 1
var game_over := false
var scores := {1: 0, 2: 0, "draw": 0}

# Per-player arrow-click budget. Each player gets `max_shifts` uses per game.
# Configured via the SpinBox in the UI. Applies on the next New Game.
var max_shifts := 3
var shifts_left := {1: 3, 2: 3}

# Scored win conditions for the current board, rebuilt whenever the board
# dimensions, win length, or the pattern config change. Each entry is a
# Dictionary from GameLogic.make_pattern — cells plus a point value.
var win_patterns: Array = []

# Which win conditions are in play and what each is worth. Mirrors the
# checkboxes + point spinboxes in the New Game dialog; consumed by
# GameLogic.build_patterns. Defaults reproduce the classic game: only
# k-in-a-row counts.
var pattern_config: Dictionary = {
	GameLogic.KIND_LINE: {"enabled": true, "points": 3},
	GameLogic.KIND_CORNERS: {"enabled": false, "points": 2},
	GameLogic.KIND_EDGES: {"enabled": false, "points": 1, "count": 3},
	GameLogic.KIND_SQUARE: {"enabled": false, "points": 2},
	GameLogic.KIND_DIAMOND: {"enabled": false, "points": 2},
}

# Round-decision rule and, for WinMode.POINTS, the score needed to take it.
var win_mode: int = WinMode.FIRST
var points_target := 5

# Points banked this round, and the set of pattern ids each player has
# already been paid for. Claiming is what stops a player from farming one
# shape by shifting pieces off it and back on — see
# GameLogic.collect_unclaimed. Both reset on New Game.
var round_points := {1: 0, 2: 0}
var claimed_patterns := {1: {}, 2: {}}

# Short note appended to the status line describing the most recent scoring
# event ("X +2 Four corners"). Cleared at the start of each resolution.
var last_score_note := ""

# "Arrow Bonus" feature: when enabled, a new game arms selected cells with
# a yellow ★ icon. The first time a player places a piece on one of those
# cells, they gain +1 to their arrow-use budget, and the bonus is consumed
# (icon disappears). `bonus_mode` picks which cells get armed (see the
# BonusMode enum above). Default is CORNERS (the classic behavior).
var bonus_mode: int = BonusMode.CORNERS
# Maps armed cell index -> true/false. true means the bonus is still available.
var bonus_armed: Dictionary = {}
# When non-null, the next _on_restart_pressed will use these indices to arm
# the ★ bonuses instead of computing them locally. This is how the Random
# bonus mode stays in sync over networked play: the host rolls the dice
# once, broadcasts the chosen indices, and the client applies them verbatim.
# Always cleared back to null after use so the next local New Game rolls
# fresh values.
var _remote_bonus_indices: Variant = null

# When true (default), pressing an arrow button also ends the current
# player's turn (like placing a piece). When false, only piece placement
# ends a turn; the current player can keep shifting until they run out of
# arrow uses or decide to place.
var arrows_end_turn := true

var cells: Array = []
var status_label: Label
var score_x: Label
var score_o: Label
var score_draw: Label
var shift_limit_spin: SpinBox
var shift_remaining_x: Label
var shift_remaining_o: Label
var shift_up_button: Button
var shift_down_button: Button
var shift_left_button: Button
var shift_right_button: Button
var grid_size_option: OptionButton
var grid_container: GridContainer
var bonus_option: OptionButton
var arrows_end_turn_checkbox: CheckBox
var points_row: HBoxContainer
var points_label_x: Label
var points_label_o: Label
var win_mode_option: OptionButton
var points_target_spin: SpinBox
var points_target_label: Label
var pattern_warn_label: Label
# Per-pattern-kind dialog controls, keyed by GameLogic.KIND_*. Each entry is
# {"check": CheckBox, "points": SpinBox} plus, for the edges kind, "count".
var pattern_controls: Dictionary = {}
var mnk_row: HBoxContainer
var mnk_m_spin: SpinBox
var mnk_n_spin: SpinBox
var mnk_k_spin: SpinBox
var turn_x_box: Panel
var turn_o_box: Panel
var turn_x_label: Label
var turn_o_label: Label
# "New Game Settings" popup that holds all game-config controls. Opened by
# the New Game button; its OK button ("Start Game") confirms the settings
# and starts a fresh game via _on_restart_pressed.
var config_dialog: ConfirmationDialog

# ---- Multiplayer (WebSocket relay) ----
# When `multiplayer_enabled` is true, input is gated by whose turn it is,
# and every user action is broadcast to the opponent via the Multiplayer
# autoload. `my_side` is the side this instance controls (1 = X, 2 = O).
# `applying_remote` is true while we're processing an inbound network
# message, which suppresses re-broadcasting the action we're applying.
var multiplayer_enabled := false
var is_net_host := false
var my_side := 0
var applying_remote := false

var mp_host_button: Button
var mp_join_button: Button
var mp_lobby_edit: LineEdit
var mp_copy_button: Button
var mp_leave_button: Button
var mp_status_label: Label

func _ready() -> void:
	_fit_window_to_screen()

	status_label = $VBox/StatusLabel
	score_x = $VBox/ScoreContainer/ScoreX/ScoreValueX
	score_o = $VBox/ScoreContainer/ScoreO/ScoreValueO
	score_draw = $VBox/ScoreContainer/ScoreDraw/ScoreValueDraw

	grid_container = $VBox/GridRow/GridContainer

	# The New Game button opens the config dialog; pressing its OK button
	# ("Start Game") fires `confirmed`, which is what actually starts a
	# fresh game via _on_restart_pressed.
	$VBox/ButtonRow/RestartButton.pressed.connect(_on_new_game_pressed)
	$VBox/ButtonRow/ResetScoresButton.pressed.connect(_on_reset_scores_pressed)

	shift_up_button = $VBox/ShiftUpRow/ShiftUpButton
	shift_down_button = $VBox/ShiftDownRow/ShiftDownButton
	shift_left_button = $VBox/GridRow/ShiftLeftButton
	shift_right_button = $VBox/GridRow/ShiftRightButton
	shift_up_button.pressed.connect(_on_shift.bind("up"))
	shift_down_button.pressed.connect(_on_shift.bind("down"))
	shift_left_button.pressed.connect(_on_shift.bind("left"))
	shift_right_button.pressed.connect(_on_shift.bind("right"))

	# Config-dialog controls all live under ConfigDialog/ConfigBox in the scene.
	config_dialog = $ConfigDialog
	config_dialog.confirmed.connect(_on_restart_pressed)
	# If the user cancels (X button, Escape, or Cancel), re-sync the dialog's
	# controls to the currently-applied state so stray edits don't leak.
	config_dialog.canceled.connect(_sync_ui_to_applied_state)

	shift_limit_spin = $ConfigDialog/ConfigBox/ShiftLimitRow/ShiftLimitSpinBox
	shift_remaining_x = $VBox/ShiftRemainingRow/ShiftRemainingX
	shift_remaining_o = $VBox/ShiftRemainingRow/ShiftRemainingO
	max_shifts = int(shift_limit_spin.value)
	shifts_left = {1: max_shifts, 2: max_shifts}

	grid_size_option = $ConfigDialog/ConfigBox/GridSizeRow/GridSizeOption
	grid_size_option.clear()
	grid_size_option.add_item("3x3", GridMode.THREE)
	grid_size_option.add_item("4x4", GridMode.FOUR)
	grid_size_option.add_item("MNK (custom)", GridMode.MNK)
	# Default selection matches current grid_mode.
	grid_size_option.select(grid_size_option.get_item_index(grid_mode))
	grid_size_option.item_selected.connect(_on_grid_size_selected)

	mnk_row = $ConfigDialog/ConfigBox/MNKRow
	mnk_m_spin = $ConfigDialog/ConfigBox/MNKRow/MSpin
	mnk_n_spin = $ConfigDialog/ConfigBox/MNKRow/NSpin
	mnk_k_spin = $ConfigDialog/ConfigBox/MNKRow/KSpin
	_refresh_mnk_row_visibility()

	bonus_option = $ConfigDialog/ConfigBox/BonusRow/BonusOption
	bonus_option.clear()
	bonus_option.add_item("Off", BonusMode.OFF)
	bonus_option.add_item("Corners", BonusMode.CORNERS)
	bonus_option.add_item("Random", BonusMode.RANDOM)
	bonus_option.select(bonus_option.get_item_index(bonus_mode))

	arrows_end_turn_checkbox = $ConfigDialog/ConfigBox/ArrowsEndTurnRow/ArrowsEndTurnCheckBox
	arrows_end_turn_checkbox.button_pressed = arrows_end_turn

	points_row = $VBox/PointsRow
	points_label_x = $VBox/PointsRow/PointsX
	points_label_o = $VBox/PointsRow/PointsO

	# Win-condition / scoring controls.
	win_mode_option = $ConfigDialog/ConfigBox/WinRuleRow/WinModeOption
	win_mode_option.clear()
	win_mode_option.add_item("First win condition", WinMode.FIRST)
	win_mode_option.add_item("Points target", WinMode.POINTS)
	win_mode_option.select(win_mode_option.get_item_index(win_mode))
	win_mode_option.item_selected.connect(_on_win_mode_selected)
	points_target_label = $ConfigDialog/ConfigBox/WinRuleRow/PointsTargetLabel
	points_target_spin = $ConfigDialog/ConfigBox/WinRuleRow/PointsTargetSpinBox
	points_target_spin.value = float(points_target)
	pattern_warn_label = $ConfigDialog/ConfigBox/PatternWarnRow/PatternWarnLabel

	var grid := $ConfigDialog/ConfigBox/PatternGrid
	pattern_controls = {
		GameLogic.KIND_LINE: {
			"check": grid.get_node("LineCheck"),
			"points": grid.get_node("LinePointsSpin"),
		},
		GameLogic.KIND_CORNERS: {
			"check": grid.get_node("CornersCheck"),
			"points": grid.get_node("CornersPointsSpin"),
		},
		GameLogic.KIND_EDGES: {
			"check": grid.get_node("EdgesCheck"),
			"points": grid.get_node("EdgesPointsSpin"),
			"count": grid.get_node("EdgesExtra/EdgeCountSpin"),
		},
		GameLogic.KIND_SQUARE: {
			"check": grid.get_node("SquareCheck"),
			"points": grid.get_node("SquarePointsSpin"),
		},
		GameLogic.KIND_DIAMOND: {
			"check": grid.get_node("DiamondCheck"),
			"points": grid.get_node("DiamondPointsSpin"),
		},
	}
	# Re-validate the dialog live so the warning line reacts as the user ticks
	# boxes, rather than only once they press Start Game.
	for kind in pattern_controls:
		var controls: Dictionary = pattern_controls[kind]
		controls["check"].toggled.connect(_on_pattern_control_changed.unbind(1))
		if controls.has("count"):
			controls["count"].value_changed.connect(_on_pattern_control_changed.unbind(1))
	_sync_pattern_controls_to_config()

	turn_x_box = $VBox/TurnIndicatorRow/TurnXBox
	turn_o_box = $VBox/TurnIndicatorRow/TurnOBox
	turn_x_label = $VBox/TurnIndicatorRow/TurnXBox/TurnXLabel
	turn_o_label = $VBox/TurnIndicatorRow/TurnOBox/TurnOLabel

	# Multiplayer UI + autoload wiring.
	mp_host_button = $VBox/MPRow/HostButton
	mp_join_button = $VBox/MPRow/JoinButton
	mp_lobby_edit = $VBox/MPRow/LobbyIdEdit
	mp_copy_button = $VBox/MPRow/CopyButton
	mp_leave_button = $VBox/MPRow/LeaveButton
	mp_status_label = $VBox/MPStatusLabel
	mp_host_button.pressed.connect(_on_host_pressed)
	mp_join_button.pressed.connect(_on_join_pressed)
	mp_copy_button.pressed.connect(_on_copy_pressed)
	mp_leave_button.pressed.connect(_on_leave_pressed)
	if Multiplayer != null:
		Multiplayer.hosting_started.connect(_on_mp_hosting_started)
		Multiplayer.opponent_joined.connect(_on_mp_opponent_joined)
		Multiplayer.join_succeeded.connect(_on_mp_join_succeeded)
		Multiplayer.message_received.connect(_on_mp_message)
		Multiplayer.disconnected_from_lobby.connect(_on_mp_disconnected)
		Multiplayer.error_reported.connect(_on_mp_error)
		if not Multiplayer.is_plugin_available():
			mp_status_label.text = "Relay URL not configured — edit RELAY_URL in Multiplayer.gd"
			mp_host_button.disabled = true
			mp_join_button.disabled = true

	_rebuild_board()
	_init_bonuses(_bonus_indices(bonus_mode))
	_refresh_bonus_icons()
	_update_shift_ui()
	_update_points_ui()
	_refresh_turn_indicator()
	_update_mp_ui()

# ---------------------------------------------------------------------------
# Window sizing
# ---------------------------------------------------------------------------

# The window opens at the design resolution from project.godot, which is sized
# for the layout rather than for any particular monitor. On a screen that can't
# fit it — a laptop panel, or a 1080p desktop once the taskbar and title bar
# come off the 1080 — the window would open taller than the desktop and push
# the bottom row of controls (New Game, Reset Scores) somewhere the user can't
# reach them. Shrink to fit and re-center; the canvas_items stretch mode then
# scales the whole UI down to suit, rather than clipping it.
func _fit_window_to_screen() -> void:
	var window := get_window()
	if window == null:
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	# Headless and some virtual displays report an empty rect; nothing to fit to.
	if usable.size.x <= 0 or usable.size.y <= 0:
		return

	window.min_size = MIN_WINDOW_SIZE
	# Decoration overhead (title bar, borders) counts against the screen too.
	var decorations: Vector2i = window.get_size_with_decorations() - window.size
	var target := clamped_window_size(window.size, usable.size, decorations, SCREEN_FIT_MARGIN)
	if target == window.size:
		return
	window.size = target
	# Shrinking keeps the old top-left, which can leave the window hanging off
	# the bottom of the screen, so re-center it on the usable area.
	var decorated: Vector2i = window.get_size_with_decorations()
	window.position = usable.position + (usable.size - decorated) / 2

# Largest window size that fits a screen whose usable area is `usable`, once
# `decorations` and a `margin` of breathing space are subtracted, never growing
# past `desired` and never shrinking below MIN_WINDOW_SIZE.
#
# Split out as pure arithmetic so the tests can cover the small-screen cases
# without needing a real display to run on.
static func clamped_window_size(
		desired: Vector2i,
		usable: Vector2i,
		decorations: Vector2i,
		margin: int) -> Vector2i:
	var room := Vector2i(
		maxi(MIN_WINDOW_SIZE.x, usable.x - decorations.x - margin),
		maxi(MIN_WINDOW_SIZE.y, usable.y - decorations.y - margin))
	return Vector2i(mini(desired.x, room.x), mini(desired.y, room.y))

# ---------------------------------------------------------------------------
# Board construction
# ---------------------------------------------------------------------------

# Rebuild the board array, cell buttons, and win-lines for the current
# grid_cols / grid_rows / win_length. Called on startup and on New Game
# (when any of those may have changed via the UI).
func _rebuild_board() -> void:
	# Clear existing cell buttons. remove_child first so the GridContainer
	# layout updates immediately (queue_free alone is deferred).
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	cells.clear()

	grid_container.columns = grid_cols
	var total := grid_cols * grid_rows
	board = []
	board.resize(total)
	for i in range(total):
		board[i] = 0

	# Size cells so the board stays visually comparable across modes.
	# 3x3 and 4x4 presets keep their original sizes; larger MNK boards
	# scale the cell size down.
	var cell_px: int
	var font_px: int
	if grid_cols == 3 and grid_rows == 3:
		cell_px = 110
		font_px = 56
	elif grid_cols == 4 and grid_rows == 4:
		cell_px = 85
		font_px = 44
	else:
		var dim: int = max(grid_cols, grid_rows)
		cell_px = clampi(int(480.0 / float(dim)), 32, 95)
		font_px = clampi(int(cell_px * 0.6), 18, 56)

	for i in range(total):
		var b := Button.new()
		b.set_script(CellScript)
		b.custom_minimum_size = Vector2(cell_px, cell_px)
		grid_container.add_child(b)
		b.setup(i)
		b.add_theme_font_size_override("font_size", font_px)
		b.pressed.connect(_on_cell_pressed.bind(i))
		cells.append(b)

	_rebuild_patterns()

# Regenerate the scored win-condition set for the current dimensions and
# pattern config. Split out from _rebuild_board because the patterns can
# change while the dimensions stay put (the user ticks "Four corners" on the
# same 3x3 board), and clears the round's claim bookkeeping either way — a
# banked pattern id is only meaningful against the set it came from.
func _rebuild_patterns() -> void:
	win_patterns = GameLogic.build_patterns(grid_cols, grid_rows, win_length, pattern_config)
	claimed_patterns = {1: {}, 2: {}}

# ---------------------------------------------------------------------------
# Play & shift
# ---------------------------------------------------------------------------

func _on_cell_pressed(index: int) -> void:
	if game_over or board[index] != 0:
		return
	# In a network game, only the local side's player can initiate a move;
	# moves received from the opponent arrive through _on_mp_message with
	# applying_remote=true and bypass this gate.
	if multiplayer_enabled and not applying_remote:
		if current_player != my_side:
			return
		Multiplayer.send({"t": "click", "i": index})
	board[index] = current_player
	cells[index].set_mark(current_player)
	# If this cell was armed with a bonus ★, grant the current player +1
	# arrow use and consume the bonus. Note: the bonus only triggers on
	# direct placement (cell click), not when a piece is shifted onto an
	# armed cell, because shifts don't call _on_cell_pressed.
	if bonus_armed.get(index, false):
		bonus_armed[index] = false
		shifts_left[current_player] = shifts_left.get(current_player, 0) + 1
	_refresh_bonus_icons()
	_resolve_board(true)

# ---------------------------------------------------------------------------
# Resolution & scoring
# ---------------------------------------------------------------------------

# Score whatever the board now shows and decide whether the round is over.
# Called after every piece placement and every arrow shift.
#
# `advance_turn` says whether a non-terminal outcome should hand play to the
# other player: always true after placing a piece, and true after an arrow
# press only when the "arrows end turn" rule is on.
func _resolve_board(advance_turn: bool) -> void:
	last_score_note = ""
	var winner := 0

	if win_mode == WinMode.POINTS:
		# Bank every newly-completed condition — a single shift can complete
		# several at once, and each pays — then see if anyone hit the target.
		_award_points(GameLogic.collect_unclaimed(board, win_patterns, claimed_patterns))
		winner = _points_winner()
	else:
		# Classic rule: the first completed condition takes the round outright,
		# whatever it's worth. When one move completes several at once (quite
		# possible after a shift), the most valuable one is credited, with ties
		# going to the player who just moved.
		var best: Variant = null
		for entry in GameLogic.completed_patterns(board, win_patterns):
			if best == null or _outranks(entry, best):
				best = entry
		if best != null:
			winner = int(best["player"])
			var earned := GameLogic.pattern_points(best["pattern"])
			round_points[winner] = round_points.get(winner, 0) + earned
			last_score_note = _score_note(winner, best["pattern"])

	if winner == 0 and GameLogic.is_board_full(board):
		# Board full and nobody reached the target. In points mode the round
		# still has a result — whoever banked more takes it, dead even is a
		# draw. In classic mode a full board is simply a draw.
		var px: int = round_points.get(1, 0)
		var po: int = round_points.get(2, 0)
		if win_mode == WinMode.POINTS and px != po:
			winner = 1 if px > po else 2
		else:
			winner = -1

	if winner != 0:
		_end_round(winner)
		return

	if advance_turn:
		current_player = 2 if current_player == 1 else 1
	_update_status()
	_update_shift_ui()
	_update_points_ui()
	_refresh_turn_indicator()

# Pay out and bank each entry returned by GameLogic.collect_unclaimed.
# Entries are processed highest-value first so the status note leads with the
# best of a simultaneous batch.
func _award_points(entries: Array) -> void:
	if entries.is_empty():
		return
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b):
		return GameLogic.pattern_points(a["pattern"]) > GameLogic.pattern_points(b["pattern"]))
	var notes: Array = []
	for entry in ordered:
		var player := int(entry["player"])
		var pattern: Variant = entry["pattern"]
		round_points[player] = round_points.get(player, 0) + GameLogic.pattern_points(pattern)
		if not claimed_patterns.has(player):
			claimed_patterns[player] = {}
		claimed_patterns[player][GameLogic.pattern_claim_key(pattern)] = true
		notes.append(_score_note(player, pattern))
	last_score_note = ", ".join(notes)

# Which player, if any, has reached `points_target`. If both crossed it in the
# same resolution the higher total takes the round; a dead-even tie goes to
# the player who just moved.
func _points_winner() -> int:
	var px: int = round_points.get(1, 0)
	var po: int = round_points.get(2, 0)
	var x_hit: bool = px >= points_target
	var o_hit: bool = po >= points_target
	if x_hit and o_hit:
		if px != po:
			return 1 if px > po else 2
		return current_player
	if x_hit:
		return 1
	if o_hit:
		return 2
	return 0

# Tie-break between two completed patterns in WinMode.FIRST: more points wins,
# and an exact tie goes to whichever belongs to the player who just moved.
func _outranks(candidate: Dictionary, incumbent: Dictionary) -> bool:
	var cp := GameLogic.pattern_points(candidate["pattern"])
	var ip := GameLogic.pattern_points(incumbent["pattern"])
	if cp != ip:
		return cp > ip
	return int(candidate["player"]) == current_player and int(incumbent["player"]) != current_player

# "X +2 Four corners" — one scoring event, for the status line.
func _score_note(player: int, pattern: Variant) -> String:
	var pname := "X" if player == 1 else "O"
	return "%s +%d %s" % [pname, GameLogic.pattern_points(pattern), GameLogic.pattern_name(pattern)]

# Close out the round: -1 for a draw, otherwise the winning mark.
func _end_round(winner: int) -> void:
	game_over = true
	if winner == -1:
		status_label.text = "It's a draw!"
		status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		scores["draw"] += 1
		score_draw.text = str(scores["draw"])
	else:
		var pname := "X" if winner == 1 else "O"
		var text := "%s wins!" % pname
		if last_score_note != "":
			text = "%s — %s" % [last_score_note, text]
		status_label.text = text
		var col := Color(0.4, 0.8, 1.0) if winner == 1 else Color(1.0, 0.6, 0.4)
		status_label.add_theme_color_override("font_color", col)
		scores[winner] += 1
		score_x.text = str(scores[1])
		score_o.text = str(scores[2])
		_highlight_winner(winner)
	_disable_all_cells()
	_update_shift_ui()
	_update_points_ui()
	_refresh_turn_indicator()

# Shift all pieces on the board in a direction, working on any N x N board.
# Pieces that slide off the edge are removed. Uses the current player's
# arrow budget.
func _on_shift(direction: String) -> void:
	if game_over:
		return
	if shifts_left.get(current_player, 0) <= 0:
		return
	# Only the side whose turn it is may press arrows; remote shifts arrive
	# via _on_mp_message with applying_remote=true.
	if multiplayer_enabled and not applying_remote:
		if current_player != my_side:
			return
		Multiplayer.send({"t": "shift", "d": direction})

	shifts_left[current_player] -= 1

	var cols := grid_cols
	var rows := grid_rows
	var total := cols * rows
	var new_board: Array = []
	new_board.resize(total)
	for i in range(total):
		new_board[i] = 0

	match direction:
		"up":
			# Each column shifts up by one; top row falls off, bottom row clears.
			for c in range(cols):
				for r in range(rows - 1):
					new_board[r * cols + c] = board[(r + 1) * cols + c]
				new_board[(rows - 1) * cols + c] = 0
		"down":
			# Each column shifts down by one; bottom row falls off, top row clears.
			for c in range(cols):
				for r in range(rows - 1, 0, -1):
					new_board[r * cols + c] = board[(r - 1) * cols + c]
				new_board[c] = 0
		"left":
			for r in range(rows):
				for c in range(cols - 1):
					new_board[r * cols + c] = board[r * cols + c + 1]
				new_board[r * cols + (cols - 1)] = 0
		"right":
			for r in range(rows):
				for c in range(cols - 1, 0, -1):
					new_board[r * cols + c] = board[r * cols + c - 1]
				new_board[r * cols] = 0

	board = new_board
	_refresh_cells()
	# After pieces move, update the bonus icons — they should show only on
	# empty, still-armed corner cells.
	_refresh_bonus_icons()

	# After pieces move, score the new board and check for a winner. A shift
	# only ends the turn when the "arrows end turn" rule is on.
	_resolve_board(arrows_end_turn)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _refresh_cells() -> void:
	for i in range(cells.size()):
		cells[i].reset()
		cells[i].apply_base_style()
		if board[i] != 0:
			cells[i].set_mark(board[i])

# Highlight every cell of every win condition the winner currently holds.
# In classic mode that's the one line they just completed; in points mode it
# shows the whole set of shapes they banked and still hold. On a
# points-on-a-full-board win the winner may hold nothing right now, in which
# case nothing highlights.
func _highlight_winner(winner: int) -> void:
	for entry in GameLogic.completed_patterns(board, win_patterns):
		if int(entry["player"]) != winner:
			continue
		for idx in GameLogic.pattern_cells(entry["pattern"]):
			cells[idx].highlight_win(winner)

func _disable_all_cells() -> void:
	for cell in cells:
		cell.disabled = true

func _update_status() -> void:
	var pname := "X" if current_player == 1 else "O"
	var text := "%s's turn" % pname
	# Lead with what just scored, if anything, so a point payout doesn't
	# vanish the instant play passes to the other side.
	if last_score_note != "":
		text = "%s — %s" % [last_score_note, text]
	status_label.text = text
	var col := Color(0.4, 0.8, 1.0) if current_player == 1 else Color(1.0, 0.6, 0.4)
	status_label.add_theme_color_override("font_color", col)

func _on_reset_scores_pressed() -> void:
	# In a network game, only the host may reset the shared scores.
	if multiplayer_enabled and not applying_remote:
		if not is_net_host:
			return
		Multiplayer.send({"t": "reset_scores"})
	scores = {1: 0, 2: 0, "draw": 0}
	score_x.text = "0"
	score_o.text = "0"
	score_draw.text = "0"
	_on_restart_pressed()

func _on_restart_pressed() -> void:
	# In a network game, only the host may start a new game. Clients reach
	# this function only via _on_mp_message (applying_remote=true), which
	# means we should skip the broadcast branch and apply settings locally.
	if multiplayer_enabled and not applying_remote and not is_net_host:
		return

	# Compute pending settings for the new game. Grid dimensions have to be
	# resolved BEFORE we compute bonus indices, because RANDOM mode rolls
	# against the new cell count, not the previous board's.
	var selected_mode := int(grid_size_option.get_selected_id())
	var new_cols: int
	var new_rows: int
	var new_k: int
	match selected_mode:
		GridMode.THREE:
			new_cols = 3; new_rows = 3; new_k = 3
		GridMode.FOUR:
			new_cols = 4; new_rows = 4; new_k = 4
		GridMode.MNK, _:
			# M = rows, N = columns (matches the m,n,k-game convention on
			# Wikipedia: "played on an m-by-n board").
			new_rows = int(mnk_m_spin.value)
			new_cols = int(mnk_n_spin.value)
			new_k = int(mnk_k_spin.value)
			# K can't exceed the longest dimension or there'd be no possible win.
			new_k = mini(new_k, maxi(new_cols, new_rows))
	var dimensions_changed: bool = (
		selected_mode != grid_mode
		or new_cols != grid_cols
		or new_rows != grid_rows
		or new_k != win_length
	)
	grid_mode = selected_mode
	grid_cols = new_cols
	grid_rows = new_rows
	win_length = new_k

	# Read the win-condition settings before (re)generating patterns, since
	# both the dimensions and the enabled shapes feed into them.
	_read_win_rule_settings()

	if dimensions_changed:
		_rebuild_board()
	else:
		# Same dimensions: just reset the board contents and regenerate the
		# patterns in case the enabled shapes or their point values changed.
		for i in range(board.size()):
			board[i] = 0
		for cell in cells:
			cell.reset()
		_apply_cell_styles()
		_rebuild_patterns()

	round_points = {1: 0, 2: 0}
	last_score_note = ""

	if shift_limit_spin != null:
		max_shifts = int(shift_limit_spin.value)
	shifts_left = {1: max_shifts, 2: max_shifts}

	# Resolve the bonus-mode selection and roll (or inherit) the ★ indices.
	# When we're applying an inbound "new_game" message, _remote_bonus_indices
	# is set to the host's rolled indices and we use those verbatim — this is
	# what keeps RANDOM in sync across host/client.
	if bonus_option != null:
		bonus_mode = int(bonus_option.get_selected_id())
	var new_bonus_indices: Array
	if applying_remote and _remote_bonus_indices != null:
		new_bonus_indices = _remote_bonus_indices
	else:
		new_bonus_indices = _bonus_indices(bonus_mode)

	# Host-side broadcast. Runs AFTER the new dims + bonus indices have been
	# computed so we can include the exact indices the client should arm.
	if multiplayer_enabled and not applying_remote:
		Multiplayer.send({
			"t": "new_game",
			"grid_mode": int(grid_size_option.get_selected_id()),
			"mnk_m": int(mnk_m_spin.value),
			"mnk_n": int(mnk_n_spin.value),
			"mnk_k": int(mnk_k_spin.value),
			"max_shifts": int(shift_limit_spin.value),
			"bonus_mode": int(bonus_option.get_selected_id()),
			"bonus_indices": new_bonus_indices,
			"arrows_end_turn": arrows_end_turn_checkbox.button_pressed,
			# Win conditions are deterministic given the dimensions plus this
			# config, so the client rebuilds the same pattern set from it —
			# no need to ship the patterns themselves.
			"win_mode": win_mode,
			"points_target": points_target,
			"pattern_config": pattern_config,
		})

	_init_bonuses(new_bonus_indices)
	_refresh_bonus_icons()

	# Apply the "arrows end turn" rule for the new game.
	if arrows_end_turn_checkbox != null:
		arrows_end_turn = arrows_end_turn_checkbox.button_pressed

	current_player = 1
	game_over = false
	_update_shift_ui()
	_update_points_ui()
	_update_status()
	_refresh_turn_indicator()
	_update_mp_ui()

func _apply_cell_styles() -> void:
	for cell in cells:
		cell.apply_base_style()

# ---------------------------------------------------------------------------
# Win-condition settings
# ---------------------------------------------------------------------------

# Pull the win-mode, points target, and per-shape config out of the dialog
# controls into the applied game state. Called from _on_restart_pressed before
# the patterns are regenerated.
func _read_win_rule_settings() -> void:
	if win_mode_option != null:
		win_mode = int(win_mode_option.get_selected_id())
	if points_target_spin != null:
		points_target = int(points_target_spin.value)

	for kind in pattern_controls:
		var controls: Dictionary = pattern_controls[kind]
		var entry: Dictionary = pattern_config.get(kind, {})
		entry["enabled"] = bool(controls["check"].button_pressed)
		entry["points"] = int(controls["points"].value)
		if controls.has("count"):
			entry["count"] = int(controls["count"].value)
		pattern_config[kind] = entry

	# A round with no enabled win condition can never be won, so fall back to
	# plain k-in-a-row rather than hand the players an unwinnable board.
	if not _any_pattern_enabled():
		pattern_config[GameLogic.KIND_LINE]["enabled"] = true
	_sync_pattern_controls_to_config()

# True when at least one win condition is ticked AND will actually generate
# patterns on the current board. The side-squares condition can be ticked but
# produce nothing (too few edge cells, or too many combinations), so it only
# counts when it's really available.
func _any_pattern_enabled() -> bool:
	for kind in pattern_config:
		if not bool(pattern_config[kind].get("enabled", false)):
			continue
		if kind == GameLogic.KIND_EDGES:
			var count: int = int(pattern_config[kind].get("count", 3))
			if not GameLogic.edge_patterns_available(grid_cols, grid_rows, count):
				continue
		return true
	return false

# Push the applied pattern config back onto the dialog controls.
func _sync_pattern_controls_to_config() -> void:
	for kind in pattern_controls:
		var controls: Dictionary = pattern_controls[kind]
		var entry: Dictionary = pattern_config.get(kind, {})
		controls["check"].button_pressed = bool(entry.get("enabled", false))
		controls["points"].value = float(int(entry.get("points", 1)))
		if controls.has("count"):
			controls["count"].value = float(int(entry.get("count", 3)))
	_refresh_win_rule_visibility()

func _on_win_mode_selected(_index: int) -> void:
	_refresh_win_rule_visibility()

func _on_pattern_control_changed() -> void:
	_refresh_win_rule_visibility()

# Grey out the points target when it doesn't apply, and surface any warning
# about the shapes the user has ticked. Runs live as the dialog is edited.
func _refresh_win_rule_visibility() -> void:
	if win_mode_option == null:
		return
	var points_active: bool = int(win_mode_option.get_selected_id()) == WinMode.POINTS
	if points_target_spin != null:
		# Only editable when it applies, and never by a connected client —
		# rules belong to the host.
		points_target_spin.editable = points_active and not _is_client_locked()
	if points_target_label != null:
		points_target_label.modulate = Color(1, 1, 1, 1.0 if points_active else 0.45)
	if pattern_warn_label != null:
		pattern_warn_label.text = _win_rule_warning()

# True while this instance is a connected non-host, in which case the host
# owns every rule setting and our copies of those controls are read-only.
func _is_client_locked() -> bool:
	return multiplayer_enabled and not is_net_host

# Rebuild a pattern config from an inbound network message. The relay forwards
# JSON, so numbers arrive as floats and any key could be missing or the wrong
# type; this pins every field back to the expected shape and ignores kinds we
# don't know about. Unlisted kinds fall back to disabled.
func _sanitize_pattern_config(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kind in [
			GameLogic.KIND_LINE, GameLogic.KIND_CORNERS, GameLogic.KIND_EDGES,
			GameLogic.KIND_SQUARE, GameLogic.KIND_DIAMOND]:
		var incoming: Variant = raw.get(kind, null)
		var defaults: Dictionary = pattern_config.get(kind, {})
		var entry: Dictionary = {
			"enabled": false,
			"points": int(defaults.get("points", GameLogic.DEFAULT_POINTS.get(kind, 1))),
		}
		if kind == GameLogic.KIND_EDGES:
			entry["count"] = int(defaults.get("count", 3))
		if typeof(incoming) == TYPE_DICTIONARY:
			entry["enabled"] = bool(incoming.get("enabled", false))
			entry["points"] = maxi(1, int(incoming.get("points", entry["points"])))
			if kind == GameLogic.KIND_EDGES:
				entry["count"] = maxi(1, int(incoming.get("count", entry["count"])))
		out[kind] = entry
	return out

# A one-line note about a ticked shape that won't do anything on the board the
# user is about to start. Empty string when everything checks out.
func _win_rule_warning() -> String:
	if pattern_controls.is_empty():
		return ""
	# Warn against the dimensions the dialog will actually apply, not the
	# board currently on screen.
	var cols := grid_cols
	var rows := grid_rows
	if grid_size_option != null:
		match int(grid_size_option.get_selected_id()):
			GridMode.THREE:
				cols = 3; rows = 3
			GridMode.FOUR:
				cols = 4; rows = 4
			GridMode.MNK:
				rows = int(mnk_m_spin.value)
				cols = int(mnk_n_spin.value)

	var edges: Dictionary = pattern_controls[GameLogic.KIND_EDGES]
	if bool(edges["check"].button_pressed):
		var count := int(edges["count"].value)
		var available: int = GameLogic.edge_indices(cols, rows).size()
		if available < count:
			return ("Side squares: a %dx%d board has only %d non-corner edge cells, "
				+ "so \"any %d\" can never happen — that condition will be skipped.") % [
					cols, rows, available, count]
		if not GameLogic.edge_patterns_available(cols, rows, count):
			return ("Side squares: \"any %d of %d\" edge cells is %d combinations, over the "
				+ "%d limit — that condition will be skipped. Lower the count or the board size.") % [
					count, available, GameLogic.edge_combination_count(cols, rows, count),
					GameLogic.MAX_EDGE_COMBINATIONS]

	var any_ticked := false
	for kind in pattern_controls:
		if bool(pattern_controls[kind]["check"].button_pressed):
			any_ticked = true
			break
	if not any_ticked:
		return "No win condition ticked — \"K in a row\" will be turned back on so the round can be won."
	return ""

# Called when the user clicks the "New Game" button. Pre-fills the config
# dialog's controls with the currently-applied game settings, then shows
# the dialog. The actual reset happens when the user clicks "Start Game"
# (the dialog's OK button), which fires `confirmed` and calls
# `_on_restart_pressed`.
func _on_new_game_pressed() -> void:
	# In a network game, only the host can change settings / start a new game.
	if multiplayer_enabled and not is_net_host:
		return
	_sync_ui_to_applied_state()
	config_dialog.popup_centered()

# Reset every dialog control so it shows the game's currently-applied state.
# Called on dialog open (so opening always reflects reality) and on cancel
# (so a discarded edit doesn't stick around for the next open).
func _sync_ui_to_applied_state() -> void:
	if grid_size_option != null:
		var idx := grid_size_option.get_item_index(grid_mode)
		if idx >= 0:
			grid_size_option.select(idx)
	if mnk_m_spin != null:
		mnk_m_spin.value = float(grid_rows)
		mnk_n_spin.value = float(grid_cols)
		mnk_k_spin.value = float(win_length)
	if shift_limit_spin != null:
		shift_limit_spin.value = float(max_shifts)
	if arrows_end_turn_checkbox != null:
		arrows_end_turn_checkbox.button_pressed = arrows_end_turn
	if bonus_option != null:
		var bidx := bonus_option.get_item_index(bonus_mode)
		if bidx >= 0:
			bonus_option.select(bidx)
	if win_mode_option != null:
		var widx := win_mode_option.get_item_index(win_mode)
		if widx >= 0:
			win_mode_option.select(widx)
	if points_target_spin != null:
		points_target_spin.value = float(points_target)
	_sync_pattern_controls_to_config()
	_refresh_mnk_row_visibility()

func _on_grid_size_selected(_index: int) -> void:
	# The M/N/K spinboxes are always visible in the dialog, but we grey them
	# out (disabled) whenever the selected mode isn't MNK — a visual cue that
	# the values only take effect when MNK is chosen. The actual grid rebuild
	# happens when the user presses Start Game.
	_refresh_mnk_row_visibility()
	_apply_grid_mode_pattern_defaults(int(grid_size_option.get_selected_id()))
	_refresh_win_rule_visibility()

# Picking a grid size re-seeds the shape checkboxes to that preset's classic
# rule set: the 4x4 preset has always included 2x2 squares and diamonds, while
# 3x3 and MNK are strict k-in-a-row. The user is free to tick anything back on
# afterwards — this only fires when the dropdown actually changes.
func _apply_grid_mode_pattern_defaults(mode: int) -> void:
	if pattern_controls.is_empty():
		return
	var extras_on: bool = mode == GridMode.FOUR
	pattern_controls[GameLogic.KIND_SQUARE]["check"].button_pressed = extras_on
	pattern_controls[GameLogic.KIND_DIAMOND]["check"].button_pressed = extras_on

# The M/N/K row is always visible in the popup so the settings are
# discoverable regardless of grid mode, but the spinboxes are editable only
# when MNK is the selected mode. In non-MNK modes the values are ignored.
func _refresh_mnk_row_visibility() -> void:
	if mnk_row == null or grid_size_option == null:
		return
	var mnk_active: bool = int(grid_size_option.get_selected_id()) == GridMode.MNK
	if mnk_m_spin != null:
		mnk_m_spin.editable = mnk_active
		mnk_n_spin.editable = mnk_active
		mnk_k_spin.editable = mnk_active

# ---------------------------------------------------------------------------
# Arrow-bonus helpers
# ---------------------------------------------------------------------------

# Returns the four corner indices for the current board (top-left, top-right,
# bottom-left, bottom-right). Thin wrapper around GameLogic.corner_indices so
# the instance-free computation can be unit tested without the scene tree.
func _corner_indices() -> Array:
	return GameLogic.corner_indices(grid_cols, grid_rows)

# Returns the set of board indices that should be armed with a ★ for the
# given bonus mode. Called fresh each New Game — RANDOM re-rolls every cell
# at a 25% chance, so each game gets a different pattern. Add future modes
# by extending this match.
func _bonus_indices(mode: int) -> Array:
	match mode:
		BonusMode.CORNERS:
			return _corner_indices()
		BonusMode.RANDOM:
			var indices: Array = []
			var total := grid_cols * grid_rows
			for i in range(total):
				if randf() < 0.25:
					indices.append(i)
			return indices
		_:
			return []

# Arm the given cell indices with ★ bonuses. Called on New Game, after the
# board has been rebuilt for the current dimensions. The caller (usually
# `_on_restart_pressed`) computes the index list once (via `_bonus_indices`
# for local games, or from the inbound multiplayer message on the client)
# and passes it in here — that way RANDOM mode is only rolled once per new
# game, not both by the host and the client.
func _init_bonuses(indices: Array) -> void:
	bonus_armed.clear()
	for idx in indices:
		bonus_armed[int(idx)] = true

# Update the yellow ★ icon on every cell. A cell shows its bonus icon
# only when it's still armed AND empty — so shifts that move pieces onto
# or off a ★ cell are reflected immediately.
func _refresh_bonus_icons() -> void:
	for i in range(cells.size()):
		var visible_bonus: bool = bonus_armed.get(i, false) and board[i] == 0
		cells[i].set_bonus(visible_bonus)

# ---------------------------------------------------------------------------
# Turn indicator
# ---------------------------------------------------------------------------

# Update the two X/O chips so the active player's chip is highlighted
# (bright player-colored border, full-color letter) and the other is dim.
# When the game is over, both chips are dimmed.
func _refresh_turn_indicator() -> void:
	if turn_x_box == null or turn_o_box == null:
		return
	var x_active: bool = not game_over and current_player == 1
	var o_active: bool = not game_over and current_player == 2
	_apply_turn_chip(turn_x_box, turn_x_label, x_active, Color(0.4, 0.8, 1.0))
	_apply_turn_chip(turn_o_box, turn_o_label, o_active, Color(1.0, 0.6, 0.4))
	# Mark which side the local user controls in a networked game.
	if multiplayer_enabled:
		turn_x_label.text = "X (You)" if my_side == 1 else "X"
		turn_o_label.text = "O (You)" if my_side == 2 else "O"
		turn_x_label.add_theme_font_size_override("font_size", 22)
		turn_o_label.add_theme_font_size_override("font_size", 22)
	else:
		turn_x_label.text = "X"
		turn_o_label.text = "O"
		turn_x_label.add_theme_font_size_override("font_size", 36)
		turn_o_label.add_theme_font_size_override("font_size", 36)

func _apply_turn_chip(panel: Panel, label: Label, active: bool, player_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	if active:
		# Darker tinted background with a bright player-colored border.
		style.bg_color = Color(
			player_color.r * 0.25,
			player_color.g * 0.25,
			player_color.b * 0.25,
			1.0)
		style.border_color = player_color
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		label.add_theme_color_override("font_color", player_color)
	else:
		style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
		style.border_color = Color(0.28, 0.28, 0.34, 1.0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	panel.add_theme_stylebox_override("panel", style)

# The points readout only means anything when the round is decided on points,
# so the row is hidden in classic mode.
func _update_points_ui() -> void:
	if points_row == null:
		return
	points_row.visible = win_mode == WinMode.POINTS
	if not points_row.visible:
		return
	points_label_x.text = "X points: %d / %d" % [round_points.get(1, 0), points_target]
	points_label_o.text = "O points: %d / %d" % [round_points.get(2, 0), points_target]

func _update_shift_ui() -> void:
	if shift_remaining_x != null:
		shift_remaining_x.text = "X arrows: %d" % shifts_left.get(1, 0)
	if shift_remaining_o != null:
		shift_remaining_o.text = "O arrows: %d" % shifts_left.get(2, 0)
	var out_of_shifts: bool = shifts_left.get(current_player, 0) <= 0
	var disabled: bool = game_over or out_of_shifts
	# In a network game, the opponent's arrows are locked on your machine.
	if multiplayer_enabled and current_player != my_side:
		disabled = true
	if shift_up_button != null:
		shift_up_button.disabled = disabled
	if shift_down_button != null:
		shift_down_button.disabled = disabled
	if shift_left_button != null:
		shift_left_button.disabled = disabled
	if shift_right_button != null:
		shift_right_button.disabled = disabled

# ---------------------------------------------------------------------------
# Multiplayer button / signal handlers
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	mp_status_label.text = "Connecting to relay..."
	Multiplayer.host()

func _on_join_pressed() -> void:
	var id_str := mp_lobby_edit.text.strip_edges()
	if id_str == "":
		mp_status_label.text = "Paste a room code first."
		return
	mp_status_label.text = "Joining room..."
	Multiplayer.join(id_str)

func _on_copy_pressed() -> void:
	if mp_lobby_edit.text == "":
		return
	DisplayServer.clipboard_set(mp_lobby_edit.text)
	mp_status_label.text = "Room code copied to clipboard."

func _on_leave_pressed() -> void:
	Multiplayer.leave()
	# Local teardown; _on_mp_disconnected will handle UI refresh.

func _on_mp_hosting_started(lobby_id_str: String) -> void:
	mp_lobby_edit.text = lobby_id_str
	mp_status_label.text = "Hosting — share this room code, then wait for opponent."
	mp_leave_button.disabled = false

func _on_mp_opponent_joined() -> void:
	multiplayer_enabled = true
	is_net_host = true
	my_side = 1  # host = X
	mp_status_label.text = "Opponent joined. You are X."
	_update_mp_ui()
	# Start a fresh game; _on_restart_pressed broadcasts the settings.
	_on_restart_pressed()

func _on_mp_join_succeeded() -> void:
	multiplayer_enabled = true
	is_net_host = false
	my_side = 2  # client = O
	mp_status_label.text = "Connected. You are O. Waiting for host to start..."
	_update_mp_ui()

func _on_mp_disconnected(reason: String) -> void:
	multiplayer_enabled = false
	is_net_host = false
	my_side = 0
	mp_status_label.text = reason
	_update_mp_ui()
	_refresh_turn_indicator()
	_update_shift_ui()

func _on_mp_error(msg: String) -> void:
	mp_status_label.text = msg

# Handle a message from the opponent. Each message describes one user
# action; we re-apply it locally with `applying_remote=true` so the same
# handlers run but don't echo the action back over the network.
func _on_mp_message(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	applying_remote = true
	var t := str(data.get("t", ""))
	match t:
		"click":
			var i := int(data.get("i", -1))
			if i >= 0 and i < cells.size():
				_on_cell_pressed(i)
		"shift":
			var d := str(data.get("d", ""))
			if d in ["up", "down", "left", "right"]:
				_on_shift(d)
		"new_game":
			# Only the client needs to sync settings from the host.
			if not is_net_host:
				var gm := int(data.get("grid_mode", grid_mode))
				var idx := grid_size_option.get_item_index(gm)
				if idx >= 0:
					grid_size_option.select(idx)
				mnk_m_spin.value = float(int(data.get("mnk_m", int(mnk_m_spin.value))))
				mnk_n_spin.value = float(int(data.get("mnk_n", int(mnk_n_spin.value))))
				mnk_k_spin.value = float(int(data.get("mnk_k", int(mnk_k_spin.value))))
				shift_limit_spin.value = float(int(data.get("max_shifts", max_shifts)))
				var bm := int(data.get("bonus_mode", bonus_mode))
				var bidx := bonus_option.get_item_index(bm)
				if bidx >= 0:
					bonus_option.select(bidx)
				arrows_end_turn_checkbox.button_pressed = bool(data.get("arrows_end_turn", arrows_end_turn))
				arrows_end_turn = arrows_end_turn_checkbox.button_pressed
				# Win conditions: adopt the host's rule set verbatim, then push
				# it onto our dialog controls so _read_win_rule_settings (run
				# from _on_restart_pressed just below) reads back the same
				# values rather than whatever this machine had selected.
				var wm := int(data.get("win_mode", win_mode))
				var widx := win_mode_option.get_item_index(wm)
				if widx >= 0:
					win_mode_option.select(widx)
				points_target_spin.value = float(int(data.get("points_target", points_target)))
				var raw_cfg: Variant = data.get("pattern_config", null)
				if typeof(raw_cfg) == TYPE_DICTIONARY:
					pattern_config = _sanitize_pattern_config(raw_cfg)
				_sync_pattern_controls_to_config()
				_refresh_mnk_row_visibility()
			# Copy the host's rolled ★ indices so _on_restart_pressed uses
			# them verbatim instead of rolling new ones on our end. Without
			# this the RANDOM mode would produce different patterns on each
			# machine.
			var raw_indices: Variant = data.get("bonus_indices", null)
			if raw_indices is Array:
				var copied: Array = []
				for v in raw_indices:
					copied.append(int(v))
				_remote_bonus_indices = copied
			else:
				_remote_bonus_indices = null
			_on_restart_pressed()
			_remote_bonus_indices = null
		"reset_scores":
			# Only zero the scores here — don't trigger a full New Game.
			# The host is about to (or just did) send a separate "new_game"
			# message with the freshly-rolled bonus indices, and we need to
			# wait for that so the client applies the host's pattern rather
			# than rolling its own.
			scores = {1: 0, 2: 0, "draw": 0}
			score_x.text = "0"
			score_o.text = "0"
			score_draw.text = "0"
	applying_remote = false

# Update enabled/disabled state for every multiplayer-affected control.
func _update_mp_ui() -> void:
	if mp_host_button == null:
		return
	var plugin_ok := Multiplayer != null and Multiplayer.is_plugin_available()
	var in_lobby := multiplayer_enabled or (Multiplayer != null and Multiplayer.is_connected_in_lobby())
	mp_host_button.disabled = (not plugin_ok) or in_lobby
	mp_join_button.disabled = (not plugin_ok) or in_lobby
	mp_lobby_edit.editable = not in_lobby
	mp_leave_button.disabled = not in_lobby
	# When connected as the non-host, lock all rule-setting controls — only
	# the host decides grid size, arrow rules, etc.
	var client_locked: bool = multiplayer_enabled and not is_net_host
	grid_size_option.disabled = client_locked
	shift_limit_spin.editable = not client_locked
	bonus_option.disabled = client_locked
	arrows_end_turn_checkbox.disabled = client_locked
	if mnk_m_spin != null:
		mnk_m_spin.editable = not client_locked
		mnk_n_spin.editable = not client_locked
		mnk_k_spin.editable = not client_locked
	if win_mode_option != null:
		win_mode_option.disabled = client_locked
	for kind in pattern_controls:
		var controls: Dictionary = pattern_controls[kind]
		controls["check"].disabled = client_locked
		controls["points"].editable = not client_locked
		if controls.has("count"):
			controls["count"].editable = not client_locked
	# Owns the points-target spinbox's editable state (it also depends on the
	# selected win mode), so run it after the lock flags above.
	_refresh_win_rule_visibility()
	$VBox/ButtonRow/RestartButton.disabled = client_locked
	$VBox/ButtonRow/ResetScoresButton.disabled = client_locked
