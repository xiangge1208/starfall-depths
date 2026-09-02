extends Node
## 成就系统（m2-t32）：22 条 M2 激活成就的判定引擎 + 解锁入档 + 右下角 toast 播报。
## autoload 名 "AchievementSystem"（无 class_name——引擎规则 class_name 不得遮蔽
## autoload 单例名，命名规则同 GameDB/RunState/SaveSystem/CodexSystem；任务卡的
## 「class_name AchievementSystem」按引擎约束不落地）。注册在 CodexSystem 之后
## （_ready 订阅其 weapon_unlocked 信号）。
##
## 判定规格权威 = 数据表附录 K（docs/superpowers/specs/数据表附录-K-成就接线.md，
## T3 定稿 24 条：22 条 M2 激活 + 试炼 2 条 M3-R-C 随试炼结算激活）。判定类型白名单：
##   event_once      订阅源信号到达且参数谓词满足 → 一次即得（first_lamp/delver/night_watcher）
##   event_count     源信号会话计数达阈值（element_scholar/demolition/dodge_master）
##   state_threshold 轮询 SaveSystem 字段达阈值（forge_smith/collector/grand_collector/
##                   full_roster/challenger/gifted/overflowing）
##   composite       多条件与：触发信号谓词 + 会话计数/RunState 字段/信号参数
##                   （bare_hands/deadeye/slum_king/flawless_elite/speedrunner/moneybags/
##                   nitpicker/no_heal/nightmare_dawn）
##
## 接线说明（附录 K.1/K.2 + 台账裁定⑧）：
## - 既有信号直连（不动发射侧文件）：EventBus.resonance_triggered / enemy_damaged /
##   enemy_killed / player_hit_resolved / room_cleared + CodexSystem.weapon_unlocked。
## - K.2 新声明信号（boss_slain/floor_reached/floor_cleared/victory/item_forged/
##   hero_unlocked/talent_purchased/prop_destroyed/roll_dodge/challenge_cleared）
##   由 T33 补线（裁定㉗）：发射点各 1 行 notify_* 直调（同 T20 count_buy 直调先例）——
##   boss_slain=floor_scene boss 房清 / floor_reached+floor_cleared=run_root 过层门 /
##   victory=run_root 胜利链 / item_forged=ui/forge 成交点 / hero_unlocked=SaveSystem.
##   unlock_hero 成功点（K.2 指定）/ talent_purchased=TalentSystem.buy 成功点 /
##   roll_dodge=player 翻滚窗躲弹幕 / challenge_cleared=floor_scene 挑战房清
##   （count_challenge 计数 + notify 同点）。
##   仍缺席的判定链（fail-closed 休眠，不误解锁）：
##   · prop_destroyed：可破坏物机制未建（props 为静态 solid，无破坏路径）→ 拆迁办
##     blocked，待机制卡落地后 1 行接入；
##   · shop_purchase：24 条成就无消费方（T20 buy_x 计数源，T35 已发射），无需就绪检测。
## - 试炼 2 条 M3-R-C 激活（trier/trial_master，state_threshold counter:trials_total）：
##   计数源 = RunState.record_trial_completed → notify_trial_completed（trials_total 为
##   CodexSystem 计数器表外键，unlock_tasks 快照持久化，见 _persist_trials_total）；
##   codex_seen（藏品家/大收藏家权威源）写键方未落地期间回落 unlocked_weapons 子集口径
##   （保守低估不误解锁，见 _state_value）。
## - 计数源与 T20 图鉴共享（计划卡明文）：单局会话计数订阅与 CodexSystem 同一批
##   EventBus 遥测信号（上述既有 5 路），累计口径一律读 SaveSystem 持久字段
##   （counters.* / unlocked_* / purchased_talents，K.5 的 T25 v2 消费位）——不造第二套
##   事件源。T20 无单局概念（其 counters 为 autoload 生命周期累计），而 K.1/K.4 单局
##   条件要求 reset_session 口径，故会话簿记由本卡自持。
## - 会话计数（单局口径）与 DeathRecorder.reset / T35 生命周期同点清零（reset_session）；
##   解锁集合跨局持久（SaveSystem.achievements），不随会话复位。
##
## 解锁路径（附录 K.1）：判定达成 → SaveSystem.unlock_achievement(id)（幂等持久化）
## → add_gems(附录 G.1 蓝晶原值) → achievement_unlocked(id) 信号 → toast
## 「成就解锁：xxx +N 蓝晶」（ui/toast.tscn 场景装配；右下角 3s 淡出，同屏最多 3 条）。

