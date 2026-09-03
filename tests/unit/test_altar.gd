class_name TestAltar
extends GdUnitTestSuite
## m4-c4 增益祭坛设施 + elite_surge 试炼分支（m3-fix1 §残留半边收口）；
## m4p-w2c（W2-c1）时序/上限按 GDD §13.1 勘误：
## 「战斗房清完后 15% 概率刷增益祭坛（本层至多 2 次）」——
## 1) 生成判定纯函数：15% 掷签语义 + altar_excludes 互斥 fail-closed（chance<=0 恒不生成）
## 2) 楼层掷签：combat 房型 + 模板 altar_chance=0.15 数据驱动、同 seed 确定性、
##    非战斗房型（elite/miniboss/boss/shop…）零生成、200 种子分布带（二项 ±3σ）、
##    每层掷签序列纯函数（达上限 2 即停掷）+ 200 种子截断分布带 + 场景级 6 房连中截停
## 3) 交互·增益分支（非试炼局）：三选一全部来自 GameDB.buffs 既有池（零新数值键）、
##    选卡经 apply 回调落地、一次性、choose 越界拒绝
## 4) 交互·elite_surge 分支（试炼局）：TrialMods.altar_elite_surge() 单点读
##    RunState.mods（elite_bonus_pct），交互改为追加 1 精英（楼层真实嘉宾行+词缀），
##    spawn 不计波次（同召唤体口径）；已清房 spawn 不回锁
## 5) 零漂移：无因子/无关因子不触发精英分支；普通局祭坛照常三选一
## 6) 时序（W2-c1）：掷签命中只记 pending，实体改「清房拍」搭建——首进开战（战斗
##    锁定期）祭坛不存在（can_interact 门控天然满足），清房后才可交互

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

func test_scene_altar_built_on_room_clear_not_on_entry() -> void:
	# W2-c1 时序：掷签仍在建层（同 seed 确定性），实体改「清房拍」搭建——首进开战
	# （战斗锁定期）祭坛不存在（can_interact 门控天然满足），清房后祭坛在房内可交互。
	var seed_hit := _seed_with_altar(SEED)
	assert_int(seed_hit).is_greater(0)
	var build := _chain(["combat"])
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(build)
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(room.altar_pending).is_true()
	assert_object(_altar_in(fs, 1)).is_null()          # 掷签只记 pending
	assert_object(_altar_in(fs, 0)).is_null()          # start 房恒无祭坛
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(_altar_in(fs, 1)).is_null()          # 首进开战不建祭坛（战后时序）
	assert_bool(room.facility_built).is_false()
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	_kill_all(room)
	await _await_until(func() -> bool: return not fs.flow.is_locked())
	var altar := _altar_in(fs, 1)
	assert_object(altar).is_not_null()                 # 清房拍搭建
	assert_bool(room.facility_built).is_true()
	assert_str(altar.action_label).contains("祭坛")
	assert_bool(altar.can_interact(fs.player_node())).is_true()


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


# ---------------------------------------------------------------- 2b) 每层上限 2（W2-c1）

func _rigged_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _true_count(pending: Array[bool]) -> int:
	var n := 0
	for p in pending:
		if p:
			n += 1
	return int(n)


func test_altar_per_floor_cap_series_pure() -> void:
	# 每层至多 2（GDD §13.1「本层至多 2 次」）：掷签序列纯函数——连中 3+ 也只取前 2，
	# 达上限即停（后续房不消费签、恒不生成）；上限内逐房命中语义不变（roll < chance）。
	var all_hit := FloorScene.roll_altar_pending_series(
		[1.0, 1.0, 1.0, 1.0, 1.0, 1.0], _rigged_rng(11))
	assert_int(all_hit.size()).is_equal(6)
	assert_int(_true_count(all_hit)).is_equal(2)       # 全命中序列 → 恰 2 座
	assert_bool(all_hit[0]).is_true()
	assert_bool(all_hit[1]).is_true()
	assert_bool(all_hit[2]).is_false()                 # 第 3 座起截停
	assert_bool(all_hit[5]).is_false()
	var two := FloorScene.roll_altar_pending_series([1.0, 0.0], _rigged_rng(3))
	assert_bool(two[0]).is_true()                      # 上限内 = 原逐房判定
	assert_bool(two[1]).is_false()
	var none := FloorScene.roll_altar_pending_series(
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], _rigged_rng(3))
	assert_int(_true_count(none)).is_equal(0)          # 零命中路径不受上限影响


