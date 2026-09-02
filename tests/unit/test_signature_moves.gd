class_name TestSignatureMoves
extends GdUnitTestSuite

## M4-C1 敌人派味特技 ×11 脑层注入帧测试（沿用 test_vine_colossus / test_enemy_ai 手法）：
## 龟缩周期免疫窗 / 抛物弹落点 / 水洼提速+玩家减速 / 落地生怪掷签+上限 / 拉拽位移 /
## 钳击扇区 / 偷币+死亡返还 / 模仿武器弹形 / 电弧链元素弹 / 两段扑咬 / 火雨区延迟结算。
## 外加 SignatureMoves 纯函数与 SignatureSchema fail-closed 校验（数据键全量登记钉死）。

const FRAME := 20000            # 注入帧基准（远离 0，同 test_boss_base）

var _coins_backup := -1


func before_test() -> void:
	_coins_backup = RunState.coins
	PuddleZone.clear()          # 静态注册表跨套件隔离


func after_test() -> void:
	RunState.coins = _coins_backup
	PuddleZone.clear()


# ---- 替身 ----

class SpyPlayer extends Node2D:
	var hits: Array = []
	var brain_pos := Vector2.ZERO
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)


## 拉拽/水洼减速共用替身：apply_pull 接缝 + splitter 读的 player 子体。
class PullProxy extends Node2D:
	var brain_pos := Vector2.ZERO
	var hits: Array = []
	var invincible := false
	var pulls: Array = []          # 接受的拉拽目标点
	var pull_calls := 0            # 全部尝试（含被无敌帧拒绝的）
	var player: Node2D = null      # splitter 玩家减速半边读 player_ref.get("player")
	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx)
	func apply_pull(target: Vector2) -> bool:
		pull_calls += 1
		if invincible:
			return false
		brain_pos = target
		pulls.append(target)
		return true


## 模仿武器读缝替身：current_weapon_row 返回可配置武器行。
class MimicProxy extends Node2D:
	var brain_pos := Vector2.ZERO
	var weapon_row := {}
	func take_hit(_ctx: Dictionary) -> void:
		pass
	func current_weapon_row() -> Dictionary:
		return weapon_row


## 水洼玩家减速半边读的玩家实体（incoming_slow_pct 既有接缝）。
class SlowBody extends Node2D:
	var incoming_slow_pct := 0.0
	var incoming_slow_until := -1


## 落地生怪替身幼体（存活计数读 state 属性）。
class MockSprout extends Node:
	var state: int = EnemyBase.State.ENGAGE


func _mk_combat(salt: String) -> CombatSystem:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := CombatSystem.new(root, RngSvc.stream(0, salt))
	root.add_child(cs)
	return cs


func _drive(e: EnemyBase, from: int, to: int) -> void:
	for f in range(from, to + 1):
		_now_frame = f
		e.brain_tick(f)


## ALERT 24t 后进 ENGAGE；返回转换拍（_on_engage_start 拍）。
func _engage_tick(e: EnemyBase) -> int:
	e.on_player_seen(FRAME)
	_drive(e, FRAME + 1, FRAME + 24)
	return FRAME + 24


func _ctx(amount: int, from: Vector2, frame: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE,
		"from": from, "frame": frame}


# ==================== SignatureSchema：fail-closed 校验 ====================

func test_schema_full_table_passes() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
	assert_bool(parsed is Dictionary and (parsed as Dictionary).size() > 0).is_true()
	var errors := SignatureSchema.validate_table(parsed)
	assert_int(errors.size()).is_equal(0)


func test_schema_missing_required_key_rejected() -> void:
	var errors := SignatureSchema.validate_row({"id": "x", "archetype": "heavy"})
	assert_bool(errors.size() > 0).is_true()


func test_schema_type_mismatches_rejected() -> void:
	var bad_bool := SignatureSchema.validate_row(
		{"id": "x", "name": "x", "archetype": "turret", "hp": 10, "radius": 6.0,
			"arc_shot": "yes"})
	var bad_frac_int := SignatureSchema.validate_row(
		{"id": "x", "name": "x", "archetype": "heavy", "hp": 10, "radius": 6.0,
			"shell_walk_ticks": 1.5})
	assert_bool(bad_bool.has("type mismatch: arc_shot want bool")).is_true()
	assert_bool(bad_frac_int.has("type mismatch: shell_walk_ticks want int")).is_true()


func test_schema_telegraph_minimum_enforced() -> void:
	# GDD §7.5：区/扫击生成前预警 ≥0.35s（21t）——低值拒收，21t 恰好放行。
	var low_claw := SignatureSchema.validate_row(
		{"id": "x", "name": "x", "archetype": "heavy", "hp": 10, "radius": 6.0,
			"claw_windup_ticks": 20})
	var ok_claw := SignatureSchema.validate_row(
		{"id": "x", "name": "x", "archetype": "heavy", "hp": 10, "radius": 6.0,
			"claw_windup_ticks": 21})
	assert_bool(low_claw.is_empty()).is_false()
	assert_bool(ok_claw.is_empty()).is_true()
	var low_rain := SignatureSchema.validate_row(
		{"id": "x", "name": "x", "archetype": "barrage", "hp": 10, "radius": 6.0,
			"firerain_delay_ticks": 10})
	assert_bool(low_rain.is_empty()).is_false()


