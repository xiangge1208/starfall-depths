class_name DeathSummary
extends Control
## 死亡结算全屏面板（m1-t22）：「守夜人陨落」+ 本局统计 + 致死原因回顾 + 蓝晶死亡保留 50%。
## 生产路径：DeathRecorder 致死时 change_scene/SceneRouter.goto("death") 进入本场景，
## _ready 直接读 DeathRecorder.current_report 填充；任意键/点击确认 →
## RunState.settle_death_gems() 一次性消费本局蓝晶 → SaveSystem.add_gems 入账持久化 →
## DeathRecorder.reset()（清窗口/报告/Telemetry 会话）→ 回主菜单。
##
## 【回主菜单路由（披露）】优先 /root/SceneRouter.goto("menu")（T23 可能未合入，
## get_node_or_null 守卫，同 T11 对 RunState 的探测模式）；SceneRouter 缺席时按
## main_menu.tscn 是否存在回落（T23 未合入则退到现存的 hero_select.tscn）。
## 测试经 exit_override 接缝注入，不真跳场景。
##
## ================================================================ m2-t24 死亡回放（演示性重放）
##
## 「回放」按钮 → 以 DeathRecorder.replay_key {run_seed, floor_idx, death_frame} 重建
## 该层 FloorScene（RunRoot 既有构建路径：DungeonBuilder.build(seed, floor_idx) +
## FloorScene.setup(build, player)；同种子同布局同波次），观战播放死亡时刻。
##
## 【观战模式】重生玩家 process_mode = DISABLED（整树停机：无移动/无开火输入）+
## 超长无敌帧（apply_iframes，伤害路径双保险）+ DeathRecorder.suppressed（任何
## 漏网致命不接管场景流）；若 fatal_event.pos 命中某房间，经 FloorFlow 邻接 BFS
## 放行沿途门（沿途房演示性 notify_room_cleared，终点保持未清）直达致死房触发
## 真波次装配，观战者落于致死点。
##
## 【演示性重放（边界披露）】本回放非逐帧确定性录像：重建只保证同种子同布局同
## 波次；原局玩家走位/开火行为不可复现，敌人 AI 与弹幕轨迹与原局存在偏差，属
## 可接受近似（task-24 规格明示的实现边界）。
##
## 【时间线】Engine.time_scale = 8.0 时间压缩快进至死亡帧前 3s（180t 预滚）→
## 恢复 1.0 实速播完最后 3 秒 → 到达 death_frame 时暂停楼层并显示
## 「这就是你的死亡时刻」。time_scale 恢复 1.0 具 finally 语义：到点 / 手动退出 /
## _exit_tree 三路兜底，防泄漏到后续场景。

signal dismissed

## 回主菜单接缝（测试注入口）：有效时替代真实路由。
var exit_override: Callable = Callable()

## m2-t24 回放状态机：IDLE → FAST_FORWARD(8x) → LIVE(1x) → DONE(暂停+横幅)。
enum ReplayState { IDLE, FAST_FORWARD, LIVE, DONE }

const REPLAY_TIME_SCALE := 8.0
const REPLAY_PRE_ROLL_TICKS := 180     # 死亡帧前 3s 预滚（3s @ 60fps，同 TimeConst.FPS）
const REPLAY_BANNER_TEXT := "这就是你的死亡时刻"
const PLAYER_SCENE := preload("res://core/player/player.tscn")
## M1 补录③（m1-final-review e6ed091；T33 预检落地）：死亡确认输入锁——面板打开后
## 0.5s（30t）内的离散按键/点击一律吞掉，防致死瞬间连按/按住直接跳过死亡回顾。
## 锁窗不作用回放退出路径：回放只能先经 Replay 按钮显式启动（GUI 输入先于
## _unhandled_input，锁窗内的点击只会落在按钮/面板上，不会触发 _confirm）。
const CONFIRM_LOCK_TICKS := 30

var _report: Dictionary = {}
var _confirmed := false               # 双击/双键守卫：蓝晶只入账一次
var _opened_frame := -9999            # 输入锁基准帧（open 时落；-9999 = 永不过期防御）
var _replay_state: int = ReplayState.IDLE
var _replay_floor: FloorScene = null
var _replay_player: Player = null
var _replay_ticks := 0                # 回放本地层内帧（自计数，time_scale 无关）
var _replay_ff_until := 0             # 快进段终点 = death_frame - 180t（clamp 0）
var _replay_death_tick := 0           # 暂停点 = death_frame（层内帧）

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 全屏面板：挡住底层交互
	# m4p-w2a 结算切曲：进死亡结算页即切 menu 曲（play_music 同曲幂等——回主菜单
	# 再 play_music("menu") 不重启，连续不跳变；披露：不做 1s 静默沉重停顿）。
	AudioMgr.play_music("menu")
	($Panel/Box/Replay as Button).pressed.connect(start_replay)
	if not DeathRecorder.current_report.is_empty():
		open(DeathRecorder.current_report)     # 场景直入时从记录器取报告

