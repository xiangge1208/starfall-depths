class_name TestHitstop
extends GdUnitTestSuite
## J-A：hitstop v2 导演（Juice v2 §2 J1 分层时间缩放 + J7 Boss 死亡定格链）TDD。
## 导演是纯逻辑状态机：apply_state / schedule / settings_host 全注入，时间由测试注入——
## 除标注「真实 Fx」的用例外不触碰 Engine.time_scale / 树暂停（用例结束即还原）。
## 数值唯一出处：res://data/balance.json 的 juice 节（JSON 数字一律 float，断言按 float 比）。

const BALANCE_PATH := "res://data/balance.json"
const SAVE_SYSTEM_SCRIPT := preload("res://autoload/save_system.gd")
const BOSS_ROW := {"id": "boss_ja", "hp": 100, "radius": 14.0, "phases": [1.0, 0.5]}
const FRAME := 10000   # 脑测注入帧基准（同 test_boss_base 习语）

var _tmp_paths: Array[String] = []
var _applied: Array = []      # 捕获 apply_state：[paused, scale]
var _scheduled: Array = []    # 捕获 schedule：[delay_ms, cb]
var _saved_director = null    # Fx._director 现场保管（用例后还原）


## push_error 间谍（同 test_save.gd SpySaver 惯例）：计数不刷控制台。
class SpyDirector extends HitstopDirector:
	var errors: Array[String] = []

	func _push_error(msg: String) -> void:
		errors.append(msg)


## 覆写 die() 且调 super 的替身——四真 Boss（gem_queen/magma_tyrant/frost_widow/prism_golem）
## 的 die() 形态，验证信号经子类覆写链仍恰发一次。
class SuperCallingBoss extends BossBase:
	func die() -> void:
		super()


func before_test() -> void:
	Fx.cancel_hitstop()
	_saved_director = Fx._director
	_applied.clear()
	_scheduled.clear()


func after_test() -> void:
	Fx._director = _saved_director
	Fx.cancel_hitstop()
	for path in _tmp_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_tmp_paths.clear()
	for child in Fx.get_children():                     # 委托用例产生的伤害数字/形状标签
		if child.name == "DamageNumber" or child.name == "ElementShape":
			child.free()


# ---- 装配 helpers ----