func test_schema_semantic_domains_rejected() -> void:
	var rows := [
		{"id": "x", "name": "x", "archetype": "splitter", "hp": 10, "radius": 6.0,
			"puddle_speed_mult": 0.9},                       # 提速倍率 <1
		{"id": "x", "name": "x", "archetype": "barrage", "hp": 10, "radius": 6.0,
			"impact_spawn_chance": 1.0},                     # 概率须在 (0,1)
		{"id": "x", "name": "x", "archetype": "suicide", "hp": 10, "radius": 6.0,
			"steal_coins": 0},                               # 偷币额须 >0
		{"id": "x", "name": "x", "archetype": "charger", "hp": 10, "radius": 6.0,
			"bite_stages": 1},                               # 两段咬须 ≥2
		{"id": "x", "name": "x", "archetype": "orbiter", "hp": 10, "radius": 6.0,
			"bullet_element": "none"},                       # none 无行为意义
		{"id": "x", "name": "x", "archetype": "heavy", "hp": 10, "radius": 6.0,
			"claw_arc_deg": 361.0},                          # 扇区角 ≤360
		{"id": "x", "name": "x", "archetype": "barrage", "hp": 10, "radius": 6.0,
			"firerain_spread_px": -1.0},                     # 散布 ≥0
	]
	for row: Dictionary in rows:
		assert_bool(SignatureSchema.validate_row(row).is_empty()).is_false()


func test_schema_impact_spawn_row_cross_reference() -> void:
	var table := {
		"pitcher": {"id": "pitcher", "name": "x", "archetype": "barrage", "hp": 10,
			"radius": 6.0, "impact_spawn_row": "ghost_child"},
	}
	var errors := SignatureSchema.validate_table(table)     # ghost_child 不在表内
	assert_bool(errors.is_empty()).is_false()
	table["ghost_child"] = {"id": "ghost_child", "name": "x", "archetype": "suicide",
		"hp": 5, "radius": 4.0}
	assert_int(SignatureSchema.validate_table(table).size()).is_equal(0)


func test_data_wiring_11_rows_carry_signature_keys() -> void:
	# 11 行为的 data 驱动键逐值钉死（enemies.json 数值修订会被此测试拦住重审）。
	var expect := {
		"hardshell_turtle": {"shell_walk_ticks": 210, "shell_up_ticks": 90},
		"thorn_turret": {"arc_shot": true},
		"moss_slime": {"puddle_interval_ticks": 240, "puddle_radius": 22.0,
			"puddle_life_seconds": 6.0, "puddle_speed_mult": 1.5,
			"puddle_player_slow_pct": 0.3},
		"seed_pitcher": {"arc_shot": true, "impact_spawn_row": "kuli_bug",
			"impact_spawn_chance": 0.3, "impact_spawn_cap": 3},
		"magnet_golem": {"pull_range_px": 96.0, "pull_px": 32.0,
			"pull_cd_ticks": 180, "pull_windup_ticks": 30},
		"frost_crab": {"claw_dmg": 15, "claw_range_px": 46.0, "claw_arc_deg": 120.0,
			"claw_cd_ticks": 240, "claw_windup_ticks": 30},
		"crystal_rat": {"steal_coins": 5},
		"echo_lurker": {"mimic_weapon": true},
		"ghost_jelly": {"bullet_element": "shock"},
		"lava_hound": {"bite_stages": 2, "bite_gap_ticks": 18, "bite_element": "fire"},
		"firerain_priest": {"firerain_count": 3, "firerain_radius": 30.0,
			"firerain_dmg": 8, "firerain_delay_ticks": 36, "firerain_spread_px": 70.0},
	}
	for id: String in expect:
		var row := GameDB.get_enemy(id)
		for key: String in expect[id]:
			var want: Variant = expect[id][key]
			assert_bool(row.has(key))
			if typeof(want) == TYPE_BOOL:
				assert_bool(bool(row.get(key))).is_equal(want)
			elif typeof(want) == TYPE_STRING:
				assert_str(String(row.get(key))).is_equal(want)
			else:
				assert_float(float(row.get(key))).is_equal_approx(float(want), 0.0001)


# ==================== SignatureMoves：抛物解算 / 模仿弹形纯函数 ====================

func test_lob_solution_exact_values() -> void:
	# dist 64 / speed 96 → g = 96²/(2·64) = 72；T = 2·64/96·60 = 80t；vel = dir·96。
	var lob := SignatureMoves.lob_solution(Vector2.ZERO, Vector2(64, 0), 96.0)
	assert_float(float(lob["arc_gravity"])).is_equal_approx(72.0, 0.0001)
	assert_int(int(lob["flight_ticks"])).is_equal(80)
	assert_vector(lob["vel"]).is_equal_approx(Vector2(96, 0), Vector2(0.0001, 0.0001))
	assert_vector(lob["arc_dir"]).is_equal_approx(Vector2(1, 0), Vector2(0.0001, 0.0001))


func test_lob_solution_min_range_and_zero_speed_return_empty() -> void:
	assert_dict(SignatureMoves.lob_solution(Vector2.ZERO, Vector2(5, 0), 96.0)).is_empty()
	assert_dict(SignatureMoves.lob_solution(Vector2.ZERO, Vector2(64, 0), 0.0)).is_empty()


