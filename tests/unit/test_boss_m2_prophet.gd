class_name TestBossM2Prophet
extends GdUnitTestSuite

## M2-T24 D-4 星陨先知（A3 隐藏 Boss，附录 E.6，HP 3200）脑层注入帧测试
## （沿用 test_boss_m2_wave1 / test_vine_colossus 手法）：
##   P1 元素轮回（火环/冰针/毒云/电链四轮，轮回序跨施法延续）/
##   星陨（3 颗追踪星体，可被近战反弹——combat.reflect 后停追踪、可击回 Boss）/
##   P2 单元素领域（8s，重施切换元素）/ 共鸣斩（对已有异常玩家强制附加第二状态）/
##   P3 星河（滚筒弹幕墙 ×3 波，缺口即安全通道；期间召唤 2 星髓聚合体）。
## 隐藏门（GDD §10/裁定）：A3 层携带任意共鸣（本层 resonance_triggered >0）击杀
##   小 Boss → 开启星陨门（FloorScene 接线：星陨先知入场 + StarfallGate 贴花）。
## 招式拍序约定（同 vine）：招式起始拍 ms，前摇 N 在 tick ms+N 结算。

const PROPHET_ROW := {
	"id": "starfall_prophet", "name": "星陨先知", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/starfall_prophet.gd",
	"hp": 3200, "contact_dmg": 9, "speed": 20, "walk_speed": 20,
	"radius": 16.0, "bullet_dmg": 6, "bullet_speed": 100,
	"bullet_life_seconds": 2.5, "bullet_radius": 4.0,
	"phases": [1.0, 0.6, 0.3], "drops": "gems3,soul",
}
const FRAME := 30000   # 注入帧基准（远离 0，同 test_boss_m2_wave1）
const BOUNDS := Rect2(Vector2(-228, -119), Vector2(456, 238))   # M0 战斗房内域


class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


## 带元素异常的玩家替身（共鸣斩强制附加的鸭子接缝）：status 走 StatusComponent 契约。
class StatusedPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	var status: StatusComponent = null
	func _init() -> void:
		status = StatusComponent.new()
		add_child(status)
		status.setup(2, false)
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}


func _prophet() -> StarfallProphet:
	var b: StarfallProphet = auto_free(StarfallProphet.new())
	b._test_init(PROPHET_ROW.duplicate(true))
	return b


## ALERT 24t 后进 ENGAGE；返回首个 _engage 拍（首招该拍起）。
func _engage_ready(b: EnemyBase) -> int:
	b.on_player_seen(FRAME)
	for f in range(FRAME + 1, FRAME + 25):
		b.brain_tick(f)
	return FRAME + 25


## 驱动至目标招式已起始，返回其 _move_start（超时即失败）。
func _drive_to_move(b: EnemyBase, move: String, f: int, limit := 6000) -> int:
	for _i in range(limit):
		if b.get("_move") == move:
			return b.get("_move_start")
		b.brain_tick(f)
		f += 1
	assert_str(String(b.get("_move"))).is_equal(move)
	return -1


# ================================================================ 星陨先知（Boss 脑层）

# ---- 前摇下限（附录 E 预警规范：所有招式前摇 ≥0.4s = 24t）----

func test_prophet_every_windup_at_least_24t() -> void:
	assert_int(StarfallProphet.CYCLE_WINDUP_TICKS).is_equal(36)      # 附录 E.6：0.6s
	assert_int(StarfallProphet.STARFALL_WINDUP_TICKS).is_equal(48)   # 0.8s
	assert_int(StarfallProphet.FIELD_WINDUP_TICKS).is_equal(60)      # 1.0s
	assert_int(StarfallProphet.SLASH_WINDUP_TICKS).is_equal(30)      # 0.5s
	assert_int(StarfallProphet.GALAXY_WINDUP_TICKS).is_equal(72)     # 1.2s

# ---- 阶段门控：P1 轮回/星陨；P2 +领域/共鸣斩；P3 +星河 ----

