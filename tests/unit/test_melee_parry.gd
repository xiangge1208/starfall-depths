class_name TestMeleeParry
extends GdUnitTestSuite
## m0-t9：近战反弹窗口边界 + CombatSystem.reflect 语义 + bodies_in_arc 扇形过滤。

class CsProbe:
	var reflected: Array = []
	var blocked: Array = []
	func reflect(p, dmg: int) -> void:
		reflected.append([p, dmg])
	func block(p) -> void:
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
	assert_bool(m.is_parry_tick(10)).is_true()
	assert_bool(m.is_parry_tick(11)).is_false()
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
