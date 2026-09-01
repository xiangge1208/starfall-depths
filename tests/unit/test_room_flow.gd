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

func test_spawn_filter_progressive_relax_farthest_first() -> void:
	# m3-fix1（B-1 停滞根因重设计）：全点位被过滤 → 渐进放宽双阈值（8px/档），返回
	# 「首个非空档」的合法点集、按离玩家距离降序（首元素 = 离玩家最远合法点）。
	# 旧「原样返回全量点位（丢弃不变量）」语义废除——怪不得刷在贴脸位/门体上。
	var points: Array[Vector2] = [Vector2(510, 135), Vector2(520, 135), Vector2(505, 140)]
	var doors: Array[Vector2] = [Vector2(480, 135)]
	var player := Vector2(500, 135)
	var valid := RoomCombat.filter_spawn_points(points, doors, player)
	# 距玩家 10 / 20 / ≈11.2 → 全部 <120：放宽至「距玩家 ≥16px」档（8px×13）才首个非空，
	# 仅 (520,135)（20px）入围 → 单点、且是三点中离玩家最远者。
	assert_int(valid.size()).is_equal(1)
	assert_vector(valid[0]).is_equal(Vector2(520, 135))

func test_spawn_filter_relax_keeps_minimal_and_orders_farthest_first() -> void:
	# 多点同档入围：验证最小放宽档（只放到位为止）+ 降序排序 + 门不变量按放宽档保留。
	# 玩家 (500,135)；两候选 (608,135)（距 108）与 (610,135)（距 110），均远门（门距
	# 不需放宽）→ 「距玩家 ≥112px」档仍空，「≥104px」档（8px×2）两点评入 → 降序输出。
	var points: Array[Vector2] = [Vector2(608, 135), Vector2(610, 135)]
	var doors: Array[Vector2] = [Vector2(100, 100), Vector2(100, 900)]
	var player := Vector2(500, 135)
	var valid := RoomCombat.filter_spawn_points(points, doors, player)
	assert_int(valid.size()).is_equal(2)
	assert_vector(valid[0]).is_equal(Vector2(610, 135))
	assert_vector(valid[1]).is_equal(Vector2(608, 135))

func test_spawn_filter_relax_zero_drift_when_any_point_legal() -> void:
	# 零漂移：任一点位在完整阈值下合法 → 走原路径、输入序原样返回（不排序不放宽）。
	var points: Array[Vector2] = [
		Vector2(700, 135), Vector2(580, 70),   # 前者合法；后者距玩家 <120
		Vector2(650, 135),
	]
	var doors: Array[Vector2] = [
		Vector2(480, 135), Vector2(720, 8), Vector2(960, 135), Vector2(720, 262),
	]
	var valid := RoomCombat.filter_spawn_points(points, doors, Vector2(500, 135))
	assert_int(valid.size()).is_equal(2)
	assert_vector(valid[0]).is_equal(Vector2(700, 135))
	assert_vector(valid[1]).is_equal(Vector2(650, 135))

func test_spawn_filter_relaxed_result_never_empty() -> void:
	# 可清性兜底：点位非空时任何阈值组合（含玩家与刷点重合的极端贴脸）都产非空结果。
	var points: Array[Vector2] = [Vector2(500, 135)]
	var doors: Array[Vector2] = [Vector2(500, 136)]
	var valid := RoomCombat.filter_spawn_points(points, doors, Vector2(500, 135))
	assert_int(valid.size()).is_equal(1)
	assert_vector(valid[0]).is_equal(Vector2(500, 135))
