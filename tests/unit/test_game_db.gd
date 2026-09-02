class_name TestGameDb
extends GdUnitTestSuite

func test_m0_weapons_loaded() -> void:
	for id in ["laohuoji", "maodingqiang", "duangong", "xuetufazhang", "tiejian", "shuangbi"]:
		assert_dict(GameDB.weapons).contains_keys(id)

func test_get_weapon_returns_row() -> void:
	var w := GameDB.get_weapon("laohuoji")
	assert_str(w.get("name", "")).is_equal("老伙计")
	assert_int(w.get("damage", -1)).is_equal(2)
	assert_bool(w.get("is_melee", true)).is_false()

func test_validate_rejects_bad_row() -> void:
	var bad := {"id": "x", "damage": "many"}   # 缺键 + 类型错
	var errors: Array[String] = GameDB.validate_row(bad, GameDB.WEAPON_SCHEMA)
	assert_int(errors.size()).is_greater(0)

func test_weapon_schema_v2_has_float_keys() -> void:
	assert_int(GameDB.WEAPON_SCHEMA.get("bullet_life", -1)).is_equal(TYPE_FLOAT)
	assert_int(GameDB.WEAPON_SCHEMA.get("bullet_radius", -1)).is_equal(TYPE_FLOAT)
	assert_int(GameDB.WEAPON_SCHEMA.get("muzzle", -1)).is_equal(TYPE_FLOAT)

func test_enemy_schema_defaults_projectile_radius() -> void:
	assert_bool(GameDB.ENEMY_OPTIONAL.has("bullet_radius")).is_true()
	assert_float(float(GameDB.ENEMY_OPTIONAL["bullet_radius"])).is_equal(3.0)
	assert_float(float(GameDB.get_enemy("crossbowman")["bullet_radius"])).is_equal(3.0)
	assert_float(float(GameDB.get_enemy("vine_colossus")["bullet_radius"])).is_equal(4.0)

func test_v2_rows_ranged_values() -> void:
	for id in ["laohuoji", "maodingqiang", "duangong", "xuetufazhang"]:
		var w := GameDB.get_weapon(id)
		assert_float(w.get("bullet_life", -1.0)).is_equal(1.2)
		assert_float(w.get("bullet_radius", -1.0)).is_equal(3.0)
		assert_float(w.get("muzzle", -1.0)).is_equal(8.0)

func test_v2_rows_melee_values() -> void:
	for id in ["tiejian", "shuangbi"]:
		var w := GameDB.get_weapon(id)
		assert_float(w.get("bullet_life", -1.0)).is_equal(0.0)
		assert_float(w.get("bullet_radius", -1.0)).is_equal(0.0)
		assert_float(w.get("muzzle", -1.0)).is_equal(0.0)

