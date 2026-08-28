class_name RoomCombat
extends Node2D
## 战斗房（m0-t12）：EntryZone 触发 → 锁门 → 按 data/rooms/m0_combat.json 逐波刷怪
## （怪全灭进下一波）→ 清完开门 + 奖励爆发 + EventBus.room_cleared。
## 波次状态机在 RoomFlow（纯逻辑，无头可测）；本文件是场景表现层与接线。
##
## 接线契约（t12）：每个刷出的敌人注入 combat / player_ref / status（setup 内惰性挂载）；
## 玩家注入 weapon_rig.combat/combat_rng + melee.combat/combat_rng/rig（共用一条 combat 流）。
## 世界布局：战斗房为世界 x∈[488,960] 的右半幅（训练房在左半幅并入时复用本场景）。

const CFG_PATH := "res://data/rooms/m0_combat.json"
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const DRIVER_SCRIPT := preload("res://core/rooms/player_driver.gd")
const GAME_CAMERA := preload("res://fx/game_camera.gd")
const DEBUG_HUD := preload("res://ui/debug_hud.gd")
const PICKUP := preload("res://core/rooms/pickup.gd")

const ROOM_RECT := Rect2(488, 0, 472, 270)          # 含墙外框
const INTERIOR := Rect2(488, 16, 456, 238)          # 可玩内域
const ROOM_CENTER := Vector2(716, 135)
const ENTRY_GATE_POS := Vector2(480, 136)           # 走廊闸门（锁门实体）
const ENTRY_ZONE_RECT := Rect2(490, 16, 28, 238)    # 入口感应区
const MIN_SPAWN_DOOR_PX := 64.0
const MIN_SPAWN_PLAYER_PX := 120.0
const DOOR_POSITIONS: Array[Vector2] = [
	Vector2(480, 136), Vector2(716, 8), Vector2(952, 135), Vector2(716, 262),
]
const MARKERS: Array[Vector2] = [
	Vector2(580, 70), Vector2(580, 200), Vector2(650, 135),
	Vector2(720, 135), Vector2(860, 70), Vector2(860, 200),
]
const ARCHETYPE_COLORS := {
	"shooter": Color(0.5, 0.6, 0.85), "suicide": Color(0.4, 0.8, 0.35),
	"charger": Color(0.7, 0.4, 0.8), "orbiter": Color(0.45, 0.42, 0.55),
	"dummy": Color(0.65, 0.5, 0.35),
}
const PLAYER_BULLET_COLOR := Color(1.0, 0.9, 0.35)
const ENEMY_BULLET_COLOR := Color(1.0, 0.35, 0.3)
const BULLET_VISUAL_CAP := 500

## 训练房并入时置 false：复用外部玩家/相机/HUD，不自带操控
@export var spawn_player := true

var room_id := "m0_combat"
var flow := RoomFlow.new()
var combat: CombatSystem
var player: Player
var player_proxy: PlayerProxy              # EnemyBase.player_ref 适配（需 brain_pos/take_hit）
var entry_frame := -1
var _cfg: Dictionary = {}
var _enemies: Array[EnemyBase] = []
var _spawn_frames: Dictionary = {}          # instance_id -> 刷出帧（ttk）
var _door_panels: Array[Polygon2D] = []
var _entry_gate: CollisionShape2D
var _entered := false
var _spawned_wave := -1                    # 已刷的最高波索引（波推进由物理帧检测补刷）
var _coins_collected := 0
var _bullet_layer: Node2D
var _bullet_sprites: Array[Polygon2D] = []

func _ready() -> void:
	if _cfg.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	load_config(_cfg)
	_pool_root_build()
	_build_walls()
	_build_doors()
	_build_entry_zone()
	_adopt_or_spawn_player()
	EventBus.enemy_killed.connect(_on_enemy_killed)

## brief 接口：外部覆盖房间配置（默认读 data/rooms/m0_combat.json）。
func load_config(cfg: Dictionary) -> void:
	_cfg = cfg
	room_id = String(_cfg.get("id", "m0_combat"))
	flow.setup(_cfg)

# ---- 刷怪点过滤（纯逻辑，单测覆盖：距门 ≥64px、距玩家 ≥120px） ----

static func filter_spawn_points(points: Array[Vector2], doors: Array[Vector2], player_pos: Vector2,
		min_door_px := MIN_SPAWN_DOOR_PX, min_player_px := MIN_SPAWN_PLAYER_PX) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pt in points:
		var ok := pt.distance_to(player_pos) >= min_player_px
		if ok:
			for d in doors:
				if pt.distance_to(d) < min_door_px:
					ok = false
					break
		if ok:
			out.append(pt)
	return out

