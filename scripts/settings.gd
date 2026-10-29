extends Control
## Settings: music and sound volume, units, camera shake, vibration, and progress reset.
## Scene: res://scenes/settings.tscn

var _reset_armed := false

@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _miles: CheckButton = %MilesToggle
@onready var _shake: CheckButton = %ShakeToggle
@onready var _vibration: CheckButton = %VibrationToggle
@onready var _reset: Button = %ResetButton


func _ready() -> void:
	_music.value = Profile.settings["music"]
	_sfx.value = Profile.settings["sfx"]
	_miles.button_pressed = Profile.settings["miles"]
	_shake.button_pressed = Profile.settings["shake"]
	_vibration.button_pressed = Profile.settings["vibration"]
	_music.value_changed.connect(func(v): Profile.set_setting("music", v))
	_sfx.value_changed.connect(func(v): Profile.set_setting("sfx", v))
	_miles.toggled.connect(_on_miles_toggled)
	_shake.toggled.connect(func(on): Profile.set_setting("shake", on))
	_vibration.toggled.connect(func(on): Profile.set_setting("vibration", on))
	_reset.pressed.connect(_on_reset)
	%BackButton.pressed.connect(_back)
	_refresh_stats()
	%BackButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _on_miles_toggled(on: bool) -> void:
	Profile.set_setting("miles", on)
	_refresh_stats()


func _refresh_stats() -> void:
	var s := Profile.stats
	%StatsLabel.text = "\n".join(PackedStringArray([
		"RACES   %d" % s["runs"],
		"TOTAL DISTANCE   " + Profile.format_distance(s["total_km"], 1),
		"TOTAL NEAR MISSES   %d" % s["total_near"],
		"MISSIONS COMPLETED   %d" % s["missions_done"],
		"CARS UNLOCKED   %d / %d" % [Profile.unlocked_ids().size(), Profile.CARS.size()],
	]))


## Reset needs two presses so it can't happen by accident.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset.text = "TAP AGAIN TO ERASE"
		get_tree().create_timer(3.0).timeout.connect(func():
			_reset_armed = false
			_reset.text = "RESET PROGRESS")
		return
	_reset_armed = false
	Profile.reset_progress()
	_reset.text = "PROGRESS ERASED"
	_refresh_stats()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
