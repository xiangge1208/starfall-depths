class_name TestHeroes
extends GdUnitTestSuite
## M1 t11：heroes.json 数据层（HERO_SCHEMA fail-closed + start_weapons 语义校验）
## + HeroApplier 装配（面板四字段/初始武器/meta 接缝/技能换装）+ HeroSelect 静态暂存。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const HERO_SELECT_SCENE := preload("res://ui/hero_select.tscn")

# ---- 数据层：heroes 装载 + schema ----

func test_six_heroes_loaded() -> void:
	assert_bool(GameDB.load_ok).is_true()
	assert_dict(GameDB.heroes).contains_keys("vanguard", "ranger", "engineer", "mage", "guardian", "assassin")
	assert_int(GameDB.heroes.size()).is_equal(6)   # M2-T8：+engineer；M2-T11：+mage/+guardian；M2-T13：+assassin

func test_hero_schema_16_required_keys_and_optional_registry() -> void:
	var want := {
		"id": TYPE_STRING, "name": TYPE_STRING,
		"hp": TYPE_INT, "shield": TYPE_INT, "energy": TYPE_INT,
		"speed": TYPE_FLOAT, "crit_chance": TYPE_FLOAT,
		"start_weapons": TYPE_ARRAY, "skill_script": TYPE_STRING,
		"skill_cd": TYPE_INT, "skill_energy": TYPE_INT,
		"passive_id": TYPE_STRING, "has_defiance": TYPE_BOOL,
		"skill_name": TYPE_STRING, "skill_desc": TYPE_STRING, "upgraded": TYPE_BOOL,
	}
	assert_int(GameDB.HERO_SCHEMA.size()).is_equal(16)
	for key: String in want:
		assert_int(GameDB.HERO_SCHEMA.get(key, -1)).is_equal(want[key])
	# m2-t13：附加键注册（T8 评审遗留收口：键外直通无校验/无默认）——
	# summon_cap（T8 工程师召唤物库存上限）+ dash_dist_px（T13 刺客影袭变体距离，
	# 缺省 = 游侠 140px）。此前 test 断言 HERO_OPTIONAL 为空，随注册同步改口径。
	assert_int(GameDB.HERO_OPTIONAL.size()).is_equal(2)
	assert_int(int(GameDB.HERO_OPTIONAL.get("summon_cap", -1))).is_equal(0)
	assert_bool(typeof(GameDB.HERO_OPTIONAL.get("summon_cap")) == TYPE_INT).is_true()
	assert_float(float(GameDB.HERO_OPTIONAL.get("dash_dist_px", -1.0))).is_equal(140.0)
	assert_bool(typeof(GameDB.HERO_OPTIONAL.get("dash_dist_px")) == TYPE_FLOAT).is_true()

func test_summon_cap_registered_engineer_keeps_2_others_default_0() -> void:
	# T8 行内值不受注册影响；其余五行（含 T13 assassin）补默认 0（非召唤系）
	assert_int(GameDB.get_hero("engineer").get("summon_cap", -1)).is_equal(2)
	for id: String in ["vanguard", "ranger", "mage", "guardian", "assassin"]:
		assert_int(GameDB.get_hero(id).get("summon_cap", -1)).is_equal(0)
		assert_bool(typeof(GameDB.get_hero(id)["summon_cap"]) == TYPE_INT).is_true()   # JSON float 已按 optional 类型还原

func test_dash_dist_px_registered_assassin_220_others_default_140() -> void:
	assert_float(float(GameDB.get_hero("assassin").get("dash_dist_px", -1.0))).is_equal_approx(220.0, 0.001)
	for id: String in ["vanguard", "ranger", "engineer", "mage", "guardian"]:
		assert_float(float(GameDB.get_hero(id).get("dash_dist_px", -1.0))).is_equal_approx(140.0, 0.001)

