class_name IceZone
extends RefCounted
## A2 冰面（M2-T4 / GDD §10 A2「冰面打滑」）：纯逻辑区域数据 + FloorScene 挂载驱动
## （便于无头测试，不用 Area2D）。玩家在冰面区域时 MoveMath 摩擦参数临时 ×0.25
## ——进入替换 / 离开恢复，帧级无缝；接缝为 Player.friction_mult（1.0 默认），
## 敌人没有任何可被冰面写入的摩擦状态（不受冰面影响）。
##
## A2 模板 JSON 的 biome/hazards 字段由后续卡驱动 add_zone；本卡由 FloorScene
## 按房补丁常量演示挂载。

const FRICTION_MULT := 0.25         # M2-T4 卡口径：摩擦 ×0.25（比 GDD「减半」更强打滑）

var zones: Array[Rect2] = []        # 世界坐标冰面矩形集合


## 摩擦选择纯函数（无头可测）：冰面上基准摩擦 ×0.25，常规地面原值。
static func effective_friction(base: float, in_ice: bool) -> float:
	return base * FRICTION_MULT if in_ice else base


func add_zone(rect: Rect2) -> void:
	zones.append(rect)


func in_ice(world_pos: Vector2) -> bool:
	for r in zones:
		if r.has_point(world_pos):
			return true
	return false


## 帧级接缝（宿主 _physics_process 每帧驱动）：玩家位置落域即写 0.25，出域即回 1.0。
## 只接受 Player——敌人不受冰面影响的结构保证。
func tick(player: Player) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.friction_mult = effective_friction(1.0, in_ice(player.global_position))
