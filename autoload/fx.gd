extends Node
## 打击感服务（m0-t12 完整实现）：hitstop / 震屏 trauma / 白闪 / 伤害数字 / 粒子。
## _ready 置 PROCESS_MODE_ALWAYS：hitstop 暂停树后，本节点（及挂其下的表现物）仍照常处理。
## J-A：hitstop v2——冻结/慢速时序由 HitstopDirector（纯逻辑状态机）驱动，本类只提供
## apply_state/schedule 生产实现并逐帧注入真实毫秒；导演缺席（脚本缺失）时回退 v1
## 常量路径，导演在位但 hitstop_enabled=false 或 balance 加载失败时请求全部 no-op。

const DIRECTOR_SCRIPT_PATH := "res://fx/hitstop_director.gd"
const BALANCE_PATH := "res://data/balance.json"
const FLASH_SHADER := preload("res://fx/white_flash.gdshader")
const DESAT_SHADER := preload("res://fx/desat.gdshader")   # J1/D-3a：玩家死亡去饱和
const FLASH_DECAY_PER_SEC := 6.0      # 命中白闪 1→0 约 0.17s
const TELEGRAPH_DECAY_PER_SEC := 2.0  # 蓄力/引信红闪更持久（约 0.5s）
const HITSTOP_CRIT_MS := 40
const HITSTOP_KILL_MS := 60
## J2 trauma 来源表键（balance.json juice 节；数值唯一出处）。
const TRAUMA_SOURCE_KEYS: Array[String] = [
	"shake_player_hurt", "shake_explosion", "shake_boss_phase", "shake_boss_death", "shake_kill",
]

const ELEMENT_SHAPES := {
	Elements.Id.FIRE: "▲",    # 火 = 三角
	Elements.Id.ICE: "◆",     # 冰 = 菱形
	Elements.Id.POISON: "●",  # 毒 = 圆
	Elements.Id.SHOCK: "ϟ",   # 电 = 闪电折线
}
const ELEMENT_COLORS := {
	Elements.Id.FIRE: Color(1.0, 0.28, 0.12),
	Elements.Id.ICE: Color(0.2, 0.9, 1.0),
	Elements.Id.POISON: Color(0.35, 1.0, 0.25),
	Elements.Id.SHOCK: Color(0.75, 0.35, 1.0),
}

var trauma := 0.0                     # J2 v2：归一化震屏能量 [0,1]（注入累加 clamp 1.0，相机每渲染帧调 decay_step(delta) 按 1.6/s 线性衰减）
var _restore_timer: SceneTreeTimer = null   # 当前"权威"恢复定时器（最长剩余者）
var _flash: Dictionary = {}           # instance_id -> {item, mat, amount, speed}（键用 id：宿主释放后不悬垂）
var _director: Object = null          # HitstopDirector（J-A v2；缺席 → v1 常量回退）
## J2/J5 juice 参数（本卡键自校验装载，fail-soft 回落规格默认；见 load_juice_params）。
var _params: Dictionary = _default_juice_params()
var _trauma_sources: Dictionary = {}  # TRAUMA_SOURCE_KEYS 子集（apply_juice_params 派生）
## J5 连击持有（纯逻辑 RefCounted；成员即初始化兜底，_ready 再按 balance 重建）。
var _combo: ComboCounter = ComboCounter.new()
## M3 J-C：池化条带播放器（火花/枪口焰/碎片环）。启动建满常驻，热路径零分配；
## 挂本节点下继承 PROCESS_MODE_ALWAYS（hitstop 冻结期表现照常）。
var particles: ParticlesPool = null
## J6 振动消费端（D-1 补课）：设置键 vibration 的运行时读取方（消费模式同
## screen_shake——消费方运行时 get_setting）。平台门控：规格「仅 Android 生效」，
## 桌面/无头不裸调 Input.vibrate_handheld；测试注入口有效时视为具备能力
## （headless 冒烟经此机检调用链）。
var vibrate_api: Callable = Callable()
## J1/D-3a：玩家死亡去饱和渐入层（挂 current_scene → 死亡结算换场景自动回收）。
var _death_desat: CanvasLayer = null
var _desat_mat: ShaderMaterial = null
var _desat_start_ms := -1             # 真实毫秒起点（Time.get_ticks_msec，与导演链同钟）
## J7/D-3c：Boss 战利品延迟喷出挂起队列——导演 loot 段开始（或快进/接管补发）统一 flush。
var _loot_pending: Array[Callable] = []
## 前台门注入缝（D-3a 机检用，同 visible_world_rect_provider 模式）：有效时替代
## DeathRecorder.is_gameplay_scene_active——无头冒烟经此走 request_player_death 全路径。
var gameplay_scene_gate: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_director()
	apply_juice_params(load_juice_params(BALANCE_PATH))
	particles = ParticlesPool.new()       # J-C：粒子池在启动时建满（同 AudioMgr POOL 先例）
	particles.name = "ParticlesPool"
	add_child(particles)
	if not EventBus.status_applied.is_connected(_on_status_applied):
		EventBus.status_applied.connect(_on_status_applied)
	if not EventBus.player_damaged.is_connected(_on_player_damaged_combo_reset):
		EventBus.player_damaged.connect(_on_player_damaged_combo_reset)   # J5：受击重置连击

