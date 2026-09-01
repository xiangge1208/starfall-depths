class_name TestTrialSystem
extends GdUnitTestSuite
## M3-R-A 试炼因子引擎 + 每日种子：
## - daily_seed 同日稳定 / 跨日不同（规格 §2 一次定稿式的行为钉死）；
## - business_date 纯函数业务日边界（05:00 刷新点；跨日/跨月/跨年/闰年）；
## - pick_factors 恰 2 条、id 升序、⊆ 8 白名单、跨会话/新实例一致、预览无副作用；
## - 抽取流种子精确复刻 RngSvc.stream 派生链（裁定③ 防实现漂移）；
## - RunState.start_trial_run 单点注入（run_seed / mods / is_trial_run）+ start_run 复位；
## - GameDB.trials 正式接线：真实数据 8 条装载 + 坏文件 fail-closed（裁定⑥）。
## 注意：JSON 数字一律 float，断言用 int()/float() 转换比较（同 test_trials_data 口径）。

# 8 条因子 id 白名单（规格 §3 既定清单；测试独立持有，不引用 GameDB 常量）
const FACTOR_IDS: Array[String] = [
	"enemy_haste", "melee_drops", "energy_tax", "bullet_haste",
	"bargain_ban", "narrow_vision", "elite_surge", "single_element",
]
const DATE := "2026-09-01"

var _sut: TrialSystem


func before_test() -> void:
	_sut = TrialSystem.new()   # RefCounted 纯逻辑，无需 auto_free


func after_test() -> void:
	RunState.start_run("vanguard")   # 试炼局改写全局种子/楼层 → 复位（跨套件卫生）


# ================================================================ 每日种子

func test_daily_seed_stable_for_same_date() -> void:
	var s1 := _sut.daily_seed(DATE)
	assert_int(s1).is_not_equal(0)
	assert_int(_sut.daily_seed(DATE)).is_equal(s1)
	assert_int(TrialSystem.new().daily_seed(DATE)).is_equal(s1)   # 新实例同值

func test_daily_seed_differs_across_dates() -> void:
	assert_int(_sut.daily_seed("2026-09-01")).is_not_equal(_sut.daily_seed("2026-09-02"))
	assert_int(_sut.daily_seed("2026-09-01")).is_not_equal(_sut.daily_seed("2026-08-31"))
	assert_int(_sut.daily_seed("2026-09-01")).is_not_equal(_sut.daily_seed("2027-09-01"))

func test_salt_trial_constant() -> void:
	assert_str(RunState.SALT_TRIAL).is_equal("trial")


# ================================================================ 业务日（纯函数）

func _dt(year: int, month: int, day: int, hour: int, minute: int) -> Dictionary:
	# Time.get_datetime_dict_from_system() 同形字典（多余键 weekday 由 business_date 忽略）
	return {"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": 0, "weekday": 3}

func test_business_date_before_refresh_belongs_to_previous_day() -> void:
	assert_str(_sut.business_date(_dt(2026, 9, 1, 4, 59))).is_equal("2026-08-31")
	assert_str(_sut.business_date(_dt(2026, 9, 1, 0, 0))).is_equal("2026-08-31")

func test_business_date_at_and_after_refresh_is_same_day() -> void:
	assert_str(_sut.business_date(_dt(2026, 9, 1, 5, 0))).is_equal("2026-09-01")
	assert_str(_sut.business_date(_dt(2026, 9, 1, 12, 0))).is_equal("2026-09-01")
	assert_str(_sut.business_date(_dt(2026, 9, 1, 23, 59))).is_equal("2026-09-01")

func test_business_date_month_and_year_boundaries() -> void:
	assert_str(_sut.business_date(_dt(2026, 3, 1, 4, 59))).is_equal("2026-02-28")   # 平年 2 月
	assert_str(_sut.business_date(_dt(2027, 1, 1, 4, 59))).is_equal("2026-12-31")   # 跨年
	assert_str(_sut.business_date(_dt(2028, 3, 1, 4, 59))).is_equal("2028-02-29")   # 闰年 2 月

func test_today_date_matches_business_date_of_system_clock() -> void:
	# 全卡唯一墙钟直读点（豁免口径）：today_date == business_date(系统字典)
	assert_str(_sut.today_date()).has_length(10)
	assert_str(_sut.today_date()) \
		.is_equal(_sut.business_date(Time.get_datetime_dict_from_system()))


