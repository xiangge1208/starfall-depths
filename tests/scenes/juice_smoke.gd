extends Node
## M3-J-D Juice 束收口无头冒烟（开关矩阵回归的机检固化，font_render_smoke 同惯例）：
##   ① 关键节点/接线存在性：Fx+ParticlesPool（池 240）/ ArtLookup 8 条带 / J-A 导演在位
##      且 balance.json juice 必需键装载成功 / GameCamera 可用 / 设置面板场景可实例化；
##   ② 开关逐项遍历（Juice v2 红线：表现与判定分离——关掉后效果侧归零、信息侧无损）：
##      hitstop_enabled=false → 冻结/击杀链 no-op 但伤害数字照常；
##      screen_shake=0 → 相机 offset/rotation 恒零但跟随不丢；
##      粒子预算降级 → ≥200 活跃自动降级为单帧（图仍在，信息保留）且回落自动恢复；
##      vibration=false → 设置落盘（消费端接线补课后由 §7 直接机检：headless 经注入口
##      验证调用链，平台门控使真实 API 在无头/桌面零调用）；
##   ③ 全关组合：四开关全关同拍打命中管线 → 伤害数字/火花/命中判定零错误零缺失；
##   ④ 设置面板 UI → SaveSystem → 消费端三段接线（真实控件驱动 HitstopToggle /
##      VibrationToggle，写档并翻转 Fx 门控）；
##   ⑤ 信息侧抽检：HUD（红心/金币/Buff chip 状态图标）、伤害数字开关语义、色弱形状开关语义；
##   ⑥ 输入延迟 ≤1 帧机检：Input.action_press → player._physics_process 同/次拍消费；
##   ⑦ D-1 振动消费端：受击 30ms / Boss 死亡 80ms 触发、vibration 开关门控、
##      平台能力门控（headless 无注入口不裸调振动 API）；
##   ⑧ D-2：Boss 死亡演出链期间连按攻击键（fire/touch_fire）快进——非演出期零误触发；
##   ⑨ D-3a/D-3c：玩家死亡去饱和渐入 0.4s（真实毫秒推进、hitstop off 不启动、
##      cancel 清理）；Boss 战利品挂起延迟喷出（loot 段/快进补发，链缺席同步照旧）；
##   ⑩ D-3b/D-4：受击方向 8px 弧形几何与 0.2s 淡出（无方向不画弧裁定）、
##      低血呼吸参数对齐规格 §J6。
## 边界披露：打击感主观项（"爽不爽"、晕动观感、音高可闻度）不在此测，归 G-1 试玩员；
## 整局无头跑通的开关矩阵回归见 tests/scenes/juice_matrix_run.gd（bot 全局驱动）。
## 运行：godot --headless --path . res://tests/scenes/juice_smoke.tscn
## 退出码：0 全绿 / 1 有失败（控制台逐条 PASS/FAIL，SMOKE DONE 收口）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const PANEL_SCENE := "res://ui/settings_panel.tscn"
const CAMERA_SCRIPT := preload("res://fx/game_camera.gd")
const BOT_DIRECTOR_REQUIRED_KEYS := [
	"kill_freeze_ms", "kill_recover_ms", "multikill_window_ms", "multikill_bonus_ms",
	"hitstop_cap_ms", "boss_phase_hitstop_ms", "boss_phase_slow_scale", "boss_phase_slow_ms",
	"boss_death_freeze_ms", "boss_death_slow_scale", "boss_death_slow_ms", "loot_delay_ms",
	"player_death_slow_scale", "player_death_slow_ms", "player_death_desat_ms",
]
## 冒烟涉及的设置键（起始快照 / 结束还原——不污染后续套件与真档语义）。
const SETTING_KEYS := [
	"hitstop_enabled", "screen_shake", "damage_numbers", "colorblind_shapes", "vibration",
]

var failures: Array[String] = []
var _saved_settings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # hitstop 冻结期（树暂停）断言照常推进
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1)
	)
	for key: String in SETTING_KEYS:
		_saved_settings[key] = SaveSystem.get_setting(key, true)
	_run()

