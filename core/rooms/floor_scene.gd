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
## T12/T13 集成缝：elite/miniboss/boss 房嘉宾三档优先级——外部 `guest_spawner`
## Callable 注入（返回 EnemyBase 即接管，T12 原契约）> `use_real_guests`（m1-t27
## 默认开：按房型换真实数据行，词缀/boss_script 经 EnemyBase.setup 数据驱动生效）
## > 占位（charger 行覆盖，供纯 FloorScene 消费/回归对照）。
## m1-t27 设施缝：room_event 首进恰一次 → shop=真商店（RunState 钱包+当层货单）/
## event=EventRoom 进房即开事件面板（全屏弹层，同 buff_pick 呈现口径）；
## treasure=宝箱武器掉落（权重 白60/绿30/蓝10，稀有档空缺回退全名录）。
## m1-t27 层间缝：boss 房清发出 boss_defeated（宿主 RunRoot 开 inter_floor）；
## 精英/垒主行内 drops（weapon/hearts2）死亡即落；金币拾取同步入账 RunState。
## 遥测：floor_enter/floor_clear（每房清房用时）/loot 行，沿用既有 Telemetry CSV。

const TILE := 16
const WALL_T := 16
## m2-t4 A2 生态（GDD §10）：冰面补丁常量演示尺寸（A2 模板 JSON biome 字段后续卡驱动）。
const A2_ICE_PATCH_PX := Vector2(96, 64)
const PASSAGE_HALF := 16.0            # 走廊通行半宽（门洞 32px，M0 同款）
const GATE_T := 16.0                  # 闸门沿走廊向厚度
const SPAWN_MIN_DOOR_PX := 64.0
const SPAWN_MIN_PLAYER_PX := 120.0
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const DRIVER_SCRIPT := preload("res://core/rooms/player_driver.gd")
const GAME_CAMERA := preload("res://fx/game_camera.gd")
const SHOP_SCENE := preload("res://core/interact/shop.tscn")   # m1-t27 商店设施
const BULLET_VISUAL_CAP := 500
const BLACK_SHOP_CHANCE := 0.25

## m2-t7 危险地块视觉常量（表现，非玩法数值——周期/伤害在 HazardSpikes/RollingRock）。
const SPIKE_WARN_COLOR := Color(1.0, 0.35, 0.3, 0.35)    # 地面红纹（预警）
const SPIKE_OUT_COLOR := Color(0.9, 0.15, 0.1, 1.0)      # 伸出（伤害窗）
const SPIKE_TILE_PX := 16.0                              # 地刺判定/视觉一格瓦片
## m2-t7 滚石发射侧 → 滚动方向（从该侧垂直滚入房）。
const ROCK_SIDE_DIRS := {
	"W": Vector2.RIGHT, "E": Vector2.LEFT, "N": Vector2.DOWN, "S": Vector2.UP,
}
## m2-t10 A3 岩浆系视觉常量（表现，非玩法数值——周期/伤害在 HazardMagma 三组件）。
const GEYSER_TILE_PX := 16.0                                # 喷口判定/视觉一格瓦片
const GEYSER_WARN_COLOR := Color(1.0, 0.45, 0.2, 0.35)       # 喷口预警（地面橙纹）
const GEYSER_ERUPT_COLOR := Color(1.0, 0.25, 0.1, 1.0)       # 喷发（伤害窗）
const MAGMA_POOL_COLOR := Color(0.9, 0.35, 0.1, 0.55)        # 岩浆池缺图回落染色
const FIRE_RAIN_WARN_COLOR := Color(1.0, 0.3, 0.2, 0.35)     # 火雨红圈（预警）
const FIRE_RAIN_BOOM_COLOR := Color(1.0, 0.5, 0.15, 0.8)     # 火雨落点爆发拍

## A1 名录（data/enemies.json）：楼层垃圾怪池，波次按房号确定性轮转组合。
const A1_TRASH := ["kuli_bug", "cave_bat", "crossbowman", "vine_charger"]
## m1-t27 真实嘉宾映射（波次标记 id → 数据行 id）：精英=双刀蜥人（swift+berserk 词缀，
## drops weapon+hearts2）、垒主=自爆王虫（armored+leech，drops weapon+hearts2）、
## boss=藤蔓巨像（行内 boss_script → 真 3 阶段 BossBase 子类）。
const REAL_GUEST_ROWS := {
	"elite_charger": "shuangdao_lizardman",
	"miniboss_charger": "zibao_wangchong",
	"vine_colossus": "vine_colossus",
}
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
	"dummy": Color(0.65, 0.5, 0.35), "mushroom_spore": Color(0.58, 0.82, 0.46),
}
const LOOT_RARITY_WEIGHTS := {"common": 60, "rare": 30, "epic": 10}   # 白/绿/蓝
## m1-t28 美术接线（ArtLookup 表驱动）：地块按生物群系选 floor_*/wall_*。
const BULLET_VISUAL_SCALE := 0.75      # 8x8 弹底图 ≈ 原 5px 方块

signal room_event(room_type: String, room_id: int)
## m1-t27：boss 房清（巨像死亡）——宿主 RunRoot 据此开层间中转。
signal boss_defeated(room_id: int)

var flow := FloorFlow.new()
var player: Player = null
var floor_idx := 1
## m1-t27 真实嘉宾开关（默认开）：false 退回 T12 占位路径（回归对照/纯楼测试）。
## 优先级：外部 guest_spawner 注入 > use_real_guests 真实行 > 占位。
var use_real_guests := true
## T12/T13 嘉宾集成缝：func(room_type: String, room_id: int, row: Dictionary,
## pos: Vector2) -> Variant（返回 EnemyBase 即接管该嘉宾的生成）。
var guest_spawner := Callable()
var buffs_manager: BuffManager = null
## m2-t4 A2 生态挂载状态：暗视野组件 + 冰面区域（set_biome_a2 挂载/卸载）。
var biome_a2 := false
var biome_fx: BiomeFx = null
var biome_ice: IceZone = null
## m2-t7 危险地块注册表（模板 hazards 字段实例化，_build_hazards 填充）：
## 藤蔓减速域（整层单实例多 zone）+ 地刺/滚石逐 hazard 实例（_tick_hazards 帧驱动）。
var hazard_vines: VineZone = null
var _spikes: Array[HazardSpikes] = []
var _spikes_vis: Array[CanvasItem] = []
var _rocks: Array[RollingRock] = []
var _rock_vis: Array[CanvasItem] = []
var _rock_line_vis: Array[CanvasItem] = []
## m2-t10 A3 岩浆系（同注册表扩展）：岩浆 DOT 域（整层单实例多 zone）+ 喷口逐 hazard
## 实例 + 火雨组件（常驻空载，Boss/事件经 schedule_fire_rain 驱动——T19/T24 契约）。
var hazard_magma: HazardMagma = null
var _geysers: Array[HazardMagma.MagmaGeyser] = []
var _geyser_vis: Array[CanvasItem] = []
var hazard_fire_rain: HazardMagma.FireRain = HazardMagma.FireRain.new()
var _fire_rain_vis: Array[CanvasItem] = []

