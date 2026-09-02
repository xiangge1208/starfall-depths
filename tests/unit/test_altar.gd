class_name TestAltar
extends GdUnitTestSuite
## m4-c4 增益祭坛设施 + elite_surge 试炼分支（m3-fix1 §残留半边收口）：
## 1) 生成判定纯函数：15% 掷签语义 + altar_excludes 互斥 fail-closed（chance<=0 恒不生成）
## 2) 楼层掷签：combat 房型 + 模板 altar_chance=0.15 数据驱动、同 seed 确定性、
##    非战斗房型（elite/miniboss/boss/shop…）零生成、200 种子分布带（二项 ±3σ）
## 3) 交互·增益分支（非试炼局）：三选一全部来自 GameDB.buffs 既有池（零新数值键）、
##    选卡经 apply 回调落地、一次性、choose 越界拒绝
## 4) 交互·elite_surge 分支（试炼局）：TrialMods.altar_elite_surge() 单点读
##    RunState.mods（elite_bonus_pct），交互改为追加 1 精英（楼层真实嘉宾行+词缀），
##    战斗中 spawn 不计波次（同召唤体口径）；已清房 spawn 不回锁
## 5) 零漂移：无因子/无关因子不触发精英分支；普通局祭坛照常三选一

const SEED := 4242
const SPAN_PX := 416.0

var _fs: FloorScene = null
var _saved_mods: Dictionary = {}
var _saved_seed: int = 0
var _saved_floor_idx: int = 0


func before_test() -> void:
	_saved_mods = RunState.mods
	_saved_seed = RngSvc.run_seed
	_saved_floor_idx = RunState.floor_idx


func after_test() -> void:
	RunState.mods = _saved_mods
	RunState.floor_idx = _saved_floor_idx
	RngSvc.setup_run(_saved_seed)
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


# ---------------------------------------------------------------- 构建替身

func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	# combat 型走 combat_a1_01（带 altar_chance=0.15 的战斗模板）；start/boss 专用模板
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


## 手工链式构建体：start(0) → types[0](1) → …（横向 E 走廊）。
func _chain(types: Array) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var grid := Vector2i(i + 1, 0)
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), grid, nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player, BuffManager.new())
	return _fs


func _altar_in(fs: FloorScene, room_id: int) -> Altar:
	for c in fs.room_node(room_id).get_children():
		if c is Altar:
			return c
	return null


func _alive_enemies(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _kill_all(room: FloorScene.FloorRoom) -> void:
	# duplicate 快照迭代（同 test_floor_scene 口径）：die() 同步从 room.enemies 擦除，
	# 原数组遍历会跳元素
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 9999, "is_crit": false, "element": 0,
				"from": e.global_position})


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for i in max_frames:
		if Callable(check).call():
			return
		await get_tree().process_frame


## 找一个「单战斗房掷签命中祭坛」的种子（纯流重放，不建场景，廉价）。
func _seed_with_altar(start_seed: int) -> int:
	for s in range(start_seed, start_seed + 200):
		RngSvc.setup_run(s)
		var rng := RngSvc.stream(1, "altar")
		if rng.randf() < 0.15:
			return s
	return -1


# ---------------------------------------------------------------- 1) 生成判定纯函数

func test_roll_pending_chance_semantics() -> void:
	# 掷签 < altar_chance 生成；[chance, 1) 不生成；chance<=0 恒不生成（缺省 fail-closed）
	assert_bool(Altar.roll_pending(0.0, 0.15, [], [])).is_true()
	assert_bool(Altar.roll_pending(0.14, 0.15, [], [])).is_true()
	assert_bool(Altar.roll_pending(0.15, 0.15, [], [])).is_false()
	assert_bool(Altar.roll_pending(0.999, 0.15, [], [])).is_false()
	assert_bool(Altar.roll_pending(0.01, 0.0, [], [])).is_false()
	assert_bool(Altar.roll_pending(0.01, -0.5, [], [])).is_false()


