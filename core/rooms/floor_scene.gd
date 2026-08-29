class_name FloorScene
extends Node2D
## 楼层场景编排者（M1-T10）：消费 DungeonBuilder 构建体，把整层房间实体按 world_pos
## 挂到世界，走廊闸门镜像 FloorFlow 门判定，玩家按图进房（start 出生 → 战斗锁门 →
## 波次 → 清房开门）。房间构建/波次/奖励/弹幕可视均沿用 M0 RoomCombat 习语
## （见 room_combat.gd / training_room.gd，只读复用不改动）。
##
## 职责划分：流程判定全在 FloorFlow（纯逻辑，无头可测）；本文件是场景表现层与接线。
## 每个战斗系房自持 CombatSystem + RoomFlow（两波：wave1 3 垃圾、wave2 3 垃圾，
## elite 波2 +1 精英标记嘉宾），敌人按模板 spawn_points 刷出（M0 距门/距玩家过滤）。
##
## T12/T13 集成缝：elite/miniboss/boss 房嘉宾默认走占位（charger 行覆盖 3×/3×/8×hp，
## colossus r16）；`guest_spawner` Callable（签名 func(room_type, room_id, row, pos)）
## 注入后改由集成卡生成嘉宾（返回 EnemyBase 即接管）；room_event 信号同拍转发供其挂钩。
## treasure=宝箱武器掉落（权重 白60/绿30/蓝10，稀有档空缺回退全名录）；
## event/shop=空 Interactable 桩（C 线接入位）。遥测：floor_enter/floor_clear
## （每房清房用时）/loot 行，沿用既有 Telemetry CSV。

const TILE := 16
const WALL_T := 16
const PASSAGE_HALF := 16.0            # 走廊通行半宽（门洞 32px，M0 同款）
const GATE_T := 16.0                  # 闸门沿走廊向厚度
const SPAWN_MIN_DOOR_PX := 64.0
const SPAWN_MIN_PLAYER_PX := 120.0
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const DRIVER_SCRIPT := preload("res://core/rooms/player_driver.gd")
const GAME_CAMERA := preload("res://fx/game_camera.gd")
const BULLET_VISUAL_CAP := 500

## A1 名录（data/enemies.json）：楼层垃圾怪池，波次按房号确定性轮转组合。
const A1_TRASH := ["kuli_bug", "cave_bat", "crossbowman", "vine_charger"]
## T12 前占位嘉宾规格：vine_charger（charger 原型）行覆盖，kind 为标记。
const GUEST_SPECS := {
	"elite_charger": {"mult": 3, "radius": 6.0, "kind": "elite", "name": "精英·藤蔓冲锋者"},
	"miniboss_charger": {"mult": 3, "radius": 6.0, "kind": "miniboss", "name": "垒主·藤蔓冲锋者"},
	"vine_colossus": {"mult": 8, "radius": 16.0, "kind": "boss", "name": "藤蔓巨像（占位）"},
}
const GUEST_COLORS := {
	"elite": Color(1.0, 0.82, 0.25), "miniboss": Color(0.85, 0.25, 0.2),
	"boss": Color(0.2, 0.55, 0.25),
}
const ARCHETYPE_COLORS := {
	"shooter": Color(0.5, 0.6, 0.85), "suicide": Color(0.4, 0.8, 0.35),
	"charger": Color(0.7, 0.4, 0.8), "orbiter": Color(0.45, 0.42, 0.55),
	"dummy": Color(0.65, 0.5, 0.35),
}
const PLAYER_BULLET_COLOR := Color(1.0, 0.9, 0.35)
const ENEMY_BULLET_COLOR := Color(1.0, 0.35, 0.3)
const LOOT_RARITY_WEIGHTS := {"common": 60, "rare": 30, "epic": 10}   # 白/绿/蓝

signal room_event(room_type: String, room_id: int)

var flow := FloorFlow.new()
var player: Player = null
var floor_idx := 1
## T12/T13 嘉宾集成缝：func(room_type: String, room_id: int, row: Dictionary,
## pos: Vector2) -> Variant（返回 EnemyBase 即接管该嘉宾的生成）。
var guest_spawner := Callable()

var _rooms: Dictionary = {}           # int id -> FloorRoom
var _gates: Dictionary = {}           # "min|max" -> {shape, panel, a, b, open}
var _used_dirs: Dictionary = {}       # int id -> {dir: true}（走廊实接门方向）
var _combat_rng: RandomNumberGenerator
var _loot_rng: RandomNumberGenerator
var _last_loot := "laohuoji"
var _registered_combat: CombatSystem = null
var _bullet_layer: Node2D = null
var _bullet_sprites: Array[Polygon2D] = []
var _hud_label: Label = null
var _built := false
var _spawn_frames: Dictionary = {}    # enemy instance_id -> 刷出帧（ttk）


# ================================================================ 生命周期

func _ready() -> void:
	if _built:
		return
	# 直接运行 floor_scene.tscn（手动验证）：自举固定种子构建体 + 玩家。
	# 测试/宿主场景先 setup() 的路径不进此分支。
	if get_tree() != null and get_tree().current_scene == self:
		_bootstrap_standalone()


