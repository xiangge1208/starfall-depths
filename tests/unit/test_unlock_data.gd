class_name TestUnlockData
extends GdUnitTestSuite
## M2-T3 图鉴解锁数据卡契约测试：res://data/unlock_tasks.json 独立 schema 校验。
## FileAccess 直读 + JSON.parse_string（数据卡先行模式，同 trials 卡），GameDB/存档
## 接线归 M2-T20（CodexSystem.progress）与 M2-T25（存档 v2 计数器持久化）。
## 覆盖：49 条计数、条件类型白名单（kill_x/clear_floor_x/craft_x/resonate_x/
## collect_gems_x/buy_x）、参数阈值 int、与 data/weapons.json 的 locked:true 集合
## 双向一致（任务 id 集合 == locked 武器 id 集合）、★熔铸限定 4 把 craft_x
## （编排者裁定③）+ forge_only 键、类型分布与紫→橙阈值梯度（附录 J 定稿值）锁定。
## 注意：JSON.parse_string 的数字一律为 float——_load_rows 按整值还原 int，
## 带小数留在 float 会被行级类型校验拒收（fail-closed）。

const UNLOCK_PATH := "res://data/unlock_tasks.json"

## 行 schema：7 键全部必填，无 optional；任一键缺失/类型错/语义校验失败 → 整行拒收。
const SCHEMA := {
	"id": TYPE_STRING, "weapon": TYPE_STRING, "type": TYPE_STRING,
	"param": TYPE_INT, "goal": TYPE_INT, "forge_only": TYPE_BOOL,
	"desc": TYPE_STRING,
}
## 条件类型白名单（计划卡 m2-t3）："_x" = 阈值 x 次/层/枚的模板位。
## 语义：kill_x=累计击杀；clear_floor_x=通过某层（param=层号 1..3）；craft_x=累计熔铸；
## resonate_x=累计元素共鸣；collect_gems_x=累计获得蓝晶；buy_x=累计商店购买。
## 全部可用遥测（Telemetry 行事件）或 RunState 判定，计数器持久化口径见附录 J。
const TYPE_WHITELIST: Array[String] = [
	"kill_x", "clear_floor_x", "craft_x", "resonate_x", "collect_gems_x", "buy_x",
]
## ★熔铸限定（附录 A）：4 把只能由附录 D 配方产出，解锁后也不入普通掉落池
## （forge_only=true，T20 图鉴引擎消费：解锁→进图鉴，掉落池仍排除）。
const FORGE_ONLY_IDS: Array[String] = ["xingyunpao", "leishenzhichui", "zhanjiandao", "yamiehexin"]
## 类型分布定稿（附录 J）：kill 15 / resonate 16 / clear_floor 7 / craft 5 / gems 3 / buy 3。
const TYPE_COUNTS := {
	"kill_x": 15, "resonate_x": 16, "clear_floor_x": 7,
	"craft_x": 5, "collect_gems_x": 3, "buy_x": 3,
}
## 阈值刻度 [min, max]（附录 J；紫=epic 前段 / 橙=legend 后段；
## clear_floor_x 按层号分档：紫=通过 A2、橙=通过 A3，goal=通过次数）。
const GOAL_BOUNDS := {
	"kill_x": {"epic": [300, 600], "legend": [900, 1200]},
	"resonate_x": {"epic": [120, 260], "legend": [800, 1000]},
	"clear_floor_x": {"epic": [1, 3], "legend": [1, 3]},
	"craft_x": {"legend": [6, 12]},
	"collect_gems_x": {"epic": [1000, 1200], "legend": [5000, 5000]},
	"buy_x": {"epic": [25, 30], "legend": [60, 60]},
}

var _rows: Dictionary = {}


func before_test() -> void:
	_rows = _load_rows()


func _load_rows() -> Dictionary:
	var rows := {}
	var f := FileAccess.open(UNLOCK_PATH, FileAccess.READ)
	if f == null:
		return rows
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return rows
	for id: String in parsed:
		var rowv: Variant = parsed[id]
		if rowv is Dictionary:
			var row: Dictionary = rowv
			for k: String in ["param", "goal"]:
				var v: Variant = row.get(k)
				# 整值还原（GameDB._normalize_row 同款口径）；带小数保持 float → 类型校验拒收
				if typeof(v) == TYPE_FLOAT and float(int(v)) == float(v):
					row[k] = int(v)
			rows[id] = row
	return rows


func _rarity(id: String) -> String:
	return str((GameDB.weapons_all.get(id, {}) as Dictionary).get("rarity", ""))


