extends Node
## 打击感服务（m0-t12 完整实现）：hitstop / 震屏 trauma / 白闪 / 伤害数字 / 粒子。
## _ready 置 PROCESS_MODE_ALWAYS：hitstop 暂停树后，本节点（及挂其下的表现物）仍照常处理。
## J-A：hitstop v2——冻结/慢速时序由 HitstopDirector（纯逻辑状态机）驱动，本类只提供
## apply_state/schedule 生产实现并逐帧注入真实毫秒；导演缺席（脚本缺失）时回退 v1
## 常量路径，导演在位但 hitstop_enabled=false 或 balance 加载失败时请求全部 no-op。

const DIRECTOR_SCRIPT_PATH := "res://fx/hitstop_director.gd"
const FLASH_SHADER := preload("res://fx/white_flash.gdshader")
const FLASH_DECAY_PER_SEC := 6.0      # 命中白闪 1→0 约 0.17s
const TELEGRAPH_DECAY_PER_SEC := 2.0  # 蓄力/引信红闪更持久（约 0.5s）
const HITSTOP_CRIT_MS := 40
const HITSTOP_KILL_MS := 60

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

var trauma := 0.0                     # 震屏强度，相机每渲染帧调 decay_step() 衰减
var _restore_timer: SceneTreeTimer = null   # 当前"权威"恢复定时器（最长剩余者）
var _flash: Dictionary = {}           # instance_id -> {item, mat, amount, speed}（键用 id：宿主释放后不悬垂）
var _director: Object = null          # HitstopDirector（J-A v2；缺席 → v1 常量回退）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_director()
	if not EventBus.status_applied.is_connected(_on_status_applied):
		EventBus.status_applied.connect(_on_status_applied)

## 懒构造 v2 导演（脚本缺失/解析失败 → null → v1 回退；balance 加载失败由导演
## load_ok=false 门控全部请求 no-op，fail-closed 不崩游戏）。
func _init_director() -> void:
	var script: Variant = load(DIRECTOR_SCRIPT_PATH)
	if script == null or not (script as Script).can_instantiate():
		return
	var d = (script as Script).new()
	d.apply_state = _apply_time_state
	d.schedule = _schedule_real_ms
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

## 震屏：trauma 取 max；duration 仅占位（衰减率由 decay_step 契约固定 ×0.9/帧）。
## m1-t18 juice v1.5：hitstop 冻结拍（树暂停中）早退不吃震屏——冻结期叠的 trauma
## 会在解冻前被白白衰减掉，且冻帧上无位移可看。
func shake(strength: float, _duration: float) -> void:
	var tree := get_tree()
	if tree != null and tree.paused:
		return
	trauma = maxf(trauma, strength)

## 玩家设置是相机振幅倍率，而非 trauma 的逻辑值：同一拍多相机时不能重复缩放 trauma。
## 读取处夹到 0..1，损坏档/未来版本的异常数值不会放大到设置允许范围外。
func screen_shake_scale() -> float:
	return clampf(float(SaveSystem.get_setting("screen_shake", 1.0)), 0.0, 1.0)

## 由相机每渲染帧调用（brief 契约：×0.9，300 帧后 ≈0）。
func decay_step() -> void:
	trauma *= 0.9
	if trauma < 0.001:
		trauma = 0.0

func on_roll(player: Node2D) -> void:
	_puff(player.global_position, Color(0.85, 0.85, 0.85), 6)

func on_player_hurt(player: Node2D, _amount: int) -> void:
	shake(2.0, 0.12)
	_flash_item(_find_sprite(player), Color(1.0, 0.3, 0.3), FLASH_DECAY_PER_SEC)

func on_enemy_hit(enemy: Node2D, ctx: Dictionary) -> void:
	if bool(ctx.get("telegraph", false)):
		# 蓄力/引信预警：红闪，无伤害数字、无遥测
		_flash_item(_find_sprite(enemy), Color(1.0, 0.25, 0.2), TELEGRAPH_DECAY_PER_SEC)
		return
	var amount := int(ctx.get("amount", 0))
	var is_crit := bool(ctx.get("is_crit", false))
	_flash_item(_find_sprite(enemy), Color.WHITE, FLASH_DECAY_PER_SEC)
	spawn_damage_number(enemy.global_position, amount, is_crit)
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
	shake(1.0, 0.1)
	_puff(at, Color(1.0, 0.55, 0.25), 12)


# ---- J-A v2 请求入口（导演缺席时回退 v1 等价行为；no-op 门控在导演内） ----

## Boss 阶段切换（J1）：120ms 冻结 + 0.3× 慢速 240ms。
func request_boss_phase() -> void:
	if _director != null:
		_director.request_boss_phase(Time.get_ticks_msec())
	else:
		hitstop(BossBase.PHASE_HITSTOP_MS)   # v1 回退：仅冻结（与阶段常量同源）

## Boss 死亡定格链（J7）。前台为工具/测试场景时不接管（同 DeathRecorder
## 前台门模式）：脑测/套件里 Boss 死亡不会冻结 GdUnit 树。
func request_boss_death() -> void:
	if _director == null or not DeathRecorder.is_gameplay_scene_active():
		return
	_director.request_boss_death(Time.get_ticks_msec())

## 玩家死亡慢速（J1）。前台门同上（测试致死路径不污染套件时序）。
func request_player_death() -> void:
	if _director == null or not DeathRecorder.is_gameplay_scene_active():
		return
	_director.request_player_death(Time.get_ticks_msec())

## Boss 死亡链快进（J7 连按攻击键；输入接线在 J-C/J-D 收口）。
func request_skip() -> void:
	if _director != null:
		_director.skip()

## 伤害数字：简单 spawn + tween 上飘淡出 + 自毁（M0 命中频率下短命对象分配有界，
## 池化收益低——控制器允许二选一，此处取简单方案）。暴击放大 1.5×。
func spawn_damage_number(pos: Vector2, amount: int, is_crit: bool) -> Label:
	if not bool(SaveSystem.get_setting("damage_numbers", true)):
		return null
	var label := Label.new()
	label.name = "DamageNumber"
	label.text = str(amount)
	label.position = pos + Vector2(-4.0, -14.0)
	label.z_index = 50
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if is_crit else Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	if is_crit:
		label.scale = Vector2(1.5, 1.5)
	add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 10.0, 0.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(label.queue_free).set_delay(0.55)
	return label

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