func _bootstrap_standalone() -> void:
	var build := DungeonBuilder.build(20260828, floor_idx)
	var p: Player = PLAYER_SCENE.instantiate() as Player
	setup(build, p)


func _physics_process(_delta: float) -> void:
	if not _built or player == null:
		return
	var frame := Engine.get_physics_frames()
	var room: FloorRoom = _rooms.get(flow.current_room)
	if room != null and room.combat != null:
		for e in room.enemies:
			if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
				e.brain_tick(frame)
		# 波推进：前一波全灭后 flow 已进下一波，此处补刷（M0 RoomCombat 习语）
		if room.room_flow.locked and not room.room_flow.cleared \
				and room.room_flow.wave_index() > room.spawned_wave:
			_spawn_wave(room)
	_detect_room_enter()


func _process(_delta: float) -> void:
	if not _built:
		return
	_sync_bullet_visuals()
	_update_hud()


# ================================================================ 装配

## 接管构建体 + 玩家：房间实体/走廊闸/玩家落位 start/交互/相机/HUD。
## 玩家无父节点时收养为子节点（宿主也可自行挂树后传入）。
func setup(build: Dictionary, p_player: Player) -> void:
	if _built:
		push_error("FloorScene.setup: already built")
		return
	_built = true
	player = p_player
	flow.setup(build)
	_combat_rng = RngSvc.stream(floor_idx, "combat")
	_loot_rng = RngSvc.stream(floor_idx, "loot")
	if player.get_parent() == null:
		add_child(player)
	if not player.is_in_group("player"):
		player.add_to_group("player")
	# 预扫描走廊 → 每房实接门方向（未用门框判定须先于房间几何构建）
	for c in build["corridors"]:
		var corridor: Dictionary = c
		_mark_used(int(corridor["a"]), String(corridor["dir"]))
		_mark_used(int(corridor["b"]), _opp(String(corridor["dir"])))
	for id in build["rooms"]:
		_build_room(int(id), build["rooms"][id])
	for c in build["corridors"]:
		_build_corridor(c)
	refresh_gates()
	_place_player_at_start()
	_wire_player_common()
	_attach_interaction()
	_attach_camera()
	_attach_hud()
	_bullet_layer = Node2D.new()
	_bullet_layer.name = "BulletVisuals"
	_bullet_layer.z_index = 20
	add_child(_bullet_layer)
	flow.room_event.connect(_on_flow_room_event)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	Telemetry.log_row(["floor_build", Engine.get_physics_frames(), str(_rooms.size())])


func _build_room(id: int, data: Dictionary) -> void:
	var room := FloorRoom.new()
	room.room_id = id
	room.name = "Room%d" % id
	room.type = String((data["node"] as Dictionary)["type"])
	room.template_id = String(data["template_id"])
	var tpl := RoomTemplate.get_room(room.template_id)
	var size: Array = tpl.get("size", [22, 14])
	var w: float = float(size[0]) * TILE
	var h: float = float(size[1]) * TILE
	room.position = Vector2(data["world_pos"])
	room.outer = Rect2(room.position, Vector2(w, h))
	var doors: Array = tpl.get("doors", [])
	_fill_door_centers(w, h, doors, room.door_local)
	add_child(room)
	_rooms[id] = room
	_build_floor_and_walls(room, w, h, doors)
	_build_unused_door_frames(room, w, h, doors)
	_build_props(room, tpl)
	_build_hazards(room, tpl)
	_init_spawn_points(room, tpl)
	if FloorFlow.COMBAT_TYPES.has(room.type):
		room.waves_cfg = waves_for(id, room.type)
		var pool_root := Node2D.new()
		pool_root.name = "ProjectilePoolRoot"
		room.add_child(pool_root)
		room.combat = CombatSystem.new(pool_root, _combat_rng)
		room.add_child(room.combat)


## 房内几何：地板染色 + 四面墙（模板门方向留 32px 门洞）。M0 _solid 习语。
func _build_floor_and_walls(room: FloorRoom, w: float, h: float, doors: Array) -> void:
	var interior := Rect2(WALL_T, WALL_T, w - WALL_T * 2.0, h - WALL_T * 2.0)
	var tint := Color(0.17, 0.15, 0.2)
	if room.type == "start":
		tint = Color(0.14, 0.16, 0.15)
	elif room.type == "boss":
		tint = Color(0.2, 0.13, 0.16)
	var floor_vis := Polygon2D.new()
	floor_vis.polygon = _rect_poly(interior)
	floor_vis.color = tint
	floor_vis.z_index = -10
	room.add_child(floor_vis)
	var cx := _door_axis(w)
	var cy := _door_axis(h)
	for seg in _wall_segments(Vector2(w, h), cx, cy, doors):
		_solid_child(room, seg)


