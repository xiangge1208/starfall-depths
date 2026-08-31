class_name TestRunState
extends GdUnitTestSuite
## m1-t15 RunState autoload：种子激活（start_run → RngSvc.setup_run）+ 分盐流 + 局内聚合字段。
## m2-t31 追加：击杀蓝晶档位（精英5/小Boss20/Boss50）+ Boss 首杀 +300 + 层间门全额入账
## （不双计）。层间入账/首杀标记会写 SaveSystem → before/after_test 统一重定向临时档
## （test_death_recorder 同款守卫），绝不触碰真实 user://save.json。

var _saved_save_path := ""
var _tmp_save := ""


func before_test() -> void:
	_saved_save_path = SaveSystem.save_path
	_tmp_save = "user://test_run_state_%d.json" % absi(randi())
	SaveSystem.save_path = _tmp_save
	SaveSystem.load_save()              # 全新空档：首杀名录/蓝晶余额不跨用例残留


func after_test() -> void:
	SaveSystem.save_path = _saved_save_path
	SaveSystem.load_save()              # 还原真实档视图
	DirAccess.remove_absolute(_tmp_save)
	DirAccess.remove_absolute(_tmp_save + ".tmp")
	RunState.start_run("vanguard")      # 池/楼层复位（跨套件卫生，同 test_victory_summary）


func test_start_run_activates_seed() -> void:
	RunState.start_run("vanguard")
	assert_int(RunState.run_seed).is_not_equal(0)
	assert_int(RngSvc.run_seed).is_equal(RunState.run_seed)   # 种子激活契约
	assert_int(RunState.floor_idx).is_equal(1)

func test_start_run_resets_all_fields() -> void:
	RunState.start_run("vanguard")
	# 污染全部局内字段（gems 是本局待结算所得；局外余额只在 SaveSystem）
	RunState.floor_idx = 3
	RunState.coins = 42
	RunState.buffs.append("swift_trigger")
	RunState.weapons[0] = "laohuoji"
	RunState.selected_slot = 1
	RunState.kills = 7
	RunState.rooms_cleared = 5
	RunState.run_time_frames = 999
	RunState.pending_investment = 3
	RunState.beggar_paid_floor = 2
	RunState.star_spring_used = true
	RunState.gems = 55
	RunState.start_run("ranger")
	assert_int(RunState.floor_idx).is_equal(1)
	assert_int(RunState.coins).is_equal(0)
	assert_array(RunState.buffs).is_empty()
	assert_array(RunState.weapons).is_equal(["", ""])
	assert_int(RunState.selected_slot).is_equal(0)
	assert_int(RunState.current_slot).is_equal(0) # 历史别名与权威字段同步
	assert_int(RunState.kills).is_equal(0)
	assert_int(RunState.rooms_cleared).is_equal(0)
	assert_int(RunState.run_time_frames).is_equal(0)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)
	assert_bool(RunState.star_spring_used).is_false()
	assert_int(RunState.gems).is_equal(0)
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
	assert_str(RunState.SALT_DUNGEON).is_equal("dungeon")

func test_facility_salt_constants() -> void:
	# M2-T1：五设施各自独立盐（M1 终审 ③：替换五处共享的掉落盐同种子重派生）。
	assert_str(RunState.SALT_SHOP).is_equal("shop")
	assert_str(RunState.SALT_SHRINE).is_equal("shrine")
	assert_str(RunState.SALT_DRINK).is_equal("drink")
	assert_str(RunState.SALT_INTER_FLOOR).is_equal("inter_floor")
	assert_str(RunState.SALT_EVENT).is_equal("event")

func test_facility_salts_give_independent_first_rolls() -> void:
	# 分盐语义：黑商/雕像/饮料机/层间三选一/事件的首掷互不关联（两两不等）。
	RunState.start_run("vanguard")
	var first_rolls: Array[float] = []
	for salt: String in [RunState.SALT_SHOP, RunState.SALT_SHRINE, RunState.SALT_DRINK,
			RunState.SALT_INTER_FLOOR, RunState.SALT_EVENT]:
		first_rolls.append(RunState.stream(salt).randf())
	for i in first_rolls.size():
		for j in range(i + 1, first_rolls.size()):
			assert_float(first_rolls[i]).is_not_equal(first_rolls[j])

func test_stream_matches_rngsvc_per_salt() -> void:
	RunState.start_run("vanguard")
	for salt: String in [RunState.SALT_PROJECTILE, RunState.SALT_RIG, RunState.SALT_DUNGEON,
			RunState.SALT_SHOP, RunState.SALT_SHRINE, RunState.SALT_DRINK,
			RunState.SALT_INTER_FLOOR, RunState.SALT_EVENT]:
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
	# GDD §14.1 每层通过 +60/120/200：进入下一层时结算；3 层后封顶 200。
	# m2-t31 层间入账契约：进门先把累积池全额入档并清空，再发过层奖励留池，
	# 门后池内恒只有本门过层奖励（上层击杀蓝晶已在门入档，不双计）。
	RunState.start_run("vanguard")
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(RunState.gems).is_equal(60)
	assert_int(RunState.next_floor()).is_equal(3)
	assert_int(RunState.gems).is_equal(120)   # 上门 60 已入档，池 = 新奖励 120
	assert_int(RunState.next_floor()).is_equal(4)
	assert_int(RunState.gems).is_equal(200)
	assert_int(RunState.next_floor()).is_equal(5)
	assert_int(RunState.gems).is_equal(200)   # clamp：第 4 次仍 +200

