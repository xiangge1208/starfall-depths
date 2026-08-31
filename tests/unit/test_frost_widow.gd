class_name TestFrostWidow
extends GdUnitTestSuite

## M2-T16 D-3 寒渊蛛母脑层注入帧测试（沿用 test_boss_m2_wave1 手法）：
## 附录 E.4（HP 1800）——冰面铺设（房间 40% 复用 T4 IceZone 数据注入）/
##   蛛网禁锢（3 张落点网，落地 24t 后禁锢 1s；玩家离开落点即网未触发）/
##   螺旋弹幕（双臂螺旋持续 4s，弹伤 5 弹速 100）/ 召唤冰蛛×3（cap 3）/
##   冰晶牢笼（玩家周围 8 根冰柱环形围困留 1 缺口，短命 3s）/
##   全屏冰刺阵（2 条缝隙安全线，其余 5 伤）。
## 招式拍序约定（同 vine/queen）：招式起始拍 ms，前摇 N 在 tick ms+N 结算。

const FROST_ROW := {
	"id": "frost_widow", "name": "寒渊蛛母", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/frost_widow.gd",
	"hp": 1800, "contact_dmg": 5, "speed": 20, "walk_speed": 20,
	"radius": 16.0, "bullet_dmg": 5, "bullet_speed": 100,
	"bullet_life_seconds": 2.0, "bullet_radius": 4.0,
	"phases": [1.0, 0.6, 0.3],
}
const FRAME := 30000   # 注入帧基准（远离 0，同 test_boss_base）
const BOUNDS := Rect2(Vector2(-228, -119), Vector2(456, 238))   # M0 战斗房内域


class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


func _ctx(amount: int) -> Dictionary:
		return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}

func _widow() -> FrostWidow:
	var b: FrostWidow = auto_free(FrostWidow.new())
	b._test_init(FROST_ROW.duplicate(true))
	return b

## ALERT 24t 后进 ENGAGE；返回首个 _engage 拍（首招该拍起）。
func _engage_ready(b: EnemyBase) -> int:
	b.on_player_seen(FRAME)
	for f in range(FRAME + 1, FRAME + 25):
		b.brain_tick(f)
	return FRAME + 25

## 驱动 ticks 拍并收集「新招起始拍」的招式名序列。
func _run_collect(b: EnemyBase, start: int, ticks: int) -> Array:
	var seq: Array = []
	for i in range(ticks):
		b.brain_tick(start + i)
		if b.get("_move") != "" and b.get("_move_start") == start + i:
			seq.append(b.get("_move"))
	return seq

## 驱动至目标招式已起始，返回其 _move_start（超时即失败）。
func _drive_to_move(b: EnemyBase, move: String, f: int, limit := 4000) -> int:
	for _i in range(limit):
		if b.get("_move") == move:
			return b.get("_move_start")
		b.brain_tick(f)
		f += 1
	assert_str(String(b.get("_move"))).is_equal(move)
	return -1


# ================================================================ 前摇下限

# ---- 前摇下限（附录 E 预警规范：所有招式前摇 ≥0.4s = 24t；数值逐字 E.4）----

func test_widow_every_windup_at_least_24t() -> void:
	assert_int(FrostWidow.MIN_WINDUP_TICKS).is_equal(24)
	assert_int(FrostWidow.CARPET_WINDUP_TICKS).is_equal(30)     # E.4 冰面铺设 0.5s
	assert_int(FrostWidow.WEBS_WINDUP_TICKS).is_equal(36)       # E.4 蛛网禁锢 0.6s
	assert_int(FrostWidow.SPIRAL_WINDUP_TICKS).is_equal(42)     # E.4 螺旋弹幕 0.7s
	assert_int(FrostWidow.SUMMON_WINDUP_TICKS).is_equal(48)     # E.4 召唤冰蛛 0.8s
	assert_int(FrostWidow.CAGE_WINDUP_TICKS).is_equal(54)       # E.4 冰晶牢笼 0.9s
	assert_int(FrostWidow.SPIKES_WINDUP_TICKS).is_equal(36)     # E.4 P3 合并行拆分披露 0.6s


# ================================================================ 阶段门控

# ---- P0 铺冰面/蛛网禁锢；P1 +螺旋弹幕/召唤冰蛛；P2 +冰晶牢笼/冰刺阵 ----