var _rooms: Dictionary = {}           # int id -> FloorRoom
var _gates: Dictionary = {}           # "min|max" -> {shape, panel, a, b, open}
var _used_dirs: Dictionary = {}       # int id -> {dir: true}（走廊实接门方向）
var _combat_rng: RandomNumberGenerator
var _rig_rng: RandomNumberGenerator
var _loot_rng: RandomNumberGenerator
var _registered_combat: CombatSystem = null
var _bullet_layer: Node2D = null
var _bullet_sprites: Array[Sprite2D] = []
var _built := false
var _spawn_frames: Dictionary = {}    # enemy instance_id -> 刷出帧（ttk）
## m1-t27：楼层流程挂起（boss 房清 → 层间中转接管玩家期间停用按图进房检测，
## 防把玩家从层间中转房抢回楼层；层重建 = 新实例，标志自然复位）。
var _flow_suspended := false
var _facility_rng: RandomNumberGenerator
var _drink_state := {"uses_left": DrinkMachine.USES_PER_FLOOR}
var _used_shrine_kinds: Dictionary = {}


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


## RunRoot 注入整局设施状态：饮料按楼层持久、四类雕像按整局持久。
## 直接运行/单测不调用本方法时仍使用本 FloorScene 实例自己的新鲜状态。
func bind_facility_state(drink_state: Dictionary, used_shrine_kinds: Dictionary) -> void:
	_drink_state = drink_state
	if not _drink_state.has("uses_left"):
		_drink_state["uses_left"] = DrinkMachine.USES_PER_FLOOR
	_used_shrine_kinds = used_shrine_kinds


## m2-t4 A2 生态开关（GDD §10 A2「暗视野 + 冰面打滑」）：true 挂暗视野组件
## （CanvasModulate + 玩家光圈 + 敌人剪影下限）并给每房铺一块冰面补丁；false 卸载
## 并恢复（敌人 modulate 复位、玩家 friction_mult 回 1.0）。幂等：重复同值调用 no-op。
## 冰面补丁现为常量演示（每房内域中心 A2_ICE_PATCH_PX）；A2 模板 JSON 的 biome 字段
## 由后续卡替换此处数据源。
func set_biome_a2(enabled: bool) -> void:
	if biome_a2 == enabled:
		return
	biome_a2 = enabled
	if enabled:
		if player == null:
			push_error("FloorScene.set_biome_a2: no player")
			biome_a2 = false
			return
		biome_fx = BiomeFx.new()
		biome_fx.name = "BiomeA2Fx"
		biome_fx.setup(player)
		add_child(biome_fx)
		biome_ice = IceZone.new()
		for id in _rooms:
			var room: FloorRoom = _rooms[id]
			var inner := room.outer.grow(-WALL_T)
			biome_ice.add_zone(Rect2(inner.get_center() - A2_ICE_PATCH_PX / 2.0, A2_ICE_PATCH_PX))
	else:
		if biome_fx != null and is_instance_valid(biome_fx):
			biome_fx.restore_enemies()
			biome_fx.queue_free()
		biome_fx = null
		biome_ice = null
		if player != null and is_instance_valid(player):
			player.friction_mult = 1.0


func _physics_process(_delta: float) -> void:
	if not _built or player == null:
		return
	var frame := Engine.get_physics_frames()
	# m2-t4 A2 冰面：帧级进出接缝（进域 ×0.25 / 出域回 1.0，只写玩家）。
	if biome_ice != null and player != null:
		biome_ice.tick(player)
	_tick_hazards(frame)
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


# ================================================================ 装配

## 接管构建体 + 玩家：房间实体/走廊闸/玩家落位 start/交互/相机/HUD。
## 玩家无父节点时收养为子节点（宿主也可自行挂树后传入）。
func setup(build: Dictionary, p_player: Player, p_buffs: BuffManager = null) -> void:
	if _built:
		push_error("FloorScene.setup: already built")
		return
	_built = true
	player = p_player
	buffs_manager = p_buffs
	flow.setup(build)
	_combat_rng = RunState.stream(RunState.SALT_PROJECTILE)
	_rig_rng = RunState.stream(RunState.SALT_RIG)
	_loot_rng = RunState.stream(RunState.SALT_EVENT)   # M2-T1：事件/房间抽取独立盐（不再共享掉落流）
	_facility_rng = RngSvc.stream(floor_idx, "facility")
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
	_bullet_layer = Node2D.new()
	_bullet_layer.name = "BulletVisuals"
	_bullet_layer.z_index = 20
	add_child(_bullet_layer)
	flow.room_event.connect(_on_flow_room_event)
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


## 房内几何：地板贴图 + 四面墙（模板门方向留 32px 门洞）。M0 _solid 习语。
## m1-t28：地块按生物群系选 floor_*/wall_*（16x16 无缝平铺）；缺图回落原染色。
func _build_floor_and_walls(room: FloorRoom, w: float, h: float, doors: Array) -> void:
	var interior := Rect2(WALL_T, WALL_T, w - WALL_T * 2.0, h - WALL_T * 2.0)
	var tiles := _biome_tiles(room.type)
	var floor_vis: Node2D = ArtLookup.make_tiled(ArtLookup.tile_path(tiles[0]), interior)
	if floor_vis == null:
		floor_vis = Polygon2D.new()
		(floor_vis as Polygon2D).polygon = _rect_poly(interior)
		(floor_vis as Polygon2D).color = _biome_tint(room.type)
	floor_vis.z_index = -10
	room.add_child(floor_vis)
	var cx := _door_axis(w)
	var cy := _door_axis(h)
	for seg in _wall_segments(Vector2(w, h), cx, cy, doors):
		_solid_child(room, seg, tiles[1])


## 生物群系地块：start=庭院 / boss=Boss 房 / 其余=洞穴。
func _biome_tiles(room_type: String) -> Array[String]:
	match room_type:
		"start":
			return ["floor_garden", "wall_garden"]
		"boss":
			return ["floor_boss", "wall_boss"]
	return ["floor_cave", "wall_cave"]


## 原染色表（贴图缺图回落用，M0 数值保留）。
func _biome_tint(room_type: String) -> Color:
	match room_type:
		"start":
			return Color(0.14, 0.16, 0.15)
		"boss":
			return Color(0.2, 0.13, 0.16)
	return Color(0.17, 0.15, 0.2)


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
	var wall_tile := _biome_tiles(room.type)[1]
	for d: String in doors:
		if used.has(d):
			continue
		match d:
			"N":
				_solid_child(room, Rect2(cx - PASSAGE_HALF, 0, PASSAGE_HALF * 2.0, WALL_T), wall_tile)
			"S":
				_solid_child(room, Rect2(cx - PASSAGE_HALF, h - WALL_T, PASSAGE_HALF * 2.0, WALL_T), wall_tile)
			"W":
				_solid_child(room, Rect2(0, cy - PASSAGE_HALF, WALL_T, PASSAGE_HALF * 2.0), wall_tile)
			"E":
				_solid_child(room, Rect2(w - WALL_T, cy - PASSAGE_HALF, WALL_T, PASSAGE_HALF * 2.0), wall_tile)


