class_name TestBossM2Wave1
extends GdUnitTestSuite

## M2-T14 D-1 双 Boss 脑层注入帧测试（沿用 test_vine_colossus 手法）：
## 宝石蜂后（附录 E.2，HP 800）——阶段招式门控 / 蜂群扇弹 8×3 / 俯冲 /
##   蜂巢柱（可破坏掩体 + 挡弹）/ 环形爆蜂 16 发 90° 缺口 / 狂暴三连冲末段自晕 72t。
## 晶棱魔像（附录 E.3，HP 1800）——棱镜射线（EnemyLaser 命中晶柱 45° 折射，复用 T7）/
##   碎晶抛射（5 落点 + 3s 晶刺区）/ 三向扫描（3 束 60°/s 旋转）/ 晶柱再生 /
##   瞬移弹幕（20 环×3，间隔 72t，RunState 分盐流确定性）。
## 招式拍序约定（同 vine）：招式起始拍 ms，前摇 N 在 tick ms+N 结算。

const QUEEN_ROW := {
	"id": "gem_queen", "name": "宝石蜂后", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/gem_queen.gd",
	"hp": 800, "contact_dmg": 4, "speed": 40, "walk_speed": 40,
	"radius": 14.0, "bullet_dmg": 3, "bullet_speed": 110,
	"bullet_life_seconds": 2.5, "bullet_radius": 3.0,
	"phases": [1.0, 0.6, 0.3],
}
const GOLEM_ROW := {
	"id": "prism_golem", "name": "晶棱魔像", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/prism_golem.gd",
	"hp": 1800, "contact_dmg": 6, "speed": 20, "walk_speed": 20,
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

func _queen() -> GemQueen:
	var b: GemQueen = auto_free(GemQueen.new())
	b._test_init(QUEEN_ROW.duplicate(true))
	return b

func _golem() -> PrismGolem:
	var b: PrismGolem = auto_free(PrismGolem.new())
	b._test_init(GOLEM_ROW.duplicate(true))
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


# ================================================================ 宝石蜂后

# ---- 前摇下限（附录 E 预警规范：所有招式前摇 ≥0.4s = 24t）----

func test_queen_every_windup_at_least_24t() -> void:
	assert_int(GemQueen.FAN_WINDUP_TICKS).is_equal(30)       # 附录 E.2：0.5s
	assert_int(GemQueen.DIVE_WINDUP_TICKS).is_equal(36)      # 0.6s
	assert_int(GemQueen.HIVE_WINDUP_TICKS).is_equal(48)      # 0.8s
	assert_int(GemQueen.RING_WINDUP_TICKS).is_equal(36)      # 0.6s
	assert_int(GemQueen.RAMPAGE_WINDUP_TICKS).is_equal(30)   # 0.5s

# ---- 阶段门控：P0 扇弹/俯冲；P1 +蜂巢柱/环形爆蜂；P2 +狂暴连冲 ----

func test_queen_p0_alternates_fan_and_dive_only() -> void:
	var b := _queen()
	var f := _engage_ready(b)
	var seq := _run_collect(b, f, 600)
	assert_int(seq.size()).is_greater_equal(6)
	assert_str(seq[0]).is_equal("fan")
	for m in seq:
		assert_bool(m == "fan" or m == "dive").is_true()
	for i in range(1, seq.size()):
		assert_bool(seq[i] != seq[i - 1]).is_true()   # 严格交替

func test_queen_move_sets_expand_by_phase() -> void:
	var b := _queen()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 400):
		assert_bool(m == "fan" or m == "dive").is_true()
	b._take_hit_at(_ctx(320), f + 400)                # 800-320=480 → P1
	var seq1 := _run_collect(b, f + 400, 900)
	assert_bool(seq1.has("hive")).is_true()
	assert_bool(seq1.has("ring")).is_true()
	assert_bool(seq1.has("rampage")).is_false()
	for m in seq1:
		assert_bool(m == "fan" or m == "dive" or m == "hive" or m == "ring").is_true()
	b._take_hit_at(_ctx(240), f + 1300)               # 480-240=240 → P2
	var seq2 := _run_collect(b, f + 1300, 1400)
	assert_bool(seq2.has("rampage")).is_true()
	for m in seq2:
		assert_bool(m == "fan" or m == "dive" or m == "hive" or m == "ring" or m == "rampage").is_true()

