class_name ArcaneNova
extends SkillBase
## 法师·烬 主动技「奥术新星」（M2-T11 计划卡 + GDD §6 技能表法师行）。
## CD 600t（10s；heroes 行 skill_cd 经 setup 覆写）、耗蓝 20（GDD §6）。
## 施放 → 以玩家为中心 120px 冰霜新星：范围内全部敌人 24 固定伤（ICE 元素，经
## EnemyBase.take_hit 与武器弹同通路推进冰层积累；is_crit=false——技能伤不掷暴击，
## GDD §7.1「伤害固定值」）+ 冻结 72t（1.2s，GDD §6）。
## 冻结复用 status_component 语义：经 StatusComponent.apply_freeze 并列消费——
## Boss 免疫由状态侧统一持有；精英减半（GDD §6「冻结 1.2s（精英减半）」→ 36t）。
## 升级版（heroes 行 upgraded，GDD §6 强化列）：半径 ×1.4（120→168px）且冻结 120t（2s）。
## 寻敌沿用 M0 分组（"enemies" 组，RoomCombat 刷怪即入组；位置以 brain_pos 为权威，
## 同坚守被动/自动炮台习语）。被动「回响」（passive_id=echo）为后续卡接线，本卡不实现。

const RADIUS_PX := 120.0                 # 冰霜新星半径（GDD §6）
const RADIUS_UPGRADED_PX := 168.0        # 升级版 120 × 1.4（GDD §6 强化「半径 +40%」）
const DAMAGE := 24                       # 固定伤（GDD §6）
const FREEZE_TICKS := 72                 # 冻结 1.2s（GDD §6）
const FREEZE_TICKS_UPGRADED := 120       # 升级版冻结 2s（GDD §6 强化）
const ELITE_FREEZE_DIVISOR := 2          # 精英冻结减半（GDD §6；72/2=36、120/2=60 整除）

var upgraded := false

func _init() -> void:
	cooldown_ticks = 600        # 10s（GDD §6；数据行覆写）
	energy_cost = 20

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 新星半径（测试/HUD 查询用）。
func nova_radius() -> float:
	return RADIUS_UPGRADED_PX if upgraded else RADIUS_PX

## 冻结时长：升级版 2s；精英再减半（GDD §6）。
func freeze_ticks(is_elite: bool) -> int:
	var t := FREEZE_TICKS_UPGRADED if upgraded else FREEZE_TICKS
	return t / ELITE_FREEZE_DIVISOR if is_elite else t

func _activate(frame: int) -> void:
	if player == null or not player.is_inside_tree():
		return
	var center := player.global_position
	var radius := nova_radius()
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		if e.brain_pos.distance_to(center) > radius:
			continue
		e.take_hit({
			"amount": DAMAGE, "is_crit": false, "element": Elements.Id.ICE,
			"from": center, "frame": frame, "source_type": "skill",
			"source_id": "arcane_nova", "source_name": "奥术新星",
			"attack_name": "奥术新星", "player_damage": true,
		})
		# 冻结须在 take_hit 之后：若命中恰好触发 ICE 阈值（目标已有 1 层冰），
		# _trigger 的直接赋值（1.0s）会覆盖本窗；apply_freeze 取 max 不受影响。
		if e.state == EnemyBase.State.DEAD:
			continue                              # 被终结者不再冻结尸体
		var st := e.status
		if st != null and st.has_method("apply_freeze"):
			st.apply_freeze(freeze_ticks(_is_elite(e)), frame)

## 精英判定：行内 elite_affixes 非空（同 EnemyBase._test_init / EliteAffix 口径）。
func _is_elite(e: EnemyBase) -> bool:
	return not (e.row.get("elite_affixes", []) as Array).is_empty()
