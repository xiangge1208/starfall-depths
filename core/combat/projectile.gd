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
	_ticks = 0
	modulate = Color.WHITE   # t9 定影：池化复用（含被反弹染色的弹）不得带上旧 tint
	visible = true

func tick() -> bool:
	position += vel / TimeConst.FPS
	_ticks += 1
	return _ticks < life_ticks

func on_despawn() -> void:
	visible = false