func test_lob_range_cap_by_bullet_life() -> void:
	# 全停弧线全程 T = 2|Δ|/v0 ≤ 寿命 → |Δ| ≤ v0·life/2。
	assert_float(SignatureMoves.lob_range_cap(110.0, 2.5)).is_equal_approx(137.5, 0.0001)
	assert_float(SignatureMoves.lob_range_cap(0.0, 2.5)).is_equal_approx(0.0, 0.0001)


func test_mimic_volley_params_copies_and_clamps() -> void:
	var weapon := {"projectiles": 12, "spread_deg": 120.0, "bullet_speed": 300.0,
		"bullet_radius": 9.0, "bullet_life": 5.0}
	var m := SignatureMoves.mimic_volley_params({"id": "echo_lurker"}, weapon)
	assert_int(int(m["projectiles"])).is_equal(8)        # 弹数上限 8（防预算打穿）
	assert_float(float(m["spread_deg"])).is_equal_approx(90.0, 0.0001)
	assert_float(float(m["bullet_speed"])).is_equal_approx(150.0, 0.0001)  # §7.5 上限
	assert_float(float(m["bullet_radius"])).is_equal_approx(6.0, 0.0001)
	assert_float(float(m["bullet_life"])).is_equal_approx(3.0, 0.0001)
	var low := SignatureMoves.mimic_volley_params({"id": "x"},
		{"projectiles": 1, "spread_deg": 0.1, "bullet_speed": 10.0,
			"bullet_radius": 0.5, "bullet_life": 0.2})
	assert_int(int(low["projectiles"])).is_equal(1)
	assert_float(float(low["spread_deg"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(low["bullet_speed"])).is_equal_approx(60.0, 0.0001)  # 下限 60 可玩
	assert_float(float(low["bullet_radius"])).is_equal_approx(2.0, 0.0001)
	assert_float(float(low["bullet_life"])).is_equal_approx(0.6, 0.0001)


func test_mimic_volley_params_melee_or_empty_weapon_return_empty() -> void:
	assert_dict(SignatureMoves.mimic_volley_params({"id": "x"},
		{"is_melee": true, "projectiles": 3})).is_empty()
	assert_dict(SignatureMoves.mimic_volley_params({"id": "x"}, {})).is_empty()


# ==================== ① 硬壳龟：龟缩周期免疫窗 ====================

func test_turtle_shell_cycle_walk_immunity_walk() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["hardshell_turtle"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(400, 0)                      # 远距：行走窗内追不上（面向不翻转）
	e.player_ref = spy
	var e0 := _engage_tick(e)                            # 转换拍 E：行走窗 E+1..E+210
	var pos_walk_end: Vector2 = Vector2.ZERO
	_drive(e, e0 + 1, e0 + 100)
	assert_int(e.hp).is_equal(45)
	e.take_hit(_ctx(10, e.brain_pos + Vector2(-10, 0), e0 + 100))   # 背面：全伤
	assert_int(e.hp).is_equal(35)
	_drive(e, e0 + 101, e0 + 210)
	pos_walk_end = e.brain_pos
	_drive(e, e0 + 211, e0 + 250)                        # 缩壳窗 E+211..E+300
	assert_vector(e.brain_pos).is_equal_approx(pos_walk_end, Vector2(0.001, 0.001))  # 停走
	e.take_hit(_ctx(10, e.brain_pos + Vector2(-10, 0), e0 + 250))   # 缩壳：全向免疫
	assert_int(e.hp).is_equal(35)
	e.take_hit(_ctx(10, e.brain_pos + Vector2(10, 0), e0 + 250))    # 正面来弹同样免疫
	assert_int(e.hp).is_equal(35)
	_drive(e, e0 + 301, e0 + 400)                        # 第二行走窗恢复移动+受击
	assert_bool(e.brain_pos.distance_to(pos_walk_end) > 0.5).is_true()
	e.take_hit(_ctx(10, e.brain_pos + Vector2(-10, 0), e0 + 400))
	assert_int(e.hp).is_equal(25)


func test_turtle_front_block_still_applies_outside_shell() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["hardshell_turtle"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 50)                           # 行走窗内：正面减伤 0.8 叠加语义不变
	e.take_hit(_ctx(10, e.brain_pos + Vector2(10, 0), e0 + 50))     # 正面：10×0.2 = 2
	assert_int(e.hp).is_equal(43)


# ==================== ② 荆棘炮台：抛物弹 ====================

func test_thorn_turret_arc_bullets_land_on_target() -> void:
	var cs := _mk_combat("sig_thorn")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["thorn_turret"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 45)                           # windup 30 → 首发 E+31，3 连发至 E+43
	assert_int(cs.active_count()).is_equal(3)
	var p0: Projectile = cs.pool.active[0]
	assert_str(p0.attack_name).is_equal("抛物弹")
	assert_float(p0.vel.length()).is_equal_approx(110.0, 0.01)
	var to_player: Vector2 = spy.brain_pos - e.brain_pos
	assert_vector(p0.arc_dir).is_equal_approx(to_player.normalized(),
		Vector2(0.001, 0.001))
	# g = v0²/(2·dist)：全停落点=发射拍玩家位置
	assert_float(p0.arc_gravity).is_equal_approx(110.0 * 110.0 / (2.0 * 100.0), 0.001)
	# 逐拍模拟：速度耗尽拍=落点，与解算目标偏差 ≤1px（离散化半拍内）
	var ticks := 0
	while p0.tick():
		ticks += 1
	assert_int(ticks).is_equal(109)                      # round(2·100/110·60) = 109
	assert_float(p0.position.distance_to(spy.brain_pos)).is_less(1.5)


func test_thorn_turret_close_range_falls_back_to_straight_bullet() -> void:
	var cs := _mk_combat("sig_thorn_close")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["thorn_turret"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(5, 0)                        # < MIN_LOB_RANGE_PX 8：贴身不抛物
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)
	assert_int(cs.active_count()).is_equal(1)
	var p0: Projectile = cs.pool.active[0]
	assert_str(p0.attack_name).is_equal("弹幕")          # 直线弹回退（attack_name 未改写）
	assert_float(p0.arc_gravity).is_equal_approx(0.0, 0.0001)
	assert_vector(p0.arc_dir).is_equal_approx(Vector2.ZERO, Vector2(0.0001, 0.0001))


# ==================== ③ 苔藓史莱姆：水洼提速 / ④ 死亡落洼 ====================

func test_puddle_zone_registry_lifecycle_and_cap() -> void:
	var z := PuddleZone.spawn(null, {"pos": Vector2(0, 0), "radius": 20.0,
		"until_frame": 1000, "speed_mult": 1.5, "player_slow_pct": 0.3})
	auto_free(z)
	assert_object(PuddleZone.zone_at(Vector2(0, 0), 500)).is_not_null()
	assert_object(PuddleZone.zone_at(Vector2(20, 0), 500)).is_not_null()   # 半径内含边界
	assert_object(PuddleZone.zone_at(Vector2(25, 0), 500)).is_null()       # 域外
	PuddleZone.prune(1000)                               # 帧基过期：到点自净
	assert_int(PuddleZone.active_count()).is_equal(0)
	assert_object(PuddleZone.zone_at(Vector2(0, 0), 1001)).is_null()       # 过期区不再返回
	for i in range(24):                                  # 全局活区上限 24：超限淘汰最旧
		var zi := PuddleZone.spawn(null, {"pos": Vector2(float(i) * 100.0, 500.0),
			"radius": 10.0, "until_frame": 5000})
		auto_free(zi)
	assert_int(PuddleZone.active_count()).is_equal(24)
	var extra := PuddleZone.spawn(null, {"pos": Vector2(9999, 500.0), "radius": 10.0,
		"until_frame": 5000})
	auto_free(extra)
	assert_int(PuddleZone.active_count()).is_equal(24)   # 淘汰最旧而非无限增长


func test_moss_slime_drops_puddle_and_speeds_up_inside() -> void:
	var cs := _mk_combat("sig_puddle")                   # 区挂 combat：随 root 释放不泄漏
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["moss_slime"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	var pos0: Vector2 = e.brain_pos
	_drive(e, e0 + 1, e0 + 1)
	assert_int(PuddleZone.active_count()).is_equal(1)    # ENGAGE 首拍脚下落洼
	var pos1: Vector2 = e.brain_pos
	# 洼外首拍基速 40/60 = 0.667px（落洼发生在本拍移动之后，首拍不提速）
	assert_float(pos1.distance_to(pos0)).is_equal_approx(40.0 / 60.0, 0.001)
	_drive(e, e0 + 2, e0 + 2)
	var pos2: Vector2 = e.brain_pos
	assert_float(pos2.distance_to(pos1)).is_equal_approx(40.0 * 1.5 / 60.0, 0.001)  # 洼内 ×1.5


func test_moss_slime_puddle_slows_player_inside_only() -> void:
	var cs := _mk_combat("sig_puddle_slow")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["moss_slime"]))
	e.combat = cs
	var body: SlowBody = auto_free(SlowBody.new())
	var proxy: PullProxy = auto_free(PullProxy.new())
	proxy.player = body
	proxy.brain_pos = Vector2(60, 0)
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 1)                            # 洼落在本拍末的 brain_pos
	body.global_position = e.brain_pos                   # 玩家站进水洼
	_drive(e, e0 + 2, e0 + 2)
	assert_float(body.incoming_slow_pct).is_equal_approx(0.3, 0.0001)
	assert_int(body.incoming_slow_until).is_greater_equal(e0 + 2)
	var until_before := body.incoming_slow_until
	body.global_position = Vector2(5000, 0)              # 出域：不再续窗
	_drive(e, e0 + 3, e0 + 3)
	assert_int(body.incoming_slow_until).is_equal(until_before)


func test_moss_slime_death_drops_final_puddle() -> void:
	var cs := _mk_combat("sig_puddle_die")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["moss_slime"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(60, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 2)
	assert_int(PuddleZone.active_count()).is_equal(1)
	e.die()                                              # 苔藓破裂留水（死亡再落一洼）
	assert_int(PuddleZone.active_count()).is_equal(2)


# ==================== ⑤ 磁石傀儡：拉拽 ====================

func test_magnet_golem_pulls_player_32px_on_cycle() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["magnet_golem"]))
	var proxy: PullProxy = auto_free(PullProxy.new())
	proxy.brain_pos = Vector2(80, 0)
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 32)                           # windup 30 → 拉在 E+31
	assert_int(proxy.pulls.size()).is_equal(1)
	assert_vector(proxy.pulls[0]).is_equal_approx(Vector2(48, 0),
		Vector2(0.0001, 0.0001))                             # 向傀儡位移恰 32px（2 格）
	assert_int(proxy.pull_calls).is_equal(1)
	proxy.brain_pos = Vector2(500, 0)                    # 拉后瞬移出射程（隔离后续拉拽）
	_drive(e, e0 + 33, e0 + 212)                         # 冷却 150 → 下一预警 E+182、执行 E+211
	assert_int(proxy.pulls.size()).is_equal(1)           # 射程外不拉
	assert_str(String(e.get("_pull_phase"))).is_equal("cool")   # 周期照常推进（180t 节拍）


