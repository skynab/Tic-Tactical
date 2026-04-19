extends RefCounted
class_name GameLogic

# Pure, stateless helpers that drive the board math. These live apart from
# Main.gd so they can be exercised by the unit tests without having to
# instantiate the full Control scene tree. Every function here is static
# and takes everything it needs as parameters — no globals, no side effects.

# Build the list of winning lines for a cols x rows board where a win is
# `k` matching marks in a horizontal, vertical, or diagonal line. When
# `include_square_diamond` is true (only used for the 4x4 preset), also
# appends every 2x2 square and every 4-cell diamond (four matching marks
# in the cells directly above, below, left, and right of any single
# center cell — the center itself is not part of the line).
static func generate_win_lines(
		cols: int,
		rows: int,
		k: int,
		include_square_diamond: bool) -> Array:
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

# The four corner cell indices (top-left, top-right, bottom-left, bottom-right)
# of a cols x rows row-major board.
static func corner_indices(cols: int, rows: int) -> Array:
	return [0, cols - 1, (rows - 1) * cols, rows * cols - 1]

# Inspect a board (row-major, 0 = empty, 1 = X, 2 = O) against a precomputed
# set of winning lines. Returns:
#   1 or 2 — the winning player's mark
#   -1     — draw (board full, no winner)
#    0     — game still in progress
static func check_winner(board: Array, win_lines: Array) -> int:
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
