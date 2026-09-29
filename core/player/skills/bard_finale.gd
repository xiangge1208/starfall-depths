class_name BardFinale
extends SkillBase
## 吟游·弦 主动技「高潮」+ 被动「渐强」（M5-T7，附录 L §3 第 15 行；heroes.json id=bard）。
##
## 被动渐强（passive_id=crescendo）：连续命中维持 3s → 攻速 +15%（受击重置）。
## - 命中喂点 = CombatSystem 命中结算缝 note_player_hit（同隼弱点洞察转发缝；「发」
##   口径 = 玩家阵营弹命中，近战不经此缝不计数——隼卡同款披露）；
## - 连击语义：相邻命中间隔 > 180t（3s）断连重计（恰 180t 不断）；自首发起维持满
##   180t 的那一拍进入 +15%（_active）。进入后不因停手退出——规格仅「受击重置」；
## - 受击重置：EventBus.player_damaged（take_hit 实际掉血落地拍，无敌帧 no-op 不发）
##   → 清状态清连击；
## - 攻速侧写：tick 每拍续写玩家 atk_speed_boost 共享窗（frame+1 滚动；血怒同款
##   「后写者胜」）——写前读现窗：已有更强窗（如高潮 0.30）存活时不写（不自我降档）。
##
## 主动高潮（CD 720t/0 蓝，heroes 行经 setup 覆写）：4s（240t）我方全体（含召唤物）——
## - 玩家攻速 +30%：atk_speed_boost 共享窗单次开窗（后写者胜）；
## - 友方实体攻速 +30%：player meta「ally_atk_speed_pct/until」通道（SummonBase.
##   ally_fire_interval 读点缝——炮台/佣兵随从开火节拍消费；m5-t5 傀儡继承框架自动
##   生效。友方枚举缝以 meta 单写多读实现，无逐实体遍历——最小增量披露）；
## - 翻滚 CD -0.2s（12t）：roll_cd_reduction_ticks 临时 +12，到期 tick 摘除。落账走
##   drink_roll_cd_reduction_ticks meta 通道（BuffManager 每拍重建该字段的唯一保留
##   来源，timeweaver 时滞先例——只写裸字段会被重 apply 冲掉）；
## - 强化（data["upgraded"]，附录 L 强化行「结束后 3s 渐强不重置」）：高潮到期后的
##   3s（180t）内渐强免疫受击重置（_grace_until 门控 reset 路径）。
##
## 遥测：finale_cast / crescendo_enter / crescendo_reset（Telemetry 既有清单无撞名）。
## sfx：bard_finale（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

const SKILL_NAME := "高潮"            # 技能中文名（heroes 行 skill_name 同值）
const FINALE_DURATION_TICKS := 240    # 4s（附录 L §3）
const FINALE_ATK_PCT := 0.30          # 全体攻速 +30%
const FINALE_ROLL_CD_REDUCTION_TICKS := 12   # 翻滚 CD -0.2s（0.2s × 60fps）
const CRESCENDO_ATK_PCT := 0.15       # 渐强：攻速 +15%
const CRESCENDO_SUSTAIN_TICKS := 180  # 连续命中维持 3s
const GRACE_TICKS := 180              # 强化：结束后 3s 渐强不重置

var upgraded := false
var _chain_start := -1                # 当前连击首拍（-1 = 无连击）
var _chain_last := -1                 # 当前连击末次命中拍
var _crescendo_active := false        # 渐强激活态（受击重置前常驻）
var _finale_until := -1               # 高潮窗终帧（>=0 时 tick 负责到期收尾）
var _roll_cd_applied := false         # 本轮高潮的翻滚减 CD 是否在账（幂等收口）
var _grace_until := -1                # 强化渐强免重置窗终帧（-1 = 无）

func _init() -> void:
	cooldown_ticks = 720               # 12s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（同影袭先例）
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)   # 受击重置：方法引用，free 时自动断连

# ================================================================ 主动：高潮