## 懒构造 v2 导演（脚本缺失/解析失败 → null → v1 回退；balance 加载失败由导演
## load_ok=false 门控全部请求 no-op，fail-closed 不崩游戏）。
func _init_director() -> void:
	var script: Variant = load(DIRECTOR_SCRIPT_PATH)
	if script == null or not (script as Script).can_instantiate():
		return
	var d = (script as Script).new()
	d.apply_state = _apply_time_state
	d.schedule = _schedule_real_ms
	d.on_loot_delay_started = _flush_boss_loot   # J7/D-3c：loot 段开始（或快进/接管补发）时喷出挂起掉落
	d.load_balance_file("res://data/balance.json")   # 失败 → load_ok=false → 请求全部 no-op
	_director = d

## 导演 apply_state 生产实现：冻结=树暂停；恢复/慢速=Engine.time_scale
## （判定在请求前已完成，此处只是表现层时间包裹）。
func _apply_time_state(paused: bool, time_scale: float) -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = paused
	Engine.time_scale = time_scale

## 导演 schedule 生产实现：ignore_time_scale 定时器（v1 hitstop 同款），暂停中照走。
func _schedule_real_ms(delay_ms: int, callback: Callable) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(float(delay_ms) / 1000.0, true, false, true).timeout.connect(callback)

## 帧冻结：暂停树，真实毫秒后恢复（create_timer ignore_time_scale，brief 契约）。
## 并发调用取更长：只认剩余时间最长的"权威"定时器恢复；换权威时**断开旧定时器**的
## 恢复回调（fix1：否则旧定时器到点仍会触发解冻——暴击 40ms + 同帧击杀 60ms 只冻 40ms）。
## 注：期限比较用 SceneTreeTimer.time_left（同一时钟域），不与 Time.get_ticks_msec 混比
## （本机 headless 实测 process delta 与墙钟可偏差 ~20%）。
func hitstop(ms: int) -> void:
	if _director != null:
		_director.request_freeze(ms, Time.get_ticks_msec())   # 总开关/加载门控在导演内
		return
	if not bool(SaveSystem.get_setting("hitstop_enabled", true)):
		return                          # v1 回退路径同样遵守总开关
	if ms <= 0:
		return                          # 0/负值：不冻结（也不占用恢复定时器）
	var tree := get_tree()
	var t := tree.create_timer(ms / 1000.0, true, false, true)
	if _restore_timer != null and is_instance_valid(_restore_timer) \
			and _restore_timer.time_left >= t.time_left:
		return                          # 已有更长的 hitstop 在生效
	if _restore_timer != null and is_instance_valid(_restore_timer):
		_restore_timer.timeout.disconnect(_on_hitstop_elapsed)
	_restore_timer = t
	tree.paused = true
	t.timeout.connect(_on_hitstop_elapsed)

func _on_hitstop_elapsed() -> void:
	get_tree().paused = false
	_restore_timer = null

## 立即结束仍在生效的 hitstop。场景/测试边界可用它清理 Autoload 持有的权威
## 定时器；必须先断开回调，避免旧定时器稍后再次改写新一轮冻结状态。
func cancel_hitstop() -> void:
	if _director != null:
		_director.cancel()      # J-A：同时结束慢速链并恢复时计（幂等）
	if _restore_timer != null and is_instance_valid(_restore_timer) \
			and _restore_timer.timeout.is_connected(_on_hitstop_elapsed):
		_restore_timer.timeout.disconnect(_on_hitstop_elapsed)
	_restore_timer = null
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	_cancel_death_desat()       # J1/D-3a：演出整体取消时去饱和层一并回收（边界卫生）