func test_vanguard_row_values() -> void:
	var h := GameDB.get_hero("vanguard")
	assert_str(h.get("name", "")).is_equal("骑士·凛")
	assert_int(h.get("hp", -1)).is_equal(8)
	assert_int(h.get("shield", -1)).is_equal(4)
	assert_int(h.get("energy", -1)).is_equal(100)
	assert_float(h.get("speed", -1.0)).is_equal_approx(80.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.05, 0.0001)
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(2)
	assert_str(String(sw[0])).is_equal("laohuoji")
	assert_str(String(sw[1])).is_equal("tiejian")
	assert_str(h.get("skill_script", "")).is_equal("res://core/player/skills/vanguard_rampage.gd")
	assert_int(h.get("skill_cd", -1)).is_equal(840)
	assert_int(h.get("skill_energy", -2)).is_equal(0)
	assert_str(h.get("passive_id", "")).is_equal("defiance")
	assert_bool(h.get("has_defiance", false)).is_true()
	assert_str(h.get("skill_name", "")).is_equal("狂潮")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()

func test_ranger_row_values() -> void:
	var h := GameDB.get_hero("ranger")
	assert_str(h.get("name", "")).is_equal("游侠·苇")
	assert_int(h.get("hp", -1)).is_equal(6)
	assert_int(h.get("shield", -1)).is_equal(4)
	assert_int(h.get("energy", -1)).is_equal(110)
	assert_float(h.get("speed", -1.0)).is_equal_approx(88.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.15, 0.0001)
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(1)
	assert_str(String(sw[0])).is_equal("duangong")
	assert_str(h.get("skill_script", "")).is_equal("res://core/player/skills/ranger_shadowstep.gd")
	assert_int(h.get("skill_cd", -1)).is_equal(540)
	assert_int(h.get("skill_energy", -2)).is_equal(0)
	assert_str(h.get("passive_id", "")).is_equal("hawk_eye")
	assert_bool(h.get("has_defiance", true)).is_false()
	assert_str(h.get("skill_name", "")).is_equal("影袭")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()

func test_assassin_row_values() -> void:
	var h := GameDB.get_hero("assassin")
	assert_str(h.get("name", "")).is_equal("刺客·蝉")
	assert_int(h.get("hp", -1)).is_equal(6)            # GDD §6 面板表
	assert_int(h.get("shield", -1)).is_equal(3)
	assert_int(h.get("energy", -1)).is_equal(100)
	assert_float(h.get("speed", -1.0)).is_equal_approx(84.0, 0.001)
	assert_float(h.get("crit_chance", -1.0)).is_equal_approx(0.05, 0.0001)   # §7.1 基础 5%（被动无暴击加成）
	var sw: Array = h.get("start_weapons", [])
	assert_int(sw.size()).is_equal(1)
	assert_str(String(sw[0])).is_equal("shuangbi")     # 双匕（GDD §6 初始武器）
	assert_str(h.get("skill_script", "")).is_equal("res://core/player/skills/shadowstep_assassin.gd")
	assert_int(h.get("skill_cd", -1)).is_equal(480)    # CD 8s（GDD §6 刺客列）
	assert_int(h.get("skill_energy", -2)).is_equal(0)
	assert_str(h.get("passive_id", "")).is_equal("shadow_reap")   # 掠影（本卡仅落数据，接线同 spare_parts 先例）
	assert_bool(h.get("has_defiance", true)).is_false()
	assert_str(h.get("skill_name", "")).is_equal("残影斩")
	assert_bool(h.get("skill_desc", "").is_empty()).is_false()
	assert_bool(h.get("upgraded", true)).is_false()
	assert_float(float(h.get("dash_dist_px", -1.0))).is_equal_approx(220.0, 0.001)   # 影袭变体距离差异化

func test_hero_skill_scripts_exist_and_extend_skill_base() -> void:
	for id: String in GameDB.heroes:
		var path := String(GameDB.heroes[id]["skill_script"])
		assert_bool(FileAccess.file_exists(path)).is_true()
		var script: Script = load(path)
		assert_object(script).is_not_null()
		# m2-t13：刺客为 RangerShadowstep 子类（非直接继承）——基链传递可达 skill_base.gd 即合法
		var chain_ok := false
		var base: Script = script.get_base_script()
		while base != null:
			if base.resource_path == "res://core/player/skills/skill_base.gd":
				chain_ok = true
				break
			base = base.get_base_script()
		assert_bool(chain_ok).is_true()

# ---- schema 语义校验（extra_check fail-closed）----

func test_validate_hero_row_rejects_unknown_weapon() -> void:
	var row := GameDB.get_hero("vanguard").duplicate()
	row["start_weapons"] = ["laohuoji", "no_such_gun"]
	var errors: Array[String] = GameDB.validate_hero_row(row)
	assert_int(errors.size()).is_greater(0)

