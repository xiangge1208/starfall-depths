class_name DoorAnim
## 统一门动画（m1-t18）：0.18s Tween 滑入/滑出，收口两处 ad-hoc 门代码——
## RoomCombat._set_doors_closed（原 0.25s 手写 Tween）、FloorScene.refresh_gates
## （原可见性瞬切；开 = 滑出走廊后隐藏，终态等价）。训练房无本地门代码（仅 hurt 行收口）。
## 契约：门体构建期 install(panel, home) 登记闭合位；close 恢复可见滑回门位；
## open 滑出到 home+PARK_OFFSET（room_combat 默认保持 M0「收进墙体仍可见」习语，
## floor_scene 传 hide_when_open=true 滑出后隐藏）。

const DURATION := 0.18
const PARK_OFFSET := Vector2(0, -46)   # 滑出位移（M0 门体藏位习语）

static func install(panel: Node2D, home: Vector2) -> void:
	panel.set_meta("door_home", home)

static func close(panel: Node2D) -> void:
	panel.visible = true
	_slide(panel, _home(panel))

static func open(panel: Node2D, hide_when_open := false) -> void:
	var tw := _slide(panel, _home(panel) + PARK_OFFSET)
	if hide_when_open:
		tw.tween_callback(func() -> void: panel.visible = false)

static func _home(panel: Node2D) -> Vector2:
	return panel.get_meta("door_home") if panel.has_meta("door_home") else panel.position

static func _slide(panel: Node2D, to: Vector2) -> Tween:
	var tw := panel.create_tween()
	tw.tween_property(panel, "position", to, DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw
