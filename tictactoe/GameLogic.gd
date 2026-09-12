extends RefCounted
class_name GameLogic

# Pure, stateless helpers that drive the board math. These live apart from
# Main.gd so they can be exercised by the unit tests without having to
# instantiate the full Control scene tree. Every function here is static
# and takes everything it needs as parameters — no globals, no side effects.
#
# ---------------------------------------------------------------------------
# Scored win patterns
# ---------------------------------------------------------------------------
# A "pattern" is one win condition: a set of cell indices that, when all
# filled by the same player, is worth some number of points. Patterns are
# Dictionaries:
#
#   {"kind": "corners", "cells": [0, 2, 6, 8], "points": 2,
#    "id": "corners:0,2,6,8", "name": "Four corners"}
#
# `id` is stable for a given board size + pattern kind, which is what lets
# Main.gd remember that a player has already banked a pattern (see
# `collect_unclaimed`) so re-forming it by shifting pieces around doesn't
# pay out twice.
#
# Several helpers below accept "patterns" that are either these
# Dictionaries or bare Arrays of indices (the older, point-free shape).
# `pattern_cells` / `pattern_points` normalize both, so `check_winner` still
# works when handed a plain list of index arrays.

# Pattern kind identifiers. These double as the keys of the config
# Dictionary passed to `build_patterns`.
const KIND_LINE := "line"
const KIND_CORNERS := "corners"
const KIND_EDGES := "edges"
const KIND_SQUARE := "square"
const KIND_DIAMOND := "diamond"

# Human-readable names, shown in the status line when a pattern scores.
const KIND_NAMES := {
	KIND_LINE: "In a row",
	KIND_CORNERS: "Four corners",
	KIND_EDGES: "Edge squares",
	KIND_SQUARE: "2x2 square",
	KIND_DIAMOND: "Diamond",
}

# Default point values for each pattern kind. A plain k-in-a-row is the
# baseline win, so it's worth the most; the optional shapes are cheaper.
const DEFAULT_POINTS := {
	KIND_LINE: 3,
	KIND_CORNERS: 2,
	KIND_EDGES: 1,
	KIND_SQUARE: 2,
	KIND_DIAMOND: 2,
}

# "Edge squares" asks for any `count` of the non-corner border cells, which
# is a combinatorial explosion on big boards (40 edge cells choose 5 is over
# half a million patterns). Generation bails out and returns nothing rather
# than freezing the game; `edge_patterns_available` lets the UI check first.
const MAX_EDGE_COMBINATIONS := 20000

# Build the list of winning lines for a cols x rows board where a win is
# `k` matching marks in a horizontal, vertical, or diagonal line. When
# `include_square_diamond` is true (only used for the 4x4 preset), also
# appends every 2x2 square and every 4-cell diamond (four matching marks
# in the cells directly above, below, left, and right of any single
# center cell — the center itself is not part of the line).
#
# Returns bare Arrays of indices (no point values). This is the legacy
# shape, kept because it's the simplest thing to assert against in tests
# and it's all `check_winner` needs. For scored play use `build_patterns`.
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
		for line_cells in square_cells(cols, rows):
			lines.append(line_cells)
		for line_cells in diamond_cells(cols, rows):
			lines.append(line_cells)

	return lines

# The four corner cell indices (top-left, top-right, bottom-left, bottom-right)
# of a cols x rows row-major board.
static func corner_indices(cols: int, rows: int) -> Array:
	return [0, cols - 1, (rows - 1) * cols, rows * cols - 1]

# The border cells that aren't corners — the "side" squares. On a 3x3 that's
# the four edge midpoints [1, 3, 5, 7]; on bigger boards it's every cell in
# the top/bottom row and left/right column except the four corners. Returned
# in ascending index order.
static func edge_indices(cols: int, rows: int) -> Array:
	var indices: Array = []
	if cols < 3 and rows < 3:
		return indices
	for r in range(rows):
		for c in range(cols):
			var on_border: bool = r == 0 or r == rows - 1 or c == 0 or c == cols - 1
			var is_corner: bool = (r == 0 or r == rows - 1) and (c == 0 or c == cols - 1)
			if on_border and not is_corner:
				indices.append(r * cols + c)
	return indices

# Every 2x2 block of cells on the board, as index arrays in
# top-left, top-right, bottom-left, bottom-right order.
static func square_cells(cols: int, rows: int) -> Array:
	var out: Array = []
	if cols < 2 or rows < 2:
		return out
	for r in range(rows - 1):
		for c in range(cols - 1):
			var tl := r * cols + c
			out.append([tl, tl + 1, tl + cols, tl + cols + 1])
	return out