## J2 v2 注入口：按 balance.json juice 来源表命名注入（trauma += 表值后 clamp [0,1]）。
## 「单事件注入 ≤0.5」由来源表数据保证（shake_boss_death 1.0 为 J7 唯一例外）；
## 未知来源 fail-soft 归 0（不震不崩）。保留 v1.5 契约：hitstop 冻结拍（树暂停中）
## 早退——冻结期叠的 trauma 会在解冻前被白白衰减掉，且冻帧上无位移可看。
func shake(source: String) -> void:
	var tree := get_tree()
	if tree != null and tree.paused:
		return
	add_trauma(trauma_source_amount(source))

## v2 注入原语：累加并 clamp 峰值 1.0（晕动防线：trauma 峰值 ≤1.0）。
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

## 来源表查询（未知来源 → 0.0）：测试断言与调用方共用，balance 为唯一数值出处。
func trauma_source_amount(source: String) -> float:
	return float(_trauma_sources.get(source, 0.0))

## 玩家设置是相机振幅倍率，而非 trauma 的逻辑值：同一拍多相机时不能重复缩放 trauma。
## 读取处夹到 0..1，损坏档/未来版本的异常数值不会放大到设置允许范围外。
func screen_shake_scale() -> float:
	return clampf(float(SaveSystem.get_setting("screen_shake", 1.0)), 0.0, 1.0)

## 由相机每渲染帧调用（J2 v2 契约：线性衰减 trauma_decay_per_s × 渲染 delta）。
## delta 为渲染帧长——表现层计时例外（与 hitstop 真实毫秒同口径，判定无关）；
## 冻结拍树暂停时相机 _process 停摆，衰减随之自然暂停（trauma 跨冻结保持）。
func decay_step(delta: float) -> void:
	trauma = maxf(trauma - trauma_decay_per_s() * delta, 0.0)


# ---- J2/J5 juice 参数装载（本卡键自校验，fail-soft） ----

## 规格默认（balance 缺失/坏键时回落——表现参数缺失降级为无演出/默认手感，不崩）。
static func _default_juice_params() -> Dictionary:
	return {
		"trauma_decay_per_s": 1.6,
		"trauma_offset_px": 8.0,
		"trauma_rot_deg": 2.0,
		"shake_player_hurt": 0.3,
		"shake_explosion": 0.4,
		"shake_boss_phase": 0.5,
		"shake_boss_death": 1.0,
		"shake_kill": 0.15,
		"combo_window_ms": 1200.0,
		"combo_pitch_step": 0.02,
		"combo_pitch_max_steps": 6.0,
		"vibration_hurt_ms": 30.0,
		"vibration_boss_death_ms": 80.0,
	}

## 只对本卡新增键做「已知即校验类型」（数值型否则回落默认）；J-A 导演加载器对
## 未知键保持忽略——其 fail-closed 必需键集不含表现参数，导演不因本卡键损坏而 no-op。
func load_juice_params(path: String) -> Dictionary:
	var out := _default_juice_params()
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var juice: Variant = (parsed as Dictionary).get("juice")
	if typeof(juice) != TYPE_DICTIONARY:
		return out
	for key: String in out.keys():
		var v: Variant = (juice as Dictionary).get(key)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			out[key] = float(v)
	return out

## 应用装载结果并按 balance 重建连击器（窗口/步长/封顶唯一出处为 balance juice 节）。
func apply_juice_params(p: Dictionary) -> void:
	_params = p
	_trauma_sources.clear()
	for key in TRAUMA_SOURCE_KEYS:
		_trauma_sources[key] = float(p.get(key, 0.0))
	_combo = ComboCounter.new(int(combo_window_ms()), combo_pitch_step(),
		int(combo_pitch_max_steps()))

func trauma_decay_per_s() -> float:
	return float(_params.get("trauma_decay_per_s", 1.6))

func trauma_offset_px() -> float:
	return float(_params.get("trauma_offset_px", 8.0))

func trauma_rot_deg() -> float:
	return float(_params.get("trauma_rot_deg", 2.0))

func combo_window_ms() -> float:
	return float(_params.get("combo_window_ms", 1200.0))

func combo_pitch_step() -> float:
	return float(_params.get("combo_pitch_step", 0.02))

func combo_pitch_max_steps() -> float:
	return float(_params.get("combo_pitch_max_steps", 6.0))

func vibration_hurt_ms() -> float:
	return float(_params.get("vibration_hurt_ms", 30.0))

func vibration_boss_death_ms() -> float:
	return float(_params.get("vibration_boss_death_ms", 80.0))

# ---- J6 振动消费端（D-1 补课；规格 §2 J6「受击 30ms / Boss 死亡 80ms，仅 Android 生效」）----