## 墙段拆分：有门方向留门洞（门心 ± PASSAGE_HALF），无门方向整墙。
func _wall_segments(size: Vector2, cx: float, cy: float, doors: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for top: float in [0.0, size.y - WALL_T]:
		var dir := "N" if top == 0.0 else "S"
		if doors.has(dir):
			out.append(Rect2(0, top, cx - PASSAGE_HALF, WALL_T))
			out.append(Rect2(cx + PASSAGE_HALF, top, size.x - cx - PASSAGE_HALF, WALL_T))
		else:
			out.append(Rect2(0, top, size.x, WALL_T))
	for left: float in [0.0, size.x - WALL_T]:
		var dir_v := "W" if left == 0.0 else "E"
		if doors.has(dir_v):
			out.append(Rect2(left, WALL_T, WALL_T, cy - PASSAGE_HALF - WALL_T))
			out.append(Rect2(left, cy + PASSAGE_HALF, WALL_T, size.y - cy - PASSAGE_HALF - WALL_T))
		else:
			out.append(Rect2(left, WALL_T, WALL_T, size.y - WALL_T * 2.0))
	return out


## T7 裁定落地：模板有门但本层无走廊的方向 → 封闭门框实体（防走出世界）。
func _build_unused_door_frames(room: FloorRoom, w: float, h: float, doors: Array) -> void:
	var used: Dictionary = _used_dirs.get(room.room_id, {})
	var cx := _door_axis(w)
	var cy := _door_axis(h)
	for d: String in doors:
		if used.has(d):
			continue
		match d:
			"N":
				_solid_child(room, Rect2(cx - PASSAGE_HALF, 0, PASSAGE_HALF * 2.0, WALL_T))
			"S":
				_solid_child(room, Rect2(cx - PASSAGE_HALF, h - WALL_T, PASSAGE_HALF * 2.0, WALL_T))
			"W":
				_solid_child(room, Rect2(0, cy - PASSAGE_HALF, WALL_T, PASSAGE_HALF * 2.0))
			"E":
				_solid_child(room, Rect2(w - WALL_T, cy - PASSAGE_HALF, WALL_T, PASSAGE_HALF * 2.0))


## 模板陈设：pillar/crate 实体阻挡，bush 仅视觉；vine 减速带本卡数据占位视觉。
func _build_props(room: FloorRoom, tpl: Dictionary) -> void:
	for p: Dictionary in tpl.get("props", []):
		var center := _tile_center(p.get("grid", [0, 0]))
		match String(p.get("kind", "")):
			"pillar":
				_solid_child(room, Rect2(center - Vector2(8, 8), Vector2(16, 16)), Color(0.5, 0.48, 0.52))
			"crate":
				_solid_child(room, Rect2(center - Vector2(8, 8), Vector2(16, 16)), Color(0.55, 0.4, 0.24))
			"bush":
				_vis_child(room, Rect2(center - Vector2(7, 7), Vector2(14, 14)), Color(0.25, 0.42, 0.24))


func _build_hazards(room: FloorRoom, tpl: Dictionary) -> void:
	for hz: Dictionary in tpl.get("hazards", []):
		if String(hz.get("kind", "")) != "vine":
			continue
		var center := _tile_center(hz.get("grid", [0, 0]))
		var vis := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 12:
			pts.append(center + Vector2.from_angle(TAU * i / 12.0) * float(hz.get("radius", 24)))
		vis.polygon = pts
		vis.color = Color(0.3, 0.55, 0.3, 0.18)
		vis.z_index = -5
		room.add_child(vis)


func _init_spawn_points(room: FloorRoom, tpl: Dictionary) -> void:
	room.spawn_points.clear()
	for sp in tpl.get("spawn_points", []):
		room.spawn_points.append(room.position + _tile_center(sp))


## 走廊：地板条 + 两侧墙 + 中点闸门（实体 + 门体视觉），状态由 refresh_gates 驱动。
func _build_corridor(c: Dictionary) -> void:
	var a := int(c["a"])
	var b := int(c["b"])
	var dir := String(c["dir"])
	var ra: FloorRoom = _rooms.get(a)
	var rb: FloorRoom = _rooms.get(b)
	var pa := ra.position
	var floor_rect := Rect2()
	var gate_pos := Vector2.ZERO
	var gate_size := Vector2()
	match dir:
		"E":
			var yc: float = pa.y + ra.door_local["E"].y
			var x0: float = pa.x + ra.outer.size.x
			var len_x: float = rb.position.x - x0
			floor_rect = Rect2(x0, yc - PASSAGE_HALF, len_x, PASSAGE_HALF * 2.0)
			gate_pos = Vector2(x0 + len_x / 2.0, yc)
			gate_size = Vector2(GATE_T, PASSAGE_HALF * 2.0)
		"W":
			var yc: float = pa.y + ra.door_local["W"].y
			var x1: float = rb.position.x + rb.outer.size.x
			var len_x: float = pa.x - x1
			floor_rect = Rect2(x1, yc - PASSAGE_HALF, len_x, PASSAGE_HALF * 2.0)
			gate_pos = Vector2(x1 + len_x / 2.0, yc)
			gate_size = Vector2(GATE_T, PASSAGE_HALF * 2.0)
		"S":
			var xc: float = pa.x + ra.door_local["S"].x
			var y0: float = pa.y + ra.outer.size.y
			var len_y: float = rb.position.y - y0
			floor_rect = Rect2(xc - PASSAGE_HALF, y0, PASSAGE_HALF * 2.0, len_y)
			gate_pos = Vector2(xc, y0 + len_y / 2.0)
			gate_size = Vector2(PASSAGE_HALF * 2.0, GATE_T)
		"N":
			var xc: float = pa.x + ra.door_local["N"].x
			var y1: float = rb.position.y + rb.outer.size.y
			var len_y: float = pa.y - y1
			floor_rect = Rect2(xc - PASSAGE_HALF, y1, PASSAGE_HALF * 2.0, len_y)
			gate_pos = Vector2(xc, y1 + len_y / 2.0)
			gate_size = Vector2(PASSAGE_HALF * 2.0, GATE_T)
		_:
			push_error("FloorScene: bad corridor dir '%s'" % dir)
			return
	var corridor_floor := Polygon2D.new()
	corridor_floor.polygon = _rect_poly(floor_rect)
	corridor_floor.color = Color(0.13, 0.12, 0.16)
	corridor_floor.z_index = -10
	add_child(corridor_floor)
	if dir == "E" or dir == "W":
		_solid_world(Rect2(floor_rect.position.x, floor_rect.position.y - WALL_T,
			floor_rect.size.x, WALL_T))
		_solid_world(Rect2(floor_rect.position.x, floor_rect.end.y,
			floor_rect.size.x, WALL_T))
	else:
		_solid_world(Rect2(floor_rect.position.x - WALL_T, floor_rect.position.y,
			WALL_T, floor_rect.size.y))
		_solid_world(Rect2(floor_rect.end.x, floor_rect.position.y,
			WALL_T, floor_rect.size.y))
	var gate := StaticBody2D.new()
	gate.position = gate_pos
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = gate_size
	cs.shape = shape
	gate.add_child(cs)
	add_child(gate)
	var panel := Polygon2D.new()
	var panel_rect := Rect2(-(gate_size.x + 2.0) / 2.0, -(gate_size.y + 2.0) / 2.0,
		gate_size.x + 2.0, gate_size.y + 2.0)
	panel.polygon = _rect_poly(panel_rect)
	panel.color = Color(0.62, 0.4, 0.22)
	panel.position = gate_pos
	panel.z_index = 5
	add_child(panel)
	DoorAnim.install(panel, gate_pos)          # m1-t18：统一门动画（闭合位即门位）
	var key := "%d|%d" % [mini(a, b), maxi(a, b)]
	_gates[key] = {"shape": cs, "panel": panel, "a": mini(a, b), "b": maxi(a, b), "open": false}


# ================================================================ 玩家 / 房间流

func _place_player_at_start() -> void:
	var start: FloorRoom = _rooms.get(flow.start_room())
	if player == null or start == null:
		push_error("FloorScene: no player or start room")
		return
	player.position = start.outer.get_center()


## 玩家侧公共接线（一次性）：初始枪 / 输入驱动。combat 注入随进房切到当前房。
func _wire_player_common() -> void:
	var rig := player.get_node("WeaponRig") as WeaponRig
	if rig.current().is_empty():
		rig.equip("laohuoji")
	if not player.has_node("Driver"):
		var driver := Node.new()
		driver.name = "Driver"
		driver.set_script(DRIVER_SCRIPT)
		player.add_child(driver)


## 进房接线（M0 t12 契约）：rig/melee/player.combat 注入当前房 combat 流并登记玩家体。
func _wire_room_combat(room: FloorRoom) -> void:
	if room.combat == null:
		return
	if _registered_combat != null and is_instance_valid(_registered_combat):
		_registered_combat.unregister_body(player)
	var rig := player.get_node("WeaponRig") as WeaponRig
	var melee := player.get_node("Melee") as Melee
	rig.combat = room.combat
	rig.combat_rng = _combat_rng
	melee.combat = room.combat
	melee.combat_rng = _combat_rng
	melee.rig = rig
	player.combat = room.combat
	room.combat.register_body(player, player.combat_faction())
	_registered_combat = room.combat
	_ensure_proxy(room)


func _ensure_proxy(room: FloorRoom) -> void:
	if room.player_proxy != null and is_instance_valid(room.player_proxy):
		return
	room.player_proxy = PlayerProxy.new()
	room.player_proxy.name = "PlayerProxy"
	room.player_proxy.player = player
	room.add_child(room.player_proxy)


## 按图进房：flow 判定（含 boss 门规则）→ 接线/开战/即清房陈设 → 门闸刷新。
## 拒绝时（理论上闸门实体已拦）把玩家推回当前房中心，防软锁。
func enter_room(id: int) -> bool:
	if not _built:
		return false
	var room: FloorRoom = _rooms.get(int(id))
	if room == null:
		return false
	if not flow.enter_room(id):
		_push_back()
		return false
	_wire_room_combat(room)
	room.entry_frame = Engine.get_physics_frames()
	Telemetry.log_row(["floor_enter", room.entry_frame, room.template_id])
	if room.combat != null and not flow.is_cleared(id):
		_start_room_combat(room)
	else:
		_place_guests(room)
		if not room.cleared_emitted:
			_emit_room_clear(room)
	refresh_gates()
	return true


func _push_back() -> void:
	var room: FloorRoom = _rooms.get(flow.current_room)
	if player != null and room != null:
		player.position = room.outer.get_center()


func _start_room_combat(room: FloorRoom) -> void:
	room.room_flow.setup(room.waves_cfg)
	room.room_flow.on_entered(room.entry_frame)
	_spawn_wave(room)


func _spawn_wave(room: FloorRoom) -> void:
	room.spawned_wave = room.room_flow.wave_index()
	var player_pos := player.global_position if player != null else room.outer.get_center()
	var doors_world: Array[Vector2] = []
	for d: Vector2 in room.door_local.values():
		doors_world.append(room.position + d)
	var points := RoomCombat.filter_spawn_points(room.spawn_points, doors_world, player_pos,
		SPAWN_MIN_DOOR_PX, SPAWN_MIN_PLAYER_PX)
	if points.is_empty():
		push_error("FloorScene: room %d has no spawn points" % room.room_id)
		return
	var i := 0
	for enemy_id: String in room.room_flow.current_wave_ids():
		_spawn_enemy(room, enemy_id, points[i % points.size()])
		i += 1


func _spawn_enemy(room: FloorRoom, id: String, world_pos: Vector2) -> void:
	var is_guest := GUEST_SPECS.has(id)
	var row: Dictionary = guest_row(id) if is_guest else GameDB.get_enemy(id)
	if row.is_empty():
		push_error("FloorScene: unknown enemy '%s'" % id)
		room.room_flow.notify_killed(id, Engine.get_physics_frames())
		return
	# T12/T13 缝：guest_spawner 注入时嘉宾生成让位集成卡（返回 EnemyBase 即接管）。
	if is_guest and guest_spawner.is_valid():
		var spawned: Variant = guest_spawner.call(room.type, room.room_id, row.duplicate(), world_pos)
		if spawned is EnemyBase:
			var g := spawned as EnemyBase
			g.position = world_pos - room.position   # 房间子节点：世界刷点 → 房间局部
			room.add_child(g)
			g.setup(row)
			g.combat = room.combat
			g.player_ref = room.player_proxy
			g.add_to_group("enemies")
			room.combat.register_body(g, g.combat_faction())
			room.enemies.append(g)
			_spawn_frames[g.get_instance_id()] = Engine.get_physics_frames()
			return
		# 缝返回非 EnemyBase：落回占位路径（响亮告警，集成卡自行排查）
		push_warning("FloorScene: guest_spawner returned type %d for '%s' — placeholder fallback"
			% [typeof(spawned), id])
	var e := EnemyBase.new()
	e.position = world_pos - room.position   # 房间子节点：世界刷点 → 房间局部
	room.add_child(e)
	e.setup(row)
	e.combat = room.combat
	e.player_ref = room.player_proxy
	e.add_to_group("enemies")
	_dress_enemy(e, row)
	room.combat.register_body(e, e.combat_faction())
	room.enemies.append(e)
	_spawn_frames[e.get_instance_id()] = Engine.get_physics_frames()


## 敌人外观（M0 习语）：碰撞圆 + 方块色块；嘉宾按 kind 染色标记。
func _dress_enemy(e: EnemyBase, row: Dictionary) -> void:
	var radius := float(row.get("radius", 6.0))
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	e.add_child(cs)
	var vis := Polygon2D.new()
	vis.name = "Sprite"                        # Fx 白闪按名寻址
	var r := maxf(radius, 5.0)
	vis.polygon = PackedVector2Array([
		Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r),
	])
	var color: Color = ARCHETYPE_COLORS.get(String(row.get("archetype", "")), Color.WHITE)
	var kind := String(row.get("guest_kind", ""))
	if GUEST_COLORS.has(kind):
		color = GUEST_COLORS[kind]
	vis.color = color
	e.add_child(vis)


