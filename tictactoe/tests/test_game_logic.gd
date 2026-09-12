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
	# Scored win patterns
	test_edge_indices()
	test_edge_indices_tiny_board()
	test_combination_count()
	test_combinations()
	test_make_pattern_shape()
	test_make_pattern_id_is_order_independent()
	test_line_patterns_carry_points()
	test_corners_patterns()
	test_edge_patterns_3x3()
	test_edge_patterns_availability()
	test_edge_patterns_unavailable_returns_empty()
	test_square_and_diamond_patterns()
	test_build_patterns_honors_config()
	test_build_patterns_defaults_to_disabled()
	test_build_patterns_dedupes_identical_shapes()
	test_pattern_accessors_handle_bare_arrays()
	test_pattern_owner()
	test_is_board_full()
	test_check_winner_accepts_scored_patterns()
	test_completed_patterns()
	test_collect_unclaimed_basic()
	test_collect_unclaimed_dedupes_shared_claim_key()
	test_collect_unclaimed_skips_already_claimed()
	test_collect_unclaimed_is_per_player()
	test_collect_unclaimed_prefers_higher_points_per_key()
	test_total_points()
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
# Scored win patterns — cell sets carrying a point value, plus the claim
# bookkeeping that stops a player from farming the same shape twice.
# ---------------------------------------------------------------------------

# Non-corner border cells. 3x3 → the four edge midpoints; 4x4 → eight cells.
func test_edge_indices() -> void:
	_expect_array_eq(GameLogic.edge_indices(3, 3), [1, 3, 5, 7], "3x3 edge cells wrong")
	_expect_array_eq(
		GameLogic.edge_indices(4, 4), [1, 2, 4, 7, 8, 11, 13, 14], "4x4 edge cells wrong")
	# Rectangular: cols=5, rows=3. Top row 1,2,3; middle 5,9; bottom 11,12,13.
	_expect_array_eq(
		GameLogic.edge_indices(5, 3), [1, 2, 3, 5, 9, 11, 12, 13], "5x3 edge cells wrong")

# A 2x2 board is all corners, so there are no side squares at all.
func test_edge_indices_tiny_board() -> void:
	_expect_eq(GameLogic.edge_indices(2, 2).size(), 0, "2x2 should have no edge cells")

func test_combination_count() -> void:
	_expect_eq(GameLogic.combination_count(4, 3), 4, "C(4,3) should be 4")
	_expect_eq(GameLogic.combination_count(8, 3), 56, "C(8,3) should be 56")
	_expect_eq(GameLogic.combination_count(5, 0), 1, "C(5,0) should be 1")
	_expect_eq(GameLogic.combination_count(5, 5), 1, "C(5,5) should be 1")
	_expect_eq(GameLogic.combination_count(3, 4), 0, "C(3,4) should be 0")
	_expect_eq(GameLogic.combination_count(40, 8), 76904685, "C(40,8) wrong")

func test_combinations() -> void:
	var combos := GameLogic.combinations([1, 3, 5, 7], 3)
	_expect_eq(combos.size(), 4, "4 choose 3 should give 4 combinations")
	_expect_contains(combos, [1, 3, 5], "combination [1,3,5] missing")
	_expect_contains(combos, [1, 3, 7], "combination [1,3,7] missing")
	_expect_contains(combos, [1, 5, 7], "combination [1,5,7] missing")
	_expect_contains(combos, [3, 5, 7], "combination [3,5,7] missing")
	# Edge cases: k=0 yields one empty subset, k>n yields nothing.
	_expect_eq(GameLogic.combinations([1, 2], 0).size(), 1, "k=0 should give one empty subset")
	_expect_eq(GameLogic.combinations([1, 2], 3).size(), 0, "k>n should give no subsets")

func test_make_pattern_shape() -> void:
	var pattern := GameLogic.make_pattern(GameLogic.KIND_CORNERS, [0, 2, 6, 8], 2)
	_expect_eq(String(pattern["kind"]), GameLogic.KIND_CORNERS, "pattern kind wrong")
	_expect_array_eq(pattern["cells"], [0, 2, 6, 8], "pattern cells wrong")
	_expect_eq(int(pattern["points"]), 2, "pattern points wrong")
	_expect_eq(String(pattern["id"]), "corners:0,2,6,8", "pattern id wrong")
	# With no explicit claim key, a pattern claims under its own id.
	_expect_eq(String(pattern["claim"]), "corners:0,2,6,8", "pattern claim key should default to id")
	_expect_eq(GameLogic.pattern_name(pattern), "Four corners", "pattern name wrong")