func test_a1_death_settlement_awards_half_once_and_consumes_pending() -> void:
	RunState.start_run("vanguard")
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(RunState.gems).is_equal(60)          # A1 通过：本局待结算 +60
	assert_int(RunState.settle_death_gems()).is_equal(30)
	assert_int(RunState.gems).is_equal(0)
	assert_int(RunState.settle_death_gems()).is_equal(0)   # 重复结算不可再领

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


# ================================================================ m2-t31 蓝晶结算完整

func test_add_gems_accumulates_pending_pool() -> void:
	# 击杀蓝晶便捷方法：直接入池（不走层结算）；入档时机 = 层间门 / 终局结算。
	RunState.start_run("vanguard")
	RunState.add_gems(5)
	RunState.add_gems(20)
	assert_int(RunState.gems).is_equal(25)

func test_kill_gem_tiers_elite_miniboss_boss() -> void:
	# 击杀蓝晶档位（GDD §14 允许口径）：精英 +5 / 小 Boss +20 / Boss +50；杂兵 +0。
	RunState.start_run("vanguard")
	assert_int(RunState.settle_kill_gems("elite", "shuangdao_lizardman")).is_equal(5)
	assert_int(RunState.settle_kill_gems("miniboss", "zibao_wangchong")).is_equal(20)
	assert_int(RunState.settle_kill_gems("boss", "vine_colossus")).is_equal(50 + 300)
	assert_int(RunState.gems).is_equal(375)
	assert_int(RunState.settle_kill_gems("", "kuli_bug")).is_equal(0)      # 杂兵无档位
	assert_int(RunState.settle_kill_gems("trash", "cave_bat")).is_equal(0) # 未知 kind 不入池
	assert_int(RunState.gems).is_equal(375)

func test_boss_first_kill_awarded_once_per_boss_and_persists() -> void:
	# 首杀 +300：SaveSystem 无该 boss 记录才发，且击杀即标记入档（死亡重试不可重刷）。
	RunState.start_run("vanguard")
	assert_array(SaveSystem.boss_first_kills()).is_empty()
	assert_int(RunState.settle_kill_gems("boss", "vine_colossus")).is_equal(50 + 300)
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus"])   # 已标记
	assert_int(RunState.settle_kill_gems("boss", "vine_colossus")).is_equal(50)  # 同 Boss 二杀：仅档位
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus"])
	# 不同 Boss 各自享受首杀。
	assert_int(RunState.settle_kill_gems("boss", "frost_widow")).is_equal(50 + 300)
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus", "frost_widow"])
	# 标记已持久化：重读档仍在（跨局防重刷）。
	SaveSystem.data = {}
	SaveSystem.load_save()
	assert_array(SaveSystem.boss_first_kills()).is_equal(["vine_colossus", "frost_widow"])

func test_next_floor_banks_pending_gems_once_no_double_count() -> void:
	# 层间入账不双计（核心口径）：门把池内全额（含击杀蓝晶）入档并清空，
	# 过层奖励留池——胜利/死亡只结算其后新累积的部分，每颗蓝晶恰入档一次。
	RunState.start_run("vanguard")
	assert_int(SaveSystem.gems()).is_equal(0)
	RunState.add_gems(40)                                  # 本层击杀蓝晶
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(SaveSystem.gems()).is_equal(40)             # 门：池 40 全额入档
	assert_int(RunState.gems).is_equal(60)                 # 过层奖励留池
	RunState.add_gems(30)                                  # 第 2 层击杀蓝晶
	assert_int(RunState.next_floor()).is_equal(3)
	assert_int(SaveSystem.gems()).is_equal(40 + 60 + 30)   # 池 90 全额入档（无重复计入）
	assert_int(RunState.gems).is_equal(120)

func test_next_floor_with_empty_pool_makes_no_save_write() -> void:
	# 池空不写盘（防无谓 IO；门后仍发过层奖励）。
	RunState.start_run("vanguard")
	assert_int(RunState.next_floor()).is_equal(2)
	assert_int(SaveSystem.gems()).is_equal(0)
	assert_int(RunState.gems).is_equal(60)

func test_death_settlement_after_door_only_halves_unbanked_pool() -> void:
	# 口径披露：过层奖励/上层击杀蓝晶已在门全额入档（落袋为安），
	# 死亡 50% 只作用于其后本层未入账池——每颗蓝晶仍恰入档一次。
	RunState.start_run("vanguard")
	RunState.add_gems(50)
	assert_int(RunState.next_floor()).is_equal(2)          # 门：50 入档，池 = 60
	RunState.add_gems(70)                                  # 第 2 层击杀蓝晶 → 池 130
	assert_int(RunState.settle_death_gems()).is_equal(65)  # 死亡减半只折损未入账池
	assert_int(SaveSystem.gems()).is_equal(50 + 65)        # 门入档 50 + 死亡入账 65
	assert_int(RunState.gems).is_equal(0)
