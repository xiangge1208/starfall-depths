class_name TestDoorAnim
extends GdUnitTestSuite
## m1-t18：统一门动画（0.18s Tween 滑入/滑出），收口 room_combat/floor_scene 的 ad-hoc 门代码。

func _panel() -> Node2D:
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)                              # Tween 须在树内才会推进
	DoorAnim.install(p, Vector2(100, 50))
	p.position = Vector2(100, 50)
	return p

func test_close_slides_home_and_visible() -> void:
	var p := _panel()
	p.position = Vector2(100, 4)              # 开位（home + 滑出位移）
	DoorAnim.close(p)
	await get_tree().create_timer(0.25).timeout
	assert_vector(p.position).is_equal_approx(Vector2(100, 50), Vector2(0.5, 0.5))
	assert_bool(p.visible).is_true()

func test_open_parks_then_hides_when_requested() -> void:
	var p := _panel()
	DoorAnim.open(p, true)                    # floor_scene 闸门：开 = 滑出后隐藏
	await get_tree().create_timer(0.25).timeout
	assert_vector(p.position).is_equal_approx(Vector2(100, 4), Vector2(0.5, 0.5))
	assert_bool(p.visible).is_false()

func test_open_keeps_retracted_panel_visible_by_default() -> void:
	var p := _panel()
	DoorAnim.open(p)                          # room_combat M0 习语：滑出收进墙体仍可见
	await get_tree().create_timer(0.25).timeout
	assert_vector(p.position).is_equal_approx(Vector2(100, 4), Vector2(0.5, 0.5))
	assert_bool(p.visible).is_true()