func _write_tmp(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	_tmp_paths.append(path)


## 临时路径设置宿主（不触真实 user://save.json，同 test_audio_mgr/_test_death_recorder 习语）。
func _settings_host(enabled: bool) -> Node:
	var s: Node = auto_free(SAVE_SYSTEM_SCRIPT.new())
	var path := "user://test_ja_settings_%d.json" % absi(randi())
	s.set("save_path", path)
	_tmp_paths.append(path)
	s.call("load_save")
	s.set_setting("hitstop_enabled", enabled)
	return s


## 裸导演（未加载 balance）+ 捕获式注入：时间完全由测试驱动。
func _bare(enabled := true) -> SpyDirector:
	var d := SpyDirector.new()
	d.settings_host = _settings_host(enabled)
	d.apply_state = func(paused: bool, scale: float) -> void:
		_applied.append([paused, scale])
	d.schedule = func(delay_ms: int, cb: Callable) -> void:
		_scheduled.append([delay_ms, cb])
	return d


func _fresh(enabled := true) -> SpyDirector:
	var d := _bare(enabled)
	d.load_balance_file(BALANCE_PATH)
	return d


func _ctx(amount: int) -> Dictionary:
	return {"amount": amount, "is_crit": false, "element": Elements.Id.NONE, "from": Vector2.ZERO}


# ---- 6. balance.json fail-closed 加载 ----

func test_shipped_balance_loads_with_all_required_params() -> void:
	var d := _fresh()
	assert_bool(d.load_ok).is_true()
	assert_int(d.errors.size()).is_equal(0)
	assert_float(d.param("kill_freeze_ms")).is_equal(20.0)
	assert_float(d.param("kill_recover_ms")).is_equal(60.0)
	assert_float(d.param("multikill_window_ms")).is_equal(300.0)
	assert_float(d.param("multikill_bonus_ms")).is_equal(40.0)
	assert_float(d.param("hitstop_cap_ms")).is_equal(120.0)
	assert_float(d.param("boss_phase_hitstop_ms")).is_equal(120.0)
	assert_float(d.param("boss_phase_slow_scale")).is_equal(0.3)
	assert_float(d.param("boss_phase_slow_ms")).is_equal(240.0)
	assert_float(d.param("boss_death_freeze_ms")).is_equal(300.0)
	assert_float(d.param("boss_death_slow_scale")).is_equal(0.3)
	assert_float(d.param("boss_death_slow_ms")).is_equal(900.0)
	assert_float(d.param("loot_delay_ms")).is_equal(300.0)
	assert_float(d.param("player_death_slow_scale")).is_equal(0.3)
	assert_float(d.param("player_death_slow_ms")).is_equal(600.0)
	assert_float(d.param("player_death_desat_ms")).is_equal(400.0)


func test_bad_json_fails_closed_and_requests_noop() -> void:
	var d := _bare()
	var path := "user://test_ja_bad_%d.json" % absi(randi())
	_write_tmp(path, "{ not json ")
	assert_bool(d.load_balance_file(path)).is_false()
	assert_bool(d.load_ok).is_false()
	d.request_kill(1000)
	d.request_boss_phase(1000)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_int(_applied.size()).is_equal(0)
	assert_int(d.errors.size()).is_equal(1)


func test_missing_required_key_fails_closed() -> void:
	var d := _bare()
	var path := "user://test_ja_misskey_%d.json" % absi(randi())
	_write_tmp(path, '{"version":1,"juice":{"kill_freeze_ms":20}}')
	assert_bool(d.load_balance_file(path)).is_false()
	assert_int(d.errors.size()).is_equal(1)


func test_wrong_type_value_fails_closed() -> void:
	var d := _bare()
	var path := "user://test_ja_badtype_%d.json" % absi(randi())
	_write_tmp(path, '{"juice":{"kill_freeze_ms":"20","kill_recover_ms":60,'
		+ '"multikill_window_ms":300,"multikill_bonus_ms":40,"hitstop_cap_ms":120,'
		+ '"boss_phase_hitstop_ms":120,"boss_phase_slow_scale":0.3,"boss_phase_slow_ms":240,'
		+ '"boss_death_freeze_ms":300,"boss_death_slow_scale":0.3,"boss_death_slow_ms":900,'
		+ '"loot_delay_ms":300,"player_death_slow_scale":0.3,"player_death_slow_ms":600,'
		+ '"player_death_desat_ms":400}}')
	assert_bool(d.load_balance_file(path)).is_false()
	assert_int(d.errors.size()).is_equal(1)


func test_missing_file_fails_closed() -> void:
	var d := _bare()
	assert_bool(d.load_balance_file("user://test_ja_absent_%d.json" % absi(randi()))).is_false()
	assert_bool(d.load_ok).is_false()
	assert_int(d.errors.size()).is_equal(1)


func test_unknown_keys_ignored_for_forward_compat() -> void:
	# J-B/J-C 会向 juice 节追加键：未知键忽略，必需键齐即过。
	var d := _bare()
	var path := "user://test_ja_extra_%d.json" % absi(randi())
	_write_tmp(path, '{"version":1,"juice":{"kill_freeze_ms":20,"kill_recover_ms":60,'
		+ '"multikill_window_ms":300,"multikill_bonus_ms":40,"hitstop_cap_ms":120,'
		+ '"boss_phase_hitstop_ms":120,"boss_phase_slow_scale":0.3,"boss_phase_slow_ms":240,'
		+ '"boss_death_freeze_ms":300,"boss_death_slow_scale":0.3,"boss_death_slow_ms":900,'
		+ '"loot_delay_ms":300,"player_death_slow_scale":0.3,"player_death_slow_ms":600,'
		+ '"player_death_desat_ms":400,"future_jb_key":123}}')
	assert_bool(d.load_balance_file(path)).is_true()
	assert_bool(d.load_ok).is_true()


# ---- 1. 击杀请求：80ms 缓出 = 20ms 全冻结 + 60ms 线性恢复 ----

func test_kill_ease_curve_sample_points() -> void:
	assert_float(HitstopDirector.ease_kill_scale(0, 20, 60)).is_equal(0.0)
	assert_float(HitstopDirector.ease_kill_scale(10, 20, 60)).is_equal(0.0)
	assert_float(HitstopDirector.ease_kill_scale(20, 20, 60)).is_equal(0.0)
	assert_float(HitstopDirector.ease_kill_scale(35, 20, 60)).is_equal_approx(0.25, 0.0001)
	assert_float(HitstopDirector.ease_kill_scale(50, 20, 60)).is_equal_approx(0.5, 0.0001)
	assert_float(HitstopDirector.ease_kill_scale(79, 20, 60)).is_equal_approx(0.9833, 0.001)
	assert_float(HitstopDirector.ease_kill_scale(80, 20, 60)).is_equal(1.0)
	assert_float(HitstopDirector.ease_kill_scale(200, 20, 60)).is_equal(1.0)


func test_kill_request_freezes_then_eases_to_restore() -> void:
	var d := _fresh()
	d.request_kill(1000)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.FREEZE)
	assert_bool(d.applied_paused()).is_true()
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_int(d.freeze_remaining_ms()).is_equal(20)
	assert_int(d.remaining_ms()).is_equal(80)
	# 段边界定时恰一：冻结段 20ms 到点强制（v1 权威定时器语义，帧率无关）
	assert_int(_scheduled.size()).is_equal(1)
	assert_int(_scheduled[0][0]).is_equal(20)
	var seg: Callable = _scheduled[0][1]
	d.tick(1010)
	assert_bool(d.applied_paused()).is_true()          # 冻结段保持
	d.tick(1020)                                       # 冻结毕 → 恢复段起点（0.0）
	assert_bool(d.applied_paused()).is_false()
	assert_float(d.applied_scale()).is_equal(0.0)
	d.tick(1050)                                       # 恢复段中点
	assert_float(d.applied_scale()).is_equal_approx(0.5, 0.0001)
	d.tick(1079)
	assert_float(d.applied_scale()).is_greater(0.9)
	d.tick(1080)                                       # 链尾：恢复时计
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_bool(d.applied_paused()).is_false()
	seg.call()                                         # 已结束：过期段回调不复活链、不排新段
	assert_int(_scheduled.size()).is_equal(1)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)