# Ids are built from sorted cells, so the same shape described in a different
# order produces the same id — that's what makes claim tracking reliable.
func test_make_pattern_id_is_order_independent() -> void:
	var a := GameLogic.make_pattern(GameLogic.KIND_LINE, [2, 4, 6], 3)
	var b := GameLogic.make_pattern(GameLogic.KIND_LINE, [6, 4, 2], 3)
	_expect_eq(String(a["id"]), String(b["id"]), "reordered cells should give the same id")

func test_line_patterns_carry_points() -> void:
	var patterns := GameLogic.line_patterns(3, 3, 3, 7)
	_expect_eq(patterns.size(), 8, "3x3 k=3 should give 8 line patterns")
	for pattern in patterns:
		if GameLogic.pattern_points(pattern) != 7:
			failures.append("line pattern should be worth 7, got %d"
				% GameLogic.pattern_points(pattern))
			return

func test_corners_patterns() -> void:
	var patterns := GameLogic.corners_patterns(3, 3, 2)
	_expect_eq(patterns.size(), 1, "corners should produce exactly one pattern")
	_expect_array_eq(GameLogic.pattern_cells(patterns[0]), [0, 2, 6, 8], "corners cells wrong")
	_expect_eq(GameLogic.pattern_points(patterns[0]), 2, "corners points wrong")

# "Any 3 of the side squares" on a 3x3: the four 3-subsets of [1,3,5,7].
# All of them share one claim key so the condition pays once per round.
func test_edge_patterns_3x3() -> void:
	var patterns := GameLogic.edge_patterns(3, 3, 3, 1)
	_expect_eq(patterns.size(), 4, "3x3 'any 3 sides' should give 4 patterns")
	_expect_contains(_cells_of(patterns), [1, 3, 5], "edge subset [1,3,5] missing")
	for pattern in patterns:
		if GameLogic.pattern_claim_key(pattern) != GameLogic.KIND_EDGES:
			failures.append("edge patterns should share the '%s' claim key, got '%s'"
				% [GameLogic.KIND_EDGES, GameLogic.pattern_claim_key(pattern)])
			return

func test_edge_patterns_availability() -> void:
	_expect_eq(GameLogic.edge_patterns_available(3, 3, 3), true, "3x3 any-3 should be available")
	# A 3x3 has only four edge cells, so "any 5" is impossible.
	_expect_eq(GameLogic.edge_patterns_available(3, 3, 5), false, "3x3 any-5 should be unavailable")
	# 12x12 has 40 edge cells; C(40,8) is ~77 million, way over the cap.
	_expect_eq(
		GameLogic.edge_patterns_available(12, 12, 8), false, "12x12 any-8 should exceed the cap")
	_expect_eq(GameLogic.edge_combination_count(4, 4, 3), 56, "4x4 any-3 should be 56 combinations")

func test_edge_patterns_unavailable_returns_empty() -> void:
	_expect_eq(GameLogic.edge_patterns(3, 3, 5, 1).size(), 0, "impossible count should give no patterns")
	_expect_eq(GameLogic.edge_patterns(12, 12, 8, 1).size(), 0, "over-cap count should give no patterns")

func test_square_and_diamond_patterns() -> void:
	_expect_eq(GameLogic.square_patterns(4, 4, 2).size(), 9, "4x4 should have 9 2x2 squares")
	_expect_eq(GameLogic.diamond_patterns(4, 4, 2).size(), 4, "4x4 should have 4 diamonds")
	# A 3x3 has exactly one interior cell, so exactly one diamond.
	_expect_eq(GameLogic.diamond_patterns(3, 3, 2).size(), 1, "3x3 should have 1 diamond")
	_expect_eq(GameLogic.diamond_patterns(2, 2, 2).size(), 0, "2x2 should have no diamonds")

func test_build_patterns_honors_config() -> void:
	# Lines only — same count as the classic 3x3 line set.
	var lines_only := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_LINE: {"enabled": true, "points": 3},
	})
	_expect_eq(lines_only.size(), 8, "lines-only 3x3 should give 8 patterns")

	# Lines + corners + any-3-sides = 8 + 1 + 4 = 13.
	var mixed := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_LINE: {"enabled": true, "points": 3},
		GameLogic.KIND_CORNERS: {"enabled": true, "points": 2},
		GameLogic.KIND_EDGES: {"enabled": true, "points": 1, "count": 3},
	})
	_expect_eq(mixed.size(), 13, "lines+corners+sides 3x3 should give 13 patterns")

	# Point values come from the config, per kind.
	var by_kind: Dictionary = {}
	for pattern in mixed:
		by_kind[String(pattern["kind"])] = GameLogic.pattern_points(pattern)
	_expect_eq(by_kind.get(GameLogic.KIND_LINE, 0), 3, "line points should be 3")
	_expect_eq(by_kind.get(GameLogic.KIND_CORNERS, 0), 2, "corners points should be 2")
	_expect_eq(by_kind.get(GameLogic.KIND_EDGES, 0), 1, "edges points should be 1")

