class_name TestInterFloor
extends GdUnitTestSuite
## m1-t20 层间流程：InterFloorFlow 状态机（BUFF→FOUNTAIN→DOOR→DONE）纯逻辑无头测试。
## 覆盖：阶段推进顺序 / 非法 buff 拒绝 / 喷泉一次 / 第 3 层胜利桩 /
## 乞丐 payout 70% 掷签（注入 rng 赢输两路）+ 付款层在本层层间门结算 /
## pending 与 paid_floor 同步清账 / next_floor 走 RunState。
##
## 掷签种子钉死（RandomNumberGenerator 首个 randf()）：
##   WIN_SEED=1  → 0.329559 < 0.7（返还）
##   LOSE_SEED=2 → 0.702882 >= 0.7（不返还，投资打水漂）

const WIN_SEED := 1
const LOSE_SEED := 2


## 空抽池管理器：钉死「三选为空 → 跳过 BUFF 直进 FOUNTAIN」的跳过规则。
class EmptyRollBuffManager extends BuffManager:
	func roll_three(_rng: RandomNumberGenerator) -> Array[String]:
		var empty: Array[String] = []
		return empty


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func _flow(floor_i: int) -> InterFloorFlow:
	var f := InterFloorFlow.new()
	f.setup(floor_i, BuffManager.new())
	return f


## 从 setup 一路推进到 DOOR（open → 选首项增益 → 注入 payout 流 → 喷泉）。
## payout_seed >= 0 时钉死乞丐掷签（否则 payout 兜底复用 open 的流，值不可预知）。
func _to_door(floor_i: int, roll_seed: int, payout_seed: int = -1) -> InterFloorFlow:
	var f := _flow(floor_i)
	f.open_with_offerings(_rng(roll_seed))
	assert_bool(f.choose_buff(f.offered[0])).is_true()
	if payout_seed >= 0:
		f.payout_rng = _rng(payout_seed)
	assert_bool(f.use_fountain(auto_free(Player.new()))).is_true()
	return f


# ================================================================ 阶段推进

func test_setup_starts_at_buff_phase() -> void:
	var f := _flow(1)
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_array(f.offered).is_empty()
	assert_bool(f.victory).is_false()
	assert_bool(f.fountain_used).is_false()

func test_phase_order_buff_fountain_door_done() -> void:
	RunState.start_run("vanguard")
	var f := _flow(1)
	var offered := f.open_with_offerings(_rng(WIN_SEED))
	# 三选一名录：1..3 条、互不重复、均为合法 buff id
	assert_int(offered.size()).is_between(1, 3)
	assert_int(f.offered.size()).is_equal(offered.size())
	var seen := {}
	for id: String in offered:
		assert_bool(GameDB.buffs.has(id)).is_true()
		assert_bool(seen.has(id)).is_false()
		seen[id] = true
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)

	var bm := f.buffs_manager
	assert_bool(f.choose_buff(offered[0])).is_true()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.FOUNTAIN)
	assert_array(bm.picked).is_equal([offered[0]])   # 经 buffs_manager.pick 落地

	assert_bool(f.use_fountain(auto_free(Player.new()))).is_true()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DOOR)

	# DOOR 阶段 advance 幂等停留（无乞丐投资时无事发生）
	f.advance()
	f.advance()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DOOR)

	var gems0 := RunState.gems
	assert_int(f.enter_next_floor()).is_equal(2)     # 真实 RunState.next_floor
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DONE)
	assert_int(RunState.floor_idx).is_equal(2)
	assert_int(RunState.gems).is_equal(gems0 + 60)   # §14.1 过层蓝晶结算

func test_advance_outside_door_is_noop() -> void:
	var f := _flow(1)
	f.advance()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)

func test_empty_offerings_skip_buff_phase() -> void:
	# 跳过规则：抽池空（roll_three 返回 []）→ 直接进 FOUNTAIN，不软锁
	var f := InterFloorFlow.new()
	f.setup(1, EmptyRollBuffManager.new())
	var offered := f.open_with_offerings(_rng(WIN_SEED))
	assert_array(offered).is_empty()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.FOUNTAIN)


# ================================================================ 增益选择

func test_choose_buff_unknown_id_rejected() -> void:
	var f := _flow(1)
	f.open_with_offerings(_rng(WIN_SEED))
	assert_bool(f.choose_buff("definitely_not_a_buff")).is_false()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_array(f.buffs_manager.picked).is_empty()

func test_choose_buff_valid_id_not_offered_rejected() -> void:
	var f := _flow(1)
	var offered := f.open_with_offerings(_rng(WIN_SEED))
	# 合法但不在本次三选内：fail-closed（未 offered 的 id 一律拒绝）
	var not_offered := ""
	for id: String in GameDB.buffs:
		if not offered.has(id):
			not_offered = id
			break
	assert_str(not_offered).is_not_empty()
	assert_bool(f.choose_buff(not_offered)).is_false()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_array(f.buffs_manager.picked).is_empty()

func test_choose_buff_before_open_rejected() -> void:
	# 未 open（offered 空）→ 任何选择拒绝（fail-closed 防软锁/防作弊路径）
	var f := _flow(1)
	assert_bool(f.choose_buff("swift_trigger")).is_false()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)

func test_choose_buff_wrong_phase_rejected() -> void:
	RunState.start_run("vanguard")
	var f := _to_door(1, WIN_SEED)          # 已到 DOOR
	assert_bool(f.choose_buff(f.offered[0])).is_false()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DOOR)


# ================================================================ 治疗喷泉

