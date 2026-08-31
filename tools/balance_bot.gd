extends Node
## Balance Bot（m2 计划 Task 27 / H-1，卡号 m2-t28）：无头自动游玩机器人，全层真实游玩回归。
##
## 基于 tests/scenes/m1_loop_smoke.gd 的无头循环驱动惯例扩展（走图算法同源复用：
## DFS 带回溯 + miniboss 前置 + boss 殿后；走廊徒步不模拟）。决策纯逻辑在
## tools/balance_bot_decisions.gd（确定性、单测钉死）；本文件只做「观测采集 →
## 决策调用 → 生产接口执行」。bot 与游戏的接口边界（无任何内部数值 hack——
## 不直改 HP/伤害/掉落，全部经由玩家真实操作面）：
##   1. 移动   —— Input.action_press/release("move_*")，与真人按键同路径
##                （player._physics_process 的 Input.get_vector 消费）。
##   2. 开火   —— PlayerDriver.touch_mode_override = true（生产触屏模式测试缝）：
##                PlayerDriver 以生产 auto_aim 逻辑选目标并自动开火——与手机玩家
##                同路径；另在战斗期按住物理 fire 键兜底（无目标时沿当前朝向）。
##   3. 翻滚   —— player.roll_ready_at(f) 守卫 + player.start_roll(dir, f)
##                （与 player._physics_process 按键路径同一方法）。
##   4. 技能   —— Skill.cast(f)（can_cast 内含 CD/耗蓝守卫，同 PlayerDriver 路径）。
##   5. 进房   —— FloorScene.enter_room(id)（同 m1_loop_smoke 惯例；生产 _push_back
##                在 enter_room 内落位新房中心，走廊徒步不模拟）。
##   6. 商店   —— shop.interact(player) → shop._buy_item("heart")（生产购买回调；
##                金币经 RunState.spend_coins 正常扣减）。
##   7. 事件   —— EventRoom.accept()（生产接受按钮回调；bot 策略=一律接受）。
##   8. 层间   —— inter._on_buff_chosen / flow.use_fountain / _on_door_interact
##                （m1_loop_smoke 同款「等价玩家按键」路径）。
##   9. 胜/死  —— run_root.victory_route_override / DeathRecorder.open_summary_override
##                （生产测试缝，替代真实跳场景以支持多局循环；死亡报告来自
##                DeathRecorder.build_report 生产口径）。
## 伤害/击杀/掉落/金币全部由生产战斗链路自然发生；bot 只读状态做启发式决策。
##
## 终局口径（重要，随基线演进自动适配）：
##   - 本基线（main c676657）A2/A3 层模板在 T26（并行在途）：run_root._on_next_floor_requested
##     的 _floor_data_available(2) 为假 → 过第 1 层门后落「A2 入口里程碑」
##     （run_root.a2_entry_active()，生产最小可玩端点）。bot 把它计为终局
##     outcome="milestone_a2"（内容上限到达，非崩溃非超时）。生产胜利（第 3 层
##     Boss 链）在本基线不可达——报告胜率带标注「不可评（内容缺口）」，不调数值凑数。
##   - T26 合并后同一 bot 无需改动即自动续走 2/3 层（循环对层数无假设）；
##     隐藏 Boss（A3 星陨先知）为波次外嘉宾，bot 对「已清房仍存活敌人」保持
##     战斗驱动（guests 分支），届时 +53/+353 经济即可对局采样。
##
## 局间隔离口径（披露）：每局 RunState.start_run 重置（种子被确定性覆写为
## seed_base+i）；SaveSystem 保持原状（headless 自动重定向 save_headless.json，
## 不污染真档）——图鉴/成就/Boss 首杀标记跨局累积，模拟真实玩家成长；影响见
## 报告「蓝晶获取曲线」节（vine_colossus 首杀 +300 只落在批次首局）。
##
## 运行：godot --headless --path . res://tools/balance_bot.tscn -- --runs=10 --seed-base=2001
##       可选 --time-scale=20 --max-frames-per-run=216000 --out-md=... --out-json=... --no-quit --debug
## 一键挂载：tools/run_balance.cmd（10 局 + 报告落 docs/superpowers/reports/）。
## 测试/冒烟以 configure() 注入参数后 add_child 复用本脚本（quit_when_done=false）。

signal finished

const RUN_ROOT_SCENE := preload("res://core/rooms/run_root.tscn")
const HEART_PRICE := 25                 # Shop.ITEM_PRICES.heart（买药决策入参）
const ROOM_MARGIN_PX := 18.0            # 房内墙距（outer 含 16px 墙）
const WANDER_SWITCH_TICKS := 45         # 切向游走符号换拍周期（0.75s，防抖动）
const CHARGE_READ_RADIUS_PX := 180.0    # 冲锋前摇读拍半径
const BOT_RUN_ROOT_LOST_GUARD := 8      # run_root 失效后仍存活的物理拍上限（崩溃判定）

# GDD §14.3 节奏校准目标带（只读对照，bot 不修改游戏数值）
const GDD_MINION_TTK_S := 2.0           # 初始武器打 A1 杂兵 ≤2.0s
const GDD_BOSS_S := [90.0, 150.0]       # Boss 战 90~150s
const GDD_ROOM_S := [20.0, 40.0]        # 单房 20~40s
const GDD_FLOOR_MIN := [8.0, 12.0]      # 单层 8~12min
const GDD_RUN_MIN := [25.0, 35.0]       # 单局 25~35min
const GDD_WIN_RATE := [0.20, 0.40]      # 本卡验收带（生产胜利口径；见终局口径披露）

var opts := {
	"runs": 10,
	"seed_base": 2001,
	"time_scale": 1.0,
	"max_frames_per_run": 64800,         # 18 局分钟守门（64800 tick @60tps 墙钟；
	                                     # 引擎 time_scale 对本作逐拍定步长逻辑无加速效用，
	                                     # 物理拍=墙钟拍，18 min 上限覆盖 GDD 单层 8~12min）
	"out_md": "",
	"out_json": "",
	"quit_when_done": true,              # 独立场景运行时自动退出
}

var results: Array[Dictionary] = []      # 每局：seed/outcome/floor/rooms/kills/duration_s/...
var aggregate := {}                      # 汇总（结局分布/TTK 分位/死亡热房/崩溃数）
var gems_curve: Array[Dictionary] = []   # {seed, floor, gems, frames} 层末/终局采样
var turret_intake := {}                  # source_id -> {dmg, first, last}（bot 实吃炮台伤）
var prophet_kills := 0                   # 星陨先知对局击杀数（⑥动态半边覆盖度）

var _run_root: Node2D = null
var _rng := RandomNumberGenerator.new()
var _won := false
var _fatal := false
var _milestone := false
var _death_report := {}
var _death_room_type := ""
var _plan: Array[int] = []
var _plan_fs: FloorScene = null
var _shop_done := {}
var _event_done := {}
var _buff_picks: Array[String] = []
var _wander_sign := 1.0
var _wander_next_switch := 0
# 统计采样（跨局累积，行内自带 floor/room_type 维度）
var _ttk_rows: Array[Dictionary] = []       # {floor, room_type, enemy_id, ttk_s}
var _ttk_seen := {}                         # enemy instance_id -> first_seen frame
var _track_room := -1
var _track_room_type := ""
var _track_room_cleared := false
var _room_entered_frame := -1
var _room_durations: Array[Dictionary] = [] # {floor, room_type, dur_s}
var _dur_fs: FloorScene = null              # 层时长：FloorScene 实例切换检测
var _dur_start_frame := -1
var _dur_floor_idx := 1
var _floor_durations: Array[Dictionary] = []  # {floor, dur_s}
var _watchdog_gen := 0
var _root_lost_ticks := 0
var _hearts_bought := 0
var _debug := false


func _ready() -> void:
	_parse_user_args()
	Engine.max_fps = 0
	Engine.max_physics_steps_per_frame = 64
	Engine.time_scale = float(opts["time_scale"])
	if not bool(SaveSystem.get_setting("auto_aim", true)):
		push_warning("BalanceBot: headless 档 auto_aim=false——生产自动瞄准停用，bot 开火退化为当前朝向")
	EventBus.player_hit_resolved.connect(_on_player_hit_resolved)
	_run_all()


func configure(p_opts: Dictionary) -> void:
	## 供测试/冒烟编程式注入（add_child 前调用）。
	for k in p_opts:
		opts[k] = p_opts[k]


