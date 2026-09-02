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
	"dummy": Color(0.65, 0.5, 0.35), "mushroom_spore": Color(0.58, 0.82, 0.46),
}
const BULLET_VISUAL_CAP := 500
## m1-t28 美术接线（ArtLookup 表驱动）：地块/门/敌人/弹丸纹理统一 res://art/generated。
const TILE_FLOOR := "floor_cave"
const TILE_WALL := "wall_cave"
const TILE_DOOR := "door_closed"
const BULLET_VISUAL_SCALE := 0.75      # 8x8 弹底图 ≈ 原 5px 方块
## m2-t21 敌人 2 帧动画：art/generated/enemies/<id>_sheet.png（2 列=idle+walk × 1 行）。
## 帧节拍与玩家 T17 ANIM_WALK_TICKS 同为 8t/帧；缺表敌种（精英/小Boss/Boss/嘉宾）回落单帧。
const ENEMY_SHEET_FMT := "res://art/generated/enemies/%s_sheet.png"
const ENEMY_ANIM_TICKS := 8           # 移动中 (物理帧/8) % 2 两帧交替
const ENEMY_ANIM_MOVE_EPS := 0.25     # 位移²阈值（<0.5px/拍 视为静止，覆盖贴墙抖动）

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
var _door_panels: Array[Sprite2D] = []
var _entry_gate: CollisionShape2D
var _entered := false
var _spawned_wave := -1                    # 已刷的最高波索引（波推进由物理帧检测补刷）
var _coins_collected := 0
var _bullet_layer: Node2D
var _bullet_sprites: Array[Sprite2D] = []
## m2-t21 敌人 2 帧动画热路径状态（持久字典 + int 实例键：零字符串/零字典新建）。
var _anim_sprites: Dictionary = {}     # instance_id -> Sprite2D（仅帧表化敌种）
var _anim_prev: Dictionary = {}        # instance_id -> 上一拍 brain_pos

## 帧表一次性解析缓存（id -> Texture2D / null 负缓存，同 T17 player._anim_sheet_cache）。
static var _enemy_sheet_cache: Dictionary = {}

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

## brief 接口：外部覆盖房间配置（默认读 data/rooms/m0_combat.json）。
func load_config(cfg: Dictionary) -> void:
	_cfg = cfg
	room_id = String(_cfg.get("id", "m0_combat"))
	flow.setup(_cfg)

# ---- 刷怪点过滤（纯逻辑，单测覆盖：距门 ≥64px、距玩家 ≥120px） ----

const SPAWN_RELAX_STEP_PX := 8.0   # fix1：全过滤时双阈值同步渐进放宽的步长（px/档）

static func filter_spawn_points(points: Array[Vector2], doors: Array[Vector2], player_pos: Vector2,
		min_door_px := MIN_SPAWN_DOOR_PX, min_player_px := MIN_SPAWN_PLAYER_PX) -> Array[Vector2]:
	var out := _filter_by_thresholds(points, doors, player_pos, min_door_px, min_player_px)
	if not out.is_empty() or points.is_empty():
		return out
	# fix1 重设计（m3-b1 报告 69/100 停滞根因之一）：全点位被过滤时旧实现「响亮式兜底」
	# 原样返回全量点位（丢弃 ≥64px 距门 / ≥120px 距玩家不变量），怪可刷在玩家贴脸位
	# 甚至门体上——玩家贴住刷点蹲守即触发。新策略：
	# ① 双阈值同步按 SPAWN_RELAX_STEP_PX/档渐进放宽，取「首个非空档」= 最小必要放宽量
	#    （保不变量本意：能不放宽就不放宽）；
	# ② 命中非空档后按「离玩家距离降序」输出（同距按输入序稳定排序）——波次刷怪依次
	#    取点，首怪必落离玩家最远的合法点（保进度、保公平）；
	# ③ 放宽至 0 阈值必有非空档（点位非空时）→ 任何点位组合都有怪可刷，房间必可清。
	var steps := int(ceil(maxf(min_door_px, min_player_px) / SPAWN_RELAX_STEP_PX))
	for i in range(1, steps + 1):
		var relax := float(i) * SPAWN_RELAX_STEP_PX
		var door_px := maxf(min_door_px - relax, 0.0)
		var player_px := maxf(min_player_px - relax, 0.0)
		var relaxed := _filter_by_thresholds(points, doors, player_pos, door_px, player_px)
		if relaxed.is_empty():
			continue
		_sort_by_player_distance_desc(relaxed, player_pos)
		push_warning("RoomCombat.filter_spawn_points: all points filtered at full thresholds "
				+ "— progressive relax %.0fpx (door>=%.0f, player>=%.0f), %d point(s), farthest-first"
				% [relax, door_px, player_px, relaxed.size()])
		return relaxed
	return points   # 防御性不可达：末档阈值为 0 时必有非空档

