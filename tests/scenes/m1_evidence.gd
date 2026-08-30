extends Node
## m1-t27 主循环截图证据驱动（有窗运行；脚本化走完整主循环并在关键节点截屏）。
## 运行：godot --path . res://tests/scenes/m1_evidence.tscn
## 产物：docs/superpowers/reports/m1-evidence/m1-*.png + 控制台逐项 PASS/FAIL（失败 exit 1）。
##
## 披露：非人工把玩——由脚本以与玩家等价的入口驱动（enter_room / interact / 交互回调），
## 渲染走真实窗口（截图为真实画面）。手感/操作体验仍需真人复核（M2 前手动验证）。

const OUT_DIR := "res://docs/superpowers/reports/m1-evidence"

var run_root: Node2D
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("EVIDENCE TIMEOUT")
		get_tree().quit(1)
	)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RunState.start_run("vanguard")
	run_root = (load("res://core/rooms/run_root.tscn") as PackedScene).instantiate()
	add_child(run_root)
	run_root._begin()
	_run()


func _run() -> void:
	await _frames(20)
	var fs: FloorScene = run_root.floor_scene
	var player: Player = run_root.player
	await _shot("01-floor-start")
	_check(fs != null and fs.room_count() == 13, "floor 1 built with 13 rooms")

	print("EVIDENCE 1: full floor walk")
	var boss := fs.flow.boss_room()
	var miniboss := fs.flow.miniboss_room()
	var order := _walk_order(fs, miniboss, boss)
	var shot := 2
	var shot_kind := {"combat": false, "elite": false, "treasure": false, "shop": false,
		"event": false, "miniboss": false}
	for id in order:
		if id == boss:
			continue
		var t := fs.flow.room_type(id)
		# `_walk_order()` contains DFS backtracking.  A room can be revisited while a
		# previous combat room is still resolving (the current seed exposed this in
		# the rendered evidence run), so wait for every entered combat room to clear
		# before taking the next graph edge.  This mirrors the playable door lock
		# contract instead of recording transient, seed-dependent enter failures.
		if not _check_store(fs.enter_room(id), "enter room %d (%s)" % [id, t]):
			continue
		# Direct evidence driving must also move the real player into the entered
		# room.  Otherwise FloorScene's production position detector observes the
		# player still standing in the previous room during screenshot waits and
		# legitimately moves the flow back, making the next DFS edge non-adjacent.
		player.position = fs.room_rect(id).get_center()
		if t in ["combat", "elite", "miniboss"] and not fs.flow.cleared.has(id):
			await _clear_room_waves(fs, id)
		if shot_kind.has(t) and not shot_kind[t]:
			shot_kind[t] = true
			await _frames(30)
			if t == "shop":
				await _open_shop_ui(fs, id)
				await _shot("%02d-shop-ui" % shot)
				_close_shop_ui(fs, id)
			else:
				await _shot("%02d-room-%s" % [shot, t])
			if t == "event":
				var ev := _event_in(fs.room_node(id))     # 事件面板关闭（等价玩家拒绝，防残留遮挡后续画面）
				if ev != null:
					ev.refuse()
			shot += 1
	_check(fs.flow.boss_door_unlocked(), "boss door unlocked after miniboss")

	print("EVIDENCE 3: boss colossus -> inter floor -> A2 entry milestone")
	_check_store(fs.enter_room(boss), "enter boss room")
	player.position = fs.room_rect(boss).get_center()
	await _until(func() -> bool: return _find_enemy(fs.room_node(boss), "vine_colossus") != null,
		"real vine_colossus spawned", "real vine_colossus spawned", 120)
	var colossus := _find_enemy(fs.room_node(boss), "vine_colossus")
	await _shot("%02d-boss-colossus" % shot)
	shot += 1
	# 截图等待期间生产 PlayerDriver 仍可能真实开火，因此当前 HP 不是稳定的
	# 配置证据；最大生命才是数据表的 800HP 契约，同时确认实例仍存活且未越界。
	_check(colossus != null and colossus.hp_max == 800 and colossus.hp > 0 \
			and colossus.hp <= colossus.hp_max,
		"real vine_colossus (hp_max 800, alive)")
	await _clear_room_waves(fs, boss)
	await _until(func() -> bool: return run_root.inter_floor != null,
		"inter floor opened", "inter floor opened")
	await _frames(30)
	await _shot("%02d-inter-floor-buff" % shot)
	var inter: Node2D = run_root.inter_floor
	shot += 1
	if inter != null:
		# 通过 Godot 的公开输入入口按下数字键 1，让 BuffPick 自己走
		# _unhandled_input -> _choose -> hide -> buff_chosen。不能直接调用业务
		# 回调，否则截图会把仍可见的三选一卡片误当成“喷泉/门阶段”。
		var choose_event := InputEventKey.new()
		choose_event.keycode = KEY_1
		choose_event.physical_keycode = KEY_1
		choose_event.pressed = true
		Input.parse_input_event(choose_event)
		await _frames(2)
		_check(not inter._buff_pick.visible, "buff pick closes after selection")
		inter.flow.use_fountain(player)
		await _frames(20)
		await _shot("%02d-inter-floor-fountain-door" % shot)
		await _until(func() -> bool: return inter.flow.phase == InterFloorFlow.Phase.DOOR,
			"fountain -> door", "door phase")
		inter._on_door_interact(player)
		await _until(func() -> bool: return run_root.a2_entry_active(),
			"A2 entry", "A2 entry milestone shown")
		await _frames(20)
		await _shot("%02d-a2-entry-milestone" % (shot + 1))
		_check(RunState.floor_idx == 2, "RunState advanced to floor 2")
		_check(String(run_root.overlay_text()).contains("已进入第 2 层"),
			"floor 2 entry text is unambiguous")

	Telemetry.flush()
	print("EVIDENCE DONE: %s (%d failed)" % ["OK" if failures.is_empty() else "FAILED",
		failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


# ================================================================ capture / walk helpers

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/m1-%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	print("  SHOT %s (%s)" % [path, "ok" if err == Error.OK else "ERR %d" % err])


## 商店 UI 开层（等价玩家按 E）：交互 → 面板出现。
func _open_shop_ui(fs: FloorScene, id: int) -> void:
	var shop := _shop_in(fs.room_node(id))
	if shop != null:
		shop.interact(run_root.player)
		await _frames(5)


func _close_shop_ui(fs: FloorScene, id: int) -> void:
	var shop := _shop_in(fs.room_node(id))
	if shop != null:
		shop.close()


func _check(ok: bool, label: String) -> bool:
	if not ok:
		failures.append(label)
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	return ok


func _check_store(ok: bool, label: String) -> bool:
	return _check(ok, label)


func _until(check: Callable, label: String, fail_label: String = "", max_frames: int = 900) -> void:
	for _i in max_frames:
		if check.call():
			_check(true, label)
			return
		await get_tree().process_frame
	_check(false, (fail_label if fail_label != "" else label) + " (timeout)")


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _clear_room_waves(fs: FloorScene, id: int) -> void:
	var room: FloorScene.FloorRoom = fs.room_node(id)
	var guard := 0
	while not room.room_flow.cleared and guard < 20:
		guard += 1
		await _until(func() -> bool: return room.room_flow.cleared \
			or _alive_count(room) > 0, "room %d wave spawned" % id,
			"room %d wave spawned" % id, 600)
		if room.room_flow.cleared:
			break
		_kill_all(room)
	await _until(func() -> bool: return fs.flow.cleared.has(id), "room %d cleared" % id,
		"room %d cleared" % id)


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


func _walk_order(fs: FloorScene, miniboss: int, boss: int) -> Array[int]:
	var start := fs.flow.start_room()
	var moves: Array[int] = []
	_dfs(fs, start, {start: true}, miniboss, boss, moves)
	if miniboss >= 0:
		var chain := _path_to(fs, start, miniboss)
		chain.pop_front()
		moves.append_array(chain)
		moves.append(miniboss)
	moves.append(boss)
	return moves


func _dfs(fs: FloorScene, cur: int, seen: Dictionary, miniboss: int, boss: int,
		moves: Array[int]) -> void:
	for n in fs.flow.adjacent(cur):
		if seen.has(n) or n == miniboss or n == boss:
			continue
		seen[n] = true
		moves.append(n)
		_dfs(fs, n, seen, miniboss, boss, moves)
		moves.append(cur)


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
