class_name TestForge
extends GdUnitTestSuite
## m2-t25 熔铸台契约测试。
## 1) fusions.json：15 行 schema + 与附录 D 逐条对齐 + a/b/result 全在 weapons 表 + 无重复对
## 2) ForgeLogic.fuse：配方命中（两种顺序等价）/ 同名武器拒绝 / 未知 id（不在池）拒绝 /
##    不同稀有度未命中返回空 / 通用升级（同稀有度 → +1 随机，注入 rng 确定性，
##    排除 a/b 与 4 把★熔铸限定 / 桶空返回空 / legend 无 +1 返回空）
## 3) ForgeLogic.preview：配方给确切产物 / 升级给目标稀有度 / 其余 none（UI 预览不掷签）
## 4) ForgeLogic.fuse_cost：两把较高稀有度基准 ×1.5 取整到 5（附录 H 锚点表逐项断言）
## 5) Forge UI（headless 实例化 forge.tscn）：开面板（双槽快照/预览/费用/金币）/
##    配方熔铸（扣费+产物入槽 0+副槽清空+不消耗升级次数）/ 通用升级（扣费+产物+RunState 计数）/
##    每局限 2 次后拒绝且不扣费 / 金币不足拒绝 / Esc·按钮关店

const SEED := 20260828

var _saved_weapons: Variant = null


# ---------------------------------------------------------------- 替身与桩

## 金币桩：duck-typed wallet（spend_coins，同 Shop/雕像契约）。
class WalletProbe:
	var coins: int = 0
	var spent: Array[int] = []

	func spend_coins(n: int) -> bool:
		if coins < n:
			return false
		coins -= n
		spent.append(n)
		return true


## RunState 计数桩：只带熔铸通用升级计数（鸭子接缝，同正式字段名；Node 型对齐 Forge.run_state）。
class RunStateProbe extends Node:
	var forge_upgrades: int = 0


func _stub_weapons(rows: Dictionary) -> void:
	_saved_weapons = GameDB.weapons
	GameDB.weapons = rows


func after_test() -> void:
	if _saved_weapons != null:
		GameDB.weapons = _saved_weapons
		_saved_weapons = null


