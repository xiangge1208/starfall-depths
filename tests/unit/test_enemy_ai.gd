class_name TestEnemyAI
extends GdUnitTestSuite

func test_state_transitions() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
	e.on_player_seen(0)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)
	e.brain_tick(23)
	assert_int(e.state).is_equal(EnemyBase.State.ALERT)     # 0.4s=24 ticks 前摇
	e.brain_tick(24)
	assert_int(e.state).is_equal(EnemyBase.State.ENGAGE)

func test_shooter_cadence() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "crossbowman", "archetype": "shooter", "hp": 16, "contact_dmg": 3, "speed": 60, "windup_ticks": 30, "cd_ticks": 108})
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	var shots := 0
	for f in range(25, 300):
		e.brain_tick(f)
		if e.fired_this_tick: shots += 1
	# 0.4s 警觉后首射，随后每 1.8s：约 (300-24)/108 + 1 ≈ 3
	assert_int(shots).is_between(2, 4)

func test_suicide_fuse_and_explosion_params() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "kuli_bug", "archetype": "suicide", "hp": 12, "speed": 95, "fuse_ticks": 30, "aoe_radius": 40, "aoe_dmg": 8})
	e.on_player_seen(0)
	for f in range(1, 25): e.brain_tick(f)
	e.brain_tick(24 + 30)     # ENGAGE 后贴身引信 30 ticks
	assert_bool(e.exploded).is_true()

func test_charger_dash_distance() -> void:
	var e: EnemyBase = auto_free(EnemyBase.new())
	e._test_init({"id": "vine_charger", "archetype": "charger", "hp": 18, "contact_dmg": 4, "walk_speed": 45, "dash_speed": 285, "windup_ticks": 30, "dash_ticks": 27, "dash_cooldown_ticks": 90})
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)                   # 第 24 帧进入 ENGAGE
	for f in range(25, 55):
		e.brain_tick(f)                   # 前摇 30 ticks（蓄力原地）
	var traveled := 0.0
	var last := e.brain_pos
	for f in range(55, 55 + 27):          # 冲刺 27 ticks = 27×285/60 ≈ 128px（附录 B.2 冲 8 瓦片）
		e.brain_tick(f)
		traveled += last.distance_to(e.brain_pos)
		last = e.brain_pos
	assert_float(traveled).is_equal_approx(128.0, 8.0)
