class_name HitArc
extends Node2D
## J6 受击方向指示（Juice v2 §2 J6 / J-D 缺口 D-3b 补课）：以玩家为中心的 8px 弧形
## 闪光指向伤害来源，0.2s 淡出（v1 红晕/白闪之上叠加）。纯 _draw 矢量弧——无贴图、
## 无缩放、无过滤（480×270 像素风红线）。挂玩家名下随玩家位移；hitstop 冻结拍随树
## 暂停（与 v1 跳字/白闪同口径）。方向裁定（规格未定义无方向语义，取「不误导」并
## 记录于 m3-juice-checklist §6 D-3b）：来源方向缺失（from 非有限值）/零向量/与玩家
## 重合（环境 DOT 等无来源）时 Fx.spawn_hit_arc 不生成本节点。

const RADIUS := 8.0          # 规格 §2 J6：8px 弧（以玩家为中心）
const FADE_SECONDS := 0.2    # 规格 §2 J6：0.2s 淡出
const SPAN_RAD := 1.6        # 弧张开角 ≈92°（实现预设：指向上保持可辨且不过度包围）
const LINE_WIDTH := 2.0      # 2px 线宽（对齐 HUD CdRing 画线惯例）
const ARC_COLOR := Color(1.0, 0.32, 0.2, 0.95)   # 受击红（v1 红晕同族色）

var dir := Vector2.RIGHT     # 指向伤害来源的单位向量（Fx.spawn_hit_arc 注入）
var _t := 0.0                # 已播时长（game-time 秒；冻结拍随树暂停）

func _process(delta: float) -> void:
	_t += delta
	if _t >= FADE_SECONDS:
		queue_free()
		return
	queue_redraw()

## 淡出曲线（线性，1→0；测试断言与 _draw 共用同一出处）。
func fade_alpha() -> float:
	return clampf(1.0 - _t / FADE_SECONDS, 0.0, 1.0)

func _draw() -> void:
	if dir == Vector2.ZERO:
		return
	var a := dir.angle()
	draw_arc(Vector2.ZERO, RADIUS, a - SPAN_RAD * 0.5, a + SPAN_RAD * 0.5, 12,
		Color(ARC_COLOR, ARC_COLOR.a * fade_alpha()), LINE_WIDTH, true)
