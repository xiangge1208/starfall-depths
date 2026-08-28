class_name TestRoomTemplates
extends GdUnitTestSuite
## M1-T4：A1 房间模板库 + GameDB rooms 加载校验。

const COMBAT_IDS := ["combat_a1_01", "combat_a1_02", "combat_a1_03", "combat_a1_04",
	"combat_a1_05", "combat_a1_06", "combat_a1_07", "combat_a1_08"]
const EXPECTED_PROP_HP := {"pillar": 20, "crate": 8, "bush": 4}


func test_all_ten_templates_loaded() -> void:
	for id: String in COMBAT_IDS + ["start_a1", "boss_a1"]:
		assert_dict(GameDB.rooms).contains_keys(id)
	assert_int(GameDB.rooms.size()).is_equal(10)


func test_all_rows_pass_room_validation() -> void:
	for id: String in GameDB.rooms:
		var errors: Array[String] = GameDB.validate_room_row(GameDB.rooms[id])
		assert_array(errors).is_empty()


func test_combat_templates_at_least_8() -> void:
	assert_int(RoomTemplate.combat_ids().size()).is_greater(7)


func test_combat_ids_exclude_start_and_boss() -> void:
	var ids := RoomTemplate.combat_ids()
	assert_int(ids.size()).is_equal(8)
	for id: String in ids:
		assert_bool(id.begins_with("combat_a1_")).is_true()


func test_combat_ids_floor_param() -> void:
	# A2/A3 模板未实装：floor_idx=2 应返回空而不是 A1 的行
	assert_array(RoomTemplate.combat_ids(2)).is_empty()


func test_accessor_get_returns_row() -> void:
	var room: Dictionary = RoomTemplate.get_room("combat_a1_01")
	assert_dict(room).contains_keys("id", "size", "doors", "spawn_points", "props", "hazards")
	assert_array(room["size"]).is_equal([22, 14])


func test_accessor_get_missing_returns_empty() -> void:
	assert_dict(RoomTemplate.get_room("no_such_room")).is_empty()


func _valid_row(id: String) -> Dictionary:
	# 全部语义约束合法的基准行：spawn (5,4)/(16,9) 距门均 >= 64px
	return {
		"id": id, "size": [22, 14], "doors": ["N", "S"],
		"spawn_points": [[5, 4], [16, 9]],
		"props": [{"kind": "pillar", "grid": [10, 7], "hp": 20}],
		"hazards": [],
	}


func test_schema_rejects_spawn_near_door() -> void:
	# 控制器样例：spawn 距门 ~30px（网格上最近可表达为 2 格 = 32px < 64px）
	var row := _valid_row("bad_dist")
	row["spawn_points"] = [[11, 2]]   # N 门 (11,0) 正下方 32px
	var errors: Array[String] = GameDB.validate_room_row(row)
	assert_int(errors.size()).is_greater(0)
	assert_str(errors[0]).contains("door")


func test_schema_rejects_bad_door_symbol() -> void:
	var row := _valid_row("bad_door")
	row["doors"] = ["N", "X"]
	var errors: Array[String] = GameDB.validate_room_row(row)
	assert_int(errors.size()).is_greater(0)
	assert_str(errors[0]).contains("door")


func test_schema_rejects_empty_doors() -> void:
	var row := _valid_row("no_doors")
	row["doors"] = []
	assert_int(GameDB.validate_room_row(row).size()).is_greater(0)


func test_schema_rejects_duplicate_doors() -> void:
	var row := _valid_row("dup_doors")
	row["doors"] = ["N", "N"]
	assert_int(GameDB.validate_room_row(row).size()).is_greater(0)


func test_schema_rejects_wrong_size() -> void:
	var row := _valid_row("bad_size")
	row["size"] = [20, 12]
	var errors: Array[String] = GameDB.validate_room_row(row)
	assert_int(errors.size()).is_greater(0)
	assert_str(errors[0]).contains("size")


func test_schema_rejects_prop_on_door_tile() -> void:
	var row := _valid_row("blocked_door")
	row["props"] = [{"kind": "crate", "grid": [11, 0], "hp": 8}]   # N 门格
	var errors: Array[String] = GameDB.validate_room_row(row)
	assert_int(errors.size()).is_greater(0)
	assert_str(errors[0]).contains("door")


func test_schema_rejects_prop_out_of_bounds() -> void:
	var row := _valid_row("oob_prop")
	row["props"] = [{"kind": "crate", "grid": [22, 5], "hp": 8}]
	var errors: Array[String] = GameDB.validate_room_row(row)
	assert_int(errors.size()).is_greater(0)
	assert_str(errors[0]).contains("bounds")


func test_schema_rejects_spawn_out_of_bounds() -> void:
	var row := _valid_row("oob_spawn")
	row["spawn_points"] = [[5, 14]]   # y 上限 13
	assert_int(GameDB.validate_room_row(row).size()).is_greater(0)


