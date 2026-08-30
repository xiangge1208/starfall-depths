class_name TestWeaponsPool
extends GdUnitTestSuite
## M2-T6 武器池数据卡测试：附录 A 全量 115 把（精确）、稀有度分布逐档精确
## （附录 A 实际清点：白 9 / 绿 21 / 蓝 36 / 紫 33 / 橙 16 = 115）、4 元素覆盖、
## id 唯一、逐行 schema v2 校验、紫/橙 49 把默认锁定（locked:true，含 4 把 ★熔铸限定）、
## 掉落池出口（GameDB.weapons）排除 locked 而图鉴出口（weapons_all）保留全量。
## fresh-instance pattern（同 test_game_db.gd）：不污染 autoload 状态。

const POOL_PATH := "res://data/weapons.json"
const EXACT_TOTAL := 115
# 附录 A 实际清点（先数一遍再写死）：白9 绿21 蓝36 紫33 橙16，合计 115
const EXACT_COMMON := 9
const EXACT_UNCOMMON := 21
const EXACT_RARE := 36
const EXACT_EPIC := 33
const EXACT_LEGEND := 16
# 附录 A 解锁规则：紫/橙共 49 把默认锁定（图鉴任务解锁后才进掉落池）
const EXACT_LOCKED := 49
const MIN_PER_ELEMENT := 2
# 设计文档 §8「11 类」：手枪/冲锋枪/步枪/霰弹/狙击重炮/激光/法杖/弓弩/投掷/近战/特殊
const CATEGORIES: Array[String] = [
	"pistol", "smg", "rifle", "shotgun", "sniper",
	"laser", "staff", "bow", "throw", "melee", "special",
]

var _pool: Dictionary = {}


func before_test() -> void:
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	_pool = db._load_table(POOL_PATH, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)


func _count_by(key: String, value: String) -> int:
	var n := 0
	for id: String in _pool:
		if str(_pool[id].get(key, "")) == value:
			n += 1
	return n


func _count_locked() -> int:
	var n := 0
	for id: String in _pool:
		if bool(_pool[id].get("locked", false)):
			n += 1
	return n


func test_pool_exactly_115() -> void:
	assert_int(_pool.size()).override_failure_message(
		"weapons pool has %d rows, want exactly %d" % [_pool.size(), EXACT_TOTAL]) \
		.is_equal(EXACT_TOTAL)


func test_ids_unique_and_match_keys() -> void:
	# JSON 重复键会被 parse 静默合并：行内 id 必须与字典键一一对应
	var seen_ids := {}
	for key: String in _pool:
		var row_id: String = _pool[key].get("id", "")
		assert_str(row_id).is_equal(key)
		assert_bool(seen_ids.has(row_id)).is_false()
		seen_ids[row_id] = true
	assert_int(seen_ids.size()).is_equal(_pool.size())


func test_names_non_empty() -> void:
	for id: String in _pool:
		assert_str(str(_pool[id].get("name", ""))).is_not_empty()


func test_every_row_passes_schema_v2() -> void:
	for id: String in _pool:
		var errors: Array[String] = GameDB.validate_row(_pool[id], GameDB.WEAPON_SCHEMA)
		assert_array(errors).override_failure_message("row %s: %s" % [id, str(errors)]) \
			.is_empty()


func test_rarity_distribution_exact() -> void:
	# 附录 A 实际清点逐档精确断言（白9/绿21/蓝36/紫33/橙16）
	assert_int(_count_by("rarity", "common")).override_failure_message(
		"common %d want %d" % [_count_by("rarity", "common"), EXACT_COMMON]) \
		.is_equal(EXACT_COMMON)
	assert_int(_count_by("rarity", "uncommon")).override_failure_message(
		"uncommon %d want %d" % [_count_by("rarity", "uncommon"), EXACT_UNCOMMON]) \
		.is_equal(EXACT_UNCOMMON)
	assert_int(_count_by("rarity", "rare")).override_failure_message(
		"rare %d want %d" % [_count_by("rarity", "rare"), EXACT_RARE]) \
		.is_equal(EXACT_RARE)
	assert_int(_count_by("rarity", "epic")).override_failure_message(
		"epic %d want %d" % [_count_by("rarity", "epic"), EXACT_EPIC]) \
		.is_equal(EXACT_EPIC)
	assert_int(_count_by("rarity", "legend")).override_failure_message(
		"legend %d want %d" % [_count_by("rarity", "legend"), EXACT_LEGEND]) \
		.is_equal(EXACT_LEGEND)


