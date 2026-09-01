class_name EnemyLaser
extends Node2D
## M2-T7 敌方直线激光束（GDD §10 A2「暗视野 + 晶柱折射敌方激光」）：供晶柱折射与
## A2 岩晶炮台（rock_crystal_turret，行键 laser=true 经 turret 原型触发）使用；
## m2-t14 晶棱魔像「棱镜射线」复用本组件。逻辑空间 = 世界坐标（laser_pos 权威，
## 节点变换仅显示镜像）；命中晶柱（PILLAR_GROUP 判定圆）按镜面轴 45° 反射再飞
## ——最多 1 次折射（已折射后再次触柱被吸收，防无限往复）。
## 生命周期：帧注入 tick()（脑层测试直呼；树内 _physics_process 自驱），
## 出房内域 / 命中玩家 / 寿命尽 / 二次触柱 任一即终结。
##
## 折射数学：晶柱视为 45° 镜面，反射向量 r = 2(d·u)u − d（u = 镜面轴单位向量，
## reflect_direction 纯函数无头可测）。与镜面轴成 45° 的轴向入射偏转恰 90°
## （右→下 / 左→上 / 上→左 / 下→右）；沿镜面法线入射原路折返；沿镜面轴掠射
## 方向不变（数学边界，仍消耗折射次数）。
##
## 弹幕预算重估（m2-audit，收口 T7 评审 m4「T14 复用时重估」的悬置承诺）：本组件
## 为独立 Node2D 直进，不经 CombatSystem 投射物池——敌弹 400 上限（ENEMY_BULLET_CAP）
## 不约束激光束，束量由发射方节律自限：①岩晶炮台（turret 行 laser=true）冷却
## cd_ticks−windup（rock_crystal_turret：180−36=144t）＞ 束寿命 DEFAULT_LIFE_TICKS
## (120t) → 每炮台至多 1 束并存（test_enemy_laser 钉死该行不变量）；②晶棱魔像
## 棱镜射线单拍 1 束（三向扫描为时序扫掠非同拍齐发）。全束上界 ≈ 场上炮台数 + 1 ≪ 400；
## F2 最密晶核层窗口探针（40 敌 + 500 弹满压）draw avg 102.2 ≤150 PASS
## （t37-evidence/m2_perf_main_2026-09-01.json）。裁定：不将激光计入 ENEMY_BULLET_CAP
## （束≠弹，计入反引入池化耦合）；新增激光发射方须维持「冷却 ≥ 束寿命」节律。

const PILLAR_GROUP := &"refraction_pillars"   # FloorScene 晶柱实体组（折射判定源）
const MIRROR_AXIS_DEG := 45.0     # 晶柱镜面轴（GDD §10 A2「按 45° 反射」）
const MAX_REFRACTIONS := 1        # 最多 1 次折射（防无限）
const PILLAR_RADIUS_PX := 8.0     # 晶柱判定圆（16px 格内切圆）
const LASER_RADIUS_PX := 3.0
const PLAYER_HIT_RADIUS_PX := 6.0
const DEFAULT_SPEED_PX := 150.0   # 与敌方弹速契约 ≤150 同口径
const DEFAULT_LIFE_TICKS := 120   # 2.0s
const TAIL_PX := 14.0             # 视觉拖尾长
const BEAM_COLOR := Color(1.0, 0.3, 0.35)

var laser_pos := Vector2.ZERO     # 权威位置（世界坐标）
var dir := Vector2.RIGHT
var damage := 5
var speed_px := DEFAULT_SPEED_PX
var life_left := DEFAULT_LIFE_TICKS
var pillars: Array[Vector2] = []  # 晶柱世界坐标集
var bounds := Rect2()             # 房间可玩内域（空矩形 = 无界，脑层测试）
var refracts_left := MAX_REFRACTIONS


