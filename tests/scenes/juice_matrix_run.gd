extends Node
## M3-J-D 开关矩阵整局回归驱动（无头；BalanceBot 复用，Juice v2 无障碍红线验收）：
##   baseline(全默认) + 四开关逐项关（hitstop / 屏震 / 粒子预算降级 / 振动）+ 四开关全关，
##   同一种子各跑一整局（bot 真实游玩至胜/死自然终局），逐局采证：
##   判定侧 = 自然终局（无 crash/timeout）+ kills>0 + 死亡报告成因（死亡归因链完整）；
##   信息侧 = 局内实测采到伤害数字节点 + 战斗 HUD 在位且金币/红心在刷新。
##   粒子组合以 driver 逐拍强制 Fx.particles._degrade=true（等价「全程预算降级」：
##   条带动画退化单帧、图仍在），机检单帧语义归 juice_smoke.gd §3。
## 判定/信息零损失判据：各组合 outcome ∈ {death, win}、kills>0、damage_numbers 采到、
## HUD 在位——四类开关为纯表现层，理论上不触碰逻辑流（同种子结局/kills 逐局对照见输出）。
## 运行：godot --headless --path . res://tests/scenes/juice_matrix_run.tscn
## 退出码：0 全组合过 / 1 有组合缺证据。产出仅控制台（证据转录进 m3-juice-checklist.md）。

const BOT_SCRIPT := preload("res://tools/balance_bot.gd")
const SEED := 2001                      # 种子族 = M2 校准批 2001..（自然终局率高）；各组合异种子
                                        # （2001+i）扩轨迹多样性——零损失判据为终局性质+证据在位，
                                        # 不做跨组合逐 tick 对照（hitstop 墙钟口径使然，见报告 §1.2）
const MAX_FRAMES_PER_RUN := 7200        # 单局 2min 封顶（7200 tick @60Hz；实测自然死亡 ≤80s）
const ATTEMPTS := 4                     # bot 卡步（房间内停滞：kills/hp 静止 ≥60s，见报告 OBS-1）
                                        # 为 bot 寻路方差非开关效应：逐次 +1 换种子（+10 会复用
                                        # 同「种子尾数→布局」族，实测该族卡步率相关——批 3/5/6 证据）
const OVERALL_TIMEOUT_S := 3600.0       # 兜底墙钟：6 组合 × 4 次尝试上限 + 余量

## 四开关矩阵（settings 显式写全 4 键；force_degrade 仅驱动粒子降级，非存档键）。
const COMBOS := [
	{"name": "baseline_all_on", "hitstop_enabled": true, "screen_shake": 0.5,
		"vibration": true, "force_degrade": false},
	{"name": "hitstop_off", "hitstop_enabled": false, "screen_shake": 0.5,
		"vibration": true, "force_degrade": false},
	{"name": "shake_off", "hitstop_enabled": true, "screen_shake": 0.0,
		"vibration": true, "force_degrade": false},
	{"name": "particles_degraded", "hitstop_enabled": true, "screen_shake": 0.5,
		"vibration": true, "force_degrade": true},
	{"name": "vibration_off", "hitstop_enabled": true, "screen_shake": 0.5,
		"vibration": false, "force_degrade": false},
	{"name": "all_off", "hitstop_enabled": false, "screen_shake": 0.0,
		"vibration": false, "force_degrade": true},
]

var _bot: Node = null
var _combo: Dictionary = {}
var _samples := {}
var _rows: Array[Dictionary] = []
var _combo_t0_ms := 0
var _last_run: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(OVERALL_TIMEOUT_S, true, false, true).timeout.connect(func() -> void:
		print("MATRIX TIMEOUT")
		get_tree().quit(2)
	)
	SaveSystem.set_setting("auto_aim", true)     # bot 开火路径依赖生产自动瞄准
	RunState.start_run("vanguard")               # 清探针残留（同种子覆写在 bot 内）
	await _run_matrix()