## 平台能力：Android 特性在位才允许触真 API；测试注入口有效视为具备能力。
## 桌面/无头在此早退——不裸调 Input.vibrate_handheld（无害 no-op 也不调，零噪音）。
func vibration_supported() -> bool:
	if vibrate_api.is_valid():
		return true
	return OS.has_feature("android")

## 振动请求原语：开关（设置键 vibration，默认开）→ 平台能力双重门控后才调用。
## 时长为表现层参数（balance.json juice 节唯一出处，fail-soft 回落规格默认）。
func request_vibrate(ms: int) -> void:
	if ms <= 0 or not bool(SaveSystem.get_setting("vibration", true)):
		return
	if not vibration_supported():
		return
	if vibrate_api.is_valid():
		vibrate_api.call(ms)
	else:
		Input.vibrate_handheld(ms)

# ---- J5 连击持有缝（命中音音高） ----

## 命中上报：远程结算点 / 近战命中缝调用（每有效命中一次）。连击窗口为表现层
## 计时（真实毫秒，与 hitstop 同口径，判定无关——只驱动音高，不碰任何数值）。
func on_combo_hit() -> void:
	_combo.on_hit(Time.get_ticks_msec())

## 命中音音高查询：1.0 + 0.02 × min(combo, 封顶档数)（消费点总紧跟 on_combo_hit）。
func combo_pitch() -> float:
	return _combo.pitch()

## 换武器重置（WeaponRig.switch_slot 调用）。
func on_weapon_switched() -> void:
	_combo.on_weapon_switch(Time.get_ticks_msec())

## 受击重置（EventBus.player_damaged 订阅）。
func _on_player_damaged_combo_reset(_amount: int, _fatal: bool) -> void:
	_combo.on_player_hurt(Time.get_ticks_msec())

func on_roll(player: Node2D) -> void:
	_puff(player.global_position, Color(0.85, 0.85, 0.85), 6)

func on_player_hurt(player: Node2D, _amount: int, from := Vector2.INF) -> void:
	shake("shake_player_hurt")   # J2 v2：来源表注入（+0.3）
	_flash_item(_find_sprite(player), Color(1.0, 0.3, 0.3), FLASH_DECAY_PER_SEC)
	spawn_hit_arc(player, from)                 # J6/D-3b：受击方向指示（v1 红晕之上叠加）
	request_vibrate(int(vibration_hurt_ms()))   # J6/D-1：受击短震 30ms（开关+平台双门控）

## J6 受击方向指示（D-3b 补课；规格 §2 J6「8px 弧形闪光指向伤害来源，0.2s 淡出」）。
## from 取伤害事件 ctx["from"]（来源位置，player.gd 受击缝传入）。方向裁定（规格未
## 定义无方向语义，取「不误导」并记录于 checklist §6 D-3b）：from 缺失（INF）/非有限/
## 与玩家重合（环境 DOT 等无来源）不生成弧。实现见 fx/hit_arc.gd（纯 _draw 矢量弧，
## 无贴图/无缩放/无过滤）。
func spawn_hit_arc(player: Node2D, from: Vector2) -> HitArc:
	if player == null or not is_instance_valid(player) or not from.is_finite():
		return null
	var dir := from - player.global_position
	if dir.length_squared() < 1.0:            # <1px 视为无方向（来源与玩家重合）
		return null
	var arc := HitArc.new()
	arc.name = "HitArc"
	arc.dir = dir.normalized()
	arc.z_index = 45                          # 玩家之上、跳字(50)之下
	player.add_child(arc)
	return arc

func on_enemy_hit(enemy: Node2D, ctx: Dictionary) -> void:
	if bool(ctx.get("telegraph", false)):
		# 蓄力/引信预警：红闪，无伤害数字、无遥测
		_flash_item(_find_sprite(enemy), Color(1.0, 0.25, 0.2), TELEGRAPH_DECAY_PER_SEC)
		return
	var amount := int(ctx.get("amount", 0))
	var is_crit := bool(ctx.get("is_crit", false))
	_flash_item(_find_sprite(enemy), Color.WHITE, FLASH_DECAY_PER_SEC)
	spawn_damage_number(enemy.global_position, amount, is_crit, _tick_element_of(ctx))
	particles.play_spark(enemy.global_position, is_crit, int(ctx.get("element", Elements.Id.NONE)))   # J3：池化火花三态
	spawn_element_shape(enemy.global_position, int(ctx.get("element", Elements.Id.NONE)))
	var proc_element := int(ctx.get("proc_element", Elements.Id.NONE))
	if proc_element != int(ctx.get("element", Elements.Id.NONE)):
		spawn_element_shape(enemy.global_position + Vector2(10.0, 0.0), proc_element)
	Telemetry.log_row(["hit", Engine.get_physics_frames(), amount, 1 if is_crit else 0])
	if is_crit:
		hitstop(HITSTOP_CRIT_MS)        # 暴击 hitstop（brief：40ms + 数字放大 1.5×）

