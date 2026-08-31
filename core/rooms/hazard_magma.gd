class_name HazardMagma
extends RefCounted
## M2-T10 A3 岩浆生态三组件（GDD §10 A3「岩浆地块(DOT 2/s)+火雨事件；间歇喷口(预警后
## 喷发)」/ 计划卡口径），单文件分区：本类 = 岩浆 DOT 区；内部类 MagmaGeyser = 间歇喷口；
## FireRain = Boss/事件驱动火雨红圈（T19 熔核暴君/T24 星陨先知的驱动接口）。
## 全部纯逻辑无头组件（IceZone/VineZone/HazardSpikes 同款模式，不用 Area2D）：
## FloorScene 持实例逐帧驱动，伤害经宿主 player.take_hit 结算。
##
## 岩浆 DOT 脉冲口径：2/s = 每 60t（1s）一脉冲 2 伤，脉冲间隔 > 玩家 0.8s 受击无敌帧
## （48t）——2/s 不被无敌帧节流成 1.25/s；抗火增益（玩家 meta buff_anti_fire 0/1，
## T12 BuffManager aggregate 落地）减半 → 每脉冲 1 伤（=1/s）。出域暂停驻留拍（不清零），
## 回域续算。敌人不受岩浆影响（tick 只接受 Player，同藤蔓/冰面公平性结构保证）。

const BASE_DPS := 2.0              # GDD §10 A3：站立 2/s
const ANTI_FIRE_MULT := 0.5        # 抗火增益减半（卡口径）
const PULSE_TICKS := 60            # 1s DOT 脉冲（TimeConst.ticks(1.0)，> HURT_IFRAME 48t）
const ANTI_FIRE_META := "buff_anti_fire"   # T12 落地键（0/1 flag，aggregate 取 max）

var zones: Array[Rect2] = []       # 世界坐标岩浆矩形集合
var _standing := 0                 # 域内驻留拍计数（出域暂停，回域续算）


## DPS 纯函数（无头可测）：常规 2/s，抗火减半 1/s。
static func effective_dps(anti_fire: bool) -> float:
	return BASE_DPS * ANTI_FIRE_MULT if anti_fire else BASE_DPS


## 单脉冲伤害纯函数：1s 脉冲 × DPS 取整（2 / 抗火 1）。
static func pulse_damage(anti_fire: bool) -> int:
	return int(round(effective_dps(anti_fire) * float(PULSE_TICKS) / TimeConst.FPS))


## 玩家抗火 meta 读取（buff_anti_fire 0/1；缺省 0 = 无增益）。
static func has_anti_fire(p: Player) -> bool:
	return p != null and is_instance_valid(p) and int(p.get_meta(ANTI_FIRE_META, 0)) != 0


func add_zone(rect: Rect2) -> void:
	zones.append(rect)


func in_magma(pos: Vector2) -> bool:
	for r in zones:
		if r.has_point(pos):
			return true
	return false


## 帧级接缝（宿主 _physics_process 每帧驱动）：玩家站域内累积驻留拍，满 60t 出一脉冲
## （返回脉冲伤害，0 = 本拍无结算；宿主经 take_hit 落地）。域外不累积也不清零。
func tick(player: Player) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	if not in_magma(player.global_position):
		return 0
	_standing += 1
	if _standing < PULSE_TICKS:
		return 0
	_standing = 0
	return pulse_damage(has_anti_fire(player))


# ================================================================ 间歇喷口

