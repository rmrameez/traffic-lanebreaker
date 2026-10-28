extends Node2D
## Traffic Lanebreaker: an endless top-down highway dodger.
## Scene: res://scenes/main.tscn. Spawns traffic, runs the game loop and drives the HUD.

enum State { TITLE, COUNTDOWN, PLAYING, CRASHED, GAME_OVER }

const PlayerCar := preload("res://scripts/player.gd")
const TrafficCar := preload("res://scripts/traffic_car.gd")

const VIEW := Vector2(672, 1120)
const ROAD_LEFT := 36.0
const LANE_W := 60.0
const LANES := 10
const ONCOMING_LANES := 2       # lanes 0..1 drive toward you
const ROAD_TILE_H := 160.0
const PX_PER_KMH := 3.0         # screen pixels per second for every km/h of speed
const PLAYER_Y := 900.0
const START_LANE := 6

const START_SPEED := 120.0      # km/h; faster than any traffic so nothing comes from behind
const MAX_SPEED := 320.0
const SPEED_STEP := 15.0
const SPEED_STEP_TIME := 8.0    # seconds between speed-ups
const BRAKE_FLOOR := 115.0
const NEAR_MISS_GAP := 12.0     # px of clearance that counts as a near miss
const KM_TO_MI := 0.621371
const SAVE_PATH := "user://traffic_lanebreaker.cfg"

const CAR_KINDS := [
	{"prefix": "sedan", "count": 6, "weight": 5.0, "speed": Vector2(60, 100)},
	{"prefix": "hatch", "count": 4, "weight": 3.0, "speed": Vector2(55, 95)},
	{"prefix": "sports", "count": 3, "weight": 1.5, "speed": Vector2(85, 110)},
	{"prefix": "van", "count": 3, "weight": 2.0, "speed": Vector2(55, 85)},
	{"prefix": "truck", "count": 2, "weight": 1.2, "speed": Vector2(45, 70)},
	{"prefix": "bus", "count": 2, "weight": 0.8, "speed": Vector2(45, 65)},
]

static var _quick_restart := false  # skip the title screen after "play again"

var state := State.TITLE
var player_kmh := 0.0
var target_kmh := START_SPEED
var distance_km := 0.0
var best_km := 0.0
var near_misses := 0
var use_miles := false

var _kinds: Array = []
var _traffic: Array = []
var _elapsed := 0.0
var _step_timer := 0.0
var _road_scroll := 0.0
var _spawn_accum := 0.0
var _countdown := 0.0
var _state_timer := 0.0
var _shake := 0.0
var _touch_dir := 0.0
var _new_record := false
var _view_top := 0.0           # world y of the top screen edge; below 0 on tall phones

var _smoke_tex: Texture2D = preload("res://assets/sprites/smoke.png")
var _spark_tex: Texture2D = preload("res://assets/sprites/spark.png")
var _hud_font: Font = load("res://assets/fonts/hud_font.tres")
var _traffic_scene: PackedScene = load("res://scenes/traffic_car.tscn")

@onready var _road: Sprite2D = %Road
@onready var _traffic_root: Node2D = %Traffic
@onready var _fx_root: Node2D = %FX
@onready var _player: PlayerCar = %Player
@onready var _you_marker: Node2D = %YouMarker
@onready var _camera: Camera2D = %Camera2D

@onready var _snd_engine: AudioStreamPlayer = %EngineSound
@onready var _snd_crash: AudioStreamPlayer = %CrashSound
@onready var _snd_whoosh: AudioStreamPlayer = %WhooshSound
@onready var _snd_horn: AudioStreamPlayer = %HornSound
@onready var _snd_beep: AudioStreamPlayer = %BeepSound
@onready var _snd_go: AudioStreamPlayer = %GoSound
@onready var _snd_speed_up: AudioStreamPlayer = %SpeedUpSound

