extends GdUnitTestSuite
## M5-A1 复活图腾（GDD §14.2「复活图腾（一次性，Boss 房前）150」落地）：
##   售卖（ReviveTotem.interact / can_interact）——150 金充能 RunState.revive_charged，
##   金币不足不充能，充能后不可再交互；
##   复活（Player.take_hit_ctx 致命伤分支）——消耗标记原地复活 50% HP / 2 盾 /
##   0.8s 无敌帧，死亡结算短路（player_hit_resolved.fatal=false）；优先级低于
##   不死鸟；无标记的致命伤照常 fatal=true；
##   清场（CombatSystem.clear_enemy_bullets_around）——只清半径内敌方弹，玩家弹
##   与半径外弹不受影响；
##   局内一次性——start_run 重置。
## 基建沿 test_buff_consumers（CombatSystem 构造 / spawn_projectile / auto_free）。

var _captured_fatal: Array = []


func before_test() -> void:
	RunState.revive_charged = false


func after_test() -> void:
	RunState.revive_charged = false


func _combat(root: Node2D) -> CombatSystem:
	var cs := CombatSystem.new(root, RngSvc.stream(0, "combat"))
	cs.crit_chance = 0.0
	auto_free(cs)
	root.add_child(cs)
	return cs


func _bullet(pos: Vector2, faction: int) -> Dictionary:
	return {"pos": pos, "vel": Vector2.ZERO, "damage": 1, "pierce": 0, "bounce": 0,
		"life_seconds": 10.0, "radius": 3.0, "faction": faction}


# —— 售卖 ——

func test_purchase_charges_and_deducts_150() -> void:
	RunState.coins = 200
	var totem: ReviveTotem = auto_free(ReviveTotem.new())
	assert_bool(totem.can_interact(null)).is_true()
	totem.interact(null)
	assert_int(RunState.coins).is_equal(50)
	assert_bool(RunState.revive_charged).is_true()
	assert_bool(totem.can_interact(null)).is_false()      # 充能后浮标隐藏（不可重复购买）


func test_purchase_insufficient_funds_noop() -> void:
	RunState.coins = 100
	var totem: ReviveTotem = auto_free(ReviveTotem.new())
	totem.interact(null)
	assert_int(RunState.coins).is_equal(100)
	assert_bool(RunState.revive_charged).is_false()
	assert_bool(totem.can_interact(null)).is_true()


# —— 复活（Player.take_hit_ctx） ——

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	return p


func _with_fatal_capture() -> void:
	_captured_fatal.clear()
	EventBus.player_hit_resolved.connect(
		func(_a: int, fatal: bool, _r: Dictionary) -> void:
			_captured_fatal.append(fatal))


func _end_fatal_capture() -> void:
	for c in EventBus.player_hit_resolved.get_connections():
		var cb: Callable = c["callable"]
		if cb.is_valid() and cb.get_object() == self:
			EventBus.player_hit_resolved.disconnect(cb)


func test_revive_consumes_totem_and_restores_half_hp_two_shield() -> void:
	var p := _player()
	RunState.revive_charged = true
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, Engine.get_physics_frames())
	assert_int(p.hp).is_equal(int(ceil(p.hp_max * 0.5)))   # 8 → 4
	assert_int(p.shield).is_equal(2)
	assert_bool(RunState.revive_charged).is_false()        # 一次性消耗


func test_revive_short_circuits_death() -> void:
	var p := _player()
	_with_fatal_capture()
	RunState.revive_charged = true
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, Engine.get_physics_frames())
	assert_array(_captured_fatal).is_equal([false])        # 死亡结算短路
	_end_fatal_capture()


func test_second_fatal_without_charge_is_real_death() -> void:
	var p := _player()
	_with_fatal_capture()
	RunState.revive_charged = true
	var f0 := Engine.get_physics_frames()
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, f0)
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, f0 + 100)  # 跳出 0.8s 无敌帧窗
	assert_array(_captured_fatal).is_equal([false, true])  # 一次性：第二次真死
	_end_fatal_capture()


func test_phoenix_takes_priority_totem_saved() -> void:
	var p := _player()
	p.set_meta("buff_phoenix_flag", 1)                     # 不死鸟在场
	RunState.revive_charged = true
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, Engine.get_physics_frames())
	assert_int(p.hp).is_equal(1)                           # 不死鸟先消费（hp=1）
	assert_bool(RunState.revive_charged).is_true()         # 图腾留给下一次致命伤


func test_no_totem_no_phoenix_fatal_normal() -> void:
	var p := _player()
	_with_fatal_capture()
	p.take_hit_ctx({"amount": 100, "source_type": "projectile"}, Engine.get_physics_frames())
	assert_array(_captured_fatal).is_equal([true])
	_end_fatal_capture()


# —— 清场（CombatSystem.clear_enemy_bullets_around） ——

func test_clear_kills_only_enemy_bullets_within_radius() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var cs := _combat(root)
	cs.spawn_projectile(_bullet(Vector2.ZERO, Projectile.Faction.ENEMY))
	cs.spawn_projectile(_bullet(Vector2(50, 0), Projectile.Faction.ENEMY))
	cs.spawn_projectile(_bullet(Vector2(300, 0), Projectile.Faction.ENEMY))
	cs.spawn_projectile(_bullet(Vector2(10, 0), Projectile.Faction.PLAYER))
	var cleared := cs.clear_enemy_bullets_around(Vector2.ZERO, 100.0)
	assert_int(cleared).is_equal(2)                        # 近距两枚敌弹
	assert_int(cs.pool.active.size()).is_equal(2)          # 远距敌弹 + 玩家弹保留
	var factions: Array = []
	for p in cs.pool.active:
		factions.append(p.faction)
	assert_array(factions).contains(Projectile.Faction.PLAYER)
	assert_array(factions).contains(Projectile.Faction.ENEMY)


# —— 局内一次性 ——

func test_start_run_resets_totem_charge() -> void:
	RunState.revive_charged = true
	RunState.start_run("vanguard")
	assert_bool(RunState.revive_charged).is_false()
