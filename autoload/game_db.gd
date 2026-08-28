extends Node
## 数据库 autoload：启动加载 data/*.json 并校验 schema；有错误则报错退出。

const WEAPON_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "category": TYPE_STRING,
	"rarity": TYPE_STRING, "damage": TYPE_INT, "rate": TYPE_FLOAT,
	"energy_cost": TYPE_INT, "bullet_speed": TYPE_INT, "spread_deg": TYPE_FLOAT,
	"projectiles": TYPE_INT, "pierce": TYPE_INT, "bounce": TYPE_INT,
	"element": TYPE_STRING, "is_melee": TYPE_BOOL,
	"bullet_life": TYPE_FLOAT, "bullet_radius": TYPE_FLOAT, "muzzle": TYPE_FLOAT,
}
# 可选键及默认值
const WEAPON_OPTIONAL := {"range": 0, "arc_deg": 0.0}
# 敌人（t10）：required 仅 5 键，其余全部 optional 默认 0
const ENEMY_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "archetype": TYPE_STRING,
	"hp": TYPE_INT, "radius": TYPE_FLOAT,
}
const ENEMY_OPTIONAL := {
	"contact_dmg": 0, "speed": 0, "windup_ticks": 0, "cd_ticks": 0,
	"fuse_ticks": 0, "aoe_radius": 0.0, "aoe_dmg": 0,
	"bullet_dmg": 0, "bullet_speed": 0, "bullet_life_seconds": 0.0,
	"walk_speed": 0, "dash_speed": 0.0, "dash_ticks": 0, "dash_cooldown_ticks": 0,
	"orbit_radius": 0.0,
}
# 房间模板（t4）：6 键全部必填，无 optional
const ROOM_SCHEMA := {
	"id": TYPE_STRING, "size": TYPE_ARRAY, "doors": TYPE_ARRAY,
	"spawn_points": TYPE_ARRAY, "props": TYPE_ARRAY, "hazards": TYPE_ARRAY,
}
const ROOM_OPTIONAL := {}
const ROOM_SIZE := [22, 14]   # A1 标准房间 22x14 格（x 0..21, y 0..13）
const DOOR_TILES := {"N": [11, 0], "S": [11, 13], "E": [21, 7], "W": [0, 7]}
const ROOM_TILE_PX := 16        # 格坐标转像素
const SPAWN_DOOR_MIN_PX := 64.0 # 刷怪点距任一门 >= 64px（GDD §9.3：4 瓦片）
const PROP_KINDS: Array[String] = ["pillar", "crate", "bush"]
# 行为契约（t4 仅数据，碰撞/挡弹由后续 RoomCombat 按 kind 实现）：
# 柱 hp20 挡弹 / 箱 hp8 挡弹 / 灌木 hp4 不挡弹（视觉+危险区）
const PROP_BLOCKS_BULLETS := {"pillar": true, "crate": true, "bush": false}
const TABLES := {
	"weapons": "res://data/weapons.json", "enemies": "res://data/enemies.json",
	"rooms": "res://data/rooms/a1_templates.json",
}

var weapons: Dictionary = {}
var enemies: Dictionary = {}
var rooms: Dictionary = {}
var load_ok := true

func _ready() -> void:
	weapons = _load_table("res://data/weapons.json", WEAPON_SCHEMA, WEAPON_OPTIONAL)
	enemies = _load_table("res://data/enemies.json", ENEMY_SCHEMA, ENEMY_OPTIONAL)
	rooms = _load_table(TABLES["rooms"], ROOM_SCHEMA, ROOM_OPTIONAL, validate_room_row)
	if not load_ok:
		push_error("GameDB: data validation failed")
		get_tree().quit(1)

func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})

func get_enemy(id: String) -> Dictionary:
	return enemies.get(id, {})

