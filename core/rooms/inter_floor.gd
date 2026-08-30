class_name InterFloor
extends Node2D
## 层间中转房（m1-t20 场景表现层 + 接线；流程判定全在 InterFloorFlow 纯逻辑类）：
## Boss 死亡后宿主调 open()，依次呈现——
##   ① 增益三选一（复用 T9 ui/buff_pick.tscn，buff_chosen → flow.choose_buff 落地）
##   ② 治疗喷泉（免费回 2 HP，仅一次，E 交互）
##   ③ 下一层门（E 进入 → flow.enter_next_floor() 推层结算 → next_floor_requested）。
##
## 楼层场景重建是 T23 路由职责：本场景只发 next_floor_requested(new_floor) 即止
## （floor_scene.tscn 的实例化范式 = FloorScene.new + DungeonBuilder.build(seed, new_floor)
## + setup(build, player)，重建须换到新楼层场景，不在本卡范围）。
## 第 3 层 Boss 后 flow.victory → 只显示胜利结算桩（M2 接完整结算）。
##
## 乞丐 payout 接缝在 flow.advance()（DOOR 阶段，见 inter_floor_flow.gd）。

signal next_floor_requested(new_floor: int)

const TILE := 16
const WALL_T := 16
const CHAMBER_W := 352.0          # 22 格（同 RoomTemplate 标准房宽）
const CHAMBER_H := 208.0          # 13 格
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const BUFF_PICK_SCENE := preload("res://ui/buff_pick.tscn")
const DRIVER_SCRIPT := preload("res://core/rooms/player_driver.gd")
const GAME_CAMERA := preload("res://fx/game_camera.gd")

var flow := InterFloorFlow.new()
var buffs_manager := BuffManager.new()
var player: Player = null

var _buff_pick: BuffPick = null
var _fountain: FlowFixture = null
var _door: FlowFixture = null
var _fountain_vis: Polygon2D = null
var _victory_label: Label = null
var _built := false


func _ready() -> void:
	if _built:
		return
	# 直接运行 inter_floor.tscn（手动验证）：自举一局 + 玩家；宿主 setup() 路径不进此分支。
	if get_tree() != null and get_tree().current_scene == self:
		if RunState.run_seed == 0:
			RunState.start_run("vanguard")
		var p: Player = PLAYER_SCENE.instantiate() as Player
		setup(p, BuffManager.new(), RunState.floor_idx)
		open()


## 宿主接线（T23 路由）：注入玩家与增益管理器（局内同一实例，跨层保留已取增益）。
## p_floor_idx < 0 时读 RunState.floor_idx。玩家无父节点时收养为子节点。
func setup(p_player: Player, p_buffs: BuffManager, p_floor_idx: int = -1) -> void:
	if _built:
		push_error("InterFloor.setup: already built")
		return
	_built = true
	player = p_player
	buffs_manager = p_buffs if p_buffs != null else BuffManager.new()
	flow.setup(p_floor_idx if p_floor_idx >= 0 else RunState.floor_idx, buffs_manager)
	_build_chamber()
	_wire_player()


## Boss 死亡触发：掷三选一（loot 盐流，确定性）→ 弹三选一 / 胜利桩。
func open() -> void:
	if not _built:
		push_error("InterFloor.open: call setup() first")
		return
	var offerings := flow.open_with_offerings(RunState.stream(RunState.SALT_LOOT))
	Telemetry.log_row(["inter_floor_open", Engine.get_physics_frames(), flow.floor_idx,
		str(flow.victory)])
	if flow.victory:
		_show_victory_stub()
		return
	if not offerings.is_empty():
		_buff_pick.open(offerings)


# ================================================================ 房间装配

