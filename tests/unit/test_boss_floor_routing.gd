class_name TestBossFloorRouting
extends GdUnitTestSuite
## M2-T36（裁定⑳/㉑ 补充卡）：Boss 楼层路由接线契约测试。
## 1) 楼层×Boss 池路由（附录 E 归属）：A1 恒 vine_colossus；A2 = gem_queen/prism_golem/
##    frost_widow 池按层确定性取一（boss_override 定向接缝）；A3 恒 magma_tyrant；
##    先知仍走隐藏门（本卡不触碰）。波次标记恒 vine_colossus（RoomFlow 计数口径不变），
##    路由发生在真实嘉宾行替换（_spawn_real_guest）。
## 2) T14 移交接线：HivePillar/Crystal 顶层挂载（出生坐标 = 世界坐标，Boss 位移不拖动）
##    + register_body/combat_radius（玩家弹可拆柱 → 晶棱 regen 博弈环闭环）。
## 3) T16 移交机制化：冰晶牢笼 restraint 化——环内玩家越环按缺口弧段判定（缺口可通行，
##    其余弧段夹回环缘）；预警期已越环者不禁锢；3s 到期自由。
## 4) 裁定㉑：视野灾厄复合进既有 biome_fx（A2 层单 CanvasModulate；0.65 乘基色/光圈），
##    房清还原；无生态组件层保持单实例路径（test_calamity 既有契约）。

const SEED := 20260828
const SPAN_PX := 416.0
const FRAME := 30000   # 注入帧基准（同 test_boss_m2_wave1）
const BOUNDS := Rect2(Vector2(-228, -119), Vector2(456, 238))   # M0 战斗房内域
const ROOM_LOCAL := Vector2(900.0, 400.0)   # 柱接线测试：Boss 挂在非零房间局部坐标

const QUEEN_ROW := {
	"id": "gem_queen", "name": "宝石蜂后", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/gem_queen.gd",
	"hp": 800, "contact_dmg": 4, "speed": 40, "walk_speed": 40,
	"radius": 14.0, "bullet_dmg": 3, "bullet_speed": 110,
	"bullet_life_seconds": 2.5, "bullet_radius": 3.0,
	"phases": [1.0, 0.6, 0.3],
}
const GOLEM_ROW := {
	"id": "prism_golem", "name": "晶棱魔像", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/prism_golem.gd",
	"hp": 1800, "contact_dmg": 6, "speed": 20, "walk_speed": 20,
	"radius": 16.0, "bullet_dmg": 5, "bullet_speed": 100,
	"bullet_life_seconds": 2.0, "bullet_radius": 4.0,
	"phases": [1.0, 0.6, 0.3],
}
const FROST_ROW := {
	"id": "frost_widow", "name": "寒渊蛛母", "archetype": "boss",
	"boss_script": "res://core/enemies/bosses/frost_widow.gd",
	"hp": 1800, "contact_dmg": 5, "speed": 20, "walk_speed": 20,
	"radius": 16.0, "bullet_dmg": 5, "bullet_speed": 100,
	"bullet_life_seconds": 2.0, "bullet_radius": 4.0,
	"phases": [1.0, 0.6, 0.3],
}


class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


var _fs: FloorScene = null
var _player: Player = null


# ---------------------------------------------------------------- 构建体替身

func _room(id: int, type: String, grid: Vector2i, next: Array, template := "") -> Dictionary:
	var tid := template
	if tid.is_empty():
		tid = "combat_a1_01"
		if type == "start":
			tid = "start_a1"
		elif type == "boss":
			tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


## 手工链式构建体：start(0) → types[0](1) → …（横向 E 走廊）；templates 可逐房覆盖。
func _typed_chain(types: Array, templates: Array = []) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var grid := Vector2i(i + 1, 0)
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		var tpl := ""
		if i < templates.size():
			tpl = String(templates[i])
		rooms[id] = _room(id, String(types[i]), grid, nxt, tpl)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


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


