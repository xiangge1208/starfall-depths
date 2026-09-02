class_name Projectile
extends Node2D
## 数据驱动的弹体；移动在此，命中判定在 CombatSystem。

enum Faction { PLAYER = 0, ENEMY = 1 }

var vel := Vector2.ZERO
var damage := 1
var faction := Faction.PLAYER
var element := Elements.Id.NONE
var pierce_left := 0
var bounce_left := 0
var life_ticks := 60
var radius := 3.0
var enchant_element := Elements.Id.NONE
var enchant_proc_chance := 0.0
var crit_detonate_pct := 0.0
var slow_pct := 0.0
var slow_ticks := 0
var source_type := "projectile"
var source_id := ""
var source_name := ""
var attack_name := "弹幕"
# m4-c1 抛物弹道（荆棘炮台/种子投手「抛物」）：沿发射轴的减速-落点弧线（顶视抛物线的
# 地面投影）。arc_gravity = 沿 arc_dir 反向的减速度（px/s²）；速度归零即「落地」消散
# （返回 false 由弹幕池回收）——落点精确等于发射时解算的目标点。缺省零 = 直线弹不变。
var arc_dir := Vector2.ZERO
var arc_gravity := 0.0
var _ticks := 0

func setup(cfg: Dictionary) -> void:
	position = cfg.get("pos", Vector2.ZERO)
	vel = cfg.get("vel", Vector2.ZERO)
	damage = cfg.get("damage", 1)
	faction = cfg.get("faction", Faction.PLAYER)
	element = cfg.get("element", Elements.Id.NONE)
	pierce_left = cfg.get("pierce", 0)
	bounce_left = cfg.get("bounce", 0)
	life_ticks = TimeConst.ticks(cfg.get("life_seconds", 1.0))
	radius = cfg.get("radius", 3.0)
	# 池化弹必须覆盖全部命中元数据；否则上一颗玩家附魔/蘑菇减速会泄漏到下一颗弹。
	enchant_element = int(cfg.get("enchant_element", Elements.Id.NONE))
	enchant_proc_chance = float(cfg.get("enchant_proc_chance", 0.0))
	crit_detonate_pct = float(cfg.get("crit_detonate_pct", 0.0))
	slow_pct = float(cfg.get("slow_pct", 0.0))
	slow_ticks = int(cfg.get("slow_ticks", 0))
	# 池化复用必须每次覆盖来源默认值，缺键不能继承上一颗弹的归因。
	source_type = String(cfg.get("source_type", "projectile"))
	source_id = String(cfg.get("source_id", ""))
	source_name = String(cfg.get("source_name", ""))
	attack_name = String(cfg.get("attack_name", "弹幕"))
	# 弧线参数逐次覆盖（池化复用不得继承上一颗弹的弧线）。
	arc_dir = cfg.get("arc_dir", Vector2.ZERO)
	arc_gravity = float(cfg.get("arc_gravity", 0.0))
	_ticks = 0
	modulate = Color.WHITE   # t9 定影：池化复用（含被反弹染色的弹）不得带上旧 tint
	visible = true

func tick() -> bool:
	_ticks += 1
	if arc_gravity > 0.0 and arc_dir != Vector2.ZERO:
		vel -= arc_dir * (arc_gravity / TimeConst.FPS)   # 沿发射轴减速（抛物减速段）
		if vel.dot(arc_dir) <= 0.0:
			return false                                  # 速度耗尽 = 落地（落点=解算目标）
	position += vel / TimeConst.FPS
	return _ticks < life_ticks

func on_despawn() -> void:
	visible = false