func test_widow_p0_carpet_once_then_webs_only() -> void:
	var b := _widow()
	var f := _engage_ready(b)
	var seq := _run_collect(b, f, 600)
	assert_int(seq.size()).is_greater_equal(6)
	assert_str(seq[0]).is_equal("carpet")             # 开战先铺冰面
	var carpet_count := 0
	for m in seq:
		assert_bool(m == "carpet" or m == "webs").is_true()
		if m == "carpet":
			carpet_count += 1
	assert_int(carpet_count).is_equal(1)              # 冰面一场一次（铺后不入序列）

func test_widow_move_sets_expand_by_phase() -> void:
	var b := _widow()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 400):
		assert_bool(m == "carpet" or m == "webs").is_true()
	b._take_hit_at(_ctx(720), f + 400)                # 1800-720=1080 → P1（60%）
	var seq1 := _run_collect(b, f + 400, 1200)
	assert_bool(seq1.has("spiral")).is_true()
	assert_bool(seq1.has("summon")).is_true()
	assert_bool(seq1.has("cage")).is_false()
	assert_bool(seq1.has("spikes")).is_false()
	for m in seq1:
		assert_bool(m == "carpet" or m == "webs" or m == "spiral" or m == "summon").is_true()
	b._take_hit_at(_ctx(540), f + 1600)               # 1080-540=540 → P2（30%）
	var seq2 := _run_collect(b, f + 1600, 1600)
	assert_bool(seq2.has("cage")).is_true()
	assert_bool(seq2.has("spikes")).is_true()
	for m in seq2:
		assert_bool(m == "carpet" or m == "webs" or m == "spiral" or m == "summon"
			or m == "cage" or m == "spikes").is_true()


# ================================================================ 冰面铺设（P0）

# ---- 前摇 30t 后房间 40% 变冰面：复用 T4 IceZone（区域经注入接口写入）----

func test_widow_carpet_covers_40pct_of_room_via_injected_ice_zone() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var injected := IceZone.new()                     # 生产接缝：房间注入 FloorScene.biome_ice
	b.ice_zone = injected
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "carpet", f)      # P0 首招即铺冰面
	for i in range(FrostWidow.CARPET_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_bool(b.get("_ice_laid")).is_true()
	assert_int(injected.zones.size()).is_equal(2)     # 2 条横带 = 40% 内域
	var total := 0.0
	for r in injected.zones:
		total += r.get_area()
		assert_bool(BOUNDS.has_point(r.get_center())).is_true()
	assert_float(total).is_equal_approx(BOUNDS.get_area() * 0.4, 0.01)
	# 冰面数据可被 IceZone.in_ice 命中（玩家摩擦接缝由 FloorScene 帧驱动）
	assert_bool(injected.in_ice(injected.zones[0].get_center())).is_true()
	assert_bool(injected.in_ice(BOUNDS.position + Vector2(4, 4))).is_false()   # 角落在带外

func test_widow_carpet_never_relaid_within_move_stream() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var injected := IceZone.new()
	b.ice_zone = injected
	var f := _engage_ready(b)
	_run_collect(b, f, 800)
	assert_int(injected.zones.size()).is_equal(2)     # 后续招式不再叠加冰面


# ================================================================ 蛛网禁锢（P0）

# ---- 前摇 36t 落 3 张落点网；落地 24t 后仍在网心半径内 → 伤 4 + 禁锢 1s；
#      玩家离开落点即网未触发（可打断）。禁锢表现：锚定玩家 brain_pos 于网心 ±6px
#      （同 vine 拍击击退的脑层位移披露口径，真实表现层接线归房间/Proxy）----

func test_widow_webs_three_targets_then_restrain_1s() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "webs", f)
	var targets: Array = b._web_targets               # 招式起始拍即定落点（预警红圈）
	assert_int(targets.size()).is_equal(3)
	assert_vector(targets[0]).is_equal_approx(Vector2(0, 0), Vector2(0.01, 0.01))   # 首落点=玩家位
	var trigger: int = ms + FrostWidow.WEBS_WINDUP_TICKS + FrostWidow.WEB_TRIGGER_DELAY_TICKS
	for i in range(trigger - ms):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)           # 落地 24t 后仍在网心 → 触发
	assert_int(spy.hits[0]["amount"]).is_equal(4)     # E.4 蛛网禁锢 伤害 4
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("蛛网禁锢")
	var center: Vector2 = targets[0]
	assert_int(b._restraints.size()).is_equal(1)
	assert_int(int(b._restraints[0]["until"])).is_equal(trigger + FrostWidow.RESTRAIN_TICKS)
	# 转 P1（螺旋接管序列）：禁锢窗内不再有背靠背蛛网干扰断言面
	b._take_hit_at(_ctx(720), trigger)                # 1800-720=1080 → P1
	# 禁锢窗内：brain_pos 被锚回网心 ±RESTRAIN_SLACK_PX
	spy.brain_pos = center + Vector2(200, 0)
	b.brain_tick(trigger + 1)
	assert_vector(spy.brain_pos).is_equal_approx(center + Vector2(FrostWidow.RESTRAIN_SLACK_PX, 0),
		Vector2(0.01, 0.01))
	for i in range(FrostWidow.RESTRAIN_TICKS - 2):    # 窗内持续锚定（frame ≤ until）
		spy.brain_pos = center + Vector2(200, 0)
		b.brain_tick(trigger + 2 + i)
	# 禁锢 1s（60t）到期：until 拍仍锚定，until+1 拍起不再锚定
	spy.brain_pos = center + Vector2(200, 0)
	b.brain_tick(trigger + FrostWidow.RESTRAIN_TICKS)
	assert_vector(spy.brain_pos).is_equal_approx(center + Vector2(FrostWidow.RESTRAIN_SLACK_PX, 0),
		Vector2(0.01, 0.01))
	spy.brain_pos = center + Vector2(200, 0)
	b.brain_tick(trigger + FrostWidow.RESTRAIN_TICKS + 1)
	assert_vector(spy.brain_pos).is_equal_approx(center + Vector2(200, 0), Vector2(0.01, 0.01))
	assert_array(b._restraints).is_empty()