## 击杀 juice v2（J1）：80ms 缓出（20ms 冻结 + 60ms 线性恢复）+ 多杀窗口，经导演。
## EventBus.enemy_killed 只有 id 无位置，故由房间层（持有敌人节点）在击杀缝处调用。
func on_enemy_killed(at: Vector2) -> void:
	if _director != null:
		_director.request_kill(Time.get_ticks_msec())   # 表现层墙钟（多杀窗口基准，判定无关）
	else:
		hitstop(HITSTOP_KILL_MS)                        # v1 回退：60ms 冻结
	shake("shake_kill")                             # J2 v2：v1 击杀震屏的 v2 移植（来源表 +0.15）
	_puff(at, Color(1.0, 0.55, 0.25), 12)
	particles.play_kill_shard(at)         # J3：v1 爆散之上叠加 6 帧碎片环（掉落吸附保持 v1）


# ---- J-A v2 请求入口（导演缺席时回退 v1 等价行为；no-op 门控在导演内） ----

## Boss 阶段切换（J1）：120ms 冻结 + 0.3× 慢速 240ms。
func request_boss_phase() -> void:
	if _director != null:
		_director.request_boss_phase(Time.get_ticks_msec())
	else:
		hitstop(BossBase.PHASE_HITSTOP_MS)   # v1 回退：仅冻结（与阶段常量同源）

## 前台门（生产 = DeathRecorder 前台门模式；测试经 gameplay_scene_gate 注入）。
func _gameplay_scene_active() -> bool:
	if gameplay_scene_gate.is_valid():
		return bool(gameplay_scene_gate.call())
	return DeathRecorder.is_gameplay_scene_active()

## Boss 死亡定格链（J7）。前台为工具/测试场景时不接管（同 DeathRecorder
## 前台门模式）：脑测/套件里 Boss 死亡不会冻结 GdUnit 树。
func request_boss_death() -> void:
	# J6/D-1：Boss 死亡振动 80ms——自有开关（vibration 键），不随演出链/前台门门控
	#（链被总开关跳过时振动仍属受击反馈的一部分；门控内部化，桌面/无头天然 no-op）。
	request_vibrate(int(vibration_boss_death_ms()))
	if _director == null or not _gameplay_scene_active():
		return
	# J2：Boss 死亡 trauma 1.0（J7 唯一例外值，读来源表）；须先注入再启链——
	# 链启动即冻结树，后注会被 v1.5 冻结拍早退契约吞掉。
	shake("shake_boss_death")
	_director.request_boss_death(Time.get_ticks_msec())

## 玩家死亡慢速（J1）。前台门同上（测试致死路径不污染套件时序）。
func request_player_death() -> void:
	if _director == null or not _gameplay_scene_active():
		return
	_director.request_player_death(Time.get_ticks_msec())
	_start_death_desat()   # J1/D-3a：0.4s 去饱和渐入（链接管失败时自检不启动）

## Boss 死亡链快进（J7 连按攻击键；输入接线在 J-C/J-D 收口）。
func request_skip() -> void:
	if _director != null:
		_director.skip()

## Boss 死亡演出链是否在跑（D-2 快进轮询 / D-3c 掉落挂起共用门控）：
## 导演缺席或非 BOSS_DEATH 链 → false。
func boss_death_chain_active() -> bool:
	var d = _director
	return d != null \
		and (d as HitstopDirector).active_kind() == HitstopDirector.SeqKind.BOSS_DEATH

## J7 快进输入接线（D-2 补课，fx.gd:300 注释自认缺口的兑现）：Boss 死亡演出链
## 期间连按攻击键（既有 InputMap 动作 fire/touch_fire，不新增键位）跳过定格与慢速段
## ——respect 老玩家节奏（规格 §2 J7「可被跳过」）。轮询式与 player_driver 同习语；
## Fx 为 PROCESS_MODE_ALWAYS，冻结拍（树暂停）本函数照跑，首按即可跳过定格段。
## 门控：仅 BOSS_DEATH 链活跃时消费——非演出期间零误触发（链 IDLE 时按键零副作用）。
func _poll_boss_death_skip() -> void:
	if not boss_death_chain_active():
		return
	if Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("touch_fire"):
		request_skip()


# ---- J1 玩家死亡去饱和渐入（D-3a 补课；规格 §2 J1「0.3× 慢速 600ms + 去饱和渐入 0.4s」）----

