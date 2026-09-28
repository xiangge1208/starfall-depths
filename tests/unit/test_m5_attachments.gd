class_name TestM5Attachments
extends GdUnitTestSuite
## m5-c 武器配件系统：12 条 3 槽（muzzle/mag/stock）契约测试。
## 1) schema/加载：12 条、稀有度白5/蓝4/橙3、槽位覆盖、id 自洽、GameDB 池零污染（weapons 仍 121）
## 2) 实例化拷贝：equip 后共享行无 attachments 键；run_root 式共享行直写槽位由
##    apply_attachment 兜底拷贝（严禁写 GameDB 共享缓存）
## 3) 同槽替换：重复拾取同槽 = 覆写且旧件消失；跨槽独立共存
## 4) 效果聚合直测 + _fire_slot 消费（RigProbe 捕获弹 cfg，test_weapon_rig 先例）：
##    三连发 +2 弹丸（不触发散弹扩张二次叠加）、dmg_pct round 先于 scaled_damage、
##    pierce/bounce flat、弹速/散布乘区、蓝耗 -25% 在 try_fire cost 处
## 5) 近战口径：muzzle 槽无效、mag 生效（挥击伤害/rate）
## 6) 冰霜弹匣主元素覆盖、折跃枪托 roll_boost 触发端
## 7) 商店第 4 货架（固定白/蓝/橙 30/60/120）、HUD「·」配件后缀、精英稀有度掷签

var _saved_weapons: Variant = null
var _seal: Dictionary = {}


func before_test() -> void:
	_seal = TestSaveSeal.seal("attachments")


func after_test() -> void:
	if _saved_weapons != null:
		GameDB.weapons = _saved_weapons
		_saved_weapons = null
	TestSaveSeal.restore(_seal)


# ---------------------------------------------------------------- 替身与桩

class RigProbe extends WeaponRig:
	var spawned: Array = []
	func _spawn(cfg: Dictionary) -> void:
		spawned.append(cfg)

class DummyBody extends Node2D:
	var hits: Array = []
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func combat_radius() -> float:
		return 6.0

## 商店 CsProbe 同款（m5-c 近战挥击伤害经 bodies_in_arc → take_hit 观察）
class CsProbe extends CombatSystem:
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
		return []

	func bodies_in_arc(_origin: Vector2, _facing: float, _range_px: float, _arc_deg: float, _faction: int) -> Array:
		return [scripted_body] if scripted_body != null else []

	func reflect(_p: Projectile, _dmg: int) -> void:
		pass

	func block(_p: Projectile) -> void:
		pass


func _rig() -> RigProbe:
	# 同 test_weapon_rig.gd 既定决议：auto_free 返回 Variant，:= 需显式类型标注
	var p: Player = auto_free(Player.new())
	p._test_init()
	var r := RigProbe.new()
	p.add_child(r)
	r._test_init()
	return r


func _inject_testgun(damage := 4, energy_cost := 0, projectiles := 1,
		spread_deg := 0.0, element := "none") -> void:
	if _saved_weapons == null:
		_saved_weapons = GameDB.weapons
	GameDB.weapons["att_testgun"] = {"id": "att_testgun", "name": "t", "category": "pistol",
		"rarity": "common", "damage": damage, "rate": 10.0, "energy_cost": energy_cost,
		"bullet_speed": 300, "spread_deg": spread_deg, "projectiles": projectiles,
		"pierce": 0, "bounce": 0, "element": element, "is_melee": false,
		"range": 0, "arc_deg": 0.0, "bullet_life": 1.2, "bullet_radius": 3.0, "muzzle": 8.0}


# ---------------------------------------------------------------- 1) schema/加载

