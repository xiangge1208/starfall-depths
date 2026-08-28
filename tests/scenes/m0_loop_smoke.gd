extends Node
## m0-t12 全闭环无头冒烟（手动验证的机检部分；视觉手感仍需真人把玩）：
## 训练房接线 → 武器架 6 台拾取 → 枪/近战打靶 → 反弹 → 进战斗房锁门 → 两波清房 →
## 开门+奖励（金币/蓝珠/红心拾取）→ 弹幕雨致死。逐项 print，失败置 exit 1。
## 运行：godot --headless --path . res://tests/scenes/m0_loop_smoke.tscn

var room: Node2D
var failures: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1)
	)
	room = (load("res://core/rooms/training_room.tscn") as PackedScene).instantiate()
	add_child(room)
	_run()

func _run() -> void:
	await _frames(5)
	var player: Player = room.get_node("Player")
	var combat_room: RoomCombat = room.get_node("RoomCombat")
	var rig: WeaponRig = player.get_node("WeaponRig")
	var melee: Melee = player.get_node("Melee")
	print("SMOKE 0: wiring")
	_check(rig.combat == combat_room.combat, "rig.combat injected")
	_check(melee.combat == combat_room.combat, "melee.combat injected")
	_check(rig.combat_rng != null and melee.combat_rng == rig.combat_rng, "shared combat rng stream")
	_check(melee.rig == rig, "melee.rig injected")
	room.call("_cheat_toggle_dummy_regen")     # T 键通路可调（开）
	room.call("_cheat_toggle_dummy_regen")     # 再关：还原默认（关），避免干扰后续伤害观测
	_check((room.get("_dummies") as Array).size() == 3, "3 dummies present")

	# ---- 1) 武器架 6 台逐台拾取 ----
	print("SMOKE 1: weapon rack x6")
	var ids: Array = room.get("RACK_WEAPON_IDS")
	for i in ids.size():
		var id := String(ids[i])
		await _touch_station(player, i)
		_check(_has_weapon(rig, id), "rack equips %s" % id)

	# ---- 2) 枪械打靶（driver 真实开火路径 → fire 遥测；再直驱验证假人掉血） ----
	print("SMOKE 2: ranged vs dummy")
	await _touch_station(player, 0)            # laohuoji（双槽满时替换当前槽 → current 可保证）
	player.global_position = Vector2(60, 135)
	player.facing = Vector2.RIGHT
	var dummy: EnemyBase = (room.get("_dummies") as Array)[1]   # (180,135) 正右方
	Input.action_press("fire")                 # driver 开火（直驱 try_fire 会占满射速门，先让位）
	for i in 30:
		await _frames(1)
	Input.action_release("fire")
	var hp0: int = dummy.hp
	var saw_bullet := false
	for i in 240:
		rig.try_fire(Vector2.RIGHT, Engine.get_physics_frames())
		await _frames(1)
		if combat_room.combat.active_count() > 0:
			saw_bullet = true
	await _frames(30)
	_check(saw_bullet, "bullets became active")
	_check(dummy.hp < hp0, "dummy took ranged damage (hp %d -> %d)" % [hp0, dummy.hp])

	# ---- 3) 近战挥击打靶 ----
	print("SMOKE 3: melee vs dummy")
	await _touch_station(player, 4)            # tiejian
	player.global_position = Vector2(145, 135)
	player.facing = Vector2.RIGHT
	await _frames(2)
	var hp1: int = dummy.hp
	_check(melee.try_attack(Engine.get_physics_frames()), "melee swing started")
	for i in 12:
		await _frames(1)
	_check(dummy.hp < hp1, "dummy took melee damage")

	print("SMOKE 4: parry reflect live bullet")
	await _seconds(0.6)                        # 近战冷却走完
	dummy.global_position = Vector2(400, 60)   # 挪出弹道：反射弹不得即刻撞进假人而同帧消失
	dummy.brain_pos = dummy.global_position    # brain_pos 为权威位：不同步会以 (brain-pos)×60 冲回
	combat_room.combat.spawn_projectile({
		# 50px 外迎面 80px/s：tick1..2 尚在弧外（不被格挡），tick3..4 入弧 → 反弹
		"pos": player.global_position + Vector2(50, 0), "vel": Vector2.LEFT * 80.0,
		"damage": 3, "faction": Projectile.Faction.ENEMY, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 2.0, "radius": 3.0,
	})
	await _frames(1)
	_check(melee.try_attack(Engine.get_physics_frames()), "swing for parry")
	var reflected := false
	for i in 20:
		await _frames(1)
		for p in combat_room.combat.pool.active:
			if p.faction == Projectile.Faction.PLAYER and p.damage == 6:
				reflected = true
	_check(reflected, "bullet reflected to player faction (dmg=6)")

	# ---- 5) 进战斗房：锁门 + 波1 + 敌人 AI/弹幕 ----
	print("SMOKE 5: enter combat room")
	player.shield = 100                        # 测试挂具护甲（fix1 起接触伤害生效）：段内不被打死
	room.set("_restarting", true)              # 阻断训练房致命重载路径（冒烟自管生命周期）
	player.hp = 8
	var cleared_flag := [false]
	EventBus.room_cleared.connect(func(_id: String) -> void: cleared_flag[0] = true)
	player.global_position = Vector2(500, 135)
	await _frames(3)
	_check(combat_room.flow.locked, "flow locked on entry")
	_check(combat_room.entry_frame >= 0, "entry frame stamped")
	await _frames(10)
	_check(_enemy_count() == 2, "wave1 spawned 2 (got %d)" % _enemy_count())
	# 接触伤害（fix1 收口）：此刻弩兵尚未进入射击相位（alert 24t + windup 30t ≈ 54 帧），
	# 场上亦无敌方弹——贴身掉盾/掉血只能来自 contact_dmg，判定确定。
	var touch := _find_enemy("crossbowman")
	if touch != null:
		var shield_before: int = player.shield
		var hp_before: int = player.hp
		player.global_position = touch.global_position
		await _frames(3)
		_check(player.shield < shield_before or player.hp < hp_before,
			"contact damage applied on touch (shield %d -> %d)" % [shield_before, player.shield])
		player.global_position = Vector2(500, 135)
		await _frames(1)
	var shooter: EnemyBase = _find_enemy("crossbowman")
	_check(shooter != null, "crossbowman present")
	await _seconds(1.2)
	_check(shooter != null and is_instance_valid(shooter) and shooter.state == EnemyBase.State.ENGAGE, "shooter ENGAGE after alert")
	await _seconds(2.0)
	_check(combat_room.combat.active_count() > 0, "enemy bullets live")

	# ---- 6) 清两波（自动开火） ----
	print("SMOKE 6: clear both waves")
	# 切到另一槽的 laohuoji（_touch_station 会把玩家传送回武器架，战斗中途不可用）
	rig.switch_slot(Engine.get_physics_frames())
	player.global_position = Vector2(500, 135)
	player.facing = Vector2.RIGHT
	var saw_wave2 := false
	var guard := 0
	while not combat_room.flow.cleared and guard < 3600:
		guard += 1
		player.shield = 100                        # 挂具护甲保持（接触+弹幕都不致死）
		player.hp = 8                              # 冒烟只验流程，不被弹幕打死
		var target := _nearest_enemy(player)
		if target != null:
			var aim := (target.global_position - player.global_position).normalized()
			rig.try_fire(aim, Engine.get_physics_frames())
		await _frames(1)
		if _enemy_count() == 3:
			saw_wave2 = true
	_check(saw_wave2, "wave2 spawned after wave1 cleared")
	_check(combat_room.flow.cleared, "flow cleared")
	_check(not combat_room.flow.locked, "doors unlocked")
	_check(cleared_flag[0], "room_cleared signal received")
	_check(_pickup_count(combat_room) == 35, "rewards burst 35 pickups (got %d)" % _pickup_count(combat_room))

	# ---- 7) 奖励拾取：金币/蓝珠/红心 ----
	print("SMOKE 7: pickups")
	var energy0: int = 50
	player.energy = energy0                    # 先放空能量，蓝珠 +8 才可观测
	var hp2: int = player.hp
	player.global_position = Vector2(716, 135) # 奖励爆发中心（金币磁吸半径内）
	await _seconds(1.0)
	# 蓝珠/红心无磁吸（GDD 仅金币）：绕中心踏一圈逐个踩过
	for k in 4:
		player.global_position = Vector2(716, 135) + Vector2.from_angle(k * PI / 2.0) * 14.0
		await _frames(10)
	await _seconds(1.0)
	_check(combat_room.coins_collected() > 0, "coins collected (=%d)" % combat_room.coins_collected())
	_check(player.energy > energy0, "energy orb added energy")
	_check(player.hp >= hp2, "heart heal no-less")

	# ---- 8) 死亡（弹幕雨 + 高伤弹） ----
	print("SMOKE 8: death")
	room.set("_restarting", true)              # 阻断训练房 1.5s 重载路径（冒烟自管退出）
	var fatal_flag := [false]
	EventBus.player_damaged.connect(func(_a: int, fatal: bool) -> void:
		if fatal:
			fatal_flag[0] = true
	)
	room.call("_cheat_rain_bullets")
	player.shield = 0
	player.hp = 1
	combat_room.combat.spawn_projectile({
		"pos": player.global_position + Vector2(80, 0), "vel": Vector2.LEFT * 160.0,
		"damage": 99, "faction": Projectile.Faction.ENEMY, "element": Elements.Id.NONE,
		"pierce": 0, "bounce": 0, "life_seconds": 2.0, "radius": 3.0,
	})
	await _seconds(2.0)
	_check(player.hp == 0, "player hp 0")
	_check(fatal_flag[0], "fatal player_damaged received")

	# ---- 9) 遥测 + HUD ----
	print("SMOKE 9: telemetry + hud")
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	for ev in ["fire", "hit", "kill", "room_clear", "hurt", "equip", "pickup", "room_enter"]:
		_check(text.contains(ev), "telemetry has '%s' rows" % ev)
	var labels: Array[Label] = []
	_collect_labels(room, labels)
	var hud_ok := false
	for l in labels:
		if l.text.contains("FPS") and l.text.contains("bullets"):
			hud_ok = true
	_check(hud_ok, "debug HUD label rendering values")

	if failures.is_empty():
		print("SMOKE RESULT: ALL PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SMOKE FAIL: ", f)
		print("SMOKE RESULT: %d FAILURES" % failures.size())
		get_tree().quit(1)

