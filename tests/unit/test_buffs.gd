class_name TestBuffs
extends GdUnitTestSuite
## M1 t9：增益系统。数据层（buffs.json + GameDB 加载）与 BuffManager（三选一/聚合落地）。
## 稀有度：common 白 / uncommon 绿 / rare 蓝；具名清单 16 条 = 白9 + 绿5 + 蓝2。

const ALL_IDS: Array[String] = [
	"fire_enchant", "ice_enchant", "poison_enchant", "shock_enchant",
	"bullet_speed", "precision", "vigor", "shield_tune",
	"swift_trigger", "deadly", "status_erode", "quick_charge",
	"energy_max", "roll_master",
	"extra_projectiles", "crit_detonate",
]
const EFFECT_WHITELIST: Array[String] = [
	"move_speed_pct", "crit_pct", "crit_dmg_pct", "atk_speed_pct",
	"bullet_speed_pct", "hp_max", "shield_max", "energy_max",
	"shield_delay_reduction_ticks", "roll_cd_pct", "element_enchant",
	"element_proc_chance", "status_rate_pct", "extra_projectiles", "crit_detonate_pct",
]

# ---- 数据层：buffs.json 经 GameDB fail-closed 加载 ----

func test_buffs_table_loaded_16_rows() -> void:
	assert_int(GameDB.buffs.size()).is_equal(16)
	for id in ALL_IDS:
		assert_dict(GameDB.buffs).contains_keys(id)

func test_buff_rarity_counts_follow_appendix_c_9_5_2() -> void:
	var counts := {"common": 0, "uncommon": 0, "rare": 0}
	for id: String in GameDB.buffs:
		var r: String = GameDB.buffs[id]["rarity"]
		counts[r] = int(counts[r]) + 1
	assert_int(counts["common"]).is_equal(9)
	assert_int(counts["uncommon"]).is_equal(5)
	assert_int(counts["rare"]).is_equal(2)

func test_buff_rows_chinese_names() -> void:
	assert_str(GameDB.get_buff("fire_enchant").get("name", "")).is_equal("火焰附魔")
	assert_str(GameDB.get_buff("vigor").get("name", "")).is_equal("强健")
	assert_str(GameDB.get_buff("swift_trigger").get("name", "")).is_equal("迅捷扳机")
	assert_str(GameDB.get_buff("extra_projectiles").get("name", "")).is_equal("散弹扩张")
	assert_str(GameDB.get_buff("crit_detonate").get("name", "")).is_equal("暴虐回响")

func test_buff_effects_whitelist_keys_only() -> void:
	for id: String in GameDB.buffs:
		var eff: Dictionary = GameDB.buffs[id]["effects"]
		assert_bool(eff.is_empty()).is_false()          # 每条增益必须至少一个效果
		for k: String in eff:
			assert_bool(EFFECT_WHITELIST.has(k)) \
				.override_failure_message("buff %s has unknown effect key %s" % [id, k]) \
				.is_true()

func test_buff_effect_value_types_normalized() -> void:
	# _normalize_row 之后：整数值得为 int，百分比值得为数值（float）
	var vigor: Dictionary = GameDB.get_buff("vigor")
	assert_int(vigor["effects"].get("hp_max", -1)).is_equal(2)
	var precision: Dictionary = GameDB.get_buff("precision")
	assert_float(precision["effects"].get("crit_pct", -1.0)).is_equal_approx(0.06, 0.0001)
	var quick: Dictionary = GameDB.get_buff("quick_charge")
	assert_int(quick["effects"].get("shield_delay_reduction_ticks", -1)).is_equal(60)  # 3.0s→2.0s
	var roll: Dictionary = GameDB.get_buff("roll_master")
	assert_float(roll["effects"].get("roll_cd_pct", 0.0)).is_equal_approx(-0.15, 0.0001)