func _exit_tree() -> void:
	EventBus.player_hit_resolved.disconnect(_on_player_hit_resolved)


# ================================================================ 多局编排

func _run_all() -> void:
	var runs := int(opts["runs"])
	var crashes := 0
	var timeouts := 0
	for i in runs:
		var outcome := await _run_one(int(opts["seed_base"]) + i)
		if outcome == "crash":
			crashes += 1
		elif outcome == "timeout":
			timeouts += 1
	aggregate = _aggregate(crashes)
	_write_outputs()
	print("BALANCE-BOT DONE: %d runs, wins=%d milestones=%d deaths=%d timeouts=%d crashes=%d" % [
		results.size(), int(aggregate.get("wins", 0)), int(aggregate.get("milestones", 0)),
		int(aggregate.get("deaths", 0)), timeouts, crashes])
	finished.emit()
	if bool(opts["quit_when_done"]) and get_tree() != null:
		# 门禁口径：崩溃或未走完（超时）即失败；死亡是合法对局结局。
		get_tree().quit(0 if crashes == 0 and timeouts == 0 else 1)


## 看门狗：单局 wall-clock 上限（ignore_time_scale），防逻辑死锁永悬进程。
## 代际号守卫：过期看门狗静默失效（SceneTreeTimer 无取消 API）。
func _arm_watchdog() -> void:
	_watchdog_gen += 1
	var gen := _watchdog_gen
	var t := get_tree().create_timer(2700.0, true, false, true)
	t.timeout.connect(func() -> void:
		if gen != _watchdog_gen:
			return
		print("BALANCE-BOT WATCHDOG TIMEOUT (wall 2700s)")
		get_tree().quit(2))


func _run_one(seed: int) -> String:
	_reset_run_state(seed)
	_arm_watchdog()
	RunState.start_run("vanguard")
	RunState.run_seed = seed                 # 种子覆写（口径披露：start_run 的墙钟
	RngSvc.setup_run(seed)                   # 种子被确定性种子替换，其余状态不变）
	_run_root = RUN_ROOT_SCENE.instantiate()
	add_child(_run_root)
	_run_root.victory_route_override = func() -> void:
		_won = true
	DeathRecorder.open_summary_override = func(report: Dictionary) -> void:
		_fatal = true
		_death_report = report
		_death_room_type = _track_room_type
	_run_root._begin()
	_enable_bot_firing(_run_root.player)
	var outcome := "timeout"
	while true:
		await get_tree().physics_frame
		if _run_root == null or not is_instance_valid(_run_root):
			_root_lost_ticks += 1            # 真实跳场景接管（不该发生）：崩溃计数
			if _root_lost_ticks > BOT_RUN_ROOT_LOST_GUARD:
				outcome = "crash"
				break
			continue
		_drive_tick()
		if Engine.get_physics_frames() % 1800 == 0:
			var prog_hp := -1
			var prog_player: Player = _run_root.player
			if prog_player != null and is_instance_valid(prog_player):
				prog_hp = prog_player.hp
			print("BOT-PROG seed=%d t=%.0fs floor=%d rooms=%d kills=%d hp=%d" % [
				seed, float(RunState.run_time_frames) / 60.0, RunState.floor_idx,
				RunState.rooms_cleared, RunState.kills, prog_hp])
		if _won:
			outcome = "win"
			break
		if _fatal:
			outcome = "death"
			break
		if _milestone:
			outcome = "milestone_a2"         # 内容上限（本基线生产终局，见头注）
			break
		if RunState.run_time_frames >= int(opts["max_frames_per_run"]):
			outcome = "timeout"
			break
	_close_floor_duration()                  # 胜利/死亡/里程碑/超时收尾：当前层时长入账
	_record_gems_sample(RunState.floor_idx)  # 终局蓝晶快照
	var boss_kills: Array = SaveSystem.data.get("boss_first_kills", [])
	var row := {
		"seed": seed,
		"outcome": outcome,
		"floor": RunState.floor_idx,
		"rooms": RunState.rooms_cleared,
		"kills": RunState.kills,
		"duration_s": snappedf(float(RunState.run_time_frames) / 60.0, 0.1),
		"coins": RunState.coins,
		"gems": RunState.gems,
		"hearts": _hearts_bought,
		"buffs": ",".join(_buff_picks),
		"death_floor": int(_death_report.get("stats", {}).get("floor", 0)) if _fatal else 0,
		"death_cause": String(_death_report.get("cause", "")) if _fatal else "",
		"death_room_type": _death_room_type if _fatal else "",
		"boss_first_kill_eligible": not boss_kills.has("vine_colossus"),
	}
	results.append(row)
	print("BALANCE-BOT RUN %d/%d: seed=%d outcome=%s floor=%d rooms=%d kills=%d dur=%.1fs coins=%d gems=%d hearts=%d death=%s(%s)" % [
		results.size(), int(opts["runs"]), seed, outcome, RunState.floor_idx, RunState.rooms_cleared,
		RunState.kills, float(RunState.run_time_frames) / 60.0, RunState.coins, RunState.gems,
		_hearts_bought, String(row["death_cause"]), String(row["death_room_type"])])
	if _run_root != null and is_instance_valid(_run_root):
		_run_root.free()
	_run_root = null
	DeathRecorder.open_summary_override = Callable()
	await get_tree().physics_frame
	return outcome


func _reset_run_state(p_seed: int) -> void:
	_won = false
	_fatal = false
	_milestone = false
	_death_report = {}
	_death_room_type = ""
	_plan = []
	_plan_fs = null
	_shop_done = {}
	_event_done = {}
	_buff_picks = []
	_wander_sign = 1.0
	_wander_next_switch = 0
	_root_lost_ticks = 0
	_hearts_bought = 0
	_ttk_seen = {}
	_track_room = -1
	_track_room_type = ""
	_track_room_cleared = false
	_room_entered_frame = -1
	_dur_fs = null
	_dur_start_frame = -1
	_rng.seed = p_seed


## 生产触屏模式测试缝：auto_aim 选目标 + 自动开火（手机玩家同路径）。
## 另在战斗期由 _set_fire_held 按住物理 fire 键兜底。
func _enable_bot_firing(player: Player) -> void:
	if player == null:
		return
	var driver: Node = player.get_node_or_null("Driver")
	if driver != null:
		driver.set("touch_mode_override", true)


func _set_fire_held(on: bool) -> void:
	_set_action("fire", on)


# ================================================================ 每拍驱动

func _drive_tick() -> void:
	if _run_root == null or not is_instance_valid(_run_root):
		return
	if _run_root.a2_entry_active():
		_milestone = true                   # A2 入口里程碑 = 本基线内容上限
		_release_move_input()
		_set_fire_held(false)
		return
	var player: Player = _run_root.player
	if player == null or not is_instance_valid(player):
		return
	var inter: Node2D = _run_root.inter_floor
	if inter != null and is_instance_valid(inter):
		_release_move_input()
		_set_fire_held(false)
		_drive_inter(inter, player)
		return
	var fs: FloorScene = _run_root.floor_scene
	if fs == null or not is_instance_valid(fs):
		return
	_track_floor_duration(fs)
	_drive_floor(fs, player)


func _drive_floor(fs: FloorScene, player: Player) -> void:
	var room_id := fs.flow.current_room
	var room: FloorScene.FloorRoom = fs.room_node(room_id)
	if room == null:
		_release_move_input()
		_set_fire_held(false)
		return
	var rtype := fs.flow.room_type(room_id)
	_track_room_entry(room_id, rtype)
	_track_enemy_ttk(fs, room)
	var guests := _alive_enemies(room)
	# 战斗驱动：波次未清，或房清后仍有存活波次外嘉宾（隐藏 Boss 同口径——死亡不回锁房）。
	if not fs.flow.is_cleared(room_id) or not guests.is_empty():
		_combat_drive(fs, room, player, guests)
		return
	# 已清房且无嘉宾：缺血先吃地上红心（elite hearts2 掉落等；磁吸拾取）→ 设施 → 走图
	_release_move_input()
	_set_fire_held(false)
	if player.hp <= player.hp_max - 2:
		var heart := _nearest_heart(room, player.global_position)
		if heart != null:
			_apply_move_input(heart.global_position - player.global_position)
			_set_fire_held(false)
			return
	var fkey := _facility_key(room_id)
	if rtype == "shop" and not _shop_done.has(fkey):
		_shop_done[fkey] = true
		_do_shop(room, player)
		return
	if rtype == "event" and not _event_done.has(fkey):
		_event_done[fkey] = true
		_do_event(room)
		return
	var nxt := _next_room(fs)
	if nxt >= 0 and nxt != room_id and fs.enter_room(nxt):
		pass                                # 落位由生产 enter_room→_push_back 完成


