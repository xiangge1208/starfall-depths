class_name TestM1Integration
extends GdUnitTestSuite
## m1-t27 最终整合卡集成测试：四处死缝的端到端契约。
## 1) RunRoot：选角承接（RunState）→ HeroApplier 装配 → DungeonBuilder（run_seed）→
##    FloorScene 首层；重建机制（旧层释放/玩家跨层存活）。
## 2) 真实嘉宾：elite/miniboss/boss 房生成数据行真实嘉宾（词缀/boss_script 数据驱动），
##    波次推进经 wave_id 回译不断链；drops 死亡即落；开关关断回占位。
## 3) 设施：shop 真商店（RunState 钱包买卖/回收）、event 进房开面板、金币入账 RunState。
## 4) 层间：boss 死亡 → inter_floor 嵌入开层；门 → RunState.next_floor() → A2 入口
##    里程碑（真实离开 A1、层号/玩家/HUD 切换）；第 3 层胜利桩流程级验证。
##
## RunState 污染守卫：每用例前 start_run 复位（test_inter_floor 同款），after_test 再复位
## 并 free RunRoot/FloorScene（整棵含 inter_floor/浮层）。

const RUN_ROOT_SCENE := "res://core/rooms/run_root.tscn"
const PLAYER_SCENE := "res://core/player/player.tscn"
const HERO_HP_VANGUARD := 8      # data/heroes.json vanguard hp
const HERO_WEAPON := "laohuoji"  # vanguard start_weapons[0]
const BEGGAR_WIN_SEED := 1        # RandomNumberGenerator 首个 randf()=0.329559 < 0.7

var _root: Node2D = null
var _fs: FloorScene = null


func before_test() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	if _fs != null and is_instance_valid(_fs):
		_fs.free()
	_fs = null
	RunState.start_run("vanguard")   # 复位楼层/种子/聚合（跨套件卫生）
	RunState.coins = 0


# ================================================================ 缝 1：RunRoot

func test_run_root_builds_floor_one_with_chosen_hero() -> void:
	_root = _make_root()
	add_child(_root)                        # 入树（玩家 _ready/@onready 需树上下文）
	_root._begin()
	var fs: FloorScene = _root.floor_scene
	assert_object(fs).is_not_null()
	assert_int(fs.room_count()).is_equal(13)             # DungeonGraph 规格 13 节点
	assert_int(fs.floor_idx).is_equal(1)
	assert_int(fs.flow.start_room()).is_equal(int(fs.flow.current_room))
	# 玩家 = HeroApplier 装配的 vanguard：面板/初始武器/技能/meta，挂 RunRoot（跨层存活）
	var player: Player = _root.player
	assert_object(player).is_not_null()
	assert_int(player.hp_max).is_equal(HERO_HP_VANGUARD)
	assert_bool(player.is_in_group("player")).is_true()
	assert_bool(player.weapon_rig.current().is_empty()).is_false()
	assert_str(String(player.weapon_rig.current().get("id", ""))).is_equal(HERO_WEAPON)
	assert_bool(player.get_node("Skill").get_script() != null).is_true()
	assert_bool(player.has_meta("crit_base")).is_true()
	# 玩家落 start 房中心
	assert_bool(fs.room_rect(fs.flow.start_room()).has_point(player.position)).is_true()


func test_run_root_embedded_does_not_autoboot() -> void:
	# 嵌入（非 current_scene）不自动开局——测试/宿主先装配的路径不进 _begin（FloorScene 同约定）
	_root = _make_root()
	add_child(_root)
	assert_object(_root.floor_scene).is_null()
	assert_object(_root.player).is_null()
	_root._begin()                          # 生产等价入口（路由 _ready 即调它）
	assert_object(_root.floor_scene).is_not_null()
	assert_object(_root.player).is_not_null()