# ---- 2. 多杀窗口 + 叠加封顶 120ms ----

func test_multikill_third_kill_bonus_and_cap_120ms() -> void:
	var d := _fresh()
	d.request_kill(0)                       # 第 1 杀：80
	assert_int(d.remaining_ms()).is_equal(80)
	d.request_kill(100)                     # 第 2 杀（仅 1 前杀在窗）：仍 80，接管重启
	d.tick(100)
	assert_int(d.remaining_ms()).is_equal(80)
	d.request_kill(200)                     # 第 3 杀：+40 → 恰 120（=cap）
	d.tick(200)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.FREEZE)
	assert_int(d.freeze_remaining_ms()).is_equal(60)   # 追加进冻结段：60 冻 + 60 恢复
	assert_int(d.remaining_ms()).is_equal(120)
	d.request_kill(300)                     # 第 4 杀：仍封顶 120
	d.tick(300)
	assert_int(d.remaining_ms()).is_equal(120)
	d.tick(420)                             # 链尾恢复
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)


func test_multikill_window_boundary_exactly_300ms_counts() -> void:
	var d := _fresh()
	d.request_kill(0)
	d.request_kill(150)
	d.tick(150)
	d.request_kill(300)                     # 距两前杀恰 300/150ms：均在内 → 第 3 杀
	d.tick(300)
	assert_int(d.remaining_ms()).is_equal(120)


func test_kill_outside_window_no_bonus() -> void:
	var d := _fresh()
	d.request_kill(0)
	d.request_kill(100)
	d.request_kill(1000)                    # 距上一杀 900ms > 窗：普通击杀
	d.tick(1000)
	assert_int(d.remaining_ms()).is_equal(80)


# ---- 3a. Boss 阶段切换：120ms 冻结 → 0.3× 慢速 240ms → 恢复 ----

