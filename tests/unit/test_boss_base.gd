class_name TestBossBase
extends GdUnitTestSuite

## BossBase 三阶段框架（GDD §15）：血量线驱动阶段推进 + 72t 阶段无敌窗。
## 帧注入经 _take_hit_at 接缝（同 player.take_hit_ctx 模式），不经真实时钟。

const BOSS_ROW := {"id": "boss_test", "hp": 800, "radius": 14.0, "phases": [1.0, 0.6, 0.3]}
const FRAME := 10000   # 任取的注入帧基准（远离 0，避免与真实物理帧语义纠缠）

# ---- 血量线解析与 phase() ----

func test_phase_thresholds_floored_from_row() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	# 800×[1.0,0.6,0.3] → 绝对血线 [800,480,240]（floor）
	assert_int(e.hp).is_equal(800)
	assert_int(e.phase()).is_equal(0)

func test_threshold_floor_999_hp_03() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init({"id": "boss_test", "hp": 999, "radius": 14.0, "phases": [1.0, 0.3]})
	# floor(999×0.3)=floor(299.7)=299：299 入 P1，300 仍 P0
	e._take_hit_at(_ctx(700), FRAME)          # 999-700=299
	assert_int(e.hp).is_equal(299)
	assert_int(e.phase()).is_equal(1)

func test_threshold_floor_boundary_keeps_phase0() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init({"id": "boss_test", "hp": 999, "radius": 14.0, "phases": [1.0, 0.3]})
	e._take_hit_at(_ctx(699), FRAME)          # 999-699=300 > 299 → 未跨线
	assert_int(e.hp).is_equal(300)
	assert_int(e.phase()).is_equal(0)

# ---- 主剧本（brief TDD 清单）：481→P0 / 480→P1（无敌窗）/ 100→P2 / 不回退 / 死亡 ----

func test_phase_progression_script() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	# 800→481：未跨 480 线，仍 P0
	e._take_hit_at(_ctx(319), FRAME)
	assert_int(e.hp).is_equal(481)
	assert_int(e.phase()).is_equal(0)
	# 481→480：恰跨血线 → P1，进入 72t 无敌窗
	e._take_hit_at(_ctx(1), FRAME + 10)
	assert_int(e.hp).is_equal(480)
	assert_int(e.phase()).is_equal(1)
	assert_int(e._phase_invuln_until).is_equal(FRAME + 10 + 72)
	# 窗内（最后一拍 F+81 < F+82）：不掉血、不推进
	e._take_hit_at(_ctx(380), FRAME + 81)
	assert_int(e.hp).is_equal(480)
	assert_int(e.phase()).is_equal(1)
	# 窗外首拍（F+82）：恢复受击，打到 100 → P2
	e._take_hit_at(_ctx(380), FRAME + 82)
	assert_int(e.hp).is_equal(100)
	assert_int(e.phase()).is_equal(2)
	# 阶段只进不退：血量回升（外部改 hp 模拟）+ 零伤 hit 不回退
	e.hp = 700
	e._take_hit_at(_ctx(0), FRAME + 200)
	assert_int(e.phase()).is_equal(2)

func test_invuln_window_is_exactly_72_ticks() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	e._take_hit_at(_ctx(320), FRAME)          # 800→480 → P1，窗至 FRAME+72
	assert_int(e.phase()).is_equal(1)
	e._take_hit_at(_ctx(10), FRAME + 71)      # 窗内倒数第二拍：挡
	assert_int(e.hp).is_equal(480)
	e._take_hit_at(_ctx(10), FRAME + 72)      # frame == until：不 <，放行
	assert_int(e.hp).is_equal(470)

func test_phase_never_regresses_multi_cross_advance_only() -> void:
	# 单次大伤跨多条血线：一步推进到最深跨线阶段（不逐线停留、不回退）
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	e._take_hit_at(_ctx(700), FRAME)          # 800→100：跨 480 与 240 → 直接 P2
	assert_int(e.hp).is_equal(100)
	assert_int(e.phase()).is_equal(2)

# ---- boss_phase 信号：每次推进恰好一次 ----