func test_prophet_move_sets_expand_by_phase() -> void:
	var b := _prophet()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 600):
		assert_bool(m == "cycle" or m == "starfall").is_true()
	b._take_hit_at(_ctx(1280), f + 600)               # 3200-1280=1920 → P2
	var seq1 := _run_collect(b, f + 600, 1600)
	assert_bool(seq1.has("field")).is_true()
	assert_bool(seq1.has("slash")).is_true()
	assert_bool(seq1.has("galaxy")).is_false()
	for m in seq1:
		assert_bool(m == "cycle" or m == "starfall" or m == "field" or m == "slash").is_true()
	b._take_hit_at(_ctx(960), f + 2200)               # 1920-960=960 → P3
	var seq2 := _run_collect(b, f + 2200, 2400)
	assert_bool(seq2.has("galaxy")).is_true()
	for m in seq2:
		assert_bool(m == "cycle" or m == "starfall" or m == "field" or m == "slash"
			or m == "galaxy").is_true()

# ---- 元素轮回：前摇 36t，四轮各 24t——火环(12 环)/冰针(5 扇)/毒云(4 慢球)/电链(4 快索)，
#      每轮元素按 火→冰→毒→电 推进；弹伤 6（行 bullet_dmg）。池序 = 发射序（append）。

func test_prophet_element_cycle_four_rounds_fire_ice_poison_shock() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_cycle_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(160, 40)
	b.player_ref = spy
	var f := _engage_ready(b)
	b.brain_tick(f)                                   # 首拍起招 cycle
	var ms: int = b.get("_move_start")
	var fired: Array = []
	for i in range(112):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_array(fired).is_equal([ms + 36, ms + 60, ms + 84, ms + 108])   # 4 轮各隔 24t
	assert_int(cs.active_count()).is_equal(25)        # 12+5+4+4
	var rounds: Array = [cs.pool.active.slice(0, 12), cs.pool.active.slice(12, 17),
		cs.pool.active.slice(17, 21), cs.pool.active.slice(21, 25)]
	var expected := [Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.POISON, Elements.Id.SHOCK]
	for r in range(4):
		for p in rounds[r]:
			assert_int(p.damage).is_equal(6)          # 附录 E.6：伤 6
			assert_int(p.element).is_equal(expected[r])
	# 火环：12 发全环均布（相邻角差 ≈ 30°）
	var ring_angles: Array = []
	for p in rounds[0]:
		ring_angles.append(p.vel.angle())
	ring_angles.sort()
	for i in range(ring_angles.size()):
		var nxt: float = ring_angles[(i + 1) % ring_angles.size()]
		assert_float(absf(wrapf(nxt - ring_angles[i], -PI, PI))).is_equal_approx(TAU / 12.0, 0.01)
	# 冰针：5 发扇形，均以玩家锁定方向为心 ±30° 内、方向互异（行弹速）
	var aim: float = Vector2(160, 40).angle()
	var needle_dirs := {}
	for p in rounds[1]:
		assert_float(p.vel.length()).is_equal_approx(100.0, 0.01)
		assert_float(absf(angle_difference(aim, p.vel.angle()))).is_less_equal(deg_to_rad(30.0) + 0.001)
		needle_dirs[int(round(rad_to_deg(p.vel.angle())))] = true
	assert_int(needle_dirs.size()).is_equal(5)
	# 毒云：4 发慢速大弹（云团口径）
	for p in rounds[2]:
		assert_float(p.vel.length()).is_equal_approx(60.0, 0.01)
		assert_float(p.radius).is_equal_approx(8.0, 0.01)
	# 电链：4 发快索（敌方弹速契约 ≤150）
	for p in rounds[3]:
		assert_float(p.vel.length()).is_equal_approx(150.0, 0.01)
		assert_float(absf(angle_difference(aim, p.vel.angle()))).is_less_equal(deg_to_rad(12.0) + 0.001)

