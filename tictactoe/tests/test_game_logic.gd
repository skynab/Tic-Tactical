extends RefCounted

# Unit tests for GameLogic.gd. Each test appends a human-readable failure
# message to `failures` when an assertion doesn't hold; an empty list means
# everything passed. The tests stay pure — they only call GameLogic's static
# methods, so no scene tree or nodes are needed.

var failures: Array = []

func run_all() -> Array:
	failures = []
	test_win_lines_3x3()
	test_win_lines_4x4_with_squares_and_diamonds()
	test_win_lines_mnk_5x5_k3()
	test_win_lines_rectangular_3x4_k3()
	test_win_lines_k_too_large_returns_empty()
	test_corner_indices_square()
	test_corner_indices_rectangular()
	test_check_winner_row()
	test_check_winner_column()
	test_check_winner_diagonal()
	test_check_winner_draw()
	test_check_winner_in_progress()
	test_check_winner_4x4_square()
	test_check_winner_4x4_diamond()
	return failures

# ---------------------------------------------------------------------------
# generate_win_lines
# ---------------------------------------------------------------------------

# Classic 3x3: 3 rows + 3 cols + 2 diagonals = 8 winning lines.
func test_win_lines_3x3() -> void:
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(lines.size(), 8, "3x3 should produce 8 winning lines")
	# Spot-check the two main diagonals are present.
	_expect_contains(lines, [0, 4, 8], "3x3 main diagonal missing")
	_expect_contains(lines, [2, 4, 6], "3x3 anti-diagonal missing")

# 4x4 preset with k=4 plus squares and diamonds:
#   4 rows + 4 cols + 2 main diagonals + 9 2x2 squares + 4 diamonds = 23 lines.
func test_win_lines_4x4_with_squares_and_diamonds() -> void:
	var lines := GameLogic.generate_win_lines(4, 4, 4, true)
	_expect_eq(lines.size(), 23, "4x4 with squares+diamonds should produce 23 lines")
	# Top-left 2x2 square.
	_expect_contains(lines, [0, 1, 4, 5], "4x4 top-left 2x2 square missing")
	# Diamond around center cell (1, 1) = index 5.
	_expect_contains(lines, [1, 4, 6, 9], "4x4 diamond around index 5 missing")

# 5x5 MNK with k=3: lots of short lines. Just sanity check nonzero + some
# specific entries to guard against accidental regressions.
func test_win_lines_mnk_5x5_k3() -> void:
	var lines := GameLogic.generate_win_lines(5, 5, 3, false)
	# 5 rows * 3 horizontal windows = 15
	# 5 cols * 3 vertical windows = 15
	# 3 * 3 = 9 down-right diagonals, same for down-left = 18
	# Total: 48.
	_expect_eq(lines.size(), 48, "5x5 k=3 should produce 48 winning lines")
	# First row's left window: [0, 1, 2].
	_expect_contains(lines, [0, 1, 2], "5x5 k=3 first-row window missing")

# Rectangular 3 cols x 4 rows with k=3: verifies the generator handles
# non-square boards without special-casing.
func test_win_lines_rectangular_3x4_k3() -> void:
	var lines := GameLogic.generate_win_lines(3, 4, 3, false)
	# rows=4, cols=3:
	#   horizontal: rows(4) * (cols-k+1=1) = 4
	#   vertical:   (rows-k+1=2) * cols(3) = 6
	#   down-right: (rows-k+1=2) * (cols-k+1=1) = 2
	#   down-left:  (rows-k+1=2) * (cols-k+1=1) = 2
	# Total: 14.
	_expect_eq(lines.size(), 14, "3x4 k=3 should produce 14 winning lines")

# When k exceeds both dimensions the result should be empty — there are no
# possible winning lines.
func test_win_lines_k_too_large_returns_empty() -> void:
	var lines := GameLogic.generate_win_lines(3, 3, 4, false)
	_expect_eq(lines.size(), 0, "k > max dim should yield no lines")

# ---------------------------------------------------------------------------
# corner_indices
# ---------------------------------------------------------------------------

