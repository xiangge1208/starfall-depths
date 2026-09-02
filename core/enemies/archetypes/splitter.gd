extends EnemyBase
## 分裂（附录 B 原型「分裂」）：缓慢逼近玩家；死亡经 spawn_callback 出 split_count
## 个子体——子体 hp 取行 split_child_hp（缺省=当前 hp 一半），子体行 split_generations
## 减 1（0 = 子体不再分裂，防无限链）。magma_slime（B.2 A3）split_generations=2：
## 大→中→小两代；mud_slime/moss_slime/ice_spider 为 1 代。
## 子体 counts_for_wave=false（镜像 EnemyBase._split_spawn_children 语义）。
##
## m4-c1 派味特技（行键门控，无键行逐行为零变化）——水洼（苔藓史莱姆，puddle_* 键）：
## ENGAGE 期每 puddle_interval_ticks 在脚下落一个水洼（死亡再落一个）；水洼内：
## 本系敌人移速 ×puddle_speed_mult（「遇水洼提速」），玩家减速 puddle_player_slow_pct
## （敌我均受影响，任务卡口径；玩家走 incoming_slow_pct 既有接缝，取 max 不互覆）。
## 水洼按 puddle_life_seconds 帧基过期 + 全局活区上限（PuddleZone.MAX_ACTIVE），
## 不滞留不泄漏——房间可清不变量零影响。

const DEFAULT_SPLIT_COUNT := 2

var _puddle_next := -1        # m4-c1：下一个水洼落点拍（<0 = 未建立/无键）


func _engage(frame: int) -> void:
	var speed := float(row.get("speed", 40))
	var mult := _puddle_speed_mult(frame)
	var to_player := _player_pos() - brain_pos
	if to_player.length_squared() > 0.0001:
		brain_pos += to_player.normalized() * (speed * mult / TimeConst.FPS)
	_tick_puddle_trail(frame)
	_apply_puddle_player_slow(frame)

## 水洼内提速倍率（「遇水洼提速」；区外/无键恒 1.0）。提速进窗出遥测一次。
func _puddle_speed_mult(frame: int) -> float:
	var mult := float(row.get("puddle_speed_mult", 0.0))
	if mult <= 1.0:
		return 1.0
	var zone := PuddleZone.zone_at(brain_pos, frame)
	if zone == null:
		if get_meta("in_puddle", false):
			set_meta("in_puddle", false)   # 出域复位：下次进窗再报（一窗一行）
		return 1.0
	if not get_meta("in_puddle", false):
		set_meta("in_puddle", true)
		Telemetry.log_row(["puddle_boost", frame, mult], String(row.get("id", "")))
	return mult

## 水洼拖尾：ENGAGE 期每 interval 落一区（首次落点在 ENGAGE 转换拍）。
func _tick_puddle_trail(frame: int) -> void:
	if float(row.get("puddle_life_seconds", 0.0)) <= 0.0:
		return
	if _puddle_next < 0:
		_puddle_next = frame
	if frame < _puddle_next:
		return
	_puddle_next = frame + int(row.get("puddle_interval_ticks", 240))
	_drop_puddle(frame)

## 落一区（挂 combat 取绘制与自净；脑层测试无 combat 不挂树，注册表语义照常——
## 不挂自身防父子变换污染世界坐标）。
func _drop_puddle(frame: int) -> void:
	var zone := PuddleZone.spawn(combat, {
		"pos": brain_pos,
		"radius": float(row.get("puddle_radius", 16.0)),
		"until_frame": frame + TimeConst.ticks(float(row.get("puddle_life_seconds", 6.0))),
		"speed_mult": float(row.get("puddle_speed_mult", 1.0)),
		"player_slow_pct": float(row.get("puddle_player_slow_pct", 0.0)),
	})
	if zone != null:
		Telemetry.log_row(["puddle_created", frame, float(row.get("puddle_radius", 16.0))],
			String(row.get("id", "")))

## 玩家在水洼内的减速半边（既有接缝写法同 VineZone.tick：刷新 2t 保持窗，出域自过期）。
func _apply_puddle_player_slow(frame: int) -> void:
	var slow_pct := float(row.get("puddle_player_slow_pct", 0.0))
	if slow_pct <= 0.0 or player_ref == null:
		return
	var pl: Node = player_ref.get("player")
	if pl == null or not "incoming_slow_pct" in pl:
		return
	var zone := PuddleZone.zone_at(pl.global_position, frame)
	if zone == null:
		return
	var cur: float = pl.get("incoming_slow_pct") \
		if frame < int(pl.get("incoming_slow_until")) else 0.0
	pl.set("incoming_slow_pct", maxf(cur, zone.player_slow_pct))
	pl.set("incoming_slow_until", maxi(int(pl.get("incoming_slow_until")), frame + 2))


## 分裂在 die() 持有（先落子体再退场）；回调未注入（脑层测试/未接线）则跳过。
## m4-c1：水洼系死亡落最后一个水洼（苔藓破裂留水——与拖尾同参同上限）。
func die() -> void:
	if state != State.DEAD:
		if float(row.get("puddle_life_seconds", 0.0)) > 0.0:
			_drop_puddle(Engine.get_physics_frames())
		_spawn_split_children()
	super()

func _spawn_split_children() -> void:
	if int(row.get("split_generations", 0)) <= 0 or not spawn_callback.is_valid():
		return
	var count := int(row.get("split_count", DEFAULT_SPLIT_COUNT))
	var child_row: Dictionary = (row as Dictionary).duplicate(true)
	child_row.erase("elite_affixes")
	var child_hp := int(row.get("split_child_hp", 0))
	if child_hp <= 0:
		child_hp = maxi(int(float(row.get("hp", 10)) * 0.5), 1)
	child_row["hp"] = child_hp
	child_row["split_generations"] = int(row.get("split_generations", 1)) - 1
	var r := combat_radius()
	for i in count:
		var child: Node = spawn_callback.call(String(row.get("id", "")),
			brain_pos + Vector2(r if i == 0 else -r, 0.0), child_row)
		if child != null:
			child.set("hp", child_hp)
			if "hp_max" in child:
				child.set("hp_max", child_hp)
			if "counts_for_wave" in child:
				child.set("counts_for_wave", false)
