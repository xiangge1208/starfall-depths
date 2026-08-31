class_name TestBossM2Wave3
extends GdUnitTestSuite

## M2-T19 D-4 熔核暴君脑层注入帧测试（沿用 test_boss_m2_wave1 手法）：
## 附录 E.5（HP 3200）——阶段招式门控 / 岩浆喷发（4 块岩浆区各 5s，复用 T10 HazardMagma
## 区数据 + DOT 脉冲语义；喷发拍爆发 7）/ 火拳（windup 30t 近身扇形 90° 伤 7）/
## 火雨（windup 48t，12 红圈落点分 3 波伤 7，复用 HazardMagma.FireRain 驱动契约）/
## 地裂火浪（windup 42t，环形火浪 Boss 扩散全房伤 8，掩体遮挡判定）/
## 怒气常驻（HP<60% 起：弹幕密度 ×1.5、移速 +20%）。
## 招式拍序约定（同 vine/queen）：招式起始拍 ms，前摇 N 在 tick ms+N 结算。

const TYRANT_ROW := {
	"id": "magma_tyrant", "name": "熔核暴君", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/magma_tyrant.gd",
	"hp": 3200, "contact_dmg": 7, "speed": 24, "walk_speed": 24,
	"radius": 18.0,
	"phases": [1.0, 0.6, 0.3],
}
const FRAME := 30000   # 注入帧基准（远离 0，同 test_boss_m2_wave1）
const BOUNDS := Rect2(Vector2(-228, -119), Vector2(456, 238))   # M0 战斗房内域

# 阶段血线（floor(3200×0.6)=1920 / floor(3200×0.3)=960）
const DMG_TO_P1 := 1280
const DMG_P1_TO_P2 := 960


class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}


## still=true 时行内速度置 0（隔离追走位移，专测招式几何）。
func _tyrant(still := false) -> MagmaTyrant:
	var r := TYRANT_ROW.duplicate(true)
	if still:
		r["speed"] = 0
		r["walk_speed"] = 0
	var b: MagmaTyrant = auto_free(MagmaTyrant.new())
	b._test_init(r)
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
## after_start > -1 时要求新批次（_move_start 更大）——用于同名招式的第二次施放。
func _drive_to_move(b: EnemyBase, move: String, f: int, limit := 6000, after_start := -1) -> int:
	for _i in range(limit):
		if b.get("_move") == move and int(b.get("_move_start")) > after_start:
			return b.get("_move_start")
		b.brain_tick(f)
		f += 1
	assert_str(String(b.get("_move"))).is_equal(move)
	return -1


# ================================================================ 前摇与数值常量

# ---- 前摇下限（GDD §15 ≥24t；数值逐字附录 E.5）----

func test_tyrant_every_windup_at_least_24t() -> void:
	assert_int(MagmaTyrant.MIN_WINDUP_TICKS).is_equal(24)
	assert_int(MagmaTyrant.ERUPT_WINDUP_TICKS).is_equal(36)   # 附录 E.5：0.6s
	assert_int(MagmaTyrant.FIST_WINDUP_TICKS).is_equal(30)    # 0.5s
	assert_int(MagmaTyrant.RAIN_WINDUP_TICKS).is_equal(48)    # 0.8s（=FireRain.WARN_TICKS）
	assert_int(MagmaTyrant.WAVE_WINDUP_TICKS).is_equal(42)    # 0.7s
	for w in [MagmaTyrant.ERUPT_WINDUP_TICKS, MagmaTyrant.FIST_WINDUP_TICKS,
			MagmaTyrant.RAIN_WINDUP_TICKS, MagmaTyrant.WAVE_WINDUP_TICKS]:
		assert_int(w).is_greater_equal(MagmaTyrant.MIN_WINDUP_TICKS)