func test_boss_phase_freeze_then_slow_then_restore() -> void:
	var d := _fresh()
	d.request_boss_phase(5000)
	assert_bool(d.applied_paused()).is_true()
	assert_int(d.freeze_remaining_ms()).is_equal(120)
	assert_int(d.remaining_ms()).is_equal(360)
	d.tick(5119)
	assert_bool(d.applied_paused()).is_true()
	d.tick(5120)
	assert_bool(d.applied_paused()).is_false()
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(5359)                                       # 慢速段末拍前
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(5360)
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)


# ---- 3b. 玩家死亡：0.3× 慢速 600ms（desat 参数在位，落地 J-C） ----

func test_player_death_slow_window_and_desat_param() -> void:
	var d := _fresh()
	d.request_player_death(0)
	assert_bool(d.applied_paused()).is_false()          # 不冻结，只慢速
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(599)
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(600)
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.param("player_death_desat_ms")).is_equal(400.0)


# ---- 3c/5. Boss 死亡定格链：300 冻结 → 0.3× 900 慢速 → loot 300 → 恢复；skip 快进 ----

func test_boss_death_chain_freeze_slow_loot_restore() -> void:
	var d := _fresh()
	var loot: Array = []
	d.on_loot_delay_started = func() -> void:
		loot.append(1)
	d.request_boss_death(0)
	assert_bool(d.applied_paused()).is_true()
	assert_int(d.remaining_ms()).is_equal(1500)         # 300 + 900 + 300
	d.tick(299)
	assert_bool(d.applied_paused()).is_true()
	d.tick(300)
	assert_bool(d.applied_paused()).is_false()
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	assert_int(loot.size()).is_equal(0)
	d.tick(1199)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.SLOW)
	d.tick(1200)                                        # 慢速毕 → 战利品延迟段
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.LOOT_DELAY)
	assert_int(loot.size()).is_equal(1)                 # 进入即回调（J-C 喷出口）
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(1499)
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	d.tick(1500)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)


func test_boss_death_skip_jumps_to_chain_end_and_restores() -> void:
	var d := _fresh()
	var loot: Array = []
	d.on_loot_delay_started = func() -> void:
		loot.append(1)
	d.request_boss_death(0)
	d.tick(310)                                         # 定格毕、慢速中
	assert_int(loot.size()).is_equal(0)
	d.skip()
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_bool(d.applied_paused()).is_false()
	assert_int(loot.size()).is_equal(1)                 # 快进不吞 loot 段事件
	d.tick(2000)                                        # 链已结束：不再变化
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)


func test_scheduled_chain_end_restores_without_tick() -> void:
	# 生产保险：tick 停摆时段边界定时器仍逐段推进到链尾恢复时计（ignore_time_scale）。
	var d := _fresh()
	var loot: Array = []
	d.on_loot_delay_started = func() -> void:
		loot.append(1)
	d.request_boss_death(0)
	assert_int(_scheduled.size()).is_equal(1)
	assert_int(_scheduled[0][0]).is_equal(300)
	var cb1: Callable = _scheduled[0][1]
	cb1.call()                                          # 定格毕 → 慢速段
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.SLOW)
	assert_int(_scheduled.size()).is_equal(2)
	assert_int(_scheduled[1][0]).is_equal(900)
	var cb2: Callable = _scheduled[1][1]
	cb2.call()                                          # 慢速毕 → loot 延迟段
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.LOOT_DELAY)
	assert_int(loot.size()).is_equal(1)
	assert_int(_scheduled.size()).is_equal(3)
	assert_int(_scheduled[2][0]).is_equal(300)
	var cb3: Callable = _scheduled[2][1]
	cb3.call()                                          # 链尾恢复时计（无需任何 tick）
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)


func test_stale_segment_callback_from_replaced_sequence_is_ignored() -> void:
	var d := _fresh()
	d.request_kill(0)
	assert_int(_scheduled.size()).is_equal(1)
	var stale: Callable = _scheduled[0][1]
	d.request_boss_phase(10)                            # 360 > 剩 70 → 接管
	var fresh: Callable = _scheduled[1][1]
	stale.call()                                        # 旧链段回调不得掐掉新链
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.FREEZE)
	d.tick(11)
	assert_bool(d.applied_paused()).is_true()
	fresh.call()                                        # 冻结段到点 → 慢速段
	assert_bool(d.applied_paused()).is_false()
	assert_float(d.applied_scale()).is_equal_approx(0.3, 0.0001)
	var tail: Callable = _scheduled[2][1]
	tail.call()                                         # 慢速到点 → 链尾恢复
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)