func test_load_table_rejects_non_dict_row() -> void:
	# 行值不是 Dictionary 的合法 JSON（如 {"laohuoji": 5}）必须报错而不是运行时崩溃
	var path := "user://test_bad_row.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"laohuoji": 5}')
	f = null
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())   # 全新实例，避免污染 autoload 状态
	var loaded: Dictionary = db._load_table(path, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func _fresh_db() -> Variant:
	# 全新实例，避免污染 autoload 状态（同 test_load_table_rejects_non_dict_row 既定模式）
	return auto_free(load("res://autoload/game_db.gd").new())

func _write_json(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f = null

func test_load_table_missing_file() -> void:
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_table("user://test_missing_61bf.json", GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()

func test_load_table_malformed_json() -> void:
	var path := "user://test_bad_json_61bf.json"
	_write_json(path, "{")
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_table(path, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_load_table_rejects_id_mismatch() -> void:
	var path := "user://test_id_mismatch_61bf.json"
	_write_json(path, '{"foo": %s}' % _valid_row_json("bar", "bar"))
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_table(path, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_dict(loaded).is_empty()          # 不匹配行必须被拒绝，不得入库
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_load_table_fills_optional_defaults() -> void:
	var path := "user://test_optional_fill_61bf.json"
	_write_json(path, '{"t1": %s}' % _valid_row_json("t1", "t1"))
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_table(path, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_bool(db.load_ok).is_true()
	assert_dict(loaded).contains_keys("t1")
	assert_int(loaded["t1"].get("range", -1)).is_equal(0)
	assert_float(loaded["t1"].get("arc_deg", -1.0)).is_equal(0.0)
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_load_table_rejects_fractional_int_field() -> void:
	# 2.5 这类带小数的值落入 TYPE_INT 键（damage）必须被 validate 拒绝
	var path := "user://test_frac_int_61bf.json"
	var row: String = _valid_row_json("t2", "t2").replace('"damage":2,', '"damage":2.5,')
	_write_json(path, '{"t2": %s}' % row)
	var db: Variant = _fresh_db()
	var loaded: Dictionary = db._load_table(path, GameDB.WEAPON_SCHEMA, GameDB.WEAPON_OPTIONAL)
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func test_validate_row_rejects_fractional_damage() -> void:
	var bad := {"id": "x", "damage": 2.5}
	var errors: Array[String] = GameDB.validate_row(bad, GameDB.WEAPON_SCHEMA)
	assert_int(errors.size()).is_greater(0)

func _valid_row_json(id: String, name: String) -> String:
	# 含 v2 必填键的完整合法行（省略可选键 range/arc_deg 以验证默认填充）
	return ('{"id":"%s","name":"%s","category":"pistol","rarity":"common","damage":2,'
		+ '"rate":4.0,"energy_cost":0,"bullet_speed":320,"spread_deg":2.0,"projectiles":1,'
		+ '"pierce":0,"bounce":0,"element":"none","is_melee":false,'
		+ '"bullet_life":1.2,"bullet_radius":3.0,"muzzle":8.0}') % [id, name]

# ---------------------------------------------------------------- m4-c4 祭坛 schema（权重/互斥 fail-closed）

func _altar_test_row(override: Dictionary) -> Dictionary:
	# 最小合法房间行（validate_room_row 全约束通过），祭坛键由 override 注入
	var row := {
		"id": "combat_a1_99", "size": [22, 14], "doors": ["N", "S"],
		"spawn_points": [[5, 9], [16, 9]], "props": [], "hazards": [],
	}
	for k: String in override:
		row[k] = override[k]
	return row

func test_room_altar_chance_validation() -> void:
	assert_array(GameDB.validate_room_row(_altar_test_row({"altar_chance": 0.15}))).is_empty()
	assert_array(GameDB.validate_room_row(_altar_test_row({"altar_chance": 0}))).is_empty()
	assert_array(GameDB.validate_room_row(_altar_test_row({"altar_chance": 1}))).is_empty()
	assert_int(GameDB.validate_room_row(_altar_test_row({"altar_chance": 1.5})).size()).is_greater(0)
	assert_int(GameDB.validate_room_row(_altar_test_row({"altar_chance": -0.1})).size()).is_greater(0)
	assert_int(GameDB.validate_room_row(_altar_test_row({"altar_chance": "high"})).size()).is_greater(0)

func test_room_altar_excludes_validation() -> void:
	assert_array(GameDB.validate_room_row(
		_altar_test_row({"altar_excludes": ["shop", "forge"]}))).is_empty()
	assert_array(GameDB.validate_room_row(_altar_test_row({"altar_excludes": []}))).is_empty()
	# 白名单外 kind / 重复 kind / 非字符串元素 → 拒收
	assert_int(GameDB.validate_room_row(
		_altar_test_row({"altar_excludes": ["statue"]})).size()).is_greater(0)
	assert_int(GameDB.validate_room_row(
		_altar_test_row({"altar_excludes": ["shop", "shop"]})).size()).is_greater(0)
	assert_int(GameDB.validate_room_row(
		_altar_test_row({"altar_excludes": [3]})).size()).is_greater(0)

func test_room_altar_facility_kinds_whitelist() -> void:
	# 设施 kind 白名单与祭坛互斥数据同源（Altar.roll_pending present/excludes 消费）
	for kind: String in ["shop", "forge", "shrine", "drink", "event", "chest", "fountain"]:
		assert_bool(GameDB.FACILITY_KINDS.has(kind)).is_true()

func test_room_altar_data_pins_combat_rows() -> void:
	# 24 战斗模板行全部带 0.15 生成权重 + 互斥清单；非战斗行（start/boss）缺省 0.0 不生成
	var combat_rows := 0
	for id: String in GameDB.rooms:
		var row: Dictionary = GameDB.rooms[id]
		if id.begins_with("combat_a"):
			combat_rows += 1
			assert_float(float(row["altar_chance"])).is_equal_approx(0.15, 0.0001)
			var exc: Array = row["altar_excludes"]
			for kind: String in ["shop", "forge", "shrine", "drink", "event"]:
				assert_array(exc).contains(kind)
			assert_int(exc.size()).is_equal(5)
		else:
			assert_float(float(row["altar_chance"])).is_equal_approx(0.0, 0.0001)
	assert_int(combat_rows).is_equal(24)

func test_room_altar_optional_defaults() -> void:
	assert_bool(GameDB.ROOM_OPTIONAL.has("altar_chance")).is_true()
	assert_float(float(GameDB.ROOM_OPTIONAL["altar_chance"])).is_equal_approx(0.0, 0.0001)
	assert_bool(GameDB.ROOM_OPTIONAL.has("altar_excludes")).is_true()
	var defaults: Array = GameDB.ROOM_OPTIONAL["altar_excludes"]
	assert_int(defaults.size()).is_equal(0)
