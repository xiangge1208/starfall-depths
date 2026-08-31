extends Node
## 图鉴 + 解锁任务引擎（m2-t20）：读 data/unlock_tasks.json（T3 定稿 49 条，J 全表），
## 六类计数条件判定（J.2）→ 达成即解锁武器：SaveSystem.unlocked_weapons 持久化 +
## 非★回掉落池（GameDB.grant_to_pool）+ weapon_unlocked 信号（UI 播报钩子）。
##
## autoload 名 "CodexSystem"（无 class_name——引擎规则 class_name 不得遮蔽 autoload
## 单例名，命名规则同 GameDB/RunState/SaveSystem）；注册在 SaveSystem 之后（_ready 读档回池）。
##
## 计数口径（J.2：跨局累计；持久化归 M2-T25 存档 v2——本卡计数器为内存会话累计，
## autoload 生命周期跨局存活、进程退出即清零，解锁结果本身已入档不丢）：
##   kills_total       ← EventBus.enemy_killed（每敌死亡 +1，与 Telemetry kill 行同源）
##   resonances_total  ← EventBus.resonance_triggered（共鸣触发 +1）
##   crafts_total      ← count_craft()（m2-t25 熔铸台已接线：ui/forge.gd 熔铸成功点 +1）
##   purchases_total   ← shop.gd 三个购买成功点 +1（J.2 的 shop_purchase 信号归 T35，
##                       本卡按控制器决议走直调 1 行）
##   gems_earned_total ← 过层蓝晶（on_floor_entered 按 RunState.FLOOR_GEMS 镜像）；
##                       击杀/首杀/成就蓝晶口径依赖 T32/T33（J.2），届时补 count_gems 调用
##   floor_clears      ← 过层分桶 {层号: 次数}（「通过第 N 层」= 进入 N+1 层）
##
## 掉落池契约（J.6）：locked 且未解锁不入池（GameDB 装载已排除）；解锁后非★回池；
## ★forge_only 4 把只进图鉴不回池（熔铸产出路径保留）。

signal weapon_unlocked(id: String)

const TASKS_PATH := "res://data/unlock_tasks.json"
## 条件类型白名单（J.2；与 test_unlock_data.TYPE_WHITELIST 一致，未知类型 fail-closed 计 0）
const TYPE_WHITELIST: Array[String] = [
	"kill_x", "clear_floor_x", "craft_x", "resonate_x", "collect_gems_x", "buy_x",
]
## 计数器键（J.2 counters.* 命名；floor_clears 为 {层号:int → 次数:int} 分桶）
const COUNTER_KEYS: Array[String] = [
	"kills_total", "resonances_total", "crafts_total",
	"purchases_total", "gems_earned_total",
]

var save_system: Node = null   # 测试注入缝（临时路径档）；_ready 兜底探测 /root/SaveSystem
var tasks: Dictionary = {}     # task id（=武器 id）→ 归一化行（param/goal float→int 还原）
var counters: Dictionary = {}  # 六类计数器（见 COUNTER_KEYS / floor_clears），内存会话累计

## _init(save) 直构注入（测试）；autoload 无参实例化 → save 为 null，_ready 探测。
## 任务表装载与计数器复位在 _init 完成（纯 FileAccess+JSON，不触树）——直构实例
## （不入树，_ready 不跑）同样具备完整任务数据。
func _init(save: Object = null) -> void:
	save_system = save
	tasks = _load_tasks()
	_reset_counters()


func _ready() -> void:
	if save_system == null:
		save_system = get_node_or_null("/root/SaveSystem")
	# 事件计数源（既有信号直连，不动发射侧文件）
	EventBus.enemy_killed.connect(count_kill)
	EventBus.resonance_triggered.connect(_on_resonance_triggered)
	# 已解锁武器回池（旧档继续有效；★排除同解锁路径）
	if save_system != null:
		for id: String in save_system.unlocked_weapons():
			_grant_if_poolable(id)


# ---- 任务装载 ----

## FileAccess 直读（T3 数据卡先行模式，不经 GameDB 装载）；float 整值还原口径同
## GameDB._normalize_row。坏行/缺文件 push_error 后跳过（引擎侧 fail-soft：缺表=全锁）。
func _load_tasks() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(TASKS_PATH):
		push_error("CodexSystem: missing %s" % TASKS_PATH)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TASKS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CodexSystem: bad json %s" % TASKS_PATH)
		return out
	for id: String in parsed:
		if typeof(parsed[id]) != TYPE_DICTIONARY:
			push_error("CodexSystem %s: row not a dictionary" % id)
			continue
		var row: Dictionary = parsed[id]
		for k: String in ["param", "goal"]:
			var v: Variant = row.get(k)
			if typeof(v) == TYPE_FLOAT and float(int(v)) == float(v):
				row[k] = int(v)
		if not TYPE_WHITELIST.has(String(row.get("type", ""))) \
				or typeof(row.get("goal")) != TYPE_INT or int(row["goal"]) <= 0:
			push_error("CodexSystem %s: bad task row, treated locked" % id)
			continue
		out[id] = row
	return out


func _reset_counters() -> void:
	counters = {
		"kills_total": 0, "resonances_total": 0, "crafts_total": 0,
		"purchases_total": 0, "gems_earned_total": 0,
		"floor_clears": {},   # {层号:int → 通过次数:int}
	}


