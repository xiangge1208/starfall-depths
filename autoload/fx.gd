extends Node
## 打击感服务（m0-t12 完整实现）：hitstop / 震屏 trauma / 白闪 / 伤害数字 / 粒子。
## _ready 置 PROCESS_MODE_ALWAYS：hitstop 暂停树后，本节点（及挂其下的表现物）仍照常处理。

const FLASH_SHADER := preload("res://fx/white_flash.gdshader")
const FLASH_DECAY_PER_SEC := 6.0      # 命中白闪 1→0 约 0.17s
const TELEGRAPH_DECAY_PER_SEC := 2.0  # 蓄力/引信红闪更持久（约 0.5s）
const HITSTOP_CRIT_MS := 40
const HITSTOP_KILL_MS := 60

var trauma := 0.0                     # 震屏强度，相机每渲染帧调 decay_step() 衰减
var _restore_timer: SceneTreeTimer = null   # 当前"权威"恢复定时器（最长剩余者）
var _flash: Dictionary = {}           # instance_id -> {item, mat, amount, speed}（键用 id：宿主释放后不悬垂）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 帧冻结：暂停树，真实毫秒后恢复（create_timer ignore_time_scale，brief 契约）。
## 并发调用取更长：只认剩余时间最长的"权威"定时器恢复；换权威时**断开旧定时器**的
## 恢复回调（fix1：否则旧定时器到点仍会触发解冻——暴击 40ms + 同帧击杀 60ms 只冻 40ms）。
## 注：期限比较用 SceneTreeTimer.time_left（同一时钟域），不与 Time.get_ticks_msec 混比
## （本机 headless 实测 process delta 与墙钟可偏差 ~20%）。
func hitstop(ms: int) -> void:
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

## 震屏：trauma 取 max；duration 仅占位（衰减率由 decay_step 契约固定 ×0.9/帧）。
func shake(strength: float, _duration: float) -> void:
	trauma = maxf(trauma, strength)

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
	Telemetry.log_row(["hit", Engine.get_physics_frames(), amount, 1 if is_crit else 0])
	if is_crit:
		hitstop(HITSTOP_CRIT_MS)        # 暴击 hitstop（brief：40ms + 数字放大 1.5×）

## 击杀 juice：hitstop 60ms + 粒子爆散。EventBus.enemy_killed 只有 id 无位置，
## 故由房间层（持有敌人节点）在击杀缝处调用。
func on_enemy_killed(at: Vector2) -> void:
	hitstop(HITSTOP_KILL_MS)
	shake(1.0, 0.1)
	_puff(at, Color(1.0, 0.55, 0.25), 12)

## 伤害数字：简单 spawn + tween 上飘淡出 + 自毁（M0 命中频率下短命对象分配有界，
## 池化收益低——控制器允许二选一，此处取简单方案）。暴击放大 1.5×。
func spawn_damage_number(pos: Vector2, amount: int, is_crit: bool) -> void:
	var label := Label.new()
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

# ---- 内部：白闪 / 粒子 ----

func _process(delta: float) -> void:
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
