class_name TestRoomCombatSummons
extends GdUnitTestSuite
## M1 Task 12/13 生产召唤接线：召唤体/分裂子体必须进入当前房间的
## CombatSystem、enemies group 和追踪数组，但不得消费原始 RoomFlow 波次计数。


func _room() -> RoomCombat:
	var room := RoomCombat.new()
	room.spawn_player = true
	add_child(room)
	return room


func test_vine_colossus_summons_real_mushrooms_without_advancing_wave() -> void:
	var room := _room()
	room.flow.setup({"waves": [["vine_colossus"]], "coins": 0, "energy_orbs": 0})
	room.flow.on_entered(100)
	var boss := room._spawn_enemy("vine_colossus", RoomCombat.ROOM_CENTER)
	assert_object(boss).is_not_null()
	assert_bool(boss is VineColossus).is_true()
	assert_bool(boss.counts_for_wave).is_true()
	(boss as VineColossus)._summon_resolve()
	var mushrooms: Array[EnemyBase] = []
	for enemy in room._enemies:
		if String(enemy.row.get("id", "")) == "mushroom_spore":
			mushrooms.append(enemy)
	assert_int(mushrooms.size()).is_equal(2)
	assert_int(room.flow.pending_spawns()).is_equal(1)       # 原始 Boss 仍是唯一波次体
	for mushroom in mushrooms:
		assert_bool(mushroom is EnemyBase).is_true()
		assert_str((mushroom.get_script() as Script).resource_path).ends_with("mushroom_spore.gd")
		assert_bool(mushroom.combat == room.combat).is_true()
		assert_bool(mushroom.player_ref == room.player_proxy).is_true()
		assert_bool(mushroom.is_in_group("enemies")).is_true()
		assert_bool(mushroom.spawn_callback.is_valid()).is_true()
		assert_bool(mushroom.counts_for_wave).is_false()
		mushroom.die()
	assert_int(room.flow.pending_spawns()).is_equal(1)
	assert_bool(room.flow.cleared).is_false()
	boss.die()
	assert_int(room.flow.pending_spawns()).is_equal(0)
	assert_bool(room.flow.cleared).is_true()


func test_zibao_summons_and_splitter_children_stay_outside_wave_count() -> void:
	var room := _room()
	room.flow.setup({"waves": [["zibao_wangchong"]], "coins": 0, "energy_orbs": 0})
	room.flow.on_entered(100)
	var miniboss := room._spawn_enemy("zibao_wangchong", RoomCombat.ROOM_CENTER)
	assert_object(miniboss).is_not_null()
	miniboss._summon_ring()
	var kuli: Array[EnemyBase] = []
	for enemy in room._enemies:
		if String(enemy.row.get("id", "")) == "kuli_bug":
			kuli.append(enemy)
	assert_int(kuli.size()).is_equal(4)
	for child in kuli:
		assert_bool(child.counts_for_wave).is_false()
		assert_bool(child.spawn_callback.is_valid()).is_true()
		child.die()
	assert_int(room.flow.pending_spawns()).is_equal(1)
	assert_bool(room.flow.cleared).is_false()

	# 同一生产 callback 路径下，splitter 子体也是半血上限、无词缀、非波次体。
	var split_row := GameDB.get_enemy("vine_charger").duplicate(true)
	split_row["elite_affixes"] = ["splitter"]
	var splitter := room._spawn_enemy("vine_charger", RoomCombat.ROOM_CENTER + Vector2(80, 0),
		split_row, false)
	assert_object(splitter).is_not_null()
	var half := maxi(int(float(splitter.row["hp"]) * 0.5), 1)
	splitter.die()
	var split_children: Array[EnemyBase] = []
	for enemy in room._enemies:
		if enemy != splitter and String(enemy.row.get("id", "")) == "vine_charger" \
				and enemy.state != EnemyBase.State.DEAD:
			split_children.append(enemy)
	assert_int(split_children.size()).is_equal(2)
	for child in split_children:
		assert_int(child.hp).is_equal(half)
		assert_int(child.hp_max).is_equal(half)
		assert_bool(child.split_on_death).is_false()
		assert_bool(child.counts_for_wave).is_false()
		assert_bool((child.row.get("elite_affixes", []) as Array).is_empty()).is_true()
		child.die()
	assert_int(room.flow.pending_spawns()).is_equal(1)
	miniboss.die()
	assert_int(room.flow.pending_spawns()).is_equal(0)
	assert_bool(room.flow.cleared).is_true()
