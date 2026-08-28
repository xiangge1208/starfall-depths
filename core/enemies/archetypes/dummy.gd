extends EnemyBase
## 木桩（m0-t12 靶场）：完全惰性原型——不移动不出手；可开关回血（训练房 T 键切换）。
## 行由训练房硬编码注入（不经 GameDB 表）：hp 99999，M0 内 effectively 不可击杀。
## m1-t6：木桩无碰撞（playtest 交接：木桩不应阻挡走位）——物理层清零，玩家可直接穿过；
## 弹/近战命中走 CombatSystem 空间哈希（register_body），不经物理层，可被打不挡路。

var regen_enabled := false                 # 默认关（M0 武器 dps 打不过 60/s 回血）；训练房 T 键开关

var _nonsolid_done := false                # 一次性：换装脚本后首个物理拍生效（set_script 发生在
                                           # setup 内，晚于 _ready，故不能挂 _ready/_init）

func _engage(_frame: int) -> void:
	pass                                  # 惰性：即便误入 ENGAGE 也无行为

## 覆写物理层：先一次性清碰撞层（玩家 move_and_slide 按 layer 查询 → 不再阻挡；
## 木桩不动，对墙等物理体也无响应需求），再走基类（含 t12 DoT/共鸣接线）+ 回血。
func _physics_process(delta: float) -> void:
	if not _nonsolid_done:
		_nonsolid_done = true
		collision_layer = 0
		collision_mask = 0
	super(delta)
	if state == State.DEAD or not regen_enabled:
		return
	var hp_max := int(row.get("hp", 99999))
	if hp < hp_max:
		hp = mini(hp_max, hp + int(ceil(delta * 20.0)))   # 每帧 +1 ≈ 60 hp/s（fix1 修正注释；数值不变）
