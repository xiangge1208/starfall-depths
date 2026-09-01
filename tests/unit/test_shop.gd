class_name TestShop
extends GdUnitTestSuite
## m1-t14 商店 + 黑商 + 回收 契约测试。
## 1) ShopLogic.price：5 稀有度 × 3 层 × 黑/白 共 30 项逐项断言（基准表×floor 系数×黑市 1.8，取整到 5）
## 2) ShopLogic.recycle_price：×0.3×floor 系数，取整到 5，min 5
## 3) roll_weapon_id：§8.2 逐层权重（A1 70/25/5、A2 45/35/16/4、A3 25/33/25/13/4），
##    桶内均匀；固定 seed 1000 抽 common 65%~75%；exclude 生效；桶空向下回退；池枯返回 ""
## 4) roll_stock：形状（3 武器 + 2 道具 + 1 饮料 + floor_idx）、同 seed 确定性、exclude 生效
## 5) Shop UI（headless 实例化 shop.tscn）：开架/买武器（扣款+直装+已售）/余额不足闪红拒绝/
##    道具（红心 25→heal2、蓝瓶 20→+20 蓝）/第六饮料卡（GameDB 行文案/价格/效果/一次售罄）/
##    回收架（callable+add_coins 双门槛，+X金 入账）/
##    黑市标题与 ×1.8 价格 / Esc·按钮关店 / 同货架重开保留售罄·新货架重置 / interact 预设字段开层
## 金币接缝：wallet 为鸭子类型（coins:int + spend_coins(n)->bool [+ add_coins(n)]），
## 测试用 WalletProbe 桩注入——T15 RunState 落地后即满足该接缝。

const SEED := 20260828
const DRAWS := 1000

var _saved_weapons: Variant = null
## m2-t33 密闭（裁定㉔）：共享 save_headless.json + 运行时池逐用例隔离（顺序/残留无关）。
var _seal: Dictionary = {}


func before_test() -> void:
	_seal = TestSaveSeal.seal("shop")


# ---------------------------------------------------------------- 替身与桩

## 金币桩：duck-typed wallet（spend_coins + add_coins 双能力）。
class WalletProbe:
	var coins: int = 0
	var spent: Array[int] = []
	var added: Array[int] = []
	var observed_rng: RandomNumberGenerator = null
	var rng_state_at_spend: int = 0

	func spend_coins(n: int) -> bool:
		if observed_rng != null:
			rng_state_at_spend = observed_rng.state
		if coins < n:
			return false
		coins -= n
		spent.append(n)
		return true

	func add_coins(n: int) -> void:
		coins += n
		added.append(n)


## 无 add_coins 的钱包桩：验证回收卡隐藏路径。
class WalletNoAdd:
	var coins: int = 0

	func spend_coins(n: int) -> bool:
		if coins < n:
			return false
		coins -= n
		return true


func _stub_weapons(rows: Dictionary) -> void:
	_saved_weapons = GameDB.weapons
	GameDB.weapons = rows


func _stub_pool(nc: int, nu: int, nr: int, ne: int, nl: int) -> Dictionary:
	# 按稀有度批量造桩行（ShopLogic 仅读 id/rarity）
	var rows: Dictionary = {}
	for i in nc:
		rows["stub_c%d" % i] = {"id": "stub_c%d" % i, "rarity": "common"}
	for i in nu:
		rows["stub_u%d" % i] = {"id": "stub_u%d" % i, "rarity": "uncommon"}
	for i in nr:
		rows["stub_r%d" % i] = {"id": "stub_r%d" % i, "rarity": "rare"}
	for i in ne:
		rows["stub_e%d" % i] = {"id": "stub_e%d" % i, "rarity": "epic"}
	for i in nl:
		rows["stub_l%d" % i] = {"id": "stub_l%d" % i, "rarity": "legend"}
	return rows


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _stock(floor_idx: int, ids: Array[String], drink_id := "shenmi_hunhe") -> Dictionary:
	return {
		"floor_idx": floor_idx,
		"weapons": ids,
		"items": [{"kind": "heart"}, {"kind": "energy"}],
		"drink": drink_id,
	}


## 建店 + 开层替身：返回 {"shop": Shop, "wallet": WalletProbe, "player": Player, "rig": WeaponRig}
## （全部 auto_free / 已入树；武器 id 默认取真实表前 3 把 common）。
func _open_shop(black := false, wallet: Object = null) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	if wallet == null:
		var w := WalletProbe.new()
		w.coins = 500
		wallet = w
	shop.open(_stock(1, ["laohuoji", "maodingqiang", "duangong"]), wallet, player, black)
	return {"shop": shop, "wallet": wallet, "player": player, "rig": rig}


func after_test() -> void:
	if _saved_weapons != null:
		GameDB.weapons = _saved_weapons
		_saved_weapons = null
	TestSaveSeal.restore(_seal)


# ================================================================ 1) price 表

func test_price_common_floor1_is_20() -> void:
	assert_int(ShopLogic.price("common", 1, false)).is_equal(20)

