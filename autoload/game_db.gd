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
# 可选键及默认值；locked:TYPE_BOOL（M2-T6）紫/橙默认锁定标记：不进 weapons 掉落池，留在 weapons_all
const WEAPON_OPTIONAL := {"range": 0, "arc_deg": 0.0, "locked": false}
# 敌人（t10）：required 仅 5 键，其余全部 optional 默认 0
const ENEMY_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "archetype": TYPE_STRING,
	"hp": TYPE_INT, "radius": TYPE_FLOAT,
}
const ENEMY_OPTIONAL := {
	"contact_dmg": 0, "speed": 0, "windup_ticks": 0, "cd_ticks": 0,
	"fuse_ticks": 0, "aoe_radius": 0.0, "aoe_dmg": 0,
	"bullet_dmg": 0, "bullet_speed": 0, "bullet_life_seconds": 0.0,
	"bullet_radius": 3.0,
	"walk_speed": 0, "dash_speed": 0.0, "dash_ticks": 0, "dash_cooldown_ticks": 0,
	"orbit_radius": 0.0,
}
# 房间模板（t4）：6 键全部必填，无 optional
const ROOM_SCHEMA := {
	"id": TYPE_STRING, "size": TYPE_ARRAY, "doors": TYPE_ARRAY,
	"spawn_points": TYPE_ARRAY, "props": TYPE_ARRAY, "hazards": TYPE_ARRAY,
}
const ROOM_OPTIONAL := {}
# 增益（t9）：5 键必填；稀有度与 effects 键白名单由 validate_buff_row 语义校验（同 rooms fail-closed 路径）
const BUFF_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "rarity": TYPE_STRING,
	"desc": TYPE_STRING, "effects": TYPE_DICTIONARY,
}
const BUFF_OPTIONAL := {}
const BUFF_RARITIES: Array[String] = ["common", "uncommon", "rare"]
# effects 键白名单（t9 控制器决议）：百分比键取数值，整型键取 int（_normalize_row 已还原）
const BUFF_PCT_KEYS: Array[String] = [
	"move_speed_pct", "crit_pct", "crit_dmg_pct", "atk_speed_pct",
	"bullet_speed_pct", "status_rate_pct", "roll_cd_pct", "crit_detonate_pct",
	"element_proc_chance",
]
const BUFF_INT_KEYS: Array[String] = [
	"hp_max", "shield_max", "energy_max", "shield_delay_reduction_ticks",
	"element_enchant", "extra_projectiles",
]
# 角色（t11）：16 键全部必填，无 optional；行级校验 validate_hero_row（start_weapons 白名单）
const HERO_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING,
	"hp": TYPE_INT, "shield": TYPE_INT, "energy": TYPE_INT,
	"speed": TYPE_FLOAT, "crit_chance": TYPE_FLOAT,
	"start_weapons": TYPE_ARRAY, "skill_script": TYPE_STRING,
	"skill_cd": TYPE_INT, "skill_energy": TYPE_INT,
	"passive_id": TYPE_STRING, "has_defiance": TYPE_BOOL,
	"skill_name": TYPE_STRING, "skill_desc": TYPE_STRING, "upgraded": TYPE_BOOL,
}
const HERO_OPTIONAL := {}
# 饮料（t16）：5 键全部必填，无 optional；行级校验 validate_drink_row（effect 白名单）
# value 统一 TYPE_INT：百分比按整数值（5 = +5%），延时/CD 按 ticks（30 = -0.5s）；
# random 行 value 固定 0（实际效果由 DrinkMachine 注入 rng 现抽）
const DRINK_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "effect": TYPE_STRING,
	"value": TYPE_INT, "price": TYPE_INT,
}
const DRINK_OPTIONAL := {}
const DRINK_EFFECTS: Array[String] = [
	"hp_max", "energy_max", "move_speed_pct", "crit_pct",
	"shield_delay_reduction_ticks", "roll_cd_ticks", "status_rate_pct", "random",
]
const DRINK_RANDOM_EFFECT := "random"
# 天赋（m2-t2）：8 键全部必填，无 optional；行级校验 validate_talent_row（分支/价格梯度/
# requires 自指重复/effects 键白名单与幅度上限），跨行校验 validate_talent_refs（引用存在 +
# 前置 tier 更低）+ validate_talent_acyclic（DFS 无环）由 _finalize_talents 收口，任一失败整表拒收。
const TALENT_SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING, "desc": TYPE_STRING,
	"branch": TYPE_STRING, "tier": TYPE_INT, "cost": TYPE_INT,
	"requires": TYPE_ARRAY, "effects": TYPE_DICTIONARY,
}
const TALENT_OPTIONAL := {}
const TALENT_BRANCHES: Array[String] = ["red", "blue", "green"]
const TALENT_COST_MIN := 100   # GDD §14.3 节点价格梯度下限
const TALENT_COST_MAX := 800   # 节点价格梯度上限
# effects 键白名单（m2-t2 控制器决议）：不带 talent_ 前缀的键必须与 BuffManager 聚合键
# 同名同义（GameDB.BUFF_*_KEYS，消费面为 M1 已接线的 Player/WeaponRig 公开字段）；
# 新键一律 talent_ 前缀，消费方逐键声明（数据表附录 I）：
#   talent_dmg_pct → M2-T15 TalentSystem → WeaponRig 伤害乘区
#   talent_hurt_iframe_pct → M2-T15 → Player.apply_iframes/HURT_IFRAME_TICKS 乘区
#   talent_gem_gain_pct → M2-T31 蓝晶结算（RunState → SaveSystem.add_gems 乘区）
#   talent_coin_gain_pct → M2-T15 → Pickup coin 结算（on_collect 计数），T31 结算复核
#   talent_pickup_radius_pct → M2-T15 → Pickup.MAGNET_RANGE_PX 乘区
const TALENT_PCT_KEYS: Array[String] = [
	"crit_pct", "crit_dmg_pct", "atk_speed_pct", "bullet_speed_pct",
	"status_rate_pct", "move_speed_pct", "roll_cd_pct", "element_proc_chance",
	"talent_dmg_pct", "talent_hurt_iframe_pct",
	"talent_gem_gain_pct", "talent_coin_gain_pct", "talent_pickup_radius_pct",
]
const TALENT_INT_KEYS: Array[String] = [
	"hp_max", "shield_max", "energy_max", "shield_delay_reduction_ticks",
]
# 单键幅度上限（GDD §14 基调：永久天赋 = 小额强化）。roll_cd_pct 沿用 buffs.json
# 约定：负值 = 缩短（Player.effective_roll_cd_ticks 用 1.0 + pct）。
# crit_dmg_pct 0.25（暴伤自身刻度：增益即 +50% 一档）、pickup 0.30（磁吸基线 56px，
# +10% 仅 5.6px 无感，QoL 键按自身刻度）为唯二放宽项。
const TALENT_KEY_MAX := {
	"crit_pct": 0.10, "crit_dmg_pct": 0.25, "atk_speed_pct": 0.10,
	"bullet_speed_pct": 0.10, "status_rate_pct": 0.15, "move_speed_pct": 0.10,
	"roll_cd_pct": 0.15, "element_proc_chance": 0.10,
	"talent_dmg_pct": 0.10, "talent_hurt_iframe_pct": 0.15,
	"talent_gem_gain_pct": 0.10, "talent_coin_gain_pct": 0.10,
	"talent_pickup_radius_pct": 0.30,
}
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
	"buffs": "res://data/buffs.json", "heroes": "res://data/heroes.json",
	"drinks": "res://data/drinks.json", "talents": "res://data/talents.json",
}

