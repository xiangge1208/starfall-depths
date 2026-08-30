class_name TestTalentsData
extends GdUnitTestSuite
## M2-T2 天赋树数据卡契约测试：24 节点 / 三系各 8 / schema fail-closed / 无环 /
## effects 键白名单（复用 buff_manager 键 + talent_ 前缀新键）/ 经济数学锁定。
## 经济数学（附录 I）：蓝晶速率取 M1 门禁校准 500~700/h。
##   保守 500/h、中值 600/h；总价 10000 → 60% = 6000 = 10h × 600/h（成本口径主契约）；
##   节点口径：最便宜 15 节点（62.5% ≥ 60%）累计 4100 ≤ 10h × 500/h（保守速率也达标）。
##   价格随 tier 单调（validate_talent_refs 强制前置层更低），「最便宜优先」购买集必为合法前置闭包。

const DESIGN_TOTAL_COST := 10000
const DESIGN_CHEAPEST_15 := 4100
const GEM_RATE_CONSERVATIVE := 500   # 蓝晶/h，M1 门禁下限
const GEM_RATE_MIDPOINT := 600       # 蓝晶/h，M1 门禁区间中值


func test_24_nodes_loaded() -> void:
	assert_int(GameDB.talents.size()).is_equal(24)
	assert_bool(GameDB.load_ok).is_true()


func test_three_branches_eight_each() -> void:
	var counts := {"red": 0, "blue": 0, "green": 0}
	for id: String in GameDB.talents:
		var row: Dictionary = GameDB.talents[id]
		assert_bool(counts.has(row["branch"])).is_true()
		counts[row["branch"]] = int(counts[row["branch"]]) + 1
	assert_int(counts["red"]).is_equal(8)
	assert_int(counts["blue"]).is_equal(8)
	assert_int(counts["green"]).is_equal(8)


func test_tiers_one_to_eight_unique_per_branch() -> void:
	# 每系 tier 1..8 各恰一节点（同分支同层唯一 → 价格梯度天然单调）
	var seen := {"red": {}, "blue": {}, "green": {}}
	for id: String in GameDB.talents:
		var row: Dictionary = GameDB.talents[id]
		var tier := int(row["tier"])
		assert_int(tier).is_between(1, 8)
		assert_bool((seen[row["branch"]] as Dictionary).has(tier)).is_false()
		(seen[row["branch"]] as Dictionary)[tier] = true
	for branch: String in ["red", "blue", "green"]:
		assert_int((seen[branch] as Dictionary).size()).is_equal(8)


func test_schema_shape_all_rows() -> void:
	for id: String in GameDB.talents:
		var row: Dictionary = GameDB.talents[id]
		assert_array(GameDB.validate_row(row, GameDB.TALENT_SCHEMA)).is_empty()
		assert_str(row["id"]).is_equal(id)
		assert_str(row["name"]).is_not_empty()
		assert_str(row["desc"]).is_not_empty()


func test_requires_exist_and_lower_tier() -> void:
	assert_array(GameDB.validate_talent_refs(GameDB.talents)).is_empty()


func test_real_table_acyclic() -> void:
	assert_bool(GameDB.validate_talent_acyclic(GameDB.talents)).is_true()


func test_acyclic_detects_two_node_cycle() -> void:
	# 控制器规格：手工构造双节点互指样本
	var nodes := {
		"a": {"id": "a", "requires": ["b"]},
		"b": {"id": "b", "requires": ["a"]},
	}
	assert_bool(GameDB.validate_talent_acyclic(nodes)).is_false()


func test_acyclic_detects_self_cycle_and_passes_dag() -> void:
	assert_bool(GameDB.validate_talent_acyclic({"a": {"requires": ["a"]}})).is_false()
	assert_bool(GameDB.validate_talent_acyclic({})).is_true()
	var dag := {
		"a": {"requires": []},
		"b": {"requires": ["a"]},
		"c": {"requires": ["a", "b"]},
	}
	assert_bool(GameDB.validate_talent_acyclic(dag)).is_true()


