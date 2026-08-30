class_name Player
extends CharacterBody2D
## 玩家。手感常量集中此处（GDD §5.2）；其余数值读 GameDB/HUD 层。

const MOVE_SPEED := 80.0
const ACCEL := 1400.0
const FRICTION := 1800.0
const ROLL_TICKS := 13
const ROLL_DIST := 56.0
const ROLL_CD_TICKS := 42          # 0.7s
const HURT_IFRAME_TICKS := 48      # 0.8s
const SHIELD_DELAY_TICKS := 180    # 3.0s
const SHIELD_INTERVAL_TICKS := 72  # 1.2s/点
const RAMPAGE_DR := 0.7            # 狂潮(升级)：受伤 ×0.7（向下取整，min 1）
const TIDE_DR := 0.8               # 生命潮汐(升级)：法阵内受伤 ×0.8（向下取整，min 1；m2-t11）
const DEFIANCE_RADIUS_PX := 60.0   # 坚守：AoE 半径
const DEFIANCE_KNOCKBACK_PX := 8.0 # 坚守：击退距离
const DEFIANCE_STUN_TICKS := 30    # 坚守：眩晕 0.5s

var hp := 8
var hp_max := 8
var shield := 4
var shield_max := 4
var energy := 100
var energy_max := 100
var move_speed := MOVE_SPEED
var facing := Vector2.RIGHT
# 局内永久/临时 modifier。Buff、饮料与雕像都写这些公开字段；生产消费者只读
# effective_*，避免先喝饮料/先选 Buff 的顺序改变结果。
var crit_bonus := 0.0
var crit_damage_bonus := 0.0
var status_rate_bonus := 0.0
var shield_delay_reduction_ticks := 0
var roll_cd_pct := 0.0
var roll_cd_reduction_ticks := 0
var move_speed_boost_pct := 0.0
var move_speed_boost_until := -1
var atk_speed_boost_pct := 0.0
var atk_speed_boost_until := -1
var energy_free_until := -1
var incoming_slow_pct := 0.0
var incoming_slow_until := -1
var weapon_rig: WeaponRig = null   # tscn 子节点（_ready 解析；测试可手工注入）
var combat: CombatSystem = null    # m1-t5：技能经 player.combat 写必暴窗（房间注入，同 rig.combat 契约）
var rampage_active_until := -1     # 狂潮(升级)减伤窗：frame < 此值时受伤 ×0.7（技能写入）
var tide_guard_until := -1         # 生命潮汐(升级)减伤窗：frame < 此值时受伤 ×0.8（技能每拍续写；m2-t11）
var has_defiance := false          # 被动「坚守」开关（角色数据注入，t11）
var friction_mult := 1.0           # m2-t4 冰面接缝：IceZone 进域写 0.25 / 出域回 1.0（MoveMath 摩擦参数临时替换）
var _roll_left := 0
var _roll_vel := Vector2.ZERO
var _roll_end_frame := -999
var _roll_cd_until := -999
var _iframe_until := -999
var _last_damaged_frame := -999
var _shield_next_at := -999

func _test_init() -> void:
	# 纯逻辑测试入口：不进场景树也能测状态机
	pass

func _ready() -> void:
	if weapon_rig == null:
		weapon_rig = get_node_or_null("WeaponRig")
	EventBus.shield_broken.connect(_on_shield_broken)

func _physics_process(_delta: float) -> void:
	var f := Engine.get_physics_frames()
	var physical_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var touch_dir := Input.get_vector("touch_move_left", "touch_move_right",
		"touch_move_up", "touch_move_down")
	var dir := (physical_dir + touch_dir).limit_length(1.0)
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if _roll_left > 0:
		_roll_left -= 1
		velocity = _roll_vel
	else:
		if (Input.is_action_just_pressed("roll") or Input.is_action_just_pressed("touch_roll")) \
				and roll_ready_at(f):
			start_roll(dir if dir != Vector2.ZERO else facing, f)
		velocity = MoveMath.accelerate(velocity, dir, effective_move_speed(f), ACCEL,
			FRICTION * friction_mult)
	move_and_slide()
	_shield_tick(f)

func start_roll(dir: Vector2, frame: int) -> void:
	var d := dir.normalized()
	_roll_vel = d * (ROLL_DIST / (float(ROLL_TICKS) / TimeConst.FPS))
	_roll_left = ROLL_TICKS
	_roll_end_frame = frame + ROLL_TICKS
	_roll_cd_until = _roll_end_frame + effective_roll_cd_ticks()
	Fx.on_roll(self)

func roll_ready_at(frame: int) -> bool:
	return frame >= _roll_cd_until

func effective_roll_cd_ticks() -> int:
	return maxi(0, int(round(float(ROLL_CD_TICKS) * (1.0 + roll_cd_pct))) \
		- roll_cd_reduction_ticks)

func effective_move_speed(frame: int) -> float:
	var boost := move_speed_boost_pct if frame < move_speed_boost_until else 0.0
	var slow := incoming_slow_pct if frame < incoming_slow_until else 0.0
	return move_speed * (1.0 + boost) * maxf(0.0, 1.0 - slow)

func effective_crit_chance(base: float) -> float:
	return clampf(base + crit_bonus, 0.0, 1.0)

func effective_crit_multiplier() -> float:
	return maxf(1.0, 2.0 + crit_damage_bonus)

func effective_status_rate_multiplier() -> float:
	return maxf(0.0, 1.0 + status_rate_bonus)

func is_invincible_at(frame: int) -> bool:
	return frame < _iframe_until or frame < _roll_end_frame