signal achievement_unlocked(id: String)

const TOAST_SCENE := "res://ui/toast.tscn"   # 计划卡 ui/toast.gd(+tscn) 场景装配面
const TOAST_SCRIPT := "res://ui/toast.gd"    # 场景缺席兜底（headless/未导入环境）

## 判定器表（附录 K 全表 24 条，M3-R-C 起全表 active=true；active=false 机制位保留
## ——置 false 即拒绝路由/解锁，当前无人使用）。试炼 2 条判定源 = counter:trials_total
## （notify_trial_completed，见 _persist_trials_total）。
## 字段：id / name(中文) / gems(蓝晶, 附录 G.1 原值) / active / type / trigger /
##   pred(触发信号参数谓词) / counter+goal(event_count) / source+goal(state_threshold) /
##   conds(composite 条件数组)。
## cond.src 命名空间：session:xxx 会话计数｜run:xxx RunState 字段｜sig:xxx 信号参数｜
##   ratio:a,b 百分比分子分母（配 op "ratio_gt" 整数交叉乘，避免浮点/截断误差）。
const DEFS: Array[Dictionary] = [
	# -- event_once --
	{"id": "first_lamp", "name": "初次点灯", "gems": 100, "active": true,
		"type": "event_once", "trigger": "boss_slain",
		"pred": {"field": "floor_idx", "op": "==", "value": 1}},
	{"id": "delver", "name": "深入者", "gems": 150, "active": true,
		"type": "event_once", "trigger": "floor_reached",
		"pred": {"field": "floor_idx", "op": ">=", "value": 3}},
	{"id": "night_watcher", "name": "守夜人", "gems": 300, "active": true,
		"type": "event_once", "trigger": "victory"},
	# -- event_count --
	{"id": "element_scholar", "name": "元素学者", "gems": 150, "active": true,
		"type": "event_count", "trigger": "resonance", "counter": "resonances", "goal": 30},
	{"id": "demolition", "name": "拆迁办", "gems": 50, "active": true,
		"type": "event_count", "trigger": "prop_destroyed", "counter": "props", "goal": 30},
	{"id": "dodge_master", "name": "走位大师", "gems": 100, "active": true,
		"type": "event_count", "trigger": "roll_dodge", "counter": "dodges", "goal": 100},
	# -- state_threshold --
	{"id": "forge_smith", "name": "熔铸匠", "gems": 100, "active": true,
		"type": "state_threshold", "source": "counter:crafts_total", "goal": 10},
	{"id": "collector", "name": "藏品家", "gems": 150, "active": true,
		"type": "state_threshold", "source": "save:codex_seen", "goal": 50},
	{"id": "grand_collector", "name": "大收藏家", "gems": 500, "active": true,
		"type": "state_threshold", "source": "save:codex_seen", "goal": 115},
	{"id": "full_roster", "name": "全员集合", "gems": 400, "active": true,
		"type": "state_threshold", "source": "save:unlocked_heroes", "goal": 6},
	{"id": "challenger", "name": "挑战者", "gems": 100, "active": true,
		"type": "state_threshold", "source": "counter:challenge_rooms_total", "goal": 5},
	{"id": "gifted", "name": "天赋异禀", "gems": 150, "active": true,
		"type": "state_threshold", "source": "save:purchased_talents", "goal": 12},
	{"id": "overflowing", "name": "满溢之光", "gems": 500, "active": true,
		"type": "state_threshold", "source": "save:purchased_talents", "goal": 24},
	# -- composite（触发谓词 + 条件与） --
	{"id": "bare_hands", "name": "赤手空拳", "gems": 200, "active": true,
		"type": "composite", "trigger": "floor_cleared",
		"conds": [
			{"src": "session:remote_fire", "op": "==", "value": 0},
			{"src": "session:melee_swings", "op": ">=", "value": 1},
		]},
	{"id": "deadeye", "name": "弹无虚发", "gems": 100, "active": true,
		"type": "composite", "trigger": "enemy_damaged",
		"conds": [
			{"src": "session:shots", "op": ">=", "value": 50},
			{"src": "ratio:crits,shots", "op": "ratio_gt", "value": 35},
		]},
	{"id": "slum_king", "name": "贫民窟之王", "gems": 100, "active": true,
		"type": "composite", "trigger": "floor_cleared",
		"pred": {"field": "floor_idx", "op": "==", "value": 1},
		"conds": [{"src": "session:deaths", "op": "==", "value": 0}]},
	{"id": "flawless_elite", "name": "无伤精英", "gems": 50, "active": true,
		"type": "composite", "trigger": "enemy_killed",
		"conds": [
			{"src": "sig:is_elite", "op": "==", "value": 1},
			{"src": "session:hurt_window", "op": "==", "value": 0},
		]},
	{"id": "speedrunner", "name": "速通者", "gems": 150, "active": true,
		"type": "composite", "trigger": "victory",
		"conds": [{"src": "run:run_time_frames", "op": "<", "value": 72000}]},   # 20min × 60fps
	{"id": "moneybags", "name": "财神", "gems": 100, "active": true,
		"type": "composite", "trigger": "floor_cleared",
		"pred": {"field": "floor_idx", "op": "==", "value": 1},
		"conds": [{"src": "run:coins", "op": ">", "value": 500}]},
	{"id": "nitpicker", "name": "鸡蛋里挑骨头", "gems": 100, "active": true,
		"type": "composite", "trigger": "boss_slain",
		"pred": {"field": "floor_idx", "op": "==", "value": 1},
		"conds": [{"src": "sig:weapon_category", "op": "==", "value": "throw"}]},
	{"id": "no_heal", "name": "拒绝治疗", "gems": 200, "active": true,
		"type": "composite", "trigger": "victory",
		"conds": [{"src": "session:heart_pickups", "op": "==", "value": 0}]},
	{"id": "nightmare_dawn", "name": "噩梦黎明", "gems": 300, "active": true,
		"type": "composite", "trigger": "boss_slain",
		"pred": {"field": "floor_idx", "op": "==", "value": 3},
		"conds": [{"src": "session:deaths", "op": "==", "value": 0}]},
	# -- 试炼 2 条（M3-R-C 随试炼结算接线激活；state_threshold counter:trials_total，
	#    计数源 = RunState.record_trial_completed → notify_trial_completed） --
	{"id": "trier", "name": "试炼者", "gems": 100, "active": true,
		"type": "state_threshold", "source": "counter:trials_total", "goal": 1},
	{"id": "trial_master", "name": "试炼大师", "gems": 200, "active": true,
		"type": "state_threshold", "source": "counter:trials_total", "goal": 10},
]

