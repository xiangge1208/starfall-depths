class_name TestFloorScene
extends GdUnitTestSuite
## M1-T10：楼层场景流契约测试。
## 1) FloorFlow（纯逻辑，无头）：start 开局已清+当前；战斗房进门锁门直至 notify；
##    3 房链门矩阵；boss 门 = miniboss 已清 且 邻接侧已清；instant 房进门即清并发
##    room_event；next_rooms 邻接+开门；notify 去重；固定种子真实构建体确定性消费。
## 2) FloorScene（场景编排，headless 实例化）：房间实体/玩家落位/门闸镜像 flow；
##    战斗房两波清房开门+遥测+奖励；treasure 宝箱/event·shop 桩；elite/miniboss/
##    boss 占位嘉宾（charger 3×/3×/8×hp，colossus r16）；链路全走通 end-to-end。

const SEED := 20260828
const SPAN_PX := 416.0
const CHARGER_HP := 18          # data/enemies.json vine_charger hp（嘉宾行倍率基准）

const A1_TYPES_COMBAT := ["combat", "elite", "miniboss", "boss"]


# ---------------------------------------------------------------- 构建体替身

func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	# 模板按类型映射（FloorScene 读模板几何/刷怪点；FloorFlow 只读 node.type）：
	# start→start_a1、boss→boss_a1、其余→combat_a1_01（4 门 + 5 刷怪点）
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


## 手工链式构建体：start(0) → types[0](1) → types[1](2) → …（横向 E 走廊）。
func _typed_chain(types: Array) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var grid := Vector2i(i + 1, 0)
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), grid, nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


## 分支替身：start(0)→combat(1)；1→miniboss(2)（E）；1→boss(3)（S）。
## 钉住：boss 门 = miniboss 已清 且 boss 的邻接侧已清，缺一不可。
func _branch_build() -> Dictionary:
	var rooms := {
		0: _room(0, "start", Vector2i(0, 0), [1]),
		1: _room(1, "combat", Vector2i(1, 0), [2, 3]),
		2: _room(2, "miniboss", Vector2i(2, 0), []),
		3: _room(3, "boss", Vector2i(1, 1), []),
	}
	var corridors := [
		{"a": 0, "b": 1, "dir": "E"},
		{"a": 1, "b": 2, "dir": "E"},
		{"a": 1, "b": 3, "dir": "S"},
	]
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": 3}


# ---------------------------------------------------------------- FloorFlow 纯逻辑

func test_start_room_begins_cleared_and_current() -> void:
	var flow := FloorFlow.new()
	flow.setup(_typed_chain(["combat", "boss"]))
	assert_int(flow.current_room).is_equal(0)
	assert_array(flow.cleared).contains(0)
	assert_int(flow.cleared.size()).is_equal(1)
	assert_bool(flow.is_locked()).is_false()


func test_combat_entry_locks_until_cleared() -> void:
	var flow := FloorFlow.new()
	flow.setup(_typed_chain(["combat", "miniboss", "boss"]))
	assert_bool(flow.enter_room(1)).is_true()
	assert_int(flow.current_room).is_equal(1)
	assert_bool(flow.is_locked()).is_true()          # 战斗流开始：房间被锁
	assert_bool(flow.cleared.has(1)).is_false()
	# 锁定期全部门封死（含来路）
	assert_bool(flow.doors_open_between(0, 1)).is_false()
	assert_bool(flow.doors_open_between(1, 2)).is_false()
	assert_array(flow.next_rooms()).is_empty()
	flow.notify_room_cleared(1)
	assert_bool(flow.is_locked()).is_false()
	assert_array(flow.cleared).contains(1)
	assert_bool(flow.doors_open_between(0, 1)).is_true()
	assert_bool(flow.doors_open_between(1, 2)).is_true()


