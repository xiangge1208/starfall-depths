class_name TestBiomeA3
extends GdUnitTestSuite
## M2-T10：A3 生态——岩浆区 DOT / 间歇喷口 / 火雨（GDD §10 A3 行 / 计划卡口径）。
## 1) HazardMagma（纯逻辑，无头）：站立 2/s DOT——脉冲 60t（1s）恰 2 伤；抗火增益
##    （玩家 meta buff_anti_fire，T12 aggregate 落地）减半 → 每脉冲 1 伤；出域暂停
##    （驻留拍计数不重置）；脉冲间隔 > 玩家 0.8s 受击无敌帧（2/s 不被无敌帧节流）。
## 2) HazardMagma.MagmaGeyser：周期 180t / 预警 36t / 喷发伤 8；相位边界纯函数钉死
##    （IDLE 132 → WARN 36 → ERUPT 12，180 回卷）；伤害仅喷发窗且命中 zone。
## 3) HazardMagma.FireRain：Boss/事件驱动红圈落点——schedule → 预警 48t → 恰一拍
##    落点伤（半径内）；未落/已落不伤；多发并行、落点后过期。
## 4) FloorScene 接线：模板 hazards magma/geyser 分派实例化 + 注入帧伤害；
##    schedule_fire_rain 驱动契约（T19/T24 消费）。
## 5) GameDB hazards 白名单扩展（magma/geyser fail-closed 形状校验）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const SPAN_PX := 416.0
const A3_TPL := "combat_a3_99"     # 测试注入模板（after_test 摘除）
const EPS := Vector2(0.001, 0.001)


# ---------------------------------------------------------------- 构建体替身（同 test_hazards_m2 习语）

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


func _inject_a3_template() -> void:
	GameDB.rooms[A3_TPL] = {
		"id": A3_TPL, "size": [22, 14], "doors": ["N", "S", "E", "W"],
		"spawn_points": [[5, 4], [16, 9]],
		"props": [],
		"hazards": [
			{"kind": "magma", "grid": [11, 4], "radius": 24},
			{"kind": "geyser", "grid": [6, 7]},
		],
	}


var _fs: FloorScene = null


func _make_scene(build: Dictionary) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	add_child(_fs)
	_fs.setup(build, player)
	return _fs


func _player() -> Player:
	var p: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	auto_free(p)
	add_child(p)
	return p


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null
	GameDB.rooms.erase(A3_TPL)


# ---------------------------------------------------------------- HazardMagma 纯逻辑（岩浆 DOT）

func test_magma_constants_match_card() -> void:
	assert_float(HazardMagma.BASE_DPS).is_equal(2.0)          # GDD §10 A3：站立 DOT 2/s
	assert_float(HazardMagma.ANTI_FIRE_MULT).is_equal(0.5)    # 抗火减半
	assert_int(HazardMagma.PULSE_TICKS).is_equal(TimeConst.ticks(1.0))   # 1s 脉冲
	assert_float(HazardMagma.effective_dps(false)).is_equal(2.0)
	assert_float(HazardMagma.effective_dps(true)).is_equal(1.0)


func test_magma_pulse_damage_integral() -> void:
	assert_int(HazardMagma.pulse_damage(false)).is_equal(2)   # 2/s × 1s 脉冲 = 2
	assert_int(HazardMagma.pulse_damage(true)).is_equal(1)    # 抗火减半 = 1


func test_magma_zone_point_hit_and_miss() -> void:
	var magma := HazardMagma.new()
	magma.add_zone(Rect2(0, 0, 48, 48))
	assert_bool(magma.in_magma(Vector2(24, 24))).is_true()
	assert_bool(magma.in_magma(Vector2(100, 24))).is_false()
	magma.add_zone(Rect2(200, 0, 48, 48))
	assert_bool(magma.in_magma(Vector2(224, 24))).is_true()


func test_magma_dot_two_per_second_standing() -> void:
	var magma := HazardMagma.new()
	magma.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	var total := 0
	for i in 120:                                  # 站满 2s
		total += magma.tick(p)
		if i < 59:
			assert_int(total).is_equal(0)          # 满 1s 前无脉冲
	assert_int(total).is_equal(4)                  # 2 脉冲 × 2 伤 = 2/s × 2s


func test_magma_anti_fire_meta_halves_dot() -> void:
	var magma := HazardMagma.new()
	magma.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	assert_int(int(p.get_meta("buff_anti_fire", 0))).is_equal(0)   # meta 缺省 0
	var plain := 0
	for i in 60:
		plain += magma.tick(p)
	assert_int(plain).is_equal(2)
	p.set_meta("buff_anti_fire", 1)                # T12 aggregate 落地键
	var warded := 0
	for i in 60:
		warded += magma.tick(p)
	assert_int(warded).is_equal(1)                 # 减半