func _find_enemy(room: FloorScene.FloorRoom, row_id: String) -> EnemyBase:
	for e in room.enemies:
		if String(e.row.get("id", "")) == row_id:
			return e
	return null


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		e.take_hit({"amount": 999999, "is_crit": false, "element": 0,
			"from": e.global_position})


func _alive_enemies(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE,
		"from": Vector2.ZERO}


# ================================================================ 1) 楼层×Boss 池路由

func test_boss_pool_and_static_floor_rows() -> void:
	# 附录 E 归属：A1 vine_colossus / A2 三选一池 / A3 magma_tyrant
	assert_array(FloorScene.BOSS_POOL).contains(
		["gem_queen", "prism_golem", "frost_widow"])
	assert_int(FloorScene.BOSS_POOL.size()).is_equal(3)
	assert_str(FloorScene.boss_row_for_floor(1)).is_equal("vine_colossus")
	assert_str(FloorScene.boss_row_for_floor(3)).is_equal("magma_tyrant")
	# 表外楼层 clamp 到界（同 miniboss_hp_for_floor 习语）
	assert_str(FloorScene.boss_row_for_floor(0)).is_equal("vine_colossus")
	assert_str(FloorScene.boss_row_for_floor(7)).is_equal("magma_tyrant")
	# A2 池按序取（roll 决定池内下标；池字典序）
	assert_str(FloorScene.boss_row_for_floor(2, 0)).is_equal("frost_widow")
	assert_str(FloorScene.boss_row_for_floor(2, 1)).is_equal("gem_queen")
	assert_str(FloorScene.boss_row_for_floor(2, 2)).is_equal("prism_golem")


func test_boss_row_draw_deterministic_per_floor() -> void:
	# 同种子同层恒同体（RngSvc.stream(floor_idx,"boss") 无状态派生）；
	# A1/A3 静态映射不掷签
	var fs1 := _make_scene(_typed_chain(["combat"]), 2)
	var fs2 := _make_scene(_typed_chain(["combat"]), 2)
	assert_array(FloorScene.BOSS_POOL).contains([fs1.boss_row()])
	assert_str(fs1.boss_row()).is_equal(fs2.boss_row())
	var fs3 := _make_scene(_typed_chain(["combat"]), 1)
	assert_str(fs3.boss_row()).is_equal("vine_colossus")
	var fs4 := _make_scene(_typed_chain(["combat"]), 3)
	assert_str(fs4.boss_row()).is_equal("magma_tyrant")


func test_boss_override_seam_wins_over_pool_draw() -> void:
	# 测试/宿主定向接缝（同 miniboss_override 习语）：非法值响亮回落池抽取
	var fs := _make_scene(_typed_chain(["combat"]), 2)
	fs.boss_override = "gem_queen"
	fs._pick_boss_row()
	assert_str(fs.boss_row()).is_equal("gem_queen")
	fs.boss_override = "not_a_boss"
	fs._pick_boss_row()
	assert_array(FloorScene.BOSS_POOL).contains([fs.boss_row()])


func test_scene_a1_boss_room_spawns_vine_colossus() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 1)
	assert_bool(fs.enter_room(1)).is_true()
	var boss := _find_enemy(fs.room_node(1), "vine_colossus")
	assert_object(boss).is_not_null()
	if boss != null:
		assert_int(boss.hp).is_equal(800)


func test_scene_a2_boss_room_spawns_pool_row_with_own_script() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 2)
	assert_bool(fs.enter_room(1)).is_true()
	var room: FloorScene.FloorRoom = fs.room_node(1)
	assert_int(_alive_enemies(room)).is_equal(1)
	var boss: EnemyBase = room.enemies[0]
	assert_array(FloorScene.BOSS_POOL).contains([String(boss.row["id"])])
	var script: Script = boss.get_script()
	assert_bool(script != null and script.resource_path
		.ends_with("%s.gd" % String(boss.row["id"]))).is_true()
	# 波次标记口径不变：RoomFlow 以 vine_colossus 计数（恒单波单只）
	assert_str(String(boss.row.get("wave_id", ""))).is_equal("vine_colossus")


