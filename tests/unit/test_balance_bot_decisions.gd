class_name TestBalanceBotDecisions
extends GdUnitTestSuite
## m2-t28 Balance Bot 决策纯逻辑测试（TDD 先行）。
## 被测对象 tools/balance_bot_decisions.gd 是无场景依赖的纯函数集：
## 机器人每拍把世界观测（自身位置/房界/敌弹/敌人/hazard 域/玩家面板）注入，
## 换取确定性行为决策。所有随机性以「采样值」显式入参（roll_sample 等），
## 同输入必同输出——这是 10 局回归可复现的前提。

const INF_F := 999999.0


# ================================================================ 走位目标选择

func test_move_dodges_approaching_bullet() -> void:
	# 右侧 60px 有子弹正向左飞（逼近）：期望向左闪避。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(60, 0), "vel": Vector2(-110, 0)}],
		[], [], 1.0)
	assert_float(dir.x).is_less(-0.5)


func test_move_ignores_receding_bullet() -> void:
	# 右侧 60px 有子弹正向右飞（远离）：不构成威胁，无敌人时不动。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(60, 0), "vel": Vector2(110, 0)}],
		[], [], 1.0)
	assert_vector(dir).is_equal(Vector2.ZERO)


func test_move_ignores_bullet_beyond_dodge_radius() -> void:
	# 200px 外的逼近弹（> 96px 感知半径）：不躲。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(200, 0), "vel": Vector2(-110, 0)}],
		[], [], 1.0)
	assert_vector(dir).is_equal(Vector2.ZERO)


func test_move_retreats_from_close_melee_enemy() -> void:
	# 左侧 50px 贴脸近敌（< 80px 拉开半径）：向右退 + 切向绕走（wander_sign=1 → +y）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(-50, 0)], [], 1.0)
	assert_float(dir.x).is_greater(0.5)
	assert_float(dir.y).is_greater(0.0)


func test_melee_tangential_sign_follows_wander_sign() -> void:
	# 确定性：wander_sign 翻转 → 切向分量翻转（同输入同输出的两种拍）。
	var plus := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(-50, 0)], [], 1.0)
	var minus := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(-50, 0)], [], -1.0)
	assert_float(plus.y).is_greater(0.0)
	assert_float(minus.y).is_less(0.0)
	assert_float(plus.x).is_equal(minus.x)   # 主退避分量不受游走符号影响


func test_move_orbits_within_ranged_band_without_threats() -> void:
	# 无弹幕威胁：100px 处敌人在理想距离带 [72,132] 内 → 环绕走位（不站桩：
	# 持续横移拉扯弹道与追踪者；wander_sign=1 → 左垂直 = +y）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(100, 0)], [], 1.0)
	assert_float(absf(dir.y)).is_greater(0.4)
	assert_float(absf(dir.x)).is_less(0.01)


func test_move_closes_gap_to_distant_enemy() -> void:
	# 无威胁且敌人 200px（> 132 上沿）：朝敌接近。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(200, 0)], [], 1.0)
	assert_float(dir.x).is_greater(0.5)


func test_move_backs_off_when_enemy_too_close_even_in_band() -> void:
	# 无弹幕但敌人 60px（< 72 下沿）：拉开。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(60, 0)], [], 1.0)
	assert_float(dir.x).is_less(-0.5)


func test_bullet_threat_overrides_band_keeping() -> void:
	# 弹幕威胁在场时理想距离带逻辑关闭（避免互相抵消原地站桩挨打）：
	# 敌 100px（带内）+ 左侧逼近弹 → 纯躲弹方向。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(-60, 0), "vel": Vector2(110, 0)}],
		[Vector2(100, 0)], [], 1.0)
	assert_float(dir.x).is_greater(0.5)


func test_wall_clamp_pulls_back_inside_bounds() -> void:
	# 玩家越出左界：x 轴强制拉回（≥1），y 不受影响。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2(-170, 0), Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(-110, 0), "vel": Vector2(-110, 0)}],   # 弹在推人向墙
		[], [], 1.0)
	assert_float(dir.x).is_greater_equal(1.0)


func test_soft_wall_avoid_keeps_off_walls() -> void:
	# 贴近左墙内侧（8px < 20 避墙距）：软性向内推（风筝贴墙即挨打）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2(-152, 0), Rect2(-160, -96, 320, 192),
		[], [], [], 1.0)
	assert_float(dir.x).is_greater(0.4)


func test_soft_wall_avoid_inactive_away_from_walls() -> void:
	# 房中央：无避墙分量。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2(0, 0), Rect2(-160, -96, 320, 192),
		[], [], [], 1.0)
	assert_vector(dir).is_equal(Vector2.ZERO)


func test_hazard_zone_repels() -> void:
	# 下方 12px 有地刺 hazard 域：向上避开（hazard 排斥半径 24px 生效）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [Rect2(-8, 12, 16, 16)], 1.0)
	assert_float(dir.y).is_less(-0.3)


func test_hazard_zone_far_away_ignored() -> void:
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [Rect2(-8, 80, 16, 16)], 1.0)
	assert_vector(dir).is_equal(Vector2.ZERO)


# ---------------- 自爆虫引信（armed bomber）走位/翻滚 ----------------

func test_move_flees_armed_bomber_blast() -> void:
	# 右侧 50px 有引信已点燃的自爆虫（aoe 40 + 余量 16 ≥ 50）：强力反向逃离。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [{"pos": Vector2(50, 0), "radius": 40.0}])
	assert_float(dir.x).is_less(-0.5)


func test_move_ignores_bomber_beyond_blast_margin() -> void:
	# 80px > 40 aoe + 16 余量：未进入爆炸域，不动。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [{"pos": Vector2(80, 0), "radius": 40.0}])
	assert_vector(dir).is_equal(Vector2.ZERO)


func test_bomber_flee_overrides_distance_band() -> void:
	# 爆炸域斥力压过理想距离带（敌在带内但自爆虫逼近 → 逃离优先）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(100, 0)], [], 1.0, [{"pos": Vector2(-45, 0), "radius": 40.0}])
	assert_float(dir.x).is_greater(0.5)


func test_roll_dodges_bomber_blast() -> void:
	# bomber_d = 距离-爆炸半径 = 30-40 = -10（炸圈内）→ 沿远离方向翻滚。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"bomber_d": -10.0, "bomber_away": Vector2.LEFT,
		"roll_sample": 0.3, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.LEFT)


func test_roll_skipped_when_outside_bomber_margin() -> void:
	# bomber_d = 20 ≥ 20 余量（m4p-bal-b 8→20，边界含入为 <）：不在炸圈边缘触发窗
	# 内，不因自爆虫翻滚。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"bomber_d": 20.0, "bomber_away": Vector2.LEFT,
		"roll_sample": 0.0, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


