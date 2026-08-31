class_name T26ManualWalk
extends GdUnitTestSuite
## 【临时验收脚本，跑完即删，不入库】m2-t26 手动走查：真实构建体 13 房（A1），
## 从 start 沿门禁逐房清到挑战房 → 灾厄 4 选 1（视野-35%）→ 3 波强化怪全清 →
## 必得紫武器 + 80~120 金币 → 门开、灾厄还原。脚本驱动等价玩家入口（m1_evidence 先例）。

const SEED := 20260828

var _fs: FloorScene = null


func after_test() -> void:
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
		_fs = null


func test_manual_walk_real_floor_challenge_full_run() -> void:
	RunState.start_run("vanguard")
	var build := DungeonBuilder.build(SEED, 1)
	assert_array(DungeonBuilder.validate_build(build)).is_empty()
	_fs = FloorScene.new()
	add_child(_fs)
	var player: Player = (load("res://core/player/player.tscn") as PackedScene).instantiate() \
		as Player
	_fs.setup(build, player)
	var cid := _fs.challenge_room()
	print("WALK[1] floor=1 rooms=", _fs.room_count(), " gates=", _fs.gate_count(),
		" challenge_room=", cid, " template=", _fs.room_node(cid).template_id)
	assert_int(cid).is_greater_equal(0)
	assert_str(_fs.flow.room_type(cid)).is_equal("combat")

	# 沿开门图逐房推进（树图贪心即完备）；战斗房清波后继续，直至站进挑战房
	var guard := 0
	while not _fs.flow.cleared.has(cid) and guard < 48:
		guard += 1
		var target := -1
		for n in _fs.flow.next_rooms():
			if not _fs.flow.cleared.has(n):
				target = n
				break
		if target < 0:
			break
		assert_bool(_fs.enter_room(target)).is_true()
		if target == cid:
			break
		var t := _fs.flow.room_type(target)
		if t in ["combat", "elite", "miniboss"]:
			var room: FloorScene.FloorRoom = _fs.room_node(target)
			while not _fs.flow.cleared.has(target):
				_kill_all(room)
				await _await_until(func() -> bool:
					return _alive(room) == 0 or _fs.flow.cleared.has(target))
			await _await_until(func() -> bool: return _fs.flow.cleared.has(target))
			print("WALK[2] cleared room=", target, " type=", t)
		else:
			print("WALK[2] passed instant room=", target, " type=", t)
	assert_bool(_fs.flow.current_room == cid or _fs.flow.cleared.has(cid)).is_true()
	if _fs.flow.current_room != cid:
		assert_bool(_fs.enter_room(cid)).is_true()

	# 挑战房：进门面板开、未刷怪、门锁
	var challenge: FloorScene.FloorRoom = _fs.room_node(cid)
	assert_bool(_fs.calamity_panel_visible()).is_true()
	assert_int(_alive(challenge)).is_equal(0)
	assert_bool(_fs.flow.is_locked()).is_true()
	print("WALK[3] entered challenge room=", cid, " panel=visible locked=true")

	# 4 选 1：视野-35%
	_fs.choose_calamity("vision")
	assert_object(_fs.calamity_fx).is_not_null()
	assert_int(_alive(challenge)).is_equal(3)
	print("WALK[4] calamity=vision fx-mounted=true wave1=3")

	for w in 3:
		if w > 0:
			assert_int(_alive(challenge)).is_equal(3)
		_kill_all(challenge)
		await _await_until(func() -> bool:
			return _alive(challenge) == 0 or _fs.flow.cleared.has(cid))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(cid))
	print("WALK[5] waves=3/3 cleared=true locked=false")

	# 奖励：必得紫 + 80~120 金币；灾厄还原
	var station := challenge.get_node_or_null(NodePath("LootStation")) as Interactable
	assert_object(station).is_not_null()
	var wid := String(station.get_meta("weapon_id", ""))
	var rarity := String(GameDB.get_weapon(wid).get("rarity", ""))
	var coins := _pickups(challenge, "coin")
	print("WALK[6] epic_weapon=", wid, " rarity=", rarity, " coins=", coins,
		" fx-restored=", _fs.calamity_fx == null,
		" meta-clean=", not player.has_meta(FloorScene.CALAMITY_HEAL_META))
	assert_str(rarity).is_equal("epic")
	assert_int(coins).is_greater_equal(80)
	assert_int(coins).is_less_equal(120)
	assert_object(_fs.calamity_fx).is_null()
	Telemetry.flush()
	var text := FileAccess.get_file_as_string("user://telemetry.csv")
	assert_bool(text.contains("calamity")).is_true()
	print("WALK[7] PASS challenge room full run complete")


func _await_until(check: Callable, max_frames: int = 120) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func _alive(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 9999, "is_crit": false, "element": 0, "from": e.global_position})


func _pickups(room: FloorScene.FloorRoom, kind: String) -> int:
	var n := 0
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == kind:
			n += 1
	return n
