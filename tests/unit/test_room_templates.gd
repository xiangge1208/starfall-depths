class_name TestRoomTemplates
extends GdUnitTestSuite
## M1-T4：A1 房间模板库 + GameDB rooms 加载校验。
## m2-t26：A2/A3 模板 ×16 落库（每生态 8 战斗 + 起始/Boss，biome 字段 + A2 冰面/地刺/
## 晶柱 + A3 岩浆/喷口 hazards 字段）。

const COMBAT_IDS := ["combat_a1_01", "combat_a1_02", "combat_a1_03", "combat_a1_04",
	"combat_a1_05", "combat_a1_06", "combat_a1_07", "combat_a1_08"]
const COMBAT_A2_IDS := ["combat_a2_01", "combat_a2_02", "combat_a2_03", "combat_a2_04",
	"combat_a2_05", "combat_a2_06", "combat_a2_07", "combat_a2_08"]
const COMBAT_A3_IDS := ["combat_a3_01", "combat_a3_02", "combat_a3_03", "combat_a3_04",
	"combat_a3_05", "combat_a3_06", "combat_a3_07", "combat_a3_08"]
const EXPECTED_PROP_HP := {"pillar": 20, "crate": 8, "bush": 4, "crystal_pillar": 20}


func test_all_ten_templates_loaded() -> void:
	for id: String in COMBAT_IDS + ["start_a1", "boss_a1"]:
		assert_dict(GameDB.rooms).contains_keys(id)
	assert_int(GameDB.rooms.size()).is_equal(30)   # m2-t26：A1 10 + A2 10 + A3 10


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
	# m2-t26：A2/A3 模板落库——floor 参数按层取池（8 行同层模板，不串层）
	var ids2 := RoomTemplate.combat_ids(2)
	assert_int(ids2.size()).is_equal(8)
	for id: String in ids2:
		assert_bool(id.begins_with("combat_a2_")).is_true()
	var ids3 := RoomTemplate.combat_ids(3)
	assert_int(ids3.size()).is_equal(8)
	for id: String in ids3:
		assert_bool(id.begins_with("combat_a3_")).is_true()


# ---------------------------------------------------------------- m2-t26 A2/A3 模板

func test_a2_a3_sixteen_combat_templates_loaded() -> void:
	# 16 战斗模板 + 各层起始/Boss（4 门完备）全部入库
	for id: String in COMBAT_A2_IDS + COMBAT_A3_IDS + ["start_a2", "boss_a2", "start_a3", "boss_a3"]:
		assert_dict(GameDB.rooms).contains_keys(id)
	for id: String in COMBAT_A2_IDS + COMBAT_A3_IDS:
		var row: Dictionary = GameDB.rooms[id]
		assert_array(row["size"]).is_equal([22, 14])
		assert_array(row["doors"]).is_not_empty()
		assert_array(row["spawn_points"]).is_not_empty()
	# 起始/Boss 模板 4 门完备（未用门为封闭门框，装配器 fit-aware 恒覆盖）
	for id: String in ["start_a1", "boss_a1", "start_a2", "boss_a2", "start_a3", "boss_a3"]:
		assert_array((GameDB.rooms[id] as Dictionary)["doors"]).is_equal(["N", "S", "E", "W"])


func test_biome_field_driven_by_template() -> void:
	# biome optional 键：A2 行 crystal / A3 行 magma / A1 行缺省 ""（无群系特效）
	for id: String in COMBAT_A2_IDS + ["start_a2", "boss_a2"]:
		assert_str(String(GameDB.rooms[id].get("biome", ""))).is_equal("crystal")
	for id: String in COMBAT_A3_IDS + ["start_a3", "boss_a3"]:
		assert_str(String(GameDB.rooms[id].get("biome", ""))).is_equal("magma")
	for id: String in COMBAT_IDS + ["start_a1", "boss_a1"]:
		assert_str(String(GameDB.rooms[id].get("biome", ""))).is_equal("")


func _hazard_kinds(ids: Array, kind: String) -> int:
	var n := 0
	for id: String in ids:
		for hz: Dictionary in (GameDB.rooms[id] as Dictionary)["hazards"]:
			if String(hz["kind"]) == kind:
				n += 1
	return n