func test_magnet_golem_pull_ignores_out_of_range() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["magnet_golem"]))
	var proxy: PullProxy = auto_free(PullProxy.new())
	proxy.brain_pos = Vector2(300, 0)                    # 96px 射程外
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 40)
	assert_int(proxy.pull_calls).is_equal(0)


func test_magnet_golem_pull_respects_player_invincible_window() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["magnet_golem"]))
	var proxy: PullProxy = auto_free(PullProxy.new())
	proxy.brain_pos = Vector2(80, 0)
	proxy.invincible = true                              # 受击硬直/翻滚窗：不可被拉动
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 32)
	assert_int(proxy.pull_calls).is_equal(1)
	assert_int(proxy.pulls.size()).is_equal(0)           # 接缝拒绝 → 无位移
	assert_vector(proxy.brain_pos).is_equal_approx(Vector2(80, 0),
		Vector2(0.0001, 0.0001))


func test_magnet_golem_pull_target_clamped_to_room_bounds() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["magnet_golem"]))
	e.combat_bounds = Rect2(0, 0, 40, 40)                # 玩家名义半径 6 内域
	var proxy: PullProxy = auto_free(PullProxy.new())
	proxy.brain_pos = Vector2(30, 0)
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 32)
	assert_int(proxy.pulls.size()).is_equal(1)
	assert_vector(proxy.pulls[0]).is_equal_approx(Vector2(6, 6),
		Vector2(0.0001, 0.0001))                             # 出界目标钳回内域（双轴 inset 6）


