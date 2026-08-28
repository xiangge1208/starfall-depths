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
	_ticks = 0
	modulate = Color.WHITE   # t9 定影：池化复用（含被反弹染色的弹）不得带上旧 tint
	visible = true

func tick() -> bool:
	position += vel / TimeConst.FPS
	_ticks += 1
	return _ticks < life_ticks

func on_despawn() -> void:
	visible = false
