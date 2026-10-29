extends Node2D
## Traffic Lanebreaker: an endless top-down highway dodger.
## Scene: res://scenes/main.tscn. Spawns traffic, scores the run, tracks missions,
## changes scenery and drives the camera. The HUD is in scripts/hud.gd.

enum State { COUNTDOWN, PLAYING, CRASHED, GAME_OVER }

const PlayerCar := preload("res://scripts/player.gd")
const TrafficCar := preload("res://scripts/traffic_car.gd")
const Hud := preload("res://scripts/hud.gd")

const VIEW := Vector2(672, 1120)
const ROAD_LEFT := 36.0
const LANE_W := 60.0
const LANES := 10
const ONCOMING_LANES := 2       # lanes 0..1 drive toward you
const ROAD_TILE_H := 320.0
const ROAD_MARGIN := 120.0      # extra roadside baked into each side of the road tiles
const PX_PER_KMH := 3.0         # screen pixels per second for every km/h of speed
const PLAYER_Y := 900.0
const START_LANE := 6

const START_SPEED := 120.0      # km/h; faster than any traffic so nothing comes from behind
const MAX_SPEED := 320.0
const SPEED_STEP := 15.0
const SPEED_STEP_TIME := 8.0    # seconds between speed-ups
const BRAKE_FLOOR := 115.0
const NEAR_MISS_GAP := 12.0     # px of clearance that counts as a near miss

# Risk scoring: 1 point per metre, times the multiplier.
const CHAIN_TIME := 4.0         # seconds a near-miss chain lasts without another near miss
const CHAIN_STEP := 0.5         # multiplier added per near miss in the chain
const CHAIN_MAX := 8            # near misses that still raise the multiplier
const ONCOMING_BONUS := 1.0     # multiplier added while driving in the oncoming lanes
const NEAR_MISS_POINTS := 50    # bonus per near miss, times the multiplier

# Camera.
const ZOOM_MAX_OUT := 0.8       # camera zoom at top speed (1.0 at start speed)

# Scenery changes every SCENERY_KM.
const SCENERY_KM := 1.5
const SCENERY := ["country", "city", "desert", "snow"]
const SCENERY_NAMES := {"country": "COUNTRYSIDE", "city": "CITY", "desert": "DESERT", "snow": "SNOWLANDS"}

const CAR_KINDS := [
	{"prefix": "sedan", "count": 8, "weight": 5.0, "speed": Vector2(60, 100)},
	{"prefix": "hatch", "count": 4, "weight": 3.0, "speed": Vector2(55, 95)},
	{"prefix": "sports", "count": 3, "weight": 1.5, "speed": Vector2(85, 110)},
	{"prefix": "van", "count": 4, "weight": 2.0, "speed": Vector2(55, 85)},
	{"prefix": "truck", "count": 3, "weight": 1.2, "speed": Vector2(45, 70)},
	{"prefix": "bus", "count": 2, "weight": 0.8, "speed": Vector2(45, 65)},
]

var state := State.COUNTDOWN
var player_kmh := 0.0
var target_kmh := START_SPEED
var distance_km := 0.0
var score := 0.0
var near_misses := 0
var multiplier := 1.0
var in_oncoming := false

var _run := {"near": 0, "km": 0.0, "oncoming_km": 0.0, "score": 0, "speed": 0.0, "multiplier": 1.0}
var _completed: Array = []      # missions finished during this run
var _chain := 0
var _chain_timer := 0.0
var _mission_timer := 0.0
var _kinds: Array = []
var _traffic: Array = []
var _elapsed := 0.0
var _step_timer := 0.0
var _road_scroll := 0.0
var _spawn_accum := 0.0
var _countdown := 0.0
var _state_timer := 0.0
var _shake := 0.0
var _zoom := 1.0
var _touch_dir := 0.0
var _view_top := 0.0            # world y of the top screen edge; moves up as the camera zooms out
var _scenery_index := 0

var _smoke_tex: Texture2D = preload("res://assets/sprites/smoke.png")
var _spark_tex: Texture2D = preload("res://assets/sprites/spark.png")
var _traffic_scene: PackedScene = load("res://scenes/traffic_car.tscn")

@onready var _road: Sprite2D = %Road
@onready var _road_next: Sprite2D = %RoadNext
@onready var _traffic_root: Node2D = %Traffic
@onready var _fx_root: Node2D = %FX
@onready var _player: PlayerCar = %Player
@onready var _you_marker: Node2D = %YouMarker
@onready var _camera: Camera2D = %Camera2D
@onready var _hud: Hud = %HUD

