class_name TestBuffs
extends GdUnitTestSuite
## M1 t9 + M2 t12：增益系统。数据层（buffs.json + GameDB 加载）与 BuffManager
## （三选一/聚合落地）。稀有度：common 白 / uncommon 绿 / rare 蓝。
## 附录 C 全表 36 条 = 白15 + 绿11 + 蓝10（附录 C 实测清点；计划卡括号 14/12/10 为占位口径）。

const ALL_IDS: Array[String] = [
	# M1 t9 既有 16 条
	"fire_enchant", "ice_enchant", "poison_enchant", "shock_enchant",
	"bullet_speed", "precision", "vigor", "shield_tune",
	"swift_trigger", "deadly", "status_erode", "quick_charge",
	"energy_max", "roll_master",
	"extra_projectiles", "crit_detonate",
	# M2 t12 新增 20 条（附录 C 剩余）
	"hunter", "resonance_amp", "avenger",
	"anti_fire", "anti_ice", "anti_poison", "nerve_reflex", "carapace",
	"thorn_armor", "dash_extend", "phoenix",
	"wealth", "glutton", "pickup_magnet", "energy_siphon", "heart_sense",
	"ammo_convert", "haggle", "element_vision", "resonance_vision",
]
const EFFECT_WHITELIST: Array[String] = [
	# M1 t9 既有键
	"move_speed_pct", "crit_pct", "crit_dmg_pct", "atk_speed_pct",
	"bullet_speed_pct", "hp_max", "shield_max", "energy_max",
	"shield_delay_reduction_ticks", "roll_cd_pct", "element_enchant",
	"element_proc_chance", "status_rate_pct", "extra_projectiles", "crit_detonate_pct",
	# M2 t12 新增键（附录 C 全量键位）
	"dmg_vs_statused_pct", "resonance_radius_pct", "resonance_duration_ticks",
	"vengeance_pct", "vengeance_ticks",
	"anti_fire", "anti_ice", "anti_poison", "hurt_iframe_bonus_ticks",
	"bullet_dmg_taken_pct", "thorns_contact_dmg", "roll_distance_pct", "phoenix_flag",
	"wealth_pct", "drink_effect_pct", "pickup_radius_pct",
	"kill_energy_chance", "kill_energy_amount", "heart_sense_pct",
	"passive_energy_interval_ticks", "passive_energy_amount",
	"haggle_pct", "element_vision", "telegraph_bonus_ticks", "resonance_vision",
]
# 唯一增益（附录 C 标注「唯一」）：散弹扩张 / 暴虐回响 / 不死鸟
const UNIQUE_BUFFS: Array[String] = ["extra_projectiles", "crit_detonate", "phoenix"]

# ---- 数据层：buffs.json 经 GameDB fail-closed 加载 ----

func test_buffs_table_loaded_36_rows() -> void:
	assert_int(GameDB.buffs.size()).is_equal(36)
	for id in ALL_IDS:
		assert_dict(GameDB.buffs).contains_keys(id)

func test_buff_rarity_counts_follow_appendix_c_15_11_10() -> void:
	# 附录 C 实测清点：C.1 攻击 6白/3绿/5蓝 + C.2 防御 5白/5绿/2蓝 + C.3 资源 4白/3绿/3蓝
	var counts := {"common": 0, "uncommon": 0, "rare": 0}
	for id: String in GameDB.buffs:
		var r: String = GameDB.buffs[id]["rarity"]
		counts[r] = int(counts[r]) + 1
	assert_int(counts["common"]).is_equal(15)
	assert_int(counts["uncommon"]).is_equal(11)
	assert_int(counts["rare"]).is_equal(10)

