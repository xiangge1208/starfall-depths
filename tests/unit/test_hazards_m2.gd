class_name TestHazardsM2
extends GdUnitTestSuite
## M2-T7：A2 地刺 + A1 藤蔓减速带/滚石（GDD §10 A1/A2 行）+ FloorScene 危险地块接线。
## 1) HazardSpikes（纯逻辑，无头）：周期 24t 预警 / 90t 伸出（伤害窗）/ 60t 缩回、
##    174t 回卷；伤害仅 OUT 相位且命中 zone；offset 错峰。
## 2) VineZone（IceZone 同款区域模式）：进入减速 40%（Player.incoming_slow 接缝，
##    2t 保持窗自然过期）；敌人无任何可被藤蔓写入的减速状态。
## 3) RollingRock（纯逻辑）：WAIT(interval) → WARN 30t（0.5s 预警线）→ ROLL
##    （200px/s 直线）→ 撞墙（出房内域）消失 → 回 WAIT；伤害仅 ROLL 相位圆接触。
## 4) FloorScene 接线：模板 hazards 字段 → vine/spikes/rock 实例化 + 帧驱动伤害；
##    pillar 陈设入 refraction_pillars 组（敌方激光折射源）。
## 注：spikes/rock 数据行当前不在 A1 模板库（GameDB hazards 白名单仅 vine，
## A2/A3 模板卡扩展 schema）——接线用注入 GameDB.rooms 测试行验证。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SPAN_PX := 416.0
const T7_TPL := "combat_a1_99"     # 测试注入模板（after_test 摘除）
const EPS := Vector2(0.001, 0.001)


# ---------------------------------------------------------------- 构建体替身（同 test_floor_scene 习语）

func _room(id: int, type: String, grid: Vector2i, next: Array, tid: String) -> Dictionary:
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * SPAN_PX,
	}


func _typed_chain(types: Array, tid: String = "combat_a1_01") -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1], "start_a1")}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), Vector2i(i + 1, 0), nxt, tid)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


func _inject_t7_template() -> void:
	GameDB.rooms[T7_TPL] = {
		"id": T7_TPL, "size": [22, 14], "doors": ["N", "S", "E", "W"],
		"spawn_points": [[5, 4], [16, 9]],
		"props": [],
		"hazards": [
			{"kind": "spikes", "grid": [11, 4]},
			{"kind": "rock", "grid": [2, 7], "side": "W", "interval_ticks": 60},
		],
	}


var _fs: FloorScene = null


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null
	GameDB.rooms.erase(T7_TPL)


# ---------------------------------------------------------------- HazardSpikes 纯逻辑

func test_spike_constants_match_card() -> void:
	assert_int(HazardSpikes.WARN_TICKS).is_equal(24)
	assert_int(HazardSpikes.OUT_TICKS).is_equal(90)
	assert_int(HazardSpikes.RETRACT_TICKS).is_equal(60)
	assert_int(HazardSpikes.DAMAGE).is_equal(4)
	assert_int(HazardSpikes.cycle_ticks()).is_equal(174)


func test_spike_phase_boundaries() -> void:
	assert_int(int(HazardSpikes.phase_at(0))).is_equal(int(HazardSpikes.Phase.WARN))
	assert_int(int(HazardSpikes.phase_at(23))).is_equal(int(HazardSpikes.Phase.WARN))
	assert_int(int(HazardSpikes.phase_at(24))).is_equal(int(HazardSpikes.Phase.OUT))
	assert_int(int(HazardSpikes.phase_at(113))).is_equal(int(HazardSpikes.Phase.OUT))
	assert_int(int(HazardSpikes.phase_at(114))).is_equal(int(HazardSpikes.Phase.RETRACT))
	assert_int(int(HazardSpikes.phase_at(173))).is_equal(int(HazardSpikes.Phase.RETRACT))
	assert_int(int(HazardSpikes.phase_at(174))).is_equal(int(HazardSpikes.Phase.WARN))   # 新周期
	assert_int(int(HazardSpikes.phase_at(-1))).is_equal(int(HazardSpikes.Phase.RETRACT))  # 负 t 回卷


