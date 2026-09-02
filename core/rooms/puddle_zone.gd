class_name PuddleZone
extends Node2D
## M4-C1 苔藓史莱姆「水洼」（GDD 附录 A1 行为文本「遇水洼提速」）：敌人生成的临时
## 水洼区域——moss_slime 系在水洼内移速 ×puddle_speed_mult（提速），玩家在水洼内
## 减速 puddle_player_slow_pct（敌我均受影响，任务卡口径；玩家走 incoming_slow_pct
## 既有接缝，与藤蔓/弹幕冰缓同通道取 max 不互覆）。区按 life 到点自净（帧基过期 +
## 全局活区上限，不滞留不泄漏），对房间可清不变量零影响。
## 视觉为半透明水色圆（本文件自绘，无 fx/ 依赖）；脑层测试无宿主时不挂树，纯注册表
## 语义仍可测（prune 帧注入）。

const MAX_ACTIVE := 24             # 全局活区上限（超限淘汰最旧，内存/绘制双封顶）
const WATER_COLOR := Color(0.35, 0.6, 0.85, 0.28)
const WATER_EDGE := Color(0.5, 0.75, 0.95, 0.7)

static var _active: Array = []     # 活区注册表（实例引用，过期/淘汰即移除）

var until_frame := 0
var speed_mult := 1.0
var player_slow_pct := 0.0
var _draw_size := 16.0


func setup(cfg: Dictionary) -> void:
	position = cfg.get("pos", Vector2.ZERO)
	until_frame = int(cfg.get("until_frame", 0))
	speed_mult = float(cfg.get("speed_mult", 1.0))
	player_slow_pct = float(cfg.get("player_slow_pct", 0.0))
	var r := maxf(float(cfg.get("radius", 16.0)), 4.0)
	_draw_size = r
	queue_redraw()


func expired(frame: int) -> bool:
	return frame >= until_frame


func contains(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= _draw_size


func _physics_process(_delta: float) -> void:
	prune(Engine.get_physics_frames())


func _draw() -> void:
	draw_circle(Vector2.ZERO, _draw_size, WATER_COLOR)
	draw_arc(Vector2.ZERO, _draw_size, 0.0, TAU, 20, WATER_EDGE, 1.0)


# ---- 静态注册表（生成/查询/过期；clear 供测试隔离） ----

## 生成一个水洼：host 非 null 时挂树获得绘制与自净 _physics_process；
## 脑层测试 host=null（不挂树），由调用方 prune(frame) 推进过期。
static func spawn(host: Node, cfg: Dictionary) -> PuddleZone:
	prune(int(cfg.get("until_frame", 0)) - 1)        # 顺手清过期（帧基单调，幂等）
	while _active.size() >= MAX_ACTIVE:
		var oldest: PuddleZone = _active[0]
		_active.remove_at(0)
		if oldest.is_inside_tree():
			oldest.queue_free()
	var z := PuddleZone.new()
	z.setup(cfg)
	_active.append(z)
	if host != null:
		host.add_child(z)
	return z


## pos 所在活区（先到先得；过期未 prune 的区跳过——调用方节奏内必有 prune）。
static func zone_at(pos: Vector2, frame: int) -> PuddleZone:
	prune(frame)
	for z: Variant in _active:
		var zone := z as PuddleZone
		if zone != null and is_instance_valid(zone) and zone.contains(pos):
			return zone
	return null


## 帧注入过期推进（宿主 _physics_process / 敌人 _engage / 测试均可驱动；幂等）。
static func prune(frame: int) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var z: PuddleZone = _active[i]
		if z == null or not is_instance_valid(z) or z.expired(frame):
			if z != null and z.is_inside_tree():
				z.queue_free()
			_active.remove_at(i)


## 测试隔离（生产路径无调用点：区全靠帧基过期自净）。
static func clear() -> void:
	for z: Variant in _active:
		var zone := z as PuddleZone
		if zone != null and is_instance_valid(zone) and zone.is_inside_tree():
			zone.queue_free()
	_active.clear()


static func active_count() -> int:
	return _active.size()