# ================================================================ 因子抽取

func test_pick_factors_exact_pair_sorted_whitelisted() -> void:
	var picked := _sut.pick_factors(DATE)
	assert_int(picked.size()).is_equal(2)
	for id: String in picked:
		assert_bool(FACTOR_IDS.has(id)) \
			.override_failure_message("picked '%s' not in whitelist" % id) \
			.is_true()
	assert_bool(picked[0] < picked[1]).is_true()   # id 升序（同日跨会话组合一致的前提）

func test_pick_factors_deterministic_across_calls_and_instances() -> void:
	var first := _sut.pick_factors(DATE)
	assert_array(first).is_equal(_sut.pick_factors(DATE))
	assert_array(TrialSystem.new().pick_factors(DATE)).is_equal(first)
	# 另一日期同样跨实例一致
	var other := _sut.pick_factors("2026-01-02")
	assert_array(TrialSystem.new().pick_factors("2026-01-02")).is_equal(other)

func test_pick_factors_has_no_side_effect_on_global_rng() -> void:
	# 裁定③：预览/抽取不得改写全局 RngSvc.run_seed（主菜单预览须无副作用）
	RngSvc.setup_run(12345)
	_sut.pick_factors(DATE)
	_sut.pick_mods(DATE)
	assert_int(RngSvc.run_seed).is_equal(12345)

func test_pick_rng_seed_equals_runstate_stream_derivation() -> void:
	# 裁定③ 防实现漂移：setup_run(daily_seed) 后 RunState.stream(SALT_TRIAL)（floor_idx=0）
	# 的派生种子与首抽序列必须与抽取局部流完全一致。
	RngSvc.setup_run(_sut.daily_seed(DATE))
	var saved_floor := RunState.floor_idx
	RunState.floor_idx = 0
	var via_state: RandomNumberGenerator = RunState.stream(RunState.SALT_TRIAL)
	RunState.floor_idx = saved_floor
	var local := RandomNumberGenerator.new()
	local.seed = _sut._pick_rng_seed(DATE)
	assert_int(via_state.seed).is_equal(local.seed)
	for _i in 8:
		assert_int(via_state.randi()).is_equal(local.randi())

func test_pick_factors_matches_reference_shuffle_via_runstate_stream() -> void:
	# 参考实现：用 RunState.stream(SALT_TRIAL)（floor_idx=0）驱动同一洗牌算法，
	# 输出与 pick_factors 全等（派生链 + 抽取算法双钉死）。
	RngSvc.setup_run(_sut.daily_seed(DATE))
	var saved_floor := RunState.floor_idx
	RunState.floor_idx = 0
	var rng: RandomNumberGenerator = RunState.stream(RunState.SALT_TRIAL)
	RunState.floor_idx = saved_floor
	var ids: Array[String] = []
	for id: String in GameDB.trials:
		ids.append(id)
	ids.sort()
	for i: int in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var expected: Array[String] = ids.slice(0, 2)
	expected.sort()
	assert_array(_sut.pick_factors(DATE)).is_equal(expected)

func test_pick_mods_merges_both_factors() -> void:
	# pick_mods = 当日两因子 mods 的并集（8 因子键互不相交 → 并集即拼接）
	var expected: Dictionary = {}
	for id: String in _sut.pick_factors(DATE):
		var row: Dictionary = GameDB.trials[id]
		var factor_mods: Dictionary = row["mods"]
		for k: String in factor_mods:
			expected[k] = factor_mods[k]
	var merged := _sut.pick_mods(DATE)
	assert_int(merged.size()).is_equal(expected.size())
	for k: String in expected:
		assert_bool(merged.has(k)).is_true()
		assert_that(merged[k]).is_equal(expected[k])


# ================================================================ RunState 试炼开局注入