## 模板陈设：pillar/crate 实体阻挡，bush 仅视觉。m1-t28：prop_*.png 接线。
## m2-t7：pillar（含 A2 晶柱形态，GDD §10「晶柱折射敌方激光」）登记
## refraction_pillars 组——EnemyLaser 折射判定按组取世界坐标。
func _build_props(room: FloorRoom, tpl: Dictionary) -> void:
	for p: Dictionary in tpl.get("props", []):
		var center := _tile_center(p.get("grid", [0, 0]))
		match String(p.get("kind", "")):
			"pillar":
				var body := _solid_child(room, Rect2(center - Vector2(8, 8), Vector2(16, 16)), "prop_pillar")
				body.add_to_group(EnemyLaser.PILLAR_GROUP)
			"crate":
				_solid_child(room, Rect2(center - Vector2(8, 8), Vector2(16, 16)), "prop_crate")
			"bush":
				_vis_child(room, Rect2(center - Vector2(8, 8), Vector2(16, 16)), "prop_bush")


## m2-t7/m2-t10 危险地块实例化（模板 hazards 字段驱动，GDD §10）：vine=藤蔓减速带（A1）
## / spikes=周期地刺（A2）/ rock=滚石发射口（A1）/ magma=岩浆 DOT 池（A3）/
## geyser=间歇喷口（A3）。未知 kind 告警跳过（fail-soft；GameDB hazards 白名单
## = vine + magma/geyser，spikes/rock 行待 A2/A3 模板卡扩展 schema 落库）。
func _build_hazards(room: FloorRoom, tpl: Dictionary) -> void:
	for hz: Dictionary in tpl.get("hazards", []):
		var grid: Array = hz.get("grid", [0, 0])
		var local := _tile_center(grid)
		var world := room.position + local
		match String(hz.get("kind", "")):
			"vine":
				_build_vine(room, local, float(hz.get("radius", 24)))
			"spikes":
				_build_spikes(room, grid, world)
			"rock":
				_build_rock(room, hz, world)
			"magma":
				_build_magma(room, local, float(hz.get("radius", 24)))
			"geyser":
				_build_geyser(room, grid, world)
			_:
				push_warning("FloorScene: unknown hazard kind '%s'" % String(hz.get("kind", "")))


## 藤蔓减速带（A1）：VineZone 域（世界坐标外接方）+ 视觉（m1-t28 贴图回落原染色圆）。
func _build_vine(room: FloorRoom, local: Vector2, radius: float) -> void:
	if hazard_vines == null:
		hazard_vines = VineZone.new()
	hazard_vines.add_zone(Rect2(local - Vector2(radius, radius) + room.position,
		Vector2(radius * 2.0, radius * 2.0)))
	# m1-t28：藤蔓减速带贴 hazard_vine.png（32x32 半透明整圆缩放至 2r）。
	var vis: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path("hazard_vine"))
	if vis == null:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 12:
			pts.append(Vector2.from_angle(TAU * i / 12.0) * radius)
		poly.polygon = pts
		poly.color = Color(0.3, 0.55, 0.3, 0.18)
		vis = poly
		vis.position = local
	else:
		(vis as Sprite2D).scale = Vector2.ONE * (radius * 2.0 / (vis as Sprite2D).texture.get_size().x)
		vis.position = local
		vis.modulate = Color(1, 1, 1, 0.9)
	vis.z_index = -5
	room.add_child(vis)


## 周期地刺（A2）：一瓦片判定域；错峰偏移 = 网格确定性散列（同层多簇不同步）。
func _build_spikes(room: FloorRoom, grid: Array, world: Vector2) -> void:
	var zone := Rect2(world - Vector2(SPIKE_TILE_PX / 2.0, SPIKE_TILE_PX / 2.0),
		Vector2(SPIKE_TILE_PX, SPIKE_TILE_PX))
	var stagger := (int(grid[0]) * 7 + int(grid[1]) * 13) % HazardSpikes.cycle_ticks()
	var s := HazardSpikes.new()
	s.setup(zone, stagger)
	_spikes.append(s)
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-SPIKE_TILE_PX / 2.0, -SPIKE_TILE_PX / 2.0,
		SPIKE_TILE_PX, SPIKE_TILE_PX))
	vis.position = world - room.position
	vis.z_index = -4
	vis.visible = false
	room.add_child(vis)
	_spikes_vis.append(vis)


## 滚石发射口（A1）：出生瓦片 + 发射侧方向 + 房内域（撞墙即消）；预警线视觉
## 沿滚动方向整条车道，石体视觉 ROLL 相位随位镜像。
func _build_rock(room: FloorRoom, hz: Dictionary, world: Vector2) -> void:
	var dir_v: Vector2 = ROCK_SIDE_DIRS.get(String(hz.get("side", "W")), Vector2.RIGHT)
	var interior := _room_interior(room)
	var r := RollingRock.new()
	r.setup(world, dir_v, interior, int(hz.get("interval_ticks", 0)))
	_rocks.append(r)
	var local := world - room.position
	var lane_len: float = interior.size.x if absf(dir_v.x) > 0.5 else interior.size.y
	var perp := Vector2(-dir_v.y, dir_v.x) * 2.0
	var lane_end := local + dir_v * lane_len
	var line := Polygon2D.new()
	line.polygon = PackedVector2Array([local - perp, local + perp,
		lane_end + perp, lane_end - perp])
	line.color = Color(1.0, 0.75, 0.2, 0.25)
	line.z_index = -4
	line.visible = false
	room.add_child(line)
	_rock_line_vis.append(line)
	var rock := Polygon2D.new()
	rock.polygon = _rect_poly(Rect2(-RollingRock.ROCK_RADIUS_PX, -RollingRock.ROCK_RADIUS_PX,
		RollingRock.ROCK_RADIUS_PX * 2.0, RollingRock.ROCK_RADIUS_PX * 2.0))
	rock.color = Color(0.45, 0.4, 0.38)
	rock.z_index = 4
	rock.visible = false
	room.add_child(rock)
	_rock_vis.append(rock)


## m2-t10 岩浆 DOT 池（A3）：HazardMagma 域（世界坐标外接方，同 vine 几何）+ 视觉
## （hazard_lava.png 贴图缩放至 2r，缺图回落暖色半透明圆）。DOT 结算在 _tick_hazards。
func _build_magma(room: FloorRoom, local: Vector2, radius: float) -> void:
	if hazard_magma == null:
		hazard_magma = HazardMagma.new()
	hazard_magma.add_zone(Rect2(local - Vector2(radius, radius) + room.position,
		Vector2(radius * 2.0, radius * 2.0)))
	var vis: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path("hazard_lava"))
	if vis == null:
		var poly := Polygon2D.new()
		poly.polygon = _circle_poly(radius)
		poly.color = MAGMA_POOL_COLOR
		vis = poly
		vis.position = local
	else:
		(vis as Sprite2D).scale = Vector2.ONE * (radius * 2.0 / (vis as Sprite2D).texture.get_size().x)
		vis.position = local
	vis.z_index = -5
	room.add_child(vis)


