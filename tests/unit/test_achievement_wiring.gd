class_name TestAchievementWiring
extends GdUnitTestSuite
## M2-T33（裁定㉗）：17 条成就发射点补线的端到端接线契约测试。
## 权威规格 = 数据表附录 K（K.2 信号清单 / K.3 全表）+ 台账裁定⑧（boss_slain(boss_id,
## floor_idx) 命名）。每条链钉死「游戏事件点 → AchievementSystem 消费」全通路：
##   FloorScene boss 房清 → notify_boss_slain（first_lamp / nitpicker / nightmare_dawn）
##   RunRoot 过层门   → notify_floor_cleared + notify_floor_reached（slum_king / moneybags /
##                      bare_hands / delver + 开火窗口重置）
##   RunRoot 胜利链   → notify_victory（night_watcher / speedrunner / no_heal）
##   挑战房清         → CodexSystem.count_challenge + notify_challenge_cleared（challenger）
##   翻滚无敌帧躲弹幕 → notify_roll_dodge（走位大师窗口源）
##   红心拾取         → notify_heart_pickup（no_heal 会话源）
##   开火/挥击成功    → notify_weapon_used（bare_hands 本层窗口源）
##   TalentSystem.buy → notify_talent_purchased（gifted / overflowing）
##   SaveSystem.unlock_hero 成功点 → notify_hero_unlocked（full_roster，K.2 指定发射点）
##   RunRoot._begin   → AchievementSystem.reset_session（单局口径清零，K.1/K.4）
##
## 密闭口径（裁定㉔ df9691a 同源）：被测消费方 = 全局 AchievementSystem autoload（与生产
## 同一实例），其 save_system 换入临时路径档；全局 SaveSystem.save_path 同样换临时路径
## （吸收 CodexSystem persist / 首杀标记等写盘）；GameDB.weapons 换副本（吸收 kill_x 回池）；
## CodexSystem.counters 深快照还原。全部 after_test 还原——零真实档/全局池残留。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const PLAYER_SCENE := "res://core/player/player.tscn"
const SAVE_SCRIPT := "res://autoload/save_system.gd"
const DRIVER_SCRIPT := "res://core/rooms/player_driver.gd"
const THROW_ID := "shoulei"      # weapons.json category=throw（nitpicker 判定锚）

var _root: Node2D = null
var _fs: FloorScene = null
var _player: Player = null
var _save_paths: Array[String] = []
var _iso_save: Node = null
var _save_path0 := ""
var _counters0: Dictionary = {}
var _weapons0: Dictionary = {}


func before_test() -> void:
	RunState.start_run("vanguard")
	# 全局密封四件套：成就档 / 存档写盘 / 掉落池 / 图鉴计数器
	_iso_save = auto_free(load(SAVE_SCRIPT).new())
	_iso_save.save_path = _tmp_path("iso")
	_iso_save.load_save()
	AchievementSystem.save_system = _iso_save
	_save_path0 = SaveSystem.save_path
	SaveSystem.save_path = _tmp_path("global")
	SaveSystem.load_save()
	_weapons0 = GameDB.weapons
	GameDB.weapons = GameDB.weapons.duplicate(true)
	_counters0 = CodexSystem.counters.duplicate(true)


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
	_fs = null
	if _player != null and is_instance_valid(_player):
		_player.free()
	_player = null
	GameDB.weapons = _weapons0
	CodexSystem.counters = _counters0
	AchievementSystem.save_system = get_node_or_null("/root/SaveSystem")
	AchievementSystem.reset_session()
	SaveSystem.save_path = _save_path0
	SaveSystem.load_save()
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()
	_iso_save = null


# ---------------------------------------------------------------- 夹具

func _tmp_path(tag: String) -> String:
	var path := "user://test_achv_wire_%s_%d.json" % [tag, absi(randi())]
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_save_paths.append(path)
	return path


func _make_scene(build: Dictionary, floor_idx: int, challenge_id := -1) -> FloorScene:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(_player)
	_fs = FloorScene.new()
	_fs.floor_idx = floor_idx
	if challenge_id >= 0:
		_fs.challenge_room_id = challenge_id
	add_child(_fs)
	_fs.setup(build, _player)
	return _fs