var weapons: Dictionary = {}        # 掉落池（locked 已排除）；消费方：FloorScene._roll_weapon / ShopLogic._weapons / validate_hero_row / get_weapon
var weapons_all: Dictionary = {}    # 全量 115 把（含 locked）；图鉴侧出口（M2-T20 CodexSystem 直接读此表）
var enemies: Dictionary = {}
var rooms: Dictionary = {}
var buffs: Dictionary = {}
var heroes: Dictionary = {}
var drinks: Dictionary = {}
var talents: Dictionary = {}
var load_ok := true

func _ready() -> void:
	weapons = _load_table("res://data/weapons.json", WEAPON_SCHEMA, WEAPON_OPTIONAL)
	# M2-T6 附录 A 解锁规则：紫/橙 49 把 locked:true 不进掉落池（weapons），
	# 全量留在 weapons_all 供图鉴展示（M2-T20 直接读 GameDB.weapons_all）。
	# get_weapon 仍走 weapons：locked 武器当前无获取途径（不掉落/非初始/熔铸未落地），
	# 解锁后再进池（T20 按 SaveSystem.unlocked 过滤）。
	weapons_all = weapons.duplicate(true)
	for id: String in weapons_all:
		if bool((weapons_all[id] as Dictionary).get("locked", false)):
			weapons.erase(id)
	enemies = _load_table("res://data/enemies.json", ENEMY_SCHEMA, ENEMY_OPTIONAL)
	rooms = _load_table(TABLES["rooms"], ROOM_SCHEMA, ROOM_OPTIONAL, validate_room_row)
	buffs = _load_table(TABLES["buffs"], BUFF_SCHEMA, BUFF_OPTIONAL, validate_buff_row)
	heroes = _load_table(TABLES["heroes"], HERO_SCHEMA, HERO_OPTIONAL, validate_hero_row)
	drinks = _load_table(TABLES["drinks"], DRINK_SCHEMA, DRINK_OPTIONAL, validate_drink_row)
	talents = _finalize_talents(_load_table(
		TABLES["talents"], TALENT_SCHEMA, TALENT_OPTIONAL, validate_talent_row))
	if not load_ok:
		push_error("GameDB: data validation failed")
		get_tree().quit(1)