func test_floor_rebuild_keeps_player_and_rebuilds_rooms() -> void:
	# 重建机制（next_floor 同入口 _start_floor）：旧层释放、玩家同实例跨层存活、新层完整装配
	_root = _make_root()
	_root._begin()
	var old_fs: FloorScene = _root.floor_scene
	var player: Player = _root.player
	_root._on_next_floor_requested(1)       # floor 1 有数据 → 重建（floor 2 走浮层，见缝 4）
	assert_bool(old_fs.is_queued_for_deletion()).is_true()
	var fs: FloorScene = _root.floor_scene
	assert_object(fs).is_not_null()
	assert_bool(fs != old_fs).is_true()
	assert_int(fs.room_count()).is_equal(13)
	assert_bool(_root.player == player).is_true()        # 玩家同实例
	assert_bool(fs.room_rect(fs.flow.start_room()).has_point(player.position)).is_true()


func test_run_root_persists_facilities_across_same_floor_rebuild_and_resets_new_run() -> void:
	_root = _make_root()
	_root._begin()
	var first_state: Dictionary = _root._drink_states[1]
	first_state["uses_left"] = 1
	_root._used_shrine_kinds["zhanshen"] = true
	_root._on_next_floor_requested(1)
	assert_int(_root.floor_scene._drink_state["uses_left"]).is_equal(1)
	_root.floor_scene._drink_state["uses_left"] = 0
	assert_int(first_state["uses_left"]).is_equal(0) # 同一持久字典，不是重建副本
	assert_bool(_root.floor_scene._used_shrine_kinds.has("zhanshen")).is_true()
	# 新局 run_seed 变化后，整局雕像门控和各层饮料状态都必须清空。
	RunState.start_run("ranger")
	_root._begin()
	assert_int(_root._drink_states[1]["uses_left"]).is_equal(DrinkMachine.USES_PER_FLOOR)
	assert_dict(_root._used_shrine_kinds).is_empty()


func test_run_root_reuse_resets_every_runtime_state_for_new_run() -> void:
	_root = _make_root()
	_root._begin()
	var old_player: Player = _root.player
	var old_buffs: BuffManager = _root.buffs
	# 污染跨层应保留、但跨局绝不能保留的全部主要运行时入口。
	old_buffs.pick("vigor")
	old_buffs.pick("swift_trigger")
	old_buffs.apply_to_player(old_player)
	old_buffs.apply_to_rig(old_player.weapon_rig)
	RunState.add_buff("vigor")
	RunState.add_buff("swift_trigger")
	DrinkMachine._apply_drink("crit_pct", 6.0, old_player)
	DrinkMachine._apply_drink("status_rate_pct", 25.0, old_player)
	old_player.atk_speed_boost_pct = Shrine.ATK_BOOST_PCT
	old_player.atk_speed_boost_until = 999999
	old_player.move_speed_boost_pct = Shrine.WIND_BOOST_PCT
	old_player.move_speed_boost_until = 999999
	old_player.energy_free_until = 999999
	old_player.weapon_rig.temporary_enchant_element = Elements.Id.FIRE
	old_player.weapon_rig.temporary_enchant_until = 999999
	old_player.set_meta("enchant_element_until", 999999)
	_root._drink_states[1]["uses_left"] = 0
	_root._used_shrine_kinds["xingsui"] = true

	RunState.start_run("ranger")
	_root._begin()
	var fresh: Player = _root.player
	assert_bool(fresh != old_player).is_true()
	assert_bool(_root.buffs != old_buffs).is_true()
	assert_array(_root.buffs.picked).is_empty()
	assert_array(RunState.buffs).is_empty()
	assert_int(fresh.hp_max).is_equal(6)
	assert_int(fresh.shield_max).is_equal(4)
	assert_int(fresh.energy_max).is_equal(110)
	assert_float(fresh.move_speed).is_equal(88.0)
	assert_float(fresh.crit_bonus).is_equal(0.0)
	assert_float(fresh.crit_damage_bonus).is_equal(0.0)
	assert_float(fresh.status_rate_bonus).is_equal(0.0)
	assert_float(fresh.roll_cd_pct).is_equal(0.0)
	assert_int(fresh.shield_delay_reduction_ticks).is_equal(0)
	assert_float(fresh.atk_speed_boost_pct).is_equal(0.0)
	assert_int(fresh.atk_speed_boost_until).is_equal(-1)
	assert_float(fresh.move_speed_boost_pct).is_equal(0.0)
	assert_int(fresh.move_speed_boost_until).is_equal(-1)
	assert_int(fresh.energy_free_until).is_equal(-1)
	assert_bool(fresh.has_meta("drink_crit_bonus")).is_false()
	assert_bool(fresh.has_meta("drink_status_rate_bonus")).is_false()
	assert_bool(fresh.has_meta("enchant_element_until")).is_false()
	assert_float(fresh.weapon_rig.rate_mult).is_equal(1.0)
	assert_float(fresh.weapon_rig.bullet_speed_mult).is_equal(1.0)
	assert_int(fresh.weapon_rig.enchant_element).is_equal(Elements.Id.NONE)
	assert_int(fresh.weapon_rig.temporary_enchant_element).is_equal(Elements.Id.NONE)
	assert_int(fresh.weapon_rig.temporary_enchant_until).is_equal(-1)
	assert_str(String(fresh.weapon_rig.current().get("id", ""))).is_equal("duangong")
	assert_int(_root._drink_states[1]["uses_left"]).is_equal(DrinkMachine.USES_PER_FLOOR)
	assert_dict(_root._used_shrine_kinds).is_empty()


