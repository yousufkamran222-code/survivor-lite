extends Node
## Persistent player progress (autoload "Save"). Holds a Profile (see
## scripts/core/profile.gd) and stores it as versioned JSON in
## user://profile.json (IndexedDB on web, app-private storage on Android).
## Writes go to a temp file first, then replace the old one, and the
## previous copy is kept as profile.bak, so a crash mid-write can't wipe
## progress. A v1 save (user://save.cfg) is imported once automatically.
##
## The old flat properties (gold, meta_levels, runs, ...) are kept as
## pass-throughs to the profile so existing call sites keep working.

const PATH := "user://profile.json"
const BACKUP := "user://profile.bak"
const LEGACY := "user://save.cfg"

var profile := Profile.new()
# Paths are variables so tests can point them at scratch files.
var path := PATH
var backup := BACKUP
var legacy := LEGACY

var gold: int:
	get: return profile.gold
	set(v): profile.gold = v
var meta_levels: Dictionary:
	get: return profile.meta_levels
	set(v): profile.meta_levels = v
var muted: bool:
	get: return bool(profile.settings.get("muted", false))
	set(v): profile.settings["muted"] = v
var mode: String:
	get: return str(profile.settings.get("mode", "infection"))
	set(v): profile.settings["mode"] = v
var runs: int:
	get: return int(profile.stats.runs)
var deaths: int:
	get: return int(profile.stats.deaths)
var best_time: float:
	get: return profile.best_time_any()


func _ready() -> void:
	load_save()


func load_save() -> void:
	var p := _read(path)
	if p == null:
		p = _read(backup)
	if p == null and FileAccess.file_exists(legacy):
		p = _import_legacy()
		if p != null:
			profile = p
			write()
			return
	if p != null:
		profile = p


func _read(path: String) -> Profile:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("Save: unreadable %s" % path)
		return null
	return Profile.from_dict(parsed)


func _import_legacy() -> Profile:
	var cf := ConfigFile.new()
	if cf.load(legacy) != OK:
		return null
	var m := str(cf.get_value("settings", "mode", "infection"))
	if cf.has_section_key("settings", "territory_mode") and not cf.has_section_key("settings", "mode"):
		m = "infection" if bool(cf.get_value("settings", "territory_mode")) else "classic"
	return Profile.from_legacy(
		int(cf.get_value("progress", "gold", 0)), cf.get_value("progress", "meta_levels", {}),
		float(cf.get_value("progress", "best_time", 0.0)), int(cf.get_value("stats", "runs", 0)),
		int(cf.get_value("stats", "deaths", 0)), bool(cf.get_value("settings", "muted", false)),
		m, cf.get_value("progress", "best_times", {}))


func write() -> void:
	profile.version = Profile.VERSION
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Save: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(profile.to_dict()))
	f.close()
	# Full paths: DirAccess.copy() fails on bare file names.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, backup)
	DirAccess.rename_absolute(tmp, path)


func meta_level(id: String) -> int:
	return profile.meta_level(id)


static func now() -> int:
	return int(Time.get_unix_time_from_system())