# ---- 元素轮回序跨施法延续：火→冰→毒→电→火…（_cycle_round 不随施法重置） ----

func test_prophet_element_cycle_persists_across_casts() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_cycle2_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(160, 40)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cycle", f)
	for i in range(112):                              # 第一次施法：火冰毒电
		b.brain_tick(ms + 1 + i)
	assert_int(b._cycle_round).is_equal(4)
	var ms2: int = _drive_to_move(b, "cycle", ms + 113)
	b.brain_tick(ms2 + 36)                            # 第二次施法首轮发射
	assert_int(b._cycle_round).is_equal(5)            # 轮回游标推进到 4（%4 = 火）
	var fire_rings := 0
	for p in cs.pool.active:
		if p.attack_name == "火环":
			fire_rings += 1
	assert_int(fire_rings).is_equal(24)               # 两次施法各 12 发火环
	for p in cs.pool.active:
		if p.attack_name == "火环":
			assert_int(p.element).is_equal(Elements.Id.FIRE)   # 第二次施法首轮回火

# ---- 星陨：前摇 48t，3 颗追踪星体（伤 7 r6）；逐拍向玩家转向；
#      近战反弹（combat.reflect）后停追踪、变玩家弹，可击回 Boss ----

func test_prophet_starfall_three_homing_stars() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_star_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(-120, 80)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "starfall", f)
	for i in range(48):
		b.brain_tick(ms + 1 + i)                      # 前摇 48t 落星
	var stars := _live_stars(cs)
	assert_int(stars.size()).is_equal(3)
	for s in stars:
		assert_int(s.damage).is_equal(7)              # 附录 E.6：伤 7
		assert_float(s.radius).is_equal_approx(6.0, 0.01)
		assert_int(s.faction).is_equal(Projectile.Faction.ENEMY)
		assert_str(s.attack_name).is_equal("星陨")
		assert_float(s.vel.length()).is_equal_approx(100.0, 0.01)   # 行弹速
	# 追踪：连续脑拍后星体速度朝玩家方向收拢（角距单调不增、有界步长）
	var turned := 0
	for i in range(30):
		var before: Array = []
		for s in _live_stars(cs):
			before.append(s.vel.angle())
		b.brain_tick(ms + 49 + i)
		var idx := 0
		for s in _live_stars(cs):
			var target: float = (spy.brain_pos - s.position).angle()
			var was_off := absf(angle_difference(before[idx], target))
			if was_off > 0.001:
				var remained := absf(angle_difference(s.vel.angle(), target))
				var stepped := absf(angle_difference(before[idx], s.vel.angle()))
				assert_float(remained).is_less_equal(was_off + 0.001)   # 朝玩家收拢
				assert_float(stepped).is_less_equal(StarfallProphet.STAR_TURN_RAD_PER_TICK + 0.001)
				turned += 1
			idx += 1
	assert_int(turned).is_greater(0)                  # 至少一颗发生了转向

func test_prophet_starfall_reflected_star_stops_homing_and_hits_boss() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_reflect_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(-120, 80)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "starfall", f)
	for i in range(48):
		b.brain_tick(ms + 1 + i)
	var all_stars := _live_stars(cs)
	var star: Projectile = all_stars[0]
	for k in range(1, all_stars.size()):
		cs.block(all_stars[k])                        # 隔离其余星体：只验证反弹星击回
	star.position = b.brain_pos + Vector2(-60, 0)     # 摆到 Boss 左侧
	star.vel = Vector2(-100, 0)                       # 正背离 Boss 飞
	cs.reflect(star, 10)                              # 近战反弹窗（Melee PARRY 同口径）
	assert_int(star.faction).is_equal(Projectile.Faction.PLAYER)
	assert_vector(star.vel).is_equal_approx(Vector2(100, 0), Vector2(0.01, 0.01))
	# 反弹后不再被 Boss 追踪（玩家弹不在追踪集）
	b.brain_tick(ms + 60)
	b.brain_tick(ms + 61)
	assert_vector(star.vel).is_equal_approx(Vector2(100, 0), Vector2(0.01, 0.01))
	# 击回：星体飞向 Boss（已注册战斗体），标准弹-体碰撞结算 Boss 受击
	cs.register_body(b, b.combat_faction())
	var hp_before: int = b.hp
	for _i in range(50):                              # 60px @100px/s ≈ 36 拍触体
		cs._physics_process(0.0)
	assert_int(b.hp).is_less(hp_before)               # 反弹星击回 Boss