@onready var _snd_engine: AudioStreamPlayer = %EngineSound
@onready var _snd_crash: AudioStreamPlayer = %CrashSound
@onready var _snd_whoosh: AudioStreamPlayer = %WhooshSound
@onready var _snd_horn: AudioStreamPlayer = %HornSound
@onready var _snd_beep: AudioStreamPlayer = %BeepSound
@onready var _snd_go: AudioStreamPlayer = %GoSound
@onready var _snd_speed_up: AudioStreamPlayer = %SpeedUpSound


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	randomize()
	_setup_input()
	_load_kinds()

	Profile.begin_run()
	_player.set_car(Profile.car_texture(Profile.selected_car))
	_player.road_left = ROAD_LEFT
	_player.road_right = ROAD_LEFT + LANE_W * LANES
	_player.crashed.connect(_on_player_crashed)
	_make_looping(_snd_engine)
	_set_scenery(0, false)
	_update_camera(0.0)

	_hud.pause_pressed.connect(_toggle_pause)
	_hud.resume_pressed.connect(_toggle_pause)
	_hud.restart_pressed.connect(_restart)
	_hud.menu_pressed.connect(_go_to.bind("res://scenes/menu.tscn"))
	_hud.garage_pressed.connect(_go_to.bind("res://scenes/garage.tscn"))
	_start_countdown()


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


func _load_kinds() -> void:
	for kind in CAR_KINDS:
		var textures: Array[Texture2D] = []
		for i in kind["count"]:
			textures.append(load("res://assets/sprites/%s_%d.png" % [kind["prefix"], i]))
		var k: Dictionary = kind.duplicate()
		k["textures"] = textures
		_kinds.append(k)


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


# ================================================================= camera & scenery

## Zooms out as speed rises and keeps the bottom screen edge at VIEW.y, so the
## player stays near the bottom and sees further ahead. Phones taller than VIEW
## also see further ahead.
func _update_camera(delta: float) -> void:
	var t := clampf((player_kmh - START_SPEED) / (MAX_SPEED - START_SPEED), 0.0, 1.0)
	var want := lerpf(1.0, ZOOM_MAX_OUT, t)
	_zoom = want if delta == 0.0 else lerpf(_zoom, want, minf(1.0, delta * 1.5))
	var h := get_viewport_rect().size.y / _zoom
	_view_top = VIEW.y - h
	_camera.zoom = Vector2(_zoom, _zoom)
	_camera.position = Vector2(VIEW.x * 0.5, VIEW.y - h * 0.5)
	for road in [_road, _road_next]:
		road.position = Vector2(-ROAD_MARGIN, _view_top - 24.0)
		road.region_rect.size = Vector2(road.texture.get_width(), h + 48.0)

	# Shake: a light rumble at high speed plus the crash shake.
	var amount := _shake
	if state == State.PLAYING:
		amount += maxf(0.0, (player_kmh - 200.0) / 120.0) * 2.0
	if not Profile.settings["shake"]:
		amount = 0.0
	_shake = move_toward(_shake, 0.0, 30.0 * delta)
	_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount


func _set_scenery(index: int, fade := true) -> void:
	_scenery_index = index
	var tex: Texture2D = load("res://assets/sprites/road_%s.png" % SCENERY[index])
	if not fade:
		_road.texture = tex
		_road_next.modulate.a = 0.0
		return
	_road_next.texture = tex
	_road_next.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_road_next, "modulate:a", 1.0, 2.0)
	tw.tween_callback(func():
		_road.texture = tex
		_road_next.modulate.a = 0.0)
	_hud.toast("ENTERING " + SCENERY_NAMES[SCENERY[index]], Color(1, 1, 1))


func _scroll(delta: float) -> void:
	_road_scroll = fmod(_road_scroll + player_kmh * PX_PER_KMH * delta, ROAD_TILE_H)
	_road.region_rect.position.y = -_road_scroll
	_road_next.region_rect.position.y = -_road_scroll


# ================================================================= input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("toggle_units"):
		Profile.set_setting("miles", not Profile.settings["miles"])
	elif event.is_action_pressed("start") and state == State.GAME_OVER and _state_timer > 0.6:
		_restart()
	elif event is InputEventMouseButton:
		# Touch arrives as emulated mouse events: hold the left or right half to steer.
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and (state == State.PLAYING or state == State.COUNTDOWN):
			_touch_dir = -1.0 if mb.position.x < VIEW.x * 0.5 else 1.0
		elif not mb.pressed:
			_touch_dir = 0.0
	elif event is InputEventMouseMotion and _touch_dir != 0.0:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_touch_dir = -1.0 if mm.position.x < VIEW.x * 0.5 else 1.0


func _notification(what: int) -> void:
	# Android back button pauses the race.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()


func _toggle_pause() -> void:
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	get_tree().paused = not get_tree().paused
	_hud.show_pause(get_tree().paused, _run)
	_touch_dir = 0.0


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _go_to(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)


# ================================================================= game flow