## m2-t10 间歇喷口（A3）：一瓦片判定域；错峰偏移 = 网格确定性散列（同地刺习语）。
func _build_geyser(room: FloorRoom, grid: Array, world: Vector2) -> void:
	var zone := Rect2(world - Vector2(GEYSER_TILE_PX / 2.0, GEYSER_TILE_PX / 2.0),
		Vector2(GEYSER_TILE_PX, GEYSER_TILE_PX))
	var stagger := (int(grid[0]) * 7 + int(grid[1]) * 13) % HazardMagma.MagmaGeyser.CYCLE_TICKS
	var g := HazardMagma.MagmaGeyser.new()
	g.setup(zone, stagger)
	_geysers.append(g)
	var vis := Polygon2D.new()
	vis.polygon = _rect_poly(Rect2(-GEYSER_TILE_PX / 2.0, -GEYSER_TILE_PX / 2.0,
		GEYSER_TILE_PX, GEYSER_TILE_PX))
	vis.position = world - room.position
	vis.z_index = -4
	vis.visible = false
	room.add_child(vis)
	_geyser_vis.append(vis)


## m2-t10 火雨驱动入口（Boss/事件驱动契约，T19 熔核暴君/T24 星陨先知消费）：
## 注入一个世界坐标红圈落点（预警 48t 后恰一拍落点结算，见 HazardMagma.FireRain）。
## 视觉 = 楼层级红圈节点（Boss 驱动不限于单房），落点后随 strike 过期自除。
func schedule_fire_rain(world_pos: Vector2) -> void:
	hazard_fire_rain.schedule(world_pos)
	var circle := Polygon2D.new()
	circle.polygon = _circle_poly(HazardMagma.FireRain.RADIUS_PX)
	circle.position = world_pos
	circle.z_index = 6
	circle.modulate = FIRE_RAIN_WARN_COLOR
	add_child(circle)
	_fire_rain_vis.append(circle)


## 房间可玩内域（世界坐标）——滚石撞墙判定 / 敌方激光飞行界共用几何。
func _room_interior(room: FloorRoom) -> Rect2:
	return Rect2(room.outer.position + Vector2(WALL_T, WALL_T),
		room.outer.size - Vector2(WALL_T * 2.0, WALL_T * 2.0))


## m2-t7/m2-t10 危险地块帧驱动：藤蔓减速（进出接缝）+ 地刺相位推进/伤害 + 滚石生命
## 周期/伤害 + 岩浆 DOT 脉冲（抗火 meta 减半）+ 喷口相位推进/伤害 + 火雨落点推进/伤害。
## 伤害经 player.take_hit（玩家 0.8s 受击无敌帧天然节流同源连击；岩浆脉冲 60t > 48t
## 不被节流）；伤害 ctx 仅命中拍构建（事件频率）；视觉仅翻可见性/引用常量色。
func _tick_hazards(frame: int) -> void:
	if hazard_vines != null:
		hazard_vines.tick(player, frame)
	var player_pos := player.global_position
	if hazard_magma != null:
		var magma_dmg := hazard_magma.tick(player)
		if magma_dmg > 0:
			player.take_hit({
				"amount": magma_dmg, "is_crit": false,
				"element": Elements.Id.FIRE, "from": player_pos,
				"source_type": "hazard", "source_id": "magma",
				"source_name": "岩浆", "attack_name": "岩浆灼烧",
			})
	for i in _spikes.size():
		var s := _spikes[i]
		s.advance()
		var vis: CanvasItem = _spikes_vis[i]
		match s.phase():
			HazardSpikes.Phase.WARN:
				vis.visible = true
				vis.modulate = SPIKE_WARN_COLOR
			HazardSpikes.Phase.OUT:
				vis.visible = true
				vis.modulate = SPIKE_OUT_COLOR
			_:
				vis.visible = false
		if s.damage_at(player_pos) > 0:
			player.take_hit({
				"amount": HazardSpikes.DAMAGE, "is_crit": false,
				"element": Elements.Id.NONE, "from": player_pos,
				"source_type": "hazard", "source_id": "spikes",
				"source_name": "地刺", "attack_name": "地刺穿刺",
			})
	for i in _rocks.size():
		var r := _rocks[i]
		r.advance()
		_rock_line_vis[i].visible = r.warning_active()
		var rock_vis: CanvasItem = _rock_vis[i]
		rock_vis.visible = r.rock_active()
		if r.rock_active():
			rock_vis.global_position = r.rock_pos
		if r.damage_at(player_pos) > 0:
			player.take_hit({
				"amount": RollingRock.DAMAGE, "is_crit": false,
				"element": Elements.Id.NONE, "from": r.rock_pos,
				"source_type": "hazard", "source_id": "rock",
				"source_name": "滚石", "attack_name": "滚石碾压",
			})
	for i in _geysers.size():
		var g := _geysers[i]
		g.advance()
		var gvis: CanvasItem = _geyser_vis[i]
		match g.phase():
			HazardMagma.MagmaGeyser.Phase.WARN:
				gvis.visible = true
				gvis.modulate = GEYSER_WARN_COLOR
			HazardMagma.MagmaGeyser.Phase.ERUPT:
				gvis.visible = true
				gvis.modulate = GEYSER_ERUPT_COLOR
			_:
				gvis.visible = false
		if g.damage_at(player_pos) > 0:
			player.take_hit({
				"amount": HazardMagma.MagmaGeyser.DAMAGE, "is_crit": false,
				"element": Elements.Id.FIRE, "from": g.zone.get_center(),
				"source_type": "hazard", "source_id": "geyser",
				"source_name": "间歇喷口", "attack_name": "间歇喷口喷发",
			})
	# 火雨：常驻组件逐帧推进；落点拍命中半径即伤，下一拍 strike 过期（视觉 FIFO 对齐）。
	hazard_fire_rain.tick()
	while _fire_rain_vis.size() > hazard_fire_rain.strikes.size():
		(_fire_rain_vis.pop_front() as CanvasItem).queue_free()
	for i in _fire_rain_vis.size():
		var fvis: CanvasItem = _fire_rain_vis[i]
		fvis.modulate = FIRE_RAIN_BOOM_COLOR \
			if bool(hazard_fire_rain.strikes[i]["boom"]) else FIRE_RAIN_WARN_COLOR
	var rain_dmg := hazard_fire_rain.striking_at(player_pos)
	if rain_dmg > 0:
		player.take_hit({
			"amount": rain_dmg, "is_crit": false,
			"element": Elements.Id.FIRE, "from": player_pos,
			"source_type": "hazard", "source_id": "fire_rain",
			"source_name": "火雨", "attack_name": "天降火雨",
		})


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
	# m1-t28：走廊地板贴 corridor_floor.png（缺图回落原染色）。
	var corridor_floor: Node2D = ArtLookup.make_tiled(ArtLookup.tile_path("corridor_floor"),
		floor_rect)
	if corridor_floor == null:
		corridor_floor = Polygon2D.new()
		(corridor_floor as Polygon2D).polygon = _rect_poly(floor_rect)
		(corridor_floor as Polygon2D).color = Color(0.13, 0.12, 0.16)
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
	# m1-t28：走廊闸门体贴 door_closed.png（覆盖 gate_size + 2px 压边）。
	var panel: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path("door_closed"))
	if panel == null:
		var poly := Polygon2D.new()
		poly.color = Color(0.62, 0.4, 0.22)
		poly.polygon = _rect_poly(Rect2(
			-(gate_size.x + 2.0) / 2.0, -(gate_size.y + 2.0) / 2.0,
			gate_size.x + 2.0, gate_size.y + 2.0))
		panel = poly
	else:
		(panel as Sprite2D).scale = (gate_size + Vector2(2, 2)) / 16.0
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
	ArtLookup.apply_player_sprite(player)      # m1-t28：英雄 meta 接缝 → hero_<id>.png
	var rig := player.get_node("WeaponRig") as WeaponRig
	rig.bind_run_state(RunState)
	if rig.current().is_empty():
		rig.equip("laohuoji")
	if buffs_manager != null:
		buffs_manager.apply_to_player(player)
		buffs_manager.apply_to_rig(rig)
	if not player.has_node("Driver"):
		var driver := Node.new()
		driver.name = "Driver"
		driver.set_script(DRIVER_SCRIPT)
		player.add_child(driver)
	# m1-hygiene：T24 完整战斗 HUD 是楼层/层间共用的唯一常驻 HUD。
	var hud := HUD.new()
	hud.player = player
	add_child(hud)