func test_enchant_rows_map_elements_id() -> void:
	assert_int(GameDB.get_buff("fire_enchant")["effects"]["element_enchant"]).is_equal(Elements.Id.FIRE)
	assert_int(GameDB.get_buff("ice_enchant")["effects"]["element_enchant"]).is_equal(Elements.Id.ICE)
	assert_int(GameDB.get_buff("poison_enchant")["effects"]["element_enchant"]).is_equal(Elements.Id.POISON)
	assert_int(GameDB.get_buff("shock_enchant")["effects"]["element_enchant"]).is_equal(Elements.Id.SHOCK)
	assert_float(GameDB.get_buff("fire_enchant")["effects"]["element_proc_chance"]).is_equal(0.2)
	assert_float(GameDB.get_buff("ice_enchant")["effects"]["element_proc_chance"]).is_equal(0.2)
	assert_float(GameDB.get_buff("poison_enchant")["effects"]["element_proc_chance"]).is_equal(0.2)
	assert_float(GameDB.get_buff("shock_enchant")["effects"]["element_proc_chance"]).is_equal(0.15)

func test_uniques_are_rare_two() -> void:
	for id in ["extra_projectiles", "crit_detonate"]:
		assert_str(GameDB.get_buff(id).get("rarity", "")).is_equal("rare")

# ---- GameDB：validate_buff_row 语义校验（fail-closed 同 rooms 路径） ----

func _valid_buff_row(id: String) -> Dictionary:
	return {"id": id, "name": "测试", "rarity": "common", "desc": "测试用",
		"effects": {"hp_max": 1}}

func test_validate_buff_row_accepts_valid() -> void:
	assert_int(GameDB.validate_buff_row(_valid_buff_row("t9x")).size()).is_equal(0)

func test_validate_buff_row_rejects_unknown_effect_key() -> void:
	var row := _valid_buff_row("t9x")
	row["effects"] = {"laser_sight": 1}
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_bad_rarity() -> void:
	var row := _valid_buff_row("t9x")
	row["rarity"] = "legendary"
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_fractional_int_effect() -> void:
	var row := _valid_buff_row("t9x")
	row["effects"] = {"hp_max": 1.5}
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_empty_effects() -> void:
	var row := _valid_buff_row("t9x")
	row["effects"] = {}
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_requires_element_and_chance_pair() -> void:
	var element_only := _valid_buff_row("element_only")
	element_only["effects"] = {"element_enchant": Elements.Id.FIRE}
	assert_int(GameDB.validate_buff_row(element_only).size()).is_greater(0)
	var chance_only := _valid_buff_row("chance_only")
	chance_only["effects"] = {"element_proc_chance": 0.2}
	assert_int(GameDB.validate_buff_row(chance_only).size()).is_greater(0)
	var bad_chance := _valid_buff_row("bad_chance")
	bad_chance["effects"] = {"element_enchant": Elements.Id.FIRE, "element_proc_chance": 0.0}
	assert_int(GameDB.validate_buff_row(bad_chance).size()).is_greater(0)

func test_get_buff_unknown_returns_empty() -> void:
	assert_dict(GameDB.get_buff("no_such_buff")).is_empty()

# ---- BuffManager：三选一抽取 ----

func _mgr() -> BuffManager:
	return BuffManager.new()

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_pick_appends_and_guards() -> void:
	var bm := _mgr()
	bm.pick("vigor")
	bm.pick("no_such_buff")               # 未知 id 拒绝
	assert_int(bm.picked.size()).is_equal(1)
	bm.pick("extra_projectiles")
	bm.pick("extra_projectiles")          # 唯一项二次 pick 拒绝（fail-closed 防线）
	assert_int(bm.picked.size()).is_equal(2)
	bm.pick("vigor")                      # 普通项可重复 append（强化可叠加）
	assert_int(bm.picked.size()).is_equal(3)

