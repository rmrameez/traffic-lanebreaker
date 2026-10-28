extends Control
## Loading screen: shows the title and credit while the game scene loads in the background.
## Scene: res://scenes/splash.tscn (the project's main scene).

const GAME_SCENE := "res://scenes/main.tscn"
const MIN_TIME := 2.5   # seconds the splash stays up, even if loading is instant
const FADE_TIME := 0.4

var _elapsed := 0.0
var _leaving := false

@onready var _bar: ProgressBar = %LoadBar
@onready var _car: TextureRect = %Car


func _ready() -> void:
	ResourceLoader.load_threaded_request(GAME_SCENE)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)
	var bob := _car.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(_car, "position:y", -10.0, 0.6).as_relative()
	bob.tween_property(_car, "position:y", 10.0, 0.6).as_relative()


func _process(delta: float) -> void:
	if _leaving:
		return
	_elapsed += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
	# The bar follows whichever is slower: real loading or the minimum display time.
	var loaded: float = 1.0 if status == ResourceLoader.THREAD_LOAD_LOADED else progress[0]
	_bar.value = minf(loaded, _elapsed / MIN_TIME) * 100.0

	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Could not load %s" % GAME_SCENE)
		set_process(false)
	elif status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_TIME:
		_leaving = true
		var scene := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		tw.tween_callback(get_tree().change_scene_to_packed.bind(scene))