# ---- 蜂群扇弹：前摇 30t，8 发扇形×3 轮（24t 间隔），伤 3 速 110，张角内锁定瞄准 ----

func test_queen_fan_three_waves_of_eight() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "queen_fan_test"))
	root.add_child(cs)
	var b := _queen()
	b.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	b.brain_tick(f)                                   # 首拍起招 fan
	var ms: int = b.get("_move_start")
	assert_int(ms).is_equal(f)
	var fired: Array = []
	for i in range(79):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_array(fired).is_equal([ms + 30, ms + 54, ms + 78])   # 3 波各隔 24t
	assert_int(cs.active_count()).is_equal(24)        # 8×3
	var aim := Vector2(200, 0).angle()                # 前摇起始拍锁定的朝向
	var wave_angles := {}
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(3)
		assert_float(p.vel.length()).is_equal_approx(110.0, 0.01)
		assert_str(p.source_id).is_equal("gem_queen")
		assert_str(p.source_name).is_equal("宝石蜂后")
		assert_str(p.attack_name).is_equal("蜂群扇弹")
		var off := angle_difference(aim, p.vel.angle())
		assert_float(absf(off)).is_less_equal(deg_to_rad(GemQueen.FAN_SPREAD_DEG) / 2.0 + 0.001)
		wave_angles[int(round(rad_to_deg(off)))] = true
	assert_int(wave_angles.size()).is_equal(8)        # 每波 8 个互异方向（三波同扇面）

# ---- 俯冲：前摇 36t，沿锁定方向直冲 30t@220（110px），伤 6 恰一跳；前摇中侧移即落空 ----

func test_queen_dive_hits_once_for6_and_travels_110px() -> void:
	var b := _queen()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "dive", f)
	for i in range(70):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(spy.hits[0]["amount"]).is_equal(6)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("俯冲")
	assert_float(b.brain_pos.x).is_equal_approx(110.0, 0.5)   # 220/60×30
	assert_float(b.brain_pos.y).is_equal_approx(0.0, 0.001)

func test_queen_dive_locks_direction_windup_dodgeable() -> void:
	var b := _queen()
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "dive", f)
	for i in range(20):
		b.brain_tick(ms + 1 + i)                      # 前摇 36t 内第 20 拍侧移
	spy.brain_pos = Vector2(60, 120)                  # 远离冲线
	for i in range(50):
		b.brain_tick(ms + 21 + i)
	assert_int(spy.hits.size()).is_equal(0)

# ---- 蜂巢柱：前摇 48t 生成 2 根可破坏掩体（hp20，登记折射组，场内域），吸收敌弹 ----

func test_queen_hive_pillars_destructible_and_block_enemy_bullets() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "queen_hive_test"))
	root.add_child(cs)
	var b := _queen()
	b.combat = cs
	b.combat_bounds = BOUNDS
	b._take_hit_at(_ctx(320), FRAME - 100)            # → P1
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "hive", f)
	for i in range(48):
		b.brain_tick(ms + 1 + i)                      # 前摇 48t 落柱
	var pillars: Array = b._pillars
	assert_int(pillars.size()).is_equal(2)
	assert_float(pillars[0].pos_world.distance_to(pillars[1].pos_world)) \
		.is_equal_approx(GemQueen.HIVE_OFFSET_PX * 2.0, 0.01)
	for p in pillars:
		assert_int(p.hp).is_equal(GemQueen.HIVE_PILLAR_HP)   # 20（同柱陈设契约）
		assert_bool(p.is_in_group(EnemyLaser.PILLAR_GROUP)).is_true()
		assert_bool(BOUNDS.grow(2.0).has_point(p.pos_world)).is_true()
	# 敌弹撞柱被吸收（掩体）；玩家弹不受掩体挡弹扫描影响（柱可被玩家火力拆）
	cs.spawn_projectile({"pos": pillars[0].pos_world, "vel": Vector2.ZERO,
		"damage": 3, "faction": Projectile.Faction.ENEMY, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 5.0, "radius": 3.0,
		"source_type": "projectile", "source_id": "gem_queen", "source_name": "宝石蜂后",
		"attack_name": "蜂群扇弹"})
	cs.spawn_projectile({"pos": pillars[0].pos_world, "vel": Vector2.ZERO,
		"damage": 1, "faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 5.0, "radius": 3.0,
		"source_type": "projectile", "source_id": "t", "source_name": "t",
		"attack_name": "t"})
	assert_int(cs.active_count()).is_equal(2)
	b.brain_tick(ms + 49)
	assert_int(cs.active_count()).is_equal(1)         # 仅敌弹被柱吸收
	# 可破坏：玩家火力拆柱（hp 归零即失效）
	pillars[0].take_hit(_ctx(20))
	assert_int(pillars[0].hp).is_equal(0)
	assert_bool(pillars[1].hp > 0).is_true()

