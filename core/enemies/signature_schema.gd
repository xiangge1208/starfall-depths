class_name SignatureSchema
extends RefCounted
## M4-C1 敌人派味特技行为键 schema（fail-closed）：data/enemies.json 新增行为键的
## 类型与语义域校验。autoload/game_db.gd 的 ENEMY_SCHEMA 属他卡所有权（本卡禁改
## autoload/**），既有口径为「未知键透传不校验」；本卡以独立校验器收口：
##   - tools/validate_enemies.gd（--script 无头独立校验，错误退出码 1）
##   - tests/unit/test_signature_moves.gd（GameDB 全行过验 + 坏行拒收）
## 双入口共用本纯静态逻辑（无 autoload 依赖，--script 模式可用）。
##
## 基础键镜像（required 5 键，与 GameDB.ENEMY_SCHEMA 对齐——漂移时此处报缺键）；
## 既有可选键仍由 archetype row.get() 缺省语义持有（m1-t10 遗留口径，本卡不扩收），
## 本卡新增派味特技键全量登记于此，语义域越界即拒收。

const BASE_REQUIRED := {
	"id": TYPE_STRING, "name": TYPE_STRING, "archetype": TYPE_STRING,
	"hp": TYPE_INT, "radius": TYPE_FLOAT,
}

## 派味特技键 → 期望类型（JSON 解析后数字为 float：int 契约键接受「无小数 float」）。
const SIGNATURE_KEYS := {
	"shell_walk_ticks": TYPE_INT,       # 龟缩：周期行走窗长（>0）
	"shell_up_ticks": TYPE_INT,         # 龟缩：缩壳免疫窗长（>0）
	"arc_shot": TYPE_BOOL,              # 抛物弹道开关（荆棘炮台/种子投手）
	"puddle_interval_ticks": TYPE_INT,  # 水洼：拖尾间隔（>0）
	"puddle_radius": TYPE_FLOAT,        # 水洼：半径 px（>0）
	"puddle_life_seconds": TYPE_FLOAT,  # 水洼：寿命 s（>0，帧基过期）
	"puddle_speed_mult": TYPE_FLOAT,    # 水洼：敌提速倍率（≥1）
	"puddle_player_slow_pct": TYPE_FLOAT,  # 水洼：玩家减速 (0,1]
	"impact_spawn_row": TYPE_STRING,    # 落地生怪：幼体行 id（须存在于同表）
	"impact_spawn_chance": TYPE_FLOAT,  # 落地生怪：掷签概率 (0,1]
	"impact_spawn_cap": TYPE_INT,       # 落地生怪：per-投手活苗上限（≥1，可清红线）
	"pull_range_px": TYPE_FLOAT,        # 拉拽：触发半径（>0）
	"pull_px": TYPE_FLOAT,              # 拉拽：位移 px（>0）
	"pull_cd_ticks": TYPE_INT,          # 拉拽：冷却（>0）
	"pull_windup_ticks": TYPE_INT,      # 拉拽：预警窗（>0）
	"claw_dmg": TYPE_INT,               # 钳击：横扫伤害（>0）
	"claw_range_px": TYPE_FLOAT,        # 钳击：半径（>0）
	"claw_arc_deg": TYPE_FLOAT,         # 钳击：扇区角 (0,360]
	"claw_cd_ticks": TYPE_INT,          # 钳击：冷却（>0）
	"claw_windup_ticks": TYPE_INT,      # 钳击：预警窗（≥21 = §7.5 0.35s）
	"steal_coins": TYPE_INT,            # 偷币：窃取额（>0；死亡全额返还）
	"mimic_weapon": TYPE_BOOL,          # 模仿武器开关（深窟回响者）
	"bullet_element": TYPE_STRING,      # 电弧链：弹元素名（fire/ice/shock/poison）
	"bite_stages": TYPE_INT,            # 两段咬：段数（≥2）
	"bite_gap_ticks": TYPE_INT,         # 两段咬：段间短蓄（>0）
	"bite_element": TYPE_STRING,        # 两段咬：扑咬元素名
	"firerain_count": TYPE_INT,         # 火雨区：区数（>0）
	"firerain_radius": TYPE_FLOAT,      # 火雨区：半径（>0）
	"firerain_dmg": TYPE_INT,           # 火雨区：单区伤害（>0）
	"firerain_delay_ticks": TYPE_INT,   # 火雨区：预警延迟（≥21 = §7.5 0.35s）
	"firerain_spread_px": TYPE_FLOAT,   # 火雨区：散布半径（≥0）
}

## 元素名域（镜像 Elements.NAMES 值；none 无行为意义不接受）。
const ELEMENT_NAMES: Array[String] = ["fire", "ice", "shock", "poison"]