func test_12_rows_loaded_with_slot_rarity_coverage() -> void:
	assert_int(GameDB.attachments.size()).is_equal(12)
	var by_rarity := {"common": 0, "rare": 0, "legend": 0}
	var by_slot := {"muzzle": 0, "mag": 0, "stock": 0}
	for id: String in GameDB.attachments:
		var row: Dictionary = GameDB.attachments[id]
		assert_str(String(row["id"])).is_equal(id)            # id 自洽
		assert_bool(GameDB.ATTACHMENT_RARITIES.has(row["rarity"])).is_true()
		assert_bool(GameDB.ATTACHMENT_SLOTS.has(row["slot"])).is_true()
		by_rarity[String(row["rarity"])] += 1
		by_slot[String(row["slot"])] += 1
	assert_int(by_rarity["common"]).is_equal(5)               # 白 5
	assert_int(by_rarity["rare"]).is_equal(4)                 # 蓝 4
	assert_int(by_rarity["legend"]).is_equal(3)               # 橙 3
	assert_int(by_slot["muzzle"]).is_equal(6)
	assert_int(by_slot["mag"]).is_equal(4)
	assert_int(by_slot["stock"]).is_equal(2)

func test_effects_keys_within_whitelist() -> void:
	var known: Array[String] = []
	known.append_array(GameDB.ATTACHMENT_PCT_KEYS)
	known.append_array(GameDB.ATTACHMENT_INT_KEYS)
	known.append_array(["roll_boost_pct", "roll_boost_ticks", "element_inject"])
	for id: String in GameDB.attachments:
		var eff: Dictionary = GameDB.attachments[id]["effects"]
		assert_int(eff.size()).is_greater(0)
		for k: String in eff:
			assert_array(known).contains(k)

func test_validate_attachment_row_fail_closed() -> void:
	var base := {"id": "x", "name": "x", "slot": "muzzle", "rarity": "common",
		"effects": {"dmg_pct": 0.1}}
	assert_array(GameDB.validate_attachment_row(base)).is_empty()
	assert_int(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "grip", "rarity": "common",
		"effects": {"dmg_pct": 0.1}}).size()).is_greater(0)                 # 坏槽位
	assert_int(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "muzzle", "rarity": "purple",
		"effects": {"dmg_pct": 0.1}}).size()).is_greater(0)                 # 坏稀有度
	assert_int(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "muzzle", "rarity": "common",
		"effects": {"haste_pct": 0.1}}).size()).is_greater(0)               # 白名单外键
	assert_int(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "muzzle", "rarity": "common",
		"effects": {"roll_boost_pct": 0.5}}).size()).is_greater(0)          # roll_boost 缺对
	assert_int(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "muzzle", "rarity": "common",
		"effects": {"element_inject": "music"}}).size()).is_greater(0)      # 非法元素名
	# 窗长键不吃通用 |v|≤10 护栏（90 = 1.5s 合法；崩引擎回归锚：协作者报告的 roll_boost_ticks 拦截）
	assert_array(GameDB.validate_attachment_row(
		{"id": "x", "name": "x", "slot": "stock", "rarity": "legend",
		"effects": {"roll_boost_pct": 0.5, "roll_boost_ticks": 90}})).is_empty()

func test_game_db_pool_zero_pollution() -> void:
	# 配件独立成表：weapons/weapons_all 数量与键空间零污染（m5-b 后基线 121）
	assert_int(GameDB.weapons_all.size()).is_equal(121)
	for id: String in GameDB.attachments:
		assert_bool(GameDB.weapons_all.has(id)).is_false()
	# 共享武器行无 attachments 键（实例化只发生在 equip/apply 兜底拷贝）
	assert_bool(GameDB.get_weapon("laohuoji").has("attachments")).is_false()

# ---------------------------------------------------------------- 2) 实例化 + 3) 同槽替换

func test_equip_instantiates_copy_shared_row_untouched() -> void:
	var r := _rig()
	r.equip("laohuoji")
	assert_bool(r.current().has("attachments")).is_true()
	r.apply_attachment("att_muzzle_dmg10")
	# 实例层挂上了，共享缓存行必须仍然干净
	assert_bool(GameDB.get_weapon("laohuoji").has("attachments")).is_false()
	assert_dict(GameDB.get_weapon("laohuoji")).contains_keys("damage")   # 行本身可读

