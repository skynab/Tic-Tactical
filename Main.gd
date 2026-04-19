extends Control

# Generalized to an M x N (cols x rows) board with a configurable "k in a
# row" win length. Three grid modes are selectable from the UI:
#   - "3x3"  : 3x3 board, win = 3-in-a-row (classic).
#   - "4x4"  : 4x4 board, win = 4-in-a-row PLUS 2x2 squares and diamonds
#              (four matching marks surrounding a center cell).
#   - "MNK"  : user-chosen columns (M), rows (N), and line length (K).
#              Wins are pure k-in-a-row (horizontal, vertical, or diagonal),
#              matching the m,n,k-game definition on Wikipedia.
#
# Board is a flat array of length grid_cols * grid_rows, row-major.
# Cell index at column c, row r is `r * grid_cols + c`.
# 0 = empty, 1 = X, 2 = O.
const CellScript = preload("res://Cell.gd")

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

# Computed whenever the board dimensions or win length change.
var win_lines: Array = []

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
# bonus mode stays in sync over Steam multiplayer: the host rolls the dice
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

# ---- Multiplayer (Steam) ----
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
			mp_status_label.text = "GodotSteam plugin not installed — see SETUP_STEAM.md"
			mp_host_button.disabled = true
			mp_join_button.disabled = true

	_rebuild_board()
	_init_bonuses(_bonus_indices(bonus_mode))
	_refresh_bonus_icons()
	_update_shift_ui()
	_refresh_turn_indicator()
	_update_mp_ui()

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

	var include_square_diamond: bool = grid_mode == GridMode.FOUR
	win_lines = _generate_win_lines(grid_cols, grid_rows, win_length, include_square_diamond)

# Build the list of winning lines for a cols x rows board where a win is
# `k` matching marks in a horizontal, vertical, or diagonal line. When
# `include_square_diamond` is true (only used for the 4x4 preset), also
# appends every 2x2 square and every 4-cell diamond (four matching marks
# in the cells directly above, below, left, and right of any single
# center cell — the center itself is not part of the line).
func _generate_win_lines(cols: int, rows: int, k: int, include_square_diamond: bool) -> Array:
	var lines: Array = []
	if k < 1:
		return lines

	# Horizontal k-in-a-row
	if cols >= k:
		for r in range(rows):
			for c in range(cols - k + 1):
				var line: Array = []
				for i in range(k):
					line.append(r * cols + c + i)
				lines.append(line)
	# Vertical k-in-a-row
	if rows >= k:
		for r in range(rows - k + 1):
			for c in range(cols):
				var line: Array = []
				for i in range(k):
					line.append((r + i) * cols + c)
				lines.append(line)
	# Diagonal top-left to bottom-right (slope down-right)
	if rows >= k and cols >= k:
		for r in range(rows - k + 1):
			for c in range(cols - k + 1):
				var line: Array = []
				for i in range(k):
					line.append((r + i) * cols + (c + i))
				lines.append(line)
	# Diagonal top-right to bottom-left (slope down-left)
	if rows >= k and cols >= k:
		for r in range(rows - k + 1):
			for c in range(k - 1, cols):
				var line: Array = []
				for i in range(k):
					line.append((r + i) * cols + (c - i))
				lines.append(line)

	# 4x4-preset-only extras: 2x2 squares and diamonds.
	if include_square_diamond and cols >= 2 and rows >= 2:
		for r in range(rows - 1):
			for c in range(cols - 1):
				var tl := r * cols + c
				lines.append([tl, tl + 1, tl + cols, tl + cols + 1])
		for r in range(1, rows - 1):
			for c in range(1, cols - 1):
				var center := r * cols + c
				lines.append([center - cols, center - 1, center + 1, center + cols])

	return lines

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
	_check_and_resolve()