func test_roll_three_returns_three_distinct() -> void:
	var bm := _mgr()
	var got: Array[String] = bm.roll_three(_rng(20260828))
	assert_int(got.size()).is_equal(3)
	var seen := {}
	for id in got:
		seen[id] = true
		assert_dict(GameDB.buffs).contains_keys(id)   # 必须是合法池内 id
	assert_int(seen.size()).is_equal(3)               # 单次三选内不重复

func test_roll_three_common_share_within_band() -> void:
	# 固定 seed 抽 1000 次 × 3 = 3000 抽；权重白55/绿30/蓝15 → 白占比应落在 50~60%
	var bm := _mgr()
	var rng := _rng(20260828)
	var common_draws := 0
	var total_draws := 0
	for i in 1000:
		for id in bm.roll_three(rng):
			total_draws += 1
			if GameDB.buffs[id]["rarity"] == "common":
				common_draws += 1
	assert_int(total_draws).is_equal(3000)
	var share := float(common_draws) / float(total_draws)
	assert_float(share).is_greater_equal(0.50)
	assert_float(share).is_less_equal(0.60)

func test_unique_removed_from_pool_after_pick() -> void:
	var bm := _mgr()
	bm.pick("extra_projectiles")
	assert_bool(bm.available_pool().has("extra_projectiles")).is_false()
	var rng := _rng(42)
	for i in 200:                         # 抽 200 次三选，唯一项不得再出现
		for id in bm.roll_three(rng):
			assert_bool(id == "extra_projectiles") \
				.override_failure_message("picked unique extra_projectiles re-rolled") \
				.is_false()

func test_non_unique_stays_available_after_pick() -> void:
	# 唯一移除仅限唯一项；普通增益可重复出现（强化可叠加）
	var bm := _mgr()
	bm.pick("vigor")
	assert_bool(bm.available_pool().has("vigor")).is_true()
	assert_int(bm.available_pool().size()).is_equal(16)

func test_roll_three_pool_exhaustion() -> void:
	# 池 < 3 → 返回剩余全部；池空 → 返回空数组
	var bm2 := TwoPool.new()
	assert_int(bm2.roll_three(_rng(7)).size()).is_equal(2)
	var bm0 := EmptyPool.new()
	assert_int(bm0.roll_three(_rng(7)).size()).is_equal(0)

class TwoPool extends BuffManager:
	func available_pool() -> Array[String]:
		return ["vigor", "deadly"]        # 均为 GameDB.buffs 内合法 id

class EmptyPool extends BuffManager:
	func available_pool() -> Array[String]:
		return []

# ---- BuffManager：聚合落地 ----

func test_apply_to_player_hp_stacks() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("vigor")
	bm.pick("vigor")                      # 强健 ×2 → +4 HP（可叠加）
	bm.pick("shield_tune")
	bm.pick("energy_max")
	bm.apply_to_player(p)
	assert_int(p.hp_max).is_equal(12)     # 8 + 2 + 2
	assert_int(p.shield_max).is_equal(5)  # 4 + 1
	assert_int(p.energy_max).is_equal(125)  # 100 + 25

func test_apply_to_player_idempotent() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("vigor")
	bm.apply_to_player(p)
	bm.apply_to_player(p)                 # 重复 apply 按已取列表重算，不叠加
	assert_int(p.hp_max).is_equal(10)

func test_apply_to_player_writes_all_runtime_consumers() -> void:
	var p: Player = auto_free(Player.new())
	var bm := _mgr()
	for id in ["precision", "deadly", "status_erode", "quick_charge", "roll_master"]:
		bm.pick(id)
	bm.apply_to_player(p)
	assert_float(p.crit_bonus).is_equal_approx(0.06, 0.0001)
	assert_float(p.crit_damage_bonus).is_equal_approx(0.5, 0.0001)
	assert_float(p.status_rate_bonus).is_equal_approx(0.25, 0.0001)
	assert_int(p.shield_delay_reduction_ticks).is_equal(60)
	assert_float(p.roll_cd_pct).is_equal_approx(-0.15, 0.0001)