func _build_chamber() -> void:
	var floor_vis := Polygon2D.new()
	floor_vis.polygon = _rect_poly(Rect2(0, 0, CHAMBER_W, CHAMBER_H))
	floor_vis.color = Color(0.14, 0.16, 0.15)
	floor_vis.z_index = -10
	add_child(floor_vis)
	_solid_wall(Rect2(0, 0, CHAMBER_W, WALL_T))
	_solid_wall(Rect2(0, CHAMBER_H - WALL_T, CHAMBER_W, WALL_T))
	_solid_wall(Rect2(0, 0, WALL_T, CHAMBER_H))
	_solid_wall(Rect2(CHAMBER_W - WALL_T, 0, WALL_T, CHAMBER_H))

	# ② 治疗喷泉（GDD §11：免费回 2 HP，一次）——房间左侧
	_fountain = FlowFixture.new()
	_fountain.name = "Fountain"
	_fountain.position = Vector2(WALL_T + 48.0, CHAMBER_H / 2.0)
	_fountain.action_label = "饮用喷泉（回2HP·一次）"
	_fountain.gate = func(_p: Node2D) -> bool: return flow.phase == InterFloorFlow.Phase.FOUNTAIN
	_fountain.add_child(_fixture_body())
	_fountain_vis = Polygon2D.new()
	_fountain_vis.polygon = _rect_poly(Rect2(-10, -10, 20, 20))
	_fountain_vis.color = Color(0.3, 0.6, 0.9)
	_fountain.add_child(_fountain_vis)
	_fountain.on_interact_cb = _on_fountain_interact
	add_child(_fountain)

	# ③ 下一层门——房间右侧（仅 DOOR 阶段可交互，跳步进门由 flow fail-closed 兜底）
	_door = FlowFixture.new()
	_door.name = "NextFloorDoor"
	_door.position = Vector2(CHAMBER_W - WALL_T - 24.0, CHAMBER_H / 2.0)
	_door.action_label = "进入下一层"
	_door.gate = func(_p: Node2D) -> bool: return flow.phase == InterFloorFlow.Phase.DOOR
	_door.add_child(_fixture_body())
	var door_vis := Polygon2D.new()
	door_vis.polygon = _rect_poly(Rect2(-10, -14, 20, 28))
	door_vis.color = Color(0.62, 0.4, 0.22)
	_door.add_child(door_vis)
	_door.on_interact_cb = _on_door_interact
	add_child(_door)

	var sys := InteractionSystem.new()
	sys.name = "InteractionSystem"
	sys.player = player
	add_child(sys)

	# ① 增益三选一浮层（复用 T9 BuffPick：键盘 1/2/3 或点击卡片）
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 30
	_buff_pick = BUFF_PICK_SCENE.instantiate() as BuffPick
	_buff_pick.buff_chosen.connect(_on_buff_chosen)
	ui_layer.add_child(_buff_pick)
	var hud := CanvasLayer.new()
	hud.layer = 20
	_victory_label = Label.new()
	_victory_label.set_anchors_preset(Control.PRESET_CENTER)
	_victory_label.add_theme_font_size_override("font_size", 24)
	_victory_label.text = "胜 利（M2 接完整结算）"
	_victory_label.visible = false
	hud.add_child(_victory_label)
	add_child(hud)
	add_child(ui_layer)   # m1-t27 修复：ui_layer 漏挂树——三选一浮层不上树即不可见（孤儿泄漏）

	var cam: Camera2D = GAME_CAMERA.new()
	cam.set("target", player)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(CHAMBER_W) + TILE
	cam.limit_bottom = int(CHAMBER_H) + TILE
	add_child(cam)


func _wire_player() -> void:
	if player.get_parent() == null:
		add_child(player)
	if not player.is_in_group("player"):
		player.add_to_group("player")
	player.position = Vector2(WALL_T + 24.0, CHAMBER_H / 2.0)
	var rig := player.get_node("WeaponRig") as WeaponRig
	if rig != null and rig.current().is_empty():
		rig.equip("laohuoji")
	if not player.has_node("Driver"):
		var driver := Node.new()
		driver.name = "Driver"
		driver.set_script(DRIVER_SCRIPT)
		player.add_child(driver)


# ================================================================ 交互落地

func _on_buff_chosen(id: String) -> void:
	if not flow.choose_buff(id):
		return
	RunState.add_buff(id)                       # 局内聚合记账（数值落地见 apply_to_player）
	buffs_manager.apply_to_player(player)
	if player.weapon_rig != null:
		buffs_manager.apply_to_rig(player.weapon_rig)


func _on_fountain_interact(_p: Node2D) -> void:
	if not flow.use_fountain(player):
		return
	_fountain.enabled = false                   # 一次性：用完禁用
	_fountain_vis.color = Color(0.25, 0.4, 0.5) # 用尽变暗


func _on_door_interact(_p: Node2D) -> void:
	var new_floor := flow.enter_next_floor()
	if new_floor <= 0:
		return                                  # 非 DOOR 阶段：flow 已拒绝
	Telemetry.log_row(["inter_floor_next", Engine.get_physics_frames(), new_floor])
	# 楼层场景重建 = T23 路由职责：只发信号即止（FloorScene 实例化范式见类头注释）。
	next_floor_requested.emit(new_floor)


func _show_victory_stub() -> void:
	_victory_label.visible = true
	_fountain.enabled = false
	_door.enabled = false


# ================================================================ 小工具

func _solid_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
	vis.color = Color(0.36, 0.3, 0.28)
	body.add_child(vis)


func _fixture_body() -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	cs.shape = shape
	return cs


func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])


## 一次性可交互物（层间喷泉/门通用）：enabled 门控 + 可选 gate 阶段条件（FloorScene 内类同款）。
class FlowFixture extends Interactable:
	var on_interact_cb := Callable()
	var enabled := true
	var gate := Callable()                    # 可选附加门控（如 phase == DOOR 才显浮标）

	func can_interact(p: Node2D) -> bool:
		if not enabled:
			return false
		return not gate.is_valid() or bool(gate.call(p))

	func interact(p: Node2D) -> void:
		if enabled and on_interact_cb.is_valid():
			on_interact_cb.call(p)
