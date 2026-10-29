extends Control
## Main menu: play, garage, settings, best score and current missions.
## Scene: res://scenes/menu.tscn

func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	%PlayButton.pressed.connect(_go.bind("res://scenes/main.tscn"))
	%GarageButton.pressed.connect(_go.bind("res://scenes/garage.tscn"))
	%SettingsButton.pressed.connect(_go.bind("res://scenes/settings.tscn"))
	%CarPreview.texture = Profile.car_texture(Profile.selected_car)
	%CarName.text = Profile.car_info(Profile.selected_car)["name"]
	var best := "BEST SCORE  " + Profile.format_score(Profile.stats["best_score"])
	best += "\nBEST DISTANCE  " + Profile.format_distance(Profile.stats["best_km"], 2)
	%BestLabel.text = best
	var lines := PackedStringArray()
	for m in Profile.missions:
		lines.append("•  " + Profile.mission_text(m))
	%MissionList.text = "\n".join(lines)
	%PlayButton.grab_focus()
	# Gentle bob on the car preview.
	var car: Control = %CarPreview
	var tw := car.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(car, "position:y", -8.0, 0.7).as_relative()
	tw.tween_property(car, "position:y", 8.0, 0.7).as_relative()


func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _notification(what: int) -> void:
	# Android back button on the main menu leaves the game.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
