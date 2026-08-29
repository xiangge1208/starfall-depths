class_name TestM1Integration
extends GdUnitTestSuite
## m1-t27 最终整合卡集成测试：四处死缝的端到端契约。
## 1) RunRoot：选角承接（RunState）→ HeroApplier 装配 → DungeonBuilder（run_seed）→
##    FloorScene 首层；重建机制（旧层释放/玩家跨层存活）。
## 2) 真实嘉宾：elite/miniboss/boss 房生成数据行真实嘉宾（词缀/boss_script 数据驱动），
##    波次推进经 wave_id 回译不断链；drops 死亡即落；开关关断回占位。
## 3) 设施：shop 真商店（RunState 钱包买卖/回收）、event 进房开面板、金币入账 RunState。
## 4) 层间：boss 死亡 → inter_floor 嵌入开层；门 → RunState.next_floor() → 无 A2 数据
##    → M1 完结浮层（第 2 层及胜利结算 M2 到来）；第 3 层胜利桩流程级验证。
##
## RunState 污染守卫：每用例前 start_run 复位（test_inter_floor 同款），after_test 再复位
## 并 free RunRoot/FloorScene（整棵含 inter_floor/浮层）。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const PLAYER_SCENE := "res://core/player/player.tscn"
const HERO_HP_VANGUARD := 8      # data/heroes.json vanguard hp
const HERO_WEAPON := "laohuoji"  # vanguard start_weapons[0]

var _root: Node2D = null
var _fs: FloorScene = null


func before_test() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
	_fs = null
	RunState.start_run("vanguard")   # 复位楼层/种子/聚合（跨套件卫生）
	RunState.coins = 0


# ================================================================ 缝 1：RunRoot

func test_run_root_builds_floor_one_with_chosen_hero() -> void:
	_root = _make_root()
	add_child(_root)                        # 入树（玩家 _ready/@onready 需树上下文）
	_root._begin()
	var fs: FloorScene = _root.floor_scene
	assert_object(fs).is_not_null()
	assert_int(fs.room_count()).is_equal(13)             # DungeonGraph 规格 13 节点
	assert_int(fs.floor_idx).is_equal(1)
	assert_int(fs.flow.start_room()).is_equal(int(fs.flow.current_room))
	# 玩家 = HeroApplier 装配的 vanguard：面板/初始武器/技能/meta，挂 RunRoot（跨层存活）
	var player: Player = _root.player
	assert_object(player).is_not_null()
	assert_int(player.hp_max).is_equal(HERO_HP_VANGUARD)
	assert_bool(player.is_in_group("player")).is_true()
	assert_bool(player.weapon_rig.current().is_empty()).is_false()
	assert_str(String(player.weapon_rig.current().get("id", ""))).is_equal(HERO_WEAPON)
	assert_bool(player.get_node("Skill").get_script() != null).is_true()
	assert_bool(player.has_meta("crit_base")).is_true()
	# 玩家落 start 房中心
	assert_bool(fs.room_rect(fs.flow.start_room()).has_point(player.position)).is_true()


func test_run_root_embedded_does_not_autoboot() -> void:
	# 嵌入（非 current_scene）不自动开局——测试/宿主先装配的路径不进 _begin（FloorScene 同约定）
	_root = _make_root()
	add_child(_root)
	assert_object(_root.floor_scene).is_null()
	assert_object(_root.player).is_null()
	_root._begin()                          # 生产等价入口（路由 _ready 即调它）
	assert_object(_root.floor_scene).is_not_null()
	assert_object(_root.player).is_not_null()