func validate_row(row: Dictionary, schema: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in schema:
		if not row.has(key):
			errors.append("missing key: %s" % key)
		elif typeof(row[key]) != schema[key]:
			errors.append("type mismatch: %s want %d got %d" % [key, schema[key], typeof(row[key])])
	return errors

## extra_check：可选的行级语义校验（如 rooms 的 validate_room_row），与 schema 校验同路径 fail-closed。
func _load_table(path: String, schema: Dictionary, optional: Dictionary,
		extra_check: Callable = Callable()) -> Dictionary:
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
		if typeof(parsed[id]) != TYPE_DICTIONARY:
			load_ok = false
			push_error("GameDB %s row %s: not a dictionary" % [path, id])
			continue
		var row: Dictionary = parsed[id]
		_normalize_row(row, schema, optional)
		if row.get("id", "") != id:
			load_ok = false
			push_error("GameDB: id mismatch %s" % id)
			continue
		var errs := validate_row(row, schema)
		if extra_check.is_valid():
			errs.append_array(extra_check.call(row))
		if not errs.is_empty():
			load_ok = false
			push_error("GameDB %s row %s: %s" % [path, id, ", ".join(errs)])
			continue
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
	# 嵌套结构（rooms 的 grid/hp/radius 等）同样按整值还原；
	# schema 明示 TYPE_FLOAT 的顶层键保持 float，不参与还原
	for key: String in row:
		if wanted.get(key, TYPE_NIL) == TYPE_FLOAT:
			continue
		row[key] = _deep_int_restore(row[key])

func _deep_int_restore(value: Variant) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			for i: int in value.size():
				value[i] = _deep_int_restore(value[i])
			return value
		TYPE_DICTIONARY:
			for k: String in value:
				value[k] = _deep_int_restore(value[k])
			return value
		TYPE_FLOAT:
			var as_int := int(value)
			if float(as_int) == value:
				return as_int
	return value

## 房间模板语义校验（几何/布局约束），作为 rooms 表 _load_table 的 extra_check。
## 约束：size 固定 [22,14]；doors 为 N/S/E/W 无重复非空子集（起始房允许仅 1 门）；
## 刷怪点界内且距任一门 >= 64px；props 界内且不得压门格；hazards 形状合法（data-only）。
func validate_room_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	# size
	var size: Variant = row.get("size")
	if typeof(size) != TYPE_ARRAY or size.size() != 2 \
			or int(size[0]) != ROOM_SIZE[0] or int(size[1]) != ROOM_SIZE[1]:
		errors.append("size must be %s" % str(ROOM_SIZE))
	# doors
	var doors: Variant = row.get("doors")
	var door_px: Array[Vector2] = []
	var door_grids: Array = []
	if typeof(doors) != TYPE_ARRAY or doors.is_empty():
		errors.append("doors must be non-empty N/S/E/W subset")
	else:
		var seen := {}
		for d: Variant in doors:
			if typeof(d) != TYPE_STRING or not DOOR_TILES.has(d):
				errors.append("bad door: %s" % str(d))
			elif seen.has(d):
				errors.append("duplicate door: %s" % d)
			else:
				seen[d] = true
				var t: Array = DOOR_TILES[d]
				door_grids.append(t)
				# 门像素位 = 门格中心（房间边缘中点）
				door_px.append(Vector2(t[0] * ROOM_TILE_PX + 8, t[1] * ROOM_TILE_PX + 8))
	# spawn_points：界内 + 距门距离
	var spawns: Variant = row.get("spawn_points", [])
	if typeof(spawns) != TYPE_ARRAY:
		errors.append("spawn_points must be array")
	else:
		for i: int in spawns.size():
			var sp: Variant = spawns[i]
			if not _is_grid(sp):
				errors.append("spawn_points[%d] must be [x,y] grid" % i)
				continue
			if not _in_bounds(sp):
				errors.append("spawn_points[%d] out of bounds: %s" % [i, str(sp)])
			var px := Vector2(float(sp[0]) * ROOM_TILE_PX + 8, float(sp[1]) * ROOM_TILE_PX + 8)
			for dp: Vector2 in door_px:
				if px.distance_to(dp) < SPAWN_DOOR_MIN_PX:
					errors.append("spawn_points[%d] %s within %dpx of door" \
						% [i, str(sp), int(SPAWN_DOOR_MIN_PX)])
	# props：kind 合法 + 界内 + 不压门格
	var props: Variant = row.get("props", [])
	if typeof(props) != TYPE_ARRAY:
		errors.append("props must be array")
	else:
		for i: int in props.size():
			var p: Variant = props[i]
			if typeof(p) != TYPE_DICTIONARY:
				errors.append("props[%d] must be object" % i)
				continue
			if not PROP_KINDS.has(p.get("kind")):
				errors.append("props[%d] bad kind: %s" % [i, str(p.get("kind"))])
			var grid: Variant = p.get("grid")
			if not _is_grid(grid):
				errors.append("props[%d] grid must be [x,y] grid" % i)
				continue
			if not _in_bounds(grid):
				errors.append("props[%d] out of bounds: %s" % [i, str(grid)])
			for dg: Array in door_grids:
				if int(grid[0]) == int(dg[0]) and int(grid[1]) == int(dg[1]):
					errors.append("props[%d] on door tile: %s" % [i, str(grid)])
	# hazards（本任务 data-only，仅校验形状）
	var hazards: Variant = row.get("hazards", [])
	if typeof(hazards) != TYPE_ARRAY:
		errors.append("hazards must be array")
	else:
		for i: int in hazards.size():
			var h: Variant = hazards[i]
			if typeof(h) != TYPE_DICTIONARY or h.get("kind") != "vine":
				errors.append("hazards[%d] kind must be vine" % i)
				continue
			var hg: Variant = h.get("grid")
			if not _is_grid(hg) or not _in_bounds(hg):
				errors.append("hazards[%d] grid out of bounds" % i)
			var radius: Variant = h.get("radius")
			if typeof(radius) != TYPE_INT and typeof(radius) != TYPE_FLOAT:
				errors.append("hazards[%d] radius must be number" % i)
	return errors

func _is_grid(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 2 \
		and (typeof(v[0]) == TYPE_INT or typeof(v[0]) == TYPE_FLOAT) \
		and (typeof(v[1]) == TYPE_INT or typeof(v[1]) == TYPE_FLOAT)

func _in_bounds(grid: Variant) -> bool:
	return float(grid[0]) >= 0.0 and float(grid[0]) <= float(ROOM_SIZE[0] - 1) \
		and float(grid[1]) >= 0.0 and float(grid[1]) <= float(ROOM_SIZE[1] - 1)