# Every 4-cell diamond: the cells directly above, left, right, and below a
# single center cell. The center itself is not part of the pattern, so the
# center has to have a neighbor on all four sides — that means interior
# cells only, and no diamonds at all on a board narrower than 3.
static func diamond_cells(cols: int, rows: int) -> Array:
	var out: Array = []
	if cols < 3 or rows < 3:
		return out
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			var center := r * cols + c
			out.append([center - cols, center - 1, center + 1, center + cols])
	return out

# ---------------------------------------------------------------------------
# Pattern construction
# ---------------------------------------------------------------------------

# Wrap a cell list into a scored pattern Dictionary. `cells` is copied and
# sorted so the generated `id` is order-independent — two callers building
# the same shape from different directions get the same id.
#
# `claim_key` is what the claim bookkeeping keys off (see `pattern_claim_key`).
# It defaults to the pattern's own id — "this exact shape pays once per
# player per round". Pass a shared key to make a whole family of patterns
# pay out only once between them, which is what the "any N side squares"
# condition needs: holding all four sides of a 3x3 completes four different
# 3-cell subsets, and that's one achievement, not four.
static func make_pattern(kind: String, cells: Array, points: int, claim_key: String = "") -> Dictionary:
	var sorted_cells: Array = cells.duplicate()
	sorted_cells.sort()
	var parts: Array = []
	for idx in sorted_cells:
		parts.append(str(idx))
	var id: String = "%s:%s" % [kind, ",".join(parts)]
	return {
		"kind": kind,
		"cells": sorted_cells,
		"points": points,
		"id": id,
		"claim": id if claim_key == "" else claim_key,
		"name": String(KIND_NAMES.get(kind, kind)),
	}

# k-in-a-row patterns (horizontal, vertical, both diagonals), each worth
# `points`. Reuses `generate_win_lines` with the extras switched off so
# there's exactly one implementation of the line math.
static func line_patterns(cols: int, rows: int, k: int, points: int) -> Array:
	var out: Array = []
	for cells in generate_win_lines(cols, rows, k, false):
		out.append(make_pattern(KIND_LINE, cells, points))
	return out

# The single "own all four corners" pattern. Returns an empty Array on a
# board too small to have four distinct corners.
static func corners_patterns(cols: int, rows: int, points: int) -> Array:
	if cols < 2 or rows < 2:
		return []
	return [make_pattern(KIND_CORNERS, corner_indices(cols, rows), points)]

# How many distinct "any `count` edge cells" patterns a board would produce.
# Used to decide whether generating them is affordable.
static func edge_combination_count(cols: int, rows: int, count: int) -> int:
	return combination_count(edge_indices(cols, rows).size(), count)

# True when `edge_patterns` will actually produce patterns for these
# arguments — i.e. the board has enough edge cells and the combination count
# is within MAX_EDGE_COMBINATIONS.
static func edge_patterns_available(cols: int, rows: int, count: int) -> bool:
	if count < 1:
		return false
	var available: int = edge_indices(cols, rows).size()
	if available < count:
		return false
	return edge_combination_count(cols, rows, count) <= MAX_EDGE_COMBINATIONS

# "Any `count` of the side squares" — every combination of `count` non-corner
# border cells, each worth `points`. On a 3x3 with count=3 that's the four
# ways to pick 3 of the cells [1, 3, 5, 7].
#
# Returns an empty Array when the request is out of range or would exceed
# MAX_EDGE_COMBINATIONS (see `edge_patterns_available`).
static func edge_patterns(cols: int, rows: int, count: int, points: int) -> Array:
	var out: Array = []
	if not edge_patterns_available(cols, rows, count):
		return out
	var pool: Array = edge_indices(cols, rows)
	for combo in combinations(pool, count):
		# All subsets share one claim key so the condition pays once per
		# player per round no matter which N sides they end up holding.
		out.append(make_pattern(KIND_EDGES, combo, points, KIND_EDGES))
	return out

# Every 2x2 square on the board, each worth `points`.
static func square_patterns(cols: int, rows: int, points: int) -> Array:
	var out: Array = []
	for cells in square_cells(cols, rows):
		out.append(make_pattern(KIND_SQUARE, cells, points))
	return out