## 阈值过滤本体（fix1 前语义：距玩家 ≥min_player_px 且距每扇门 ≥min_door_px）。
static func _filter_by_thresholds(points: Array[Vector2], doors: Array[Vector2],
		player_pos: Vector2, min_door_px: float, min_player_px: float) -> Array[Vector2]:
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

## 按离玩家距离降序原地排序（同距保持传入次序，稳定可复现）。
static func _sort_by_player_distance_desc(points: Array[Vector2], player_pos: Vector2) -> void:
	var order: Array = []
	for i in points.size():
		order.append({"pt": points[i], "i": i})
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := (a["pt"] as Vector2).distance_squared_to(player_pos)
		var db := (b["pt"] as Vector2).distance_squared_to(player_pos)
		if absf(da - db) > 0.0001:
			return da > db
		return int(a["i"]) < int(b["i"]))
	for i in order.size():
		points[i] = order[i]["pt"]

func valid_spawn_points() -> Array[Vector2]:
	var player_pos := player.global_position if player != null else Vector2(500, 135)
	return filter_spawn_points(MARKERS, DOOR_POSITIONS, player_pos)

# ---- 每帧 ----

func _physics_process(_delta: float) -> void:
	# AI 拍驱动：物理层 brain_tick 由房间推进（EnemyBrain 组件属后续里程碑）
	var frame := Engine.get_physics_frames()
	for e in _enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.brain_tick(frame)
			_tick_enemy_anim(e, frame)
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

func _spawn_enemy(id: String, pos: Vector2, row_override: Dictionary = {},
		counts_for_wave := true) -> EnemyBase:
	var row := row_override.duplicate(true) if not row_override.is_empty() else GameDB.get_enemy(id)
	if row.is_empty():
		push_error("RoomCombat: unknown enemy '%s'" % id)
		if counts_for_wave:
			flow.notify_killed(id, Engine.get_physics_frames())   # 坏行不计波次
		return null
	var e := EnemyFactory.spawn(row, self, pos)
	if e == null:
		push_error("RoomCombat: cannot construct enemy '%s'" % id)
		if counts_for_wave:
			flow.notify_killed(id, Engine.get_physics_frames())
		return null
	_dress_enemy(e, row)
	_register_enemy(e, counts_for_wave)
	return e


func _register_enemy(e: EnemyBase, counts_for_wave: bool) -> void:
	e.combat = combat
	e.player_ref = player_proxy                # 替身：EnemyBase 契约需 brain_pos/take_hit
	e.combat_bounds = INTERIOR
	e.counts_for_wave = counts_for_wave
	e.spawn_callback = Callable(self, "_spawn_summoned_enemy")
	if not e.is_in_group("enemies"):
		e.add_to_group("enemies")
	combat.register_body(e, e.combat_faction())
	_enemies.append(e)
	_spawn_frames[e.get_instance_id()] = Engine.get_physics_frames()
	e.died.connect(_on_enemy_died)


func _spawn_summoned_enemy(row_id: String, world_pos: Vector2,
		row_override: Dictionary) -> Node:
	var radius := float(row_override.get("radius", GameDB.get_enemy(row_id).get("radius", 6.0)))
	var legal := Rect2(INTERIOR.position + Vector2.ONE * radius,
		INTERIOR.size - Vector2.ONE * radius * 2.0)
	var clamped := Vector2(clampf(world_pos.x, legal.position.x, legal.end.x),
		clampf(world_pos.y, legal.position.y, legal.end.y))
	return _spawn_enemy(row_id, clamped, row_override, false)