func test_buff_rows_chinese_names() -> void:
	assert_str(GameDB.get_buff("fire_enchant").get("name", "")).is_equal("火焰附魔")
	assert_str(GameDB.get_buff("vigor").get("name", "")).is_equal("强健")
	assert_str(GameDB.get_buff("swift_trigger").get("name", "")).is_equal("迅捷扳机")
	assert_str(GameDB.get_buff("extra_projectiles").get("name", "")).is_equal("散弹扩张")
	assert_str(GameDB.get_buff("crit_detonate").get("name", "")).is_equal("暴虐回响")
	assert_str(GameDB.get_buff("hunter").get("name", "")).is_equal("猎杀者")
	assert_str(GameDB.get_buff("resonance_amp").get("name", "")).is_equal("共鸣增幅")
	assert_str(GameDB.get_buff("avenger").get("name", "")).is_equal("复仇者")
	assert_str(GameDB.get_buff("anti_fire").get("name", "")).is_equal("抗火")
	assert_str(GameDB.get_buff("anti_ice").get("name", "")).is_equal("抗冰")
	assert_str(GameDB.get_buff("anti_poison").get("name", "")).is_equal("抗毒")
	assert_str(GameDB.get_buff("nerve_reflex").get("name", "")).is_equal("神经反射")
	assert_str(GameDB.get_buff("carapace").get("name", "")).is_equal("甲壳")
	assert_str(GameDB.get_buff("thorn_armor").get("name", "")).is_equal("荆棘护甲")
	assert_str(GameDB.get_buff("dash_extend").get("name", "")).is_equal("冲刺延伸")
	assert_str(GameDB.get_buff("phoenix").get("name", "")).is_equal("不死鸟")
	assert_str(GameDB.get_buff("wealth").get("name", "")).is_equal("财富")
	assert_str(GameDB.get_buff("glutton").get("name", "")).is_equal("大胃王")
	assert_str(GameDB.get_buff("pickup_magnet").get("name", "")).is_equal("捡拾磁铁")
	assert_str(GameDB.get_buff("energy_siphon").get("name", "")).is_equal("蓝能汲取")
	assert_str(GameDB.get_buff("heart_sense").get("name", "")).is_equal("红心感应")
	assert_str(GameDB.get_buff("ammo_convert").get("name", "")).is_equal("弹药转化")
	assert_str(GameDB.get_buff("haggle").get("name", "")).is_equal("议价")
	assert_str(GameDB.get_buff("element_vision").get("name", "")).is_equal("元素视界")
	assert_str(GameDB.get_buff("resonance_vision").get("name", "")).is_equal("共鸣视界")

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

func test_uniques_are_rare_three() -> void:
	for id in UNIQUE_BUFFS:
		assert_str(GameDB.get_buff(id).get("rarity", "")).is_equal("rare")

# ---- 附录 C 逐条转录核对（M2 t12 新增 20 条） ----

func _expect_effect(id: String, key: String, want: float, eps := 0.0001) -> void:
	var eff: Dictionary = GameDB.get_buff(id).get("effects", {})
	assert_bool(eff.has(key)) \
		.override_failure_message("buff %s missing effect key %s" % [id, key]).is_true()
	if eff.has(key):
		assert_float(float(eff[key])).is_equal_approx(want, eps)

func test_appendix_c_new_attack_rows_transcribed() -> void:
	# C.1 攻击新增：猎杀者（蓝，对异常目标伤害 +20%）
	assert_str(GameDB.get_buff("hunter")["rarity"]).is_equal("rare")
	_expect_effect("hunter", "dmg_vs_statused_pct", 0.20)
	# 共鸣增幅（蓝，共鸣 AoE 半径 +30%、持续 +1s）
	assert_str(GameDB.get_buff("resonance_amp")["rarity"]).is_equal("rare")
	_expect_effect("resonance_amp", "resonance_radius_pct", 0.30)
	var amp_eff: Dictionary = GameDB.get_buff("resonance_amp")["effects"]
	assert_int(int(amp_eff.get("resonance_duration_ticks", -1))).is_equal(60)   # +1s
	# 复仇者（蓝，受击后 3s 内伤害 +25%）
	assert_str(GameDB.get_buff("avenger")["rarity"]).is_equal("rare")
	_expect_effect("avenger", "vengeance_pct", 0.25)
	var av_eff: Dictionary = GameDB.get_buff("avenger")["effects"]
	assert_int(int(av_eff.get("vengeance_ticks", -1))).is_equal(180)            # 3s