## 填充面板（测试可直接注入报告）。「回放」按钮只在有回放键时可见。
func open(report: Dictionary) -> void:
	_report = report
	_opened_frame = Engine.get_physics_frames()   # M1 补录③：确认输入锁基准帧
	_fill()
	($Panel/Box/Replay as Button).visible = not DeathRecorder.replay_key.is_empty()

func label_texts() -> Array[String]:
	var out: Array[String] = []
	for c in $Panel/Box.get_children():
		if c is Label:
			out.append(String(c.text))
	return out

func _fill() -> void:
	var stats: Dictionary = _report.get("stats", {})
	$Panel/Box/Title.text = TrialPanelUI.trial_title_text("守夜人陨落")   # M3-R-B 试炼局冠「每日试炼」
	TrialPanelUI.add_settlement_medal($Panel/Box)   # M3-R-B：试炼局标题徽标（倍率明细行归 R-C）
	$Panel/Box/Stats.text = "房数 %d　　击杀 %d　　金币 %d　　层数 %d\n时长 %s　　受击 %d 次　　DPS 峰值 %d" % [
		int(stats.get("rooms", 0)), int(stats.get("kills", 0)),
		int(stats.get("coins", 0)), int(stats.get("floor", 0)),
		_format_time(float(stats.get("run_time", 0.0))), int(stats.get("hurt_count", 0)),
		int(stats.get("peak_dps", 0)),
	]
	$Panel/Box/Cause.text = "致死原因：%s" % str(_report.get("cause", "未知"))
	var fatal_event: Dictionary = _report.get("fatal_event", {})
	var hp_text := "未知" if int(fatal_event.get("remaining_hp", -1)) < 0 \
		else str(int(fatal_event.get("remaining_hp", 0)))
	var roll_text := "可用" if bool(fatal_event.get("roll_available", false)) else "不可用"
	$Panel/Box/Cause.text += "\n致死后剩余生命：%s　当时翻滚：%s" % [hp_text, roll_text]
	# M3-R-C：试炼局倍率明细行（保底 75% 口径，覆盖报告 50% 快照）；普通局文案不变
	$Panel/Box/Gems.text = TrialPanelUI.settlement_gems_line(_stats_gems(), true) \
		if RunState.is_trial_run else "蓝晶结算：+%d（死亡保留 50%%）" % _gems_awarded()
	$Panel/Box/Hint.text = "—— 按任意键返回 ——"

func _format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]

## 入账蓝晶：优先报告中的 gems_awarded；报告缺 stats 时按 RunState.gems 现算 floor/2。
func _gems_awarded() -> int:
	var stats: Dictionary = _report.get("stats", {})
	if stats.has("gems_awarded"):
		return int(stats["gems_awarded"])
	return int(floor(int(stats.get("gems", RunState.gems)) / 2.0))

## 报告快照的待结算池（M3-R-C 试炼倍率明细行的「基础 X」；缺 stats 回落现值）。
func _stats_gems() -> int:
	var stats: Dictionary = _report.get("stats", {})
	return int(stats.get("gems", RunState.gems))

func _unhandled_input(event: InputEvent) -> void:
	if _replay_state != ReplayState.IDLE:
		# 回放期间任意键/点击 = 退出回放回结算面板（不触发蓝晶确认/离场）
		var key := event as InputEventKey
		var mb := event as InputEventMouseButton
		if (key != null and key.pressed and not key.echo) \
				or (mb != null and mb.pressed):
			get_viewport().set_input_as_handled()
			end_replay()
		return
	# M1 补录③：确认输入锁（open 后 0.5s 窗口）——吞掉离散按键/点击，防误确认。
	if Engine.get_physics_frames() - _opened_frame < CONFIRM_LOCK_TICKS:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if not key_ev.pressed or key_ev.echo:
			return
	elif event is InputEventMouseButton:
		var mb_ev := event as InputEventMouseButton
		if not mb_ev.pressed:
			return
	else:
		return
	get_viewport().set_input_as_handled()
	_confirm()

