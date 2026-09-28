class_name TimeweaverTimeDilation
extends SkillBase
## 时空·隙 主动技「时缓域」+ 被动「时滞」（M5-T3，附录 L §3 第 12 行）。
##
## 主动（CD 720t/25 蓝，heroes 行经 setup 覆写）：以施放位置为心开 4s（240t）半径
## 110px 时缓域——域内敌方弹幕与敌人移速 ×0.6，Boss 行 ×0.8（减速减半）；强化版
## （data["upgraded"]，Appendix L 强化行）域内我方弹速 +20%。域出恢复 / 4s 到期恢复。
##
## 乘区通道（单点注入，同试炼 mods 惯例，禁散弹式改写）：
## - 数值与进出域判定全部收口在纯函数 domain_scale（本文件，直测）；
## - 唯一读点 = ProjectilePool.velocity_scale_hook（弹池静态取样缝）+ ProjectilePool
##   .field_velocity_scale；唯一弹侧消费点 = ProjectilePool.spawn（出弹时刻缩放，同
##   TrialMods.enemy_bullet_speed_px 出弹单点口径）；唯一体侧消费点 = EnemyBase
##   ._physics_process 速度式一行乘区（TrialMods.enemy_speed_scale 同位追加）。
##   无域/域外/过期恒 1.0（IEEE 精确恒等，非时空英雄逐字节零漂移）。
## 口径披露：①弹幕乘区取「出弹时刻的落点」——弹在飞行中离开域不回加速（与试炼
##   bullet_speed_pct 出弹单点同口径）；敌方「移速」为逐拍体速取样，出域即恢复；
##   ②激光器（EnemyLaser）非弹池实体，不在本乘区口径。
##
## 被动「时滞」（passive_id=time_lag）：翻滚 CD -0.1s（=6t，ROLL_CD_TICKS 42t → 36t）。
## 落地缝（player.gd 本卡禁碰）：经 player 外部累积 meta 通道写 roll CD 减免——
## BuffManager.apply_to_player 对 roll_cd_reduction_ticks 的重建口径是「饮料 meta 全量
## 还原」（buff_manager.gd 181 行），故被动贡献落 drink_roll_cd_reduction_ticks meta 并
## 同步现值：增益/天赋/饮料后续刷新重算（还原自该 meta）不丢失、不重复计数。键名
## drink_ 为「外部累积保留通道」既有语义，非饮品独占。重复装配幂等（delta 对账）。
##
## 域状态为静态单例（一次只一个域；CD 720t > 时长 240t，重开域必不重叠）——池/敌侧
## 静态读点由此取得；测试经 clear_field() 隔离。视觉表现本卡不落（逻辑层，fx 后续卡）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "时缓域"
const FIELD_RADIUS_PX := 110.0        # 附录 L §3：半径 110px
const FIELD_DURATION_TICKS := 240     # 4s
const ENEMY_SCALE := 0.6              # 域内敌弹/敌速 -40%
const BOSS_SCALE := 0.8               # Boss 行减速减半（-20%）
const UPGRADED_PLAYER_BULLET_SCALE := 1.2   # 强化：域内我方弹速 +20%
const PASSIVE_ROLL_CD_REDUCTION_TICKS := 6  # 时滞：0.1s = 6t（GDD §6 拍口径 TimeConst.FPS=60）

## 激活域静态单例（<0 until = 无域）。唯一写点 _activate / clear_field。
static var _field_center := Vector2.ZERO
static var _field_until := -1
static var _field_upgraded := false

var upgraded := false

func _init() -> void:
	cooldown_ticks = 720        # 12s（附录 L §3；数据行覆写）
	energy_cost = 25

func _load(data: Dictionary) -> void:
	super._load(data)           # SkillBase 无字段装载；保留钩子链（同影袭/狂潮先例）
	upgraded = bool(data.get("upgraded", false))
	# 域乘区取样钩子（装配期一次性注册；绑定本实例——实例释放 is_valid()=false，
	# 读点自动回落恒等，跨局/跨角色无残留）。
	ProjectilePool.velocity_scale_hook = Callable(self, "_field_velocity_scale")
	_apply_time_lag_passive()

# ---- 域乘区（纯函数，直测） ----

## 时缓域速度乘区唯一实现：窗闭（until 为末帧，含）/域外 → 1.0（域出恢复两口径）；
## 域内敌方弹/体 → 0.6（Boss 来源行 0.8）；域内我方弹 → 强化 1.2 / 非强化 1.0。
static func domain_scale(center: Vector2, radius: float, until_frame: int, upgraded: bool,
		pos: Vector2, faction: int, is_boss: bool, frame: int) -> float:
	if frame > until_frame:
		return 1.0
	if pos.distance_to(center) > radius:
		return 1.0
	if faction == Projectile.Faction.ENEMY:
		return BOSS_SCALE if is_boss else ENEMY_SCALE
	return UPGRADED_PLAYER_BULLET_SCALE if upgraded else 1.0

## 池/敌侧静态读点的被注入方：读当前静态域状态（无域恒等）。
func _field_velocity_scale(pos: Vector2, faction: int, is_boss: bool, frame: int) -> float:
	return domain_scale(_field_center, FIELD_RADIUS_PX, _field_until, _field_upgraded,
		pos, faction, is_boss, frame)

## 测试隔离（生产路径域全靠帧基过期自净，同 PuddleZone.clear 惯例）。
static func clear_field() -> void:
	_field_until = -1
	_field_upgraded = false
	_field_center = Vector2.ZERO

## 域是否在窗内（测试/遥测查询用；末帧含）。
static func field_active(frame: int) -> bool:
	return frame <= _field_until

func _activate(frame: int) -> void:
	if player == null:
		return
	_field_center = player.global_position
	_field_until = frame + FIELD_DURATION_TICKS
	_field_upgraded = upgraded
	AudioMgr.play("time_dilation")   # m5-t3：时缓域施放拍（cast 过门后到此才响）
	Telemetry.log_row(["time_dilation_cast", frame, FIELD_DURATION_TICKS,
		1 if upgraded else 0], "timeweaver")

# ---- 被动「时滞」（翻滚 CD -0.1s） ----

## 装配期落地（HeroApplier：passive_id 先写、_mount_skill 后调——门控可读）。
## 幂等：贡献以 passive meta 对账，重复装配/换装不重复叠加。
func _apply_time_lag_passive() -> void:
	if player == null or player.passive_id != "time_lag":
		return
	var prev := int(player.get_meta("passive_roll_cd_reduction_ticks", 0))
	var delta := PASSIVE_ROLL_CD_REDUCTION_TICKS - prev
	if delta == 0:
		return
	# 外部累积通道（BuffManager 重建 roll_cd_reduction_ticks 的唯一保留来源）落账 + 现值同步。
	player.set_meta("drink_roll_cd_reduction_ticks",
		int(player.get_meta("drink_roll_cd_reduction_ticks", 0)) + delta)
	player.set_meta("passive_roll_cd_reduction_ticks", PASSIVE_ROLL_CD_REDUCTION_TICKS)
	player.roll_cd_reduction_ticks += delta