func test_price_common_floor2_rounds_to_30() -> void:
	assert_int(ShopLogic.price("common", 2, false)).is_equal(30)

func test_price_common_floor3_rounds_to_50() -> void:
	assert_int(ShopLogic.price("common", 3, false)).is_equal(50)

func test_price_uncommon_floor1_42_rounds_to_40() -> void:
	assert_int(ShopLogic.price("uncommon", 1, false)).is_equal(40)

func test_price_uncommon_floor2_65() -> void:
	assert_int(ShopLogic.price("uncommon", 2, false)).is_equal(65)

func test_price_uncommon_floor3_110() -> void:
	assert_int(ShopLogic.price("uncommon", 3, false)).is_equal(110)

func test_price_rare_all_floors() -> void:
	assert_int(ShopLogic.price("rare", 1, false)).is_equal(85)
	assert_int(ShopLogic.price("rare", 2, false)).is_equal(135)
	assert_int(ShopLogic.price("rare", 3, false)).is_equal(220)

func test_price_epic_all_floors() -> void:
	assert_int(ShopLogic.price("epic", 1, false)).is_equal(155)
	assert_int(ShopLogic.price("epic", 2, false)).is_equal(250)
	assert_int(ShopLogic.price("epic", 3, false)).is_equal(395)

func test_price_legend_all_floors() -> void:
	assert_int(ShopLogic.price("legend", 1, false)).is_equal(260)
	assert_int(ShopLogic.price("legend", 2, false)).is_equal(415)
	assert_int(ShopLogic.price("legend", 3, false)).is_equal(665)

func test_price_black_multiplies_then_rounds_to_5() -> void:
	# 黑市 ×1.8：common 20→36→35；uncommon 42→75.6→75；rare 85→153→155；
	# epic 155→279→280；legend 260→468→470（均为 floor1）
	assert_int(ShopLogic.price("common", 1, true)).is_equal(35)
	assert_int(ShopLogic.price("uncommon", 1, true)).is_equal(75)
	assert_int(ShopLogic.price("rare", 1, true)).is_equal(155)
	assert_int(ShopLogic.price("epic", 1, true)).is_equal(280)
	assert_int(ShopLogic.price("legend", 1, true)).is_equal(470)

func test_price_black_deep_floors() -> void:
	# common f2: 20×1.6×1.8=57.6→60；common f3: 92.16→90
	assert_int(ShopLogic.price("common", 2, true)).is_equal(60)
	assert_int(ShopLogic.price("common", 3, true)).is_equal(90)
	# uncommon f3: 42×2.56×1.8=193.536→195
	assert_int(ShopLogic.price("uncommon", 3, true)).is_equal(195)
	# rare f2: 85×1.6×1.8=244.8→245；rare f3: 391.68→390
	assert_int(ShopLogic.price("rare", 2, true)).is_equal(245)
	assert_int(ShopLogic.price("rare", 3, true)).is_equal(390)
	# epic f2: 446.4→445；epic f3: 714.24→715
	assert_int(ShopLogic.price("epic", 2, true)).is_equal(445)
	assert_int(ShopLogic.price("epic", 3, true)).is_equal(715)
	# legend f2: 748.8→750；legend f3: 1198.08→1200
	assert_int(ShopLogic.price("legend", 2, true)).is_equal(750)
	assert_int(ShopLogic.price("legend", 3, true)).is_equal(1200)

func test_price_floor_idx_clamped() -> void:
	# 越界层号夹取到 [1,3]：floor 0 → ×1.0；floor 99 → ×2.56
	assert_int(ShopLogic.price("common", 0, false)).is_equal(20)
	assert_int(ShopLogic.price("common", 99, false)).is_equal(50)

func test_price_unknown_rarity_falls_back_to_common_base() -> void:
	# 防御性：未知稀有度按 common 基准计价（不崩溃）
	assert_int(ShopLogic.price("bogus", 1, false)).is_equal(20)

func test_price_result_always_multiple_of_5() -> void:
	var rarities: Array[String] = ["common", "uncommon", "rare", "epic", "legend"]
	for r: String in rarities:
		for f: int in [1, 2, 3]:
			for black: bool in [true, false]:
				var p := ShopLogic.price(r, f, black)
				assert_int(p % 5).is_equal(0)


# ================================================================ 2) recycle_price

