extends Node
## Saved progress and settings, garage unlocks, missions and background music.
## Autoload: Profile (available from every scene).

const SAVE_PATH := "user://traffic_lanebreaker.cfg"
const KM_TO_MI := 0.621371
const ACTIVE_MISSIONS := 3

## Garage. `need` is the stat that unlocks the car and `value` the amount needed.
const CARS := [
	{"id": "racer", "name": "Red Racer", "sprite": "player", "need": "", "value": 0},
	{"id": "lime", "name": "Lime Bolt", "sprite": "sports_2", "need": "best_km", "value": 1.0},
	{"id": "taxi", "name": "City Taxi", "sprite": "sedan_6", "need": "total_km", "value": 5.0},
	{"id": "pocket", "name": "Pink Pocket", "sprite": "hatch_0", "need": "total_near", "value": 25},
	{"id": "viper", "name": "Teal Viper", "sprite": "sports_1", "need": "missions_done", "value": 3},
	{"id": "police", "name": "Interceptor", "sprite": "sedan_7", "need": "best_score", "value": 5000},
	{"id": "ambulance", "name": "Ambulance", "sprite": "van_3", "need": "total_km", "value": 20.0},
	{"id": "firetruck", "name": "Fire Truck", "sprite": "truck_2", "need": "missions_done", "value": 10},
]

## Mission templates. Each level is harder; new missions get harder as you complete more.
const MISSION_TYPES := {
	"near": {"text": "Get %s near misses in one run", "levels": [3, 5, 8, 12, 20]},
	"km": {"text": "Drive %s in one run", "levels": [0.5, 1.0, 2.0, 3.0, 5.0]},
	"oncoming_km": {"text": "Drive %s in oncoming lanes", "levels": [0.1, 0.25, 0.5, 0.8, 1.2]},
	"score": {"text": "Score %s in one run", "levels": [1000, 2500, 5000, 10000, 20000]},
	"speed": {"text": "Reach %s", "levels": [180.0, 210.0, 240.0, 285.0, 320.0]},
	"multiplier": {"text": "Reach a x%s multiplier", "levels": [2.0, 3.0, 4.0, 5.0, 6.0]},
}

var stats := {"best_score": 0, "best_km": 0.0, "total_km": 0.0, "total_near": 0,
	"missions_done": 0, "runs": 0}
var settings := {"music": 0.7, "sfx": 0.9, "miles": false, "shake": true, "vibration": true}
var selected_car := "racer"
var missions: Array = []   # [{"type", "value", "done"}]

var _music: AudioStreamPlayer
var _unlocked_at_start: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	load_profile()
	_fill_missions()
	apply_audio()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	var stream := load("res://assets/audio/music_loop.wav") as AudioStreamWAV
	if stream:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		_music.stream = stream
		add_child(_music)
		_music.play()


# ================================================================= saving

func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in stats:
		stats[key] = cfg.get_value("stats", key, stats[key])
	for key in settings:
		settings[key] = cfg.get_value("settings", key, settings[key])
	# Saves from before the garage only stored best_km / miles.
	stats["best_km"] = maxf(stats["best_km"], cfg.get_value("score", "best_km", 0.0))
	selected_car = cfg.get_value("garage", "selected", selected_car)
	missions = cfg.get_value("missions", "active", [])
	if not is_unlocked(selected_car):
		selected_car = "racer"


func save_profile() -> void:
	var cfg := ConfigFile.new()
	for key in stats:
		cfg.set_value("stats", key, stats[key])
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.set_value("garage", "selected", selected_car)
	cfg.set_value("missions", "active", missions)
	cfg.save(SAVE_PATH)


func reset_progress() -> void:
	for key in stats:
		stats[key] = 0 if stats[key] is int else 0.0
	selected_car = "racer"
	missions.clear()
	_fill_missions()
	save_profile()


# ================================================================= settings & audio

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_audio()
	save_profile()


func apply_audio() -> void:
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		var vol: float = settings["music" if bus_name == "Music" else "sfx"]
		AudioServer.set_bus_mute(idx, vol <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.001)))


func vibrate(ms: int) -> void:
	if settings["vibration"]:
		Input.vibrate_handheld(ms)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# ================================================================= units