# ---- 4. hitstop_enabled=false 短路（四类请求 + 直调冻结） ----

func test_disabled_short_circuits_all_requests() -> void:
	var d := _fresh(false)
	assert_bool(d.load_ok).is_true()
	d.request_kill(0)
	d.request_boss_phase(0)
	d.request_boss_death(0)
	d.request_player_death(0)
	d.request_freeze(40, 0)
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_bool(d.applied_paused()).is_false()
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_int(_applied.size()).is_equal(0)
	assert_int(_scheduled.size()).is_equal(0)


func test_failed_load_short_circuits_requests() -> void:
	var d := _bare()
	assert_bool(d.load_balance_file("user://test_ja_missing_%d.json" % absi(randi()))).is_false()
	d.request_kill(0)
	d.request_boss_phase(0)
	d.request_boss_death(0)
	d.request_player_death(0)
	d.request_freeze(40, 0)
	assert_int(_applied.size()).is_equal(0)
	assert_int(_scheduled.size()).is_equal(0)


# ---- 7a. 直调冻结路径（v1 hitstop 语义等价：取更长合并、fix1 不提前解冻） ----

func test_request_freeze_take_longer_no_early_unfreeze() -> void:
	var d := _fresh()
	d.request_freeze(40, 0)
	assert_bool(d.applied_paused()).is_true()
	d.request_freeze(60, 1)                             # 权威换 60ms（起点 t1）
	d.tick(50)                                          # 已越过旧 40ms 到期点
	assert_bool(d.applied_paused()).is_true()
	d.tick(61)
	assert_bool(d.applied_paused()).is_false()
	d.request_freeze(40, 200)
	d.request_freeze(10, 201)                           # 活动中更短 → 忽略
	d.tick(201)
	assert_int(d.remaining_ms()).is_equal(39)
	d.tick(240)                                         # 冻结到期恢复
	d.request_freeze(0, 300)                            # 0/负：不冻结
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)


# ---- 7b. fx.gd 委托：暴击/击杀/直调经导演；总开关短路；v1 回退 ----

func test_fx_kill_crit_and_direct_hitstop_delegate_to_director() -> void:
	var d := _fresh()
	Fx._director = d
	var host: Node2D = auto_free(Node2D.new())
	# 击杀路径 → 导演 KILL 序列（捕获注入：不真冻树/不动 time_scale）
	Fx.on_enemy_killed(Vector2.ZERO)
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.KILL)
	assert_int(d.freeze_remaining_ms()).is_less_equal(20)
	# 活动击杀链内更小的暴击 40ms 被「取更长」正确忽略（v1 权威语义推广）
	Fx.on_enemy_hit(host, {"amount": 5, "is_crit": true})
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.KILL)
	assert_bool(get_tree().paused).is_false()
	Fx.cancel_hitstop()
	# 暴击路径：hitstop(HITSTOP_CRIT_MS) 直调 → 导演 PLAIN_FREEZE
	Fx.on_enemy_hit(host, {"amount": 5, "is_crit": true})
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.PLAIN_FREEZE)
	assert_int(d.freeze_remaining_ms()).is_greater(0)
	assert_int(d.freeze_remaining_ms()).is_less_equal(40)
	Fx.cancel_hitstop()
	# 直调 hitstop 经导演
	Fx.hitstop(50)
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.PLAIN_FREEZE)
	assert_int(d.freeze_remaining_ms()).is_greater(40)
	assert_int(d.freeze_remaining_ms()).is_less_equal(50)
	assert_bool(get_tree().paused).is_false()


func test_fx_delegate_disabled_setting_never_pauses() -> void:
	var d := _fresh(false)
	Fx._director = d
	Fx.hitstop(40)
	Fx.on_enemy_killed(Vector2.ZERO)
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.NONE)
	assert_bool(get_tree().paused).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_fx_v1_fallback_when_director_absent() -> void:
	Fx._director = null
	Fx.hitstop(40)
	assert_bool(get_tree().paused).is_true()            # v1 树暂停路径
	await get_tree().create_timer(0.1, true, false, true).timeout
	assert_bool(get_tree().paused).is_false()


