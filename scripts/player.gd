extends Area2D
## The player's car: steering, body tilt and crash detection.
## Scene: res://scenes/player.tscn

signal crashed(other: Area2D)

const STEER_RESPONSE := 9.0

var steer_input := 0.0   # -1..1, set by the game every frame
var speed_kmh := 0.0     # set by the game; steering gets quicker at speed
var road_left := 0.0     # set by the game
var road_right := 2000.0
var alive := true
var size := Vector2.ZERO

var _vel_x := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _shadow: Sprite2D = $Shadow
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	set_car(_sprite.texture)
	area_entered.connect(_on_area_entered)


## Swaps the car sprite (from the garage) and resizes the hitbox to match.
func set_car(tex: Texture2D) -> void:
	_sprite.texture = tex
	_shadow.texture = tex
	# Body size without the mirror/padding margin baked into the sprites.
	size = Vector2(tex.get_width() - 8, tex.get_height() - 2)
	var shape := RectangleShape2D.new()
	shape.size = size - Vector2(6, 8)  # slightly forgiving
	_collision.shape = shape


func _physics_process(delta: float) -> void:
	var min_x := road_left + size.x * 0.5
	var max_x := road_right - size.x * 0.5
	if not alive:
		_vel_x = move_toward(_vel_x, 0.0, 300.0 * delta)
		position.x = clampf(position.x + _vel_x * delta, min_x, max_x)
		return
	var max_steer := 220.0 + speed_kmh * 0.9
	_vel_x = lerpf(_vel_x, steer_input * max_steer, minf(1.0, STEER_RESPONSE * delta))
	position.x += _vel_x * delta
	if position.x < min_x or position.x > max_x:
		position.x = clampf(position.x, min_x, max_x)
		_vel_x = 0.0
	rotation = _vel_x / max_steer * 0.2


## Spin out after a crash. `dir` is -1 or 1.
func spin_out(dir: float) -> void:
	_vel_x = dir * 160.0
	var tw := create_tween()
	tw.tween_property(self, "rotation", rotation + dir * TAU * 0.8, 1.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_area_entered(area: Area2D) -> void:
	if alive:
		alive = false
		crashed.emit(area)