func test_appendix_c_new_defense_rows_transcribed() -> void:
	# 抗火/抗冰/抗毒（白，免疫系 flag）
	for pair in [["anti_fire", "抗火"], ["anti_ice", "抗冰"], ["anti_poison", "抗毒"]]:
		var id: String = pair[0]
		assert_str(GameDB.get_buff(id)["rarity"]).is_equal("common")
		assert_int(int(GameDB.get_buff(id)["effects"][id])).is_equal(1)
		assert_str(GameDB.get_buff(id)["desc"]).is_equal(
			{"anti_fire": "免疫燃烧；岩浆伤害 -50%",
			 "anti_ice": "免疫冰缓与冰面打滑",
			 "anti_poison": "免疫中毒"}[id])
	# 神经反射（绿，受击无敌帧 +0.25s = 15t）
	assert_str(GameDB.get_buff("nerve_reflex")["rarity"]).is_equal("uncommon")
	assert_int(int(GameDB.get_buff("nerve_reflex")["effects"]["hurt_iframe_bonus_ticks"])).is_equal(15)
	# 甲壳（绿，受弹幕伤害 -8%）
	assert_str(GameDB.get_buff("carapace")["rarity"]).is_equal("uncommon")
	_expect_effect("carapace", "bullet_dmg_taken_pct", -0.08)
	# 荆棘护甲（绿，被接触时反伤 3）
	assert_str(GameDB.get_buff("thorn_armor")["rarity"]).is_equal("uncommon")
	assert_int(int(GameDB.get_buff("thorn_armor")["effects"]["thorns_contact_dmg"])).is_equal(3)
	# 冲刺延伸（蓝，翻滚距离 +25%）
	assert_str(GameDB.get_buff("dash_extend")["rarity"]).is_equal("rare")
	_expect_effect("dash_extend", "roll_distance_pct", 0.25)
	# 不死鸟（蓝，唯一：致死伤害保留 1 HP 每局 1 次）
	assert_str(GameDB.get_buff("phoenix")["rarity"]).is_equal("rare")
	assert_int(int(GameDB.get_buff("phoenix")["effects"]["phoenix_flag"])).is_equal(1)

func test_appendix_c_new_resource_rows_transcribed() -> void:
	# 财富（白，金币获取 +20%）
	assert_str(GameDB.get_buff("wealth")["rarity"]).is_equal("common")
	_expect_effect("wealth", "wealth_pct", 0.20)
	# 大胃王（白，饮料效果 +50%）
	assert_str(GameDB.get_buff("glutton")["rarity"]).is_equal("common")
	_expect_effect("glutton", "drink_effect_pct", 0.50)
	# 捡拾磁铁（白，拾取范围 +60%）
	assert_str(GameDB.get_buff("pickup_magnet")["rarity"]).is_equal("common")
	_expect_effect("pickup_magnet", "pickup_radius_pct", 0.60)
	# 蓝能汲取（绿，击杀 10% 概率回 2 蓝）
	assert_str(GameDB.get_buff("energy_siphon")["rarity"]).is_equal("uncommon")
	_expect_effect("energy_siphon", "kill_energy_chance", 0.10)
	assert_int(int(GameDB.get_buff("energy_siphon")["effects"]["kill_energy_amount"])).is_equal(2)
	# 红心感应（绿，红心掉率 +50%）
	assert_str(GameDB.get_buff("heart_sense")["rarity"]).is_equal("uncommon")
	_expect_effect("heart_sense", "heart_sense_pct", 0.50)
	# 弹药转化（绿，每 30s 被动回 10 蓝）
	assert_str(GameDB.get_buff("ammo_convert")["rarity"]).is_equal("uncommon")
	assert_int(int(GameDB.get_buff("ammo_convert")["effects"]["passive_energy_interval_ticks"])).is_equal(1800)
	assert_int(int(GameDB.get_buff("ammo_convert")["effects"]["passive_energy_amount"])).is_equal(10)
	# 议价（蓝，商店价格 -15%；负值 = 降价，同 roll_cd_pct 负值 = 缩短约定）
	assert_str(GameDB.get_buff("haggle")["rarity"]).is_equal("rare")
	_expect_effect("haggle", "haggle_pct", -0.15)
	# 元素视界（蓝，弹幕/激光预警 +0.15s = 9t，预警线更醒目）
	assert_str(GameDB.get_buff("element_vision")["rarity"]).is_equal("rare")
	assert_int(int(GameDB.get_buff("element_vision")["effects"]["element_vision"])).is_equal(1)
	assert_int(int(GameDB.get_buff("element_vision")["effects"]["telegraph_bonus_ticks"])).is_equal(9)
	# 共鸣视界（蓝，处于异常状态的敌人高亮描边）
	assert_str(GameDB.get_buff("resonance_vision")["rarity"]).is_equal("rare")
	assert_int(int(GameDB.get_buff("resonance_vision")["effects"]["resonance_vision"])).is_equal(1)