const COND_OPS: Array[String] = ["==", "!=", ">=", "<=", ">", "<", "ratio_gt"]

var save_system: Node = null   # 测试注入缝（临时路径档）；_ready 兜底探测 /root/SaveSystem
var toast: Node = null         # toast 注入缝（SpyToast/真实层）；_ready 自建 ui/toast.gd 层
var session: Dictionary = {}   # 会话计数（单局口径，reset_session 清零；K.3 判定数据）

var _defs_by_id: Dictionary = {}
var _defs_by_trigger: Dictionary = {}   # trigger 名 → id 数组


## _init(save) 直构注入（测试）；autoload 无参实例化 → save 为 null，_ready 探测。
func _init(save: Object = null) -> void:
	save_system = save
	for def: Dictionary in DEFS:
		_defs_by_id[String(def["id"])] = def
		_defs_by_trigger.get_or_add(String(def.get("trigger", "")), [] as Array).append(String(def["id"]))
	reset_session()


func _ready() -> void:
	if save_system == null:
		save_system = get_node_or_null("/root/SaveSystem")
	if toast == null:
		var packed: Variant = load(TOAST_SCENE)
		toast = packed.instantiate() if packed is PackedScene else load(TOAST_SCRIPT).new()
		add_child(toast)
	# 既有信号直连（K.2 既有 4 + player_hit_resolved/room_cleared 会话窗口源）
	EventBus.resonance_triggered.connect(
		func(_reaction: int, _at: Vector2, _payload: Dictionary) -> void: notify_resonance())
	EventBus.enemy_damaged.connect(notify_enemy_damaged)
	EventBus.enemy_killed.connect(notify_enemy_killed)
	EventBus.player_hit_resolved.connect(
		func(amount: int, fatal: bool, _ctx: Dictionary) -> void: notify_player_hit(amount, fatal))
	EventBus.room_cleared.connect(func(_room_id: String) -> void: notify_room_cleared())
	# 累计口径触发源（T20 解锁信号实例）：藏品家/大收藏家轮询点
	var codex := get_node_or_null("/root/CodexSystem")
	if codex != null and codex.has_signal("weapon_unlocked"):
		codex.weapon_unlocked.connect(func(_weapon_id: String) -> void: recheck())
		# m4-c3：codex_seen 写入方落地——首次见过武器（获取/任务解锁）同为轮询点，
		# 权威口径切换后见集增长即触发重判（回落逻辑 _state_value 不删不惑）。
		if codex.has_signal("weapon_seen"):
			codex.weapon_seen.connect(func(_weapon_id: String) -> void: recheck())