## A3 间歇喷口（卡口径：周期 180t、预警 36t、喷发伤 8）。HazardSpikes 同款相位机：
## IDLE(132) → WARN(36) → ERUPT(喷发窗) → 回卷；相位边界由纯函数 phase_at 钉死，
## offset_ticks 网格确定性散列错峰（不引随机）。伤害 = ERUPT 相位且命中 zone
## （宿主 take_hit，玩家受击无敌帧天然节流整窗连击）。
class MagmaGeyser extends RefCounted:
	enum Phase { IDLE, WARN, ERUPT }

	const CYCLE_TICKS := 180     # 周期 180t（卡口径）
	const WARN_TICKS := 36       # 预警 36t（卡口径）
	const ERUPT_TICKS := 12      # 喷发窗 0.2s（卡未定时长——短爆发拍，见任务偏差记录）
	const DAMAGE := 8            # 喷发伤 8（卡口径）

	var zone := Rect2()          # 世界坐标判定矩形（一瓦片 16×16）
	var offset_ticks := 0        # 错峰偏移
	var _t := 0


	static func idle_ticks() -> int:
		return CYCLE_TICKS - WARN_TICKS - ERUPT_TICKS


	## 周期相位纯函数：t ∈ [0,132) 蛰伏 / [132,168) 预警 / [168,180) 喷发，180 回卷。
	## 边界语义同地刺：预警结束拍（t=168）立即进入伤害窗。
	static func phase_at(t: int) -> Phase:
		var m := posmod(t, CYCLE_TICKS)
		if m < idle_ticks():
			return Phase.IDLE
		if m < idle_ticks() + WARN_TICKS:
			return Phase.WARN
		return Phase.ERUPT


	func setup(rect: Rect2, stagger := 0) -> void:
		zone = rect
		offset_ticks = stagger
		_t = 0


	func advance() -> void:
		_t += 1


	func phase() -> Phase:
		return phase_at(_t + offset_ticks)


	## 伤害结算查询：仅喷发相位且命中 zone（>0 = 宿主应结算伤害）。
	func damage_at(pos: Vector2) -> int:
		if phase() != Phase.ERUPT or not zone.has_point(pos):
			return 0
		return DAMAGE


# ================================================================ 火雨

## A3 火雨（卡口径：Boss/事件驱动全屏红圈落点，预警 48t）。驱动契约（T19/T24 消费）：
## 宿主注入 world_pos 调 schedule（每落点一红圈，可多发并行）→ 宿主每帧 tick() 推进
## 预告倒计时 → 第 48 拍恰一拍落点（striking_at 命中半径即伤）→ 下一拍过期自除。
## 倒计时制（非绝对帧）与地刺/滚石一致，注入帧测试与真实 60Hz 同语义。
class FireRain extends RefCounted:
	const WARN_TICKS := 48       # 红圈预警 48t（卡口径）
	const DAMAGE := 7            # 落点伤（卡未定值——取 GDD §10 A3 敌弹幕档 7，见偏差记录）
	const RADIUS_PX := 24.0      # 红圈判定半径（卡未定值，见偏差记录）

	## 落点集（FIFO：同预警时长 → 先排先落先除）：
	## {"pos": Vector2, "warn_left": int, "boom": bool}
	var strikes: Array = []


	## Boss/事件驱动入口：登记一个红圈落点（世界坐标）。
	func schedule(pos: Vector2) -> void:
		strikes.append({"pos": pos, "warn_left": WARN_TICKS, "boom": false})


	## 帧推进：预警倒计时；第 48 拍置 boom（该拍可判定伤害），再下一拍移除。
	func tick() -> void:
		for i in range(strikes.size() - 1, -1, -1):
			var s: Dictionary = strikes[i]
			if s["boom"]:
				strikes.remove_at(i)
				continue
			s["warn_left"] = int(s["warn_left"]) - 1
			if int(s["warn_left"]) <= 0:
				s["boom"] = true


	## 落点伤害查询：恰 boom 拍且命中任一落点半径（>0 = 宿主应结算伤害）。
	func striking_at(pos: Vector2) -> int:
		for s in strikes:
			if s["boom"] and (s["pos"] as Vector2).distance_to(pos) <= RADIUS_PX:
				return DAMAGE
		return 0


	## 当前落点总数（预警中 + 本拍 boom）。
	func strike_count() -> int:
		return strikes.size()