func _check_and_resolve() -> void:
	var winner := _check_winner()
	if winner != 0:
		game_over = true
		if winner == -1:
			status_label.text = "It's a draw!"
			status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			scores["draw"] += 1
			score_draw.text = str(scores["draw"])
		else:
			var pname := "X" if winner == 1 else "O"
			status_label.text = "%s wins!" % pname
			var col := Color(0.4, 0.8, 1.0) if winner == 1 else Color(1.0, 0.6, 0.4)
			status_label.add_theme_color_override("font_color", col)
			scores[winner] += 1
			score_x.text = str(scores[1])
			score_o.text = str(scores[2])
			_highlight_winner(winner)
		_disable_all_cells()
		_update_shift_ui()
		_refresh_turn_indicator()
	else:
		current_player = 2 if current_player == 1 else 1
		_update_status()
		_update_shift_ui()
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

	# After a shift, re-check for a winner.
	var winner := _check_winner()
	if winner == 1 or winner == 2:
		game_over = true
		var pname := "X" if winner == 1 else "O"
		status_label.text = "%s wins!" % pname
		var col := Color(0.4, 0.8, 1.0) if winner == 1 else Color(1.0, 0.6, 0.4)
		status_label.add_theme_color_override("font_color", col)
		scores[winner] += 1
		score_x.text = str(scores[1])
		score_o.text = str(scores[2])
		_highlight_winner(winner)
		_disable_all_cells()
	elif arrows_end_turn:
		# Arrow use consumed the current player's turn; pass to the other.
		current_player = 2 if current_player == 1 else 1
		_update_status()
	# Always refresh arrow-button state and turn indicator to stay in sync.
	_update_shift_ui()
	_refresh_turn_indicator()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _refresh_cells() -> void:
	for i in range(cells.size()):
		cells[i].reset()
		cells[i].apply_base_style()
		if board[i] != 0:
			cells[i].set_mark(board[i])

func _check_winner() -> int:
	for line in win_lines:
		var first: int = board[line[0]]
		if first == 0:
			continue
		var all_match := true
		for idx in line:
			if board[idx] != first:
				all_match = false
				break
		if all_match:
			return first
	if not 0 in board:
		return -1
	return 0

func _highlight_winner(winner: int) -> void:
	for line in win_lines:
		var all_match := true
		for idx in line:
			if board[idx] != winner:
				all_match = false
				break
		if all_match:
			for idx in line:
				cells[idx].highlight_win(winner)
			return

func _disable_all_cells() -> void:
	for cell in cells:
		cell.disabled = true

func _update_status() -> void:
	var pname := "X" if current_player == 1 else "O"
	status_label.text = "%s's turn" % pname
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
	if dimensions_changed:
		_rebuild_board()
	else:
		# Same dimensions: just reset the board contents.
		for i in range(board.size()):
			board[i] = 0
		for cell in cells:
			cell.reset()
		_apply_cell_styles()

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
		})

	_init_bonuses(new_bonus_indices)
	_refresh_bonus_icons()

	# Apply the "arrows end turn" rule for the new game.
	if arrows_end_turn_checkbox != null:
		arrows_end_turn = arrows_end_turn_checkbox.button_pressed

	current_player = 1
	game_over = false
	_update_shift_ui()
	_update_status()
	_refresh_turn_indicator()
	_update_mp_ui()

func _apply_cell_styles() -> void:
	for cell in cells:
		cell.apply_base_style()

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
	_refresh_mnk_row_visibility()

func _on_grid_size_selected(_index: int) -> void:
	# The M/N/K spinboxes are always visible in the dialog, but we grey them
	# out (disabled) whenever the selected mode isn't MNK — a visual cue that
	# the values only take effect when MNK is chosen. The actual grid rebuild
	# happens when the user presses Start Game.
	_refresh_mnk_row_visibility()

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
# bottom-left, bottom-right).
func _corner_indices() -> Array:
	var cols := grid_cols
	var rows := grid_rows
	return [0, cols - 1, (rows - 1) * cols, rows * cols - 1]

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
	mp_status_label.text = "Connecting to Steam..."
	Multiplayer.host()

func _on_join_pressed() -> void:
	var id_str := mp_lobby_edit.text.strip_edges()
	if id_str == "":
		mp_status_label.text = "Paste a lobby ID first."
		return
	mp_status_label.text = "Joining lobby..."
	Multiplayer.join(id_str)

func _on_copy_pressed() -> void:
	if mp_lobby_edit.text == "":
		return
	DisplayServer.clipboard_set(mp_lobby_edit.text)
	mp_status_label.text = "Lobby ID copied to clipboard."

func _on_leave_pressed() -> void:
	Multiplayer.leave()
	# Local teardown; _on_mp_disconnected will handle UI refresh.

func _on_mp_hosting_started(lobby_id_str: String) -> void:
	mp_lobby_edit.text = lobby_id_str
	mp_status_label.text = "Hosting — share this Lobby ID, then wait for opponent."
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
	$VBox/ButtonRow/RestartButton.disabled = client_locked
	$VBox/ButtonRow/ResetScoresButton.disabled = client_locked