func _typed_chain(types: Array) -> Dictionary:
	var span := 416.0
	var rooms := {0: {
		"node": {"id": 0, "type": "start", "grid": Vector2i(0, 0), "depth": 0, "next": [1]},
		"template_id": "start_a1", "world_pos": Vector2(Vector2i(0, 0)),
	}}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var tid := "combat_a1_01"
		if String(types[i]) == "boss":
			tid = "boss_a1"
		rooms[id] = {
			"node": {"id": id, "type": String(types[i]), "grid": Vector2i(i + 1, 0),
				"depth": 0, "next": [] if i == types.size() - 1 else [id + 1]},
			"template_id": tid, "world_pos": Vector2(Vector2i(i + 1, 0)) * span,
		}
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


func _make_root() -> Node2D:
	var root: Node2D = (load(RUN_ROOT_SCENE) as PackedScene).instantiate() as Node2D
	var ts := TalentSystem.new()
	ts.save_system = null       # 密封：不读真实档已购天赋（test_m1_integration 同款）
	ts.purchased = []
	root.talents = ts
	return root


func _find_enemy(room: FloorScene.FloorRoom, row_id: String) -> EnemyBase:
	for e in room.enemies:
		if String(e.row.get("id", "")) == row_id:
			return e
	return null


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		e.take_hit({"amount": 999999, "is_crit": false, "element": 0,
			"from": e.global_position})


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


## 直驱 FloorFlow 清到 boss 门口（test_m1_integration 同款 BFS）。
func _path_to_boss(fs: FloorScene, boss: int) -> Array[int]:
	var start := fs.flow.start_room()
	var parent := {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == boss:
			break
		for n in fs.flow.adjacent(cur):
			if not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var path: Array[int] = []
	var walk := boss
	while walk != start:
		path.push_front(walk)
		walk = int(parent[walk])
	return path


# ---------------------------------------------------------------- 1) boss_slain 链

func test_boss_room_kill_unlocks_first_lamp_with_gems() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 1)
	assert_bool(fs.enter_room(1)).is_true()
	var boss := _find_enemy(fs.room_node(1), "vine_colossus")
	assert_object(boss).is_not_null()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	# 链断言：FloorScene boss 房清 → notify_boss_slain("vine_colossus", 1) →
	# 全局 AchievementSystem 判定 → 临时档入账 + 100 蓝晶（附录 G.1）。
	assert_bool(_iso_save.is_achievement_unlocked("first_lamp")).is_true()
	assert_int(_iso_save.gems()).is_equal(100)


func test_boss_slain_carries_killing_weapon_for_nitpicker() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 1)
	var rig: WeaponRig = _player.get_node("WeaponRig")
	rig._test_init()
	rig.equip(THROW_ID)             # 击杀武器 = 投掷（category throw）
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(_iso_save.is_achievement_unlocked("nitpicker")).is_true()


func test_floor3_boss_kill_unlocks_nightmare_dawn_not_first_lamp() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 3)
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(_find_enemy(fs.room_node(1), "magma_tyrant")).is_not_null()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(_iso_save.is_achievement_unlocked("nightmare_dawn")).is_true()
	assert_bool(_iso_save.is_achievement_unlocked("first_lamp")).is_false()


# ---------------------------------------------------------------- 2) 过层链

func test_door_progression_emits_floor_cleared_then_reached() -> void:
	_root = _make_root()
	add_child(_root)
	_root._begin()
	var fs: FloorScene = _root.floor_scene
	var boss := fs.flow.boss_room()
	for id in _path_to_boss(fs, boss):
		if id == boss:
			continue
		assert_bool(fs.flow.enter_room(id)).is_true()
		if fs.flow.room_type(id) != "start":
			fs.flow.notify_room_cleared(id)
	assert_bool(fs.enter_room(boss)).is_true()
	_kill_all(fs.room_node(boss))
	await _await_until(func() -> bool: return _root.inter_floor != null)
	# 门点（InterFloorFlow.enter_next_floor → next_floor_requested → 宿主接线）：
	# 生产发射函数直驱（UI 门路径已有 test_m1_integration 覆盖）。
	RunState.coins = 600                     # moneybags：通关 A1 携带 >500
	_root._on_next_floor_requested(2)
	# floor_cleared(1) 先于 floor_reached(2) 求值：财神/贫民窟之王在窗口重置前判定。
	assert_bool(_iso_save.is_achievement_unlocked("moneybags")).is_true()
	assert_bool(_iso_save.is_achievement_unlocked("slum_king")).is_true()
	# floor_reached(2)：开火窗口已重置（本测试从未开火 → 赤手空拳不误解锁）。
	assert_bool(_iso_save.is_achievement_unlocked("bare_hands")).is_false()
	# 抵达 A3：notify_floor_reached(3) → 深入者。
	_root._on_next_floor_requested(3)
	assert_bool(_iso_save.is_achievement_unlocked("delver")).is_true()