func test_start_trial_run_injects_seed_flags_and_mods() -> void:
	RunState.start_trial_run("vanguard", DATE)
	assert_bool(RunState.is_trial_run).is_true()
	assert_int(RunState.run_seed).is_equal(_sut.daily_seed(DATE))
	assert_int(RngSvc.run_seed).is_equal(RunState.run_seed)   # 种子激活契约
	assert_int(RunState.floor_idx).is_equal(1)
	# mods = 当日两因子 mods 的并集（单点注入完整）
	var expected: Dictionary = {}
	for id: String in _sut.pick_factors(DATE):
		var factor_mods: Dictionary = (GameDB.trials[id] as Dictionary)["mods"]
		for k: String in factor_mods:
			expected[k] = factor_mods[k]
	assert_int(RunState.mods.size()).is_equal(expected.size())
	for k: String in expected:
		assert_bool(RunState.mods.has(k)) \
			.override_failure_message("RunState.mods missing '%s'" % k) \
			.is_true()
		assert_that(RunState.mods[k]).is_equal(expected[k])

func test_start_trial_run_same_date_same_seed_regardless_of_hero() -> void:
	# 种子不含角色 id（§2 同日所有人同布局）
	RunState.start_trial_run("vanguard", DATE)
	var seed1 := RunState.run_seed
	RunState.start_trial_run("ranger", DATE)
	assert_int(RunState.run_seed).is_equal(seed1)
	assert_bool(RunState.is_trial_run).is_true()

func test_start_run_resets_trial_fields() -> void:
	# 试炼后开普通局不留残 mods / is_trial_run
	RunState.start_trial_run("vanguard", DATE)
	assert_bool(RunState.mods.is_empty()).is_false()
	assert_bool(RunState.is_trial_run).is_true()
	RunState.start_run("ranger")
	assert_bool(RunState.is_trial_run).is_false()
	assert_dict(RunState.mods).is_empty()


# ================================================================ GameDB 正式接线（真实数据）

func test_gamedb_trials_loads_all_eight_factors() -> void:
	assert_int(GameDB.trials.size()).is_equal(8)
	for id: String in FACTOR_IDS:
		assert_bool(GameDB.trials.has(id)).is_true()
		var row: Dictionary = GameDB.trials[id]
		assert_str(str(row.get("name", ""))).is_not_empty()
		assert_str(str(row.get("desc", ""))).is_not_empty()
		assert_dict(row.get("mods", {})).is_not_empty()

func test_gamedb_trials_values_match_spec_section3() -> void:
	# §3 表数值（mods 键互不相交 → 8 因子并集 = 10 键）；
	# 整值经 GameDB 装载器 _deep_int_restore 还原（20 → int 20）
	var expected := {
		"enemy_speed_pct": 20, "enemy_attack_speed_pct": 20,
		"drop_melee_only": true, "energy_cost_mult": 1.5,
		"bullet_speed_pct": 25, "shop_discount_pct": 50, "no_hearts": true,
		"vision_scale": 0.65, "elite_bonus_pct": 100, "force_element": "random",
	}
	var merged: Dictionary = {}
	for id: String in GameDB.trials:
		var mods: Dictionary = GameDB.trials[id]["mods"]
		for k: String in mods:
			merged[k] = mods[k]
	assert_int(merged.size()).is_equal(expected.size())
	for k: String in expected:
		assert_bool(merged.has(k)) \
			.override_failure_message("merged mods missing '%s'" % k) \
			.is_true()
		if expected[k] is float:
			assert_float(float(merged[k])).is_equal_approx(expected[k], 0.0001)
		else:
			assert_that(merged[k]).is_equal(expected[k])


# ================================================================ 坏文件 fail-closed（裁定⑥）

func _fresh_db() -> Variant:
	# 全新实例不进树（不触发 _ready 的 quit），同 test_game_db 既定模式
	return auto_free(load("res://autoload/game_db.gd").new())

func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null

func _factor(id: String, mods: Dictionary) -> Dictionary:
	return {"id": id, "name": "测试因子", "desc": "测试描述", "mods": mods}

func _valid_factor(id: String) -> Dictionary:
	# §3 表原值（数值域唯一出处）
	var mods := {
		"enemy_haste": {"enemy_speed_pct": 20, "enemy_attack_speed_pct": 20},
		"melee_drops": {"drop_melee_only": true},
		"energy_tax": {"energy_cost_mult": 1.5},
		"bullet_haste": {"bullet_speed_pct": 25},
		"bargain_ban": {"shop_discount_pct": 50, "no_hearts": true},
		"narrow_vision": {"vision_scale": 0.65},
		"elite_surge": {"elite_bonus_pct": 100},
		"single_element": {"force_element": "random"},
	}
	return _factor(id, mods[id])

