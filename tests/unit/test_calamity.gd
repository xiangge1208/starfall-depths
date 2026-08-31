class_name TestCalamity
extends GdUnitTestSuite
## m2-t26：挑战房灾厄收口 + 小 Boss 楼层缩放契约测试。
## 1) 灾厄目录（ui/calamity.gd）：恰 4 项中文（敌速+30% / 视野-35% / 治疗无效 / 弹速+25%），
##    面板 4 选 1（键盘位/点击同路径）→ calamity_chosen(id)。
## 2) FloorScene 挑战房：combat 房择一标记；进门先 4 选 1（不刷怪、门锁）；选定才开战
##    （3 波 = 战斗房配置轮转 ×1.25 强度，行级 override 不污染 GameDB 缓存）；
##    敌速 ×1.3 / 视野 -35%（复用 BiomeFx）/ 治疗无效（玩家临时 meta + 房内红心截断）/
##    弹速 ×1.25；清房必得紫武器 + 80~120 金币；房清灾厄全还原（meta 摘除 / fx 卸载）。
## 3) 小 Boss 楼层缩放（附录 B.3）：floor2 行 hp 400 / floor3 870（词缀在其上照常生效），
##    floor1 基准不动。

const SEED := 20260828
const SPAN_PX := 416.0


# ---------------------------------------------------------------- 构建体替身

func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


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


# ---------------------------------------------------------------- 灾厄目录 / 面板

func test_calamity_catalog_four_cn_options() -> void:
	# 恰 4 项，id 与中文标签逐字对齐 GDD §11 挑战房行
	assert_int(CalamityPanel.CALAMITIES.size()).is_equal(4)
	var ids := CalamityPanel.CALAMITY_IDS
	assert_array(ids).contains(["enemy_speed", "vision", "heal_disable", "bullet_speed"])
	var labels: Array = []
	for c: Dictionary in CalamityPanel.CALAMITIES:
		labels.append(String(c["label"]))
	assert_array(labels).contains(["敌速+30%", "视野-35%", "治疗无效", "弹速+25%"])


func test_calamity_panel_open_choose_flow() -> void:
	var panel: CalamityPanel = CalamityPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert_bool(panel.visible).is_false()            # 构建后隐藏，open() 才显示
	var chosen: Array = []
	panel.calamity_chosen.connect(func(id: String) -> void: chosen.append(id))
	panel.open()
	assert_bool(panel.visible).is_true()
	assert_str(panel.title_text()).contains("仅本房生效")
	for i in 4:
		assert_str(panel.card_label(i)).contains(String(CalamityPanel.CALAMITIES[i]["label"]))
	panel._choose(2)                                  # 键盘位/点击共用同一入口
	assert_array(chosen).is_equal(["heal_disable"])
	assert_bool(panel.visible).is_false()
	panel.open()                                      # 重开重填，再选其余项
	panel._choose(0)
	assert_array(chosen).is_equal(["heal_disable", "enemy_speed"])
	panel.free()


# ---------------------------------------------------------------- 静态契约

func test_challenge_waves_three_waves_zeroed_rewards() -> void:
	# 3 波（战斗房 2 波配置 + 波1 复用），每波 3 只全在 A1 名录；奖励置零（清房改发紫+金币）
	var roster := ["kuli_bug", "cave_bat", "crossbowman", "vine_charger"]
	var cfg := FloorScene.challenge_waves_for(1)
	var waves: Array = cfg["waves"]
	assert_int(waves.size()).is_equal(3)
	for w: Array in waves:
		assert_int(w.size()).is_equal(3)
		for id: String in w:
			assert_array(roster).contains(id)
	assert_str(var_to_str(waves[0])).is_equal(var_to_str(waves[2]))   # 波3 = 波1 轮转复用
	assert_int(int(cfg["coins"])).is_equal(0)
	assert_int(int(cfg["energy_orbs"])).is_equal(0)
	assert_int(int(cfg["hearts"])).is_equal(0)
	assert_str(var_to_str(FloorScene.challenge_waves_for(1))).is_equal(var_to_str(cfg))


