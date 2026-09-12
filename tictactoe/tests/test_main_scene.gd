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
	test_config_dialog_fits_its_contents(root)
	test_layout_fits_the_design_viewport(root)
	test_stretch_settings_scale_the_ui(root)
	test_clamped_window_size(root)
	test_win_condition_diagrams(root)
	test_diagrams_dim_when_condition_is_off(root)
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

# Ticking a condition that can't produce any pattern on this board is the same
# as ticking nothing, so the line fallback has to kick in there too.
func test_unavailable_edges_condition_falls_back_to_lines(root: Window) -> void:
	var main := _make_main(root)
	# A 3x3 has only four non-corner edge cells, so "any 5" is unsatisfiable.
	_configure(main, main.WinMode.FIRST, 5, {
		"line": {"enabled": false, "points": 3},
		"edges": {"enabled": true, "points": 1, "count": 5},
	})
	_expect_eq(main.win_patterns.size(), 8, "an unsatisfiable condition should fall back to lines")
	_expect_true(
		bool(main.pattern_config["line"]["enabled"]), "the line condition should be forced back on")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Dialog validation warnings
# ---------------------------------------------------------------------------

func test_no_warning_for_a_sane_config(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.POINTS, 5, {
		"line": {"enabled": true, "points": 3},
		"edges": {"enabled": true, "points": 1, "count": 3},
	})
	_expect_eq(main._win_rule_warning(), "", "a workable config should warn about nothing")
	_free_main(root, main)

func test_warning_when_board_has_too_few_edge_cells(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.POINTS, 5, {
		"line": {"enabled": true, "points": 3},
		"edges": {"enabled": true, "points": 1, "count": 5},
	})
	var warning: String = main._win_rule_warning()
	_expect_true(warning.contains("never happen"),
		"should warn that 'any 5' is impossible on a 3x3, got: %s" % warning)
	# The live label is kept in step with it, not just the function.
	_expect_eq(main.pattern_warn_label.text, warning, "warning label should show the warning")
	_free_main(root, main)

# 12x12 has 40 non-corner edge cells; "any 8" of those is ~77 million
# combinations, so generation refuses and the dialog says so.
func test_warning_when_edge_combinations_exceed_the_cap(root: Window) -> void:
	var main := _make_main(root)
	_select_mnk(main, 12, 12, 5)
	_configure(main, main.WinMode.POINTS, 5, {
		"line": {"enabled": true, "points": 3},
		"edges": {"enabled": true, "points": 1, "count": 8},
	})
	var warning: String = main._win_rule_warning()
	_expect_true(warning.contains("limit"),
		"should warn that the combination count is over the cap, got: %s" % warning)
	# The board still works — lines are unaffected, the edges condition is just
	# dropped.
	_expect_true(main.win_patterns.size() > 0, "lines should still be generated")
	for pattern in main.win_patterns:
		if String(pattern["kind"]) == GameLogic.KIND_EDGES:
			failures.append("over-cap edges condition should have produced no patterns")
			break
	_free_main(root, main)

func test_warning_when_nothing_is_ticked(root: Window) -> void:
	var main := _make_main(root)
	for kind in main.pattern_controls:
		main.pattern_controls[kind]["check"].button_pressed = false
	var warning: String = main._win_rule_warning()
	_expect_true(warning.contains("No win condition"),
		"should warn when nothing is ticked, got: %s" % warning)
	_free_main(root, main)

# The 4x4 preset has always meant "lines plus 2x2 squares plus diamonds", so
# choosing it re-seeds those two checkboxes; the other modes clear them.
func test_four_by_four_preset_reseeds_squares_and_diamonds(root: Window) -> void:
	var main := _make_main(root)
	_select_grid_mode(main, main.GridMode.FOUR)
	_expect_true(bool(main.pattern_controls[GameLogic.KIND_SQUARE]["check"].button_pressed),
		"4x4 should switch the 2x2-square condition on")
	_expect_true(bool(main.pattern_controls[GameLogic.KIND_DIAMOND]["check"].button_pressed),
		"4x4 should switch the diamond condition on")
	main._on_restart_pressed()
	# 4 rows + 4 cols + 2 diagonals + 9 squares + 4 diamonds = 23.
	_expect_eq(main.win_patterns.size(), 23, "4x4 preset should give the classic 23 conditions")

	_select_grid_mode(main, main.GridMode.THREE)
	_expect_false(bool(main.pattern_controls[GameLogic.KIND_SQUARE]["check"].button_pressed),
		"3x3 should switch the 2x2-square condition back off")
	_expect_false(bool(main.pattern_controls[GameLogic.KIND_DIAMOND]["check"].button_pressed),
		"3x3 should switch the diamond condition back off")
	_free_main(root, main)