# ---- 查询 ----

func is_unlocked(weapon_id: String) -> bool:
	if save_system == null:
		return false
	return save_system.unlocked_weapons().has(weapon_id)


## ★熔铸限定（unlock_tasks.forge_only；未知武器 → false）
func forge_only(weapon_id: String) -> bool:
	var row: Dictionary = tasks.get(weapon_id, {})
	return bool(row.get("forge_only", false))


## 任务进度：{cur, goal}。clear_floor_x 的 cur = floor_clears[param]（J.2 按层分桶，
## goal = 通过次数）；未知任务/未知类型返回零进度（fail-closed，永不误解锁）。
func progress(task_id: String) -> Dictionary:
	var row: Dictionary = tasks.get(task_id, {})
	var goal := int(row.get("goal", 0)) if not row.is_empty() else 0
	return {"cur": _cur_of(row), "goal": goal}


func _cur_of(row: Dictionary) -> int:
	if row.is_empty():
		return 0
	match String(row.get("type", "")):
		"kill_x":
			return int(counters.get("kills_total", 0))
		"resonate_x":
			return int(counters.get("resonances_total", 0))
		"craft_x":
			return int(counters.get("crafts_total", 0))
		"buy_x":
			return int(counters.get("purchases_total", 0))
		"collect_gems_x":
			return int(counters.get("gems_earned_total", 0))
		"clear_floor_x":
			var bucket: Dictionary = counters.get("floor_clears", {})
			return int(bucket.get(int(row.get("param", 0)), 0))
	return 0   # 未知类型 fail-closed


## 会话计数快照（T22 结算 / T25 迁移 / UI 进度展示读取）。
func snapshot_counters() -> Dictionary:
	return counters.duplicate(true)


# ---- 解锁引擎 ----

## 全表扫描：条件达成（cur >= goal）且未解锁 → 入档 + 回池（非★）+ 播信号。
## 返回本次新解锁的武器 id 列表。幂等（已解锁跳过）；save 缺席（直构未注入）时不动作。
## 挂点：每层进入（run_root → on_floor_entered）、每次计数事件后（本卡计数 API 内联调用）。
func check_unlocks() -> Array[String]:
	var newly: Array[String] = []
	if save_system == null:
		return newly
	for id: String in tasks:
		var weapon := String(tasks[id].get("weapon", id))
		if is_unlocked(weapon):
			continue
		var p := progress(id)
		if int(p["cur"]) < int(p["goal"]):
			continue
		save_system.unlock_weapon(weapon)
		_grant_if_poolable(weapon)
		newly.append(weapon)
		weapon_unlocked.emit(weapon)
	return newly


## ★不回池（J.6）：forge_only 解锁只点亮图鉴，掉落路径保留熔铸产出。
func _grant_if_poolable(weapon: String) -> void:
	if not forge_only(weapon):
		GameDB.grant_to_pool(weapon)


# ---- 计数 API（发射点：EventBus 订阅 / shop.gd 购买成功 / T25 熔铸 / T32-T33 蓝晶） ----

func count_kill(_enemy_id: String) -> void:
	counters["kills_total"] = int(counters.get("kills_total", 0)) + 1
	check_unlocks()


func _on_resonance_triggered(_reaction: int, _at: Vector2, _payload: Dictionary) -> void:
	count_resonate()


func count_resonate() -> void:
	counters["resonances_total"] = int(counters.get("resonances_total", 0)) + 1
	check_unlocks()


## 熔铸计数（调用方：m2-t25 ui/forge.gd 的熔铸成功路径，配方熔铸与通用升级各 +1）
func count_craft() -> void:
	counters["crafts_total"] = int(counters.get("crafts_total", 0)) + 1
	check_unlocks()


## 商店购买计数（shop.gd 武器/道具/饮料三个购买成功点各 +1）
func count_buy() -> void:
	counters["purchases_total"] = int(counters.get("purchases_total", 0)) + 1
	check_unlocks()


## 蓝晶入账计数（本卡仅过层蓝晶经 on_floor_entered 间接进入；击杀/成就蓝晶口径 T32/T33）
func count_gems(n: int) -> void:
	if n <= 0:
		return
	counters["gems_earned_total"] = int(counters.get("gems_earned_total", 0)) + n
	check_unlocks()


## 层进入挂点（run_root._on_next_floor_requested 1 行直调）：进入 N 层（N>=2）即
## 「通过第 N-1 层」→ clears[N-1]+1 并按 RunState.FLOOR_GEMS 镜像过层蓝晶入账，
## 随后 check_unlocks（结算点与每层进入合一）。
func on_floor_entered(new_floor: int) -> void:
	if new_floor < 2:
		return
	var cleared := new_floor - 1
	var bucket: Dictionary = counters.get("floor_clears", {})
	bucket[cleared] = int(bucket.get(cleared, 0)) + 1
	counters["floor_clears"] = bucket
	var gems_table: Array = RunState.FLOOR_GEMS
	var awarded := int(gems_table[clampi(cleared - 1, 0, gems_table.size() - 1)])
	counters["gems_earned_total"] = int(counters.get("gems_earned_total", 0)) + awarded
	check_unlocks()