# ---- 单元素领域：前摇 60t → 选元素开 8s（480t）领域；领域内存续招式弹带领域元素
##      （「领域内敌我伤害转化」的 Boss 侧口径）；重施切换元素并重锚窗口 ----

func test_prophet_field_lasting_8s_and_switch_on_recast() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_field_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(400, 300)                 # 斩外/远位：只看领域与轮回弹
	b.player_ref = spy
	b._take_hit_at(_ctx(1280), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "field", f)
	b.brain_tick(ms + 60)                             # 前摇 60t 开领域
	assert_int(b._field_element).is_equal(Elements.Id.FIRE)     # 领域序首元：火
	assert_int(b._field_until).is_equal(ms + 60 + StarfallProphet.FIELD_DURATION_TICKS)
	assert_int(StarfallProphet.FIELD_DURATION_TICKS).is_equal(480)   # 8s
	# 领域存续内的轮回弹全带领域元素（无领域时应为 火/冰/毒/电 四色——形成对照）
	var ms2: int = _drive_to_move(b, "cycle", ms + 62)
	for i in range(112):
		b.brain_tick(ms2 + 1 + i)
	assert_int(cs.active_count()).is_equal(25)
	for p in cs.pool.active:
		assert_int(p.element).is_equal(Elements.Id.FIRE)
	# 重施切换：第二门领域换元素并重锚窗口
	var ms3: int = _drive_to_move(b, "field", ms2 + 113)
	b.brain_tick(ms3 + 60)
	assert_int(b._field_element).is_equal(Elements.Id.ICE)      # 领域序轮转：冰
	assert_int(b._field_until).is_equal(ms3 + 60 + StarfallProphet.FIELD_DURATION_TICKS)
	# 过期：窗口后领域元素清空
	b._field_until = ms3 - 1
	b._field_tick(ms3)
	assert_int(b._field_element).is_equal(Elements.Id.NONE)

# ---- 共鸣斩：前摇 30t 扇形（90°/70px）伤 8；对已有异常玩家强制附加第二状态
#      （第二击带可共鸣搭档元素——引发共鸣，教玩家危险）；无异常仅一击 ----

func test_prophet_resonance_slash_forces_second_status_on_anomaly() -> void:
	var b := _prophet()
	var spy: StatusedPlayer = auto_free(StatusedPlayer.new())
	spy.brain_pos = Vector2(40, 0)                    # 斩击扇内
	b.player_ref = spy
	# 玩家已带火异常（StatusComponent 激活表）
	spy.status.active[Elements.Id.FIRE] = FRAME + 1000
	b._take_hit_at(_ctx(1280), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "slash", f)
	for i in range(30):
		b.brain_tick(ms + 1 + i)                      # 前摇 30t 结算
	assert_int(spy.hits.size()).is_equal(2)           # 本击 + 强制第二状态
	assert_int(spy.hits[0]["amount"]).is_equal(8)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("共鸣斩")
	assert_int(spy.hits[1]["amount"]).is_equal(8)
	assert_str(String(spy.hits[1]["attack_name"])).is_equal("元素共鸣")
	# 第二状态：与已有异常可共鸣的搭档元素（火 → 冰：淬爆组合）
	assert_int(int(spy.hits[1]["element"])).is_equal(Elements.Id.ICE)
	# 强制共鸣已按 StatusComponent 契约结算（forced 标记落表）
	assert_bool(bool(spy.status.resonance_event.get("forced", false))).is_true()

