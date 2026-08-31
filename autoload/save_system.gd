extends Node
## 存档系统 autoload（m1-t17）：meta 进度（蓝晶/角色解锁/成就/设置）的持久化。
## autoload 名 "SaveSystem"（无 class_name，命名规则同 GameDB/RunState）；
## project.godot 中注册在 RunState 之后。
##
## 【有意 fail-SOFT——与 GameDB 的 fail-closed 相反】GameDB 管的是开发资产数据表，
## 校验失败宁可启动即退（防错误数据静默扩散）；本系统管的是玩家存档，损坏档
## 绝不能阻断启动——丢一档好过开不了游戏。故损坏/畸形/键型错一律 push_error
## 或静默回落后照常可玩，游戏永不因存档问题 quit。
##
## 接线说明（控制器决议）：本卡只交付服务+测试；RunState.next_floor 的蓝晶结算
## 不在本卡改动 run_state.gd，由 T20/T22 结算时调用 SaveSystem.add_gems 持久化。

## m2-t31+m2-t32 存档 v2：SAVE_VERSION 1→2。v2 相对 v1 纯增量（additive）——新增
## unlock_tasks 进度（CodexSystem 计数器快照）与 boss_first_kills 名录（m2-t31），
## 成就字段正式入版本化口径（achievements id→true，v1 及更早档由 _migrate 归一，
## m2-t32）。全部由 _merge_saved 的默认骨架回落，无键搬移/改形；版本戳是正式化
## （此后新字段按版本分支演进，不再靠 additive 默认值隐式兜底）。
## purchased_talents（m2-t15）/unlocked_weapons（m2-t20）/成就字段自 v1 起已存在。
const SAVE_VERSION := 2   # 迁移钩子：档结构变更时递增，并在 _migrate 补 from_version 分支

const DEFAULT_SETTINGS := {
	"screen_shake": 1.0,
	"damage_numbers": true,
	"colorblind_shapes": false,
	"auto_aim": true,
	"touch_controls": false,
}

# save_path 可被测试覆写（临时 user:// 路径注入）；生产代码勿改。
# headless（GdUnit / 场景冒烟 / 无头工具）一律重定向到隔离档：测试驱动的真实玩法
# 结算（层进入/解锁/死亡胜利落盘）不得污染开发者真档（T31+T32 合并后暴露）。
var save_path := "user://save.json"
var data: Dictionary = {}

func _ready() -> void:
	if DisplayServer.get_name() == "headless" and save_path == "user://save.json":
		save_path = "user://save_headless.json"
	load_save()

## 默认档：每次调用全新构造（调用方可自由改写，不与常量共享引用）。
func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"gems": 0,
		"unlocked_heroes": ["vanguard"] as Array[String],
		"achievements": {},
		"settings": DEFAULT_SETTINGS.duplicate(),
		# m2-t15 已购天赋列表（v1 起 additive；v2 保留口径不变）：旧档缺失由
		# _merge_saved 回落默认空表。TalentSystem.buy 成功后经 record_talent_purchase
		# 入库（别造第二套：读写都走本系统）。
		"purchased_talents": [] as Array[String],
		# m2-t20：图鉴已解锁武器 id（T20 解锁引擎达成任务后入库；同 additive 键位，
		# 旧档缺失回落空表。★4 把 forge_only 解锁后也记这里，掉落池过滤由 GameDB 侧排除）。
		"unlocked_weapons": [] as Array[String],
		# m2-t31（v2 新增）：Boss 首杀名录（击杀蓝晶 +300 的防重刷标记；旧档缺失
		# 由 _merge_saved 回落默认空表）。
		"boss_first_kills": [] as Array[String],
		# m2-t31（v2 新增）：图鉴解锁任务进度（CodexSystem.counters 快照：五标量
		# 计数 + floor_clears 层号分桶）。CodexSystem 在层进入/解锁/终局结算点写入，
		# _ready 读档恢复——J.2 跨局累计的持久化后端。
		"unlock_tasks": {},
	}

