class_name TestWeaponsPool
extends GdUnitTestSuite
## T25 武器池数据卡测试：≥40 把、4 元素各 ≥2、rarity 分布（白≥8/绿≥12/蓝≥15，含旧 6 把）、
## id 唯一、name 非空、逐行 schema v2 校验、存在 projectiles ≥2 的多弹丸武器。
## fresh-instance pattern（同 test_game_db.gd）：不污染 autoload 状态。

const POOL_PATH := "res://data/weapons.json"
const MIN_TOTAL := 40
# 白/绿/蓝/紫/橙 → common/uncommon/rare/epic/legend（shop_logic.gd §8.2 既定映射）
const MIN_COMMON := 8
const MIN_UNCOMMON := 12
const MIN_RARE := 15
const MIN_PER_ELEMENT := 2

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


func test_pool_at_least_40() -> void:
	assert_int(_pool.size()).is_greater_equal(MIN_TOTAL)


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
		assert_array(errors).is_empty()


func test_rarity_distribution() -> void:
	assert_int(_count_by("rarity", "common")).is_greater_equal(MIN_COMMON)
	assert_int(_count_by("rarity", "uncommon")).is_greater_equal(MIN_UNCOMMON)
	assert_int(_count_by("rarity", "rare")).is_greater_equal(MIN_RARE)


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


func test_multi_projectile_rows_exist() -> void:
	# 散弹扩张增益（extra_projectiles）需有 projectiles ≥2 的行才能生效
	var found := false
	for id: String in _pool:
		if int(_pool[id].get("projectiles", 0)) >= 2:
			found = true
			break
	assert_bool(found).is_true()