## kill 路由（M0 习语）：EventBus.enemy_killed → 当前房匹配 → 波次推进 → 清房。
func _on_enemy_killed(enemy_id: String) -> void:
	if not _built:
		return
	var room: FloorRoom = _rooms.get(flow.current_room)
	if room == null or room.combat == null:
		return
	var frame := Engine.get_physics_frames()
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == enemy_id:
			var ttk := frame - int(_spawn_frames.get(e.get_instance_id(), frame))
			Fx.on_enemy_killed(e.global_position)
			Telemetry.log_row(["kill", frame, enemy_id, ttk],
				RoomCombat.kill_source(e.row, _current_weapon_id()))
			room.enemies.erase(e)
			break
	room.room_flow.notify_killed(enemy_id, frame)
	if room.room_flow.cleared and not room.cleared_emitted:
		flow.notify_room_cleared(room.room_id)
		_emit_room_clear(room)
		refresh_gates()


## m1-t18 kill 行来源取值：玩家当前武器 id（rig 未接线 → ""）；boss 判定复用 RoomCombat.kill_source。
func _current_weapon_id() -> String:
	if player != null and player.weapon_rig != null:
		var w := player.weapon_rig.current()
		if not w.is_empty():
			return String(w.get("id", ""))
	return ""


## 清房：遥测（每房清房用时）+ room_cleared 广播 + 奖励爆发（战斗房）。
func _emit_room_clear(room: FloorRoom) -> void:
	room.cleared_emitted = true
	var frame := Engine.get_physics_frames()
	Telemetry.log_row(["floor_clear", frame, room.template_id, frame - room.entry_frame])
	EventBus.room_cleared.emit(room.template_id)
	var rewards := room.room_flow.rewards
	if not rewards.is_empty():
		_spawn_rewards(room, rewards)