func test_roll_pending_exclusion_semantics() -> void:
	# 互斥：房内既有设施 kind 命中 altar_excludes → 不生成；无关设施不拦截
	assert_bool(Altar.roll_pending(0.01, 0.15, ["shop", "forge"], ["shrine"])).is_true()
	assert_bool(Altar.roll_pending(0.01, 0.15, [], ["shop"])).is_true()
	assert_bool(Altar.roll_pending(0.01, 0.15, ["shop", "forge"], ["event", "forge"])).is_false()
	assert_bool(Altar.roll_pending(0.01, 0.15, ["shop"], ["shop"])).is_false()


# ---------------------------------------------------------------- 2) 楼层掷签

func test_scene_combat_room_altar_pending_deterministic() -> void:
	# 模板 altar_chance=0.15 数据驱动：命中种子下首进战斗房必建祭坛（设施缝），
	# 同 seed 两次 setup 恒同态（确定性）。
	var seed_hit := _seed_with_altar(SEED)
	assert_int(seed_hit).is_greater(0)
	var build := _chain(["combat"])
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(build)
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(room.altar_pending).is_true()
	assert_object(_altar_in(fs, 1)).is_null()          # 掷签只记 pending，实体在首进建
	assert_object(_altar_in(fs, 0)).is_null()          # start 房恒无祭坛
	assert_bool(fs.enter_room(1)).is_true()
	var altar := _altar_in(fs, 1)
	assert_object(altar).is_not_null()
	assert_bool(room.facility_built).is_true()
	assert_str(altar.action_label).contains("祭坛")


func test_scene_altar_seed_miss_no_facility() -> void:
	# 未命中种子：pending=false，进房不建祭坛、不置 facility_built（零变化路径）
	var build := _chain(["combat"])
	var miss := -1
	for s in range(SEED, SEED + 200):
		RngSvc.setup_run(s)
		var rng := RngSvc.stream(1, "altar")
		if rng.randf() >= 0.15:
			miss = s
			break
	assert_int(miss).is_greater(0)
	RngSvc.setup_run(miss)
	var fs := _make_scene(build)
	assert_bool((fs.room_node(1) as FloorScene.FloorRoom).altar_pending).is_false()
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(_altar_in(fs, 1)).is_null()
	assert_bool((fs.room_node(1) as FloorScene.FloorRoom).facility_built).is_false()


func test_scene_non_combat_room_types_never_roll() -> void:
	# 房型门：elite/miniboss/boss 嘉宾战斗房与 shop/event 客房不掷签（既有设施语义
	# 「嘉宾战斗房无设施」延伸）；即便误挂 combat 模板（替身如此）也不生成。
	var build := _chain(["elite", "shop", "treasure"])
	RngSvc.setup_run(_seed_with_altar(SEED))
	var fs := _make_scene(build)
	assert_bool(fs.enter_room(1)).is_true()
	fs.flow.notify_room_cleared(1)                     # 清 elite 锁（走图推进语义）
	assert_bool(fs.enter_room(2)).is_true()
	assert_bool(fs.enter_room(3)).is_true()
	assert_object(_altar_in(fs, 1)).is_null()
	assert_object(_altar_in(fs, 2)).is_null()
	assert_object(_altar_in(fs, 3)).is_null()


func test_altar_generation_fifteen_percent_band() -> void:
	# 概率钉：200 独立种子 × 单战斗房，生成率落二项分布 ±3σ 带（p=0.15 → μ=30、σ≈5.05，
	# 带 [13, 47]）；消费端与数据值同源（roll < 模板 altar_chance 单一比较）。
	var hits := 0
	for s in range(6100, 6300):
		RngSvc.setup_run(s)
		var rng := RngSvc.stream(1, "altar")
		if rng.randf() < 0.15:
			hits += 1
	assert_int(hits).is_between(13, 47)


# ---------------------------------------------------------------- 3) 增益分支（单元级）

func _make_altar(apply_ids: Array, elite_calls: Array, seed_val: int) -> Altar:
	var altar := Altar.new()
	var buffs := BuffManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	altar.setup(buffs, rng,
		func(id: String) -> void: apply_ids.append(id),
		func(_wp: Vector2) -> void: elite_calls.append(_wp))
	return altar