func test_miniboss_hp_floor_scaling_table() -> void:
	# 附录 B.3：A1 基准（行原值不动）/ A2 400 / A3 870；表外楼层 clamp 到界
	assert_int(FloorScene.miniboss_hp_for_floor(1, 180)).is_equal(180)
	assert_int(FloorScene.miniboss_hp_for_floor(1, 54)).is_equal(54)   # 占位换算基准也不动
	assert_int(FloorScene.miniboss_hp_for_floor(2, 180)).is_equal(400)
	assert_int(FloorScene.miniboss_hp_for_floor(3, 180)).is_equal(870)
	assert_int(FloorScene.miniboss_hp_for_floor(7, 180)).is_equal(870)


# ---------------------------------------------------------------- 场景编排

var _fs: FloorScene = null
var _player: Player = null


## 玩家由测试自持（不收养）→ 场景 free 后仍可断言 meta 还原。
## challenge_id >= 0：setup 前显式指定挑战房（战斗房波次组成按房号确定 → 断言稳定）。
func _make_scene(build: Dictionary, floor_idx: int = 1, challenge_id := -1) -> FloorScene:
	_player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(_player)
	_fs = FloorScene.new()
	_fs.floor_idx = floor_idx
	if challenge_id >= 0:
		_fs.challenge_room_id = challenge_id
	add_child(_fs)
	_fs.setup(build, _player)
	return _fs


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null
	if _player != null and is_instance_valid(_player):
		_player.free()
		_player = null


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func test_challenge_room_auto_pick_deterministic() -> void:
	# 同种子两次构建 → 同一挑战房；必为 combat 房型；未设 combat 房（退化链）则不设
	var build := DungeonBuilder.build(SEED, 1)
	var fs1 := _make_scene(build)
	var cid := fs1.challenge_room()
	assert_int(cid).is_greater_equal(0)
	assert_str(fs1.flow.room_type(cid)).is_equal("combat")
	var build2 := DungeonBuilder.build(SEED, 1)
	var fs2 := _make_scene(build2)
	assert_int(fs2.challenge_room()).is_equal(cid)
	var room: FloorScene.FloorRoom = fs1.room_node(cid)
	assert_bool(room.is_challenge).is_true()
	assert_int((room.waves_cfg["waves"] as Array).size()).is_equal(3)


func test_single_combat_chain_has_no_challenge_room() -> void:
	# 退化构建体（combat < 2）不自动设挑战房：常规战斗语义保留（回归对照链兼容）
	var fs := _make_scene(_typed_chain(["combat"]))
	assert_int(fs.challenge_room()).is_equal(-1)
	assert_bool(fs.enter_room(1)).is_true()
	assert_bool(fs.calamity_panel_visible()).is_false()
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(3)


func test_challenge_entry_holds_waves_until_choice() -> void:
	# 进挑战房：门锁 + 灾厄面板开 + 不刷怪；RoomFlow 未启动（双 combat 链触发自动择一）
	var fs := _make_scene(_typed_chain(["combat", "combat"]))
	var cid := fs.challenge_room()
	assert_int(cid).is_greater_equal(0)
	assert_bool(fs.enter_room(cid)).is_true()
	assert_bool(fs.flow.is_locked()).is_true()
	assert_bool(fs.gate_is_open(0, cid)).is_false()
	assert_bool(fs.calamity_panel_visible()).is_true()
	assert_int(_alive_enemies(fs.room_node(cid))).is_equal(0)


func test_non_challenge_combat_room_starts_immediately() -> void:
	# 显式指定 2 号房为挑战房（setup 前覆盖）→ 1 号普通战斗房进房即刷波、无面板
	_player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(_player)
	_fs = FloorScene.new()
	_fs.challenge_room_id = 2
	add_child(_fs)
	_fs.setup(_typed_chain(["combat", "combat"]), _player)
	assert_int(_fs.challenge_room()).is_equal(2)
	assert_bool(_fs.enter_room(1)).is_true()
	assert_bool(_fs.calamity_panel_visible()).is_false()
	assert_int(_alive_enemies(_fs.room_node(1))).is_equal(3)