func test_apply_attachment_same_slot_replaces_old_gone() -> void:
	var r := _rig()
	r.equip("laohuoji")
	assert_dict(r.apply_attachment("att_muzzle_dmg10")).is_not_empty()
	assert_str(String(r.current()["attachments"]["muzzle"])).is_equal("att_muzzle_dmg10")
	# 同槽重复拾取 = 替换，旧件消失（attachments 内不再有旧 id 引用）
	assert_dict(r.apply_attachment("att_muzzle_rate10")).is_not_empty()
	assert_str(String(r.current()["attachments"]["muzzle"])).is_equal("att_muzzle_rate10")
	var atts: Dictionary = r.current()["attachments"]
	for slot_name: String in atts:
		assert_str(String(atts[slot_name])).is_not_equal("att_muzzle_dmg10")
	# 跨槽独立共存
	r.apply_attachment("att_mag_frost")
	r.apply_attachment("att_stock_bounce1")
	assert_int((r.current()["attachments"] as Dictionary).size()).is_equal(3)

func test_apply_attachment_guards() -> void:
	var r := _rig()
	assert_dict(r.apply_attachment("att_muzzle_dmg10")).is_empty()      # 空槽（手刀态）拒装
	r.equip("laohuoji")
	assert_dict(r.apply_attachment("no_such_attachment")).is_empty()    # 未知 id 拒装

func test_apply_attachment_on_shared_row_does_not_pollute_gamedb() -> void:
	# run_root 对账路径直写共享行进槽（rig.slots[i] = GameDB 行）——apply 必须先实例化兜底
	var r := _rig()
	r.slots = [GameDB.get_weapon("laohuoji"), {}]
	r.slot = 0
	r.apply_attachment("att_muzzle_dmg10")
	assert_str(String(r.current()["attachments"]["muzzle"])).is_equal("att_muzzle_dmg10")
	assert_bool(GameDB.get_weapon("laohuoji").has("attachments")).is_false()

# ---------------------------------------------------------------- 4) 聚合 + _fire_slot 消费

func test_attachment_effects_aggregation() -> void:
	var r := _rig()
	r.equip("laohuoji")
	r.apply_attachment("att_muzzle_dmg10")       # dmg +0.10
	r.apply_attachment("att_mag_dmg20")          # dmg +0.20, rate -0.05
	r.apply_attachment("att_stock_bounce1")      # bounce +1
	var eff := r._attachment_effects(r.current())
	assert_float(float(eff["dmg_pct"])).is_equal_approx(0.30, 0.0001)   # 跨槽加法
	assert_float(float(eff["rate_pct"])).is_equal_approx(-0.05, 0.0001)
	assert_int(int(eff["bounce_flat"])).is_equal(1)
	# 近战口径：muzzle 槽整体无效（dmg 0.10 剔除，仅 mag 的 0.20）
	var eff_melee := r._attachment_effects(r.current(), true)
	assert_float(float(eff_melee["dmg_pct"])).is_equal_approx(0.20, 0.0001)
	assert_int(int(eff_melee["bounce_flat"])).is_equal(1)

func test_fire_slot_burst_projectiles_and_damage() -> void:
	_inject_testgun(4)                           # 伤害 4，单发
	var r := _rig()
	r.equip("att_testgun")
	r.apply_attachment("att_muzzle_burst")       # 三连发：+2 弹丸 / dmg -0.25
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(r.spawned.size()).is_equal(3)     # 1 + 2（一簇三连）
	for cfg: Dictionary in r.spawned:
		assert_int(int(cfg["damage"])).is_equal(3)   # round(4×0.75)=3 先于 scaled_damage
	# 配件弹丸不触发散弹扩张二次叠加：base_n=1 时散弹扩张仍不加成
	r.bonus_projectiles = 5
	r.spawned.clear()
	r.try_fire(Vector2.RIGHT, 100)
	assert_int(r.spawned.size()).is_equal(3)