func test_run_begin_resets_achievement_session() -> void:
	# K.1/K.4 单局口径：RunRoot._begin 与 DeathRecorder.reset 同点清零会话计数
	# （T32 Minor ④ 移交项的落地）。
	AchievementSystem.session["resonances"] = 7
	_root = _make_root()
	add_child(_root)
	_root._begin()
	assert_int(int(AchievementSystem.session.get("resonances", -1))).is_equal(0)


# ---------------------------------------------------------------- 3) 胜利链

func test_victory_unlocks_night_watcher_speedrunner_no_heal() -> void:
	_root = _make_root()
	add_child(_root)
	RunState.floor_idx = 3
	_root._begin()
	var routed := [false]
	_root.victory_route_override = func() -> void: routed[0] = true
	var fs: FloorScene = _root.floor_scene
	# 真实 13 房图：先清出 boss 门路径（同 door 测试），boss 房真场景开战。
	var boss := fs.flow.boss_room()
	for id in _path_to_boss(fs, boss):
		if id == boss:
			continue
		assert_bool(fs.flow.enter_room(id)).is_true()
		if fs.flow.room_type(id) != "start":
			fs.flow.notify_room_cleared(id)
	assert_bool(fs.enter_room(boss)).is_true()
	_kill_all(fs.room_node(boss))
	await _await_until(func() -> bool: return routed[0] or _root.inter_floor != null)
	# 胜利链：inter_floor flow.victory_achieved → RunRoot._on_victory_achieved →
	# notify_victory → 守夜人 / 速通者（run_time_frames < 72000）/ 拒绝治疗（未拾红心）。
	RunState.run_time_frames = 100
	assert_bool(_iso_save.is_achievement_unlocked("night_watcher")).is_true()
	assert_bool(_iso_save.is_achievement_unlocked("speedrunner")).is_true()
	assert_bool(_iso_save.is_achievement_unlocked("no_heal")).is_true()
	assert_bool(routed[0]).is_true()


# ---------------------------------------------------------------- 4) 挑战房链

