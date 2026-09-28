extends GdUnitTestSuite
## M5-E 局内武器升级台：契约测试。
## 1) 售卖（UpgradeBench.interact / can_interact）——35/55/80 递增扣款、金币不足
##    no-op、满级拒绝（can_interact=false + 「已满级」文案 + 交互 no-op）；
## 2) 实例字段 up_level——equip 副本写入（GameDB 共享行零污染，复用 m5-c 的
##    laohuoji 锚定断言）；对账路径直塞共享行由写入前 deep-copy 兜底（同款护栏）；
## 3) 两把武器实例隔离——升级 A 不影响 B（级数/伤害双断言）；
## 4) 伤害乘区——try_fire 弹 damage 25→27→29→31（RigProbe 捕获，test_m5_attachments
##    先例）；player.scaled_damage 漏斗直测（= 近战挥击同出口）；配件 dmg_pct 先
##    round、up_level 后 round 的链式次序；无 rig/无 up_level 恒 1.0 零漂移。
## 基建沿 test_m5_attachments（TestSaveSeal 密封 / RigProbe / 注入行还原）。

var _saved_weapons: Variant = null
var _seal: Dictionary = {}


func before_test() -> void:
	_seal = TestSaveSeal.seal("upgrade_bench")
	RunState.coins = 0


func after_test() -> void:
	if _saved_weapons != null:
		GameDB.weapons = _saved_weapons
		_saved_weapons = null
	TestSaveSeal.restore(_seal)
	RunState.coins = 0


# ---------------------------------------------------------------- 替身与桩

class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)


func _rig(id := "bench_gun") -> RigProbe:
	# 同 test_m5_attachments._rig 决议：auto_free 返回 Variant，:= 需显式类型标注；
	# 另将 p.weapon_rig 显式接线（scaled_damage 漏斗读当前槽 up_level 的消费前提）。
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r
	r.equip(id)
	return r


func _inject_gun(id: String, damage: int, gun_name := "t") -> void:
	if _saved_weapons == null:
		_saved_weapons = GameDB.weapons
	GameDB.weapons[id] = {"id": id, "name": gun_name, "category": "pistol",
		"rarity": "common", "damage": damage, "rate": 10.0, "energy_cost": 0,
		"bullet_speed": 300, "spread_deg": 0.0, "projectiles": 1,
		"pierce": 0, "bounce": 0, "element": "none", "is_melee": false,
		"range": 0, "arc_deg": 0.0, "bullet_life": 1.2, "bullet_radius": 3.0, "muzzle": 8.0}


func _bench() -> UpgradeBench:
	var b: UpgradeBench = auto_free(UpgradeBench.new())
	b.wallet = RunState
	return b


## 连升到 target 级（钱包由用例自备；返回最终余额）。
func _upgrade_to(bench: UpgradeBench, p: Player, target: int) -> int:
	for i in target:
		bench.interact(p)
	return RunState.coins


# ---------------------------------------------------------------- 1) 售卖契约

func test_upgrade_deducts_incremental_prices() -> void:
	_inject_gun("bench_gun", 25)
	var r := _rig()
	var b := _bench()
	RunState.coins = 200
	b.interact(r.get_parent())
	assert_int(RunState.coins).is_equal(165)                 # 200-35
	assert_int(int(r.current()["up_level"])).is_equal(1)
	b.interact(r.get_parent())
	assert_int(RunState.coins).is_equal(110)                 # -55
	assert_int(int(r.current()["up_level"])).is_equal(2)
	b.interact(r.get_parent())
	assert_int(RunState.coins).is_equal(30)                  # -80
	assert_int(int(r.current()["up_level"])).is_equal(3)


