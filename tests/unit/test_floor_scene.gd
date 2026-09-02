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


func test_room_event_fires_once_per_room_on_backtrack() -> void:
	# 回归钉住（fix round 1）：room_event 只在「进清/首进」转换发一次——回溯重进
	# 已清客房（instant 与战斗系嘉宾 alike）不得重发（C 线 guest UI / T12 缝防重复触发）。
	var flow := FloorFlow.new()
	var seen: Array = []
	flow.room_event.connect(func(t: String, id: int) -> void: seen.append("%s:%d" % [t, id]))
	flow.setup(_typed_chain(["treasure", "elite"]))
	assert_bool(flow.enter_room(1)).is_true()        # treasure：进清转换 → 恰 1 次
	assert_bool(flow.enter_room(2)).is_true()        # elite：首进（战斗锁）→ 恰 1 次
	assert_bool(flow.is_locked()).is_true()
	flow.notify_room_cleared(2)
	assert_bool(flow.enter_room(1)).is_true()        # 回溯重进 treasure：不再发
	assert_bool(flow.enter_room(2)).is_true()        # 重进已清 elite：不再发
	assert_bool(flow.enter_room(1)).is_true()
	assert_array(seen).is_equal(["treasure:1", "elite:2"])   # 恰好各 1 次、载荷正确


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


func test_scene_mounts_one_full_hud_without_task_debug_labels() -> void:
	var fs := _make_scene(_typed_chain(["combat"]))
	# 旧任务卡 Label 在首个 _process 前 text 为空；至少过一帧再扫描，防假绿。
	await get_tree().process_frame
	assert_int(_full_hud_count(fs)).is_equal(1)
	var hud := _find_full_hud(fs)
	assert_object(hud).is_not_null()
	if hud != null:
		assert_object(hud.player).is_same(fs.player_node())
	assert_bool(_contains_task_debug_label(fs)).is_false()


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
	# 清波1 → 波2（3 只）补刷（fix round 2：条件等待替代固定 4 帧窗，负载不敏感）
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	assert_int(_alive_enemies(room)).is_equal(3)
	# 清波2 → 房清、门开、奖励爆发、EventBus.room_cleared(模板 id)
	_kill_all(room)
	await _await_until(func() -> bool: return fs.flow.is_locked() == false)
	assert_bool(fs.flow.is_locked()).is_false()
	assert_bool(fs.flow.cleared.has(1)).is_true()
	assert_bool(fs.gate_is_open(0, 1)).is_true()
	assert_int(_pickups(room)).is_greater(0)
	assert_array(cleared_ids).contains("combat_a1_01")
	Telemetry.flush()   # m1-t18：遥测改缓冲落盘，读盘前先清缓冲（原逐行即写）
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("floor_enter")).is_true()
	assert_bool(text.contains("floor_clear")).is_true()