func test_widow_webs_dodge_before_trigger_cancels_web() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "webs", f)
	for i in range(FrostWidow.WEBS_WINDUP_TICKS - 4): # 落地前离开落点
		b.brain_tick(ms + 1 + i)
	spy.brain_pos = Vector2(0, 160)
	for i in range(FrostWidow.WEB_TRIGGER_DELAY_TICKS + 2):
		b.brain_tick(ms + FrostWidow.WEBS_WINDUP_TICKS + i)
	assert_int(spy.hits.size()).is_equal(0)           # 网未触发
	assert_array(b._restraints).is_empty()


# ================================================================ 螺旋弹幕（P1）

# ---- 前摇 42t 后双臂螺旋持续 4s：80 轮×2 臂=160 发，弹伤 5 弹速 100，
#      同轮两臂相差 180°，逐轮旋进 2.25°（0.75°/拍×3 拍轮距；4s 恰扫满半圆无重向）----

func test_widow_spiral_4s_dual_arm_160_bullets() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "widow_spiral_test"))
	root.add_child(cs)
	var b := _widow()
	b.combat = cs
	b._take_hit_at(_ctx(720), FRAME - 100)            # → P1
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "spiral", f)
	var fired: Array = []
	var total_ticks := FrostWidow.SPIRAL_WINDUP_TICKS + FrostWidow.SPIRAL_DURATION_TICKS + 2
	for i in range(total_ticks):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_int(fired.size()).is_equal(FrostWidow.SPIRAL_VOLLEYS)                # 80 轮
	assert_int(fired[0]).is_equal(ms + FrostWidow.SPIRAL_WINDUP_TICKS)          # 前摇 42t 首轮
	assert_int(fired[1] - fired[0]).is_equal(FrostWidow.SPIRAL_PERIOD_TICKS)    # 轮距 3t
	assert_int(cs.active_count()).is_equal(FrostWidow.SPIRAL_VOLLEYS * FrostWidow.SPIRAL_ARMS)  # 160
	# 双臂：每发都有相差 180° 的对臂；螺旋方向（mod π）恰 80 个互异值（逐轮旋进 2.25°）
	var mods: Array[float] = []
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(5)
		assert_float(p.vel.length()).is_equal_approx(100.0, 0.01)
		assert_str(p.attack_name).is_equal("螺旋弹幕")
		var a := wrapf(p.vel.angle(), 0.0, TAU)
		var has_opposite := false
		for q in cs.pool.active:
			if absf(absf(angle_difference(a, wrapf(q.vel.angle(), 0.0, TAU))) - PI) < 0.001:
				has_opposite = true
				break
		assert_bool(has_opposite).is_true()
		var m := wrapf(a, 0.0, PI)
		var seen := false
		for existing in mods:
			if absf(angle_difference(m, existing)) < 0.001:
				seen = true
				break
		if not seen:
			mods.append(m)
	assert_int(mods.size()).is_equal(FrostWidow.SPIRAL_VOLLEYS)