func test_physical_walk_into_adjacent_room_triggers_enter() -> void:
	# 回归钉住（m1-t27 diff 复审发现）：按图进房检测必须无条件跑（含 start 等无战斗
	# 房）——真实玩家物理走图靠它进房；若只在有 combat 的房跑，start/设施房即软锁。
	_fs = _make_floor(["combat"])
	var player: Player = _fs.player_node()
	var start := _fs.flow.start_room()
	var next: int = _fs.flow.adjacent(start)[0]
	player.global_position = _fs.room_center(next)      # 物理走位（非 enter_room 直驱）
	await _await_until(func() -> bool: return _fs.flow.current_room == next)
	assert_int(_fs.flow.current_room).is_equal(next)     # 检测进房 + 锁门开战
	assert_bool(_fs.flow.is_locked()).is_true()
	# 回走 start（无 combat 房）→ 检测同样要生效（拒绝→推回，current 不变）
	_fs.flow.notify_room_cleared(next)
	player.global_position = _fs.room_center(start)
	await _await_until(func() -> bool: return _fs.flow.current_room == start)
	assert_int(_fs.flow.current_room).is_equal(start)


# ================================================================ 缝 2：真实嘉宾

func test_real_guests_spawn_and_waves_advance() -> void:
	_fs = _make_floor(["elite", "miniboss", "boss"])
	# elite：波2 真双刀蜥人（swift+berserk）→ kill 经 wave_id 回译 elite_charger → 房清
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "shuangdao_lizardman") != null)
	var elite := _find_enemy(_fs.room_node(1), "shuangdao_lizardman")
	assert_int(elite.hp).is_equal(180)
	assert_bool(elite.has_berserk).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	assert_bool(_fs.flow.cleared.has(1)).is_true()
	# miniboss：真自爆王虫（armored ×3、leech）→ 回译 miniboss_charger → 房清
	assert_bool(_fs.enter_room(2)).is_true()
	_kill_all(_fs.room_node(2))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(2), "zibao_wangchong") != null)
	var mb := _find_enemy(_fs.room_node(2), "zibao_wangchong")
	assert_int(mb.hp).is_equal(540)
	assert_bool(mb.leech).is_true()
	_kill_all(_fs.room_node(2))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(2))
	assert_bool(_fs.flow.cleared.has(2)).is_true()


func test_guest_drops_weapon_station_and_hearts() -> void:
	# drops "weapon,hearts2"：精英死 → 武器掉落台（ShopLogic roll）+ 2 红心，掉落台可 E 换手
	_fs = _make_floor(["elite"])
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "shuangdao_lizardman") != null)
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	var station: Interactable = _fs.room_node(1).get_node_or_null(NodePath("LootStation"))
	assert_object(station).is_not_null()
	# 红心 4 = 精英嘉宾 drops 2 + elite 房清奖励 2（waves_for hearts）
	var hearts := 0
	for c in _fs.room_node(1).get_children():
		if c is Pickup and (c as Pickup).kind == "heart":
			hearts += 1
	assert_int(hearts).is_equal(4)
	var player: Player = _fs.player_node()
	assert_bool(player.weapon_rig.slots[1].is_empty()).is_true()
	station.interact(player)
	assert_bool(player.weapon_rig.slots[1].is_empty()).is_false()


