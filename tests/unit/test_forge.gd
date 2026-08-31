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
var _saved_crafts: Variant = null


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


## 熔铸会上报 CodexSystem 的 craft_x 计数器（autoload 全局），逐例还原避免跨套件污染：
## 一旦累计到 craft_x 最小 goal（10，湮灭号角非★）会真的触发解锁并回池、改全局掉落池。
func before_test() -> void:
	_saved_crafts = CodexSystem.counters.get("crafts_total", 0)


func after_test() -> void:
	if _saved_weapons != null:
		GameDB.weapons = _saved_weapons
		_saved_weapons = null
	if _saved_crafts != null:
		CodexSystem.counters["crafts_total"] = _saved_crafts
		_saved_crafts = null


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


## M-3：双向覆盖（此前只做正向包含，4 元素重复数组也能通过）。
func test_fusion_only_marks_exactly_the_four_star_weapons() -> void:
	var names := ["雷神之锤", "斩舰刀", "星陨炮", "湮灭核心"]
	assert_int(ForgeLogic.FUSION_ONLY.size()).is_equal(4)
	var got: Array[String] = []
	for id: String in ForgeLogic.FUSION_ONLY:
		got.append(String(GameDB.get_weapon(id).get("name", "")))
	got.sort()
	for nm: String in names:                     # 正向：常量里的名字都是★
		assert_bool(names.has(nm)).is_true()
	for nm: String in names:                     # 反向：4 个★名字都被常量命中
		assert_bool(got.has(nm)).override_failure_message("star not covered: " + nm).is_true()
	assert_int(got.size()).is_equal(names.size())   # 名字互不重复（防重复元素数组）


## 裁定⑭：权威源 = data/unlock_tasks.json 的 forge_only:true 条目。双向钉死「两处一致」，
## 数据侧增删★而常量未同步（或反之）立刻 RED，杜绝静默漂移。
func test_fusion_only_matches_unlock_tasks_forge_only_data() -> void:
	var data_ids := ForgeLogic.forge_only_from_data()
	assert_int(data_ids.size()).is_equal(ForgeLogic.FUSION_ONLY.size())
	for id: String in data_ids:
		assert_bool(ForgeLogic.FUSION_ONLY.has(id)) \
			.override_failure_message("data has star not in FUSION_ONLY: " + id).is_true()
	for id: String in ForgeLogic.FUSION_ONLY:
		assert_bool(data_ids.has(id)) \
			.override_failure_message("FUSION_ONLY has id not marked forge_only: " + id).is_true()
	# 数据可用时 fusion_only() 走数据侧（不落兜底）
	assert_int(ForgeLogic.fusion_only().size()).is_equal(data_ids.size())


## M-1：缓存哨兵可重置，重置后重读结果一致（缺文件不会每次调用都重读刷 error）。
func test_reset_caches_then_reload_gives_same_tables() -> void:
	ForgeLogic.reset_caches()
	assert_int(ForgeLogic.recipes().size()).is_equal(15)
	assert_int(ForgeLogic.fusion_only().size()).is_equal(4)


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


# ---- 裁定⑯：附录 D 产物继承（蓝耗取两材料较高者、元素附魔取 B 材料）----

func test_fuse_recipe_inherits_energy_cost_as_higher_of_materials() -> void:
	# 铁剑(ec0) + 燃烧瓶(ec2) → 烈焰剑（静表 ec0）→ 继承后 = max(0,2) = 2
	assert_int(int(GameDB.get_weapon("lieyanjian").get("energy_cost", -1))).is_equal(0)
	var out := ForgeLogic.fuse("tiejian", "ranshaoping", GameDB.weapons, _rng())
	assert_str(String(out.get("id", ""))).is_equal("lieyanjian")
	assert_int(int(out.get("energy_cost", -1))).is_equal(2)


## 元素取「配方表 b 键」那把（燃烧瓶 fire），而非第二个入参——熔铸对投入顺序无感。
func test_fuse_recipe_inherits_element_from_recipe_b_slot() -> void:
	var fwd := ForgeLogic.fuse("tiejian", "ranshaoping", GameDB.weapons, _rng())
	assert_str(String(fwd.get("element", ""))).is_equal("fire")
	# 顺序反转：若实现误取「第二个入参」（此时是铁剑 none）则此断言失败
	var rev := ForgeLogic.fuse("ranshaoping", "tiejian", GameDB.weapons, _rng())
	assert_str(String(rev.get("element", ""))).is_equal("fire")
	assert_int(int(rev.get("energy_cost", -1))).is_equal(int(fwd.get("energy_cost", -1)))


## 继承值覆盖静表值（光剑 ec0 + 时间沙漏 ec8 → 湮灭核心 静表 ec5 → 8）。
func test_fuse_recipe_inherited_energy_cost_overrides_static_row() -> void:
	var out := ForgeLogic.fuse("guangjian", "shijianshalou", GameDB.weapons_all, _rng())
	assert_str(String(out.get("id", ""))).is_equal("yamiehexin")
	assert_int(int(out.get("energy_cost", -1))).is_equal(8)


