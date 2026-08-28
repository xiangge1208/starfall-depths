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