## 行级校验（schema 形状 + 语义，fail-closed）：返回错误列表，空 = 通过。
static func validate_unlock_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in SCHEMA:
		if not row.has(key):
			errors.append("missing key: %s" % key)
		elif typeof(row[key]) != SCHEMA[key]:
			errors.append("type mismatch: %s want %d got %d" % [key, SCHEMA[key], typeof(row[key])])
	if not errors.is_empty():
		return errors
	if str(row["id"]) != str(row["weapon"]):
		errors.append("id must equal weapon (task id = weapon id)")
	if not TYPE_WHITELIST.has(row["type"]):
		errors.append("bad type: %s" % str(row["type"]))
	var goal := int(row["goal"])
	var param := int(row["param"])
	if goal <= 0:
		errors.append("goal must be positive int: %d" % goal)
	if str(row["type"]) == "clear_floor_x":
		if param < 1 or param > 3:
			errors.append("clear_floor_x param must be floor 1..3: %d" % param)
	elif param != 0:
		errors.append("only clear_floor_x may carry nonzero param: %d" % param)
	if str(row["desc"]).is_empty():
		errors.append("desc must be non-empty")
	return errors


func _valid_row() -> Dictionary:
	return {
		"id": "testgun", "weapon": "testgun", "type": "kill_x",
		"param": 0, "goal": 300, "forge_only": false,
		"desc": "累计击杀 300 名敌人",
	}


func _goals_of(type: String, rarity: String) -> Array:
	var out := []
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		if str(row["type"]) != type or _rarity(id) != rarity:
			continue
		out.append(int(row["goal"]))
	return out


func _max_goal(type: String, rarity: String) -> int:
	var goals := _goals_of(type, rarity)
	return int(goals.max()) if not goals.is_empty() else -1


func _min_goal(type: String, rarity: String) -> int:
	var goals := _goals_of(type, rarity)
	return int(goals.min()) if not goals.is_empty() else 9999999


func test_file_readable_and_parses() -> void:
	assert_bool(FileAccess.file_exists(UNLOCK_PATH)).is_true()
	assert_that(FileAccess.open(UNLOCK_PATH, FileAccess.READ)).is_not_null()
	assert_dict(_rows).is_not_empty()


func test_exactly_49_tasks() -> void:
	assert_int(_rows.size()).is_equal(49)


func test_all_rows_pass_validator() -> void:
	for id: String in _rows:
		assert_array(validate_unlock_row(_rows[id])) \
			.override_failure_message("%s: %s" % [id, str(validate_unlock_row(_rows[id]))]) \
			.is_empty()


func test_row_key_set_exact_no_extras() -> void:
	for id: String in _rows:
		assert_int(_rows[id].size()).is_equal(SCHEMA.size())
		for key: String in SCHEMA:
			assert_bool(_rows[id].has(key)) \
				.override_failure_message("%s: missing %s" % [id, key]).is_true()
		assert_str(_rows[id]["id"]).is_equal(id)
		assert_str(_rows[id]["weapon"]).is_equal(id)


func test_param_and_goal_are_int() -> void:
	# JSON float 还原后必须为 int（带小数源数据会留在 float 而在此失败）
	for id: String in _rows:
		assert_int(typeof(_rows[id]["param"])).is_equal(TYPE_INT)
		assert_int(typeof(_rows[id]["goal"])).is_equal(TYPE_INT)
		assert_int(int(_rows[id]["goal"])).is_greater(0)


func test_bidirectional_match_with_weapons_locked_set() -> void:
	# 双向一致：任务 id 集合 == data/weapons.json 中 locked:true 的武器 id 集合
	var locked := {}
	for id: String in GameDB.weapons_all:
		if bool((GameDB.weapons_all[id] as Dictionary).get("locked", false)):
			locked[id] = true
	assert_int(locked.size()).is_equal(49)
	for id: String in _rows:
		assert_bool(locked.has(id)) \
			.override_failure_message("task %s is not a locked weapon" % id).is_true()
	for id: String in locked:
		assert_bool(_rows.has(id)) \
			.override_failure_message("locked weapon %s has no unlock task" % id).is_true()


func test_rarity_distribution_33_epic_16_legend() -> void:
	var epic := 0
	var legend := 0
	for id: String in _rows:
		var rarity := _rarity(id)
		assert_bool(rarity == "epic" or rarity == "legend") \
			.override_failure_message("%s: bad rarity %s" % [id, rarity]).is_true()
		if rarity == "epic":
			epic += 1
		elif rarity == "legend":
			legend += 1
	assert_int(epic).is_equal(33)
	assert_int(legend).is_equal(16)


func test_type_distribution_locked() -> void:
	var counts := {}
	for id: String in _rows:
		var t: String = _rows[id]["type"]
		assert_bool(TYPE_WHITELIST.has(t)).is_true()
		counts[t] = int(counts.get(t, 0)) + 1
	assert_int(counts.size()).is_equal(TYPE_COUNTS.size())
	for t: String in TYPE_COUNTS:
		assert_int(int(counts.get(t, 0))).is_equal(int(TYPE_COUNTS[t])) \
			.override_failure_message("type %s count mismatch" % t)


func test_forge_only_exactly_four_star_weapons() -> void:
	var flagged := 0
	for id: String in _rows:
		if bool(_rows[id]["forge_only"]):
			flagged += 1
			assert_bool(FORGE_ONLY_IDS.has(id)) \
				.override_failure_message("%s: forge_only but not a star weapon" % id).is_true()
	assert_int(flagged).is_equal(FORGE_ONLY_IDS.size())
	for id: String in FORGE_ONLY_IDS:
		assert_bool(_rows.has(id) and bool(_rows[id]["forge_only"])) \
			.override_failure_message("%s: star weapon missing forge_only" % id).is_true()


