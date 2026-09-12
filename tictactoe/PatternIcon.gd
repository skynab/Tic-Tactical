extends Control

# A small diagram of one win condition: a miniature board with the cells the
# shape needs drawn as solid marks and the rest as empty outlines. One sits
# beside each checkbox in the New Game dialog's win-condition list so the
# shapes are recognizable at a glance instead of having to be read.
#
# Everything is drawn in _draw() rather than assembled from child nodes, so
# each diagram is a single cheap Control. Configured from Main.gd via setup().
#
# The diagrams are illustrative, not a render of the live rules: every one is
# drawn on a 3x3 so they sit side by side and compare directly, whatever board
# size or K value the game is actually set to.

# Diagram dimensions (not the game board's).
var cols: int = 3
var rows: int = 3
# Cell indices, row-major into cols x rows, drawn as filled marks.
var filled: Array = []

# Filled cells use the X player's blue so the diagrams read as "pieces".
const COLOR_FILL := Color(0.4, 0.8, 1.0)
const COLOR_FILL_BORDER := Color(0.65, 0.9, 1.0)
const COLOR_EMPTY := Color(0.16, 0.16, 0.21)
const COLOR_EMPTY_BORDER := Color(0.34, 0.34, 0.42)

# Gap between cells, in pixels.
const CELL_GAP := 2.0

func setup(p_cols: int, p_rows: int, p_filled: Array) -> void:
	cols = maxi(1, p_cols)
	rows = maxi(1, p_rows)
	filled = p_filled.duplicate()
	queue_redraw()

func _draw() -> void:
	# Square cells, as large as fit, centered in whatever space the grid gives
	# us — so the diagram stays square even in a wider cell.
	var cell := minf(
		(size.x - CELL_GAP * float(cols - 1)) / float(cols),
		(size.y - CELL_GAP * float(rows - 1)) / float(rows))
	if cell <= 0.0:
		return
	var used := Vector2(
		cell * float(cols) + CELL_GAP * float(cols - 1),
		cell * float(rows) + CELL_GAP * float(rows - 1))
	var origin := (size - used) * 0.5

	var is_filled: Dictionary = {}
	for idx in filled:
		is_filled[int(idx)] = true

	# Build the two styles once rather than per cell.
	var style_on := _cell_style(true, cell)
	var style_off := _cell_style(false, cell)

	for r in range(rows):
		for c in range(cols):
			var rect := Rect2(
				origin + Vector2(float(c) * (cell + CELL_GAP), float(r) * (cell + CELL_GAP)),
				Vector2(cell, cell))
			draw_style_box(style_on if is_filled.has(r * cols + c) else style_off, rect)

# StyleBoxFlat is used rather than draw_rect because it gives rounded corners,
# matching the rounded board cells in Cell.gd.
func _cell_style(on: bool, cell: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FILL if on else COLOR_EMPTY
	style.border_color = COLOR_FILL_BORDER if on else COLOR_EMPTY_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	var radius := int(maxf(2.0, cell * 0.22))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