# ---- 查询 ----

func defs() -> Array[Dictionary]:
	return DEFS


func is_active(id: String) -> bool:
	var def: Dictionary = _defs_by_id.get(id, {})
	return not def.is_empty() and bool(def.get("active", false))


func is_unlocked(id: String) -> bool:
	if save_system == null:
		return false
	return save_system.is_achievement_unlocked(id)


func unlocked_achievements() -> Array[String]:
	if save_system == null:
		return [] as Array[String]
	return save_system.unlocked_achievements()


# ---- 会话生命周期（挂 DeathRecorder.reset / T35 新局生命周期同点调用） ----

## 单局口径清零：击杀/暴击窗口、死亡、受击窗口、红心、可破坏物、翻滚、
## 开火窗口（赤手空拳的本层窗口）。解锁集合持久，不清。
func reset_session() -> void:
	session = {
		"resonances": 0,
		"shots": 0,
		"crits": 0,
		"deaths": 0,
		"hurt_window": 0,
		"heart_pickups": 0,
		"props": 0,
		"dodges": 0,
		"remote_fire": 0,
		"melee_swings": 0,
	}


# ---- 事件吸收 + 判定路由 ----

## 统一入口：吸收会话计数/窗口 → 路由该 trigger 名下的判定器。
## EventBus 订阅闭包与 notify_* API 都汇到此处（直构实例不经 _ready 也可判）。
func _notify(source: String, sig: Dictionary = {}) -> void:
	_absorb(source, sig)
	_route(source, sig)


func _absorb(source: String, sig: Dictionary) -> void:
	match source:
		"resonance":
			session["resonances"] = int(session["resonances"]) + 1
		"enemy_damaged":
			if int(sig.get("amount", 0)) > 0:
				session["shots"] = int(session["shots"]) + 1
				if bool(sig.get("is_crit", false)):
					session["crits"] = int(session["crits"]) + 1
		"player_hit":
			if int(sig.get("amount", 0)) > 0:
				session["hurt_window"] = int(session["hurt_window"]) + 1
			if bool(sig.get("fatal", false)):
				session["deaths"] = int(session["deaths"]) + 1   # death 口径（K.4：≠受击）
		"room_cleared":
			session["hurt_window"] = 0            # 下一房受击窗口（无伤精英）
		"floor_reached":
			session["hurt_window"] = 0            # 新层窗口：受击 + 开火（赤手空拳本层口径）
			session["remote_fire"] = 0
			session["melee_swings"] = 0
		"heart_pickup":
			session["heart_pickups"] = int(session["heart_pickups"]) + 1
		"prop_destroyed":
			session["props"] = int(session["props"]) + 1
		"roll_dodge":
			session["dodges"] = int(session["dodges"]) + 1
		"weapon_used":
			var cat := String(sig.get("weapon_category", ""))
			if cat == "melee":
				session["melee_swings"] = int(session["melee_swings"]) + 1
			else:
				session["remote_fire"] = int(session["remote_fire"]) + 1   # 未知武器保守计远程
		_:
			pass   # boss_slain/floor_cleared/victory/item_forged 等：纯触发源，无吸收


func _route(source: String, sig: Dictionary) -> void:
	for id: String in _defs_by_trigger.get(source, [] as Array):
		var def: Dictionary = _defs_by_id[id]
		if not bool(def.get("active", false)) or is_unlocked(String(def["id"])):
			continue
		match String(def.get("type", "")):
			"event_once":
				if _pred_met(def, sig):
					_unlock(String(def["id"]))
			"event_count":
				if _has_signal_params(def) and not _pred_met(def, sig):
					continue
				if int(session.get(String(def.get("counter", "")), 0)) >= int(def.get("goal", 0)):
					_unlock(String(def["id"]))
			"composite":
				if _has_signal_params(def) and not _pred_met(def, sig):
					continue
				if _conds_met(def.get("conds", [] as Array), sig):
					_unlock(String(def["id"]))


