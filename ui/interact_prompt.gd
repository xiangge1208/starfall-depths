class_name InteractPrompt
extends Label
## 交互浮标（m1-t6）：悬于当前最佳交互物上方 (+16px) 显示 action_label；
## 由 InteractionSystem 驱动 bind/clear，自身无状态。

const LIFT_PX := 16.0

func _init() -> void:
	z_index = 50                              # 压过地板/实体绘层
	add_theme_font_size_override("font_size", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 绑定目标：文案 = action_label，水平居中悬于目标上方（null 视为 clear）。
func bind(target: Interactable) -> void:
	if target == null:
		clear()
		return
	text = target.action_label
	reset_size()
	global_position = target.global_position + Vector2(-size.x / 2.0, -LIFT_PX)
	show()

## 解除绑定：隐藏。
func clear() -> void:
	hide()