func _spawn_rewards(room: FloorRoom, rewards: Dictionary) -> void:
	var center := room.outer.get_center()
	for i in int(rewards.get("coins", 0)):
		_spawn_pickup(room, "coin", center + _scatter(i))
	for i in int(rewards.get("energy_orbs", 0)):
		_spawn_pickup(room, "energy", center + _scatter(37 + i))
	for i in int(rewards.get("hearts", 0)):
		_spawn_pickup(room, "heart", center + _scatter(53 + i))


## 确定性散布（黄金角），不引入随机（M0 习语）。
func _scatter(i: int) -> Vector2:
	return Vector2.from_angle(float(i) * 2.399963) * (6.0 + 5.0 * sqrt(float(i % 17)))


func _spawn_pickup(room: FloorRoom, kind: String, world_pos: Vector2) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.position = world_pos - room.position   # 房间子节点：世界落点 → 房间局部
	p.on_collect = func() -> void: room.coins += 1
	room.add_child(p)


func _detect_room_enter() -> void:
	if player == null:
		return
	for id in _rooms:
		var room: FloorRoom = _rooms[id]
		if int(id) != flow.current_room and room.outer.has_point(player.global_position):
			enter_room(int(id))
			return


func _on_flow_room_event(room_type: String, room_id: int) -> void:
	room_event.emit(room_type, room_id)


