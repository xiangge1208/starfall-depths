class_name HazardSpikes
extends RefCounted
## M2-T7 A2 周期地刺（GDD §10 A2「地刺(周期伸缩)」/ 计划卡口径：周期 90t 伸出、
## 预警 24t 地面红纹、伤 4、缩回 60t）。纯逻辑状态机（m2-t4 IceZone 同款无头模式，
## 不用 Area2D）：FloorScene 持实例逐帧 advance，OUT 相位对 zone 内玩家查询
## damage_at（宿主决定 take_hit 时机，玩家 0.8s 受击无敌帧天然节流同格连击）。
## 相位边界由纯函数 phase_at 钉死（可独立单测）；多簇地刺用 offset_ticks 错峰
## （确定性网格散列，不引随机）。

enum Phase { RETRACT, WARN, OUT }

const WARN_TICKS := 24      # 预警：地面红纹
const OUT_TICKS := 90       # 伸出：伤害窗
const RETRACT_TICKS := 60   # 缩回：安全
const DAMAGE := 4


## 完整周期（24 + 90 + 60 = 174t）。
static func cycle_ticks() -> int:
	return WARN_TICKS + OUT_TICKS + RETRACT_TICKS


## 周期相位纯函数：t ∈ [0,24) 预警 / [24,114) 伸出 / [114,174) 缩回，174 回卷。
## 边界语义：预警结束拍（t=24）立即进入伤害窗；伸出结束拍（t=114）立即安全。
static func phase_at(t: int) -> Phase:
	var m := posmod(t, cycle_ticks())
	if m < WARN_TICKS:
		return Phase.WARN
	if m < WARN_TICKS + OUT_TICKS:
		return Phase.OUT
	return Phase.RETRACT


var zone := Rect2()          # 世界坐标判定矩形（一瓦片 16×16）
var offset_ticks := 0        # 错峰偏移（同层多簇不同步伸缩）
var _t := 0


func setup(rect: Rect2, stagger := 0) -> void:
	zone = rect
	offset_ticks = stagger


func advance() -> void:
	_t += 1


func phase() -> Phase:
	return phase_at(_t + offset_ticks)


## 伤害结算查询：仅伸出相位且命中 zone（>0 = 宿主应结算伤害）。
func damage_at(pos: Vector2) -> int:
	if phase() != Phase.OUT or not zone.has_point(pos):
		return 0
	return DAMAGE
