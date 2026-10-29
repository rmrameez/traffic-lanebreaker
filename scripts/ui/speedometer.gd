extends Control
## Round speedometer for the HUD: coloured arc, needle, digital readout and a
## marker for the speed the car is climbing towards.

const START_ANGLE := deg_to_rad(135.0)
const SWEEP := deg_to_rad(270.0)
const NAVY := Color(0.17, 0.15, 0.24)

@export var max_kmh := 320.0

var kmh := 0.0          # current speed
var target_kmh := 0.0   # the next speed level
var shown_value := 0    # number printed in the middle (km/h or mph)
var unit := "KM/H"


func set_speed(current: float, target: float, value: int, unit_text: String) -> void:
	kmh = current
	target_kmh = target
	shown_value = value
	unit = unit_text
	queue_redraw()


func _angle(v: float) -> float:
	return START_ANGLE + SWEEP * clampf(v / max_kmh, 0.0, 1.0)


func _speed_color(t: float) -> Color:
	var green := Color(0.40, 0.85, 0.45)
	var yellow := Color(0.99, 0.74, 0.22)
	var red := Color(0.95, 0.33, 0.26)
	return green.lerp(yellow, t * 2.0) if t < 0.5 else yellow.lerp(red, (t - 0.5) * 2.0)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r + 3.0, NAVY)
	draw_circle(c, r, Color(0.24, 0.22, 0.33))

	# Track and coloured fill.
	var arc_r := r - 12.0
	draw_arc(c, arc_r, START_ANGLE, START_ANGLE + SWEEP, 48, Color(1, 1, 1, 0.12), 12.0, true)
	var t := clampf(kmh / max_kmh, 0.0, 1.0)
	if t > 0.005:
		draw_arc(c, arc_r, START_ANGLE, _angle(kmh), 48, _speed_color(t), 12.0, true)

	# Ticks every 40 km/h.
	for v in range(0, int(max_kmh) + 1, 40):
		var a := _angle(v)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (arc_r - 12.0), c + dir * (arc_r - 20.0), Color(1, 1, 1, 0.6), 2.0, true)

	# Next speed level marker.
	if target_kmh > 0.0:
		var a := _angle(target_kmh)
		var dir := Vector2(cos(a), sin(a))
		var tip := c + dir * (arc_r + 8.0)
		var side := Vector2(-dir.y, dir.x) * 5.0
		draw_colored_polygon(PackedVector2Array([tip, tip + dir * 10.0 + side, tip + dir * 10.0 - side]),
			Color(1, 1, 1, 0.85))

	# Needle.
	var na := _angle(kmh)
	draw_line(c, c + Vector2(cos(na), sin(na)) * (arc_r - 6.0), Color(0.95, 0.33, 0.26), 4.0, true)
	draw_circle(c, 7.0, NAVY)

	# Readout.
	var font := get_theme_default_font()
	var big := 34
	var text := str(shown_value)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_string_outline(font, c + Vector2(-w * 0.5, r * 0.55), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 6, NAVY)
	draw_string(font, c + Vector2(-w * 0.5, r * 0.55), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color.WHITE)
	var small := 14
	var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, c + Vector2(-uw * 0.5, r * 0.55 + 18.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
		Color(0.99, 0.74, 0.22))
