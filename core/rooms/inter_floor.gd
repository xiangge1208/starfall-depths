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
## 第 3 层 Boss 后 flow.victory → 禁用喷泉/门；结算面板由 RunRoot 经 SceneRouter
## 路由 VictorySummary（m2-t18；原胜利桩 Label 已按 T18 移交清单清理，m2-t35 ⑥）。
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
## m2-t35 ③：宿主（RunRoot）注入的局内天赋系统；层间三选一 pick → buffs 重 apply 后
## 走 player.repair_talent_absolute_keys 成对修补（固定顺序 Hero→Buffs→Talents）。
var talents_system: TalentSystem = null

var _buff_pick: BuffPick = null
var _fountain: FlowFixture = null
var _door: FlowFixture = null
var _fountain_vis: CanvasItem = null       # m4p-u2：贴图态 Sprite2D / 缺图回落 Polygon2D
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
## m2-t35：第 4 参注入局内天赋系统（缺省 null = 只跳过天赋补 apply，不崩）。
## p_floor_idx < 0 时读 RunState.floor_idx。玩家无父节点时收养为子节点。
func setup(p_player: Player, p_buffs: BuffManager, p_floor_idx: int = -1,
		p_talents: TalentSystem = null) -> void:
	if _built:
		push_error("InterFloor.setup: already built")
		return
	_built = true
	player = p_player
	buffs_manager = p_buffs if p_buffs != null else BuffManager.new()
	talents_system = p_talents
	flow.setup(p_floor_idx if p_floor_idx >= 0 else RunState.floor_idx, buffs_manager)
	_build_chamber()
	_wire_player()


## Boss 死亡触发：掷三选一（inter_floor 盐流，确定性）→ 弹三选一 / 胜利桩。
func open() -> void:
	if not _built:
		push_error("InterFloor.open: call setup() first")
		return
	var offerings := flow.open_with_offerings(RunState.stream(RunState.SALT_INTER_FLOOR))
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
	# m4p-u2：喷泉贴图两态（满水 fountain_full.png → 用尽 fountain_used.png，切换在
	# _on_fountain_interact；色块回落态沿用原染色+变暗）。中心对齐交互格，节点名
	# "Sprite" 同交互物贴图约定。
	_fountain_vis = ArtLookup.make_sprite(ArtLookup.facility_texture_path("fountain_full"))
	if _fountain_vis == null:
		var poly := Polygon2D.new()
		poly.polygon = _rect_poly(Rect2(-10, -10, 20, 20))
		poly.color = Color(0.3, 0.6, 0.9)
		_fountain_vis = poly
	else:
		_fountain_vis.name = "Sprite"
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
	# m4p-u2：层间出口水晶贴图（exit_crystal.png 12x18 中心对齐门格；缺图回落原门色块）。
	var door_vis: CanvasItem = ArtLookup.make_sprite(ArtLookup.facility_texture_path("exit_crystal"))
	if door_vis == null:
		var dpoly := Polygon2D.new()
		dpoly.polygon = _rect_poly(Rect2(-10, -14, 20, 28))
		dpoly.color = Color(0.62, 0.4, 0.22)
		door_vis = dpoly
	else:
		door_vis.name = "Sprite"
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
	add_child(ui_layer)   # m1-t27 修复：ui_layer 漏挂树——三选一浮层不上树即不可见（孤儿泄漏）
	# m2-t35 ⑥：T18 移交清理——原「胜 利（M2 接完整结算）」胜利桩 Label 已删；
	# 胜利结算由 RunRoot._on_victory_achieved 经 SceneRouter 路由 VictorySummary（m2-t18）。

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
	# m2-t35 ③：固定顺序第 3 拍——buff 重 apply 绝对写覆盖六键天赋贡献，
	# 成对修补（wipe→repair；可加键 buff 侧 own-delta 天然保留，无需重复落地）。
	if talents_system != null:
		player.repair_talent_absolute_keys()


func _on_fountain_interact(_p: Node2D) -> void:
	if not flow.use_fountain(player):
		return
	_fountain.enabled = false                   # 一次性：用完禁用
	# m4p-u2 两态切换：贴图态换 fountain_used.png；色块回落态沿用变暗（兜底表现两态共用）。
	var spr := _fountain_vis as Sprite2D
	if spr != null:
		var used := ArtLookup.tex(ArtLookup.facility_texture_path("fountain_used"))
		if used != null:
			spr.texture = used
	_fountain_vis.modulate = Color(0.25, 0.4, 0.5) # 用尽变暗


func _on_door_interact(_p: Node2D) -> void:
	var new_floor := flow.enter_next_floor()
	if new_floor <= 0:
		return                                  # 非 DOOR 阶段：flow 已拒绝
	Telemetry.log_row(["inter_floor_next", Engine.get_physics_frames(), new_floor])
	# 楼层场景重建 = T23 路由职责：只发信号即止（FloorScene 实例化范式见类头注释）。
	next_floor_requested.emit(new_floor)


## 第 3 层胜利分支：只禁用喷泉与门（层间不再流转）。
## 胜利结算面板由 RunRoot 监听 flow.victory_achieved → SceneRouter 路由（m2-t18）；
## 原「胜利桩 Label」按 T18 移交清单清理（m2-t35 ⑥）。
func _show_victory_stub() -> void:
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