# The New Game dialog's window size is hand-set in the scene, so it needs a
# guard: big enough for the controls it holds (the win-condition grid made it
# considerably taller), and still small enough to fit the game's viewport.
func test_config_dialog_fits_its_contents(root: Window) -> void:
	var main := _make_main(root)
	var dialog: Window = main.config_dialog
	# Measure it as the user sees it. popup_centered grows the window to its
	# contents minimum, so checking beforehand would test the scene's stored
	# size rather than the size actually shown.
	dialog.popup_centered()
	var needed: Vector2 = dialog.get_contents_minimum_size()
	_expect_true(float(dialog.size.x) >= needed.x,
		"config dialog is %dpx wide but needs %d" % [dialog.size.x, int(needed.x)])
	_expect_true(float(dialog.size.y) >= needed.y,
		"config dialog is %dpx tall but needs %d" % [dialog.size.y, int(needed.y)])

	# It's an embedded subwindow, so it has to fit the viewport it pops up in.
	var viewport_w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 760))
	var viewport_h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 1040))
	_expect_true(dialog.size.x <= viewport_w,
		"config dialog (%dpx) is wider than the %dpx viewport" % [dialog.size.x, viewport_w])
	_expect_true(dialog.size.y <= viewport_h,
		"config dialog (%dpx) is taller than the %dpx viewport" % [dialog.size.y, viewport_h])
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Scaling to different screens
# ---------------------------------------------------------------------------

# The whole scaling scheme rests on one invariant: the layout has to fit the
# design viewport in project.godot. The stretch mode guarantees the logical
# viewport never shrinks below that size, so if the content fits here it fits
# at every window size — and if it doesn't, controls run off the bottom on
# every screen. That's exactly how the bottom row went missing once, so this
# test fails if the layout outgrows the design size again (add a row, bump the
# viewport height to match).
func test_layout_fits_the_design_viewport(root: Window) -> void:
	var main := _make_main(root)
	var vbox: Control = main.get_node("VBox")
	var needed: Vector2 = vbox.get_combined_minimum_size()
	var design := _design_viewport()
	# The VBox is inset from the viewport edges; count that against the budget.
	var inset := 16.0
	_expect_true(needed.y + inset <= design.y,
		"layout needs %dpx of height (+%d inset) but the design viewport is only %d — "
		% [int(needed.y), int(inset), int(design.y)]
		+ "raise display/window/size/viewport_height in project.godot")
	_expect_true(needed.x + inset <= design.x,
		"layout needs %dpx of width (+%d inset) but the design viewport is only %d"
		% [int(needed.x), int(inset), int(design.x)])
	_free_main(root, main)

# The stretch settings are what make the UI scale with the window instead of
# being clipped by it. They're invisible in the scene tree and easy to drop, so
# assert them directly: without canvas_items the UI doesn't scale at all, and
# without "expand" the viewport can shrink below the design size and clip.
func test_stretch_settings_scale_the_ui(_root: Window) -> void:
	_expect_eq(
		String(ProjectSettings.get_setting("display/window/stretch/mode", "disabled")),
		"canvas_items",
		"display/window/stretch/mode must be canvas_items or the UI won't scale to the window")
	_expect_eq(
		String(ProjectSettings.get_setting("display/window/stretch/aspect", "ignore")),
		"expand",
		"display/window/stretch/aspect must be expand or the viewport can clip the layout")