func test_four_elements_at_least_two_each() -> void:
	# element 字段非 "none" 计数；四元素名以 Elements.NAMES 为准
	for elem: String in ["fire", "ice", "poison", "shock"]:
		assert_int(_count_by("element", elem)) \
			.override_failure_message("element %s has %d rows, want >= %d"
				% [elem, _count_by("element", elem), MIN_PER_ELEMENT]) \
			.is_greater_equal(MIN_PER_ELEMENT)


func test_element_values_are_known() -> void:
	var valid: Array = Elements.NAMES.values()
	for id: String in _pool:
		assert_bool(valid.has(_pool[id].get("element", ""))) \
			.override_failure_message("row %s bad element: %s" % [id, str(_pool[id].get("element"))]) \
			.is_true()


func test_categories_within_11_kinds() -> void:
	# 设计文档 §8：武器 11 类；category 拼写错误在此拦截
	for id: String in _pool:
		var cat: String = _pool[id].get("category", "")
		assert_bool(CATEGORIES.has(cat)) \
			.override_failure_message("row %s bad category: %s" % [id, cat]) \
			.is_true()
	# 11 类全部在池中出现（附录 A 每类至少 1 把）
	for cat: String in CATEGORIES:
		assert_bool(_count_by("category", cat) > 0) \
			.override_failure_message("category %s missing from pool" % cat) \
			.is_true()


func test_locked_is_optional_key_default_false() -> void:
	# GameDB 对 locked 的唯一契约：可选 TYPE_BOOL 键，缺省 false（白/绿/蓝默认可用）
	# 经局部 Dictionary 取值（const 字面量索引会被解析期常量折叠拒绝缺键）
	var defaults: Dictionary = GameDB.WEAPON_OPTIONAL
	assert_bool(defaults.has("locked")).is_true()
	assert_bool(bool(defaults.get("locked", true))).is_false()


func test_locked_matches_rarity_rule() -> void:
	# 附录 A 解锁规则：紫/橙共 49 把默认锁定；白/绿/蓝一律未锁定
	assert_int(_count_locked()).override_failure_message(
		"locked rows %d want %d" % [_count_locked(), EXACT_LOCKED]) \
		.is_equal(EXACT_LOCKED)
	for id: String in _pool:
		var row: Dictionary = _pool[id]
		var want_locked: bool = str(row.get("rarity")) in ["epic", "legend"]
		assert_bool(bool(row.get("locked", false))) \
			.override_failure_message("row %s rarity=%s locked=%s want %s"
				% [id, str(row.get("rarity")), str(row.get("locked")), str(want_locked)]) \
			.is_equal(want_locked)


func test_drop_pool_excludes_locked_but_codex_keeps_all() -> void:
	# GameDB 载入侧两处出口：weapons = 掉落池（消费方 FloorScene._roll_weapon /
	# ShopLogic._weapons，locked 不得出现）；weapons_all = 全量（图鉴侧，M2-T20 消费）。
	assert_int(GameDB.weapons_all.size()).override_failure_message(
		"weapons_all has %d rows, want %d" % [GameDB.weapons_all.size(), EXACT_TOTAL]) \
		.is_equal(EXACT_TOTAL)
	assert_int(GameDB.weapons.size()).override_failure_message(
		"drop pool has %d rows, want %d (115 - 49 locked)"
			% [GameDB.weapons.size(), EXACT_TOTAL - EXACT_LOCKED]) \
		.is_equal(EXACT_TOTAL - EXACT_LOCKED)
	for id: String in GameDB.weapons:
		assert_bool(bool((GameDB.weapons[id] as Dictionary).get("locked", false))) \
			.override_failure_message("drop pool contains locked row: %s" % id) \
			.is_false()
	# locked 行只存在于 weapons_all；get_weapon 走掉落池表（locked 尚无获取途径，
	# 解锁进池是 M2-T20 的职责），非 locked id 必须可查行
	var locked_seen := 0
	for id: String in GameDB.weapons_all:
		if bool((GameDB.weapons_all[id] as Dictionary).get("locked", false)):
			locked_seen += 1
			assert_bool(GameDB.weapons.has(id)) \
				.override_failure_message("locked row %s leaked into drop pool" % id) \
				.is_false()
		else:
			assert_bool(GameDB.get_weapon(id).is_empty()) \
				.override_failure_message("get_weapon must resolve unlocked id %s" % id) \
				.is_false()
	assert_int(locked_seen).is_equal(EXACT_LOCKED)