func _valid_row() -> Dictionary:
	return {
		"id": "t", "name": "测试节点", "desc": "测试用", "branch": "red",
		"tier": 1, "cost": 100, "requires": [],
		"effects": {"talent_dmg_pct": 0.03},
	}


func test_row_validator_rejects_bad_branch_tier_cost() -> void:
	var b := _valid_row()
	b["branch"] = "purple"
	assert_array(GameDB.validate_talent_row(b)).is_not_empty()
	var t := _valid_row()
	t["tier"] = 9
	assert_array(GameDB.validate_talent_row(t)).is_not_empty()
	var t2 := _valid_row()
	t2["tier"] = 0
	assert_array(GameDB.validate_talent_row(t2)).is_not_empty()
	var c := _valid_row()
	c["cost"] = 50   # 低于价格梯度下限 100
	assert_array(GameDB.validate_talent_row(c)).is_not_empty()
	var c2 := _valid_row()
	c2["cost"] = 900   # 高于价格梯度上限 800
	assert_array(GameDB.validate_talent_row(c2)).is_not_empty()


func test_row_validator_rejects_bad_requires() -> void:
	var r := _valid_row()
	r["requires"] = ["t"]   # 自指
	assert_array(GameDB.validate_talent_row(r)).is_not_empty()
	var d := _valid_row()
	d["requires"] = ["x", "x"]   # 重复前置（引用存在性由跨行校验负责）
	assert_array(GameDB.validate_talent_row(d)).is_not_empty()
	var s := _valid_row()
	s["requires"] = "a"   # 非 Array
	assert_array(GameDB.validate_talent_row(s)).is_not_empty()
	var n := _valid_row()
	n["requires"] = [5]   # 元素非 String
	assert_array(GameDB.validate_talent_row(n)).is_not_empty()


func test_row_validator_rejects_bad_effects() -> void:
	var e := _valid_row()
	e["effects"] = {}   # 空效果
	assert_array(GameDB.validate_talent_row(e)).is_not_empty()
	var u := _valid_row()
	u["effects"] = {"make_win_pct": 1.0}   # 白名单外私造键
	assert_array(GameDB.validate_talent_row(u)).is_not_empty()
	var big := _valid_row()
	big["effects"] = {"talent_dmg_pct": 0.20}   # 超出 GDD §14 基调（单节点 ≤ +10%）
	assert_array(GameDB.validate_talent_row(big)).is_not_empty()
	var neg := _valid_row()
	neg["effects"] = {"crit_pct": -0.05}   # 除 roll_cd_pct（负=缩短）外禁止负值
	assert_array(GameDB.validate_talent_row(neg)).is_not_empty()
	var frac := _valid_row()
	frac["effects"] = {"hp_max": 1.5}   # 整型键带小数
	assert_array(GameDB.validate_talent_row(frac)).is_not_empty()
	var rollpos := _valid_row()
	rollpos["effects"] = {"roll_cd_pct": 0.12}   # 该复用键约定负值 = 缩短（与 buffs.json 一致）
	assert_array(GameDB.validate_talent_row(rollpos)).is_not_empty()
	var bigroll := _valid_row()
	bigroll["effects"] = {"roll_cd_pct": -0.30}   # 幅度超键上限
	assert_array(GameDB.validate_talent_row(bigroll)).is_not_empty()


