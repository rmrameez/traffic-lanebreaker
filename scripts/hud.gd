extends CanvasLayer
## In-race HUD: score, risk multiplier, speedometer, missions, pause and game-over panels.
## Lives in res://scenes/main.tscn; scripts/game.gd feeds it every frame.

signal pause_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal garage_pressed

const YELLOW := Color(0.99, 0.74, 0.22)
const GREEN := Color(0.40, 0.85, 0.45)
const RED := Color(0.95, 0.33, 0.26)
const NAVY := Color(0.17, 0.15, 0.24)
const Speedometer := preload("res://scripts/ui/speedometer.gd")

var _shown_mult := -1.0

@onready var _score_value: Label = %ScoreValue
@onready var _best_value: Label = %BestValue
@onready var _dist_value: Label = %DistValue
@onready var _mult_badge: PanelContainer = %MultBadge
@onready var _mult_label: Label = %MultLabel
@onready var _chain_bar: ProgressBar = %ChainBar
@onready var _oncoming_label: Label = %OncomingLabel
@onready var _speedometer: Speedometer = %Speedometer
@onready var _mission_labels: Array = [%Mission0, %Mission1, %Mission2]
@onready var _center_label: Label = %CenterLabel
@onready var _toast_label: Label = %ToastLabel
@onready var _flash: ColorRect = %Flash
@onready var _pause_panel: Control = %PausePanel
@onready var _pause_missions: Label = %PauseMissions
@onready var _over_panel: Control = %GameOverPanel
@onready var _new_best: Label = %NewBestLabel
@onready var _over_stats: Label = %OverStats
@onready var _over_missions: Label = %OverMissions
@onready var _unlock_label: Label = %UnlockLabel


func _ready() -> void:
	%PauseButton.pressed.connect(pause_pressed.emit)
	%ResumeButton.pressed.connect(resume_pressed.emit)
	%RestartButton.pressed.connect(restart_pressed.emit)
	%PauseMenuButton.pressed.connect(menu_pressed.emit)
	%RetryButton.pressed.connect(restart_pressed.emit)
	%GarageButton.pressed.connect(garage_pressed.emit)
	%OverMenuButton.pressed.connect(menu_pressed.emit)
	_center_label.text = ""
	_toast_label.text = ""
	_best_value.text = "BEST " + Profile.format_score(Profile.stats["best_score"])
	var blink := _oncoming_label.create_tween().set_loops()
	blink.tween_property(_oncoming_label, "modulate:a", 0.45, 0.35)
	blink.tween_property(_oncoming_label, "modulate:a", 1.0, 0.35)


func update_live(score: int, km: float, kmh: float, target_kmh: float, multiplier: float,
		chain_left: float, in_oncoming: bool, run: Dictionary) -> void:
	_score_value.text = Profile.format_score(score)
	_dist_value.text = Profile.format_distance(km, 2)
	_speedometer.set_speed(kmh, target_kmh, Profile.speed_value(kmh), Profile.speed_unit())
	_chain_bar.value = chain_left * 100.0
	_chain_bar.visible = chain_left > 0.0
	_oncoming_label.visible = in_oncoming
	if not is_equal_approx(multiplier, _shown_mult):
		if multiplier > _shown_mult and _shown_mult > 0.0:
			_bump(_mult_badge)
		_shown_mult = multiplier
		_mult_label.text = "x%.1f" % multiplier
		# Badge colour heats up with the multiplier.
		var t := clampf((multiplier - 1.0) / 4.0, 0.0, 1.0)
		_mult_badge.self_modulate = YELLOW.lerp(RED, t) if multiplier > 1.0 else Color(0.75, 0.75, 0.8)
	for i in _mission_labels.size():
		var label: Label = _mission_labels[i]
		if i >= Profile.missions.size():
			label.text = ""
			continue
		var m: Dictionary = Profile.missions[i]
		var pct := roundi(Profile.mission_progress(m, run) * 100.0)
		label.text = ("DONE  " if m["done"] else "%d%%  " % pct) + Profile.mission_text(m)
		label.modulate = GREEN if m["done"] else Color.WHITE


func flash_center(text: String, color: Color, duration := 0.9, font_size := 64) -> void:
	_center_label.text = text
	_center_label.label_settings.font_color = color
	_center_label.label_settings.font_size = font_size
	_center_label.modulate.a = 1.0
	_center_label.pivot_offset = _center_label.size * 0.5
	_center_label.scale = Vector2(1.3, 1.3)
	var tw := _center_label.create_tween()
	tw.tween_property(_center_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration * 0.5)
	tw.tween_property(_center_label, "modulate:a", 0.0, duration * 0.3)


## Message under the score, e.g. a new scenery or a finished mission.
func toast(text: String, color: Color) -> void:
	_toast_label.text = text
	_toast_label.label_settings.font_color = color
	_toast_label.modulate.a = 0.0
	var tw := _toast_label.create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.0)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


## Floating text that rises and fades at a world position, e.g. "NEAR MISS +75".
func popup(text: String, color: Color, world_pos: Vector2) -> void:
	var ls := LabelSettings.new()
	ls.font = _center_label.label_settings.font
	ls.font_size = 26
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = NAVY
	var l := Label.new()
	l.text = text
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = get_viewport().get_canvas_transform() * world_pos - Vector2(150, 20)
	l.size.x = 300
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func crash_flash() -> void:
	_center_label.text = ""
	_flash.color.a = 0.8
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.3)


func show_pause(paused: bool, run: Dictionary) -> void:
	_pause_panel.visible = paused
	if paused:
		_pause_missions.text = _missions_text(run)
		%ResumeButton.grab_focus()


func show_game_over(run: Dictionary, result: Dictionary, completed: Array) -> void:
	var lines := PackedStringArray([
		"SCORE   " + Profile.format_score(run["score"]),
		"DISTANCE   " + Profile.format_distance(run["km"], 2),
		"NEAR MISSES   %d" % run["near"],
		"TOP MULTIPLIER   x%.1f" % run["multiplier"],
		"BEST SCORE   " + Profile.format_score(Profile.stats["best_score"]),
	])
	_over_stats.text = "\n".join(lines)
	_new_best.visible = result["best_score"]
	if completed.is_empty():
		_over_missions.text = ""
	else:
		var done := PackedStringArray()
		for m in completed:
			done.append("DONE  " + Profile.mission_text(m))
		_over_missions.text = "MISSIONS COMPLETED\n" + "\n".join(done)
	var unlocked: Array = result["unlocked"]
	_unlock_label.visible = not unlocked.is_empty()
	if not unlocked.is_empty():
		var names := PackedStringArray()
		for id in unlocked:
			names.append(Profile.car_info(id)["name"])
		_unlock_label.text = "NEW CAR UNLOCKED: " + ", ".join(names) + "!"
	_over_panel.visible = true
	_over_panel.modulate.a = 0.0
	_over_panel.create_tween().tween_property(_over_panel, "modulate:a", 1.0, 0.3)
	%RetryButton.grab_focus()


func _missions_text(run: Dictionary) -> String:
	var lines := PackedStringArray(["MISSIONS"])
	for m in Profile.missions:
		var pct := roundi(Profile.mission_progress(m, run) * 100.0)
		lines.append(("DONE  " if m["done"] else "%d%%  " % pct) + Profile.mission_text(m))
	return "\n".join(lines)


func _bump(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.15)
