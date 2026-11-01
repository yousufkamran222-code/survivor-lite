class_name StubAdBackend
extends CanvasLayer
## Fake ad backend for web, desktop and tests. Shows a labelled overlay for a
## moment, then completes. Rewarded ads always reward.

var _overlay: ColorRect
var _label: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.88)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 40)
	_overlay.add_child(_label)


func get_backend_name() -> String:
	return "stub"


func is_rewarded_ready() -> bool:
	return true


func is_interstitial_ready() -> bool:
	return true


func show_rewarded(placement: String, done: Callable) -> void:
	_play("REWARDED AD (test stub)\n%s" % placement, func() -> void: done.call(true))


func show_interstitial(placement: String, done: Callable) -> void:
	_play("INTERSTITIAL AD (test stub)\n%s" % placement, done)


func _play(text: String, done: Callable) -> void:
	_label.text = text
	_overlay.visible = true
	var secs := 1.0
	var main := get_tree().root.get_node_or_null("Main")
	if main and "data" in main and main.data.has("balance"):
		secs = float(main.data.balance.ads.stub_duration_s)
	await get_tree().create_timer(secs, true, false, true).timeout
	_overlay.visible = false
	done.call()