func test_tyrant_rage_and_attack_constants() -> void:
	assert_float(MagmaTyrant.RAGE_DENSITY_MULT).is_equal_approx(1.5, 0.001)   # 弹幕密度 ×1.5
	assert_float(MagmaTyrant.RAGE_SPEED_MULT).is_equal_approx(1.2, 0.001)     # 移速 +20%
	assert_int(MagmaTyrant.FIST_DMG).is_equal(7)               # 火拳伤 7（任务逐参数）
	assert_int(MagmaTyrant.FIST_ARC_DEG).is_equal(90)          # 近身扇形 90°
	assert_int(MagmaTyrant.ERUPT_BURST_DMG).is_equal(7)        # 岩浆喷发爆发 7（E.5「7/跳」）
	assert_int(MagmaTyrant.WAVE_DMG).is_equal(8)               # 地裂火浪 8
	assert_int(MagmaTyrant.ERUPT_BASE_COUNT).is_equal(4)       # 4 块岩浆区
	assert_int(MagmaTyrant.ERUPT_DURATION_TICKS).is_equal(300) # 各持续 5s
	assert_float(MagmaTyrant.ERUPT_ZONE_RADIUS_PX).is_equal_approx(24.0, 0.01)   # T10 岩浆池半径
	assert_int(MagmaTyrant.RAIN_WAVES).is_equal(3)             # 12 红圈分 3 波
	assert_int(MagmaTyrant.RAIN_BASE_PER_WAVE).is_equal(4)
	assert_int(MagmaTyrant.RAIN_WAVE_GAP_TICKS).is_equal(24)


# ================================================================ 阶段门控

# ---- P0 岩浆喷发/火拳；P1(60%) +火雨+怒气；P2(30%) +地裂火浪 ----

func test_tyrant_move_sets_expand_by_phase() -> void:
	var b := _tyrant(true)
	var f := _engage_ready(b)
	var seq0 := _run_collect(b, f, 500)
	assert_bool(seq0.size() >= 6).is_true()
	for m in seq0:
		assert_bool(m == "erupt" or m == "fist").is_true()
	b._take_hit_at(_ctx(DMG_TO_P1), f + 500)          # 3200-1280=1920 → P1（怒气起）
	var seq1 := _run_collect(b, f + 500, 1600)
	assert_bool(seq1.has("rain")).is_true()
	assert_bool(seq1.has("wave")).is_false()
	for m in seq1:
		assert_bool(m == "erupt" or m == "fist" or m == "rain").is_true()
	b._take_hit_at(_ctx(DMG_P1_TO_P2), f + 2100)      # 1920-960=960 → P2
	var seq2 := _run_collect(b, f + 2100, 3200)
	assert_bool(seq2.has("wave")).is_true()
	for m in seq2:
		assert_bool(m == "erupt" or m == "fist" or m == "rain" or m == "wave").is_true()


# ================================================================ 岩浆喷发

# ---- 前摇 36t 锁 4 块岩浆区（玩家为心 72px 环，T10 外接方 48×48），喷发拍爆发 7，
#      区存续 5s：站区内每 60t 一跳 T10 岩浆 DOT（2 伤，抗火减半），过期自清 ----