func test_fire_slot_shotgun_expansion_gated_on_weapon_base_n() -> void:
	_inject_testgun(2, 0, 3, 30.0)               # base_n=3（散弹枪口径）
	var r := _rig()
	r.equip("att_testgun")
	r.bonus_projectiles = 2                      # 散弹扩张（base_n>1 门槛：生效）
	r.apply_attachment("att_muzzle_burst")       # +2
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(r.spawned.size()).is_equal(7)     # 3 + 2扩张 + 2配件

func test_fire_slot_pierce_and_speed_and_spread() -> void:
	_inject_testgun(2, 0, 2, 40.0)
	var r := _rig()
	r.equip("att_testgun")
	r.apply_attachment("att_muzzle_speed15")     # 弹速 +15%
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(r.spawned.size()).is_equal(2)
	for cfg: Dictionary in r.spawned:
		assert_float((cfg["vel"] as Vector2).length()).is_equal_approx(345.0, 0.0001)
		assert_int(int(cfg["pierce"])).is_equal(0)
	r.spawned.clear()
	r.apply_attachment("att_muzzle_pierce1")     # 同槽替换：穿甲 +1
	r.try_fire(Vector2.RIGHT, 100)
	assert_int(int(r.spawned[0]["pierce"])).is_equal(1)
	# 散布 -20%：40° → 32°（n=2 扇形两端角差；combat_rng 未注入零抖动）
	r.spawned.clear()
	r.apply_attachment("att_muzzle_spread20")
	r.try_fire(Vector2.RIGHT, 200)
	var a0: float = (r.spawned[0]["vel"] as Vector2).angle()
	var a1: float = (r.spawned[1]["vel"] as Vector2).angle()
	assert_float(absf(a1 - a0)).is_equal_approx(deg_to_rad(32.0), 0.0001)

func test_fire_slot_bounce_flat() -> void:
	_inject_testgun(2)
	var r := _rig()
	r.equip("att_testgun")
	r.apply_attachment("att_stock_bounce1")
	r.try_fire(Vector2.RIGHT, 0)
	assert_int(int(r.spawned[0]["bounce"])).is_equal(1)

func test_energy_pct_consumed_in_try_fire_cost() -> void:
	_inject_testgun(2, 4)                        # 蓝耗 4
	var r := _rig()
	r.equip("att_testgun")
	var p := r.get_parent() as Player
	p.energy = 3
	assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_false()   # 无配件：4 > 3 拒
	p.energy = 3
	r.apply_attachment("att_mag_energy25")       # 蓝耗 -25% → 3
	assert_bool(r.try_fire(Vector2.RIGHT, 0)).is_true()
	assert_int(p.energy).is_equal(0)             # ceil(4×0.75)=3 恰好付清

func test_rate_pct_in_effective_attack_rate() -> void:
	var r := _rig()
	r.equip("laohuoji")                          # rate 4.0
	r.apply_attachment("att_muzzle_rate10")
	var p := r.get_parent() as Player
	assert_float(r.effective_attack_rate(r.current(), p, 0)).is_equal_approx(4.4, 0.0001)

# ---------------------------------------------------------------- 5) 近战口径

func test_melee_mag_damage_applies_muzzle_ignored() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("tiejian"), {}]   # 铁剑 6 伤（共享行直写，run_root 同款路径）
	m.combat = auto_free(CsProbe.new())
	(m.combat as CsProbe).scripted_body = auto_free(DummyBody.new())
	m.rig.apply_attachment("att_mag_dmg20")            # mag：dmg +0.20 / rate -0.05
	m.rig.apply_attachment("att_muzzle_dmg10")         # muzzle：近战必须无效
	# 射速：近战口径 = 2.2 × (1-0.05)，muzzle 的 +10% 不参与
	assert_float(m.rig.effective_attack_rate(m.rig.current(), p, 0, true)) \
		.is_equal_approx(2.2 * 0.95, 0.0001)
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	var body: DummyBody = (m.combat as CsProbe).scripted_body
	assert_int(body.hits[0]["amount"]).is_equal(7)     # round(6×1.2)=7（muzzle +10% 未吃）