func test_star_weapons_use_craft_x_per_ruling() -> void:
	# 编排者裁定③：4 把★熔铸限定条件类型一律 craft_x（熔铸获取）
	for id: String in FORGE_ONLY_IDS:
		assert_str(_rows[id]["type"]).is_equal("craft_x")


func test_non_star_weapons_unlock_into_drop_pool() -> void:
	# 非★武器 forge_only 必为 false：解锁（T20）后即进普通掉落池；
	# ★解锁后仍只走熔铸产出（forge_only=true 是 T20 掉落过滤的依据键）
	for id: String in _rows:
		if not FORGE_ONLY_IDS.has(id):
			assert_bool(bool(_rows[id]["forge_only"])) \
				.override_failure_message("%s: non-star must not be forge_only" % id).is_false()


func test_goal_within_bounds_by_type_and_rarity() -> void:
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var t: String = row["type"]
		var rarity := _rarity(id)
		var bounds: Variant = (GOAL_BOUNDS[t] as Dictionary).get(rarity)
		if bounds == null:
			assert_bool(false) \
				.override_failure_message("%s: type %s not allowed for rarity %s" % [id, t, rarity]) \
				.is_true()
			continue
		assert_int(int(row["goal"])).is_between(int(bounds[0]), int(bounds[1])) \
			.override_failure_message("%s: goal %d outside %s/%s bounds" % [id, int(row["goal"]), t, rarity])


func test_goal_gradient_epic_below_legend() -> void:
	# 紫（epic）阈值前段 / 橙（legend）阈值后段；clear_floor_x 以层号分档（紫 A2 < 橙 A3）
	for t: String in ["kill_x", "resonate_x", "collect_gems_x"]:
		assert_int(_max_goal(t, "epic")).is_less(_min_goal(t, "legend")) \
			.override_failure_message("type %s: epic/legend goal bands overlap" % t)
	for id: String in _rows:
		if str(_rows[id]["type"]) == "clear_floor_x":
			var want_floor := 2 if _rarity(id) == "epic" else 3
			assert_int(int(_rows[id]["param"])).is_equal(want_floor) \
				.override_failure_message("%s: floor param must be %d" % [id, want_floor])


func test_desc_contains_goal_and_floor_numbers() -> void:
	# 图鉴 UI 直读 desc 作条件文案：阈值数字（与层数）必须与数据字段一致
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var desc: String = str(row["desc"])
		assert_bool(desc.contains(str(int(row["goal"])))) \
			.override_failure_message("%s: desc missing goal %d" % [id, int(row["goal"])]).is_true()
		if str(row["type"]) == "clear_floor_x":
			assert_bool(desc.contains(str(int(row["param"])))) \
				.override_failure_message("%s: desc missing floor %d" % [id, int(row["param"])]).is_true()


func test_row_validator_rejects_bad_type() -> void:
	var r := _valid_row()
	r["type"] = "headshot_x"
	assert_array(validate_unlock_row(r)).is_not_empty()


func test_row_validator_rejects_bad_goal_and_param() -> void:
	var zero := _valid_row()
	zero["goal"] = 0
	assert_array(validate_unlock_row(zero)).is_not_empty()
	var neg := _valid_row()
	neg["goal"] = -5
	assert_array(validate_unlock_row(neg)).is_not_empty()
	var frac := _valid_row()
	frac["goal"] = 300.5   # 带小数：非 int
	assert_array(validate_unlock_row(frac)).is_not_empty()
	var stray := _valid_row()
	stray["param"] = 2   # 非 clear_floor_x 携带参数
	assert_array(validate_unlock_row(stray)).is_not_empty()
	var floor_bad := _valid_row()
	floor_bad["type"] = "clear_floor_x"
	floor_bad["param"] = 4   # 层号越界（M2 共 3 层）
	assert_array(validate_unlock_row(floor_bad)).is_not_empty()
	var floor_ok := _valid_row()
	floor_ok["type"] = "clear_floor_x"
	floor_ok["param"] = 3
	floor_ok["desc"] = "通过第 3 层 3 次"
	assert_array(validate_unlock_row(floor_ok)).is_empty()


func test_row_validator_rejects_shape_errors() -> void:
	assert_array(validate_unlock_row({})).is_not_empty()
	var mismatch := _valid_row()
	mismatch["weapon"] = "othergun"   # 任务 id ≠ 目标武器 id
	assert_array(validate_unlock_row(mismatch)).is_not_empty()
	var empty_desc := _valid_row()
	empty_desc["desc"] = ""
	assert_array(validate_unlock_row(empty_desc)).is_not_empty()
	var wrong_bool := _valid_row()
	wrong_bool["forge_only"] = 1   # 非 bool
	assert_array(validate_unlock_row(wrong_bool)).is_not_empty()