func test_spike_damage_window_only_while_out() -> void:
	var s := HazardSpikes.new()
	s.setup(Rect2(100, 100, 16, 16))
	var on := Vector2(108, 108)
	for i in 24:                       # t=0..23 预警：全程无伤
		assert_int(s.damage_at(on)).is_equal(0)
		s.advance()
	assert_int(s.damage_at(on)).is_equal(HazardSpikes.DAMAGE)   # t=24 伸出即伤害窗
	for i in 89:                       # t=25..113 仍在窗内
		s.advance()
	assert_int(s.damage_at(on)).is_equal(HazardSpikes.DAMAGE)
	s.advance()                        # t=114 缩回
	assert_int(s.damage_at(on)).is_equal(0)


func test_spike_damage_requires_zone_hit() -> void:
	var s := HazardSpikes.new()
	s.setup(Rect2(100, 100, 16, 16), HazardSpikes.WARN_TICKS)   # offset → 直接进入 OUT
	var off := Vector2(200, 200)
	assert_int(s.damage_at(off)).is_equal(0)
	assert_int(s.damage_at(Vector2(100, 108))).is_equal(HazardSpikes.DAMAGE)   # 左边界内
	assert_int(s.damage_at(Vector2(115.9, 115.9))).is_equal(HazardSpikes.DAMAGE)
	assert_int(s.damage_at(Vector2(116.1, 108))).is_equal(0)                   # 右边界外


func test_spike_offset_staggers_phase() -> void:
	var s := HazardSpikes.new()
	s.setup(Rect2(), 100)             # 100 ∈ [24,114) → OUT
	assert_int(int(s.phase())).is_equal(int(HazardSpikes.Phase.OUT))
	var s2 := HazardSpikes.new()
	s2.setup(Rect2(), HazardSpikes.cycle_ticks())   # 整周期偏移 ≡ 无偏移
	assert_int(int(s2.phase())).is_equal(int(HazardSpikes.Phase.WARN))


# ---------------------------------------------------------------- VineZone 纯逻辑

func test_vine_slow_pct_constants() -> void:
	assert_float(VineZone.SLOW_PCT).is_equal(0.4)
	assert_float(VineZone.effective_slow_pct(true)).is_equal(0.4)
	assert_float(VineZone.effective_slow_pct(false)).is_equal(0.0)


func test_vine_zone_point_hit_and_miss() -> void:
	var vine := VineZone.new()
	vine.add_zone(Rect2(0, 0, 48, 48))
	assert_bool(vine.in_vine(Vector2(24, 24))).is_true()
	assert_bool(vine.in_vine(Vector2(100, 24))).is_false()
	vine.add_zone(Rect2(200, 0, 48, 48))
	assert_bool(vine.in_vine(Vector2(224, 24))).is_true()


func _player() -> Player:
	var p: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	auto_free(p)
	add_child(p)
	return p


func test_vine_tick_slows_player_and_expires_after_leave() -> void:
	var vine := VineZone.new()
	vine.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	assert_float(p.effective_move_speed(10)).is_equal(Player.MOVE_SPEED)   # 80
	vine.tick(p, 10)                       # 进入：写 0.4 + until 12
	assert_float(p.effective_move_speed(10)).is_equal(Player.MOVE_SPEED * 0.6)
	assert_float(p.effective_move_speed(11)).is_equal(Player.MOVE_SPEED * 0.6)
	p.position = Vector2(500, 500)
	vine.tick(p, 11)                       # 离开：不再刷新
	assert_float(p.effective_move_speed(11)).is_equal(Player.MOVE_SPEED * 0.6)   # 保持窗内
	assert_float(p.effective_move_speed(12)).is_equal(Player.MOVE_SPEED)         # 自然过期


