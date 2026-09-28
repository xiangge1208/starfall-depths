class_name BerserkBloodbath
extends SkillBase
## 狂战士·烈 主动技「破釜」+ 被动「血怒」（附录 L §3，M5 T4；heroes.json id=berserk）。
##
## 被动血怒：HP<50%（严格低于，判定单一出处 Player.bloodrage_enraged，恰 50% 不激活）时
## 攻速 +25%、受到伤害 +1：
## - 攻速侧：本技能 _physics_process 自驱 tick（life_tide 习语，测试可注入任意帧直驱）
##   每拍续写玩家 atk_speed_boost 共享窗（frame+1 滚动；战神像/折跃枪托同款「后写者胜」
##   覆写语义——血怒为持续状态，激活期它就是每拍的最后写入者）；未激活拍零写入（不
##   覆盖既有窗），停写后旧窗 1 拍内自然过期。
## - 受伤 +1：Player.take_hit_ctx 伤害入口读点消费（乘区收口后固定 +1，不吃任何乘区）。
##
## 主动破釜：CD 720t（12s，数据行 skill_cd 覆写）/0 蓝，耗 2 HP（Player.pay_hp 血蓝
## 转换缝，绕盾直扣）：5s（300t）内全伤害 +40%（player.skill_dmg_bonus 窗，祝福同
## 通道，远程+近战统一经 scaled_damage 出口）、移速 +15%（move_speed_boost 共享窗）。
## 强化（data["upgraded"]，HeroApplier 按存档注入）：持续 8s（480t）+ 窗内击杀返还
## 1 HP（每次施放 ≤2 次；EventBus.enemy_killed 订阅于 setup，ranger 鹰眼先例；治疗走
## heal() 单一收口——挑战房 heal_disable 灾厄下返还失效且不消耗次数）。
##
## 禁自杀守卫（生产守卫 + 单测钉死）：HP≤2 时不可发动——can_cast 门控（HUD 同步灰）
## + pay_hp 生产兜底双保险；施放消耗 2 HP 后恒 hp>=1。
##
## 遥测：bloodbath_cast / kill_hp_refund（Telemetry 既有清单无撞名）。
## sfx：bloodbath（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

const SKILL_NAME := "破釜"          # 技能中文名（heroes 行 skill_name 同值）
const HP_COST := 2                  # 耗 2 HP（附录 L §3 逐字）
const DURATION_TICKS := 300         # 5s
const DURATION_TICKS_UPGRADED := 480  # 强化：8s
const BLOODBATH_DMG_PCT := 0.40     # 伤害 +40%
const BLOODBATH_MOVE_PCT := 0.15    # 移速 +15%
const BLOODRAGE_ATK_PCT := 0.25     # 血怒：攻速 +25%
const REFUND_HP := 1                # 强化：击杀返还 1 HP
const REFUND_MAX_PER_CAST := 2      # 每次施放 ≤2 次

var upgraded := false
var _refund_left := 0               # 本次施放窗内剩余返还次数（0 = 未武装）
var _refund_until := -1             # 返还窗终帧（frame > 此值失效）

func _init() -> void:
	cooldown_ticks = 720               # 12s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 禁自杀守卫（HP≤2 不可发动）叠加在框架 CD/耗蓝门之上；player==null（占位冒烟
## 无绑定装配）保持框架直通语义，零漂移。
func can_cast(frame: int) -> bool:
	if player != null and player.hp <= HP_COST:
		return false
	return super.can_cast(frame)

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)   # 强化返还：方法引用，free 时自动断连

## 施放生效：扣 2 HP（pay_hp 生产兜底守卫）→ 开全伤害/移速窗（后写者胜共享窗语义）
## → 强化武装击杀返还。任何窗字段不读缺省即恒等（非烈零漂移由玩家字段缺省保证）。
func _activate(frame: int) -> void:
	if player == null:
		return
	if not player.pay_hp(HP_COST):
		return                            # 不可达（can_cast 已门控）；兜底拒绝不耗 CD 外副作用
	var dur := DURATION_TICKS_UPGRADED if upgraded else DURATION_TICKS
	AudioMgr.play("bloodbath")
	player.skill_dmg_bonus_pct = BLOODBATH_DMG_PCT
	player.skill_dmg_bonus_until = frame + dur
	player.move_speed_boost_pct = BLOODBATH_MOVE_PCT
	player.move_speed_boost_until = frame + dur
	_refund_left = REFUND_MAX_PER_CAST if upgraded else 0
	_refund_until = frame + dur if upgraded else -1
	Telemetry.log_row(["bloodbath_cast", frame, HP_COST, dur])

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：血怒激活期续写攻速共享窗。
func tick(frame: int) -> void:
	if player == null or not player.bloodrage_enraged():
		return
	player.atk_speed_boost_pct = BLOODRAGE_ATK_PCT
	player.atk_speed_boost_until = frame + 1   # 滚动 1 拍窗：停写即过期，无残留

## 强化返还：窗内击杀 → heal(1)（单一收口；灾厄禁疗返回 false 不消耗次数）。
## 次数按次施放重置（_activate 武装），窗外/用尽/非强化静默返回。
func _on_enemy_killed(_enemy_id: String) -> void:
	if player == null or _refund_left <= 0:
		return
	if Engine.get_physics_frames() > _refund_until:
		return
	if not player.heal(REFUND_HP):
		return
	_refund_left -= 1
	Telemetry.log_row(["kill_hp_refund", Engine.get_physics_frames(), REFUND_HP, _refund_left])

## 生产自驱（life_tide 习语）。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
