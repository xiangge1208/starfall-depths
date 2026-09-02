extends EnemyBase
## 弹幕（附录 B 原型「弹幕」）：低速驻守（speed 0 为主），周期 windup 预警 → 齐射 →
## 冷却。齐射形态（行键驱动）：
## - volley_mode "ring"：volley_count 发全向环弹（冰晶法师「冰环弹」/星髓聚合体）；
## - 默认扇面：volley_count 发以玩家方向为中心、volley_spread_deg 均布扇弹
##   （种子投手/深窟回响者/烈焰巫妖「火墙推进弹」）。
## 增益键：slow_pct/slow_ticks（冰缓，沿用蘑菇孢子手弹契约）；
## element_rotate=true 时元素按 火→冰→电→毒 逐轮轮换（星髓聚合体「随机切换 4 元素」
## 的确定性轮换实现——同 seed 可复现，不引入额外 RNG 流）。
##
## m4-c1 派味特技（行键门控，无键行逐行为零变化）：
## - 火雨区（火雨祭司，firerain_* 键）：齐射拍改施放 firerain_count 个预警红圈火雨区
##   （FirerainZone，延迟 firerain_delay_ticks ≥21t §7.5，到点对圈内玩家结算
##   firerain_dmg）——替换既有环形弹（task-9 口径：环形弹为火雨区的占位实现）。
## - 模仿武器（深窟回响者，mimic_weapon=true）：读玩家当前武器行弹形（只读
##   GameDB/weapons.json，SignatureMoves.mimic_volley_params 复制弹数/散射/弹速/
##   弹径/弹寿，伤害保持行口径），无武器/近战/无接缝时回退默认扇弹。
## - 抛物+落地生怪（种子投手，arc_shot + impact_spawn_* 键）：齐射改抛物弹（落点=
##   发射拍解算点），每弹落地时按 impact_spawn_chance 掷签生 1 只 impact_spawn_row
##   幼体（per-投手存活上限 impact_spawn_cap 防爆；召唤体 counts_for_wave=false，
##   不阻清房）。

const DEFAULT_VOLLEY_COUNT := 3
const DEFAULT_SPREAD_DEG := 30.0
const ROTATE_ELEMENTS: Array[int] = [
	Elements.Id.FIRE, Elements.Id.ICE, Elements.Id.SHOCK, Elements.Id.POISON,
]

var _phase := "idle"
var _phase_left := 0
var _volley_index := 0

# ---- m4-c1 落地生怪排程 ----
var _pending_sprouts: Array[Dictionary] = []   # {due_frame, pos, rolled}
var _sprout_alive: Array = []                  # 已生幼体引用（存活计数用）
var _sprout_rng: RandomNumberGenerator = null  # 惰性派生（run_seed+floor+实例 id）
var _last_firerain: Array = []                 # 最近一轮火雨区引用（测试帧注入接缝）


func _engage(frame: int) -> void:
	_tick_pending_sprouts(frame)
	var speed := float(row.get("speed", 0))
	if speed > 0.0:
		var to_player := _player_pos() - brain_pos
		if to_player.length_squared() > 0.0001:
			brain_pos += to_player.normalized() * (speed / TimeConst.FPS)
	match _phase:
		"idle":
			_phase = "windup"
			_phase_left = _windup_ticks(30)
			Fx.on_enemy_hit(self, {"telegraph": true})
		"windup":
			_phase_left -= 1
			if _phase_left <= 0:
				_fire_volley(frame)
				_phase = "cool"
				_phase_left = _attack_cooldown_ticks(108)
		"cool":
			_phase_left -= 1
			if _phase_left <= 0:
				_phase = "windup"
				_phase_left = _windup_ticks(30)
				Fx.on_enemy_hit(self, {"telegraph": true})