func test_door_matrix_three_room_chain() -> void:
	# 门矩阵：仅相邻 + 至少一侧已清 + 锁定期全封；boss 门另受 miniboss 规则
	var flow := FloorFlow.new()
	flow.setup(_typed_chain(["combat", "miniboss", "boss"]))
	# 非相邻恒闭
	assert_bool(flow.doors_open_between(0, 2)).is_false()
	assert_bool(flow.doors_open_between(0, 3)).is_false()
	assert_bool(flow.doors_open_between(1, 3)).is_false()
	# 未达房间（两侧均未清）恒闭
	assert_bool(flow.doors_open_between(1, 2)).is_false()
	assert_bool(flow.doors_open_between(2, 3)).is_false()
	# 已清侧 → 未清邻房开（可进）；进入后锁闭；清后重开
	assert_bool(flow.doors_open_between(0, 1)).is_true()
	assert_bool(flow.enter_room(1)).is_true()
	assert_bool(flow.doors_open_between(0, 1)).is_false()
	flow.notify_room_cleared(1)
	assert_bool(flow.doors_open_between(0, 1)).is_true()
	# 无向性：同一走廊两侧查询同值
	assert_bool(flow.doors_open_between(1, 0)).is_true()
	assert_bool(flow.doors_open_between(2, 1)).is_true()


func test_boss_door_gated_on_miniboss_clear() -> void:
	var flow := FloorFlow.new()
	flow.setup(_branch_build())
	# 清 combat(1)：miniboss 未清 → 邻接 boss 门仍锁
	assert_bool(flow.enter_room(1)).is_true()
	flow.notify_room_cleared(1)
	assert_bool(flow.boss_door_unlocked()).is_false()
	assert_bool(flow.doors_open_between(1, 3)).is_false()
	# 未清的 miniboss(2) 可进（普通邻接门语义），清后解锁 boss 门
	assert_bool(flow.enter_room(2)).is_true()
	flow.notify_room_cleared(2)
	assert_bool(flow.boss_door_unlocked()).is_true()
	assert_bool(flow.enter_room(1)).is_true()        # 折返 boss 的邻接侧
	assert_bool(flow.doors_open_between(1, 3)).is_true()
	assert_bool(flow.enter_room(3)).is_true()        # boss 可进（进房即锁，战斗流）
	assert_bool(flow.is_locked()).is_true()


func test_boss_door_needs_adjacent_cleared_side() -> void:
	# miniboss 已清但 boss 的邻接侧(1)未清 → 仍闭（adjacent-cleared-path 规则）
	var flow := FloorFlow.new()
	flow.setup(_branch_build())
	flow.notify_room_cleared(2)                      # 直接通知清 miniboss（跳走 1）
	assert_bool(flow.boss_door_unlocked()).is_true()
	assert_bool(flow.doors_open_between(1, 3)).is_false()
	assert_bool(flow.enter_room(1)).is_true()
	flow.notify_room_cleared(1)
	assert_bool(flow.doors_open_between(1, 3)).is_true()


func test_instant_clear_rooms_emit_room_event() -> void:
	var flow := FloorFlow.new()
	var seen: Array = []
	flow.room_event.connect(func(t: String, id: int) -> void: seen.append("%s:%d" % [t, id]))
	flow.setup(_typed_chain(["treasure", "shop", "event"]))
	assert_bool(flow.enter_room(1)).is_true()
	assert_bool(flow.is_locked()).is_false()          # instant 房不锁
	assert_array(flow.cleared).contains(1)            # 进门即清
	assert_array(seen).contains("treasure:1")
	assert_bool(flow.enter_room(2)).is_true()
	assert_array(flow.cleared).contains(2)
	assert_array(seen).contains("shop:2")
	assert_bool(flow.enter_room(3)).is_true()
	assert_array(flow.cleared).contains(3)
	assert_array(seen).contains("event:3")
	assert_int(seen.size()).is_equal(3)


func test_next_rooms_only_adjacent_and_open() -> void:
	var flow := FloorFlow.new()
	flow.setup(_branch_build())
	assert_array(flow.next_rooms()).contains(1)
	assert_int(flow.next_rooms().size()).is_equal(1)
	assert_bool(flow.enter_room(1)).is_true()
	flow.notify_room_cleared(1)
	# 1 清后：next = [0(回程), 2]（boss 因 miniboss 未清不在列）
	var nxt := flow.next_rooms()
	assert_array(nxt).contains(0)
	assert_array(nxt).contains(2)
	assert_bool(nxt.has(3)).is_false()
	assert_int(nxt.size()).is_equal(2)
	flow.notify_room_cleared(2)                      # miniboss 清（合法的流程外通知）
	assert_array(flow.next_rooms()).contains(3)
	assert_int(flow.next_rooms().size()).is_equal(3)


