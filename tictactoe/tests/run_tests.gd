extends SceneTree

# Headless test runner. Invoked by CI via:
#   godot --headless --path <project_dir> --script res://tests/run_tests.gd
#
# Returns exit code 0 on success, 1 on any failure — that's what GitHub
# Actions checks to turn the workflow red or green. Note that a *parse* error
# in this file makes Godot exit 0 without running anything, so the CI step
# also greps for the success line; see .github/workflows/tests.yml.
#
# Runs two suites:
#   - test_game_logic.gd  — pure static board math, no scene tree needed.
#   - test_main_scene.gd  — instantiates Main.tscn and plays moves through it,
#                           which is what catches scene/script wiring breaks.

func _initialize() -> void:
	print("Running unit tests...")

# The suites run on the first idle frame rather than in _initialize: during
# initialization the SceneTree's root window is not yet inside the tree, so
# nodes added to it don't get _ready called until later — and the scene suite
# depends on _ready having run. Returning true ends the main loop.
func _process(_delta: float) -> bool:
	var failures: Array = []

	for suite in [
			{"path": "res://tests/test_game_logic.gd", "needs_root": false},
			{"path": "res://tests/test_main_scene.gd", "needs_root": true}]:
		var result: Variant = _run_suite(String(suite["path"]), bool(suite["needs_root"]))
		if result == null:
			quit(1)
			return true
		failures.append_array(result)

	if failures.is_empty():
		print("All tests passed.")
		quit(0)
	else:
		printerr("%d test failure(s):" % failures.size())
		for msg in failures:
			printerr("  - %s" % msg)
		quit(1)
	return true

# Load one test script and run it. Returns its failure list, or null when the
# script itself couldn't be loaded (already reported). `needs_root` picks which
# run_all signature to call.
#
# The can_instantiate check matters: a GDScript with a parse error still loads
# to a non-null object, and calling new() on it raises a runtime error that
# aborts this frame before quit() runs — which is how a broken test file ends
# up exiting 0. Checking first turns that into a clean reported failure.
func _run_suite(path: String, needs_root: bool) -> Variant:
	var script: Variant = load(path)
	if script == null:
		printerr("Could not load %s" % path)
		return null
	if not (script is GDScript) or not script.can_instantiate():
		printerr("Could not instantiate %s — parse error in the test script?" % path)
		return null
	var runner: Variant = script.new()
	if runner == null:
		printerr("Instantiating %s returned null" % path)
		return null
	if needs_root:
		return runner.run_all(root)
	return runner.run_all()
