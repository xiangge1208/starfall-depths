extends Node2D
## 训练房（m0-t12，主场景）：假人×3（可开关回血、无碰撞可穿过）+ 武器架 6 台（E 键交互）+
## Debug HUD + debug 弹幕雨作弊键。右半幅并入 RoomCombat 实例——玩家穿走廊进房 → 锁门/波次/奖励。
## 世界布局：训练房 x∈[0,488]（左半幅），战斗房 x∈[488,960]（RoomCombat 自建）。

const DRIVER_SCRIPT := preload("res://core/rooms/player_driver.gd")
const GAME_CAMERA := preload("res://fx/game_camera.gd")
const DEBUG_HUD := preload("res://ui/debug_hud.gd")

const TRAIN_INTERIOR := Rect2(16, 16, 456, 238)
const WORLD_RECT := Rect2(0, 0, 960, 270)
# 假人行不经 GameDB 表（属训练房专用靶材，不入敌人图鉴）：hp 99999（brief： effectively 不可杀）
const DUMMY_ROW := {
	"id": "dummy", "name": "木桩", "archetype": "dummy",
	"hp": 99999, "radius": 6.0, "contact_dmg": 0, "speed": 0,
}
const DUMMY_POINTS: Array[Vector2] = [Vector2(180, 70), Vector2(180, 135), Vector2(180, 200)]
const RACK_WEAPON_IDS: Array[String] = [
	"laohuoji", "maodingqiang", "duangong", "xuetufazhang", "tiejian", "shuangbi",
]
const RACK_BASE := Vector2(100, 240)

@onready var player: Player = $Player
@onready var combat_room: RoomCombat = $RoomCombat

var _dummies: Array[EnemyBase] = []
var _restarting := false

func _ready() -> void:
	_build_walls_and_signage()
	_wire_player()
	_spawn_dummies()
	_build_weapon_rack()
	_wire_interaction()
	_attach_camera_and_hud()
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.room_cleared.connect(_on_room_cleared)

# ---- 玩家接线（t12 契约的玩家侧在 RoomCombat._adopt_or_spawn_player 完成；此处补操控/初始枪） ----

func _wire_player() -> void:
	var rig := player.get_node("WeaponRig") as WeaponRig
	rig.equip("laohuoji")                     # 初始手枪；其余 5 把自武器架拾取
	player.combat = combat_room.combat        # m1-t5：影袭经 player.combat 写必暴窗（同 rig 契约）
	if not player.has_node("Driver"):
		var driver := Node.new()
		driver.name = "Driver"
		driver.set_script(DRIVER_SCRIPT)
		player.add_child(driver)
	# m1-hygiene：T24 完整战斗 HUD 上树（layer 10，debug_hud layer 20 并存）
	var hud := HUD.new()
	hud.player = player
	add_child(hud)

# ---- 假人 ----

func _spawn_dummies() -> void:
	for pos in DUMMY_POINTS:
		var e := EnemyFactory.spawn(DUMMY_ROW.duplicate(), self, pos)
		if e == null:
			push_error("TrainingRoom: cannot construct dummy")
			continue
		e.combat = combat_room.combat
		e.add_to_group("enemies")
		_dress_enemy(e)
		combat_room.combat.register_body(e, e.combat_faction())
		_dummies.append(e)

func _dress_enemy(e: EnemyBase) -> void:
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	cs.shape = shape
	e.add_child(cs)
	var vis := Polygon2D.new()
	vis.name = "Sprite"                       # Fx 白闪按名寻址
	vis.polygon = PackedVector2Array([
		Vector2(-6, -7), Vector2(6, -7), Vector2(6, 7), Vector2(-6, 7),
	])
	vis.color = Color(0.65, 0.5, 0.35)
	e.add_child(vis)

# ---- 武器架（6 台：E 键交互 equip 入玩家双槽；m1-t6 E 化，接触拾取已移除） ----

func _build_weapon_rack() -> void:
	for i in RACK_WEAPON_IDS.size():
		var id := RACK_WEAPON_IDS[i]
		_build_rack_station(id, RACK_BASE + Vector2(52.0 * i, 0))

func _build_rack_station(weapon_id: String, pos: Vector2) -> void:
	var station := CallbackInteractable.new()
	station.position = pos
	station.action_label = "拾取 %s" % _weapon_name(weapon_id)
	var cs := CollisionShape2D.new()          # 形体占位（选台走距离制，layer/mask 已由基类清零）
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	cs.shape = shape
	station.add_child(cs)
	var vis := Polygon2D.new()
	vis.name = "Sprite"
	vis.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	])
	vis.color = Color(0.28, 0.4, 0.6)
	station.add_child(vis)
	var label := Label.new()
	label.text = _weapon_name(weapon_id)
	label.position = Vector2(-16, -18)
	label.add_theme_font_size_override("font_size", 8)
	station.add_child(label)
	station.on_interact = func(p: Node2D) -> void:
		var pl := p as Player
		if pl == null or pl.weapon_rig == null:
			return
		pl.weapon_rig.equip(weapon_id)
		label.modulate = Color(0.5, 1.0, 0.5)     # 已拾取反馈
		Telemetry.log_row(["equip", Engine.get_physics_frames(), weapon_id])
	add_child(station)