func test_insufficient_funds_noop() -> void:
	_inject_gun("bench_gun", 25)
	var r := _rig()
	var b := _bench()
	RunState.coins = 34                                      # 差 1 金
	b.interact(r.get_parent())
	assert_int(RunState.coins).is_equal(34)                  # 余额不动
	assert_bool(r.current().has("up_level")).is_false()
	assert_bool(b.can_interact(r.get_parent())).is_true()    # 仍可交互（金币 HUD 即反馈）
	RunState.coins = 35
	b.interact(r.get_parent())
	assert_int(int(r.current()["up_level"])).is_equal(1)


func test_max_level_rejects_and_label_maxed() -> void:
	_inject_gun("bench_gun", 25)
	var r := _rig()
	var b := _bench()
	RunState.coins = 170                                     # 35+55+80 恰好
	_upgrade_to(b, r.get_parent(), 3)
	assert_bool(b.can_interact(r.get_parent())).is_false()   # 满级浮标隐藏（图腾充能同款）
	assert_str(b.action_label).is_equal("已满级")
	b.interact(r.get_parent())                               # 满级交互 no-op
	assert_int(RunState.coins).is_equal(0)
	assert_int(int(r.current()["up_level"])).is_equal(3)


func test_empty_slot_not_interactable() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r                                         # 空槽（手刀态）
	var b := _bench()
	assert_bool(b.can_interact(p)).is_false()


func test_label_reflects_weapon_name_and_next_price() -> void:
	_inject_gun("bench_gun", 25, "t")
	var r := _rig()
	var b := _bench()
	assert_bool(b.can_interact(r.get_parent())).is_true()
	assert_str(b.action_label).is_equal("升级 t（35金）")
	RunState.coins = 200
	b.interact(r.get_parent())
	assert_str(b.action_label).is_equal("升级 t（55金）")     # can_interact 每拍刷新文案
	b.interact(r.get_parent())
	assert_str(b.action_label).is_equal("升级 t（80金）")


# ---------------------------------------------------------------- 2) 实例隔离 + 零污染

func test_two_weapons_up_level_instance_isolation() -> void:
	_inject_gun("bench_gun", 25, "t")
	_inject_gun("bench_gun_b", 10, "u")
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r
	r.equip("bench_gun")                                     # 槽 0
	r.equip("bench_gun_b")                                   # 槽 1（当前槽仍 0）
	var b := _bench()
	RunState.coins = 100
	b.interact(p)                                            # 升级手持的 bench_gun
	assert_int(int(r.current()["up_level"])).is_equal(1)
	r.switch_slot(0)                                         # 切到 bench_gun_b
	assert_bool(r.current().has("up_level")).is_false()      # B 未升级：无键、无乘区
	assert_bool(b.can_interact(p)).is_true()                 # B 从 0 级重新计价
	assert_str(b.action_label).is_equal("升级 u（35金）")
	assert_int(RunState.coins).is_equal(65)
	r.try_fire(Vector2.RIGHT, 100)                           # 帧过换枪锁（15t）再开火
	assert_int(int(r.spawned[0]["damage"])).is_equal(10)     # B 伤害吃不到 A 的乘区
	r.switch_slot(0)                                         # 切回 A
	assert_int(int(r.current()["up_level"])).is_equal(1)     # A 级数保留
	r.try_fire(Vector2.RIGHT, 200)
	assert_int(int(r.spawned[1]["damage"])).is_equal(27)     # A 乘区仍生效


func test_equip_copy_upgraded_shared_row_untouched() -> void:
	# 复用 m5-c 锚定断言（test_equip_instantiates_copy_shared_row_untouched）：
	# 实例层挂 up_level，共享缓存行必须仍然干净（weapons_all 121 基线零污染）。
	var r := _rig("laohuoji")
	var b := _bench()
	RunState.coins = 100
	b.interact(r.get_parent())
	assert_int(int(r.current()["up_level"])).is_equal(1)
	assert_bool(GameDB.get_weapon("laohuoji").has("up_level")).is_false()
	assert_dict(GameDB.get_weapon("laohuoji")).contains_keys("damage")
	assert_bool(GameDB.get_weapon("laohuoji").has("attachments")).is_false()
	assert_int(GameDB.weapons_all.size()).is_equal(121)