func test_appendix_notation_spot_checks() -> void:
	# 附录 A 特性记法的转录抽查：N×M 弹丸 / 穿透 N / 反弹 N / 弹速+50% / 射程 px / DOT 伤害
	var spot: Dictionary = {
		"shuangzixing": {"damage": 2, "projectiles": 2},          # 双子星 2×2
		"zhanhaoqingxiao": {"damage": 2, "projectiles": 8},       # 战壕清扫 2×8
		"yaniemhaojiao": {"damage": 2, "projectiles": 12},        # 湮灭号角 2×12
		"lengjingquanzhang": {"damage": 5, "projectiles": 3},     # 棱镜权杖 5×3
		"guidaobiaojiqi": {"damage": 8, "projectiles": 6},        # 轨道标记器 8×6跳
		"jishulei": {"damage": 6, "projectiles": 4},              # 集束雷 6×4子雷
		"wurenjimujian": {"damage": 4, "projectiles": 2},         # 无人机母舰 2×4伤
		"shenpanzhe": {"pierce": 2},                              # 审判者 穿透 2
		"guanchuanzhe": {"pierce": 3},                            # 贯穿者 穿透 3
		"liexiong": {"pierce": 1},                                # 猎熊 穿透 1
		"liefengchanggong": {"pierce": 3},                        # 猎风长弓 满蓄力穿透 3
		"shezhezhe": {"bounce": 3},                               # 折射者 反弹 3
		"tanshexian": {"bounce": 2},                              # 弹射霰 反弹 2
		"tantiaokuwu": {"bounce": 4},                             # 弹跳苦无 反弹 4
		"lieluren": {"bullet_speed": 630},                        # 猎鹿人 弹速+50%（420×1.5）
		"changqiang": {"range": 220},                             # 长枪 突刺 220px
		"duyepensa": {"range": 180},                              # 毒液喷洒 射程 180px
		"guanglengshoudian": {"range": 160},                      # 光棱手电 射程 160px
		"qiegezhe": {"range": 240},                               # 切割者 射程 240px
		"xiangweirenguang": {"range": 120},                       # 相位刃光 短距 120px
		"ranshaoping": {"damage": 3, "projectiles": 1, "element": "fire"},   # 燃烧瓶 3/s×3s（DOT 非 N 弹丸）
		"duqiguan": {"damage": 2, "projectiles": 1, "element": "poison"},   # 毒气罐 2/s×4s（DOT 非 N 弹丸）
		"heidongfashengqi": {"damage": 8, "projectiles": 1},      # 黑洞发生器 8/s
	}
	for id: String in spot:
		var row: Dictionary = _pool.get(id, {})
		assert_bool(row.is_empty()).override_failure_message("missing row %s" % id).is_false()
		for key: String in spot[id]:
			var got: Variant = row.get(key, null)
			assert_str(str(got)).override_failure_message(
				"row %s %s: got %s want %s" % [id, key, str(got), str(spot[id][key])]) \
				.is_equal(str(spot[id][key]))


func test_multi_projectile_rows_exist() -> void:
	# 散弹扩张增益（extra_projectiles）需有 projectiles ≥2 的行才能生效
	var found := false
	for id: String in _pool:
		if int(_pool[id].get("projectiles", 0)) >= 2:
			found = true
			break
	assert_bool(found).is_true()