func test_floor_rebuild_keeps_player_and_rebuilds_rooms() -> void:
	# 重建机制（next_floor 同入口 _start_floor）：旧层释放、玩家同实例跨层存活、新层完整装配
	_root = _make_root()
	_root._begin()
	var old_fs: FloorScene = _root.floor_scene
	var player: Player = _root.player
	_root._on_next_floor_requested(1)       # floor 1 有数据 → 重建（floor 2 走浮层，见缝 4）
	assert_bool(old_fs.is_queued_for_deletion()).is_true()
	var fs: FloorScene = _root.floor_scene
	assert_object(fs).is_not_null()
	assert_bool(fs != old_fs).is_true()
	assert_int(fs.room_count()).is_equal(13)
	assert_bool(_root.player == player).is_true()        # 玩家同实例
	assert_bool(fs.room_rect(fs.flow.start_room()).has_point(player.position)).is_true()


func test_physical_walk_into_adjacent_room_triggers_enter() -> void:
	# 回归钉住（m1-t27 diff 复审发现）：按图进房检测必须无条件跑（含 start 等无战斗
	# 房）——真实玩家物理走图靠它进房；若只在有 combat 的房跑，start/设施房即软锁。
	_fs = _make_floor(["combat"])
	var player: Player = _fs.player_node()
	var start := _fs.flow.start_room()
	var next: int = _fs.flow.adjacent(start)[0]
	player.global_position = _fs.room_center(next)      # 物理走位（非 enter_room 直驱）
	await _await_until(func() -> bool: return _fs.flow.current_room == next)
	assert_int(_fs.flow.current_room).is_equal(next)     # 检测进房 + 锁门开战
	assert_bool(_fs.flow.is_locked()).is_true()
	# 回走 start（无 combat 房）→ 检测同样要生效（拒绝→推回，current 不变）
	_fs.flow.notify_room_cleared(next)
	player.global_position = _fs.room_center(start)
	await _await_until(func() -> bool: return _fs.flow.current_room == start)
	assert_int(_fs.flow.current_room).is_equal(start)


# ================================================================ 缝 2：真实嘉宾

func test_real_guests_spawn_and_waves_advance() -> void:
	_fs = _make_floor(["elite", "miniboss", "boss"])
	# elite：波2 真双刀蜥人（swift+berserk）→ kill 经 wave_id 回译 elite_charger → 房清
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "shuangdao_lizardman") != null)
	var elite := _find_enemy(_fs.room_node(1), "shuangdao_lizardman")
	assert_int(elite.hp).is_equal(180)
	assert_bool(elite.has_berserk).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	assert_bool(_fs.flow.cleared.has(1)).is_true()
	# miniboss：真自爆王虫（armored ×3、leech）→ 回译 miniboss_charger → 房清
	assert_bool(_fs.enter_room(2)).is_true()
	_kill_all(_fs.room_node(2))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(2), "zibao_wangchong") != null)
	var mb := _find_enemy(_fs.room_node(2), "zibao_wangchong")
	assert_int(mb.hp).is_equal(540)
	assert_bool(mb.leech).is_true()
	_kill_all(_fs.room_node(2))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(2))
	assert_bool(_fs.flow.cleared.has(2)).is_true()


func test_guest_drops_weapon_station_and_hearts() -> void:
	# drops "weapon,hearts2"：精英死 → 武器掉落台（ShopLogic roll）+ 2 红心，掉落台可 E 换手
	_fs = _make_floor(["elite"])
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "shuangdao_lizardman") != null)
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	var station: Interactable = _fs.room_node(1).get_node_or_null(NodePath("LootStation"))
	assert_object(station).is_not_null()
	# 红心 4 = 精英嘉宾 drops 2 + elite 房清奖励 2（waves_for hearts）
	var hearts := 0
	for c in _fs.room_node(1).get_children():
		if c is Pickup and (c as Pickup).kind == "heart":
			hearts += 1
	assert_int(hearts).is_equal(4)
	var player: Player = _fs.player_node()
	assert_bool(player.weapon_rig.slots[1].is_empty()).is_true()
	station.interact(player)
	assert_bool(player.weapon_rig.slots[1].is_empty()).is_false()


