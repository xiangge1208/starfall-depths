class_name TestWeaponRig
extends GdUnitTestSuite

class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)

func before_test() -> void:
	# 前置自检：注入夹具必须已清理，防止跨用例泄漏（配合 after_test）
	assert_bool(GameDB.weapons.has("testgun")).is_false()
	assert_bool(GameDB.weapons.has("testgun3")).is_false()

func after_test() -> void:
	# brief ②：删除测试注入的 testgun/testgun3 夹具后必须清理，保持 GameDB.weapons 干净
	GameDB.weapons.erase("testgun")
	GameDB.weapons.erase("testgun3")

func _rig() -> RigProbe:
	# 注：brief 原文 `var p := auto_free(Player.new())`，auto_free 返回 Variant，:= 无法推断类型
	# （同 test_player_state.gd / test_combat_system.gd 既定决议），需显式类型标注。
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	return r

func test_rate_limiting() -> void:
	var r := _rig()
	r.equip("laohuoji")                  # 4.0/s → 15 ticks
	assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_true()
	assert_bool(r.try_fire(Vector2.RIGHT, 14)).is_false()
	assert_bool(r.try_fire(Vector2.RIGHT, 15)).is_true()

func test_energy_block_when_empty() -> void:
	GameDB.weapons["testgun3"] = {"id":"testgun3","name":"t3","category":"pistol","rarity":"common","damage":1,"rate":2.0,"energy_cost":5,"bullet_speed":300,"spread_deg":0.0,"projectiles":1,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0,"bullet_life":1.2,"bullet_radius":3.0,"muzzle":8.0}
	var r := _rig()
	r.equip("testgun3")                  # 蓝耗 5（M0 六把初始武器全 0 耗，注入一把有耗的验证空蓝规则）
	r.get_parent().energy = 3
	assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_false()

func test_melee_weapon_not_fired_by_rig() -> void:
	var r := _rig()
	r.equip("tiejian")
	assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_false()

func test_multishot_fan_count() -> void:
	GameDB.weapons["testgun"] = {"id":"testgun","name":"t","category":"pistol","rarity":"common","damage":1,"rate":10.0,"energy_cost":0,"bullet_speed":300,"spread_deg":30.0,"projectiles":3,"pierce":0,"bounce":0,"element":"none","is_melee":false,"range":0,"arc_deg":0.0,"bullet_life":1.2,"bullet_radius":3.0,"muzzle":8.0}
	var r := _rig()
	r.equip("testgun")
	r.combat_rng = RngSvc.stream(0, "combat")
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(r.spawned.size()).is_equal(3)

func test_switch_lock() -> void:
	var r := _rig()
	r.equip("laohuoji")                  # equip 规则：填第一个空槽；两槽满替换当前槽
	r.equip("maodingqiang")              # -> 槽 1
	r.switch_slot(0)                     # -> 槽 1（铆钉枪），锁定至第 15 帧
	assert_bool(r.try_fire(Vector2.RIGHT, 14)).is_false()
	assert_bool(r.try_fire(Vector2.RIGHT, 15)).is_true()