func test_queen_hive_respects_cap_two() -> void:
	var b := _queen()
	b._take_hit_at(_ctx(320), FRAME - 100)            # → P1
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 1200):
		if m == "hive":
			break
	assert_int(b._pillars.size()).is_equal(2)         # 落柱后不再重复施放
	var before := b._pillars.size()
	for m in _run_collect(b, f + 1200, 1200):
		assert_str(String(m)).is_not_equal("hive")    # 2 根存活期内 hive 不入序列
	assert_int(b._pillars.size()).is_equal(before)

# ---- 环形爆蜂：前摇 36t，16 发，每 90° 留缺口（4 象限×4）----

func test_queen_ring_16_bullets_gap_every_90_deg() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "queen_ring_test"))
	root.add_child(cs)
	var b := _queen()
	b.combat = cs
	b._take_hit_at(_ctx(320), FRAME - 100)            # → P1
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "ring", f)
	var fired: Array = []
	for i in range(40):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_array(fired).is_equal([ms + 36])           # 前摇 36t 齐射
	assert_int(cs.active_count()).is_equal(16)
	var gap_centers := [0.0, 90.0, 180.0, 270.0]
	var per_quadrant := [0, 0, 0, 0]
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(3)
		assert_float(p.vel.length()).is_equal_approx(110.0, 0.01)
		assert_str(p.attack_name).is_equal("环形爆蜂")
		var a := wrapf(rad_to_deg(p.vel.angle()), 0.0, 360.0)
		for g in gap_centers:
			var d := absf(a - g)
			d = minf(d, 360.0 - d)
			assert_float(d).is_greater_equal(15.0)    # 缺口无弹（±15°）
		per_quadrant[int(a / 90.0) % 4] += 1
	assert_array(per_quadrant).is_equal([4, 4, 4, 4]) # 16 = 4 象限×4

# ---- 狂暴连冲：前摇 30t → 三段各 24t（段间 12t 再瞄准），每段触伤 6，
#      末段收尾撞墙自晕 1.2s（72t），晕内 brain 空转 ----

func test_queen_rampage_three_charges_then_self_stun_72t() -> void:
	var b := _queen()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(560), FRAME - 100)            # 800-560=240 → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "rampage", f)
	for i in range(130):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(3)           # 每段恰一跳
	for h in spy.hits:
		assert_int(h["amount"]).is_equal(6)
		assert_str(String(h["attack_name"])).is_equal("狂暴连冲")
	# 末段结束拍 = 30(前摇)+24×3(段)+12×2(段间) = 90 → 自晕 72t
	var seg3_end: int = ms + GemQueen.RAMPAGE_WINDUP_TICKS \
		+ GemQueen.RAMPAGE_CHARGES * GemQueen.RAMPAGE_SEG_TICKS \
		+ (GemQueen.RAMPAGE_CHARGES - 1) * GemQueen.RAMPAGE_GAP_TICKS
	assert_int(seg3_end).is_equal(ms + 126)
	assert_int(GemQueen.RAMPAGE_STUN_TICKS).is_equal(72)
	assert_int(b.stun_until).is_equal(seg3_end + GemQueen.RAMPAGE_STUN_TICKS)
	assert_str(String(b.get("_move"))).is_equal("")   # 撞墙后招式位清空
	# 晕内（72t）brain 空转：不再起新招
	var moves_after: Array = _run_collect(b, seg3_end + 1, 70)
	assert_array(moves_after).is_equal([])