func format_distance(km: float, decimals := 2) -> String:
	if settings["miles"]:
		return ("%." + str(decimals) + "f mi") % (km * KM_TO_MI)
	return ("%." + str(decimals) + "f km") % km


func format_speed(kmh: float) -> String:
	if settings["miles"]:
		return "%d mph" % roundi(kmh * KM_TO_MI)
	return "%d km/h" % roundi(kmh)


func speed_value(kmh: float) -> int:
	return roundi(kmh * KM_TO_MI) if settings["miles"] else roundi(kmh)


func speed_unit() -> String:
	return "MPH" if settings["miles"] else "KM/H"


static func format_score(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


# ================================================================= garage

func car_info(id: String) -> Dictionary:
	for car in CARS:
		if car["id"] == id:
			return car
	return CARS[0]


func car_texture(id: String) -> Texture2D:
	return load("res://assets/sprites/%s.png" % car_info(id)["sprite"])


func is_unlocked(id: String) -> bool:
	var car := car_info(id)
	return car["need"] == "" or stats[car["need"]] >= car["value"]


func unlock_progress(id: String) -> float:
	var car := car_info(id)
	if car["need"] == "":
		return 1.0
	return clampf(float(stats[car["need"]]) / float(car["value"]), 0.0, 1.0)


func unlock_text(id: String) -> String:
	var car := car_info(id)
	var v = car["value"]
	match car["need"]:
		"best_km": return "Drive %s in one run" % format_distance(v, 1)
		"total_km": return "Drive %s in total" % format_distance(v, 0)
		"total_near": return "Get %d near misses in total" % v
		"missions_done": return "Complete %d missions" % v
		"best_score": return "Score %s in one run" % format_score(v)
	return "Unlocked"


func unlocked_ids() -> Array:
	return CARS.filter(func(c): return is_unlocked(c["id"])).map(func(c): return c["id"])


# ================================================================= missions

func mission_text(m: Dictionary) -> String:
	var v = m["value"]
	var shown := ""
	match m["type"]:
		"km", "oncoming_km": shown = format_distance(v, 2 if v < 1.0 else 1)
		"speed": shown = format_speed(v)
		"score": shown = format_score(v)
		"multiplier": shown = str(int(v))
		_: shown = str(v)
	return MISSION_TYPES[m["type"]]["text"] % shown


## Progress of a mission (0..1) for the current run.
func mission_progress(m: Dictionary, run: Dictionary) -> float:
	if m["done"]:
		return 1.0
	return clampf(float(run.get(m["type"], 0.0)) / float(m["value"]), 0.0, 1.0)


## Marks missions finished by `run`. Returns the ones that just completed.
func check_missions(run: Dictionary) -> Array:
	var completed := []
	for m in missions:
		if not m["done"] and float(run.get(m["type"], 0.0)) >= float(m["value"]):
			m["done"] = true
			stats["missions_done"] += 1
			completed.append(m)
	return completed


## Call when a race starts, so finish_run() can tell which cars the run unlocked.
func begin_run() -> void:
	_unlocked_at_start = unlocked_ids()


## Records a finished run. Returns {"best_score", "best_km", "unlocked": [car ids]}.
func finish_run(run: Dictionary) -> Dictionary:
	var unlocked_before := _unlocked_at_start
	var result := {"best_score": false, "best_km": false}
	stats["runs"] += 1
	stats["total_km"] += run["km"]
	stats["total_near"] += run["near"]
	if run["score"] > stats["best_score"]:
		stats["best_score"] = run["score"]
		result["best_score"] = true
	if run["km"] > stats["best_km"]:
		stats["best_km"] = run["km"]
		result["best_km"] = true
	# Swap finished missions for new ones.
	missions = missions.filter(func(m): return not m["done"])
	_fill_missions()
	result["unlocked"] = unlocked_ids().filter(func(id): return not id in unlocked_before)
	save_profile()
	return result


func _fill_missions() -> void:
	var level := mini(stats["missions_done"] / 3, 4)
	var types := MISSION_TYPES.keys()
	while missions.size() < ACTIVE_MISSIONS:
		types.shuffle()
		for t in types:
			if missions.any(func(m): return m["type"] == t):
				continue
			var levels: Array = MISSION_TYPES[t]["levels"]
			var lv := clampi(level + randi_range(-1, 0), 0, levels.size() - 1)
			missions.append({"type": t, "value": levels[lv], "done": false})
			break