func test_melee_without_attachments_zero_drift() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var m: Melee = auto_free(Melee.new())
	p.add_child(m)
	m._test_init()
	m.rig = auto_free(WeaponRig.new())
	m.rig.slots = [GameDB.get_weapon("tiejian"), {}]
	m.combat = auto_free(CsProbe.new())
	(m.combat as CsProbe).scripted_body = auto_free(DummyBody.new())
	assert_bool(m.try_attack(0)).is_true()
	m._physics_process(1.0 / TimeConst.FPS)
	var body: DummyBody = (m.combat as CsProbe).scripted_body
	assert_int(body.hits[0]["amount"]).is_equal(6)     # 基线平伤（TTK-R 零漂移锚）

# ---------------------------------------------------------------- 6) 元素注入 + roll_boost

func test_frost_mag_overrides_native_element() -> void:
	_inject_testgun(2, 0, 1, 0.0, "fire")
	var r := _rig()
	r.equip("att_testgun")
	var profile := r.element_hit_profile(r.current(), 0)
	assert_int(int(profile["element"])).is_equal(Elements.Id.FIRE)
	r.apply_attachment("att_mag_frost")
	profile = r.element_hit_profile(r.current(), 0)
	assert_int(int(profile["element"])).is_equal(Elements.Id.ICE)   # 主元素覆盖为冰

func test_blink_stock_roll_boost_trigger() -> void:
	var r := _rig()
	r.equip("laohuoji")
	var p := r.get_parent() as Player
	r._trigger_roll_boost(p, 1000)
	assert_float(p.atk_speed_boost_pct).is_equal(0.0)  # 无折跃枪托：不触发
	assert_int(p.atk_speed_boost_until).is_equal(-1)
	r.apply_attachment("att_stock_blink")
	r._trigger_roll_boost(p, 1000)
	assert_float(p.atk_speed_boost_pct).is_equal(0.5)
	assert_int(p.atk_speed_boost_until).is_equal(1090) # 1000 + 90t（1.5s）
	# 轮询边沿：静止 → 滚动上升沿触发一次
	p.atk_speed_boost_pct = 0.0
	p.atk_speed_boost_until = -1
	p._roll_left = 0
	r._physics_process(1.0 / 60.0)                     # 静止帧：基线
	p._roll_left = 1                                   # 起滚
	var f := Engine.get_physics_frames()
	r._physics_process(1.0 / 60.0)
	assert_float(p.atk_speed_boost_pct).is_equal(0.5)
	assert_int(p.atk_speed_boost_until).is_greater_equal(int(f) + 89)
	p._roll_left = 0
	p.atk_speed_boost_pct = 0.0
	p.atk_speed_boost_until = -1
	r._physics_process(1.0 / 60.0)                     # 归零帧：吸收沿
	p._roll_left = 1
	f = Engine.get_physics_frames()
	r._physics_process(1.0 / 60.0)                     # 再次起滚：重新触发
	assert_float(p.atk_speed_boost_pct).is_equal(0.5)

# ---------------------------------------------------------------- 7) 商店第 4 货架 / HUD 后缀 / 精英掷签

class WalletProbe:
	var coins: int = 0
	var spent: Array[int] = []
	func spend_coins(n: int) -> bool:
		if coins < n:
			return false
		coins -= n
		spent.append(n)
		return true

func _shop_fixture(wallet: WalletProbe, with_weapon := true) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	if with_weapon:
		rig.equip("laohuoji")
	var stock := {"floor_idx": 1, "weapons": ["laohuoji", "maodingqiang", "duangong"],
		"items": [{"kind": "heart"}, {"kind": "energy"}], "drink": "shenmi_hunhe"}
	shop.open(stock, wallet, player, false)
	return {"shop": shop, "wallet": wallet, "player": player, "rig": rig, "stock": stock}