func test_queen_rampage_reaims_each_segment() -> void:
	var b := _queen()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(70, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(560), FRAME - 100)            # → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "rampage", f)
	# 第一段（elapsed 30..53）直冲 (70,0) 命中
	for i in range(GemQueen.RAMPAGE_WINDUP_TICKS + GemQueen.RAMPAGE_SEG_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(spy.hits.size()).is_equal(1)
	# 段间 12t 内把玩家移到斜上方（在第二段 88px 冲程内）：第二段须再瞄准仍命中
	spy.brain_pos = Vector2(40, 60)
	for i in range(GemQueen.RAMPAGE_GAP_TICKS + GemQueen.RAMPAGE_SEG_TICKS - 1):
		b.brain_tick(ms + 55 + i)                    # 至第二段收尾（elapsed 89）
	assert_int(spy.hits.size()).is_equal(2)

# ---- 数据接线与死亡路径 ----

func test_queen_gamedb_row_and_factory_wiring() -> void:
	var row := GameDB.get_enemy("gem_queen")
	assert_int(row.get("hp", 0)).is_equal(800)        # 附录 E.2：HP 800
	assert_str(String(row.get("name", ""))).is_equal("宝石蜂后")
	assert_array(row.get("phases", [])).is_equal([1, 0.6, 0.3])   # GameDB 深度整值还原（1.0→1，vine 同口径）
	assert_bool(row.has("boss_script")).is_true()
	assert_int(int(row.get("bullet_speed", 0))).is_less_equal(150)   # 弹速契约
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	assert_object(e).is_not_null()
	assert_bool(e is GemQueen).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	e._take_hit_at(_ctx(320), 9999)                   # 800-320=480 → P1
	assert_int(e.phase()).is_equal(1)

func test_queen_dies_and_despawns_pillars() -> void:
	var b := _queen()
	b._take_hit_at(_ctx(320), FRAME - 100)            # → P1（蜂巢柱解锁）
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "hive", f)
	for i in range(48):
		b.brain_tick(ms + 1 + i)
	assert_int(b._pillars.size()).is_equal(2)
	var pillar := b._pillars[0]
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(1000), ms + 100)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["gem_queen"])
	assert_bool(pillar.hp <= 0).is_true()             # 柱随 Boss 退场
	EventBus.enemy_killed.disconnect(cb)


# ================================================================ 晶棱魔像

# ---- 前摇下限 ----

func test_golem_every_windup_at_least_24t() -> void:
	assert_int(PrismGolem.RAY_WINDUP_TICKS).is_equal(36)       # 附录 E.3：0.6s
	assert_int(PrismGolem.SHARDS_WINDUP_TICKS).is_equal(30)    # 0.5s
	assert_int(PrismGolem.SWEEP_WINDUP_TICKS).is_equal(48)     # 0.8s
	assert_int(PrismGolem.REGEN_WINDUP_TICKS).is_equal(36)     # 0.6s
	assert_int(PrismGolem.BLINK_WINDUP_TICKS).is_equal(30)     # 0.5s

# ---- 开战自带 2 根晶柱（可破坏、登记折射组、在场内域）----

func test_golem_engages_with_two_crystals() -> void:
	var b := _golem()
	b.combat_bounds = BOUNDS
	var f := _engage_ready(b)
	assert_int(b._crystals.size()).is_equal(2)
	assert_float(b._crystals[0].pos_world.distance_to(b._crystals[1].pos_world)) \
		.is_equal_approx(PrismGolem.CRYSTAL_OFFSET_PX * 2.0, 0.01)
	for c in b._crystals:
		assert_int(c.hp).is_equal(PrismGolem.CRYSTAL_HP)
		assert_bool(c.is_in_group(EnemyLaser.PILLAR_GROUP)).is_true()
		assert_bool(BOUNDS.grow(2.0).has_point(c.pos_world)).is_true()

# ---- 阶段门控：P0 射线/碎晶；P1 +三向扫描/晶柱再生（拆柱后）；P2 +瞬移弹幕 ----