## 进房接线（M0 t12 契约）：rig/melee/player.combat 注入当前房 combat 流并登记玩家体。
func _wire_room_combat(room: FloorRoom) -> void:
	if room.combat == null:
		return
	if _registered_combat != null and is_instance_valid(_registered_combat):
		_registered_combat.unregister_body(player)
	var rig := player.get_node("WeaponRig") as WeaponRig
	var melee := player.get_node("Melee") as Melee
	rig.combat = room.combat
	rig.combat_rng = _rig_rng
	melee.combat = room.combat
	melee.combat_rng = _rig_rng
	melee.rig = rig
	player.combat = room.combat
	# 精灵像可能在商店房（无 CombatSystem）生成；进入后续战斗房时必须切到
	# 当前房间的弹池，否则它会一直查看 null/旧房间，生产路径无法挡弹。
	for child in player.get_children():
		if child is ShieldSpirit:
			(child as ShieldSpirit).combat = room.combat
	# m1-t27：英雄暴击基础值注入（HeroApplier meta 接缝 "crit_base" 的房间层读出，
	# T11 披露的接线位；无 meta（裸玩家测试路径）保持 CombatSystem 默认值）。
	if player.has_meta("crit_base"):
		room.combat.crit_chance = player.effective_crit_chance(float(player.get_meta("crit_base")))
	room.combat.crit_multiplier = player.effective_crit_multiplier()
	room.combat.status_rate_mult = player.effective_status_rate_multiplier()
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


func _spawn_enemy(room: FloorRoom, id: String, world_pos: Vector2,
		row_override: Dictionary = {}, counts_for_wave := true) -> EnemyBase:
	var is_guest := GUEST_SPECS.has(id)
	var row: Dictionary = row_override.duplicate(true) if not row_override.is_empty() \
		else (guest_row(id) if is_guest else GameDB.get_enemy(id))
	if row.is_empty():
		push_error("FloorScene: unknown enemy '%s'" % id)
		if counts_for_wave:
			room.room_flow.notify_killed(id, Engine.get_physics_frames())
		return null
	# T12/T13 缝：guest_spawner 注入时嘉宾生成让位宿主（返回 EnemyBase 即接管）。
	if row_override.is_empty() and is_guest and guest_spawner.is_valid():
		var spawned: Variant = guest_spawner.call(room.type, room.room_id, row.duplicate(), world_pos)
		if spawned is EnemyBase:
			var g := spawned as EnemyBase
			g.position = world_pos - room.position   # 房间子节点：世界刷点 → 房间局部
			room.add_child(g)
			g.setup(row)
			_register_enemy(room, g, row, counts_for_wave)
			return g
		# 缝返回非 EnemyBase：落回占位路径（响亮告警，集成卡自行排查）
		push_warning("FloorScene: guest_spawner returned type %d for '%s' — placeholder fallback"
			% [typeof(spawned), id])
	# m1-t27：默认真实嘉宾（数据行替换占位；真实行缺失时落回占位路径）
	if row_override.is_empty() and is_guest and use_real_guests:
		var real_guest := _spawn_real_guest(room, id, world_pos, counts_for_wave)
		if real_guest != null:
			return real_guest
	var e := EnemyFactory.spawn(row, room, world_pos - room.position)
	if e == null:
		push_error("FloorScene: cannot construct enemy '%s'" % id)
		if counts_for_wave:
			room.room_flow.notify_killed(id, Engine.get_physics_frames())
		return null
	_dress_enemy(e, row)
	_register_enemy(room, e, row, counts_for_wave)
	return e


## 敌人递归生产接线：所有波次体、Boss/王虫召唤体、分裂子体都走同一注册路径。
## callback 统一 3 参（row_id/world_pos/row_override），room 作为 bind 尾参注入；
## 召唤体明确 counts_for_wave=false，死亡只做战斗/遥测清理，绝不消费原始波次数。
func _register_enemy(room: FloorRoom, e: EnemyBase, row: Dictionary, counts_for_wave: bool) -> void:
	e.combat = room.combat
	e.player_ref = room.player_proxy
	e.combat_bounds = Rect2(room.outer.position + Vector2(WALL_T, WALL_T),
		room.outer.size - Vector2(WALL_T * 2.0, WALL_T * 2.0))
	e.counts_for_wave = counts_for_wave
	e.spawn_callback = Callable(self, "_spawn_summoned_enemy").bind(room)
	if not e.is_in_group("enemies"):
		e.add_to_group("enemies")
	room.combat.register_body(e, e.combat_faction())
	room.enemies.append(e)
	_spawn_frames[e.get_instance_id()] = Engine.get_physics_frames()
	e.died.connect(_on_enemy_died.bind(room))