func test_scene_runstate_counts_actual_kills_and_non_start_clear_once() -> void:
	# 生产聚合口径：实际死亡就计 kills；counts_for_wave 只决定是否消费波次。
	# 因此召唤体（counts_for_wave=false）仍是一次真实击杀，但不得推进当前波。
	RunState.start_run("vanguard")
	var fs := _make_scene(_typed_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_int(RunState.kills).is_equal(0)
	assert_int(RunState.rooms_cleared).is_equal(0) # setup 时已清的 start 房不计
	assert_bool(fs.enter_room(1)).is_true()
	assert_int(_alive_enemies(room)).is_equal(3)
	var wave_before := room.room_flow.wave_index()
	var summon := fs._spawn_enemy(room, "kuli_bug", room.outer.get_center(), {}, false)
	assert_object(summon).is_not_null()
	assert_bool(summon.counts_for_wave).is_false()
	summon.take_hit({"amount": 9999, "is_crit": false, "element": 0,
		"from": summon.global_position})
	assert_int(RunState.kills).is_equal(1)
	assert_int(room.room_flow.wave_index()).is_equal(wave_before)
	assert_int(_alive_enemies(room)).is_equal(3)
	assert_bool(fs.flow.is_locked()).is_true()

	# 两个正式波次各 3 只；连同召唤体，本房共 7 次真实死亡。
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	_kill_all(room)
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_int(RunState.kills).is_equal(7)
	assert_int(RunState.rooms_cleared).is_equal(1)
	fs._emit_room_clear(room) # 同一房重复回调必须受 cleared_emitted 幂等门保护
	assert_int(RunState.rooms_cleared).is_equal(1)
	assert_bool(fs.enter_room(0)).is_true()
	assert_int(RunState.rooms_cleared).is_equal(1) # 回到起始房仍不得计入清房数


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
	# shop：m1-t27 真商店设施（T14 Shop 交互物，货单/钱包在 _build_shop 接线）
	assert_bool(fs.enter_room(2)).is_true()
	var shop := _interactable_in_room(fs, 2)
	assert_object(shop).is_not_null()
	assert_str(shop.action_label).contains("商店")
	assert_bool(shop is Shop).is_true()
	assert_bool((shop as Shop).stock.has("weapons")).is_true()
	# event：m1-t27 事件设施（EventRoom 进房即开面板）
	assert_bool(fs.enter_room(3)).is_true()
	var ev := _event_room_in(fs, 3)
	assert_object(ev).is_not_null()
	assert_bool(ev.ui_visible()).is_true()
	assert_array(EventRoom.EVENT_IDS).contains(ev.current_event())


func test_scene_treasure_chest_preserves_single_weapon_until_station_pickup() -> void:
	var fs := _make_scene(_typed_chain(["treasure"]))
	assert_bool(fs.enter_room(1)).is_true()
	var chest := _interactable_in_room(fs, 1)
	var player: Player = fs.player_node()
	var rig: WeaponRig = player.get_node("WeaponRig")
	var before := _weapon_slot_ids(rig)
	assert_str(before[0]).is_equal("laohuoji")
	assert_str(before[1]).is_empty()
	chest.interact(player)
	# 开箱只揭示掉落并生成武器台，绝不能越过 E 拾取直接改写玩家武器槽。
	assert_bool(chest.can_interact(player)).is_false()
	assert_array(_weapon_slot_ids(rig)).is_equal(before)
	assert_int(_interactable_count(fs, 1)).is_equal(2)
	var station := _node_in_room(fs, 1, "LootStation") as Interactable
	assert_object(station).is_not_null()
	var dropped_id := String(station.get_meta("weapon_id", ""))
	assert_bool(not GameDB.get_weapon(dropped_id).is_empty()).is_true()
	station.interact(player)
	assert_str(String(rig.slots[0].get("id", ""))).is_equal("laohuoji")
	assert_str(String(rig.slots[1].get("id", ""))).is_equal(dropped_id)
	assert_bool(station.can_interact(player)).is_false()
	var after_first_pickup := _weapon_slot_ids(rig)
	station.interact(player)                         # 一次性：重复 E 不得再次装备
	assert_array(_weapon_slot_ids(rig)).is_equal(after_first_pickup)
	Telemetry.flush()   # m1-t18：遥测改缓冲落盘，读盘前先清缓冲（原逐行即写）
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("loot")).is_true()