func test_scene_a3_boss_room_spawns_magma_tyrant() -> void:
	var fs := _make_scene(_typed_chain(["boss"]), 3)
	assert_bool(fs.enter_room(1)).is_true()
	var boss := _find_enemy(fs.room_node(1), "magma_tyrant")
	assert_object(boss).is_not_null()
	if boss != null:
		assert_int(boss.hp).is_equal(3200)


func test_boss_wave_marker_invariant_for_routing() -> void:
	# 波次标记恒 vine_colossus：路由发生在真实嘉宾行替换（RoomFlow 计数/占位回归对照不变）
	assert_array(FloorScene.waves_for(9, "boss")["waves"][0]).is_equal(["vine_colossus"])


# ================================================================ 2) T14 柱接线

## 房间内 Boss 实体（in-tree、非零房间局部坐标、物理层冻结）：挂独立 CombatSystem
## 供 register_body 命中链断言。返回 [boss, combat]。
func _boss_in_tree(boss: EnemyBase, row: Dictionary) -> Array:
	# 返回类型显式 Array（推断自 Variant 的 := 会按工程纪律判错）
	add_child(boss)
	boss.set_physics_process(false)          # 冻结物理表现层（测试直驱 brain）
	boss.position = ROOM_LOCAL               # 模拟房间局部非零偏移
	boss._test_init(row.duplicate(true))
	boss.brain_pos = boss.global_position    # in-tree：脑位 == 世界位（setup 同步口径）
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs: CombatSystem = auto_free(CombatSystem.new(root, RandomNumberGenerator.new()))
	root.add_child(cs)
	boss.combat = cs
	return [boss, cs]


func _engage_ready(b: EnemyBase) -> int:
	b.on_player_seen(FRAME)
	for f in range(FRAME + 1, FRAME + 25):
		b.brain_tick(f)
	return FRAME + 25


func _drive_to_move(b: EnemyBase, move: String, f: int, limit := 4000) -> int:
	for _i in range(limit):
		if b.get("_move") == move:
			return b.get("_move_start")
		b.brain_tick(f)
		f += 1
	assert_str(String(b.get("_move"))).is_equal(move)
	return -1


func _fire_player_bullet(cs: CombatSystem, at: Vector2, damage: int) -> void:
	cs.spawn_projectile({"pos": at, "vel": Vector2.ZERO, "damage": damage,
		"faction": Projectile.Faction.PLAYER, "element": 0, "pierce": 0, "bounce": 0,
		"life_seconds": 2.0, "radius": 3.0,
		"source_type": "projectile", "source_id": "t36", "source_name": "测试",
		"attack_name": "测试弹"})


func _advance_combat(cs: CombatSystem, frames: int) -> void:
	var base := Engine.get_physics_frames()
	for i in frames:
		cs._physics_process(base + i)