func test_corner_indices_square() -> void:
	_expect_array_eq(GameLogic.corner_indices(3, 3), [0, 2, 6, 8], "3x3 corners wrong")
	_expect_array_eq(GameLogic.corner_indices(4, 4), [0, 3, 12, 15], "4x4 corners wrong")

# Rectangular board: cols=5, rows=3 → top row = [0..4], bottom row = [10..14].
func test_corner_indices_rectangular() -> void:
	_expect_array_eq(GameLogic.corner_indices(5, 3), [0, 4, 10, 14], "5x3 corners wrong")

# ---------------------------------------------------------------------------
# check_winner
# ---------------------------------------------------------------------------

# Returns a fresh empty 3x3 board (9 zeros).
func _empty_3x3() -> Array:
	return [0, 0, 0, 0, 0, 0, 0, 0, 0]

# X takes the top row.
func test_check_winner_row() -> void:
	var board := _empty_3x3()
	board[0] = 1; board[1] = 1; board[2] = 1
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(GameLogic.check_winner(board, lines), 1, "row win should return 1 (X)")

# O takes the left column.
func test_check_winner_column() -> void:
	var board := _empty_3x3()
	board[0] = 2; board[3] = 2; board[6] = 2
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(GameLogic.check_winner(board, lines), 2, "column win should return 2 (O)")

# X takes the main diagonal.
func test_check_winner_diagonal() -> void:
	var board := _empty_3x3()
	board[0] = 1; board[4] = 1; board[8] = 1
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(GameLogic.check_winner(board, lines), 1, "diagonal win should return 1 (X)")

# Full board with no winner → draw (-1).
func test_check_winner_draw() -> void:
	# X O X
	# X O O
	# O X X   — no 3-in-a-row anywhere.
	var board := [1, 2, 1, 1, 2, 2, 2, 1, 1]
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(GameLogic.check_winner(board, lines), -1, "full board with no winner should be a draw")

# Board in progress (has empties, no winner) → 0.
func test_check_winner_in_progress() -> void:
	var board := _empty_3x3()
	board[0] = 1; board[4] = 2
	var lines := GameLogic.generate_win_lines(3, 3, 3, false)
	_expect_eq(GameLogic.check_winner(board, lines), 0, "in-progress board should return 0")

# 4x4 square win: X occupies the top-left 2x2.
func test_check_winner_4x4_square() -> void:
	var board: Array = []
	board.resize(16)
	for i in range(16):
		board[i] = 0
	board[0] = 1; board[1] = 1; board[4] = 1; board[5] = 1
	var lines := GameLogic.generate_win_lines(4, 4, 4, true)
	_expect_eq(GameLogic.check_winner(board, lines), 1, "4x4 2x2-square win should return 1 (X)")

# 4x4 diamond win: O on the four neighbors of center cell (1, 1) = index 5.
# Neighbors: above=1, left=4, right=6, below=9.
func test_check_winner_4x4_diamond() -> void:
	var board: Array = []
	board.resize(16)
	for i in range(16):
		board[i] = 0
	board[1] = 2; board[4] = 2; board[6] = 2; board[9] = 2
	var lines := GameLogic.generate_win_lines(4, 4, 4, true)
	_expect_eq(GameLogic.check_winner(board, lines), 2, "4x4 diamond win should return 2 (O)")

# ---------------------------------------------------------------------------
# Tiny assertion helpers — each records a failure instead of aborting so one
# bad test doesn't mask others.
# ---------------------------------------------------------------------------

func _expect_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [msg, str(expected), str(actual)])

func _expect_array_eq(actual: Array, expected: Array, msg: String) -> void:
	if actual.size() != expected.size():
		failures.append("%s (size mismatch: expected %d, got %d; expected=%s actual=%s)"
			% [msg, expected.size(), actual.size(), str(expected), str(actual)])
		return
	for i in range(expected.size()):
		if actual[i] != expected[i]:
			failures.append("%s (index %d: expected %s, got %s; full expected=%s actual=%s)"
				% [msg, i, str(expected[i]), str(actual[i]), str(expected), str(actual)])
			return

func _expect_contains(lines: Array, line: Array, msg: String) -> void:
	for candidate in lines:
		if _array_equal(candidate, line):
			return
	failures.append("%s (did not find %s)" % [msg, str(line)])

func _array_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true