func test_widow_spiral_not_cast_before_p1() -> void:
	var b := _widow()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 800):
		assert_str(String(m)).is_not_equal("spiral")  # P0 不施放螺旋弹幕


# ================================================================ 召唤冰蛛（P1）

# ---- 前摇 48t 召唤冰蛛×3（ice_spider 行，经 spawn_callback），cap 3 ----

func test_widow_summon_three_ice_spiders_via_callback() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	b._take_hit_at(_ctx(720), FRAME - 100)            # → P1
	var spawned: Array = []
	var cb := func(row_id: String, pos: Vector2, _override: Dictionary) -> Node:
		var minion := Node2D.new()
		minion.set("row_id", row_id)
		minion.position = pos
		spawned.append(row_id)
		return minion
	b.spawn_callback = cb
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "summon", f)
	for i in range(FrostWidow.SUMMON_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_array(spawned).is_equal(["ice_spider", "ice_spider", "ice_spider"])   # ×3
	assert_int(b._minions.size()).is_equal(3)
	for m in b._minions:
		assert_bool(BOUNDS.grow(2.0).has_point(m.position)).is_true()
	for m in b._minions:                              # 召唤体由测试收养（防孤儿泄漏）
		m.free()

func test_widow_summon_gated_while_cap_three_alive() -> void:
	var b := _widow()
	b._take_hit_at(_ctx(720), FRAME - 100)            # → P1
	var cb := func(_row_id: String, _pos: Vector2, _override: Dictionary) -> Node:
		return Node2D.new()                           # 活体（无 DEAD 状态）→ cap 顶满
	b.spawn_callback = cb
	var f := _engage_ready(b)
	_run_collect(b, f, 900)
	assert_int(b._minions.size()).is_equal(3)
	for m in _run_collect(b, f + 900, 1200):
		assert_str(String(m)).is_not_equal("summon")  # 3 只存活期内召唤不入序列
	for m in b._minions:                              # 召唤体由测试收养（防孤儿泄漏）
		m.free()


# ================================================================ 冰晶牢笼（P2）

# ---- 前摇 54t 在玩家周围落 8 根冰柱（9 环位留 1 缺口 = 80° 豁口），短命 3s；
#      落柱点位压玩家 → 伤 6 恰一跳 ----

func test_widow_cage_eight_pillars_single_gap() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)           # 1800-1260=540 → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	assert_vector(b._cage_center).is_equal_approx(Vector2(0, 0), Vector2(0.01, 0.01))   # 锁定玩家位
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	var pillars: Array = b._cage_pillars
	assert_int(pillars.size()).is_equal(FrostWidow.CAGE_PILLAR_COUNT)           # 8 根
	var angles: Array[float] = []
	for p in pillars:
		assert_float(p.pos_world.distance_to(b._cage_center)) \
			.is_equal_approx(FrostWidow.CAGE_RING_RADIUS_PX, 0.5)               # 同环半径
		angles.append(wrapf((p.pos_world - b._cage_center).angle(), 0.0, TAU))
	angles.sort()
	var gaps: Array[float] = []
	for i in angles.size():
		var nxt := angles[(i + 1) % angles.size()]
		var gap := wrapf(nxt - angles[i], 0.0, TAU)
		gaps.append(rad_to_deg(gap))
	gaps.sort()
	for i in range(gaps.size() - 1):                  # 除缺口外 7 个相邻间距 = 40°
		assert_float(gaps[i]).is_equal_approx(40.0, 0.5)
	assert_float(gaps[gaps.size() - 1]).is_equal_approx(80.0, 0.5)              # 缺口 = 80°（1 空位）

