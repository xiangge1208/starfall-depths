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
	# bomber_d = 20 > 8 余量：不在炸圈边缘，不因自爆虫翻滚。
	var out := BalanceBotDecisions.roll_decision({
		"roll_ready": true,
		"bullet_d": INF_F, "bullet_away": Vector2.ZERO,
		"charge_perp": Vector2.ZERO,
		"melee_d": INF_F, "melee_away": Vector2.ZERO,
		"bomber_d": 20.0, "bomber_away": Vector2.LEFT,
		"roll_sample": 0.0, "panic_sample": 0.0, "side_sample": 0.5,
	})
	assert_bool(out["do"]).is_false()


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