func _has_signal_params(def: Dictionary) -> bool:
	return def.has("pred")


func _pred_met(def: Dictionary, sig: Dictionary) -> bool:
	var pred: Dictionary = def.get("pred", {})
	if pred.is_empty():
		return true
	return _cmp(int(sig.get(String(pred.get("field", "")), 0)),
		String(pred.get("op", "==")), int(pred.get("value", 0)))


func _conds_met(conds: Array, sig: Dictionary) -> bool:
	for cond: Dictionary in conds:
		if not _cond_met(cond, sig):
			return false
	return true


func _cond_met(cond: Dictionary, sig: Dictionary) -> bool:
	var src := String(cond.get("src", ""))
	var op := String(cond.get("op", ""))
	if op == "ratio_gt":                     # a/b 比值 > value%：交叉乘整型（无截断误差）
		var parts := src.substr(6).split(",")
		var a := int(session.get(parts[0], 0))
		var b := int(session.get(parts[1], 0))
		return a * 100 > int(cond.get("value", 0)) * maxi(b, 1)
	if not COND_OPS.has(op):
		return false                         # 未知 op fail-closed
	var value: Variant = cond.get("value")
	if typeof(value) == TYPE_STRING:         # 字符串条件（如 sig:weapon_category=="throw"）：
		if op != "==" and op != "!=":        # 仅等/不等；其余 op 对字符串无定义 → fail-closed
			return false
		var cur := _src_text(src, sig)
		return cur == String(value) if op == "==" else cur != String(value)
	return _cmp(_src_value(src, sig), op, int(value))


func _src_value(src: String, sig: Dictionary) -> int:
	if src.begins_with("session:"):
		return int(session.get(src.substr(8), 0))
	if src.begins_with("run:"):
		return int(RunState.get(src.substr(4)))
	if src.begins_with("sig:"):
		return int(sig.get(src.substr(4), 0))
	return 0   # 未知源 fail-closed


## 字符串版取值（type-strict：仅 TYPE_STRING 通过，类型不符/源缺席 → "" fail-closed）。
func _src_text(src: String, sig: Dictionary) -> String:
	if src.begins_with("session:"):
		var sv: Variant = session.get(src.substr(8))
		return String(sv) if typeof(sv) == TYPE_STRING else ""
	if src.begins_with("run:"):
		var rv: Variant = RunState.get(src.substr(4))
		return String(rv) if typeof(rv) == TYPE_STRING else ""
	if src.begins_with("sig:"):
		var gv: Variant = sig.get(src.substr(4))
		return String(gv) if typeof(gv) == TYPE_STRING else ""
	return ""


func _cmp(cur: int, op: String, value: int) -> bool:
	match op:
		"==": return cur == value
		"!=": return cur != value
		">=": return cur >= value
		"<=": return cur <= value
		">": return cur > value
		"<": return cur < value
	return false


# ---- 解锁引擎 ----

## 解锁：入档（幂等）→ 蓝晶奖励（附录 G.1 原值）→ 信号 → toast。
## save 缺席（直构未注入）/未知 id/试炼 M3 未激活 → false 不动作。
func _unlock(id: String) -> bool:
	if save_system == null:
		return false
	var def: Dictionary = _defs_by_id.get(id, {})
	if def.is_empty() or not bool(def.get("active", false)):
		return false
	if not save_system.unlock_achievement(id):
		return false                         # 已解锁（幂等去重，蓝晶不重复入账）
	save_system.add_gems(int(def.get("gems", 0)))
	achievement_unlocked.emit(id)
	_show_toast(id)
	return true


## state_threshold 全表扫描（轮询判定）：在任意 notify 事件 / recheck 显式调用点结算。
## 返回本次新解锁 id 列表（测试/UI 用）。
func recheck() -> Array[String]:
	var newly: Array[String] = []
	if save_system == null:
		return newly
	for id: String in _defs_by_id:
		var def: Dictionary = _defs_by_id[id]
		if String(def.get("type", "")) != "state_threshold":
			continue
		if not bool(def.get("active", false)) or is_unlocked(id):
			continue
		if _state_value(String(def.get("source", ""))) >= int(def.get("goal", 0)):
			if _unlock(id):
				newly.append(id)
	return newly


