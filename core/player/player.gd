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

var hp := 8
var hp_max := 8
var shield := 4
var shield_max := 4
var energy := 100
var energy_max := 100
var move_speed := MOVE_SPEED
var facing := Vector2.RIGHT
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

func _physics_process(_delta: float) -> void:
	var f := Engine.get_physics_frames()
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if _roll_left > 0:
		_roll_left -= 1
		velocity = _roll_vel
	else:
		if Input.is_action_just_pressed("roll") and roll_ready_at(f):
			start_roll(dir if dir != Vector2.ZERO else facing, f)
		velocity = MoveMath.accelerate(velocity, dir, move_speed, ACCEL, FRICTION)
	move_and_slide()
	_shield_tick(f)

func start_roll(dir: Vector2, frame: int) -> void:
	var d := dir.normalized()
	_roll_vel = d * (ROLL_DIST / (float(ROLL_TICKS) / TimeConst.FPS))
	_roll_left = ROLL_TICKS
	_roll_end_frame = frame + ROLL_TICKS
	_roll_cd_until = _roll_end_frame + ROLL_CD_TICKS
	Fx.on_roll(self)

func roll_ready_at(frame: int) -> bool:
	return frame >= _roll_cd_until

func is_invincible_at(frame: int) -> bool:
	return frame < _iframe_until or frame < _roll_end_frame

func is_invincible() -> bool:
	return is_invincible_at(Engine.get_physics_frames())

func take_hit(ctx: Dictionary) -> void:
	take_hit_ctx(ctx, Engine.get_physics_frames())

func take_hit_ctx(ctx: Dictionary, frame: int) -> void:
	if is_invincible_at(frame):
		return
	_iframe_until = frame + HURT_IFRAME_TICKS
	_last_damaged_frame = frame
	var dmg: int = ctx["amount"]
	var to_hp := maxi(0, dmg - shield)
	shield = maxi(0, shield - dmg)
	if to_hp > 0:
		hp = maxi(0, hp - to_hp)
	_shield_next_at = frame + SHIELD_DELAY_TICKS
	EventBus.player_damaged.emit(dmg, hp <= 0)
	Fx.on_player_hurt(self, dmg)

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