# ---- GameDB：validate_buff_row 语义校验（fail-closed 同 rooms 路径） ----

func _valid_buff_row(id: String) -> Dictionary:
	return {"id": id, "name": "测试", "rarity": "common", "desc": "测试用",
		"effects": {"hp_max": 1}}

func test_validate_buff_row_accepts_valid() -> void:
	assert_int(GameDB.validate_buff_row(_valid_buff_row("t12x")).size()).is_equal(0)

func test_validate_buff_row_accepts_new_t12_keys() -> void:
	for k in ["anti_fire", "phoenix_flag", "element_vision"]:
		var row := _valid_buff_row("t12x")
		row["effects"] = {k: 1}
		assert_int(GameDB.validate_buff_row(row).size()) \
			.override_failure_message("key %s should be accepted" % k).is_equal(0)
	var pct_row := _valid_buff_row("t12y")
	pct_row["effects"] = {"haggle_pct": -0.15, "pickup_radius_pct": 0.6}
	assert_int(GameDB.validate_buff_row(pct_row).size()).is_equal(0)

func test_validate_buff_row_rejects_unknown_effect_key() -> void:
	var row := _valid_buff_row("t12x")
	row["effects"] = {"laser_sight": 1}
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_bad_rarity() -> void:
	var row := _valid_buff_row("t12x")
	row["rarity"] = "legendary"
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_fractional_int_effect() -> void:
	var row := _valid_buff_row("t12x")
	row["effects"] = {"hp_max": 1.5}
	assert_int(GameDB.validate_buff_row(row).size()).is_greater(0)

func test_validate_buff_row_rejects_flag_out_of_range() -> void:
	# 免疫/视界/不死鸟为 0/1 语义 flag，幅度 >1 拒收（fail-closed）
	for k in ["anti_fire", "anti_ice", "anti_poison", "phoenix_flag",
			"element_vision", "resonance_vision"]:
		var row := _valid_buff_row("t12x")
		row["effects"] = {k: 2}
		assert_int(GameDB.validate_buff_row(row).size()) \
			.override_failure_message("flag %s = 2 should be rejected" % k).is_greater(0)

func test_validate_buff_row_rejects_empty_effects() -> void:
	var row := _valid_buff_row("t12x")
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
	bm.pick("phoenix")
	bm.pick("phoenix")                    # 不死鸟同为唯一项
	assert_int(bm.picked.size()).is_equal(3)
	bm.pick("vigor")                      # 普通项可重复 append（强化可叠加）
	assert_int(bm.picked.size()).is_equal(4)

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
	bm.pick("phoenix")
	assert_bool(bm.available_pool().has("extra_projectiles")).is_false()
	assert_bool(bm.available_pool().has("phoenix")).is_false()
	var rng := _rng(42)
	for i in 200:                         # 抽 200 次三选，已取唯一项不得再出现
		for id in bm.roll_three(rng):
			assert_bool(id == "extra_projectiles" or id == "phoenix") \
				.override_failure_message("picked unique %s re-rolled" % id) \
				.is_false()