func is_invincible() -> bool:
	return is_invincible_at(Engine.get_physics_frames())

## 技能接缝（m1-t5 影袭）：开启一段无敌窗，取 max 不缩短既有窗（含受伤/翻滚窗）。
func apply_iframes(ticks: int, frame: int) -> void:
	_iframe_until = maxi(_iframe_until, frame + ticks)

func take_hit(ctx: Dictionary) -> void:
	take_hit_ctx(ctx, Engine.get_physics_frames())

func take_hit_ctx(ctx: Dictionary, frame: int) -> void:
	# 非正伤害必须在狂潮减伤、状态、无敌帧和护盾结算前成为完整 no-op；
	# 否则狂潮的 min 1 会把负数变成伤害，shield - dmg 也会反向增加护盾。
	var dmg := maxi(0, int(ctx.get("amount", 0)))
	if dmg == 0:
		return
	if is_invincible_at(frame):
		return
	var slow_ticks := int(ctx.get("slow_ticks", 0))
	var slow_pct := clampf(float(ctx.get("slow_pct", 0.0)), 0.0, 1.0)
	if slow_ticks > 0 and slow_pct > 0.0:
		incoming_slow_pct = maxf(incoming_slow_pct if frame < incoming_slow_until else 0.0, slow_pct)
		incoming_slow_until = maxi(incoming_slow_until, frame + slow_ticks)
	_iframe_until = frame + HURT_IFRAME_TICKS
	_last_damaged_frame = frame
	if frame < rampage_active_until:
		dmg = maxi(1, int(floor(float(dmg) * RAMPAGE_DR)))   # 狂潮(升级)：-30%
	if frame < tide_guard_until:
		dmg = maxi(1, int(floor(float(dmg) * TIDE_DR)))      # 生命潮汐(升级)：法阵内 -20%
	var shield_before := shield
	var hp_before := hp
	var effective_before := maxi(0, shield_before) + maxi(0, hp_before)
	var to_hp := maxi(0, dmg - shield)
	shield = maxi(0, shield - dmg)
	if to_hp > 0:
		hp = maxi(0, hp - to_hp)
	# 事件、死亡回顾、遥测和表现均使用真实落地伤害。来伤可以超过剩余
	# 护盾+生命，但 overkill 不能虚高本次受击或死亡窗口中的数值。
	var actual := mini(maxi(0, dmg), effective_before)
	_shield_next_at = frame + maxi(0, SHIELD_DELAY_TICKS - shield_delay_reduction_ticks)
	if shield_before > 0 and shield == 0:
		EventBus.shield_broken.emit()                        # 破碎拍广播（坚守被动在此挂钩）
	var fatal := hp <= 0
	# 不修改调用方共享 ctx；将实际结算伤害、帧和来源补齐后发详细归因信号。
	var resolved := ctx.duplicate(true)
	resolved["amount"] = actual
	resolved["fatal"] = fatal
	resolved["frame"] = frame
	resolved["source_type"] = String(ctx.get("source_type", ""))
	resolved["source_id"] = String(ctx.get("source_id", ""))
	resolved["source_name"] = String(ctx.get("source_name", ""))
	resolved["attack_name"] = String(ctx.get("attack_name", ""))
	resolved["from"] = ctx.get("from", global_position)
	resolved["remaining_hp"] = hp
	resolved["roll_available"] = roll_ready_at(frame)
	resolved["hp_damage"] = mini(hp_before, to_hp)
	EventBus.player_hit_resolved.emit(actual, fatal, resolved)
	EventBus.player_damaged.emit(actual, fatal)   # 旧两参契约仍只发一次
	Telemetry.log_row(["hurt", frame, actual, hp])   # m1-t18：hurt 行收口至玩家受击路径（原 training_room 本地行）
	Fx.on_player_hurt(self, actual)

## 被动「坚守」（GDD §6 骑士·凛）：护盾破碎瞬间对 60px 内敌人 1 伤 + 击退 8px + 眩晕 30t。
## 寻敌沿用 M0 分组（RoomCombat 刷怪即入 "enemies" 组），位置以 brain_pos 权威（同敌方 AI）。
func _on_shield_broken() -> void:
	if not has_defiance or not is_inside_tree():
		return
	var frame := Engine.get_physics_frames()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		var to := e.brain_pos - global_position
		if to.length() > DEFIANCE_RADIUS_PX:
			continue
		e.take_hit({"amount": 1, "is_crit": false, "element": Elements.Id.NONE, "from": global_position})
		if e.state == EnemyBase.State.DEAD:                  # 被 1 伤终结则不再位移/眩晕尸体
			continue
		e.brain_pos += to.normalized() * DEFIANCE_KNOCKBACK_PX
		e.stun_until = frame + DEFIANCE_STUN_TICKS

func _shield_tick(frame: int) -> void:
	if shield >= shield_max or frame < _shield_next_at:
		return
	shield += 1
	_shield_next_at = frame + SHIELD_INTERVAL_TICKS

func shield_at(frame: int) -> int:
	# 纯查询：给定未来帧的护盾值（测试与 UI 预估用）
	if shield >= shield_max or frame < _shield_next_at:
		return shield
	var gained := int(floor(float(frame - _shield_next_at) / SHIELD_INTERVAL_TICKS)) + 1
	return mini(shield_max, shield + gained)

func heal(n: int) -> void:
	hp = mini(hp_max, hp + n)

func add_energy(n: int) -> void:
	energy = mini(energy_max, energy + n)

func combat_radius() -> float:
	return 6.0

func combat_faction() -> int:
	return Projectile.Faction.PLAYER