func test_shared_row_slot_injection_zero_pollution() -> void:
	# run_root 对账路径直写共享行进槽（rig.slots[i] = GameDB 行）——升级台必须先
	# 实例化兜底再写 up_level（m5-c apply_attachment 同款护栏）。
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	p.weapon_rig = r
	r.slots = [GameDB.get_weapon("laohuoji"), {}]
	r.slot = 0
	var b := _bench()
	RunState.coins = 100
	b.interact(p)
	assert_int(int(r.current()["up_level"])).is_equal(1)
	assert_bool(r.current().has("attachments")).is_true()    # 换成了实例副本
	assert_bool(GameDB.get_weapon("laohuoji").has("up_level")).is_false()
	assert_bool(GameDB.get_weapon("laohuoji").has("attachments")).is_false()
	assert_int(RunState.coins).is_equal(65)


# ---------------------------------------------------------------- 3) 伤害乘区

func test_fire_slot_damage_multiplier_per_level() -> void:
	_inject_gun("bench_gun", 25)
	var r := _rig()
	var b := _bench()
	var player := r.get_parent() as Player
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(int(r.spawned[0]["damage"])).is_equal(25)     # L0 原伤零漂移
	r.spawned.clear()                                        # 捕获缓冲 append-only，逐拍清
	RunState.coins = 170
	b.interact(player)
	r.try_fire(Vector2.RIGHT, 100)
	assert_int(int(r.spawned[0]["damage"])).is_equal(27)     # round(25×1.08)
	r.spawned.clear()
	b.interact(player)
	r.try_fire(Vector2.RIGHT, 200)
	assert_int(int(r.spawned[0]["damage"])).is_equal(29)     # round(25×1.16)
	r.spawned.clear()
	b.interact(player)
	r.try_fire(Vector2.RIGHT, 300)
	assert_int(int(r.spawned[0]["damage"])).is_equal(31)     # round(25×1.24)


func test_scaled_damage_funnel_applies_up_level() -> void:
	# player.scaled_damage = 远程（talent_scaled_damage）与近战挥击（melee.gd）唯一
	# 共同漏斗——直测即覆盖双出口；无 rig/无 up_level 恒原伤零漂移。
	_inject_gun("bench_gun", 25)
	var r := _rig()
	var b := _bench()
	var player := r.get_parent() as Player
	assert_int(player.scaled_damage(25)).is_equal(25)        # L0
	RunState.coins = 170
	b.interact(player)
	assert_int(player.scaled_damage(25)).is_equal(27)
	b.interact(player)
	assert_int(player.scaled_damage(25)).is_equal(29)
	b.interact(player)
	assert_int(player.scaled_damage(25)).is_equal(31)
	var bare: Player = auto_free(Player.new())               # 无 rig（历史直调先例零漂移）
	bare._test_init()
	assert_int(bare.scaled_damage(25)).is_equal(25)


func test_attachment_dmg_first_then_up_level_round_chain() -> void:
	# 乘区次序（披露口径）：配件 dmg_pct 先 round 整数化（m5-c，_fire_slot 内联）→
	# up_level 后 round（scaled_damage 入口）→ 天赋/祝福。10 伤 + 伤害+10%：
	# att→up = round(round(10×1.1)×1.24)=round(11×1.24)=14（次序颠倒 = round(12×1.1)=13，
	# 本断言钉死「配件在先」口径）。
	_inject_gun("bench_gun", 10)
	var r := _rig()
	var b := _bench()
	var player := r.get_parent() as Player
	assert_dict(r.apply_attachment("att_muzzle_dmg10")).is_not_empty()
	RunState.coins = 170
	_upgrade_to(b, player, 3)
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(int(r.spawned[0]["damage"])).is_equal(14)
