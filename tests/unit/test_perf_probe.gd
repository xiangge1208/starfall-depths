class_name TestPerfProbe
extends GdUnitTestSuite
## m2-t29 H-2：压测探针纯逻辑锁（预算判定表驱动/最密模板选型/压力名单/弹配置/
## 探针构建体/统计助手）+ 场景构建计数（40 敌注入 / 500 弹封顶 / 非弹幕实体账目）。
## 帧耗时/绘制等渲染指标由探针场景窗口运行产出（本套件不测墙钟数值，防拖慢全量）。

const PROBE := preload("res://tests/scenes/perf_probe.gd")
const PLAYER_SCENE := preload("res://core/player/player.tscn")

var _fs: FloorScene = null


func before_test() -> void:
	RunState.start_run("vanguard")


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


# ---------------------------------------------------------------- 选型（密度口径）

func test_a1_combat_pool_loaded_with_8_templates() -> void:
	assert_int(RoomTemplate.combat_ids(1).size()).is_equal(8)


func test_density_is_spawn_plus_props_plus_hazards() -> void:
	# combat_a1_03：4 刷点 + 14 箱 + 0 危险 = 18（手工钉值）
	assert_int(PROBE.combat_density(RoomTemplate.get_room("combat_a1_03"))).is_equal(18)


func test_densest_selection_is_combat_a1_03() -> void:
	assert_str(PROBE.densest_combat_id(1)).is_equal("combat_a1_03")


func test_densest_falls_back_to_floor1_pool_when_floor_pool_empty() -> void:
	# 当前基线 a2/a3 模板 JSON 未落地（T26 分支未合）：floor 2/3 池空 → 回退 floor 1 池。
	# T26 合入后 combat_ids(2/3) 非空，本断言自动转为钉 a2/a3 各自最密（届时改钉值）。
	for f in [2, 3]:
		var expect := PROBE.densest_combat_id(1) if RoomTemplate.combat_ids(f).is_empty() \
			else PROBE.densest_combat_id(f)
		assert_str(PROBE.densest_combat_id(f)).is_equal(expect)
		assert_str(PROBE.densest_combat_id(f)).is_not_empty()


func test_densest_is_deterministic() -> void:
	assert_str(PROBE.densest_combat_id(3)).is_equal(PROBE.densest_combat_id(3))


# ---------------------------------------------------------------- 压力名单

func test_stress_enemy_ids_deterministic_no_bosses() -> void:
	var ids := PROBE.stress_enemy_ids(40)
	assert_int(ids.size()).is_equal(40)
	for id in ids:
		assert_bool(GameDB.enemies.has(id)).is_true()
		assert_bool((GameDB.enemies[id] as Dictionary).has("boss_script")).is_false()
	# 字典序确定性
	assert_array(ids).is_equal(PROBE.stress_enemy_ids(40))


func test_stress_enemy_ids_caps_at_pool_size() -> void:
	assert_int(PROBE.stress_enemy_ids(999).size()).is_less_equal(46)


func test_bullet_cfg_is_zero_damage_both_factions() -> void:
	var cfg := PROBE.bullet_cfg(Vector2(10, 20), Vector2(1, 0), Projectile.Faction.ENEMY)
	assert_int(int(cfg["damage"])).is_equal(0)
	assert_int(cfg["faction"]).is_equal(Projectile.Faction.ENEMY)
	var cfg_p := PROBE.bullet_cfg(Vector2.ZERO, Vector2.ZERO, Projectile.Faction.PLAYER)
	assert_int(cfg_p["faction"]).is_equal(Projectile.Faction.PLAYER)
	assert_int(int(cfg_p["damage"])).is_equal(0)


# ---------------------------------------------------------------- 探针构建体

func test_probe_build_shape_uses_densest_template() -> void:
	var build := PROBE.probe_build()
	assert_int((build["rooms"] as Dictionary).size()).is_equal(2)
	var combat: Dictionary = (build["rooms"] as Dictionary)[1]
	assert_str(String(combat["template_id"])).is_equal(PROBE.densest_combat_id(1))
	assert_str(String(combat["node"]["type"])).is_equal("combat")
	assert_int(int(build["boss_room_id"])).is_equal(-1)
	var corridors: Array = build["corridors"]
	assert_int(corridors.size()).is_equal(1)
	assert_str(String(corridors[0]["dir"])).is_equal("E")


# ---------------------------------------------------------------- 统计助手

func test_stat_avg_and_max_on_samples() -> void:
	var xs: Array[float] = [3.0, 1.0, 2.0]
	assert_float(PROBE.stat_avg(xs)).is_equal(2.0)
	assert_float(PROBE.stat_max(xs)).is_equal(3.0)


func test_stat_avg_empty_is_zero() -> void:
	var xs: Array[float] = []
	assert_float(PROBE.stat_avg(xs)).is_equal(0.0)
	assert_float(PROBE.stat_max(xs)).is_equal(0.0)