## 45° 镜面反射纯函数：incident 关于 axis_deg 轴镜像（保持单位长度）。
## 零向量安全返回零向量（不产生 NaN 方向）。
static func reflect_direction(incident: Vector2, axis_deg := MIRROR_AXIS_DEG) -> Vector2:
	var d := incident.normalized()
	if d == Vector2.ZERO:
		return Vector2.ZERO
	var u := Vector2.from_angle(deg_to_rad(axis_deg))
	return (2.0 * d.dot(u) * u - d).normalized()


var _has_bounds := false
var _alive := true
var _player = null                # 契约：brain_pos + take_hit（PlayerProxy / 测试替身）
var _source_id := ""
var _source_name := ""
var _attack_name := "晶棱激光"


func setup(cfg: Dictionary) -> void:
	laser_pos = cfg.get("pos", Vector2.ZERO)
	var d: Vector2 = cfg.get("dir", Vector2.RIGHT)
	dir = d.normalized() if d != Vector2.ZERO else Vector2.RIGHT
	damage = int(cfg.get("damage", 5))
	speed_px = float(cfg.get("speed_px", DEFAULT_SPEED_PX))
	life_left = int(cfg.get("life_ticks", DEFAULT_LIFE_TICKS))
	bounds = cfg.get("bounds", Rect2())
	_has_bounds = bounds.has_area()
	for p in cfg.get("pillars", []):
		pillars.append(p)
	_player = cfg.get("player", null)
	_source_id = String(cfg.get("source_id", ""))
	_source_name = String(cfg.get("source_name", ""))
	_attack_name = String(cfg.get("attack_name", "晶棱激光"))
	_sync_display()


func alive() -> bool:
	return _alive


## 帧注入接缝：每调一次推进 1 拍（脑层测试直呼驱动；树内 _physics_process 喂）。
func tick() -> void:
	if not _alive:
		return
	life_left -= 1
	if life_left <= 0:
		_end()
		return
	laser_pos += dir * (speed_px / TimeConst.FPS)
	if _tick_pillar():
		return
	if _tick_player():
		return
	if _has_bounds and not bounds.grow(LASER_RADIUS_PX).has_point(laser_pos):
		_end()                     # 撞墙（出房内域）消失
		return
	_sync_display()


## 晶柱拍：命中判定圆 → 未折射则 45° 反射再飞（从柱面沿新向弹出，防同柱反复
## 判定）；已折射过则吸收终结。返回 true = 本拍已终结。
func _tick_pillar() -> bool:
	for i in pillars.size():
		if laser_pos.distance_to(pillars[i]) > PILLAR_RADIUS_PX + LASER_RADIUS_PX:
			continue
		if refracts_left > 0:
			refracts_left -= 1
			dir = reflect_direction(dir)
			laser_pos = pillars[i] + dir * (PILLAR_RADIUS_PX + LASER_RADIUS_PX + 1.0)
			_sync_display()
			return false           # 本拍折射，后续拍沿新方向继续飞
		_end()                     # 第二次触柱吸收（防无限往复）
		return true
	return false


## 玩家拍：圆接触 → take_hit（玩家无敌帧天然节流）后消亡。返回 true = 已终结。
func _tick_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.brain_pos.distance_to(laser_pos) > LASER_RADIUS_PX + PLAYER_HIT_RADIUS_PX:
		return false
	_player.take_hit({
		"amount": damage, "is_crit": false, "element": Elements.Id.NONE,
		"from": laser_pos, "source_type": "laser", "source_id": _source_id,
		"source_name": _source_name, "attack_name": _attack_name,
	})
	_end()
	return true


func _end() -> void:
	_alive = false
	if is_inside_tree():
		queue_free()


func _physics_process(_delta: float) -> void:
	tick()


## 显示镜像（逻辑在世界坐标，节点可挂任意父——树内经 global_position 归位）。
func _sync_display() -> void:
	if is_inside_tree():
		global_position = laser_pos
	else:
		position = laser_pos
	queue_redraw()


func _draw() -> void:
	if not _alive:
		return
	draw_line(Vector2.ZERO, -dir * TAIL_PX, BEAM_COLOR, 2.0)
	draw_circle(Vector2.ZERO, LASER_RADIUS_PX, BEAM_COLOR)
