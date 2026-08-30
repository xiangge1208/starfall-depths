class_name TestMeleeParry
extends GdUnitTestSuite
## m0-t9：近战反弹窗口边界 + CombatSystem.reflect 语义 + bodies_in_arc 扇形过滤。

class CsProbe extends CombatSystem:
	# 注：Melee.combat 字段强类型 CombatSystem（brief 原文），纯 RefCounted 探针无法赋值，
	# 故以 CombatSystem 子类覆写实现"脚本化弹幕 + 记录"（裁决意图不变）。
	# _init 经 super(...) 会预分配 300 弹挂池根，PREDELETE 时释放池根避免孤儿。
	var reflected: Array = []                 # [p, dmg] 逐次记录
	var blocked: Array = []                   # p 逐次记录
	var scripted_projectiles: Array[Projectile] = []
	var scripted_body: Node2D                 # 裁决原文写 bodies_in_arc "returning empty"，
	                                          # 但"伤害恰好一次"断言须经 take_hit 路径观察，故返回单个脚本体
	var _pool_root: Node2D

	func _init() -> void:
		_pool_root = Node2D.new()
		super(_pool_root, null)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _pool_root != null:
			_pool_root.free()
			_pool_root = null

	func projectiles_in_arc(_origin: Vector2, _facing: float, _range_px: float, _arc_deg: float, _faction: int) -> Array[Projectile]:
		return scripted_projectiles

	func bodies_in_arc(_origin: Vector2, _facing: float, _range_px: float, _arc_deg: float, _faction: int) -> Array:
		return [scripted_body] if scripted_body != null else []

	func reflect(p: Projectile, dmg: int) -> void:
		reflected.append([p, dmg])

	func block(p: Projectile) -> void:
		blocked.append(p)

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

func test_parry_window_bounds() -> void:
	# 注：brief 原文 `var p := auto_free(...)`，auto_free 返回 Variant，:= 无法推断类型
	# （同 test_weapon_rig.gd / test_combat_system.gd 既定决议），需显式类型标注。
	var p: Player = auto_free(Player.new())
	p._test_init()
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	# 注：rig 持 auto_free，避免孤儿节点（brief 原文 WeaponRig.new() 未入树未释放）。
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("tiejian"), {}]   # 近战 2.2/s → 27 ticks
	assert_bool(m.try_attack(0)).is_true()
	assert_bool(m.is_parry_tick(2)).is_false()
	assert_bool(m.is_parry_tick(3)).is_true()
	assert_bool(m.is_parry_tick(9)).is_true()    # 窗口 [3,9]（GDD §7.4 修订：0.12s = 第 3~9 逻辑帧）
	assert_bool(m.is_parry_tick(10)).is_false()
	# 补（控制器决议：_next_frame = frame + max(1, round(60/rate))，brief 测试未覆盖边界）：
	m._swing_left = 0                           # 清挥击态，单测帧率门
	assert_bool(m.try_attack(26)).is_false()    # tiejian 2.2/s → 27 ticks 冷却
	assert_bool(m.try_attack(27)).is_true()

func test_reflect_sets_melee_damage() -> void:
	# 直接测 CombatSystem.reflect 语义（与 m0-t6 接口一致性）
	var proj: Projectile = auto_free(Projectile.new())
	proj.faction = Projectile.Faction.ENEMY
	proj.vel = Vector2.RIGHT * 100
	# 注：brief 原文 CombatSystem.new(Node.new(), ...) 内联节点未释放会产生 300+ 孤儿
	#（ProjectilePool 预分配挂其下），改为持 auto_free 引用。
	var pool_root: Node = auto_free(Node.new())
	var cs: CombatSystem = auto_free(CombatSystem.new(pool_root, RngSvc.stream(0, "t")))
	cs.reflect(proj, 6)
	assert_int(proj.faction).is_equal(Projectile.Faction.PLAYER)
	assert_int(proj.damage).is_equal(6)
	assert_float(proj.vel.x).is_equal_approx(-100.0, 0.001)