func _activate(frame: int) -> void:
	if player == null:
		return
	_rollback_roll_cd()                # 幂等守卫（CD 门控下不可达；测试重放兜底）
	_finale_until = frame + FINALE_DURATION_TICKS
	_roll_cd_applied = true
	player.atk_speed_boost_pct = FINALE_ATK_PCT            # 共享窗（后写者胜）
	player.atk_speed_boost_until = _finale_until
	player.set_meta("ally_atk_speed_pct", FINALE_ATK_PCT)  # 友方实体通道（SummonBase 读）
	player.set_meta("ally_atk_speed_until", _finale_until)
	# 翻滚 CD -0.2s：meta 通道落账（BuffManager 重建唯一保留来源）+ 现值同步（时滞先例）。
	player.set_meta("drink_roll_cd_reduction_ticks",
		int(player.get_meta("drink_roll_cd_reduction_ticks", 0)) + FINALE_ROLL_CD_REDUCTION_TICKS)
	player.roll_cd_reduction_ticks += FINALE_ROLL_CD_REDUCTION_TICKS
	AudioMgr.play("bard_finale")
	Telemetry.log_row(["finale_cast", frame, FINALE_DURATION_TICKS,
		1 if upgraded else 0], "bard")

## 到期收尾（tick 驱动）：摘翻滚减 CD 落账 + 强化开渐强免重置窗。
func _expire_finale(frame: int) -> void:
	_rollback_roll_cd()
	_finale_until = -1
	if upgraded:
		_grace_until = frame + GRACE_TICKS

## 摘除本轮翻滚减 CD（meta 通道 + 现值成对回退；幂等）。
func _rollback_roll_cd() -> void:
	if not _roll_cd_applied:
		return
	_roll_cd_applied = false
	if player == null:
		return
	player.set_meta("drink_roll_cd_reduction_ticks",
		maxi(0, int(player.get_meta("drink_roll_cd_reduction_ticks", 0))
			- FINALE_ROLL_CD_REDUCTION_TICKS))
	player.roll_cd_reduction_ticks = maxi(0,
		player.roll_cd_reduction_ticks - FINALE_ROLL_CD_REDUCTION_TICKS)

## 高潮窗是否在（测试/HUD 查询用；读口径 = frame < until，同 atk_speed_boost 窗语义）。
func finale_active(frame: int) -> bool:
	return _finale_until >= 0 and frame < _finale_until

## 渐强是否激活（测试/HUD 查询用）。
func crescendo_active() -> bool:
	return _crescendo_active

# ================================================================ 被动：渐强

## 命中喂点缝（combat 掷签前转发，隼弱点洞察同缝）：弦不做必暴，恒返回 false；
## 副作用仅连击推进/进入判定。
func note_player_hit(_target: Node2D, frame: int) -> bool:
	if _crescendo_active:
		return false                    # 已激活：命中仅保活（规格无退出条件，受击才重置）
	if _chain_last >= 0 and frame - _chain_last > CRESCENDO_SUSTAIN_TICKS:
		_chain_start = -1               # 断连：间隔 >3s（恰 180t 不断）
	if _chain_start < 0:
		_chain_start = frame
	_chain_last = frame
	if frame - _chain_start >= CRESCENDO_SUSTAIN_TICKS:
		_crescendo_active = true
		Telemetry.log_row(["crescendo_enter", frame], "bard")
	return false

## 受击重置（EventBus.player_damaged 实际掉血拍）：强化免重置窗内静默，否则清状态。
func _on_player_damaged(_amount: int, _fatal: bool) -> void:
	if not _crescendo_active and _chain_start < 0:
		return
	if Engine.get_physics_frames() < _grace_until:
		return                          # 强化「结束后 3s 渐强不重置」
	_crescendo_active = false
	_chain_start = -1
	_chain_last = -1
	Telemetry.log_row(["crescendo_reset", Engine.get_physics_frames()], "bard")

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：
## 高潮到期收尾 → 渐强激活期续写攻速共享窗（不强吃更高窗）。
func tick(frame: int) -> void:
	if _finale_until >= 0 and frame >= _finale_until:
		_expire_finale(frame)
	if player == null or not _crescendo_active:
		return
	var current := player.atk_speed_boost_pct \
		if frame < player.atk_speed_boost_until else 0.0
	if current >= CRESCENDO_ATK_PCT:
		return                          # 已有更强窗（高潮/战神像）存活：不自我降档
	player.atk_speed_boost_pct = CRESCENDO_ATK_PCT
	player.atk_speed_boost_until = frame + 1   # 滚动 1 拍窗：停写即过期，无残留

## 生产自驱（life_tide/bloodbath 习语）。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