func test_widow_cage_landing_hits_player_on_pillar_once_for6() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	# 落柱前把玩家移到某一非缺口环位（slot 0 或 slot 1）上 → 落柱压中
	var slot := 0 if int(b._cage_gap_slot) != 0 else 1
	spy.brain_pos = b._cage_center \
		+ Vector2.from_angle(TAU * float(slot) / float(FrostWidow.CAGE_SLOTS)) \
		* FrostWidow.CAGE_RING_RADIUS_PX
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(6)     # E.4 冰晶牢笼 伤害 6
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("冰晶牢笼")

func test_widow_cage_pillars_shortlived_3s() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(b._cage_pillars.size()).is_equal(8)
	for i in range(FrostWidow.CAGE_PILLAR_LIFE_TICKS):
		b.brain_tick(ms + FrostWidow.CAGE_WINDUP_TICKS + 1 + i)
	assert_int(b._cage_pillars.size()).is_equal(8)    # until 拍仍在（生命周期恰 3s）
	b.brain_tick(ms + FrostWidow.CAGE_WINDUP_TICKS + FrostWidow.CAGE_PILLAR_LIFE_TICKS + 1)
	assert_int(b._cage_pillars.size()).is_equal(0)    # until+1 拍清场


# ================================================================ 全屏冰刺阵（P2）

# ---- 前摇 36t 蓝纹预警后全屏冰刺：8 泳道中 2 条缝隙安全线，其余泳道 5 伤 ----

func test_widow_spike_field_two_safe_gap_lanes() -> void:
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "spikes", f)
	var gaps: Array = b._spike_gap_indices
	assert_int(gaps.size()).is_equal(FrostWidow.SPIKE_GAP_LANES)                # 2 条缝隙
	assert_bool(gaps[0] != gaps[1]).is_true()         # 缝隙互异
	var lane_w := BOUNDS.size.x / float(FrostWidow.SPIKE_LANE_COUNT)
	# 泳道内玩家：中招 5 伤恰一跳
	var spike_lane := 0
	while gaps.has(spike_lane):
		spike_lane += 1
	spy.brain_pos = Vector2(BOUNDS.position.x + lane_w * (float(spike_lane) + 0.5), 0.0)
	b.brain_tick(ms + FrostWidow.SPIKES_WINDUP_TICKS)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(5)     # E.4 冰刺阵 5 伤
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("冰刺阵")
	# 下一轮冰刺阵：缝隙泳道内玩家免伤（驱动途中蛛网等伤害不进入免伤断言面）
	var ms2: int = _drive_to_move(b, "spikes", ms + FrostWidow.SPIKES_WINDUP_TICKS + 1)
	var gaps2: Array = b._spike_gap_indices
	spy.hits.clear()
	spy.brain_pos = Vector2(
		BOUNDS.position.x + lane_w * (float(gaps2[0]) + 0.5), 0.0)
	b.brain_tick(ms2 + FrostWidow.SPIKES_WINDUP_TICKS)
	assert_int(spy.hits.size()).is_equal(0)           # 安全线免伤


# ================================================================ 数据接线与死亡路径

func test_widow_gamedb_row_and_factory_wiring() -> void:
	var row := GameDB.get_enemy("frost_widow")
	assert_int(row.get("hp", 0)).is_equal(1800)       # 附录 E.4：HP 1800
	assert_str(String(row.get("name", ""))).is_equal("寒渊蛛母")
	assert_int(int(row.get("contact_dmg", 0))).is_equal(5)
	assert_array(row.get("phases", [])).is_equal([1, 0.6, 0.3])   # GameDB 深度整值还原（1.0→1，vine 同口径）
	assert_bool(row.has("boss_script")).is_true()
	assert_int(int(row.get("bullet_speed", 0))).is_less_equal(150)   # 弹速契约
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	assert_object(e).is_not_null()
	assert_bool(e is FrostWidow).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	e._take_hit_at(_ctx(720), 9999)                   # 1800-720=1080 → P1
	assert_int(e.phase()).is_equal(1)

func test_widow_dies_and_despawns_cage_pillars() -> void:
	var b := _widow()
	b._take_hit_at(_ctx(1260), FRAME - 100)           # → P2（牢笼解锁）
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(b._cage_pillars.size()).is_equal(8)
	var pillar = b._cage_pillars[0]
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(2000), ms + 100)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["frost_widow"])
	assert_bool(bool(pillar.alive)).is_false()        # 冰柱随 Boss 退场
	EventBus.enemy_killed.disconnect(cb)
