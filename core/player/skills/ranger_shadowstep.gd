class_name RangerShadowstep
extends SkillBase
## 游侠·影 主动技「影袭」+ 被动「鹰眼」（GDD §6）。
## 影袭：CD 540t（9s）、0 耗蓝。施放 → 沿 player.facing 瞬步 140px（单帧直接位移，
## 披露：不经 move_and_collide/move_and_slide，不查询碰撞——M1 竖切已知取舍，墙体夹取
## 留给房间接缝），并复用玩家受伤无敌窗（player._iframe_until，经 apply_iframes 公共接缝，
## 取 max 不缩短既有窗）。后 240t（4s）射击必暴 + 弹速 +20%：
## 必暴功能侧写 combat.forced_crit_until（暴击在命中结算掷签，rig 层无法强制），
## 弹速侧写 weapon_rig.speed_boost_until（rig try_fire 时 ×1.2）；rig.crit_boost_until
## 为同窗状态镜像（HUD/查询用）。升级版（data["upgraded"]）：无敌 36t（否则 15t）。
## 鹰眼被动：监听 EventBus.player_crit_landed，掷签 <50% → player.add_energy(1)。
## 掷签流可经 hawk_rng 注入；未注入时从当前 RunState 楼层的独立 "hawk" 盐流惰性派生。
## 技能脚本按角色注入（T11），游侠才挂本节点 → 被动天然随角色门控（同坚守挂玩家的先例）。

const DASH_DIST_PX := 140.0         # 瞬步距离（GDD §6）
const BUFF_TICKS := 240             # 4s：必暴 + 弹速窗
const IFRAME_TICKS := 15            # 0.25s
const IFRAME_TICKS_UPGRADED := 36   # 0.6s（升级版）
const HAWK_PROC_CHANCE := 0.5       # 鹰眼 50% 返 1 蓝

var upgraded := false
var hawk_rng: RandomNumberGenerator = null   # 显式注入流（测试/宿主可替换；非 null 时始终优先）
var _derived_hawk_rng: RandomNumberGenerator = null
var _derived_hawk_floor := -1

func _init() -> void:
	cooldown_ticks = 540               # 9s（GDD §6；数据行可覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.player_crit_landed.is_connected(_on_player_crit_landed):
		EventBus.player_crit_landed.connect(_on_player_crit_landed)   # 鹰眼：方法引用，free 时自动断连

func _activate(frame: int) -> void:
	if player == null:
		return
	player.position += player.facing.normalized() * DASH_DIST_PX          # 单帧位移（披露见头注）
	player.apply_iframes(IFRAME_TICKS_UPGRADED if upgraded else IFRAME_TICKS, frame)
	if player.weapon_rig != null:
		player.weapon_rig.crit_boost_until = frame + BUFF_TICKS           # 状态镜像窗
		player.weapon_rig.speed_boost_until = frame + BUFF_TICKS          # rig 弹速 ×1.2
	if player.combat != null:
		player.combat.forced_crit_until = frame + BUFF_TICKS              # 命中结算必暴（掷签接缝）

## 鹰眼：玩家弹暴击落地 → 50% 返 1 蓝。
func _on_player_crit_landed(_amount: int, _at: Vector2) -> void:
	if player == null:
		return
	if _hawk_proc():
		player.add_energy(1)

## 掷签接缝：本地 RandomNumberGenerator.randf() 为原生方法不可覆写，
## 故以本方法为桩点（测试以子类探针覆写，同 RigProbe 先例）。
func _hawk_proc() -> bool:
	return _hawk_should_return_energy(_next_hawk_roll())

## 阈值判定独立成纯函数便于直测：< 50% 返蓝。
func _hawk_should_return_energy(roll: float) -> bool:
	return roll < HAWK_PROC_CHANCE

## 取下一掷签值：优先使用显式注入流；否则按当前楼层 + "hawk" 盐惰性派生。
## 技能节点跨层保留，因此楼层变化时必须换流，不能继续消费上一层序列。
func _next_hawk_roll() -> float:
	if hawk_rng != null:
		return hawk_rng.randf()
	if _derived_hawk_rng == null or _derived_hawk_floor != RunState.floor_idx:
		_derived_hawk_floor = RunState.floor_idx
		_derived_hawk_rng = RunState.stream("hawk")
	return _derived_hawk_rng.randf()