func test_recycle_price_is_30pct_floormult_round5_min5() -> void:
	assert_int(ShopLogic.recycle_price("common", 1)).is_equal(5)      # 20×0.3=6→1.2→5
	assert_int(ShopLogic.recycle_price("common", 2)).is_equal(10)     # 9.6→1.92→10
	assert_int(ShopLogic.recycle_price("common", 3)).is_equal(15)     # 15.36→3.072→15
	assert_int(ShopLogic.recycle_price("uncommon", 1)).is_equal(15)   # 12.6→2.52→15
	assert_int(ShopLogic.recycle_price("uncommon", 2)).is_equal(20)   # 20.16→4.032→20
	assert_int(ShopLogic.recycle_price("rare", 1)).is_equal(25)       # 25.5→5.1→25
	assert_int(ShopLogic.recycle_price("rare", 2)).is_equal(40)       # 40.8→8.16→40
	assert_int(ShopLogic.recycle_price("epic", 1)).is_equal(45)       # 46.5→9.3→45
	assert_int(ShopLogic.recycle_price("epic", 3)).is_equal(120)      # 119.04→23.808→120
	assert_int(ShopLogic.recycle_price("legend", 1)).is_equal(80)     # 78→15.6→80
	assert_int(ShopLogic.recycle_price("legend", 3)).is_equal(200)    # 199.68→39.936→200

func test_recycle_price_floor_clamped() -> void:
	assert_int(ShopLogic.recycle_price("common", -1)).is_equal(5)
	assert_int(ShopLogic.recycle_price("common", 7)).is_equal(15)


# ================================================================ 3) roll_weapon_id

func test_roll_weapon_distribution_floor1_a1_weights() -> void:
	# §8.2 A1 行 70/25/5/0/0：固定 seed 1000 抽 common 落 65%~75%
	_stub_weapons(_stub_pool(7, 3, 2, 1, 1))
	var rng := _rng(SEED)
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legend": 0}
	var exclude: Array[String] = []
	for i in DRAWS:
		var id := ShopLogic.roll_weapon_id(rng, 1, exclude)
		assert_bool(counts.has(GameDB.weapons[id]["rarity"])).is_true()
		counts[GameDB.weapons[id]["rarity"]] = int(counts[GameDB.weapons[id]["rarity"]]) + 1
	assert_int(int(counts["common"])).is_between(650, 750)
	assert_int(int(counts["uncommon"])).is_between(200, 300)
	assert_int(int(counts["rare"])).is_between(20, 80)
	assert_int(int(counts["epic"])).is_equal(0)
	assert_int(int(counts["legend"])).is_equal(0)

func test_roll_weapon_floor2_can_drop_epic_floor3_legend() -> void:
	# A2 行含 epic 4% / A3 行含 legend 4%（有池时真实掉出）
	_stub_weapons(_stub_pool(6, 4, 3, 2, 1))
	var epic_hits := 0
	var rng := _rng(SEED)
	var exclude: Array[String] = []
	for i in DRAWS:
		var id := ShopLogic.roll_weapon_id(rng, 2, exclude)
		if id == "stub_e0" or id == "stub_e1":
			epic_hits += 1
	assert_int(epic_hits).is_between(15, 65)          # epic 桶合计名义 4%：40±3σ
	var legend_hits := 0
	rng = _rng(SEED)
	for i in DRAWS:
		if ShopLogic.roll_weapon_id(rng, 3, exclude) == "stub_l0":
			legend_hits += 1
	assert_int(legend_hits).is_between(15, 65)        # legend 桶单把名义 4%

func test_roll_weapon_m1_data_all_common_falls_down_to_common() -> void:
	# 真实 M1 表（6 把全 common）：uncommon/rare 桶空 → 向下回退到 common，
	# 100 抽全部落在真实 id 集内
	var rng := _rng(SEED)
	var real_ids: Array[String] = []
	for id: String in GameDB.weapons:
		real_ids.append(id)
	var exclude: Array[String] = []
	for i in 100:
		var id := ShopLogic.roll_weapon_id(rng, 1, exclude)
		assert_bool(real_ids.has(id)).is_true()

func test_roll_weapon_exclusion_respected_and_fallback_down() -> void:
	# exclude 掉全部 rare：roll 中 rare（5%）时向下回退 uncommon；绝不返回被排除 id
	_stub_weapons(_stub_pool(3, 2, 1, 0, 0))
	var rng := _rng(SEED)
	var exclude: Array[String] = ["stub_r0"]
	for i in 300:
		var id := ShopLogic.roll_weapon_id(rng, 1, exclude)
		assert_str(id).is_not_equal("stub_r0")

func test_roll_weapon_pool_dry_returns_empty_string() -> void:
	# 桩池仅 1 把 rare 且被排除 → 向下无桶可落 → ""（池枯哨兵，调用方跳过该卡）
	_stub_weapons(_stub_pool(0, 0, 1, 0, 0))
	var rng := _rng(SEED)
	var exclude: Array[String] = ["stub_r0"]
	assert_str(ShopLogic.roll_weapon_id(rng, 1, exclude)).is_equal("")

func test_roll_weapon_uniform_within_bucket() -> void:
	# 桶内均匀：桩池仅 3 把 common → 高稀有度 roll 全部向下回退，
	# 1000 抽全落 common 桶，各约 1/3（333 ± 3.5σ）
	_stub_weapons(_stub_pool(3, 0, 0, 0, 0))
	var rng := _rng(SEED)
	var hits := {"stub_c0": 0, "stub_c1": 0, "stub_c2": 0}
	var exclude: Array[String] = []
	for i in DRAWS:
		var id := ShopLogic.roll_weapon_id(rng, 1, exclude)
		hits[id] = int(hits[id]) + 1
	for id: String in hits:
		assert_int(int(hits[id])).is_between(278, 392)