func test_golem_move_sets_expand_by_phase() -> void:
	var b := _golem()
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 400):
		assert_bool(m == "ray" or m == "shards").is_true()
	for c in b._crystals:
		c.take_hit(_ctx(PrismGolem.CRYSTAL_HP))       # 拆光晶柱：regen 才会登场
	b._take_hit_at(_ctx(720), f + 400)                # 1800-720=1080 → P1
	var seq1 := _run_collect(b, f + 400, 1600)
	assert_bool(seq1.has("sweep")).is_true()
	assert_bool(seq1.has("regen")).is_true()
	assert_bool(seq1.has("blink")).is_false()
	for m in seq1:
		assert_bool(m == "ray" or m == "shards" or m == "sweep" or m == "regen").is_true()
	b._take_hit_at(_ctx(540), f + 2000)               # 1080-540=540 → P2
	var seq2 := _run_collect(b, f + 2000, 2600)
	assert_bool(seq2.has("blink")).is_true()

# ---- 棱镜射线：前摇 36t 发 EnemyLaser（速 150 伤 5），命中晶柱 45° 折射（T7 复用）----

func test_golem_prism_ray_refracts_off_crystal_45() -> void:
	var b := _golem()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(300, 0)                   # 与开局晶柱 (80,0) 同轴
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "ray", f)
	var fired: Array = []
	for i in range(38):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
	assert_array(fired).is_equal([ms + 36])           # 前摇 36t 出束
	var laser: EnemyLaser = null
	for child in b.get_children():
		if child is EnemyLaser:
			laser = child
	assert_object(laser).is_not_null()
	assert_int(laser.damage).is_equal(5)
	assert_float(laser.speed_px).is_equal_approx(150.0, 0.01)
	assert_vector(laser.dir).is_equal_approx(Vector2.RIGHT, Vector2(0.001, 0.001))
	assert_int(laser.refracts_left).is_equal(1)
	assert_bool(laser.pillars.has(Vector2(80, 0))).is_true()   # 自有晶柱已注入折射源
	for _i in range(60):                              # 2.5px/t → ~32 拍触柱 (80,0)
		if laser.alive():
			laser.tick()
	assert_bool(laser.alive()).is_true()              # 折射后继续飞
	assert_int(laser.refracts_left).is_equal(0)
	assert_vector(laser.dir).is_equal_approx(Vector2.DOWN, Vector2(0.001, 0.001))   # 右→下

# ---- 碎晶抛射：前摇 30t 定 5 落点（预警红圈），飞行 36t 落地伤 5，
#      生 3s 晶刺区（每 30t 5 伤）----

func test_golem_shards_five_targets_landing_then_spike_zone_3s() -> void:
	var b := _golem()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 50)
	b.player_ref = spy
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "shards", f)
	var targets: Array = b._shard_targets            # 招式起始拍即定落点（预警）
	assert_int(targets.size()).is_equal(PrismGolem.SHARD_COUNT)
	assert_vector(targets[0]).is_equal_approx(Vector2(100, 50), Vector2(0.01, 0.01))   # 玩家位为心
	var hit_frames: Array = []
	for i in range(320):
		b.brain_tick(ms + 1 + i)
		if spy.hits.size() > hit_frames.size():
			hit_frames.append(ms + 1 + i)
	var landing: int = ms + PrismGolem.SHARDS_WINDUP_TICKS + PrismGolem.SHARD_FLIGHT_TICKS
	assert_int(landing).is_equal(ms + 66)
	assert_array(hit_frames.slice(0, 1)).is_equal([landing])   # 落地拍命中
	assert_int(spy.hits[0]["amount"]).is_equal(5)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("碎晶抛射")
	# 晶刺区：落地后每 30t 一跳（5 伤），至 +180t 停（共 6 跳）
	var zone_hits: Array = []
	for i in range(1, spy.hits.size()):
		assert_int(spy.hits[i]["amount"]).is_equal(5)
		assert_str(String(spy.hits[i]["attack_name"])).is_equal("晶刺区")
		zone_hits.append(hit_frames[i])
	assert_array(zone_hits).is_equal([landing + 30, landing + 60, landing + 90,
		landing + 120, landing + 150, landing + 180])
	for i in range(26):
		b.brain_tick(ms + 321 + i)                   # 区过期（+180t 步进已在上方窗口穷尽）后无新跳；
	assert_int(spy.hits.size()).is_equal(7)          # 窗口止于下一轮 shards 落点 ms+350 之前（背靠背循环节拍）