@onready var _hud: CanvasLayer = %HUD
@onready var _dist_caption: Label = %DistCaption
@onready var _dist_value: Label = %DistValue
@onready var _speed_value: Label = %SpeedValue
@onready var _best_label: Label = %BestLabel
@onready var _near_label: Label = %NearLabel
@onready var _center_label: Label = %CenterLabel
@onready var _flash: ColorRect = %Flash
@onready var _title_panel: Control = %TitlePanel
@onready var _title_best: Label = %TitleBest
@onready var _over_panel: Control = %GameOverPanel
@onready var _over_stats: Label = %OverStats
@onready var _over_record: Label = %OverRecord
@onready var _pause_panel: Control = %PausePanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	randomize()
	_setup_input()
	_load_save()
	_load_kinds()
	_fit_to_screen()
	get_viewport().size_changed.connect(_fit_to_screen)

	_player.road_left = ROAD_LEFT
	_player.road_right = ROAD_LEFT + LANE_W * LANES
	_player.crashed.connect(_on_player_crashed)
	%PauseButton.pressed.connect(_toggle_pause)
	_make_looping(_snd_engine)
	for l in get_tree().get_nodes_in_group("blink"):
		_blink(l)
	_center_label.text = ""
	_update_hud()

	# `godot -- --quick` skips the title screen (handy while developing).
	if _quick_restart or OS.get_cmdline_user_args().has("--quick"):
		_quick_restart = false
		_start_countdown()
	else:
		_title_panel.visible = true


# ================================================================= setup

func _setup_input() -> void:
	_add_action("steer_left", [KEY_LEFT, KEY_A])
	_add_action("steer_right", [KEY_RIGHT, KEY_D])
	_add_action("brake", [KEY_DOWN, KEY_S])
	_add_action("pause", [KEY_P, KEY_ESCAPE])
	_add_action("start", [KEY_SPACE, KEY_ENTER])
	_add_action("toggle_units", [KEY_U])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_km = cfg.get_value("score", "best_km", 0.0)
		use_miles = cfg.get_value("settings", "miles", false)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best_km", best_km)
	cfg.set_value("settings", "miles", use_miles)
	cfg.save(SAVE_PATH)


func _load_kinds() -> void:
	for kind in CAR_KINDS:
		var textures: Array[Texture2D] = []
		for i in kind["count"]:
			textures.append(load("res://assets/sprites/%s_%d.png" % [kind["prefix"], i]))
		var k: Dictionary = kind.duplicate()
		k["textures"] = textures
		_kinds.append(k)


## Phones are taller than VIEW. The extra height opens up above the road, so the
## player keeps the same distance from the bottom edge and sees further ahead.
func _fit_to_screen() -> void:
	var h := get_viewport_rect().size.y
	_view_top = VIEW.y - h
	_camera.position = Vector2(VIEW.x * 0.5, VIEW.y - h * 0.5)
	_road.position.y = _view_top - 24.0
	_road.region_rect.size.y = h + 48.0


## The engine sample is one seamless second; make it loop.
func _make_looping(player: AudioStreamPlayer) -> void:
	var wav := player.stream as AudioStreamWAV
	if wav == null:
		return
	wav = wav.duplicate()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
	player.stream = wav


# ================================================================= HUD

func _blink(l: CanvasItem) -> void:
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "modulate:a", 0.25, 0.5)
	tw.tween_property(l, "modulate:a", 1.0, 0.5)


func _update_hud() -> void:
	var factor := KM_TO_MI if use_miles else 1.0
	_dist_caption.text = "MILES" if use_miles else "KM"
	_dist_value.text = "%.3f" % (distance_km * factor)
	_speed_value.text = "%d" % roundi(player_kmh * factor)
	var unit := "mi" if use_miles else "km"
	_best_label.text = "BEST %.2f %s" % [best_km * factor, unit]
	_title_best.text = "BEST: %.2f %s" % [best_km * factor, unit] if best_km > 0.0 else ""
	_near_label.text = "NEAR MISS x%d" % near_misses if near_misses > 0 else ""


## Floating text that rises and fades, e.g. "NEAR MISS!".
func _popup(text: String, color: Color, pos: Vector2, size := 30) -> void:
	var ls := LabelSettings.new()
	ls.font = _hud_font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	var l := Label.new()
	l.text = text
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = get_viewport().get_canvas_transform() * pos - Vector2(150, 20)
	l.size.x = 300
	_hud.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func _flash_center(text: String, color: Color, duration := 0.9, font_size := 64) -> void:
	_center_label.text = text
	_center_label.label_settings.font_color = color
	_center_label.label_settings.font_size = font_size
	_center_label.modulate.a = 1.0
	var tw := _center_label.create_tween()
	tw.tween_interval(duration * 0.6)
	tw.tween_property(_center_label, "modulate:a", 0.0, duration * 0.4)