func _mark_used(id: int, dir: String) -> void:
	if not _used_dirs.has(id):
		_used_dirs[id] = {}
	(_used_dirs[id] as Dictionary)[dir] = true


# ================================================================ 门闸

## 全楼闸门刷新：flow 门判定镜像到走廊闸实体（开 = 碰撞关 + DoorAnim 滑出隐藏；
## 规则锁（boss 未解 / 双未清）红门，战斗封门棕门——brief「未达房间门显示锁形」）。
## m1-t18：可见性瞬切改统一 DoorAnim（开 = 滑出后隐藏，终态等价原瞬隐）。
func refresh_gates() -> void:
	for key in _gates:
		var g: Dictionary = _gates[key]
		var open: bool = flow.doors_open_between(int(g["a"]), int(g["b"]))
		g["open"] = open
		var cs: CollisionShape2D = g["shape"]
		cs.set_deferred("disabled", open)
		var panel: Polygon2D = g["panel"]
		if open:
			DoorAnim.open(panel, true)
		else:
			DoorAnim.close(panel)
		panel.color = Color(0.7, 0.2, 0.2) if (not open and _rule_locked(int(g["a"]), int(g["b"]))) \
			else Color(0.62, 0.4, 0.22)


func _rule_locked(a: int, b: int) -> bool:
	if (a == flow.boss_room() or b == flow.boss_room()) and not flow.boss_door_unlocked():
		return true
	return not (flow.is_cleared(a) or flow.is_cleared(b))


func gate_is_open(a: int, b: int) -> bool:
	var key := "%d|%d" % [mini(a, b), maxi(a, b)]
	if not _gates.has(key):
		return false
	return bool(_gates[key]["open"])


# ================================================================ 客房陈设（数据占位）

## 首次进入时放置：treasure 宝箱 / event·shop 空桩（elite/miniboss/boss 嘉宾走战斗波次）。
func _place_guests(room: FloorRoom) -> void:
	if room.guests_placed:
		return
	room.guests_placed = true
	var center := room.outer.get_center() - room.position
	match room.type:
		"treasure":
			_build_chest(room, center)
		"shop":
			_build_stub(room, center, "商店（C线未接入）")
		"event":
			_build_stub(room, center, "事件（C线未接入）")


## 宝箱：开箱 → 权重 roll 武器（loot 遥测）→ 掉落台出现在箱位（再按 E 换手）。
func _build_chest(room: FloorRoom, local_pos: Vector2) -> void:
	var chest := FixtureInteractable.new()
	chest.name = "Chest"
	chest.position = local_pos
	chest.action_label = "打开宝箱"
	chest.add_child(_fixture_body())
	var vis := Polygon2D.new()
	vis.name = "Sprite"
	vis.polygon = _rect_poly(Rect2(-9, -7, 18, 14))
	vis.color = Color(0.75, 0.58, 0.2)
	chest.add_child(vis)
	chest.on_interact_cb = func(p: Node2D) -> void:
		chest.enabled = false                       # 一次性
		vis.color = Color(0.4, 0.34, 0.16)
		var pl := p as Player
		if pl != null:
			var rig := pl.get_node("WeaponRig") as WeaponRig
			var rarity := _roll_rarity()
			var wid := _roll_weapon(rarity)
			rig.equip(wid)
			Telemetry.log_row(["loot", Engine.get_physics_frames(), wid, rarity])
		room.add_child(_build_loot_station(room, local_pos + Vector2(0, 22)))
	room.add_child(chest)