func test_prop_hp_contract() -> void:
	# pillar 20 / crate 8 / bush 4，全表一致
	for id: String in GameDB.rooms:
		for p: Dictionary in GameDB.rooms[id]["props"]:
			assert_int(p["hp"]).is_equal(EXPECTED_PROP_HP[p["kind"]])


func test_prop_kinds_and_bullets() -> void:
	# 柱/箱挡弹，灌木不挡弹（视觉/危险区）——行为契约由后续 RoomCombat 按 kind 实现
	assert_bool(GameDB.PROP_BLOCKS_BULLETS["pillar"]).is_true()
	assert_bool(GameDB.PROP_BLOCKS_BULLETS["crate"]).is_true()
	assert_bool(GameDB.PROP_BLOCKS_BULLETS["bush"]).is_false()


func test_combat_layouts_distinct() -> void:
	# 8 个战斗房布局签名（kind@grid 集合）两两不同
	var sigs := {}
	for id: String in COMBAT_IDS:
		var parts: Array[String] = []
		for p: Dictionary in RoomTemplate.get_room(id)["props"]:
			parts.append("%s@%d,%d" % [p["kind"], p["grid"][0], p["grid"][1]])
		parts.sort()
		sigs["|".join(PackedStringArray(parts))] = true
	assert_int(sigs.size()).is_equal(8)


func test_hazards_vine_data_only() -> void:
	# 本任务 hazard 仅数据（藤蔓减速带，效果后续任务实现）
	var hazard_count := 0
	for id: String in GameDB.rooms:
		for h: Dictionary in GameDB.rooms[id]["hazards"]:
			hazard_count += 1
			assert_str(h["kind"]).is_equal("vine")
			assert_int(h["radius"]).is_equal(24)
	assert_int(hazard_count).is_greater(0)


func test_start_room_safe() -> void:
	var start: Dictionary = RoomTemplate.get_room("start_a1")
	# fix round 1（裁定）：start_a1 门补全为 4 向——未用门为封闭门框几何，
	# 房间只对实际使用的门上锁/解锁（M0 行为）；安全房契约（无刷怪点）不变
	assert_int(start["doors"].size()).is_equal(4)
	assert_int(start["spawn_points"].size()).is_equal(0)


func test_boss_room_two_pillars() -> void:
	var boss: Dictionary = RoomTemplate.get_room("boss_a1")
	# fix round 1（裁定）：boss_a1 门补全为 4 向（同 start_a1 语义）
	assert_int(boss["doors"].size()).is_equal(4)
	var pillars := 0
	for p: Dictionary in boss["props"]:
		if p["kind"] == "pillar":
			pillars += 1
	assert_int(pillars).is_equal(2)


func test_nested_int_restore() -> void:
	# JSON.parse_string 全浮点：嵌套的 hp/坐标必须还原为 int
	var room: Dictionary = RoomTemplate.get_room("combat_a1_01")
	assert_int(typeof(room["props"][0]["hp"])).is_equal(TYPE_INT)
	assert_int(typeof(room["spawn_points"][0][0])).is_equal(TYPE_INT)


func test_load_table_rejects_bad_room_row() -> void:
	# fail-closed 闭环：extra_check（validate_room_row）报错的行被拒且 load_ok=false
	var path := "user://test_bad_room_t4.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"bad": {"id":"bad","size":[22,14],"doors":["N"],'
		+ '"spawn_points":[[11,2]],"props":[],"hazards":[]}}')
	f = null
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var loaded: Dictionary = db._load_table(path, GameDB.ROOM_SCHEMA, GameDB.ROOM_OPTIONAL,
		Callable(db, "validate_room_row"))
	assert_dict(loaded).is_empty()
	assert_bool(db.load_ok).is_false()
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)


func test_load_table_accepts_valid_room_row() -> void:
	var path := "user://test_ok_room_t4.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"ok": {"id":"ok","size":[22,14],"doors":["N","S"],'
		+ '"spawn_points":[[5,4],[16,9]],"props":[{"kind":"pillar","grid":[10,7],"hp":20}],'
		+ '"hazards":[{"kind":"vine","grid":[8,8],"radius":24}]}}')
	f = null
	var db: Variant = auto_free(load("res://autoload/game_db.gd").new())
	var loaded: Dictionary = db._load_table(path, GameDB.ROOM_SCHEMA, GameDB.ROOM_OPTIONAL,
		Callable(db, "validate_room_row"))
	assert_bool(db.load_ok).is_true()
	assert_dict(loaded).contains_keys("ok")
	assert_int(loaded["ok"]["props"][0]["hp"]).is_equal(20)
	assert_int(loaded["ok"]["hazards"][0]["radius"]).is_equal(24)
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)
