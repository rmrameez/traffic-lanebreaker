extends SceneTree
## Renders the Android launcher icons from the SVG layers in assets/icon/.
## Run from the project folder:
##   godot --headless --path . --script res://tools/generate_icons.gd

const ICON_DIR := "res://assets/icon/"


func _init() -> void:
	var bg := _render("icon_background.svg", 432)
	var fg := _render("icon_foreground.svg", 432)
	_save(bg, "icon_background_432.png")
	_save(fg, "icon_foreground_432.png")

	# Legacy (non-adaptive) icon: the centre 2/3 a launcher would show, flattened.
	var full := bg.duplicate() as Image
	full.blend_rect(fg, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	var legacy := full.get_region(Rect2i(72, 72, 288, 288))
	legacy.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	_save(legacy, "icon_192.png")

	# Themed-icon monochrome layer: the foreground silhouette in white.
	var mono := fg.duplicate() as Image
	for y in mono.get_height():
		for x in mono.get_width():
			mono.set_pixel(x, y, Color(1, 1, 1, mono.get_pixel(x, y).a))
	_save(mono, "icon_monochrome_432.png")

	print("Traffic Lanebreaker icons generated.")
	quit()


func _render(file_name: String, size: int) -> Image:
	var svg := FileAccess.get_file_as_string(ICON_DIR + file_name)
	var img := Image.new()
	img.load_svg_from_string(svg, size / 432.0)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file_name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(ICON_DIR + file_name))