func test_prophet_resonance_slash_single_hit_without_anomaly() -> void:
	var b := _prophet()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(40, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1280), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	# 先走完首门领域并令其过期（排除领域元素被视作玩家异常的路径）
	var ms_field: int = _drive_to_move(b, "field", f)
	b.brain_tick(ms_field + 60)
	b._field_until = ms_field
	b._field_tick(ms_field + 60)
	assert_int(b._field_element).is_equal(Elements.Id.NONE)
	var ms: int = _drive_to_move(b, "slash", ms_field + 61)
	for i in range(30):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)           # 无异常：仅本击
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("共鸣斩")

func test_prophet_resonance_slash_treats_field_as_player_anomaly() -> void:
	var b := _prophet()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(40, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(1280), FRAME - 100)           # → P2
	var f := _engage_ready(b)
	# 先开领域（玩家被视为携带领域元素）
	var ms_field: int = _drive_to_move(b, "field", f)
	b.brain_tick(ms_field + 60)
	assert_int(b._field_element).is_equal(Elements.Id.FIRE)
	var ms: int = _drive_to_move(b, "slash", ms_field + 61)
	for i in range(30):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(2)           # 领域元素视作已有异常 → 强制第二状态
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.FIRE)   # 领域内直击转化
	assert_int(int(spy.hits[1]["element"])).is_equal(Elements.Id.ICE)   # 火 → 冰搭档

# ---- 星河：前摇 72t，滚筒弹幕墙 ×3 波（各隔 48t）横向推进，每波 12 行其中
#      2 缺口×2 行（缺口罩间=安全通道）；期间召唤 2 星髓聚合体 ----

func test_prophet_galaxy_three_walls_with_gaps_and_two_summons() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "prophet_galaxy_test"))
	root.add_child(cs)
	var b := _prophet()
	b.combat = cs
	b.combat_bounds = BOUNDS
	b._take_hit_at(_ctx(2240), FRAME - 100)           # 3200-2240=960 → P3
	var spawned: Array = []
	var minions: Array = []
	b.spawn_callback = func(arch: String, pos: Vector2, row_override: Dictionary) -> Variant:
		spawned.append(arch)
		var m := Node.new()
		minions.append(m)
		return m
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "galaxy", f)
	var fired: Array = []
	for i in range(168):                              # 驱动至第 3 波发射拍（ms+168）止：
		b.brain_tick(ms + 1 + i)                      # 下一拍即起新招并清 _galaxy_waves 记录面
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_array(fired).is_equal([ms + 72, ms + 120, ms + 168])   # 3 波各隔 48t
	# 每波 12 行、2 缺口×2 行 → 8 弹/波，共 24 弹；横向纯推进（滚筒）
	assert_int(cs.active_count()).is_equal(24)
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(6)
		assert_int(p.faction).is_equal(Projectile.Faction.ENEMY)
		assert_str(p.attack_name).is_equal("星河")
		assert_float(p.vel.y).is_equal_approx(0.0, 0.001)
		assert_float(absf(p.vel.x)).is_equal_approx(100.0, 0.01)
	# 逐波记录面：方向交替（+1/-1/+1），每波 8 行，缺口恰 2×2 连续行（安全通道）
	var waves: Array = (b._galaxy_waves as Array).duplicate()
	assert_int(waves.size()).is_equal(3)
	var dirs: Array = [1, -1, 1]
	for w in range(3):
		var wave: Dictionary = waves[w]
		assert_int(int(wave["dir"])).is_equal(dirs[w])
		var ys: Array = (wave["ys"] as Array).duplicate()
		ys.sort()
		assert_int(ys.size()).is_equal(8)
		# 期望 12 行网格（内域纵向居中，行距 GALAXY_ROW_GAP_PX）→ 缺失行 = 缺口
		var center_y: float = BOUNDS.get_center().y
		var expected: Array = []
		for r in range(StarfallProphet.GALAXY_ROWS):
			expected.append(center_y + (float(r) - 5.5) * StarfallProphet.GALAXY_ROW_GAP_PX)
		var missing: Array = []
		for e in expected:
			var found := false
			for y in ys:
				if absf(float(y) - float(e)) < 0.01:
					found = true
					break
			if not found:
				missing.append(expected.find(e))
		assert_int(missing.size()).is_equal(4)        # 2 缺口 × 2 行
		assert_int(missing[0] + 1).is_equal(missing[1])   # 连续成对
		assert_int(missing[2] + 1).is_equal(missing[3])
		assert_int(missing[0]).is_greater_equal(0)
		assert_int(missing[1]).is_less_equal(5)       # 第一缺口在前半区
		assert_int(missing[2]).is_greater_equal(6)    # 第二缺口在后半区
		assert_int(missing[3]).is_less_equal(StarfallProphet.GALAXY_ROWS - 1)
	# 期间召唤 2 星髓聚合体
	assert_array(spawned).is_equal(["starmarrow_blob", "starmarrow_blob"])
	for m in minions:
		if is_instance_valid(m):
			m.free()

