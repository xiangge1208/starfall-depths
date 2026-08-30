class_name TestHeroes
extends GdUnitTestSuite
## M1 t11：heroes.json 数据层（HERO_SCHEMA fail-closed + start_weapons 语义校验）
## + HeroApplier 装配（面板四字段/初始武器/meta 接缝/技能换装）+ HeroSelect 静态暂存。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const HERO_SELECT_SCENE := preload("res://ui/hero_select.tscn")

# ---- 数据层：heroes 装载 + schema ----

func test_three_heroes_loaded() -> void:
	assert_bool(GameDB.load_ok).is_true()
	assert_dict(GameDB.heroes).contains_keys("vanguard", "ranger", "engineer")
	assert_int(GameDB.heroes.size()).is_equal(3)   # M2-T8：+engineer（工程师·铆）

func test_hero_schema_all_16_keys_required() -> void:
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
	assert_dict(GameDB.HERO_OPTIONAL).is_empty()      # 全部必填，无 optional 默认

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

func test_hero_skill_scripts_exist_and_extend_skill_base() -> void:
	for id: String in GameDB.heroes:
		var path := String(GameDB.heroes[id]["skill_script"])
		assert_bool(FileAccess.file_exists(path)).is_true()
		var script: Script = load(path)
		assert_object(script).is_not_null()
		assert_str(script.get_base_script().resource_path).is_equal("res://core/player/skills/skill_base.gd")

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

# ---- HeroSelect 静态暂存 + 选角 UI（逻辑层无头测试；观感手动）----

func _reset_last_chosen() -> void:
	HeroSelect.last_chosen = ""      # 静态状态跨用例复位

func test_hero_select_static_fallback_stores_choice() -> void:
	_reset_last_chosen()
	HeroSelect.last_chosen = "ranger"
	assert_str(HeroSelect.last_chosen).is_equal("ranger")
	_reset_last_chosen()

func test_hero_select_scene_builds_three_cards() -> void:
	var ui: Control = HERO_SELECT_SCENE.instantiate()
	auto_free(ui)
	add_child(ui)
	assert_int(ui._cards.size()).is_equal(3)   # M2-T8：GameDB 驱动自动扩展（+engineer）
	assert_int(ui._ids.size()).is_equal(3)

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