func test_non_unique_stays_available_after_pick() -> void:
	# 唯一移除仅限唯一项；普通增益可重复出现（强化可叠加）
	var bm := _mgr()
	bm.pick("vigor")
	assert_bool(bm.available_pool().has("vigor")).is_true()
	assert_int(bm.available_pool().size()).is_equal(36)

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

func test_apply_to_player_writes_new_defense_meta_keys() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("anti_fire")
	bm.pick("anti_ice")
	bm.pick("anti_poison")
	bm.pick("nerve_reflex")
	bm.pick("carapace")
	bm.pick("thorn_armor")
	bm.pick("dash_extend")
	bm.pick("phoenix")
	bm.apply_to_player(p)
	assert_int(int(p.get_meta("buff_anti_fire", 0))).is_equal(1)          # 消费方待接线 → T35
	assert_int(int(p.get_meta("buff_anti_ice", 0))).is_equal(1)           # 同上（T35 接冰面/岩浆抗性）
	assert_int(int(p.get_meta("buff_anti_poison", 0))).is_equal(1)
	assert_int(int(p.get_meta("buff_hurt_iframe_bonus_ticks", 0))).is_equal(15)
	assert_float(float(p.get_meta("buff_bullet_dmg_taken_pct", 0.0))).is_equal_approx(-0.08, 0.0001)
	assert_int(int(p.get_meta("buff_thorns_contact_dmg", 0))).is_equal(3)
	assert_float(float(p.get_meta("buff_roll_distance_pct", 0.0))).is_equal_approx(0.25, 0.0001)
	assert_int(int(p.get_meta("buff_phoenix_flag", 0))).is_equal(1)

func test_apply_to_player_writes_new_resource_meta_keys() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("wealth")
	bm.pick("glutton")
	bm.pick("pickup_magnet")
	bm.pick("energy_siphon")
	bm.pick("heart_sense")
	bm.pick("ammo_convert")
	bm.pick("haggle")
	bm.pick("element_vision")
	bm.pick("resonance_vision")
	bm.apply_to_player(p)
	assert_float(float(p.get_meta("buff_wealth_pct", 0.0))).is_equal_approx(0.20, 0.0001)
	assert_float(float(p.get_meta("buff_drink_effect_pct", 0.0))).is_equal_approx(0.50, 0.0001)
	assert_float(float(p.get_meta("buff_pickup_radius_pct", 0.0))).is_equal_approx(0.60, 0.0001)
	assert_float(float(p.get_meta("buff_kill_energy_chance", 0.0))).is_equal_approx(0.10, 0.0001)
	assert_int(int(p.get_meta("buff_kill_energy_amount", 0))).is_equal(2)
	assert_float(float(p.get_meta("buff_heart_sense_pct", 0.0))).is_equal_approx(0.50, 0.0001)
	assert_int(int(p.get_meta("buff_passive_energy_interval_ticks", 0))).is_equal(1800)
	assert_int(int(p.get_meta("buff_passive_energy_amount", 0))).is_equal(10)
	assert_float(float(p.get_meta("buff_haggle_pct", 0.0))).is_equal_approx(-0.15, 0.0001)
	assert_int(int(p.get_meta("buff_element_vision", 0))).is_equal(1)
	assert_int(int(p.get_meta("buff_telegraph_bonus_ticks", 0))).is_equal(9)
	assert_int(int(p.get_meta("buff_resonance_vision", 0))).is_equal(1)

func test_new_meta_keys_neutral_when_unpicked() -> void:
	# 未取键 apply 后保持中性默认（消费方 get_meta 带默认值读取，双保险）
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("vigor")
	bm.apply_to_player(p)
	assert_int(int(p.get_meta("buff_anti_fire", 0))).is_equal(0)
	assert_float(float(p.get_meta("buff_haggle_pct", 0.0))).is_equal_approx(0.0, 0.0001)
	assert_int(int(p.get_meta("buff_phoenix_flag", 0))).is_equal(0)

