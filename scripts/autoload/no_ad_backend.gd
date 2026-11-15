class_name NoAdBackend
extends Node
## Ad backend for builds that must show no ads at all: the CrazyGames build
## during Basic Launch (their rules: no ads, and no ad buttons that do nothing).
## Nothing is ever ready, so every ad placement hides itself (revive, double
## gold, reroll, the menu "+75" chip, the between-runs interstitial). If a
## call slips through anyway it finishes at once with no reward.


func get_backend_name() -> String:
	return "none"


func is_rewarded_ready() -> bool:
	return false


func is_interstitial_ready() -> bool:
	return false


func show_rewarded(_placement: String, done: Callable) -> void:
	done.call(false)


func show_interstitial(_placement: String, done: Callable) -> void:
	done.call()