func test_scene_treasure_chest_preserves_full_loadout_before_explicit_swap() -> void:
	var fs := _make_scene(_typed_chain(["treasure"]))
	assert_bool(fs.enter_room(1)).is_true()
	var player: Player = fs.player_node()
	var rig: WeaponRig = player.get_node("WeaponRig")
	rig.equip("maodingqiang")
	var before := _weapon_slot_ids(rig)
	assert_str(before[0]).is_equal("laohuoji")
	assert_str(before[1]).is_equal("maodingqiang")
	var chest := _interactable_in_room(fs, 1)
	chest.interact(player)
	assert_array(_weapon_slot_ids(rig)).is_equal(before)
	var station := _node_in_room(fs, 1, "LootStation") as Interactable
	assert_object(station).is_not_null()
	var dropped_id := String(station.get_meta("weapon_id", ""))
	assert_bool(not GameDB.get_weapon(dropped_id).is_empty()).is_true()
	station.interact(player)
	# 两槽已满时显式拾取只替换当前槽；副槽保持，掉落台自己的 id 不受后续 roll 污染。
	assert_str(String(rig.slots[0].get("id", ""))).is_equal(dropped_id)
	assert_str(String(rig.slots[1].get("id", ""))).is_equal("maodingqiang")
	var after_first_pickup := _weapon_slot_ids(rig)
	station.interact(player)
	assert_array(_weapon_slot_ids(rig)).is_equal(after_first_pickup)


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
	# 端到端链路（m1-t27 真实嘉宾）：start→elite(锁→2 波→清)→miniboss(自爆王虫)→
	# boss(真藤蔓巨像 boss_script)→全清 + boss_defeated。
	# m2-t26：小 Boss 抽取池化后定向钉自爆王虫（armored ×3 + leech 断言口径）。
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	_fs.miniboss_override = "zibao_wangchong"
	add_child(_fs)
	_fs.setup(_typed_chain(["elite", "miniboss", "boss"]), player)
	var fs := _fs
	var events: Array = []
	fs.room_event.connect(func(t: String, id: int) -> void: events.append("%s:%d" % [t, id]))
	# elite：进房即锁 + 波1 三只 + room_event 转发
	assert_bool(fs.enter_room(1)).is_true()
	assert_array(events).contains("elite:1")
	assert_bool(fs.flow.is_locked()).is_true()
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(3)
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _alive_enemies(fs.room_node(1)) == 4)
	# 波2：3 垃圾 + 1 真实精英（双刀蜥人行：hp 180）——m2-audit §12.3 后 A1 层
	# 精英无词缀（词缀 A2 起 1 条 / A3 两条，见 test_scene_elite_affixes_progression）
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(4)
	var elite_guest := _find_enemy(fs.room_node(1), "shuangdao_lizardman")
	assert_object(elite_guest).is_not_null()
	assert_int(elite_guest.hp).is_equal(180)
	assert_bool(elite_guest.has_berserk).is_false()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(fs.flow.cleared.has(1)).is_true()
	# m1-t27 精英掉落（行内 drops "weapon,hearts2"）：武器掉落台 + 红心
	# （红心 4 = drops 2 + elite 房清奖励 2）
	assert_object(_node_in_room(fs, 1, "LootStation")).is_not_null()
	assert_int(_heart_pickups(fs.room_node(1))).is_equal(4)
	# miniboss：清后 boss 门解锁；波2 = 真实自爆王虫（armored 词缀 hp×3、leech）
	assert_bool(fs.enter_room(2)).is_true()
	assert_array(events).contains("miniboss:2")
	_kill_all(fs.room_node(2))
	await _await_until(func() -> bool: return _find_enemy(fs.room_node(2), "zibao_wangchong") != null)
	var mb_guest := _find_enemy(fs.room_node(2), "zibao_wangchong")
	assert_object(mb_guest).is_not_null()
	assert_int(mb_guest.hp).is_equal(180 * 3)
	assert_bool(mb_guest.leech).is_true()
	_kill_all(fs.room_node(2))
	await _await_until(func() -> bool: return fs.flow.cleared.has(2))
	assert_bool(fs.flow.cleared.has(2)).is_true()
	assert_bool(fs.flow.boss_door_unlocked()).is_true()
	# boss：单波真 vine_colossus（行 hp 800；boss_script → BossBase 子类换装），
	# 清后 boss 房清 + boss_defeated 发出（层间触发，宿主消费）
	assert_bool(fs.enter_room(3)).is_true()
	var colossus := _find_enemy(fs.room_node(3), "vine_colossus")
	assert_object(colossus).is_not_null()
	assert_int(colossus.hp).is_equal(800)
	var script: Script = colossus.get_script()
	assert_bool(script != null and script.resource_path.ends_with("vine_colossus.gd")).is_true()
	var boss_defeats: Array = []
	fs.boss_defeated.connect(func(rid: int) -> void: boss_defeats.append(rid))
	_kill_all(fs.room_node(3))
	await _await_until(func() -> bool: return fs.flow.cleared.has(3))
	assert_bool(fs.flow.cleared.has(3)).is_true()
	assert_bool(fs.flow.is_locked()).is_false()
	assert_array(boss_defeats).contains(3)


