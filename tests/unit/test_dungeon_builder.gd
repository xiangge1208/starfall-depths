class_name TestDungeonBuilder
extends GdUnitTestSuite
## M1-T7：DungeonBuilder 地牢装配契约测试。
## 断言清单来源：task-7-brief——3 种子样本结构断言（13 房/12 走廊/world_pos 数学）、
## 人为错配被 validate_build 拒绝、combat 模板层内去重 ≤2、同种子逐字段确定性。
##
## 数据发现（详见 task-7-report）：A1 固定模板门集合与图的随机方向需门存在系统性错配
## （start_a1={S,E} 仅覆盖 ~44% 种子的 start 需门；boss_a1={N,S} 仅 ~50%）。故本套件
## 对真实构建体钉住「除门错配外其余校验必净」；门全对齐由手工构造的对齐构建体正/
## 反两向验证（accepts aligned / rejects corrupted），不静默重映射。

const SEEDS := [20260828, 7, 1234]
const SALT := 777
const TOTAL_NODES := 13
const EDGE_COUNT := 12  # 13 节点树
const SPAN_PX := 416.0  # 房间跨度 26 格 × 16px


func _build(seed: int) -> Dictionary:
	return DungeonBuilder.build(seed, 1)


# ---------------------------------------------------------------- build 结构

func test_build_root_shape_three_seeds() -> void:
	for s in SEEDS:
		var build := _build(int(s))
		assert_dict(build).contains_keys("rooms", "corridors", "start_room_id", "boss_room_id")
		var rooms: Dictionary = build["rooms"]
		assert_int(rooms.size()).is_equal(TOTAL_NODES)
		var corridors: Array = build["corridors"]
		assert_int(corridors.size()).is_equal(EDGE_COUNT)
		# start/boss 房存在且类型正确；start id 恒 0（DungeonGraph 规格）
		assert_int(int(build["start_room_id"])).is_equal(0)
		var start: Dictionary = rooms[int(build["start_room_id"])]
		assert_str(String(start["node"]["type"])).is_equal("start")
		var boss: Dictionary = rooms[int(build["boss_room_id"])]
		assert_str(String(boss["node"]["type"])).is_equal("boss")


func test_room_payload_and_template_exists() -> void:
	var build := _build(SEEDS[0])
	var rooms: Dictionary = build["rooms"]
	for id in rooms:
		var room: Dictionary = rooms[id]
		assert_bool(room.has("node") and room.has("template_id") and room.has("world_pos")).is_true()
		var node: Dictionary = room["node"]
		assert_int(int(node["id"])).is_equal(int(id))
		var tid := String(room["template_id"])
		assert_bool(RoomTemplate.get_room(tid).is_empty()).is_false()
	# start/boss 模板固定
	assert_str(String(rooms[int(build["start_room_id"])]["template_id"])).is_equal("start_a1")
	assert_str(String(rooms[int(build["boss_room_id"])]["template_id"])).is_equal("boss_a1")


func test_special_types_use_combat_pool() -> void:
	# elite/shop/treasure/event/miniboss/combat 全部从 combat 池取模板（本任务只管几何）
	var pool := RoomTemplate.combat_ids(1)
	for s in SEEDS:
		var rooms: Dictionary = _build(int(s))["rooms"]
		for id in rooms:
			var room: Dictionary = rooms[id]
			var ntype := String(room["node"]["type"])
			var tid := String(room["template_id"])
			if ntype == "start":
				assert_str(tid).is_equal("start_a1")
			elif ntype == "boss":
				assert_str(tid).is_equal("boss_a1")
			else:
				assert_bool(pool.has(tid)).is_true()


func test_world_pos_is_grid_times_span() -> void:
	var build := _build(SEEDS[0])
	var rooms: Dictionary = build["rooms"]
	for id in rooms:
		var room: Dictionary = rooms[id]
		var grid: Vector2i = room["node"]["grid"]
		var wp: Vector2 = room["world_pos"]
		assert_bool(wp == Vector2(grid) * SPAN_PX).is_true()
	# 锚点：start 恒在 grid (0,0) → 世界原点
	var start: Dictionary = rooms[int(build["start_room_id"])]
	assert_bool(start["world_pos"] == Vector2.ZERO).is_true()


