extends Area2D
## A traffic vehicle. It moves relative to the player and may signal and change lanes.
## Scene: res://scenes/traffic_car.tscn. Add it to the tree before calling setup().

const BLINK_TIME := 0.9
const LANE_CHANGE_SPEED := 75.0  # px/s sideways

var lane := 0
var prev_lane := -1         # lane being left during a lane change, else -1
var oncoming := false
var cruise_kmh := 80.0      # the speed the driver wants
var target_kmh := 80.0      # cruise, limited by the car in front
var speed_kmh := 80.0
var size := Vector2.ZERO
var wrecked := false
var passed := false         # already went past the player (near-miss checked)
var honked := false
var change_delay := -1.0    # counts down to a lane-change attempt; < 0 = never

var _change_dir := 0
var _target_x := 0.0
var _blink_t := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _shadow: Sprite2D = $Shadow
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _blinker: Node2D = $Blinker


func _ready() -> void:
	_blinker.draw.connect(_draw_blinker)


func setup(tex: Texture2D, lane_idx: int, is_oncoming: bool, kmh: float, will_change: bool) -> void:
	lane = lane_idx
	oncoming = is_oncoming
	cruise_kmh = kmh
	target_kmh = kmh
	speed_kmh = kmh
	_sprite.texture = tex
	_shadow.texture = tex
	if oncoming:
		_sprite.rotation = PI
		_shadow.rotation = PI

	size = Vector2(tex.get_width() - 8, tex.get_height() - 2)
	# Each car gets its own shape, sized to its sprite.
	var shape := RectangleShape2D.new()
	shape.size = size - Vector2(4, 6)
	_collision.shape = shape
	if will_change and not oncoming:
		change_delay = randf_range(0.3, 2.5)


func is_changing_lane() -> bool:
	return _change_dir != 0


func begin_lane_change(dir: int, target_x: float) -> void:
	_change_dir = dir
	_target_x = target_x
	_blink_t = 0.0
	prev_lane = lane
	lane += dir
	change_delay = -1.0


## Move for one frame. Positive y is toward the bottom of the screen (behind the player).
func advance(delta: float, player_kmh: float, px_per_kmh: float) -> void:
	if wrecked:
		speed_kmh = move_toward(speed_kmh, 0.0, 150.0 * delta)
	else:
		speed_kmh = move_toward(speed_kmh, target_kmh, 70.0 * delta)
	var rel := player_kmh + speed_kmh if oncoming else player_kmh - speed_kmh
	position.y += rel * px_per_kmh * delta

	if change_delay > 0.0:
		change_delay -= delta
	if _change_dir != 0 and not wrecked:
		_blink_t += delta
		if _blink_t > BLINK_TIME:
			position.x = move_toward(position.x, _target_x, LANE_CHANGE_SPEED * delta)
			rotation = 0.12 * _change_dir
			if is_equal_approx(position.x, _target_x):
				_change_dir = 0
				prev_lane = -1
				rotation = 0.0
		_blinker.queue_redraw()


func wreck(spin_dir: float) -> void:
	wrecked = true
	_change_dir = 0
	_blinker.queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "rotation", rotation + spin_dir * TAU * 0.6, 1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position:x", position.x + spin_dir * 30.0, 1.0)


func _draw_blinker() -> void:
	if _change_dir == 0 or fmod(_blink_t, 0.4) > 0.2:
		return
	var x := _change_dir * (size.x * 0.5 - 1.0)
	var c := Color(1.0, 0.6, 0.05)
	_blinker.draw_circle(Vector2(x, -size.y * 0.5 + 4.0), 3.5, c)
	_blinker.draw_circle(Vector2(x, size.y * 0.5 - 4.0), 3.5, c)
