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

const SAVE_VERSION := 1   # 迁移钩子：将来档结构变更时递增，并在 _migrate 补 from_version 分支

const DEFAULT_SETTINGS := {
	"screen_shake": 1.0,
	"damage_numbers": true,
	"colorblind_shapes": false,
	"auto_aim": true,
	"touch_controls": false,
}

# save_path 可被测试覆写（临时 user:// 路径注入）；生产代码勿改
var save_path := "user://save.json"
var data: Dictionary = {}

func _ready() -> void:
	load_save()

## 默认档：每次调用全新构造（调用方可自由改写，不与常量共享引用）。
func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"gems": 0,
		"unlocked_heroes": ["vanguard"] as Array[String],
		"achievements": {},
		"settings": DEFAULT_SETTINGS.duplicate(),
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
	if typeof(saved.get("achievements")) == TYPE_DICTIONARY:
		out["achievements"] = saved["achievements"]
	var settings_v: Variant = saved.get("settings")
	if typeof(settings_v) == TYPE_DICTIONARY:
		var saved_settings: Dictionary = settings_v
		for k: String in out["settings"]:
			var sv: Variant = saved_settings.get(k)
			if typeof(sv) == typeof(out["settings"][k]):
				out["settings"][k] = sv
	return out

## 迁移桩（结构就绪）：当前 SAVE_VERSION=1，无历史版本，故为 no-op。
## 将来加档字段时：递增 SAVE_VERSION，在此按 from_version 分支补默认值/搬移键，
## 返回迁移后的完整档（版本戳由 load_save 统一盖）。
func _migrate(migrated: Dictionary, from_version: int) -> Dictionary:
	return migrated

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