func valid_spawn_points() -> Array[Vector2]:
	var player_pos := player.global_position if player != null else Vector2(500, 135)
	var out := filter_spawn_points(MARKERS, DOOR_POSITIONS, player_pos)
	return out if not out.is_empty() else MARKERS   # 兜底：极端位置也要有怪可刷

# ---- 每帧 ----

func _physics_process(_delta: float) -> void:
	# AI 拍驱动：物理层 brain_tick 由房间推进（EnemyBrain 组件属后续里程碑）
	var frame := Engine.get_physics_frames()
	for e in _enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.brain_tick(frame)
	# 波推进：前一波全灭后 flow 已进下一波，此处补刷（含后续任意波数）
	if flow.locked and not flow.cleared and flow.wave_index() > _spawned_wave:
		_spawn_wave()

func _process(_delta: float) -> void:
	_sync_bullet_visuals()

# ---- 流程 ----

func _on_entry_zone_entered(body: Node2D) -> void:
	if body is Player:
		_do_entry.call_deferred(body)      # Area 信号处于物理 flush 中：刷怪须出栈后做

func _do_entry(_body: Node2D) -> void:
	if _entered or flow.cleared:
		return
	_entered = true
	entry_frame = Engine.get_physics_frames()
	flow.on_entered(entry_frame)
	_set_doors_closed(true)
	_spawn_wave()
	Telemetry.log_row(["room_enter", entry_frame, room_id])

func _spawn_wave() -> void:
	_spawned_wave = flow.wave_index()
	var points := valid_spawn_points()
	var i := 0
	for id in flow.current_wave_ids():
		_spawn_enemy(String(id), points[i % points.size()])
		i += 1

func _spawn_enemy(id: String, pos: Vector2) -> void:
	var row := GameDB.get_enemy(id)
	if row.is_empty():
		push_error("RoomCombat: unknown enemy '%s'" % id)
		flow.notify_killed(id, Engine.get_physics_frames())   # 坏行不计波次
		return
	var e := EnemyBase.new()
	e.position = pos
	add_child(e)
	e.setup(row)                               # 原型换装 + status 惰性挂载（t12 接线）
	e.combat = combat
	e.player_ref = player_proxy                # 替身：EnemyBase 契约需 brain_pos/take_hit
	e.add_to_group("enemies")
	_dress_enemy(e, row)
	combat.register_body(e, e.combat_faction())
	_enemies.append(e)
	_spawn_frames[e.get_instance_id()] = Engine.get_physics_frames()

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
	vis.color = ARCHETYPE_COLORS.get(String(row.get("archetype", "")), Color.WHITE)
	e.add_child(vis)

func _on_enemy_killed(enemy_id: String) -> void:
	var frame := Engine.get_physics_frames()
	for e in _enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == enemy_id:
			var ttk := frame - int(_spawn_frames.get(e.get_instance_id(), frame))
			Fx.on_enemy_killed(e.global_position)
			Telemetry.log_row(["kill", frame, enemy_id, ttk])
			_enemies.erase(e)
			break
	flow.notify_killed(enemy_id, frame)
	if flow.cleared:
		_on_cleared(frame)

func _on_cleared(frame: int) -> void:
	_set_doors_closed(false)
	_spawn_rewards()
	EventBus.room_cleared.emit(room_id)
	Telemetry.log_row(["room_clear", frame, frame - entry_frame])

func _spawn_rewards() -> void:
	for i in int(flow.rewards.get("coins", 0)):
		_spawn_pickup("coin", ROOM_CENTER + _scatter(i))
	for i in int(flow.rewards.get("energy_orbs", 0)):
		_spawn_pickup("energy", ROOM_CENTER + _scatter(37 + i))
	if int(flow.rewards.get("hearts", 0)) > 0:
		_spawn_pickup("heart", ROOM_CENTER)

## 确定性散布（黄金角），不引入随机。
func _scatter(i: int) -> Vector2:
	return Vector2.from_angle(float(i) * 2.399963) * (6.0 + 5.0 * sqrt(float(i % 17)))

func _spawn_pickup(kind: String, pos: Vector2) -> void:
	var p: Pickup = PICKUP.new()
	p.kind = kind
	p.position = pos
	p.on_collect = func() -> void: _coins_collected += 1
	add_child(p)

func coins_collected() -> int:
	return _coins_collected

# ---- 门（表现层 Tween + 走廊实体闸） ----