func test_fx_cancel_hitstop_cancels_director_chain_and_restores() -> void:
	var d := _fresh()
	Fx._director = d
	Fx.hitstop(80)
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.PLAIN_FREEZE)
	Fx.cancel_hitstop()
	assert_int(d.phase()).is_equal(HitstopDirector.Phase.IDLE)
	assert_float(d.applied_scale()).is_equal(1.0)
	assert_bool(d.applied_paused()).is_false()


func test_fx_request_boss_death_guarded_by_gameplay_scene() -> void:
	# gdUnit 前台非游戏场景（同 DeathRecorder 前台门）：脑测/套件里 Boss 死亡不冻结测试树。
	var d := _fresh()
	Fx._director = d
	Fx.request_boss_death()
	assert_int(d.active_kind()).is_equal(HitstopDirector.SeqKind.NONE)


# ---- 8. boss_base：死亡信号恰一次；阶段切换接线（真实 Fx，含新增慢速段） ----

func test_boss_base_defeated_signal_emitted_once_on_death() -> void:
	var e: BossBase = auto_free(BossBase.new())
	e._test_init(BOSS_ROW)
	var events: Array = []
	var cb := func(boss): events.append(boss)
	e.boss_defeated.connect(cb)
	e._take_hit_at(_ctx(50), FRAME)                     # 100→50 恰跨半血线：阶段非死亡
	assert_int(e.phase()).is_equal(1)
	assert_int(events.size()).is_equal(0)
	e._take_hit_at(_ctx(100), FRAME + 500)              # 致死：恰一次
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(events.size()).is_equal(1)
	assert_bool(events[0] == e).is_true()
	e._take_hit_at(_ctx(10), FRAME + 1000)              # 尸体不再发
	assert_int(events.size()).is_equal(1)


func test_boss_subclass_die_override_with_super_emits_once() -> void:
	var e: SuperCallingBoss = auto_free(SuperCallingBoss.new())
	e._test_init(BOSS_ROW)
	var n := [0]
	e.boss_defeated.connect(func(_boss): n[0] += 1)
	e.die()
	e.die()                                             # 状态门：重复调用不重复发
	assert_int(n[0]).is_equal(1)


func test_real_boss_subclass_emits_once_via_super_chain() -> void:
	# 真 Boss（覆写 die() 且调 super）：信号经子类链恰发一次。
	var e: GemQueen = auto_free(GemQueen.new())
	e._test_init({"id": "gem_queen", "hp": 10, "radius": 10.0})
	var n := [0]
	e.boss_defeated.connect(func(_boss): n[0] += 1)
	e._take_hit_at(_ctx(99), FRAME)
	assert_int(e.state).is_equal(EnemyBase.State.DEAD)
	assert_int(n[0]).is_equal(1)


func test_boss_phase_in_tree_freeze_then_slow_scale_with_real_fx() -> void:
	var e: BossBase = BossBase.new()
	e._test_init(BOSS_ROW)
	add_child(e)
	Fx.trauma = 0.0
	e._take_hit_at(_ctx(60), FRAME)                     # 100→40 跨半血线 → P1
	assert_int(e.phase()).is_equal(1)
	assert_bool(get_tree().paused).is_true()            # v1 既有语义：120ms 冻结
	assert_float(Fx.trauma).is_equal_approx(0.5, 0.001)   # m3-jb：v2 来源表注入（shake_boss_phase）
	await get_tree().create_timer(0.16, true, false, true).timeout
	assert_bool(get_tree().paused).is_false()
	assert_float(Engine.time_scale).is_equal_approx(0.3, 0.0001)   # J-A 新增慢速段
	await get_tree().create_timer(0.25, true, false, true).timeout
	assert_float(Engine.time_scale).is_equal(1.0)       # 链尾恢复时计
	e.free()


# ---- 生产接线钉（行数极简，时序逻辑由导演用例覆盖） ----

func test_production_wiring_lines_present() -> void:
	assert_bool(FileAccess.get_file_as_string("res://core/rooms/floor_scene.gd")
		.contains("Fx.request_boss_death()")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/meta/death_recorder.gd")
		.contains("Fx.request_player_death()")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/enemies/boss_base.gd")
		.contains("Fx.request_boss_phase()")).is_true()
