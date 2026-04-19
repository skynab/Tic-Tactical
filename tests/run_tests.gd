extends SceneTree

# Headless test runner. Invoked by CI via:
#   godot --headless --path <project_dir> --script res://tests/run_tests.gd
#
# Returns exit code 0 on success, 1 on any failure — that's what GitHub
# Actions checks to turn the workflow red or green.

func _init() -> void:
	print("Running unit tests...")
	var TestGameLogic = load("res://tests/test_game_logic.gd")
	if TestGameLogic == null:
		printerr("Could not load res://tests/test_game_logic.gd")
		quit(1)
		return
	var runner = TestGameLogic.new()
	var failures: Array = runner.run_all()
	if failures.is_empty():
		print("All tests passed.")
		quit(0)
	else:
		printerr("%d test failure(s):" % failures.size())
		for msg in failures:
			printerr("  - %s" % msg)
		quit(1)
