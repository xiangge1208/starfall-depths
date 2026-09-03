class_name Interactable
extends Area2D
## 可交互物基类（m1-t6）：InteractionSystem 每物理拍取玩家 radius 内最近者，
## 浮标显示 action_label，按 E 触发 interact(player)。
## 选取机制为距离制（InteractionSystem.pick_best 只读 global_position），
## Area2D 物理重叠不参与寻的——_ready 显式清零 layer/mask，防意外的 body 事件。

@export var action_label := "交互"

func _ready() -> void:
	add_to_group(InteractionSystem.GROUP)     # 自注册：房间动态增删交互物无需登记
	collision_layer = 0
	collision_mask = 0

## 门控：false 时 pick_best 跳过该候选（浮标不显示、E 无效）。子类覆写加条件。
func can_interact(_player: Node2D) -> bool:
	return true

## 交互落地行为（子类覆写）。
func interact(_player: Node2D) -> void:
	pass                                      # 基类无行为


## 设施世界贴图挂载（m4p-u2 设施贴图收编）：按 ArtLookup 设施表给交互物挂最近邻
## Sprite2D（节点名 "Sprite" 同敌装约定；中心对齐交互格；默认 z0 = 地板(-10)之上、
## 交互浮标(z50)之下）。幂等：已有 "Sprite" 节点只换纹理（两态切换缝）。
## 缺图 no-op（fail-soft，同表契约——调用方保留原无装饰/色块表现）。
func mount_facility_sprite(facility_name: String) -> Sprite2D:
	var path := ArtLookup.facility_texture_path(facility_name)
	if path.is_empty():
		return null
	var tex := ArtLookup.tex(path)
	if tex == null:
		return null
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr != null:
		spr.texture = tex
		return spr
	spr = ArtLookup.make_sprite(path)
	if spr == null:
		return null
	spr.name = "Sprite"
	add_child(spr)
	return spr