func test_altar_per_floor_band_two_hundred_seeds_cap_two() -> void:
	# 200 种子分布带（6 战斗房 × p=0.15，掷签流同生产口径 RngSvc.stream(1,"altar")）：
	# 每种子命中数 ≤2（GDD「本层至多 2 次」断言），总量均值落截断二项 ±3σ 带。
	# X~Bin(6,0.15)：P0=.3772 / P1=.3993 / P≥2=.2235；Y=min(X,2) 期望 0.8464/种子
	# → 200 种子 μ≈169.3、σ≈10.7，带 [137, 202]。
	var total_hits := 0
	var chances: Array[float] = [0.15, 0.15, 0.15, 0.15, 0.15, 0.15]
	for s in range(6100, 6300):
		RngSvc.setup_run(s)
		var pending := FloorScene.roll_altar_pending_series(chances, RngSvc.stream(1, "altar"))
		var hits := _true_count(pending)
		assert_int(hits).is_less_equal(2)              # 每层至多 2（截断语义）
		total_hits += hits
	assert_int(total_hits).is_between(137, 202)


func test_scene_altar_per_floor_cap_six_room_chain() -> void:
	# 场景级接线：6 连战斗房、掷签原始连中 ≥3 的种子 → 实际恰 2 间命中（层上限截停）。
	var seed_multi := -1
	for s in range(6100, 6400):
		RngSvc.setup_run(s)
		var rng := RngSvc.stream(1, "altar")
		var raw_hits := 0
		for i in 6:
			if rng.randf() < 0.15:
				raw_hits += 1
		if raw_hits >= 3:
			seed_multi = s
			break
	assert_int(seed_multi).is_greater(0)
	var types: Array = []
	for i in 6:
		types.append("combat")
	RngSvc.setup_run(seed_multi)
	var fs := _make_scene(_chain(types))
	var pending_rooms: Array[int] = []
	for id in range(1, 7):
		if (fs.room_node(id) as FloorScene.FloorRoom).altar_pending:
			pending_rooms.append(id)
	assert_int(pending_rooms.size()).is_equal(2)       # 原始 ≥3 连中 → 恰 2（GDD 上限）


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
	# 普通局（零因子）：清房 → 交互 → 三选一 → 选卡落地（BuffManager.pick +
	# RunState.add_buff 记账 + apply_to_player 玩家 meta）。W2-c1 时序：先清房祭坛才存在。
	var seed_hit := _seed_with_altar(SEED)
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(_chain(["combat"]))
	var buffs := fs.buffs_manager as BuffManager
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(fs.enter_room(1)).is_true()
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	_kill_all(room)
	await _await_until(func() -> bool: return not fs.flow.is_locked())
	var altar := _altar_in(fs, 1)
	assert_object(altar).is_not_null()
	altar.interact(fs.player_node())
	assert_int(altar.offerings().size()).is_equal(3)
	assert_bool(altar.choose(0)).is_true()
	assert_int(buffs.picked.size()).is_equal(1)
	assert_int(RunState.buffs.size()).is_equal(1)
	assert_str(String(RunState.buffs[0])).is_equal(String(buffs.picked[0]))


func test_scene_elite_surge_altar_post_clear_interact_only() -> void:
	# W2-c1 时序 + elite_surge 语义不变：战斗中祭坛不存在（旧「战斗中交互追加精英」
	# 随清房时序退役）；清房后交互追加 1 精英嘉宾（真实行+楼层词缀），不计波次
	# （同召唤体口径：清房判定不被它拖住），但击杀照常入 RunState.kills
	RunState.mods = {"elite_bonus_pct": 100}
	var seed_hit := _seed_with_altar(SEED)
	RngSvc.setup_run(seed_hit)
	var fs := _make_scene(_chain(["combat"]))
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(_altar_in(fs, 1)).is_null()          # 战斗锁定期无祭坛（新时序钉）
	_kill_all(room)
	await _await_until(func() -> bool: return _alive_enemies(room) == 3)
	_kill_all(room)
	await _await_until(func() -> bool: return not fs.flow.is_locked())
	var altar := _altar_in(fs, 1)
	assert_object(altar).is_not_null()                 # 清房拍搭建
	var before := _alive_enemies(room)
	altar.interact(fs.player_node())
	assert_int(_alive_enemies(room)).is_equal(before + 1)
	var surge := room.enemies[room.enemies.size() - 1]
	assert_bool(surge.counts_for_wave).is_false()      # 波次外嘉宾（不拖清房判定）
	var kills_before_surge := RunState.kills
	surge.take_hit({"amount": 9999, "is_crit": false, "element": 0,
		"from": surge.global_position})
	assert_int(RunState.kills).is_equal(kills_before_surge + 1)   # 击杀照常入账
	# 追加精英不回锁已清房
	assert_bool(fs.flow.is_locked()).is_false()
	assert_bool(fs.flow.cleared.has(1)).is_true()


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