# ================================================================ 4) roll_stock

func test_roll_stock_shape() -> void:
	var stock := ShopLogic.roll_stock(_rng(SEED), 2, [])
	assert_int(int(stock.get("floor_idx", 0))).is_equal(2)
	var weapons: Array = stock.get("weapons", [])
	assert_int(weapons.size()).is_equal(3)
	# 3 把互不重复且都在真实表内
	var real_ids: Array[String] = []
	for id: String in GameDB.weapons:
		real_ids.append(id)
	var uniq := {}
	for id: Variant in weapons:
		uniq[id] = true
		assert_bool(real_ids.has(id)).is_true()
	assert_int(uniq.size()).is_equal(3)
	var items: Array = stock.get("items", [])
	assert_int(items.size()).is_equal(2)
	assert_str(String(items[0].get("kind", ""))).is_equal("heart")
	assert_str(String(items[1].get("kind", ""))).is_equal("energy")
	assert_str(String(stock.get("drink", ""))).is_equal("shenmi_hunhe")

func test_black_stock_prefers_epic_then_rare() -> void:
	# 密封化（df9691a 先例）：无头共享档 save_headless.json 的图鉴解锁会经
	# CodexSystem.grant_to_pool 回池，破坏「紫全锁」前提——桩表固定池保证确定性。
	_stub_weapons(_stub_pool(4, 4, 4, 2, 0))
	var stock := ShopLogic.roll_stock(_rng(SEED), 1, [], true)
	assert_int((stock["weapons"] as Array).size()).is_equal(3)
	for id: String in stock["weapons"]:
		assert_bool(["epic", "rare"].has(String(GameDB.get_weapon(id)["rarity"]))).is_true()

func test_roll_stock_deterministic_same_seed() -> void:
	var a := ShopLogic.roll_stock(_rng(SEED), 1, [])
	var b := ShopLogic.roll_stock(_rng(SEED), 1, [])
	assert_array(a.get("weapons", []) as Array).is_equal(b.get("weapons", []))

func test_roll_stock_respects_exclude_and_stays_unique() -> void:
	# 排除池内 4 把 → 池剩 2 把：货架 2 把（第 3 抽池枯跳过）且互不重复。
	# t25 扩池后真实表 40 把不再池枯（原「真实表前 4 把」写法绑死了表大小），
	# 改用本套件既有的桩表机制固定 6 把池，保持原语义不变（_stub_weapons 由 after_test 还原）。
	_stub_weapons(_stub_pool(6, 0, 0, 0, 0))
	var exclude: Array[String] = ["stub_c0", "stub_c1", "stub_c2", "stub_c3"]
	var stock := ShopLogic.roll_stock(_rng(SEED), 1, exclude)
	var weapons: Array = stock.get("weapons", [])
	assert_int(weapons.size()).is_equal(2)
	for id: Variant in weapons:
		assert_bool(exclude.has(id)).is_false()


# ================================================================ 5) Shop UI（headless）

func test_shop_is_interactable_and_joins_group() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	assert_bool(shop is Interactable).is_true()
	assert_bool(shop.is_in_group(InteractionSystem.GROUP)).is_true()

func test_open_populates_cards_and_labels() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	assert_bool(shop.ui_visible()).is_true()
	assert_str(shop.title_text()).is_equal("商店")
	assert_str(shop.weapon_name_text(0)).is_equal("老伙计")
	assert_str(shop.weapon_name_text(1)).is_equal("铆钉枪")
	assert_str(shop.weapon_name_text(2)).is_equal("短弓")
	# common × floor1 × 非黑 = 20
	assert_str(shop.weapon_price_text(0)).is_equal("20 金币")
	assert_str(shop.coins_text()).is_equal("500 金币")
	assert_str(shop.item_price_text("heart")).is_equal("25 金币")
	assert_str(shop.item_price_text("energy")).is_equal("20 金币")
	assert_bool(shop.drink_visible()).is_true()
	assert_str(shop.drink_id()).is_equal("shenmi_hunhe")
	assert_str(shop.drink_name_text()).is_equal("神秘混合")
	assert_str(shop.drink_effect_text()).is_equal("随机一条上述效果")
	assert_str(shop.drink_price_text()).is_equal("20 金币")
	assert_bool(shop.recycle_visible()).is_false()

func test_drink_card_reads_concrete_game_db_row_verbatim() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	shop.open(_stock(1, ["laohuoji", "maodingqiang", "duangong"], "shengming_soda"),
		ctx["wallet"], ctx["player"], false)
	assert_str(shop.drink_id()).is_equal("shengming_soda")
	assert_str(shop.drink_name_text()).is_equal("生命苏打")
	assert_str(shop.drink_effect_text()).is_equal("HP上限+2")
	assert_str(shop.drink_price_text()).is_equal("30 金币")

