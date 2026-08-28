class_name TestRunState
extends GdUnitTestSuite
## m1-t15 RunState autoload：种子激活（start_run → RngSvc.setup_run）+ 分盐流 + 局内聚合字段。


func test_start_run_activates_seed() -> void:
	RunState.start_run("vanguard")
	assert_int(RunState.run_seed).is_not_equal(0)
	assert_int(RngSvc.run_seed).is_equal(RunState.run_seed)   # 种子激活契约
	assert_int(RunState.floor_idx).is_equal(1)

func test_start_run_resets_all_fields() -> void:
	RunState.start_run("vanguard")
	# 污染全部局内字段（gems 为 meta：T17 口径，start_run 不动）
	RunState.floor_idx = 3
	RunState.coins = 42
	RunState.buffs.append("swift_trigger")
	RunState.weapons[0] = "laohuoji"
	RunState.current_slot = 1
	RunState.kills = 7
	RunState.rooms_cleared = 5
	RunState.run_time_frames = 999
	RunState.pending_investment = 3
	RunState.gems = 55
	RunState.start_run("ranger")
	assert_int(RunState.floor_idx).is_equal(1)
	assert_int(RunState.coins).is_equal(0)
	assert_array(RunState.buffs).is_empty()
	assert_array(RunState.weapons).is_equal(["", ""])
	assert_int(RunState.current_slot).is_equal(0)
	assert_int(RunState.kills).is_equal(0)
	assert_int(RunState.rooms_cleared).is_equal(0)
	assert_int(RunState.run_time_frames).is_equal(0)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.gems).is_equal(55)   # gems 不重置（meta，T17 口径）
	assert_str(RunState.hero_id).is_equal("ranger")

func test_start_run_stores_hero_and_last_chosen() -> void:
	RunState.start_run("vanguard")
	assert_str(RunState.hero_id).is_equal("vanguard")
	assert_str(RunState.last_chosen_hero).is_equal("vanguard")

func test_select_hero_alias_activates_run() -> void:
	# T11 守卫契约：/root/RunState 存在且有 select_hero(id) 方法则调用之。
	# select_hero = start_run 别名（选角即开局）：点击时刻激活种子（GDD §9.1），
	# 不留"存了 hero_id 但种子仍未激活"的死接缝。
	RngSvc.setup_run(0)
	RunState.select_hero("ranger")
	assert_str(RunState.hero_id).is_equal("ranger")
	assert_str(RunState.last_chosen_hero).is_equal("ranger")
	assert_int(RunState.run_seed).is_not_equal(0)
	assert_int(RngSvc.run_seed).is_equal(RunState.run_seed)   # 种子激活契约
	assert_int(RunState.floor_idx).is_equal(1)

func test_distinct_salts_give_distinct_sequences() -> void:
	# 分盐目的：rig 散布掷签与弹幕暴击掷签不得共享同一序列（房间接线按盐分溪）。
	RunState.start_run("vanguard")
	var rig: float = RunState.stream(RunState.SALT_RIG).randf()
	var proj: float = RunState.stream(RunState.SALT_PROJECTILE).randf()
	assert_float(rig).is_not_equal(proj)

func test_salt_constants() -> void:
	assert_str(RunState.SALT_PROJECTILE).is_equal("proj_crit")
	assert_str(RunState.SALT_RIG).is_equal("rig")
	assert_str(RunState.SALT_LOOT).is_equal("loot")
	assert_str(RunState.SALT_DUNGEON).is_equal("dungeon")

func test_stream_matches_rngsvc_per_salt() -> void:
	RunState.start_run("vanguard")
	for salt: String in [RunState.SALT_PROJECTILE, RunState.SALT_RIG, RunState.SALT_LOOT, RunState.SALT_DUNGEON]:
		var via_run: RandomNumberGenerator = RunState.stream(salt)
		var via_svc: RandomNumberGenerator = RngSvc.stream(RunState.floor_idx, salt)
		for _i in 8:
			assert_float(via_run.randf()).is_equal(via_svc.randf())

func test_stream_follows_floor() -> void:
	RunState.start_run("vanguard")
	var floor1: RandomNumberGenerator = RunState.stream(RunState.SALT_PROJECTILE)
	RunState.next_floor()
	var floor2: RandomNumberGenerator = RunState.stream(RunState.SALT_PROJECTILE)
	var diff := false
	for _i in 8:
		if floor1.randf() != floor2.randf():
			diff = true
	assert_bool(diff).is_true()

func test_next_floor_returns_new_index_and_gems_boundaries() -> void:
	# GDD §14.1 每层通过 +60/120/200：进入下一层时结算；3 层后封顶 200
	RunState.start_run("vanguard")
	var g0 := RunState.gems
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(RunState.gems).is_equal(g0 + 60)
	assert_int(RunState.next_floor()).is_equal(3)
	assert_int(RunState.gems).is_equal(g0 + 180)
	assert_int(RunState.next_floor()).is_equal(4)
	assert_int(RunState.gems).is_equal(g0 + 380)
	assert_int(RunState.next_floor()).is_equal(5)
	assert_int(RunState.gems).is_equal(g0 + 580)   # clamp：第 4 次仍 +200

func test_spend_coins_insufficient() -> void:
	RunState.start_run("vanguard")
	RunState.add_coins(10)
	assert_bool(RunState.spend_coins(11)).is_false()
	assert_int(RunState.coins).is_equal(10)

func test_spend_coins_sufficient() -> void:
	RunState.start_run("vanguard")
	RunState.add_coins(10)
	assert_bool(RunState.spend_coins(10)).is_true()
	assert_int(RunState.coins).is_equal(0)
	assert_bool(RunState.spend_coins(1)).is_false()   # 花光后再花即拒

func test_add_kill_and_room_cleared() -> void:
	RunState.start_run("vanguard")
	RunState.add_kill()
	RunState.add_kill()
	RunState.add_room_cleared()
	assert_int(RunState.kills).is_equal(2)
	assert_int(RunState.rooms_cleared).is_equal(1)

func test_add_buff() -> void:
	RunState.start_run("vanguard")
	RunState.add_buff("swift_trigger")
	RunState.add_buff("bulwark")
	assert_array(RunState.buffs).is_equal(["swift_trigger", "bulwark"])

func test_record_weapon_slots() -> void:
	RunState.start_run("vanguard")
	RunState.record_weapon(0, "laohuoji")
	RunState.record_weapon(1, "tiejian")
	assert_array(RunState.weapons).is_equal(["laohuoji", "tiejian"])
	RunState.record_weapon(2, "duangong")   # 越界槽：忽略不崩溃
	assert_array(RunState.weapons).is_equal(["laohuoji", "tiejian"])

func test_run_time_accumulation() -> void:
	RunState.start_run("vanguard")
	assert_int(RunState.run_time_frames).is_equal(0)
	for _i in 5:
		RunState._tick_run_time()             # _physics_process 每物理帧调用同一路径
	assert_int(RunState.run_time_frames).is_equal(5)