func test_vine_tick_does_not_weaken_stronger_slow() -> void:
	var vine := VineZone.new()
	vine.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	p.incoming_slow_pct = 0.6             # 弹幕冰缓先中
	p.incoming_slow_until = 200
	vine.tick(p, 100)                     # 藤蔓不覆盖削弱（取 max）
	assert_float(p.incoming_slow_pct).is_equal(0.6)
	assert_int(p.incoming_slow_until).is_equal(200)


func test_vine_never_touches_enemies() -> void:
	# 敌人不受藤蔓影响（GDD §10 A1）：减速接缝只存在于 Player（incoming_slow 字段）
	var enemy := EnemyBase.new()
	auto_free(enemy)
	assert_bool(enemy.get("incoming_slow_pct") == null).is_true()
	var vine := VineZone.new()
	vine.add_zone(Rect2(0, 0, 64, 64))
	enemy.position = Vector2(32, 32)
	assert_bool(vine.in_vine(enemy.global_position)).is_true()   # 区域命中也不产生效果载体


# ---------------------------------------------------------------- RollingRock 纯逻辑

func _rock(interval := 60) -> RollingRock:
	var r := RollingRock.new()
	r.setup(Vector2(16, 96), Vector2.RIGHT, Rect2(16, 80, 320, 128), interval)
	return r


func test_rock_constants_match_card() -> void:
	assert_int(RollingRock.WARN_TICKS).is_equal(TimeConst.ticks(0.5))   # 0.5s 预警线
	assert_float(RollingRock.SPEED_PX).is_equal(200.0)
	assert_int(RollingRock.DAMAGE).is_equal(6)


func test_rock_lifecycle_wait_warn_roll_despawn() -> void:
	var r := _rock(60)
	assert_bool(r.rock_active()).is_false()          # 初始 WAIT
	assert_bool(r.warning_active()).is_false()
	for i in 59:
		r.advance()
	assert_bool(r.warning_active()).is_false()       # 间隔未满
	r.advance()                                      # 第 60 拍转 WARN
	assert_bool(r.warning_active()).is_true()
	assert_bool(r.rock_active()).is_false()
	assert_int(r.damage_at(Vector2(20, 96))).is_equal(0)   # 预警期无伤
	for i in RollingRock.WARN_TICKS:
		r.advance()
	assert_bool(r.rock_active()).is_true()           # 预警结束：滚石出现在出生点
	assert_vector(r.rock_pos).is_equal_approx(Vector2(16, 96), EPS)
	var start := r.rock_pos
	r.advance()
	assert_float(r.rock_pos.x - start.x).is_equal_approx(RollingRock.SPEED_PX / TimeConst.FPS, 0.001)
	var ticks := 0
	while r.rock_active() and ticks < 400:           # 滚到撞墙消失
		r.advance()
		ticks += 1
	assert_bool(r.rock_active()).is_false()
	assert_bool(r.warning_active()).is_false()       # 撞墙后回 WAIT
	assert_int(ticks).is_less(400)


func test_rock_damage_contact_only_while_rolling() -> void:
	var r := _rock(60)
	for i in 60 + RollingRock.WARN_TICKS:
		r.advance()
	assert_bool(r.rock_active()).is_true()
	assert_int(r.damage_at(Vector2(20, 96))).is_equal(RollingRock.DAMAGE)   # 车道接触
	assert_int(r.damage_at(Vector2(20, 130))).is_equal(0)                   # 偏离车道
	var r2 := _rock(60)
	for i in 60:                                     # WAIT/WARN 期站位无伤
		r2.advance()
	assert_int(r2.damage_at(Vector2(20, 96))).is_equal(0)


func test_rock_direction_from_side_normalized() -> void:
	var r := RollingRock.new()
	r.setup(Vector2(50, 50), Vector2(0, -5), Rect2(0, 0, 100, 100), 0)
	assert_vector(r.dir).is_equal_approx(Vector2.UP, EPS)
	assert_int(r.interval_ticks).is_equal(RollingRock.DEFAULT_INTERVAL_TICKS)   # interval=0 → 默认


# ---------------------------------------------------------------- FloorScene 接线