func test_drink_card_hidden_for_missing_or_invalid_stock_id() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	shop.open(_stock(1, ["laohuoji"], ""), ctx["wallet"], ctx["player"], false)
	assert_bool(shop.drink_visible()).is_false()
	shop.open(_stock(1, ["laohuoji"], "not_in_game_db"),
		ctx["wallet"], ctx["player"], false)
	assert_bool(shop.drink_visible()).is_false()

func test_open_uses_floor_idx_from_stock_for_prices() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	var wallet := WalletProbe.new()
	wallet.coins = 500
	shop.open(_stock(2, ["laohuoji", "maodingqiang", "duangong"]), wallet, player, false)
	# common × floor2 (×1.6) = 32 → 取整到 30
	assert_str(shop.weapon_price_text(0)).is_equal("30 金币")

func test_black_variant_title_and_price() -> void:
	var ctx := _open_shop(true)
	var shop: Shop = ctx["shop"]
	assert_str(shop.title_text()).is_equal("黑市商人")
	# common ×1.8 → 36 → 35
	assert_str(shop.weapon_price_text(0)).is_equal("35 金币")
	# 道具价为规格固定常量（25/20），不吃黑市/floor 系数（控制器规格明示，披露）
	assert_str(shop.item_price_text("heart")).is_equal("25 金币")
	assert_str(shop.item_price_text("energy")).is_equal("20 金币")

func test_buy_weapon_success_spends_equips_marks_sold() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var rig: WeaponRig = ctx["rig"]
	shop._buy_weapon(0)
	assert_int(wallet.spent.size()).is_equal(1)
	assert_int(wallet.spent[0]).is_equal(20)
	assert_int(wallet.coins).is_equal(480)
	assert_str(String(rig.slots[0].get("id", ""))).is_equal("laohuoji")
	assert_bool(shop.is_sold(0)).is_true()
	assert_str(shop.weapon_price_text(0)).is_equal("已售")
	assert_str(shop.coins_text()).is_equal("480 金币")

func test_buy_weapon_insufficient_funds_rejected() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var rig: WeaponRig = ctx["rig"]
	wallet.coins = 5
	shop._buy_weapon(0)
	assert_int(wallet.spent.size()).is_equal(0)
	assert_int(wallet.coins).is_equal(5)
	assert_int(rig.slots[0].size()).is_equal(0)
	assert_bool(shop.is_sold(0)).is_false()

func test_buy_weapon_twice_charges_once() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	shop._buy_weapon(1)
	shop._buy_weapon(1)
	assert_int(wallet.spent.size()).is_equal(1)
	assert_int(wallet.coins).is_equal(480)

func test_buy_weapon_direct_equip_fills_first_empty_slot() -> void:
	# M1 简化：买入直接 equip（首填空槽，两槽满则替换当前槽——rig 既有契约）
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var rig: WeaponRig = ctx["rig"]
	rig.equip("tiejian")
	shop._buy_weapon(2)
	assert_str(String(rig.slots[0].get("id", ""))).is_equal("tiejian")
	assert_str(String(rig.slots[1].get("id", ""))).is_equal("duangong")

func test_buy_heart_heals_2_for_25() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	player.hp = 3
	shop._buy_item("heart")
	assert_int(player.hp).is_equal(5)
	assert_int(wallet.coins).is_equal(475)
	assert_bool(shop.item_sold("heart")).is_true()

func test_buy_energy_adds_20_for_20() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	player.energy = 10
	shop._buy_item("energy")
	assert_int(player.energy).is_equal(30)
	assert_int(wallet.coins).is_equal(480)
	assert_bool(shop.item_sold("energy")).is_true()

func test_buy_item_insufficient_funds_rejected() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	wallet.coins = 10
	player.hp = 3
	shop._buy_item("heart")
	assert_int(player.hp).is_equal(3)
	assert_int(wallet.coins).is_equal(10)
	assert_bool(shop.item_sold("heart")).is_false()

func test_heal_clamped_at_max_hp() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var player: Player = ctx["player"]
	player.hp = 7
	shop._buy_item("heart")
	assert_int(player.hp).is_equal(8)   # heal 上限夹取（player.heal 既有契约）

func test_buy_drink_success_uses_row_price_applies_effect_and_sells_once() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	shop.open(_stock(1, ["laohuoji", "maodingqiang", "duangong"], "shengming_soda"),
		wallet, player, false)
	shop._buy_drink()
	assert_int(wallet.spent.size()).is_equal(1)
	assert_int(wallet.spent[0]).is_equal(30)
	assert_int(wallet.coins).is_equal(470)
	assert_int(player.hp_max).is_equal(10)
	assert_bool(shop.drink_sold()).is_true()
	assert_str(shop.drink_price_text()).is_equal("已售")
	# 同一开架只售一杯：再次点击不再扣款，也不重复落地效果。
	shop._buy_drink()
	assert_int(wallet.spent.size()).is_equal(1)
	assert_int(wallet.coins).is_equal(470)
	assert_int(player.hp_max).is_equal(10)