# ================================================================= input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("toggle_units"):
		use_miles = not use_miles
		_save()
		_update_hud()
	elif event.is_action_pressed("start"):
		_on_start_pressed()
	elif event is InputEventMouseButton:
		# Touch arrives as emulated mouse events.
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if state == State.TITLE or state == State.GAME_OVER:
				_on_start_pressed()
			else:
				_touch_dir = -1.0 if mb.position.x < VIEW.x * 0.5 else 1.0
		else:
			_touch_dir = 0.0
	elif event is InputEventMouseMotion and _touch_dir != 0.0:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_touch_dir = -1.0 if mm.position.x < VIEW.x * 0.5 else 1.0


func _on_start_pressed() -> void:
	if get_tree().paused:
		return
	if state == State.TITLE:
		_title_panel.visible = false
		_start_countdown()
	elif state == State.GAME_OVER and _state_timer > 0.6:
		_quick_restart = true
		get_tree().reload_current_scene()


func _toggle_pause() -> void:
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	get_tree().paused = not get_tree().paused
	_pause_panel.visible = get_tree().paused
	_touch_dir = 0.0


# ================================================================= game flow

func _start_countdown() -> void:
	state = State.COUNTDOWN
	_countdown = 3.0
	_center_label.text = "3"
	_center_label.label_settings.font_size = 64
	_center_label.modulate.a = 1.0
	_snd_beep.play()
	# Some traffic already on the road ahead, but never in the starting lane.
	for i in 12:
		var lane := randi() % LANES
		if lane == START_LANE:
			continue
		_try_spawn_in_lane(lane, randf_range(_view_top - 500.0, PLAYER_Y - 260.0), _pick_kind())


func _start_race() -> void:
	state = State.PLAYING
	player_kmh = 0.0
	target_kmh = START_SPEED
	_flash_center("GO!", Color(0.35, 1.0, 0.35), 0.8)
	_snd_go.play()
	_snd_engine.play()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_state_timer += delta
	match state:
		State.COUNTDOWN:
			_process_countdown(delta)
		State.PLAYING:
			_process_driving(delta)
		State.CRASHED:
			player_kmh = move_toward(player_kmh, 0.0, 200.0 * delta)
			_scroll(delta)
			_update_traffic(delta)
			if _state_timer > 1.6:
				_show_game_over()
		State.GAME_OVER:
			player_kmh = move_toward(player_kmh, 0.0, 200.0 * delta)
			_scroll(delta)
			_update_traffic(delta)

	_you_marker.position = _player.position
	_you_marker.visible = state == State.COUNTDOWN or (state == State.PLAYING and _elapsed < 3.0)
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, 30.0 * delta)
		_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if state != State.TITLE:
		_update_hud()


func _process_countdown(delta: float) -> void:
	var before := ceili(_countdown)
	_countdown -= delta
	var now := ceili(_countdown)
	if _countdown <= 0.0:
		_start_race()
	elif now != before:
		_center_label.text = str(now)
		_snd_beep.play()


func _process_driving(delta: float) -> void:
	_elapsed += delta

	# Speed climbs in steps up to the limit; braking only slows you temporarily.
	_step_timer += delta
	if _step_timer >= SPEED_STEP_TIME and target_kmh < MAX_SPEED:
		_step_timer = 0.0
		target_kmh = minf(MAX_SPEED, target_kmh + SPEED_STEP)
		_flash_center("MAX SPEED!" if target_kmh >= MAX_SPEED else "SPEED UP!", Color(1.0, 0.85, 0.2), 1.2, 48)
		_snd_speed_up.play()
	var braking := Input.is_action_pressed("brake")
	var want := maxf(BRAKE_FLOOR, target_kmh * 0.6) if braking else target_kmh
	var rate := 160.0 if braking else (120.0 if player_kmh < START_SPEED else 45.0)
	player_kmh = move_toward(player_kmh, want, rate * delta)
	distance_km += player_kmh * delta / 3600.0

	var steer := Input.get_axis("steer_left", "steer_right") + _touch_dir
	_player.steer_input = clampf(steer, -1.0, 1.0)
	_player.speed_kmh = player_kmh

	_snd_engine.pitch_scale = 0.55 + player_kmh / MAX_SPEED * 1.3
	_scroll(delta)
	_spawn_traffic(delta)
	_update_traffic(delta)
	_check_passes()