func test_roll_triggers_within_widened_bomber_margin() -> void:
	# m4p-bal-b 余量 8→20（引信 0.5s 内虫闭近 ~47px，旧 8px 触发几乎必吃爆炸；
	# 20px 给翻滚 56px 位移+无敌帧留余量）：bomber_d = 15（旧余量外/新余量内）
	# → 沿远离方向翻滚（语义变更钉测）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"bomber_d": 15.0, "bomber_away": Vector2.LEFT,
		"roll_sample": 0.5, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.LEFT)


func test_bullet_roll_takes_precedence_over_bomber() -> void:
	# 同时贴弹 + 在炸圈：弹优先（高频威胁优先于低频爆炸）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": 20.0, "bullet_away": Vector2.DOWN,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"bomber_d": -10.0, "bomber_away": Vector2.LEFT,
		"roll_sample": 0.1, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.DOWN)


# ---------------- 走位机动性（juke / 未点燃自爆虫保距） ----------------

func test_approaching_bullet_adds_lateral_juke() -> void:
	# 右侧逼近弹：除闪避主分量外带切向 juke（wander_sign=1 → +y），不站桩挨打。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(60, 0), "vel": Vector2(-110, 0)}],
		[], [], 1.0)
	assert_float(dir.x).is_less(-0.5)
	assert_float(dir.y).is_greater(0.05)


func test_juke_sign_follows_wander_sign() -> void:
	var plus := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(60, 0), "vel": Vector2(-110, 0)}],
		[], [], 1.0)
	var minus := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(60, 0), "vel": Vector2(-110, 0)}],
		[], [], -1.0)
	assert_float(plus.y).is_greater(0.05)
	assert_float(minus.y).is_less(-0.05)


func test_move_keeps_distance_from_unarmed_bomber() -> void:
	# 未点燃自爆虫（armed=false）：保距斥力压过距离带趋近，但弱于点燃后的强逃。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [{"pos": Vector2(60, 0), "radius": 40.0, "armed": false}])
	assert_float(dir.x).is_less(-0.3)
	assert_float(dir.x).is_greater(-2.0)   # 温和权重（弱于 armed 的 2.4 强逃）


func test_move_ignores_unarmed_bomber_beyond_keepaway() -> void:
	# 未点燃自爆虫在保距域外（60+16+44=120 < 140）：不构成斥力。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [{"pos": Vector2(140, 0), "radius": 40.0, "armed": false}])
	assert_vector(dir).is_equal(Vector2.ZERO)


# ================================================================ 翻滚触发

func test_roll_blocked_by_cooldown() -> void:
	# 翻滚 CD 未就绪：贴弹也不翻（生产 roll_ready_at 守卫等价）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": false,
		"bullet_d": 20.0, "bullet_away": Vector2.LEFT,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.0, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


func test_roll_on_close_bullet_sample_pass() -> void:
	# 贴弹 20px（< 40 触发半径）+ 采样 0.3 < 0.5 概率 → 沿远离弹方向翻滚。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": 20.0, "bullet_away": Vector2.LEFT,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.3, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.LEFT)


func test_roll_skipped_when_sample_fails() -> void:
	# 贴弹但采样 0.9 ≥ 0.5：本拍不翻（概率翻滚——受玩家 CD 自然限频）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": 20.0, "bullet_away": Vector2.LEFT,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.9, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


func test_roll_bullet_far_no_panic_no_roll() -> void:
	# 弹 100px（> 40 触发半径）且无近战贴脸：不翻。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": 100.0, "bullet_away": Vector2.LEFT,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.0, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


func test_roll_perpendicular_to_charge() -> void:
	# 冲锋怪前摇指向自己：沿垂直方向侧闪（charge_perp 为调用方算好的垂直向）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2(0, 1),
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.0, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_float(absf(out["dir"].x)).is_less(0.01)
	assert_float(absf(out["dir"].y)).is_greater(0.99)


func test_melee_panic_roll() -> void:
	# 近战贴脸 30px（< 34 panic 半径）+ panic 采样 0.2 < 0.4：沿远离方向翻。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": 30.0, "melee_away": Vector2.UP,
		"roll_sample": 0.0, "panic_sample": 0.2, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.UP)


func test_melee_panic_blocked_by_sample() -> void:
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": 30.0, "melee_away": Vector2.UP,
		"roll_sample": 0.0, "panic_sample": 0.9, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


func test_bullet_roll_takes_precedence_over_melee_panic() -> void:
	# 同时贴弹 + 贴脸：弹优先（弹是主要死因），方向取远离弹。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": 20.0, "bullet_away": Vector2.DOWN,
		"charge_perp": Vector2.ZERO,
		"melee_d": 10.0, "melee_away": Vector2.UP,
		"roll_sample": 0.1, "panic_sample": 0.1, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2.DOWN)


# ================================================================ 购买决策

func test_buy_heart_when_missing_hp_and_affordable() -> void:
	assert_bool(BalanceBotDecisions.buy_heart(3, 8, 30, 25, false)).is_true()


func test_no_buy_when_hp_near_full() -> void:
	# 缺 1 HP（红心回 2 溢出）→ 不买（缺 ≥2 才买）。
	assert_bool(BalanceBotDecisions.buy_heart(7, 8, 30, 25, false)).is_false()


func test_no_buy_when_coins_insufficient() -> void:
	assert_bool(BalanceBotDecisions.buy_heart(3, 8, 20, 25, false)).is_false()


func test_no_buy_when_already_sold() -> void:
	assert_bool(BalanceBotDecisions.buy_heart(3, 8, 30, 25, true)).is_false()


func test_no_buy_at_full_hp() -> void:
	assert_bool(BalanceBotDecisions.buy_heart(8, 8, 30, 25, false)).is_false()


# ================================================================ 三选一贪心

func _buff_rows() -> Dictionary:
	return {
		"b_atk": {"rarity": "common", "effects": {"atk_speed_pct": 0.1}},
		"b_hp": {"rarity": "common", "effects": {"hp_max": 2}},
		"b_rare": {"rarity": "rare", "effects": {"crit_pct": 0.05}},
		"b_shield": {"rarity": "uncommon", "effects": {"shield_max": 1}},
	}


func test_greedy_prefers_heal_when_hurt() -> void:
	# 缺 3 HP：hp_max 增益生存权重最高，胜过更高稀有度的输出键。
	var pick: String = BalanceBotDecisions.greedy_pick(
		["b_atk", "b_hp", "b_rare"], _buff_rows(), 3)
	assert_str(pick).is_equal("b_hp")