func test_a2_hazard_fields_ice_spikes_crystal_pillars() -> void:
	# A2：冰面（radius 形状）+ 地刺（grid）+ 晶柱（crystal_pillar props，折射语义 M4 接线）
	var ice := _hazard_kinds(COMBAT_A2_IDS, "ice")
	var spikes := _hazard_kinds(COMBAT_A2_IDS, "spikes")
	assert_int(ice).is_greater_equal(8)
	assert_int(spikes).is_greater_equal(12)
	var crystals := 0
	for id: String in COMBAT_A2_IDS:
		var has_crystal := false
		for p: Dictionary in (GameDB.rooms[id] as Dictionary)["props"]:
			if String(p["kind"]) == "crystal_pillar":
				assert_int(int(p["hp"])).is_equal(20)
				has_crystal = true
		crystals += 1 if has_crystal else 0
	assert_int(crystals).is_equal(8)          # 每张 A2 战斗模板至少 1 根晶柱
	for hz: Dictionary in (GameDB.rooms["combat_a2_01"] as Dictionary)["hazards"]:
		if String(hz["kind"]) == "ice":
			assert_int(int(hz["radius"])).is_greater(0)


func test_a3_hazard_fields_magma_geysers() -> void:
	# A3：岩浆 DOT 池（radius）+ 间歇喷口（grid）；每张 A3 战斗模板至少 1 个岩浆系 hazards
	var magma := _hazard_kinds(COMBAT_A3_IDS, "magma")
	var geysers := _hazard_kinds(COMBAT_A3_IDS, "geyser")
	assert_int(magma).is_greater_equal(8)
	assert_int(geysers).is_greater_equal(10)
	for id: String in COMBAT_A3_IDS:
		var has_lava := false
		for hz: Dictionary in (GameDB.rooms[id] as Dictionary)["hazards"]:
			match String(hz["kind"]):
				"magma":
					assert_int(int(hz["radius"])).is_greater(0)
					has_lava = true
				"geyser":
					has_lava = true
		assert_bool(has_lava).is_true()


func test_a2_a3_template_layouts_distinct() -> void:
	# 布局差异化（T4 原则）：同层 8 模板的 props+hazards 布局指纹互不相同
	for ids: Array in [COMBAT_A2_IDS, COMBAT_A3_IDS]:
		var seen := {}
		for id: String in ids:
			var row: Dictionary = GameDB.rooms[id]
			var fingerprint := var_to_str(row["doors"]) + "|" + var_to_str(row["props"]) \
				+ "|" + var_to_str(row["hazards"])
			assert_bool(seen.has(fingerprint)).is_false()
			seen[fingerprint] = id


func test_schema_rejects_bad_biome_tag() -> void:
	var row := _valid_row("bad_biome")
	row["biome"] = "jungle"
	assert_array(GameDB.validate_room_row(row)).is_not_empty()


func test_schema_accepts_ice_hazard_with_radius() -> void:
	var row := _valid_row("ice_ok")
	row["hazards"] = [{"kind": "ice", "grid": [11, 7], "radius": 32}]
	assert_array(GameDB.validate_room_row(row)).is_empty()


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
	# 本任务 hazard 仅数据（藤蔓减速带，效果后续任务实现）；m2-t26 起库含 A2/A3
	# 冰面/地刺/岩浆/喷口行——本契约收窄到 A1 行（A1 生态唯一 hazard = vine r24）
	var hazard_count := 0
	for id: String in COMBAT_IDS + ["start_a1", "boss_a1"]:
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


func test_combat_rows_carry_forge_offset() -> void:
	# m2-audit（T25 披露收口）：熔铸台常驻偏移模板行驱动——24 个 combat 行全录
	# [0,56]（迁移值，行为保持）；start/boss 行不选型（缺省 []）。
	for fl in [1, 2, 3]:
		var ids: Array[String] = RoomTemplate.combat_ids(fl)
		assert_int(ids.size()).is_equal(8)
		for id: String in ids:
			var forge: Array = GameDB.rooms[id].get("forge", [])
			assert_int(forge.size()).is_equal(2)
			assert_int(int(forge[0])).is_equal(0)
			assert_int(int(forge[1])).is_equal(56)
	for id in ["start_a1", "boss_a1", "start_a2", "boss_a2", "start_a3", "boss_a3"]:
		assert_array(GameDB.rooms[id].get("forge", [])).is_empty()


func test_schema_rejects_bad_forge_shape() -> void:
	# m2-audit：forge 形状校验 fail-closed——非数组 / 非恰 2 元 / 非数字均拒
	var base := {"id": "f", "size": [22, 14], "doors": ["N", "S"],
		"spawn_points": [[5, 4], [16, 9]], "props": [], "hazards": []}
	var one := base.duplicate(true)
	one["forge"] = [0]
	assert_int(GameDB.validate_room_row(one).size()).is_greater(0)
	var bad_type := base.duplicate(true)
	bad_type["forge"] = ["x", 56]
	assert_int(GameDB.validate_room_row(bad_type).size()).is_greater(0)
	var not_array := base.duplicate(true)
	not_array["forge"] = 56
	assert_int(GameDB.validate_room_row(not_array).size()).is_greater(0)
	var good := base.duplicate(true)
	good["forge"] = [0, 56]
	assert_array(GameDB.validate_room_row(good)).is_empty()
