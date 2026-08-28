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
	active.append(p)
	return p

func despawn(p: Projectile) -> void:
	if not active.has(p):
		return
	active.erase(p)
	p.on_despawn()
	_free.append(p)

func active_count() -> int:
	return active.size()

func _victim() -> Projectile:
	for p in active:                      # 先找最旧敌方弹，否则最旧
		if p.faction == Projectile.Faction.ENEMY:
			return p
	return active[0]
