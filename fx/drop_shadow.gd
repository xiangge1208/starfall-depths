class_name DropShadow
extends Node2D
## 通用接地阴影组件（类《元气骑士》脚下椭圆阴影）：
## 挂载于角色/敌人/实体脚底，绘制半透明扁平黑色椭圆，解决 2D 顶视图漂浮感。

@export var radius_x: float = 6.0
@export var radius_y: float = 3.0
@export var offset_y: float = 6.0
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.38)

func _init() -> void:
	z_index = -1

func _ready() -> void:
	z_index = -1
	position = Vector2(0.0, offset_y)
	queue_redraw()

func set_shadow_size(rx: float, ry: float, off_y: float = 6.0) -> void:
	radius_x = rx
	radius_y = ry
	offset_y = off_y
	position = Vector2(0.0, offset_y)
	queue_redraw()

func _draw() -> void:
	var pts := PackedVector2Array()
	var segments := 16
	for i in segments:
		var rad := float(i) * TAU / float(segments)
		pts.append(Vector2(cos(rad) * radius_x, sin(rad) * radius_y))
	draw_colored_polygon(pts, shadow_color)