func test_boss_phase_signal_emitted_once_per_transition() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	var events: Array = []
	var cb := func(boss, idx): events.append([boss, idx])
	EventBus.boss_phase.connect(cb)
	e._take_hit_at(_ctx(319), FRAME)          # 未跨线：不发
	e._take_hit_at(_ctx(1), FRAME + 10)       # → P1：一次
	e._take_hit_at(_ctx(380), FRAME + 82)     # → P2：一次
	e._take_hit_at(_ctx(0), FRAME + 200)      # 零伤不跨线：不发
	assert_int(events.size()).is_equal(2)
	assert_bool(events[0][0] == e).is_true()
	assert_int(events[0][1]).is_equal(1)
	assert_bool(events[1][0] == e).is_true()
	assert_int(events[1][1]).is_equal(2)
	EventBus.boss_phase.disconnect(cb)

# ---- 死亡路径不受影响 ----

func test_death_by_damage_outside_window() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	var killed: Array = []
	var cb := func(id): killed.append(id)
	EventBus.enemy_killed.connect(cb)
	e._take_hit_at(_ctx(1000), FRAME)         # 一击致死
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(killed.size()).is_equal(1)
	assert_str(killed[0]).is_equal("boss_test")
	EventBus.enemy_killed.disconnect(cb)

func test_dead_guard_after_death() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	e._take_hit_at(_ctx(1000), FRAME)
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	e._take_hit_at(_ctx(10), FRAME + 500)     # 尸体不再受击
	assert_int(e.hp).is_equal(-200)

func test_public_take_hit_delegates_to_seam() -> void:
	# 公共 take_hit（真实物理帧源）走同一接缝：初始无窗 → 正常扣血致死
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	e.take_hit(_ctx(1000))
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)

# ---- 子类契约：_on_phase_enter 钩子 + _engage 按 phase() 分支 ----

class PhaseSpy extends BossBase:
	var entered: Array = []
	func _on_phase_enter(idx: int) -> void:
		entered.append(idx)

class EngageSpy extends BossBase:
	var engage_log: Array = []      # [phase, frame]
	var engage_starts: Array = []
	func _engage(frame: int) -> void:
		engage_log.append([phase(), frame])
	func _on_engage_start(frame: int) -> void:
		engage_starts.append(frame)

func test_on_phase_enter_hook_called_with_index() -> void:
	var e: PhaseSpy = auto_free(PhaseSpy.new())
	e._test_init(BOSS_ROW)
	e._take_hit_at(_ctx(319), FRAME)          # 未跨线：无钩子
	assert_int(e.entered.size()).is_equal(0)
	e._take_hit_at(_ctx(1), FRAME + 10)       # → P1
	e._take_hit_at(_ctx(380), FRAME + 82)     # → P2
	assert_int(e.entered.size()).is_equal(2)
	assert_int(e.entered[0]).is_equal(1)
	assert_int(e.entered[1]).is_equal(2)

func test_subclass_engage_branches_on_phase() -> void:
	var e: EngageSpy = auto_free(EngageSpy.new())
	e._test_init(BOSS_ROW)
	e.on_player_seen(0)
	for f in range(1, 25):
		e.brain_tick(f)                       # 24t 警觉后进入 ENGAGE（_on_engage_start 一拍钩子）
	assert_array(e.engage_starts).is_equal([24])
	for f in range(25, 40):
		e.brain_tick(f)
	assert_int(e.engage_log[0][0]).is_equal(0)          # P0 分支
	e._take_hit_at(_ctx(320), 99999)          # → P1（跨 480 线）
	for f in range(40, 50):
		e.brain_tick(f)
	assert_int(e.engage_log.back()[0]).is_equal(1)      # P1 分支生效

# ---- 数据缺省：无 phases 行退化为单阶段（框架对普通行安全） ----

func test_missing_phases_defaults_single_phase() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init({"id": "boss_test", "hp": 100, "radius": 14.0})
	e._take_hit_at(_ctx(50), FRAME)
	assert_int(e.phase()).is_equal(0)
	assert_int(e.hp).is_equal(50)

func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}
