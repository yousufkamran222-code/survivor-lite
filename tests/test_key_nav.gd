extends TestCase
## Keyboard menus (S6): KeyNav.pick chooses the button a key moves to.


func test_moves_down_a_column() -> void:
	var rects := [Rect2(0, 0, 400, 80), Rect2(0, 100, 400, 80), Rect2(0, 200, 400, 80)]
	check_eq(KeyNav.pick(rects[0], rects, Vector2.DOWN), 1)
	check_eq(KeyNav.pick(rects[1], rects, Vector2.DOWN), 2)
	check_eq(KeyNav.pick(rects[2], rects, Vector2.DOWN), -1, "nothing below the last")
	check_eq(KeyNav.pick(rects[2], rects, Vector2.UP), 1)


func test_grid_prefers_straight_ahead() -> void:
	# 2 rows of 3 tiles; from the middle top tile, down goes to the middle bottom one.
	var rects := []
	for row in 2:
		for col in 3:
			rects.append(Rect2(col * 160, row * 160, 140, 140))
	check_eq(KeyNav.pick(rects[1], rects, Vector2.DOWN), 4)
	check_eq(KeyNav.pick(rects[1], rects, Vector2.RIGHT), 2)
	check_eq(KeyNav.pick(rects[1], rects, Vector2.LEFT), 0)
	check_eq(KeyNav.pick(rects[4], rects, Vector2.UP), 1)


func test_wide_button_under_a_row() -> void:
	# A row of 4 tiles above a wide PLAY button: down from any tile lands on PLAY,
	# up from PLAY lands on a tile above it, not on something off to the side.
	var rects := [Rect2(0, 0, 100, 100), Rect2(120, 0, 100, 100), Rect2(240, 0, 100, 100), Rect2(360, 0, 100, 100), Rect2(0, 140, 460, 120), Rect2(600, 300, 100, 60)]
	for i in 4:
		check_eq(KeyNav.pick(rects[i], rects, Vector2.DOWN), 4)
	var up := KeyNav.pick(rects[4], rects, Vector2.UP)
	check(up >= 0 and up <= 3, "up from PLAY goes to the row above")
