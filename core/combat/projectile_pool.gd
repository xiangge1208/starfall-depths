class_name ProjectilePool
## 弹幕对象池（GDD §18.2）。预分配 300，上限 500；满时淘汰最旧非玩家弹，否则最旧弹。

const PREALLOC := 300
const MAX_PROJECTILES := 500

var active: Array[Projectile] = []
## cap 淘汰回调（m0-final fix1）：淘汰发生前调用（参数为被淘汰弹）。
## 池不耦合 CombatSystem——由持有者注入（CombatSystem._init 置 _kill，
## 以清 spatial-hash 条目与 _proj_meta，否则每淘汰一次泄漏一条）。
var on_evict := Callable()
var _free: Array[Projectile] = []
var _root: Node

func _init(root: Node) -> void:
	_root = root
	for _i in PREALLOC:
		_free.append(_make())

func _make() -> Projectile:
	var p := Projectile.new()
	p.visible = false
	_root.add_child(p)
	return p

func spawn(cfg: Dictionary) -> Projectile:
	var p: Projectile
	if not _free.is_empty():
		p = _free.pop_back()
	elif active.size() < MAX_PROJECTILES:
		p = _make()
	else:
		p = _victim()
		if on_evict.is_valid():
			on_evict.call(p)        # fix1：淘汰先回调清理（CombatSystem._kill：哈希条目+元数据）
		despawn(p)                  # 出 active + 回收 _free（回调内已 despawn 则幂等跳过）
		p = _free.pop_back()        # 复用刚回收实例（LIFO 队尾即该弹，行为同旧版复用）
	p.setup(cfg)
	# M5-T3 时缓域弹速乘区（唯一弹侧消费点）：出弹时刻按落点取样缩放（敌方弹 ×0.6、
	# Boss 来源 ×0.8；我方弹仅强化域内 ×1.2）。无钩子零开销（纯字段读）；缩放只乘
	# 一次 vel，检测/遥测不受影响。披露：出弹后弹速不再随进出域变化（试炼弹速乘区同口径）。
	if velocity_scale_hook.is_valid():
		var vs := float(velocity_scale_hook.call(p.position, p.faction,
			source_is_boss(p.source_id), Engine.get_physics_frames()))
		if vs != 1.0:
			p.vel *= vs
	active.append(p)
	return p

func despawn(p: Projectile) -> void:
	if not active.has(p):
		return
	active.erase(p)
	p.on_despawn()
	_free.append(p)

# ---- M5-T3 时空·隙 域速度乘区单点取样缝（同试炼 mods 惯例） ----
## 乘区逻辑与进出域判定全部在被注入方（TimeweaverTimeDilation.domain_scale 纯函数），
## 本类只持有唯一读点 + 唯一弹侧消费点（spawn 出弹时刻缩放——同 TrialMods
## enemy_bullet_speed_px 的「出弹单点」口径；域出恢复由取样函数按 pos/frame 判定）。
## 禁散弹式改写：任何新域乘区消费端只许调 field_velocity_scale，不得自建乘区。

## 域速度乘区取样钩子：(pos, faction, is_boss, frame) -> float。由 TimeweaverTimeDilation
## 装配期注入（Callable 绑技能实例；实例释放 is_valid()=false 自动回落恒等 1.0）。
static var velocity_scale_hook := Callable()

## 域速度乘区取样（体/弹同源单点）：无注入/域外/已过期恒 1.0（IEEE 精确恒等零漂移）。
## 弹侧消费点 = spawn()；体侧消费点 = EnemyBase._physics_process 速度式（一行乘区，
## TrialMods.enemy_speed_scale 同位追加）。
static func field_velocity_scale(pos: Vector2, faction: int, is_boss: bool, frame: int) -> float:
	if not velocity_scale_hook.is_valid():
		return 1.0
	return float(velocity_scale_hook.call(pos, faction, is_boss, frame))

## 弹来源是否 Boss 行（enemies.json 行 archetype="boss" 或带 phases 键——镜像
## EnemyBase._row_is_boss 的数据半边；未知 id 恒 false）。仅出弹低频路径查表。
static func source_is_boss(source_id: String) -> bool:
	var row := GameDB.get_enemy(source_id)
	return String(row.get("archetype", "")) == "boss" or row.has("phases")

func active_count() -> int:
	return active.size()

func _victim() -> Projectile:
	for p in active:                      # 先找最旧敌方弹，否则最旧
		if p.faction == Projectile.Faction.ENEMY:
			return p
	return active[0]