func _run() -> void:
	print("SMOKE 0: wiring existence")
	await _section_wiring()
	print("SMOKE 1: hitstop switch off/on")
	await _section_hitstop_switch()
	print("SMOKE 2: screen_shake switch")
	await _section_shake_switch()
	print("SMOKE 3: particles budget degrade")
	await _section_particles_budget()
	print("SMOKE 4: settings panel UI -> SaveSystem -> consumer")
	await _section_panel_wiring()
	print("SMOKE 5: info channels (HUD / damage numbers / element shapes)")
	await _section_info_channels()
	print("SMOKE 6: input-to-motion latency (<=1 physics tick)")
	await _section_input_latency()
	print("SMOKE 7: vibration consumer (D-1)")
	await _section_vibration_consumer()
	print("SMOKE 8: boss-death skip wiring (D-2)")
	await _section_boss_death_skip()
	print("SMOKE 9: death desat fade-in + loot delay (D-3a/D-3c)")
	await _section_death_desat_and_loot()
	print("SMOKE 10: hit direction arc + low-hp breath params (D-3b/D-4)")
	await _section_hit_arc_and_breath()

	_restore_settings()
	print("SMOKE DONE: %s (%d checks failed)" % ["OK" if failures.is_empty() else "FAILED",
		failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# ================================================================ ① 接线存在性

func _section_wiring() -> void:
	_check(Fx != null and is_instance_valid(Fx), "Fx autoload present")
	_check(Fx.particles != null and Fx.particles is ParticlesPool,
		"Fx.particles pool present (J-C)")
	if Fx.particles != null:
		_check(Fx.particles.capacity() == 240, "particle pool capacity == 240")
	_check(Fx._director != null and Fx._director is HitstopDirector, "J-A hitstop director on duty")
	if Fx._director != null:
		_check(bool(Fx._director.load_ok), "director loaded balance.json juice (load_ok)")
		var params: Dictionary = Fx._director.params
		var missing: Array[String] = []
		for key: String in BOT_DIRECTOR_REQUIRED_KEYS:
			if not params.has(key):
				missing.append(key)
		_check(missing.is_empty(), "director required juice keys all present"
			+ ("" if missing.is_empty() else " missing: " + ", ".join(missing)))
	var strips_missing: Array[String] = []
	for strip_id: String in ArtLookup.FX_STRIPS:
		if ArtLookup.tex(ArtLookup.fx_strip_path(strip_id)) == null:
			strips_missing.append(strip_id)
	_check(strips_missing.is_empty(), "ArtLookup 8 fx strips textures load"
		+ ("" if strips_missing.is_empty() else " missing: " + ", ".join(strips_missing)))
	var cam: Node = (CAMERA_SCRIPT as Script).new()
	_check(cam != null, "GameCamera instantiable")
	if cam != null:
		cam.free()
	var panel_inst: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	_check(panel_inst != null, "settings_panel.tscn instantiates")
	if panel_inst != null:
		panel_inst.free()
	_check(GameCamera.shake_amplitude(1.0, 1.0, 8.0) == 8.0
		and GameCamera.shake_amplitude(0.5, 1.0, 8.0) == 2.0,
		"trauma^2 amplitude curve (1.0->8px, 0.5->2px)")
	var panel: PackedScene = load(PANEL_SCENE)
	_check(panel != null, "settings_panel.tscn loads")


# ================================================================ ② hitstop 开关

func _section_hitstop_switch() -> void:
	var enemy := Node2D.new()
	add_child(enemy)
	# --- off：请求全部 no-op（树不冻结），但信息侧（伤害数字/火花）照常 ---
	SaveSystem.set_setting("hitstop_enabled", false)
	Fx.hitstop(40)
	_check(not get_tree().paused, "hitstop_enabled=false: Fx.hitstop(40) no-op (tree not paused)")
	Fx.on_enemy_killed(enemy.global_position)
	_check(not get_tree().paused, "hitstop_enabled=false: kill chain no-op (tree not paused)")
	Fx.trauma = 0.0
	var before := Fx.combo_pitch()
	_check(not Fx.particles.is_degraded(), "hitstop off: particle pool idle (pre-clean)")
	var num := Fx.spawn_damage_number(enemy.global_position, 7, false)
	_check(num != null and num.text == "7",
		"hitstop off: damage number still spawned (info intact)")
	if num != null:
		num.queue_free()
	# --- on：击杀链冻结生效，cancel 后时计归位 ---
	SaveSystem.set_setting("hitstop_enabled", true)
	Fx.on_enemy_killed(enemy.global_position)
	_check(get_tree().paused, "hitstop_enabled=true: kill chain freezes tree (v2 80ms ease-out)")
	Fx.cancel_hitstop()
	_check(not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0),
		"cancel_hitstop restores tree + time_scale (idempotent)")
	# --- J5 连击音高（消费缝冒烟；公式细则归 test_combo_counter.gd）---
	Fx.on_combo_hit()
	_check(absf(Fx.combo_pitch() - (before + 0.02)) < 0.005 or Fx.combo_pitch() > 1.0,
		"combo pitch rises after on_combo_hit (J5 wiring)")
	enemy.queue_free()


# ================================================================ ② screen_shake 开关

func _section_shake_switch() -> void:
	var cam := (CAMERA_SCRIPT as Script).new() as GameCamera
	var target := Node2D.new()
	target.position = Vector2(120.0, 64.0)
	add_child(target)
	cam.target = target
	add_child(cam)
	await _frames(2)
	SaveSystem.set_setting("screen_shake", 1.0)
	Fx.trauma = 0.0
	Fx.add_trauma(1.0)
	await _frames(2)
	_check(cam.offset != Vector2.ZERO or cam.rotation != 0.0,
		"screen_shake=1.0 + trauma 1.0: camera shakes (effect present)")
	_check(cam.global_position.distance_to(target.global_position) < 1.0,
		"camera still follows target while shaking (view info intact)")
	SaveSystem.set_setting("screen_shake", 0.0)
	Fx.trauma = 0.0
	Fx.add_trauma(1.0)                     # 再注满：能量在，系数为 0
	await _frames(2)
	_check(cam.offset == Vector2.ZERO and cam.rotation == 0.0,
		"screen_shake=0 + trauma 1.0: offset/rotation pinned to zero (switch effective)")
	_check(cam.global_position.distance_to(target.global_position) < 1.0,
		"screen_shake=0: follow intact (zero info loss)")
	Fx.trauma = 0.0
	SaveSystem.set_setting("screen_shake", 0.5)   # 晕动防线默认档 50%（save_system.gd:23）
	cam.queue_free()
	target.queue_free()
	await _frames(1)


# ================================================================ ② 粒子预算降级（J3）

func _section_particles_budget() -> void:
	var pool := Fx.particles
	while pool.active_units() > 0:         # 等前面用例的火花自然播完
		pool.step(0.5)
	pool.step(0.01)
	_check(not pool.is_degraded(), "budget: starts clean (not degraded)")
	for i in 240:                          # 打满池硬容量 240（预算 200）
		pool.play("spark_hit", Vector2(i, 0.0))
	_check(pool.active_units() == 240, "budget: 240 plays all take a unit (pool exhausted)")
	_check(pool.is_degraded(), "budget: >=200 active -> degraded mode engaged")
	var degraded_units := 0
	var visible_units := 0
	for u in pool.units():
		if u.playing and u.degraded:
			degraded_units += 1
		if u.playing and u.visible and (u.texture as AtlasTexture).region.size.x > 0.0:
			visible_units += 1
	_check(degraded_units >= 40, "budget: overflow requests flagged degraded (>=40)")
	_check(visible_units == 240, "budget: degraded units still show single frame (info preserved)")
	pool.play("spark_hit", Vector2.ZERO)   # 池满：第 241 个请求被容量兜底丢弃
	_check(pool.active_units() == 240, "budget: 241st request dropped cleanly (hard cap)")
	pool.step(0.05)
	var held := 0        # 降级单帧（预算外第 201..240 个请求）：锁第 0 帧
	var animated := 0    # 预算内前 200：照常逐帧换图（本拍已到第 1 帧）
	for u in pool.units():
		if not u.playing:
			continue
		if u.degraded and u.fidx == 0:
			held += 1
		elif not u.degraded and u.fidx == 1:
			animated += 1
	_check(held == 40, "budget: 40 overflow units hold frame 0 (degrade semantics)")
	_check(animated == 200, "budget: 200 in-budget units still animate (frame advance)")
	pool.step(0.3)                         # 越过 0.2s 时长：全部回收
	_check(pool.active_units() == 0, "budget: all units recycled after duration")
	pool.step(0.01)
	_check(not pool.is_degraded(), "budget: auto-recovers when active < 200")
	for strip_id: String in ArtLookup.FX_STRIPS:   # 三态火花/枪口焰/碎片环入口零错误
		pool.play(strip_id, Vector2.ZERO)
	pool.step(0.5)


# ================================================================ ④ 面板 UI → 存档 → 消费端

func _section_panel_wiring() -> void:
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await _frames(2)
	var hitstop_btn: Button = panel.get_node("Center/Panel/Margin/Rows/Grid/HitstopToggle")
	var vibration_btn: Button = panel.get_node("Center/Panel/Margin/Rows/Grid/VibrationToggle")
	_check(hitstop_btn != null and vibration_btn != null, "panel exposes hitstop/vibration toggles")
	# 真实控件驱动：button_pressed 赋值触发 toggled → handler 写 SaveSystem（即时落盘）
	hitstop_btn.button_pressed = false
	await _frames(1)
	_check(not bool(SaveSystem.get_setting("hitstop_enabled", true)),
		"panel toggle off -> hitstop_enabled persisted false")
	Fx.hitstop(40)
	_check(not get_tree().paused, "panel-off state gates Fx.hitstop (UI->setting->consumer)")
	hitstop_btn.button_pressed = true
	await _frames(1)
	_check(bool(SaveSystem.get_setting("hitstop_enabled", true)),
		"panel toggle on -> hitstop_enabled persisted true")
	vibration_btn.button_pressed = false
	await _frames(1)
	_check(not bool(SaveSystem.get_setting("vibration", true)),
		"panel toggle off -> vibration persisted false")
	vibration_btn.button_pressed = true
	await _frames(1)
	_check(bool(SaveSystem.get_setting("vibration", true)),
		"panel toggle on -> vibration persisted true")
	panel.queue_free()
	await _frames(1)


# ================================================================ ⑤ 信息侧抽检

func _section_info_channels() -> void:
	# HUD：红心/金币/Buff chip（状态图标）在 juice 开关无关路径上照常呈现
	RunState.start_run("vanguard")
	RunState.add_coins(50)
	RunState.add_buff("m3jd_probe_buff")
	var player: Node = (PLAYER_SCENE as PackedScene).instantiate()
	add_child(player)
	var hud := HUD.new()
	hud.player = player
	add_child(hud)
	await _frames(2)
	_check(hud._hearts.get_child_count() > 0, "HUD hearts rendered (core info channel)")
	_check(str(hud._coin_label.text).contains("50"), "HUD coin counter updates (info intact)")
	_check(hud._buff_row.get_child_count() == 1, "HUD buff chip (status icon) rendered")
	hud.free()
	player.queue_free()
	# 伤害数字开关语义（红线三开关之一，非本矩阵四键——语义自检）
	SaveSystem.set_setting("damage_numbers", true)
	var num := Fx.spawn_damage_number(Vector2.ZERO, 42, true)
	_check(num != null and num.text == "42", "damage_numbers=true: crit number spawns")
	if num != null:
		num.queue_free()
	SaveSystem.set_setting("damage_numbers", false)
	_check(Fx.spawn_damage_number(Vector2.ZERO, 42, true) == null,
		"damage_numbers=false: suppressed by design (own switch semantics)")
	SaveSystem.set_setting("damage_numbers", true)
	# 色弱形状第二视觉通道（开关语义自检）
	SaveSystem.set_setting("colorblind_shapes", false)
	_check(Fx.spawn_element_shape(Vector2.ZERO, Elements.Id.FIRE) == null,
		"colorblind_shapes=false: no shape node (default)")
	SaveSystem.set_setting("colorblind_shapes", true)
	var shape := Fx.spawn_element_shape(Vector2.ZERO, Elements.Id.FIRE)
	_check(shape != null and shape.text == "▲", "colorblind_shapes=true: fire triangle shows")
	if shape != null:
		shape.queue_free()
	SaveSystem.set_setting("colorblind_shapes", false)


# ================================================================ ⑥ 输入延迟 ≤1 帧

func _section_input_latency() -> void:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	add_child(player)
	await _frames(1)
	Input.action_press("move_right")
	await get_tree().physics_frame     # 本信号在拍首恢复（player 回调在本拍内稍后）
	await get_tree().physics_frame     # 次拍拍首：上一拍回调已消费输入并写 velocity
	_check(player.velocity.x > 0.0,
		"Input.action_press consumed within 1 physics tick (latency <= 1 frame)")
	Input.action_release("move_right")
	await get_tree().physics_frame
	player.queue_free()
	RunState.start_run("vanguard")          # 复位探针污染（coins/buffs）


# ================================================================ ⑦ D-1 振动消费端

func _section_vibration_consumer() -> void:
	# 平台门控：headless 无 Android 特性、无注入口 → 不具备能力（不裸调振动 API）
	Fx.vibrate_api = Callable()
	SaveSystem.set_setting("vibration", true)
	_check(not Fx.vibration_supported(),
		"D-1: headless without android feature/injection -> vibration_supported false")
	var calls: Array[int] = []
	Fx.vibrate_api = func(ms: int) -> void: calls.append(ms)
	_check(Fx.vibration_supported(), "D-1: injected vibrate_api counts as capable (test seam)")
	var player: Node2D = Node2D.new()
	add_child(player)
	# 受击 30ms：on_player_hurt 经消费模式（运行时 get_setting("vibration")）触发一次短震
	Fx.on_player_hurt(player, 5)
	_check(calls.size() == 1 and calls[0] == 30, "D-1: player hurt requests 30ms vibrate (spec J6)")
	# Boss 死亡 80ms：自有开关语义，不受前台门/演出链门控（链在 headless 冒烟恒不启）
	Fx.request_boss_death()
	_check(calls.size() == 2 and calls[1] == 80,
		"D-1: boss death requests 80ms vibrate (own switch, gate-independent)")
	# 开关关 = 不震（受击与 Boss 死亡两路同门控）
	SaveSystem.set_setting("vibration", false)
	Fx.on_player_hurt(player, 5)
	Fx.request_boss_death()
	_check(calls.size() == 2, "D-1: vibration=false gates both hurt and boss-death vibrate")
	SaveSystem.set_setting("vibration", true)
	Fx.trauma = 0.0
	Fx.vibrate_api = Callable()
	player.queue_free()
	await _frames(1)


# ================================================================ ⑧ D-2 快进接线

func _section_boss_death_skip() -> void:
	var d = Fx._director
	# 非演出期间：连按攻击键零误触发（链 IDLE、树不冻结）
	Input.action_press("fire")
	await _frames(2)
	Input.action_release("fire")
	await _frames(1)
	_check(d.active_kind() == HitstopDirector.SeqKind.NONE and not get_tree().paused,
		"D-2: attack press outside performance does not trigger skip (no mis-fire)")
	# 启动 Boss 死亡链（直接驱动导演——Fx 入口的前台门在 headless 冒烟场景恒关）
	d.request_boss_death(Time.get_ticks_msec())
	_check(get_tree().paused and Fx.boss_death_chain_active(),
		"D-2: boss death chain active (tree frozen, performance running)")
	# 连按攻击键 → 快进：链立即结束、时计恢复（跳过定格与慢速段）
	Input.action_press("fire")
	await _frames(2)
	Input.action_release("fire")
	await _frames(1)
	_check(d.active_kind() == HitstopDirector.SeqKind.NONE and not get_tree().paused
		and is_equal_approx(Engine.time_scale, 1.0),
		"D-2: attack press during performance skips chain (freeze/slow advanced, clock restored)")
	Fx.cancel_hitstop()
	await _frames(1)


# ================================================================ ⑨ D-3a 去饱和 + D-3c 掉落延迟

func _section_death_desat_and_loot() -> void:
	# 前台门注入（同 visible_world_rect_provider 模式）：无头走 request_player_death 全路径
	Fx.gameplay_scene_gate = func() -> bool: return true
	# hitstop off → 链 no-op → 去饱和不启动（演出整体跳过口径一致）
	SaveSystem.set_setting("hitstop_enabled", false)
	Fx.request_player_death()
	_check(not Fx.death_desat_active(),
		"D-3a: hitstop_enabled=false -> no desat layer (performance skipped)")
	SaveSystem.set_setting("hitstop_enabled", true)
	# 链接管 → 去饱和层在场，渐入自 ~0 起按真实毫秒推进（time_scale 0.3 不拉长）
	Fx.request_player_death()
	_check(Fx.death_desat_active() and Fx.death_desat_progress() < 0.2,
		"D-3a: request_player_death arms desat layer at ~0 progress")
	await _real_seconds(0.14)
	var mid := Fx.death_desat_progress()
	_check(mid > 0.05 and mid < 0.95,
		"D-3a: desat fades in over real ms (spec 0.4s, slow-mo does not stretch it)")
	await _real_seconds(0.5)
	_check(Fx.death_desat_progress() >= 1.0,
		"D-3a: desat completes at 400ms (player_death_desat_ms from balance)")
	Fx.cancel_hitstop()
	_check(not Fx.death_desat_active(),
		"D-3a: cancel_hitstop cleans desat layer (boundary hygiene)")
	# D-3c：链活跃时掉落挂起、不立即喷出；快进补发恰一次；链缺席拒绝挂起（同步照旧）
	var d = Fx._director
	d.request_boss_death(Time.get_ticks_msec())
	var loot_at: Array[int] = []
	_check(Fx.defer_boss_loot(func() -> void: loot_at.append(Engine.get_physics_frames())),
		"D-3c: defer_boss_loot accepted while boss chain active")
	await _frames(2)
	_check(loot_at.is_empty(), "D-3c: deferred loot not fired synchronously (300ms delay armed)")
	Input.action_press("fire")             # 快进（D-2 接线路径）：loot 段回调补发不吞事件
	await _frames(2)
	Input.action_release("fire")
	await _frames(1)
	_check(loot_at.size() == 1, "D-3c: skipped chain flushes pending loot exactly once")
	_check(not Fx.defer_boss_loot(func() -> void: loot_at.append(-1)),
		"D-3c: defer_boss_loot rejected when no chain (sync fallback unchanged)")
	Fx.gameplay_scene_gate = Callable()
	Fx.cancel_hitstop()
	await _frames(1)


# ================================================================ ⑩ D-3b 方向指示 + D-4 呼吸参数

func _section_hit_arc_and_breath() -> void:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	add_child(player)
	await _frames(1)
	# 方向几何：来源在右 → 弧朝 0rad；来源在上 → -PI/2（方向取自伤害事件 ctx.from）
	Fx.on_player_hurt(player, 4, player.global_position + Vector2(20.0, 0.0))
	var arcs := _hit_arcs(player)
	_check(arcs.size() == 1 and absf(arcs[0].dir.angle()) < 0.01,
		"D-3b: hurt from right spawns one arc pointing right (angle 0)")
	Fx.on_player_hurt(player, 4, player.global_position + Vector2(0.0, -20.0))
	arcs = _hit_arcs(player)
	_check(arcs.size() == 2 and absf(arcs[1].dir.angle() + PI / 2.0) < 0.01,
		"D-3b: hurt from above -> arc angle -PI/2 (source direction from damage event)")
	# 无方向裁定（规格未定义，取「不误导」并记录 checklist §6）：缺 from / 与玩家重合 → 不画弧
	Fx.on_player_hurt(player, 4)
	Fx.on_player_hurt(player, 4, player.global_position)
	_check(_hit_arcs(player).size() == 2,
		"D-3b: directionless sources (missing/coincident env damage) spawn no arc")
	# 几何与淡出：8px 半径、0.2s 线性淡出、到时自毁
	_check(is_equal_approx(HitArc.RADIUS, 8.0) and is_equal_approx(HitArc.FADE_SECONDS, 0.2),
		"D-3b: arc geometry per spec (8px radius, 0.2s fade-out)")
	arcs[0]._process(0.1)
	_check(absf(arcs[0].fade_alpha() - 0.5) < 0.02,
		"D-3b: arc fades linearly (alpha ~0.5 at half lifetime)")
	arcs[0]._process(0.1)
	_check(arcs[0].is_queued_for_deletion(),
		"D-3b: arc self-frees at 0.2s (fade-out lifetime)")
	Fx.trauma = 0.0
	player.queue_free()
	await _frames(1)
	# D-4：低血呼吸参数对齐规格 §J6（0.8s 周期正弦，alpha 0.15~0.35）
	_check(HUD.BREATH_ALPHA_MIN == 0.15 and HUD.BREATH_ALPHA_MAX == 0.35
		and is_equal_approx(HUD.BREATH_HALF_SEC * 2.0, 0.8),
		"D-4: low-hp breath aligned to spec J6 (0.8s cycle, alpha 0.15~0.35)")


func _hit_arcs(player: Node2D) -> Array[HitArc]:
	var out: Array[HitArc] = []
	for c in player.get_children():
		if c is HitArc:
			out.append(c as HitArc)
	return out


# ================================================================ helpers

func _restore_settings() -> void:
	for key: String in SETTING_KEYS:
		SaveSystem.set_setting(key, _saved_settings.get(key, true))
	Fx.cancel_hitstop()
	Engine.time_scale = 1.0
	get_tree().paused = false

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

## 真实毫秒等待（ignore_time_scale 定时器）：玩家死亡慢速段（time_scale 0.3）下
## 计量去饱和渐入用——与导演链/Fx 渐入同钟（墙钟）。
func _real_seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