## 确认结算：蓝晶入账（一次性）→ 复位记录器 → 广播 dismissed → 回主菜单。
## m2-t31：确认即终局结算点——图鉴跨局计数器（CodexSystem）快照落盘（存档 v2）。
func _confirm() -> void:
	if _confirmed:
		return
	_confirmed = true
	var awarded := RunState.settle_death_gems()
	if awarded > 0:
		SaveSystem.add_gems(awarded)
	var codex: Node = get_node_or_null("/root/CodexSystem")
	if codex != null and codex.has_method("persist_counters"):
		codex.persist_counters()
	TrialPanelUI.settlement_record(awarded, false)   # M3-R-C：试炼局 records + trial_completed（普通局无操作）
	DeathRecorder.reset()
	dismissed.emit()
	_exit_to_menu()

func _exit_to_menu() -> void:
	if exit_override.is_valid():
		exit_override.call()                                # 测试/整合注入口
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call("goto", "menu")                         # T23 已合入：正式路由
		return
	if ResourceLoader.exists("res://ui/main_menu.tscn"):
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	get_tree().change_scene_to_file("res://ui/hero_select.tscn")   # T23 未合入兜底（现存场景）


# ================================================================ m2-t24 死亡回放

func _physics_process(_delta: float) -> void:
	if _replay_state == ReplayState.FAST_FORWARD or _replay_state == ReplayState.LIVE:
		_replay_ticks += 1
		_replay_advance(_replay_ticks)

## 回放时间线推进（层内 tick 驱动；测试可直调注入任意 tick）。
func _replay_advance(ticks: int) -> void:
	if _replay_state == ReplayState.FAST_FORWARD and ticks >= _replay_ff_until:
		Engine.time_scale = 1.0                 # 快进段终点：恢复 1.0 实速播最后 3 秒
		_replay_state = ReplayState.LIVE
	if _replay_state == ReplayState.LIVE and ticks >= _replay_death_tick:
		_finish_replay_moment()

## 到点（death_frame）：time_scale 恢复 1.0（finally 语义）+ 暂停楼层 + 死亡时刻横幅。
func _finish_replay_moment() -> void:
	Engine.time_scale = 1.0
	if _replay_floor != null and is_instance_valid(_replay_floor):
		_replay_floor.process_mode = Node.PROCESS_MODE_DISABLED
	($ReplayView/Banner as Label).text = REPLAY_BANNER_TEXT
	_replay_state = ReplayState.DONE

## 进入回放：以 ReplayKey 重建楼层（RunRoot 既有构建路径）→ 观战模式 → 8x 快进。
func start_replay() -> void:
	if _replay_state != ReplayState.IDLE or DeathRecorder.replay_key.is_empty():
		return
	var key := DeathRecorder.replay_key
	_replay_death_tick = maxi(int(key.get("death_frame", 0)), 0)
	_replay_ff_until = maxi(_replay_death_tick - REPLAY_PRE_ROLL_TICKS, 0)
	_replay_ticks = 0
	_build_replay_floor()
	if _replay_floor == null:
		return
	($Panel as PanelContainer).visible = false
	($Dim as ColorRect).visible = false
	($ReplayView as Control).visible = true
	DeathRecorder.suppressed = true         # 观战期间致命不接管（防漏网伤害开新结算）
	Engine.time_scale = REPLAY_TIME_SCALE
	_replay_state = ReplayState.FAST_FORWARD

## 退出回放（任意键/点击）：time_scale 恢复 1.0（finally 语义）→ 释放回放场景 → 回面板。
func end_replay() -> void:
	if _replay_state == ReplayState.IDLE:
		return
	Engine.time_scale = 1.0
	DeathRecorder.suppressed = false
	if _replay_floor != null and is_instance_valid(_replay_floor):
		_replay_floor.free()                # immediate free：面板同帧要回来，不等帧末
	_replay_floor = null
	if _replay_player != null and is_instance_valid(_replay_player):
		_replay_player.free()
	_replay_player = null
	($ReplayView as Control).visible = false
	($Panel as PanelContainer).visible = true
	($Dim as ColorRect).visible = true
	_replay_state = ReplayState.IDLE

func _exit_tree() -> void:
	# finally 语义兜底：任何路径离场（确认结算换场景/外部释放）都恢复实速，
	# 观战接管标志仅在回放未收尾时由本节点负责复位。
	if _replay_state != ReplayState.IDLE:
		DeathRecorder.suppressed = false
	Engine.time_scale = 1.0

