extends Button

@export var cell_index: int = 0

var mark: int = 0  # 0=empty, 1=X, 2=O

const COLOR_X := Color(0.4, 0.8, 1.0)
const COLOR_O := Color(1.0, 0.6, 0.4)
const COLOR_BG := Color(0.18, 0.18, 0.24)
const COLOR_HOVER := Color(0.22, 0.22, 0.30)
const COLOR_WIN_X := Color(0.2, 0.5, 0.8)
const COLOR_WIN_O := Color(0.7, 0.35, 0.15)
const COLOR_BONUS := Color(1.0, 0.85, 0.2)

# A small yellow star shown in the top-right of the cell to mark a
# "bonus corner" — placing on one of these grants the current player +1
# arrow use. Managed by Main.gd via set_bonus().
var bonus_icon: Label = null

func setup(_index: int) -> void:
	cell_index = _index
	apply_base_style()
	flat = false
	clip_contents = true

func apply_base_style() -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_BG
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = Color(0.3, 0.3, 0.4)
	style_normal.corner_radius_top_left = 10
	style_normal.corner_radius_top_right = 10
	style_normal.corner_radius_bottom_left = 10
	style_normal.corner_radius_bottom_right = 10
	add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = COLOR_HOVER
	style_hover.border_width_left = 2
	style_hover.border_width_right = 2
	style_hover.border_width_top = 2
	style_hover.border_width_bottom = 2
	style_hover.border_color = Color(0.5, 0.5, 0.65)
	style_hover.corner_radius_top_left = 10
	style_hover.corner_radius_top_right = 10
	style_hover.corner_radius_bottom_left = 10
	style_hover.corner_radius_bottom_right = 10
	add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.25, 0.25, 0.32)
	style_pressed.border_width_left = 2
	style_pressed.border_width_right = 2
	style_pressed.border_width_top = 2
	style_pressed.border_width_bottom = 2
	style_pressed.border_color = Color(0.5, 0.5, 0.65)
	style_pressed.corner_radius_top_left = 10
	style_pressed.corner_radius_top_right = 10
	style_pressed.corner_radius_bottom_left = 10
	style_pressed.corner_radius_bottom_right = 10
	add_theme_stylebox_override("pressed", style_pressed)

func set_mark(player: int) -> void:
	mark = player
	if player == 1:
		text = "X"
		add_theme_color_override("font_color", COLOR_X)
	else:
		text = "O"
		add_theme_color_override("font_color", COLOR_O)
	add_theme_font_size_override("font_size", 56)
	disabled = true

	# Dim the disabled style so it looks the same
	var style_dis := StyleBoxFlat.new()
	style_dis.bg_color = COLOR_BG
	style_dis.border_width_left = 2
	style_dis.border_width_right = 2
	style_dis.border_width_top = 2
	style_dis.border_width_bottom = 2
	style_dis.border_color = Color(0.3, 0.3, 0.4)
	style_dis.corner_radius_top_left = 10
	style_dis.corner_radius_top_right = 10
	style_dis.corner_radius_bottom_left = 10
	style_dis.corner_radius_bottom_right = 10
	add_theme_stylebox_override("disabled", style_dis)

func highlight_win(player: int) -> void:
	var bg = COLOR_WIN_X if player == 1 else COLOR_WIN_O
	var border = COLOR_X if player == 1 else COLOR_O

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = border
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	add_theme_stylebox_override("disabled", style)

	var txt_color = COLOR_X if player == 1 else COLOR_O
	add_theme_color_override("font_disabled_color", txt_color)

func reset() -> void:
	mark = 0
	text = ""
	disabled = false
	remove_theme_color_override("font_color")
	remove_theme_color_override("font_disabled_color")
	remove_theme_stylebox_override("disabled")
	apply_base_style()

# Show or hide the small yellow star that marks a "bonus corner". Called
# by Main.gd; it creates the Label lazily on first use and then toggles
# visibility. The star is rendered above the button text in the top-right.
func set_bonus(enabled: bool) -> void:
	if bonus_icon == null:
		if not enabled:
			return
		bonus_icon = Label.new()
		bonus_icon.text = "★"
		bonus_icon.add_theme_color_override("font_color", COLOR_BONUS)
		bonus_icon.add_theme_font_size_override("font_size", 18)
		bonus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Anchor the label to the button's top-right corner explicitly.
		bonus_icon.anchor_left = 1.0
		bonus_icon.anchor_right = 1.0
		bonus_icon.anchor_top = 0.0
		bonus_icon.anchor_bottom = 0.0
		bonus_icon.offset_left = -22.0
		bonus_icon.offset_right = -4.0
		bonus_icon.offset_top = 2.0
		bonus_icon.offset_bottom = 24.0
		bonus_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bonus_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(bonus_icon)
	bonus_icon.visible = enabled