func test_validate_hero_row_rejects_empty_weapons() -> void:
	var row := GameDB.get_hero("ranger").duplicate()
	row["start_weapons"] = []
	var errors: Array[String] = GameDB.validate_hero_row(row)
	assert_int(errors.size()).is_greater(0)

func test_validate_hero_row_accepts_valid_row() -> void:
	var errors: Array[String] = GameDB.validate_hero_row(GameDB.get_hero("vanguard"))
	assert_int(errors.size()).is_equal(0)

func _fresh_db() -> Variant:
	# 全新实例，避免污染 autoload 状态（同 test_game_db.gd 既定模式）
	return auto_free(load("res://autoload/game_db.gd").new())

func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null

func test_load_table_rejects_hero_with_unknown_weapon_end_to_end() -> void:
	var path := "user://test_hero_bad_gun_61bf.json"
	_write_json(path, '{"r1": {"id":"r1","name":"甲","hp":8,"shield":4,"energy":100,"speed":80.0,'
		+ '"crit_chance":0.05,"start_weapons":["ghost_gun"],"skill_script":"res://x.gd",'
		+ '"skill_cd":1,"skill_energy":0,"passive_id":"p","has_defiance":false,'
		+ '"skill_name":"技","skill_desc":"描述","upgraded":false}}')
	var db: Variant = _fresh_db()
	db.weapons = GameDB.weapons                     # 语义校验依赖 weapons 表（先于 heroes 装载）
	var loaded: Dictionary = db._load_table(path, GameDB.HERO_SCHEMA, GameDB.HERO_OPTIONAL, db.validate_hero_row)
	assert_dict(loaded).is_empty()                  # 未知武器必须被拒绝，不得入库
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_load_table_accepts_valid_hero_row_end_to_end() -> void:
	var path := "user://test_hero_ok_61bf.json"
	_write_json(path, '{"r2": {"id":"r2","name":"乙","hp":6,"shield":4,"energy":110,"speed":88.0,'
		+ '"crit_chance":0.15,"start_weapons":["duangong"],"skill_script":"res://x.gd",'
		+ '"skill_cd":1,"skill_energy":0,"passive_id":"p","has_defiance":false,'
		+ '"skill_name":"技","skill_desc":"描述","upgraded":false}}')
	var db: Variant = _fresh_db()
	db.weapons = GameDB.weapons
	var loaded: Dictionary = db._load_table(path, GameDB.HERO_SCHEMA, GameDB.HERO_OPTIONAL, db.validate_hero_row)
	assert_bool(db.load_ok).is_true()
	assert_dict(loaded).contains_keys("r2")
	assert_int(loaded["r2"].get("hp", -1)).is_equal(6)   # JSON float → 按 schema 还原 int
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

# ---- HeroApplier 装配 ----

func _in_tree_player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	auto_free(p)
	add_child(p)                          # 入树 → _ready 解析 WeaponRig/Skill
	return p

func test_apply_writes_panel_fields_and_snaps_current_to_max() -> void:
	var p := _in_tree_player()
	p.hp = 3; p.shield = 0; p.energy = 7   # 跨角色残留旧值：装配须对齐新上限
	HeroApplier.apply(GameDB.get_hero("ranger"), p)
	assert_int(p.hp_max).is_equal(6)
	assert_int(p.shield_max).is_equal(4)
	assert_int(p.energy_max).is_equal(110)
	assert_float(p.move_speed).is_equal_approx(88.0, 0.001)
	assert_int(p.hp).is_equal(6)
	assert_int(p.shield).is_equal(4)
	assert_int(p.energy).is_equal(110)
	HeroApplier.apply(GameDB.get_hero("vanguard"), p)
	assert_int(p.hp_max).is_equal(8)
	assert_int(p.energy_max).is_equal(100)
	assert_float(p.move_speed).is_equal_approx(80.0, 0.001)

func test_apply_equips_start_weapons_in_order() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("vanguard"), p)
	assert_str(String(p.weapon_rig.slots[0].get("id", ""))).is_equal("laohuoji")   # 槽 0 先占
	assert_str(String(p.weapon_rig.slots[1].get("id", ""))).is_equal("tiejian")    # 其余填下一空槽
	assert_int(p.weapon_rig.slot).is_equal(0)
	var q := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("ranger"), q)
	assert_str(String(q.weapon_rig.slots[0].get("id", ""))).is_equal("duangong")
	assert_dict(q.weapon_rig.slots[1]).is_empty()                                  # 仅 1 把：槽 1 空