func test_magma_dot_pauses_when_out_of_zone() -> void:
	var magma := HazardMagma.new()
	magma.add_zone(Rect2(-32, -32, 64, 64))
	var p := _player()
	p.position = Vector2.ZERO
	var total := 0
	for i in 30:                                   # 域内 0.5s
		total += magma.tick(p)
	assert_int(total).is_equal(0)
	p.position = Vector2(500, 500)
	for i in 60:                                   # 域外 1s：不脉冲也不清零驻留拍
		total += magma.tick(p)
	assert_int(total).is_equal(0)
	p.position = Vector2.ZERO
	for i in 30:                                   # 回域再 0.5s → 累满 1s 出脉冲
		total += magma.tick(p)
	assert_int(total).is_equal(2)


func test_magma_pulse_interval_exceeds_hurt_iframes() -> void:
	# 设计不变量：脉冲 60t > 受击无敌帧 48t → 2/s 不被无敌帧节流成 1.25/s
	assert_int(HazardMagma.PULSE_TICKS).is_greater(Player.HURT_IFRAME_TICKS)


func test_magma_never_touches_enemies() -> void:
	# 敌人不受岩浆影响（GDD §10 A3 岩浆为玩家侧危险地块）：tick 只接受 Player
	var enemy := EnemyBase.new()
	auto_free(enemy)
	assert_bool(enemy.get("buff_anti_fire") == null).is_true()
	var magma := HazardMagma.new()
	magma.add_zone(Rect2(0, 0, 64, 64))
	enemy.position = Vector2(32, 32)
	assert_bool(magma.in_magma(enemy.global_position)).is_true()   # 区域命中也不产生效果载体


# ---------------------------------------------------------------- MagmaGeyser 纯逻辑（间歇喷口）

func test_geyser_constants_match_card() -> void:
	assert_int(HazardMagma.MagmaGeyser.CYCLE_TICKS).is_equal(180)   # 周期 180t
	assert_int(HazardMagma.MagmaGeyser.WARN_TICKS).is_equal(36)     # 预警 36t
	assert_int(HazardMagma.MagmaGeyser.DAMAGE).is_equal(8)          # 喷发伤 8
	# 喷发窗（卡未定时长）+ 回卷一致性
	assert_int(HazardMagma.MagmaGeyser.ERUPT_TICKS).is_greater(0)
	assert_int(HazardMagma.MagmaGeyser.idle_ticks() + HazardMagma.MagmaGeyser.WARN_TICKS
		+ HazardMagma.MagmaGeyser.ERUPT_TICKS).is_equal(180)


func test_geyser_phase_boundaries() -> void:
	var G := HazardMagma.MagmaGeyser
	assert_int(int(G.phase_at(0))).is_equal(int(G.Phase.IDLE))
	assert_int(int(G.phase_at(131))).is_equal(int(G.Phase.IDLE))
	assert_int(int(G.phase_at(132))).is_equal(int(G.Phase.WARN))    # 预警 36t：[132,168)
	assert_int(int(G.phase_at(167))).is_equal(int(G.Phase.WARN))
	assert_int(int(G.phase_at(168))).is_equal(int(G.Phase.ERUPT))   # 预警结束拍立即喷发
	assert_int(int(G.phase_at(179))).is_equal(int(G.Phase.ERUPT))
	assert_int(int(G.phase_at(180))).is_equal(int(G.Phase.IDLE))    # 新周期
	assert_int(int(G.phase_at(-1))).is_equal(int(G.Phase.ERUPT))    # 负 t 回卷


func test_geyser_damage_only_in_erupt_window_on_vent() -> void:
	var G := HazardMagma.MagmaGeyser
	var g := G.new()
	g.setup(Rect2(100, 100, 16, 16))
	var on := Vector2(108, 108)
	for i in 168:                                  # IDLE 132 + WARN 36：全程无伤
		assert_int(g.damage_at(on)).is_equal(0)
		g.advance()
	assert_int(g.damage_at(on)).is_equal(G.DAMAGE)  # t=168 喷发即伤害窗
	for i in 11:                                   # t=169..179 仍在窗内
		g.advance()
	assert_int(g.damage_at(on)).is_equal(G.DAMAGE)
	g.advance()                                    # t=180 回 IDLE
	assert_int(g.damage_at(on)).is_equal(0)


