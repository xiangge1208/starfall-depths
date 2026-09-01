class_name TrialRecords
extends RefCounted
## 每日试炼本地排行榜（M3-R-B，试炼规格 §5）：`user://trial_records.json` 纯本地读写。
## 数据形状：{ "version": 1, "records": [record ×N], "daily_best": { 日期 → {deepest_floor,
## clear_time_s} } }；每次试炼局结束追加 1 条 records（写入点随 R-C 接线），保留最近 30 条；
## daily_best 同日「最深层数优先、次取最短用时」。
##
## 【有意 fail-SOFT——对齐 SaveSystem 语义，与 GameDB fail-closed 相反】本类管的是玩家
## 本地战绩：损坏/缺字段/类型错一律 push_error 重建空表，绝不阻断启动（丢一表好过开不了
## 游戏）。record 字段校验从宽：缺字段回落合理默认（§5 示例同形补全），仅 date（非空串）
## 与 factors（数组）类型必须对——不合者单条剔除（一条坏行不牵连整表）。
##
## 测试注入缝：records_path 可覆写为临时 user:// 路径（同 SaveSystem.save_path 惯例，
## 测试禁写真档）。纯逻辑类（RefCounted，无树依赖）；读取不缓存——每次调用直读盘上
## 活动档（UI 卡低频打开，非热路径）。

const VERSION := 1
const MAX_RECORDS := 30     # records 保留上限（规格 §5「保留最近 30 条」）
const HISTORY_ROWS := 10    # 面板历史行数（规格 §5 UI「历史最近 10 条」）

var records_path := "user://trial_records.json"


## 空表骨架：每次全新构造（调用方可自由改写，不与共享引用粘连）。
func _empty_table() -> Dictionary:
	return {"version": VERSION, "records": [], "daily_best": {}}


## 读取 + 校验：缺文件 = 首次使用（静默空表，不报错）；顶层形状坏（非对象/records 非
## 数组/daily_best 非字典/JSON 损坏）→ 重建空表；record 级问题单条剔除（见类头注释）。
func load_records() -> Dictionary:
	if not FileAccess.file_exists(records_path):
		return _empty_table()
	var text := ""
	var f := FileAccess.open(records_path, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
		f = null
	if text.is_empty():
		_fail("empty or unreadable")
		return _empty_table()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail("not a JSON object")
		return _empty_table()
	var raw: Dictionary = parsed
	var table := _empty_table()
	var records_v: Variant = raw.get("records", null)
	if not (records_v is Array):
		_fail("records must be an array")
		return _empty_table()
	for r: Variant in records_v:
		var rec := _sanitize_record(r)
		if not rec.is_empty():
			(table["records"] as Array).append(rec)
	var best_v: Variant = raw.get("daily_best", null)
	if not (best_v is Dictionary):
		_fail("daily_best must be an object")
		return _empty_table()
	var best: Dictionary = table["daily_best"]
	for k: Variant in best_v:
		var row: Variant = best_v[k]
		if row is Dictionary:
			var d: Dictionary = row
			best[String(k)] = {
				"deepest_floor": int(d.get("deepest_floor", 0)),
				"clear_time_s": int(d.get("clear_time_s", 0)),
			}
	return table


## 追加 1 条（规格 §5）：字段校验从宽同读取（date/factors 类型必须对，否则拒收）→
## 截断最近 30 条 → daily_best 归并 → 落盘。返回是否入档。
func append_record(record: Dictionary) -> bool:
	var rec := _sanitize_record(record)
	if rec.is_empty():
		return false
	var table := load_records()
	var records: Array = table["records"]
	records.append(rec)
	if records.size() > MAX_RECORDS:
		table["records"] = records.slice(records.size() - MAX_RECORDS)   # 保留最近 30
	_merge_daily_best(table, rec)
	return _save(table)


## 某日今日最佳（无记录日期 → 空字典）。
func daily_best(date_str: String) -> Dictionary:
	var best: Dictionary = load_records()["daily_best"]
	var row: Variant = best.get(date_str, {})
	return row if row is Dictionary else {}


## 最近 n 条记录，最新在前（面板直显序）；不足 n 全给，n ≤ 0 返回空表。
func recent(n: int) -> Array:
	var records: Array = load_records()["records"]
	var out := records.slice(maxi(records.size() - maxi(n, 0), 0))
	out.reverse()
	return out


# ---------------------------------------------------------------- 内部

## record 校验从宽：缺字段回落 §5 默认；date（非空 String）/ factors（Array）类型必须
## 对——不合者返回空字典（单条剔除）。factors 元素统一 String 归一。
func _sanitize_record(r: Variant) -> Dictionary:
	if not (r is Dictionary):
		_fail("record is not an object")
		return {}
	var d: Dictionary = r
	var date: Variant = d.get("date", "")
	if not (date is String) or (date as String).is_empty():
		_fail("record.date must be a non-empty string")
		return {}
	var factors_v: Variant = d.get("factors", null)
	if not (factors_v is Array):
		_fail("record.factors must be an array")
		return {}
	var factors: Array[String] = []
	for fid: Variant in factors_v:
		factors.append(String(fid))
	return {
		"date": date,
		"hero_id": String(d.get("hero_id", "")),
		"deepest_floor": int(d.get("deepest_floor", 0)),
		"clear_time_s": int(d.get("clear_time_s", 0)),
		"gems_earned": int(d.get("gems_earned", 0)),
		"victory": bool(d.get("victory", false)),
		"factors": factors,
	}


## daily_best 归并（规格 §5）：同日「最深层数优先、次取最短用时」；首次即建档。
func _merge_daily_best(table: Dictionary, rec: Dictionary) -> void:
	var best: Dictionary = table["daily_best"]
	var date := String(rec["date"])
	var cur_v: Variant = best.get(date, null)
	if cur_v is Dictionary:
		var cur: Dictionary = cur_v
		var cur_floor := int(cur.get("deepest_floor", 0))
		var floor_i := int(rec["deepest_floor"])
		var deeper := floor_i > cur_floor
		var same_depth_faster := floor_i == cur_floor \
			and int(rec["clear_time_s"]) < int(cur.get("clear_time_s", 0))
		if not (deeper or same_depth_faster):
			return
	best[date] = {
		"deepest_floor": int(rec["deepest_floor"]),
		"clear_time_s": int(rec["clear_time_s"]),
	}


## 落盘（紧凑 JSON）。原子写（M3-R-C 移交①，对齐 SaveSystem.save_now 手法）：tmp 写完
## flush 后 rename 覆盖目标——进程任意时刻死掉最多留下 .tmp 残骸，records 本体要么是
## 旧表要么是新表，不会写半截。写失败 push_error 返回 false（fail-soft：丢一写不崩进程）。
func _save(table: Dictionary) -> bool:
	var tmp := records_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_fail("write failed")
		return false
	f.store_string(JSON.stringify(table))
	f.flush()
	f = null   # 先落引用再改名（Windows 上打开中的文件不可 rename）
	if DirAccess.rename_absolute(tmp, records_path) != OK:
		_fail("rename failed")
		return false
	return true


## fail-soft 单点：损坏可观测（push_error）但不崩、不阻断（对齐 SaveSystem 头注释口径）。
func _fail(why: String) -> void:
	push_error("TrialRecords: %s (%s) —— 重建空表（fail-soft）" % [why, records_path])