## 渐入启动（链在跑才启动——hitstop off/加载失败时 request 已 no-op，这里按
## active_kind 自检，保证「演出整体跳过」口径一致）。全屏 hint_screen_texture
## shader（fx/desat.gdshader，亮度加权去饱和）：无缩放/无重采样/无过滤切换，
## 像素风红线不破。层挂 current_scene——死亡结算换场景时随宿主自动回收。
func _start_death_desat() -> void:
	var d = _director
	if d == null or (d as HitstopDirector).active_kind() != HitstopDirector.SeqKind.PLAYER_DEATH:
		return
	if death_desat_active():
		return                            # 已在渐入（重复致命不重启）
	var layer := CanvasLayer.new()
	layer.name = "DeathDesat"
	layer.layer = 100                    # HUD(10) 之上：死亡时刻全屏演出
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 自醒目：像素风红线
	_desat_mat = ShaderMaterial.new()
	_desat_mat.shader = DESAT_SHADER
	_desat_mat.set_shader_parameter("progress", 0.0)
	rect.material = _desat_mat
	layer.add_child(rect)
	var cs := get_tree().current_scene if get_tree() != null else null
	if cs != null:
		cs.add_child(layer)
	else:
		add_child(layer)                  # 工具边界：挂 Fx（cancel_hitstop 兜底回收）
	_death_desat = layer
	_desat_start_ms = Time.get_ticks_msec()

## 渐入推进（Fx._process 逐帧；真实毫秒口径与导演链一致——慢速段 time_scale 0.3
## 不拉长渐入，0.4s 在 600ms 链尾结算前完成）。时长 = 导演参数
## player_death_desat_ms（balance juice 唯一出处）。到 1.0 停更，层留宿主回收。
func _step_death_desat() -> void:
	if _desat_mat == null or _desat_start_ms < 0:
		return
	var d = _director
	var ms := int(d.param("player_death_desat_ms")) if d != null else 400
	var progress := clampf(
		float(Time.get_ticks_msec() - _desat_start_ms) / float(maxi(ms, 1)), 0.0, 1.0)
	_desat_mat.set_shader_parameter("progress", progress)
	if progress >= 1.0:
		_desat_mat = null
		_desat_start_ms = -1

func death_desat_active() -> bool:
	return _death_desat != null and is_instance_valid(_death_desat)

func death_desat_progress() -> float:
	if _desat_mat == null:
		return 1.0 if death_desat_active() else 0.0
	var v: Variant = _desat_mat.get_shader_parameter("progress")
	return float(v) if v != null else 0.0

func _cancel_death_desat() -> void:
	if _death_desat != null and is_instance_valid(_death_desat):
		_death_desat.queue_free()
	_death_desat = null
	_desat_mat = null
	_desat_start_ms = -1


# ---- J7 战利品延迟喷出（D-3c 补课；规格 §2 J7「战利品延迟 300ms 喷出（视觉聚焦）」）----

## 掉落挂起：Boss 死亡链在跑时，floor_scene 把掉落生成交给本队列，导演 loot 段
## 开始（定格+慢速走完，loot_delay_ms=300 段仍保持 0.3× 慢速）或快进/链接管补发时
## 统一 flush（快进不吞事件语义）。返回 true = 已挂起（调用方跳过同步掉落）；
## false = 链未接管（hitstop off/加载失败/前台门外）→ 调用方照旧同步掉落，零改动。
func defer_boss_loot(cb: Callable) -> bool:
	if not boss_death_chain_active():
		return false
	_loot_pending.append(cb)
	return true

## loot 段开始/快进/接管补发的统一喷出口（director.on_loot_delay_started 挂接）。
func _flush_boss_loot() -> void:
	if _loot_pending.is_empty():
		return
	var pending := _loot_pending.duplicate()
	_loot_pending.clear()
	for cb in pending:
		if cb.is_valid():                 # 宿主场景可能已释放（层间切换等）
			cb.call()

# ---- J4 伤害数字 v2 常量与视野裁剪缝（Juice v2 §2 J4；表现参数为规格直译，收口归 J-D） ----

const CRIT_BOUNCE_SEC := 0.18          # 暴击弹跳总时长：1.0 → 1.6 → 1.3
const CRIT_BOUNCE_PEAK := 1.6
const CRIT_BOUNCE_SETTLE := 1.3
const TICK_NUMBER_SCALE := 0.8         # 元素 tick 小号 0.8×