## 状态源解析：save:xxx → SaveSystem 防御性集合大小；counter:xxx → 权威计数器。
## counter 口径（T33 补线）：优先 CodexSystem 活计数器（存档 v2 unlock_tasks 的内存
## 权威，count_craft/count_challenge 写入方同源，结算点落盘）；直构实例（无树，
## codex 缺席）回落 save.data["counters"]（T32 期测试注入缝，保留）。
## codex_seen（K.3/K.5 藏品家/大收藏家权威源）当前无写入方（T20 只写 unlocked_weapons，
## 持久化归 T25 v2）：键缺席期间回落 unlocked_weapons 子集口径——它是 codex_seen 的
## 真子集（任务解锁必已见过），保守低估、绝不误解锁；写键方落地后自动切换为权威口径。
func _state_value(source: String) -> int:
	if source.begins_with("save:"):
		match source.substr(5):
			"unlocked_weapons":
				return save_system.unlocked_weapons().size()
			"codex_seen":
				var seen: Variant = save_system.data.get("codex_seen")
				if typeof(seen) == TYPE_ARRAY:
					var n := 0
					for e: Variant in seen:
						if typeof(e) == TYPE_STRING:
							n += 1
					return n
				return save_system.unlocked_weapons().size()   # 键缺席回落（见上）
			"purchased_talents":
				return save_system.purchased_talents().size()
			"unlocked_heroes":
				var arr: Variant = save_system.data.get("unlocked_heroes", [])
				var h := 0
				if typeof(arr) == TYPE_ARRAY:
					for e: Variant in arr:
						if typeof(e) == TYPE_STRING:
							h += 1
				return h
		return 0
	if source.begins_with("counter:"):
		var key := source.substr(8)
		var codex := get_node_or_null("/root/CodexSystem")
		if codex != null and codex.get("counters") is Dictionary \
				and (codex.get("counters") as Dictionary).has(key):
			return int((codex.get("counters") as Dictionary).get(key, 0))
		# M3-R-C：表外键（trials_total——CodexSystem.COUNTER_KEYS 无此键，计数源在
		# notify_trial_completed）回落存档 unlock_tasks 快照（持久化权威）；legacy
		# data["counters"] 直构测试缝保留其后（crafts_total 等六类键仍以 CodexSystem
		# 活计数器为权威，行为不变）。
		var tasks: Variant = save_system.data.get("unlock_tasks", {})
		if typeof(tasks) == TYPE_DICTIONARY and (tasks as Dictionary).has(key):
			return int((tasks as Dictionary).get(key, 0))
		var counters: Variant = save_system.data.get("counters", {})
		if typeof(counters) == TYPE_DICTIONARY:
			return int((counters as Dictionary).get(key, 0))
		return 0
	return 0   # 未知源 fail-closed（占位 0，永不误解锁）


# ---- 计数 / 通知 API（发射点：EventBus 订阅闭包 / 各发射责任卡直调 1 行） ----

## —— 纯触发源（K.2 新声明信号；发射点不在本卡所有权，直调接入点见头注释） ——
## 发射点：BossBase/RoomCombat 死亡上下文（携带 boss_id + 层号 + 击杀武器 id，
## kill 行已有该数据；weapon_id 缺省 "" = 类别未知，nitpicker 判定 fail-closed 不解锁）。
func notify_boss_slain(boss_id: String, floor_idx: int, weapon_id: String = "") -> bool:
	var cat := ""
	if weapon_id != "":
		cat = String(GameDB.get_weapon(weapon_id).get("category", ""))
	return _route_unlock("boss_slain", {"boss_id": boss_id, "floor_idx": floor_idx,
		"weapon_category": cat})


## 发射点：RunState.next_floor 后（抵达层号）。
func notify_floor_reached(floor_idx: int) -> bool:
	return _route_unlock("floor_reached", {"floor_idx": floor_idx})


## 发射点：InterFloor 层通过点（通过层号）。
func notify_floor_cleared(floor_idx: int) -> bool:
	return _notify_and_report("floor_cleared", {"floor_idx": floor_idx})


## 发射点：InterFloorFlow.victory_achieved（T18 既有实例信号，胜利链 1 行桥接）。
func notify_victory() -> bool:
	return _notify_and_report("victory", {})


## 发射点：熔铸台成交点（T25）/ 角色解锁成功点 / 天赋购买成功点（T15 buy）/ 挑战房收口。
func notify_item_forged(_recipe_id: String = "") -> bool:
	return _recheck_and_report()


