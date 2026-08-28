class_name TestVineColossus
extends GdUnitTestSuite

## 藤蔓巨像（A1 Boss，附录 E.1）脑层注入帧测试（沿用 test_boss_base 手法）。
## 三阶段招式集门控 / 拍击扇形 / 弹环 12+12 计数 / 横扫条带 / 毒雨安全圈 / 召唤上限。

const ROW := {
	"id": "vine_colossus", "name": "藤蔓巨像", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/vine_colossus.gd",
	"hp": 800, "contact_dmg": 5, "speed": 30, "walk_speed": 30,
	"radius": 16.0, "bullet_dmg": 3, "bullet_speed": 110,
	"phases": [1.0, 0.6, 0.3],
}
const FRAME := 20000   # 注入帧基准（远离 0，同 test_boss_base）

class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)

func _boss() -> VineColossus:
	var b: VineColossus = auto_free(VineColossus.new())
	b._test_init(ROW.duplicate(true))
	return b

func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}

## ALERT 24t 后进 ENGAGE；返回首个 _engage 拍（首招起始拍）。
func _engage_ready(b: VineColossus) -> int:
	b.on_player_seen(FRAME)
	for f in range(FRAME + 1, FRAME + 25):
		b.brain_tick(f)
	return FRAME + 25

## 一次大伤落进目标阶段血线（amount 由调用方按当前 hp 预算：321→479/P1；再 239→240/P2）。
func _take_to_phase(b: VineColossus, amount: int, frame: int) -> void:
	b._take_hit_at(_ctx(amount), frame)

## 驱动 ticks 拍并收集「新招起始拍」的招式名序列。
func _run_collect(b: VineColossus, start: int, ticks: int) -> Array:
	var seq: Array = []
	for i in range(ticks):
		b.brain_tick(start + i)
		if b._move != "" and b._move_start == start + i:
			seq.append(b._move)
	return seq

## 找到下一个 sweep 招并跑完整个前摇+行进（42+36 拍），返回结束帧。
func _drive_sweep(b: VineColossus, f: int) -> int:
	for _i in range(600):
		if b._move == "sweep":
			break
		b.brain_tick(f)
		f += 1
	assert_str(b._move).is_equal("sweep")
	for i in range(79):
		b.brain_tick(f + i)
	return f + 79

# ---- 前摇下限（GDD §15：所有招式前摇 ≥0.4s = 24t）----

func test_every_windup_at_least_24t() -> void:
	assert_int(VineColossus.SLAP_WINDUP_TICKS).is_greater_equal(24)
	assert_int(VineColossus.RING_WINDUP_TICKS).is_greater_equal(24)
	assert_int(VineColossus.SWEEP_WINDUP_TICKS).is_greater_equal(24)
	assert_int(VineColossus.SUMMON_WINDUP_TICKS).is_greater_equal(24)
	assert_int(VineColossus.RAIN_WINDUP_TICKS).is_greater_equal(24)

# ---- 阶段门控：P0 拍击/弹环交替；P1 +横扫；P2 +毒雨 ----

func test_p0_alternates_slap_and_ring_only() -> void:
	var b := _boss()
	var f := _engage_ready(b)
	var seq := _run_collect(b, f, 600)
	assert_int(seq.size()).is_greater_equal(6)
	assert_str(seq[0]).is_equal("slap")
	for m in seq:
		assert_bool(m == "slap" or m == "ring").is_true()
	for i in range(1, seq.size()):
		assert_bool(seq[i] != seq[i - 1]).is_true()   # 严格交替

func test_move_sets_expand_by_phase_p0_p1_p2() -> void:
	var b := _boss()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 400):                     # P0：仅拍击/弹环
		assert_bool(m == "slap" or m == "ring").is_true()
	_take_to_phase(b, 321, f + 400)
	var seq1 := _run_collect(b, f + 400, 800)             # P1：+横扫，无毒雨
	assert_bool(seq1.has("sweep")).is_true()
	assert_bool(seq1.has("rain")).is_false()
	for m in seq1:
		assert_bool(m == "slap" or m == "ring" or m == "sweep").is_true()
	_take_to_phase(b, 239, f + 1200)   # 479-239=240 ≤ 240 → P2（不死）
	var seq2 := _run_collect(b, f + 1200, 1100)           # P2：+毒雨
	assert_bool(seq2.has("sweep")).is_true()
	assert_bool(seq2.has("rain")).is_true()
	for m in seq2:
		assert_bool(m == "slap" or m == "ring" or m == "sweep" or m == "rain").is_true()