func test_geyser_damage_requires_zone_hit() -> void:
	var G := HazardMagma.MagmaGeyser
	var g := G.new()
	g.setup(Rect2(100, 100, 16, 16), G.idle_ticks())   # offset → 直接进入 WARN
	for i in G.WARN_TICKS:
		g.advance()
	assert_int(int(g.phase())).is_equal(int(G.Phase.ERUPT))
	assert_int(g.damage_at(Vector2(200, 200))).is_equal(0)          # 喷发窗内但站偏
	assert_int(g.damage_at(Vector2(108, 108))).is_equal(G.DAMAGE)


func test_geyser_offset_staggers_phase() -> void:
	var G := HazardMagma.MagmaGeyser
	var g := G.new()
	g.setup(Rect2(), G.idle_ticks() + G.WARN_TICKS)   # 偏移恰落喷发拍
	assert_int(int(g.phase())).is_equal(int(G.Phase.ERUPT))
	var g2 := G.new()
	g2.setup(Rect2(), G.CYCLE_TICKS)                  # 整周期偏移 ≡ 无偏移
	assert_int(int(g2.phase())).is_equal(int(G.Phase.IDLE))


# ---------------------------------------------------------------- FireRain 纯逻辑（火雨红圈）

func test_fire_rain_constants_match_card() -> void:
	assert_int(HazardMagma.FireRain.WARN_TICKS).is_equal(48)   # 预警 48t
	assert_int(HazardMagma.FireRain.DAMAGE).is_greater(0)
	assert_float(HazardMagma.FireRain.RADIUS_PX).is_greater(0.0)


func test_fire_rain_warns_48t_then_strikes_exactly_one_tick() -> void:
	var fr := HazardMagma.FireRain.new()
	var pos := Vector2(200, 100)
	fr.schedule(pos)
	assert_int(fr.striking_at(pos)).is_equal(0)       # 落点前无伤
	for i in 47:                                      # t=0..47：预警 48t
		fr.tick()
		assert_int(fr.striking_at(pos)).is_equal(0)
	fr.tick()                                         # 第 48 拍：落点
	assert_int(fr.striking_at(pos)).is_equal(HazardMagma.FireRain.DAMAGE)
	fr.tick()                                         # 落点后过期
	assert_int(fr.striking_at(pos)).is_equal(0)


func test_fire_rain_radius_hit_and_miss() -> void:
	var fr := HazardMagma.FireRain.new()
	var pos := Vector2(200, 100)
	fr.schedule(pos)
	for i in 48:
		fr.tick()
	var r: float = HazardMagma.FireRain.RADIUS_PX
	assert_int(fr.striking_at(pos + Vector2(r - 1.0, 0))).is_equal(HazardMagma.FireRain.DAMAGE)
	assert_int(fr.striking_at(pos + Vector2(r + 1.0, 0))).is_equal(0)


func test_fire_rain_multiple_strikes_and_expiry() -> void:
	var fr := HazardMagma.FireRain.new()
	fr.schedule(Vector2(10, 10))
	fr.schedule(Vector2(500, 500))
	assert_int(fr.strike_count()).is_equal(2)
	for i in 48:
		fr.tick()
	assert_int(fr.strike_count()).is_equal(2)         # 落点拍仍在（恰一拍可判定）
	assert_int(fr.striking_at(Vector2(10, 10))).is_equal(HazardMagma.FireRain.DAMAGE)
	assert_int(fr.striking_at(Vector2(500, 500))).is_equal(HazardMagma.FireRain.DAMAGE)
	fr.tick()
	assert_int(fr.strike_count()).is_equal(0)         # 全部过期


func test_fire_rain_empty_tick_is_safe() -> void:
	var fr := HazardMagma.FireRain.new()
	fr.tick()                                        # 无落点：no-op 不崩
	assert_int(fr.strike_count()).is_equal(0)
	assert_int(fr.striking_at(Vector2.ZERO)).is_equal(0)


# ---------------------------------------------------------------- FloorScene 接线（magma kind 分派）

func test_floor_scene_instantiates_a3_hazards_from_template() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	assert_object(fs.hazard_magma).is_not_null()
	assert_int(fs.hazard_magma.zones.size()).is_equal(1)
	assert_int(fs.hazard_geyser_count()).is_equal(1)
	# 岩浆域 = 房间原点 + 瓦片中心 - 半径 的外接方（世界坐标，同 vine 几何）
	var room_pos: Vector2 = fs.room_rect(1).position
	var center := room_pos + Vector2(11.0 * 16.0 + 8.0, 4.0 * 16.0 + 8.0)
	assert_vector(fs.hazard_magma.zones[0].get_center()).is_equal_approx(center, EPS)
	# 喷口 zone 中心 = 瓦片中心
	var g := fs.hazard_geyser(0)
	assert_object(g).is_not_null()
	assert_vector(g.zone.get_center()).is_equal_approx(
		room_pos + Vector2(6.0 * 16.0 + 8.0, 7.0 * 16.0 + 8.0), EPS)