func test_enter_room_rejects_non_adjacent_and_stays() -> void:
	var flow := FloorFlow.new()
	flow.setup(_typed_chain(["combat", "miniboss", "boss"]))
	assert_bool(flow.enter_room(2)).is_false()        # 不相邻
	assert_bool(flow.enter_room(3)).is_false()
	assert_int(flow.current_room).is_equal(0)


func test_notify_room_cleared_dedupes() -> void:
	var flow := FloorFlow.new()
	flow.setup(_typed_chain(["combat"]))
	flow.enter_room(1)
	flow.notify_room_cleared(1)
	flow.notify_room_cleared(1)
	flow.notify_room_cleared(1)
	assert_int(flow.cleared.size()).is_equal(2)       # start + 1，无重复


func test_room_type_accessor() -> void:
	var flow := FloorFlow.new()
	flow.setup(_branch_build())
	assert_str(flow.room_type(0)).is_equal("start")
	assert_str(flow.room_type(1)).is_equal("combat")
	assert_str(flow.room_type(2)).is_equal("miniboss")
	assert_str(flow.room_type(3)).is_equal("boss")


func test_real_build_deterministic_consumption() -> void:
	# 固定种子真实构建体：全图 DFS 可走序清房（miniboss 留最后），推进全程 boss 门恒锁；
	# 清 miniboss 后解锁且 miniboss→boss 门开；同种子两次 setup 邻接表同态。
	var build := DungeonBuilder.build(SEED, 1)
	var miniboss := _find_by_type(build, "miniboss")
	var boss := int(build["boss_room_id"])
	assert_int(miniboss).is_greater_equal(0)
	var flow := FloorFlow.new()
	flow.setup(build)
	for id in _walk_order(build, miniboss, boss):
		assert_bool(flow.enter_room(id)).is_true()
		if String((build["rooms"][id] as Dictionary)["node"]["type"]) in A1_TYPES_COMBAT:
			flow.notify_room_cleared(id)
		if id != miniboss:
			assert_bool(flow.boss_door_unlocked()).is_false()
	assert_bool(flow.enter_room(miniboss)).is_true()
	flow.notify_room_cleared(miniboss)
	assert_bool(flow.boss_door_unlocked()).is_true()
	assert_bool(flow.adjacent(miniboss).has(boss)).is_true()   # 图规格：主路径倒数第二
	assert_bool(flow.doors_open_between(miniboss, boss)).is_true()
	# 确定性：同种子重放 → 邻接表逐字段同态
	var flow2 := FloorFlow.new()
	flow2.setup(DungeonBuilder.build(SEED, 1))
	assert_str(var_to_str(flow2.adjacent(0))).is_equal(var_to_str(flow.adjacent(0)))


## 可走遍历序（每步相邻）：DFS 带回溯（跳过 miniboss/boss），末段沿主路径 parent 链
## 走到 miniboss。树上传送限制由 enter_room 的邻接校验兜底。
func _walk_order(build: Dictionary, miniboss: int, boss: int) -> Array[int]:
	var start_id := int(build["start_room_id"])
	var parent := {start_id: -1}
	var queue: Array[int] = [start_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n in _neighbors(build, cur):
			if not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var moves: Array[int] = []
	_dfs_walk(build, start_id, miniboss, boss, {start_id: true}, moves)
	# 回到 start 后沿 parent 链走到 miniboss
	var chain: Array[int] = []
	var cur := miniboss
	while cur != start_id:
		chain.append(cur)
		cur = int(parent[cur])
	chain.reverse()
	moves.append_array(chain)
	return moves


func _dfs_walk(build: Dictionary, cur: int, miniboss: int, boss: int,
		visited: Dictionary, moves: Array[int]) -> void:
	for n in _neighbors(build, cur):
		if visited.has(n) or n == miniboss or n == boss:
			continue
		visited[n] = true
		moves.append(n)
		_dfs_walk(build, n, miniboss, boss, visited, moves)
		moves.append(cur)                     # 回溯


func _neighbors(build: Dictionary, id: int) -> Array[int]:
	var out: Array[int] = []
	for c in build["corridors"]:
		var a := int((c as Dictionary)["a"])
		var b := int((c as Dictionary)["b"])
		if a == id:
			out.append(b)
		if b == id:
			out.append(a)
	return out


# ---------------------------------------------------------------- FloorScene 场景编排

var _fs: FloorScene = null


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)      # setup 收养无父玩家（挂为 FloorScene 子节点）
	return _fs


