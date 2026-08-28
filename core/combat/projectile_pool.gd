class_name ProjectilePool
## 弹幕对象池（GDD §18.2）。预分配 300，上限 500；满时淘汰最旧非玩家弹，否则最旧弹。

const PREALLOC := 300
const MAX_PROJECTILES := 500

var active: Array[Projectile] = []
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
		active.erase(p)
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
