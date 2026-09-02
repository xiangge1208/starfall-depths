class_name PlayerProxy
extends Node2D
## EnemyBase.player_ref 适配器（m0-t12 房间接线）。
## EnemyBase 契约（见其 player_ref 注释「玩家替身/实例（需有 brain_pos）」）：
## 视线/瞄准/自爆引信读 player_ref.brain_pos，自爆结算调 player_ref.take_hit(ctx)。
## 真实 Player 无 brain_pos 字段（core/player 不属 t12 修改范围），故由房间挂一个
## 镜像替身：每物理帧镜像玩家位置，受击原样转发（iframe/护盾由 Player 自身裁决）。

var player: Player
var brain_pos := Vector2.ZERO              # EnemyBase 读的权威位置（每物理帧镜像）

func _physics_process(_delta: float) -> void:
	if player != null:
		global_position = player.global_position
		brain_pos = player.global_position

func take_hit(ctx: Dictionary) -> void:
	if player != null:
		player.take_hit(ctx)


## m4-c1 磁石傀儡拉拽接缝：把玩家实体位移到 target（敌人侧已按房间内域钳制）。
## 尊重玩家无敌帧/翻滚窗（is_invincible）——受击硬直与翻滚中不可被拉动；其余返回 true。
func apply_pull(target: Vector2) -> bool:
	if player == null or player.is_invincible():
		return false
	player.global_position = target
	return true


## m4-c1 深窟回响者模仿武器读缝：玩家当前槽位武器行 id → GameDB 全行（只读，
## 不写 weapons 侧任何状态）。无玩家/无 rig/空槽返回 {}（敌人侧回退默认扇弹）。
func current_weapon_row() -> Dictionary:
	if player == null:
		return {}
	var rig: Node = player.get_node_or_null("WeaponRig")
	if rig == null:
		return {}
	var cur: Dictionary = rig.call("current")
	if cur.is_empty():
		return {}
	return GameDB.get_weapon(String(cur.get("id", "")))