## 读取存档到 data 并返回。缺文件→默认档（静默）；损坏/畸形→push_error+默认档；
## 可解析但键缺失/类型错→逐键回落默认（同样 fail-SOFT）。
## version 缺失/非法视为 0（最老），< SAVE_VERSION 时走 _migrate 迁移钩子。
func load_save() -> Dictionary:
	data = _default_data()
	if not FileAccess.file_exists(save_path):
		return data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: corrupted save %s — falling back to defaults (fail-soft)" % save_path)
		return data
	var from_version := 0
	var version_v: Variant = parsed.get("version")
	if typeof(version_v) == TYPE_INT or typeof(version_v) == TYPE_FLOAT:
		from_version = int(version_v)
	var merged := _merge_saved(parsed)
	if from_version < SAVE_VERSION:
		merged = _migrate(merged, from_version)
	merged["version"] = SAVE_VERSION   # 迁移（或首次规范化）后盖当前版本戳
	data = merged
	return data

## 把已解析的存档行并入默认档骨架：类型正确的键覆盖，缺失/类型错的键保留默认。
func _merge_saved(saved: Dictionary) -> Dictionary:
	var out := _default_data()
	var gems_v: Variant = saved.get("gems")
	if typeof(gems_v) == TYPE_INT or typeof(gems_v) == TYPE_FLOAT:
		out["gems"] = int(gems_v)   # JSON 数字统一为 float，此处还原 int
	var heroes_v: Variant = saved.get("unlocked_heroes")
	if typeof(heroes_v) == TYPE_ARRAY:
		var arr: Array[String] = []
		for e: Variant in heroes_v:
			if typeof(e) == TYPE_STRING:
				arr.append(e)   # 非法元素静默丢弃（fail-SOFT）
		out["unlocked_heroes"] = arr
	# m2-t15：已购天赋列表同 unlocked_heroes 口径合并（数组内非 String 元素静默丢弃）
	var talents_v: Variant = saved.get("purchased_talents")
	if typeof(talents_v) == TYPE_ARRAY:
		var tarr: Array[String] = []
		for e: Variant in talents_v:
			if typeof(e) == TYPE_STRING:
				tarr.append(e)
		out["purchased_talents"] = tarr
	# m2-t20：图鉴已解锁武器同口径合并（数组内非 String 元素静默丢弃）
	var weapons_v: Variant = saved.get("unlocked_weapons")
	if typeof(weapons_v) == TYPE_ARRAY:
		var warr: Array[String] = []
		for e: Variant in weapons_v:
			if typeof(e) == TYPE_STRING:
				warr.append(e)
		out["unlocked_weapons"] = warr
	# m2-t31：Boss 首杀名录同口径合并（数组内非 String 元素静默丢弃）
	var boss_kills_v: Variant = saved.get("boss_first_kills")
	if typeof(boss_kills_v) == TYPE_ARRAY:
		var barr: Array[String] = []
		for e: Variant in boss_kills_v:
			if typeof(e) == TYPE_STRING:
				barr.append(e)
		out["boss_first_kills"] = barr
	# m2-t31（v2）：解锁任务进度合并（标量计数 int 还原；floor_clears 的 JSON 字符串
	# 键归一化回 int——CodexSystem 按整型层号查桶；非数字/非字典该键回落默认）
	out["unlock_tasks"] = _normalize_unlock_tasks(saved.get("unlock_tasks"))
	if typeof(saved.get("achievements")) == TYPE_DICTIONARY:
		var ach_in: Dictionary = saved["achievements"]
		var ach: Dictionary = {}
		for k: Variant in ach_in:               # 键归一 String（id）；脏键静默丢弃
			if typeof(k) == TYPE_STRING:
				ach[String(k)] = true           # 值归一 true（集合语义，不存旧值）
		out["achievements"] = ach
	var settings_v: Variant = saved.get("settings")
	if typeof(settings_v) == TYPE_DICTIONARY:
		var saved_settings: Dictionary = settings_v
		for k: String in out["settings"]:
			var sv: Variant = saved_settings.get(k)
			if typeof(sv) == typeof(out["settings"][k]):
				out["settings"][k] = sv
	return out