func test_apply_sets_meta_seams() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("vanguard"), p)
	assert_bool(p.has_meta("hero")).is_true()
	assert_str(String((p.get_meta("hero") as Dictionary)["id"])).is_equal("vanguard")
	assert_bool(p.has_meta("crit_base")).is_true()
	assert_float(p.get_meta("crit_base")).is_equal_approx(0.05, 0.0001)
	HeroApplier.apply(GameDB.get_hero("ranger"), p)
	assert_float(p.get_meta("crit_base")).is_equal_approx(0.15, 0.0001)            # 重装配覆盖

func test_apply_sets_defiance_flag() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("vanguard"), p)
	assert_bool(p.has_defiance).is_true()
	HeroApplier.apply(GameDB.get_hero("ranger"), p)
	assert_bool(p.has_defiance).is_false()

func test_apply_mounts_vanguard_skill_and_cast_works() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("vanguard"), p)
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal("res://core/player/skills/vanguard_rampage.gd")
	assert_int(skill.get("cooldown_ticks")).is_equal(840)    # CD 经 data 注入（skill_cd）
	assert_int(skill.get("energy_cost")).is_equal(0)
	assert_bool(skill.get("upgraded")).is_false()
	assert_object(skill.get("player")).is_same(p)
	assert_bool(skill.cast(100)).is_true()                   # 装配后技能即用：双持窗生效
	assert_int(p.weapon_rig.dual_wield_until).is_equal(100 + 480)

func test_apply_mounts_ranger_skill_and_cast_works() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("ranger"), p)
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal("res://core/player/skills/ranger_shadowstep.gd")
	assert_int(skill.get("cooldown_ticks")).is_equal(540)
	assert_bool(skill.get("upgraded")).is_false()
	p.facing = Vector2.RIGHT
	assert_bool(skill.cast(100)).is_true()                   # 短弓远程 0 耗蓝 → cast 通过
	assert_int(p.weapon_rig.crit_boost_until).is_equal(100 + 240)
	assert_bool(p.is_invincible_at(100 + 14)).is_true()      # 瞬步自带 15t 无敌

func test_apply_mounts_assassin_skill_and_cast_works() -> void:
	var p := _in_tree_player()
	HeroApplier.apply(GameDB.get_hero("assassin"), p)
	var skill: Node = p.get_node("Skill")
	assert_str((skill.get_script() as Script).resource_path).is_equal("res://core/player/skills/shadowstep_assassin.gd")
	assert_int(skill.get("cooldown_ticks")).is_equal(480)    # CD 8s（GDD §6；行 skill_cd 注入）
	assert_int(skill.get("energy_cost")).is_equal(0)
	assert_int(p.hp_max).is_equal(6)                         # 面板四字段全落地（GDD §6 刺客行）
	assert_int(p.shield_max).is_equal(3)
	assert_int(p.energy_max).is_equal(100)
	assert_float(p.move_speed).is_equal_approx(84.0, 0.001)
	assert_str(String(p.weapon_rig.slots[0].get("id", ""))).is_equal("shuangbi")   # 双匕初始装备
	p.facing = Vector2.RIGHT
	p.position = Vector2(100, 50)
	assert_bool(skill.cast(100)).is_true()                   # 0 耗蓝近战 → cast 通过
	assert_float(p.position.x).is_equal_approx(320.0, 0.001) # 影袭变体：+220px（英雄行 dash_dist_px 注入）
	assert_float(p.position.y).is_equal_approx(50.0, 0.001)
	assert_bool(p.is_invincible_at(100 + 14)).is_true()      # 无敌窗继承游侠（15t）
	assert_int(p.weapon_rig.crit_boost_until).is_equal(100 + 240)   # 4s 必暴窗继承