func _rng(seed_value := SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 合成武器池：稀有度阶梯可控（区别于真实表，升级桶内容完全可断言）。
func _stub_pool() -> Dictionary:
	return {
		"ca": {"id": "ca", "name": "白A", "rarity": "common"},
		"cb": {"id": "cb", "name": "白B", "rarity": "common"},
		"ua": {"id": "ua", "name": "绿A", "rarity": "uncommon"},
		"ub": {"id": "ub", "name": "绿B", "rarity": "uncommon"},
		"ra": {"id": "ra", "name": "蓝A", "rarity": "rare"},
		"rb": {"id": "rb", "name": "蓝B", "rarity": "rare"},
		"ea": {"id": "ea", "name": "紫A", "rarity": "epic"},
		"eb": {"id": "eb", "name": "紫B", "rarity": "epic"},
		"la": {"id": "la", "name": "橙A", "rarity": "legend"},
		"lb": {"id": "lb", "name": "橙B", "rarity": "legend"},
	}


## 开面板替身：返回 {"forge", "wallet", "run_state", "player", "rig"}。
## pool 缺省 = GameDB.weapons（掉落池，同生产接线）；升级路径用例传合成池。
func _open_forge(slot_ids: Array, coins := 500, upgrades := 0,
		pool: Dictionary = {}) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var forge: Forge = auto_free((load("res://ui/forge.tscn") as PackedScene).instantiate())
	root.add_child(forge)
	var player: Player = auto_free(Player.new())
	root.add_child(player)
	var rig: WeaponRig = auto_free(WeaponRig.new())
	rig._test_init()
	player.weapon_rig = rig
	for id_v: Variant in slot_ids:
		var id := String(id_v)
		if not id.is_empty():
			rig.equip(id)
	var wallet := WalletProbe.new()
	wallet.coins = coins
	var run_state: RunStateProbe = auto_free(RunStateProbe.new())
	run_state.forge_upgrades = upgrades
	forge.wallet = wallet
	forge.pool = pool if not pool.is_empty() else GameDB.weapons
	forge.run_state = run_state
	forge.rng = _rng()
	forge.open(player)
	return {"forge": forge, "wallet": wallet, "run_state": run_state,
		"player": player, "rig": rig}


# ================================================================ 1) 数据表

func _recipes() -> Array:
	return ForgeLogic.recipes()


func test_recipes_table_has_15_rows() -> void:
	assert_int(_recipes().size()).is_equal(15)


func test_recipes_rows_have_ab_result_schema() -> void:
	for r: Variant in _recipes():
		var row: Dictionary = r
		assert_bool(row.has("a") and row.has("b") and row.has("result")).is_true()


## 附录 D 15 条逐条钉死（防数据漂移）。
func test_recipes_match_appendix_d() -> void:
	var expected := [
		["tiejian", "ranshaoping", "lieyanjian"],
		["tiejian", "bingdonglei", "bingshuangjujian"],
		["shuangbi", "duqiguan", "duyaduanren"],
		["changqiang", "dianque", "leishenzhichui"],
		["zhuixingdajian", "xingheliudan", "zhanjiandao"],
		["ronghuoshouqiang", "xunxiang", "zhongyanjicu"],
		["guanchuanzhe", "shenkong", "caijue"],
		["xinggui", "pojixuanding", "xingyunpao"],
		["guanglengshoudian", "lengjingquanzhang", "caihongfashengqi"],
		["xuetufazhang", "yunshizhang", "zhongyanzhizhang"],
		["duangong", "fenliejian", "guanxinggong"],
		["shoulei", "diancimaichonglei", "xingheliudan"],
		["guangjian", "shijianshalou", "yamiehexin"],
		["zhanhaoqingxiao", "tanshexian", "yaniemhaojiao"],
		["liefengchanggong", "leimingnu", "dianciguidao"],
	]
	var actual: Array[String] = []
	for r: Variant in _recipes():
		var row: Dictionary = r
		actual.append("%s+%s=%s" % [row["a"], row["b"], row["result"]])
	for e: Variant in expected:
		var triple: Array = e
		var key := "%s+%s=%s" % [triple[0], triple[1], triple[2]]
		assert_bool(actual.has(key)).override_failure_message("missing recipe " + key).is_true()


func test_recipes_ids_all_exist_in_weapons_table() -> void:
	for r: Variant in _recipes():
		var row: Dictionary = r
		for key: String in ["a", "b", "result"]:
			assert_bool(GameDB.get_weapon(String(row[key])).is_empty()) \
				.override_failure_message("weapon missing: " + String(row[key])).is_false()


func test_recipes_pairs_unique() -> void:
	var seen: Array[String] = []
	for r: Variant in _recipes():
		var row: Dictionary = r
		var pair: Array = [String(row["a"]), String(row["b"])]
		pair.sort()
		var key := "|".join(pair)
		assert_bool(seen.has(key)).override_failure_message("duplicate pair " + key).is_false()
		seen.append(key)


func test_fusion_only_marks_exactly_the_four_star_weapons() -> void:
	var names := ["雷神之锤", "斩舰刀", "星陨炮", "湮灭核心"]
	assert_int(ForgeLogic.FUSION_ONLY.size()).is_equal(4)
	for id: String in ForgeLogic.FUSION_ONLY:
		assert_bool(names.has(String(GameDB.get_weapon(id).get("name", "")))).is_true()


# ================================================================ 2) fuse

func test_fuse_recipe_hit_returns_product() -> void:
	var out := ForgeLogic.fuse("tiejian", "ranshaoping", GameDB.weapons, _rng())
	assert_str(String(out.get("id", ""))).is_equal("lieyanjian")
	assert_str(String(out.get("kind", ""))).is_equal("recipe")
	assert_str(String(out.get("rarity", ""))).is_equal("rare")


func test_fuse_recipe_hit_is_order_insensitive() -> void:
	var out := ForgeLogic.fuse("ranshaoping", "tiejian", GameDB.weapons, _rng())
	assert_str(String(out.get("id", ""))).is_equal("lieyanjian")
	assert_str(String(out.get("kind", ""))).is_equal("recipe")


func test_fuse_all_15_recipes_hit() -> void:
	# 用全量表（含 locked）：部分配方材料为紫/橙（locked 不入掉落池），
	# 全表才含全部材料；产物 id 以配方表为准。
	for r: Variant in _recipes():
		var row: Dictionary = r
		var out := ForgeLogic.fuse(String(row["a"]), String(row["b"]), GameDB.weapons_all, _rng())
		assert_str(String(out.get("id", ""))).is_equal(String(row["result"]))
		assert_str(String(out.get("kind", ""))).is_equal("recipe")


func test_fuse_same_weapon_rejected() -> void:
	# 同名武器不可作材料（即使稀有度相同、即使存在配方也不可能 a==b）
	assert_dict(ForgeLogic.fuse("tiejian", "tiejian", GameDB.weapons, _rng())).is_empty()


func test_fuse_unknown_id_rejected() -> void:
	# locked/未知武器不在池 → 拒绝（fail-closed）
	assert_dict(ForgeLogic.fuse("tiejian", "nonexistent_weapon", GameDB.weapons, _rng())).is_empty()
	assert_dict(ForgeLogic.fuse("", "tiejian", GameDB.weapons, _rng())).is_empty()


func test_fuse_different_rarity_miss_returns_empty() -> void:
	# 铁剑(common)+电雀(epic)：无配方、稀有度不同 → 不升级不熔铸（全表池，电雀在场）
	assert_dict(ForgeLogic.fuse("tiejian", "dianque", GameDB.weapons_all, _rng())).is_empty()


func test_fuse_locked_material_not_in_drop_pool_rejected() -> void:
	# locked（紫/橙未解锁）不入掉落池（GameDB.weapons）→ 即使是有效配方对也拒绝：
	# 「locked 武器不可作材料——locked 未解锁本就不在池」（长枪 common 在池，电雀 epic 不在）
	assert_bool(GameDB.weapons.has("dianque")).is_false()
	assert_dict(ForgeLogic.fuse("changqiang", "dianque", GameDB.weapons, _rng())).is_empty()
	# 同一对换全量表即可命中（对照）
	assert_str(String(ForgeLogic.fuse("changqiang", "dianque", GameDB.weapons_all, _rng())
		.get("id", ""))).is_equal("leishenzhichui")


func test_fuse_generic_upgrade_picks_next_rarity() -> void:
	var out := ForgeLogic.fuse("ca", "cb", _stub_pool(), _rng())
	# 白对 → +1 = 绿桶 → 候选 [ua, ub]（排除不适用：材料必不在 +1 桶）；
	# 期望值 = 同种子探针 rng 的首抽（与 fuse 内部选取同源对齐）
	var probe := _rng()
	var expected: String = ["ua", "ub"][probe.randi_range(0, 1)]
	assert_str(String(out.get("id", ""))).is_equal(expected)
	assert_str(String(out.get("kind", ""))).is_equal("upgrade")
	assert_str(String(out.get("rarity", ""))).is_equal("uncommon")


func test_fuse_generic_upgrade_deterministic_with_same_seed() -> void:
	var a := ForgeLogic.fuse("ca", "cb", _stub_pool(), _rng(7))
	var b := ForgeLogic.fuse("ca", "cb", _stub_pool(), _rng(7))
	assert_str(String(a.get("id", ""))).is_equal(String(b.get("id", "")))


func test_fuse_generic_upgrade_excludes_fusion_only_legends() -> void:
	# 紫对 → 目标橙桶只含★星陨炮 → 被排除 → 无候选返回空
	var pool := _stub_pool()
	pool["xingyunpao"] = GameDB.get_weapon("xingyunpao")
	pool.erase("la")
	pool.erase("lb")
	assert_dict(ForgeLogic.fuse("ea", "eb", pool, _rng())).is_empty()


func test_fuse_generic_upgrade_empty_bucket_returns_empty() -> void:
	# 白对但池内无绿 → 桶空返回空
	var pool := {"ca": {"id": "ca", "name": "白A", "rarity": "common"},
		"cb": {"id": "cb", "name": "白B", "rarity": "common"}}
	assert_dict(ForgeLogic.fuse("ca", "cb", pool, _rng())).is_empty()


func test_fuse_legend_pair_has_no_next_rarity() -> void:
	# 橙已是顶稀有度 → 无 +1 可升 → 返回空
	var pool := _stub_pool()
	pool.erase("ea")
	pool.erase("eb")
	assert_dict(ForgeLogic.fuse("la", "lb", pool, _rng())).is_empty()


# ================================================================ 3) preview

func test_preview_recipe_gives_exact_product() -> void:
	var out := ForgeLogic.preview("tiejian", "ranshaoping", GameDB.weapons)
	assert_str(String(out.get("kind", ""))).is_equal("recipe")
	assert_str(String(out.get("id", ""))).is_equal("lieyanjian")


func test_preview_upgrade_gives_target_rarity_without_rolling() -> void:
	var out := ForgeLogic.preview("ca", "cb", _stub_pool())
	assert_str(String(out.get("kind", ""))).is_equal("upgrade")
	assert_str(String(out.get("target_rarity", ""))).is_equal("uncommon")
	assert_bool(out.has("id")).is_false()          # 预览不掷签、不出具体 id


func test_preview_none_cases() -> void:
	assert_str(String(ForgeLogic.preview("tiejian", "dianque", GameDB.weapons)
		.get("kind", ""))).is_equal("none")
	assert_str(String(ForgeLogic.preview("tiejian", "tiejian", GameDB.weapons)
		.get("kind", ""))).is_equal("none")
	assert_str(String(ForgeLogic.preview("", "", GameDB.weapons)
		.get("kind", ""))).is_equal("none")


func test_preview_upgrade_empty_bucket_is_none() -> void:
	# preview 与 fuse 同源：+1 桶空（当前数据期全紫橙 locked 不入掉落池）→ 预览即 none，
	# 不会出现「可预览、熔铸却失败」的付费陷阱
	assert_str(String(ForgeLogic.preview("shuangya", "xunxiang", GameDB.weapons)
		.get("kind", ""))).is_equal("none")
	# 对照：全表池（T20 解锁进池后的语义）紫桶有候选 → upgrade
	assert_str(String(ForgeLogic.preview("shuangya", "xunxiang", GameDB.weapons_all)
		.get("kind", ""))).is_equal("upgrade")


# ================================================================ 4) fuse_cost

func test_fuse_cost_same_rarity_pairs() -> void:
	assert_int(ForgeLogic.fuse_cost("common", "common")).is_equal(30)
	assert_int(ForgeLogic.fuse_cost("uncommon", "uncommon")).is_equal(65)
	assert_int(ForgeLogic.fuse_cost("rare", "rare")).is_equal(130)
	assert_int(ForgeLogic.fuse_cost("epic", "epic")).is_equal(235)
	assert_int(ForgeLogic.fuse_cost("legend", "legend")).is_equal(390)


func test_fuse_cost_uses_higher_rarity_of_pair() -> void:
	assert_int(ForgeLogic.fuse_cost("common", "uncommon")).is_equal(65)
	assert_int(ForgeLogic.fuse_cost("uncommon", "common")).is_equal(65)
	assert_int(ForgeLogic.fuse_cost("common", "rare")).is_equal(130)
	assert_int(ForgeLogic.fuse_cost("epic", "legend")).is_equal(390)


func test_fuse_cost_unknown_rarity_defensive_common_base() -> void:
	assert_int(ForgeLogic.fuse_cost("foo", "common")).is_equal(30)


# ================================================================ 5) UI

func test_ui_is_interactable_and_opens_with_snapshot() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	assert_bool(forge is Interactable).is_true()
	assert_bool(forge.ui_visible()).is_true()
	assert_str(forge.title_text()).is_equal("熔铸台")
	assert_str(forge.material_name_text(0)).is_equal("铁剑")
	assert_str(forge.material_name_text(1)).is_equal("燃烧瓶")
	assert_str(forge.coins_text()).is_equal("500 金币")


func test_ui_preview_recipe_and_cost_display() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	assert_str(forge.preview_text()).contains("烈焰剑")
	assert_str(forge.cost_text()).is_equal("65 金币")   # 两把较高=绿42×1.5→65


func test_ui_recipe_fuse_spends_equips_slot0_clears_slot1_keeps_counter() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	forge._on_fuse_pressed()
	var rig: WeaponRig = h["rig"]
	assert_str(String(rig.slots[0].get("id", ""))).is_equal("lieyanjian")
	assert_dict(rig.slots[1]).is_empty()
	assert_int(rig.slot).is_equal(0)
	var wallet: WalletProbe = h["wallet"]
	assert_array(wallet.spent).contains([65])
	assert_str(forge.coins_text()).is_equal("435 金币")
	assert_int((h["run_state"] as RunStateProbe).forge_upgrades).is_equal(0)


func test_ui_generic_upgrade_fuse_spends_and_counts() -> void:
	# 真实绿对（双子星/蜂刺，均 unlocked 在掉落池）→ +1 蓝桶随机
	var h := _open_forge(["shuangzixing", "fengci"])
	var forge: Forge = h["forge"]
	assert_str(forge.preview_text()).contains("通用升级")
	forge._on_fuse_pressed()
	var wallet: WalletProbe = h["wallet"]
	assert_array(wallet.spent).contains([65])
	assert_int((h["run_state"] as RunStateProbe).forge_upgrades).is_equal(1)
	var rig: WeaponRig = h["rig"]
	assert_str(String(rig.slots[0].get("rarity", ""))).is_equal("rare")
	assert_str(String(rig.slots[1].get("id", ""))).is_empty()


func test_ui_upgrade_limit_blocks_third_attempt_without_charge() -> void:
	var h := _open_forge(["shuangzixing", "fengci"], 5000, 2)
	var forge: Forge = h["forge"]
	assert_str(forge.preview_text()).contains("上限")
	forge._on_fuse_pressed()
	var wallet: WalletProbe = h["wallet"]
	assert_array(wallet.spent).is_empty()
	assert_int((h["run_state"] as RunStateProbe).forge_upgrades).is_equal(2)


func test_ui_recipe_fuse_not_blocked_by_upgrade_limit() -> void:
	# 配方熔铸不受通用升级 2 次上限约束
	var h := _open_forge(["tiejian", "ranshaoping"], 500, 2)
	var forge: Forge = h["forge"]
	assert_str(forge.preview_text()).contains("烈焰剑")
	forge._on_fuse_pressed()
	assert_str(String(h["rig"].slots[0].get("id", ""))).is_equal("lieyanjian")


func test_ui_insufficient_coins_rejected() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"], 50)   # 费用 65 > 50
	var forge: Forge = h["forge"]
	forge._on_fuse_pressed()
	assert_str(String(h["rig"].slots[0].get("id", ""))).is_equal("tiejian")
	assert_array((h["wallet"] as WalletProbe).spent).is_empty()


func test_ui_empty_slot_shows_no_fuse() -> void:
	var h := _open_forge(["tiejian", ""])
	var forge: Forge = h["forge"]
	assert_str(forge.preview_text()).contains("无法熔铸")
	forge._on_fuse_pressed()
	assert_array((h["wallet"] as WalletProbe).spent).is_empty()


func test_ui_close_hides_panel() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	forge.close()
	assert_bool(forge.ui_visible()).is_false()


func test_ui_interact_uses_preset_fields() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	forge.close()
	forge.interact(h["player"])
	assert_bool(forge.ui_visible()).is_true()