# ==================== ⑥ 冻土巨蟹：钳击横扫 ====================

func test_frost_crab_claw_sweep_hits_locked_sector_for15_ice() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["frost_crab"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(40, 0)                       # 46+6 射程内、扇区内
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 32)                           # windup 30 → 横扫 E+31
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(int(spy.hits[0]["amount"])).is_equal(15)
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.ICE)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("钳击横扫")
	assert_str(String(spy.hits[0]["source_type"])).is_equal("melee_enemy")
	assert_str(String(e.get("_claw_phase"))).is_equal("cool")
	_drive(e, e0 + 33, e0 + 240)
	assert_str(String(e.get("_claw_phase"))).is_equal("cool")   # cd 240−30=210，未回预警
	_drive(e, e0 + 241, e0 + 241)
	assert_str(String(e.get("_claw_phase"))).is_equal("windup") # 240t 节拍回预警


func test_frost_crab_claw_sector_locked_at_windup_start_is_dodgeable() -> void:
	# 预警扇区在 windup 起始拍锁定：预警内离开扇区/射程即躲（task-9「预警扇区」语义）。
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["frost_crab"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(40, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 10)                           # 预警起始锁定面向 (+1,0)
	spy.brain_pos = Vector2(20, 45)                      # 预警内闪出扇区：偏角 66° > 60°
	_drive(e, e0 + 11, e0 + 32)
	assert_int(spy.hits.size()).is_equal(0)              # 横扫落空（扇区语义可躲）
	var e2: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["frost_crab"]))
	var spy2: SpyPlayer = auto_free(SpyPlayer.new())
	spy2.brain_pos = Vector2(40, 0)
	e2.player_ref = spy2
	var e02 := _engage_tick(e2)
	_drive(e2, e02 + 1, e02 + 10)
	spy2.brain_pos = Vector2(70, 0)                      # 预警内闪出射程：>46+6
	_drive(e2, e02 + 11, e02 + 32)
	assert_int(spy2.hits.size()).is_equal(0)             # 射程外同样落空


# ==================== ⑦ 窃晶鼠群：偷币 + 死亡返还 ====================

func test_crystal_rat_steals_5_coins_then_flees() -> void:
	RunState.coins = 20
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["crystal_rat"]))
	e.brain_pos = Vector2(100, 0)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 400)                          # 接触 <14px 即窃（约 E+48）
	assert_int(RunState.coins).is_equal(15)              # 窃走 min(20, 5)
	assert_int(int(e.get("_fuse_deadline"))).is_equal(-1)   # 得手不点燃引信
	assert_bool(bool(e.get("_fleeing"))).is_true()
	assert_float(e.brain_pos.distance_to(spy.brain_pos)).is_greater(300.0)  # 背向全速离场
	assert_int(e.state).is_not_equal(EnemyBase.State.DEAD)  # 仍可被击杀（房间可清不变量）