func test_greedy_takes_rarity_when_healthy() -> void:
	# 满血：稀有度主导（rare 3.0 > common 输出 1.5）。
	var pick: String = BalanceBotDecisions.greedy_pick(
		["b_atk", "b_hp", "b_rare"], _buff_rows(), 0)
	assert_str(pick).is_equal("b_rare")


func test_greedy_tie_breaks_by_offer_order() -> void:
	# 平分取先出现者（确定性；无隐藏随机）。
	var pick: String = BalanceBotDecisions.greedy_pick(
		["b_atk", "b_shield"], {
			"b_atk": {"rarity": "common", "effects": {"crit_pct": 0.05}},
			"b_shield": {"rarity": "common", "effects": {"shield_max": 1}},
		}, 4)
	# crit 输出键 +0.5 / shield +1.0 → shield 胜（不平分，非首个）。
	assert_str(pick).is_equal("b_shield")
	var pick2: String = BalanceBotDecisions.greedy_pick(
		["b_atk", "b_shield"], {
			"b_atk": {"rarity": "common", "effects": {"atk_speed_pct": 0.1}},
			"b_shield": {"rarity": "common", "effects": {}},
		}, 4)
	# 同为 common：atk 1+0.5=1.5 vs shield 1+0=1 → atk（首个且更高）。
	assert_str(pick2).is_equal("b_atk")


func test_greedy_unknown_effects_fall_back_to_rarity() -> void:
	# 未知效果键（新数据行）：退化为纯稀有度排序，不崩溃。
	var pick: String = BalanceBotDecisions.greedy_pick(
		["b_new_a", "b_new_b"], {
			"b_new_a": {"rarity": "common", "effects": {"unknown_key": 1}},
			"b_new_b": {"rarity": "uncommon", "effects": {}},
		}, 0)
	assert_str(pick).is_equal("b_new_b")


# ================================================================ m4-b3② shooter 接近带（风筝残差主因）

func test_threat_approaches_far_shooter() -> void:
	# m3-fix2 §2.1.3 形态：弩兵 180px 外风筝 + 弹自 shooter 方向逼近（(90,0) 向左飞）。
	# 既有逻辑在 has_threat 下整段跳过距离带 → 恒距 150~200px 打不进；
	# B-3② 起超带 shooter 给趋近主分量：躲避（juke ±y）保持的同时净趋近（+x）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(90, 0), "vel": Vector2(-110, 0)}],
		[Vector2(180, 0)], [], 1.0, [], [Vector2(180, 0)])
	assert_float(dir.x).override_failure_message("dir=%s 应含向 shooter 的净趋近" % dir).is_greater(0.5)
	assert_float(absf(dir.y)).override_failure_message("dir=%s 应保留切向 juke" % dir).is_greater(0.3)

func test_threat_no_shooter_approach_within_band() -> void:
	# shooter 已在距离带内（≤132px 上沿）：无额外趋近——躲避分量不被反向抵消
	#（弹逼近 → 斥力 -x 仍在，不被趋近翻转符号）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[{"pos": Vector2(90, 0), "vel": Vector2(-110, 0)}],
		[Vector2(100, 0)], [], 1.0, [], [Vector2(100, 0)])
	assert_float(dir.x).override_failure_message("dir=%s 带内不得施加趋近" % dir).is_less(0.0)

func test_no_threat_shooter_param_zero_drift() -> void:
	# 无威胁时既有距离带逻辑照旧趋近（shooters 参数不叠加、不改变无威胁行为）。
	var base := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(180, 0)], [], 1.0)
	var with_shooters := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(180, 0)], [], 1.0, [], [Vector2(180, 0)])
	assert_vector(with_shooters).is_equal(base)
	assert_float(base.x).is_greater(0.5)


# ================================================================ m4-b3③ 实体斥力场（3271-a3 Seek 楔死柱面修法）

func test_solid_repulsion_pushes_off_face() -> void:
	# 站在柱右面外 12px（带宽 14px 内）：O(1) 寻的 +x 上叠加额外离面斥力
	#（净 +x 大于纯归一化 seek 的 1.0）。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0), Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)
	assert_float(dir.x).override_failure_message("dir=%s 应含离面斥力" % dir).is_greater(1.1)

func test_solid_repulsion_slide_aligns_with_intent() -> void:
	# 滑移方向取「沿面且与意图同侧」（帮助绕行而非对顶）：寻的 (1,0.5) 与面切向
	# (0,1) 点积为正 → 滑移 +y；寻的 (1,-0.5) → 滑移 -y。
	var s1 := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0.5), Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)
	var s2 := BalanceBotDecisions.seek_with_solids(
		Vector2(1, -0.5), Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)
	assert_float(s1.y).is_greater(0.0)
	assert_float(s2.y).is_less(0.0)

func test_solid_repulsion_slide_orthogonal_intent_falls_back_to_wander_sign() -> void:
	# 意图与面切向正交（点积 0）：回落 wander_sign（确定性 = 同种子可复现）。
	var s1 := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0), Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)
	var s2 := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0), Vector2(44, 16), [Rect2(0, 0, 32, 32)], -1.0)
	assert_float(s1.y).is_greater(0.0)
	assert_float(s2.y).is_less(0.0)

func test_solid_repulsion_decays_with_distance() -> void:
	# 线性衰减：离面越近斥力越强（4px 处 > 12px 处；x 同为纯 +x 寻的，只比斥力差）。
	var near := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0), Vector2(36, 16), [Rect2(0, 0, 32, 32)], 1.0)
	var far := BalanceBotDecisions.seek_with_solids(
		Vector2(1, 0), Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)
	assert_float(near.x).is_greater(far.x)

func test_solid_repulsion_outside_band_is_zero() -> void:
	# 带宽（14px）外无斥力：O(1) seek 原样直通（归一化不动点）。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(-1, 0), Vector2(120, 16), [Rect2(32, 0, 32, 32)], 1.0)
	assert_vector(dir).is_equal(Vector2(-1, 0))

func test_seek_with_solids_normalizes_large_magnitude_seek() -> void:
	# 3230 复跑实证的契约：调用方可直传「目标-自身」距离向量（如 47px 寻的），
	# 非 O(1) 的 seek 须归一——否则 O(1) 斥力/滑移被大模长淹没，8 向量化后
	# 垂直分量低于 0.35 阈值、顶死柱面复发。带外时返回归一化 seek（无斥力叠加）。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(47, 0.5), Vector2(1050, 20), [Rect2(1056, 144, 16, 16)], 1.0)
	assert_vector(dir).is_equal_approx(Vector2(47, 0.5).normalized(), Vector2(0.001, 0.001))

