class_name TestSafePlacement
extends GdUnitTestSuite
## m3-fix2：中心落位防卡缝（`FloorScene.find_safe_placement` 静态纯函数契约）。
##
## 产品侧背景（B-2 停滞 11% 的产品侧根因，探针实证 seeds 3221/3251/3258/3268 +
## 3221 中途冻结形态）：combat_a1_01 等模板把柱/箱实体放在**房心**，`_push_back`/
## `_place_player_at_start` 的「房心落位」把玩家 CharacterBody2D（r=6）直接放进
## 2×2 柱阵缝，move_and_slide 去重叠相互抵消 → 玩家 dir/vel 非零仍全程零位移，
## 风筝敌脱离点杀距离后伤害停摆。本套件钉死：合法落位零漂移、非法落位确定性
## 弹出到最近自由点、圆-矩形间距不变量、interior 边界收缩、防御性回退。

const TILE := 16.0

# combat_a1_01 房心 2×2 柱阵（模板 props grid (10,6),(11,6),(10,7),(11,7)）房内局部矩形。
static func _a1_01_center_pillars() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for g: Vector2i in [Vector2i(10, 6), Vector2i(11, 6), Vector2i(10, 7), Vector2i(11, 7)]:
		var c := Vector2(float(g.x) * TILE + 8.0, float(g.y) * TILE + 8.0)
		out.append(Rect2(c - Vector2(8, 8), Vector2(16, 16)))
	return out

# combat_a1_05 房心偏东的箱柱列（props crate grid (11,5..8)）。
static func _a1_05_crate_column() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for gy: int in [5, 6, 7, 8]:
		var c := Vector2(11.0 * TILE + 8.0, float(gy) * TILE + 8.0)
		out.append(Rect2(c - Vector2(8, 8), Vector2(16, 16)))
	return out

# 22×14 格房的内域（去 16px 墙带）。
static func _interior() -> Rect2:
	return Rect2(16, 16, 22.0 * TILE - 32.0, 14.0 * TILE - 32.0)


static func _circle_rect_gap(at: Vector2, rect: Rect2) -> float:
	var closest := Vector2(
		clampf(at.x, rect.position.x, rect.end.x),
		clampf(at.y, rect.position.y, rect.end.y))
	return closest.distance_to(at)


func test_free_point_returns_unchanged() -> void:
	var center := Vector2(176, 112)
	var out := FloorScene.find_safe_placement(center, [], 6.0, _interior())
	assert_vector(out).is_equal_approx(center, Vector2(0.001, 0.001))


func test_center_inside_a1_01_pillar_block_is_ejected() -> void:
	var center := Vector2(176, 112)
	var out := FloorScene.find_safe_placement(center, _a1_01_center_pillars(), 6.0, _interior())
	# 柱阵 32×32 → 最近自由点距中心 ≥ 16+6-ε（半径升序环搜取近端）
	assert_vector(out).is_not_equal(center)
	assert_float((out - center).length()).is_between(20.0, 34.0)
	for rect in _a1_01_center_pillars():
		assert_float(_circle_rect_gap(out, rect)).is_greater_equal(6.0)
	assert_bool(_interior().has_point(out)).is_true()


func test_center_inside_a1_05_crate_column_is_ejected() -> void:
	var center := Vector2(176, 112)
	var out := FloorScene.find_safe_placement(center, _a1_05_crate_column(), 6.0, _interior())
	assert_vector(out).is_not_equal(center)
	for rect in _a1_05_crate_column():
		assert_float(_circle_rect_gap(out, rect)).is_greater_equal(6.0)
	assert_bool(_interior().has_point(out)).is_true()


func test_result_respects_wall_interior_margin() -> void:
	# 贴墙点（x=20 < 内域左沿 16+6）即使无实体也非法 → 弹回内域
	var out := FloorScene.find_safe_placement(Vector2(20, 112), [], 6.0, _interior())
	assert_float(out.x).is_greater_equal(_interior().position.x + 6.0)
	assert_bool(_interior().has_point(out)).is_true()


func test_deterministic_same_input_same_output() -> void:
	var solids := _a1_01_center_pillars()
	var a := FloorScene.find_safe_placement(Vector2(176, 112), solids, 6.0, _interior())
	var b := FloorScene.find_safe_placement(Vector2(176, 112), solids, 6.0, _interior())
	assert_vector(a).is_equal(b)


func test_no_feasible_point_returns_preferred_defensively() -> void:
	# interior 收缩到负尺寸（退化构造体）：无处可放 → 原样返回（防御路径）
	var tiny := Rect2(100, 100, 2, 2)
	var out := FloorScene.find_safe_placement(Vector2(101, 101), [], 6.0, tiny)
	assert_vector(out).is_equal(Vector2(101, 101))


func test_off_center_point_near_solids_stays_when_free() -> void:
	# 离柱阵 ≥ 半径的点：合法 → 零漂移（不无事生非）
	var free := Vector2(230, 112)
	var out := FloorScene.find_safe_placement(free, _a1_01_center_pillars(), 6.0, _interior())
	assert_vector(out).is_equal_approx(free, Vector2(0.001, 0.001))


func test_blocked_direction_finds_free_ring_point() -> void:
	# 点在两矩形夹缝（共享边两侧各 4px）→ 弹出到最近自由点且不再相交
	var solids: Array[Rect2] = [
		Rect2(160, 96, 16, 64),   # 竖板 A
		Rect2(192, 96, 16, 64),   # 竖板 B（与 A 之间 16px 缝 < 2×radius）
	]
	var out := FloorScene.find_safe_placement(Vector2(184, 128), solids, 6.0, _interior())
	for rect in solids:
		assert_float(_circle_rect_gap(out, rect)).is_greater_equal(6.0)
	assert_bool(_interior().has_point(out)).is_true()