func _spawn_summoned_enemy(row_id: String, world_pos: Vector2, row_override: Dictionary,
		room: FloorRoom) -> Node:
	if room == null or not is_instance_valid(room) or room.combat == null:
		return null
	var radius := float(row_override.get("radius", GameDB.get_enemy(row_id).get("radius", 6.0)))
	var interior := Rect2(room.outer.position + Vector2(WALL_T + radius, WALL_T + radius),
		room.outer.size - Vector2((WALL_T + radius) * 2.0, (WALL_T + radius) * 2.0))
	var legal_pos := Vector2(
		clampf(world_pos.x, interior.position.x, interior.end.x),
		clampf(world_pos.y, interior.position.y, interior.end.y))
	return _spawn_enemy(room, row_id, legal_pos, row_override, false)


## m1-t27 真实嘉宾生成：波次标记 id（GUEST_SPECS 键）→ REAL_GUEST_ROWS 数据行。
## 词缀（elite_affixes）与 boss_script 均由 EnemyBase.setup 数据驱动生效；
## guest_kind 沿用占位标记（染成嘉宾色），行内记 wave_id 供 kill 路由回译波次
## （RoomFlow._alive 以波次标记 id 计数，见 _on_enemy_killed）。
## 返回 false = 真实行缺失（调用方落回占位路径）。
func _spawn_real_guest(room: FloorRoom, wave_id: String, world_pos: Vector2,
		counts_for_wave: bool) -> EnemyBase:
	var real_id := String(REAL_GUEST_ROWS.get(wave_id, ""))
	if real_id.is_empty():
		return null
	var real_row: Dictionary = GameDB.get_enemy(real_id).duplicate()
	if real_row.is_empty():
		push_warning("FloorScene: real guest row '%s' missing — placeholder fallback" % real_id)
		return null
	real_row["guest_kind"] = String((GUEST_SPECS[wave_id] as Dictionary)["kind"])
	real_row["wave_id"] = wave_id
	var e := EnemyFactory.spawn(real_row, room, world_pos - room.position)
	if e == null:
		push_error("FloorScene: cannot construct real guest '%s'" % real_id)
		return null
	_dress_enemy(e, real_row)
	_register_enemy(room, e, real_row, counts_for_wave)
	return e


## 敌人外观（M0 习语 → m1-t28 表驱动贴图）：生成像素图按行 id；占位嘉宾按
## guest_kind 变体回落；缺图回落色块并告警。body_scale 由 EnemyBase.setup 整节点放大。
func _dress_enemy(e: EnemyBase, row: Dictionary) -> void:
	var radius := float(row.get("radius", 6.0))
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	e.add_child(cs)
	if not ArtLookup.dress_enemy_sprite(e, row):
		push_warning("FloorScene: no enemy sprite for '%s' — color block fallback"
			% String(row.get("id", "?")))
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


## 精确实例死亡路由：EnemyBase.died 直接携带死亡体，消除相同 id 多实例时全局 id
## 匹配错体的歧义。召唤体照常移出 CombatSystem/房间跟踪并记遥测，但 counts_for_wave=false
## 时不通知 RoomFlow，也不触发嘉宾掉落；原始波次计数与召唤生态严格隔离。
func _on_enemy_died(e: EnemyBase, room: FloorRoom) -> void:
	if not _built:
		return
	if room == null or not is_instance_valid(room) or not room.enemies.has(e):
		return
	# 局聚合按“真实敌人死亡”记账，而不是按波次消费记账。召唤/分裂体虽以
	# counts_for_wave=false 与原始波次生态隔离，仍是玩家本局的一次真实击杀；
	# room.enemies.has(e) 是重复 died 回调的幂等门，确保每个实例只计一次。
	RunState.add_kill()
	var frame := Engine.get_physics_frames()
	var enemy_id := String(e.row.get("id", ""))
	var notify_id := String(e.row.get("wave_id", enemy_id))
	var killed_row: Dictionary = (e.row as Dictionary).duplicate(true)
	var death_pos := e.global_position
	var ttk := frame - int(_spawn_frames.get(e.get_instance_id(), frame))
	Fx.on_enemy_killed(death_pos)
	Telemetry.log_row(["kill", frame, enemy_id, ttk],
		RoomCombat.kill_source(e.row, _current_weapon_id()))
	room.enemies.erase(e)
	_spawn_frames.erase(e.get_instance_id())
	if not e.counts_for_wave:
		return
	room.room_flow.notify_killed(notify_id, frame)
	_spawn_guest_drops(room, killed_row, death_pos)
	if room.room_flow.cleared and not room.cleared_emitted:
		flow.notify_room_cleared(room.room_id)
		_emit_room_clear(room)
		refresh_gates()
		if room.type == "boss":
			_flow_suspended = true           # 层间中转接管玩家（防进房检测抢人）
			boss_defeated.emit(room.room_id)


## m1-t27 嘉宾死亡掉落（行内 drops 契约："weapon"=随机武器掉落台（ShopLogic.roll_weapon_id，
## loot 盐流确定性），"hearts2"=2 红心）。掉落台复用宝箱的 _build_loot_station（E 拾取换手）。
func _spawn_guest_drops(room: FloorRoom, row: Dictionary, world_pos: Vector2) -> void:
	var drops := String(row.get("drops", ""))
	if drops.is_empty():
		return
	if drops.contains("weapon"):
		var exclude: Array[String] = []
		var wid := ShopLogic.roll_weapon_id(_loot_rng, floor_idx, exclude)
		if wid.is_empty():
			wid = _roll_weapon(_roll_rarity())   # 池枯哨兵兜底（全名录 roll）
		Telemetry.log_row(["loot", Engine.get_physics_frames(), wid, "guest_drop"])
		room.add_child(_build_loot_station(room, world_pos - room.position, wid))
	if drops.contains("hearts2"):
		for i in 2:
			_spawn_pickup(room, "heart", world_pos + _scatter(71 + i))


## m1-t18 kill 行来源取值：玩家当前武器 id（rig 未接线 → ""）；boss 判定复用 RoomCombat.kill_source。
func _current_weapon_id() -> String:
	if player != null and player.weapon_rig != null:
		var w := player.weapon_rig.current()
		if not w.is_empty():
			return String(w.get("id", ""))
	return ""


## 清房：遥测（每房清房用时）+ room_cleared 广播 + 奖励爆发（战斗房）。
func _emit_room_clear(room: FloorRoom) -> void:
	# 所有清房副作用共用同一幂等门；回溯重进或重复死亡通知不得重复统计、
	# 遥测、广播或奖励。start 在 FloorFlow.setup 时已清，仅作为出生/回程房，
	# 不属于玩家实际完成的房间数。
	if room == null or room.cleared_emitted:
		return
	room.cleared_emitted = true
	if room.type != "start":
		RunState.add_room_cleared()
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
	p.on_collect = func() -> void:
		room.coins += 1
		RunState.add_coins(1)                # m1-t27：局内金币记账（商店钱包鸭子接缝）
	room.add_child(p)