func test_seek_with_solids_empty_or_zero_passthrough_exact() -> void:
	# 空 solids / 零 seek：逐字节直通（存量调用路径零漂移）。
	assert_vector(BalanceBotDecisions.seek_with_solids(
		Vector2(-21.5, 0.5), Vector2.ZERO, [], 1.0)).is_equal(Vector2(-21.5, 0.5))
	assert_vector(BalanceBotDecisions.seek_with_solids(
		Vector2.ZERO, Vector2(44, 16), [Rect2(0, 0, 32, 32)], 1.0)).is_equal(Vector2.ZERO)

func test_seek_with_solids_unwedges_realistic_pickup_seek() -> void:
	# 3230-a3 复跑捕获形态（心寻的 47px + 16px 箱在正前方 6px）：归一化后斥力
	# 与滑移同量级——顶死轴（+x）分量衰减到 8 向阈值下、切向滑移轴（-y）越过
	# 阈值 → 沿箱面滑移绕行（楔死被打破）。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(47, 0.5), Vector2(1050, 148),
		[Rect2(1072, 128, 16, 16), Rect2(1072, 144, 16, 16), Rect2(1056, 144, 16, 16)],
		1.0)
	assert_float(absf(dir.y)).override_failure_message("dir=%s 滑移轴未越过 8 向阈值" % dir).is_greater(0.35)
	assert_float(dir.x).override_failure_message("dir=%s 顶死轴未释放" % dir).is_less(0.35)

func test_seek_with_solids_nearest_slide_rounds_corner() -> void:
	# 3230-a2 复跑捕获形态回归钉（心寻的 89px 西北向 + 贴身两枚错切向箱面）：
	# 双面对齐滑移互拍（垂直净剩 0.245 < 0.35）+ 径向西推 → 单轴顶死箱面。
	# 滑移改取最近面单源后：西轴释放、北轴（绕角方向）≥0.35 按压 → 斜滑绕角。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(-85.5, -26), Vector2(1094, 151),
		[Rect2(1072, 128, 16, 16), Rect2(1072, 144, 16, 16)], 1.0)
	assert_float(dir.y).override_failure_message("dir=%s 绕角轴未按压" % dir).is_less(-0.35)
	assert_float(absf(dir.x)).override_failure_message("dir=%s 顶死轴未释放" % dir).is_less(0.35)

func test_seek_with_solids_no_dead_zone_equilibrium() -> void:
	# 3217-a2 复跑捕获形态回归钉（心寻的 85px 西南向 + 正北侧两枚平行箱面）：
	# wander_sign 定向滑移曾同向叠加（+1.33x）对消寻的（-0.956x）→ 净向量
	# (0.34,-0.27) 双轴落入 8 向死区 → 玩家零输入定死。滑移对齐意图后合成向量
	# 恢复寻的侧按压（西行绕过箱列西端）。
	var solids := [Rect2(-1024, -720, 16, 16), Rect2(-1008, -720, 16, 16),
		Rect2(-992, -720, 16, 16), Rect2(-976, -720, 16, 16), Rect2(-960, -720, 16, 16)]
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(-81.5, 25), Vector2(-982, -732), solids, 1.0)
	assert_float(dir.x).override_failure_message("dir=%s 死区复现（x 轴未按压）" % dir).is_less(-0.35)

func test_seek_with_solids_unwedges_head_on_seek() -> void:
	# 3271-a3 形态：寻的 seek 顶死柱面（柱面在正前方 12px）——叠加斥力后出现
	# 切向滑移（y≠0），同时寻的分量仍保留（斥力是带内附加，不是接管）。
	var dir := BalanceBotDecisions.seek_with_solids(
		Vector2(-1, 0), Vector2(76, 16), [Rect2(32, 0, 32, 32)], 1.0)
	assert_float(absf(dir.y)).override_failure_message("dir=%s 楔死未破" % dir).is_greater(0.0001)
	assert_float(dir.x).is_less(0.0)

func test_combat_move_dir_default_args_zero_drift() -> void:
	# 既有 7 参调用（缺省 shooters/solids）行为逐字节不变（B-3 硬验收：
	# 既有决策契约零漂移）。
	var bullets := [{"pos": Vector2(60, 0), "vel": Vector2(-110, 0)}]
	var enemies: Array = [Vector2(-50, 0)]
	var base := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192), bullets, enemies, [], 1.0)
	var explicit := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192), bullets, enemies, [], 1.0, [], [], [])
	assert_vector(explicit).is_equal(base)

func test_combat_move_dir_applies_solid_repulsion_in_combat() -> void:
	# 战斗走位同样吃斥力场：无弹无敌时站在柱面外 12px → 合力含离面 +x 分量。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2(76, 16), Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [], [], [Rect2(32, 0, 32, 32)])
	assert_float(dir.x).is_greater(0.0)


# ================================================================ m4-b3① 观测差分速度（lead 预判入参）

func test_velocity_from_track_two_tick_window() -> void:
	# 2 拍窗：位移 (1,-2)px / (2/60)s → 速度 (30,-60) px/s。
	var v := BalanceBotDecisions.velocity_from_track(
		Vector2(100, 100), 1000, Vector2(101, 98), 1002)
	assert_vector(v).is_equal_approx(Vector2(30, -60), Vector2(0.001, 0.001))

func test_velocity_from_track_rejects_noise_and_stale_windows() -> void:
	# dt=1 逐拍抖动噪声拒收；dt>30 陈旧锚点拒收——均按「静止目标」处理
	#（lead 退化为直瞄，不注入虚假预判）。
	assert_vector(BalanceBotDecisions.velocity_from_track(
		Vector2.ZERO, 1000, Vector2(5, 0), 1001)).is_equal(Vector2.ZERO)
	assert_vector(BalanceBotDecisions.velocity_from_track(
		Vector2.ZERO, 1000, Vector2(50, 0), 1035)).is_equal(Vector2.ZERO)


# ================================================================ m4p-bal-b 自爆虫逃离去对消（bomber_flee_vector）

func test_flee_two_bugs_pincer_nonzero_not_toward_either() -> void:
	# 两虫等距对夹（90° 夹角，均入爆炸域 48 < 40+16）：新口径 = 最近一只径向
	# （权重 2.4）+ 左垂直切向机动（权重 1.0，wander_sign=1）——向量非零，且对
	# 两虫方向的投影均为负（不指向任一虫；旧求和口径在此形态已开始互拍）。
	var v := BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO,
		[{"pos": Vector2(48, 0), "radius": 40.0, "armed": true},
			{"pos": Vector2(0, 48), "radius": 40.0, "armed": true}],
		1.0)
	assert_float(v.length()).override_failure_message(
		"v=%s 对夹逃离不得为零（旧求和口径对消病灶）" % v).is_greater(0.3)
	assert_float(v.dot(Vector2(1, 0))).override_failure_message(
		"v=%s 不得指向虫 1" % v).is_less(0.0)
	assert_float(v.dot(Vector2(0, 1))).override_failure_message(
		"v=%s 不得指向虫 2" % v).is_less(0.0)