func after_test() -> void:
	# EventBus 桥接在场景 free 后不得残留悬挂回调（FloorScene 于 _exit_tree 断连）
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


func test_scene_builds_rooms_and_places_player_at_start() -> void:
	var build := DungeonBuilder.build(SEED, 1)
	var fs := _make_scene(build)
	var start := int(build["start_room_id"])
	# 13 房实体 + 走廊闸门齐全
	assert_int(fs.room_count()).is_equal(13)
	assert_int(fs.gate_count()).is_equal(12)
	# 玩家落在 start 房内域中心
	var center: Vector2 = fs.room_center(start)
	assert_bool(fs.room_rect(start).has_point(fs.player_node().position)).is_true()
	assert_vector(fs.player_node().position).is_equal_approx(center, Vector2(0.5, 0.5))
	assert_int(fs.flow.current_room).is_equal(start)
	assert_bool(fs.flow.cleared.has(start)).is_true()
	# 世界定位：房间节点 origin == world_pos
	for id in build["rooms"]:
		var wp: Vector2 = (build["rooms"][id] as Dictionary)["world_pos"]
		assert_vector(fs.room_node(int(id)).position).is_equal(wp)


func test_scene_gates_mirror_flow() -> void:
	var build := DungeonBuilder.build(SEED, 1)
	var fs := _make_scene(build)
	var start := int(build["start_room_id"])
	var boss := int(build["boss_room_id"])
	var miniboss := _find_by_type(build, "miniboss")
	for id in build["rooms"]:
		var nid := int(id)
		if nid == start or not fs.flow.adjacent(start).has(nid):
			continue
		var expected := fs.flow.next_rooms().has(nid)
		assert_bool(fs.gate_is_open(start, nid)).is_equal(expected)
	# boss 门：miniboss 未清 → 闸关；清后开（miniboss 恒主路径倒数第二 → 必相邻）
	assert_bool(fs.gate_is_open(miniboss, boss)).is_false()
	fs.flow.notify_room_cleared(miniboss)
	fs.refresh_gates()
	assert_bool(fs.gate_is_open(miniboss, boss)).is_true()


func test_scene_combat_lock_two_waves_clear() -> void:
	var build := _typed_chain(["combat"])
	var fs := _make_scene(build)
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var cleared_ids: Array = []
	EventBus.room_cleared.connect(func(id: String) -> void: cleared_ids.append(id))
	assert_bool(fs.enter_room(1)).is_true()
	# 波1 已刷（3 只），门全封
	assert_int(_alive_enemies(room)).is_equal(3)
	assert_bool(fs.flow.is_locked()).is_true()
	assert_bool(fs.gate_is_open(0, 1)).is_false()
	# 清波1 → 波2（3 只）补刷
	_kill_all(room)
	for i in 4:
		await get_tree().physics_frame
	assert_int(_alive_enemies(room)).is_equal(3)
	# 清波2 → 房清、门开、奖励爆发、EventBus.room_cleared(模板 id)
	_kill_all(room)
	for i in 4:
		await get_tree().physics_frame
	assert_bool(fs.flow.is_locked()).is_false()
	assert_bool(fs.flow.cleared.has(1)).is_true()
	assert_bool(fs.gate_is_open(0, 1)).is_true()
	assert_int(_pickups(room)).is_greater(0)
	assert_array(cleared_ids).contains("combat_a1_01")
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("floor_enter")).is_true()
	assert_bool(text.contains("floor_clear")).is_true()


func test_scene_player_retreat_and_reentry_no_relock() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	assert_bool(fs.enter_room(1)).is_true()
	fs.flow.notify_room_cleared(1)
	assert_bool(fs.enter_room(0)).is_true()          # 回 start
	assert_bool(fs.enter_room(1)).is_true()          # 重进已清战斗房：不重锁
	assert_bool(fs.flow.is_locked()).is_false()