func test_placeholder_fallback_when_use_real_guests_off() -> void:
	# 开关回归对照：use_real_guests=false → T12 占位路径原样（elite_charger 3×hp）
	_fs = FloorScene.new()
	_fs.use_real_guests = false
	add_child(_fs)
	_fs.setup(_typed_chain(["elite"]), _player_instance())
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _find_enemy(_fs.room_node(1), "elite_charger") != null)
	var guest := _find_enemy(_fs.room_node(1), "elite_charger")
	assert_int(guest.hp).is_equal(18 * 3)


# ================================================================ 缝 3：设施

func test_shop_facility_buys_with_runstate_wallet_and_recycles() -> void:
	_fs = _make_floor(["shop"])
	RunState.coins = 1000
	assert_bool(_fs.enter_room(1)).is_true()
	var shop := _shop_in(_fs.room_node(1))
	assert_object(shop).is_not_null()
	# 货单：3 武器位 roll（层权重逐位 roll，池 40 把）+ 道具 + 层号元数据
	assert_int((shop.stock["weapons"] as Array).size()).is_equal(3)
	assert_int(int(shop.stock["floor_idx"])).is_equal(1)
	assert_object(_fs.room_node(1).get_node_or_null("DrinkMachine")).is_instanceof(DrinkMachine)
	for kind in Shrine.KINDS:
		assert_object(_fs.room_node(1).get_node_or_null("Shrine_%s" % kind)).is_instanceof(Shrine)
	# 买：RunState 钱包扣款 → 入空槽（玩家初始 laohuoji 占槽 0）。
	# open() 由玩家交互触发（E），测试走同一入口；价格按货品实际稀有度计。
	var wid := String((shop.stock["weapons"] as Array)[0])
	var rarity := String(GameDB.get_weapon(wid).get("rarity", "common"))
	shop.interact(_fs.player_node())
	shop._buy_weapon(0)
	assert_bool(shop.is_sold(0)).is_true()
	assert_str(String(_fs.player_node().weapon_rig.slots[1].get("id", ""))).is_equal(wid)
	assert_int(RunState.coins).is_equal(1000 - ShopLogic.price(rarity, 1, shop.black))
	# 回收：副手（槽 1 = 刚买的 wid）→ recycle_price 入账 RunState，槽清空
	_fs.player_node().weapon_rig.equip("tiejian")     # 双槽满 → 替换当前槽 0
	RunState.coins = 0
	shop._recycle()
	assert_int(RunState.coins).is_equal(ShopLogic.recycle_price(rarity, 1))
	assert_bool(_fs.player_node().weapon_rig.slots[1].is_empty()).is_true()


func test_shop_drink_machine_consumes_bound_floor_state() -> void:
	_fs = _make_floor(["shop"])
	RunState.coins = 1000
	assert_bool(_fs.enter_room(1)).is_true()
	var drink := _fs.room_node(1).get_node("DrinkMachine") as DrinkMachine
	drink.open(_fs._drink_state, RunState, _fs.player_node())
	var idx := drink.drink_ids().find("jifeng_bohe")
	assert_bool(drink.buy(idx)).is_true()
	assert_int(_fs._drink_state["uses_left"]).is_equal(2)


func test_shield_spirit_rebinds_to_current_combat_room() -> void:
	_fs = _make_floor(["shop", "combat"])
	RunState.coins = 1000
	assert_bool(_fs.enter_room(1)).is_true()
	var shrine := _fs.room_node(1).get_node("Shrine_jingling") as Shrine
	assert_bool(shrine.activate(_fs.player_node(), 100)).is_true()
	var spirit: ShieldSpirit = null
	for child in _fs.player_node().get_children():
		if child is ShieldSpirit:
			spirit = child as ShieldSpirit
	assert_object(spirit).is_not_null()
	assert_object(spirit.combat).is_null()
	assert_bool(_fs.enter_room(2)).is_true()
	assert_object(spirit.combat).is_same(_fs.room_node(2).combat)


func test_mystery_merchant_roll_cooldown_uses_fixed_tick_conversion() -> void:
	var p := _player_instance()
	add_child(p)
	assert_int(p.roll_cd_reduction_ticks).is_equal(0)
	var fs := FloorScene.new()
	fs._apply_event_drink_effect("roll_cd_pct", 0.05, p)
	assert_int(p.roll_cd_reduction_ticks).is_equal(TimeConst.ticks(0.05))
	assert_int(p.roll_cd_reduction_ticks).is_equal(3)
	fs.free()
	p.free()