func test_shadowstep_assassin_defaults_without_hero_meta() -> void:
	# 纯逻辑实例（setup 无 hero meta）：子类缺省自洽——突进 220px + CD 480（GDD §6 刺客列），
	# 不依赖 HeroApplier 装配路径（同 _shadowstep 纯逻辑测试习语）
	var p := _in_tree_player()
	var sk: RangerShadowstep = auto_free(load("res://core/player/skills/shadowstep_assassin.gd").new())
	sk.name = "SkillVariant"
	p.add_child(sk)
	sk.setup(p, {})
	assert_int(sk.cooldown_ticks).is_equal(480)
	p.facing = Vector2.RIGHT
	p.position = Vector2(100, 50)
	assert_bool(sk.cast(100)).is_true()
	assert_float(p.position.x).is_equal_approx(320.0, 0.001)
	assert_bool(sk.cast(580)).is_true()                      # CD 门 480t 后可再放
	assert_float(p.position.x).is_equal_approx(540.0, 0.001)

# ---- HeroSelect 静态暂存 + 选角 UI（逻辑层无头测试；观感手动）----

func _reset_last_chosen() -> void:
	HeroSelect.last_chosen = ""      # 静态状态跨用例复位

func test_hero_select_static_fallback_stores_choice() -> void:
	_reset_last_chosen()
	HeroSelect.last_chosen = "ranger"
	assert_str(HeroSelect.last_chosen).is_equal("ranger")
	_reset_last_chosen()

func test_hero_select_scene_builds_all_hero_cards() -> void:
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_int(ui._cards.size()).is_equal(6)   # M2-T8/T11/T13：GameDB 驱动自动扩展（+assassin 零改动验证）
	assert_int(ui._ids.size()).is_equal(6)

func test_hero_select_passives_cover_all_hero_ids() -> void:
	# 被动中文文案归 UI 层 PASSIVES 常量：新英雄 passive_id 必须同步补文案，
	# 防卡片回退显示裸 id（m2-t13：+assassin shadow_reap 掠影）
	for id: String in GameDB.heroes:
		var passive := String(GameDB.heroes[id].get("passive_id", ""))
		assert_bool(HeroSelect.PASSIVES.has(passive)).is_true()

func test_hero_select_choose_emits_signal_and_stores_static() -> void:
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._choose(1)
	assert_array(chosen).contains_exactly(["ranger"])
	assert_str(HeroSelect.last_chosen).is_equal("ranger")     # 静态暂存 fallback（RunState 未合并）
	ui._choose(0)
	assert_array(chosen).contains_exactly(["ranger", "vanguard"])
	assert_str(HeroSelect.last_chosen).is_equal("vanguard")
	_reset_last_chosen()

func test_hero_select_choose_out_of_range_ignored() -> void:
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._choose(-1)
	ui._choose(9)
	assert_array(chosen).is_empty()
	_reset_last_chosen()

func test_hero_select_keyboard_navigation_and_enter() -> void:
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._unhandled_input(_key(KEY_D))                          # D/→：右移选中
	assert_int(ui._selected).is_equal(1)
	ui._unhandled_input(_key(KEY_A))                          # A/←：回左
	assert_int(ui._selected).is_equal(0)
	ui._unhandled_input(_key(KEY_ENTER))                      # Enter：选择当前高亮
	assert_array(chosen).contains_exactly(["vanguard"])
	assert_str(HeroSelect.last_chosen).is_equal("vanguard")
	_reset_last_chosen()

func test_hero_select_click_card_chooses() -> void:
	# M4-K2：轻点激活语义（按下记录、松开对账）——对齐 BaseButton 释放激活 +
	# 横滚滑动起手防误选（滑动释放位移超阈不选，另见 tap_vs_drag 用例）
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._on_card_input(_click(1, true), 1)
	assert_array(chosen).is_empty()                  # 仅按下不选（释放对账）
	ui._on_card_input(_click(1, false), 1)
	assert_array(chosen).contains_exactly(["ranger"])
	_reset_last_chosen()