func test_buy_drink_insufficient_funds_has_no_side_effect_and_flashes_red() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	wallet.coins = 29
	shop.open(_stock(1, ["laohuoji"], "shengming_soda"), wallet, player, false)
	shop._buy_drink()
	assert_int(wallet.spent.size()).is_equal(0)
	assert_int(wallet.coins).is_equal(29)
	assert_int(player.hp_max).is_equal(8)
	assert_bool(shop.drink_sold()).is_false()
	assert_str(shop.drink_price_text()).is_equal("30 金币")
	assert_that(shop.drink_price_color()).is_equal(Shop.FAIL_FLASH)

func test_new_stock_resets_drink_sold_state() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	shop.open(_stock(1, ["laohuoji"], "shengming_soda"),
		wallet, ctx["player"], false)
	shop._buy_drink()
	assert_bool(shop.drink_sold()).is_true()
	shop.open(_stock(1, ["laohuoji"], "yingyan_kafei"),
		wallet, ctx["player"], false)
	assert_bool(shop.drink_sold()).is_false()
	assert_str(shop.drink_id()).is_equal("yingyan_kafei")
	assert_str(shop.drink_name_text()).is_equal("鹰眼咖啡")
	assert_str(shop.drink_effect_text()).is_equal("暴击+3%")
	assert_str(shop.drink_price_text()).is_equal("35 金币")

func test_mystery_drink_insufficient_funds_does_not_advance_rng() -> void:
	# 支付失败必须是完整 no-op：连随机流也不得掷签/推进。
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	wallet.coins = 19
	shop.open(_stock(1, ["laohuoji"], "shenmi_hunhe"),
		wallet, ctx["player"], false)
	var rng := _rng(141416)
	shop.drink_rng = rng
	var state_before := rng.state
	wallet.observed_rng = rng
	shop._buy_drink()
	assert_int(wallet.rng_state_at_spend).is_equal(state_before)
	assert_int(rng.state).is_equal(state_before)
	assert_int(wallet.coins).is_equal(19)
	assert_bool(shop.drink_sold()).is_false()

func test_mystery_drink_success_advances_rng_after_payment() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	wallet.coins = 20
	shop.open(_stock(1, ["laohuoji"], "shenmi_hunhe"),
		wallet, ctx["player"], false)
	var rng := _rng(141416)
	shop.drink_rng = rng
	var state_before := rng.state
	wallet.observed_rng = rng
	shop._buy_drink()
	# 精确证明顺序：钱包执行支付时 RNG 尚未推进；支付返回成功后才掷签。
	assert_int(wallet.rng_state_at_spend).is_equal(state_before)
	assert_int(rng.state).is_not_equal(state_before)
	assert_int(wallet.coins).is_equal(0)
	assert_bool(shop.drink_sold()).is_true()

func test_shop_drink_sale_does_not_consume_independent_machine_uses() -> void:
	# GDD §11 的第六货位与 §13.2 的独立饮料机并存：商店售罄不能偷扣机器 3 次额度。
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var player: Player = ctx["player"]
	var machine_state := {"uses_left": DrinkMachine.USES_PER_FLOOR}
	var machine: DrinkMachine = auto_free(DrinkMachine.new())
	machine.configure(machine_state, wallet)
	shop.open(_stock(1, ["laohuoji"], "jifeng_bohe"), wallet, player, false)
	shop._buy_drink()
	assert_bool(shop.drink_sold()).is_true()
	assert_int(machine.uses_left).is_equal(DrinkMachine.USES_PER_FLOOR)
	assert_int(machine_state["uses_left"]).is_equal(DrinkMachine.USES_PER_FLOOR)
	# 机器随后仍能独立购买并只消费自己的 1 次。
	machine.open(machine_state, wallet, player)
	var machine_idx := machine.drink_ids().find("jifeng_bohe")
	assert_bool(machine.buy(machine_idx)).is_true()
	assert_int(machine.uses_left).is_equal(DrinkMachine.USES_PER_FLOOR - 1)
	assert_int(machine_state["uses_left"]).is_equal(DrinkMachine.USES_PER_FLOOR - 1)

