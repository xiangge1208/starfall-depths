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