func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})

func get_enemy(id: String) -> Dictionary:
	return enemies.get(id, {})

func get_buff(id: String) -> Dictionary:
	return buffs.get(id, {})

func get_hero(id: String) -> Dictionary:
	return heroes.get(id, {})

func get_drink(id: String) -> Dictionary:
	return drinks.get(id, {})

func get_talent(id: String) -> Dictionary:
	return talents.get(id, {})

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

## 增益行语义校验（t9），作为 buffs 表 _load_table 的 extra_check。
## 约束：rarity ∈ 白/绿/蓝；effects 非空且键全部在白名单内；
## 百分比键取数值、整型键取 int（带小数会被 _normalize_row 留成 float 而在此拒绝）；
## element_enchant 必须是合法 Elements.Id。
func validate_buff_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not BUFF_RARITIES.has(row.get("rarity")):
		errors.append("bad rarity: %s" % str(row.get("rarity")))
	var eff: Variant = row.get("effects")
	if typeof(eff) != TYPE_DICTIONARY or (eff as Dictionary).is_empty():
		errors.append("effects must be non-empty object")
		return errors
	for k: String in eff:
		var v: Variant = eff[k]
		if BUFF_PCT_KEYS.has(k):
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				errors.append("effect %s must be number" % k)
		elif BUFF_INT_KEYS.has(k):
			if typeof(v) != TYPE_INT:
				errors.append("effect %s must be int" % k)
			elif k == "element_enchant" and not Elements.NAMES.has(v):
				errors.append("effect element_enchant bad Elements.Id: %d" % int(v))
		else:
			errors.append("unknown effect key: %s" % k)
	# 元素附魔是「命中概率附加状态」契约：元素与概率必须成对出现。
	# 星髓像的 100% 临时覆盖不走 buffs.json，不能用缺省概率把永久 Buff 误做成必触发。
	var has_element := (eff as Dictionary).has("element_enchant")
	var has_chance := (eff as Dictionary).has("element_proc_chance")
	if has_element != has_chance:
		errors.append("element_enchant and element_proc_chance must appear together")
	if has_element and int((eff as Dictionary)["element_enchant"]) == Elements.Id.NONE:
		errors.append("element_enchant must be a non-none Elements.Id")
	if has_chance:
		var chance := float((eff as Dictionary)["element_proc_chance"])
		if chance <= 0.0 or chance > 1.0:
			errors.append("element_proc_chance must be in (0,1]")
	return errors