func test_crystal_rat_death_refunds_stolen_coins() -> void:
	RunState.coins = 20
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["crystal_rat"]))
	e.brain_pos = Vector2(100, 0)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 400)
	assert_int(RunState.coins).is_equal(15)
	e.take_hit(_ctx(100, Vector2.ZERO, e0 + 500))        # 击杀 → 全额返还
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(RunState.coins).is_equal(20)              # 偷币永不净损失


func test_crystal_rat_with_empty_purse_keeps_fuse_explode() -> void:
	RunState.coins = 0                                   # 窃不到 → 原自爆行为不变
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["crystal_rat"]))
	e.brain_pos = Vector2(100, 0)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 100)                          # 接触 E+48 点引信，E+78 自爆
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(int(spy.hits[0]["amount"])).is_equal(6)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("自爆")


func test_crystal_rat_partial_steal_when_poorer_than_steal_amount() -> void:
	RunState.coins = 3
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["crystal_rat"]))
	e.brain_pos = Vector2(100, 0)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(0, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 400)
	assert_int(RunState.coins).is_equal(0)               # min(3, 5) = 3 全窃
	assert_bool(bool(e.get("_fleeing"))).is_true()


# ==================== ⑧ 深窟回响者：模仿武器弹形 ====================

func test_echo_lurker_mimics_player_weapon_volley_shape() -> void:
	var cs := _mk_combat("sig_mimic")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["echo_lurker"]))
	e.combat = cs
	var proxy: MimicProxy = auto_free(MimicProxy.new())
	proxy.brain_pos = Vector2(100, 0)
	proxy.weapon_row = {"projectiles": 4, "spread_deg": 20.0, "bullet_speed": 200.0,
		"bullet_radius": 2.5, "bullet_life": 1.0}
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)                           # windup 30 → E+31 齐射
	assert_int(cs.active_count()).is_equal(4)            # 弹数=玩家武器（≤8）
	for p: Projectile in cs.pool.active:
		assert_int(int(p.damage)).is_equal(5)            # 伤害保持行口径
		assert_float(p.vel.length()).is_equal_approx(150.0, 0.01)   # 弹速封顶 150
		assert_float(p.radius).is_equal(2.5)
		assert_int(int(p.life_ticks)).is_equal(60)       # life 1.0s
		assert_str(p.attack_name).is_equal("模仿弹幕")
		assert_int(int(p.faction)).is_equal(Projectile.Faction.ENEMY)   # 阵营不变


func test_echo_lurker_falls_back_to_default_fan_without_weapon() -> void:
	var cs := _mk_combat("sig_mimic_fb")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["echo_lurker"]))
	e.combat = cs
	var proxy: MimicProxy = auto_free(MimicProxy.new())
	proxy.brain_pos = Vector2(100, 0)
	proxy.weapon_row = {}                                # 无武器行（近战/空槽/无接缝）
	e.player_ref = proxy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)
	assert_int(cs.active_count()).is_equal(3)            # 默认扇弹 volley_count 3
	for p: Projectile in cs.pool.active:
		assert_str(p.attack_name).is_equal("弹幕齐射")
		assert_float(p.vel.length()).is_equal_approx(110.0, 0.01)


# ==================== ⑨ 幽光水母：电弧链（元素弹归因） ====================

func test_ghost_jelly_fires_shock_element_bullet() -> void:
	var cs := _mk_combat("sig_jelly")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["ghost_jelly"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(140, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)                           # 绕行中周期开火：windup 30
	assert_int(cs.active_count()).is_equal(1)
	assert_int(int(cs.pool.active[0].element)).is_equal(Elements.Id.SHOCK)
	assert_str(cs.pool.active[0].attack_name).is_equal("弹幕")


func test_bullet_element_absent_row_stays_none_element() -> void:
	var cs := _mk_combat("sig_wing")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["wing_lizard"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(110, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)
	assert_int(cs.active_count()).is_equal(1)
	assert_int(int(cs.pool.active[0].element)).is_equal(Elements.Id.NONE)   # 无键行零漂移


# ==================== ⑩ 熔岩犬：两段扑咬 ====================

func test_lava_hound_two_stage_bite_with_gap_and_fire_contact() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["lava_hound"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	var dash_starts: Array = []
	var positions := {}
	var prev_phase := ""
	for f in range(e0 + 1, e0 + 120):
		e.brain_tick(f)
		var phase := String(e.get("_phase"))
		if phase == "dash" and prev_phase != "dash":
			dash_starts.append(f)
		if phase == "bite_windup" and prev_phase != "bite_windup":
			positions["gap_start"] = e.brain_pos
		if phase == "dash" and prev_phase == "bite_windup":
			positions["gap_end"] = e.brain_pos
		prev_phase = phase
	assert_array(dash_starts).is_equal([e0 + 31, e0 + 73])   # dash1 → 段间短蓄 → dash2
	assert_vector(positions["gap_start"]).is_equal_approx(positions["gap_end"],
		Vector2(0.001, 0.001))                            # 段间短蓄 18t 不移动
	assert_int(int(e._contact_element())).is_equal(Elements.Id.FIRE)   # 扑咬燃烧归因


func test_charger_without_bite_keys_keeps_single_dash() -> void:
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["vine_charger"]))
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(200, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	var seen := {}
	for f in range(e0 + 1, e0 + 400):                    # 一个完整冷却周期以上
		e.brain_tick(f)
		seen[String(e.get("_phase"))] = true
	assert_bool(seen.has("dash")).is_true()
	assert_bool(seen.has("cool")).is_true()
	assert_bool(seen.has("bite_windup")).is_false()      # 无键行零漂移


# ==================== ⑪ 火雨祭司：火雨区（预警红圈） ====================

func test_firerain_priest_casts_three_telegraphed_zones_no_bullets() -> void:
	var cs := _mk_combat("sig_firerain")
	var e: EnemyBase = auto_free(EnemyFactory.create(GameDB.enemies["firerain_priest"]))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(70, 0)
	e.player_ref = spy
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 35)                           # windup 30 → E+31 施放
	assert_int(cs.active_count()).is_equal(0)            # 替换环形弹：零直线弹
	var zones: Array = e.get("_last_firerain")
	assert_int(zones.size()).is_equal(3)
	for z: FirerainZone in zones:
		assert_float(z.radius()).is_equal_approx(30.0, 0.0001)
		assert_int(z.remaining()).is_equal(36)           # 预警延迟（§7.5 ≥21t）
		assert_bool(z.is_inside_tree()).is_true()
	assert_vector((zones[0] as Node2D).position).is_equal_approx(spy.brain_pos,
		Vector2(0.0001, 0.0001))                          # 首区压玩家位
	for i in range(1, 3):
		assert_float((zones[i] as Node2D).position.distance_to(spy.brain_pos)) \
			.is_equal_approx(70.0 * 0.6, 0.001)          # 散布 42px > 半径 30（圈间可站）
	# 三区到点全爆：玩家仅被首区命中一次（散布区间距保安全位）
	var hit_frames: Array = []
	for t in range(36):
		for z: FirerainZone in zones:
			if is_instance_valid(z) and not z.is_queued_for_deletion():
				var before: int = spy.hits.size()
				z.tick()
				if spy.hits.size() > before:
					hit_frames.append(t)
	assert_int(spy.hits.size()).is_equal(1)
	assert_int(int(spy.hits[0]["amount"])).is_equal(8)
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.FIRE)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("火雨")
	assert_str(String(spy.hits[0]["source_id"])).is_equal("firerain_priest")
	assert_int(int(hit_frames[0])).is_equal(35)          # 恰在第 36 拍（延迟 36t）结算