func test_shop_attachment_shelf_display_and_prices() -> void:
	var ctx := _shop_fixture(_wallet(500))
	var shop: Shop = ctx["shop"]
	assert_str(shop.attachment_name_text(0)).is_equal("锐利膛线")   # 白
	assert_str(shop.attachment_name_text(1)).is_equal("重装弹芯")   # 蓝
	assert_str(shop.attachment_name_text(2)).is_equal("三连发模块") # 橙
	assert_str(shop.attachment_price_text(0)).is_equal("30 金币")
	assert_str(shop.attachment_price_text(1)).is_equal("60 金币")
	assert_str(shop.attachment_price_text(2)).is_equal("120 金币")

func test_shop_attachment_buy_applies_to_current_weapon() -> void:
	var ctx := _shop_fixture(_wallet(500))
	var shop: Shop = ctx["shop"]
	var rig: WeaponRig = ctx["rig"]
	var wallet: WalletProbe = ctx["wallet"]
	shop._buy_attachment(1)                      # 蓝 60
	assert_bool(shop.attachment_sold(1)).is_true()
	assert_str(String(rig.current()["attachments"]["mag"])).is_equal("att_mag_dmg20")
	assert_array(wallet.spent).is_equal([60] as Array[int])
	# 同一 stock 字典重开保留售罄态（新字典=全新货架，契约同武器位）
	var stock: Dictionary = ctx["stock"]
	shop.open(stock, wallet, ctx["player"], false)
	assert_bool(shop.attachment_sold(1)).is_true()

func test_shop_attachment_rejects_when_broke_or_unarmed() -> void:
	var ctx := _shop_fixture(_wallet(10))
	var shop: Shop = ctx["shop"]
	shop._buy_attachment(0)                      # 余额不足
	assert_bool(shop.attachment_sold(0)).is_false()
	assert_array((ctx["wallet"] as WalletProbe).spent).is_empty()
	# 空槽（手刀态）先于扣款拒售
	var ctx2 := _shop_fixture(_wallet(500), false)
	(ctx2["shop"] as Shop)._buy_attachment(0)
	assert_bool((ctx2["shop"] as Shop).attachment_sold(0)).is_false()
	assert_array((ctx2["wallet"] as WalletProbe).spent).is_empty()

func _wallet(coins: int) -> WalletProbe:
	var w := WalletProbe.new()
	w.coins = coins
	return w

func test_hud_attachment_suffix() -> void:
	assert_str(HUD.attachment_suffix({})).is_empty()
	var r := _rig()
	r.equip("laohuoji")
	var p := r.get_parent() as Player
	p.weapon_rig = r                            # hud_snapshot 经 player.weapon_rig 寻址
	var run_stub: Node = auto_free(load("res://autoload/run_state.gd").new())
	r.apply_attachment("att_muzzle_dmg10")
	var snap := HUD.hud_snapshot(p, run_stub, 100)
	assert_array(snap["weapon_names"]).contains("老伙计·锐")
	r.apply_attachment("att_mag_dmg20")
	r.apply_attachment("att_stock_bounce1")
	snap = HUD.hud_snapshot(p, run_stub, 100)
	assert_array(snap["weapon_names"]).contains("老伙计·锐重弹")   # muzzle/mag/stock 序首字拼接

func test_elite_attachment_rarity_mapping() -> void:
	# 与同一掷签值自洽映射（70/25/5 分段）；FloorScene 实例重，static 纯函数直锚。
	# 口径：同种子下「探针抽 1 次」与「函数内抽 1 次」必须复放同一个 randf 值。
	var rng := RandomNumberGenerator.new()
	for i in 64:
		rng.seed = 20260929 + i
		var roll: float = rng.randf()          # 探针抽（首抽）
		rng.seed = 20260929 + i                # 重播种复放同一首抽
		var out := FloorScene.elite_attachment_rarity(rng)
		var expect := "common" if roll < 0.70 else ("rare" if roll < 0.95 else "legend")
		assert_str(out).is_equal(expect)