# ---- 数据接线与死亡路径 ----

func test_prophet_gamedb_row_and_factory_wiring() -> void:
	var row := GameDB.get_enemy("starfall_prophet")
	assert_int(row.get("hp", 0)).is_equal(3200)       # 附录 E.6：HP 3200
	assert_str(String(row.get("name", ""))).is_equal("星陨先知")
	assert_array(row.get("phases", [])).is_equal([1, 0.6, 0.3])   # GameDB 深度整值还原（同 wave1 口径）
	assert_bool(row.has("boss_script")).is_true()
	assert_str(String(row.get("drops", ""))).contains("gems3")     # 死亡掉落 3 蓝晶
	assert_str(String(row.get("drops", ""))).contains("soul")      # + 头目魂（纯叙事贴花）
	assert_int(int(row.get("bullet_speed", 0))).is_less_equal(150) # 弹速契约
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	assert_object(e).is_not_null()
	assert_bool(e is StarfallProphet).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	e._take_hit_at(_ctx(1280), 9999)                  # 3200-1280=1920 → P2
	assert_int(e.phase()).is_equal(1)

func test_prophet_dies_via_standard_path() -> void:
	var b := _prophet()
	_engage_ready(b)
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(4000), FRAME)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["starfall_prophet"])
	EventBus.enemy_killed.disconnect(cb)


# ================================================================ 隐藏门（FloorScene 接线）

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SPAN_PX := 416.0

var _fs: FloorScene = null
var _saved_floor_idx := -1


func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


func _typed_chain(types: Array) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), Vector2i(i + 1, 0), nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 9999, "is_crit": false, "element": 0, "from": e.global_position})


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id:
			return e
	return null


func _await_until(check: Callable, max_frames: int = 120) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func before_test() -> void:
	_saved_floor_idx = RunState.floor_idx


func after_test() -> void:
	RunState.floor_idx = _saved_floor_idx
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
	_fs = null


## 携带判定 = 本层 resonance_triggered 计数（宽松口径）：EventBus 每发一次 +1。
func test_floor_counts_resonance_events_this_floor() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	var before: int = fs._floor_resonances
	EventBus.resonance_triggered.emit(Resonance.R.SHATTER, Vector2.ZERO, {})
	assert_int(fs._floor_resonances).is_equal(before + 1)
	EventBus.resonance_triggered.emit(Resonance.R.BLAZE, Vector2.ZERO, {})
	assert_int(fs._floor_resonances).is_equal(before + 2)

## A3 层（floor_idx ≥3）+ 本层有共鸣 → 击杀小 Boss 开星陨门：星陨先知入场（波次外，
## 不回锁已清房）+ StarfallGate 贴花 + starfall_gate_opened 信号。