func test_scene_instant_rooms_place_guest_stubs() -> void:
	var fs := _make_scene(_typed_chain(["treasure", "shop", "event"]))
	var events: Array = []
	fs.room_event.connect(func(t: String, id: int) -> void: events.append("%s:%d" % [t, id]))
	# treasure：进门即清 + 宝箱可交互物在房间内
	assert_bool(fs.enter_room(1)).is_true()
	assert_array(events).contains("treasure:1")
	var chest := _interactable_in_room(fs, 1)
	assert_object(chest).is_not_null()
	assert_str(chest.action_label).contains("宝箱")
	# treasure 清后邻接门开（推进链不断）
	assert_bool(fs.flow.doors_open_between(1, 2)).is_true()
	# shop / event 桩（C 线接入位）
	assert_bool(fs.enter_room(2)).is_true()
	var shop := _interactable_in_room(fs, 2)
	assert_object(shop).is_not_null()
	assert_str(shop.action_label).contains("商店")
	assert_bool(fs.enter_room(3)).is_true()
	var ev := _interactable_in_room(fs, 3)
	assert_object(ev).is_not_null()
	assert_str(ev.action_label).contains("事件")


func test_scene_treasure_chest_drops_weapon() -> void:
	var fs := _make_scene(_typed_chain(["treasure"]))
	assert_bool(fs.enter_room(1)).is_true()
	var chest := _interactable_in_room(fs, 1)
	var player: Player = fs.player_node()
	var rig: WeaponRig = player.get_node("WeaponRig")
	assert_bool(rig.slots[1].is_empty()).is_true()   # 初始仅 laohuoji 占槽 0
	chest.interact(player)
	# 宝箱一次性：can_interact 翻 false；掉落武器台出现在房间（第二交互物）；loot 遥测留痕
	assert_bool(chest.can_interact(player)).is_false()
	assert_bool(rig.slots[1].is_empty()).is_false()
	assert_int(_interactable_count(fs, 1)).is_equal(2)
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("loot")).is_true()


func test_scene_guest_placeholders() -> void:
	# 占位嘉宾行（静态）：elite/miniboss = charger 3×hp；boss vine_colossus = 8×hp r16；
	# T12/T13 接缝：guest_spawner Callable 默认无效 → 走占位路径
	var build := DungeonBuilder.build(SEED, 1)
	var fs := _make_scene(build)
	var elite := _find_by_type(build, "elite")
	var miniboss := _find_by_type(build, "miniboss")
	var boss := _find_by_type(build, "boss")
	var elite_room: FloorScene.FloorRoom = fs.room_node(elite)
	assert_str(elite_room.type).is_equal("elite")
	assert_int((elite_room.wave_ids(0) as Array).size()).is_equal(3)
	var w2: Array = elite_room.wave_ids(1)
	assert_int(w2.size()).is_equal(4)
	assert_bool(w2.has("elite_charger")).is_true()
	var mb_room: FloorScene.FloorRoom = fs.room_node(miniboss)
	assert_bool((mb_room.wave_ids(0) as Array).size() >= 1).is_true()
	assert_bool((mb_room.wave_ids(1) as Array).has("miniboss_charger")).is_true()
	var boss_room: FloorScene.FloorRoom = fs.room_node(boss)
	assert_int((boss_room.wave_ids(0) as Array).size()).is_equal(1)
	assert_bool((boss_room.wave_ids(0) as Array).has("vine_colossus")).is_true()
	var elite_row := FloorScene.guest_row("elite_charger")
	var mb_row := FloorScene.guest_row("miniboss_charger")
	var colossus := FloorScene.guest_row("vine_colossus")
	assert_int(int(elite_row["hp"])).is_equal(CHARGER_HP * 3)
	assert_int(int(mb_row["hp"])).is_equal(CHARGER_HP * 3)
	assert_int(int(colossus["hp"])).is_equal(CHARGER_HP * 8)
	assert_float(float(colossus["radius"])).is_equal_approx(16.0, 0.001)
	assert_bool(fs.guest_spawner.is_valid()).is_false()


