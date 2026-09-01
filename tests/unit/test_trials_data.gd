class_name TestTrialsData
extends GdUnitTestSuite
## M3-P0-3 试炼数据卡测试：res://data/trials.json 独立 schema 校验。
## FileAccess 直读 + JSON.parse_string，不依赖 GameDB（数据卡先行批次）。
## 覆盖：可读/可解析、顶层标量、8 因子 id 白名单且无重复、name/desc 非空、
## mods 键白名单 + 逐因子 mods 精确比对、数值域与布尔类型。
## 注意：JSON.parse_string 的数字一律为 float，断言用 int()/float() 转换比较，
## 绝不 typeof == TYPE_INT 判断。

const TRIALS_PATH := "res://data/trials.json"

# 8 条因子 id 白名单（既定清单，顺序即策划案顺序）
const FACTOR_IDS: Array[String] = [
	"enemy_haste", "melee_drops", "energy_tax", "bullet_haste",
	"bargain_ban", "narrow_vision", "elite_surge", "single_element",
]

# mods 键白名单（跨全部因子的合法键）
const MOD_KEYS: Array[String] = [
	"enemy_speed_pct", "enemy_attack_speed_pct", "drop_melee_only",
	"energy_cost_mult", "bullet_speed_pct", "shop_discount_pct",
	"no_hearts", "vision_scale", "elite_bonus_pct", "force_element",
]

# 每条因子 mods 的逐键精确期望（键集合 + 数值都要一致）
const EXPECTED_MODS := {
	"enemy_haste": {"enemy_speed_pct": 20.0, "enemy_attack_speed_pct": 20.0},
	"melee_drops": {"drop_melee_only": true},
	"energy_tax": {"energy_cost_mult": 1.5},
	"bullet_haste": {"bullet_speed_pct": 25.0},
	"bargain_ban": {"shop_discount_pct": 50.0, "no_hearts": true},
	"narrow_vision": {"vision_scale": 0.65},
	"elite_surge": {"elite_bonus_pct": 100.0},
	"single_element": {"force_element": "random"},
}

var _data: Dictionary = {}
var _factors: Array = []