func test_new_meta_keys_idempotent_and_stack() -> void:
	var p: Player = auto_free(Player.new())
	p._test_init()
	var bm := _mgr()
	bm.pick("haggle")
	bm.apply_to_player(p)
	bm.apply_to_player(p)                 # meta 为绝对值重写，幂等不叠加
	assert_float(float(p.get_meta("buff_haggle_pct", 0.0))).is_equal_approx(-0.15, 0.0001)
	bm.pick("haggle")                     # 议价 ×2 → 聚合 -0.30（叠加经 picked 重算）
	bm.apply_to_player(p)
	assert_float(float(p.get_meta("buff_haggle_pct", 0.0))).is_equal_approx(-0.30, 0.0001)

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

func test_apply_to_rig_writes_new_output_meta_keys() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var bm := _mgr()
	bm.pick("hunter")                     # 对异常目标伤害 +20%
	bm.pick("resonance_amp")              # 共鸣 AoE 半径 +30%、持续 +1s
	bm.pick("avenger")                    # 受击后 3s 内伤害 +25%
	bm.apply_to_rig(rig)
	assert_float(float(rig.get_meta("buff_dmg_vs_statused_pct", 0.0))).is_equal_approx(0.20, 0.0001)
	assert_float(float(rig.get_meta("buff_resonance_radius_pct", 0.0))).is_equal_approx(0.30, 0.0001)
	assert_int(int(rig.get_meta("buff_resonance_duration_ticks", 0))).is_equal(60)
	assert_float(float(rig.get_meta("buff_vengeance_pct", 0.0))).is_equal_approx(0.25, 0.0001)
	assert_int(int(rig.get_meta("buff_vengeance_ticks", 0))).is_equal(180)

func test_rig_output_meta_keys_neutral_when_unpicked() -> void:
	var rig: WeaponRig = auto_free(WeaponRig.new())
	var bm := _mgr()
	bm.apply_to_rig(rig)
	assert_float(float(rig.get_meta("buff_dmg_vs_statused_pct", 0.0))).is_equal_approx(0.0, 0.0001)
	assert_float(float(rig.get_meta("buff_vengeance_pct", 0.0))).is_equal_approx(0.0, 0.0001)

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

func test_aggregate_sums_new_keys_and_flags() -> void:
	var bm := _mgr()
	bm.pick("carapace")
	bm.pick("carapace")                   # 甲壳 ×2 → -16%
	assert_float(bm.aggregate()["bullet_dmg_taken_pct"]).is_equal_approx(-0.16, 0.0001)
	bm.pick("anti_fire")
	assert_int(bm.aggregate()["anti_fire"]).is_equal(1)
	assert_int(bm.aggregate()["anti_ice"]).is_equal(0)         # 未取 flag 中性 0
	assert_float(bm.aggregate()["wealth_pct"]).is_equal_approx(0.0, 0.0001)

func test_flag_keys_aggregate_max_not_sum() -> void:
	# 评审 Major 修复②：flag 键 0/1 语义——重复拾取聚合取 max（非求和），恒 0/1。
	# anti_* 为白卡可重复拾；element_vision 为蓝卡非唯一亦可重复；phoenix 唯一不可重复。
	var bm := _mgr()
	bm.pick("anti_fire")
	bm.pick("anti_fire")                  # 抗火 ×2 → 聚合仍为 1（不是 2）
	bm.pick("element_vision")
	bm.pick("element_vision")
	assert_int(bm.aggregate()["anti_fire"]).is_equal(1)
	assert_int(bm.aggregate()["element_vision"]).is_equal(1)
	assert_int(bm.aggregate()["anti_ice"]).is_equal(0)
	# 落地 meta 同样恒 1
	var p: Player = auto_free(Player.new())
	p._test_init()
	bm.apply_to_player(p)
	assert_int(int(p.get_meta("buff_anti_fire", 0))).is_equal(1)
	assert_int(int(p.get_meta("buff_element_vision", 0))).is_equal(1)
