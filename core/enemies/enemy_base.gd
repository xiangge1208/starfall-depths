class_name EnemyBase
extends CharacterBody2D
## 敌人状态机（GDD §12.2）：IDLE→ALERT(24t)→ENGAGE；AI 决策在 EnemyBrain（可注入帧测试）。

enum State { IDLE, ALERT, ENGAGE, DEAD }
const ALERT_TICKS := 24     # 0.4s
const VISION_PX := 240.0    # 视距（物理表现层用）

var row: Dictionary
var hp := 10
var state := State.IDLE
var fired_this_tick := false
var exploded := false
var brain_pos := Vector2.ZERO
var combat: CombatSystem = null    # 房间注入
var status: Node = null            # StatusComponent，m0-t11 注入
var player_ref = null              # 玩家替身/实例（需有 brain_pos），房间注入
var _seen_frame := -1

func _test_init(r: Dictionary) -> void:
	_apply_archetype_script(r)   # 数据驱动：先按行换上原型脚本（set_script 会重建脚本实例并重置成员）
	# set_script 后当前函数帧仍绑定旧实例，直接写成员会丢失——须经 Object.set 落到新实例
	set("row", r)
	set("hp", int(r.get("hp", 10)))
	set("brain_pos", Vector2.ZERO)

## 数据驱动原型挂载：行内 archetype → archetypes/<name>.gd（均 extends EnemyBase 覆写 _engage）。
## 仅当当前脚本是基类时才换，避免子类实例二次换脚本；未知原型告警并留在基类（IDLE 空转）。
func _apply_archetype_script(r: Dictionary) -> void:
	var arch := String(r.get("archetype", ""))
	if arch == "":
		return
	var script := get_script() as Script
	if script == null or script.resource_path != "res://core/enemies/enemy_base.gd":
		return
	var path := "res://core/enemies/archetypes/%s.gd" % arch
	if ResourceLoader.exists(path):
		set_script(load(path))
	else:
		push_warning("EnemyBase: unknown archetype '%s'" % arch)

func setup(r: Dictionary) -> void:
	# m0-t12 修复：global_position 须在换脚本前读取——_test_init 内 set_script 后当前帧
	# 绑定旧实例，此后读原生属性可触发 "Internal error getting property"（4.7.2 实测）。
	var at := global_position
	_test_init(r)
	set("brain_pos", at)   # 同 _test_init：经 Object.set 避开旧实例帧
	# m0-t12 接线：非玩家实体惰性挂载 StatusComponent（M0 无精英/Boss，统一小怪阈值 2 层）。
	# 读写均须 Object.get/set：换脚本后直接读写成员会落到旧实例而丢失（下同，见 _test_init 注）。
	if get("status") == null:
		var s := StatusComponent.new()
		add_child(s)
		s.setup(2, false)
		set("status", s)

func on_player_seen(frame: int) -> void:
	if state == State.IDLE:
		state = State.ALERT
		_seen_frame = frame

func brain_tick(frame: int) -> void:
	fired_this_tick = false
	match state:
		State.ALERT:
			if frame - _seen_frame >= ALERT_TICKS:
				state = State.ENGAGE
				_on_engage_start(frame)   # 转换拍钩子：接触触发型原型（苦力虫引信）在此拍锚定
		State.ENGAGE:
			_engage(frame)
		_:
			pass

func _engage(_frame: int) -> void:
	pass                                  # 原型覆写

## 进入 ENGAGE 的转换拍调用一次（此后每拍走 _engage）；默认无操作，
## 其余原型不覆写即完全保持原行为（不多不少一拍）。
func _on_engage_start(_frame: int) -> void:
	pass

func fire_bullet(target: Vector2, frame: int) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var dir := (target - brain_pos).normalized()
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * float(row.get("bullet_speed", 110)),
		"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
		"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.5)), "radius": 3.0,
	})

func take_hit(ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	hp -= int(ctx["amount"])
	Fx.on_enemy_hit(self, ctx)
	if status != null:
		status.apply_hit(int(ctx.get("element", 0)), int(ctx["amount"]), Engine.get_physics_frames())
	if hp <= 0:
		die()

func die() -> void:
	state = State.DEAD
	if combat != null:
		combat.unregister_body(self)
	EventBus.enemy_killed.emit(String(row.get("id", "")))
	queue_free()

func combat_radius() -> float:
	return float(row.get("radius", 6.0))

func combat_faction() -> int:
	return Projectile.Faction.ENEMY

## 原型取玩家位置；未注入 player_ref（纯 brain 测试）时退化为自身位置（零向量方向，不移动）。
func _player_pos() -> Vector2:
	return player_ref.brain_pos if player_ref != null else brain_pos

# ---- 物理表现层（手动验证；测试直接驱动 brain，不经此处） ----
func _physics_process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if player_ref != null and state == State.IDLE \
			and global_position.distance_to(player_ref.brain_pos) <= VISION_PX:
		on_player_seen(Engine.get_physics_frames())
	# brain_pos 为权威位置：以差值速度过 move_and_slide 处理碰撞，之后把 brain 对齐实际位置
	velocity = (brain_pos - global_position) * TimeConst.FPS
	move_and_slide()
	brain_pos = global_position
	# m0-t12 接线：DoT 结算 + 共鸣事件消费（读后清空）
	if status != null:
		var frame := Engine.get_physics_frames()
		var dot: int = status.tick(frame)
		if dot > 0:
			hp -= dot
			if hp <= 0:
				die()
				return
		if not status.resonance_event.is_empty():
			var ev: Dictionary = status.resonance_event
			status.resonance_event = {}
			EventBus.resonance_triggered.emit(int(ev["reaction"]), global_position, ev)
			# M0：SHATTER=90px AoE（1.5× 触发伤害）；BLAZE/SUPERCONDUCT/ELECTROLYSIS 仅广播
			if int(ev["reaction"]) == Resonance.R.SHATTER:
				_shatter_aoe(int(ev["last_damage"]))

## 淬爆（SHATTER）M0 执行：以自身为中心 90px 全向 AoE，对敌方体结算 1.5× 触发伤害。
## M0 武器无元素，此通路暂不可达（为 t13+/元素武器预留，行为按控制器决议字面实现）。
func _shatter_aoe(last_damage: int) -> void:
	if combat == null:
		return
	var amount := int(float(last_damage) * 1.5)
	for body in combat.bodies_in_arc(global_position, 0.0, 90.0, 360.0, Projectile.Faction.ENEMY):
		body.take_hit({"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": global_position})