func test_drink_then_buff_and_buff_then_drink_have_same_result() -> void:
	var a: Player = auto_free(Player.new())
	DrinkMachine._apply_drink("crit_pct", 3, a)
	DrinkMachine._apply_drink("move_speed_pct", 5, a)
	var ba := _mgr(); ba.pick("precision"); ba.apply_to_player(a)
	var b: Player = auto_free(Player.new())
	var bb := _mgr(); bb.pick("precision"); bb.apply_to_player(b)
	DrinkMachine._apply_drink("crit_pct", 3, b)
	DrinkMachine._apply_drink("move_speed_pct", 5, b)
	assert_float(a.crit_bonus).is_equal_approx(b.crit_bonus, 0.0001)
	assert_float(a.move_speed).is_equal_approx(b.move_speed, 0.0001)
	assert_float(a.crit_bonus).is_equal_approx(0.09, 0.0001)
	assert_float(a.move_speed).is_equal_approx(84.0, 0.0001)

func test_apply_to_rig_writes_five_fields() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var bm := _mgr()
	bm.pick("swift_trigger")              # 攻速 +12%
	bm.pick("bullet_speed")               # 弹速 +15%
	bm.pick("fire_enchant")               # 附魔 → enchant_element
	bm.pick("extra_projectiles")          # 唯一：弹丸 +1
	bm.pick("crit_detonate")              # 唯一：暴击 20% 强制共鸣
	bm.apply_to_rig(rig)
	assert_float(rig.rate_mult).is_equal_approx(1.12, 0.0001)
	assert_float(rig.bullet_speed_mult).is_equal_approx(1.15, 0.0001)
	assert_int(rig.enchant_element).is_equal(Elements.Id.FIRE)
	assert_float(rig.enchant_proc_chance).is_equal_approx(0.2, 0.0001)
	assert_int(rig.bonus_projectiles).is_equal(1)
	assert_float(rig.crit_detonate_pct).is_equal_approx(0.2, 0.0001)

func test_apply_to_rig_idempotent_and_stacks() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var bm := _mgr()
	bm.pick("deadly")
	bm.pick("deadly")                     # 致命 ×2 → 暴伤聚合 +100%
	bm.apply_to_rig(rig)
	bm.apply_to_rig(rig)
	assert_float(bm.aggregate()["crit_dmg_pct"]).is_equal_approx(1.0, 0.0001)
	assert_float(rig.rate_mult).is_equal_approx(1.0, 0.0001)   # 未取攻速保持中性

func test_element_enchant_last_picked_wins() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var bm := _mgr()
	bm.pick("fire_enchant")
	bm.apply_to_rig(rig)
	assert_int(rig.enchant_element).is_equal(Elements.Id.FIRE)
	bm.pick("ice_enchant")
	bm.apply_to_rig(rig)                  # 同类附魔后取覆盖前取
	assert_int(rig.enchant_element).is_equal(Elements.Id.ICE)
	assert_float(rig.enchant_proc_chance).is_equal_approx(0.2, 0.0001)

func test_rig_fields_default_neutral() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	assert_int(rig.enchant_element).is_equal(Elements.Id.NONE)
	assert_float(rig.enchant_proc_chance).is_equal(0.0)
	assert_int(rig.bonus_projectiles).is_equal(0)
	assert_float(rig.crit_detonate_pct).is_equal(0.0)
	assert_float(rig.rate_mult).is_equal(1.0)
	assert_float(rig.bullet_speed_mult).is_equal(1.0)

func test_aggregate_sums_picked_effects() -> void:
	var bm := _mgr()
	bm.pick("precision")
	bm.pick("precision")
	assert_float(bm.aggregate()["crit_pct"]).is_equal_approx(0.12, 0.0001)
	assert_int(bm.aggregate()["hp_max"]).is_equal(0)           # 未取键为中性默认
	assert_int(bm.aggregate()["element_enchant"]).is_equal(Elements.Id.NONE)