# Every diamond on the board, each worth `points`.
static func diamond_patterns(cols: int, rows: int, points: int) -> Array:
	var out: Array = []
	for cells in diamond_cells(cols, rows):
		out.append(make_pattern(KIND_DIAMOND, cells, points))
	return out

# Assemble the full pattern set for a board from a config Dictionary keyed by
# pattern kind:
#
#   {
#     "line":    {"enabled": true,  "points": 3},
#     "corners": {"enabled": true,  "points": 2},
#     "edges":   {"enabled": true,  "points": 1, "count": 3},
#     "square":  {"enabled": false, "points": 2},
#     "diamond": {"enabled": false, "points": 2},
#   }
#
# Missing keys are treated as disabled; a missing "points" falls back to
# DEFAULT_POINTS and a missing edge "count" to 3. Duplicate cell sets within
# the same kind are collapsed (the same shape can't be generated twice), but
# two different kinds covering the same cells stay separate patterns — the
# `kind` prefix in the id keeps them distinct, and each is worth its own
# points.
static func build_patterns(cols: int, rows: int, k: int, config: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}

	var groups: Array = []
	if _kind_enabled(config, KIND_LINE):
		groups.append(line_patterns(cols, rows, k, _kind_points(config, KIND_LINE)))
	if _kind_enabled(config, KIND_CORNERS):
		groups.append(corners_patterns(cols, rows, _kind_points(config, KIND_CORNERS)))
	if _kind_enabled(config, KIND_EDGES):
		var count: int = _kind_count(config, KIND_EDGES)
		groups.append(edge_patterns(cols, rows, count, _kind_points(config, KIND_EDGES)))
	if _kind_enabled(config, KIND_SQUARE):
		groups.append(square_patterns(cols, rows, _kind_points(config, KIND_SQUARE)))
	if _kind_enabled(config, KIND_DIAMOND):
		groups.append(diamond_patterns(cols, rows, _kind_points(config, KIND_DIAMOND)))

	for group in groups:
		for pattern in group:
			var id: String = String(pattern.get("id", ""))
			if seen.has(id):
				continue
			seen[id] = true
			out.append(pattern)
	return out