func test_placeholder_fallback_when_use_real_guests_off() -> void:
	# 开关回归对照：use_real_guests=false → T12 占位路径原样（elite_charger 3×hp）
	_fs = FloorScene.new()
	_fs.use_real_guests = false
	add_child(_fs)
	_fs.setup(_typed_chain(["elite"]), _player_instance())
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "elite_charger") != null)
	var guest := _find_enemy(_fs.room_node(1), "elite_charger")
	assert_int(guest.hp).is_equal(18 * 3)


# ================================================================ 缝 3：设施

func test_shop_facility_buys_with_runstate_wallet_and_recycles() -> void:
	_fs = _make_floor(["shop"])
	RunState.coins = 100
	assert_bool(_fs.enter_room(1)).is_true()
	var shop := _shop_in(_fs.room_node(1))
	assert_object(shop).is_not_null()
	# 货单：3 武器位 roll（层权重逐位 roll，池 40 把）+ 道具 + 层号元数据
	assert_int((shop.stock["weapons"] as Array).size()).is_equal(3)
	assert_int(int(shop.stock["floor_idx"])).is_equal(1)
	# 买：RunState 钱包扣款 → 入空槽（玩家初始 laohuoji 占槽 0）。
	# open() 由玩家交互触发（E），测试走同一入口；价格按货品实际稀有度计。
	var wid := String((shop.stock["weapons"] as Array)[0])
	var rarity := String(GameDB.get_weapon(wid).get("rarity", "common"))
	shop.interact(_fs.player_node())
	shop._buy_weapon(0)
	assert_bool(shop.is_sold(0)).is_true()
	assert_str(String(_fs.player_node().weapon_rig.slots[1].get("id", ""))).is_equal(wid)
	assert_int(RunState.coins).is_equal(100 - ShopLogic.price(rarity, 1, false))
	# 回收：副手（槽 1 = 刚买的 wid）→ recycle_price 入账 RunState，槽清空
	_fs.player_node().weapon_rig.equip("tiejian")     # 双槽满 → 替换当前槽 0
	RunState.coins = 0
	shop._recycle()
	assert_int(RunState.coins).is_equal(ShopLogic.recycle_price(rarity, 1))
	assert_bool(_fs.player_node().weapon_rig.slots[1].is_empty()).is_true()


func test_event_facility_opens_panel_on_entry() -> void:
	_fs = _make_floor(["event"])
	assert_bool(_fs.enter_room(1)).is_true()
	var ev := _event_in(_fs.room_node(1))
	assert_object(ev).is_not_null()
	assert_bool(ev.ui_visible()).is_true()
	assert_array(EventRoom.EVENT_IDS).contains(ev.current_event())


func test_coin_pickup_credits_runstate() -> void:
	_fs = _make_floor(["combat"])
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _alive_count(_fs.room_node(1)) == 3)   # 波2 补刷
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	var coin := _coin_in(_fs.room_node(1))
	assert_object(coin).is_not_null()
	var before := RunState.coins
	coin.on_collect.call()
	assert_int(RunState.coins).is_equal(before + 1)


# ================================================================ 缝 4：层间