func test_firerain_zone_detonates_after_delay_inside_radius() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(20, 0)
	var z := FirerainZone.new()
	holder.add_child(z)
	z.setup({"pos": Vector2(0, 0), "radius": 30.0, "dmg": 8, "ticks": 36,
		"player": spy, "source_id": "firerain_priest", "source_name": "火雨祭司"})
	for _i in range(35):
		z.tick()
	assert_int(spy.hits.size()).is_equal(0)              # 预警窗内零伤害
	z.tick()
	assert_int(spy.hits.size()).is_equal(1)              # 恰 36 拍结算
	assert_int(int(spy.hits[0]["amount"])).is_equal(8)
	assert_int(int(spy.hits[0]["element"])).is_equal(Elements.Id.FIRE)
	assert_str(String(spy.hits[0]["attack_name"])).is_equal("火雨")
	assert_bool(z.is_queued_for_deletion()).is_true()    # 一次性打击后自毁
	assert_float(z.radius()).is_equal_approx(30.0, 0.0001)


func test_firerain_zone_misses_player_outside_radius() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(100, 0)                      # 距区心 100 > 30
	var z := FirerainZone.new()
	holder.add_child(z)
	z.setup({"pos": Vector2(0, 0), "radius": 30.0, "dmg": 8, "ticks": 36,
		"player": spy, "source_id": "firerain_priest", "source_name": "火雨祭司"})
	for _i in range(36):
		z.tick()
	assert_int(spy.hits.size()).is_equal(0)
	assert_bool(z.is_queued_for_deletion()).is_true()    # 打空同样到期自毁


# ==================== ④' 种子投手：抛物 + 落地生怪（掷签/上限） ====================

const SPROUT_SEED := 20260902

var _now_frame := 0            # 驱动循环当前帧（回调捕获出苗拍用）


## chance=1.0 行替身（确定性掷签）：首波 3 弹出苗恰满 cap=3，落点=解算目标，此后哑火。
func test_seed_pitcher_sprouts_at_impact_under_cap() -> void:
	RngSvc.setup_run(SPROUT_SEED)
	var cs := _mk_combat("sig_sprout")
	var row: Dictionary = GameDB.enemies["seed_pitcher"].duplicate(true)
	row["impact_spawn_chance"] = 1.0                     # 确定性：每弹必中签
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(80, 0)
	e.player_ref = spy
	var calls: Array = []
	e.spawn_callback = func(row_id: String, pos: Vector2, override: Dictionary) -> Variant:
		calls.append({"row_id": row_id, "pos": pos, "override": override})
		return auto_free(MockSprout.new())
	var e0 := _engage_tick(e)
	var volley_frame := -1
	for f in range(e0 + 1, e0 + 40):
		_now_frame = f
		e.brain_tick(f)
		if e.fired_this_tick:
			volley_frame = f
			break
	assert_int(volley_frame).is_equal(e0 + 31)           # windup 30 → 首轮齐射
	assert_int(calls.size()).is_equal(0)                 # 弹未落地不出苗
	_drive(e, volley_frame + 1, volley_frame + 300)      # 落地拍= flight 101t 后陆续出苗
	assert_int(calls.size()).is_equal(3)                 # cap=3：一波 3 弹即满，其余哑火
	for c: Dictionary in calls:
		assert_str(String(c["row_id"])).is_equal("kuli_bug")
		assert_bool((c["override"] as Dictionary).is_empty()).is_true()   # 净行召唤（房间回调持有 counts_for_wave）
		assert_float((c["pos"] as Vector2).length()).is_equal_approx(80.0, 0.01)  # 落点=解算目标