func _all_valid_factors() -> Array:
	var factors: Array = []
	for id: String in FACTOR_IDS:
		factors.append(_valid_factor(id))
	return factors

func _trials_json(factors: Array, overrides: Dictionary = {}, drop_factors := false) -> String:
	var data := {"version": 1, "refresh_hour": 5, "pick_per_day": 2,
		"reward_gem_multiplier": 1.5, "factors": factors}
	for k: String in overrides:
		data[k] = overrides[k]
	if drop_factors:
		data.erase("factors")
	return JSON.stringify(data)

## 坏形断言单点：load_ok=false 且整表拒收（返回空 dict）
func _assert_reject(json: String, ctx: String) -> void:
	var path := "user://test_bad_trials_%d.json" % absi(randi())
	_write_json(path, json)
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_trials(path)
	assert_bool(db.load_ok) \
		.override_failure_message("%s: load_ok should be false" % ctx) \
		.is_false()
	assert_dict(loaded) \
		.override_failure_message("%s: table must be empty on reject" % ctx) \
		.is_empty()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_bad_trials_missing_factors_key() -> void:
	_assert_reject(_trials_json(_all_valid_factors(), {}, true), "missing factors")

func test_bad_trials_empty_or_nine_factors() -> void:
	_assert_reject(_trials_json([]), "empty factors")
	var factors := _all_valid_factors()
	factors.append(_valid_factor("enemy_haste"))   # 第 9 条
	_assert_reject(_trials_json(factors), "9 factors")

func test_bad_trials_duplicate_id() -> void:
	var factors := _all_valid_factors()
	factors[7] = _valid_factor("enemy_haste")   # 仍 8 条但重复 id（缺 single_element）
	_assert_reject(_trials_json(factors), "duplicate id")

func test_bad_trials_unknown_factor_id() -> void:
	var factors := _all_valid_factors()
	factors[0] = _factor("mystery_factor", {"enemy_speed_pct": 20})
	_assert_reject(_trials_json(factors), "unknown factor id")

func test_bad_trials_unknown_mod_key() -> void:
	var factors := _all_valid_factors()
	factors[0] = _factor("enemy_haste", {"enemy_speed_pct": 20, "haste_bonus": 1})
	_assert_reject(_trials_json(factors), "unknown mod key")

func test_bad_trials_force_element_invalid() -> void:
	var factors := _all_valid_factors()
	factors[7] = _factor("single_element", {"force_element": "fire"})
	_assert_reject(_trials_json(factors), "force_element='fire'")

func test_bad_trials_bool_wrong_type() -> void:
	var factors := _all_valid_factors()
	factors[1] = _factor("melee_drops", {"drop_melee_only": 1})   # 数字冒充布尔
	_assert_reject(_trials_json(factors), "bool mod as number")

func test_bad_trials_pct_out_of_domain() -> void:
	var factors := _all_valid_factors()
	factors[0] = _factor("enemy_haste", {"enemy_speed_pct": 120, "enemy_attack_speed_pct": 20})
	_assert_reject(_trials_json(factors), "pct 120 out of (0, 100]")
	factors[0] = _factor("enemy_haste", {"enemy_speed_pct": 0, "enemy_attack_speed_pct": 20})
	_assert_reject(_trials_json(factors), "pct 0 out of (0, 100]")

func test_bad_trials_fixed_value_mismatch() -> void:
	var factors := _all_valid_factors()
	factors[2] = _factor("energy_tax", {"energy_cost_mult": 1.2})   # §3 定值 1.5
	_assert_reject(_trials_json(factors), "energy_cost_mult=1.2")

func test_bad_trials_top_level_scalar_mismatches() -> void:
	_assert_reject(_trials_json(_all_valid_factors(), {"version": 2}), "version=2")
	_assert_reject(_trials_json(_all_valid_factors(), {"refresh_hour": 4}), "refresh_hour=4")
	_assert_reject(_trials_json(_all_valid_factors(), {"pick_per_day": 3}), "pick_per_day=3")
	_assert_reject(_trials_json(_all_valid_factors(), {"reward_gem_multiplier": 2.0}),
		"reward_gem_multiplier=2.0")

func test_bad_trials_missing_file() -> void:
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_trials("user://test_missing_trials_b00d.json")
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()

func test_bad_trials_malformed_json() -> void:
	_assert_reject("{", "malformed json")
