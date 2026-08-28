class_name TestRoomFlow
extends GdUnitTestSuite
## m0-t12：房间波次状态机（纯逻辑，无头驱动）。

func test_lock_waves_clear() -> void:
	# 注：brief 原文 `var flow := auto_free(...)`，auto_free 返回 Variant，:= 推断触发
	# 警告即错误（同 test_weapon_rig.gd / test_melee_parry.gd 既定决议），需显式类型标注。
	var flow: RoomFlow = auto_free(RoomFlow.new())
	flow.setup({"waves": [["a"], ["b", "c"]], "coins": 30, "energy_orbs": 4})
	flow.on_entered(0)
	assert_bool(flow.locked).is_true()
	assert_int(flow.pending_spawns()).is_equal(1)
	flow.notify_killed("a", 10)               # 第一波清
	assert_int(flow.pending_spawns()).is_equal(2)
	flow.notify_killed("b", 20)
	flow.notify_killed("c", 21)
	assert_bool(flow.locked).is_false()
	assert_bool(flow.cleared).is_true()
	assert_int(flow.rewards.get("coins", 0)).is_equal(30)

func test_valid_spawn_points_filter() -> void:
	# m0 战斗房点位静态过滤：距 4 门 ≥64px 且距玩家 ≥120px（brief：过滤函数单测覆盖）。
	# 门位：西入口(480,135)、北(720,8)、东(960,135)、南(720,262)；入场玩家位 (500,135)。
	var points: Array[Vector2] = [
		Vector2(580, 70), Vector2(580, 200), Vector2(650, 135),
		Vector2(720, 135), Vector2(860, 70), Vector2(860, 200),
	]
	var doors: Array[Vector2] = [
		Vector2(480, 135), Vector2(720, 8), Vector2(960, 135), Vector2(720, 262),
	]
	var valid := RoomCombat.filter_spawn_points(points, doors, Vector2(500, 135))
	# (580,70)/(580,200) 距玩家 ≈103px < 120 → 剔除；其余 4 点距门 ≥64、距玩家 ≥120 → 保留
	assert_bool(valid.has(Vector2(580, 70))).is_false()
	assert_bool(valid.has(Vector2(580, 200))).is_false()
	assert_bool(valid.has(Vector2(650, 135))).is_true()
	assert_bool(valid.has(Vector2(720, 135))).is_true()
	assert_bool(valid.has(Vector2(860, 70))).is_true()
	assert_bool(valid.has(Vector2(860, 200))).is_true()
	assert_int(valid.size()).is_equal(4)

func test_spawn_filter_fallback_when_all_filtered() -> void:
	# fix1：全点位被过滤（距玩家 <120px）→ 兜底原样返回全量点位（放弃不变量，push_warning 留痕）。
	# 无怪可刷 = 流程卡死，兜底是有意保留的行为；本用例钉住其存在与语义。
	var points: Array[Vector2] = [Vector2(510, 135), Vector2(520, 135), Vector2(505, 140)]
	var doors: Array[Vector2] = [Vector2(480, 135)]
	var valid := RoomCombat.filter_spawn_points(points, doors, Vector2(500, 135))
	assert_int(valid.size()).is_equal(3)
	assert_bool(valid.has(Vector2(510, 135))).is_true()
	assert_bool(valid.has(Vector2(520, 135))).is_true()
	assert_bool(valid.has(Vector2(505, 140))).is_true()