func notify_hero_unlocked(_hero_id: String = "") -> bool:
	return _recheck_and_report()


func notify_talent_purchased(_talent_id: String = "") -> bool:
	return _recheck_and_report()


func notify_challenge_cleared() -> bool:
	return _recheck_and_report()


## 发射点：RunState.record_trial_completed（M3-R-C 试炼局结束单点；每局至多一次的
## 防重守卫在 RunState 侧）。trials_total +1 → state_threshold 轮询（试炼者 goal 1 /
## 试炼大师 goal 10）。trials_total 为 CodexSystem 计数器表外键（计数源在本卡），
## 持久化走 unlock_tasks 快照（见 _persist_trials_total）。返回本次是否产生新解锁。
func notify_trial_completed() -> bool:
	_persist_trials_total(_state_value("counter:trials_total") + 1)
	return _recheck_and_report()


## trials_total 快照落盘（对齐 m2-t31 unlock_tasks 手法）：与 CodexSystem 计数器快照
## 并档整体覆写（unlock_tasks 是整体快照语义——不并档会抹掉六类计数器最近快照）。
## 结算点顺序契约：Death/VictorySummary 确认内 codex.persist_counters() 先行、
## 本函数殿后 → 最终快照恒含两源（HUD 放弃路无显式 persist，由本函数并档覆盖）。
func _persist_trials_total(total: int) -> void:
	if save_system == null or not save_system.has_method("record_unlock_tasks"):
		return
	var snap: Dictionary = {}
	var codex := get_node_or_null("/root/CodexSystem")
	if codex != null and codex.has_method("snapshot_counters"):
		snap = codex.snapshot_counters()
	snap["trials_total"] = total
	save_system.record_unlock_tasks(snap)


## —— 计数源（会话吸收 + 触发判定） ——
func notify_prop_destroyed(_prop_kind: String = "") -> bool:
	return _notify_and_report("prop_destroyed", {})


func notify_roll_dodge() -> bool:
	return _notify_and_report("roll_dodge", {})


func notify_heart_pickup() -> bool:
	return _notify_and_report("heart_pickup", {})


## 开火窗口源（赤手空拳本层口径）：近战挥击计 melee，其余（含未知 id）保守计远程。
func notify_weapon_used(weapon_id: String) -> bool:
	var cat := String(GameDB.get_weapon(weapon_id).get("category", ""))
	return _notify_and_report("weapon_used", {"weapon_category": cat})


## —— EventBus 既有信号闭包直调入口（_ready 订阅 → 这里；测试亦可直驱） ——
func notify_resonance() -> bool:
	return _notify_and_report("resonance", {})


func notify_enemy_damaged(amount: int, is_crit: bool) -> bool:
	return _notify_and_report("enemy_damaged", {"amount": amount, "is_crit": is_crit})


func notify_enemy_killed(enemy_id: String) -> bool:
	var row: Dictionary = GameDB.enemies.get(enemy_id, {})
	var is_elite := not ((row.get("elite_affixes", []) as Array).is_empty())
	return _notify_and_report("enemy_killed", {"enemy_id": enemy_id, "is_elite": 1 if is_elite else 0})


func notify_player_hit(amount: int, fatal: bool) -> bool:
	return _notify_and_report("player_hit", {"amount": amount, "fatal": fatal})


func notify_room_cleared() -> bool:
	return _notify_and_report("room_cleared", {})


# ---- 内部路由 / 播报 ----

## 纯触发源路径：吸收（可能有窗口重置）→ 路由 → 返回本次是否产生了新解锁。
func _notify_and_report(source: String, sig: Dictionary) -> bool:
	var before := unlocked_achievements()
	_notify(source, sig)
	return unlocked_achievements().size() > before.size()


## 无吸收的纯触发源（boss_slain/floor_reached 只带参数）。
func _route_unlock(source: String, sig: Dictionary) -> bool:
	return _notify_and_report(source, sig)


func _recheck_and_report() -> bool:
	var before := unlocked_achievements()
	recheck()
	return unlocked_achievements().size() > before.size()


func _show_toast(id: String) -> void:
	var def: Dictionary = _defs_by_id.get(id, {})
	if toast != null and toast.has_method("show_toast") and not def.is_empty():
		toast.show_toast("成就解锁：%s +%d 蓝晶" % [String(def.get("name", id)), int(def.get("gems", 0))])