## 单行校验（raw JSON 行；返回错误串数组，空=通过）。
static func validate_row(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in BASE_REQUIRED:
		if not row.has(key):
			errors.append("missing key: %s" % key)
		elif not _type_ok(row[key], BASE_REQUIRED[key]):
			errors.append("type mismatch: %s" % key)
	for key: String in row:
		if not SIGNATURE_KEYS.has(key):
			continue
		var want: int = SIGNATURE_KEYS[key]
		var v: Variant = row[key]
		if not _type_ok(v, want):
			errors.append("type mismatch: %s want %s" % [key, _type_name(want)])
			continue
		errors.append_array(_domain_check(key, v))
	return errors

## 整表校验（含跨行引用：impact_spawn_row 必须指向表内既有行 id）。
static func validate_table(table: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for id: String in table:
		var row: Dictionary = table[id]
		for err in validate_row(row):
			errors.append("%s: %s" % [id, err])
		if row.has("impact_spawn_row") and not table.has(String(row["impact_spawn_row"])):
			errors.append("%s: impact_spawn_row not in table: %s"
				% [id, str(row["impact_spawn_row"])])
	return errors


static func _type_ok(v: Variant, want: int) -> bool:
	match want:
		TYPE_INT:
			# Godot 4.7.2 JSON 数字全解析为 float：整值 float 视为合法 int 契约
			return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and float(int(v)) == float(v))
		TYPE_FLOAT:
			return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
		TYPE_BOOL:
			return typeof(v) == TYPE_BOOL
		TYPE_STRING:
			return typeof(v) == TYPE_STRING
		_:
			return false

static func _type_name(t: int) -> String:
	match t:
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_STRING: return "string"
	return "?"

## 语义域分组（int >0 / float >0 / 域内枚举 / §7.5 预警下限 21t）。
const DOMAIN_POSITIVE_INT: Array[String] = [
	"shell_up_ticks", "shell_walk_ticks", "puddle_interval_ticks", "impact_spawn_cap",
	"pull_cd_ticks", "pull_windup_ticks", "claw_dmg", "claw_cd_ticks",
	"steal_coins", "bite_gap_ticks", "firerain_count", "firerain_dmg",
]
const DOMAIN_POSITIVE_FLOAT: Array[String] = [
	"puddle_radius", "pull_range_px", "pull_px", "claw_range_px",
	"firerain_radius",
]
const DOMAIN_ELEMENT: Array[String] = ["bullet_element", "bite_element"]
const TELEGRAPH_MIN_TICKS := 21      # GDD §7.5：任何弹幕/区生成前预警 ≥0.35s


static func _domain_check(key: String, v: Variant) -> Array[String]:
	var errors: Array[String] = []
	if DOMAIN_POSITIVE_INT.has(key):
		if int(v) <= 0:
			errors.append("out of domain: %s must be > 0" % key)
		return errors
	if key == "bite_stages":
		if int(v) < 2:
			errors.append("out of domain: bite_stages must be >= 2")
		return errors
	if key == "claw_windup_ticks":
		if int(v) < TELEGRAPH_MIN_TICKS:
			errors.append("out of domain: claw_windup_ticks must be >= %d (GDD §7.5)"
				% TELEGRAPH_MIN_TICKS)
		return errors
	if key == "firerain_delay_ticks":
		if int(v) < TELEGRAPH_MIN_TICKS:
			errors.append("out of domain: firerain_delay_ticks must be >= %d (GDD §7.5)"
				% TELEGRAPH_MIN_TICKS)
		return errors
	if DOMAIN_POSITIVE_FLOAT.has(key) or key == "puddle_life_seconds":
		if float(v) <= 0.0:
			errors.append("out of domain: %s must be > 0" % key)
		return errors
	if key == "firerain_spread_px":
		if float(v) < 0.0:
			errors.append("out of domain: firerain_spread_px must be >= 0")
		return errors
	if key == "claw_arc_deg":
		if float(v) <= 0.0 or float(v) > 360.0:
			errors.append("out of domain: claw_arc_deg must be in (0,360]")
		return errors
	if key == "puddle_speed_mult":
		if float(v) < 1.0:
			errors.append("out of domain: puddle_speed_mult must be >= 1.0")
		return errors
	if key == "puddle_player_slow_pct" or key == "impact_spawn_chance":
		if float(v) <= 0.0 or float(v) >= 1.0:
			errors.append("out of domain: %s must be in (0,1)" % key)
		return errors
	if DOMAIN_ELEMENT.has(key) and not ELEMENT_NAMES.has(String(v)):
		errors.append("out of domain: %s must be in %s" % [key, str(ELEMENT_NAMES)])
	return errors