func test_corridors_match_graph_edges_and_dirs() -> void:
	for s in SEEDS:
		var build := _build(int(s))
		var rooms: Dictionary = build["rooms"]
		var expected := {}
		var edge_total := 0
		for id in rooms:
			var nexts: Array = rooms[id]["node"]["next"]
			edge_total += nexts.size()
			for nx in nexts:
				expected["%d->%d" % [int(id), int(nx)]] = true
		assert_int(edge_total).is_equal(EDGE_COUNT)
		var corridors: Array = build["corridors"]
		assert_int(corridors.size()).is_equal(EDGE_COUNT)
		var seen := {}
		for c in corridors:
			var corridor: Dictionary = c
			assert_bool(corridor.has("a") and corridor.has("b") and corridor.has("dir")).is_true()
			var key := "%d->%d" % [int(corridor["a"]), int(corridor["b"])]
			assert_bool(expected.has(key)).is_true()   # 恰为图边集
			assert_bool(seen.has(key)).is_false()      # 无重复
			seen[key] = true
			var ga: Vector2i = rooms[int(corridor["a"])]["node"]["grid"]
			var gb: Vector2i = rooms[int(corridor["b"])]["node"]["grid"]
			var delta := gb - ga
			var dir := String(corridor["dir"])
			var want := Vector2i.ZERO
			match dir:
				"N":
					want = Vector2i(0, -1)
				"S":
					want = Vector2i(0, 1)
				"E":
					want = Vector2i(1, 0)
				"W":
					want = Vector2i(-1, 0)
			assert_bool(delta == want).is_true()       # dir 与网格位移一致


# ---------------------------------------------------------------- 去重/确定性

func test_no_combat_template_more_than_twice_per_floor() -> void:
	# 40 层样本：任一 combat 模板同层使用 ≤2；start/boss 恒 1 次
	var pool := RoomTemplate.combat_ids(1)
	for i in 40:
		var rooms: Dictionary = _build(100000 + i)["rooms"]
		var counts := {}
		for id in rooms:
			var tid := String(rooms[id]["template_id"])
			counts[tid] = int(counts.get(tid, 0)) + 1
		for tid: String in counts:
			if pool.has(tid):
				assert_int(int(counts[tid])).is_less_equal(2)
			else:
				assert_int(int(counts[tid])).is_equal(1)  # start_a1 / boss_a1


func test_deterministic_same_seed_identical_build() -> void:
	var a := _build(SEEDS[0])
	var b := _build(SEEDS[0])
	# 逐字段（字典序列化含键序，逐字节相同即逐字段相同）
	assert_str(var_to_str(a)).is_equal(var_to_str(b))
	# 关键字段显式复核
	var ar: Dictionary = a["rooms"]
	var br: Dictionary = b["rooms"]
	assert_int(ar.size()).is_equal(br.size())
	for id in ar:
		assert_str(String(ar[id]["template_id"])).is_equal(String(br[id]["template_id"]))
		assert_bool(Vector2(ar[id]["world_pos"]) == Vector2(br[id]["world_pos"])).is_true()
	var ac: Array = a["corridors"]
	var bc: Array = b["corridors"]
	assert_int(ac.size()).is_equal(bc.size())
	for i in ac.size():
		assert_str(var_to_str(ac[i])).is_equal(var_to_str(bc[i]))


func test_seed_at_uses_stable_hash_with_salt_777() -> void:
	assert_int(DungeonBuilder.seed_at(0)).is_equal(RngSvc.stable_hash(0, SALT))
	assert_int(DungeonBuilder.seed_at(999)).is_equal(RngSvc.stable_hash(999, SALT))


func test_combat_pool_matches_room_template_accessor() -> void:
	# --script 无头模式编译约束（见 dungeon_builder.gd 头注）镜像了 combat_ids 逻辑，
	# 此处钉住两者等价，防漂移
	assert_array(DungeonBuilder.combat_pool(1)).is_equal(RoomTemplate.combat_ids(1))
	assert_array(DungeonBuilder.combat_pool(2)).is_empty()


# ---------------------------------------------------------------- validate_build