## 饮料行语义校验（t16），作为 drinks 表 _load_table 的 extra_check。
## 约束：effect ∈ 白名单；random 行 value 固定 0（现抽）；
## 具体效果 value 必须为正（GameDB 已按 schema 还原 int，带小数在类型校验即拒绝）。
func validate_drink_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var effect: String = row.get("effect", "")
	if not DRINK_EFFECTS.has(effect):
		errors.append("bad effect: %s" % effect)
		return errors
	var value := int(row.get("value", 0))
	if effect == DRINK_RANDOM_EFFECT:
		if value != 0:
			errors.append("random effect value must be 0")
	elif value <= 0:
		errors.append("effect %s value must be positive" % effect)
	if int(row.get("price", -1)) < 0:
		errors.append("price must be >= 0")
	return errors

## 角色行语义校验（t11），作为 heroes 表 _load_table 的 extra_check。
## 约束：start_weapons 非空且每把武器都存在于 weapons 表（weapons 先于 heroes 装载）。
## skill_script 存在性由单测覆盖（test_hero_skill_scripts_exist_and_extend_skill_base）。
func validate_hero_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var sw: Variant = row.get("start_weapons")
	if typeof(sw) != TYPE_ARRAY or (sw as Array).is_empty():
		errors.append("start_weapons must be non-empty array")
		return errors
	for w: Variant in sw:
		if typeof(w) != TYPE_STRING or not weapons.has(w):
			errors.append("unknown start weapon: %s" % str(w))
	return errors

## 天赋行语义校验（m2-t2），作为 talents 表 _load_table 的 extra_check。
## 约束：branch ∈ 红/蓝/绿；tier ∈ 1..8；cost ∈ 价格梯度 [100, 800]；
## requires 元素全为 String、无重复、无自指（引用存在性与层序由跨行校验负责）；
## effects 非空、键在白名单（复用 buff_manager 键 + talent_ 前缀新键）内、
## 百分键幅度 ≤ TALENT_KEY_MAX（roll_cd_pct 约定负值 = 缩短）、整型键为正 int。
func validate_talent_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not TALENT_BRANCHES.has(row.get("branch")):
		errors.append("bad branch: %s" % str(row.get("branch")))
	var tier := int(row.get("tier", 0))
	if tier < 1 or tier > 8:
		errors.append("tier must be in 1..8: %d" % tier)
	var cost := int(row.get("cost", 0))
	if cost < TALENT_COST_MIN or cost > TALENT_COST_MAX:
		errors.append("cost must be in [%d, %d]: %d" % [TALENT_COST_MIN, TALENT_COST_MAX, cost])
	var requires: Variant = row.get("requires")
	if typeof(requires) != TYPE_ARRAY:
		errors.append("requires must be array")
	else:
		var seen := {}
		for req: Variant in requires:
			if typeof(req) != TYPE_STRING:
				errors.append("requires element must be string: %s" % str(req))
				continue
			if req == row.get("id"):
				errors.append("requires self: %s" % req)
			elif seen.has(req):
				errors.append("duplicate requires: %s" % req)
			else:
				seen[req] = true
	var eff: Variant = row.get("effects")
	if typeof(eff) != TYPE_DICTIONARY or (eff as Dictionary).is_empty():
		errors.append("effects must be non-empty object")
		return errors
	for k: String in eff:
		var v: Variant = eff[k]
		if TALENT_PCT_KEYS.has(k):
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				errors.append("effect %s must be number" % k)
				continue
			var f := float(v)
			if k == "roll_cd_pct":
				if f > 0.0 or absf(f) > float(TALENT_KEY_MAX[k]):
					errors.append("effect %s must be negative and |v| <= %s" % [k, str(TALENT_KEY_MAX[k])])
			elif f <= 0.0 or f > float(TALENT_KEY_MAX[k]):
				errors.append("effect %s must be in (0, %s]" % [k, str(TALENT_KEY_MAX[k])])
		elif TALENT_INT_KEYS.has(k):
			if typeof(v) != TYPE_INT:
				errors.append("effect %s must be int" % k)
			elif int(v) < 1 or int(v) > 100:
				errors.append("effect %s must be int in [1, 100]: %d" % [k, int(v)])
		else:
			errors.append("unknown effect key: %s" % k)
	return errors