func test_tyrant_erupt_four_zones_burst7_then_t10_dot_for_5s() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)                     # 环 ±72px 全落内域（含 24px 夹边）
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "erupt", f)
	var centers: Array = b._erupt_centers             # 前摇起始拍锁定（预警位即落点）
	assert_int(centers.size()).is_equal(4)
	assert_int(b._fx.size()).is_equal(4)              # 4 块红纹预警
	for i in range(centers.size()):
		assert_vector(centers[i]).is_equal_approx(
			Vector2.from_angle(TAU * float(i) / 4.0) * 72.0, Vector2(0.01, 0.01))
	# 前摇中岩浆区未激活：站在未来落点不受伤
	spy.brain_pos = centers[0]
	for i in range(MagmaTyrant.ERUPT_WINDUP_TICKS - 1):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(0)
	b.brain_tick(ms + MagmaTyrant.ERUPT_WINDUP_TICKS)   # 喷发拍：爆发 7
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(7)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("岩浆喷发")
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.FIRE)
	# 复用 T10：区数据落在 HazardMagma（外接方 48×48，含心判真、区外判假）
	assert_int(b._magma.zones.size()).is_equal(4)
	for z in b._magma.zones:
		assert_vector(z.size).is_equal_approx(Vector2(48, 48), Vector2(0.01, 0.01))
	assert_bool(b._magma.in_magma(centers[0])).is_true()
	assert_bool(b._magma.in_magma(centers[0] + Vector2(48, 0))).is_false()
	# DOT：站区内每 60t 一跳 2 伤（T10 pulse_damage），5s 共 5 跳，过期即停
	var dot_frames: Array = []
	var resolve := ms + MagmaTyrant.ERUPT_WINDUP_TICKS
	var hits_before := spy.hits.size()               # 基线：喷发拍爆发命中不计入（同 wave1 手法）
	for i in range(420):
		b.brain_tick(resolve + 1 + i)
		if spy.hits.size() > hits_before + dot_frames.size():
			dot_frames.append(resolve + 1 + i)
	assert_array(dot_frames).is_equal([resolve + 60, resolve + 120, resolve + 180,
		resolve + 240, resolve + 300])
	for i in range(1, spy.hits.size()):
		assert_int(spy.hits[i]["amount"]).is_equal(HazardMagma.pulse_damage(false))
		assert_str(String(spy.hits[i]["attack_name"])).is_equal("岩浆区")
	assert_int(HazardMagma.pulse_damage(false)).is_equal(2)

# ---- 怒气密度：P0 喷发 4 块 → P1 起 6 块（ceili(4×1.5)），环距 60° 步进 ----

func test_tyrant_rage_densifies_erupt_zones_four_to_six() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "erupt", f)
	assert_int(b._erupt_centers.size()).is_equal(4)
	b._take_hit_at(_ctx(DMG_TO_P1), ms)               # → P1（怒气常驻）
	assert_bool(b.rage_active()).is_true()
	_drive_to_move(b, "erupt", ms + 1, 6000, ms)      # 下一批 erupt（非仍在施放的首批）
	var centers: Array = b._erupt_centers
	assert_int(centers.size()).is_equal(6)            # ceili(4×1.5)
	assert_int(b._density_count(MagmaTyrant.ERUPT_BASE_COUNT)).is_equal(6)
	for i in range(centers.size()):
		assert_vector(centers[i] - spy.brain_pos).is_equal_approx(
			Vector2.from_angle(TAU * float(i) / 6.0) * 72.0, Vector2(0.01, 0.01))
		assert_bool(BOUNDS.grow(-24.0).has_point(centers[i])).is_true()


# ================================================================ 火拳

# ---- 前摇 30t，近身扇形 90° 伤 7：朝向前摇起始拍锁定，出弧/出程即落空 ----

func test_tyrant_fist_arc90_hits_for7_once() -> void:
	var b := _tyrant(true)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(50, 0)                    # 50px ≤ 70，弧心正对
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "fist", f)
	assert_int(b._fx.size()).is_equal(1)              # 扇形红纹预警
	assert_float(b._fist_facing).is_equal_approx(0.0, 0.001)   # 朝向 = 起始拍瞄准角
	var hit_frame := -1
	for i in range(1, 32):
		b.brain_tick(ms + i)
		if spy.hits.size() == 1 and hit_frame < 0:    # 只记首跳拍（后续拍不再重复断言）
			hit_frame = ms + i
	assert_int(hit_frame).is_equal(ms + MagmaTyrant.FIST_WINDUP_TICKS)   # 前摇 30t 恰一跳
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(7)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("火拳")

