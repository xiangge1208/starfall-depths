class_name TestTalentSystem
extends GdUnitTestSuite
## M2-T15 天赋树系统契约测试：前置门控 / 蓝晶扣减 / 效果落地 / 重复购买拒绝 / 持久化往返。
## 数据源 data/talents.json（T2 表，24 节点）；效果键 ⊆ 附录 I 白名单（复用键 +
## talent_ 前缀新键）。SaveSystem 全部走临时 user:// 路径注入（同 test_save 模式），
## 不触碰真实 user://save.json（/autoload 只读冒烟除外）。

const FULL_TREE_COST := 10000   # 附录 I.2 经济数学锁定值


# ---- 夹具 ----

func _tmp_path(tag: String) -> String:
	return "user://test_talent_%s_%d.json" % [tag, absi(randi())]


func _wipe(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func _fresh_save(tag: String) -> Variant:
	var path := _tmp_path(tag)
	_wipe(path)
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = path
	s.load_save()
	return s


## 带蓝晶垫付的全新 TalentSystem（save 注入，隔离真实 autoload）。
func _ts(tag: String, gems: int) -> TalentSystem:
	var s: Variant = _fresh_save(tag)
	s.add_gems(gems)
	return TalentSystem.new(s)


func _player_with_rig() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	p.weapon_rig = auto_free(WeaponRig.new())
	p.weapon_rig._test_init()
	return p


## 按 tier 升序买整系（表校验保证前置 tier 严格更低 → tier 序恒合法）。
func _buy_branch(ts: TalentSystem, branch: String) -> void:
	var ids: Array = []
	for id: String in GameDB.talents:
		if String(GameDB.talents[id]["branch"]) == branch:
			ids.append(id)
	ids.sort_custom(_tier_less)
	for id in ids:
		var ok := ts.buy(String(id))
		assert_bool(ok).override_failure_message("buy %s failed" % id).is_true()


func _tier_less(a: Variant, b: Variant) -> bool:
	return int(GameDB.talents[a]["tier"]) < int(GameDB.talents[b]["tier"])


func _buy_all(ts: TalentSystem) -> void:
	for branch: String in ["red", "blue", "green"]:
		_buy_branch(ts, branch)


# ---- 前置门控 ----

func test_fresh_available_is_three_tier1_roots() -> void:
	var ts := _ts("roots", 0)
	assert_array(ts.available()).is_equal(["blue_vitality", "green_deep_cell", "red_sharpen"])


func test_available_excludes_unbought_children() -> void:
	var ts := _ts("gate", 10000)
	assert_bool(ts.available().has("red_deadeye")).is_false()
	assert_bool(ts.available().has("red_apex")).is_false()
	assert_bool(ts.is_available("blue_barrier")).is_false()


func test_buy_root_unlocks_dependent() -> void:
	var ts := _ts("unlock", 10000)
	assert_bool(ts.buy("red_sharpen")).is_true()
	assert_bool(ts.available().has("red_deadeye")).is_true()
	# 红系其余 6 节点前置链更深（tier2+/支线），tier1 后仍全部锁定
	for id: String in ["red_rapid_hammer", "red_catalyst", "red_gouge",
			"red_ballistics", "red_conduit", "red_apex"]:
		assert_bool(ts.is_available(id)).is_false()


func test_chain_gating_step_by_step() -> void:
	# 绿系主脊 deep_cell→scavenge→magnet→crystal_vein→prospector→vortex 逐级放行
	var ts := _ts("chain", 10000)
	for id: String in ["green_deep_cell", "green_scavenge", "green_magnet",
			"green_crystal_vein", "green_prospector", "green_vortex"]:
		assert_bool(ts.is_available(id)).is_true()
		assert_bool(ts.buy(id)).is_true()
	# 绿系剩 super_cell（前置 deep_cell 已购 → 可买）与 resonator（前置 super_cell 未购 → 锁）
	assert_array(ts.available()).is_equal(["blue_vitality", "green_super_cell", "red_sharpen"])


# ---- 蓝晶校验与扣减 ----

func test_buy_deducts_gems_and_records() -> void:
	var ts := _ts("deduct", 500)
	assert_bool(ts.buy("red_sharpen")).is_true()
	assert_int(ts.save_system.gems()).is_equal(400)
	assert_array(ts.purchased).is_equal(["red_sharpen"])


func test_buy_insufficient_gems_rejected() -> void:
	var ts := _ts("poor", 99)
	assert_bool(ts.buy("red_sharpen")).is_false()
	assert_int(ts.save_system.gems()).is_equal(99)
	assert_array(ts.purchased).is_empty()


func test_buy_exact_gems_boundary_allowed() -> void:
	var ts := _ts("exact", 100)
	assert_bool(ts.buy("red_sharpen")).is_true()
	assert_int(ts.save_system.gems()).is_equal(0)


func test_buy_unknown_id_rejected() -> void:
	var ts := _ts("unknown", 10000)
	assert_bool(ts.buy("no_such_talent")).is_false()
	assert_int(ts.save_system.gems()).is_equal(10000)
	assert_array(ts.purchased).is_empty()


func test_buy_prereq_unmet_rejected_no_deduction() -> void:
	var ts := _ts("prereq", 10000)
	assert_bool(ts.buy("blue_bulwark")).is_false()   # tier8，前置链全未购
	assert_int(ts.save_system.gems()).is_equal(10000)
	assert_array(ts.purchased).is_empty()


# ---- 重复购买拒绝 ----

func test_buy_twice_rejected_single_deduction() -> void:
	var ts := _ts("dup", 500)
	assert_bool(ts.buy("red_sharpen")).is_true()
	assert_bool(ts.buy("red_sharpen")).is_false()    # 重复购买拒绝
	assert_int(ts.save_system.gems()).is_equal(400)  # 只扣一次
	assert_array(ts.purchased).is_equal(["red_sharpen"])


# ---- 效果落地：聚合 ----

func test_aggregate_empty_is_neutral() -> void:
	var ts := _ts("neutral", 0)
	var agg := ts.aggregate()
	for k: String in GameDB.TALENT_PCT_KEYS:
		assert_float(float(agg[k])).is_equal(0.0)
	for k: String in GameDB.TALENT_INT_KEYS:
		assert_int(int(agg[k])).is_equal(0)


func test_aggregate_sums_purchased_effects() -> void:
	# blue_vitality(+2hp) + blue_barrier(+1shield) + blue_second_wind(+1shield)
	var ts := _ts("agg", 10000)
	ts.buy("blue_vitality")
	ts.buy("blue_barrier")
	ts.buy("blue_second_wind")
	var agg := ts.aggregate()
	assert_int(int(agg["hp_max"])).is_equal(2)
	assert_int(int(agg["shield_max"])).is_equal(2)


func test_aggregate_keys_subset_of_whitelist() -> void:
	# 契约：apply 落地键 ⊆ 附录 I 白名单（PCT + INT 两表并集）
	var ts := _ts("white", 10000)
	_buy_all(ts)
	var agg := ts.aggregate()
	for k: String in agg:
		assert_bool(GameDB.TALENT_PCT_KEYS.has(k) or GameDB.TALENT_INT_KEYS.has(k)) \
			.override_failure_message("key %s outside appendix-I whitelist" % k).is_true()


func test_full_tree_aggregate_matches_appendix_totals() -> void:
	# 附录 I.5 满系累计：红(伤害+8%/暴击+6%/攻速+6%/暴伤+25%/异常+10%/弹速+8%/附魔+5%)
	# 蓝(HP+4/盾+2/盾延时-90t/移速+8%/翻滚-12%/无敌帧+10%) 绿(能量+40/金币+15%/蓝晶+15%/磁吸+30%)
	var ts := _ts("fullagg", FULL_TREE_COST)
	_buy_all(ts)
	var agg := ts.aggregate()
	assert_float(float(agg["talent_dmg_pct"])).is_equal_approx(0.08, 0.0001)
	assert_float(float(agg["crit_pct"])).is_equal_approx(0.06, 0.0001)
	assert_float(float(agg["atk_speed_pct"])).is_equal_approx(0.06, 0.0001)
	assert_float(float(agg["crit_dmg_pct"])).is_equal_approx(0.25, 0.0001)
	assert_float(float(agg["status_rate_pct"])).is_equal_approx(0.10, 0.0001)
	assert_float(float(agg["bullet_speed_pct"])).is_equal_approx(0.08, 0.0001)
	assert_float(float(agg["element_proc_chance"])).is_equal_approx(0.05, 0.0001)
	assert_int(int(agg["hp_max"])).is_equal(4)
	assert_int(int(agg["shield_max"])).is_equal(2)
	assert_int(int(agg["shield_delay_reduction_ticks"])).is_equal(90)
	assert_float(float(agg["move_speed_pct"])).is_equal_approx(0.08, 0.0001)
	assert_float(float(agg["roll_cd_pct"])).is_equal_approx(-0.12, 0.0001)
	assert_float(float(agg["talent_hurt_iframe_pct"])).is_equal_approx(0.10, 0.0001)
	assert_int(int(agg["energy_max"])).is_equal(40)
	assert_float(float(agg["talent_coin_gain_pct"])).is_equal_approx(0.15, 0.0001)
	assert_float(float(agg["talent_gem_gain_pct"])).is_equal_approx(0.15, 0.0001)
	assert_float(float(agg["talent_pickup_radius_pct"])).is_equal_approx(0.30, 0.0001)


# ---- 效果落地：apply_to_player ----

func test_apply_without_purchase_is_noop() -> void:
	var ts := _ts("noop", 0)
	var p := _player_with_rig()
	ts.apply_to_player(p)
	assert_int(p.hp_max).is_equal(8)
	assert_int(p.shield_max).is_equal(4)
	assert_int(p.energy_max).is_equal(100)
	assert_float(p.move_speed).is_equal(80.0)
	assert_float(p.crit_bonus).is_equal(0.0)
	assert_float(p.roll_cd_pct).is_equal(0.0)
	assert_float(p.weapon_rig.rate_mult).is_equal(1.0)


func test_apply_lands_blue_branch_player_fields() -> void:
	var ts := _ts("blue", FULL_TREE_COST)
	_buy_branch(ts, "blue")
	var p := _player_with_rig()
	ts.apply_to_player(p)
	assert_int(p.hp_max).is_equal(12)          # 8 + 4
	assert_int(p.shield_max).is_equal(6)       # 4 + 2
	assert_int(p.shield_delay_reduction_ticks).is_equal(90)
	assert_float(p.move_speed).is_equal_approx(86.4, 0.0001)   # 80 × 1.08
	assert_float(p.roll_cd_pct).is_equal_approx(-0.12, 0.0001)


func test_apply_lands_red_branch_scalar_fields() -> void:
	var ts := _ts("red", FULL_TREE_COST)
	_buy_branch(ts, "red")
	var p := _player_with_rig()
	ts.apply_to_player(p)
	assert_float(p.crit_bonus).is_equal_approx(0.06, 0.0001)
	assert_float(p.crit_damage_bonus).is_equal_approx(0.25, 0.0001)
	assert_float(p.status_rate_bonus).is_equal_approx(0.10, 0.0001)


func test_apply_lands_rig_fields() -> void:
	var ts := _ts("rig", FULL_TREE_COST)
	_buy_branch(ts, "red")
	var p := _player_with_rig()
	ts.apply_to_player(p)
	assert_float(p.weapon_rig.rate_mult).is_equal_approx(1.06, 0.0001)
	assert_float(p.weapon_rig.bullet_speed_mult).is_equal_approx(1.08, 0.0001)
	assert_float(p.weapon_rig.enchant_proc_chance).is_equal_approx(0.05, 0.0001)


func test_apply_lands_talent_prefixed_keys_on_meta() -> void:
	# talent_ 前缀键（伤害乘区/受击无敌帧/金币/蓝晶/磁吸）经 player meta "talent_effects"
	# 落地全量聚合，消费方接线见附录 I.4（weapon_rig 伤害乘区 / apply_iframes / Pickup / T31）
	var ts := _ts("meta", FULL_TREE_COST)
	_buy_all(ts)
	var p := _player_with_rig()
	ts.apply_to_player(p)
	var eff := TalentSystem.effects_of(p)
	assert_float(float(eff["talent_dmg_pct"])).is_equal_approx(0.08, 0.0001)
	assert_float(float(eff["talent_hurt_iframe_pct"])).is_equal_approx(0.10, 0.0001)
	assert_float(float(eff["talent_coin_gain_pct"])).is_equal_approx(0.15, 0.0001)
	assert_float(float(eff["talent_gem_gain_pct"])).is_equal_approx(0.15, 0.0001)
	assert_float(float(eff["talent_pickup_radius_pct"])).is_equal_approx(0.30, 0.0001)


func test_apply_idempotent() -> void:
	var ts := _ts("idem", FULL_TREE_COST)
	_buy_all(ts)
	var p := _player_with_rig()
	ts.apply_to_player(p)
	ts.apply_to_player(p)   # 重复 apply 按已购列表重算，不叠加
	assert_int(p.hp_max).is_equal(12)
	assert_int(p.energy_max).is_equal(140)
	assert_float(p.move_speed).is_equal_approx(86.4, 0.0001)
	assert_float(p.weapon_rig.rate_mult).is_equal_approx(1.06, 0.0001)
	assert_float(p.weapon_rig.bullet_speed_mult).is_equal_approx(1.08, 0.0001)


func test_apply_recompute_preserves_external_writes() -> void:
	# own-delta 重算（BuffManager 同款）：外部写入（英雄重装配/饮料/其他 manager）不丢
	var ts := _ts("ext", 200)
	ts.buy("blue_vitality")
	var p := _player_with_rig()
	ts.apply_to_player(p)
	assert_int(p.hp_max).is_equal(10)
	p.hp_max = 15                       # 外部写入（如 HeroApplier 重设面板）
	ts.apply_to_player(p)               # 15 - 2 + 2
	assert_int(p.hp_max).is_equal(15)
	p.move_speed = 100.0                # 外部写入移速
	ts.apply_to_player(p)               # (100 / 1.0) × 1.0 —— 未购移速键保持中性
	assert_float(p.move_speed).is_equal(100.0)


# ---- 持久化往返 ----

func test_purchased_roundtrip_new_save_instance() -> void:
	var tag := "roundtrip"
	var path := _tmp_path(tag)
	_wipe(path)
	var s1: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s1.save_path = path
	s1.load_save()
	s1.add_gems(500)
	var ts1 := TalentSystem.new(s1)
	ts1.buy("red_sharpen")
	ts1.buy("red_deadeye")
	# 全新 save 实例从盘上重读 → purchased 列表与蓝晶余额一致
	var s2: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s2.save_path = path
	s2.load_save()
	var ts2 := TalentSystem.new(s2)
	assert_array(ts2.purchased).is_equal(["red_sharpen", "red_deadeye"])
	assert_int(s2.gems()).is_equal(200)   # 500 - 100 - 200
	_wipe(path)


func test_reload_prevents_rebuy_and_keeps_gating() -> void:
	var tag := "reload"
	var path := _tmp_path(tag)
	_wipe(path)
	var s1: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s1.save_path = path
	s1.load_save()
	s1.add_gems(500)
	var ts1 := TalentSystem.new(s1)
	ts1.buy("red_sharpen")
	var s2: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s2.save_path = path
	s2.load_save()
	var ts2 := TalentSystem.new(s2)
	# 重读后：已购不可重复买（不扣蓝晶），tier2 依赖已放行
	assert_bool(ts2.buy("red_sharpen")).is_false()
	assert_int(s2.gems()).is_equal(400)
	assert_bool(ts2.buy("red_deadeye")).is_true()
	assert_int(s2.gems()).is_equal(200)
	_wipe(path)


func test_save_purchased_field_failsoft_on_garbage() -> void:
	# 损坏 purchased_talents 键（非数组/脏元素）→ fail-SOFT 回落空表，不崩（同 unlocked_heroes）
	var tag := "garbage"
	var path := _tmp_path(tag)
	_wipe(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"version": 1, "gems": 7, "purchased_talents": [42, "red_sharpen", true]}')
	f = null
	var s: Variant = auto_free(load("res://autoload/save_system.gd").new())
	s.save_path = path
	s.load_save()
	assert_array(s.purchased_talents()).is_equal(["red_sharpen"])
	_wipe(path)


func test_full_tree_buyable_and_gems_exhausted() -> void:
	var ts := _ts("whole", FULL_TREE_COST)
	_buy_all(ts)
	assert_int(ts.purchased.size()).is_equal(24)
	assert_int(ts.save_system.gems()).is_equal(0)
	assert_array(ts.available()).is_empty()


# ---- autoload 接线冒烟（只读，不触碰真实档）----

func test_autoload_save_has_purchased_api() -> void:
	var save_system: Node = get_tree().root.get_node_or_null("SaveSystem")
	assert_that(save_system).is_not_null()
	assert_bool(save_system.has_method("purchased_talents")).is_true()
	assert_bool(save_system.has_method("record_talent_purchase")).is_true()
	assert_int(save_system.purchased_talents().size()).is_greater_equal(0)   # API 可调（只读）
