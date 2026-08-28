extends Node
## 数据库 autoload：启动加载 data/*.json 并校验 schema；有错误则报错退出。

const WEAPON_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "category": TYPE_STRING,
	"rarity": TYPE_STRING, "damage": TYPE_INT, "rate": TYPE_FLOAT,
	"energy_cost": TYPE_INT, "bullet_speed": TYPE_INT, "spread_deg": TYPE_FLOAT,
	"projectiles": TYPE_INT, "pierce": TYPE_INT, "bounce": TYPE_INT,
	"element": TYPE_STRING, "is_melee": TYPE_BOOL,
}
# 可选键及默认值
const WEAPON_OPTIONAL := {"range": 0, "arc_deg": 0.0}
const TABLES := {"weapons": "res://data/weapons.json"}

var weapons: Dictionary = {}
var load_ok := true

func _ready() -> void:
	weapons = _load_table("res://data/weapons.json", WEAPON_SCHEMA, WEAPON_OPTIONAL)
	if not load_ok:
		push_error("GameDB: data validation failed")
		get_tree().quit(1)

func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})

func validate_row(row: Dictionary, schema: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in schema:
		if not row.has(key):
			errors.append("missing key: %s" % key)
		elif typeof(row[key]) != schema[key]:
			errors.append("type mismatch: %s want %d got %d" % [key, schema[key], typeof(row[key])])
	return errors

func _load_table(path: String, schema: Dictionary, optional: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		load_ok = false
		push_error("GameDB: missing %s" % path)
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		load_ok = false
		push_error("GameDB: bad json %s" % path)
		return out
	for id: String in parsed:
		var row: Dictionary = parsed[id]
		_normalize_row(row, schema, optional)
		if row.get("id", "") != id:
			load_ok = false
			push_error("GameDB: id mismatch %s" % id)
		var errs := validate_row(row, schema)
		if not errs.is_empty():
			load_ok = false
			push_error("GameDB %s row %s: %s" % [path, id, ", ".join(errs)])
		for k: String in optional:
			if not row.has(k):
				row[k] = optional[k]
		out[id] = row
	return out

## Godot 4.7.2 的 JSON.parse_string 把所有数字（含整数字面量）都解析为 float。
## 按 schema 与 optional 默认值声明的类型，把无小数部分的 float 还原为 int，
## 保证行内 Variant 类型与 schema 契约一致（后续任务按此读表）。
func _normalize_row(row: Dictionary, schema: Dictionary, optional: Dictionary) -> void:
	var wanted := schema.duplicate()
	for k: String in optional:
		if not wanted.has(k):
			wanted[k] = typeof(optional[k])
	for key: String in wanted:
		if wanted[key] == TYPE_INT and typeof(row.get(key)) == TYPE_FLOAT:
			var as_int := int(row[key])
			if float(as_int) == row[key]:
				row[key] = as_int