func test_hero_select_tap_vs_drag_release_displacement() -> void:
	# 轻点（位移 ≤ 8px）选中；拖动（位移 > 8px，触摸滑动滚动起手）不选中
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._on_card_input(_click(2, true, Vector2(40.0, 30.0)), 2)
	ui._on_card_input(_click(2, false, Vector2(200.0, 30.0)), 2)   # 横扫 160px：滚动非选择
	assert_array(chosen).is_empty()
	ui._on_card_input(_click(2, true, Vector2(10.0, 10.0)), 2)
	ui._on_card_input(_click(2, false, Vector2(15.0, 12.0)), 2)    # 位移 ~5.4px：轻点
	assert_array(chosen).contains_exactly(["engineer"])
	# 串扰防护：A 卡按下后 B 卡释放（松开别处）不选
	ui._on_card_input(_click(0, true, Vector2.ZERO), 0)
	ui._on_card_input(_click(0, false, Vector2.ZERO), 1)
	assert_array(chosen).contains_exactly(["engineer"])
	_reset_last_chosen()

func test_hero_select_scroll_layout_and_focus_chain_closed() -> void:
	# M4-K2 撤 S-C 豁免的落地验收（单测侧结构断言；像素视口断言归 font_render_smoke）：
	# 卡行收进 CardScroll 横滚 + follow_focus；6 卡 FOCUS_ALL；focus_neighbors 右向
	# 6 跳闭合遍历全卡（卡 5 → 卡 0 环回），左向对称；上/下自锚防纵向逃逸
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var scroll := ui.get_node("CardScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	assert_bool(scroll.follow_focus).is_true()
	assert_int(scroll.horizontal_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	var cards: Array = ui._cards
	assert_int(cards.size()).is_equal(6)
	for c: Control in cards:
		assert_int(c.focus_mode).is_equal(Control.FOCUS_ALL)
	for dir: String in ["focus_neighbor_right", "focus_neighbor_left"]:
		var visited := {}
		var cur: Control = cards[0]
		for i in 6:
			assert_bool(visited.has(cur)).is_false()   # 未走满 6 卡即成环 = 链断
			visited[cur] = true
			assert_bool((cur as Control).has_node(cur.get(dir))).is_true()
			cur = cur.get_node(cur.get(dir)) as Control
		assert_object(cur).is_same(cards[0])           # 6 跳后回到起点（闭环）
		assert_int(visited.size()).is_equal(6)
	for c: Control in cards:
		assert_object(c.get_node(c.focus_neighbor_top) as Control).is_same(c)
		assert_object(c.get_node(c.focus_neighbor_bottom) as Control).is_same(c)

func test_hero_select_focus_and_selection_single_source() -> void:
	# 双路汇一：A/D 动作（move_right/move_left）→ _selected 移动 + 焦点回写；
	# 焦点链移动（grab_focus 模拟手柄 ui_left/right 落点）→ 高亮同步
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var cards: Array = ui._cards
	ui._unhandled_input(_key(KEY_D))
	assert_int(ui._selected).is_equal(1)
	assert_object(ui.get_viewport().gui_get_focus_owner()).is_same(cards[1])   # 焦点回写
	cards[3].grab_focus()
	assert_int(ui._selected).is_equal(3)               # 焦点移动 → 高亮同步
	ui._unhandled_input(_key(KEY_A))
	assert_int(ui._selected).is_equal(2)
	assert_object(ui.get_viewport().gui_get_focus_owner()).is_same(cards[2])
	_reset_last_chosen()

func _click(idx: int, pressed: bool, pos := Vector2.ZERO) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = pos
	return click

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

# ---- M4.5 u3：选角卡立绘/技能/被动图标接线 + 解锁状态视觉标签 ----

func test_hero_select_portraits_wired() -> void:
	# 6 卡各有非空 portrait 纹理：生成器原生 32x32、×2 整数放大、最近邻、
	# 鼠标穿透（不吞 PanelContainer 的轻点判定）
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_int(ui._portraits.size()).is_equal(6)
	for i in 6:
		var p: TextureRect = ui._portraits[i]
		assert_object(p.texture).is_not_null()
		assert_int(p.texture.get_width()).is_equal(32)
		assert_int(p.texture.get_height()).is_equal(32)
		assert_vector(p.custom_minimum_size).is_equal(Vector2(64, 64))
		assert_int(p.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_hero_select_icon_maps_cover_all_heroes_and_files_exist() -> void:
	# 表驱动映射全覆盖 6 英雄（passive 按 passive_id、skill 按英雄 id），且每条
	# 映射指向的贴图文件真实存在（同 ArtLookup「表驱动路径必须存在」契约）
	assert_int(HeroSelect.PASSIVE_ICONS.size()).is_equal(6)
	assert_int(HeroSelect.SKILL_ICONS.size()).is_equal(6)
	for id: String in GameDB.heroes:
		var pid := String(GameDB.heroes[id].get("passive_id", ""))
		assert_bool(HeroSelect.PASSIVE_ICONS.has(pid)).is_true()
		assert_bool(FileAccess.file_exists(
			"res://art/generated/ui/%s.png" % HeroSelect.PASSIVE_ICONS[pid])).is_true()
		assert_bool(HeroSelect.SKILL_ICONS.has(id)).is_true()
		assert_bool(FileAccess.file_exists(
			"res://art/generated/ui/%s.png" % HeroSelect.SKILL_ICONS[id])).is_true()

func test_hero_select_cards_show_skill_and_passive_icons() -> void:
	# 卡内被动/技能行各挂非空图标：原生 12x12/16x16 ×2 整数放大、最近邻
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_int(ui._passive_icons.size()).is_equal(6)
	assert_int(ui._skill_icons.size()).is_equal(6)
	for i in 6:
		var pi: TextureRect = ui._passive_icons[i]
		assert_object(pi.texture).is_not_null()
		assert_vector(pi.custom_minimum_size).is_equal(Vector2(24, 24))
		assert_int(pi.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		var si: TextureRect = ui._skill_icons[i]
		assert_object(si.texture).is_not_null()
		assert_vector(si.custom_minimum_size).is_equal(Vector2(32, 32))
		assert_int(si.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)

func test_hero_select_unlock_badges_follow_unlocked_list() -> void:
	# 解锁标签与解锁名单一致（unlocked_override 注入确定态，不触碰环境档——
	# headless 共享档残留态不得造成跨用例漂移）：仅 vanguard 已解锁时其余 5 卡
	# 角标可见 + 立绘半透明；角标文案含「待解锁」「开放体验」。过渡语义：未解锁
	# 卡保持可点可玩（不锁 _choose，购买流裁定前的开放试玩标注）。
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	ui.unlocked_override = ["vanguard"] as Array[String]
	add_child(ui)
	for i in 6:
		var locked := String(ui._ids[i]) != "vanguard"
		assert_bool(ui._badges[i].visible).is_equal(locked)
		assert_bool(ui.is_hero_unlocked(String(ui._ids[i]))).is_equal(not locked)
		assert_float(ui._portraits[i].modulate.a).is_equal_approx(0.45 if locked else 1.0, 0.001)
	# m4p-ui1 分工：铭牌角标只放「锁」一览信号（72px 铭牌容不下两行文案——曾因塞
	# 折叠 Label 触发 font_render_smoke「Label 收在卡内」告警）；「待解锁 · 开放体验」
	# 的解释文案移入共享详情面板，且仅当选中英雄未解锁时可见。
	var badge_texts: Array[String] = []
	for l: Node in (ui._badges[1] as Control).find_children("*", "Label", true, false):
		badge_texts.append((l as Label).text)
	assert_array(badge_texts).contains("锁")
	ui._selected = 1                                  # 选中未解锁的 ranger
	ui._refresh()
	assert_bool(ui._detail_badge.visible).is_true()
	assert_str(ui._detail_badge.text).contains("待解锁")
	assert_str(ui._detail_badge.text).contains("开放体验")
	ui._selected = 0                                  # 选中已解锁的 vanguard → 提示隐藏
	ui._refresh()
	assert_bool(ui._detail_badge.visible).is_false()
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	ui._choose(1)                                     # 未解锁（ranger）仍可选中
	assert_array(chosen).contains_exactly(["ranger"])
	_reset_last_chosen()

func test_hero_select_detail_panel_shows_only_selected_hero() -> void:
	# m4p-ui1 视觉重做的核心契约：长文案（被动/技能）从「6 张卡各抄一份」改为
	# 「共享详情面板只渲染选中那份」。逐英雄预建 6 份行容器（图标注册表长度恒 6
	# 的既有契约不变），任一时刻恰好 1 份可见；名字/数值/初始武器随选中同步。
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_object(ui._detail_name).is_not_null()
	for sel in [0, 3, 5, 1]:
		ui._selected = sel
		ui._refresh()
		var id := String(ui._ids[sel])
		var hero: Dictionary = GameDB.get_hero(id)
		assert_str(ui._detail_name.text).is_equal(String(hero["name"]))
		var visible_passives := 0
		var visible_skills := 0
		for i in 6:
			if ui._passive_rows[i].visible:
				visible_passives += 1
				assert_int(i).is_equal(sel)      # 可见的那份必须是选中英雄
			if ui._skill_rows[i].visible:
				visible_skills += 1
				assert_int(i).is_equal(sel)
		assert_int(visible_passives).is_equal(1)
		assert_int(visible_skills).is_equal(1)
		assert_str(ui._skill_labels[sel].text).contains(String(hero["skill_name"]))
		assert_str(ui._detail_weapon.text).contains("初始")
	# 数值芯片：5 项（HP/盾/蓝/速/暴击）逐项独立底块，值随选中英雄刷新
	assert_int(ui._detail_stats.get_child_count()).is_equal(5)
	ui._selected = 0
	ui._refresh()
	var vanguard: Dictionary = GameDB.get_hero(String(ui._ids[0]))
	var hp_chip := ui._detail_stats.get_child(0) as PanelContainer
	assert_str((hp_chip.get_child(0).get_child(1) as Label).text) \
		.is_equal(str(int(vanguard["hp"])))

func test_hero_select_plaques_all_fit_without_scrolling() -> void:
	# ui1 布局意图钉死：6 枚铭牌一屏全见（旧 206px 卡在 480px 视窗只见 2 张）。
	# 铭牌总宽 = 6×72 + 5×6 间距 = 462 ≤ CardScroll 视窗 468；同时保留横滚容器
	# （触屏惯例 + follow_focus + 窄屏兜底），故只断言「不需要滚动」而非「禁用滚动」。
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_vector(HeroSelect.CARD_MIN).is_equal(Vector2(72, 96))
	var row := ui.get_node("CardScroll/Cards") as HBoxContainer
	var sep := int(row.get_theme_constant("separation"))
	var total := 6 * int(HeroSelect.CARD_MIN.x) + 5 * sep
	var viewport_w := int((ui.get_node("CardScroll") as ScrollContainer).size.x)
	assert_int(total).is_less_equal(viewport_w)
	# 选中态四重视觉信号（48px 级铭牌单靠 1px 描边区分度不足）：顶部高亮条不透明、
	# 立绘微放大、名字金字、底色转暖——逐项断言选中/未选中确有差异
	ui._selected = 2
	ui._refresh()
	assert_float(ui._accents[2].color.a).is_equal_approx(1.0, 0.001)
	assert_float(ui._accents[0].color.a).is_equal_approx(0.0, 0.001)
	assert_bool(ui._portraits[2].scale.x > ui._portraits[0].scale.x).is_true()
	assert_object(ui._name_labels[2].get_theme_color("font_color")) \
		.is_not_equal(ui._name_labels[0].get_theme_color("font_color"))

func test_hero_select_save_absent_renders_all_unlocked_zero_drift() -> void:
	# SaveSystem 缺席（ignore_save 模拟缺席路径）按全解锁渲染：无角标、立绘不
	# 透明、is_hero_unlocked 恒真——测试/无头环境零漂移基线
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	ui.ignore_save = true
	add_child(ui)
	for i in 6:
		assert_bool(ui._badges[i].visible).is_false()
		assert_bool(ui.is_hero_unlocked(String(ui._ids[i]))).is_true()
		assert_float(ui._portraits[i].modulate.a).is_equal_approx(1.0, 0.001)

func test_hero_select_unlock_labels_match_ambient_save_when_present() -> void:
	# 环境存在 SaveSystem（GdUnit 进程 autoload 恒载）时：构建期解析与档内
	# unlocked_heroes 键逐英雄一致（只读；键损/缺席 fail-SOFT 全解锁）
	var ss := get_node_or_null("/root/SaveSystem")
	if ss == null:
		return                # 无 autoload 环境：缺席路径已由 ignore_save 用例覆盖
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var saved: Variant = (ss.get("data") as Dictionary).get("unlocked_heroes")
	if typeof(saved) != TYPE_ARRAY:
		for i in 6:
			assert_bool(ui.is_hero_unlocked(String(ui._ids[i]))).is_true()
		return
	for i in 6:
		var id := String(ui._ids[i])
		assert_bool(ui.is_hero_unlocked(id)).is_equal((saved as Array).has(id))