func test_queen_hive_pillars_world_position_and_destructible() -> void:
	# T14 移交：HivePillar 出生接线——顶层挂载（出生坐标 = 世界坐标，Boss 位移不拖动）
	# + register_body/combat_radius（玩家弹可拆柱）
	var pair := _boss_in_tree(GemQueen.new(), QUEEN_ROW)
	var b: GemQueen = pair[0]
	var cs: CombatSystem = pair[1]
	var f := _engage_ready(b)
	b._take_hit_at(_ctx(320), f)                     # 800-320=480 → P1
	var ms: int = _drive_to_move(b, "hive", f)
	for i in range(GemQueen.HIVE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	var pillars: Array = b._pillars
	assert_int(pillars.size()).is_equal(2)
	var expected := [b.brain_pos + Vector2(GemQueen.HIVE_OFFSET_PX, 0.0),
		b.brain_pos - Vector2(GemQueen.HIVE_OFFSET_PX, 0.0)]
	for i in pillars.size():
		var p: Node2D = pillars[i]
		# 出生坐标 = 脑位 ±48px（世界坐标；Boss 房间局部偏移不被二次叠加）
		assert_vector(p.global_position).is_equal_approx(expected[i], Vector2(0.5, 0.5))
		assert_float(p.call("combat_radius")).is_greater(0.0)   # 战斗体半径契约
	# 玩家弹拆柱：register_body 命中链 take_hit → hp0 → 退场出列
	var pillar: Node2D = pillars[0]
	_fire_player_bullet(cs, pillar.global_position, 25)
	_advance_combat(cs, 3)
	assert_int(pillars[0].hp).is_equal(0)            # 20 hp 一发 25 拆除
	assert_int(b._alive_pillars()).is_equal(1)       # 失效柱出列
	# 柱亡后战斗体注销：同位补弹不再被吸收（弹继续飞行 = 无可命中体、无悬挂体崩溃）
	_fire_player_bullet(cs, pillar.global_position, 25)
	_advance_combat(cs, 3)
	assert_int(cs.active_count()).is_equal(1)


func test_golem_crystal_world_position_and_regen_loop_closes() -> void:
	# T14 移交：Crystal 同接线（出生坐标 = 脑位 ±80px 世界坐标）；拆柱 → P1 regen
	# 回归招式表（拆柱→再生博弈环闭环）
	var pair := _boss_in_tree(PrismGolem.new(), GOLEM_ROW)
	var b: PrismGolem = pair[0]
	var cs: CombatSystem = pair[1]
	var f := _engage_ready(b)                        # ENGAGE 转换拍自带 2 根晶柱
	assert_int(b._alive_crystals()).is_equal(2)
	var crystals: Array = b._crystals
	var expected := [b.brain_pos + Vector2(PrismGolem.CRYSTAL_OFFSET_PX, 0.0),
		b.brain_pos - Vector2(PrismGolem.CRYSTAL_OFFSET_PX, 0.0)]
	for i in crystals.size():
		var c: Node2D = crystals[i]
		assert_vector(c.global_position).is_equal_approx(expected[i], Vector2(0.5, 0.5))
		assert_float(c.call("combat_radius")).is_greater(0.0)
	b._take_hit_at(_ctx(720), f + 200)               # 1800-720=1080 → P1
	assert_bool(b._move_list().has("regen")).is_false()   # 晶柱齐全时无 regen
	# 玩家弹拆一根晶柱 → regen 入表（博弈环闭环）
	var crystal: Node2D = crystals[0]
	_fire_player_bullet(cs, crystal.global_position, 25)
	_advance_combat(cs, 3)
	assert_int(crystals[0].hp).is_equal(0)
	assert_int(b._alive_crystals()).is_equal(1)
	assert_bool(b._move_list().has("regen")).is_true()


# ================================================================ 3) T16 牢笼机制化

func _widow() -> FrostWidow:
	var b: FrostWidow = auto_free(FrostWidow.new())
	b._test_init(FROST_ROW.duplicate(true))
	return b


func _gap_angle(b: FrostWidow) -> float:
	return TAU * float(b._cage_gap_slot) / float(FrostWidow.CAGE_SLOTS)


## 驱动至冰晶牢笼落地完成（玩家居环心 → 禁锢激活）。返回 [boss, spy, 落地末拍]。
func _cage_landed() -> Array:
	# 返回类型显式 Array（推断自 Variant 的 := 会按工程纪律判错）
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)          # 1800-1260=540 → P2
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	assert_int(b._cage_pillars.size()).is_equal(FrostWidow.CAGE_PILLAR_COUNT)
	return [b, spy, ms + FrostWidow.CAGE_WINDUP_TICKS]


