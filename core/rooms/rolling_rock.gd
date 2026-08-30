class_name RollingRock
extends RefCounted
## M2-T7 A1 滚石（GDD §10 A1「滚石(直线碾压，有预警)」/ 计划卡口径：从房间一侧
## 直线滚动，预警线 0.5s、速度 200、伤 6、撞墙消失）。纯逻辑（IceZone 同款无头
## 模式）：WAIT(间隔) → WARN(30t 预警线) → ROLL(沿 dir 直线 200px/s，滚出房内域
## 即撞墙消) → 回 WAIT 循环。伤害 = ROLL 相位圆接触（ROCK_RADIUS + 玩家半径，
## 玩家 0.8s 受击无敌帧天然节流碾压连击）。视觉（预警线/石体）由 FloorScene 挂。

enum Phase { WAIT, WARN, ROLL }

const WARN_TICKS := 30               # 0.5s 预警线（TimeConst.ticks(0.5)）
const SPEED_PX := 200.0              # 滚动速度
const DAMAGE := 6
const ROCK_RADIUS_PX := 10.0
const PLAYER_HIT_RADIUS_PX := 6.0    # Player.combat_radius 同值
const DEFAULT_INTERVAL_TICKS := 240  # 两次滚石间隔

var lane_spawn := Vector2.ZERO       # 出生点（世界坐标，发射侧瓦片中心）
var dir := Vector2.RIGHT             # 滚动方向（发射侧的垂直向）
var bounds := Rect2()                # 房间可玩内域（撞墙即消）
var interval_ticks := DEFAULT_INTERVAL_TICKS
var phase := Phase.WAIT
var phase_left := DEFAULT_INTERVAL_TICKS
var rock_pos := Vector2.ZERO         # 当前滚石位置（非 ROLL 相位无意义）


func setup(spawn: Vector2, direction: Vector2, area: Rect2, interval := 0) -> void:
	lane_spawn = spawn
	dir = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	bounds = area
	interval_ticks = interval if interval > 0 else DEFAULT_INTERVAL_TICKS
	phase = Phase.WAIT
	phase_left = interval_ticks


func advance() -> void:
	match phase:
		Phase.WAIT:
			phase_left -= 1
			if phase_left <= 0:
				phase = Phase.WARN
				phase_left = WARN_TICKS
		Phase.WARN:
			phase_left -= 1
			if phase_left <= 0:
				phase = Phase.ROLL
				rock_pos = lane_spawn
		Phase.ROLL:
			rock_pos += dir * (SPEED_PX / TimeConst.FPS)
			if not bounds.grow(ROCK_RADIUS_PX).has_point(rock_pos):
				phase = Phase.WAIT              # 撞墙消失
				phase_left = interval_ticks


func rock_active() -> bool:
	return phase == Phase.ROLL


func warning_active() -> bool:
	return phase == Phase.WARN


## 伤害结算查询：仅滚动相位且圆接触（>0 = 宿主应结算伤害）。
func damage_at(pos: Vector2) -> int:
	if phase != Phase.ROLL:
		return 0
	return DAMAGE if rock_pos.distance_to(pos) <= ROCK_RADIUS_PX + PLAYER_HIT_RADIUS_PX else 0