func test_hidden_gate_opens_on_a3_miniboss_kill_with_resonance() -> void:
	RunState.floor_idx = 3
	var fs := _make_scene(_typed_chain(["miniboss"]))
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(fs.room_node(1), "zibao_wangchong") != null)
	# 携带任意共鸣（本层触发过共鸣）再击杀小 Boss
	EventBus.resonance_triggered.emit(Resonance.R.SUPERCONDUCT, Vector2.ZERO, {})
	var gates: Array = []
	fs.starfall_gate_opened.connect(func(rid: int) -> void: gates.append(rid))
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(fs.flow.cleared.has(1)).is_true()
	var prophet := _find_enemy(fs.room_node(1), "starfall_prophet")
	assert_object(prophet).is_not_null()              # 星陨先知自隐藏门入场
	assert_bool(prophet.counts_for_wave).is_false()   # 波次外：不消费波次/不回锁
	assert_object(fs.room_node(1).get_node_or_null("StarfallGate")).is_not_null()
	assert_array(gates).is_equal([1])
	# 击杀隐藏 Boss：死亡掉落 3 蓝晶 + 头目魂（波次外路径也发奖励）
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(fs.room_node(1), "starfall_prophet") == null)
	var gems_found := 0
	for child in fs.room_node(1).get_children():
		var pk := child as Pickup
		if pk != null and pk.kind == "gem":
			gems_found += 1
	assert_int(gems_found).is_equal(3)
	assert_object(fs.room_node(1).get_node_or_null("BossSoul")).is_not_null()

## 未携带共鸣（本层无 resonance_triggered）→ 击杀 A3 小 Boss 不开门。

func test_hidden_gate_stays_closed_without_resonance() -> void:
	RunState.floor_idx = 3
	var fs := _make_scene(_typed_chain(["miniboss"]))
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(fs.room_node(1), "zibao_wangchong") != null)
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_object(_find_enemy(fs.room_node(1), "starfall_prophet")).is_null()
	assert_object(fs.room_node(1).get_node_or_null("StarfallGate")).is_null()

## A3 以下（floor_idx <3）即使有共鸣也不开门。

func test_hidden_gate_stays_closed_below_a3() -> void:
	RunState.floor_idx = 2
	var fs := _make_scene(_typed_chain(["miniboss"]))
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(fs.room_node(1), "zibao_wangchong") != null)
	EventBus.resonance_triggered.emit(Resonance.R.SHATTER, Vector2.ZERO, {})
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_object(_find_enemy(fs.room_node(1), "starfall_prophet")).is_null()
	assert_object(fs.room_node(1).get_node_or_null("StarfallGate")).is_null()


# ================================================================ 掉落支持（蓝晶/头目魂）

## RunState.add_gems：局内蓝晶入账（同 add_coins 习语）。

func test_run_state_add_gems() -> void:
	var before: int = RunState.gems
	RunState.add_gems(3)
	assert_int(RunState.gems).is_equal(before + 3)

## Pickup "gem" 种类：接触结算走 on_collect（同 coin 路由）——蓝晶 +1 由接线方落账。

func test_gem_pickup_collects_via_on_collect() -> void:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	auto_free(player)
	var gem: Pickup = auto_free(Pickup.new())
	gem.kind = "gem"
	var collected: Array = []
	gem.on_collect = func() -> void: collected.append(1)
	add_child(gem)
	gem._on_body_entered(player)
	assert_array(collected).is_equal([1])
	assert_bool(gem.is_queued_for_deletion()).is_true()   # 拾取即回收（同 coin）


# ================================================================ helpers

func _live_stars(cs: CombatSystem) -> Array:
	var out: Array = []
	for p in cs.pool.active:
		if p.faction == Projectile.Faction.ENEMY and p.attack_name == "星陨":
			out.append(p)
	return out


func _run_collect(b: EnemyBase, start: int, ticks: int) -> Array:
	var seq: Array = []
	for i in range(ticks):
		b.brain_tick(start + i)
		if b.get("_move") != "" and b.get("_move_start") == start + i:
			seq.append(b.get("_move"))
	return seq