## 武器掉落台：宝箱→掉落的落地形态，再按 E 换手（一次性）。
func _build_loot_station(room: FloorRoom, local_pos: Vector2) -> FixtureInteractable:
	var station := FixtureInteractable.new()
	station.name = "LootStation"
	station.position = local_pos
	station.action_label = "拾取武器"
	station.add_child(_fixture_body())
	var sv := Polygon2D.new()
	sv.polygon = _rect_poly(Rect2(-6, -6, 12, 12))
	sv.color = Color(0.3, 0.6, 0.75)
	station.add_child(sv)
	var wid := _last_loot
	station.on_interact_cb = func(p: Node2D) -> void:
		station.enabled = false
		var pl := p as Player
		if pl != null:
			(pl.get_node("WeaponRig") as WeaponRig).equip(wid)
	return station


func _build_stub(room: FloorRoom, local_pos: Vector2, label: String) -> void:
	var stub := FixtureInteractable.new()
	stub.position = local_pos
	stub.action_label = label
	stub.add_child(_fixture_body())
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-8, -8, 16, 16))
	vis.color = Color(0.35, 0.35, 0.45)
	stub.add_child(vis)
	room.add_child(stub)


func _fixture_body() -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	cs.shape = shape
	return cs


## 掉落权重 白60/绿30/蓝10（LOOT_RARITY_WEIGHTS 累积区间）；确定性 loot 流。
func _roll_rarity() -> String:
	var roll := _loot_rng.randi_range(1, 100)
	var acc := 0
	for rarity: String in ["common", "rare", "epic"]:
		acc += int(LOOT_RARITY_WEIGHTS.get(rarity, 0))
		if roll <= acc:
			return rarity
	return "common"


func _roll_weapon(rarity: String) -> String:
	var ids: Array[String] = []
	for wid: String in GameDB.weapons:
		if String((GameDB.weapons[wid] as Dictionary).get("rarity", "common")) == rarity:
			ids.append(wid)
	if ids.is_empty():
		for wid: String in GameDB.weapons:
			ids.append(wid)
	ids.sort()
	_last_loot = ids[_loot_rng.randi_range(0, ids.size() - 1)]
	return _last_loot


# ================================================================ 波次/嘉宾数据（静态可测）

## 波次组合（按 floor 预算的 A1 名录确定性轮转）：combat 2 波各 3 垃圾；
## elite 波2 +1 精英标记嘉宾 +2 红心；miniboss 2 垃圾→强化怪；boss 单波巨像占位。
static func waves_for(room_id: int, room_type: String) -> Dictionary:
	var trash := func(offset: int, n: int) -> Array:
		var out: Array = []
		for i in n:
			out.append(A1_TRASH[(offset + i) % A1_TRASH.size()])
		return out
	var o := (int(room_id) * 2) % A1_TRASH.size()
	match room_type:
		"combat":
			return {"waves": [trash.call(o, 3), trash.call(o + 3, 3)],
				"coins": 20, "energy_orbs": 4, "hearts": 0}
		"elite":
			var w2: Array = trash.call(o + 3, 3)
			w2.append("elite_charger")
			return {"waves": [trash.call(o, 3), w2],
				"coins": 20, "energy_orbs": 4, "hearts": 2}
		"miniboss":
			return {"waves": [trash.call(o, 2), ["miniboss_charger"]],
				"coins": 40, "energy_orbs": 6, "hearts": 0}
		"boss":
			return {"waves": [["vine_colossus"]],
				"coins": 60, "energy_orbs": 8, "hearts": 0}
	return {}


## T12 前占位嘉宾行：vine_charger（charger 原型）按规格覆盖 hp/radius，kind 为标记。
static func guest_row(id: String) -> Dictionary:
	var spec: Dictionary = GUEST_SPECS.get(id, {})
	if spec.is_empty():
		return {}
	var row: Dictionary = GameDB.get_enemy("vine_charger").duplicate()
	if row.is_empty():
		return {}
	row["id"] = id
	row["name"] = String(spec["name"])
	row["hp"] = int(row.get("hp", 18)) * int(spec["mult"])
	row["radius"] = float(spec["radius"])
	row["guest_kind"] = String(spec["kind"])
	return row


# ================================================================ 相机 / HUD / 弹幕可视

func _attach_interaction() -> void:
	var sys := InteractionSystem.new()
	sys.name = "InteractionSystem"
	sys.player = player
	add_child(sys)


func _attach_camera() -> void:
	var bounds := Rect2()
	for id in _rooms:
		bounds = bounds.merge((_rooms[id] as FloorRoom).outer)
	var cam: Camera2D = GAME_CAMERA.new()
	cam.set("target", player)
	cam.limit_left = int(bounds.position.x) - TILE
	cam.limit_top = int(bounds.position.y) - TILE
	cam.limit_right = int(bounds.end.x) + TILE
	cam.limit_bottom = int(bounds.end.y) + TILE
	add_child(cam)


func _attach_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_hud_label = Label.new()
	_hud_label.position = Vector2(4, 2)
	_hud_label.add_theme_font_size_override("font_size", 8)
	layer.add_child(_hud_label)
	add_child(layer)


