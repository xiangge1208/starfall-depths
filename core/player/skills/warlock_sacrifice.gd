class_name WarlockSacrifice
extends SkillBase
## 术士·蚀 主动技「献祭」+ 被动「虹吸」（附录 L §3，M5 T4；heroes.json id=warlock）。
##
## 被动虹吸：击杀吸 2 蓝——Player._on_enemy_killed 击杀挂钩读点消费（EventBus
## .enemy_killed，passive_id=="siphon" 门控，同掠影先例；全击杀源覆盖），add_energy
## 上限 clamp（蓝满不再溢出）。
##
## 主动献祭：CD 600t（10s，数据行 skill_cd 覆写）/0 蓝，耗 2 HP 得 40 蓝
## （Player.pay_hp 血蓝转换缝绕盾直扣 + add_energy clamp）。施放后 4s（240t）内
## 法杖/激光类武器伤害 +20%：CombatSystem._player_global_mult 回响同款消费口径
## （source_type "weapon" + category staff/laser 复用 _is_echo_weapon_category，
## 乘区 ×1.2，取整收口在 DamageCalc）——窗口字段 player.sacrifice_weapon_until。
## 强化（data["upgraded"]，HeroApplier 按存档注入）：附加 6s（360t）全伤害 +10%
## （player.skill_dmg_bonus 窗，祝福同通道）——「附加」= 与 +20% 乘区叠乘
## （staff/laser 窗前 4s 内 1.2×1.1=1.32）。
##
## 禁自杀守卫（生产守卫 + 单测钉死）：HP≤2 时不可发动——can_cast 门控（HUD 同步灰）
## + pay_hp 生产兜底双保险；施放消耗 2 HP 后恒 hp>=1。
##
## 遥测：sacrifice_cast / kill_energy_siphon（Telemetry 既有清单无撞名）。
## sfx：sacrifice（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

const SKILL_NAME := "献祭"          # 技能中文名（heroes 行 skill_name 同值）
const HP_COST := 2                  # 耗 2 HP（附录 L §3 逐字）
const ENERGY_GAIN := 40             # 得 40 蓝
const WEAPON_BUFF_TICKS := 240      # 4s：法杖/激光伤 +20% 窗
const UPG_BUFF_TICKS := 360         # 强化：6s 全伤害 +10% 窗
const UPG_DMG_PCT := 0.10           # 强化：全伤害 +10%

var upgraded := false

func _init() -> void:
	cooldown_ticks = 600               # 10s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 禁自杀守卫（HP≤2 不可发动）叠加在框架 CD/耗蓝门之上；player==null（占位冒烟
## 无绑定装配）保持框架直通语义，零漂移。
func can_cast(frame: int) -> bool:
	if player != null and player.hp <= HP_COST:
		return false
	return super.can_cast(frame)

## 施放生效：扣 2 HP（pay_hp 生产兜底守卫）→ 得 40 蓝（clamp）→ 开法杖/激光窗；
## 强化再开全伤害窗。无 tick 需求（窗口帧判定，过期自然回落）。
func _activate(frame: int) -> void:
	if player == null:
		return
	if not player.pay_hp(HP_COST):
		return                            # 不可达（can_cast 已门控）；兜底拒绝不产生转换
	AudioMgr.play("sacrifice")
	player.add_energy(ENERGY_GAIN)
	player.sacrifice_weapon_until = frame + WEAPON_BUFF_TICKS
	if upgraded:
		player.skill_dmg_bonus_pct = UPG_DMG_PCT
		player.skill_dmg_bonus_until = frame + UPG_BUFF_TICKS
	Telemetry.log_row(["sacrifice_cast", frame, HP_COST, player.energy])