func _dress_enemy(e: EnemyBase, row: Dictionary) -> void:
	var radius := float(row.get("radius", 6.0))
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	e.add_child(cs)
	# m1-t28：生成像素图按行 id 接线（guest 占位行按 guest_kind 变体回落）；
	# 缺图回落 ARCHETYPE_COLORS 色块并告警留痕。body_scale 由 EnemyBase.setup
	# 整节点 ×1.25，视觉随之放大。
	if not ArtLookup.dress_enemy_sprite(e, row):
		push_warning("RoomCombat: no enemy sprite for '%s' — color block fallback"
			% String(row.get("id", "?")))
		var vis := Polygon2D.new()
		vis.name = "Sprite"                        # Fx 白闪按名寻址
		var r := maxf(radius, 5.0)
		vis.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r),
		])
		vis.color = ARCHETYPE_COLORS.get(String(row.get("archetype", "")), Color.WHITE)
		e.add_child(vis)
	_apply_enemy_anim_sheet(e, row)

# ---- m2-t21 敌人 2 帧动画（帧表驱动，纯整数运算零分配；参照 T17 player 模式） ----

## 2 帧步态纯函数：静止恒列 0（idle）；移动中以 8t/帧在列 0/1 交替（同玩家节拍）。
static func enemy_anim_frame(moving: bool, frame: int) -> int:
	if not moving:
		return 0
	return int(floor(float(frame) / ENEMY_ANIM_TICKS)) % 2

## 帧表查询（一次性解析 + 负缓存；ArtLookup.tex 缺图告警一次后缓存 null）。
static func enemy_sheet(id: String) -> Texture2D:
	if not _enemy_sheet_cache.has(id):
		_enemy_sheet_cache[id] = ArtLookup.tex(ENEMY_SHEET_FMT % id)
	return _enemy_sheet_cache[id]

## 有帧表的常规敌换装 2 列网格：帧尺寸 = 表宽/2（缩放按帧尺寸重算，保持原 footprint）；
## 缺表（精英/小Boss/Boss/嘉宾）保留 dress_enemy_sprite 的单帧外观不动。
func _apply_enemy_anim_sheet(e: EnemyBase, row: Dictionary) -> void:
	var spr := e.get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return
	var sheet := enemy_sheet(String(row.get("id", "")))
	if sheet == null:
		return
	var frame_px := Vector2(sheet.get_width() / 2.0, float(sheet.get_height()))
	var radius := maxf(float(row.get("radius", 6.0)), 5.0)
	var s := (radius * 2.0) / maxf(frame_px.x, frame_px.y)
	spr.texture = sheet
	spr.hframes = 2
	spr.vframes = 1
	spr.frame = 0
	spr.scale = Vector2(s, s)
	_anim_sprites[e.get_instance_id()] = spr
	_anim_prev[e.get_instance_id()] = e.brain_pos

## 动画拍（零分配热路径：int 键查持久字典、位移²阈值判移动、帧变化才写 Sprite）。
func _tick_enemy_anim(e: EnemyBase, frame: int) -> void:
	var id := e.get_instance_id()
	if not _anim_sprites.has(id):
		return
	var pos := e.brain_pos
	var prev: Vector2 = _anim_prev.get(id, pos)
	_anim_prev[id] = pos
	var spr := _anim_sprites[id] as Sprite2D
	if spr == null or not is_instance_valid(spr):
		return
	var idx := enemy_anim_frame(pos.distance_squared_to(prev) > ENEMY_ANIM_MOVE_EPS, frame)
	if spr.frame != idx:
		spr.frame = idx

func _on_enemy_died(e: EnemyBase) -> void:
	_anim_sprites.erase(e.get_instance_id())   # m2-t21：实例 id 可复用，死亡即清动画跟踪（先于注册守卫）
	_anim_prev.erase(e.get_instance_id())
	if not _enemies.has(e):
		return
	var frame := Engine.get_physics_frames()
	var enemy_id := String(e.row.get("id", ""))
	var ttk := frame - int(_spawn_frames.get(e.get_instance_id(), frame))
	Fx.on_enemy_killed(e.global_position)
	Telemetry.log_row(["kill", frame, enemy_id, ttk], kill_source(e.row, _current_weapon_id()))
	_enemies.erase(e)
	_spawn_frames.erase(e.get_instance_id())
	if not e.counts_for_wave:
		return
	flow.notify_killed(String(e.row.get("wave_id", enemy_id)), frame)
	if flow.cleared:
		_on_cleared(frame)