func test_tyrant_fist_dodgeable_windup_locks_facing() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 50)                    # 正上 50px → 锁定朝向 +90°
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "fist", f)
	for i in range(15):
		b.brain_tick(ms + 1 + i)                      # 前摇 30t 内第 15 拍侧移
	spy.brain_pos = Vector2(50, 0)                    # 距 50px ≤70，但偏离锁定弧心 90°
	for i in range(20):
		b.brain_tick(ms + 16 + i)
	assert_int(spy.hits.size()).is_equal(0)           # 出弧落空（侧移可躲）


# ================================================================ 火雨

# ---- 前摇 48t：12 红圈分 3 波（4/波，24t 波距），红圈预警随排程出现，
#      复用 HazardMagma.FireRain（预警 48t 倒计时、恰 boom 拍结算 7、下一拍自除）----

func test_tyrant_rain_twelve_circles_three_waves_fire_rain_contract() -> void:
	const SEED := 20260830
	RngSvc.setup_run(SEED)
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 50)
	b.player_ref = spy
	b._take_hit_at(_ctx(DMG_TO_P1), FRAME - 100)      # → P1
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "rain", f)
	assert_int(b._rain_targets.size()).is_equal(4)    # 第 1 波随起始拍排程
	assert_int(b._fire_rain.strike_count()).is_equal(4)
	assert_int(b._rain_fx.size()).is_equal(4)         # 红圈预警
	spy.brain_pos = b._rain_targets[0]                # 站第 1 波落点
	var hit_frames: Array = []
	for i in range(1, 110):                           # 逐拍推进（FireRain 倒计时语义）
		b.brain_tick(ms + i)
		if i == 24:
			assert_int(b._rain_targets.size()).is_equal(8)     # 第 2 波（+24t）
		if i == 48:
			assert_int(b._rain_targets.size()).is_equal(12)    # 第 3 波：共 12 红圈
			assert_str(String(b.get("_move"))).is_equal("")    # 末波排程后释放招式位（背景结算）
		if spy.hits.size() > hit_frames.size():
			hit_frames.append(ms + i)
	assert_array(hit_frames.slice(0, 1)).is_equal([ms + MagmaTyrant.RAIN_WINDUP_TICKS])
	assert_int(spy.hits[0]["amount"]).is_equal(7)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("火雨")
	for t in b._rain_targets:
		assert_bool(BOUNDS.grow(-8.0).has_point(t)).is_true()
	assert_int(b._fire_rain.strike_count()).is_equal(0)        # 末波 ms+96 落、ms+97 自除
	assert_int(b._rain_fx.size()).is_equal(0)                  # 红圈随落点自除


# ================================================================ 地裂火浪

# ---- 前摇 42t，环形火浪从 Boss 扩散至全房（2px/拍 至 300px ≥ 战斗房半对角），
#      火浪前沿越过玩家拍结算 8；掩体（注入世界坐标）挡线即遮挡 ----

func test_tyrant_wave_ring_expands_and_hits_for8() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(DMG_TO_P1 + DMG_P1_TO_P2), FRAME - 100)   # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "wave", f)
	assert_int(b._fx.size()).is_equal(1)              # 扩散红环预警
	assert_vector(b._wave_anchor).is_equal_approx(Vector2.ZERO, Vector2(0.01, 0.01))   # Boss 位锚定
	for i in range(MagmaTyrant.WAVE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_float(b._wave_front).is_equal_approx(0.0, 0.01)   # 前摇中不扩散
	var hit_frame := -1
	for i in range(150):                              # 窗口止于收招拍（ms+192），不引入后继招式干扰
		b.brain_tick(ms + MagmaTyrant.WAVE_WINDUP_TICKS + 1 + i)
		if spy.hits.size() > 0 and hit_frame < 0:
			hit_frame = ms + MagmaTyrant.WAVE_WINDUP_TICKS + 1 + i
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(hit_frame).is_equal(ms + MagmaTyrant.WAVE_WINDUP_TICKS + 100)   # 2px/拍 → 200px
	assert_int(spy.hits[0]["amount"]).is_equal(8)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("地裂火浪")
	assert_float(b._wave_front).is_equal_approx(300.0, 0.01)   # 扩散至全房
	assert_str(String(b.get("_move"))).is_equal("")   # 全房覆盖后收招

func test_tyrant_wave_blocked_by_cover_on_line() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	b.player_ref = spy
	b.cover_points = [Vector2(100, 0)]                # 掩体正挡 Boss→玩家连线
	b._take_hit_at(_ctx(DMG_TO_P1 + DMG_P1_TO_P2), FRAME - 100)
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "wave", f)
	for i in range(150):                              # 窗口止于收招拍，避免后继招式落点干扰
		b.brain_tick(ms + MagmaTyrant.WAVE_WINDUP_TICKS + 1 + i)
	assert_int(spy.hits.size()).is_equal(0)           # 掩体遮挡判定：火浪被挡