## 手工构造的门全对齐构建体：start_a1(E 门)→combat_a1_01(W/S 门)→boss_a1(N 门)。
func _aligned_build() -> Dictionary:
	var rooms := {
		0: {
			"node": {"id": 0, "type": "start", "grid": Vector2i(0, 0), "depth": 0, "next": [1]},
			"template_id": "start_a1", "world_pos": Vector2.ZERO,
		},
		1: {
			"node": {"id": 1, "type": "combat", "grid": Vector2i(1, 0), "depth": 1, "next": [2]},
			"template_id": "combat_a1_01", "world_pos": Vector2(SPAN_PX, 0.0),
		},
		2: {
			"node": {"id": 2, "type": "boss", "grid": Vector2i(1, 1), "depth": 2, "next": []},
			"template_id": "boss_a1", "world_pos": Vector2(SPAN_PX, SPAN_PX),
		},
	}
	var corridors := [{"a": 0, "b": 1, "dir": "E"}, {"a": 1, "b": 2, "dir": "S"}]
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": 2}


func test_validate_accepts_door_aligned_build() -> void:
	# 门对齐「正向」用例：合法构建体 → 空错误
	assert_array(DungeonBuilder.validate_build(_aligned_build())).is_empty()


func test_validate_rejects_corridor_dir_flip() -> void:
	# 人为错配：翻转一条走廊方向 → 拒绝
	var build := _aligned_build()
	var corridors: Array = build["corridors"]
	(corridors[0] as Dictionary)["dir"] = "S"  # 0→1 网格位移是 E，翻成 S
	var errs := DungeonBuilder.validate_build(build)
	assert_array(errs).is_not_empty()


func test_validate_rejects_missing_door() -> void:
	# 门对齐「反向」用例：combat 换成无 S 门的模板 → 门错配被报
	var build := _aligned_build()
	(build["rooms"][1] as Dictionary)["template_id"] = "combat_a1_03"  # doors W,E,N
	var errs := DungeonBuilder.validate_build(build)
	assert_array(errs).is_not_empty()
	var door_errs := 0
	for e in errs:
		if String(e).begins_with("door mismatch"):
			door_errs += 1
	assert_int(door_errs).is_greater(0)


func test_validate_rejects_unknown_template() -> void:
	var build := _aligned_build()
	(build["rooms"][1] as Dictionary)["template_id"] = "no_such_room"
	assert_array(DungeonBuilder.validate_build(build)).is_not_empty()


func test_validate_rejects_bad_world_pos() -> void:
	var build := _aligned_build()
	(build["rooms"][1] as Dictionary)["world_pos"] = Vector2(123.0, 0.0)
	var errs := DungeonBuilder.validate_build(build)
	assert_array(errs).is_not_empty()
	var pos_errs := 0
	for e in errs:
		if String(e).contains("world_pos"):
			pos_errs += 1
	assert_int(pos_errs).is_greater(0)


func test_validate_rejects_missing_root_keys() -> void:
	assert_array(DungeonBuilder.validate_build({})).is_not_empty()
	assert_array(DungeonBuilder.validate_build({"rooms": {}})).is_not_empty()


func test_validate_rejects_dangling_corridor() -> void:
	var build := _aligned_build()
	build["corridors"] = [{"a": 0, "b": 9, "dir": "E"}]
	assert_array(DungeonBuilder.validate_build(build)).is_not_empty()


func test_real_builds_fail_only_on_door_mismatch() -> void:
	# 数据发现钉住：真实构建体除「门错配」外，全部其余校验（模板存在/world_pos/走廊
	# 完整性/朝向）必净——即任何错误只来自模板门数据与图方向的系统性错配，
	# 而非装配逻辑缺陷。
	for s in SEEDS:
		var errs := DungeonBuilder.validate_build(_build(int(s)))
		for e in errs:
			assert_bool(String(e).begins_with("door mismatch")).is_true()


func test_real_seed_388_fully_door_aligned() -> void:
	# 1000 种子扫描中唯一门全对齐样本（tools/validate_dungeon.gd 的 1/1000 PASS）：
	# 真实构建体 + 真实模板的门对齐「正向」钉住
	var build := _build(DungeonBuilder.seed_at(388))
	assert_array(DungeonBuilder.validate_build(build)).is_empty()


func test_floor_without_templates_fails_closed() -> void:
	# A2 模板未实装：floor_idx=2 产出结构但 validate_build 报缺失（不静默回退 A1）
	var build := DungeonBuilder.build(SEEDS[0], 2)
	assert_int((build["rooms"] as Dictionary).size()).is_equal(TOTAL_NODES)
	assert_array(DungeonBuilder.validate_build(build)).is_not_empty()