func test_recycle_visible_only_with_callable_and_add_coins() -> void:
	# 三门槛：callable 有效 + wallet 有 add_coins → 显示；缺一 → 隐藏
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var rig: WeaponRig = ctx["rig"]
	rig.equip("tiejian")
	rig.equip("shuangbi")
	var calls: Array[Dictionary] = []
	var cb: Callable = func(_p: Node2D) -> Dictionary:
		var info := {"id": "shuangbi", "name": "双匕", "rarity": "common"}
		calls.append(info)
		return info
	# 回收架在 open 填架时结算可见性（接线约定：字段先注入后 open），注入后重开一次
	shop.drop_weapon = cb
	shop.open(_stock(1, ["laohuoji", "maodingqiang", "duangong"]),
		ctx["wallet"], ctx["player"], false, cb)
	assert_bool(shop.recycle_visible()).is_true()
	assert_str(shop.recycle_label_text()).is_equal("回收副手 +5金")   # common×f1 回收 = 5
	# 无 add_coins 的 wallet → 隐藏
	var root2: Node2D = auto_free(Node2D.new())
	add_child(root2)
	var shop2: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root2.add_child(shop2)
	var player2: Player = auto_free(Player.new())
	root2.add_child(player2)
	var rig2: WeaponRig = auto_free(WeaponRig.new())
	rig2._test_init()
	player2.weapon_rig = rig2
	shop2.open(_stock(1, ["laohuoji"]), WalletNoAdd.new(), player2, false, cb)
	assert_bool(shop2.recycle_visible()).is_false()
	# callable 缺省 → 隐藏（ctx 店换空 callable 重开）
	shop.drop_weapon = Callable()
	shop.open(_stock(1, ["laohuoji"]), ctx["wallet"], ctx["player"], false)
	assert_bool(shop.recycle_visible()).is_false()

func test_recycle_credits_wallet_and_hides_card() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var calls: Array[Dictionary] = []
	var cb: Callable = func(_p: Node2D) -> Dictionary:
		var info := {"id": "shuangbi", "name": "双匕", "rarity": "common"}
		calls.append(info)
		return info
	shop.drop_weapon = cb
	shop._recycle()
	assert_int(calls.size()).is_equal(1)
	assert_int(wallet.added.size()).is_equal(1)
	assert_int(wallet.added[0]).is_equal(5)
	assert_bool(shop.recycle_visible()).is_false()
	# 再点不再入账（一次性）
	shop._recycle()
	assert_int(wallet.added.size()).is_equal(1)

func test_close_hides_and_esc_closes() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	shop.close()
	assert_bool(shop.ui_visible()).is_false()
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	shop._unhandled_input(ev)
	# 未开层时 Esc 不生效也无害；开层后 Esc 关闭
	shop.open(_stock(1, ["laohuoji"]), ctx["wallet"], ctx["player"], false)
	assert_bool(shop.ui_visible()).is_true()
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_ESCAPE
	ev2.pressed = true
	shop._unhandled_input(ev2)
	assert_bool(shop.ui_visible()).is_false()

func test_close_button_closes() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	shop._close()
	assert_bool(shop.ui_visible()).is_false()

func test_new_stock_resets_weapon_sold_state() -> void:
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	shop._buy_weapon(0)
	assert_bool(shop.is_sold(0)).is_true()
	shop.open(_stock(1, ["laohuoji", "maodingqiang", "duangong"]), wallet, ctx["player"], false)
	assert_bool(shop.is_sold(0)).is_false()
	assert_str(shop.weapon_price_text(0)).is_equal("20 金币")

func test_same_stock_close_and_interact_preserves_all_consumed_state() -> void:
	# 生产路径：InteractionSystem 再按 E → interact(player) → open(shop.stock, ...)。
	# 同一货架关闭/重开不得让武器、道具、饮料或回收架复活。
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	player.hp = 3
	player.energy = 10
	var wallet := WalletProbe.new()
	wallet.coins = 1000
	var recycle_calls: Array[int] = []
	var cb: Callable = func(_p: Node2D) -> Dictionary:
		recycle_calls.append(1)
		return {"id": "shuangbi", "name": "双匕", "rarity": "common"}
	var same_stock := _stock(1, ["laohuoji", "maodingqiang", "duangong"],
		"shengming_soda")
	shop.open(same_stock, wallet, player, false, cb)
	shop._buy_weapon(0)
	shop._buy_item("heart")
	shop._buy_item("energy")
	shop._buy_drink()
	shop._recycle()
	assert_int(recycle_calls.size()).is_equal(1)
	var coins_after_first_pass := wallet.coins
	var hp_after_first_pass := player.hp
	var energy_after_first_pass := player.energy
	var hp_max_after_first_pass := player.hp_max
	shop.close()
	shop.interact(player)
	assert_bool(shop.is_sold(0)).is_true()
	assert_str(shop.weapon_price_text(0)).is_equal("已售")
	assert_bool(shop.item_sold("heart")).is_true()
	assert_bool(shop.item_sold("energy")).is_true()
	assert_str(shop.item_price_text("heart")).is_equal("已售")
	assert_str(shop.item_price_text("energy")).is_equal("已售")
	assert_bool(shop.drink_sold()).is_true()
	assert_str(shop.drink_price_text()).is_equal("已售")
	assert_bool(shop.recycle_visible()).is_false()
	# 尝试重购/重回收仍必须 no-op。
	shop._buy_weapon(0)
	shop._buy_item("heart")
	shop._buy_item("energy")
	shop._buy_drink()
	shop._recycle()
	assert_int(wallet.coins).is_equal(coins_after_first_pass)
	assert_int(player.hp).is_equal(hp_after_first_pass)
	assert_int(player.energy).is_equal(energy_after_first_pass)
	assert_int(player.hp_max).is_equal(hp_max_after_first_pass)
	assert_int(recycle_calls.size()).is_equal(1)