func test_tyrant_wave_not_blocked_by_cover_off_line() -> void:
	var b := _tyrant(true)
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	b.player_ref = spy
	b.cover_points = [Vector2(100, 80)]               # 掩体偏离连线 80px：不构成遮挡
	b._take_hit_at(_ctx(DMG_TO_P1 + DMG_P1_TO_P2), FRAME - 100)
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "wave", f)
	for i in range(150):                              # 窗口止于收招拍，避免后继招式落点干扰
		b.brain_tick(ms + MagmaTyrant.WAVE_WINDUP_TICKS + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)


# ================================================================ 怒气移速

# ---- HP<60% 起常驻：追走移速 +20%（行 speed 24px/s → 28.8px/s）----

func test_tyrant_rage_move_speed_plus_20_percent() -> void:
	var b := _tyrant()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(300, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	for i in range(60):
		b.brain_tick(f + i)
	assert_float(b.brain_pos.x).is_equal_approx(24.0, 0.01)   # 24px/s × 1s
	b._take_hit_at(_ctx(DMG_TO_P1), f + 60)           # → P1：怒气常驻
	var x1: float = b.brain_pos.x
	for i in range(60):
		b.brain_tick(f + 61 + i)
	assert_float(b.brain_pos.x - x1).is_equal_approx(28.8, 0.01)   # ×1.2
	assert_bool(b.rage_active()).is_true()


# ================================================================ 数据接线与死亡路径

func test_tyrant_gamedb_row_and_factory_wiring() -> void:
	var row := GameDB.get_enemy("magma_tyrant")
	assert_int(row.get("hp", 0)).is_equal(3200)       # 附录 E.5：HP 3200
	assert_str(String(row.get("name", ""))).is_equal("熔核暴君")
	assert_int(int(row.get("contact_dmg", 0))).is_equal(7)
	assert_float(float(row.get("radius", 0))).is_equal_approx(18.0, 0.01)
	assert_array(row.get("phases", [])).is_equal([1, 0.6, 0.3])   # GameDB 深度整值还原（vine 同口径）
	assert_bool(row.has("boss_script")).is_true()
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	assert_object(e).is_not_null()
	assert_bool(e is MagmaTyrant).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	e._take_hit_at(_ctx(DMG_TO_P1), 9999)             # 3200-1280=1920 → P1
	assert_int(e.phase()).is_equal(1)

func test_tyrant_dies_and_clears_fire_fields() -> void:
	var b := _tyrant(true)
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "erupt", f)
	for i in range(MagmaTyrant.ERUPT_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_bool(b._magma.zones.size() > 0).is_true()
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(4000), ms + 100)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["magma_tyrant"])
	assert_int(b._magma.zones.size()).is_equal(0)     # 岩浆区随 Boss 退场清空
	EventBus.enemy_killed.disconnect(cb)

# ---- Boss 免疫冻结语义（T11 已立，回归钉死）----

func test_tyrant_immune_to_freeze() -> void:
	var b := _tyrant()
	assert_bool(b.status.is_boss).is_true()
	b.status.apply_freeze(120, FRAME)
	assert_bool(b.status.is_frozen(FRAME + 1)).is_false()