# ---------------------------------------------------------------- 场景构建计数

func _make_scene() -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	_fs = FloorScene.new()
	_fs.floor_idx = 1
	add_child(_fs)
	_fs.setup(PROBE.probe_build(), player)
	return _fs


func _probe_node() -> Node:
	return PROBE.new()


func test_scene_builds_with_expected_room_count() -> void:
	var fs := _make_scene()
	assert_int(fs.room_count()).is_equal(2)
	assert_str(String(fs.room_node(1).template_id)).is_equal("combat_a1_03")


func test_probe_injects_40_enemies_and_caps_bullets_at_500() -> void:
	var fs := _make_scene()
	var probe := _probe_node()
	auto_free(probe)
	assert_bool(fs.enter_room(1)).is_true()
	for _i in 5:
		await get_tree().physics_frame          # 波次落地（enter 同拍 + 余量）
	var room: FloorScene.FloorRoom = fs.room_node(1)
	var ids := PROBE.stress_enemy_ids(40)
	var injected: int = probe._inject_enemies(fs, room, ids)
	assert_int(injected).is_equal(40)
	var alive := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			alive += 1
	# 40 注入 + wave1 垃圾（3 只口径）→ 宽断言 40..44（波次配置变更不脆断）
	assert_int(alive).is_greater_equal(40)
	assert_int(alive).is_less_equal(44)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260831
	# 生产形态填充：物理 tick 内逐批补足（探针 _physics_process 同款循环语义）
	for _i in 20:
		probe._top_up_bullets(fs, room, rng)
		if room.combat.pool.active_count() >= 500:
			break
	assert_int(room.combat.pool.active_count()).is_equal(500)
	# 敌弹打满 400 上限（GDD §7.5 公平淘汰线）后补玩家弹到 500
	var enemy_bullets := 0
	for p in room.combat.pool.active:
		if p.faction == Projectile.Faction.ENEMY:
			enemy_bullets += 1
	assert_int(enemy_bullets).is_equal(400)


# ---------------------------------------------------------------- 预算判定（表驱动）

func _synthetic_result(overrides: Dictionary) -> Dictionary:
	var res := {
		"floor_idx": 1, "template_id": "combat_a1_03", "template_density": 18,
		"enemies_injected": 40, "enemies_alive": 43, "enemies_peak": 43,
		"bullets_active": 500, "bullets_peak": 500,
		"props": 14, "hazards": 0, "hazard_injects": 0, "entities_nonbullet": 57,
		"logic_ms_avg": 2.0, "logic_ms_max": 3.0,
		"render_cpu_ms_avg": 3.0, "render_cpu_ms_max": 5.0,
		"draw_calls_avg": 60.0, "draw_calls_max": 80.0,
		"frame_wall_ms": 4.0, "frame_est_ms": 6.0,
		"paced_fps": 60.0, "steps_per_frame": 1.02,
	}
	res.merge(overrides, true)
	return res


func test_judge_returns_six_budget_items() -> void:
	assert_int(PROBE.judge(_synthetic_result({})).size()).is_equal(6)


func test_judge_all_pass_on_healthy_synthetic_result() -> void:
	for item in PROBE.judge(_synthetic_result({})):
		assert_bool(item["pass"]).is_true()


func test_judge_flags_each_budget_breach() -> void:
	# 表驱动：每个预算项单独击穿 → 恰好 1 项 FAIL
	var cases := [
		{"logic_ms_avg": 6.001},
		{"render_cpu_ms_avg": 10.001},
		{"draw_calls_avg": 150.001},
		{"entities_nonbullet": 301},
		{"bullets_peak": 501},
		{"frame_est_ms": 16.671},
	]
	for case in cases:
		var items := PROBE.judge(_synthetic_result(case))
		var failed := 0
		for item in items:
			if not item["pass"]:
				failed += 1
		assert_int(failed).is_equal(1)


func test_judge_boundary_values_pass_inclusive() -> void:
	# 预算线本身（≤）应 PASS：6/10/150/300/500/16.667
	var b: Dictionary = PROBE.BUDGET
	var items := PROBE.judge(_synthetic_result({
		"logic_ms_avg": b["logic_ms"], "render_cpu_ms_avg": b["render_cpu_ms"],
		"draw_calls_avg": b["draw_calls"], "entities_nonbullet": b["entities"],
		"bullets_peak": b["bullets"], "frame_est_ms": b["frame_est_ms"],
	}))
	for item in items:
		assert_bool(item["pass"]).is_true()


func test_frame_est_composition_is_logic_plus_uncapped_wall() -> void:
	# 60fps 能力线 = 逻辑帧 + 不节流整帧（合成口径）：2.0 + 4.0 = 6.0
	var res := _synthetic_result({"logic_ms_avg": 2.0, "frame_wall_ms": 4.5})
	assert_float(PROBE.frame_est(res)).is_equal(6.5)
