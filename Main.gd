extends Control

# Generalized to an N x N board.
# grid_size determines layout and win conditions:
#   - 3x3: rows, columns, and two diagonals (classic)
#   - 4x4: rows, columns, two diagonals, 2x2 squares, and diamonds.
#     A "square" is four cells forming any 2x2 block of matching marks.
#     A "diamond" is the four cells surrounding a single center cell
#     (up, left, right, down) all matching.
#
# Board is a flat array of length grid_size * grid_size, row-major.
# 0 = empty, 1 = X, 2 = O.
const CellScript = preload("res://Cell.gd")

var grid_size := 3
var board: Array = []
var current_player := 1
var game_over := false
var scores := {1: 0, 2: 0, "draw": 0}

# Per-player arrow-click budget. Each player gets `max_shifts` uses per game.
# Configured via the SpinBox in the UI. Applies on the next New Game.
var max_shifts := 3
var shifts_left := {1: 3, 2: 3}

# Computed whenever grid_size changes.
var win_lines: Array = []

# "Corner bonus" feature: when enabled, a new game arms the four corner
# cells with a yellow ★ icon. The first time a player places a piece on
# one of those corners, they gain +1 to their arrow-use budget, and the
# bonus is consumed (icon disappears).
var corner_bonuses_enabled := true
# Maps corner index -> true/false. true means the bonus is still available.
var corner_bonus_armed: Dictionary = {}

# When true, pressing an arrow button also ends the current player's turn
# (like placing a piece). When false (default), only piece placement ends a
# turn; the current player can keep shifting until they run out of arrow
# uses or decide to place.
var arrows_end_turn := false

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
var bonus_checkbox: CheckBox
var arrows_end_turn_checkbox: CheckBox
var turn_x_box: Panel
var turn_o_box: Panel
var turn_x_label: Label
var turn_o_label: Label

func _ready() -> void:
	status_label = $VBox/StatusLabel
	score_x = $VBox/ScoreContainer/ScoreX/ScoreValueX
	score_o = $VBox/ScoreContainer/ScoreO/ScoreValueO
	score_draw = $VBox/ScoreContainer/ScoreDraw/ScoreValueDraw

	grid_container = $VBox/GridRow/GridContainer

	$VBox/ButtonRow/RestartButton.pressed.connect(_on_restart_pressed)
	$VBox/ButtonRow/ResetScoresButton.pressed.connect(_on_reset_scores_pressed)

	shift_up_button = $VBox/ShiftUpRow/ShiftUpButton
	shift_down_button = $VBox/ShiftDownRow/ShiftDownButton
	shift_left_button = $VBox/GridRow/ShiftLeftButton
	shift_right_button = $VBox/GridRow/ShiftRightButton
	shift_up_button.pressed.connect(_on_shift.bind("up"))
	shift_down_button.pressed.connect(_on_shift.bind("down"))
	shift_left_button.pressed.connect(_on_shift.bind("left"))
	shift_right_button.pressed.connect(_on_shift.bind("right"))

	shift_limit_spin = $VBox/ShiftLimitRow/ShiftLimitSpinBox
	shift_remaining_x = $VBox/ShiftRemainingRow/ShiftRemainingX
	shift_remaining_o = $VBox/ShiftRemainingRow/ShiftRemainingO
	max_shifts = int(shift_limit_spin.value)
	shifts_left = {1: max_shifts, 2: max_shifts}
	shift_limit_spin.value_changed.connect(_on_shift_limit_changed)

	grid_size_option = $VBox/GridSizeRow/GridSizeOption
	grid_size_option.clear()
	grid_size_option.add_item("3x3", 3)
	grid_size_option.add_item("4x4", 4)
	# Default selection matches current grid_size.
	grid_size_option.select(grid_size_option.get_item_index(grid_size))
	grid_size_option.item_selected.connect(_on_grid_size_selected)

	bonus_checkbox = $VBox/BonusRow/BonusCheckBox
	bonus_checkbox.button_pressed = corner_bonuses_enabled
	bonus_checkbox.toggled.connect(_on_bonus_toggled)

	arrows_end_turn_checkbox = $VBox/ShiftLimitRow/ArrowsEndTurnCheckBox
	arrows_end_turn_checkbox.button_pressed = arrows_end_turn
	arrows_end_turn_checkbox.toggled.connect(_on_arrows_end_turn_toggled)

	turn_x_box = $VBox/TurnIndicatorRow/TurnXBox
	turn_o_box = $VBox/TurnIndicatorRow/TurnOBox
	turn_x_label = $VBox/TurnIndicatorRow/TurnXBox/TurnXLabel
	turn_o_label = $VBox/TurnIndicatorRow/TurnOBox/TurnOLabel

	_rebuild_board()
	_init_corner_bonuses()
	_refresh_bonus_icons()
	_update_shift_ui()
	_refresh_turn_indicator()

