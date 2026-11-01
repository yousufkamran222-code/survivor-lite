extends Node
## Analytics facade (autoload "Analytics"). Game code only calls
## Analytics.event(name, params). For now events are printed and kept in a
## ring buffer; the Firebase backend is wired in a later milestone without
## touching call sites. Event names: snake_case, <= 40 chars (Firebase limits).

const KEEP := 200

var recent: Array = []
var session_start_ms := 0


func _ready() -> void:
	session_start_ms = Time.get_ticks_msec()
	event("session_start", {"platform": OS.get_name()})


func event(name: String, params: Dictionary = {}) -> void:
	recent.append({"name": name, "params": params, "t": Time.get_ticks_msec()})
	if recent.size() > KEEP:
		recent.pop_front()
	if OS.is_debug_build():
		print("[analytics] ", name, " ", params)
