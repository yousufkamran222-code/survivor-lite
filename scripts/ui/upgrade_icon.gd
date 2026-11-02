class_name UpgradeIcon
extends Control
## A Control that draws one IconArt icon at its size. Ignores input so it can
## sit inside buttons.

var key := ""
var color := Color.WHITE
var evolved := false


static func make(icon_key: String, col: Color, px: float, evo: bool = false) -> UpgradeIcon:
	var ic := UpgradeIcon.new()
	ic.key = icon_key
	ic.color = col
	ic.evolved = evo
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _draw() -> void:
	IconArt.draw(self, key, size / 2.0, minf(size.x, size.y), color, evolved)