# ---- 巨掌拍击：90° 扇形 / 70px 射程 / 伤 5 / 击退 8px ----

func test_slap_hits_player_in_arc_for5_knockback8() -> void:
	var b := _boss()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)                        # 60px ≤70，扇形内
	b.set("player_ref", spy)
	var f := _engage_ready(b)
	for i in range(31):                                   # 前摇 30t，末拍结算
		b.brain_tick(f + i)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(5)
	assert_float(float(spy.hits[0]["knockback"])).is_equal_approx(8.0, 0.001)
	assert_float(spy.brain_pos.x).is_equal_approx(68.0, 0.01)   # 击退 8px 远离 Boss
	assert_float(spy.brain_pos.y).is_equal_approx(0.0, 0.01)

func test_slap_ignores_out_of_range_and_out_of_arc() -> void:
	var b := _boss()                                      # 90px > 70px 射程
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(90, 0)
	b.set("player_ref", spy)
	var f := _engage_ready(b)
	for i in range(31):
		b.brain_tick(f + i)
	assert_int(spy.hits.size()).is_equal(0)
	var b2 := _boss()                                     # 前摇中锁定朝向后闪出扇形：
	var spy2: SpyPlayer = auto_free(SpyPlayer.new())
	spy2.brain_pos = Vector2(60, 0)
	b2.set("player_ref", spy2)
	var f2 := _engage_ready(b2)
	for i in range(5):
		b2.brain_tick(f2 + i)                             # 朝向锁定指向 (60,0)
	spy2.brain_pos = Vector2(40, 45)                      # 距 60px 在射程内，但偏角 48.4° > 45°
	for i in range(26):
		b2.brain_tick(f2 + 5 + i)                         # 前摇余 25t 至结算拍
	assert_int(spy2.hits.size()).is_equal(0)

# ---- 种子弹环：前摇 36t，附录 E.1「12 发×2 轮」= 12+12 两波（24t 间隔）全环 24 发，速 110 伤 3 ----

func test_seed_ring_24_projectiles_in_two_waves() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	root.add_child(cs)
	var b := _boss()
	b.combat = cs
	var f := _engage_ready(b)                             # 首招 slap 先打完
	for i in range(31):
		b.brain_tick(f + i)
	var fr := f + 31                                      # 弹环起始拍
	var fired_frames: Array = []
	for i in range(37):
		b.brain_tick(fr + i)
		if b.fired_this_tick:
			fired_frames.append(fr + i)
	assert_array(fired_frames).is_equal([fr + 36])        # 第 1 波（12 发）：前摇 36t 后
	assert_int(cs.active_count()).is_equal(12)
	for i in range(24):
		b.brain_tick(fr + 37 + i)
		if b.fired_this_tick:
			fired_frames.append(fr + 37 + i)
	assert_array(fired_frames).is_equal([fr + 36, fr + 60])   # 第 2 波：恰 24t 后
	assert_int(cs.active_count()).is_equal(24)            # 12+12 = 全环 24 发
	var angles := {}
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(3)
		assert_float(p.vel.length()).is_equal_approx(110.0, 0.01)
		angles[int(round(rad_to_deg(p.vel.angle())))] = true
	assert_int(angles.size()).is_equal(24)                # 24 个均布方向（两轮各 30° 步进错 15°）

# ---- 藤蔓横扫：前摇 42t，条带 36t 横穿，伤 5，恰一跳，左右交替 ----