## 重建该层 FloorScene（RunRoot._spawn_hero_player/_start_floor 既有路径镜像）：
## 玩家入树（@onready 就位）→ rig 接 RunState → HeroApplier 装配 → FloorScene.setup。
func _build_replay_floor() -> void:
	var key := DeathRecorder.replay_key
	var idx := maxi(int(key.get("floor_idx", 1)), 1)
	var build := DungeonBuilder.build(int(key.get("run_seed", 0)), idx)
	var p: Player = PLAYER_SCENE.instantiate() as Player
	add_child(p)
	var rig := p.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		p.weapon_rig = rig
		rig.bind_run_state(RunState)
	var hero_row := GameDB.get_hero(RunState.hero_id)
	if not hero_row.is_empty():
		HeroApplier.apply(hero_row, p)
	# 观战模式：玩家整树停机（无移动/开火输入）+ 超长无敌帧（伤害路径双保险）
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.apply_iframes(1 << 28, Engine.get_physics_frames())
	_replay_player = p
	_replay_floor = FloorScene.new()
	_replay_floor.floor_idx = idx
	add_child(_replay_floor)
	move_child(_replay_floor, 0)            # 楼层垫底：结算面板/回放横幅仍在顶层
	_replay_floor.setup(build, p)
	# 致死点观战：fatal_event.pos 命中房间 → BFS 放行沿途门 + 进房触发真波次装配
	var pos_v: Variant = (_report.get("fatal_event", {}) as Dictionary).get("pos", Vector2.ZERO)
	var pos: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
	if pos != Vector2.ZERO:
		_spectate_to_fatal_pos(_replay_floor, build, pos)

## 观战直达致死房：定位 pos 所在房 → FloorFlow 邻接 BFS 求路 → 沿途房演示性放行
## （notify_room_cleared 开门链，绕过「战斗锁门」；终点保持未清以触发真战斗装配）
## → 观战者落于致死点 → floor.enter_room 终点（接线 + 波次 + 锁门）。
## 任一环失败（pos 在走廊 / 图不连通 / boss 门未解）静默降级：观战者留在出生房。
func _spectate_to_fatal_pos(floor_scene: FloorScene, build: Dictionary, pos: Vector2) -> void:
	var target := -1
	for id in build["rooms"]:
		var rid := int(id)
		if floor_scene.room_rect(rid).has_point(pos):
			target = rid
			break
	if target < 0:
		return
	var path := _bfs_path(floor_scene, target)
	if path.is_empty():
		return
	for i in range(1, path.size() - 1):
		floor_scene.flow.notify_room_cleared(path[i])      # 演示放行：沿途门开
	if target == floor_scene.flow.boss_room() and floor_scene.flow.miniboss_room() >= 0:
		floor_scene.flow.notify_room_cleared(floor_scene.flow.miniboss_room())   # boss 门演示放行
	for i in range(1, path.size() - 1):
		if not floor_scene.flow.enter_room(path[i]):       # 纯状态推进（不触发战斗装配）
			return
	if _replay_player != null and is_instance_valid(_replay_player):
		_replay_player.global_position = pos
	floor_scene.enter_room(target)                         # 终点：真装配（接线+波次+锁门）
	# m2-t26：致死房是挑战房时回放自动代选灾厄（观战近似——重建的挑战房未走过
	# 4 选 1，不代选则波次被灾厄面板挂起、回放无战斗可看；不追求复现当时所选条目）。
	if target == floor_scene.challenge_room() and floor_scene.calamity_panel_visible():
		floor_scene.choose_calamity("enemy_speed")

## FloorFlow 邻接 BFS（start → target）；不可达返回空表。
func _bfs_path(floor_scene: FloorScene, target: int) -> Array[int]:
	var start := floor_scene.flow.start_room()
	if start < 0:
		return []
	var prev: Dictionary = {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == target:
			break
		for nxt in floor_scene.flow.adjacent(cur):
			if not prev.has(nxt):
				prev[nxt] = cur
				queue.append(nxt)
	if not prev.has(target):
		return []
	var path: Array[int] = []
	var walk := target
	while walk >= 0:
		path.push_front(walk)
		walk = int(prev[walk])
	return path

# ---- 回放查询面（测试/HUD） ----

func replay_active() -> bool:
	return _replay_state != ReplayState.IDLE


func replay_state() -> int:
	return _replay_state


func replay_floor() -> FloorScene:
	return _replay_floor


func replay_banner_text() -> String:
	return ($ReplayView/Banner as Label).text