func test_fountain_heals_two_once() -> void:
	var p: Player = auto_free(Player.new())
	p.hp = 3
	var f := _flow(1)
	f.open_with_offerings(_rng(WIN_SEED))
	f.choose_buff(f.offered[0])
	assert_bool(f.use_fountain(p)).is_true()
	assert_int(p.hp).is_equal(5)            # 免费 +2
	assert_bool(f.fountain_used).is_true()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DOOR)
	# 一次契约：再按 E 无效（阶段已走 + used 旗双保险）
	assert_bool(f.use_fountain(p)).is_false()
	assert_int(p.hp).is_equal(5)

func test_fountain_caps_at_hp_max() -> void:
	var p: Player = auto_free(Player.new())
	p.hp = 7                                # hp_max=8：+2 只补到 8
	var f := _flow(1)
	f.open_with_offerings(_rng(WIN_SEED))
	f.choose_buff(f.offered[0])
	assert_bool(f.use_fountain(p)).is_true()
	assert_int(p.hp).is_equal(8)

func test_fountain_requires_fountain_phase() -> void:
	var p: Player = auto_free(Player.new())
	p.hp = 3
	var f := _flow(1)                       # BUFF 阶段直接按喷泉 → 拒绝
	assert_bool(f.use_fountain(p)).is_false()
	assert_int(p.hp).is_equal(3)
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)
	assert_bool(f.fountain_used).is_false()


# ================================================================ 第 3 层胜利桩

func test_floor3_victory_stub_skips_all_phases() -> void:
	RunState.start_run("vanguard")
	var f := _flow(3)
	var offered := f.open_with_offerings(_rng(WIN_SEED))
	assert_array(offered).is_empty()
	assert_bool(f.victory).is_true()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DONE)
	# 全阶段禁用：不能选增益 / 不能喷泉 / 不能进下一层
	assert_bool(f.choose_buff("swift_trigger")).is_false()
	assert_bool(f.use_fountain(auto_free(Player.new()))).is_false()
	assert_int(f.enter_next_floor()).is_equal(-1)
	assert_int(RunState.floor_idx).is_equal(1)   # 胜利路径不推层（RunState 维持 start_run 的 1）

func test_floor2_still_runs_full_flow() -> void:
	# 边界：floor_idx=2 不触发胜利桩，走全流程
	RunState.start_run("vanguard")
	var f := _flow(2)
	var offered := f.open_with_offerings(_rng(WIN_SEED))
	assert_array(offered).is_not_empty()
	assert_bool(f.victory).is_false()
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.BUFF)


# ================================================================ 下一层门

func test_enter_next_floor_requires_door_phase() -> void:
	RunState.start_run("vanguard")
	var f := _flow(1)                       # BUFF 阶段跳步进门 → 拒绝
	assert_int(f.enter_next_floor()).is_equal(-1)
	assert_int(RunState.floor_idx).is_equal(1)
	f.open_with_offerings(_rng(WIN_SEED))
	f.choose_buff(f.offered[0])             # FOUNTAIN 阶段跳步进门 → 拒绝
	assert_int(f.enter_next_floor()).is_equal(-1)
	assert_int(RunState.floor_idx).is_equal(1)


# ================================================================ 乞丐 payout 接缝（T19）

func test_beggar_payout_win_path() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0
	RunState.pending_investment = 120
	RunState.beggar_paid_floor = 1          # A1 付款，应在离开 A1 的层间门结算
	var f := _to_door(1, WIN_SEED, WIN_SEED)  # use_fountain → DOOR → advance 掷签
	assert_int(RunState.coins).is_equal(120) # 70% 命中：投资返还
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)
	assert_int(f.phase).is_equal(InterFloorFlow.Phase.DOOR)

func test_beggar_payout_lose_path() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0
	RunState.pending_investment = 120
	RunState.beggar_paid_floor = 1
	var f := _to_door(1, WIN_SEED, LOSE_SEED)  # 首 randf 0.7029 >= 0.7：不返还
	assert_int(RunState.coins).is_equal(0)
	assert_int(RunState.pending_investment).is_equal(0)   # 但 pending 仍结清（投资打水漂）
	assert_int(RunState.beggar_paid_floor).is_equal(0)

func test_beggar_payout_floor_mismatch_no_roll() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 0
	RunState.pending_investment = 5
	RunState.beggar_paid_floor = 2          # ≠ 当前待离开的 floor_idx(=1)：本层结不了
	var f := _to_door(1, WIN_SEED, WIN_SEED)
	f.advance()                             # 多拍重试也无效
	f.advance()
	assert_int(RunState.coins).is_equal(0)
	assert_int(RunState.pending_investment).is_equal(5)   # 投资保留，顺延到后续层门
	assert_int(RunState.beggar_paid_floor).is_equal(2)

func test_beggar_payout_no_pending_noop() -> void:
	RunState.start_run("vanguard")
	RunState.coins = 7
	RunState.pending_investment = 0
	RunState.beggar_paid_floor = 0
	var f := _to_door(1, WIN_SEED, WIN_SEED)
	assert_int(RunState.coins).is_equal(7)  # 无 pending：金币不动

func test_beggar_payout_resolves_once_per_door() -> void:
	# 赢路后 pending/paid_floor 清零：重复 advance/进门不会二次入账
	RunState.start_run("vanguard")
	RunState.coins = 0
	RunState.pending_investment = 120
	RunState.beggar_paid_floor = 1
	var f := _to_door(1, WIN_SEED, WIN_SEED)
	f.advance()
	assert_int(f.enter_next_floor()).is_equal(2)
	f.advance()
	assert_int(f.enter_next_floor()).is_equal(-1)
	assert_int(RunState.coins).is_equal(120)
	assert_int(RunState.pending_investment).is_equal(0)
	assert_int(RunState.beggar_paid_floor).is_equal(0)
