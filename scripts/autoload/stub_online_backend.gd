class_name StubOnlineBackend
extends Node
## Local-only online backend for web, desktop, tests and until Play Games is
## wired up. Never signed in; scores and achievements are only logged (the
## Profile already keeps the player's own records and achievements).

var submitted := {}  # board id -> best value seen this session


func get_backend_name() -> String:
	return "stub"


func is_signed_in() -> bool:
	return false


func player_name() -> String:
	return "Local player"


func submit_score(board_id: String, value: int) -> void:
	submitted[board_id] = maxi(int(submitted.get(board_id, 0)), value)
	if OS.is_debug_build():
		print("[online stub] score ", board_id, " = ", value)


func unlock_achievement(id: String) -> void:
	if OS.is_debug_build():
		print("[online stub] achievement ", id)


func push_profile(_data: Dictionary) -> void:
	pass


func pull_profile(on_done: Callable) -> void:
	on_done.call(null)
