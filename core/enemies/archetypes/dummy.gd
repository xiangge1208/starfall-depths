extends EnemyBase
## 木桩（m0-t12 靶场）：完全惰性原型——不移动不出手；可开关回血（训练房 T 键切换）。
## 行由训练房硬编码注入（不经 GameDB 表）：hp 99999，M0 内 effectively 不可击杀。

var regen_enabled := false                 # 默认关（M0 武器 dps 打不过 60/s 回血）；训练房 T 键开关

func _engage(_frame: int) -> void:
	pass                                  # 惰性：即便误入 ENGAGE 也无行为

## 覆写物理层：先走基类（含 t12 DoT/共鸣接线），再按开关回血（每帧 +1 ≈ 60 hp/s @60fps）。
func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.DEAD or not regen_enabled:
		return
	var hp_max := int(row.get("hp", 99999))
	if hp < hp_max:
		hp = mini(hp_max, hp + int(ceil(delta * 20.0)))   # 每帧 +1 ≈ 60 hp/s（fix1 修正注释；数值不变）