func _scroll(delta: float) -> void:
	_road_scroll = fmod(_road_scroll + player_kmh * PX_PER_KMH * delta, ROAD_TILE_H)
	_road.region_rect.position.y = -_road_scroll


func _on_player_crashed(other: Area2D) -> void:
	state = State.CRASHED
	_state_timer = 0.0
	_player.steer_input = 0.0
	var dir := -1.0 if other.position.x > _player.position.x else 1.0
	_player.spin_out(dir)
	var hit_car := other as TrafficCar
	if hit_car:
		hit_car.wreck(-dir)
	var hit_pos: Vector2 = (_player.position + other.position) * 0.5
	_explode(hit_pos)
	_shake = 16.0
	_snd_engine.stop()
	_snd_crash.play()
	_center_label.text = ""
	var flash_tw := _flash.create_tween()
	_flash.color.a = 0.8
	flash_tw.tween_property(_flash, "color:a", 0.0, 0.3)
	# Brief slow motion.
	Engine.time_scale = 0.35
	get_tree().create_timer(0.7, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _show_game_over() -> void:
	state = State.GAME_OVER
	_state_timer = 0.0
	_new_record = distance_km > best_km
	if _new_record:
		best_km = distance_km
		_save()
	var factor := KM_TO_MI if use_miles else 1.0
	var unit := "MILES" if use_miles else "KM"
	_over_stats.text = "DISTANCE  %.3f %s\nNEAR MISSES  %d\nBEST  %.3f %s" % [
		distance_km * factor, unit, near_misses, best_km * factor, unit]
	_over_record.visible = _new_record
	_over_panel.visible = true


# ================================================================= traffic

func _lane_x(lane: int) -> float:
	return ROAD_LEFT + LANE_W * (lane + 0.5)


func _pick_kind() -> Dictionary:
	var total := 0.0
	for k in _kinds:
		total += k["weight"]
	var r := randf() * total
	for k in _kinds:
		r -= k["weight"]
		if r <= 0.0:
			return k
	return _kinds[0]


## True when nothing occupies `lane` between y0 and y1 (top to bottom).
func _lane_clear(lane: int, y0: float, y1: float, ignore: Area2D = null) -> bool:
	for car in _traffic:
		if car == ignore or (car.lane != lane and car.prev_lane != lane):
			continue
		if car.position.y + car.size.y * 0.5 > y0 and car.position.y - car.size.y * 0.5 < y1:
			return false
	return true


func _try_spawn_in_lane(lane: int, y: float, kind: Dictionary) -> bool:
	var tex: Texture2D = kind["textures"].pick_random()
	var h := tex.get_height()
	if not _lane_clear(lane, y - h * 0.5 - 180.0, y + h * 0.5 + 140.0):
		return false
	var oncoming := lane < ONCOMING_LANES
	var speed: Vector2 = kind["speed"]
	var car := _traffic_scene.instantiate() as TrafficCar
	car.position = Vector2(_lane_x(lane), y)
	_traffic_root.add_child(car)
	car.setup(tex, lane, oncoming, randf_range(speed.x, speed.y), randf() < 0.3)
	_traffic.append(car)
	return true


func _spawn_traffic(delta: float) -> void:
	_spawn_accum += player_kmh * PX_PER_KMH * delta
	# Traffic gets denser the longer you survive.
	var gap := lerpf(300.0, 165.0, clampf(_elapsed / 150.0, 0.0, 1.0)) * 6.0 / LANES
	if _spawn_accum < gap:
		return
	_spawn_accum = 0.0

	# Always leave at least two lanes open near the top of the screen.
	var blocked := 0
	for lane in LANES:
		if not _lane_clear(lane, _view_top - 420.0, _view_top + 60.0):
			blocked += 1
	if blocked >= LANES - 2:
		return
	var kind := _pick_kind()
	var lanes := range(LANES)
	lanes.shuffle()
	for lane in lanes.slice(0, 3):
		var tex_h: float = kind["textures"][0].get_height()
		if _try_spawn_in_lane(lane, _view_top - tex_h * 0.5 - 30.0, kind):
			return


func _update_traffic(delta: float) -> void:
	# Each driver slows to the speed of the car in front in its lane.
	for car in _traffic:
		var limit: float = car.cruise_kmh
		for other in _traffic:
			if other == car or (other.lane != car.lane and other.prev_lane != car.lane):
				continue
			# "Ahead" is up the screen for same-direction cars, down for oncoming ones.
			var gap: float
			if car.oncoming:
				gap = (other.position.y - other.size.y * 0.5) - (car.position.y + car.size.y * 0.5)
			else:
				gap = (car.position.y - car.size.y * 0.5) - (other.position.y + other.size.y * 0.5)
			if gap < 0.0 or gap > 240.0:
				continue
			limit = minf(limit, other.speed_kmh)
			if gap < 30.0:
				car.speed_kmh = minf(car.speed_kmh, other.speed_kmh)
		car.target_kmh = limit

		if state == State.PLAYING and car.change_delay > 0.0 and car.change_delay <= delta + 0.0001:
			_try_lane_change(car)
		car.advance(delta, player_kmh, PX_PER_KMH)

	for car in _traffic.duplicate():
		if car.position.y > VIEW.y + 220.0 or car.position.y < _view_top - 1400.0:
			_traffic.erase(car)
			car.queue_free()


func _try_lane_change(car: TrafficCar) -> void:
	var dirs := [-1, 1]
	dirs.shuffle()
	for dir in dirs:
		var target: int = car.lane + dir
		if target < ONCOMING_LANES or target >= LANES:
			continue
		var half: float = car.size.y * 0.5
		if _lane_clear(target, car.position.y - half - 150.0, car.position.y + half + 150.0, car):
			car.begin_lane_change(dir, _lane_x(target))
			return
	car.change_delay = 0.8  # blocked; try again shortly


func _check_passes() -> void:
	var p_top: float = _player.position.y - _player.size.y * 0.5
	var p_bottom: float = _player.position.y + _player.size.y * 0.5
	for car in _traffic:
		if car.wrecked:
			continue
		var dx: float = absf(car.position.x - _player.position.x)
		var side_gap: float = dx - (car.size.x + _player.size.x) * 0.5

		# Oncoming car heading straight at you: it honks.
		if car.oncoming and not car.honked and side_gap < 4.0 \
				and car.position.y < p_top and p_top - car.position.y < 700.0:
			car.honked = true
			_snd_horn.pitch_scale = randf_range(0.9, 1.1)
			_snd_horn.play()

		# Car has fully passed the player: was it close?
		if not car.passed and car.position.y - car.size.y * 0.5 > p_bottom:
			car.passed = true
			if side_gap < NEAR_MISS_GAP:
				near_misses += 1
				_snd_whoosh.pitch_scale = randf_range(0.9, 1.2)
				_snd_whoosh.play()
				_popup("NEAR MISS!", Color(1.0, 0.85, 0.2), Vector2(_player.position.x, p_top - 30.0), 26)


# ================================================================= effects

func _explode(pos: Vector2) -> void:
	var fire := _particles(_smoke_tex, 40, 0.9, Vector2(60, 240), Vector2(0.6, 1.8), [
		Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.45, 0.1, 0.9),
		Color(0.25, 0.25, 0.25, 0.6), Color(0.2, 0.2, 0.2, 0.0)])
	fire.position = pos
	_fx_root.add_child(fire)
	fire.emitting = true

	var sparks := _particles(_spark_tex, 34, 0.5, Vector2(200, 520), Vector2(0.6, 1.2), [
		Color(1.0, 1.0, 0.7, 1.0), Color(1.0, 0.6, 0.1, 0.8), Color(1.0, 0.3, 0.0, 0.0)])
	sparks.position = pos
	_fx_root.add_child(sparks)
	sparks.emitting = true

	# The wreck keeps smoking.
	var smoke := _particles(_smoke_tex, 24, 1.4, Vector2(20, 70), Vector2(0.8, 2.4), [
		Color(0.35, 0.35, 0.35, 0.0), Color(0.3, 0.3, 0.3, 0.55), Color(0.2, 0.2, 0.2, 0.0)])
	smoke.one_shot = false
	smoke.explosiveness = 0.0
	smoke.spread = 25.0
	_player.add_child(smoke)
	smoke.emitting = true


func _particles(tex: Texture2D, amount: int, lifetime: float, velocity: Vector2,
		scale_range: Vector2, colors: Array) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = velocity.x
	p.initial_velocity_max = velocity.y
	p.damping_min = 120.0
	p.damping_max = 220.0
	p.scale_amount_min = scale_range.x
	p.scale_amount_max = scale_range.y
	var ramp := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	p.color_ramp = ramp
	return p