func _update_hud() -> void:
	if _hud_label == null:
		return
	var room: FloorRoom = _rooms.get(flow.current_room)
	if room == null:
		return
	var t := 0.0
	if room.entry_frame >= 0:
		t = float(Engine.get_physics_frames() - room.entry_frame) / 60.0
	var boss_state := "解锁" if flow.boss_door_unlocked() else "锁定"
	_hud_label.text = "M1-T10 floor%d | %s(%s) %s | 用时%.1fs | boss门:%s" % [
		floor_idx, room.template_id, room.type,
		"已清" if flow.is_cleared(room.room_id) else "未清", t, boss_state,
	]


## 表现层弹幕镜像（M0 习语）：当前房 combat 池 → 共享多边形逐帧同步。
func _sync_bullet_visuals() -> void:
	var active: Array = []
	var room: FloorRoom = _rooms.get(flow.current_room)
	if room != null and room.combat != null:
		active = room.combat.pool.active
	if _bullet_layer == null:
		return
	while _bullet_sprites.size() < active.size() and _bullet_sprites.size() < BULLET_VISUAL_CAP:
		var vis := Polygon2D.new()
		vis.polygon = PackedVector2Array([
			Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(2.5, 2.5), Vector2(-2.5, 2.5),
		])
		_bullet_layer.add_child(vis)
		_bullet_sprites.append(vis)
	for i in _bullet_sprites.size():
		var vis := _bullet_sprites[i]
		if i < active.size():
			var p: Projectile = active[i]
			vis.visible = true
			vis.position = p.position
			var base := PLAYER_BULLET_COLOR if p.faction == Projectile.Faction.PLAYER else ENEMY_BULLET_COLOR
			vis.modulate = base * p.modulate
		else:
			vis.visible = false


# ================================================================ 查询面（测试/HUD）

func room_count() -> int:
	return _rooms.size()


func gate_count() -> int:
	return _gates.size()


func room_node(id: int) -> FloorRoom:
	return _rooms.get(int(id))


func room_rect(id: int) -> Rect2:
	return (_rooms.get(int(id)) as FloorRoom).outer


func room_center(id: int) -> Vector2:
	return (_rooms.get(int(id)) as FloorRoom).outer.get_center()


func player_node() -> Player:
	return player


# ================================================================ 内部类型 / 小工具

## 一次性可交互物（宝箱/桩/掉落台通用）：enabled 门控 + 回调。
class FixtureInteractable extends Interactable:
	var on_interact_cb := Callable()
	var enabled := true

	func can_interact(_player_node: Node2D) -> bool:
		return enabled

	func interact(p: Node2D) -> void:
		if enabled and on_interact_cb.is_valid():
			on_interact_cb.call(p)


## 楼层房间实体：几何/波次配置/战斗系统/敌表的挂载点（M0 RoomCombat 的层内化身）。
class FloorRoom extends Node2D:
	var room_id := -1
	var type := "combat"
	var template_id := ""
	var outer := Rect2()                      # 世界坐标外框（含墙）
	var combat: CombatSystem = null
	var room_flow := RoomFlow.new()           # 每房波次状态机（M0 纯逻辑复用）
	var player_proxy: PlayerProxy = null
	var spawn_points: Array[Vector2] = []     # 世界坐标刷怪点
	var door_local: Dictionary = {}           # dir -> 局部门心
	var waves_cfg := {}
	var enemies: Array[EnemyBase] = []
	var entry_frame := -1
	var spawned_wave := -1
	var guests_placed := false
	var cleared_emitted := false
	var coins := 0

	func wave_ids(index: int) -> Array:
		var waves: Array = waves_cfg.get("waves", [])
		if index < 0 or index >= waves.size():
			return []
		return waves[index]


## 门洞轴向中心：偶数格宽取几何中点（22 格 → 176px 轴向，开 32px 洞）。
func _door_axis(span_px: float) -> float:
	return span_px / 2.0


## 模板门方向 → 局部门心（墙带中点；洞几何与门框/闸门共用此轴）。
func _fill_door_centers(w: float, h: float, doors: Array, into: Dictionary) -> void:
	into.clear()
	var cx := _door_axis(w)
	var cy := _door_axis(h)
	for d: String in doors:
		match d:
			"N":
				into[d] = Vector2(cx, WALL_T / 2.0)
			"S":
				into[d] = Vector2(cx, h - WALL_T / 2.0)
			"W":
				into[d] = Vector2(WALL_T / 2.0, cy)
			"E":
				into[d] = Vector2(w - WALL_T / 2.0, cy)


func _tile_center(grid: Array) -> Vector2:
	return Vector2(float(grid[0]) * TILE + TILE / 2.0, float(grid[1]) * TILE + TILE / 2.0)


func _solid_child(room: FloorRoom, rect: Rect2, color: Color = Color(0.36, 0.3, 0.28)) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	room.add_child(body)
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
	vis.color = color
	body.add_child(vis)


func _solid_world(rect: Rect2) -> void:
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


func _vis_child(room: FloorRoom, rect: Rect2, color: Color) -> void:
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
	vis.position = rect.get_center()
	vis.color = color
	room.add_child(vis)


func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])


func _opp(dir: String) -> String:
	match dir:
		"N":
			return "S"
		"S":
			return "N"
		"E":
			return "W"
	return "E"