func test_bodies_in_arc_sector_filter() -> void:
	# m0-t9 Step3 补充：bodies_in_arc 与 projectiles_in_arc 同构——
	# 弧内命中、弧外排除、射程门（含体半径）、阵营过滤。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	root.add_child(cs)
	var inside: DummyBody = auto_free(DummyBody.new())
	root.add_child(inside)
	inside.position = Vector2(80, 0)                   # 距离 80 ≤ 100+6，角度 0° ≤ 45°
	cs.register_body(inside, Projectile.Faction.ENEMY)
	var outside_arc: DummyBody = auto_free(DummyBody.new())
	root.add_child(outside_arc)
	outside_arc.position = Vector2(0, 80)              # 角度 90° > 半角 45°
	cs.register_body(outside_arc, Projectile.Faction.ENEMY)
	var far: DummyBody = auto_free(DummyBody.new())
	root.add_child(far)
	far.position = Vector2(200, 0)                     # 距离 200 > 100+6
	cs.register_body(far, Projectile.Faction.ENEMY)
	var friendly: DummyBody = auto_free(DummyBody.new())
	root.add_child(friendly)
	friendly.position = Vector2(80, 0)                 # 阵营不符
	cs.register_body(friendly, Projectile.Faction.PLAYER)
	var radius_edge: DummyBody = auto_free(DummyBody.new())
	root.add_child(radius_edge)
	radius_edge.position = Vector2(105, 0)             # 距离 105 ≤ 100+6（半径计入射程）
	cs.register_body(radius_edge, Projectile.Faction.ENEMY)
	var hit := cs.bodies_in_arc(Vector2.ZERO, 0.0, 100.0, 90.0, Projectile.Faction.ENEMY)
	assert_int(hit.size()).is_equal(2)
	assert_bool(hit.has(inside)).is_true()
	assert_bool(hit.has(radius_edge)).is_true()
	var friendly_hit := cs.bodies_in_arc(Vector2.ZERO, 0.0, 100.0, 90.0, Projectile.Faction.PLAYER)
	assert_int(friendly_hit.size()).is_equal(1)
	assert_bool(friendly_hit.has(friendly)).is_true()

func test_swing_routing_block_reflect_damage_once() -> void:
	# 控制器裁决补测（闭环审查空白）：逐 tick 手动驱动整段挥击（不经物理帧，直接调 _physics_process）——
	# tick1..2 窗口外格挡；tick3..9 窗口内反弹（恰 7 次）；伤害经 bodies_in_arc→take_hit 恰好一次。
	var p: Player = auto_free(Player.new())
	p._test_init()
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("tiejian"), {}]
	# 注：CsProbe 经 CombatSystem 继承自 Node（非 RefCounted），必须 auto_free，
	# 否则探针 + 池根 + 300 预分配弹全部泄漏（auto_free → PREDELETE → 释放池根）。
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]   # 每 tick 恰一枚弧内敌方弹
	probe.scripted_body = auto_free(DummyBody.new())
	m.combat = probe
	assert_bool(m.try_attack(0)).is_true()
	for i in Melee.SWING_TICKS:
		m._physics_process(1.0 / TimeConst.FPS)
		if i < 2:
			assert_int(probe.blocked.size()).is_equal(i + 1)     # tick1..2 → 逐 tick 格挡
			assert_int(probe.reflected.size()).is_equal(0)
		else:
			assert_int(probe.reflected.size()).is_equal(i - 1)   # tick3..9 → 反弹累计 1..7
			assert_int(probe.blocked.size()).is_equal(2)
	assert_int(probe.reflected.size()).is_equal(7)
	assert_int(probe.blocked.size()).is_equal(2)
	assert_int(probe.reflected[0][1]).is_equal(6)                # 反弹伤害 = 铁剑伤害
	var body: DummyBody = probe.scripted_body
	assert_int(body.hits.size()).is_equal(1)                     # 伤害恰一次（_hit_done 守卫）
	assert_int(body.hits[0]["amount"]).is_equal(6)               # combat_rng 未注入 → 平伤
	assert_bool(body.hits[0]["is_crit"]).is_false()
	assert_int(body.hits[0]["element"]).is_equal(Elements.Id.NONE)

func test_melee_consumes_attack_speed_crit_damage_status_and_element_proc() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.set_meta("crit_base", 0.05)
	p.crit_bonus = 0.95
	p.crit_damage_bonus = 0.5
	p.status_rate_bonus = 0.25
	p.atk_speed_boost_pct = 0.25
	p.atk_speed_boost_until = 100
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var native_ice_blade := GameDB.get_weapon("tiejian").duplicate(true)
	native_ice_blade["element"] = "ice"
	rig.slots = [native_ice_blade, {}]
	rig.rate_mult = 1.12
	rig.enchant_element = Elements.Id.FIRE
	rig.enchant_proc_chance = 1.0
	rig.crit_detonate_pct = 1.0
	m.rig = rig
	m.combat_rng = RandomNumberGenerator.new()
	m.combat_rng.seed = 12345
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_body = auto_free(DummyBody.new())
	m.combat = probe
	assert_bool(m.try_attack(0)).is_true()
	# 2.2 * 1.12 * 1.25 = 3.08/s -> round(60/3.08)=19t
	m._swing_left = 0
	assert_bool(m.try_attack(18)).is_false()
	assert_bool(m.try_attack(19)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	var hit: Dictionary = (probe.scripted_body as DummyBody).hits[0]
	assert_int(hit["amount"]).is_equal(15) # 铁剑 6 * (2.0 + 0.5)
	assert_bool(hit["is_crit"]).is_true()
	assert_int(hit["element"]).is_equal(Elements.Id.ICE)
	assert_int(hit["proc_element"]).is_equal(Elements.Id.FIRE)
	assert_float(hit["status_rate_mult"]).is_equal(1.25)
	assert_bool(hit["force_resonance"]).is_true()