func test_flee_diametric_bugs_no_cancellation() -> void:
	# 180° 对夹（旧口径 away 求和恰好 ≈0 定身挨炸——本卡去对消核心回归钉）：
	# 逃离向量非零，且保留「远离最近虫（先出现者）」的径向主分量。
	var v := BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO,
		[{"pos": Vector2(48, 0), "radius": 40.0, "armed": true},
			{"pos": Vector2(-48, 0), "radius": 40.0, "armed": true}],
		1.0)
	assert_float(v.length()).override_failure_message(
		"v=%s 对夹逃离不得为零（求和对消复发）" % v).is_greater(0.3)
	assert_float(v.dot(Vector2(1, 0))).is_less(0.0)


func test_flee_tangent_sign_follows_wander_sign() -> void:
	# 确定性：切向机动符号随 wander_sign 翻转（同输入必同输出的两种拍）；
	# 径向主分量不受游走符号影响。
	var plus := BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO, [{"pos": Vector2(48, 0), "radius": 40.0, "armed": true}], 1.0)
	var minus := BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO, [{"pos": Vector2(48, 0), "radius": 40.0, "armed": true}], -1.0)
	assert_float(plus.x).is_equal(minus.x)
	assert_float(plus.y).is_less(0.0)
	assert_float(minus.y).is_greater(0.0)


func test_flee_zero_outside_blast_or_unarmed() -> void:
	# 爆炸域外（80 > 40+16）的武装虫 / 未点燃虫（保距走 combat_move_dir 原段）：
	# 均不产生逃离分量（触发域口径同旧）。
	assert_vector(BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO, [{"pos": Vector2(80, 0), "radius": 40.0, "armed": true}], 1.0)
	).is_equal(Vector2.ZERO)
	assert_vector(BalanceBotDecisions.bomber_flee_vector(
		Vector2.ZERO, [{"pos": Vector2(30, 0), "radius": 40.0, "armed": false}], 1.0)
	).is_equal(Vector2.ZERO)


func test_move_not_frozen_between_diametric_armed_bombers() -> void:
	# 走位层集成钉：两虫 180° 对夹均入爆炸域，combat_move_dir 输出含逃离+切向
	# 机动（|v|>0.3）——旧求和口径恰好对消为 0，bot 定身挨炸（100 局死因主形态）。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [], [], 1.0,
		[{"pos": Vector2(48, 0), "radius": 40.0}, {"pos": Vector2(-48, 0), "radius": 40.0}])
	assert_float(dir.length()).override_failure_message(
		"dir=%s 对夹走位不得为零（对消复发）" % dir).is_greater(0.3)


# ================================================================ m4p-bal-b 自爆虫优先瞄准（aim_priority_index）

func test_aim_priority_locks_armed_bomber_within_priority_px() -> void:
	# 武装虫 ≤240px：锁定该虫下标——即使普通敌人（60px）更近也优先（先杀后走：
	# 玩家移速 80 < 自爆虫 95 跑不掉只能早杀）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(300, 0), Vector2(120, 0), Vector2(60, 0)],
		[false, true, false],
		[300.0, 120.0, 60.0])
	assert_int(idx).is_equal(1)


func test_aim_priority_picks_nearest_among_armed_bombers() -> void:
	# 多只武装虫满足：取最近一只（严格 <，同距取先出现者——确定性）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(200, 0), Vector2(90, 0)],
		[true, true],
		[200.0, 90.0])
	assert_int(idx).is_equal(1)


func test_aim_priority_ignores_armed_bomber_beyond_priority_px() -> void:
	# 仅远处武装虫（>240px）：无优先 → -1（走默认最近目标）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(300, 0)], [true], [300.0])
	assert_int(idx).is_equal(-1)


func test_aim_priority_ignores_unarmed_bomber_within_priority_px() -> void:
	# 未点燃虫：即便 ≤240px 也不优先（走位层保距已覆盖，瞄准不让位）→ -1。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(100, 0)], [false], [100.0])
	assert_int(idx).is_equal(-1)


func test_aim_priority_boundary_at_priority_px() -> void:
	# 边界：恰好 240px（≤240px 含入）→ 优先。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(240, 0)], [true], [240.0])
	assert_int(idx).is_equal(0)


func test_aim_priority_distance_fallback_from_poses() -> void:
	# bomber_ds 缺项：回落 pos×enemy_poses 几何距离（纯函数容错，不炸）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(120, 0)], [true], [])
	assert_int(idx).is_equal(0)


# ================================================================ m4p-bal-c① 大体积距离带
# probe 3493 归因：电磁蛛（radius 7×1.25=8.75，speed 80 = 玩家移速）80px 拉开带
# 外恒距逼近 → 贴墙收尾接触冲撞死；Boss 半径 16 更甚。缺口与带沿随 combat_radius
# 线性外扩（k=2），半径观测缺项按 0 = 既有行为零漂移。

func test_big_body_gap_scales_melee_retreat() -> void:
	# Boss（radius 16）在 100px：旧缺口 80 外无退避（带内环绕 y 轴分量）；
	# 新缺口 80+16×2=112 内 → 退避（+x）。
	var base := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(-100, 0)], [], 1.0, [], [], [], [0.0])
	assert_float(absf(base.x)).override_failure_message(
		"base=%s 小怪口径 100px 不得退避" % base).is_less(0.01)
	var big := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(-100, 0)], [], 1.0, [], [], [], [16.0])
	assert_float(big.x).override_failure_message(
		"big=%s 大体积缺口应触发退避" % big).is_greater(0.5)

func test_big_body_band_scales_band_edges() -> void:
	# Boss（radius 16）在 150px：旧带上沿 132 外 → 趋近；新上沿 132+32=164 内 →
	# 环绕（x 轴零分量，不推入 70px 拍击扇形程）。
	var base := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(150, 0)], [], 1.0, [], [], [], [0.0])
	assert_float(base.x).override_failure_message(
		"base=%s 旧口径 150px 应趋近" % base).is_greater(0.5)
	var big := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192),
		[], [Vector2(150, 0)], [], 1.0, [], [], [], [16.0])
	assert_float(absf(big.x)).override_failure_message(
		"big=%s 新带内不得趋近" % big).is_less(0.01)