# ---- 三向扫描：前摇 48t 起 3 束相隔 120° 旋转激光（60°/s = 1°/拍），伤 5 ----

func test_golem_tri_sweep_beams_rotate_and_hit_for5() -> void:
	var b := _golem()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	b.player_ref = spy
	b._take_hit_at(_ctx(720), FRAME - 100)            # → P1
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "sweep", f)
	var base: float = b._sweep_base_angle
	assert_float(base).is_equal_approx(0.0, 0.001)    # 起始角即瞄准角
	var hits_before: int = spy.hits.size()            # 先前招式（碎晶落点含玩家位）既有命中基线
	var hit_frames: Array = []
	for i in range(138):                              # 激活拍 + 90 拍旋转
		b.brain_tick(ms + 1 + i)
		if spy.hits.size() > hits_before + hit_frames.size():
			hit_frames.append(ms + 1 + i)
	assert_array(hit_frames).is_equal([ms + PrismGolem.SWEEP_WINDUP_TICKS])   # 激活拍正对玩家
	assert_int(spy.hits[hits_before]["amount"]).is_equal(5)
	assert_str(String(spy.hits[hits_before]["attack_name"])).is_equal("三向扫描")
	assert_float(b._sweep_rotated_deg).is_equal_approx(90.0, 0.01)   # 60°/s×1.5s
	var angles: Array = b._sweep_angles
	assert_int(angles.size()).is_equal(3)
	for k in range(1, 3):
		assert_float(wrapf(angles[k] - angles[0], -PI, PI)) \
			.is_equal_approx(wrapf(deg_to_rad(120.0 * k), -PI, PI), 0.01)   # 束间 120°（±π 等价角）

# ---- 晶柱再生：拆光晶柱后 regen 登场，前摇 36t 补满 2 根（场内域）----

func test_golem_regen_restores_crystals_to_two() -> void:
	var b := _golem()
	b.combat_bounds = BOUNDS
	var f := _engage_ready(b)
	for c in b._crystals:
		c.take_hit(_ctx(PrismGolem.CRYSTAL_HP))       # 玩家火力拆光
	assert_int(b._alive_crystals()).is_equal(0)
	b._take_hit_at(_ctx(720), FRAME + 100)            # → P1
	var ms: int = _drive_to_move(b, "regen", f, 6000)
	for i in range(PrismGolem.REGEN_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(b._alive_crystals()).is_equal(2)
	for c in b._crystals:
		if is_instance_valid(c) and c.hp > 0:
			assert_bool(BOUNDS.grow(2.0).has_point(c.pos_world)).is_true()

func test_golem_regen_gated_while_crystals_full() -> void:
	var b := _golem()
	b._take_hit_at(_ctx(720), FRAME - 100)            # → P1（晶柱 2 根完好）
	var f := _engage_ready(b)
	for m in _run_collect(b, f, 2000):
		assert_str(String(m)).is_not_equal("regen")

# ---- 瞬移弹幕：前摇 30t → 瞬移+20 环×3（间隔 72t），瞬移落点场内域、分盐流确定 ----

func test_golem_blink_three_teleport_rings_of_20() -> void:
	const SEED := 20260830
	RngSvc.setup_run(SEED)
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "golem_blink_test"))
	root.add_child(cs)
	var b := _golem()
	b.combat = cs
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(-200, -100)
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)           # 1800-1260=540 → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "blink", f, 8000)
	var fired: Array = []
	var teleports: Array = []
	var prev_pos := b.brain_pos
	for i in range(PrismGolem.BLINK_WINDUP_TICKS + 2 * PrismGolem.BLINK_INTERVAL_TICKS + 2):
		b.brain_tick(ms + 1 + i)
		if b.fired_this_tick:
			fired.append(ms + 1 + i)
		if b.brain_pos != prev_pos:
			teleports.append(b.brain_pos)
			prev_pos = b.brain_pos
	assert_array(fired).is_equal([ms + 30, ms + 102, ms + 174])   # 3 次间隔 72t
	assert_int(cs.active_count()).is_equal(60)        # 20×3
	assert_int(teleports.size()).is_equal(3)
	for pos in teleports:
		assert_bool(BOUNDS.grow(-8.0).has_point(pos)).is_true()   # 落点场内域
	for p in cs.pool.active:
		assert_int(p.damage).is_equal(5)
		assert_float(p.vel.length()).is_equal_approx(100.0, 0.01)
		assert_str(p.attack_name).is_equal("瞬移弹幕")
	# 同 seed 重复局：瞬移序列逐点一致（分盐流确定性）
	RngSvc.setup_run(SEED)
	var b2 := _golem()
	b2.combat_bounds = BOUNDS
	b2._take_hit_at(_ctx(1260), FRAME - 100)
	var f2 := _engage_ready(b2)
	var ms2: int = _drive_to_move(b2, "blink", f2, 8000)
	for i in range(PrismGolem.BLINK_WINDUP_TICKS + 2 * PrismGolem.BLINK_INTERVAL_TICKS + 2):
		b2.brain_tick(ms2 + 1 + i)
	assert_str(var_to_str(b2._blink_positions)).is_equal(var_to_str(b._blink_positions))