func test_enemy_speed_calamity_row_override() -> void:
	# 敌速+30%：波次行 speed 族 ×1.3；hp ×1.25 恒定（强化怪与灾厄无关）；GameDB 缓存不污染
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	fs.choose_calamity("enemy_speed")
	assert_bool(fs.calamity_panel_visible()).is_false()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_int(_alive_enemies(room)).is_equal(3)
	assert_str(room.calamity_id).is_equal("enemy_speed")
	var shooter := _find_enemy(room, "crossbowman")
	assert_object(shooter).is_not_null()
	if shooter != null:
		assert_int(int(shooter.row["hp"])).is_equal(20)            # 16 ×1.25
		assert_float(float(shooter.row["speed"])).is_equal_approx(78.0, 0.001)   # 60 ×1.3
	var charger := _find_enemy(room, "vine_charger")
	assert_object(charger).is_not_null()
	if charger != null:
		assert_float(float(charger.row["walk_speed"])).is_equal_approx(58.5, 0.001)
		assert_float(float(charger.row["dash_speed"])).is_equal_approx(370.5, 0.001)
	# GameDB 缓存行不得被改写
	assert_int(int(GameDB.get_enemy("crossbowman")["hp"])).is_equal(16)
	assert_float(float(GameDB.get_enemy("crossbowman")["speed"])).is_equal_approx(60.0, 0.001)


func test_bullet_speed_calamity_row_override() -> void:
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	fs.choose_calamity("bullet_speed")
	var shooter := _find_enemy(fs.room_node(1), "crossbowman")
	assert_object(shooter).is_not_null()
	if shooter != null:
		assert_float(float(shooter.row["bullet_speed"])).is_equal_approx(137.5, 0.001)   # 110 ×1.25
	assert_float(float(GameDB.get_enemy("crossbowman")["bullet_speed"])) \
		.is_equal_approx(110.0, 0.001)


