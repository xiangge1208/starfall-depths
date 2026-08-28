extends "res://core/enemies/archetypes/suicide.gd"
## 自爆王虫（小 Boss，附录 B.3「追击+周期召唤苦力虫环；本体死亡延迟 1s 大爆」）：
## 完整继承苦力虫追击/引信/爆炸语义，叠加召唤环——ENGAGE 转换拍即召第一环，
## 此后每 300t 补召；已召存活数 ≤4（自身经 tracked 数组计数，含同拍已死者清理）。
## 延迟大爆由行 delayed_death_ticks=60 驱动（EnemyBase.die() 分支 → DelayedBlast），
## 本脚本不持有爆炸逻辑（单一爆炸源原则不变）。

const SUMMON_EVERY_TICKS := 300
const MAX_SUMMONED := 4        # 已召小怪存活上限（B.3「≤4 只」）
const RING_COUNT := 4          # 一环 4 只（均布象限）
const RING_RADIUS_PX := 40.0
const SUMMON_ROW := "kuli_bug"

var _summoned: Array = []      # 已召体引用表（存活计数；free/死亡者按拍清理）
var _last_summon_frame := -1

## ENGAGE 转换拍：先锚定引信（苦力虫语义照旧），再召第一环并锚定召唤节拍。
func _on_engage_start(frame: int) -> void:
	super(frame)
	_last_summon_frame = frame
	_summon_ring()

func _engage(frame: int) -> void:
	super(frame)
	if state == State.DEAD:
		return                   # 引信到点拍 super 内已 die()，本拍不再召唤
	if frame - _last_summon_frame >= SUMMON_EVERY_TICKS:
		_last_summon_frame = frame
		_summon_ring()

## 召唤环：存活数 < 上限时补召（一次至多一环，总量夹到上限）；经 spawn_callback 接缝，
## 回调未注入（脑层测试/未接线）则静默跳过。
func _summon_ring() -> void:
	if not spawn_callback.is_valid():
		return
	_prune_tracked()
	var room := MAX_SUMMONED - _summoned.size()
	if room <= 0:
		return
	var count := mini(room, RING_COUNT)
	for i in count:
		var ang := TAU * float(i) / float(RING_COUNT)
		var child: Node = spawn_callback.call(SUMMON_ROW, brain_pos + Vector2.from_angle(ang) * RING_RADIUS_PX)
		if child != null:
			_summoned.append(child)

## 清理跟踪表：已 free 或已死亡（state==DEAD）者移出存活计数。
func _prune_tracked() -> void:
	var alive: Array = []
	for c in _summoned:
		if c == null or not is_instance_valid(c):
			continue
		var st: Variant = c.get("state")
		if st != null and st == EnemyBase.State.DEAD:
			continue
		alive.append(c)
	_summoned = alive
