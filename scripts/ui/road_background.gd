extends Control
## Slowly scrolling road used behind the menu screens.

@export var texture: Texture2D = preload("res://assets/sprites/road_country.png")
@export var speed := 220.0       # px per second
@export var dim := Color(0.10, 0.09, 0.16, 0.45)

var _scroll := 0.0


func _process(delta: float) -> void:
	_scroll = fmod(_scroll + speed * delta, float(texture.get_height()))
	queue_redraw()


func _draw() -> void:
	var tex_size := texture.get_size()
	# Centre the road horizontally; the wide roadside covers the rest.
	var x := (size.x - tex_size.x) * 0.5
	var y := _scroll - tex_size.y
	while y < size.y:
		draw_texture(texture, Vector2(x, y))
		y += tex_size.y
	draw_rect(Rect2(Vector2.ZERO, size), dim)