# ---------------------------------------------------------------------------
# Board construction
# ---------------------------------------------------------------------------

# Rebuild the board array, cell buttons, and win-lines for the current
# grid_size. Called on startup and on New Game (when grid size may have
# changed via the OptionButton).
func _rebuild_board() -> void:
	# Clear existing cell buttons. remove_child first so the GridContainer
	# layout updates immediately (queue_free alone is deferred).
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	cells.clear()

	grid_container.columns = grid_size
	var n := grid_size
	board = []
	board.resize(n * n)
	for i in range(n * n):
		board[i] = 0

	# Size cells so the board stays visually comparable between 3x3 and 4x4.
	var cell_px := 110 if n == 3 else 85
	var font_px := 56 if n == 3 else 44

	for i in range(n * n):
		var b := Button.new()
		b.set_script(CellScript)
		b.custom_minimum_size = Vector2(cell_px, cell_px)
		grid_container.add_child(b)
		b.setup(i)
		b.add_theme_font_size_override("font_size", font_px)
		b.pressed.connect(_on_cell_pressed.bind(i))
		cells.append(b)

	win_lines = _generate_win_lines(n)

# Build the list of winning lines for an N x N board.
# For n == 3, this is the classic 8 lines (3 rows, 3 cols, 2 diagonals).
# For n == 4, we additionally include every 2x2 square and every diamond
# (four cells surrounding a center cell: up, left, right, down).
func _generate_win_lines(n: int) -> Array:
	var lines: Array = []

	# Rows
	for r in range(n):
		var row: Array = []
		for c in range(n):
			row.append(r * n + c)
		lines.append(row)

	# Columns
	for c in range(n):
		var col: Array = []
		for r in range(n):
			col.append(r * n + c)
		lines.append(col)

	# Two main diagonals (full-length)
	var diag1: Array = []
	var diag2: Array = []
	for i in range(n):
		diag1.append(i * n + i)
		diag2.append(i * n + (n - 1 - i))
	lines.append(diag1)
	lines.append(diag2)

	# 4x4-only win shapes: 2x2 squares and diamonds.
	if n == 4:
		# 2x2 squares: top-left corner at (r, c) for r, c in [0, n-2].
		for r in range(n - 1):
			for c in range(n - 1):
				var tl := r * n + c
				var tr := tl + 1
				var bl := tl + n
				var br := bl + 1
				lines.append([tl, tr, bl, br])
		# Diamonds: center at (r, c) with 1 <= r <= n-2 and 1 <= c <= n-2.
		# The diamond consists of the four orthogonal neighbors of the center
		# (up, left, right, down). The center cell itself is NOT part of the
		# winning line; only the four surrounding cells must match.
		for r in range(1, n - 1):
			for c in range(1, n - 1):
				var center := r * n + c
				var up := center - n
				var left := center - 1
				var right := center + 1
				var down := center + n
				lines.append([up, left, right, down])

	return lines

# ---------------------------------------------------------------------------
# Play & shift
# ---------------------------------------------------------------------------

func _on_cell_pressed(index: int) -> void:
	if game_over or board[index] != 0:
		return
	board[index] = current_player
	cells[index].set_mark(current_player)
	# If this corner was armed with a bonus, grant the current player +1
	# arrow use and consume the bonus. Note: the bonus only triggers on
	# direct placement (cell click), not when a piece is shifted onto a
	# corner, because shifts don't call _on_cell_pressed.
	if corner_bonus_armed.get(index, false):
		corner_bonus_armed[index] = false
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

	shifts_left[current_player] -= 1

	var n := grid_size
	var new_board: Array = []
	new_board.resize(n * n)
	for i in range(n * n):
		new_board[i] = 0

	match direction:
		"up":
			# Each column shifts up by one; top row falls off, bottom row clears.
			for c in range(n):
				for r in range(n - 1):
					new_board[r * n + c] = board[(r + 1) * n + c]
				new_board[(n - 1) * n + c] = 0
		"down":
			# Each column shifts down by one; bottom row falls off, top row clears.
			for c in range(n):
				for r in range(n - 1, 0, -1):
					new_board[r * n + c] = board[(r - 1) * n + c]
				new_board[c] = 0
		"left":
			for r in range(n):
				for c in range(n - 1):
					new_board[r * n + c] = board[r * n + c + 1]
				new_board[r * n + (n - 1)] = 0
		"right":
			for r in range(n):
				for c in range(n - 1, 0, -1):
					new_board[r * n + c] = board[r * n + c - 1]
				new_board[r * n] = 0

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
	scores = {1: 0, 2: 0, "draw": 0}
	score_x.text = "0"
	score_o.text = "0"
	score_draw.text = "0"
	_on_restart_pressed()

