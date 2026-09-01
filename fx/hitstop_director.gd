class_name HitstopDirector
extends RefCounted
## J-A hitstop v2 导演（Juice v2 §2 J1/J7）：分层时间缩放的时间线状态机。
## 纯逻辑、无树依赖：真实效果（冻结树 / 设 Engine.time_scale / 恢复）经注入的
## apply_state 执行；定时经注入的 schedule（生产侧 ignore_time_scale 定时器，
## 测试侧捕获 (ms, cb) 手动推进）；时间全部由外部注入（请求 at_ms / tick(now_ms)），
## headless 测试完全确定。热路径零分配：tick 每帧调用，只做标量比较与赋值，
## 分配仅发生在事件驱动的请求时刻（允许）。
## 表现与判定红线（Juice v2）：本类只产「冻结/时间缩放」状态，不触碰任何数值与判定；
## hitstop_enabled=false 或 load_ok=false 时所有请求 no-op，游戏照常进行。

## 时间线段（查询用枚举；tick 内部按段边界推进）。
enum Phase { IDLE, FREEZE, RECOVER, SLOW, LOOT_DELAY }
## 序列种类（多杀窗口记杀数与种类无关；仅用于查询/调试）。
enum SeqKind { NONE, PLAIN_FREEZE, KILL, BOSS_PHASE, BOSS_DEATH, PLAYER_DEATH }

## 必需参数键（严格校验、未知键忽略——J-B/J-C 会向 juice 节追加键，前瞻兼容）。
const REQUIRED_KEYS: Array[String] = [
	"kill_freeze_ms", "kill_recover_ms", "multikill_window_ms", "multikill_bonus_ms",
	"hitstop_cap_ms", "boss_phase_hitstop_ms", "boss_phase_slow_scale", "boss_phase_slow_ms",
	"boss_death_freeze_ms", "boss_death_slow_scale", "boss_death_slow_ms", "loot_delay_ms",
	"player_death_slow_scale", "player_death_slow_ms", "player_death_desat_ms",
]

## 注入缝：apply_state(paused: bool, time_scale: float)——生产侧真正冻结树/设缩放/恢复。
var apply_state := Callable()
## 注入缝：schedule(delay_ms: int, callback: Callable)——生产侧 ignore_time_scale
## 定时器；测试侧捕获后手动触发（导演只保证回调幂等：换代号后旧回调失效）。
var schedule := Callable()
## 设置宿主注入（同 AudioMgr.settings_host 模式）：null 时读全局 SaveSystem。
var settings_host = null
## 战利品延迟段进入的一次性回调（J7；J-C 实际喷出在此接线，可空）。
var on_loot_delay_started := Callable()

var load_ok := false
var params := {}                       # 必需键 → float（JSON 数字一律 float）

# ---- 活动序列（扁平标量字段，tick 热路径零分配）----
var _seq_kind: int = SeqKind.NONE
var _start_ms := 0
var _freeze_ms := 0                    # 冻结段（树暂停）
var _recover_ms := 0                   # 线性恢复段（0→1，仅击杀）
var _slow_ms := 0                      # 慢速段（_slow_scale）
var _loot_ms := 0                      # 战利品延迟段（仍慢速，Boss 死亡专属）
var _slow_scale := 1.0
var _total_ms := 0
var _serial := 0                       # 序列代号：被替换/取消后旧链尾回调失效
var _phase: int = Phase.IDLE
var _fired_loot := false
var _applied_paused := false
var _applied_scale := 1.0
var _now_ms := 0

# ---- 多杀窗口（滚动双槽，零分配）：「第 3+ 杀」判定只需最近两次击杀时刻 ----
var _kill_prev1 := -(1 << 30)
var _kill_prev2 := -(1 << 30)


# ---- fail-closed 加载 ----