func test_interact_buff_branch_offers_three_from_existing_pool() -> void:
	var applied: Array = []
	var elite_calls: Array = []
	var altar := _make_altar(applied, elite_calls, 7)
	add_child(altar)
	assert_bool(altar.can_interact(null)).is_true()
	altar.interact(null)
	# 三选一全部来自 buffs.json 既有池（禁止新数值键的池边界）
	assert_int(altar.offerings().size()).is_equal(3)
	var unique := {}
	for id: String in altar.offerings():
		assert_bool(GameDB.buffs.has(id)).is_true()
		unique[id] = true
	assert_int(unique.size()).is_equal(3)              # 单次三选内不重复
	assert_int(elite_calls.size()).is_equal(0)         # 非试炼不触发精英分支
	assert_bool(altar.is_used()).is_true()
	assert_bool(altar.can_interact(null)).is_false()   # 一次性
	# 选卡：经 apply 回调落地；choices 清空；再选拒绝
	assert_bool(altar.choose(0)).is_true()
	assert_int(applied.size()).is_equal(1)
	assert_bool(GameDB.buffs.has(String(applied[0]))).is_true()
	assert_array(altar.offerings()).is_empty()
	assert_bool(altar.choose(1)).is_false()            # 用后 choose 拒绝
	assert_int(applied.size()).is_equal(1)


func test_interact_buff_branch_deterministic_offerings() -> void:
	# 同 rng 种子恒同三选（可复现）
	var applied_a: Array = []
	var applied_b: Array = []
	var a := _make_altar(applied_a, [], 99)
	var b := _make_altar(applied_b, [], 99)
	add_child(a)
	add_child(b)
	a.interact(null)
	b.interact(null)
	assert_array(a.offerings()).is_equal(b.offerings())


func test_choose_out_of_range_rejected() -> void:
	var applied: Array = []
	var altar := _make_altar(applied, [], 5)
	add_child(altar)
	altar.interact(null)
	assert_bool(altar.choose(-1)).is_false()
	assert_bool(altar.choose(3)).is_false()
	assert_int(applied.size()).is_equal(0)


# ---------------------------------------------------------------- 4) elite_surge 分支

func test_interact_elite_surge_branch_replaces_buff() -> void:
	# 试炼局 elite_surge（mods 键 elite_bonus_pct，TrialMods 单点读）：交互改为
	# 「追加 1 精英」，不再弹三选一
	RunState.mods = {"elite_bonus_pct": 100}
	var applied: Array = []
	var elite_calls: Array = []
	var altar := _make_altar(applied, elite_calls, 7)
	add_child(altar)
	altar.interact(null)
	assert_int(elite_calls.size()).is_equal(1)
	assert_array(altar.offerings()).is_empty()         # 无增益分支
	assert_int(applied.size()).is_equal(0)
	assert_bool(altar.is_used()).is_true()             # 照样一次性
	assert_bool(altar.choose(0)).is_false()


func test_elite_branch_requires_positive_pct() -> void:
	# 边界：pct<=0（无因子）不触发；>0 即触发（同 elite_extra_copies 口径）
	var applied: Array = []
	var elite_calls: Array = []
	RunState.mods = {"elite_bonus_pct": 0}
	var altar := _make_altar(applied, elite_calls, 7)
	add_child(altar)
	altar.interact(null)
	assert_int(elite_calls.size()).is_equal(0)
	assert_int(altar.offerings().size()).is_equal(3)

	RunState.mods = {"elite_bonus_pct": 1}
	var applied2: Array = []
	var elite_calls2: Array = []
	var altar2 := _make_altar(applied2, elite_calls2, 7)
	add_child(altar2)
	altar2.interact(null)
	assert_int(elite_calls2.size()).is_equal(1)


# ---------------------------------------------------------------- 5) 场景集成

func test_scene_altar_buff_branch_end_to_end() -> void:
	# 普通局（零因子）：进房 → 交互 → 三选一 → 选卡落地（BuffManager.pick +
	# RunState.add_buff 记账 + apply_to_player 玩家 meta）
	var seed_hit := _seed_with_altar(SEED)
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(_chain(["combat"]))
	var buffs := fs.buffs_manager as BuffManager
	assert_bool(fs.enter_room(1)).is_true()
	var altar := _altar_in(fs, 1)
	assert_object(altar).is_not_null()
	altar.interact(fs.player_node())
	assert_int(altar.offerings().size()).is_equal(3)
	assert_bool(altar.choose(0)).is_true()
	assert_int(buffs.picked.size()).is_equal(1)
	assert_int(RunState.buffs.size()).is_equal(1)
	assert_str(String(RunState.buffs[0])).is_equal(String(buffs.picked[0]))


