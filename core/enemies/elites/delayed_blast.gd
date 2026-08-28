class_name DelayedBlast
extends Node2D
## m1-t12 延迟大爆（附录 B.3 自爆王虫「本体死亡延迟 1s 大爆」）：
## 由 EnemyBase.die() 的延迟分支生成；倒计时到点按 M0 死亡爆炸语义结算——
## 爆点半径内玩家吃 aoe_dmg（经 player_ref.take_hit，ctx 带 is_crit=false/element=NONE/from），
## 玩家受击无敌帧天然节流（本节点不另设冷却，与 EnemyBase._death_explosion 同约定）。

var _remaining := 0
var _radius := 0.0
var _dmg := 0
var _player = null               # 玩家替身/实例（契约：brain_pos + take_hit）

func setup(cfg: Dictionary) -> void:
	position = cfg.get("pos", Vector2.ZERO)
	_radius = float(cfg.get("radius", 0.0))
	_dmg = int(cfg.get("dmg", 0))
	_remaining = int(cfg.get("ticks", 0))
	_player = cfg.get("player", null)

## 帧注入接缝：每调一次计 1 拍（脑层测试直呼驱动）；树内由 _physics_process 每物理拍喂 1 次。
func tick() -> void:
	if _remaining <= 0:
		return
	_remaining -= 1
	if _remaining <= 0:
		_detonate()

func _physics_process(_delta: float) -> void:
	tick()

## 爆炸结算：与 EnemyBase._death_explosion 同语义（半径内玩家 take_hit，爆毕自毁）。
func _detonate() -> void:
	if _player != null and _player.has_method("take_hit") \
			and _player.brain_pos.distance_to(global_position) <= _radius:
		_player.take_hit({
			"amount": _dmg, "is_crit": false,
			"element": Elements.Id.NONE, "from": global_position,
		})
	queue_free()
