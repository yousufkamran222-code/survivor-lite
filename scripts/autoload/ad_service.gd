extends Node
## AdService: the ONLY way game code touches ads (autoload "Ads").
##
## Game code calls:
##   Ads.show_rewarded("revive", func(rewarded: bool): ...)
##   Ads.show_interstitial("between_runs")
##   Ads.is_rewarded_available()
##
## The backend is picked at startup. On web, desktop and in tests the stub is
## used: it shows a fake "ad" overlay and always rewards, so flows can be
## playtested. The real AdMob backend (Android) is added in a later milestone
## as scripts/autoload/ads/admob_backend.gd implementing the same methods, and
## is only selected when the AdMob plugin singleton exists.

signal ad_started(kind: String, placement: String)
signal ad_finished(kind: String, placement: String, rewarded: bool)

var backend: Object
var busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	backend = StubAdBackend.new()
	add_child(backend)
	print("AdService backend: ", backend.get_backend_name())


func is_rewarded_available() -> bool:
	return not busy and backend.is_rewarded_ready()


func show_rewarded(placement: String, on_done: Callable) -> void:
	if busy:
		on_done.call(false)
		return
	busy = true
	ad_started.emit("rewarded", placement)
	Analytics.event("ad_rewarded_start", {"placement": placement})
	backend.show_rewarded(placement, func(rewarded: bool) -> void:
		busy = false
		ad_finished.emit("rewarded", placement, rewarded)
		Analytics.event("ad_rewarded_end", {"placement": placement, "rewarded": rewarded})
		on_done.call(rewarded))


func show_interstitial(placement: String, on_done: Callable = Callable()) -> void:
	if busy or not backend.is_interstitial_ready():
		if on_done.is_valid():
			on_done.call()
		return
	busy = true
	ad_started.emit("interstitial", placement)
	Analytics.event("ad_interstitial", {"placement": placement})
	backend.show_interstitial(placement, func() -> void:
		busy = false
		ad_finished.emit("interstitial", placement, false)
		if on_done.is_valid():
			on_done.call())