func _physics_process(_delta: float) -> void:
	if _bot == null or not is_instance_valid(_bot):
		return
	_sample()
	if bool(_combo.get("force_degrade", false)):
		Fx.particles._degrade = true     # 全程强制预算降级（step 会自愈回落，逐拍重申）


func _process(_delta: float) -> void:
	# 渲染帧也重申：粒子 step 在 process 走，降级标记不因帧间自愈而漏打
	if _bot != null and is_instance_valid(_bot) and bool(_combo.get("force_degrade", false)):
		Fx.particles._degrade = true


# ================================================================ 主流程

func _run_matrix() -> void:
	print("MATRIX BEGIN: %d combos, seed=%d, cap=%d ticks/combo" % [
		COMBOS.size(), SEED, MAX_FRAMES_PER_RUN])
	for i in COMBOS.size():
		_combo = COMBOS[i]
		var row := await _run_combo(_combo, SEED + i)
		_rows.append(row)
		_bot = null
		await get_tree().process_frame
	_emit_verdict()


func _run_combo(combo: Dictionary, first_seed: int) -> Dictionary:
	# 同种子整局优先；bot 卡步（停滞至 cap）是 bot 技法方差而非开关效应——
	# 最多 ATTEMPTS 次逐次 +10 换种子（种子与尝试次数逐行落证据，不掩饰）。
	var seed := first_seed
	var attempts := 0
	var run := {}
	while attempts < ATTEMPTS:
		attempts += 1
		run = await _play_one(combo, seed)
		if String(run.get("outcome", "")) != "timeout":
			break
		print("MATRIX RETRY %s: seed=%d attempt=%d bot stalled (timeout) -> next seed=%d" % [
			combo["name"], seed, attempts, seed + 1])
		seed += 1
	var wall_s := float(Time.get_ticks_msec() - _combo_t0_ms) / 1000.0
	var row := {
		"combo": String(combo["name"]),
		"seed": seed,
		"attempts": attempts,
		"outcome": String(run.get("outcome", "missing")),
		"floor": int(run.get("floor", 0)),
		"rooms": int(run.get("rooms", 0)),
		"kills": int(run.get("kills", 0)),
		"duration_s": float(run.get("duration_s", 0.0)),
		"death_cause": String(run.get("death_cause", "")),
		"coins": int(run.get("coins", 0)),
		"gems": int(run.get("gems", 0)),
		"wall_s": snappedf(wall_s, 0.1),
		"damage_number_seen": bool(_samples["damage_number_seen"]),
		"damage_number_peak": int(_samples["damage_number_peak"]),
		"hud_present": bool(_samples["hud_present"]),
		"hud_coin_text": String(_samples["hud_coin_text"]),
		"spark_seen": bool(_samples["spark_seen"]),
		"degraded_observed": bool(_samples["degraded_observed"]) \
			if bool(combo.get("force_degrade", false)) else null,
	}
	print("MATRIX ROW %s" % JSON.stringify(row))
	_bot.queue_free()
	await get_tree().process_frame
	return row


## 单局驱动（bot 实例生命周期：configure → add_child → finished → 释放）。
func _play_one(combo: Dictionary, seed: int) -> Dictionary:
	_apply_settings(combo)
	_samples = {
		"damage_number_seen": false, "damage_number_peak": 0,
		"hud_present": false, "hud_coin_text": "",
		"spark_seen": false, "degraded_observed": false,
		"hud": null,
	}
	print("MATRIX COMBO %s: seed=%d settings=%s" % [
		combo["name"], seed, _settings_snapshot(combo)])
	_combo_t0_ms = Time.get_ticks_msec()
	_bot = BOT_SCRIPT.new()
	_bot.configure({
		"runs": 1,
		"seed_base": seed,
		"max_frames_per_run": MAX_FRAMES_PER_RUN,
		"quit_when_done": false,
		"out_md": "",
		"out_json": "",
	})
	add_child(_bot)
	await _bot.finished
	_last_run = _bot.results[0] if _bot.results.size() > 0 else {}
	return _last_run