func test_sweep_strip_hits_once_for5_then_alternates() -> void:
	var b := _boss()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(30, -100)                     # 纵程内（|y| ≤ 119）
	b.set("player_ref", spy)
	_take_to_phase(b, 321, FRAME - 100)
	var f := _engage_ready(b)
	_drive_sweep(b, f)
	assert_int(spy.hits.size()).is_equal(1)               # 条带经过恰好一跳
	assert_int(spy.hits[0]["amount"]).is_equal(5)
	assert_int(b._sweep_dir).is_equal(-1)                 # 下次右→左（交替）

func test_sweep_ignores_player_outside_strip_span() -> void:
	var b := _boss()                                      # x=400 在行进带（±228）外
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(400, 0)
	b.set("player_ref", spy)
	_take_to_phase(b, 321, FRAME - 100)
	_drive_sweep(b, _engage_ready(b))
	assert_int(spy.hits.size()).is_equal(0)
	var b2 := _boss()                                     # y=200 在纵程（±119）外
	var spy2: SpyPlayer = auto_free(SpyPlayer.new())
	spy2.brain_pos = Vector2(0, 200)
	b2.set("player_ref", spy2)
	_take_to_phase(b2, 321, FRAME - 100)
	_drive_sweep(b2, _engage_ready(b2))
	assert_int(spy2.hits.size()).is_equal(0)

# ---- 毒雨：前摇 60t，360t 内每 30t 1 伤，3 个 r48 安全区（锚 ± 固定偏移）----

func _rain_activate(b: VineColossus) -> int:
	var f := _engage_ready(b)
	for _i in range(600):
		if b._move == "rain":
			break
		b.brain_tick(f)
		f += 1
	assert_str(b._move).is_equal("rain")
	var ms := b._move_start                              # 招式实际起始拍（= f-1）
	var act := -1
	for fr in range(ms, ms + 61):                        # 前摇 60t 后激活（已处理拍跳过）
		if fr >= f:
			b.brain_tick(fr)
		if act < 0 and b._rain_until > 0:
			act = fr
	assert_int(act).is_equal(ms + 60)
	return act

func test_poison_rain_circles_are_room_anchored_offsets() -> void:
	var b := _boss()
	_take_to_phase(b, 561, FRAME - 100)   # 800-561=239 ≤ 240 → P2
	var act := _rain_activate(b)
	assert_int(act).is_greater(0)
	assert_int(b._rain_circles.size()).is_equal(3)
	for c in b._rain_circles:
		assert_bool(c == Vector2(-160, 0) or c == Vector2.ZERO or c == Vector2(160, 0)).is_true()

func test_poison_rain_ticks_1dmg_every_30t_outside_safety() -> void:
	var b := _boss()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 300)                       # 距最近圈心 300 > 48；y 免横扫
	b.set("player_ref", spy)
	_take_to_phase(b, 561, FRAME - 100)   # 800-561=239 ≤ 240 → P2
	var act := _rain_activate(b)
	var hit_frames: Array = []
	for i in range(361):                                  # 激活后 360t（含末拍界）
		var fr := act + 1 + i
		b.brain_tick(fr)
		if spy.hits.size() > hit_frames.size():
			hit_frames.append(fr)
	assert_int(hit_frames.size()).is_equal(12)            # 30..360 每 30t 一跳 ×12
	for i in range(12):
		assert_int(spy.hits[i]["amount"]).is_equal(1)
		assert_int(hit_frames[i]).is_equal(act + 30 * (i + 1))