func _set_doors_closed(closed: bool) -> void:
	for i in _door_panels.size():
		var panel := _door_panels[i]
		var target := DOOR_POSITIONS[i] if closed else DOOR_POSITIONS[i] + Vector2(0, -46)
		var tw := panel.create_tween()
		tw.tween_property(panel, "position", target, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _entry_gate != null:
		_entry_gate.set_deferred("disabled", not closed)

# ---- 玩家接线（t12 契约：rig/melee 注入 combat + 共用 combat 流） ----

func _adopt_or_spawn_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Player
	if player == null and spawn_player:
		player = PLAYER_SCENE.instantiate() as Player
		player.position = Vector2(560, 135)
		add_child(player)
		player.add_to_group("player")
	if player == null:
		push_error("RoomCombat: no player to wire")
		return
	var rig := player.get_node("WeaponRig") as WeaponRig
	var melee := player.get_node("Melee") as Melee
	var combat_rng := RngSvc.stream(0, "combat")
	rig.combat = combat
	rig.combat_rng = combat_rng
	melee.combat = combat
	melee.combat_rng = combat_rng
	melee.rig = rig
	combat.register_body(player, player.combat_faction())
	player_proxy = PlayerProxy.new()
	player_proxy.name = "PlayerProxy"
	player_proxy.player = player
	add_child(player_proxy)
	if spawn_player:
		_attach_driver()
		_attach_camera()
		_attach_hud()

func _attach_driver() -> void:
	if player.has_node("Driver"):
		return
	var driver := Node.new()
	driver.name = "Driver"
	driver.set_script(DRIVER_SCRIPT)
	player.add_child(driver)

func _attach_camera() -> void:
	var cam: Camera2D = GAME_CAMERA.new()
	cam.set("target", player)
	cam.limit_left = int(ROOM_RECT.position.x)
	cam.limit_top = 0
	cam.limit_right = int(ROOM_RECT.end.x)
	cam.limit_bottom = int(ROOM_RECT.end.y)
	add_child(cam)

func _attach_hud() -> void:
	var hud: CanvasLayer = DEBUG_HUD.new()
	hud.set("player", player)
	hud.set("combat", combat)
	hud.set("room", self)
	add_child(hud)

# ---- 构建 ----

func _pool_root_build() -> void:
	var pool_root := Node2D.new()
	pool_root.name = "ProjectilePoolRoot"
	add_child(pool_root)
	combat = CombatSystem.new(pool_root, RngSvc.stream(0, "combat"))
	add_child(combat)
	_bullet_layer = Node2D.new()
	_bullet_layer.name = "BulletVisuals"
	_bullet_layer.z_index = 20
	add_child(_bullet_layer)

func _build_walls() -> void:
	_solid(Rect2(944, 0, 16, 270))          # 东墙
	_solid(Rect2(488, 0, 472, 16))          # 北墙
	_solid(Rect2(488, 254, 472, 16))        # 南墙
	_floor_tint()

func _solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var vis := Polygon2D.new()
	var h := rect.size / 2.0
	vis.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	vis.position = rect.get_center()
	vis.color = Color(0.36, 0.3, 0.28)
	add_child(vis)

func _floor_tint() -> void:
	var floor_vis := Polygon2D.new()
	floor_vis.polygon = PackedVector2Array([
		INTERIOR.position, Vector2(INTERIOR.end.x, INTERIOR.position.y),
		INTERIOR.end, Vector2(INTERIOR.position.x, INTERIOR.end.y),
	])
	floor_vis.color = Color(0.17, 0.15, 0.2)
	floor_vis.z_index = -10
	add_child(floor_vis)

func _build_doors() -> void:
	for i in DOOR_POSITIONS.size():
		var panel := Polygon2D.new()
		panel.name = "Door%d" % i
		panel.polygon = PackedVector2Array([
			Vector2(-8, -18), Vector2(8, -18), Vector2(8, 18), Vector2(-8, 18),
		])
		panel.color = Color(0.62, 0.4, 0.22)
		panel.position = DOOR_POSITIONS[i] + Vector2(0, -46)   # 初始敞开（藏进门体）
		panel.z_index = 5
		add_child(panel)
		_door_panels.append(panel)
	var gate := StaticBody2D.new()
	gate.position = ENTRY_GATE_POS
	_entry_gate = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 32)
	_entry_gate.shape = shape
	_entry_gate.disabled = true               # 初始开：可自由进房
	gate.add_child(_entry_gate)
	add_child(gate)

func _build_entry_zone() -> void:
	var zone := Area2D.new()
	zone.name = "EntryZone"
	zone.position = ENTRY_ZONE_RECT.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = ENTRY_ZONE_RECT.size
	cs.shape = shape
	zone.add_child(cs)
	zone.body_entered.connect(_on_entry_zone_entered)
	add_child(zone)

# ---- 弹幕可视化（表现层镜像：Projectile 本体无外观，逐帧同步共享多边形） ----

func _sync_bullet_visuals() -> void:
	if combat == null:
		return
	var active := combat.pool.active
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
			vis.modulate = base * p.modulate   # 反弹弹带 (1,1,0.4) 染色（setup 已重置为 WHITE）
		else:
			vis.visible = false