static func _kind_enabled(config: Dictionary, kind: String) -> bool:
	var entry: Variant = config.get(kind, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	return bool(entry.get("enabled", false))

static func _kind_points(config: Dictionary, kind: String) -> int:
	var entry: Variant = config.get(kind, null)
	var fallback: int = int(DEFAULT_POINTS.get(kind, 1))
	if typeof(entry) != TYPE_DICTIONARY:
		return fallback
	return int(entry.get("points", fallback))

static func _kind_count(config: Dictionary, kind: String) -> int:
	var entry: Variant = config.get(kind, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return 3
	return int(entry.get("count", 3))

# ---------------------------------------------------------------------------
# Pattern accessors — tolerate both the Dictionary and bare-Array shapes.
# ---------------------------------------------------------------------------

static func pattern_cells(pattern: Variant) -> Array:
	if typeof(pattern) == TYPE_DICTIONARY:
		var cells: Variant = pattern.get("cells", [])
		return cells if cells is Array else []
	if pattern is Array:
		return pattern
	return []

static func pattern_points(pattern: Variant) -> int:
	if typeof(pattern) == TYPE_DICTIONARY:
		return int(pattern.get("points", 0))
	return 0

static func pattern_id(pattern: Variant) -> String:
	if typeof(pattern) == TYPE_DICTIONARY and pattern.has("id"):
		return String(pattern["id"])
	# Bare-Array patterns have no kind, so fall back to the cell list.
	var parts: Array = []
	for idx in pattern_cells(pattern):
		parts.append(str(idx))
	return ",".join(parts)

static func pattern_name(pattern: Variant) -> String:
	if typeof(pattern) == TYPE_DICTIONARY:
		return String(pattern.get("name", pattern.get("kind", "Pattern")))
	return "Line"

# The key the claim bookkeeping uses for this pattern. Patterns sharing a key
# pay out only once between them per player per round; by default each
# pattern is its own key. See `make_pattern`.
static func pattern_claim_key(pattern: Variant) -> String:
	if typeof(pattern) == TYPE_DICTIONARY and pattern.has("claim"):
		return String(pattern["claim"])
	return pattern_id(pattern)

# ---------------------------------------------------------------------------
# Board inspection
# ---------------------------------------------------------------------------

# Which player, if any, owns every cell of `pattern`. Returns 1, 2, or 0
# for "nobody yet".
static func pattern_owner(board: Array, pattern: Variant) -> int:
	var cells: Array = pattern_cells(pattern)
	if cells.is_empty():
		return 0
	var first: int = int(board[cells[0]])
	if first == 0:
		return 0
	for idx in cells:
		if int(board[idx]) != first:
			return 0
	return first

static func is_board_full(board: Array) -> bool:
	return not 0 in board

# Inspect a board (row-major, 0 = empty, 1 = X, 2 = O) against a precomputed
# set of winning patterns (Dictionaries or bare index Arrays). Returns:
#   1 or 2 — the winning player's mark
#   -1     — draw (board full, no winner)
#    0     — game still in progress
#
# This is the "first completed pattern ends the round" rule; the points
# system doesn't come into it.
static func check_winner(board: Array, win_patterns: Array) -> int:
	for pattern in win_patterns:
		var owner := pattern_owner(board, pattern)
		if owner != 0:
			return owner
	if not is_board_full(board):
		return 0
	return -1

# Every pattern currently completed, as `{"player": int, "pattern": Variant}`
# entries in the order the patterns were generated.
static func completed_patterns(board: Array, win_patterns: Array) -> Array:
	var out: Array = []
	for pattern in win_patterns:
		var owner := pattern_owner(board, pattern)
		if owner != 0:
			out.append({"player": owner, "pattern": pattern})
	return out

# Completed patterns that the owning player hasn't banked yet. `claimed` maps
# player mark -> Dictionary of claim-key -> true, and is NOT modified here —
# the caller decides whether to bank what comes back (Main.gd does, in
# `_award_points`).
#
# This is what stops a player from farming the same pattern over and over by
# shifting pieces off it and back on: once banked, that claim key is worth
# nothing more to that player for the rest of the round. The other player can
# still score it.
#
# Results are deduplicated by (player, claim key), so a family of patterns
# that share a key — the side-squares subsets — yields at most one entry even
# when several of them complete on the same move. Where several patterns share
# a key, the highest-value one is the one returned.
static func collect_unclaimed(board: Array, win_patterns: Array, claimed: Dictionary) -> Array:
	var out: Array = []
	# Claim key -> index into `out`, so a later, better-paying pattern with the
	# same key replaces the one already collected.
	var seen: Dictionary = {}
	for pattern in win_patterns:
		var owner := pattern_owner(board, pattern)
		if owner == 0:
			continue
		var key: String = pattern_claim_key(pattern)
		var owned: Variant = claimed.get(owner, {})
		if typeof(owned) == TYPE_DICTIONARY and owned.has(key):
			continue
		var dedupe_key: String = "%d:%s" % [owner, key]
		if seen.has(dedupe_key):
			var at: int = seen[dedupe_key]
			if pattern_points(pattern) > pattern_points(out[at]["pattern"]):
				out[at] = {"player": owner, "pattern": pattern}
			continue
		seen[dedupe_key] = out.size()
		out.append({"player": owner, "pattern": pattern})
	return out

# Total points a player would hold if every listed pattern were theirs.
static func total_points(entries: Array, player: int) -> int:
	var sum := 0
	for entry in entries:
		if int(entry.get("player", 0)) == player:
			sum += pattern_points(entry.get("pattern", null))
	return sum

# ---------------------------------------------------------------------------
# Combinatorics
# ---------------------------------------------------------------------------

# n choose k, computed iteratively to keep the intermediate values small.
# Returns 0 for out-of-range k.
static func combination_count(n: int, k: int) -> int:
	if k < 0 or k > n:
		return 0
	if k == 0 or k == n:
		return 1
	var kk: int = mini(k, n - k)
	var result := 1
	for i in range(kk):
		result = result * (n - i) / (i + 1)
	return result

# All `k`-element subsets of `pool`, each in the pool's original order.
# Iterative (index-odometer) rather than recursive so deep k values don't
# grow the call stack.
static func combinations(pool: Array, k: int) -> Array:
	var out: Array = []
	var n: int = pool.size()
	if k < 0 or k > n:
		return out
	if k == 0:
		out.append([])
		return out

	var idx: Array = []
	for i in range(k):
		idx.append(i)
	while true:
		var combo: Array = []
		for i in idx:
			combo.append(pool[i])
		out.append(combo)
		# Advance the odometer: find the rightmost index with room to grow.
		var pos := k - 1
		while pos >= 0 and idx[pos] == n - k + pos:
			pos -= 1
		if pos < 0:
			break
		idx[pos] += 1
		for j in range(pos + 1, k):
			idx[j] = idx[j - 1] + 1
	return out