func test_effects_whitelist_no_dead_keys_and_prefixed_new_keys() -> void:
	var used := {}
	for id: String in GameDB.talents:
		var eff: Dictionary = GameDB.talents[id]["effects"]
		for k: String in eff:
			used[k] = true
			assert_bool(GameDB.TALENT_PCT_KEYS.has(k) or GameDB.TALENT_INT_KEYS.has(k)).is_true()
	# 白名单零死键：每个声明的键都必须至少被一个节点使用（NO new key without a stated consumer 的数据面）
	for k: String in GameDB.TALENT_PCT_KEYS:
		assert_bool(used.has(k)).is_true()
	for k: String in GameDB.TALENT_INT_KEYS:
		assert_bool(used.has(k)).is_true()
	# 复用键之外的新键必须带 talent_ 前缀（复用键 = buff_manager 聚合白名单同名键）
	for k: String in used:
		if not GameDB.BUFF_PCT_KEYS.has(k) and not GameDB.BUFF_INT_KEYS.has(k):
			assert_bool(k.begins_with("talent_")).is_true()


func test_total_cost_matches_10h_60pct_math() -> void:
	# 主契约（成本口径）：总价 10000 → 60% = 6000 蓝晶 = 10h × 600/h（M1 门禁 500~700/h 中值）。
	# 保守 500/h → 50%，乐观 700/h → 70%，设计点居中。
	var total := 0
	for id: String in GameDB.talents:
		total += int(GameDB.talents[id]["cost"])
	assert_int(total).is_equal(DESIGN_TOTAL_COST)
	assert_int(int(total * 0.6)).is_equal(GEM_RATE_MIDPOINT * 10)


func test_cheapest_15_nodes_affordable_in_10h_conservative() -> void:
	# 节点口径：最便宜 15 节点（15/24 = 62.5% ≥ 60%）累计 4100 ≤ 10h × 500/h（保守速率下限）。
	var costs := []
	for id: String in GameDB.talents:
		costs.append(int(GameDB.talents[id]["cost"]))
	costs.sort()
	var sum := 0
	for i in 15:
		sum += int(costs[i])
	assert_int(sum).is_equal(DESIGN_CHEAPEST_15)
	assert_bool(sum <= GEM_RATE_CONSERVATIVE * 10).is_true()


func test_branch_cost_totals() -> void:
	# 红 3400 / 蓝 3300 / 绿 3300（攻击系毕业优先向稍贵），合计 10000
	var by := {"red": 0, "blue": 0, "green": 0}
	for id: String in GameDB.talents:
		var row: Dictionary = GameDB.talents[id]
		by[row["branch"]] = int(by[row["branch"]]) + int(row["cost"])
	assert_int(by["red"]).is_equal(3400)
	assert_int(by["blue"]).is_equal(3300)
	assert_int(by["green"]).is_equal(3300)


func test_branch_effect_aggregates_match_design() -> void:
	# 附录 I「分支累计」设计值的机器锁定（百分键按千分位整型累加规避浮点误差；整型键原值累加）
	var sums := {}   # branch -> key -> int
	for id: String in GameDB.talents:
		var row: Dictionary = GameDB.talents[id]
		var eff: Dictionary = row["effects"]
		for k: String in eff:
			var bucket: Dictionary = sums.get_or_add(row["branch"], {})
			if GameDB.TALENT_INT_KEYS.has(k):
				bucket[k] = int(bucket.get(k, 0)) + int(eff[k])
			else:
				bucket[k] = int(bucket.get(k, 0)) + int(round(float(eff[k]) * 1000.0))
	var red: Dictionary = sums["red"]
	var blue: Dictionary = sums["blue"]
	var green: Dictionary = sums["green"]
	# 红/攻击：伤害 +8%、暴击 +6%、攻速 +6%、暴伤 +25%、异常积累 +10%、弹速 +8%、附魔概率 +5%
	assert_int(red["talent_dmg_pct"]).is_equal(80)
	assert_int(red["crit_pct"]).is_equal(60)
	assert_int(red["atk_speed_pct"]).is_equal(60)
	assert_int(red["crit_dmg_pct"]).is_equal(250)
	assert_int(red["status_rate_pct"]).is_equal(100)
	assert_int(red["bullet_speed_pct"]).is_equal(80)
	assert_int(red["element_proc_chance"]).is_equal(50)
	# 蓝/防御：HP +4、盾 +2、盾延时 -90 ticks(1.5s)、移速 +8%、翻滚 CD -12%、受击无敌帧 +10%
	assert_int(blue["hp_max"]).is_equal(4)
	assert_int(blue["shield_max"]).is_equal(2)
	assert_int(blue["shield_delay_reduction_ticks"]).is_equal(90)
	assert_int(blue["move_speed_pct"]).is_equal(80)
	assert_int(blue["roll_cd_pct"]).is_equal(-120)
	assert_int(blue["talent_hurt_iframe_pct"]).is_equal(100)
	# 绿/资源：能量上限 +40、金币 +15%、蓝晶 +15%、磁吸范围 +30%
	assert_int(green["energy_max"]).is_equal(40)
	assert_int(green["talent_coin_gain_pct"]).is_equal(150)
	assert_int(green["talent_gem_gain_pct"]).is_equal(150)
	assert_int(green["talent_pickup_radius_pct"]).is_equal(300)