func test_vision_calamity_mounts_dim_fx_and_restores() -> void:
	# 视野-35%：复用 BiomeFx（CanvasModulate 0.65 灰 + 光圈半径 ×0.65）；清房卸载
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	assert_bool(fs.calamity_fx == null).is_true()
	fs.choose_calamity("vision")
	assert_object(fs.calamity_fx).is_not_null()
	if fs.calamity_fx != null:
		var cm := fs.calamity_fx.canvas_modulate
		assert_vector(Vector3(cm.color.r, cm.color.g, cm.color.b)) \
			.is_equal_approx(Vector3(0.65, 0.65, 0.65), Vector3(0.001, 0.001, 0.001))
		var base_scale := BiomeFx.LIGHT_RADIUS_PX * 2.0 / float(BiomeFx.LIGHT_TEXTURE_PX)
		assert_float(fs.calamity_fx.light.texture_scale).is_equal_approx(base_scale * 0.65, 0.001)
	var room: FloorScene.FloorRoom = fs.room_node(1)
	for _w in 3:                                      # 3 波全清 → 房清还原
		_kill_all(room)
		await _await_until(func() -> bool: return _alive_enemies(room) == 3 \
			or fs.flow.cleared.has(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(fs.calamity_fx == null).is_true()      # 房清即卸载


func test_heal_disable_calamity_meta_flag_and_heart_gate() -> void:
	# 治疗无效：玩家临时 meta 标志 + 挑战房内红心不落（coin 不受影响）；房清还原
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	fs.choose_calamity("heal_disable")
	assert_bool(_player.has_meta(FloorScene.CALAMITY_HEAL_META)).is_true()
	fs._spawn_pickup(room, "heart", room.outer.get_center())
	fs._spawn_pickup(room, "coin", room.outer.get_center() + Vector2(8, 0))
	assert_int(_pickups_of(room, "heart")).is_equal(0)
	assert_int(_pickups_of(room, "coin")).is_equal(1)
	for _w in 3:                                      # 3 波全清 → 房清还原
		_kill_all(room)
		await _await_until(func() -> bool: return _alive_enemies(room) == 3 \
			or fs.flow.cleared.has(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(_player.has_meta(FloorScene.CALAMITY_HEAL_META)).is_false()
	fs._spawn_pickup(room, "heart", room.outer.get_center())
	assert_int(_pickups_of(room, "heart")).is_equal(1)   # 还原后红心恢复掉落


func test_challenge_clear_guarantees_epic_and_coins_then_restores() -> void:
	# 完整走通：4 选 1 → 3 波全清 → 门开 + 必得紫武器掉落台 + 80~120 金币 + meta 摘除
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	fs.choose_calamity("heal_disable")
	var room: FloorScene.FloorRoom = fs.room_node(1)
	for _w in 3:
		assert_int(_alive_enemies(room)).is_equal(3)
		_kill_all(room)
		await _await_until(func() -> bool: return _alive_enemies(room) == 3 \
			or fs.flow.cleared.has(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(fs.flow.is_locked()).is_false()
	assert_bool(fs.gate_is_open(0, 1)).is_true()
	# 必得紫：掉落台 weapon_id 稀有度恒 epic（locked 行经 weapons_all 取，get_weapon 回落）
	var station := room.get_node_or_null(NodePath("LootStation")) as Interactable
	assert_object(station).is_not_null()
	if station != null:
		var wid := String(station.get_meta("weapon_id", ""))
		assert_str(String(GameDB.get_weapon(wid).get("rarity", ""))).is_equal("epic")
	# 大量金币：80~120 枚（无红心/蓝珠混入标准奖励）
	var coins := _pickups_of(room, "coin")
	assert_int(coins).is_greater_equal(80)
	assert_int(coins).is_less_equal(120)
	assert_int(_pickups_of(room, "heart")).is_equal(0)
	# 灾厄还原（meta 摘除在 heal 用例详测，此处钉房清状态位复位）
	assert_str(room.calamity_id).is_empty()
	Telemetry.flush()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("calamity")).is_true()


func test_miniboss_floor_scaling_scene() -> void:
	# floor2 小 Boss：抽取池任意行 → 行 hp 400（B.3 楼层表；armored 词缀在其上 ×3，
	# 无 armored 行保持 400——词缀是行内数据，不属楼层缩放）；数据行不落缩放
	var fs := _make_scene(_typed_chain(["miniboss"]), 2)
	assert_bool(FloorScene.MINIBOSS_POOL.has(fs.miniboss_row())).is_true()
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(fs.room_node(1))
	await _await_until(func() -> bool: return _find_miniboss(fs.room_node(1)) != null)
	var mb := _find_miniboss(fs.room_node(1))
	assert_object(mb).is_not_null()
	if mb != null:
		var want := 400
		if (mb.row.get("elite_affixes", []) as Array).has("armored"):
			want *= 3
		assert_int(mb.hp).is_equal(want)
		assert_int(int(GameDB.get_enemy(String(mb.row["id"]))["hp"])).is_equal(180)


func test_miniboss_pool_per_floor_deterministic() -> void:
	# m2-t26 抽取池按层接线：同 run_seed 同层恒同体（RngSvc.stream 无状态派生），
	# 池 = 附录 B.3 全 6 行；层数独立取值（不重复派生同盐流）
	RngSvc.setup_run(SEED)
	var fs2 := _make_scene(_typed_chain(["miniboss"]), 2)
	RngSvc.setup_run(SEED)
	var fs2b := _make_scene(_typed_chain(["miniboss"]), 2)
	RngSvc.setup_run(SEED)
	var fs3 := _make_scene(_typed_chain(["miniboss"]), 3)
	assert_str(fs2b.miniboss_row()).is_equal(fs2.miniboss_row())
	assert_bool(FloorScene.MINIBOSS_POOL.has(fs3.miniboss_row())).is_true()
	assert_int(FloorScene.MINIBOSS_POOL.size()).is_equal(6)
	# 数据契约：6 行全 hp 180 + drops 一致（guest 掉落口径不随抽取体漂移）
	for id: String in FloorScene.MINIBOSS_POOL:
		var row := GameDB.get_enemy(id)
		assert_int(int(row["hp"])).is_equal(180)
		assert_str(String(row.get("drops", ""))).is_equal("weapon,hearts2")


func test_calamity_meta_removed_on_scene_exit() -> void:
	# 换层/场景销毁兜底：玩家 meta 标志由 FloorScene._exit_tree 摘除（玩家不被收养时）
	var fs := _make_scene(_typed_chain(["combat", "combat"]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	fs.choose_calamity("heal_disable")
	assert_bool(_player.has_meta(FloorScene.CALAMITY_HEAL_META)).is_true()
	fs.free()
	_fs = null
	assert_bool(_player.has_meta(FloorScene.CALAMITY_HEAL_META)).is_false()


# ---------------------------------------------------------------- 真实构建体全图走查
# （t26_manual_walk_tmp 转正：脚本驱动等价玩家入口，m1_evidence 先例。DFS 带回溯
# 沿开门图走遍 13 房到挑战房 → 灾厄 4 选 1（视野）→ 3 波全清 → 紫武器+金币 → 灾厄还原。）

func test_challenge_full_run_on_real_build() -> void:
	RunState.start_run("vanguard")
	var build := DungeonBuilder.build(SEED, 1)
	assert_array(DungeonBuilder.validate_build(build)).is_empty()
	_player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(_player)
	_fs = FloorScene.new()
	_fs.floor_idx = 1
	add_child(_fs)
	_fs.setup(build, _player)
	var cid := _fs.challenge_room()
	assert_int(cid).is_greater_equal(0)
	assert_str(_fs.flow.room_type(cid)).is_equal("combat")
	await _dfs_room(int(build["start_room_id"]), -1, cid)
	assert_bool(_fs.flow.cleared.has(cid)).is_true()


## DFS 走房（带回溯）：逐房进门 → 战斗房型清波 → 挑战房跑灾厄全流程 → 子房递归 →
## 回溯重进父房（两侧清房门恒开，flow.enter_room 只许邻房移动）。
func _dfs_room(id: int, from: int, cid: int) -> void:
	if _fs.flow.current_room != id:
		assert_bool(_fs.enter_room(id)).is_true()
	if id == cid:
		await _run_challenge_room(cid)
	elif FloorFlow.COMBAT_TYPES.has(_fs.flow.room_type(id)):
		await _clear_room(id)
	for n in _fs.flow.adjacent(id):
		if n == from:
			continue
		await _dfs_room(n, id, cid)
	if from >= 0 and _fs.flow.current_room != from:
		assert_bool(_fs.enter_room(from)).is_true()


## 清一房波次：杀当前波 → 固定让帧等下一波刷出（让帧是必须的——零让帧自旋会
## 饿死物理帧，波次调度永不推进）；guard 防异常挂死。
func _clear_room(id: int) -> void:
	if _fs.flow.cleared.has(id):
		return
	var room: FloorScene.FloorRoom = _fs.room_node(id)
	var guard := 0
	while not _fs.flow.cleared.has(id) and guard < 60:
		guard += 1
		_kill_all(room)
		await _wait_frames(20)
	assert_bool(_fs.flow.cleared.has(id)).is_true()


func _run_challenge_room(cid: int) -> void:
	var room: FloorScene.FloorRoom = _fs.room_node(cid)
	# 进门：门锁 + 面板开 + 未刷怪
	assert_bool(_fs.calamity_panel_visible()).is_true()
	assert_int(_alive_enemies(room)).is_equal(0)
	assert_bool(_fs.flow.is_locked()).is_true()
	# 4 选 1：视野-35%（BiomeFx 复用路径）→ 3 波全清
	_fs.choose_calamity("vision")
	assert_object(_fs.calamity_fx).is_not_null()
	var guard := 0
	while not _fs.flow.cleared.has(cid) and guard < 60:
		guard += 1
		_kill_all(room)
		await _wait_frames(20)
	assert_bool(_fs.flow.cleared.has(cid)).is_true()
	assert_bool(_fs.flow.is_locked()).is_false()
	# 必得紫 + 80~120 金币；灾厄还原
	var station := room.get_node_or_null(NodePath("LootStation")) as Interactable
	assert_object(station).is_not_null()
	if station != null:
		var wid := String(station.get_meta("weapon_id", ""))
		assert_str(String(GameDB.get_weapon(wid).get("rarity", ""))).is_equal("epic")
	var coins := _pickups_of(room, "coin")
	assert_int(coins).is_greater_equal(80)
	assert_int(coins).is_less_equal(120)
	assert_bool(_fs.calamity_fx == null).is_true()
	assert_str(room.calamity_id).is_empty()


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


# ---------------------------------------------------------------- helpers

func _alive_enemies(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 9999, "is_crit": false, "element": 0, "from": e.global_position})


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


## 小 Boss 嘉宾按波次标记定位（抽取池化后数据行 id 不再恒 zibao_wangchong）。
func _find_miniboss(room: FloorScene.FloorRoom) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("wave_id", "")) == "miniboss_charger" \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


func _pickups_of(room: FloorScene.FloorRoom, kind: String) -> int:
	var n := 0
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == kind:
			n += 1
	return n
