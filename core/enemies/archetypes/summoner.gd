extends EnemyBase
## 召唤（附录 B 原型「召唤」）：ENGAGE 转换拍召第一波，此后每 summon_interval_ticks
## 补召；已召存活数 ≤ summon_cap。召唤经 spawn_callback 接缝（镜像 zibao_wangchong），
## 子体不计波次（counts_for_wave=false 由房间回调路径持有，脑测替身不校验）。
## speed>0 时缓慢逼近玩家（电磁蛛 80；三系召唤师本体 0=原地驻守）。

const RING_RADIUS_PX := 40.0

var _summoned: Array = []
var _last_summon_frame := -1

func _on_engage_start(frame: int) -> void:
	_last_summon_frame = frame
	_summon_wave()

func _engage(frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	var speed := float(row.get("speed", 0))
	if speed > 0.0 and to_player.length_squared() > 0.0001:
		brain_pos += to_player.normalized() * (speed / TimeConst.FPS)
	if frame - _last_summon_frame >= int(row.get("summon_interval_ticks", 240)):
		_last_summon_frame = frame
		_summon_wave()

## 一波至多 summon_count 只，总量夹到存活上限；回调未注入则静默跳过。
func _summon_wave() -> void:
	if not spawn_callback.is_valid():
		return
	_prune_tracked()
	var cap := int(row.get("summon_cap", 3))
	var room := cap - _summoned.size()
	if room <= 0:
		return
	var count := mini(room, int(row.get("summon_count", 1)))
	var radius := maxf(float(row.get("ring_radius_px", RING_RADIUS_PX)), 1.0)
	for i in count:
		var ang := TAU * float(i) / float(count)
		var child: Node = spawn_callback.call(String(row.get("summon_row", "")),
			brain_pos + Vector2.from_angle(ang) * radius, {})
		if child != null:
			_summoned.append(child)

## 存活计数清理：已 free 或 state==DEAD 者移出（镜像 zibao_wangchong._prune_tracked）。
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