# ---- 晶柱挡敌弹（可藏柱后）：魔像自身弹幕被晶柱吸收 ----

func test_golem_crystals_block_enemy_bullets() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "golem_block_test"))
	root.add_child(cs)
	var b := _golem()
	b.combat = cs
	b.combat_bounds = BOUNDS
	_engage_ready(b)
	var crystal := b._crystals[0]
	cs.spawn_projectile({"pos": crystal.pos_world, "vel": Vector2.ZERO,
		"damage": 5, "faction": Projectile.Faction.ENEMY, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 5.0, "radius": 4.0,
		"source_type": "projectile", "source_id": "prism_golem", "source_name": "晶棱魔像",
		"attack_name": "瞬移弹幕"})
	assert_int(cs.active_count()).is_equal(1)
	b.brain_tick(FRAME + 30)
	assert_int(cs.active_count()).is_equal(0)         # 被晶柱吸收

# ---- 数据接线与死亡路径 ----

func test_golem_gamedb_row_and_factory_wiring() -> void:
	var row := GameDB.get_enemy("prism_golem")
	assert_int(row.get("hp", 0)).is_equal(1800)       # 附录 E.3：HP 1800
	assert_str(String(row.get("name", ""))).is_equal("晶棱魔像")
	assert_array(row.get("phases", [])).is_equal([1, 0.6, 0.3])   # GameDB 深度整值还原（1.0→1，vine 同口径）
	assert_bool(row.has("boss_script")).is_true()
	assert_int(int(row.get("bullet_speed", 0))).is_less_equal(150)   # 弹速契约
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	assert_object(e).is_not_null()
	assert_bool(e is PrismGolem).is_true()
	assert_bool(e is BossBase).is_true()
	e.on_player_seen(0)
	for f in range(1, 26):
		e.brain_tick(f)
	e._take_hit_at(_ctx(720), 9999)                   # 1800-720=1080 → P1
	assert_int(e.phase()).is_equal(1)

func test_golem_dies_and_despawns_crystals() -> void:
	var b := _golem()
	_engage_ready(b)
	var crystal := b._crystals[0]
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	b._take_hit_at(_ctx(2000), FRAME)
	assert_int(b.state).is_equal(EnemyBase.State.DEAD)
	assert_array(killed).is_equal(["prism_golem"])
	assert_bool(crystal.hp <= 0).is_true()            # 晶柱随 Boss 退场
	EventBus.enemy_killed.disconnect(cb)

# ---- 双 Boss 免疫冻结语义（T11 已立：is_boss 冻结豁免，回归钉死）----

func test_m2_bosses_immune_to_freeze() -> void:
	var q := _queen()
	assert_bool(q.status.is_boss).is_true()
	q.status.apply_freeze(120, FRAME)
	assert_bool(q.status.is_frozen(FRAME + 1)).is_false()
	var g := _golem()
	assert_bool(g.status.is_boss).is_true()
	g.status.apply_freeze(120, FRAME)
	assert_bool(g.status.is_frozen(FRAME + 1)).is_false()
