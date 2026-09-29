class_name LycanShift
extends SkillBase
## 狼人·牙 主动技「变身」+ 被动「嗜血」（M5-T9，附录 L §3 第 17 行；heroes.json id=lycan）。
##
## 被动嗜血（passive_id=bloodthirst）：近战击杀回 1 HP，每房 ≤2 次。
## - 上报缝同 m4-c2 掠影先例：melee.gd 击杀路径只负责上报（player.on_melee_kill），
##   门控在 Player（bloodthirst 分支转发本节点 on_melee_kill_report，melee.gd 零改动）；
## - 治疗走 heal() 单一收口（灾厄禁疗返回 false 不消耗次数——berserk 击杀返还先例）；
## - 「每房」计数：EventBus.room_cleared（房清唯一广播）重置 ≤2 配额——房清即上一房
##   结束拍，下一房以满配额起算；从未清房的房（训练房驻留）沿用当房配额（披露）。
##
## 主动变身（CD 840t/0 蓝，heroes 行经 setup 覆写）：6s（360t）狼形——
## - 移速 +20%：move_speed_boost 共享窗单次开窗（后写者胜，berserk 破釜先例）；
## - 近战伤 +50%：player.melee_dmg_bonus 窗（m5-t9 参数缝；scaled_damage 近战面
##   单点读数——当前武器 is_melee/空槽手刀口径；狼形期远程锁定，远程面读不到本窗）；
## - 翻滚变 80px 突进：player.roll_dist_override_px 形态距离档覆写（56px 基线直取
##   替换，非乘区——m2-t35 buff_roll_distance_pct 通道是增益语义不合形态替换）；
##   到期 tick 摘除恢复基线（bard 翻滚减 CD 回退先例）；CD 840t > 时长，重施不重叠；
## - 期间远程锁定：player.ranged_lock_until 窗，weapon_rig.try_fire 开火入口读点
##   拒发（不耗蓝不进冷却）；HUD 锁定表现非本卡范围（计划卡披露）；
## - 强化（data["upgraded"]，HeroApplier 按存档注入，附录 L 强化行）：持续 10s（600t）
##   且结束回 1 HP（heal() 单一收口；灾厄禁疗下结束治疗失效，telemetry 记 healed=0）。
##
## 遥测：shift_cast / shift_end / bloodthirst_heal（Telemetry 既有清单无撞名）。
## sfx：lycan_shift（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "变身"
const SHIFT_DURATION_TICKS := 360         # 6s（附录 L §3）
const SHIFT_DURATION_TICKS_UPGRADED := 600  # 强化：10s
const WOLF_MOVE_PCT := 0.20               # 移速 +20%
const WOLF_MELEE_DMG_PCT := 0.50          # 近战伤 +50%
const WOLF_ROLL_DIST_PX := 80.0           # 翻滚变 80px 突进（附录 L §3 逐字）
const BLOODTHIRST_HEAL := 1               # 嗜血：近战击杀回 1 HP
const BLOODTHIRST_PER_ROOM := 2           # 每房 ≤2 次
const SHIFT_END_HEAL := 1                 # 强化：结束回 1 HP

var upgraded := false
var _shift_until := -1               # 狼形窗终帧（>=0 时 tick 负责到期收尾）
var _room_heals_left := BLOODTHIRST_PER_ROOM   # 嗜血当房剩余次数

func _init() -> void:
	cooldown_ticks = 840               # 14s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（m5-t7 先例）
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.room_cleared.is_connected(_on_room_cleared):
		EventBus.room_cleared.connect(_on_room_cleared)   # 每房配额重置：方法引用，free 时自动断连

## 狼形是否在窗（测试/HUD 查询用；读口径 = frame < until，同共享窗语义）。
func shift_active(frame: int) -> bool:
	return _shift_until >= 0 and frame < _shift_until

## 嗜血当房剩余次数（测试/HUD 查询用）。
func bloodthirst_heals_left() -> int:
	return _room_heals_left

## 施放生效：开狼形四参数覆写（三窗一覆写）。无 player（占位冒烟）框架直通。
func _activate(frame: int) -> void:
	if player == null:
		return
	var dur := SHIFT_DURATION_TICKS_UPGRADED if upgraded else SHIFT_DURATION_TICKS
	AudioMgr.play("lycan_shift")
	_shift_until = frame + dur
	player.move_speed_boost_pct = WOLF_MOVE_PCT
	player.move_speed_boost_until = _shift_until
	player.melee_dmg_bonus_pct = WOLF_MELEE_DMG_PCT
	player.melee_dmg_bonus_until = _shift_until
	player.roll_dist_override_px = WOLF_ROLL_DIST_PX
	player.ranged_lock_until = _shift_until
	Telemetry.log_row(["shift_cast", frame, dur, 1 if upgraded else 0], "lycan")

## 到期收尾（tick 驱动）：摘翻滚距离覆写（窗字段按帧自然过期，无需回写）+
## 强化结束回 1 HP（heal 单一收口，灾厄禁疗失效不补）。
func _expire_shift(frame: int) -> void:
	_shift_until = -1
	if player == null:
		return
	player.roll_dist_override_px = -1.0
	var healed := 0
	if upgraded and player.heal(SHIFT_END_HEAL):
		healed = SHIFT_END_HEAL
	Telemetry.log_row(["shift_end", frame, healed], "lycan")

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：狼形到期收尾。
func tick(frame: int) -> void:
	if _shift_until >= 0 and frame >= _shift_until:
		_expire_shift(frame)

## 嗜血：近战击杀上报（Player.on_melee_kill bloodthirst 分支转发；m4-c2 掠影同缝）。
## 配额内且 heal() 成功才消耗次数（灾厄禁疗不消耗）；满配额静默。
func on_melee_kill_report(frame: int) -> void:
	if player == null or _room_heals_left <= 0:
		return
	if not player.heal(BLOODTHIRST_HEAL):
		return
	_room_heals_left -= 1
	Telemetry.log_row(["bloodthirst_heal", frame, BLOODTHIRST_HEAL, _room_heals_left], "lycan")

## 房清重置当房配额（EventBus.room_cleared；见头注「每房」口径）。
func _on_room_cleared(_room_id: String) -> void:
	_room_heals_left = BLOODTHIRST_PER_ROOM

## 生产自驱（life_tide/bloodbath 习语）。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
