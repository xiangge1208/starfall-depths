class_name VineZone
extends RefCounted
## M2-T7 A1 藤蔓减速带（GDD §10 A1「藤蔓(减速带)」/ 计划卡口径：玩家进入减速 40%，
## 敌人不受影响）。m2-t4 IceZone 同款区域模式（Array[Rect2] + add_zone + tick 帧级
## 接缝）——冰面写摩擦、藤蔓写移速，语义不同故平级复用模式而非继承。
## 接缝 = Player.incoming_slow_pct/until（既有玩家减速通道，弹幕冰缓同字段）：
## 域内每拍刷新 0.4 + HOLD_TICKS 保持窗；出域不写，2t 内自然过期回常速
## （无需显式恢复，楼层销毁也不泄漏——与 friction_mult 不同，本接缝帧基自过期）。

const SLOW_PCT := 0.4        # 玩家减速 40%
const HOLD_TICKS := 2        # 出域后自然过期窗口（帧刷新接缝）

var zones: Array[Rect2] = [] # 世界坐标减速矩形集合


## 减速选择纯函数（无头可测）：藤蔓内 0.4，常规地面 0。
static func effective_slow_pct(in_vine: bool) -> float:
	return SLOW_PCT if in_vine else 0.0


func add_zone(rect: Rect2) -> void:
	zones.append(rect)


func in_vine(pos: Vector2) -> bool:
	for r in zones:
		if r.has_point(pos):
			return true
	return false


## 帧级接缝（宿主 _physics_process 每帧驱动）：域内刷新减速（与弹幕冰缓取 max，
## 不互相覆盖削弱——藤蔓 0.4 不得把既有 0.6 冰缓降速）；域外不写，让 until 过期。
## 只接受 Player——敌人没有任何可被藤蔓写入的减速状态（GDD §10 A1）。
func tick(player: Player, frame: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not in_vine(player.global_position):
		return
	var cur: float = player.incoming_slow_pct if frame < player.incoming_slow_until else 0.0
	player.incoming_slow_pct = maxf(cur, SLOW_PCT)
	player.incoming_slow_until = maxi(player.incoming_slow_until, frame + HOLD_TICKS)