# ---- helpers ----

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  - ", what)
	else:
		failures.append(what)
		print("  FAIL- ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _touch_station(player: Player, index: int) -> void:
	# m1-t6：武器架 E 化（接触拾取路径已移除）——走近（InteractionSystem 半径 24px
	# 选最近台）后模拟 E 按下。action_press 在 physics_frame 信号窗口（本拍 _physics_frames
	# 已自增、节点尚未处理）调用，同拍 is_action_just_pressed 成立，一拍即消费。
	player.global_position = Vector2(100, 240) + Vector2(52.0 * index, 0) + Vector2(0, -3)
	await _frames(2)                           # InteractionSystem 物理拍 bind 最近台
	Input.action_press("interact")
	await _frames(1)
	Input.action_release("interact")
	await _frames(1)

func _has_weapon(rig: WeaponRig, id: String) -> bool:
	for s in rig.slots:
		if not s.is_empty() and String(s["id"]) == id:
			return true
	return false

func _enemy_count() -> int:
	return _room_enemies().size()

func _room_enemies() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is EnemyBase and e.get_parent() == room.get_node("RoomCombat"):
			out.append(e)
	return out

func _find_enemy(id: String) -> EnemyBase:
	for e in _room_enemies():
		if String(e.row.get("id", "")) == id:
			return e
	return null

func _nearest_enemy(player: Player) -> EnemyBase:
	var best: EnemyBase = null
	var best_d := INF
	for e in _room_enemies():
		if e.state != EnemyBase.State.DEAD:
			var d: float = e.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = e
	return best

func _pickup_count(combat_room: RoomCombat) -> int:
	var n := 0
	for c in combat_room.get_children():
		if c is Pickup:
			n += 1
	return n

func _collect_labels(node: Node, out: Array[Label]) -> void:
	for c in node.get_children():
		if c is Label:
			out.append(c)
		_collect_labels(c, out)