func _start_countdown() -> void:
	state = State.COUNTDOWN
	_countdown = 3.0
	_hud.flash_center("3", Color.WHITE, 1.0)
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
	_hud.flash_center("GO!", Color(0.40, 0.85, 0.45), 0.8)
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
		State.CRASHED, State.GAME_OVER:
			player_kmh = move_toward(player_kmh, 0.0, 200.0 * delta)
			_scroll(delta)
			_update_traffic(delta)
			if state == State.CRASHED and _state_timer > 1.6:
				_show_game_over()

	_update_camera(delta)
	_you_marker.position = _player.position
	_you_marker.visible = state == State.COUNTDOWN or (state == State.PLAYING and _elapsed < 3.0)
	var chain_left := _chain_timer / CHAIN_TIME if _chain > 0 else 0.0
	_hud.update_live(int(score), distance_km, player_kmh, target_kmh, multiplier, chain_left, in_oncoming, _run)


func _process_countdown(delta: float) -> void:
	var before := ceili(_countdown)
	_countdown -= delta
	var now := ceili(_countdown)
	if _countdown <= 0.0:
		_start_race()
	elif now != before:
		_hud.flash_center(str(now), Color.WHITE, 1.0)
		_snd_beep.play()


func _process_driving(delta: float) -> void:
	_elapsed += delta

	# Speed climbs in steps up to the limit; braking only slows you temporarily.
	_step_timer += delta
	if _step_timer >= SPEED_STEP_TIME and target_kmh < MAX_SPEED:
		_step_timer = 0.0
		target_kmh = minf(MAX_SPEED, target_kmh + SPEED_STEP)
		_hud.flash_center("MAX SPEED!" if target_kmh >= MAX_SPEED else "SPEED UP!", Color(0.99, 0.74, 0.22), 1.2, 48)
		_snd_speed_up.play()
	var braking := Input.is_action_pressed("brake")
	var want := maxf(BRAKE_FLOOR, target_kmh * 0.6) if braking else target_kmh
	var rate := 160.0 if braking else (120.0 if player_kmh < START_SPEED else 45.0)
	player_kmh = move_toward(player_kmh, want, rate * delta)

	var steer := Input.get_axis("steer_left", "steer_right") + _touch_dir
	_player.steer_input = clampf(steer, -1.0, 1.0)
	_player.speed_kmh = player_kmh
	_snd_engine.pitch_scale = 0.55 + player_kmh / MAX_SPEED * 1.3

	_update_score(delta)
	_scroll(delta)
	_spawn_traffic(delta)
	_update_traffic(delta)
	_check_passes()

	var scenery := int(distance_km / SCENERY_KM) % SCENERY.size()
	if scenery != _scenery_index:
		_set_scenery(scenery)


## Distance, risk multiplier, score and mission progress.
func _update_score(delta: float) -> void:
	var km := player_kmh * delta / 3600.0
	distance_km += km
	in_oncoming = _player.position.x < ROAD_LEFT + LANE_W * ONCOMING_LANES
	if in_oncoming:
		_run["oncoming_km"] += km
	if _chain > 0:
		_chain_timer -= delta
		if _chain_timer <= 0.0:
			_chain = 0
	multiplier = 1.0 + CHAIN_STEP * mini(_chain, CHAIN_MAX) + (ONCOMING_BONUS if in_oncoming else 0.0)
	score += km * 1000.0 * multiplier

	_run["km"] = distance_km
	_run["score"] = int(score)
	_run["near"] = near_misses
	_run["speed"] = maxf(_run["speed"], player_kmh)
	_run["multiplier"] = maxf(_run["multiplier"], multiplier)

	_mission_timer -= delta
	if _mission_timer <= 0.0:
		_mission_timer = 0.25
		for m in Profile.check_missions(_run):
			_completed.append(m)
			_hud.toast("MISSION COMPLETE!\n" + Profile.mission_text(m), Color(0.40, 0.85, 0.45))
			_snd_speed_up.play()


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
	Profile.vibrate(400)
	_hud.crash_flash()
	# Brief slow motion.
	Engine.time_scale = 0.35
	get_tree().create_timer(0.7, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _show_game_over() -> void:
	state = State.GAME_OVER
	_state_timer = 0.0
	var result := Profile.finish_run(_run)
	_hud.show_game_over(_run, result, _completed)


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
				_on_near_miss(p_top)


func _on_near_miss(p_top: float) -> void:
	near_misses += 1
	_chain += 1
	_chain_timer = CHAIN_TIME
	multiplier = 1.0 + CHAIN_STEP * mini(_chain, CHAIN_MAX) + (ONCOMING_BONUS if in_oncoming else 0.0)
	var bonus := roundi(NEAR_MISS_POINTS * multiplier)
	score += bonus
	_snd_whoosh.pitch_scale = randf_range(0.9, 1.2) + _chain * 0.03
	_snd_whoosh.play()
	Profile.vibrate(30)
	_hud.popup("NEAR MISS +%d" % bonus, Color(0.99, 0.74, 0.22), Vector2(_player.position.x, p_top - 30.0))


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
