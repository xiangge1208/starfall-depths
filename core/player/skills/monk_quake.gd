class_name MonkQuake
extends SkillBase
## 武僧·岳 主动技「震山」+ 被动「行云」（附录 L §3，M5 T8；heroes.json id=monk）。
##
## 被动行云（passive_id=flow_stance 门控）：近战命中积「势」（≤5 层），每层近战伤 +8%。
## - 命中喂点 = melee.gd 直击路径上报缝（单点，"Skill" 节点 has_method 门控——非武僧
##   零漂移；逐目标口径与相邻 Fx.on_combo_hit 相同。近战命中不经 combat 的
##   note_player_hit 缝——隼卡同款披露——故上报缝必须落 melee.gd 命中处）；
## - 每层近战伤 +8%：乘区随层变化写玩家 meta「flow_momentum_mult」（1 + 0.08×层），
##   由 melee.gd 伤害聚合处单点读数消费（位置 = 玩家出口 scaled_damage 之后、暴击
##   掷签之前——祝福同段位；round + min 1 收口）。meta 通道 = 弦 ally_atk_speed 同款
##   「单写多读」，player.gd 零改动；
## - 无衰减/无重置条款（规格未给）：层持续至震山耗尽；跨房保留（技能实例状态）。
##
## 主动震山：CD 540t（9s，数据行 skill_cd 覆写）/0 蓝，耗尽全部「势」→ 以玩家为心
## 90px 环形震荡（半径 90px 议定值——hunter 爆裂/starfall AoE 同款先例）：
## 每层 8 伤（固定值，不走玩家乘区——坚守/hunter 爆裂同口径）+ 击退 8px（议定值，
## 坚守 DEFIANCE_KNOCKBACK_PX 同款；规格未给击退量）。已死体不结算不击退。
## 0 层施放 = 合法 no-op（框架过门语义——hunter「无目标照常过门」同惯例，CD 照走，
## 披露：规格未给 0 层拒施门）。
## 强化（data["upgraded"]，HeroApplier 按存档注入）：满「势」时近战反弹窗口 ×2
## （0.12→0.24s = 7t→14t，窗口 3..16t）——写玩家 meta「flow_parry_extra_ticks」，
## melee.gd 反弹窗开启拍（第 3 拍）单点读数定格本挥击上界 + 挥击处理长度补足
## （meta 缺省 0 = 基线 3..9t 零漂移）。满势随挥击实时生效：挥击第 1 拍命中补满势时，
## 第 3 拍窗口开启已可见满势 meta → 本挥击即 ×2；窗开启后中途耗尽不缩窗（已定格）。
##
## 遥测：flow_full（势满沿一次）/ quake_cast（帧,层数,受击数）——Telemetry 既有清单无撞名。
## sfx：monk_quake（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。
## 视觉表现本卡不落（逻辑层，T3/T4 同先例，fx 后续卡）。

const SKILL_NAME := "震山"                  # 技能中文名（heroes 行 skill_name 同值）
const MOMENTUM_CAP := 5                     # 「势」层数上限（附录 L §3 逐字）
const MOMENTUM_DMG_PCT_PER_STACK := 0.08    # 每层近战伤 +8%（附录 L §3 逐字）
const QUAKE_RADIUS_PX := 90.0               # 议定值（hunter 爆裂/starfall AoE 先例）
const QUAKE_DAMAGE_PER_STACK := 8           # 每层 8 伤（附录 L §3 逐字）
const QUAKE_KNOCKBACK_PX := 8.0             # 议定值（坚守击退同款）
const PARRY_EXTRA_TICKS := 7                # 强化：反弹窗 7t → 14t（0.12→0.24s）
# 玩家 meta 键（melee.gd 读点缝契约；单写多读——弦 ally_atk_speed 同款通道）。
const META_MOMENTUM_MULT := "flow_momentum_mult"
const META_PARRY_EXTRA := "flow_parry_extra_ticks"

var upgraded := false
var momentum := 0                     # 当前「势」层数（0..5；震山耗尽归零）

func _init() -> void:
	cooldown_ticks = 540               # 9s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（影袭先例）
	upgraded = bool(data.get("upgraded", false))
	_sync_metas()                      # 装配基线落 meta（0 层 → ×1.0 / 无扩展；幂等）

## 当前近战伤害乘区（测试/HUD 查询用）。
func momentum_mult() -> float:
	return 1.0 + MOMENTUM_DMG_PCT_PER_STACK * float(momentum)

## 势是否满层（测试/HUD 查询用）。
func momentum_full() -> bool:
	return momentum >= MOMENTUM_CAP

## 近战命中上报缝（melee.gd 单点调用）：积一层（≤5 封顶），随层同步玩家 meta。
## 无衰减条款 → 无帧参数（规格无时间语义）。
func note_melee_hit() -> void:
	if player == null or player.passive_id != "flow_stance":
		return
	if momentum >= MOMENTUM_CAP:
		return
	momentum += 1
	_sync_metas()
	if momentum == MOMENTUM_CAP:
		Telemetry.log_row(["flow_full", Engine.get_physics_frames()], "monk")

## meta 同步（乘区 + 反弹窗扩展；仅层变化/装配时写，非热路径）。
func _sync_metas() -> void:
	if player == null:
		return
	player.set_meta(META_MOMENTUM_MULT, momentum_mult())
	player.set_meta(META_PARRY_EXTRA,
		PARRY_EXTRA_TICKS if upgraded and momentum >= MOMENTUM_CAP else 0)

## 震山生效：耗尽全部势 → 环形 AoE（每层 8 伤 + 击退 8px）。0 层合法 no-op。
func _activate(frame: int) -> void:
	if player == null:
		return
	var stacks := momentum
	momentum = 0
	_sync_metas()
	AudioMgr.play("monk_quake")
	var victims := 0
	var combat = player.combat
	if stacks > 0 and combat != null and combat.has_method("bodies_in_radius"):
		for body in combat.bodies_in_radius(player.global_position, QUAKE_RADIUS_PX,
				Projectile.Faction.ENEMY):
			if body.get("state") == EnemyBase.State.DEAD:
				continue
			victims += 1
			body.take_hit({
				"amount": stacks * QUAKE_DAMAGE_PER_STACK, "is_crit": false,
				"element": Elements.Id.NONE,
				"from": player.global_position, "frame": frame,
				"source_type": "skill", "source_id": "monk_quake",
				"source_name": SKILL_NAME, "attack_name": "震山",
				"player_damage": true,
			})
			# 击退（坚守同款 brain_pos 直改）：已死体跳过（尸位不位移）。
			var e := body as EnemyBase
			if e != null and e.state != EnemyBase.State.DEAD:
				e.brain_pos += (e.brain_pos - player.global_position).normalized() \
					* QUAKE_KNOCKBACK_PX
	Telemetry.log_row(["quake_cast", frame, stacks, victims], "monk")