func test_boss_death_opens_inter_floor_and_door_ends_m1() -> void:
	# boss 死亡 → inter_floor 嵌入开层（BUFF 三选一）→ 选增益 → 喷泉 → 门 →
	# InterFloorFlow.enter_next_floor 推层+蓝晶 → 无 A2 数据 → M1 完结浮层。
	_root = _make_root()
	add_child(_root)                        # 入树（kill→EventBus→Fx/层间链需树上下文）
	_root._begin()
	var fs: FloorScene = _root.floor_scene
	# 直驱 FloorFlow 走到 boss 门口（纯逻辑清图；boss 房走真实场景 enter_room 开战）
	var boss := fs.flow.boss_room()
	for id in _path_to_boss(fs, boss):
		if id == boss:
			continue                           # boss 留给真实场景 enter_room 开战
		assert_bool(fs.flow.enter_room(id)).is_true()
		if fs.flow.room_type(id) != "start":
			fs.flow.notify_room_cleared(id)
	assert_bool(fs.enter_room(boss)).is_true()          # boss 房：真巨像开战
	assert_object(_find_enemy(fs.room_node(boss), "vine_colossus")).is_not_null()
	_kill_all(fs.room_node(boss))
	await _await_until(func() -> bool: return _root.inter_floor != null)
	var inter: Node2D = _root.inter_floor
	assert_bool(is_instance_valid(inter)).is_true()
	assert_bool(fs._flow_suspended).is_true()           # 楼层流程挂起（防进房检测抢人）
	assert_int(inter.flow.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_bool(inter.flow.offered.is_empty()).is_false()
	# 三选一 → 喷泉 → 门（走场景层回调，等价玩家操作）
	inter._on_buff_chosen(inter.flow.offered[0])
	assert_array(RunState.buffs).contains(inter.flow.offered[0])
	var hp0: int = _root.player.hp
	assert_bool(inter.flow.use_fountain(_root.player)).is_true()
	assert_int(_root.player.hp).is_equal(mini(hp0 + 2, _root.player.hp_max))
	var gems0 := RunState.gems
	inter._on_door_interact(_root.player)
	# 门侧效：InterFloorFlow.enter_next_floor 已推层 + §14.1 蓝晶结算（1→2 给 60）
	assert_int(RunState.floor_idx).is_equal(2)
	assert_int(RunState.gems).is_equal(gems0 + 60)
	assert_bool(_root.m1_overlay_visible()).is_true()   # 无 A2 数据 → 浮层（同拍落地）
	assert_str(_root.overlay_text()).contains("M1 完结")
	assert_bool(inter.is_queued_for_deletion()).is_true()
	assert_object(_root.floor_scene).is_not_null()      # 第 1 层保留（无 A2 数据不重建）


func test_boss_death_flow_victory_stub_at_floor_three() -> void:
	# 第 3 层胜利桩（InterFloorFlow.VICTORY_FLOOR=3 契约）：M1 数据到不了第 3 层，
	# 流程级验证：floor_idx=3 开层间 → victory 直显结算桩；DONE 阶段推层 fail-closed。
	_root = _make_root()
	add_child(_root)
	_root._begin()
	RunState.floor_idx = 3
	var inter: Node2D = (load("res://core/rooms/inter_floor.tscn") as PackedScene).instantiate()
	_root.add_child(inter)
	inter.setup(_root.player, _root.buffs, 3)
	inter.open()
	assert_bool(inter.flow.victory).is_true()
	assert_int(inter.flow.phase).is_equal(InterFloorFlow.Phase.DONE)
	assert_bool(inter._victory_label.visible).is_true()
	var f0 := RunState.floor_idx
	assert_int(inter.flow.enter_next_floor()).is_equal(-1)   # DONE 阶段拒绝推层
	assert_int(RunState.floor_idx).is_equal(f0)


# ================================================================ helpers

func _make_root() -> Node2D:
	return (load(RUN_ROOT_SCENE) as PackedScene).instantiate() as Node2D


func _player_instance() -> Player:
	return (load(PLAYER_SCENE) as PackedScene).instantiate() as Player


func _make_floor(types: Array) -> FloorScene:
	var fs := FloorScene.new()
	add_child(fs)
	fs.setup(_typed_chain(types), _player_instance())    # setup 收养无父玩家
	_fs = fs
	return fs


## 直驱 FloorFlow 的到 boss 可达路径：BFS 最短路（boss 唯一邻接 = 主路径倒数第二节点），
## 终点 boss（由测试真实 enter_room）。战斗房经 notify 清（纯逻辑，场景波次不驱动）。
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
	var cur2 := boss
	while cur2 != start:
		path.push_front(cur2)
		cur2 = int(parent[cur2])
	return path


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


func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * 416.0,
	}


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 99999, "is_crit": false, "element": 0, "from": e.global_position})


func _alive_count(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


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


func _coin_in(room: FloorScene.FloorRoom) -> Pickup:
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == "coin":
			return c
	return null