## 设施一次性键：层号×房号（房型 id 跨层重复，裸 room_id 会误判已交互）。
func _facility_key(room_id: int) -> int:
	return RunState.floor_idx * 1000 + room_id


# ---------------- 战斗驱动（观测 → BalanceBotDecisions → 生产接口） ----------------

func _combat_drive(fs: FloorScene, room: FloorScene.FloorRoom, player: Player,
		alive: Array[EnemyBase]) -> void:
	var frame := Engine.get_physics_frames()
	var pos := player.global_position
	var bounds: Rect2 = room.outer.grow(-ROOM_MARGIN_PX)
	if frame >= _wander_next_switch:
		_wander_sign = 1.0 if _rng.randf() < 0.5 else -1.0
		_wander_next_switch = frame + WANDER_SWITCH_TICKS

	# 观测采集：敌弹 / 活敌（自爆型单列为 bombers，不进距离带/近战目标——趋近它们
	# 只会贴脸引信）/ hazard 判定域
	var bullets: Array = []
	var combat: CombatSystem = room.combat
	if combat != null and combat.pool != null:
		for p in combat.pool.active:
			if is_instance_valid(p) and p.faction == Projectile.Faction.ENEMY:
				bullets.append({"pos": p.position, "vel": p.vel})
	var bombers := _bombers_observation(alive)
	var enemies: Array = []
	for e in alive:
		if not _is_bomber_row(e.row):
			enemies.append(e.brain_pos)
	var hazards := _hazard_zones(fs)

	# 决策：走位（避弹/避爆炸域/避 hazard/近敌拉开/距离带）→ 8 向生产输入
	var dir := BalanceBotDecisions.combat_move_dir(pos, bounds, bullets, enemies,
		hazards, _wander_sign, bombers)
	_apply_move_input(dir)

	# 决策：翻滚（贴弹/冲锋临身/近战贴脸 panic；概率采样来自 bot 确定性 rng）
	var nearest_bullet_d := INF
	var bullet_away := Vector2.ZERO
	for b in bullets:
		var to: Vector2 = pos - b["pos"]
		var d := to.length()
		if d < nearest_bullet_d:
			nearest_bullet_d = d
			bullet_away = to / maxf(d, 1.0)
	var bomber_d := INF
	var bomber_away := Vector2.ZERO
	for b in bombers:
		var db: float = pos.distance_to(b["pos"]) - float(b["radius"])
		if db < bomber_d:
			bomber_d = db
			bomber_away = (pos - (b["pos"] as Vector2)) \
				/ maxf(pos.distance_to(b["pos"]), 1.0)
	var nearest_d := INF
	var nearest_away := Vector2.ZERO
	var charge_perp := Vector2.ZERO
	var nearest := _nearest_of(alive, pos)
	if nearest != null:
		nearest_d = nearest.brain_pos.distance_to(pos)
		nearest_away = (pos - nearest.brain_pos) / maxf(nearest_d, 1.0)
		charge_perp = _read_charge_telegraph(nearest, pos)
	# 引信已点燃的自爆虫在场：翻滚优先留给爆炸（bullet_d 压成 INF 抑制贴弹翻滚——
	# 普通弹靠走位甩，确定性大伤才值得花 CD）。
	var roll_bullet_d := nearest_bullet_d
	for b in bombers:
		if bool(b.get("armed", false)):
			roll_bullet_d = INF
			break
	var roll := BalanceBotDecisions.roll_decision({
		"roll_ready": player.roll_ready_at(frame),
		"bullet_d": roll_bullet_d, "bullet_away": bullet_away,
		"bomber_d": bomber_d, "bomber_away": bomber_away,
		"charge_perp": charge_perp,
		"melee_d": nearest_d, "melee_away": nearest_away,
		"roll_sample": _rng.randf(), "panic_sample": _rng.randf(),
		"side_sample": _rng.randf(),
	})
	if bool(roll["do"]):
		var rd: Vector2 = roll["dir"]
		player.start_roll(rd if rd.length_squared() > 0.0 else player.facing, frame)

	# 技能（CD/耗蓝守卫在生产 can_cast 内）+ 索敌开火（生产 auto_aim 路径）
	var skill: SkillBase = player.get_node_or_null("Skill") as SkillBase
	if skill != null:
		skill.cast(frame)
	_set_fire_held(true)
	_nudge_aim_if_unlocked(player, alive, pos)
	if _debug and frame % 60 == 0:
		print("BOT-DBG f=%d hp=%d/%d shield=%d pos=%s room=%d(%s) alive=%d bullets=%d bombers=%d dir=%s aim=%s" % [
			frame, player.hp, player.hp_max, player.shield,
			str(player.global_position.round()), room.room_id, fs.flow.room_type(room.room_id),
			alive.size(), bullets.size(), bombers.size(), str(dir.round()),
			str((player.get_node_or_null("Driver") as Node).get("current_aim"))])


## 瞄准摇杆等价注入（接口披露见头注 2）：生产 auto_aim 只在「当前瞄准向 60° 锥内」
## 重锁目标（AutoAim.pick_target 契约），锥外敌人永远锁不上——真实触屏玩家此时会
## 拨右摇杆换向。bot 在且仅在 Driver 本拍未锁目标（_auto_target_locked=false）时，
## 把 driver.current_aim 转向最近活敌（与触屏摇杆同字段的同一消费路径），下一拍
## 生产锥选自然重锁。锁着不动（不抢生产 auto_aim 的选择权）。
func _nudge_aim_if_unlocked(player: Player, alive: Array[EnemyBase], pos: Vector2) -> void:
	if alive.is_empty():
		return
	var driver: Node = player.get_node_or_null("Driver")
	if driver == null or bool(driver.get("_auto_target_locked")):
		return
	var target: EnemyBase = null
	var best_d := INF
	for e in alive:
		if not is_instance_valid(e):
			continue
		var d := e.brain_pos.distance_to(pos)
		if d < best_d:
			best_d = d
			target = e
	if target != null and best_d > 1.0:
		driver.set("current_aim", (target.brain_pos - pos).normalized())


