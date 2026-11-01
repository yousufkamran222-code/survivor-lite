extends Node
## Persistent player progress (autoload "Save"). Stored in user://save.cfg,
## which is IndexedDB on web and app-private storage on Android.

const PATH := "user://save.cfg"

var gold := 0
var meta_levels := {}  # meta id -> level
var best_time := 0.0
var runs := 0
var deaths := 0
var muted := false


func _ready() -> void:
	load_save()


func load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	gold = int(cf.get_value("progress", "gold", 0))
	meta_levels = cf.get_value("progress", "meta_levels", {})
	best_time = float(cf.get_value("progress", "best_time", 0.0))
	runs = int(cf.get_value("stats", "runs", 0))
	deaths = int(cf.get_value("stats", "deaths", 0))
	muted = bool(cf.get_value("settings", "muted", false))


func write() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "gold", gold)
	cf.set_value("progress", "meta_levels", meta_levels)
	cf.set_value("progress", "best_time", best_time)
	cf.set_value("stats", "runs", runs)
	cf.set_value("stats", "deaths", deaths)
	cf.set_value("settings", "muted", muted)
	cf.save(PATH)


func meta_level(id: String) -> int:
	return int(meta_levels.get(id, 0))
