extends Node
## m2-t29 H-2 §18.3 全指标压测探针（GDD §18.3 预算表）：
##   活动实体 ≤300 / 同屏弹幕 ≤500 / draw call ≤150（全图集）/ 逻辑帧 ≤6ms / 渲染 ≤10ms。
##
## 场景构成（每层）：start_a<层> → 该层最密战斗模板（密度 = 刷点+陈设+危险地块，平局
## 取字典序最小）。T26 已合入：a2/a3 模板池在库，densest_combat_id 按层池自动选型
## （combat_a2_01 / combat_a3_08）；A3 岩浆池/间歇泉由模板 hazards 行走生产路径实例化
## （首批注入 workaround 已随内容落地移除）。生态特效（floor_idx 驱动 cave/crystal/
## magma 瓦片套件，A2 暗视野+剪影+冰面，A3 火雨）照旧全开。
## 压力注入：40 敌（enemies.json 非 boss 字典序前 40，确定性）+ 敌弹打满 400 公平
## 淘汰线（GDD §7.5）+ 0 伤玩家弹补足 500 总池（0 伤保证敌/玩家不死、负载稳定）+
## 层生态特效全开。0 伤命中仍走完整命中管线（伤害数字/白闪/音频事件）= juice 全开。
##
## 测量口径（双窗口，均关 vsync；4.7.2 Performance 时间监视器实测毫秒——文档标注
## "seconds" 与实测/引擎行为不符，见 _probe_api_check 证据与报告披露）：
##   - 节流窗 Engine.max_fps=60（生产节奏）：~1 物理 step/渲染帧（实测 1.07）→
##     TIME_PHYSICS_PROCESS 逐帧采样即每逻辑帧耗时（≤6ms 线）；
##     渲染 CPU 侧 = TIME_PROCESS + RenderingServer.get_frame_setup_time_cpu()
##     （GPU 侧逐帧时间无公开 API 未采——以 draw call ≤150 间接约束，口径披露）；
##     draw call = RENDER_TOTAL_DRAW_CALLS_IN_FRAME 逐帧 avg/max；
##   - 不节流窗 max_fps=0：整帧墙钟 avg = 渲染+引擎开销的真实整帧成本（逻辑 tick
##     按 60Hz 摊入）；60fps 能力线（合成口径）= 逻辑帧 avg + 整帧墙钟 avg ≤ 16.67ms，
##     另以节流窗 TIME_FPS≈60（1s 粒度）与 steps/frame≈1 作运行实证；
##   - 热身 120 帧（着色器编译/流送稳定）+ 采样 480 帧（=8s 游戏时间 @60Hz）；
##   - 无头运行渲染侧指标为 0（Dummy RenderingServer）仅逻辑线有效——报告数值必须
##     来自窗口运行。
##
## 观察项（T4 评审移交）：A2 剪影/暗视野逐敌 O(n) 与逐帧组查询分配——以 floor 2 对
## floor 1 的逻辑/处理耗时增量 + OBJECT/ORPHAN 计数作监视器证据（见报告「观察项」）。
##
## 运行：godot --path . res://tests/scenes/perf_probe.tscn
## 产出：控制台逐项 PASS/FAIL + user://m2_perf.json；exit 0 全达标 / 1 有超标。

const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 480
const CAP_WARMUP_FRAMES := 30
const CAP_SAMPLE_FRAMES := 240
const ENEMY_TARGET := 40
const BULLET_TARGET := 500
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const OUT_PATH := "user://m2_perf.json"
## 每预算线（GDD §18.3）
const BUDGET := {
	"logic_ms": 6.0, "render_cpu_ms": 10.0, "draw_calls": 150,
	"entities": 300, "bullets": 500, "frame_est_ms": 16.667,
}

var _topup_fs: FloorScene = null
var _topup_room: FloorScene.FloorRoom = null
var _topup_rng := RandomNumberGenerator.new()
var _topup_active := false


