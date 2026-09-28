extends GdUnitTestSuite
## M5-A2 手刀（空手攻击）：空槽按开火 = 徒手挥击——虚拟行走与真实近战同一条
## 挥击/反弹路径（Melee.HAND_BLADE，单一事实源；GDD §7.4 窗口语义不变）。
## 覆盖：空槽可挥击 / 远程武器不路由 / 伤害与来源归因 hand_blade / 反弹伤害=1 /
## 射速节流 3.0/s（20 ticks）/ 真实近战行为不受影响（tiejian 对照）。
## 驱动方式沿 test_melee_parry（CsProbe 脚本化弹幕 + 手动 _physics_process 逐 tick）。
## 探针经 CombatSystem 子类覆写（同 test_melee_parry 裁决：Melee.combat 强类型，
## 纯 RefCounted 探针无法赋值）；auto_free 释放池根防 300 预分配弹孤儿。


class CsProbe extends CombatSystem:
	var reflected: Array = []
	var blocked: Array = []
	var scripted_projectiles: Array[Projectile] = []
	var scripted_body: Node2D
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


func _rigged_melee(slot0: Dictionary, slot1: Dictionary) -> Array:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [slot0, slot1]
	var probe: CsProbe = auto_free(CsProbe.new())
	probe.scripted_projectiles = [auto_free(Projectile.new())]
	probe.scripted_body = auto_free(DummyBody.new())
	m.combat = probe
	return [p, m, probe]


func test_empty_slot_can_attack() -> void:
	var r := _rigged_melee({}, {})
	assert_bool((r[1] as Melee).try_attack(0)).is_true()


func test_ranged_weapon_still_rejects_melee_path() -> void:
	var r := _rigged_melee(GameDB.get_weapon("laohuoji"), {})
	assert_bool((r[1] as Melee).try_attack(0)).is_false()


func test_hand_blade_damage_and_source_attribution() -> void:
	var r := _rigged_melee({}, {})
	var m: Melee = r[1]
	assert_bool(m.try_attack(0)).is_true()
	for _i in Melee.SWING_TICKS:
		m._physics_process(1.0 / TimeConst.FPS)
	var body: DummyBody = (r[2] as CsProbe).scripted_body
	assert_int(body.hits.size()).is_equal(1)                  # 伤害恰一次（_hit_done 守卫）
	assert_int(body.hits[0]["amount"]).is_equal(1)            # 手刀伤害 1
	assert_int(body.hits[0]["element"]).is_equal(Elements.Id.NONE)
	assert_bool(body.hits[0]["is_crit"]).is_false()
	assert_int((r[2] as CsProbe).reflected.size()).is_equal(7)  # 反弹窗口 [3,9] 同近战
	assert_int((r[2] as CsProbe).reflected[0][1]).is_equal(1)   # 反弹伤害 = 手刀伤害 1


func test_hand_blade_rate_throttle_3_per_second() -> void:
	var r := _rigged_melee({}, {})
	var m: Melee = r[1]
	assert_bool(m.try_attack(0)).is_true()
	(m as Melee)._swing_left = 0                               # 清挥击态，单测帧率门
	assert_bool(m.try_attack(19)).is_false()                   # 3.0/s → 20 ticks 冷却
	assert_bool(m.try_attack(20)).is_true()


func test_melee_weapon_path_unchanged_after_hand_blade() -> void:
	var r := _rigged_melee(GameDB.get_weapon("tiejian"), {})
	var m: Melee = r[1]
	assert_bool(m.try_attack(0)).is_true()
	for _i in Melee.SWING_TICKS:
		m._physics_process(1.0 / TimeConst.FPS)
	var body: DummyBody = (r[2] as CsProbe).scripted_body
	assert_int(body.hits[0]["amount"]).is_equal(6)             # 铁剑伤害 6（既有契约不漂移）
	assert_int((r[2] as CsProbe).reflected[0][1]).is_equal(6)


func test_hand_blade_virtual_row_is_not_in_gamedb() -> void:
	# 手刀不入武器表（图鉴/掉落池零污染契约）
	assert_dict(GameDB.get_weapon("hand_blade")).is_empty()