func test_big_body_radii_missing_is_zero_drift() -> void:
	# enemy_radii 缺项（空数组/短数组）= 半径 0：既有行为逐字节不变（容错契约）。
	var without := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192), [], [Vector2(150, 0)], [], 1.0)
	var with_empty := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192), [], [Vector2(150, 0)], [], 1.0,
		[], [], [], [])
	var with_short := BalanceBotDecisions.combat_move_dir(
		Vector2.ZERO, Rect2(-160, -96, 320, 192), [], [Vector2(150, 0)], [], 1.0,
		[], [], [], [4.0])
	assert_vector(with_empty).is_equal(without)
	assert_vector(with_short).is_equal(without)


# ================================================================ m4p-bal-c② Boss 预告观测

func test_wedge_zone_repels_inside() -> void:
	# 拍击扇形（apex 原点、facing +x、range 70、half 45°）：玩家 (40,10) 在域内
	# → 从 apex 径向推出（+x 逃离主分量 + 微切向）。
	var v := BalanceBotDecisions.boss_zone_repulsion(Vector2(40, 10), [{
		"kind": "wedge", "apex": Vector2.ZERO, "facing": 0.0,
		"range_px": 70.0, "half_angle": PI * 0.25,
	}])
	assert_float(v.x).override_failure_message("v=%s 应径向推出" % v).is_greater(1.0)
	assert_float(v.y).override_failure_message("v=%s 应保留方位切向" % v).is_greater(0.05)

func test_wedge_zone_ignores_outside_range_or_arc() -> void:
	var zone := {"kind": "wedge", "apex": Vector2.ZERO, "facing": 0.0,
		"range_px": 70.0, "half_angle": PI * 0.25}
	# 距离 80 > 70：域外零分量。
	assert_vector(BalanceBotDecisions.boss_zone_repulsion(Vector2(80, 0), [zone])
		).is_equal(Vector2.ZERO)
	# 弧外（180°）：零分量。
	assert_vector(BalanceBotDecisions.boss_zone_repulsion(Vector2(-40, 0), [zone])
		).is_equal(Vector2.ZERO)
	# 未知 kind：零分量（契约外数据不炸）。
	assert_vector(BalanceBotDecisions.boss_zone_repulsion(Vector2(40, 0),
		[{"kind": "unknown"}])).is_equal(Vector2.ZERO)

func test_wedge_zone_in_combat_move_dir() -> void:
	# 走位集成钉：拍击 windup 内玩家站扇形域中 → 合力含逃离主分量。
	var dir := BalanceBotDecisions.combat_move_dir(
		Vector2(40, 0), Rect2(-160, -96, 320, 192),
		[], [], [], 1.0, [], [], [], [],
		[{"kind": "wedge", "apex": Vector2.ZERO, "facing": 0.0,
			"range_px": 70.0, "half_angle": PI * 0.25}])
	assert_float(dir.x).override_failure_message("dir=%s 扇形域应逃离" % dir).is_greater(1.0)

func test_boss_band_impact_ticks_windup_static_at_anchor() -> void:
	# windup 段条带静止于 x0=0：elapsed=10 → 命中拍 = 余 32t + (100-12)/12.67 ≈ 38.9。
	var t := BalanceBotDecisions.boss_band_impact_ticks(10.0, 100.0, 0.0, 456.0, 42, 36, 12.0)
	assert_float(t).is_equal_approx(32.0 + 88.0 * 36.0 / 456.0, 0.01)

func test_boss_band_impact_ticks_travel_approaching_and_passed() -> void:
	# travel 中段（elapsed=60 → 中心 228）：玩家 300 前方 72px → (72-12)/(456/36)≈4.74；
	# 玩家 100 已越过（dist=-128 < -12）→ INF（单回合单次命中已结算语义）。
	var t := BalanceBotDecisions.boss_band_impact_ticks(60.0, 300.0, 0.0, 456.0, 42, 36, 12.0)
	assert_float(t).is_equal_approx(60.0 * 36.0 / 456.0, 0.01)
	assert_float(BalanceBotDecisions.boss_band_impact_ticks(
		60.0, 100.0, 0.0, 456.0, 42, 36, 12.0)).is_equal(INF)

func test_boss_band_impact_ticks_behind_origin_and_travel_end() -> void:
	# windup 段玩家在行进起点后方（dist < -半厚）→ 条带出发即远离 → INF；
	# travel 结束（progress=1）未及玩家（dist > 半厚）→ INF；条带缘（dist=半厚）→ 0。
	assert_float(BalanceBotDecisions.boss_band_impact_ticks(
		10.0, -30.0, 0.0, 456.0, 42, 36, 12.0)).is_equal(INF)
	assert_float(BalanceBotDecisions.boss_band_impact_ticks(
		78.0, 470.0, 0.0, 456.0, 42, 36, 12.0)).is_equal(INF)
	assert_float(BalanceBotDecisions.boss_band_impact_ticks(
		78.0, 468.0, 0.0, 456.0, 42, 36, 12.0)).is_equal(0.0)
	# 反向行进（x1 < x0）：前向镜像几何（中心 228、玩家在前方 72px）。
	var t := BalanceBotDecisions.boss_band_impact_ticks(60.0, 156.0, 456.0, 0.0, 42, 36, 12.0)
	assert_float(t).is_equal_approx(60.0 * 36.0 / 456.0, 0.01)

func test_roll_band_triggers_against_travel_direction() -> void:
	# 条带命中前 8 拍（≤9 阈值）+ 采样 0.5 < 0.9 → 翻滚，方向 = 逆行进向
	#（条带 12.7px/t 快于翻滚 4.3px/t，顺向滚 i-frame 13t 内被追上——迎面穿越）。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"boss_band_ticks": 8.0, "boss_band_dir": Vector2(1, 0),
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.5, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2(-1, 0))

func test_roll_band_skipped_when_far_or_sample_fails() -> void:
	# 命中 30 拍后（> 9 阈值）：不因条带翻滚（i-frame 13t 覆盖不到，留到临身拍）。
	var ctx := {
		"roll_ready": true,
		"boss_band_ticks": 30.0, "boss_band_dir": Vector2(1, 0),
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.5, "panic_sample": 0.0, "side_sample": 0.5,
	}
	assert_bool(BalanceBotDecisions.roll_decision(ctx)["do"]).is_false()
	# 临身但采样 0.95 ≥ 0.9：本拍不翻（概率口径同自爆虫）。
	ctx["boss_band_ticks"] = 8.0
	ctx["roll_sample"] = 0.95
	assert_bool(BalanceBotDecisions.roll_decision(ctx)["do"]).is_false()