## m1-t18 kill 行来源（纯静态可测）：boss 行（boss_script 派生 / boss 嘉宾）→ "boss"，
## 否则取玩家当前武器 id（rig 未接线 → ""）。contact/dot 死因区分需 enemy_base 侧
## 死因管线（本卡文件所有权外）——v1.5 先以武器 id 归因，交接披露。
static func kill_source(row: Dictionary, weapon_id: String) -> String:
	if String(row.get("boss_script", "")) != "" or String(row.get("guest_kind", "")) == "boss":
		return "boss"
	return weapon_id

func _current_weapon_id() -> String:
	if player != null and player.weapon_rig != null:
		var w := player.weapon_rig.current()
		if not w.is_empty():
			return String(w.get("id", ""))
	return ""

func _on_cleared(frame: int) -> void:
	_set_doors_closed(false)
	_spawn_rewards()
	EventBus.room_cleared.emit(room_id)
	Telemetry.log_row(["room_clear", frame, frame - entry_frame])

# ---- m4-c3 红心感应（heart_sense，掉落侧奖励区） ----
const SALT_HEART_SENSE := "heart_sense"   # 局内掷签独立盐（RunState.stream 任意盐串先例，同 player.SALT_KILL_ENERGY）
var _heart_rng: RandomNumberGenerator = null   # 惰性缓存盐流（fresh-per-call 会退化成恒同掷签）

func _spawn_rewards() -> void:
	for i in int(flow.rewards.get("coins", 0)):
		_spawn_pickup("coin", ROOM_CENTER + _scatter(i))
	for i in int(flow.rewards.get("energy_orbs", 0)):
		_spawn_pickup("energy", ROOM_CENTER + _scatter(37 + i))
	if int(flow.rewards.get("hearts", 0)) > 0:
		_spawn_pickup("heart", ROOM_CENTER)
	_heart_sense_bonus()

## 红心感应（buff_heart_sense_pct，player meta）：房奖励红心掉率 roll——pct > 0 时
## 每次清房奖励以 pct 概率追加 1 心（基线 1 心 → 期望 1+pct，desc「红心掉率 +50%」
## 即期望 +50%）。pct ≤ 0 不掷签不建流（无增益零漂移：m0_loop_smoke 35 pickups
## 断言不回归）；追加落点沿 _scatter 黄金角习语（确定性）。仅玩家身体带该 meta
## （BuffManager PLAYER_META_KEYS 落点）；掷签走独立盐流（kill_energy 先例）。
func _heart_sense_bonus() -> void:
	var pct := 0.0
	if player != null and player.has_meta("buff_heart_sense_pct"):
		pct = float(player.get_meta("buff_heart_sense_pct"))
	if pct <= 0.0:
		return
	if _heart_rng == null:
		_heart_rng = RunState.stream(SALT_HEART_SENSE)
	var won := _heart_rng.randf() < clampf(pct, 0.0, 1.0)
	Telemetry.log_row(["heart_sense_roll", Engine.get_physics_frames(), 1 if won else 0])
	if won:
		_spawn_pickup("heart", ROOM_CENTER + _scatter(53))

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

# ---- 门（m1-t18：统一 DoorAnim 0.18s 滑入/滑出 + 走廊实体闸） ----