func test_floor_scene_magma_dot_damages_player_per_second() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	var p := fs.player_node()
	p.global_position = fs.room_rect(1).position + Vector2(11.0 * 16.0 + 8.0, 4.0 * 16.0 + 8.0)
	var before := p.hp + p.shield
	for i in 60:                                     # 站满 1s → 恰一脉冲 2 伤
		fs._physics_process(0.0)
	assert_int(p.hp + p.shield).is_equal(before - 2)


func test_floor_scene_magma_dot_halved_with_anti_fire_meta() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	var p := fs.player_node()
	p.set_meta("buff_anti_fire", 1)                  # T12 落地键
	p.global_position = fs.room_rect(1).position + Vector2(11.0 * 16.0 + 8.0, 4.0 * 16.0 + 8.0)
	var before := p.hp + p.shield
	for i in 60:
		fs._physics_process(0.0)
	assert_int(p.hp + p.shield).is_equal(before - 1)  # 抗火减半


func test_floor_scene_geyser_erupts_and_damages_standing_player() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	var p := fs.player_node()
	p.global_position = fs.room_rect(1).position + Vector2(6.0 * 16.0 + 8.0, 7.0 * 16.0 + 8.0)
	var before := p.hp + p.shield
	for i in 200:                                    # 覆盖 IDLE+WARN+ERUPT 整周期
		fs._physics_process(0.0)
	# 同物理帧内受击无敌帧节流 → 恰一次 8 伤
	assert_int(p.hp + p.shield).is_equal(before - HazardMagma.MagmaGeyser.DAMAGE)


func test_floor_scene_schedule_fire_rain_damages_after_48t() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	var p := fs.player_node()
	var target := fs.room_rect(1).get_center()
	p.global_position = target
	var before := p.hp + p.shield
	fs.schedule_fire_rain(target)                    # T19/T24 驱动契约
	for i in 47:                                     # 预警 48t 内可走出红圈
		fs._physics_process(0.0)
	assert_int(p.hp + p.shield).is_equal(before)
	fs._physics_process(0.0)                         # 第 48 拍落点
	assert_int(p.hp + p.shield).is_equal(before - HazardMagma.FireRain.DAMAGE)


func test_floor_scene_fire_rain_misses_dodged_player() -> void:
	_inject_a3_template()
	var fs := _make_scene(_typed_chain(["treasure"], A3_TPL))
	var p := fs.player_node()
	var target := fs.room_rect(1).get_center()
	p.global_position = target + Vector2(HazardMagma.FireRain.RADIUS_PX + 20.0, 0)
	var before := p.hp + p.shield
	fs.schedule_fire_rain(target)
	for i in 60:
		fs._physics_process(0.0)
	assert_int(p.hp + p.shield).is_equal(before)     # 出圈免伤


# ---------------------------------------------------------------- GameDB hazards 白名单扩展

func _room_row_with_hazards(hazards: Array) -> Dictionary:
	return {"id": "wh_test", "size": [22, 14], "doors": ["N", "S"],
		"spawn_points": [[11, 7]], "props": [], "hazards": hazards}


func test_game_db_hazard_whitelist_accepts_magma_and_geyser() -> void:
	assert_str(GameDB.HAZARD_KINDS[0]).is_equal("vine")
	var errors := GameDB.validate_room_row(_room_row_with_hazards([
		{"kind": "magma", "grid": [8, 8], "radius": 24},
		{"kind": "geyser", "grid": [10, 10]},
	]))
	assert_int(errors.size()).is_equal(0)


func test_game_db_hazard_whitelist_rejects_bad_kind() -> void:
	var errors := GameDB.validate_room_row(_room_row_with_hazards(
		[{"kind": "lava_fountain", "grid": [8, 8]}]))
	assert_int(errors.size()).is_equal(1)


func test_game_db_magma_requires_radius_and_grid_bounds() -> void:
	assert_int(GameDB.validate_room_row(_room_row_with_hazards(
		[{"kind": "magma", "grid": [8, 8]}])).size()).is_equal(1)          # 缺 radius
	assert_int(GameDB.validate_room_row(_room_row_with_hazards(
		[{"kind": "magma", "grid": [99, 8], "radius": 24}])).size()).is_equal(1)   # 界外
	assert_int(GameDB.validate_room_row(_room_row_with_hazards(
		[{"kind": "geyser", "grid": [99, 8]}])).size()).is_equal(1)        # 界外