## 视野裁剪注入缝（J4 屏外目标不生成跳字）：测试注入返回世界矩形的 Callable；
## 未注入（生产默认）→ 视口 + 相机推导，无相机（脑测/工具场景）→ 不裁剪。
var visible_world_rect_provider := Callable()
## m4-k3：存在非 WHITE 光圈折叠色的存量伤害数字（光圈消失后的回落复位依据；
## 复位完成即清零回到常态零成本早退）。
var _aid_tinted := false

func _pos_on_screen(pos: Vector2) -> bool:
	var r := Rect2()
	if visible_world_rect_provider.is_valid():
		r = visible_world_rect_provider.call() as Rect2
	else:
		var vp := get_viewport()
		var cam := vp.get_camera_2d() if vp != null else null
		if cam == null:
			return true                   # 无相机：不裁剪（纯逻辑测试零相机依赖）
		var size := vp.get_visible_rect().size
		r = Rect2(cam.get_screen_center_position() - size * 0.5, size)
	return r.size == Vector2.ZERO or r.has_point(pos)

## 元素 tick 跳字判定（J4）：DOT（燃烧/中毒）与燎原毒火云结算以 source_type="status"
## 标记；色取结算点注入的 tick_element（DOT 结算点各 +1 行，判定无关——
## StatusComponent.apply_hit_context 不读该键）。无注入退化为白色小号 tick。
func _tick_element_of(ctx: Dictionary) -> int:
	if String(ctx.get("source_type", "")) != "status":
		return Elements.Id.NONE
	return int(ctx.get("tick_element", Elements.Id.NONE))

## 伤害数字：简单 spawn + tween 上飘淡出 + 自毁（M0 命中频率下短命对象分配有界，
## 池化收益低——控制器允许二选一，此处取简单方案）。
## J4 v2：暴击弹跳缓动（scale 1.0→1.6→1.3，0.18s，tween；既有上飘/淡出保留）；
## tick_element 非 NONE 时为元素 tick：元素色、0.8× 小号、不弹跳。既有三参调用零破坏。
func spawn_damage_number(pos: Vector2, amount: int, is_crit: bool,
		tick_element: int = Elements.Id.NONE) -> Label:
	if not bool(SaveSystem.get_setting("damage_numbers", true)):
		return null
	if not _pos_on_screen(pos):
		return null                       # J4 视野裁剪：屏外目标不生成跳字
	var label := Label.new()
	label.name = "DamageNumber"
	label.set_meta("aid_damage_number", true)   # m4-k3：折叠刷新的识别标记（同名兄弟会被
	label.text = str(amount)                    # 引擎自动改名 @Label@N，name 匹配不可靠）
	label.position = pos + Vector2(-4.0, -14.0)
	label.z_index = 50
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	var is_tick := tick_element != Elements.Id.NONE
	if is_tick:
		# 元素 tick：元素色小号，不弹跳（白色兜底 = 结算点未注入元素色）
		label.add_theme_color_override("font_color",
			ELEMENT_COLORS.get(tick_element, Color.WHITE) as Color)
		label.scale = Vector2(TICK_NUMBER_SCALE, TICK_NUMBER_SCALE)
	elif is_crit:
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		label.add_theme_color_override("font_color", Color.WHITE)
	add_child(label)
	# m4-k3（K-3 披露收口）：A2 光圈内伤害数字增亮折叠（BiomeFx.bullet_aid 同形，
	# 状态源/半径/强度走既有口径）。伤害数字不进光照参与集（T37 探针 +47 draw 已
	# 否决）——表现侧 self_modulate 写入零批处理成本、零判定影响；与下方既有
	# modulate:a 淡出 tween 正交（modulate × self_modulate 相乘）。无光圈 = WHITE。
	label.self_modulate = BiomeFx.light_aid_at(label.global_position)
	if label.self_modulate != Color.WHITE:
		_aid_tinted = true                   # 存量增亮标记：光圈消失后的回落复位依据
	if is_crit and not is_tick:
		# J4 暴击弹跳：1.0 → 1.6 → 1.3 共 0.18s（替代 v1 定值 1.5×；金描边既有保留）
		var bounce := label.create_tween()
		bounce.tween_property(label, "scale",
			Vector2(CRIT_BOUNCE_PEAK, CRIT_BOUNCE_PEAK), CRIT_BOUNCE_SEC * 0.5)
		bounce.tween_property(label, "scale",
			Vector2(CRIT_BOUNCE_SETTLE, CRIT_BOUNCE_SETTLE), CRIT_BOUNCE_SEC * 0.5)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 10.0, 0.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(label.queue_free).set_delay(0.55)
	return label


