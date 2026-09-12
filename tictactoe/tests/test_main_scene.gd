extends RefCounted

# Integration tests that drive the real Main scene. Where test_game_logic.gd
# exercises the pure board math, these instantiate Main.tscn and play moves
# through it — which is what catches broken node paths in the scene/script
# wiring and mistakes in the turn/scoring flow that pure functions can't see.
#
# Each test builds its own fresh Main instance so nothing leaks between them.

var failures: Array = []

# `root` is the SceneTree root supplied by run_tests.gd; instances have to be
# added to it for _ready to fire.
func run_all(root: Window) -> Array:
	failures = []
	test_scene_wiring(root)
	test_classic_line_win(root)
	test_classic_corners_win(root)
	test_classic_points_are_ignored_for_the_verdict(root)
	test_points_mode_accumulates_without_ending(root)
	test_points_mode_wins_on_target(root)
	test_points_mode_claim_blocks_refarming(root)
	test_points_row_visibility_follows_win_mode(root)
	test_new_game_clears_round_points(root)
	test_empty_condition_set_falls_back_to_lines(root)
	test_unavailable_edges_condition_falls_back_to_lines(root)
	test_no_warning_for_a_sane_config(root)
	test_warning_when_board_has_too_few_edge_cells(root)
	test_warning_when_edge_combinations_exceed_the_cap(root)
	test_warning_when_nothing_is_ticked(root)
	test_four_by_four_preset_reseeds_squares_and_diamonds(root)
	return failures

# ---------------------------------------------------------------------------
# Scene wiring
# ---------------------------------------------------------------------------

# Every node the script reaches for has to exist, or _ready would have failed
# outright. This asserts the pieces the new win-condition UI depends on.
func test_scene_wiring(root: Window) -> void:
	var main := _make_main(root)
	_expect_eq(main.cells.size(), 9, "default board should have 9 cells")
	_expect_true(main.win_mode_option != null, "WinModeOption should be wired")
	_expect_true(main.points_target_spin != null, "PointsTargetSpinBox should be wired")
	_expect_true(main.points_row != null, "PointsRow should be wired")
	_expect_true(main.pattern_warn_label != null, "PatternWarnLabel should be wired")
	_expect_eq(main.pattern_controls.size(), 5, "every pattern kind should have dialog controls")
	for kind in main.pattern_controls:
		var controls: Dictionary = main.pattern_controls[kind]
		_expect_true(controls.get("check") != null, "%s check box missing" % kind)
		_expect_true(controls.get("points") != null, "%s points spinbox missing" % kind)
	# Default rules are the classic game: lines only, first-condition-wins.
	_expect_eq(main.win_mode, main.WinMode.FIRST, "default win mode should be FIRST")
	_expect_eq(main.win_patterns.size(), 8, "default 3x3 should have the 8 classic lines")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Classic mode — the first completed condition takes the round
# ---------------------------------------------------------------------------

func test_classic_line_win(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 5, {"line": {"enabled": true, "points": 3}})
	# X: 0, 1, 2 (top row) against O: 3, 4.
	_play(main, [0, 3, 1, 4, 2])
	_expect_true(main.game_over, "top row should end the round")
	_expect_eq(main.scores[1], 1, "X should have taken the round")
	_free_main(root, main)

# With k-in-a-row switched off and "four corners" on, the corners alone decide
# the round — the point of making win conditions configurable.
func test_classic_corners_win(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 5, {
		"line": {"enabled": false, "points": 3},
		"corners": {"enabled": true, "points": 2},
	})
	_expect_eq(main.win_patterns.size(), 1, "corners-only should give exactly one pattern")
	# X: 0, 2, 6, 8 (the corners) against O: 1, 3, 4.
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_true(main.game_over, "four corners should end the round")
	_expect_eq(main.scores[1], 1, "X should have taken the round on corners")
	_free_main(root, main)

# In classic mode points are still tracked for the status line, but they have
# no bearing on who wins — a 1-point condition ends the round just the same.
func test_classic_points_are_ignored_for_the_verdict(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 99, {
		"line": {"enabled": false, "points": 3},
		"corners": {"enabled": true, "points": 1},
	})
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_true(main.game_over, "a 1-point condition should still end a classic round")
	_expect_eq(main.scores[1], 1, "X should have taken the round")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Points mode — conditions bank points and play continues
# ---------------------------------------------------------------------------

# The same corners that end a classic round only bank 2 points here, and with
# the target out of reach the round carries on.
func test_points_mode_accumulates_without_ending(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.POINTS, 99, {
		"line": {"enabled": true, "points": 3},
		"corners": {"enabled": true, "points": 2},
	})
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_false(main.game_over, "round should continue while the target is out of reach")
	_expect_eq(main.round_points[1], 2, "X should have banked 2 points for the corners")
	_expect_eq(main.round_points[2], 0, "O should have banked nothing")
	_free_main(root, main)

func test_points_mode_wins_on_target(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.POINTS, 2, {
		"line": {"enabled": false, "points": 3},
		"corners": {"enabled": true, "points": 2},
	})
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_true(main.game_over, "reaching the points target should end the round")
	_expect_eq(main.round_points[1], 2, "X should have banked exactly the target")
	_expect_eq(main.scores[1], 1, "X should have taken the round on points")
	_free_main(root, main)