func test_scene_elite_surge_altar_spawns_uncounted_elite_mid_fight() -> void:
	# 试炼局 elite_surge：战斗中交互 → 追加 1 精英嘉宾（真实行+楼层词缀），不计波次
	# （同召唤体口径：清房判定不被它拖住），但击杀照常入 RunState.kills
	RunState.mods = {"elite_bonus_pct": 100}
	var seed_hit := _seed_with_altar(SEED)
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(fs.enter_room(1)).is_true()
	var before := _alive_enemies(room)
	var kills_before := RunState.kills
	var altar := _altar_in(fs, 1)
	altar.interact(fs.player_node())
	assert_int(_alive_enemies(room)).is_equal(before + 1)
	var surge := room.enemies[room.enemies.size() - 1]
	assert_bool(surge.counts_for_wave).is_false()      # 波次外嘉宾（不拖清房判定）
	surge.take_hit({"amount": 9999, "is_crit": false, "element": 0,
		"from": surge.global_position})
	assert_int(RunState.kills).is_equal(kills_before + 1)
	# 清房判定不被祭坛精英拖住：清掉原波 → 波 2 照常推进
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	assert_bool(fs.flow.is_locked()).is_true()         # 波 1 清 → 波 2（祭坛精英已不计）


func test_scene_elite_surge_altar_cleared_room_spawn_no_relock() -> void:
	# 已清战斗房交互：追加精英不计波次、不回锁（bot 冒烟走的正是此路径）
	RunState.mods = {"elite_bonus_pct": 100}
	var seed_hit := _seed_with_altar(SEED)
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)   # 波 2 补刷
	_kill_all(room)
	await _await_until(func() -> bool: return not fs.flow.is_locked())
	assert_bool(fs.flow.cleared.has(1)).is_true()
	var altar := _altar_in(fs, 1)
	assert_bool(altar.can_interact(fs.player_node())).is_true()
	altar.interact(fs.player_node())
	assert_int(_alive_enemies(room)).is_equal(1)
	assert_bool(fs.flow.is_locked()).is_false()        # 不回锁
	assert_bool(fs.flow.cleared.has(1)).is_true()


func test_scene_no_altar_without_pending_even_in_trial() -> void:
	# 未命中种子 + 试炼因子：无祭坛即无分支（掷签是生成唯一入口）
	RunState.mods = {"elite_bonus_pct": 100}
	var build := _chain(["combat"])
	var miss := -1
	for s in range(SEED, SEED + 200):
		RngSvc.setup_run(s)
		var rng := RngSvc.stream(1, "altar")
		if rng.randf() >= 0.15:
			miss = s
			break
	RngSvc.setup_run(miss)
	var fs := _make_scene(build)
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(_altar_in(fs, 1)).is_null()
	assert_int(_alive_enemies(fs.room_node(1))).is_equal(3)   # 波次零改动


# ---------------------------------------------------------------- 互斥规则接线

func test_room_facility_kinds_scanned_for_exclusion() -> void:
	# FloorScene._room_facility_kinds：房内既有设施 class → kind 映射（互斥 present 侧）
	RngSvc.setup_run(_seed_with_altar(SEED))
	var fs := _make_scene(_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_array(fs._room_facility_kinds(room)).is_empty()   # 战斗房无设施
	var shrine := Shrine.new().setup("zhanshen", {})
	room.add_child(shrine)
	var shop: Shop = (load("res://core/interact/shop.tscn") as PackedScene).instantiate() as Shop
	room.add_child(shop)
	var kinds := fs._room_facility_kinds(room)
	assert_array(kinds).contains("shrine")
	assert_array(kinds).contains("shop")
	assert_int(kinds.size()).is_equal(2)
	# 互斥落地：present 命中 excludes → roll_pending 拒绝（Altar 侧已钉，此处钉映射对齐）
	assert_bool(Altar.roll_pending(0.01, 0.15,
		["shop", "forge", "shrine", "drink", "event"], kinds)).is_false()