func before_test() -> void:
	_data = {}
	_factors = []
	var f := FileAccess.open(TRIALS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed
		if _data.get("factors") is Array:
			_factors = _data["factors"]


func _factor_mods(id: String) -> Dictionary:
	for factor: Dictionary in _factors:
		if str(factor.get("id", "")) == id:
			return factor.get("mods", {})
	return {}


## 按期望值类型分派断言：bool 精确、String 精确、数值用 is_equal_approx
func _assert_mod_value(mods: Dictionary, key: String, expected: Variant, ctx: String) -> void:
	assert_bool(mods.has(key)) \
		.override_failure_message("%s: missing mod key '%s'" % [ctx, key]) \
		.is_true()
	if expected is bool:
		assert_bool(mods[key] is bool) \
			.override_failure_message("%s: mod '%s' should be bool, got %s" % [ctx, key, str(mods[key])]) \
			.is_true()
		assert_bool(mods[key]).is_equal(expected)
	elif expected is String:
		assert_str(str(mods[key])) \
			.override_failure_message("%s: mod '%s' = '%s', want '%s'" % [ctx, key, str(mods[key]), str(expected)]) \
			.is_equal(expected)
	else:
		assert_float(float(mods[key])) \
			.override_failure_message("%s: mod '%s' = %s, want %s" % [ctx, key, str(mods[key]), str(expected)]) \
			.is_equal_approx(float(expected), 0.0001)


func test_file_readable_and_parses() -> void:
	assert_bool(FileAccess.file_exists(TRIALS_PATH)).is_true()
	assert_that(FileAccess.open(TRIALS_PATH, FileAccess.READ)).is_not_null()
	# before_test 解析成功才有内容；解析失败/非 dict 会是空 dict
	assert_dict(_data).is_not_empty()


func test_top_level_scalars() -> void:
	# JSON.parse_string 数字均为 float → int() 转换后比较
	assert_int(int(_data.get("version", -1.0))).is_equal(1)
	assert_int(int(_data.get("refresh_hour", -1.0))).is_equal(5)
	assert_int(int(_data.get("pick_per_day", -1.0))).is_equal(2)
	assert_float(float(_data.get("reward_gem_multiplier", 0.0))).is_equal_approx(1.5, 0.0001)


func test_factors_count_and_ids_unique_whitelisted() -> void:
	assert_int(_factors.size()).is_equal(8)
	var seen := {}
	for factor: Dictionary in _factors:
		var id := str(factor.get("id", ""))
		assert_bool(FACTOR_IDS.has(id)) \
			.override_failure_message("factor id '%s' not in whitelist" % id) \
			.is_true()
		assert_bool(seen.has(id)) \
			.override_failure_message("duplicate factor id '%s'" % id) \
			.is_false()
		seen[id] = true
	# 8 个无重复 id 且全部在 8 元白名单内 ⟺ id 集合完全一致
	assert_int(seen.size()).is_equal(FACTOR_IDS.size())


func test_names_and_descs_non_empty() -> void:
	for factor: Dictionary in _factors:
		assert_str(str(factor.get("name", ""))) \
			.override_failure_message("factor '%s' name empty" % str(factor.get("id"))) \
			.is_not_empty()
		assert_str(str(factor.get("desc", ""))) \
			.override_failure_message("factor '%s' desc empty" % str(factor.get("id"))) \
			.is_not_empty()


func test_mods_keys_in_whitelist() -> void:
	for factor: Dictionary in _factors:
		var id := str(factor.get("id", ""))
		var mods: Dictionary = factor.get("mods", {})
		assert_int(mods.size()).is_greater(0)
		for key: String in mods:
			assert_bool(MOD_KEYS.has(key)) \
				.override_failure_message("factor '%s': mod key '%s' not whitelisted" % [id, key]) \
				.is_true()


func test_mods_exact_match_per_factor() -> void:
	assert_int(_factors.size()).is_equal(EXPECTED_MODS.size())
	for id: String in FACTOR_IDS:
		var ctx := "factor '%s'" % id
		var mods := _factor_mods(id)
		var expected: Dictionary = EXPECTED_MODS[id]
		# 键集合一致：数量相等 + 每个期望键都存在（见 _assert_mod_value）
		assert_int(mods.size()) \
			.override_failure_message("%s: mods size %d, want %d" % [ctx, mods.size(), expected.size()]) \
			.is_equal(expected.size())
		for key: String in expected:
			_assert_mod_value(mods, key, expected[key], ctx)


func test_numeric_domains() -> void:
	for factor: Dictionary in _factors:
		var id := str(factor.get("id", ""))
		var mods: Dictionary = factor.get("mods", {})
		# 百分比域 (0, 100]
		for pct_key: String in ["enemy_speed_pct", "enemy_attack_speed_pct",
				"bullet_speed_pct", "shop_discount_pct", "elite_bonus_pct"]:
			if mods.has(pct_key):
				var v := float(mods[pct_key])
				assert_bool(v > 0.0 and v <= 100.0) \
					.override_failure_message("factor '%s': %s = %s out of (0, 100]" % [id, pct_key, str(v)]) \
					.is_true()
		if mods.has("energy_cost_mult"):
			assert_float(float(mods["energy_cost_mult"])).is_equal_approx(1.5, 0.0001)
		if mods.has("vision_scale"):
			assert_float(float(mods["vision_scale"])).is_equal_approx(0.65, 0.0001)
		if mods.has("force_element"):
			assert_bool(["random"].has(str(mods["force_element"]))) \
				.override_failure_message("factor '%s': force_element must be 'random'" % id) \
				.is_true()
		# 布尔键必须真是 bool（JSON 解析后 true/false 不会变型，防御未来手改）
		for bool_key: String in ["drop_melee_only", "no_hearts"]:
			if mods.has(bool_key):
				assert_bool(mods[bool_key] is bool) \
					.override_failure_message("factor '%s': '%s' should be bool" % [id, bool_key]) \
					.is_true()