## 缺文件 / 解析失败 / 必需键缺失或类型错 → push_error + load_ok=false，
## 此后所有请求 no-op。取「不崩游戏」而非 quit：本类是表现层（GameDB 的
## 数据 quit 语义不适用），参数缺失只该降级为无演出，不该终止进程。
func load_balance_file(path: String) -> bool:
	load_ok = false
	params = {}
	if not FileAccess.file_exists(path):
		_push_error("HitstopDirector: balance 文件缺失：%s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_push_error("HitstopDirector: balance 解析失败：%s" % path)
		return false
	var juice: Variant = (parsed as Dictionary).get("juice")
	if typeof(juice) != TYPE_DICTIONARY:
		_push_error("HitstopDirector: balance 缺 juice 节：%s" % path)
		return false
	for key in REQUIRED_KEYS:
		if not (juice as Dictionary).has(key):
			_push_error("HitstopDirector: 缺必需键 juice.%s" % key)
			return false
		var v: Variant = (juice as Dictionary)[key]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			_push_error("HitstopDirector: juice.%s 非数值" % key)
			return false
		params[key] = float(v)
	load_ok = true
	return true


## 错误上报缝（测试子类覆写以计数，避免控制台噪声——同 test_save.gd SpySaver 惯例）。
func _push_error(msg: String) -> void:
	push_error(msg)


func param(key: String) -> float:
	return float(params.get(key, 0.0))


func pms(key: String) -> int:
	return int(param(key))


## 总开关（既有 hitstop_enabled 语义扩展）：false 时全部请求 no-op。
func is_enabled() -> bool:
	var host: Variant = settings_host if settings_host != null else SaveSystem
	return bool(host.get_setting("hitstop_enabled", true))


# ---- 查询 ----

func phase() -> int:
	return _phase


func active_kind() -> int:
	return _seq_kind


func remaining_ms() -> int:
	return maxi(0, _start_ms + _total_ms - _now_ms)


func freeze_remaining_ms() -> int:
	return maxi(0, _start_ms + _freeze_ms - _now_ms)


func applied_paused() -> bool:
	return _applied_paused


func applied_scale() -> float:
	return _applied_scale


# ---- 请求 API（事件驱动；at_ms 由生产侧注入表现层墙钟） ----

## 击杀（J1）：kill_freeze+kill_recover 缓出；0.3s 窗内第 3+ 杀追加
## multikill_bonus（进冻结段），叠加封顶 hitstop_cap。
## at_ms 用 Time.get_ticks_msec()（Fx 注入）——表现层墙钟，判定无关，允许；
## 窗口记杀与是否接管无关注册（击杀事件即计数）。
func request_kill(at_ms: int) -> void:
	if not _gate():
		return
	var window := pms("multikill_window_ms")
	var in_window := at_ms - _kill_prev1 <= window and at_ms - _kill_prev2 <= window
	_kill_prev2 = _kill_prev1
	_kill_prev1 = at_ms
	var total := pms("kill_freeze_ms") + pms("kill_recover_ms")
	if in_window:
		total = mini(total + pms("multikill_bonus_ms"), pms("hitstop_cap_ms"))
	_start_seq(SeqKind.KILL, total - pms("kill_recover_ms"), pms("kill_recover_ms"),
		0, 0, 1.0, at_ms)


## 直调冻结（v1 Fx.hitstop 等价路径）：纯树暂停 ms 毫秒，取更长合并。
func request_freeze(ms: int, at_ms: int = -1) -> void:
	if not _gate() or ms <= 0:
		return
	_start_seq(SeqKind.PLAIN_FREEZE, ms, 0, 0, 0, 1.0, at_ms if at_ms >= 0 else _now_ms)


## Boss 阶段切换（J1）：hitstop 冻结 → slow_scale 慢速 slow_ms → 恢复。
func request_boss_phase(at_ms: int = -1) -> void:
	if not _gate():
		return
	_start_seq(SeqKind.BOSS_PHASE, pms("boss_phase_hitstop_ms"), 0,
		pms("boss_phase_slow_ms"), 0, param("boss_phase_slow_scale"),
		at_ms if at_ms >= 0 else _now_ms)


## Boss 死亡（J7）：定格 → 慢速爆散 → 战利品延迟（仍慢速）→ 恢复时计。
func request_boss_death(at_ms: int = -1) -> void:
	if not _gate():
		return
	_start_seq(SeqKind.BOSS_DEATH, pms("boss_death_freeze_ms"), 0,
		pms("boss_death_slow_ms"), pms("loot_delay_ms"), param("boss_death_slow_scale"),
		at_ms if at_ms >= 0 else _now_ms)


## 玩家死亡（J1）：慢速 slow_ms（desat_ms 渐入参数随链存在，着色器落地在 J-C）。
func request_player_death(at_ms: int = -1) -> void:
	if not _gate():
		return
	_start_seq(SeqKind.PLAYER_DEATH, 0, 0, pms("player_death_slow_ms"), 0,
		param("player_death_slow_scale"), at_ms if at_ms >= 0 else _now_ms)


## Boss 死亡链快进（J7 连按攻击键）：跳到链尾——未发的 loot 段回调先补发
## （快进不吞事件），立即恢复时计。对其余链等价为立即结束（幂等）。
func skip() -> void:
	if _seq_kind == SeqKind.NONE:
		return
	_fire_loot()
	_serial += 1
	_finish()


## 立即结束活动链并恢复时计（Fx.cancel_hitstop 语义扩展：同时掐掉慢速链）。
func cancel() -> void:
	if _seq_kind == SeqKind.NONE:
		_apply(false, 1.0)     # 无链兜底：幂等确保时计归位
		return
	_serial += 1
	_finish()


## 时钟推进（生产侧 Fx._process 每渲染帧注入真实毫秒；测试侧注入任意值）。
func tick(now_ms: int) -> void:
	_now_ms = now_ms
	if _seq_kind == SeqKind.NONE:
		return
	_update_state(now_ms - _start_ms)


## 段状态推导（tick 与请求启动共用）：按链内偏移落段并应用对应冻结/缩放。
func _update_state(e: int) -> void:
	if e < 0:
		return                 # 时钟回拨守卫（异常注入不推进）
	if e < _freeze_ms:
		_set_phase(Phase.FREEZE, true, 1.0)
	elif e < _freeze_ms + _recover_ms:
		_set_phase(Phase.RECOVER, false, ease_kill_scale(e, _freeze_ms, _recover_ms))
	elif e < _freeze_ms + _recover_ms + _slow_ms:
		_set_phase(Phase.SLOW, false, _slow_scale)
	elif e < _total_ms:
		_set_phase(Phase.LOOT_DELAY, false, _slow_scale)
		_fire_loot()
	else:
		_finish()


# ---- 内部 ----

func _gate() -> bool:
	return load_ok and is_enabled()


## 启动序列（v1「权威定时器取更长」语义推广：新总时长 > 当前剩余才接管）。
func _start_seq(kind: int, freeze_ms: int, recover_ms: int, slow_ms: int, loot_ms: int,
		slow_scale: float, at_ms: int) -> void:
	var total := freeze_ms + recover_ms + slow_ms + loot_ms
	if total <= 0:
		return
	if _seq_kind != SeqKind.NONE and _start_ms + _total_ms - at_ms >= total:
		return                 # 已有更长演出在跑：忽略
	# J-C 必跟②：接管补偿——被替换链若有待发 loot（Boss 死亡链未走完 loot 段）立即补发
	# 一次（与 skip 的「快进不吞事件」对称；普通链 _loot_ms=0 无此段，天然跳过）。
	if _seq_kind != SeqKind.NONE and not _fired_loot and _loot_ms > 0:
		_fire_loot()
	_serial += 1              # 换代号：被替换链的链尾保险回调失效
	_seq_kind = kind
	_start_ms = at_ms
	_now_ms = at_ms
	_freeze_ms = freeze_ms
	_recover_ms = recover_ms
	_slow_ms = slow_ms
	_loot_ms = loot_ms
	_slow_scale = slow_scale
	_total_ms = total
	_fired_loot = false
	_update_state(0)          # 初始段统一由段推导落位（冻结段为 0 的链直接进慢速/恢复）
	_schedule_next_seg(0, _serial)


# ---- 段边界定时强制（v1 权威定时器语义推广：到点推进不依赖帧率） ----

## 下一段边界（> from_offset；0 = 无）。标量链实现：tick 热路径不调用，本函数仅在
## 请求/段回调时执行（事件驱动，允许分配）。
func _next_boundary(from_offset: int) -> int:
	var b1 := _freeze_ms
	var b2 := b1 + _recover_ms
	var b3 := b2 + _slow_ms
	if from_offset < b1:
		return b1
	if from_offset < b2:
		return b2
	if from_offset < b3:
		return b3
	if from_offset < _total_ms:
		return _total_ms
	return 0


func _schedule_next_seg(from_offset: int, serial: int) -> void:
	var nxt := _next_boundary(from_offset)
	if nxt <= from_offset or not schedule.is_valid():
		return
	schedule.call(nxt - from_offset, _seg_cb(nxt, serial))


## 请求时分配（事件驱动，允许）：段边界到点回调——把序列时钟对齐到目标偏移，
## 冻结→恢复→慢速→链尾的跨越与 v1 恢复一样由 ignore_time_scale 定时器保证，
## 低帧率（headless 套件/卡顿）不会推迟解冻；tick 仍负责段内连续缓动采样。
func _seg_cb(target_offset: int, serial: int) -> Callable:
	return func() -> void:
		_on_seg(target_offset, serial)


func _on_seg(target_offset: int, serial: int) -> void:
	if serial != _serial or _seq_kind == SeqKind.NONE:
		return
	_start_ms = _now_ms - target_offset   # 时钟对齐（真实到点时刻 ≈ 目标偏移）
	_update_state(target_offset)
	if _seq_kind != SeqKind.NONE:
		_schedule_next_seg(target_offset, serial)


func _set_phase(p: int, paused: bool, scale: float) -> void:
	_phase = p
	_apply(paused, scale)


## 幂等应用：状态真变才外呼（恢复段逐帧变缩放，冻结/慢速段去重）。
func _apply(paused: bool, scale: float) -> void:
	if _applied_paused == paused and is_equal_approx(_applied_scale, scale):
		return
	_applied_paused = paused
	_applied_scale = scale
	if apply_state.is_valid():
		apply_state.call(paused, scale)


func _finish() -> void:
	_seq_kind = SeqKind.NONE
	_phase = Phase.IDLE
	_apply(false, 1.0)


func _fire_loot() -> void:
	if _fired_loot:
		return
	_fired_loot = true
	if on_loot_delay_started.is_valid():
		on_loot_delay_started.call()


## 击杀缓出采样（J1）：前 freeze_ms 全冻结（0），后 recover_ms 线性恢复 0→1，越界夹取。
static func ease_kill_scale(elapsed_ms: int, freeze_ms: int, recover_ms: int) -> float:
	if elapsed_ms <= freeze_ms or recover_ms <= 0:
		return 0.0
	return clampf(float(elapsed_ms - freeze_ms) / float(recover_ms), 0.0, 1.0)