# The arithmetic behind shrinking the window onto a screen that can't fit it.
# Pure, so the awkward cases are checked without needing those screens.
func test_clamped_window_size(root: Window) -> void:
	var main := _make_main(root)
	var desired := Vector2i(720, 980)
	var decorations := Vector2i(16, 39)
	var margin := 24

	# Roomy screen: nothing to do.
	_expect_eq(main.clamped_window_size(desired, Vector2i(2560, 1400), decorations, margin),
		desired, "a screen with room should leave the window alone")

	# 1080p with a taskbar — the case that broke: 1040 usable, minus a 39px
	# title bar and margin, leaves 977, so the 980-tall window has to shrink.
	_expect_eq(main.clamped_window_size(desired, Vector2i(1920, 1040), decorations, margin),
		Vector2i(720, 977), "a 1080p desktop should shrink the window to fit")

	# A short laptop panel clamps height while leaving width alone.
	_expect_eq(main.clamped_window_size(desired, Vector2i(1366, 728), decorations, margin),
		Vector2i(720, 665), "a short screen should clamp the height")

	# Absurdly small screens stop at the minimum rather than shrinking to
	# nothing — better to overflow than to be unusable.
	var tiny: Vector2i = main.clamped_window_size(desired, Vector2i(320, 200), decorations, margin)
	_expect_eq(tiny, main.MIN_WINDOW_SIZE, "a tiny screen should floor at the minimum size")
	_free_main(root, main)

# ---------------------------------------------------------------------------
# Win-condition diagrams
# ---------------------------------------------------------------------------

# Every condition gets a diagram, each drawing a different shape. A diagram
# that silently ends up blank or duplicated is the kind of thing that looks
# fine in code and wrong on screen, so check the actual cell sets.
func test_win_condition_diagrams(root: Window) -> void:
	var main := _make_main(root)
	var seen: Dictionary = {}
	for kind in main.pattern_controls:
		var icon: Variant = main.pattern_controls[kind].get("icon", null)
		_expect_true(icon != null, "%s has no diagram" % kind)
		if icon == null:
			continue
		var cells: Array = icon.filled
		_expect_true(cells.size() >= 3, "%s diagram should mark at least 3 cells" % kind)
		# Every cell has to be on the 3x3 the diagram draws.
		for idx in cells:
			_expect_true(int(idx) >= 0 and int(idx) < 9,
				"%s diagram cell %s is off the 3x3" % [kind, str(idx)])
		var signature := "%s" % [cells]
		_expect_false(seen.has(signature),
			"%s draws the same shape as %s" % [kind, str(seen.get(signature, ""))])
		seen[signature] = kind
	_expect_eq(seen.size(), 5, "all five conditions should draw a distinct shape")
	_free_main(root, main)

# An unticked condition's diagram is faded, so the grid can be read at a
# glance without checking each box.
func test_diagrams_dim_when_condition_is_off(root: Window) -> void:
	var main := _make_main(root)
	_configure(main, main.WinMode.FIRST, 5, {
		"line": {"enabled": true, "points": 3},
		"corners": {"enabled": false, "points": 2},
	})
	var lit: Control = main.pattern_controls[GameLogic.KIND_LINE]["icon"]
	var dim: Control = main.pattern_controls[GameLogic.KIND_CORNERS]["icon"]
	_expect_eq(lit.modulate.a, 1.0, "an enabled condition's diagram should be fully opaque")
	_expect_true(dim.modulate.a < 1.0, "a disabled condition's diagram should be faded")

	# Ticking it live brightens it without needing to start a game.
	main.pattern_controls[GameLogic.KIND_CORNERS]["check"].button_pressed = true
	_expect_eq(dim.modulate.a, 1.0, "ticking a condition should brighten its diagram")
	_free_main(root, main)

# The design resolution the layout is built against, from project.godot.
func _design_viewport() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 720)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 980)))

# ---------------------------------------------------------------------------
# Harness helpers
# ---------------------------------------------------------------------------

# Pick a grid mode the way a user would, including the signal handler that
# re-seeds the preset's shape checkboxes (OptionButton.select alone doesn't
# emit item_selected).
func _select_grid_mode(main: Node, mode: int) -> void:
	var idx: int = main.grid_size_option.get_item_index(mode)
	main.grid_size_option.select(idx)
	main._on_grid_size_selected(idx)

func _select_mnk(main: Node, rows: int, cols: int, k: int) -> void:
	_select_grid_mode(main, main.GridMode.MNK)
	main.mnk_m_spin.value = float(rows)
	main.mnk_n_spin.value = float(cols)
	main.mnk_k_spin.value = float(k)

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