func test_floor_scene_instantiates_hazard_components_from_template() -> void:
	_inject_t7_template()
	var fs := _make_scene(_typed_chain(["treasure"], T7_TPL))
	assert_int(fs.hazard_spikes_count()).is_equal(1)
	assert_int(fs.hazard_rock_count()).is_equal(1)
	assert_object(fs.hazard_vines).is_null()         # 本模板无 vine
	# 地刺 zone 中心 = 房间原点 + 瓦片中心（世界坐标）
	var expect := fs.room_rect(1).position + Vector2(11.0 * 16.0 + 8.0, 4.0 * 16.0 + 8.0)
	var s := fs.hazard_spike(0)
	assert_object(s).is_not_null()
	assert_vector(s.zone.get_center()).is_equal_approx(expect, EPS)
	# 滚石出生点 = 瓦片中心；dir 由 side=W → 向东
	var rock := fs.hazard_rock(0)
	assert_object(rock).is_not_null()
	assert_vector(rock.lane_spawn).is_equal_approx(
		fs.room_rect(1).position + Vector2(2.0 * 16.0 + 8.0, 7.0 * 16.0 + 8.0), EPS)
	assert_vector(rock.dir).is_equal_approx(Vector2.RIGHT, EPS)


func test_floor_scene_vine_hazard_slows_player() -> void:
	var fs := _make_scene(_typed_chain(["treasure"], "combat_a1_04"))   # vine@[11,7] r24
	assert_object(fs.hazard_vines).is_not_null()
	var p := fs.player_node()
	p.global_position = fs.room_rect(1).position + Vector2(11.0 * 16.0 + 8.0, 7.0 * 16.0 + 8.0)
	fs._physics_process(0.0)                        # 玩家站上藤蔓 → 减速 40%
	assert_float(p.effective_move_speed(Engine.get_physics_frames())).is_equal(
		Player.MOVE_SPEED * (1.0 - VineZone.SLOW_PCT))
	p.global_position = fs.room_rect(1).position + Vector2(8.0 * 16.0, 2.0 * 16.0)
	fs._physics_process(0.0)                        # 离开：不再刷新（自然过期见纯逻辑测试）
	assert_bool(fs.hazard_vines.in_vine(p.global_position)).is_false()


func test_floor_scene_spikes_damage_player_in_window() -> void:
	_inject_t7_template()
	var fs := _make_scene(_typed_chain(["treasure"], T7_TPL))
	var p := fs.player_node()
	p.global_position = fs.room_rect(1).position + Vector2(11.0 * 16.0 + 8.0, 4.0 * 16.0 + 8.0)
	var before := p.hp + p.shield
	for i in 200:                                    # 覆盖 预警24 + 伸出90（伤害窗）
		fs._physics_process(0.0)
	# 同物理帧内玩家 0.8s 受击无敌帧节流 → 恰一次 4 伤
	assert_int(p.hp + p.shield).is_equal(before - HazardSpikes.DAMAGE)


func test_floor_scene_rock_rolls_and_damages_player_on_lane() -> void:
	_inject_t7_template()
	var fs := _make_scene(_typed_chain(["treasure"], T7_TPL))
	var p := fs.player_node()
	p.global_position = fs.room_rect(1).position + Vector2(8.0 * 16.0 + 8.0, 7.0 * 16.0 + 8.0)
	var before := p.hp + p.shield
	var saw_rock := false
	for i in 400:                                    # WAIT60 + WARN30 + ROLL~100 全周期
		fs._physics_process(0.0)
		if fs.hazard_rock(0).rock_active():
			saw_rock = true
	assert_bool(saw_rock).is_true()
	assert_int(p.hp + p.shield).is_equal(before - RollingRock.DAMAGE)


func test_pillar_props_join_refraction_group() -> void:
	var fs := _make_scene(_typed_chain(["treasure"], "combat_a1_01"))   # 4 根 pillar
	var pillars := fs.get_tree().get_nodes_in_group(EnemyLaser.PILLAR_GROUP)
	assert_int(pillars.size()).is_greater_equal(4)
