class_name SignatureMoves
extends RefCounted
## M4-C1 敌人派味特技的纯函数助手（无 autoload 依赖，无头可测）。
##
## ① 抛物弹道解算（荆棘炮台/种子投手「抛物」）：沿发射轴的减速-落点弧线。
##    弹体以初速 v0 出膛、沿 dir 受减速度 g、速度耗尽拍恰落在目标点：
##      v0² = 2·g·|Δ| 且 落点 = 出膛点 + dir·|Δ|（位移 v0²/2g = |Δ|）
##    给定 v0（行 bullet_speed 经 TrialMods 封顶）与 |Δ| 反解 g 与全程拍数 T = 2|Δ|/v0。
##    §7.5 弹速上限天然满足（v0 即既有封顶后的敌弹速），弧线全程可读可躲。
##
## ② 模仿武器弹形（深窟回响者）：读玩家当前武器行的弹形键（只读 GameDB/weapons.json），
##    复制「弹数/散射/弹速/弹径/弹寿」五形，伤害/阵营/来源保持敌人行口径不变。
##    弹速经 §7.5 上限 150 封顶（TrialMods 缩放后仍封顶）、下限 60 保底可玩。

const MIMIC_SPEED_MIN := 60.0
const MIMIC_SPEED_MAX := 150.0     # GDD §7.5 敌弹速度上限
const MIMIC_PROJECTILES_MAX := 8   # 弹数复制上限（防霰弹类把敌弹预算打穿）
const MIMIC_SPREAD_MAX_DEG := 90.0
const MIMIC_RADIUS_MIN := 2.0
const MIMIC_RADIUS_MAX := 6.0
const MIMIC_LIFE_MIN := 0.6
const MIMIC_LIFE_MAX := 3.0
const MIN_LOB_RANGE_PX := 8.0      # 近距（贴身）不抛物：直线弹语义，防除零/原地打转


## 抛物弹解算：from=出膛点，target=落点，speed=封顶后初速。
## 返回 {} 表示距离过近不抛物（调用方回退直线弹）；
## 否则 {vel, arc_dir, arc_gravity, flight_ticks}——vel 为初速矢量，
## flight_ticks 为出膛到落点的拍数（种子投手落地生怪按此排程）。
## 超射程（T 超过 life_seconds 由调用方钳制 |Δ|，此处不管寿命）。
static func lob_solution(from: Vector2, target: Vector2, speed: float) -> Dictionary:
	if speed <= 0.0:
		return {}
	var delta := target - from
	var dist := delta.length()
	if dist < MIN_LOB_RANGE_PX:
		return {}
	var dir := delta / dist
	var gravity := speed * speed / (2.0 * dist)
	var flight_ticks := int(round(2.0 * dist / speed * TimeConst.FPS))
	return {
		"vel": dir * speed,
		"arc_dir": dir,
		"arc_gravity": gravity,
		"flight_ticks": maxi(flight_ticks, 1),
	}


## |Δ| 射程钳制（寿命封顶）：全停弧线的全程拍数 T = 2|Δ|/v0 不得超过弹寿命。
static func lob_range_cap(speed: float, life_seconds: float) -> float:
	if speed <= 0.0:
		return 0.0
	return speed * life_seconds * 0.5


## 模仿武器弹形参数：weapon 为玩家当前武器行（GameDB/weapons.json 只读）；
## 返回 {projectiles, spread_deg, bullet_speed, bullet_radius, bullet_life}；
## 近战行（is_melee）无弹形可抄，返回 {}（调用方回退默认扇弹）。
static func mimic_volley_params(row: Dictionary, weapon: Dictionary) -> Dictionary:
	if row.is_empty() or weapon.is_empty() or bool(weapon.get("is_melee", false)):
		return {}
	var speed := clampf(TrialMods.enemy_bullet_speed_px(float(weapon.get("bullet_speed", 110))),
		MIMIC_SPEED_MIN, MIMIC_SPEED_MAX)
	return {
		"projectiles": clampi(int(weapon.get("projectiles", 1)), 1, MIMIC_PROJECTILES_MAX),
		"spread_deg": clampf(float(weapon.get("spread_deg", 2.0)), 1.0, MIMIC_SPREAD_MAX_DEG),
		"bullet_speed": speed,
		"bullet_radius": clampf(float(weapon.get("bullet_radius", 3.0)),
			MIMIC_RADIUS_MIN, MIMIC_RADIUS_MAX),
		"bullet_life": clampf(float(weapon.get("bullet_life", 1.2)),
			MIMIC_LIFE_MIN, MIMIC_LIFE_MAX),
	}
