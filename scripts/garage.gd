extends Control
## Garage: browse the cars, see how to unlock them and pick the one to race.
## Scene: res://scenes/garage.tscn

var _index := 0

@onready var _preview: TextureRect = %Preview
@onready var _name: Label = %CarName
@onready var _status: Label = %Status
@onready var _progress: ProgressBar = %UnlockProgress
@onready var _counter: Label = %Counter
@onready var _select: Button = %SelectButton


func _ready() -> void:
	for i in Profile.CARS.size():
		if Profile.CARS[i]["id"] == Profile.selected_car:
			_index = i
	%PrevButton.pressed.connect(_step.bind(-1))
	%NextButton.pressed.connect(_step.bind(1))
	%BackButton.pressed.connect(_back)
	_select.pressed.connect(_on_select)
	_refresh()
	%BackButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_cancel"):
		_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _step(dir: int) -> void:
	_index = wrapi(_index + dir, 0, Profile.CARS.size())
	_refresh()
	_preview.pivot_offset = _preview.size * 0.5
	_preview.scale = Vector2(0.85, 0.85)
	_preview.create_tween().tween_property(_preview, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh() -> void:
	var car: Dictionary = Profile.CARS[_index]
	var id: String = car["id"]
	var unlocked := Profile.is_unlocked(id)
	_preview.texture = Profile.car_texture(id)
	# Locked cars show as a dark silhouette.
	_preview.modulate = Color.WHITE if unlocked else Color(0.08, 0.07, 0.14, 0.9)
	_name.text = car["name"] if unlocked else "???"
	_counter.text = "%d / %d" % [_index + 1, Profile.CARS.size()]
	_progress.visible = not unlocked
	if unlocked:
		_status.text = "IN USE" if id == Profile.selected_car else "READY TO RACE"
	else:
		_status.text = "LOCKED\n" + Profile.unlock_text(id)
		_progress.value = Profile.unlock_progress(id) * 100.0
	_select.disabled = not unlocked or id == Profile.selected_car
	_select.text = "SELECTED" if id == Profile.selected_car else ("SELECT" if unlocked else "LOCKED")


func _on_select() -> void:
	Profile.selected_car = Profile.CARS[_index]["id"]
	Profile.save_profile()
	_refresh()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