func test_poison_rain_no_damage_inside_safety_circle() -> void:
	# 圈内免的是「毒雨」结算（POISON 签名）；横扫/拍击为独立招式不豁免——
	# 圈心 y=0 必在横扫纵程内，故按毒雨元素命中数断言（横扫伤 5/元素 NONE 不计入）。
	var poison_hits := func(spy: SpyPlayer) -> int:
		var n := 0
		for h in spy.hits:
			if int(h["element"]) == Elements.Id.POISON:
				n += 1
		return n
	var b := _boss()                                      # 圈心（160,0）
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(160, 0)
	b.set("player_ref", spy)
	_take_to_phase(b, 561, FRAME - 100)   # 800-561=239 ≤ 240 → P2
	var act := _rain_activate(b)
	for i in range(361):
		b.brain_tick(act + 1 + i)
	assert_int(poison_hits.call(spy)).is_equal(0)
	assert_int(spy.hits.size()).is_greater_equal(1)       # 横扫照常可命中（分层不受安全区豁免）
	var b2 := _boss()                                     # 恰在圈界（dist=48 ≤ r48，圈内）
	var spy2: SpyPlayer = auto_free(SpyPlayer.new())
	spy2.brain_pos = Vector2(112, 0)
	b2.set("player_ref", spy2)
	_take_to_phase(b2, 561, FRAME - 100)
	var act2 := _rain_activate(b2)
	for i in range(361):
		b2.brain_tick(act2 + 1 + i)
	assert_int(poison_hits.call(spy2)).is_equal(0)
	var b3 := _boss()                                     # 圈外 1px（dist=49）必吃毒雨
	var spy3: SpyPlayer = auto_free(SpyPlayer.new())
	spy3.brain_pos = Vector2(111, 0)
	b3.set("player_ref", spy3)
	_take_to_phase(b3, 561, FRAME - 100)
	var act3 := _rain_activate(b3)
	for i in range(361):
		b3.brain_tick(act3 + 1 + i)
	assert_int(poison_hits.call(spy3)).is_greater_equal(1)

# ---- 召唤蘑菇（shooter 替身）：上限 2，周期补 ----

func test_summon_shooter_stand_in_cap_two_replenish() -> void:
	var b := _boss()
	var spawned: Array = []
	var pos_log: Array = []
	var minions: Array = []
	b.spawn_callback = func(arch: String, pos: Vector2) -> Variant:
		spawned.append(arch)
		pos_log.append(pos)
		var m := Node.new()
		minions.append(m)
		return m
	_take_to_phase(b, 321, FRAME - 100)
	var f := _engage_ready(b)
	for i in range(800):                                  # ≥2 个 240t 周期
		b.brain_tick(f + i)
	assert_array(spawned).is_equal(["shooter", "shooter"])   # 一轮补满至上限 2
	assert_array(pos_log).is_equal([Vector2(48, 0), Vector2(-48, 0)])   # 左右交替落点
	assert_int(b._minions.size()).is_equal(2)
	minions[0].free()                                     # 一只死亡 → 下周期补 1
	for i in range(400):
		b.brain_tick(f + 800 + i)
	assert_int(spawned.size()).is_equal(3)
	for m in minions:                                     # 清理替身活体（防 gdUnit orphan 计数）
		if is_instance_valid(m):
			m.free()

func test_summon_without_callback_never_starts() -> void:
	# 未接线（spawn_callback 空调用）→ 召唤招不入序列（生产接线归房间层，披露）
	var b := _boss()
	_take_to_phase(b, 561, FRAME - 100)   # 800-561=239 ≤ 240 → P2
	for m in _run_collect(b, _engage_ready(b), 800):
		assert_bool(m != "summon").is_true()

# ---- 数据接线与死亡路径 ----

func test_gamedb_row_wires_boss_script_and_phases() -> void:
	var row := GameDB.get_enemy("vine_colossus")
	assert_int(row.get("hp", 0)).is_equal(800)
	assert_bool(row.has("phases")).is_true()
	assert_bool(row.has("boss_script")).is_true()
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init(row)                                     # 生产同路径：_test_init 内 boss_script 换装
	assert_bool(e is VineColossus).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)                                   # 首拍 _engage 自愈补析血线（换装丢成员修复）
	e._take_hit_at(_ctx(321), 9999)                       # 800-321=479 ≤ 480 → P1
	assert_int(e.hp).is_equal(479)
	assert_int(e.phase()).is_equal(1)

func test_boss_dies_via_die_path_without_aoe() -> void:
	var b := _boss()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO                          # 贴身：行无 aoe 键 → 不应被炸
	b.set("player_ref", spy)
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(1000), FRAME)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["vine_colossus"])
	assert_int(spy.hits.size()).is_equal(0)               # M0 die() 爆炸路径语义不变
	EventBus.enemy_killed.disconnect(cb)