## 迁移钩子（结构就绪；m2-t31+m2-t32 双口径合并）。v1→v2：纯 additive——
## unlock_tasks 进度 / boss_first_kills 名录（m2-t31）与成就字段版本化归一
## （m2-t32，id→true 集合由 _merge_saved 完成）等 v2 新键 v1 写档器从不写入，
## _merge_saved 默认骨架已回落，v1 既有键（gems/unlocked_heroes/purchased_talents/
## unlocked_weapons/achievements/settings）原样保留，故本分支无搬移动作，仅作正式化
## 记录。幂等由 load_save 保证：from_version == SAVE_VERSION 时不进本函数（重复载入
## v2 档零迁移）。将来 v3：在此按 from_version 分支补默认值/搬移键，返回迁移后的
## 完整档（版本戳由 load_save 统一盖）。
func _migrate(migrated: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		pass   # v1→v2 additive-only：见上注，无键搬移
	return migrated

## unlock_tasks 进度归一化（m2-t31 v2）：标量计数 float→int 还原（JSON 数字统一为
## float）；floor_clears 分桶键 int 化（JSON 对象键只能是字符串，CodexSystem 按整型
## 层号查桶）；非数字标量/非字典分桶整键丢弃（fail-SOFT 回落默认）。未知顶层键按
## 原样保留（SaveSystem 不做 codex 键白名单——单一事实源在 CodexSystem.COUNTER_KEYS）。
func _normalize_unlock_tasks(saved: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(saved) != TYPE_DICTIONARY:
		return out
	for k: String in saved:
		var val: Variant = saved[k]
		if k == "floor_clears":
			if typeof(val) == TYPE_DICTIONARY:
				var bucket: Dictionary = {}
				for fk: Variant in val:
					var fv: Variant = val[fk]
					if _is_number(fv):
						bucket[int(fk)] = int(fv)
				out[k] = bucket
		elif _is_number(val):
			out[k] = int(val)
	return out

func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

## 写盘：临时文件写完 flush 后 rename 覆盖目标（原子性足够——进程任意时刻死掉
## 最多留下 .tmp 残骸，save.json 本体要么是旧档要么是新档，不会写半截）。
func save_now() -> void:
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s (err %d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	f = null   # 先落引用再改名（Windows 上打开中的文件不可 rename）
	var err := DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		push_error("SaveSystem: rename %s -> %s failed (err %d)" % [tmp, save_path, err])

func add_gems(n: int) -> void:
	data["gems"] = gems() + n
	save_now()

func gems() -> int:
	return int(data.get("gems", 0))

func is_setting_explicit(key: String) -> bool:
	return data.get("settings", {}).has(key)   # 键存在即用户显式设置过（含 false）


func get_setting(key: String, default: Variant) -> Variant:
	var settings: Variant = data.get("settings")
	if typeof(settings) != TYPE_DICTIONARY:
		return default
	return settings.get(key, default)

func set_setting(key: String, value: Variant) -> void:
	if typeof(data.get("settings")) != TYPE_DICTIONARY:
		data["settings"] = DEFAULT_SETTINGS.duplicate()
	data["settings"][key] = value
	save_now()

## 解锁角色：已解锁→false（幂等，不重复入库不重写盘）；新解锁→入库+存盘+true。
func unlock_hero(id: String) -> bool:
	var heroes: Array = data.get("unlocked_heroes", [])
	if heroes.has(id):
		return false
	heroes.append(id)
	data["unlocked_heroes"] = heroes
	save_now()
	return true

## 已购天赋列表（m2-t15 最小新增）：防御性读取——档内非数组/脏元素一律过滤，
## 恒返回 Array[String]（空表 = 未购任何节点）。T31 migration v2 时保留本口径。
func purchased_talents() -> Array[String]:
	var out: Array[String] = []
	var saved: Variant = data.get("purchased_talents")
	if typeof(saved) == TYPE_ARRAY:
		for e: Variant in saved:
			if typeof(e) == TYPE_STRING:
				out.append(e)   # 非法元素静默丢弃（fail-SOFT）
	return out

## 天赋购买入库（m2-t15）：幂等 append + 落盘。蓝晶扣减由调用方（TalentSystem.buy）
## 经 add_gems(-cost) 完成——两次落盘在菜单场景可接受，非热路径。
func record_talent_purchase(id: String) -> void:
	var arr: Array = data.get("purchased_talents", [])
	if not arr.has(id):
		arr.append(id)
	data["purchased_talents"] = arr
	save_now()

## 图鉴解锁武器入库（m2-t20）：幂等 append + 落盘（口径同 unlock_hero——已解锁→false
## 不重复入库不重写盘；新解锁→true）。调用方 CodexSystem.check_unlocks 在任务达成时调。
func unlock_weapon(id: String) -> bool:
	var arr: Array = data.get("unlocked_weapons", [])
	if arr.has(id):
		return false
	arr.append(id)
	data["unlocked_weapons"] = arr
	save_now()
	return true

## 已解锁武器列表（m2-t20）：防御性读取——档内非数组/脏元素一律过滤，
## 恒返回 Array[String]（空表 = 全部 49 把 locked 仍锁定）。
func unlocked_weapons() -> Array[String]:
	var out: Array[String] = []
	var saved: Variant = data.get("unlocked_weapons")
	if typeof(saved) == TYPE_ARRAY:
		for e: Variant in saved:
			if typeof(e) == TYPE_STRING:
				out.append(e)   # 非法元素静默丢弃（fail-SOFT）
	return out

## Boss 首杀名录（m2-t31）：防御性读取——档内非数组/脏元素一律过滤，
## 恒返回 Array[String]（空表 = 尚无任何 Boss 被首杀）。
func boss_first_kills() -> Array[String]:
	var out: Array[String] = []
	var saved: Variant = data.get("boss_first_kills")
	if typeof(saved) == TYPE_ARRAY:
		for e: Variant in saved:
			if typeof(e) == TYPE_STRING:
				out.append(e)   # 非法元素静默丢弃（fail-SOFT）
	return out

## Boss 首杀标记入库（m2-t31）：幂等 append + 落盘（口径同 unlock_weapon——
## 已记录 → false 不重复入库不重写盘；新记录 → true）。调用方 RunState.settle_kill_gems
## 在 Boss 死亡结算时查询并标记，防死亡重试/跨局重刷首杀 +300。
func record_boss_first_kill(id: String) -> bool:
	var arr: Array = data.get("boss_first_kills", [])
	if arr.has(id):
		return false
	arr.append(id)
	data["boss_first_kills"] = arr
	save_now()
	return true

## 解锁任务进度读取（m2-t31 v2）：防御性——档内非字典/脏键经 _merge_saved 归一化，
## 恒返回 Dictionary（空表 = 全零进度）。CodexSystem._ready 恢复计数器用。
func unlock_tasks() -> Dictionary:
	var saved: Variant = data.get("unlock_tasks")
	if typeof(saved) == TYPE_DICTIONARY:
		return saved
	return {}

## 解锁任务进度入库（m2-t31 v2）：整体快照覆写 + 落盘（计数器只在层进入/解锁/
## 终局结算点写入，非每次击杀热路径）。floor_clears 分桶键 int 化后存储，JSON 落盘
## 自动转字符串、_merge_saved 读回再归一化（往返一致）。
func record_unlock_tasks(progress: Dictionary) -> void:
	data["unlock_tasks"] = _normalize_unlock_tasks(progress)
	save_now()

## ---- 成就（m2-t32）：持久化集合（achievements id→true）+ 幂等解锁 ----
## 字段 m1-t17 起即在默认档骨架（"achievements": {}），本卡补访问器并随 SAVE_VERSION=2
## 正式版本化（_merge_saved 键值归一）。附录 K.5 命名 unlocked_achievements 对齐到
## 访问器名；档内键沿用既有 "achievements"（避免同档双键漂移）。

## 成就解锁入库：已解锁→false（幂等，不重写盘）；新解锁→入集+存盘+true。
## 蓝晶奖励由调用方 AchievementSystem._unlock 按 DEFS 表 add_gems（本层不识奖励表）。
func unlock_achievement(id: String) -> bool:
	var ach: Dictionary = data.get("achievements", {})
	if typeof(ach) != TYPE_DICTIONARY:
		ach = {}
	if ach.has(id):
		return false
	ach[id] = true
	data["achievements"] = ach
	save_now()
	return true

## 已解锁成就 id 列表（防御性读取，恒 Array[String]）。
func unlocked_achievements() -> Array[String]:
	var out: Array[String] = []
	var saved: Variant = data.get("achievements")
	if typeof(saved) == TYPE_DICTIONARY:
		for k: Variant in saved:
			if typeof(k) == TYPE_STRING:
				out.append(String(k))
	return out

func is_achievement_unlocked(id: String) -> bool:
	var saved: Variant = data.get("achievements")
	return typeof(saved) == TYPE_DICTIONARY and (saved as Dictionary).has(id)