## m4-k3：伤害数字折叠色逐帧刷新（跟随玩家/光圈位移与 _vision_factor 缩径；光圈
## 消失后复位 WHITE——跳字挂本 autoload 不随楼层回收，跨层残留须回落）。常态
## （无光圈且无存量增亮）零成本早退；遍历用 get_child 索引式访问（热路径零分配），
## 以 meta 标记识别跳字（同名兄弟节点会被引擎自动改名 @Label@N，name 匹配不可靠；
## 元素形状/爆散粒子无标记，天然排除）。
func _refresh_damage_number_aid() -> void:
	var live := BiomeFx.light_aid_active()
	if not live and not _aid_tinted:
		return
	var tinted := false
	var n := get_child_count()
	for i in n:
		var c := get_child(i)
		if c is Label and (c as Label).has_meta("aid_damage_number"):
			var lbl := c as Label
			lbl.self_modulate = BiomeFx.light_aid_at(lbl.global_position)
			if lbl.self_modulate != Color.WHITE:
				tinted = true
	_aid_tinted = tinted

## 枪口焰消费入口（J3）：weapon_rig._fire_slot 开火缝调用；条带与类别 tint 预设在池内。
func spawn_muzzle_flash(pos: Vector2, angle: float, weapon_category: String) -> void:
	particles.play_muzzle(pos, angle, weapon_category)

## 色弱形状编码是颜色以外的第二视觉通道。M1 在每次元素命中位置短暂显示编码：
## 火=三角、冰=菱形、毒=圆、电=闪电折线；关闭设置时完全不创建表现节点。
func spawn_element_shape(pos: Vector2, element: int) -> Label:
	if not bool(SaveSystem.get_setting("colorblind_shapes", false)):
		return null
	var glyph := element_shape(element)
	if glyph.is_empty():
		return null
	var label := Label.new()
	label.name = "ElementShape"
	label.text = glyph
	label.position = pos + Vector2(5.0, -19.0)
	label.z_index = 51
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color",
		ELEMENT_COLORS.get(element, Color.WHITE) as Color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 8.0, 0.45)
	tw.tween_property(label, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(label.queue_free).set_delay(0.5)
	return label

## 状态达到阈值时再给一次偏左的形状确认；命中形状与状态形状都复用同一映射，
## 玩家无需仅凭红/青/绿/紫颜色判断“命中元素”或“异常已生效”。
func _on_status_applied(target: Node, element: int) -> void:
	if target is Node2D:
		spawn_element_shape((target as Node2D).global_position + Vector2(-10.0, -3.0), element)

static func element_shape(element: int) -> String:
	return String(ELEMENT_SHAPES.get(element, ""))

# ---- 内部：白闪 / 粒子 ----

func _process(delta: float) -> void:
	if _director != null:
		_director.tick(Time.get_ticks_msec())   # J-A：逐帧注入真实毫秒（热路径空闲即 O(1) 早退）
	_poll_boss_death_skip()                     # J7/D-2：演出链期间连按攻击键快进
	_step_death_desat()                         # J1/D-3a：玩家死亡去饱和渐入（真实毫秒）
	_refresh_damage_number_aid()                # m4-k3：A2 光圈内伤害数字折叠色逐帧刷新/回落
	if _flash.is_empty():
		return
	var done: Array[int] = []
	for id: int in _flash:
		var st: Dictionary = _flash[id]
		var item = st["item"]           # 无类型：宿主可能已 free（typed 赋值会报 freed instance）
		if not is_instance_valid(item):
			done.append(id)
			continue
		var amount: float = maxf(0.0, float(st["amount"]) - float(st["speed"]) * delta)
		(st["mat"] as ShaderMaterial).set_shader_parameter("flash_amount", amount)
		st["amount"] = amount
		if amount <= 0.0:
			done.append(id)
	for id in done:
		_flash.erase(id)

## 白闪目标：宿主名下 "Sprite"（Polygon2D/Sprite2D 等 CanvasItem）；缺失则跳过（纯逻辑测试宿主无外观）。
func _find_sprite(host: Node2D) -> CanvasItem:
	if host == null:
		return null
	return host.get_node_or_null("Sprite") as CanvasItem

func _flash_item(item: CanvasItem, color: Color, speed: float) -> void:
	if item == null:
		return
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != FLASH_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = FLASH_SHADER
		item.material = mat
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_amount", 1.0)
	_flash[item.get_instance_id()] = {"item": item, "mat": mat, "amount": 1.0, "speed": speed}

## 一次性 CPUParticles2D 爆散，0.8s 后自毁。
func _puff(at: Vector2, color: Color, count: int) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 40
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.35
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)