func test_fresh_identical_stock_resets_all_consumed_state() -> void:
	# 新货架即使内容碰巧相同，只要是新注入的库存字典，也应有全新售卖/回收状态。
	var ctx := _open_shop()
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	var cb: Callable = func(_p: Node2D) -> Dictionary:
		return {"id": "shuangbi", "name": "双匕", "rarity": "common"}
	var first_stock := _stock(1, ["laohuoji", "maodingqiang", "duangong"],
		"shengming_soda")
	shop.open(first_stock, wallet, ctx["player"], false, cb)
	shop._buy_weapon(0)
	shop._buy_item("heart")
	shop._buy_item("energy")
	shop._buy_drink()
	shop._recycle()
	var fresh_but_identical := _stock(1, ["laohuoji", "maodingqiang", "duangong"],
		"shengming_soda")
	shop.open(fresh_but_identical, wallet, ctx["player"], false, cb)
	assert_bool(shop.is_sold(0)).is_false()
	assert_str(shop.weapon_price_text(0)).is_equal("20 金币")
	assert_bool(shop.item_sold("heart")).is_false()
	assert_bool(shop.item_sold("energy")).is_false()
	assert_str(shop.item_price_text("heart")).is_equal("25 金币")
	assert_str(shop.item_price_text("energy")).is_equal("20 金币")
	assert_bool(shop.drink_sold()).is_false()
	assert_str(shop.drink_price_text()).is_equal("30 金币")
	assert_bool(shop.recycle_visible()).is_true()

func test_interact_opens_with_preset_fields() -> void:
	# 房间接线约定：FloorScene 注入 stock/wallet/black/drop_weapon 字段后，
	# InteractionSystem 走 interact(player) → open 同参开层
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var shop: Shop = auto_free((load("res://core/interact/shop.tscn") as PackedScene).instantiate())
	root.add_child(shop)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	var wallet := WalletProbe.new()
	wallet.coins = 60
	shop.stock = _stock(1, ["laohuoji", "maodingqiang", "duangong"])
	shop.wallet = wallet
	shop.black = true
	shop.interact(player)
	assert_bool(shop.ui_visible()).is_true()
	assert_str(shop.title_text()).is_equal("黑市商人")
	assert_str(shop.coins_text()).is_equal("60 金币")

func test_black_affects_actual_charge_not_just_label() -> void:
	# 黑市购买实扣 ×1.8 价（非仅展示）
	var ctx := _open_shop(true)
	var shop: Shop = ctx["shop"]
	var wallet: WalletProbe = ctx["wallet"]
	shop._buy_weapon(0)
	assert_int(wallet.coins).is_equal(465)   # 500 - 35


# ================================================================ m2-audit 补录

func test_roll_weapon_source_rows_chest_and_elite() -> void:
	# m2-audit：§8.2 非按层来源行——宝箱房 30/35/22/10/3、精英房奖励 10/30/35/20/5。
	# 五档全桩池下固定 seed 连抽，两源各自五档均可达（最低档权重 3%，400 抽缺席
	# 概率 ~0.95^400 ≈ 1.3e-9）；combat 缺省口径不变（A1 行无紫橙，桩池下紫橙仅
	# 可经 chest/elite 源出现）。
	_stub_weapons(_stub_pool(1, 1, 1, 1, 1))
	var rng := _rng(SEED)
	var chest := {}
	var elite := {}
	var combat_epic_or_legend := false
	for i in 400:
		chest[ShopLogic.roll_weapon_id(rng, 1, [], "chest")] = true
		elite[ShopLogic.roll_weapon_id(rng, 1, [], "elite")] = true
		var c := ShopLogic.roll_weapon_id(rng, 1, [], "combat")
		if c == "stub_e0" or c == "stub_l0":
			combat_epic_or_legend = true
	for id in ["stub_c0", "stub_u0", "stub_r0", "stub_e0", "stub_l0"]:
		assert_bool(chest.has(id)).is_true()
		assert_bool(elite.has(id)).is_true()
	assert_bool(combat_epic_or_legend).is_false()


func test_fallback_weapons_exclude_locked() -> void:
	# m2-audit：--script 回退装载过滤 locked（T6 评审移交「回退未过滤」收口）——
	# 与 autoload _ready 同口径。直接调回退装载器（GameDB 在树时 _weapons 不走此
	# 路径）；断言无 locked 行、数量 = 115 − 49、id 全部在 weapons_all。
	var table := ShopLogic._load_fallback_weapons()
	assert_int(table.size()).is_equal(115 - 49)
	var all_ids: Array = GameDB.weapons_all.keys()
	for id: String in table:
		assert_bool(bool((table[id] as Dictionary).get("locked", false))).is_false()
		assert_array(all_ids).contains(id)