## 房内最近红心掉落（缺血时顺路吃；combat 期不冒险绕路，只在本房已清时吃）。
func _nearest_heart(room: FloorScene.FloorRoom, pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for c in room.get_children():
		if c is Pickup and (c as Pickup).kind == "heart" and is_instance_valid(c):
			var d: float = (c as Node2D).global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = c as Node2D
	return best


## 自爆型敌人判定（suicide 原型 + 自爆网虫特型——两型行内都有 aoe 引爆契约）。
func _is_bomber_row(row: Dictionary) -> bool:
	var arch := String(row.get("archetype", ""))
	return arch == "suicide" or arch == "zibao_wangchong"


## 自爆虫观测：全部自爆型进 bombers（未点燃=armed false 走保距；点燃=armed true
## 走强逃/翻滚）。点燃态 = suicide 原型 `_fuse_deadline >= 0`（玩家可观察的膨胀
## 预警窗；无该字段的特型按已点燃强度处理——保守规避）。
func _bombers_observation(alive: Array[EnemyBase]) -> Array:
	var out: Array = []
	for e in alive:
		if not _is_bomber_row(e.row):
			continue
		var fd: Variant = e.get("_fuse_deadline")
		var armed := fd == null or int(fd) >= 0
		out.append({"pos": e.brain_pos, "radius": float(e.row.get("aoe_radius", 40)),
			"armed": armed})
	return out


## 活敌中最近的非自爆型（距离带/近战/冲锋读拍目标；无则 null）。
func _nearest_of(alive: Array[EnemyBase], pos: Vector2) -> EnemyBase:
	var best: EnemyBase = null
	var best_d := INF
	for e in alive:
		if not is_instance_valid(e) or _is_bomber_row(e.row):
			continue
		var d := e.brain_pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


## 冲锋前摇读拍（玩家可观察的红闪 telegraph）：windup 且冲刺指向自己 → 垂直闪避向。
func _read_charge_telegraph(e: EnemyBase, pos: Vector2) -> Vector2:
	if e == null or not is_instance_valid(e):
		return Vector2.ZERO
	var phase_v: Variant = e.get("_phase")
	if phase_v == null or String(phase_v) != "windup":
		return Vector2.ZERO
	var dash_v: Variant = e.get("_dash_dir")
	if dash_v == null or dash_v is not Vector2:
		return Vector2.ZERO
	var dash_dir: Vector2 = dash_v
	var to_p := pos - e.brain_pos
	if to_p.length() < CHARGE_READ_RADIUS_PX and dash_dir.length() > 0.1 \
			and dash_dir.normalized().dot(to_p.normalized()) > 0.8:
		var d := dash_dir.normalized()
		return Vector2(-d.y, d.x)
	return Vector2.ZERO


func _hazard_zones(fs: FloorScene) -> Array:
	var zones: Array = []
	for i in fs.hazard_spikes_count():
		zones.append(fs.hazard_spike(i).zone)
	for i in fs.hazard_geyser_count():
		zones.append(fs.hazard_geyser(i).zone)
	if fs.hazard_magma != null:
		for z: Rect2 in fs.hazard_magma.zones:
			zones.append(z)
	if fs.hazard_vines != null:
		for z: Rect2 in fs.hazard_vines.zones:
			zones.append(z)
	return zones


func _alive_enemies(room: FloorScene.FloorRoom) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in room.enemies:
		if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
			out.append(e)
	return out


func _apply_move_input(dir: Vector2) -> void:
	# 8 向量化（规避 action deadzone 吞斜向小分量）；get_vector 消费端归一化斜向。
	var dx := 0.0
	var dy := 0.0
	if dir.x > 0.35:
		dx = 1.0
	elif dir.x < -0.35:
		dx = -1.0
	if dir.y > 0.35:
		dy = 1.0
	elif dir.y < -0.35:
		dy = -1.0
	_set_action("move_right", dx > 0.0)
	_set_action("move_left", dx < 0.0)
	_set_action("move_down", dy > 0.0)
	_set_action("move_up", dy < 0.0)


func _set_action(action: String, on: bool) -> void:
	if on:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _release_move_input() -> void:
	for a in ["move_right", "move_left", "move_down", "move_up"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


# ---------------- 设施（商店买药 / 事件接受） ----------------

func _do_shop(room: FloorScene.FloorRoom, player: Player) -> void:
	for c in room.get_children():
		if c is Shop:
			var shop := c as Shop
			shop.interact(player)
			# 买药决策（缺血 ≥2 且买得起）；扣款走 RunState.spend_coins 生产路径。
			if BalanceBotDecisions.buy_heart(player.hp, player.hp_max,
					RunState.coins, HEART_PRICE, false):
				var before := RunState.coins
				shop._buy_item("heart")
				if RunState.coins < before:
					_hearts_bought += 1
			shop.close()
			return


func _do_event(room: FloorScene.FloorRoom) -> void:
	for c in room.get_children():
		if c is EventRoom and (c as EventRoom).ui_visible():
			(c as EventRoom).accept()   # bot 策略：一律接受（正负事件同权重，披露）
			return


# ---------------- 层间（三选一贪心 → 喷泉 → 门） ----------------

func _drive_inter(inter: Node2D, player: Player) -> void:
	var flow: InterFloorFlow = inter.flow
	match int(flow.phase):
		InterFloorFlow.Phase.BUFF:
			if flow.offered.is_empty():
				return
			var rows := {}
			for id: String in flow.offered:
				rows[id] = GameDB.get_buff(id)
			var pick: String = BalanceBotDecisions.greedy_pick(flow.offered, rows,
				player.hp_max - player.hp)
			_buff_picks.append(pick)
			inter._on_buff_chosen(pick)
		InterFloorFlow.Phase.FOUNTAIN:
			flow.use_fountain(player)           # 幂等（fountain_used 守卫）
		InterFloorFlow.Phase.DOOR:
			_record_gems_sample(RunState.floor_idx)   # 过层前蓝晶快照
			inter._on_door_interact(player)           # → next_floor_requested → 换层/里程碑
		_:
			pass


# ---------------- 走图计划（算法同 m1_loop_smoke._walk_order） ----------------

func _next_room(fs: FloorScene) -> int:
	if _plan_fs != fs:
		_plan_fs = fs
		_plan = _walk_order(fs)
	var cur := fs.flow.current_room
	var idx := _plan.find(cur)
	if idx < 0 or idx + 1 >= _plan.size():
		return -1
	return _plan[idx + 1]                   # 沿计划逐步走（清房战斗在步进中自然发生）


func _walk_order(fs: FloorScene) -> Array[int]:
	var start := fs.flow.start_room()
	var miniboss := fs.flow.miniboss_room()
	var boss := fs.flow.boss_room()
	var moves: Array[int] = []
	_dfs(fs, start, {start: true}, miniboss, boss, moves)
	if miniboss >= 0:
		var chain := _path_to(fs, start, miniboss)
		chain.pop_front()                    # start 已在（DFS 起点）
		moves.append_array(chain)
		moves.append(miniboss)
	if boss >= 0:
		moves.append(boss)
	return moves


func _dfs(fs: FloorScene, cur: int, seen: Dictionary, miniboss: int, boss: int,
		moves: Array[int]) -> void:
	for n in fs.flow.adjacent(cur):
		if seen.has(n) or n == miniboss or n == boss:
			continue
		seen[n] = true
		moves.append(n)
		_dfs(fs, n, seen, miniboss, boss, moves)
		moves.append(cur)                    # 回溯（回走已清房，enter_room 幂等）


func _path_to(fs: FloorScene, start: int, target: int) -> Array[int]:
	var parent := {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == target:
			break
		for n in fs.flow.adjacent(cur):
			if not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var path: Array[int] = []
	var cur2 := target
	while cur2 != start:
		path.push_front(cur2)
		cur2 = int(parent[cur2])
	path.push_front(start)
	return path


# ================================================================ 统计采样

func _track_room_entry(room_id: int, rtype: String) -> void:
	if room_id == _track_room:
		return
	_track_room = room_id
	_track_room_type = rtype
	_track_room_cleared = false
	_room_entered_frame = Engine.get_physics_frames()
	_ttk_seen.clear()


## 清房时长入账：入房 → 房清（含战斗全部波次；死亡/超时未清房不入账）。
func _track_room_clear(fs: FloorScene) -> void:
	if _track_room < 0 or _track_room_cleared or _room_entered_frame < 0:
		return
	if not FloorFlow.COMBAT_TYPES.has(_track_room_type):
		_track_room_cleared = true
		return
	if not fs.flow.is_cleared(_track_room):
		return
	_track_room_cleared = true
	var dur := float(Engine.get_physics_frames() - _room_entered_frame) / 60.0
	if dur >= 2.0:
		_room_durations.append({
			"floor": RunState.floor_idx,
			"room_type": _track_room_type,
			"dur_s": snappedf(dur, 0.1),
		})


## TTK 采样：首见敌人时挂生产 `died` 信号（一次性）——死亡体当拍即从
## room.enemies 摘除，轮询口观察不到死亡；TTK = 首见→死亡（入房起测，
## 与 §14.3「打 A1 杂兵 ≤2.0s」的交入口径同源）。
func _track_enemy_ttk(fs: FloorScene, room: FloorScene.FloorRoom) -> void:
	var frame := Engine.get_physics_frames()
	for e in room.enemies:
		if not is_instance_valid(e):
			continue
		var key := e.get_instance_id()
		if _ttk_seen.has(key):
			continue
		_ttk_seen[key] = frame
		var eid := String(e.row.get("id", ""))
		var rtype := String(fs.flow.room_type(room.room_id))
		var floor_idx := RunState.floor_idx
		e.died.connect(_on_tracked_enemy_died.bind(eid, frame, floor_idx, rtype),
			CONNECT_ONE_SHOT)
	_track_room_clear(fs)


func _on_tracked_enemy_died(_e: EnemyBase, eid: String, born_frame: int,
		floor_idx: int, rtype: String) -> void:
	_ttk_rows.append({
		"floor": floor_idx,
		"room_type": rtype,
		"enemy_id": eid,
		"ttk_s": snappedf(float(Engine.get_physics_frames() - born_frame) / 60.0, 0.1),
	})
	if eid == "starfall_prophet":
		prophet_kills += 1        # ⑥动态半边覆盖度（本基线 A3 不可达 → 预期 0）


func _track_floor_duration(fs: FloorScene) -> void:
	if fs != _dur_fs:
		_close_floor_duration()
		_dur_fs = fs
		_dur_start_frame = Engine.get_physics_frames()
		_dur_floor_idx = RunState.floor_idx


## 层时长入账：仅当该层 boss 房已清（= 本层完成）才记录。
func _close_floor_duration() -> void:
	if _dur_fs == null or not is_instance_valid(_dur_fs) or _dur_start_frame < 0:
		return
	var boss := _dur_fs.flow.boss_room()
	if boss >= 0 and _dur_fs.flow.is_cleared(boss):
		var dur := float(Engine.get_physics_frames() - _dur_start_frame) / 60.0
		if dur > 10.0:
			_floor_durations.append({"floor": _dur_floor_idx, "dur_s": snappedf(dur, 0.1)})
	_dur_fs = null
	_dur_start_frame = -1


func _record_gems_sample(floor_idx: int) -> void:
	gems_curve.append({
		"seed": int(opts["seed_base"]) + results.size(),
		"floor": floor_idx,
		"gems": RunState.gems,
		"frames": RunState.run_time_frames,
	})


## bot 实吃伤害速率采样（校准点①的动态半边：炮台来源聚合；走位相关仅供参考）。
func _on_player_hit_resolved(amount: int, _fatal: bool, ctx: Dictionary) -> void:
	var sid := String(ctx.get("source_id", ""))
	if not sid.contains("turret"):
		return
	var frame := int(ctx.get("frame", Engine.get_physics_frames()))
	var agg: Dictionary = turret_intake.get(sid, {"dmg": 0, "first": frame, "last": frame})
	agg["dmg"] = int(agg["dmg"]) + amount
	agg["last"] = frame
	turret_intake[sid] = agg


# ================================================================ 汇总与报告

func _aggregate(crashes: int) -> Dictionary:
	var wins := 0
	var milestones := 0
	var deaths := 0
	var timeouts := 0
	var durs: Array[float] = []
	var hot := {}
	for r in results:
		match String(r["outcome"]):
			"win":
				wins += 1
			"milestone_a2":
				milestones += 1
			"death":
				deaths += 1
				var key := "F%d:%s" % [int(r["death_floor"]), String(r["death_room_type"])]
				hot[key] = int(hot.get(key, 0)) + 1
			"timeout":
				timeouts += 1
		durs.append(float(r["duration_s"]))
	var by_class := {}
	for row: Dictionary in _ttk_rows:
		var rt := String(row["room_type"])
		if not by_class.has(rt):
			by_class[rt] = []
		(by_class[rt] as Array).append(row)
	var combat_rows: Array = by_class.get("combat", [])
	return {
		"runs": results.size(),
		"wins": wins,
		"milestones": milestones,
		"deaths": deaths,
		"timeouts": timeouts,
		"win_rate": float(wins) / maxi(1, results.size()),
		# 内容上限到达率：走到本基线生产终局（胜利或 A2 入口里程碑）的局占比。
		"ceiling_rate": float(wins + milestones) / maxi(1, results.size()),
		"crashes": crashes,
		"avg_duration_s": _mean(durs),
		"median_duration_s": _percentile(durs, 0.5),
		"death_hot_rooms": hot,
		"prophet_kills": prophet_kills,
		"ttk": {
			"minion_a1": _ttk_summary_floor(combat_rows, 1),
			"minion_a2": _ttk_summary_floor(combat_rows, 2),
			"minion_a3": _ttk_summary_floor(combat_rows, 3),
			"miniboss": _ttk_summary_any(by_class.get("miniboss", [])),
			"boss": _ttk_summary_any(by_class.get("boss", [])),
			"elite": _ttk_summary_any(by_class.get("elite", [])),
		},
		"room_dur": _room_dur_summary(),
		"floor_dur": _floor_durations.duplicate(true),
	}


func _ttk_summary_floor(rows: Array, floor_idx: int) -> Dictionary:
	var vals: Array[float] = []
	for row: Dictionary in rows:
		if int(row["floor"]) == floor_idx:
			vals.append(float(row["ttk_s"]))
	return _ttk_vals(vals)


func _ttk_summary_any(rows: Array) -> Dictionary:
	var vals: Array[float] = []
	for row: Dictionary in rows:
		vals.append(float(row["ttk_s"]))
	return _ttk_vals(vals)


func _ttk_vals(vals: Array[float]) -> Dictionary:
	if vals.is_empty():
		return {}
	return {"median_s": _percentile(vals, 0.5), "p90_s": _percentile(vals, 0.9),
		"n": vals.size()}


func _room_dur_summary() -> Dictionary:
	var out := {}
	for rt in ["combat", "elite", "miniboss", "boss"]:
		var vals: Array[float] = []
		for row: Dictionary in _room_durations:
			if String(row["room_type"]) == rt:
				vals.append(float(row["dur_s"]))
		if not vals.is_empty():
			out[rt] = {"median_s": _percentile(vals, 0.5), "p90_s": _percentile(vals, 0.9),
				"n": vals.size()}
	return out


func _mean(vals: Array[float]) -> float:
	if vals.is_empty():
		return 0.0
	var s := 0.0
	for v in vals:
		s += v
	return snappedf(s / vals.size(), 0.1)


func _percentile(vals: Array[float], p: float) -> float:
	if vals.is_empty():
		return 0.0
	var sorted := vals.duplicate()
	sorted.sort()
	var idx := clampi(int(round(float(sorted.size() - 1) * p)), 0, sorted.size() - 1)
	return snappedf(sorted[idx], 0.1)


# ================================================================ 输出

func _write_outputs() -> void:
	if String(opts["out_json"]) != "":
		var f := FileAccess.open(String(opts["out_json"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({
				"opts": opts, "results": results, "aggregate": aggregate,
				"gems_curve": gems_curve, "ttk_rows": _ttk_rows,
				"room_durations": _room_durations, "floor_durations": _floor_durations,
				"turret_intake": turret_intake,
				"calibration": _calibration_rows(),
			}, "\t"))
			f.close()
	if String(opts["out_md"]) != "":
		_write_md(String(opts["out_md"]))


## 校准点①③④⑤⑥静态/函数半边 + ②映射复核（机器值；报告引用，逐值有
## test_balance_bot_calibration 钉死）。⑥ prophet 数据行已在本基线（先知卡合入），
## 结算函数半边 = settle_kill_gems 首杀 350 / 非首杀 50；+3 gems3 半边为行内
## drops 契约；对局动态半边需 A3 层（T26 模板在途）→ 报告按未覆盖披露。
func _calibration_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tid in ["thorn_turret", "rock_crystal_turret", "lava_turret"]:
		var erow := GameDB.get_enemy(tid)
		if erow.is_empty():
			continue
		rows.append({"id": tid, "kind": "turret_dps",
			"value": BalanceBotDecisions.turret_cycle_dps(erow)})
	rows.append({"id": "forge_cost_ladder", "kind": "forge_cost",
		"value": {
			"common": ForgeLogic.fuse_cost("common", "common"),
			"uncommon": ForgeLogic.fuse_cost("uncommon", "uncommon"),
			"rare": ForgeLogic.fuse_cost("rare", "rare"),
			"epic": ForgeLogic.fuse_cost("epic", "epic"),
			"legend": ForgeLogic.fuse_cost("legend", "legend"),
		}})
	var guardian := GameDB.get_hero("guardian")
	var staff_id := String((guardian.get("start_weapons") as Array)[0])
	var staff := GameDB.get_weapon(staff_id)
	rows.append({"id": "guardian_staff", "kind": "guardian_weapon",
		"value": {"weapon": staff_id, "rarity": String(staff.get("rarity", "")),
			"damage": int(staff.get("damage", 0)), "rate": float(staff.get("rate", 0.0))}})
	rows.append({"id": "life_tide_circle", "kind": "tide_heal",
		"value": {"instant": LifeTide.INSTANT_HEAL, "duration_ticks": LifeTide.DURATION_TICKS,
			"heal_per_tick": LifeTide.HEAL_PER_TICK,
			"nominal_hp": 1.5, "landed_hp": 1}})
	var prophet := GameDB.get_enemy("starfall_prophet")
	rows.append({"id": "oracle_economy", "kind": "oracle_gems",
		"value": {"boss_kill": int(RunState.KILL_GEMS.get("boss", 0)),
			"boss_first_kill": RunState.BOSS_FIRST_KILL_GEMS,
			"prophet_on_main": not prophet.is_empty(),
			"prophet_hp": int(prophet.get("hp", 0)),
			"prophet_drops_gems3": String(prophet.get("drops", "")).contains("gems3"),
			"settle_first": int(RunState.KILL_GEMS.get("boss", 0)) + RunState.BOSS_FIRST_KILL_GEMS,
			"settle_repeat": int(RunState.KILL_GEMS.get("boss", 0)),
			"in_run_prophet_kills": prophet_kills,
			"covered": prophet_kills > 0}})
	return rows


func _fmt_band(band: Array) -> String:
	return "%s~%s" % [str(band[0]), str(band[1])]


func _band_flag(val: float, band: Array, unit: String) -> String:
	if val >= float(band[0]) and val <= float(band[1]):
		return "达标"
	return "偏离（目标 %s%s）" % [_fmt_band(band), unit]


func _write_md(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BalanceBot: cannot write %s" % path)
		return
	var a := aggregate
	var wr: float = float(a.get("win_rate", 0.0))
	var cr: float = float(a.get("ceiling_rate", 0.0))
	f.store_line("# M2 Balance Bot 全层回归报告（%s · Task 27 / H-1 · m2-t28）" % _today())
	f.store_line("")
	f.store_line("- 驱动：`tools/balance_bot.gd` 无头自动游玩（启发式走位/避弹/避爆炸域/避 hazard/环绕走位/索敌开火/概率翻滚/商店买红心/事件一律接受/三选一贪心），hero=vanguard，headless 墙钟速率（引擎 time_scale 对本作逐拍定步长逻辑无加速效用，物理拍=真实玩家体验时长）")
	f.store_line("- 决策纯逻辑：`tools/balance_bot_decisions.gd`（确定性，tests/unit/test_balance_bot_decisions.gd 钉死）；校准点机器值：tests/unit/test_balance_bot_calibration.gd 钉死")
	f.store_line("- 局数：%d（种子 %s）｜崩溃：%d｜超时中止：%d" % [int(a.get("runs", 0)), _seed_span(),
		int(a.get("crashes", 0)), int(a.get("timeouts", 0))])
	f.store_line("")
	f.store_line("## 内容覆盖前提（先读这段再读数据）")
	f.store_line("")
	f.store_line("- **本批回归基线 = main c676657：仅第 1 层为完整可玩内容。** A2/A3 房间模板在 T26（并行在途，含修复轮）；`run_root._floor_data_available(2)` 为假 → 过第 1 层层间门后进入生产「A2 入口里程碑」（`a2_entry_active()`，Task 20/26 定义的最小可玩端点），bot 记为终局 `milestone_a2`。")
	f.store_line("- 因此 **生产胜利（第 3 层 Boss 链）在本基线不可达，§14.3 胜率带（20%%~40%%）本批「不可评」**——如实标注，不调数值凑数。可评口径：第 1 层内的死亡热房 / TTK / 房间与单层时长 / 蓝晶曲线 / 内容上限到达率（胜利或 milestone_a2 到达占比 = %.0f%%）。" % (cr * 100.0))
	f.store_line("- 已知内容缺口（T26 合并后仍成立，T36 承接）：A2/A3 波次将仍用 A1 敌人名录、Boss 三层恒 vine_colossus——届时胜率/TTK 的含义仍受此限制：三层难度递进缺失使深层数据偏「同难度复读」，真实分层后胜率预计低于届时测量。")
	f.store_line("- T26 合并后同一 bot（零改动）自动续走 2/3 层并复评胜率带；本报告即「第 1 层全内容回归 + 骨架就绪证明」。")
	f.store_line("")
	f.store_line("## 汇总（结局分布 + 可评带对照）")
	f.store_line("")
	f.store_line("| 指标 | 实测 | §14.3 目标带 | 判定 |")
	f.store_line("|---|---|---|---|")
	f.store_line("| 生产胜率（第 3 层胜利） | %d/%d | 20%%~40%% | **不可评（本基线无 2/3 层内容）** |" % [
		int(a.get("wins", 0)), int(a.get("runs", 0))])
	f.store_line("| 内容上限到达率（win+milestone_a2） | %.0f%% | -（本卡替代口径） | %s |" % [
		cr * 100.0, "达标" if cr >= 1.0 else "有未走完局（超时/崩溃）"])
	var avg_min: float = float(a.get("avg_duration_s", 0.0)) / 60.0
	var med_min: float = float(a.get("median_duration_s", 0.0)) / 60.0
	f.store_line("| 单局时长(均值/中位) | %.1f / %.1f min | %s min（单局口径） | 第 1 层子集，仅参考 |" % [
		avg_min, med_min, _fmt_band(GDD_RUN_MIN)])
	f.store_line("")
	f.store_line("## 逐局")
	f.store_line("")
	f.store_line("| seed | 结果 | 止步 | 房间 | 击杀 | 时长(min) | 金币 | 蓝晶 | 买红心 | 增益选择 | 首杀可获 | 死因 |")
	f.store_line("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var stop := ""
		match String(r["outcome"]):
			"win":
				stop = "胜利"
			"milestone_a2":
				stop = "A2 入口里程碑（第 1 层全清）"
			"timeout":
				stop = "超时"
			"crash":
				stop = "崩溃"
			_:
				stop = "第%d层" % int(r["floor"])
		var cause := String(r["death_cause"])
		if String(r["death_room_type"]) != "":
			cause += "（%s）" % String(r["death_room_type"])
		f.store_line("| %d | %s | %s | %d | %d | %.1f | %d | %d | %d | %s | %s | %s |" % [
			int(r["seed"]), String(r["outcome"]), stop, int(r["rooms"]),
			int(r["kills"]), float(r["duration_s"]) / 60.0, int(r["coins"]),
			int(r["gems"]), int(r["hearts"]),
			String(r["buffs"]) if String(r["buffs"]) != "" else "-",
			"是" if bool(r["boss_first_kill_eligible"]) else "否",
			cause if cause != "" else "-"])
	f.store_line("")
	f.store_line("- 「首杀可获」= 该局开始时 vine_colossus 尚无 SaveSystem 首杀标记（击杀蓝晶 +300 只落批次首局，见局间隔离披露）。")
	f.store_line("")
	f.store_line("## 死亡热房（死亡楼层 × 房型）")
	f.store_line("")
	var hot: Dictionary = a.get("death_hot_rooms", {})
	if hot.is_empty():
		f.store_line("无死亡局。")
	else:
		f.store_line("| 层:房型 | 死亡次数 |")
		f.store_line("|---|---|")
		for k in hot:
			f.store_line("| %s | %d |" % [String(k), int(hot[k])])
	f.store_line("")
	f.store_line("## TTK / 节奏（对照 §14.3；本批全部为第 1 层口径）")
	f.store_line("")
	f.store_line("| 指标 | 实测(中位/p90) | §14.3 目标 | 判定 |")
	f.store_line("|---|---|---|---|")
	var ttk: Dictionary = a.get("ttk", {})
	var m_a1: Dictionary = ttk.get("minion_a1", {})
	if not m_a1.is_empty():
		f.store_line("| A1 杂兵 TTK | %.1f / %.1f s (n=%d) | ≤2.0 s | %s |" % [
			float(m_a1["median_s"]), float(m_a1["p90_s"]), int(m_a1["n"]),
			"达标" if float(m_a1["median_s"]) <= GDD_MINION_TTK_S else "偏离"])
	for fl in [2, 3]:
		var m_ax: Dictionary = ttk.get("minion_a%d" % fl, {})
		if not m_ax.is_empty():
			f.store_line("| A%d 杂兵 TTK | %.1f / %.1f s (n=%d) | （参考） | - |" % [
				fl, float(m_ax["median_s"]), float(m_ax["p90_s"]), int(m_ax["n"])])
	var m_el: Dictionary = ttk.get("elite", {})
	if not m_el.is_empty():
		f.store_line("| 精英击杀 | %.1f / %.1f s (n=%d) | （参考） | - |" % [
			float(m_el["median_s"]), float(m_el["p90_s"]), int(m_el["n"])])
	var m_mb: Dictionary = ttk.get("miniboss", {})
	if not m_mb.is_empty():
		f.store_line("| 小 Boss 击杀 | %.1f / %.1f s (n=%d) | （参考） | - |" % [
			float(m_mb["median_s"]), float(m_mb["p90_s"]), int(m_mb["n"])])
	var m_boss: Dictionary = ttk.get("boss", {})
	if not m_boss.is_empty():
		f.store_line("| Boss 单体击杀 | %.1f / %.1f s (n=%d) | （参考） | - |" % [
			float(m_boss["median_s"]), float(m_boss["p90_s"]), int(m_boss["n"])])
	var room_dur: Dictionary = a.get("room_dur", {})
	var cd: Dictionary = room_dur.get("combat", {})
	if not cd.is_empty():
		f.store_line("| 战斗房时长 | %.1f / %.1f s (n=%d) | %s s | %s |" % [
			float(cd["median_s"]), float(cd["p90_s"]), int(cd["n"]), _fmt_band(GDD_ROOM_S),
			_band_flag(float(cd["median_s"]), GDD_ROOM_S, " s")])
	var bd: Dictionary = room_dur.get("boss", {})
	if not bd.is_empty():
		f.store_line("| Boss 房时长(入房→清房) | %.1f / %.1f s (n=%d) | %s s | %s |" % [
			float(bd["median_s"]), float(bd["p90_s"]), int(bd["n"]), _fmt_band(GDD_BOSS_S),
			_band_flag(float(bd["median_s"]), GDD_BOSS_S, " s")])
	for row: Dictionary in a.get("floor_dur", []):
		var mins := float(row["dur_s"]) / 60.0
		f.store_line("| 第 %d 层时长 | %.1f min | %s min | %s |" % [int(row["floor"]), mins,
			_fmt_band(GDD_FLOOR_MIN), _band_flag(mins, GDD_FLOOR_MIN, " min")])
	f.store_line("")
	f.store_line("## 蓝晶获取曲线（每局层末快照；§14.1 过层 60/120/200 + 击杀档位）")
	f.store_line("")
	f.store_line("| seed | F1 末(过层门快照) | 终局 |")
	f.store_line("|---|---|---|")
	var by_seed := {}
	for g in gems_curve:
		var sid := int(g["seed"])
		if not by_seed.has(sid):
			by_seed[sid] = {"door": "-", "final": "-"}
		if String((by_seed[sid] as Dictionary)["door"]) == "-":
			(by_seed[sid] as Dictionary)["door"] = int(g["gems"])
		(by_seed[sid] as Dictionary)["final"] = int(g["gems"])
	for r2 in results:
		var sid2 := int(r2["seed"])
		var g2: Dictionary = by_seed.get(sid2, {})
		f.store_line("| %d | %s | %s |" % [sid2, str(g2.get("door", "-")), str(g2.get("final", "-"))])
	f.store_line("")
	f.store_line("- 口径披露：`RunState.gems` 为本局待结算蓝晶（死亡减半/胜利全额入档在终局确认；本 bot 经测试缝捕获终局，不入档）。vine_colossus Boss 首杀 +300 只落在批次首局（SaveSystem 跨局累积，模拟真实玩家成长），其余局 +50/次；elite +5 / miniboss +20 随杀随入池。")
	f.store_line("")
	_write_md_calibration(f)
	_write_md_findings(f, wr, cr)
	_write_md_disclosure(f)
	f.close()
	print("BALANCE-BOT report written: ", path)


func _write_md_calibration(f: FileAccess) -> void:
	f.store_line("## 校准点复核（裁定①②③④⑤⑥，逐项带值）")
	f.store_line("")
	f.store_line("### ① 炮台 DPS（裁定①口径：射速 2/s × 伤 4 = 8 DPS）")
	f.store_line("")
	f.store_line("| 炮台 | 周期(t) | 发/周期 | 单发伤 | 持续 DPS | vs 8 DPS 口径 |")
	f.store_line("|---|---|---|---|---|---|")
	for row: Dictionary in _calibration_rows():
		if String(row["kind"]) != "turret_dps":
			continue
		var v: Dictionary = row["value"]
		var e := GameDB.get_enemy(String(row["id"]))
		f.store_line("| %s | %d | %d | %d | %.2f | %.0f%% |" % [String(row["id"]),
			int(v["cycle_ticks"]), int(v["shots_per_cycle"]), int(e.get("bullet_dmg", 0)),
			float(v["sustained_dps"]), float(v["sustained_dps"]) / 8.0 * 100.0])
	f.store_line("")
	f.store_line("- 结论：**thorn_turret 实装 4.5 DPS（裁定①口径 8 DPS 的 56%）**——3 连发周期 160t（1.125 发/s）未达计划卡「射速 2/s」。lava_turret 扇形 5 发全中 13.33 DPS（理想暴露值）；rock_crystal_turret 蓄能激光 2.0 DPS。三种炮台均以数据行 + 原型循环语义机器复核（test_balance_bot_calibration 钉死）。")
	if not turret_intake.is_empty():
		f.store_line("- 动态半边（bot 实吃炮台伤，走位相关仅供参考）：")
		for sid: String in turret_intake:
			var t: Dictionary = turret_intake[sid]
			var span := int(t["last"]) - int(t["first"])
			if span > 60:
				f.store_line("  - %s：吃 %d 伤 / %.1fs 曝露窗 ≈ %.2f DPS" % [sid, int(t["dmg"]),
					float(span) / 60.0, float(t["dmg"]) * 60.0 / float(span)])
	else:
		f.store_line("- 动态半边：本批 bot 未记录到炮台来源实吃伤害（走位规避生效或本批房间未出炮台）。")
	f.store_line("")
	f.store_line("### ② LOOT_RARITY_WEIGHTS 绿→rare 映射漂移（T6 移交复核）")
	f.store_line("")
	f.store_line("- 权重表（floor_scene.gd，注释「白/绿/蓝」）：白 60 / rare 30 / epic 10。")
	f.store_line("- 实际语义：初始掉落池（locked 已排除，66 把 = 白9+绿21+蓝36；运行时经图鉴解锁回池可能更大，见局间隔离披露）内按 rarity 字符串直配——30% 权重键 `rare` 抽的是**蓝 36 把**而非注释所称「绿」；**uncommon（绿 21 把）无权重键，不可能被直接抽中**。")
	f.store_line("- 第二面：`epic` 键（10%）池内 0 命中（紫 33 全 locked 不在池）→ `_roll_weapon` 空池兜底退化为**全池均匀**（66 把任抽）——绿装仅能以 10% × 21/66 ≈ 3.2% 综合概率经此兜底出现（设计意图 30%）。")
	f.store_line("- 结论：漂移确认，与移交描述一致且更严重（绿装近乎绝迹）。**本卡不修**（T6 移交项复核职责；修复建议：权重键改 common/uncommon/rare，或池侧建 GDD 颜色档→稀有度键映射）。")
	f.store_line("")
	f.store_line("### ③ 熔铸费用公式 30~390 阶梯（裁定⑰）")
	f.store_line("")
	f.store_line("- 实测阶梯（较高稀有度基准价 ×1.5 取整到 5）：白 30 / 绿 65 / 蓝 130 / 紫 235 / 橙 390——**两端点 30/390 与裁定⑰一致**，中间档单调递增无跳变（test_balance_bot_calibration 钉死）。")
	f.store_line("")
	f.store_line("### ④ 守护者史诗星辉杖无弱化（裁定⑥）")
	f.store_line("")
	for row: Dictionary in _calibration_rows():
		if String(row["kind"]) != "guardian_weapon":
			continue
		var v: Dictionary = row["value"]
		f.store_line("- guardian.start_weapons = `%s` → weapons 表原行 rarity=%s damage=%d rate=%.1f；全表无弱化变体 id。**与裁定⑥一致（无弱化）**。" % [
			String(v["weapon"]), String(v["rarity"]), int(v["damage"]), float(v["rate"])])
	f.store_line("- 覆盖口径：bot 本批全部 vanguard（初始武器 laohuoji），守护者/星辉杖手感**未在对局覆盖**——本项为数据面复核（采不到对局数据，按数据侧核对处理）。")
	f.store_line("")
	f.store_line("### ⑤ 生命潮汐法阵 3s 实落 1HP（裁定⑥）")
	f.store_line("")
	f.store_line("- 实装口径：施放立即回 2 HP；法阵 180t（3s）× 0.5 HP/s 名义 1.5 HP，整数累加器只落 1 HP（第 2 秒拍），余 0.5 消散且不跨施放携带；阵外节拍空转。**与裁定⑥「3s 实落 1HP」一致**。")
	f.store_line("- 覆盖口径：bot 用 vanguard（技能狂潮），生命潮汐为 guardian 技能——**对局未覆盖**；本项为帧注入直驱复核（test_balance_bot_calibration 逐拍验证）。")
	f.store_line("")
	f.store_line("### ⑥ 先知击杀经济 +53/+353（裁定⑲）")
	f.store_line("")
	for row: Dictionary in _calibration_rows():
		if String(row["kind"]) != "oracle_gems":
			continue
		var v: Dictionary = row["value"]
		f.store_line("- 数据行半边：`starfall_prophet` **已在 main**（m2-t24 先知卡合入）——hp=%d，行内 drops 含 gems3（3 蓝晶实体掉落，拾取各 +1）。" % int(v["prophet_hp"]))
		f.store_line("- 结算函数半边（RunState.settle_kill_gems 生产口径，test_balance_bot_calibration 以首杀标记快照/还原钉死）：击杀 +50（Boss 档）；首杀再 +300 = **+350**。")
		f.store_line("- 合计口径（裁定⑲）：普通击杀 = 50 + 3（gems3 拾取）= **+53**；首杀 = 350 + 3 = **+353**。✅ 与裁定⑲一致。")
		f.store_line("- 对局动态半边：隐藏门需 A3 层（`A3_FLOOR_IDX=3`），本基线 A2/A3 模板在 T26 在途 → **本批对局内未覆盖**（bot 先知击杀数 = %d）。T26 合并后复跑即自动采样（bot 已对「已清房存活波次外嘉宾」保持战斗驱动）。" % int(v["in_run_prophet_kills"]))
	f.store_line("")


func _write_md_findings(f: FileAccess, wr: float, cr: float) -> void:
	f.store_line("## 校准建议（只给建议不改数值——校准归后续裁定）")
	f.store_line("")
	f.store_line("- 胜率带（20%%~40%%）本批不可评（生产胜利需 3 层内容；本基线仅第 1 层可玩）。**行动项：T26 合并后以同一 bot 复跑 10 局出带**；本批第 1 层口径的上半程生存率 %.0f%% 可作为届时带判的先导信号（上半程全活 ≠ 全局带内，届时以全 3 层测量为准）。" % (cr * 100.0))
	for s in _imbalance_findings(wr):
		f.store_line("- " + s)
	f.store_line("")


func _write_md_disclosure(f: FileAccess) -> void:
	f.store_line("## 接口边界与前提披露")
	f.store_line("")
	f.store_line("- **接口边界**：bot 只经由生产接口操作——Input 移动、`PlayerDriver.touch_mode_override`（生产触屏 auto_aim 自动开火，手机玩家同路径）+ 战斗期按住物理 fire、`player.start_roll`/`Skill.cast`（CD/耗蓝守卫在生产侧）、`FloorScene.enter_room`（生产 enter_room→_push_back 落位，走廊徒步不模拟，同 m1_loop_smoke 惯例）、`Shop.interact` + `_buy_item(\"heart\")`（RunState.spend_coins 扣款）、`EventRoom.accept`（bot 一律接受）、层间三回调。伤害/击杀/掉落/金币全部由生产战斗链路自然发生；bot 不使用熔铸台/雕像/饮料机（商店仅买红心）。")
	f.store_line("- **种子口径**：`RunState.start_run` 墙钟种子被 `RunState.run_seed = seed` + `RngSvc.setup_run(seed)` 确定性覆写（start_run 其余状态不变）；bot 决策采样用独立 `_rng`（同种子播种）——同 seed 可复现整局（bot 行为侧；敌人 AI 消费 RunState 盐流，同种子同确定性）。")
	f.store_line("- **局间隔离**：每局 `start_run` 重置局内状态；SaveSystem 原状保留（headless 自动重定向 save_headless.json，真档不受影响）——图鉴/成就计数与 Boss 首杀标记跨局累积（真实玩家成长模拟），vine_colossus 首杀 +300 只落批次首局（逐局表「首杀可获」列可查）。多局会推进 save_headless.json 的图鉴/解锁进度，属产品正确行为（裁定㉒口径）。")
	f.store_line("- **胜/死捕获**：生产测试缝 `run_root.victory_route_override` / `DeathRecorder.open_summary_override`（死亡报告 = DeathRecorder.build_report 生产口径）；终局蓝晶**不入档**（无 DeathSummary/VictorySummary 确认路径）。")
	f.store_line("- **内容缺口（前提，非本卡缺陷）**：本基线 A2/A3 层模板在 T26（并行在途）——本报告全部统计为第 1 层口径；A2/A3 就绪后波次仍为 A1 名录、Boss 恒 vine_colossus（T36 承接），届时报告继续注明该限制。")
	f.store_line("")


func _imbalance_findings(_wr: float) -> Array[String]:
	# 数据驱动的失衡因子排查（只给建议，不改数值）
	var out: Array[String] = []
	var ttk: Dictionary = aggregate.get("ttk", {})
	var m_a1: Dictionary = ttk.get("minion_a1", {})
	var m_boss: Dictionary = ttk.get("boss", {})
	var bd: Dictionary = (aggregate.get("room_dur", {}) as Dictionary).get("boss", {})
	var hot: Dictionary = aggregate.get("death_hot_rooms", {})
	var hot_top := ""
	var hot_n := 0
	for k in hot:
		if int(hot[k]) > hot_n:
			hot_n = int(hot[k])
			hot_top = String(k)
	var a1_txt := "无样本"
	if not m_a1.is_empty():
		a1_txt = "%.1fs" % float(m_a1["median_s"])
	var boss_txt := "无样本"
	if not m_boss.is_empty():
		boss_txt = "%.0fs" % float(m_boss["median_s"])
	if not m_a1.is_empty() and float(m_a1["median_s"]) > GDD_MINION_TTK_S:
		out.append("因子一（输出端）：A1 杂兵 TTK 中位 %s 超出 §14.3「初始武器 ≤2.0s」。建议校准初始武器（laohuoji）基础伤害/攻速 +20%%~30%% 后复测。" % a1_txt)
	if not bd.is_empty() and (float(bd["median_s"]) < float(GDD_BOSS_S[0]) \
			or float(bd["median_s"]) > float(GDD_BOSS_S[1])):
		out.append("因子二（Boss 节奏）：Boss 房时长中位 %.1fs 偏出 %ss 带（Boss 单体击杀中位 %s）。 vine_colossus 800 HP 对照玩家预期 DPS 22 → 纯输出 36s，带下沿主要靠阶段演出与走位垫高；若复测仍偏短，优先复核 Boss 三阶段血量线（100%%~60%%~30%%）切换演出时长。" % [
			float(bd["median_s"]), _fmt_band(GDD_BOSS_S), boss_txt])
	if hot_n > 0:
		out.append("因子三（生存端）：死亡热房 %s（%d 次）。若集中于特定房型，建议校准该房型敌方弹幕密度（§7.5 上限）或弹速 -10%%~15%%；死亡集中于 Boss 房则复核 P2/P3 弹幕量曲线。" % [hot_top, hot_n])
	if out.is_empty():
		out.append("本批第 1 层口径未触发失衡因子阈值（TTK/房时长带内、无死亡热房）；胜率带待全 3 层内容就绪后复评。")
	return out


func _seed_span() -> String:
	if results.is_empty():
		return "-"
	return "%d..%d" % [int(results[0]["seed"]), int(results.back()["seed"])]


func _today() -> String:
	return Time.get_date_string_from_system()


# ================================================================ 参数解析

func _parse_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() == 1:
			match kv[0]:                     # 无值旗标
				"no-quit":
					opts["quit_when_done"] = false
				"debug":
					_debug = true
			continue
		if kv.size() != 2:
			continue
		match kv[0]:
			"runs":
				opts["runs"] = int(kv[1])
			"seed-base":
				opts["seed_base"] = int(kv[1])
			"time-scale":
				opts["time_scale"] = float(kv[1])
			"max-frames-per-run":
				opts["max_frames_per_run"] = int(kv[1])
			"out-md":
				opts["out_md"] = kv[1]
			"out-json":
				opts["out_json"] = kv[1]
			"no-quit":
				opts["quit_when_done"] = false
			"debug":
				_debug = true