func _set_doors_closed(closed: bool) -> void:
	for panel in _door_panels:
		if closed:
			DoorAnim.close(panel)
		else:
			DoorAnim.open(panel)               # M0 习语：滑出收进墙体后仍可见
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
	ArtLookup.apply_player_sprite(player)      # m1-t28：英雄 meta 接缝 → hero_<id>.png
	var melee := player.get_node("Melee") as Melee
	var combat_rng := RunState.stream(RunState.SALT_RIG)   # m1-t15：rig/melee 走 "rig" 盐（与 CombatSystem 的 "proj_crit" 盐分溪，避免散布/暴击共用序列）
	rig.combat = combat
	rig.combat_rng = combat_rng
	melee.combat = combat
	melee.combat_rng = combat_rng
	melee.rig = rig
	player.combat = combat                 # m1-t5：影袭经 player.combat 写必暴窗（同 rig 契约）
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
	combat = CombatSystem.new(pool_root, RunState.stream(RunState.SALT_PROJECTILE))   # m1-t15：同上分盐
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
	# m1-t28：墙体贴 wall_cave.png（16x16 无缝平铺，顶部 1px 亮色内嵌）；缺图回落色块。
	var vis: Node2D = ArtLookup.make_tiled(ArtLookup.tile_path(TILE_WALL),
		Rect2(-rect.size / 2.0, rect.size))
	if vis == null:
		var poly := Polygon2D.new()
		var h := rect.size / 2.0
		poly.polygon = PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
		poly.color = Color(0.36, 0.3, 0.28)
		vis = poly
	body.add_child(vis)

func _floor_tint() -> void:
	# m1-t28：地板贴 floor_cave.png（16x16 无缝平铺）。
	var floor_vis: Node2D = ArtLookup.make_tiled(ArtLookup.tile_path(TILE_FLOOR), INTERIOR)
	if floor_vis == null:
		floor_vis = Polygon2D.new()
		(floor_vis as Polygon2D).polygon = PackedVector2Array([
			INTERIOR.position, Vector2(INTERIOR.end.x, INTERIOR.position.y),
			INTERIOR.end, Vector2(INTERIOR.position.x, INTERIOR.end.y),
		])
		(floor_vis as Polygon2D).color = Color(0.17, 0.15, 0.2)
	floor_vis.z_index = -10
	add_child(floor_vis)

func _build_doors() -> void:
	for i in DOOR_POSITIONS.size():
		# m1-t28：门体贴 door_closed.png（16x36 盖板 = 16px 墙厚 + 32px 门洞）；
		# 开门仍走 DoorAnim 滑出收进墙体（M0 习语）。
		var panel: Node2D = ArtLookup.make_sprite(ArtLookup.tile_path(TILE_DOOR))
		if panel == null:
			var poly := Polygon2D.new()
			poly.color = Color(0.62, 0.4, 0.22)
			poly.polygon = PackedVector2Array([
				Vector2(-8, -18), Vector2(8, -18), Vector2(8, 18), Vector2(-8, 18),
			])
			panel = poly
		else:
			(panel as Sprite2D).scale = Vector2(1.0, 36.0 / 16.0)
		panel.name = "Door%d" % i
		panel.position = DOOR_POSITIONS[i] + DoorAnim.PARK_OFFSET   # 初始敞开（藏进门体）
		panel.z_index = 5
		add_child(panel)
		DoorAnim.install(panel, DOOR_POSITIONS[i])
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

# ---- 弹幕可视化（表现层镜像：Projectile 本体无外观，逐帧同步共享 Sprite2D） ----
## m1-t28：弹丸贴图按阵营/元素换装（bullet_player/bullet_enemy/elem_*），
## p.modulate 保留反弹染色语义；laser 谱系 M1 无弹形（laser_seg.png 预留）。
## m4-a1：必暴窗内玩家弹换暴击专用帧（金描边/强化发光）——forced_crit_until 为
## CombatSystem 命中结算的既有暴击判定状态，本处只读镜像（零 RNG 消费零判定影响，
## 暴击 roll 仍是全游戏唯一随机乘区）；元素弹保持元素身份（ArtLookup 内 element 优先）。

func _sync_bullet_visuals() -> void:
	if combat == null:
		return
	var active := combat.pool.active
	var crit_window := Engine.get_physics_frames() < combat.forced_crit_until   # m4-a1 只读镜像
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
			vis.texture = ArtLookup.bullet_texture(p.faction, p.element,
				crit_window and p.faction == Projectile.Faction.PLAYER)   # M2-T1 备忘缓存（m4-a1 加 crit 位）
			vis.modulate = p.modulate          # 反弹弹带 (1,1,0.4) 染色（setup 已重置为 WHITE）
		else:
			vis.visible = false