func _detect_room_enter() -> void:
	if player == null or _flow_suspended:
		return
	for id in _rooms:
		var room: FloorRoom = _rooms[id]
		if int(id) != flow.current_room and room.outer.has_point(player.global_position):
			enter_room(int(id))
			return


func _on_flow_room_event(room_type: String, room_id: int) -> void:
	room_event.emit(room_type, room_id)
	_open_facility(room_type, _rooms.get(room_id))


## m1-t27 设施接线（room_event 首进恰一次）：shop=真商店（RunState 钱包 + 当层货单 +
## 副手回收回调）；event=EventRoom 进房即开事件面板（全屏弹层，Esc=拒绝）。
## treasure 走 _place_guests 既有宝箱；elite/miniboss/boss 为嘉宾战斗房无设施。
func _open_facility(room_type: String, room: FloorRoom) -> void:
	if room == null or room.facility_built:
		return
	match room_type:
		"shop":
			room.facility_built = true
			_build_shop(room, room.outer.get_center() - room.position)
		"event":
			room.facility_built = true
			_build_event(room)


## 商店设施（T14 Shop 契约）：货单 ShopLogic.roll_stock（RunState loot 盐流，当层确定），
## 钱包 = RunState（coins/spend_coins/add_coins 鸭子接缝），回收回调 = 副手丢弃。
func _build_shop(room: FloorRoom, local_pos: Vector2) -> void:
	var shop := SHOP_SCENE.instantiate() as Shop
	shop.name = "Shop"
	shop.position = local_pos + Vector2(-72, 0)
	var exclude: Array[String] = []
	shop.black = _facility_rng.randf() < BLACK_SHOP_CHANCE
	shop.stock = ShopLogic.roll_stock(_loot_rng, floor_idx, exclude, shop.black)
	shop.wallet = RunState
	shop.drop_weapon = _drop_offhand
	room.add_child(shop)
	var drink := DrinkMachine.new()
	drink.name = "DrinkMachine"
	drink.position = local_pos + Vector2(72, 0)
	drink.configure(_drink_state, RunState, _facility_rng)
	room.add_child(drink)
	# 四种雕像全部位于正常 A1 商店房，可步行到达；同类状态由局根共享字典门控。
	var offsets := [Vector2(-72, -56), Vector2(-24, -56), Vector2(24, -56), Vector2(72, -56)]
	for i in Shrine.KINDS.size():
		var shrine := Shrine.new().setup(Shrine.KINDS[i], _used_shrine_kinds)
		shrine.name = "Shrine_%s" % Shrine.KINDS[i]
		shrine.position = local_pos + offsets[i]
		shrine.wallet = RunState
		shrine.rng = _facility_rng
		shrine.combat = player.combat
		room.add_child(shrine)


## 商店回收回调（Shop.drop_weapon 契约）：丢弃副手（非当前槽）→ 返回武器信息
## （空 {} = 无副手，Shop 拒绝入账）。
func _drop_offhand(p: Node2D) -> Dictionary:
	var pl := p as Player
	if pl == null or pl.weapon_rig == null or pl.weapon_rig.slots.size() < 2:
		return {}
	var rig := pl.weapon_rig
	var alt := (rig.slot + 1) % 2
	var w: Dictionary = rig.slots[alt]
	if w.is_empty():
		return {}
	rig.clear_slot(alt)
	return {"id": String(w.get("id", "")), "name": String(w.get("name", "")),
		"rarity": String(w.get("rarity", "common"))}


## 事件设施（T19 EventRoom 契约）：进房即 4 选 1 开面板（每房一次由 flow 单发 +
## EventRoom._used 双守卫）；抽取确定性 = RunState loot 盐流。
func _build_event(room: FloorRoom) -> void:
	var ev := EventRoom.new()
	ev.setup(player, _facility_rng)
	ev.apply_effect = _apply_event_drink_effect
	room.add_child(ev)                        # _ready 建面板 UI
	ev.open_random_event()


## 神秘商人复用真实饮料消费者。事件表的百分比用分数表示；翻滚项的 value
## 是秒数（0.05s），必须经固定 60Hz TimeConst 换算为 3 tick，不能按总 CD 百分比取整。
func _apply_event_drink_effect(effect: String, value: float, p: Node2D) -> void:
	var drink_value := value * 100.0 if effect in ["move_speed_pct", "status_rate_pct"] else value
	if effect == "roll_cd_pct":
		effect = "roll_cd_ticks"
		drink_value = TimeConst.ticks(value)
	DrinkMachine._apply_drink(effect, drink_value, p as Player)


## 首次进入时放置：treasure 宝箱 / shop·event 桩（设施已接时让位，防双交互物）
## （elite/miniboss/boss 嘉宾走战斗波次）。
func _place_guests(room: FloorRoom) -> void:
	if room.guests_placed:
		return
	room.guests_placed = true
	var center := room.outer.get_center() - room.position
	match room.type:
		"treasure":
			_build_chest(room, center)
		"shop":
			if not room.facility_built:
				_build_stub(room, center, "商店（C线未接入）")
		"event":
			if not room.facility_built:
				_build_stub(room, center, "事件（C线未接入）")


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
		var panel: Node2D = g["panel"]
		if open:
			DoorAnim.open(panel, true)
		else:
			DoorAnim.close(panel)
		# m1-t28：规则锁（boss 未解 / 双未清）= door_locked 红门，战斗封门 = door_closed 棕门。
		var tile := "door_locked" if (not open and _rule_locked(int(g["a"]), int(g["b"]))) \
			else "door_closed"
		var t := ArtLookup.tex(ArtLookup.tile_path(tile))
		if t != null and panel is Sprite2D:
			(panel as Sprite2D).texture = t


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

## 宝箱：开箱 → 权重 roll 武器（loot 遥测）→ 掉落台出现在箱位（再按 E 换手）。
## m1-t28：箱体贴 chest_closed.png（开箱后 modulate 压暗表示已开启）。
func _build_chest(room: FloorRoom, local_pos: Vector2) -> void:
	var chest := FixtureInteractable.new()
	chest.name = "Chest"
	chest.position = local_pos
	chest.action_label = "打开宝箱"
	chest.add_child(_fixture_body())
	var vis: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path("chest_closed"))
	if vis == null:
		vis = Polygon2D.new()
		(vis as Polygon2D).color = Color(0.75, 0.58, 0.2)
		(vis as Polygon2D).polygon = _rect_poly(Rect2(-9, -7, 18, 14))
	else:
		vis.name = "Sprite"
	chest.add_child(vis)
	chest.on_interact_cb = func(p: Node2D) -> void:
		chest.enabled = false                       # 一次性
		vis.modulate = Color(0.55, 0.5, 0.4)
		var rarity := _roll_rarity()
		var wid := _roll_weapon(rarity)
		Telemetry.log_row(["loot", Engine.get_physics_frames(), wid, rarity])
		# 开箱只揭示掉落；玩家必须再按 E 与武器台交互才会换枪。
		# 这既保留开箱前双槽，也防同一武器被开箱与武器台各装备一次。
		room.add_child(_build_loot_station(room, local_pos + Vector2(0, 22), wid))
	room.add_child(chest)


