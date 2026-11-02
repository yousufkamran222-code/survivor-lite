extends Node
## Online features facade (autoload "Online"): accounts, leaderboards,
## achievements and cloud saves. Game code only talks to this, never to a
## platform SDK, exactly like Ads.
##
## Today the backend is StubOnlineBackend (local only: everything works
## offline, nothing is sent anywhere). Later a PlayGamesBackend (Google Play
## Games Services) implements the same methods and is picked when its plugin
## singleton exists. Profile.merge() resolves cloud-vs-local conflicts.

signal signed_in_changed(signed_in: bool)

var backend: Object


func _ready() -> void:
	backend = StubOnlineBackend.new()
	add_child(backend)
	print("Online backend: ", backend.get_backend_name())


func backend_name() -> String:
	return backend.get_backend_name()


func is_signed_in() -> bool:
	return backend.is_signed_in()


func player_name() -> String:
	return backend.player_name()


func submit_score(board_id: String, value: int) -> void:
	backend.submit_score(board_id, value)


func unlock_achievement(id: String) -> void:
	backend.unlock_achievement(id)


## Uploads the profile (no-op on the stub).
func push_profile(data: Dictionary) -> void:
	backend.push_profile(data)


## Fetches the cloud profile; calls on_done with a Dictionary or null.
func pull_profile(on_done: Callable) -> void:
	backend.pull_profile(on_done)


## Called after every run: submits each matching leaderboard and unlocks
## newly earned achievements. `summary` comes from Progression.run_summary.
func report_run(summary: Dictionary, boards: Array, new_achievements: Array) -> void:
	for lb in boards:
		if lb.mode == summary.mode:
			submit_score(lb.id, Progression.metric_value(summary, lb.metric))
	for a in new_achievements:
		unlock_achievement(a.id)