func _weapon_name(weapon_id: String) -> String:
	return String(GameDB.get_weapon(weapon_id).get("name", weapon_id))

# ---- 交互系统接线（m1-t6：玩家 + 浮标；E 键路由见 InteractionSystem） ----

func _wire_interaction() -> void:
	var sys := InteractionSystem.new()
	sys.name = "InteractionSystem"
	sys.player = player
	add_child(sys)

# ---- 相机 / HUD ----

func _attach_camera_and_hud() -> void:
	var cam: Camera2D = GAME_CAMERA.new()
	cam.set("target", player)
	cam.limit_left = int(WORLD_RECT.position.x)
	cam.limit_top = 0
	cam.limit_right = int(WORLD_RECT.end.x)
	cam.limit_bottom = int(WORLD_RECT.end.y)
	add_child(cam)
	var hud: CanvasLayer = DEBUG_HUD.new()
	hud.set("player", player)
	hud.set("combat", combat_room.combat)
	hud.set("room", combat_room)
	add_child(hud)

# ---- 事件 ----

func _on_player_damaged(_amount: int, fatal: bool) -> void:
	# m1-t18：hurt 遥测行收口至 Player.take_hit_ctx（此处只剩死亡重启接线，防双记）。
	if fatal and not _restarting:
		_restarting = true
		print("[M0] player died - restart in 1.5s")
		await get_tree().create_timer(1.5, true).timeout
		get_tree().reload_current_scene()

func _on_room_cleared(room_id: String) -> void:
	print("[M0] room cleared: ", room_id, " coins=", combat_room.coins_collected())

# ---- debug 键（仅 debug 构建） ----

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_K:
			_cheat_rain_bullets()             # [DEBUG] t13 压测预演：60 发边缘弹幕雨
		KEY_T:
			_cheat_toggle_dummy_regen()       # [DEBUG] 木桩回血开关（brief：可开关回血）

## [DEBUG] K：从世界边缘向玩家齐射 60 发敌方弹（确定性排布，不占 RngSvc 流）。
func _cheat_rain_bullets() -> void:
	if combat_room == null or combat_room.combat == null or player == null:
		return
	print("[DEBUG] cheat: bullet rain x60")
	for i in 60:
		var t := float(i) / 4.0
		var pos: Vector2
		match i % 4:
			0: pos = Vector2(lerpf(16.0, 944.0, t), 8.0)
			1: pos = Vector2(952.0, lerpf(8.0, 262.0, t))
			2: pos = Vector2(lerpf(944.0, 16.0, t), 262.0)
			_: pos = Vector2(8.0, lerpf(262.0, 8.0, t))
		var dir := (player.global_position - pos).normalized()
		combat_room.combat.spawn_projectile({
			"pos": pos, "vel": dir * 130.0, "damage": 1,
			"faction": Projectile.Faction.ENEMY, "element": Elements.Id.NONE,
			"pierce": 0, "bounce": 0, "life_seconds": 4.0, "radius": 3.0,
		})

## [DEBUG] T：木桩回血开关。
func _cheat_toggle_dummy_regen() -> void:
	var state := ""
	for d in _dummies:
		if is_instance_valid(d):
			var next := not bool(d.get("regen_enabled"))
			d.set("regen_enabled", next)
			state = str(next)
	print("[DEBUG] dummy regen -> ", state)

# ---- 静态构建 ----

func _build_walls_and_signage() -> void:
	_solid(Rect2(0, 0, 16, 270))              # 西墙
	_solid(Rect2(0, 0, 488, 16))              # 北墙（训练侧）
	_solid(Rect2(0, 254, 488, 16))            # 南墙（训练侧）
	_solid(Rect2(472, 0, 16, 120))            # 隔墙上半（走廊缺口 y∈[120,152]）
	_solid(Rect2(472, 152, 16, 118))          # 隔墙下半
	var floor_vis := Polygon2D.new()
	floor_vis.polygon = PackedVector2Array([
		TRAIN_INTERIOR.position, Vector2(TRAIN_INTERIOR.end.x, TRAIN_INTERIOR.position.y),
		TRAIN_INTERIOR.end, Vector2(TRAIN_INTERIOR.position.x, TRAIN_INTERIOR.end.y),
	])
	floor_vis.color = Color(0.14, 0.16, 0.15)
	floor_vis.z_index = -10
	add_child(floor_vis)
	_label_at("TRAINING RANGE", Vector2(24, 20))
	_label_at("COMBAT ->", Vector2(392, 20))

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

func _label_at(text: String, pos: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 8)
	label.modulate = Color(1, 1, 1, 0.5)
	add_child(label)