func test_challenge_room_clear_counts_and_notifies() -> void:
	# 计数器预置 4（CodexSystem 全局 counters 快照还原）：清 1 房 → challenge_rooms_total
	# = 5 → notify_challenge_cleared → 挑战者（counter 权威源 = CodexSystem 活计数）。
	CodexSystem.counters["challenge_rooms_total"] = 4
	var fs := _make_scene(_typed_chain(["combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	fs.choose_calamity("enemy_speed")          # 挑战房：灾厄 4 选 1 后波次启动
	var waves: Array = fs.room_node(1).waves_cfg.get("waves", [])
	assert_int(waves.size()).is_equal(3)                       # 挑战房 3 波契约
	for w in waves.size():
		_kill_all(fs.room_node(1))
		if w < waves.size() - 1:
			await _await_until(func() -> bool:
				return _alive(fs.room_node(1)) > 0)
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_int(int(CodexSystem.counters.get("challenge_rooms_total", 0))).is_equal(5)
	assert_bool(_iso_save.is_achievement_unlocked("challenger")).is_true()


func _alive(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if e.state != EnemyBase.State.DEAD:
			n += 1
	return n


# ---------------------------------------------------------------- 5) 窗口源链

func test_roll_dodge_counts_projectile_dodged_in_roll_window() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(_player)
	_player.start_roll(Vector2.RIGHT, 1000)
	var hp0 := _player.hp
	_player.take_hit_ctx({"amount": 3, "source_type": "projectile"}, 1001)
	assert_int(_player.hp).is_equal(hp0)                       # 无伤（翻滚无敌帧）
	assert_int(int(AchievementSystem.session.get("dodges", 0))).is_equal(1)
	# 非弹幕（接触）不计数（K.3「翻滚躲过弹幕」口径）；受击无敌帧（非翻滚窗）也不计数。
	_player.take_hit_ctx({"amount": 1, "source_type": "contact"}, 1002)
	assert_int(int(AchievementSystem.session.get("dodges", 0))).is_equal(1)


func test_heart_pickup_counts_session_hearts() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(_player)
	var heart := Pickup.new()
	heart.kind = "heart"
	add_child(heart)
	heart._on_body_entered(_player)
	assert_int(int(AchievementSystem.session.get("heart_pickups", 0))).is_equal(1)


func test_weapon_use_windows_via_driver_success_points() -> void:
	_player = Player.new()
	_player._test_init()
	add_child(_player)
	var driver := Node.new()
	driver.set_script(load(DRIVER_SCRIPT))
	_player.add_child(driver)
	driver._log_fire({"id": "tiejian"}, 50)      # category=melee
	assert_int(int(AchievementSystem.session.get("melee_swings", 0))).is_equal(1)
	assert_int(int(AchievementSystem.session.get("remote_fire", 0))).is_equal(0)
	driver._log_fire({"id": "laohuoji"}, 51)     # category=pistol
	assert_int(int(AchievementSystem.session.get("remote_fire", 0))).is_equal(1)
	# 赤手空拳：本层有远程开火 → floor_cleared 判定不通过（K.3 口径）。
	AchievementSystem.notify_floor_cleared(1)
	assert_bool(_iso_save.is_achievement_unlocked("bare_hands")).is_false()
	# 新层窗口重置（floor_reached 吸收）后仅近战 → 下一层清房判定通过。
	AchievementSystem.notify_floor_reached(2)
	driver._log_fire({"id": "tiejian"}, 52)
	AchievementSystem.notify_floor_cleared(2)
	assert_bool(_iso_save.is_achievement_unlocked("bare_hands")).is_true()


# ---------------------------------------------------------------- 6) 累计口径链

func test_talent_purchase_notifies_gifted_and_overflowing() -> void:
	_iso_save.add_gems(99999)
	var ts := TalentSystem.new(_iso_save)
	var bought := 0
	while true:
		var avail := ts.available()          # 前置满足集（逐轮重算，深度链可购尽）
		if avail.is_empty():
			break
		if not ts.buy(avail[0]):
			break                            # 防御：蓝晶充足不应失败
		bought += 1
		if bought == 12:
			assert_bool(_iso_save.is_achievement_unlocked("gifted")).is_true()
			assert_bool(_iso_save.is_achievement_unlocked("overflowing")).is_false()
	assert_int(bought).is_equal(GameDB.talents.size())
	assert_bool(_iso_save.is_achievement_unlocked("overflowing")).is_true()


func test_hero_unlock_success_point_notifies_full_roster() -> void:
	# K.2：hero_unlocked 发射点 = SaveSystem.unlock_hero 成功点。
	var ids: Array = GameDB.heroes.keys()
	assert_int(ids.size()).is_equal(6)
	var unlocked := 0
	for id in ids:
		if _iso_save.unlock_hero(String(id)):
			unlocked += 1
	assert_int(unlocked).is_equal(5)               # vanguard 默认已解锁
	assert_bool(_iso_save.is_achievement_unlocked("full_roster")).is_true()


func test_forge_counter_source_reads_codex_live_counters() -> void:
	# 熔铸匠数据源修复：counter:crafts_total 权威 = CodexSystem 活计数器
	# （存档 v2 落地形态 unlock_tasks 的内存权威；T32 期读 save.data["counters"]
	# 恒 0 不可达——裁定㉗「两半都修」的数据半边）。
	CodexSystem.counters["crafts_total"] = 0   # 基线归零（boot 恢复值不确定；快照还原兜底）
	for i in 10:
		CodexSystem.count_craft()
	assert_int(AchievementSystem._state_value("counter:crafts_total")).is_equal(10)
	# 轮询点次序不敏感（K.1 结算点轮询）：craft_x 达标经 weapon_unlocked 搭车 recheck
	# 或 ui/forge 成交点 notify_item_forged 显式轮询，两条路都必须让熔铸匠入档。
	AchievementSystem.notify_item_forged()
	assert_bool(_iso_save.is_achievement_unlocked("forge_smith")).is_true()