# Kinds absent from the config, or present but not enabled, contribute nothing.
func test_build_patterns_defaults_to_disabled() -> void:
	_expect_eq(GameLogic.build_patterns(3, 3, 3, {}).size(), 0, "empty config should give no patterns")
	var disabled := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_LINE: {"enabled": false, "points": 3},
		GameLogic.KIND_CORNERS: {"enabled": false, "points": 2},
	})
	_expect_eq(disabled.size(), 0, "all-disabled config should give no patterns")

# k=1 makes the line generator emit each single cell four times over (once per
# direction). build_patterns collapses them by id, so a 3x3 yields 9, not 36.
func test_build_patterns_dedupes_identical_shapes() -> void:
	_expect_eq(GameLogic.generate_win_lines(3, 3, 1, false).size(), 36,
		"k=1 generator should emit one line per cell per direction")
	var patterns := GameLogic.build_patterns(3, 3, 1, {
		GameLogic.KIND_LINE: {"enabled": true, "points": 1},
	})
	_expect_eq(patterns.size(), 9, "k=1 should collapse to one pattern per cell")

# The accessors tolerate the older bare-index-array shape, which is what keeps
# check_winner working when handed generate_win_lines output directly.
func test_pattern_accessors_handle_bare_arrays() -> void:
	_expect_array_eq(GameLogic.pattern_cells([0, 1, 2]), [0, 1, 2], "bare array cells wrong")
	_expect_eq(GameLogic.pattern_points([0, 1, 2]), 0, "bare array should be worth 0 points")
	_expect_eq(GameLogic.pattern_id([0, 1, 2]), "0,1,2", "bare array id wrong")
	_expect_eq(GameLogic.pattern_claim_key([0, 1, 2]), "0,1,2", "bare array claim key wrong")

func test_pattern_owner() -> void:
	var board := _empty_3x3()
	var pattern := GameLogic.make_pattern(GameLogic.KIND_CORNERS, [0, 2, 6, 8], 2)
	_expect_eq(GameLogic.pattern_owner(board, pattern), 0, "empty board should have no owner")
	board[0] = 1; board[2] = 1; board[6] = 1
	_expect_eq(GameLogic.pattern_owner(board, pattern), 0, "partial pattern should have no owner")
	board[8] = 1
	_expect_eq(GameLogic.pattern_owner(board, pattern), 1, "completed pattern should be owned by X")
	board[8] = 2
	_expect_eq(GameLogic.pattern_owner(board, pattern), 0, "mixed marks should have no owner")

func test_is_board_full() -> void:
	_expect_eq(GameLogic.is_board_full(_empty_3x3()), false, "empty board is not full")
	_expect_eq(GameLogic.is_board_full([1, 2, 1, 1, 2, 2, 2, 1, 1]), true, "filled board is full")

# check_winner works the same whether it's handed scored patterns or bare
# lines, and an optional condition (corners) can win the round on its own.
func test_check_winner_accepts_scored_patterns() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_LINE: {"enabled": true, "points": 3},
		GameLogic.KIND_CORNERS: {"enabled": true, "points": 2},
	})
	var board := _empty_3x3()
	board[0] = 2; board[2] = 2; board[6] = 2; board[8] = 2
	_expect_eq(GameLogic.check_winner(board, patterns), 2, "four corners should win for O")
	_expect_eq(GameLogic.check_winner(_empty_3x3(), patterns), 0, "empty board should be in progress")

func test_completed_patterns() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_LINE: {"enabled": true, "points": 3},
		GameLogic.KIND_CORNERS: {"enabled": true, "points": 2},
	})
	var board := _empty_3x3()
	# X takes the top row; that completes one line and nothing else.
	board[0] = 1; board[1] = 1; board[2] = 1
	var completed := GameLogic.completed_patterns(board, patterns)
	_expect_eq(completed.size(), 1, "top row should complete exactly one pattern")
	_expect_eq(int(completed[0]["player"]), 1, "top-row pattern should belong to X")
	_expect_eq(GameLogic.pattern_points(completed[0]["pattern"]), 3, "top row should be worth 3")