func _fire_volley(frame: int) -> void:
	if int(row.get("firerain_count", 0)) > 0:
		_cast_firerain(frame)
		return
	if bool(row.get("mimic_weapon", false)):
		var mimic := SignatureMoves.mimic_volley_params(row, _player_weapon_row())
		if not mimic.is_empty():
			_fire_mimic_volley(frame, mimic)
			return
	fired_this_tick = true
	if combat == null:
		return
	var count := int(row.get("volley_count", DEFAULT_VOLLEY_COUNT))
	var element := _volley_element()
	var dirs := _volley_dirs(count)
	for i in dirs.size():
		var dir: Vector2 = dirs[i]
		var cfg := {
			"pos": brain_pos, "vel": dir * enemy_bullet_speed(95.0),
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": element, "pierce": 0, "bounce": 0,
			"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
			"radius": float(row.get("bullet_radius", 4.0)),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))), "attack_name": "弹幕齐射",
		}
		var slow := float(row.get("slow_pct", 0.0))
		if slow > 0.0:
			cfg["slow_pct"] = slow
			cfg["slow_ticks"] = int(row.get("slow_ticks", 60))
		if bool(row.get("arc_shot", false)):
			_spawn_arc_bullet(cfg, dir, frame)
		else:
			combat.spawn_projectile(cfg)


## 齐射方向集（ring / 默认扇面；mimic 用武器弹数与散射重排同结构）。
func _volley_dirs(count: int) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	if String(row.get("volley_mode", "")) == "ring":
		for i in count:
			dirs.append(Vector2.from_angle(TAU * float(i) / float(count)))
	else:
		var base_dir := (_player_pos() - brain_pos).normalized()
		if base_dir == Vector2.ZERO:
			base_dir = Vector2.RIGHT
		var spread := deg_to_rad(float(row.get("volley_spread_deg", DEFAULT_SPREAD_DEG)))
		for i in count:
			var ang := -spread / 2.0 + spread * float(i) / float(maxi(count - 1, 1))
			dirs.append(base_dir.rotated(ang))
	return dirs


## m4-c1 抛物弹（种子投手）：落点=沿弹方向的解算点；同时排程落地生怪掷签。
func _spawn_arc_bullet(cfg: Dictionary, dir: Vector2, frame: int) -> void:
	var speed := float(cfg["vel"].length())
	if speed <= 0.0:
		combat.spawn_projectile(cfg)
		return
	var reach := minf(_player_pos().distance_to(brain_pos),
		SignatureMoves.lob_range_cap(speed, float(cfg["life_seconds"])))
	var target := brain_pos + dir * reach
	var lob := SignatureMoves.lob_solution(brain_pos, target, speed)
	if lob.is_empty():
		combat.spawn_projectile(cfg)
		return
	cfg["vel"] = lob["vel"]
	cfg["arc_dir"] = lob["arc_dir"]
	cfg["arc_gravity"] = lob["arc_gravity"]
	cfg["attack_name"] = "抛物种子"
	combat.spawn_projectile(cfg)
	_schedule_sprout(frame, target, int(lob["flight_ticks"]))


## 落地生怪掷签（30% 生 1 苦力虫；per-投手存活上限防溢出——房间可清不变量红线）。
func _schedule_sprout(frame: int, pos: Vector2, flight_ticks: int) -> void:
	if String(row.get("impact_spawn_row", "")) == "":
		return
	if _sprout_rng == null:
		_sprout_rng = RngSvc.stream(RunState.floor_idx, "sig_impact_spawn")
		_sprout_rng.seed = RngSvc.stable_hash(int(_sprout_rng.seed), get_instance_id())
	var chance := float(row.get("impact_spawn_chance", 0.0))
	var rolled := chance > 0.0 and _sprout_rng.randf() < chance
	_pending_sprouts.append({
		"due_frame": frame + maxi(flight_ticks, 1),
		"pos": pos,
		"rolled": rolled,
	})


func _tick_pending_sprouts(frame: int) -> void:
	if _pending_sprouts.is_empty():
		return
	var remain: Array[Dictionary] = []
	for p: Dictionary in _pending_sprouts:
		if frame < int(p["due_frame"]):
			remain.append(p)
			continue
		if not bool(p["rolled"]) or not spawn_callback.is_valid():
			continue                    # 未中签 / 脑层测试无回调：种子落地不出苗
		if not _sprout_under_cap():
			continue                    # 上限防爆：活苗满员时种子哑火（不变量红线）
		var child: Node = spawn_callback.call(String(row["impact_spawn_row"]),
			p["pos"], {})
		if child != null:
			_sprout_alive.append(child)
			Telemetry.log_row(["seed_sprout", frame, String(row["impact_spawn_row"]),
				_sprout_alive_count()], String(row.get("id", "")))
	_pending_sprouts = remain


