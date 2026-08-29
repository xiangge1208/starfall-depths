extends Node
## m1-t27 主循环无头冒烟（机检部分；视觉手感以 m1_evidence 截图驱动为辅）：
## run_root 装配（选角承接→HeroApplier→首层）→ 全层真实走图（战斗房两波清房、
## 精英/垒主/巨像真嘉宾、商店/宝箱/事件设施）→ boss 死亡开层间（三选一+喷泉+门）→
## 推层第 2 层 → M1 完结浮层。逐项 print，失败置 exit 1。
## 运行：godot --headless --path . res://tests/scenes/m1_loop_smoke.tscn

var run_root: Node2D
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1)
	)
	RunState.start_run("vanguard")
	run_root = (load("res://core/rooms/run_root.tscn") as PackedScene).instantiate()
	add_child(run_root)
	run_root._begin()
	_run()


func _run() -> void:
	await _frames(5)
	var fs: FloorScene = run_root.floor_scene
	var player: Player = run_root.player

	print("SMOKE 0: run root assembly")
	_check(fs != null and fs.room_count() == 13, "floor 1 built with 13 rooms")
	_check(player != null and player.hp_max == 8, "vanguard assembled (hp_max 8)")
	_check(String(player.weapon_rig.current().get("id", "")) == "laohuoji",
		"start weapon laohuoji equipped")
	_check(fs.room_rect(fs.flow.start_room()).has_point(player.position), "player at start room")

	# ---- 全层走图：start → 全部战斗房 → miniboss → boss（真实场景 enter_room + 波次清房）
	print("SMOKE 1: full floor walk (combat x%d, elite, miniboss)" % _count_type(fs, "combat"))
	var boss := fs.flow.boss_room()
	var miniboss := fs.flow.miniboss_room()
	var order := _walk_order(fs, miniboss, boss)
	for id in order:
		if id == boss:
			continue
		_check(fs.enter_room(id), "enter room %d (%s)" % [id, fs.flow.room_type(id)])
		if _is_combat_type(fs.flow.room_type(id)) and not fs.flow.cleared.has(id):
			await _clear_room_waves(fs, id)
	_check(fs.flow.boss_door_unlocked(), "boss door unlocked after miniboss")

	# ---- 设施抽查（首进即设）：商店货单 / 事件面板 / 宝箱
	print("SMOKE 2: facilities")
	var shop_room := _find_room(fs, func(t: String) -> bool: return t == "shop")
	_check(shop_room >= 0 and _shop_in(fs.room_node(shop_room)) != null, "shop facility placed")
	var event_room := _find_room(fs, func(t: String) -> bool: return t == "event")
	_check(event_room >= 0 and _event_in(fs.room_node(event_room)) != null, "event panel opened")

	# ---- 巨像（真 3 阶段 Boss）→ 层间 → 门 → M1 完结浮层
	print("SMOKE 3: boss colossus -> inter floor")
	_check(fs.enter_room(boss), "enter boss room")
	var colossus := _find_enemy(fs.room_node(boss), "vine_colossus")
	_check(colossus != null and colossus.hp == 800, "real vine_colossus spawned (hp 800)")
	_check(colossus != null and colossus.get_script() != null \
		and (colossus.get_script() as Script).resource_path.ends_with("vine_colossus.gd"),
		"boss_script mounted (BossBase subclass)")
	await _clear_room_waves(fs, boss)
	await _until(func() -> bool: return run_root.inter_floor != null,
		"inter floor opened on boss defeat")
	var inter: Node2D = run_root.inter_floor
	if inter != null:
		# 选增益走场景回调（等价玩家按 1）；phase BUFF(0)→FOUNTAIN(1) 即落地
		inter._on_buff_chosen(inter.flow.offered[0])
		await _until(func() -> bool: return inter.flow.phase >= InterFloorFlow.Phase.FOUNTAIN,
			"buff chosen via inter floor")
		inter.flow.use_fountain(player)
		await _until(func() -> bool: return inter.flow.phase == InterFloorFlow.Phase.DOOR,
			"fountain -> door phase")
		var gems0 := RunState.gems
		inter._on_door_interact(player)
		_check(RunState.floor_idx == 2, "RunState advanced to floor 2")
		_check(RunState.gems == gems0 + 60, "floor clear gems +60 (GDD 14.1)")
		await _until(func() -> bool: return run_root.m1_overlay_visible(),
			"M1 end overlay shown (floor 2 data lands in M2)")
		_check(String(run_root.overlay_text()).contains("M1 完结"), "overlay text present")

	Telemetry.flush()
	print("SMOKE DONE: %s (%d checks failed)" % ["OK" if failures.is_empty() else "FAILED",
		failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# ================================================================ helpers

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _until(check: Callable, label: String, max_frames: int = 300) -> void:
	for _i in max_frames:
		if check.call():
			_check(true, label)
			return
		await get_tree().process_frame
	_check(false, label + " (timeout)")


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _is_combat_type(t: String) -> bool:
	return t in ["combat", "elite", "miniboss", "boss"]


## 真实清房：逐波「等本波落地 → kill_all」（击杀 hitstop 会暂停树推迟补刷，
## 故全程按条件等待，不按帧数）；波推进由 RoomFlow 同拍结算，floor 补刷跨拍落地。
func _clear_room_waves(fs: FloorScene, id: int) -> void:
	var room: FloorScene.FloorRoom = fs.room_node(id)
	var guard := 0
	while not room.room_flow.cleared and guard < 20:
		guard += 1
		await _until(func() -> bool: return room.room_flow.cleared \
			or _alive_count(room) > 0, "room %d wave spawned" % id, 600)
		if room.room_flow.cleared:
			break
		_kill_all(room)
	await _until(func() -> bool: return fs.flow.cleared.has(id), "room %d cleared" % id)


func _alive_count(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 99999, "is_crit": false, "element": 0, "from": e.global_position})


## 可走遍历序：DFS 带回溯（相邻步进，回走已清房幂等）；末段沿 BFS parent 链走到
## miniboss（图规格：主路径倒数第二），boss 殿后（boss 门规则：miniboss 已清）。
func _walk_order(fs: FloorScene, miniboss: int, boss: int) -> Array[int]:
	var start := fs.flow.start_room()
	var moves: Array[int] = []
	_dfs(fs, start, {start: true}, miniboss, boss, moves)
	if miniboss >= 0:
		var chain := _path_to(fs, start, miniboss)
		chain.pop_front()                     # start 已在（DFS 起点）
		moves.append_array(chain)
		moves.append(miniboss)
	moves.append(boss)
	return moves


## BFS 最短路 parent 链 start→target（含两端）。
func _path_to(fs: FloorScene, start: int, target: int) -> Array[int]:
	var parent := {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == target:
			break
		for n in fs.flow.adjacent(cur):
			if not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var path: Array[int] = []
	var cur2 := target
	while cur2 != start:
		path.push_front(cur2)
		cur2 = int(parent[cur2])
	path.push_front(start)
	return path


func _dfs(fs: FloorScene, cur: int, seen: Dictionary, miniboss: int, boss: int,
		moves: Array[int]) -> void:
	for n in fs.flow.adjacent(cur):
		if seen.has(n) or n == miniboss or n == boss:
			continue
		seen[n] = true
		moves.append(n)
		_dfs(fs, n, seen, miniboss, boss, moves)
		moves.append(cur)                     # 回溯（回走已清房，enter_room 幂等）


func _count_type(fs: FloorScene, t: String) -> int:
	var n := 0
	for id in fs.flow._types:
		if String(fs.flow._types[id]) == t:
			n += 1
	return n


func _find_room(fs: FloorScene, pred: Callable) -> int:
	for id in fs.flow._types:
		if pred.call(String(fs.flow._types[id])):
			return int(id)
	return -1


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


func _shop_in(room: FloorScene.FloorRoom) -> Shop:
	for c in room.get_children():
		if c is Shop:
			return c
	return null


func _event_in(room: FloorScene.FloorRoom) -> EventRoom:
	for c in room.get_children():
		if c is EventRoom:
			return c
	return null