func test_event_facility_opens_panel_on_entry() -> void:
	_fs = _make_floor(["event"])
	assert_bool(_fs.enter_room(1)).is_true()
	var ev := _event_in(_fs.room_node(1))
	assert_object(ev).is_not_null()
	assert_bool(ev.ui_visible()).is_true()
	assert_array(EventRoom.EVENT_IDS).contains(ev.current_event())


func test_coin_pickup_credits_runstate() -> void:
	_fs = _make_floor(["combat"])
	assert_bool(_fs.enter_room(1)).is_true()
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _alive_count(_fs.room_node(1)) == 3)   # 波2 补刷
	_kill_all(_fs.room_node(1))
	await _await_until(func() -> bool: return _fs.flow.cleared.has(1))
	var coin := _coin_in(_fs.room_node(1))
	assert_object(coin).is_not_null()
	var before := RunState.coins
	coin.on_collect.call()
	assert_int(RunState.coins).is_equal(before + 1)


# ================================================================ 缝 4：层间

func test_boss_death_opens_inter_floor_and_door_enters_floor_two() -> void:
	# boss 死亡 → inter_floor 嵌入开层（BUFF 三选一）→ 选增益 → 喷泉 → 门 →
	# InterFloorFlow.enter_next_floor 推层+蓝晶 → 真正切到 A2 入口里程碑。
	_root = _make_root()
	add_child(_root)                        # 入树（kill→EventBus→Fx/层间链需树上下文）
	_root._begin()
	var fs: FloorScene = _root.floor_scene
	# 直驱 FloorFlow 走到 boss 门口（纯逻辑清图；boss 房走真实场景 enter_room 开战）
	var boss := fs.flow.boss_room()
	for id in _path_to_boss(fs, boss):
		if id == boss:
			continue                           # boss 留给真实场景 enter_room 开战
		assert_bool(fs.flow.enter_room(id)).is_true()
		if fs.flow.room_type(id) != "start":
			fs.flow.notify_room_cleared(id)
	assert_bool(fs.enter_room(boss)).is_true()          # boss 房：真巨像开战
	assert_object(_find_enemy(fs.room_node(boss), "vine_colossus")).is_not_null()
	var old_combat: CombatSystem = fs.room_node(boss).combat
	var rig: WeaponRig = _root.player.weapon_rig
	var melee: Melee = _root.player.get_node("Melee") as Melee
	var spirit := ShieldSpirit.new()
	_root.player.add_child(spirit)
	spirit.setup(_root.player, old_combat, 3)
	_kill_all(fs.room_node(boss))
	await _await_until(func() -> bool: return _root.inter_floor != null)
	var inter: Node2D = _root.inter_floor
	assert_bool(is_instance_valid(inter)).is_true()
	assert_bool(fs._flow_suspended).is_true()           # 楼层流程挂起（防进房检测抢人）
	# Boss 清房同拍必须把旧楼层整棵停机并解除所有玩家侧战斗引用；否则残弹、
	# 环境伤害或仍在运行的旧 CombatSystem 会在三选一/喷泉期间继续伤害玩家。
	assert_int(fs.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_object(fs._registered_combat).is_null()
	assert_object(_root.player.combat).is_null()
	assert_object(rig.combat).is_null()
	assert_object(rig.combat_rng).is_null()
	assert_object(melee.combat).is_null()
	assert_object(melee.combat_rng).is_null()
	assert_object(spirit.combat).is_null()
	var survivability_before: int = int(_root.player.hp) + int(_root.player.shield)
	old_combat.spawn_projectile({
		"pos": _root.player.global_position, "vel": Vector2.ZERO, "damage": 1,
		"faction": Projectile.Faction.ENEMY, "life_seconds": 5.0, "radius": 8.0,
	})
	for _i in 3:
		await get_tree().physics_frame
	assert_int(_root.player.hp + _root.player.shield).is_equal(survivability_before)
	assert_int(inter.flow.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_bool(inter.flow.offered.is_empty()).is_false()
	assert_int(_full_hud_count(_root)).is_equal(1)
	assert_bool(_contains_task_debug_label(_root)).is_false()
	# 三选一 → 喷泉 → 门（走场景层回调，等价玩家操作）
	inter._on_buff_chosen(inter.flow.offered[0])
	assert_array(RunState.buffs).contains(inter.flow.offered[0])
	var hp0: int = _root.player.hp
	assert_bool(inter.flow.use_fountain(_root.player)).is_true()
	assert_int(_root.player.hp).is_equal(mini(hp0 + 2, _root.player.hp_max))
	var gems0 := RunState.gems
	var save0 := SaveSystem.gems()
	inter._on_door_interact(_root.player)
	# 门侧效：InterFloorFlow.enter_next_floor 已推层 + §14.1 蓝晶结算（1→2 给 60）。
	# m2-t31 层间入账：门先把 gems0 累积池（含本层击杀蓝晶/首杀）全额入档并清空，
	# 门后池内恒 = 过层奖励 60，累积部分已落袋，胜利/死亡不再重复结算。
	assert_int(RunState.floor_idx).is_equal(2)
	assert_int(SaveSystem.gems()).is_equal(save0 + gems0)
	assert_int(RunState.gems).is_equal(60)
	assert_bool(_root.a2_entry_active()).is_true()
	assert_bool(_root.m1_overlay_visible()).is_true()
	assert_str(_root.overlay_text()).contains("已进入第 2 层")
	assert_bool(inter.is_queued_for_deletion()).is_true()
	assert_object(_root.floor_scene).is_null()          # 已离开 A1，不以覆盖层冒充跨层
	assert_object(_root.player.get_parent()).is_same(_root)
	assert_int(int(_root._a2_entry.get_meta("floor_idx"))).is_equal(2)


func test_beggar_accept_settles_on_a1_inter_floor_before_a2_entry() -> void:
	# 生产组件链：EventRoom.accept 真扣 40/记账 A1 → FloorScene.boss_defeated 信号
	# → RunRoot 嵌入真 InterFloor → DOOR 掷签结清 → 进入 A2 里程碑。
	_root = _make_root()
	add_child(_root)
	_root._begin()
	RunState.coins = EventRoom.BEGGAR_COST
	var ev := EventRoom.new()
	_root.floor_scene.add_child(ev)
	ev.setup(_root.player, _rng(20260828))
	assert_bool(ev.open_event("beggar")).is_true()
	ev.accept()
	assert_int(RunState.coins).is_equal(0)
	assert_int(RunState.pending_investment).is_equal(EventRoom.BEGGAR_PAYOUT)
	assert_int(RunState.beggar_paid_floor).is_equal(1)

	_root.floor_scene.boss_defeated.emit(_root.floor_scene.flow.boss_room())
	var inter: InterFloor = _root.inter_floor as InterFloor
	assert_object(inter).is_not_null()
	inter.flow.payout_rng = _rng(BEGGAR_WIN_SEED)
	inter._on_buff_chosen(inter.flow.offered[0])
	assert_bool(inter.flow.use_fountain(_root.player)).is_true()
	# 进入 DOOR 当拍就是「下层」结算点；不得把 A1 投资留到 A2 Boss 后。
	assert_int(RunState.coins).is_equal(EventRoom.BEGGAR_PAYOUT)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)

	inter._on_door_interact(_root.player)
	assert_int(RunState.floor_idx).is_equal(2)
	assert_bool(_root.a2_entry_active()).is_true()
	var settled_coins := RunState.coins
	inter.flow.advance()
	inter._on_door_interact(_root.player)
	assert_int(RunState.coins).is_equal(settled_coins) # 重复泵/门不二次返还


func test_boss_death_flow_victory_stub_at_floor_three() -> void:
	# 第 3 层胜利桩（InterFloorFlow.VICTORY_FLOOR=3 契约）：M1 数据到不了第 3 层，
	# 流程级验证：floor_idx=3 开层间 → victory 直显结算桩；DONE 阶段推层 fail-closed。
	_root = _make_root()
	add_child(_root)
	_root._begin()
	RunState.floor_idx = 3
	var inter: Node2D = (load("res://core/rooms/inter_floor.tscn") as PackedScene).instantiate()
	_root.add_child(inter)
	inter.setup(_root.player, _root.buffs, 3)
	inter.open()
	assert_bool(inter.flow.victory).is_true()
	assert_int(inter.flow.phase).is_equal(InterFloorFlow.Phase.DONE)
	assert_bool(inter._victory_label.visible).is_true()
	var f0 := RunState.floor_idx
	assert_int(inter.flow.enter_next_floor()).is_equal(-1)   # DONE 阶段拒绝推层
	assert_int(RunState.floor_idx).is_equal(f0)


# ================================================================ helpers

func _make_root() -> Node2D:
	return (load(RUN_ROOT_SCENE) as PackedScene).instantiate() as Node2D


func _player_instance() -> Player:
	return (load(PLAYER_SCENE) as PackedScene).instantiate() as Player


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _make_floor(types: Array) -> FloorScene:
	var fs := FloorScene.new()
	add_child(fs)
	fs.setup(_typed_chain(types), _player_instance())    # setup 收养无父玩家
	_fs = fs
	return fs


## 直驱 FloorFlow 的到 boss 可达路径：BFS 最短路（boss 唯一邻接 = 主路径倒数第二节点），
## 终点 boss（由测试真实 enter_room）。战斗房经 notify 清（纯逻辑，场景波次不驱动）。
func _path_to_boss(fs: FloorScene, boss: int) -> Array[int]:
	var start := fs.flow.start_room()
	var parent := {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == boss:
			break
		for n in fs.flow.adjacent(cur):
			if not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var path: Array[int] = []
	var cur2 := boss
	while cur2 != start:
		path.push_front(cur2)
		cur2 = int(parent[cur2])
	return path


func _typed_chain(types: Array) -> Dictionary:
	var rooms := {0: _room(0, "start", Vector2i(0, 0), [1])}
	var corridors: Array = []
	for i in types.size():
		var id := i + 1
		var grid := Vector2i(i + 1, 0)
		var nxt: Array = [] if i == types.size() - 1 else [id + 1]
		rooms[id] = _room(id, String(types[i]), grid, nxt)
		corridors.append({"a": id - 1, "b": id, "dir": "E"})
	return {"rooms": rooms, "corridors": corridors, "start_room_id": 0, "boss_room_id": -1}


func _room(id: int, type: String, grid: Vector2i, next: Array) -> Dictionary:
	var tid := "combat_a1_01"
	if type == "start":
		tid = "start_a1"
	elif type == "boss":
		tid = "boss_a1"
	return {
		"node": {"id": id, "type": type, "grid": grid, "depth": 0, "next": next},
		"template_id": tid, "world_pos": Vector2(grid) * 416.0,
	}


func _await_until(check: Callable, max_frames: int = 60) -> void:
	for _i in max_frames:
		if check.call():
			return
		await get_tree().physics_frame


func _kill_all(room: FloorScene.FloorRoom) -> void:
	for e in room.enemies.duplicate():
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			e.take_hit({"amount": 99999, "is_crit": false, "element": 0, "from": e.global_position})


func _alive_count(room: FloorScene.FloorRoom) -> int:
	var n := 0
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			n += 1
	return n


func _full_hud_count(node: Node) -> int:
	var count := 1 if node is HUD else 0
	for child in node.get_children():
		count += _full_hud_count(child)
	return count


func _contains_task_debug_label(node: Node) -> bool:
	if node is Label and String((node as Label).text).begins_with("M1-T"):
		return true
	for child in node.get_children():
		if _contains_task_debug_label(child):
			return true
	return false


func _find_enemy(room: FloorScene.FloorRoom, id: String) -> EnemyBase:
	for e in room.enemies:
		if is_instance_valid(e) and String(e.row.get("id", "")) == id \
				and e.state != EnemyBase.State.DEAD:
			return e
	return null


func _shop_in(room: FloorScene.FloorRoom) -> Shop:
	for c in room.get_children():
		if c is Shop:
			return c
	return null


func _event_in(room: FloorScene.FloorRoom) -> EventRoom:
	for c in room.get_children():
		if c is EventRoom:
			return c
	return null


func _coin_in(room: FloorScene.FloorRoom) -> Pickup:
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == "coin":
			return c
	return null