func test_widow_cage_blocks_exit_except_gap_arc() -> void:
	# 遮挡几何断言：环内玩家向非缺口弧段越环 → 夹回环缘（方向保持）；缺口弧段放行
	var trio := _cage_landed()
	var b: FrostWidow = trio[0]
	var spy: SpyPlayer = trio[1]
	var land_end: int = trio[2]
	var gap_ang := _gap_angle(b)
	var blocked_ang := wrapf(gap_ang + PI, 0.0, TAU)          # 对侧：必有柱弧段
	# 环内玩家越环（blocked 方向）→ 夹回环缘 r64
	spy.brain_pos = b._cage_center \
		+ Vector2.from_angle(blocked_ang) * (FrostWidow.CAGE_RING_RADIUS_PX + 26.0)
	b.brain_tick(land_end + 1)
	assert_float(spy.brain_pos.distance_to(b._cage_center)) \
		.is_equal_approx(FrostWidow.CAGE_RING_RADIUS_PX, 0.5)
	assert_vector(spy.brain_pos.normalized()).is_equal_approx(
		Vector2.from_angle(blocked_ang), Vector2(0.01, 0.01))
	# 缺口弧段越环 → 放行（合法逃脱，禁锢解除）
	spy.brain_pos = b._cage_center
	b.brain_tick(land_end + 2)
	spy.brain_pos = b._cage_center \
		+ Vector2.from_angle(gap_ang) * (FrostWidow.CAGE_RING_RADIUS_PX + 26.0)
	b.brain_tick(land_end + 3)
	assert_float(spy.brain_pos.distance_to(b._cage_center)) \
		.is_equal_approx(FrostWidow.CAGE_RING_RADIUS_PX + 26.0, 0.5)


func test_widow_cage_escape_cancels_confinement() -> void:
	# 缺口逃脱后禁锢解除：环外（blocked 方向）不再被夹回
	var trio := _cage_landed()
	var b: FrostWidow = trio[0]
	var spy: SpyPlayer = trio[1]
	var land_end: int = trio[2]
	var gap_ang := _gap_angle(b)
	# 先从缺口合法逃脱
	spy.brain_pos = b._cage_center \
		+ Vector2.from_angle(gap_ang) * (FrostWidow.CAGE_RING_RADIUS_PX + 26.0)
	b.brain_tick(land_end + 1)
	# 再横移到 blocked 方向环外 → 不回拉（已不在笼内）
	var outside := b._cage_center \
		+ Vector2.from_angle(wrapf(gap_ang + PI, 0.0, TAU)) \
		* (FrostWidow.CAGE_RING_RADIUS_PX + 40.0)
	spy.brain_pos = outside
	b.brain_tick(land_end + 2)
	assert_vector(spy.brain_pos).is_equal_approx(outside, Vector2(0.01, 0.01))


func test_widow_cage_no_confinement_when_outside_at_land() -> void:
	# 预警期冲出环外者落地即不在笼内：不禁锢（不回拉）
	var b := _widow()
	b.combat_bounds = BOUNDS
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2.ZERO
	b.player_ref = spy
	b._take_hit_at(_ctx(1260), FRAME - 100)
	var f := _engage_ready(b)
	var ms: int = _drive_to_move(b, "cage", f)
	var blocked_ang := wrapf(_gap_angle(b) + PI, 0.0, TAU)
	var outside := Vector2.from_angle(blocked_ang) \
		* (FrostWidow.CAGE_RING_RADIUS_PX + 60.0)
	spy.brain_pos = outside                       # 预警期冲出
	for i in range(FrostWidow.CAGE_WINDUP_TICKS):
		b.brain_tick(ms + 1 + i)
	b.brain_tick(ms + FrostWidow.CAGE_WINDUP_TICKS + 1)
	assert_vector(spy.brain_pos).is_equal_approx(outside, Vector2(0.01, 0.01))