# The claim bookkeeping under shifting: a line that slides to a new position is
# a different shape and pays again, but sliding it back to one already banked
# pays nothing. Without this a player could farm one line forever.
func test_points_mode_claim_blocks_refarming(root: Window) -> void:
	var main := _make_main(root)
	# Arrows must not end the turn, so X can shift twice in a row.
	main.arrows_end_turn_checkbox.button_pressed = false
	_configure(main, main.WinMode.POINTS, 99, {"line": {"enabled": true, "points": 3}})
	_expect_false(main.arrows_end_turn, "arrows should not end the turn in this test")

	# Hand X the middle row directly, then score it.
	main.board[3] = 1; main.board[4] = 1; main.board[5] = 1
	main._refresh_cells()
	main._resolve_board(false)
	_expect_eq(main.round_points[1], 3, "middle row should bank 3 points")
	_expect_eq(main.current_player, 1, "X should still be on turn")

	# Shift up: the row lands on 0,1,2 — a different line, so it pays again.
	main._on_shift("up")
	_expect_eq(main.round_points[1], 6, "the line in a new position should pay again")

	# Shift back down: 3,4,5 is already banked, so nothing more is owed.
	main._on_shift("down")
	_expect_eq(main.round_points[1], 6, "re-forming an already-banked line should pay nothing")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# UI state and New Game
# ---------------------------------------------------------------------------

# The points readout is meaningless in classic mode, so it stays hidden there.
func test_points_row_visibility_follows_win_mode(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 5, {"line": {"enabled": true, "points": 3}})
	_expect_false(main.points_row.visible, "points row should be hidden in classic mode")
	_configure(main, main.WinMode.POINTS, 5, {"line": {"enabled": true, "points": 3}})
	_expect_true(main.points_row.visible, "points row should be shown in points mode")
	_free_main(root, main)

# A new game has to wipe both the banked points and the claim record, or the
# next round would start with conditions already spent.
func test_new_game_clears_round_points(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.POINTS, 99, {
		"line": {"enabled": true, "points": 3},
		"corners": {"enabled": true, "points": 2},
	})
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_eq(main.round_points[1], 2, "X should have banked the corners")
	main._on_restart_pressed()
	_expect_eq(main.round_points[1], 0, "new game should clear banked points")
	_expect_eq(main.claimed_patterns[1].size(), 0, "new game should clear the claim record")
	# And the corners must be scoreable all over again.
	_play(main, [0, 1, 2, 3, 6, 4, 8])
	_expect_eq(main.round_points[1], 2, "corners should pay again in a fresh round")
	_free_main(root, main)

# Unticking every condition would make the round unwinnable, so k-in-a-row is
# forced back on rather than handing the players a dead board.
func test_empty_condition_set_falls_back_to_lines(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 5, {
		"line": {"enabled": false, "points": 3},
		"corners": {"enabled": false, "points": 2},
		"edges": {"enabled": false, "points": 1, "count": 3},
		"square": {"enabled": false, "points": 2},
		"diamond": {"enabled": false, "points": 2},
	})
	_expect_eq(main.win_patterns.size(), 8, "an empty condition set should fall back to lines")
	_expect_true(
		bool(main.pattern_config["line"]["enabled"]), "the line condition should be forced back on")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Harness helpers
# ---------------------------------------------------------------------------

# Instantiate Main.tscn and add it to the tree so _ready runs.
func _make_main(root: Window) -> Node:
	var scene: PackedScene = load("res://Main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	return main

func _free_main(root: Window, main: Node) -> void:
	root.remove_child(main)
	main.free()

# Apply a rule set the way the New Game dialog would: push the config onto the
# dialog controls, then start a game, which reads them back. Going through the
# controls (rather than setting `pattern_config` directly) is deliberate — it
# covers the round trip the real UI performs.
#
# `config` may list only the kinds a test cares about; the rest are filled in
# as disabled.
func _configure(main: Node, mode: int, target: int, config: Dictionary) -> void:
	var full: Dictionary = {}
	for kind in main.pattern_config:
		var defaults: Dictionary = {"enabled": false, "points": 1}
		if kind == GameLogic.KIND_EDGES:
			defaults["count"] = 3
		var given: Variant = config.get(kind, null)
		if typeof(given) == TYPE_DICTIONARY:
			for key in given:
				defaults[key] = given[key]
		full[kind] = defaults
	main.pattern_config = full
	main._sync_pattern_controls_to_config()
	main.win_mode_option.select(main.win_mode_option.get_item_index(mode))
	main.points_target_spin.value = float(target)
	main._on_restart_pressed()

# Click the given cell indices in order, alternating players as the game does.
func _play(main: Node, indices: Array) -> void:
	for i in indices:
		main._on_cell_pressed(int(i))

func _expect_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [msg, str(expected), str(actual)])

func _expect_true(value: bool, msg: String) -> void:
	if not value:
		failures.append("%s (expected true)" % msg)

func _expect_false(value: bool, msg: String) -> void:
	if value:
		failures.append("%s (expected false)" % msg)