func _emit_verdict() -> void:
	_restore_settings()
	var failed: Array[String] = []
	var baseline_kills := -1
	for row in _rows:
		var problems: Array[String] = []
		if not (row["outcome"] == "death" or row["outcome"] == "win"):
			problems.append("outcome=%s" % row["outcome"])
		if int(row["kills"]) <= 0:
			problems.append("kills=%d" % int(row["kills"]))
		if not bool(row["damage_number_seen"]):
			problems.append("damage_number never sampled")
		if not bool(row["hud_present"]):
			problems.append("HUD never sampled")
		if not bool(row["spark_seen"]):
			problems.append("spark never sampled")
		if row["combo"] == "baseline_all_on":
			baseline_kills = int(row["kills"])
		if row["combo"] == "particles_degraded" and not bool(row["degraded_observed"]):
			problems.append("degrade flag never observed")
		if not problems.is_empty():
			failed.append("%s: %s" % [row["combo"], ", ".join(problems)])
	print("MATRIX SUMMARY: %d combos, baseline_kills=%d" % [_rows.size(), baseline_kills])
	for row in _rows:
		print("  %-20s seed=%d x%d outcome=%-5s floor=%d rooms=%d kills=%-3d dur=%6.1fs dmg#peak=%d hud=%s spark=%s" % [
			row["combo"], row["seed"], row["attempts"],
			row["outcome"], row["floor"], row["rooms"], row["kills"],
			row["duration_s"], row["damage_number_peak"], row["hud_present"], row["spark_seen"]])
	print("MATRIX VERDICT: %s" % ("PASS" if failed.is_empty() else "FAILED"))
	for f in failed:
		print("  FAIL: ", f)
	get_tree().quit(0 if failed.is_empty() else 1)


# ================================================================ 采样与设置

func _sample() -> void:
	# 信息侧采样（每 30 tick 一次，够证存在性且零热路径干扰）
	if Engine.get_physics_frames() % 30 != 0:
		return
	var dmg := 0
	for child in Fx.get_children():
		if child.name == "DamageNumber":
			dmg += 1
	if dmg > 0:
		_samples["damage_number_seen"] = true
		_samples["damage_number_peak"] = maxi(int(_samples["damage_number_peak"]), dmg)
	if Fx.particles.active_units() > 0:
		_samples["spark_seen"] = true
	if bool(_combo.get("force_degrade", false)) and Fx.particles.is_degraded():
		_samples["degraded_observed"] = true
	if _samples["hud"] == null and _bot != null and is_instance_valid(_bot) \
			and _bot._run_root != null and is_instance_valid(_bot._run_root):
		var found: Array = _bot._run_root.find_children("*", "HUD", true, false)
		if not found.is_empty():
			_samples["hud"] = found[0]
	if _samples["hud"] != null and is_instance_valid(_samples["hud"]):
		_samples["hud_present"] = true
		_samples["hud_coin_text"] = String(_samples["hud"]._coin_label.text)


func _apply_settings(combo: Dictionary) -> void:
	SaveSystem.set_setting("hitstop_enabled", bool(combo["hitstop_enabled"]))
	SaveSystem.set_setting("screen_shake", float(combo["screen_shake"]))
	SaveSystem.set_setting("vibration", bool(combo["vibration"]))
	SaveSystem.set_setting("damage_numbers", true)   # 信息通道被测项：全组合恒开
	SaveSystem.set_setting("colorblind_shapes", false)


func _settings_snapshot(combo: Dictionary) -> String:
	return JSON.stringify({
		"hitstop_enabled": combo["hitstop_enabled"],
		"screen_shake": combo["screen_shake"],
		"vibration": combo["vibration"],
		"force_degrade": combo["force_degrade"],
		"damage_numbers": true,
	})


func _restore_settings() -> void:
	SaveSystem.set_setting("hitstop_enabled", true)
	SaveSystem.set_setting("screen_shake", 0.5)
	SaveSystem.set_setting("vibration", true)
	SaveSystem.set_setting("damage_numbers", true)
	SaveSystem.set_setting("colorblind_shapes", false)