## 材料/产物行缺 energy_cost/element 时按常规回落（0 / "none"）。
func test_fuse_recipe_inheritance_falls_back_when_fields_absent() -> void:
	var pool := {
		"tiejian": {"id": "tiejian", "name": "铁剑", "rarity": "common"},
		"ranshaoping": {"id": "ranshaoping", "name": "燃烧瓶", "rarity": "uncommon"},
		"lieyanjian": {"id": "lieyanjian", "name": "烈焰剑", "rarity": "rare"},
	}
	var out := ForgeLogic.fuse("tiejian", "ranshaoping", pool, _rng())
	assert_int(int(out.get("energy_cost", -1))).is_equal(0)
	assert_str(String(out.get("element", ""))).is_equal("none")


func test_preview_recipe_reports_inherited_stats() -> void:
	var out := ForgeLogic.preview("tiejian", "ranshaoping", GameDB.weapons)
	assert_int(int(out.get("energy_cost", -1))).is_equal(2)
	assert_str(String(out.get("element", ""))).is_equal("fire")


## 继承是局内实例属性：绝不回写 GameDB 表行（rig.slots 存的是共享行引用，必须复制）。
func test_fuse_recipe_does_not_mutate_global_weapon_table() -> void:
	var before_ec := int(GameDB.get_weapon("lieyanjian").get("energy_cost", -1))
	var before_el := String(GameDB.get_weapon("lieyanjian").get("element", ""))
	ForgeLogic.fuse("tiejian", "ranshaoping", GameDB.weapons, _rng())
	assert_int(int(GameDB.get_weapon("lieyanjian").get("energy_cost", -1))).is_equal(before_ec)
	assert_str(String(GameDB.get_weapon("lieyanjian").get("element", ""))).is_equal(before_el)


## M-2：产物 locked 不在掉落池时 name 不得退化成拼音 id（回落 weapons_all 取展示名）。
func test_fuse_locked_product_name_falls_back_to_weapons_all() -> void:
	# 星轨 + 迫击·悬顶 → ★星陨炮（locked，不在掉落池）
	var out := ForgeLogic.fuse("xinggui", "pojixuanding", GameDB.weapons, _rng())
	assert_str(String(out.get("id", ""))).is_equal("xingyunpao")
	assert_str(String(out.get("name", ""))).is_equal("星陨炮")
	assert_str(String(out.get("rarity", ""))).is_equal("legend")


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


## M-3：不再用「同种子探针再跑一遍 randi_range」当 oracle（同义反复，实现换抽法会跟着漂移）。
## 改为两条独立断言：①候选集 = 独立算出的目标桶（字典序、排除材料与★）；
## ②golden 值硬编码（SEED 下首抽索引 = 1 → "ub"）。
func test_fuse_generic_upgrade_picks_next_rarity() -> void:
	var pool := _stub_pool()
	var out := ForgeLogic.fuse("ca", "cb", pool, _rng())
	assert_array(ForgeLogic._candidates(pool, "uncommon", "ca", "cb")).is_equal(["ua", "ub"])
	assert_str(String(out.get("id", ""))).is_equal("ub")
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


## 裁定⑯：继承值落到实际装备的槽位行（局内实例），且不污染 GameDB 全量表。
func test_ui_recipe_fuse_applies_inherited_stats_to_equipped_slot() -> void:
	var h := _open_forge(["tiejian", "ranshaoping"])
	var forge: Forge = h["forge"]
	forge._on_fuse_pressed()
	var rig: WeaponRig = h["rig"]
	assert_str(String(rig.slots[0].get("id", ""))).is_equal("lieyanjian")
	assert_int(int(rig.slots[0].get("energy_cost", -1))).is_equal(2)
	assert_str(String(rig.slots[0].get("element", ""))).is_equal("fire")
	# 槽位行必须是全表行的副本：改实例不得污染全局（slots 存的是共享行引用）
	assert_int(int(GameDB.get_weapon("lieyanjian").get("energy_cost", -1))).is_equal(0)


## Important-1（评审 5b1061b）：熔铸成功必须上报图鉴 craft_x 计数。
## 此前 CodexSystem.count_craft() 无调用方，5 条 craft_x 任务（含 4 把★图鉴项）进度恒 0。
func test_ui_fuse_reports_craft_to_codex_system() -> void:
	var before := int(CodexSystem.counters.get("crafts_total", 0))
	var h := _open_forge(["tiejian", "ranshaoping"])
	h["forge"]._on_fuse_pressed()
	assert_int(int(CodexSystem.counters.get("crafts_total", 0))).is_equal(before + 1)


## Important-1 对照：被拒绝的熔铸（金币不足）不得计数。
func test_ui_rejected_fuse_does_not_report_craft() -> void:
	var before := int(CodexSystem.counters.get("crafts_total", 0))
	var h := _open_forge(["tiejian", "ranshaoping"], 50)   # 费用 65 > 50
	h["forge"]._on_fuse_pressed()
	assert_int(int(CodexSystem.counters.get("crafts_total", 0))).is_equal(before)


## Minor-3：兜底路径的盐字面量必须与 RunState.SALT_FORGE 常量一致（防改一处忘一处）。
func test_forge_fallback_salt_matches_run_state_constant() -> void:
	assert_str(ForgeLogic.SALT_FORGE).is_equal(RunState.SALT_FORGE)


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