func test_single_node_magnitude_within_gdd_tone() -> void:
	# 设计质量线：单节点 float 幅度 ≤ 键上限（crit_dmg 0.25 / pickup 0.30 按自身刻度放宽，其余 ≤ 0.10/0.15）
	for id: String in GameDB.talents:
		var eff: Dictionary = GameDB.talents[id]["effects"]
		for k: String in eff:
			var v := float(eff[k])
			if GameDB.TALENT_INT_KEYS.has(k):
				assert_int(int(v)).is_between(1, 100)
			else:
				assert_float(absf(v)).is_less_equal(float(GameDB.TALENT_KEY_MAX[k]))
				assert_float(v).is_not_equal(0.0)


func test_finalize_talents_fail_closed_on_cycle_and_bad_ref() -> void:
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var cyc := {
		"a": {"id": "a", "tier": 1, "requires": ["b"]},
		"b": {"id": "b", "tier": 2, "requires": ["a"]},
	}
	assert_dict(db._finalize_talents(cyc)).is_empty()
	var dangling := {"a": {"id": "a", "tier": 1, "requires": ["ghost"]}}
	assert_dict(db._finalize_talents(dangling)).is_empty()
	# 同层前置（违反「前置 tier 更低」设计规则）
	var same_tier := {
		"a": {"id": "a", "tier": 2, "requires": ["b"]},
		"b": {"id": "b", "tier": 2, "requires": []},
	}
	assert_dict(db._finalize_talents(same_tier)).is_empty()
	var ok := {
		"a": {"id": "a", "tier": 1, "requires": []},
		"b": {"id": "b", "tier": 2, "requires": ["a"]},
	}
	assert_dict(db._finalize_talents(ok)).is_not_empty()


func test_get_talent_returns_row() -> void:
	var t: Dictionary = GameDB.get_talent("red_apex")
	assert_str(t.get("name", "")).is_equal("处刑时刻")
	assert_int(t.get("tier", -1)).is_equal(8)
	assert_dict(GameDB.get_talent("no_such_talent")).is_empty()


func test_load_table_rejects_bad_talent_file_end_to_end() -> void:
	# 全链路 fail-closed：合法 schema 但跨行环 → 整表拒收（fresh-db 模式同 test_game_db）
	var path := "user://test_talent_cycle_61bf.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"a": %s, "b": %s}' % [
		_valid_json_row("a", 1, ["b"]), _valid_json_row("b", 2, ["a"]),
	])
	f = null
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var loaded: Dictionary = db._finalize_talents(
		db._load_table(path, GameDB.TALENT_SCHEMA, GameDB.TALENT_OPTIONAL, db.validate_talent_row))
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)


func _valid_json_row(id: String, tier: int, requires: Array) -> String:
	return ('{"id":"%s","name":"测试","desc":"测试","branch":"red","tier":%d,'
		+ '"cost":100,"requires":%s,"effects":{"talent_dmg_pct":0.03}}') % [id, tier, JSON.stringify(requires)]