## 武器掉落台：宝箱→掉落的落地形态，再按 E 换手（一次性）。m1-t28：weapon_crate.png。
func _build_loot_station(room: FloorRoom, local_pos: Vector2,
		weapon_id: String) -> FixtureInteractable:
	var station := FixtureInteractable.new()
	station.name = "LootStation"
	station.position = local_pos
	station.set_meta("weapon_id", weapon_id)          # 测试/UI 可读，且每个台子自持掉落 id
	var weapon_row := GameDB.get_weapon(weapon_id)
	station.action_label = "拾取武器：%s" % String(weapon_row.get("name", weapon_id))
	station.add_child(_fixture_body())
	var sv: Node2D = ArtLookup.make_sprite(ArtLookup.pickup_texture_path("weapon_crate"))
	if sv == null:
		sv = Polygon2D.new()
		(sv as Polygon2D).color = Color(0.3, 0.6, 0.75)
		(sv as Polygon2D).polygon = _rect_poly(Rect2(-6, -6, 12, 12))
	station.add_child(sv)
	station.on_interact_cb = func(p: Node2D) -> void:
		station.enabled = false
		var pl := p as Player
		if pl != null:
			(pl.get_node("WeaponRig") as WeaponRig).equip(weapon_id)
	return station


func _build_stub(room: FloorRoom, local_pos: Vector2, label: String) -> void:
	var stub := FixtureInteractable.new()
	stub.position = local_pos
	stub.action_label = label
	stub.add_child(_fixture_body())
	var vis: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path("prop_crate"))
	if vis == null:
		vis = Polygon2D.new()
		(vis as Polygon2D).color = Color(0.35, 0.35, 0.45)
		(vis as Polygon2D).polygon = _rect_poly(Rect2(-8, -8, 16, 16))
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
	return ids[_loot_rng.randi_range(0, ids.size() - 1)]


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


## 表现层弹幕镜像（M0 习语）：当前房 combat 池 → 共享 Sprite2D 逐帧同步。
## m1-t28：弹丸贴图按阵营/元素换装（bullet_player/bullet_enemy/elem_*）。
func _sync_bullet_visuals() -> void:
	var active: Array = []
	var room: FloorRoom = _rooms.get(flow.current_room)
	if room != null and room.combat != null:
		active = room.combat.pool.active
	if _bullet_layer == null:
		return
	while _bullet_sprites.size() < active.size() and _bullet_sprites.size() < BULLET_VISUAL_CAP:
		var vis := Sprite2D.new()
		vis.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vis.scale = Vector2.ONE * BULLET_VISUAL_SCALE
		_bullet_layer.add_child(vis)
		_bullet_sprites.append(vis)
	for i in _bullet_sprites.size():
		var vis := _bullet_sprites[i]
		if i < active.size():
			var p: Projectile = active[i]
			vis.visible = true
			vis.position = p.position
			vis.texture = ArtLookup.bullet_texture(p.faction, p.element)   # M2-T1 备忘缓存
			vis.modulate = p.modulate
		else:
			vis.visible = false


# ================================================================ 查询面（测试/HUD）

func room_count() -> int:
	return _rooms.size()


# ---- m2-t7 危险地块查询面（测试/HUD；越界返回 null 不崩） ----

func hazard_spikes_count() -> int:
	return _spikes.size()


func hazard_rock_count() -> int:
	return _rocks.size()


func hazard_spike(i: int) -> HazardSpikes:
	return _spikes[i] if i >= 0 and i < _spikes.size() else null


func hazard_rock(i: int) -> RollingRock:
	return _rocks[i] if i >= 0 and i < _rocks.size() else null


# ---- m2-t10 A3 岩浆系查询面（测试/HUD；越界返回 null 不崩） ----

func hazard_geyser_count() -> int:
	return _geysers.size()


func hazard_geyser(i: int) -> HazardMagma.MagmaGeyser:
	return _geysers[i] if i >= 0 and i < _geysers.size() else null


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
	var facility_built := false               # m1-t27：设施已接（shop/event 真设施占位）
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


## 实体阻挡块：tile_name 非空时贴 tiles/<名>.png（16x16 无缝平铺），缺图回落原染色。
## m2-t7 返回实体（pillar 陈设需登记 refraction_pillars 组——敌方激光折射判定源）。
func _solid_child(room: FloorRoom, rect: Rect2, tile_name: String = "") -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	room.add_child(body)
	var vis: Node2D = null
	if not tile_name.is_empty():
		vis = ArtLookup.make_tiled(ArtLookup.tile_path(tile_name),
			Rect2(-rect.size / 2.0, rect.size))
	if vis == null:
		var poly := Polygon2D.new()
		poly.polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
		poly.color = Color(0.36, 0.3, 0.28) if tile_name.is_empty() else _prop_fallback_color(tile_name)
		vis = poly
	body.add_child(vis)
	return body


func _solid_world(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# m1-t28：走廊墙体贴 wall_cave.png（16x16 无缝平铺）。
	var vis: Node2D = ArtLookup.make_tiled(ArtLookup.tile_path("wall_cave"),
		Rect2(-rect.size / 2.0, rect.size))
	if vis == null:
		var poly := Polygon2D.new()
		poly.polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
		poly.color = Color(0.36, 0.3, 0.28)
		vis = poly
	body.add_child(vis)


## 纯视觉块：tile_name 非空时贴 tiles/<名>.png（居中，原尺寸）。
func _vis_child(room: FloorRoom, rect: Rect2, tile_name: String = "") -> void:
	var vis: Node2D = null
	if not tile_name.is_empty():
		vis = ArtLookup.make_sprite(ArtLookup.tile_path(tile_name))
	if vis == null:
		vis = Polygon2D.new()
		(vis as Polygon2D).polygon = _rect_poly(Rect2(-rect.size.x / 2.0, -rect.size.y / 2.0, rect.size.x, rect.size.y))
		(vis as Polygon2D).color = _prop_fallback_color(tile_name)
	vis.position = rect.get_center()
	room.add_child(vis)


## 陈设缺图回落的 M0 染色（与原色块数值一致）。
func _prop_fallback_color(tile_name: String) -> Color:
	match tile_name:
		"prop_pillar":
			return Color(0.5, 0.48, 0.52)
		"prop_crate":
			return Color(0.55, 0.4, 0.24)
		"prop_bush":
			return Color(0.25, 0.42, 0.24)
	return Color(0.36, 0.3, 0.28)


func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])


## 12 边圆多边形（岩浆池/火雨红圈缺图回落与红圈视觉用；构建时一次性分配）。
func _circle_poly(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(Vector2.from_angle(TAU * i / 12.0) * radius)
	return pts


func _opp(dir: String) -> String:
	match dir:
		"N":
			return "S"
		"S":
			return "N"
		"E":
			return "W"
	return "E"