func test_seed_pitcher_sprout_delay_equals_flight_ticks() -> void:
	RngSvc.setup_run(SPROUT_SEED)
	var cs := _mk_combat("sig_sprout_delay")
	var row: Dictionary = GameDB.enemies["seed_pitcher"].duplicate(true)
	row["impact_spawn_chance"] = 1.0
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(80, 0)
	e.player_ref = spy
	var spawn_frames: Array = []
	e.spawn_callback = func(_row_id: String, _pos: Vector2, _override: Dictionary) -> Variant:
		spawn_frames.append(_now_frame)
		return auto_free(MockSprout.new())
	var e0 := _engage_tick(e)
	var volley_frame := -1
	for f in range(e0 + 1, e0 + 40):
		_now_frame = f
		e.brain_tick(f)
		if e.fired_this_tick:
			volley_frame = f
			break
	_drive(e, volley_frame + 1, volley_frame + 200)
	assert_int(spawn_frames.size()).is_equal(3)
	var flight := int(SignatureMoves.lob_solution(Vector2.ZERO, Vector2(80, 0), 95.0)["flight_ticks"])
	assert_int(int(spawn_frames[0])).is_equal(volley_frame + flight)   # 落地拍出苗
	assert_int(int(spawn_frames[1])).is_equal(volley_frame + flight)   # 同拍 3 弹齐落
	assert_int(int(spawn_frames[2])).is_equal(volley_frame + flight)


func test_seed_pitcher_cap_release_after_sprout_death() -> void:
	RngSvc.setup_run(SPROUT_SEED)
	var cs := _mk_combat("sig_sprout_cap")
	var row: Dictionary = GameDB.enemies["seed_pitcher"].duplicate(true)
	row["impact_spawn_chance"] = 1.0
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(80, 0)
	e.player_ref = spy
	var sprouts: Array = []
	e.spawn_callback = func(_row_id: String, _pos: Vector2, _override: Dictionary) -> Variant:
		var m := MockSprout.new()
		sprouts.append(m)
		auto_free(m)
		return m
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 700)                          # ≥2 波齐射窗口（每 108t 一轮）
	assert_int(sprouts.size()).is_equal(3)               # cap 满员：后续种子哑火
	(sprouts[0] as MockSprout).state = EnemyBase.State.DEAD   # 击杀一只苗
	_drive(e, e0 + 701, e0 + 1100)                       # 下一轮齐射落地 → 补 1
	assert_int(sprouts.size()).is_equal(4)               # 上限释放：恰补 1 只
	_drive(e, e0 + 1101, e0 + 1500)
	assert_int(sprouts.size()).is_equal(4)               # 再次满员封顶


func test_seed_pitcher_zero_chance_never_spawns_fail_closed() -> void:
	var cs := _mk_combat("sig_sprout_zero")
	var row: Dictionary = GameDB.enemies["seed_pitcher"].duplicate(true)
	row["impact_spawn_chance"] = 0.0                     # fail-closed：无概率不生苗
	row.erase("impact_spawn_cap")
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(80, 0)
	e.player_ref = spy
	var calls: Array = []                                # lambda 捕获按值：用引用容器计数
	e.spawn_callback = func(_row_id: String, _pos: Vector2, _override: Dictionary) -> Variant:
		calls.append(1)
		return auto_free(MockSprout.new())
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 500)                          # ~4 轮齐射
	assert_int(cs.active_count()).is_greater(0)          # 抛物弹照常发射
	assert_int(calls.size()).is_equal(0)                 # 但零生苗


func test_seed_pitcher_chance_statistics_within_bounds() -> void:
	RngSvc.setup_run(SPROUT_SEED + 1)
	var cs := _mk_combat("sig_sprout_stat")
	var row: Dictionary = GameDB.enemies["seed_pitcher"].duplicate(true)
	row["impact_spawn_cap"] = 999                        # 解除上限观察纯掷签分布
	var e: EnemyBase = auto_free(EnemyFactory.create(row))
	e.combat = cs
	var spy: SpyPlayer = auto_free(SpyPlayer.new())
	spy.brain_pos = Vector2(80, 0)
	e.player_ref = spy
	var calls: Array = []                                # lambda 捕获按值：用引用容器计数
	e.spawn_callback = func(_row_id: String, _pos: Vector2, _override: Dictionary) -> Variant:
		calls.append(1)
		return auto_free(MockSprout.new())
	var e0 := _engage_tick(e)
	_drive(e, e0 + 1, e0 + 2900)                         # ~26 轮 × 3 弹 = 78 掷签
	# 30% 掷签：78 样本均值 23.4；[8, 40] 界外概率 < 1e-6（防 flaky 的宽统计界）
	assert_int(calls.size()).is_greater_equal(8)
	assert_int(calls.size()).is_less_equal(40)