## 活苗计数（引用失效或已死不计——上限语义为「同时存活」）。
func _sprout_alive_count() -> int:
	var n := 0
	for c: Variant in _sprout_alive:
		var node: Node = c
		if node != null and is_instance_valid(node) \
				and int(node.get("state")) != EnemyBase.State.DEAD:
			n += 1
	# 顺手压实（死体引用清出，数组不随局单调膨胀）
	_sprout_alive = _sprout_alive.filter(func(c: Variant) -> bool:
		var node: Node = c
		return node != null and is_instance_valid(node) \
			and int(node.get("state")) != EnemyBase.State.DEAD)
	return n


func _sprout_under_cap() -> bool:
	var cap := int(row.get("impact_spawn_cap", 0))
	if cap <= 0:
		return false                   # 无上限键 = 不生苗（fail-closed）
	return _sprout_alive_count() < cap


## m4-c1 模仿武器齐射：弹形五键来自玩家武器（伤害/来源保持行口径），命中判定同敌弹。
func _fire_mimic_volley(frame: int, mimic: Dictionary) -> void:
	fired_this_tick = true
	if combat == null:
		return
	var base_dir := (_player_pos() - brain_pos).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	var count := int(mimic["projectiles"])
	var spread := deg_to_rad(float(mimic["spread_deg"]))
	for i in count:
		var ang := -spread / 2.0 + spread * float(i) / float(maxi(count - 1, 1))
		combat.spawn_projectile({
			"pos": brain_pos, "vel": base_dir.rotated(ang) * float(mimic["bullet_speed"]),
			"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.ENEMY,
			"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
			"life_seconds": float(mimic["bullet_life"]),
			"radius": float(mimic["bullet_radius"]),
			"source_type": "projectile", "source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))),
			"attack_name": "模仿弹幕",
		})
	Telemetry.log_row(["enemy_mimic_shot", frame, count], String(row.get("id", "")))


## m4-c1 火雨区（火雨祭司）：以玩家当前位置为心的确定性散布 N 区
## （区 i 圆心 = 玩家位 + from_angle(TAU·i/N + 0.5)·spread·0.6，首区压玩家位）。
## 延迟 ≥21t（§7.5 0.35s，schema fail-closed 钉域）；一次齐射一报遥测。
func _cast_firerain(frame: int) -> void:
	fired_this_tick = true
	var count := int(row.get("firerain_count", 1))
	var radius := float(row.get("firerain_radius", 30.0))
	var spread := float(row.get("firerain_spread_px", 0.0))
	var center := _player_pos()
	_last_firerain = []
	for i in count:
		var pos := center
		if i > 0:
			pos += Vector2.from_angle(TAU * float(i) / float(count) + 0.5) * (spread * 0.6)
		var zone := FirerainZone.new()
		zone.setup({
			"pos": pos, "radius": radius,
			"dmg": int(row.get("firerain_dmg", 0)),
			"ticks": int(row.get("firerain_delay_ticks", 36)),
			"player": player_ref,
			"source_id": String(row.get("id", "")),
			"source_name": String(row.get("name", row.get("id", ""))),
		})
		_last_firerain.append(zone)
		if combat != null:
			combat.add_child(zone)
		elif is_inside_tree():
			get_tree().current_scene.add_child(zone)
		# 无处挂载（纯脑层测试）：不挂树，测试经 _last_firerain + tick() 直驱结算
	Telemetry.log_row(["firerain_strike", frame, count], String(row.get("id", "")))


func _volley_element() -> int:
	if not bool(row.get("element_rotate", false)):
		return Elements.Id.NONE
	var element: int = ROTATE_ELEMENTS[_volley_index % ROTATE_ELEMENTS.size()]
	_volley_index += 1
	return element