func test_scene_kill_gem_routing_guest_and_boss_script_rows() -> void:
	# m2-t31 击杀蓝晶路由：A1 嘉宾按 guest_kind 档位（boss=50+首杀300）；
	# 真实 Boss 行（boss_script、无 guest_kind——frost_widow 等 M2 Boss 同形）等价
	# 归 boss 档；杂兵两键皆空 = 0。首杀标记写 SaveSystem → 临时档重定向守卫
	# （同 test_death_recorder 手法，绝不触真实 user://save.json）。
	var saved_path := SaveSystem.save_path
	var tmp := "user://test_t31_killgems_%d.json" % absi(randi())
	SaveSystem.save_path = tmp
	SaveSystem.load_save()                    # 全新空档：首杀名录清零
	RunState.start_run("vanguard")
	var fs := _make_scene(_typed_chain(["boss"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(room)                           # 嘉宾藤蔓巨像（guest_kind=boss）
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_int(RunState.gems).is_equal(50 + 300)
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus"])
	# 真实 Boss 行 frost_widow：仅 boss_script 无 guest_kind → 等价 boss 档 + 各自首杀
	var widow := fs._spawn_enemy(room, "frost_widow", room.outer.get_center(), {}, false)
	assert_object(widow).is_not_null()
	widow.take_hit({"amount": 999999, "is_crit": false, "element": 0,
		"from": widow.global_position})
	assert_int(RunState.gems).is_equal(50 + 300 + 50 + 300)
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus", "frost_widow"])
	# 杂兵（两键皆空）：0 入池
	var bug := fs._spawn_enemy(room, "kuli_bug", room.outer.get_center(), {}, false)
	assert_object(bug).is_not_null()
	bug.take_hit({"amount": 9999, "is_crit": false, "element": 0, "from": bug.global_position})
	assert_int(RunState.gems).is_equal(700)
	SaveSystem.save_path = saved_path         # 还原真实档视图
	SaveSystem.load_save()
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(tmp + ".tmp")


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


func test_scene_summons_rewire_combat_on_room_switch() -> void:
	# m2-t26（T25 评审 Important-2 移入本卡）：召唤物跨房间残留收口——summons 组
	# 成员（挂楼层任意处，非玩家子节点）换房时 combat 重接当前房，不残留旧房弹池。
	# 房 2 显式指定为挑战房：进房接线先于灾厄面板挂起（面板不影响本断言）。
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	_fs.challenge_room_id = 2
	add_child(_fs)
	_fs.setup(_typed_chain(["combat", "combat"]), player)
	var summon := SummonBase.new()
	summon.add_to_group("summons")
	_fs.add_child(summon)
	assert_bool(_fs.enter_room(1)).is_true()
	assert_object(summon.combat).is_same(_fs.room_node(1).combat)
	var room: FloorScene.FloorRoom = _fs.room_node(1)
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	_kill_all(room)
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	assert_bool(_fs.enter_room(2)).is_true()
	assert_object(summon.combat).is_same(_fs.room_node(2).combat)
	summon.queue_free()


# ---------------------------------------------------------------- helpers

## 确定性等待（fix round 2）：条件成立即返回；至多 max_frames 帧后放弃（由后续
## 断言报红）。固定 4 帧窗在套件负载下会错过跨拍事件（波2 补刷/清房推进）——
## 本文件所有跨拍门控等待统一走此 helper；无纯同帧落地型固定等待残留。
func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame

func _find_by_type(build: Dictionary, type: String) -> int:
	for id in build["rooms"]:
		if String((build["rooms"][id] as Dictionary)["node"]["type"]) == type:
			return int(id)
	return -1


func _contains_task_debug_label(node: Node) -> bool:
	if node is Label and String((node as Label).text).begins_with("M1-T"):
		return true
	for child in node.get_children():
		if _contains_task_debug_label(child):
			return true
	return false


func _full_hud_count(node: Node) -> int:
	var count := 1 if node is HUD else 0
	for child in node.get_children():
		count += _full_hud_count(child)
	return count


func _find_full_hud(node: Node) -> HUD:
	if node is HUD:
		return node as HUD
	for child in node.get_children():
		var found := _find_full_hud(child)
		if found != null:
			return found
	return null


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


func _node_in_room(fs: FloorScene, room_id: int, node_name: String) -> Node:
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	return room.get_node_or_null(NodePath(node_name))


func _event_room_in(fs: FloorScene, room_id: int) -> EventRoom:
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	for c in room.get_children():
		if c is EventRoom:
			return c
	return null


func _heart_pickups(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == "heart":
			n += 1
	return n


func _interactable_count(fs: FloorScene, room_id: int) -> int:
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	var n := 0
	for c in room.get_children():
		if c is Interactable:
			n += 1
	return n


func _weapon_slot_ids(rig: WeaponRig) -> Array[String]:
	var ids: Array[String] = []
	for slot_row: Dictionary in rig.slots:
		ids.append(String(slot_row.get("id", "")))
	return ids


# ================================================================ m2-audit 补录

const A2_TRASH_IDS := ["crystal_bat", "ice_mage", "magnet_golem", "ghost_jelly",
	"frost_crab", "crystal_rat", "rock_crystal_turret", "crystal_summoner",
	"prism_ranger", "ice_spider", "echo_lurker", "crystal_dragon"]
const A3_TRASH_IDS := ["lava_hound", "ash_shooter", "firerain_priest", "magma_slime",
	"obsidian_guard", "sulfur_moth", "lava_turret", "ember_summoner",
	"scorch_stomper", "flame_lich", "magma_wyvern", "starmarrow_blob"]


func test_scene_waves_floor_rosters() -> void:
	# m2-audit：A2/A3 波次名录分层（附录 B.2 特有种 12 行；此前恒 A1）。
	# 规模契约不变（2 波各 3 只）；缺省 floor=1 = M1 契约（A1 小池）。
	for fl in [2, 3]:
		var roster := A2_TRASH_IDS if fl == 2 else A3_TRASH_IDS
		for rid in [1, 5, 9]:
			var cfg: Dictionary = FloorScene.waves_for(rid, "combat", fl)
			assert_int(cfg["waves"].size()).is_equal(2)
			for w in cfg["waves"]:
				assert_int((w as Array).size()).is_equal(3)
				for id in w:
					assert_array(roster).contains(id)
		# elite 波2 = 本层杂兵 3 + 精英标记（词缀递进见 elite_affixes_for_floor 测试）
		var elite_w2: Array = FloorScene.waves_for(2, "elite", fl)["waves"][1]
		assert_array(elite_w2).contains("elite_charger")
		for id in elite_w2:
			if id != "elite_charger":
				assert_array(roster).contains(id)
	for id: String in A2_TRASH_IDS + A3_TRASH_IDS:
		assert_dict(GameDB.get_enemy(id)).is_not_empty()   # id 转录无漂移
	# 挑战房随层（复用本层战斗配置）
	var ch: Dictionary = FloorScene.challenge_waves_for(3, 2)
	for w in ch["waves"]:
		for id in w:
			assert_array(A2_TRASH_IDS).contains(id)


func test_scene_floor_pool_enemies_constructible() -> void:
	# m2-audit：分层池全部行可构造（防「池内行缺失 → 波次空转 → 房间不可清」软锁；
	# FLOOR_TRASH 与 enemies.json 行漂移在此即红）。
	for fl in [1, 2, 3]:
		for id: String in FloorScene.FLOOR_TRASH[fl]:
			var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.get_enemy(id)))
			assert_object(e).is_not_null()


func test_scene_elite_affixes_progression() -> void:
	# m2-audit：§12.3 精英词缀楼层递进——A1 无 / A2 一条 / A3 两条不重复，值域合法；
	# 同层同盐确定性（层派生 SALT_ELITE，同层恒同组）。
	var valid: Array = EliteAffix.AFFIXES
	var r1: Array[String] = FloorScene.elite_affixes_for_floor(1,
		RngSvc.stream(1, RunState.SALT_ELITE))
	assert_int(r1.size()).is_equal(0)
	var r2: Array[String] = FloorScene.elite_affixes_for_floor(2,
		RngSvc.stream(2, RunState.SALT_ELITE))
	assert_int(r2.size()).is_equal(1)
	assert_array(valid).contains(r2[0])
	var r3: Array[String] = FloorScene.elite_affixes_for_floor(3,
		RngSvc.stream(3, RunState.SALT_ELITE))
	assert_int(r3.size()).is_equal(2)
	for a in r3:
		assert_array(valid).contains(a)
	assert_str(r3[0]).is_not_equal(r3[1])
	var r3b: Array[String] = FloorScene.elite_affixes_for_floor(3,
		RngSvc.stream(3, RunState.SALT_ELITE))
	assert_str(var_to_str(r3)).is_equal(var_to_str(r3b))


# ---------------------------------------------------------------- m3-fix2 中心落位防卡缝

static func _circle_rect_gap(at: Vector2, rect: Rect2) -> float:
	var closest := Vector2(
		clampf(at.x, rect.position.x, rect.end.x),
		clampf(at.y, rect.position.y, rect.end.y))
	return closest.distance_to(at)


func test_scene_push_back_never_places_player_inside_center_pillars() -> void:
	# B-2 停滞残差产品侧根因回归钉死：combat_a1_01（_typed_chain 战斗房默认模板）
	# 房心 2×2 柱阵恰好占住 outer 中心 → 旧实现 _push_back 把玩家放进柱缝
	# （探针实证 seeds 3221/3251/3258/3268：dir/vel 非零而 pp 全窗零位移）。
	# 修复后落位必须与全部实体保持玩家半径间距且在内域。
	var fs := _make_scene(_typed_chain(["combat", "combat"]))
	var combat_room := 1
	assert_bool(fs.enter_room(combat_room)).is_true()
	fs.push_player_back()
	var pp: Vector2 = fs.player_node().position
	var room_rect: Rect2 = fs.room_rect(combat_room)
	var interior := Rect2(room_rect.position + Vector2(16, 16),
		room_rect.size - Vector2(32, 32))
	assert_bool(interior.has_point(pp)).is_true()
	var radius := fs._player_body_radius()
	assert_float(radius).is_equal_approx(6.0, 0.001)
	for rect in fs._room_solid_rects(fs.room_node(combat_room)):
		assert_float(_circle_rect_gap(pp, rect)).is_greater_equal(radius - 0.001)


func test_scene_place_player_at_start_respects_solids() -> void:
	# start 房模板（start_a1）当前无房心实体 → 零漂移落在中心（原契约保持）；
	# 若未来模板引入房心实体，落位仍必须合法（同一 safe 路径）。
	var fs := _make_scene(_typed_chain(["combat"]))
	var start := int(fs.flow.start_room())
	var pp: Vector2 = fs.player_node().position
	var center := fs.room_center(start)
	assert_vector(pp).is_equal_approx(center, Vector2(0.5, 0.5))
	for rect in fs._room_solid_rects(fs.room_node(start)):
		assert_float(_circle_rect_gap(pp, rect)).is_greater_equal(
			fs._player_body_radius() - 0.001)


func test_scene_pickup_spawn_clamped_out_of_solids() -> void:
	# m3-fix2（B-2 seed 3271 产品侧半边）：掉落/奖励散布点可落进房心柱/箱实体 →
	# 拾取物成为不可达死物。_spawn_pickup 必须把落点钳到实体外（玩家圆 r=6 可及）。
	var fs := _make_scene(_typed_chain(["combat", "combat"]))
	var room := fs.room_node(1)
	var interior := Rect2(fs.room_rect(1).position + Vector2(16, 16),
		fs.room_rect(1).size - Vector2(32, 32))
	var solids := fs._room_solid_rects(room)
	# combat_a1_01 房心柱阵西柱中心（必然与实体相交的落点）
	var inside := Vector2(168, 104)
	var world_inside := room.position + inside
	fs._spawn_pickup(room, "coin", world_inside)
	var pickups: Array = []
	for c in room.get_children():
		if c is Pickup:
			pickups.append(c)
	assert_int(pickups.size()).is_equal(1)
	var p := pickups[0] as Pickup
	var at: Vector2 = (p as Node2D).global_position
	assert_bool(interior.has_point(at)).is_true()
	for rect in solids:
		assert_float(_circle_rect_gap(at, rect)).is_greater_equal(6.0 - 0.001)


func test_scene_pickup_spawn_free_point_unchanged() -> void:
	# 合法落点零漂移（防钳制无事生非）。
	var fs := _make_scene(_typed_chain(["combat"]))
	var room := fs.room_node(1)
	var free := room.position + Vector2(230, 60)
	fs._spawn_pickup(room, "coin", free)
	for c in room.get_children():
		if c is Pickup:
			assert_vector((c as Node2D).global_position).is_equal_approx(free,
				Vector2(0.001, 0.001))
			return
	fail("no pickup spawned")