func _on_restart_pressed() -> void:
	# Apply pending settings for the new game.
	var selected_size := int(grid_size_option.get_selected_id())
	if selected_size != grid_size:
		grid_size = selected_size
		_rebuild_board()
	else:
		# Same size: just reset the board contents.
		for i in range(board.size()):
			board[i] = 0
		for cell in cells:
			cell.reset()
		_apply_cell_styles()

	if shift_limit_spin != null:
		max_shifts = int(shift_limit_spin.value)
	shifts_left = {1: max_shifts, 2: max_shifts}

	# Re-arm corner bonuses from the checkbox state.
	if bonus_checkbox != null:
		corner_bonuses_enabled = bonus_checkbox.button_pressed
	_init_corner_bonuses()
	_refresh_bonus_icons()

	current_player = 1
	game_over = false
	_update_shift_ui()
	_update_status()
	_refresh_turn_indicator()

func _apply_cell_styles() -> void:
	for cell in cells:
		cell.apply_base_style()

func _on_shift_limit_changed(new_value: float) -> void:
	# Takes effect on the next New Game for raises; lowering clamps existing
	# remaining counts immediately so the display stays sensible.
	var new_max := int(new_value)
	if shifts_left[1] > new_max:
		shifts_left[1] = new_max
	if shifts_left[2] > new_max:
		shifts_left[2] = new_max
	max_shifts = new_max
	_update_shift_ui()

func _on_grid_size_selected(_index: int) -> void:
	# Grid size takes effect on the next New Game, matching the arrow-limit
	# behavior. Show a hint in the status when a pending change is queued.
	var selected_size := int(grid_size_option.get_selected_id())
	if game_over:
		return
	if selected_size != grid_size:
		status_label.text = "Grid size %dx%d queued — press New Game" % [selected_size, selected_size]
		status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	else:
		# Restore the normal turn status (user reverted their selection).
		_update_status()

# ---------------------------------------------------------------------------
# Corner-bonus helpers
# ---------------------------------------------------------------------------

# Returns the four corner indices for the current grid_size.
func _corner_indices() -> Array:
	var n := grid_size
	return [0, n - 1, (n - 1) * n, n * n - 1]

# Arm all four corner cells with a bonus (if the feature is enabled).
func _init_corner_bonuses() -> void:
	corner_bonus_armed.clear()
	if not corner_bonuses_enabled:
		return
	for idx in _corner_indices():
		corner_bonus_armed[idx] = true

# Update the yellow ★ icon on every cell. A cell shows its bonus icon
# only when the corresponding corner is still armed AND the cell is empty.
# This way, shifts that move pieces onto/off corners are reflected
# immediately.
func _refresh_bonus_icons() -> void:
	for i in range(cells.size()):
		var visible_bonus: bool = corner_bonus_armed.get(i, false) and board[i] == 0
		cells[i].set_bonus(visible_bonus)

func _on_bonus_toggled(pressed: bool) -> void:
	# Takes effect on the next New Game — keep consistent with other options.
	corner_bonuses_enabled = pressed
	if not game_over:
		status_label.text = "Corner bonus %s — press New Game" % (
			"enabled" if pressed else "disabled")
		status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))

func _on_arrows_end_turn_toggled(pressed: bool) -> void:
	# Takes effect immediately — this is a pure rule change with no board state.
	arrows_end_turn = pressed

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
	if shift_up_button != null:
		shift_up_button.disabled = disabled
	if shift_down_button != null:
		shift_down_button.disabled = disabled
	if shift_left_button != null:
		shift_left_button.disabled = disabled
	if shift_right_button != null:
		shift_right_button.disabled = disabled
