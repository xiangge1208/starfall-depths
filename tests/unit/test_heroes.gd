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
	_reset_last_chosen()
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	var chosen: Array = []
	ui.hero_chosen.connect(func(id: String) -> void: chosen.append(id))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui._on_card_input(click, 1)
	assert_array(chosen).contains_exactly(["ranger"])
	_reset_last_chosen()

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev
