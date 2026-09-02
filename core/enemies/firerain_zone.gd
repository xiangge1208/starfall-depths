class_name FirerainZone
extends Node2D
## M4-C1 火雨祭司「火雨区（预警红圈）」（GDD 附录 A3 行为文本）：
## 延迟结算的地面警示区——落点画红圈预警 firerain_delay_ticks（§7.5 ≥0.35s），
## 到点对圈内玩家结算 firerain_dmg（FIRE 归因）后自毁。DelayedBlast 同族语义
## （player 契约 = brain_pos + take_hit；tick() 帧注入接缝供脑层测试直驱），
## 差异仅在带红圈预警绘制与 FIRE 元素归因。区为一次性打击（玩家无敌帧天然节流）。

const WARN_COLOR := Color(1.0, 0.25, 0.2, 0.35)
const WARN_EDGE := Color(1.0, 0.3, 0.25, 0.8)

var _remaining := 0
var _radius := 0.0
var _dmg := 0
var _player = null               # 玩家替身/实例（契约：brain_pos + take_hit）
var _source_id := ""
var _source_name := ""


func setup(cfg: Dictionary) -> void:
	position = cfg.get("pos", Vector2.ZERO)
	_radius = float(cfg.get("radius", 0.0))
	_dmg = int(cfg.get("dmg", 0))
	_remaining = int(cfg.get("ticks", 0))
	_player = cfg.get("player", null)
	_source_id = String(cfg.get("source_id", ""))
	_source_name = String(cfg.get("source_name", ""))
	queue_redraw()


func radius() -> float:
	return _radius


func remaining() -> int:
	return _remaining


## 帧注入接缝（同 DelayedBlast.tick）：每调一次计 1 拍。
func tick() -> void:
	if _remaining <= 0:
		return
	_remaining -= 1
	queue_redraw()
	if _remaining <= 0:
		_detonate()


func _physics_process(_delta: float) -> void:
	tick()


func _detonate() -> void:
	if is_instance_valid(_player) and _player.has_method("take_hit") \
			and _player.brain_pos.distance_to(global_position) <= _radius:
		_player.take_hit({
			"amount": _dmg, "is_crit": false,
			"element": Elements.Id.FIRE, "from": global_position,
			"source_type": "projectile", "source_id": _source_id,
			"source_name": _source_name, "attack_name": "火雨",
		})
	queue_free()


func _draw() -> void:
	# 预警红圈：半透明填充 + 亮边；临近爆发（≤9t）边缘加亮提示（可读性，无判定影响）。
	draw_circle(Vector2.ZERO, _radius, WARN_COLOR)
	var edge := WARN_EDGE if _remaining > 9 else Color(1.0, 0.55, 0.2, 1.0)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 24, edge, 1.5)