func test_scene_full_walk_elite_miniboss_boss() -> void:
	# 端到端链路：start→elite(锁→2 波→清)→miniboss(强化怪)→boss(colossus)→全清
	var fs := _make_scene(_typed_chain(["elite", "miniboss", "boss"]))
	var events: Array = []
	fs.room_event.connect(func(t: String, id: int) -> void: events.append("%s:%d" % [t, id]))
	# elite：进房即锁 + 波1 三只 + room_event 转发
	assert_bool(fs.enter_room(1)).is_true()
	assert_array(events).contains("elite:1")
	assert_bool(fs.flow.is_locked()).is_true()
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(3)
	_kill_all(fs.room_node(1))
	for i in 4:
		await get_tree().physics_frame
	# 波2：3 垃圾 + 1 精英嘉宾（占位 charger 3×hp）
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(4)
	var elite_guest := _find_enemy(fs.room_node(1), "elite_charger")
	assert_object(elite_guest).is_not_null()
	assert_int(elite_guest.hp).is_equal(CHARGER_HP * 3)
	_kill_all(fs.room_node(1))
	for i in 4:
		await get_tree().physics_frame
	assert_bool(fs.flow.cleared.has(1)).is_true()
	# miniboss：清后 boss 门解锁；波2 = 强化怪（占位 charger 3×hp）
	assert_bool(fs.enter_room(2)).is_true()
	assert_array(events).contains("miniboss:2")
	_kill_all(fs.room_node(2))
	for i in 4:
		await get_tree().physics_frame
	var mb_guest := _find_enemy(fs.room_node(2), "miniboss_charger")
	assert_object(mb_guest).is_not_null()
	_kill_all(fs.room_node(2))
	for i in 4:
		await get_tree().physics_frame
	assert_bool(fs.flow.cleared.has(2)).is_true()
	assert_bool(fs.flow.boss_door_unlocked()).is_true()
	# boss：单波 vine_colossus 占位（8×hp / r16），清后 boss 房清
	assert_bool(fs.enter_room(3)).is_true()
	var colossus := _find_enemy(fs.room_node(3), "vine_colossus")
	assert_object(colossus).is_not_null()
	assert_int(colossus.hp).is_equal(CHARGER_HP * 8)
	_kill_all(fs.room_node(3))
	for i in 4:
		await get_tree().physics_frame
	assert_bool(fs.flow.cleared.has(3)).is_true()
	assert_bool(fs.flow.is_locked()).is_false()


func test_scene_wave_composition_deterministic() -> void:
	var a := FloorScene.waves_for(3, "combat")
	var b := FloorScene.waves_for(3, "combat")
	assert_str(var_to_str(a)).is_equal(var_to_str(b))
	var c := FloorScene.waves_for(4, "combat")
	assert_bool(var_to_str(a) != var_to_str(c)).is_true()
	# 波次规模：combat 恒 2 波各 3 只；每只都在 A1 名录内
	var roster := ["kuli_bug", "cave_bat", "crossbowman", "vine_charger"]
	var waves: Array = a["waves"]
	assert_int(waves.size()).is_equal(2)
	for w in waves:
		assert_int((w as Array).size()).is_equal(3)
		for id in w:
			assert_array(roster).contains(id)
	# elite 波2 = 3 垃圾 + 1 精英；boss 单波 colossus
	assert_int((FloorScene.waves_for(1, "elite")["waves"][1] as Array).size()).is_equal(4)
	assert_array(FloorScene.waves_for(1, "boss")["waves"][0]).contains("vine_colossus")


# ---------------------------------------------------------------- helpers

func _find_by_type(build: Dictionary, type: String) -> int:
	for id in build["rooms"]:
		if String((build["rooms"][id] as Dictionary)["node"]["type"]) == type:
			return int(id)
	return -1


func _alive_enemies(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _kill_all(room: FloorScene.FloorRoom) -> void:
	# duplicate：die() → EventBus.enemy_killed → 同步处理器从 room.enemies 擦除，
	# 迭代副本防遍历中变更跳元素
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 9999, "is_crit": false, "element": 0, "from": e.global_position})


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


func _pickups(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for c in room.get_children():
		if c is Pickup:
			n += 1
	return n


func _interactable_in_room(fs: FloorScene, room_id: int) -> Interactable:
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	for c in room.get_children():
		if c is Interactable:
			return c
	return null


func _interactable_count(fs: FloorScene, room_id: int) -> int:
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	var n := 0
	for c in room.get_children():
		if c is Interactable:
			n += 1
	return n