## 天赋跨行校验（m2-t2）：requires 引用必须存在于同表，且前置 tier 严格更低。
## 层序规则保证「价格随层单调」→ 最便宜优先购买集必为合法前置闭包（60% 经济数学前提）。
static func validate_talent_refs(nodes: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for id: String in nodes:
		var row: Dictionary = nodes[id]
		for req: Variant in row.get("requires", []):
			if not nodes.has(req):
				errors.append("%s: unknown requires: %s" % [id, str(req)])
			elif int((nodes[req] as Dictionary).get("tier", 0)) >= int(row.get("tier", 0)):
				errors.append("%s: requires tier must be lower: %s" % [id, str(req)])
	return errors

## 天赋环检测（m2-t2，纯函数可单测）：按 requires 建边（节点 → 前置），DFS 三色标记，
## 遇灰色回边即有环。缺失引用不在此判定（归 validate_talent_refs），视为无该边跳过。
static func validate_talent_acyclic(nodes: Dictionary) -> bool:
	var state := {}
	for id: String in nodes:
		state[id] = 0
	for id: String in nodes:
		if int(state[id]) == 0 and not _talent_dfs(id, nodes, state):
			return false
	return true

static func _talent_dfs(id: String, nodes: Dictionary, state: Dictionary) -> bool:
	state[id] = 1
	for req: Variant in (nodes[id] as Dictionary).get("requires", []):
		if not nodes.has(req) or typeof(req) != TYPE_STRING:
			continue
		var s := int(state[req])
		if s == 1:
			return false
		if s == 0 and not _talent_dfs(req, nodes, state):
			return false
	state[id] = 2
	return true

## talents 装载收口（fail-closed）：行级校验已由 _load_table 完成，此处整表执行
## 跨行校验（引用存在 + 层序）与无环检测，任一失败即整表拒收并置 load_ok = false
## （_ready 据此 push_error + quit(1)）。
func _finalize_talents(nodes: Dictionary) -> Dictionary:
	if nodes.is_empty():
		return nodes
	var errors := validate_talent_refs(nodes)
	if errors.is_empty() and not validate_talent_acyclic(nodes):
		errors.append("requires cycle detected")
	if not errors.is_empty():
		load_ok = false
		push_error("GameDB talents: %s" % ", ".join(errors))
		return {}
	return nodes

func _is_grid(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 2 \
		and (typeof(v[0]) == TYPE_INT or typeof(v[0]) == TYPE_FLOAT) \
		and (typeof(v[1]) == TYPE_INT or typeof(v[1]) == TYPE_FLOAT)

func _in_bounds(grid: Variant) -> bool:
	return float(grid[0]) >= 0.0 and float(grid[0]) <= float(ROOM_SIZE[0] - 1) \
		and float(grid[1]) >= 0.0 and float(grid[1]) <= float(ROOM_SIZE[1] - 1)