func test_widow_cage_expiry_frees_player() -> void:
	# 3s 到期清场 → 禁锢随之解除
	var trio := _cage_landed()
	var b: FrostWidow = trio[0]
	var spy: SpyPlayer = trio[1]
	var land_end: int = trio[2]
	var blocked_ang := wrapf(_gap_angle(b) + PI, 0.0, TAU)
	for i in range(FrostWidow.CAGE_PILLAR_LIFE_TICKS):
		b.brain_tick(land_end + 1 + i)
	assert_int(b._cage_pillars.size()).is_equal(FrostWidow.CAGE_PILLAR_COUNT)  # until 拍仍在
	b.brain_tick(land_end + FrostWidow.CAGE_PILLAR_LIFE_TICKS + 1)             # until+1 清场
	assert_int(b._cage_pillars.size()).is_equal(0)
	var outside := Vector2.from_angle(blocked_ang) \
		* (FrostWidow.CAGE_RING_RADIUS_PX + 26.0)
	spy.brain_pos = outside
	b.brain_tick(land_end + FrostWidow.CAGE_PILLAR_LIFE_TICKS + 2)
	assert_vector(spy.brain_pos).is_equal_approx(outside, Vector2(0.01, 0.01))


# ================================================================ 4) 视野灾厄复合（裁定㉑）

func _count_canvas_modulates(root: Node) -> int:
	var n := 0
	if root is CanvasModulate:
		n += 1
	for child in root.get_children():
		n += _count_canvas_modulates(child)
	return n


func test_vision_calamity_compounds_into_biome_fx() -> void:
	# A2 层（模板 biome=crystal 已挂生态暗视野）挑战房选「视野-35%」：
	# 复合进既有 biome_fx（单 CanvasModulate），不再二次实例
	var fs := _make_scene(
		_typed_chain(["combat", "combat"], ["combat_a2_01", ""]), 1, 1)
	assert_bool(fs.enter_room(1)).is_true()
	assert_object(fs.biome_fx).is_not_null()      # crystal 模板已挂生态暗视野
	var base_color: Color = fs.biome_fx.canvas_modulate.color
	fs.choose_calamity("vision")
	assert_object(fs.biome_fx).is_not_null()
	assert_bool(fs.calamity_fx == null).is_true() # 裁定㉑：不二次实例
	assert_int(_count_canvas_modulates(fs)).is_equal(1)
	# 复合：基色 ×0.65 + 光圈/剪影口径同比缩径
	var cm: CanvasModulate = fs.biome_fx.canvas_modulate
	assert_vector(Vector3(cm.color.r, cm.color.g, cm.color.b)).is_equal_approx(
		Vector3(base_color.r * 0.65, base_color.g * 0.65, base_color.b * 0.65),
		Vector3(0.001, 0.001, 0.001))
	var base_scale := BiomeFx.LIGHT_RADIUS_PX * 2.0 / float(BiomeFx.LIGHT_TEXTURE_PX)
	assert_float(fs.biome_fx.light.texture_scale).is_equal_approx(base_scale * 0.65, 0.001)
	assert_float(fs.biome_fx.light_radius_px) \
		.is_equal_approx(BiomeFx.LIGHT_RADIUS_PX * 0.65, 0.001)
	# 房清还原：复合系数复位、生态组件本体保留
	var room: FloorScene.FloorRoom = fs.room_node(1)
	for _w in 3:
		_kill_all(room)
		await _await_until(func() -> bool: return _alive_enemies(room) == 3 \
			or fs.flow.cleared.has(1))
	await _await_until(func() -> bool: return fs.flow.cleared.has(1))
	assert_bool(is_instance_valid(fs.biome_fx)).is_true()
	if is_instance_valid(fs.biome_fx):
		var restored: CanvasModulate = fs.biome_fx.canvas_modulate
		assert_vector(Vector3(restored.color.r, restored.color.g, restored.color.b)) \
			.is_equal_approx(Vector3(base_color.r, base_color.g, base_color.b),
				Vector3(0.001, 0.001, 0.001))
		assert_float(fs.biome_fx.light_radius_px) \
			.is_equal_approx(BiomeFx.LIGHT_RADIUS_PX, 0.001)