func test_roll_band_takes_precedence_over_bullet() -> void:
	# 同时临条带 + 贴弹：条带优先（5 伤必中 > 3 伤可躲），方向取逆行进向。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"boss_band_ticks": 6.0, "boss_band_dir": Vector2(1, 0),
		"bullet_d": 20.0, "bullet_away": Vector2.DOWN,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.3, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_true()
	assert_vector(out["dir"]).is_equal(Vector2(-1, 0))

func test_roll_band_absent_zero_drift() -> void:
	# boss_band_* 缺省（INF/ZERO）：既有 roll_decision 契约逐字节不变。
	var ctx := {
		"roll_ready": true,
		"bullet_d": 20.0, "bullet_away": Vector2.LEFT,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"roll_sample": 0.3, "panic_sample": 0.0, "side_sample": 0.5,
	}
	var with_key := ctx.duplicate()
	with_key["boss_band_ticks"] = INF
	with_key["boss_band_dir"] = Vector2.ZERO
	assert_vector(BalanceBotDecisions.roll_decision(with_key)["dir"]
		).is_equal(BalanceBotDecisions.roll_decision(ctx)["dir"])


# ================================================================ m4p-bal-c③ 红心目标黏滞
# probe 3472-a1 实拍（3271 式极限环）：已清 elite 房双心分居柱面两侧
# (176.5,957)/(165.5,933.5)，逐拍重选使 seek 滑移符号随最近心翻转 → 柱东面
# y∈[954,959.5] 9 唯一位极限环，160s 零拾取。锁定窗内维持目标，窗满重锁最近。

func test_sticky_heart_locks_within_window() -> void:
	# 锁定窗内（50 < 90 拍）：即使 2 号更近（3271 捕获形态：最近心随玩家滑动
	# 逐拍翻转）也维持 1 号锁——绕柱方向承诺不被逐拍撤销。
	var cands := [{"id": 1, "pos": Vector2(165.5, 933.5)},
		{"id": 2, "pos": Vector2(176.5, 957.0)}]
	var pick := BalanceBotDecisions.sticky_heart_id(1, 100, cands,
		Vector2(201.5, 956.0), 150, 90)
	assert_int(pick).is_equal(1)

func test_sticky_heart_relocks_after_window() -> void:
	# 窗满（100 ≥ 90）：恢复最近心评估。原位（2 号仍最近）重锁结果不变——
	# 评估不引入抖动；玩家绕到柱北（y=920，1 号最近）→ 允许换目标（黏滞非永久锁）。
	var cands := [{"id": 1, "pos": Vector2(165.5, 933.5)},
		{"id": 2, "pos": Vector2(176.5, 957.0)}]
	assert_int(BalanceBotDecisions.sticky_heart_id(2, 100, cands,
		Vector2(201.5, 956.0), 200, 90)).is_equal(2)
	assert_int(BalanceBotDecisions.sticky_heart_id(2, 100, cands,
		Vector2(201.5, 920.0), 200, 90)).is_equal(1)

func test_sticky_heart_initial_and_gone_and_empty() -> void:
	var cands := [{"id": 1, "pos": Vector2(165.5, 933.5)},
		{"id": 2, "pos": Vector2(176.5, 957.0)}]
	# 无旧锁（-1）：直接最近。
	assert_int(BalanceBotDecisions.sticky_heart_id(-1, -1, cands,
		Vector2(201.5, 956.0), 100, 90)).is_equal(2)
	# 旧锁已消失（拾取/失效）：自愈重锁最近。
	assert_int(BalanceBotDecisions.sticky_heart_id(3, 100, cands,
		Vector2(201.5, 956.0), 150, 90)).is_equal(2)
	# 无候选：-1。
	assert_int(BalanceBotDecisions.sticky_heart_id(1, 100, [],
		Vector2.ZERO, 150, 90)).is_equal(-1)


# ================================================================ m4p-bal-d② Boss 房小怪优先瞄准
# aim_priority_index 二级扩展：Boss（boss_flags）在场且存在 ≤160px 会开火小怪
# （minion_flags，Boss 房蘑菇孢子手减速孢子扇）→ 优先最近小怪；否则回落原逻辑
# （武装自爆虫一级语义不变）。

func test_aim_priority_minion_preferred_over_nearer_boss() -> void:
	# Boss+小怪：Boss 60px 更近、孢子手 120px（≤160）→ 优先小怪（下标 1）——
	# 旧口径取最近必锁 Boss 本体，小怪在旁白嫖（两轮门禁 Boss 房死因）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(60, 0), Vector2(120, 0)],
		[false, false],
		[60.0, 120.0],
		[true, false],
		[false, true])
	assert_int(idx).is_equal(1)


func test_aim_priority_boss_only_falls_back() -> void:
	# 仅 Boss（无会开火小怪）：-1 走默认最近（= Boss 本体）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(60, 0)], [false], [60.0], [true], [false])
	assert_int(idx).is_equal(-1)


func test_aim_priority_minion_beyond_priority_px_falls_back() -> void:
	# 小怪超距（>160px）：-1（不打横穿半房去够炮手，先走位打 Boss）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(80, 0), Vector2(200, 0)],
		[false, false],
		[80.0, 200.0],
		[true, false],
		[false, true])
	assert_int(idx).is_equal(-1)


func test_aim_priority_minion_boundary_at_priority_px() -> void:
	# 边界：恰好 160px（≤ 含入）→ 优先。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(160, 0)], [false], [160.0], [true], [true])
	assert_int(idx).is_equal(0)


func test_aim_priority_armed_bomber_still_first_over_minion() -> void:
	# 一级语义不变：武装虫在场（150px ≤240）压过 Boss 房小怪二级（100px ≤160）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(100, 0), Vector2(150, 0), Vector2(300, 0)],
		[false, true, false],
		[100.0, 150.0, 300.0],
		[false, false, true],
		[true, false, false])
	assert_int(idx).is_equal(1)


func test_aim_priority_firing_minion_without_boss_ignored() -> void:
	# 会开火小怪在 ≤160px 但无 Boss（普通/精英/垒主房）：二级不触发 → -1
	# （弩兵风筝等既有走位带语义不变）。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(100, 0)], [false], [100.0], [false], [true])
	assert_int(idx).is_equal(-1)


func test_aim_priority_minion_tie_picks_first_and_ds_fallback() -> void:
	# 多只小怪满足：同距取先出现者（确定性）；bomber_ds 缺项回落几何距离。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(120, 0), Vector2(0, 120)],
		[false, false],
		[120.0, 120.0],
		[true, false],
		[true, true])
	assert_int(idx).is_equal(0)
	var idx2 := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(120, 0)], [false], [], [true], [true])
	assert_int(idx2).is_equal(0)