func _ready() -> void:
	# 兜底超时：ignore_time_scale 真实墙钟 240s，探针卡死以失败退出，不挂起编排者
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("PERF TIMEOUT")
		get_tree().quit(1)
	)
	RunState.start_run("vanguard")
	# 关 vsync：节流/吞吐由 max_fps 控制，墙钟反映真实工作而非刷新率钳制
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		print("PERF WARN: headless run — render metrics invalid (Dummy RenderingServer); "
			+ "report values must come from a windowed run")
	_topup_rng.seed = 20260831

	var results: Array[Dictionary] = []
	for floor_idx in [1, 2, 3]:
		var res := await _probe_floor(floor_idx)
		results.append(res)
		_print_floor(res)
	_emit_summary(results, headless)


func _physics_process(_delta: float) -> void:
	# 弹幕补充满额（生产同侧：物理 tick 内补弹，enemy 射击节奏的等价物）
	if _topup_active and _topup_room != null and is_instance_valid(_topup_fs):
		_top_up_bullets(_topup_fs, _topup_room, _topup_rng)


# ================================================================ 压测主流程

func _probe_floor(floor_idx: int) -> Dictionary:
	var fs := _make_floor(floor_idx)
	var room: FloorScene.FloorRoom = fs.room_node(1)

	if floor_idx == 2:
		fs.set_biome_a2(true)             # A2 全特效：暗视野+敌人剪影+冰面（观察项：剪影 O(n)）
	fs.enter_room(1)
	# 玩家落位战斗房中心（m1_evidence 习语：位置检测器据此维持当前房）
	fs.player.position = fs.room_rect(1).get_center()
	await _physics_frames(5)             # 波次落地（enter 同拍 + 余量）
	var injected := _inject_enemies(fs, room, stress_enemy_ids(ENEMY_TARGET))
	_top_up_bullets(fs, room, _topup_rng)

	# ---- 节流窗（生产节奏 60fps）：逻辑帧 / 渲染 CPU / draw call ----
	Engine.set("max_fps", 60)
	_topup_fs = fs                        # 热身即保持满压（弹亡即补，物理 tick 内）
	_topup_room = room
	_topup_active = true
	for _i in WARMUP_FRAMES:
		await get_tree().process_frame
	var logic_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var enemies_peak := 0
	var bullets_peak := 0
	var objects_peak := 0
	var orphans_peak := 0
	var pf0 := Engine.get_physics_frames()
	for i in SAMPLE_FRAMES:
		await get_tree().process_frame
		if floor_idx == 3 and i % 120 == 0:   # 火雨（2s 周期，8s 窗 4 落）
			fs.schedule_fire_rain(room.global_position
				+ room.outer.size * 0.5 + Vector2(60.0 * (i / 120 - 1.5), 0))
		logic_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		render_cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)
			+ RenderingServer.get_frame_setup_time_cpu())
		draw_calls.append(float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		bullets_peak = maxi(bullets_peak, room.combat.pool.active_count())
		if i % 8 == 0:
			enemies_peak = maxi(enemies_peak, _alive_enemies(room))
			objects_peak = maxi(objects_peak, int(Performance.get_monitor(
				Performance.OBJECT_COUNT)))
			orphans_peak = maxi(orphans_peak, int(Performance.get_monitor(
				Performance.OBJECT_ORPHAN_NODE_COUNT)))
	var pf1 := Engine.get_physics_frames()
	var paced_fps := float(Performance.get_monitor(Performance.TIME_FPS))

	# ---- 不节流窗：整帧墙钟（渲染+引擎开销，逻辑按 60Hz 摊入）----
	Engine.set("max_fps", 0)
	for _i in CAP_WARMUP_FRAMES:
		await get_tree().process_frame
	var walls: Array[float] = []
	var t_prev := Time.get_ticks_usec()
	for _i in CAP_SAMPLE_FRAMES:
		await get_tree().process_frame
		var t := Time.get_ticks_usec()
		walls.append((t - t_prev) / 1000.0)
		t_prev = t
	_topup_active = false
	Engine.set("max_fps", 60)

	var res := _pack_result(floor_idx, fs, room, injected, enemies_peak, bullets_peak,
		logic_ms, render_cpu_ms, draw_calls, walls,
		float(pf1 - pf0) / float(SAMPLE_FRAMES), paced_fps,
		objects_peak, orphans_peak)
	fs.free()                            # 玩家已被收养，随层释放
	return res


func _make_floor(floor_idx: int) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	var fs := FloorScene.new()
	fs.floor_idx = floor_idx             # 地块按 cave/crystal/magma 套件走（构建期消费）
	add_child(fs)
	fs.setup(probe_build(floor_idx), player)
	# 压测不为数值平衡负责：抬血保证敌接触/岩浆 DOT 下玩家全程存活（不影响帧成本）
	player.hp_max = 9999
	player.hp = 9999
	return fs


# ================================================================ 注入器

## 压力敌名单：GameDB.enemies 键字典序，跳过 boss_script 行，取前 count（确定性）。
static func stress_enemy_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in GameDB.enemies:
		var row: Dictionary = GameDB.enemies[id]
		if row.has("boss_script"):
			continue
		out.append(id)
	out.sort()
	out.resize(mini(count, out.size()))
	return out


## 敌体注入：counts_for_wave=false（不消费波次账目，死亡不触清房）。
func _inject_enemies(fs: FloorScene, room: FloorScene.FloorRoom, ids: Array[String]) -> int:
	var interior := fs._room_interior(room)
	var cols := 8
	var n := 0
	for i in ids.size():
		var cell := Vector2(float(i % cols) + 0.5, float(i / cols) + 0.5)
		var pos := interior.position + Vector2(
			interior.size.x * cell.x / cols, interior.size.y * cell.y / 5.0)
		var e := fs._spawn_enemy(room, ids[i], pos, {}, false)
		if e != null:
			n += 1
	return n


## A3 岩浆套件（生产路径 _build_magma/_build_geyser；a1 模板无 magma hazard 行）。
func _inject_magma_suite(fs: FloorScene, room: FloorScene.FloorRoom) -> void:
	var interior := fs._room_interior(room)
	var c := interior.get_center()
	fs._build_magma(room, c - Vector2(96, 48) - room.position, 44.0)
	fs._build_magma(room, c + Vector2(96, 48) - room.position, 44.0)
	fs._build_geyser(room, [3, 5], c + Vector2(0, -72))


## 0 伤弹填充到预算上限：走生产路径 spawn_projectile（空间哈希/元数据注册齐全）。
## 敌方弹打满 400 公平淘汰线（GDD §7.5）后以玩家弹（0 伤）补足 500 总池。
static func bullet_cfg(pos: Vector2, vel: Vector2, faction: int) -> Dictionary:
	return {
		"pos": pos, "vel": vel, "damage": 0, "faction": faction,
		"radius": 3.0, "life_seconds": 5.0,
		"source_type": "probe", "source_id": "perf_probe", "source_name": "压测探针",
		"attack_name": "压测弹",
	}


func _top_up_bullets(fs: FloorScene, room: FloorScene.FloorRoom,
		rng: RandomNumberGenerator) -> void:
	var combat := room.combat
	if combat == null or combat.pool == null:
		return
	var interior := fs._room_interior(room)
	var batch := 0
	while combat.pool.active_count() < BULLET_TARGET and batch < 60:
		var pos := Vector2(
			rng.randf_range(interior.position.x + 8, interior.end.x - 8),
			rng.randf_range(interior.position.y + 8, interior.end.y - 8))
		var vel := Vector2.from_angle(rng.randf_range(0, TAU)) * 110.0
		var faction := Projectile.Faction.ENEMY \
			if combat._enemy_alive_count() < CombatSystem.ENEMY_BULLET_CAP \
			else Projectile.Faction.PLAYER
		combat.spawn_projectile(bullet_cfg(pos, vel, faction))
		batch += 1


func _alive_enemies(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


# ================================================================ 选型与构建（单测消费）

## 模板密度 = 刷点 + 陈设 + 危险地块（压测负荷口径）。
static func combat_density(tpl: Dictionary) -> int:
	return int(tpl.get("spawn_points", []).size()) \
		+ int(tpl.get("props", []).size()) + int(tpl.get("hazards", []).size())


## 最密战斗模板 id（该层池；池空回退 floor 1 池——a2/a3 JSON 未落地期，平局取
## 字典序最小，确定性）。
static func densest_combat_id(floor_idx: int = 1) -> String:
	var pool := RoomTemplate.combat_ids(floor_idx)
	if pool.is_empty():
		pool = RoomTemplate.combat_ids(1)
	var best := ""
	var best_d := -1
	for id in pool:
		var d := combat_density(RoomTemplate.get_room(id))
		if d > best_d:
			best_d = d
			best = id
	return best


## 探针构建体：start_a1 → 最密战斗房（E 走廊）；boss_room_id=-1（不走 boss 流程）。
## start 恒 start_a1：start_a2/3 模板同未落地（几何由 a1 承担，生态由 floor_idx 承担）。
static func probe_build(floor_idx: int = 1) -> Dictionary:
	var rooms := {
		0: {
			"node": {"id": 0, "type": "start", "grid": Vector2i(0, 0), "depth": 0, "next": [1]},
			"template_id": "start_a1", "world_pos": Vector2.ZERO,
		},
		1: {
			"node": {"id": 1, "type": "combat", "grid": Vector2i(1, 0), "depth": 1, "next": []},
			"template_id": densest_combat_id(floor_idx), "world_pos": Vector2(416.0, 0),
		},
	}
	return {
		"rooms": rooms, "corridors": [{"a": 0, "b": 1, "dir": "E"}],
		"start_room_id": 0, "boss_room_id": -1,
	}


# ================================================================ 度量与判定

func _pack_result(floor_idx: int, fs: FloorScene, room: FloorScene.FloorRoom,
		injected: int, enemies_peak: int, bullets_peak: int,
		logic_ms: Array[float], render_cpu_ms: Array[float],
		draw_calls: Array[float], walls: Array[float],
		steps_per_frame: float, paced_fps: float,
		objects_peak: int, orphans_peak: int) -> Dictionary:
	var tpl := RoomTemplate.get_room(room.template_id)
	var enemies_alive := _alive_enemies(room)
	var props := int(tpl.get("props", []).size())
	var hazards := int(tpl.get("hazards", []).size())
	# floor 3 注入岩浆池×2+间歇泉×1（模板无 hazard 行，注入量常量钉死）
	var hazard_injects := 3 if floor_idx == 3 else 0
	var logic_avg := stat_avg(logic_ms)
	var wall_avg := stat_avg(walls)
	return {
		"floor_idx": floor_idx,
		"template_id": room.template_id,
		"template_density": combat_density(tpl),
		"enemies_injected": injected,
		"enemies_alive": enemies_alive,
		"enemies_peak": enemies_peak,
		"bullets_active": room.combat.pool.active_count(),
		"bullets_peak": bullets_peak,
		"props": props,
		"hazards": hazards,
		"hazard_injects": hazard_injects,
		"entities_nonbullet": maxi(enemies_peak, enemies_alive) + props + hazards + hazard_injects,
		"logic_ms_avg": logic_avg,
		"logic_ms_max": stat_max(logic_ms),
		"render_cpu_ms_avg": stat_avg(render_cpu_ms),
		"render_cpu_ms_max": stat_max(render_cpu_ms),
		"draw_calls_avg": stat_avg(draw_calls),
		"draw_calls_max": stat_max(draw_calls),
		"frame_wall_ms": wall_avg,
		"frame_est_ms": logic_avg + wall_avg,
		"paced_fps": paced_fps,
		"steps_per_frame": steps_per_frame,
		"objects_peak": objects_peak,
		"orphans_peak": orphans_peak,
	}


static func stat_avg(xs: Array[float]) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x in xs:
		s += x
	return s / xs.size()


static func stat_max(xs: Array[float]) -> float:
	var m := 0.0
	for x in xs:
		m = maxf(m, x)
	return m


## 60fps 能力线（合成口径）：逻辑帧 avg + 不节流整帧 avg（两者均在生产 60fps 下
## 每帧各发生一次：1 物理 tick + 1 渲染帧）。
static func frame_est(res: Dictionary) -> float:
	return float(res["logic_ms_avg"]) + float(res["frame_wall_ms"])


## 单层判定：逐预算项 PASS/FAIL（含预算线，≤ 通过）。
static func judge(res: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_item("逻辑帧 ≤6ms", res["logic_ms_avg"], BUDGET["logic_ms"],
		"avg %.3f / max %.3f ms" % [res["logic_ms_avg"], res["logic_ms_max"]]))
	out.append(_item("渲染 CPU ≤10ms", res["render_cpu_ms_avg"], BUDGET["render_cpu_ms"],
		"avg %.3f / max %.3f ms（TIME_PROCESS+frame_setup_cpu；GPU 侧未采）" % [
			res["render_cpu_ms_avg"], res["render_cpu_ms_max"]]))
	out.append(_item("draw call ≤150", res["draw_calls_avg"], BUDGET["draw_calls"],
		"avg %.1f / max %.0f" % [res["draw_calls_avg"], res["draw_calls_max"]]))
	out.append(_item("活动实体 ≤300（非弹幕）", res["entities_nonbullet"],
		BUDGET["entities"],
		"%d（敌峰 %d+陈设 %d+危险 %d+注入 %d）" % [res["entities_nonbullet"],
			res["enemies_peak"], res["props"], res["hazards"], res["hazard_injects"]]))
	out.append(_item("同屏弹幕 ≤500", res["bullets_peak"], BUDGET["bullets"],
		"峰 %d / 末 %d" % [res["bullets_peak"], res["bullets_active"]]))
	out.append(_item("60fps 能力（合成 ≤16.67ms）", res["frame_est_ms"],
		BUDGET["frame_est_ms"], "逻辑 %.3f + 整帧 %.3f = %.3f ms；节流窗 fps=%.1f steps/frame=%.2f" % [
			res["logic_ms_avg"], res["frame_wall_ms"], res["frame_est_ms"],
			res["paced_fps"], res["steps_per_frame"]]))
	return out


static func _item(item_name: String, value: float, budget: float, note: String) -> Dictionary:
	return {"name": item_name, "value": value, "budget": budget,
		"pass": value <= budget, "note": note}


func _print_floor(res: Dictionary) -> void:
	print("PERF floor %d (template %s, density %d): 敌 %d 注入/%d 存活/%d 峰, 弹 %d 峰" % [
		res["floor_idx"], res["template_id"], res["template_density"],
		res["enemies_injected"], res["enemies_alive"], res["enemies_peak"],
		res["bullets_peak"]])
	for item in judge(res):
		print("  %s %s (%s)" % ["PASS" if item["pass"] else "FAIL",
			item["name"], item["note"]])
	print("  OBS objects_peak=%d orphans_peak=%d" % [res["objects_peak"], res["orphans_peak"]])


func _emit_summary(results: Array[Dictionary], headless: bool) -> void:
	var all_pass := true
	print("PERF SUMMARY (GDD §18.3 budget)")
	for res in results:
		for item in judge(res):
			if not item["pass"]:
				all_pass = false
	print("PERF VERDICT: %s" % ("PASS" if all_pass else "FAIL"))
	var meta := {
		"date": Time.get_datetime_string_from_system(),
		"display_server": DisplayServer.get_name(),
		"headless": headless,
		"vsync": "disabled",
		"paced_window": {"max_fps": 60, "warmup": WARMUP_FRAMES, "sample": SAMPLE_FRAMES},
		"capacity_window": {"max_fps": 0, "warmup": CAP_WARMUP_FRAMES, "sample": CAP_SAMPLE_FRAMES},
		"enemy_target": ENEMY_TARGET,
		"bullet_target": BULLET_TARGET,
		"engine": Engine.get_version_info().get("string", ""),
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"meta": meta, "floors": results}, "  "))
		file.close()
		print("PERF JSON: %s" % OUT_PATH)
	else:
		print("PERF WARN: cannot write %s" % OUT_PATH)
	get_tree().quit(0 if all_pass else 1)


func _physics_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