func test_collect_unclaimed_basic() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_CORNERS: {"enabled": true, "points": 2},
	})
	var board := _empty_3x3()
	board[0] = 1; board[2] = 1; board[6] = 1; board[8] = 1
	var unclaimed := GameLogic.collect_unclaimed(board, patterns, {1: {}, 2: {}})
	_expect_eq(unclaimed.size(), 1, "four corners should be one unclaimed entry")
	_expect_eq(int(unclaimed[0]["player"]), 1, "corners should belong to X")

# Holding all four side squares completes four different 3-subsets, but that's
# one achievement — the shared claim key collapses them into a single payout.
func test_collect_unclaimed_dedupes_shared_claim_key() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_EDGES: {"enabled": true, "points": 1, "count": 3},
	})
	var board := _empty_3x3()
	board[1] = 1; board[3] = 1; board[5] = 1; board[7] = 1
	var unclaimed := GameLogic.collect_unclaimed(board, patterns, {1: {}, 2: {}})
	_expect_eq(unclaimed.size(), 1, "all four sides should pay out once, not four times")
	_expect_eq(GameLogic.total_points(unclaimed, 1), 1, "all four sides should be worth 1 point")

func test_collect_unclaimed_skips_already_claimed() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_EDGES: {"enabled": true, "points": 1, "count": 3},
	})
	var board := _empty_3x3()
	board[1] = 1; board[3] = 1; board[5] = 1
	var claimed := {1: {GameLogic.KIND_EDGES: true}, 2: {}}
	_expect_eq(GameLogic.collect_unclaimed(board, patterns, claimed).size(), 0,
		"a banked claim key should not pay again")

# One player's claim must not block the other's.
func test_collect_unclaimed_is_per_player() -> void:
	var patterns := GameLogic.build_patterns(3, 3, 3, {
		GameLogic.KIND_EDGES: {"enabled": true, "points": 1, "count": 3},
	})
	var board := _empty_3x3()
	board[1] = 2; board[3] = 2; board[5] = 2
	var claimed := {1: {GameLogic.KIND_EDGES: true}, 2: {}}
	var unclaimed := GameLogic.collect_unclaimed(board, patterns, claimed)
	_expect_eq(unclaimed.size(), 1, "X's claim should not block O")
	_expect_eq(int(unclaimed[0]["player"]), 2, "the unclaimed entry should belong to O")

# When several patterns share a claim key and complete together, the entry
# that survives dedup is the highest-paying one.
func test_collect_unclaimed_prefers_higher_points_per_key() -> void:
	var patterns := [
		GameLogic.make_pattern(GameLogic.KIND_EDGES, [1, 3], 1, GameLogic.KIND_EDGES),
		GameLogic.make_pattern(GameLogic.KIND_EDGES, [3, 5], 4, GameLogic.KIND_EDGES),
	]
	var board := _empty_3x3()
	board[1] = 1; board[3] = 1; board[5] = 1
	var unclaimed := GameLogic.collect_unclaimed(board, patterns, {1: {}, 2: {}})
	_expect_eq(unclaimed.size(), 1, "shared claim key should give one entry")
	_expect_eq(GameLogic.pattern_points(unclaimed[0]["pattern"]), 4,
		"the higher-paying pattern should win the dedup")

func test_total_points() -> void:
	var entries := [
		{"player": 1, "pattern": GameLogic.make_pattern(GameLogic.KIND_LINE, [0, 1, 2], 3)},
		{"player": 1, "pattern": GameLogic.make_pattern(GameLogic.KIND_CORNERS, [0, 2, 6, 8], 2)},
		{"player": 2, "pattern": GameLogic.make_pattern(GameLogic.KIND_EDGES, [1, 3, 5], 1)},
	]
	_expect_eq(GameLogic.total_points(entries, 1), 5, "X should total 5 points")
	_expect_eq(GameLogic.total_points(entries, 2), 1, "O should total 1 point")
	_expect_eq(GameLogic.total_points([], 1), 0, "no entries should total 0")

# ---------------------------------------------------------------------------
# Tiny assertion helpers — each records a failure instead of aborting so one
# bad test doesn't mask others.
# ---------------------------------------------------------------------------

# Strip a pattern list down to plain cell arrays so _expect_contains can be
# used against it.
func _cells_of(patterns: Array) -> Array:
	var out: Array = []
	for pattern in patterns:
		out.append(GameLogic.pattern_cells(pattern))
	return out

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