func test_aim_priority_legacy_four_arg_zero_drift() -> void:
	# 既有 4 参调用（卡 B 契约）行为逐字节不变：新可选参缺省 = 二级永不触发。
	var idx := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO,
		[Vector2(300, 0), Vector2(120, 0), Vector2(60, 0)],
		[false, true, false],
		[300.0, 120.0, 60.0])
	assert_int(idx).is_equal(1)
	var no_bomber := BalanceBotDecisions.aim_priority_index(
		Vector2.ZERO, [Vector2(90, 0)], [false], [90.0])
	assert_int(no_bomber).is_equal(-1)


# ================================================================ m4p-bal-d① 武器升级拾取
# DPS 口径 = damage×rate（近战同口径，range/arc 不折算）；严格优于当前较弱槽才换
# （平手不换）；空槽必拾。生产缝：LootStation.interact → WeaponRig.equip
# 「填第一个空槽；双槽满替换当前槽」（weapon_rig.gd）——bot 预切较弱槽后换装。

func _vanguard_slots() -> Array:
	# 初始双槽数值形态：laohuoji 3×4.0=12.0 / tiejian 6×2.2=13.2（较弱 = 槽 0）。
	return [{"id": "laohuoji", "damage": 3, "rate": 4.0},
		{"id": "tiejian", "damage": 6, "rate": 2.2, "is_melee": true}]


func test_upgrade_picks_when_strictly_better_than_weakest() -> void:
	# 地面 14 DPS > 较弱槽 12.0 → 拾取（哪怕低于较强槽 13.2——规则对较弱槽）。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "testgun", "damage": 7, "rate": 2.0})).is_true()


func test_upgrade_skips_tie_or_weaker_vs_weakest() -> void:
	# 平手不换（12.0 == 较弱槽 12.0，容差内）；更差（11.9）不换。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "dupe", "damage": 3, "rate": 4.0})).is_false()
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "weak", "damage": 7, "rate": 1.7})).is_false()


func test_upgrade_empty_slot_always_picks() -> void:
	# 空槽（{}）必拾：即便地面武器更弱（单武器英雄第二把等）。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(
		[{"id": "duangong", "damage": 6, "rate": 1.8}, {}],
		{"id": "weak", "damage": 2, "rate": 1.6})).is_true()
	# 无武器（退化 rig）必拾；地面行空（未知 id）保守不换。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup([],
		{"id": "any", "damage": 1, "rate": 1.0})).is_true()
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{})).is_false()


func test_upgrade_melee_same_caliber_no_range_folding() -> void:
	# 近战同口径：damage×rate 直比（range/arc 覆盖差不折算）——14 DPS 近战拾取、
	# 11 DPS 近战不换。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "melee_up", "damage": 7, "rate": 2.0, "is_melee": true,
			"range": 40, "arc_deg": 90.0})).is_true()
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "melee_down", "damage": 5, "rate": 2.2, "is_melee": true,
			"range": 40, "arc_deg": 90.0})).is_false()


func test_upgrade_missing_keys_treated_as_zero() -> void:
	# 行缺 damage/rate 键（特殊武器防御形态）→ DPS 0：不触发换装（除非空槽）。
	assert_bool(BalanceBotDecisions.weapon_upgrade_pickup(_vanguard_slots(),
		{"id": "special", "rarity": "rare"})).is_false()


func test_weakest_slot_index_contract() -> void:
	# 双槽满：较弱槽下标（严格 <，同 DPS 取先出现者）；空槽即最弱；空数组 -1。
	assert_int(BalanceBotDecisions.weakest_slot_index(_vanguard_slots())).is_equal(0)
	assert_int(BalanceBotDecisions.weakest_slot_index([
		{"id": "tiejian", "damage": 6, "rate": 2.2},
		{"id": "laohuoji", "damage": 3, "rate": 4.0}])).is_equal(1)
	assert_int(BalanceBotDecisions.weakest_slot_index([{}, _vanguard_slots()[0]])).is_equal(0)
	assert_int(BalanceBotDecisions.weakest_slot_index([
		{"damage": 3, "rate": 4.0}, {"damage": 6, "rate": 2.0}])).is_equal(0)
	assert_int(BalanceBotDecisions.weakest_slot_index([])).is_equal(-1)


func test_weapon_loot_index_picks_highest_dps_passing() -> void:
	# 三台中仅中间台合格（10 更差、12 平手均被过滤）：取合格者（下标 1）。
	var cands := [
		{"id": 11, "pos": Vector2(50, 0), "row": {"damage": 5, "rate": 2.0}},   # 10 更差
		{"id": 22, "pos": Vector2(90, 0), "row": {"damage": 5, "rate": 4.0}},   # 20 合格
		{"id": 33, "pos": Vector2(10, 0), "row": {"damage": 3, "rate": 4.0}},   # 12 平手
	]
	assert_int(BalanceBotDecisions.weapon_loot_index(cands, _vanguard_slots(),
		Vector2.ZERO)).is_equal(1)


func test_weapon_loot_index_tie_prefers_nearest_then_first() -> void:
	# DPS 平手：取最近（下标 2 近于下标 1）；完全等价取先出现者（下标 0）。
	var cands := [
		{"id": 11, "pos": Vector2(90, 0), "row": {"damage": 5, "rate": 4.0}},
		{"id": 22, "pos": Vector2(40, 0), "row": {"damage": 10, "rate": 2.0}},
		{"id": 33, "pos": Vector2(20, 0), "row": {"damage": 5, "rate": 4.0}},
	]
	assert_int(BalanceBotDecisions.weapon_loot_index(cands, _vanguard_slots(),
		Vector2.ZERO)).is_equal(2)
	var tie := [
		{"id": 11, "pos": Vector2(30, 0), "row": {"damage": 5, "rate": 4.0}},
		{"id": 22, "pos": Vector2(30, 0), "row": {"damage": 5, "rate": 4.0}},
	]
	assert_int(BalanceBotDecisions.weapon_loot_index(tie, _vanguard_slots(),
		Vector2.ZERO)).is_equal(0)


func test_weapon_loot_index_none_passing_or_empty() -> void:
	# 全体不合格（平手/更差/空行）或无候选：-1（bot 不寻的、直接走图）。
	var cands := [
		{"id": 11, "pos": Vector2(50, 0), "row": {"damage": 3, "rate": 4.0}},   # 平手
		{"id": 22, "pos": Vector2(60, 0), "row": {}},                            # 未知行
	]
	assert_int(BalanceBotDecisions.weapon_loot_index(cands, _vanguard_slots(),
		Vector2.ZERO)).is_equal(-1)
	assert_int(BalanceBotDecisions.weapon_loot_index([], _vanguard_slots(),
		Vector2.ZERO)).is_equal(-1)
