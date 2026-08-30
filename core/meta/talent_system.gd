class_name TalentSystem
extends RefCounted
## 天赋树系统（m2-t15）：永久 meta 成长的购买与落地。数据源 GameDB.talents
## （data/talents.json，T2 表 24 节点三系各 8）；购买列表持久化走 SaveSystem
## （purchased_talents，m2-t15 最小新增字段，T31 migration v2 formalize）。
##
## 三入口（计划卡契约）：
## - available()：前置全购 + 本体未购的可买集；
## - buy(id)：未知/重复/前置未满足/蓝晶不足 → false；成功 → SaveSystem 扣蓝晶
##   （add_gems(-cost)）+ purchased 列表落盘；
## - apply_to_player(player)：购得节点效果全量落地，效果键 ⊆ 附录 I 白名单
##   （GameDB.TALENT_PCT_KEYS / TALENT_INT_KEYS）。
##
## 落地口径（BuffManager.apply_to_player 模式参照）：
## - 复用键 → Player / WeaponRig 既有公开字段，own-delta 幂等重算（剥上次本系统
##   贡献 → 保留期间英雄装配/饮料/BuffManager 写入 → 按当前已购重加）；
## - talent_ 前缀新键 → player meta "talent_effects" 全量聚合 + TalentSystem.effects_of
##   只读出口。附录 I.4 声明的消费方接线（WeaponRig 伤害乘区 / Player.apply_iframes
##   乘区 / Pickup 磁吸与金币乘区 / T31 蓝晶结算）落在各自文件所有权卡，本卡交付
##   聚合值与读取接口（见类尾「消费方接线表」）。
##
## 与 BuffManager 的组合披露：crit_bonus / crit_damage_bonus / status_rate_bonus /
## shield_delay_reduction_ticks / roll_cd_pct / enchant_proc_chance 六键 BuffManager
## 为基线绝对写——其重 apply 会覆盖本系统贡献，重排后本系统 own-delta 会把幻影
## 上次贡献减掉。收口卡接线时应保证 apply 顺序（talents 先于 buffs、或 buff 重算
## 后 talents 重 apply 一次），或 T12 buff_manager 并入 talent_effects 读取。

## 持久化后端（autoload "SaveSystem" 或测试注入实例）。duck-typed：gems() /
## add_gems() / purchased_talents() / record_talent_purchase() 四方法契约。
var save_system: Node = null
## 已购节点 id 列表（构造时从 SaveSystem 读入；buy() 成功后同步）。
var purchased: Array[String] = []

var _p_last := {}    # 上次 apply_to_player 写入的自身贡献（own-delta 重算用）
var _rig_last := {}  # 上次落到 weapon_rig 的自身贡献

func _init(p_save_system: Node = null) -> void:
	save_system = p_save_system if p_save_system != null else _default_save()
	if save_system != null and save_system.has_method("purchased_talents"):
		purchased = (save_system.purchased_talents() as Array[String]).duplicate()

## 生产默认后端：/root/SaveSystem autoload（缺席时 null，buy 会 fail-loud）。
static func _default_save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("SaveSystem")
	return null

# ---- 查询 ----

## 可买集：全部节点中「前置全已购 + 本体未购」者，按 id 排序（确定性）。
func available() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameDB.talents:
		if is_available(id):
			out.append(id)
	out.sort()
	return out

func is_available(id: String) -> bool:
	if purchased.has(id):
		return false
	var row := GameDB.get_talent(id)
	if row.is_empty():
		return false
	for req: Variant in row["requires"]:
		if not purchased.has(String(req)):
			return false
	return true

func is_purchased(id: String) -> bool:
	return purchased.has(id)

# ---- 购买 ----

## 购买：蓝晶校验 → SaveSystem 扣除 → purchased 列表持久化。
## 未知 id / 重复购买 / 前置未满足 / 蓝晶不足 / 后端缺席 → false（前两者中未知 id
## 与后端缺席为程序错误，push_error fail-loud；其余为正常业务拒绝，静默 false）。
func buy(id: String) -> bool:
	var row := GameDB.get_talent(id)
	if row.is_empty():
		push_error("TalentSystem: unknown talent %s" % id)
		return false
	if purchased.has(id):
		return false                     # 重复购买拒绝（幂等）
	for req: Variant in row["requires"]:
		if not purchased.has(String(req)):
			return false                 # 前置未满足
	if save_system == null or not save_system.has_method("add_gems"):
		push_error("TalentSystem: no SaveSystem backend for buy(%s)" % id)
		return false
	var cost := int(row["cost"])
	if save_system.gems() < cost:
		return false                     # 蓝晶不足（经济数值以附录 I 为准）
	save_system.add_gems(-cost)
	save_system.record_talent_purchase(id)
	purchased.append(id)
	return true

# ---- 聚合 ----

## 中性聚合（全键默认值）：float 键 0.0 / int 键 0，键集 = 附录 I 白名单两表并集。
static func neutral_effects() -> Dictionary:
	var agg := {}
	for k: String in GameDB.TALENT_PCT_KEYS:
		agg[k] = 0.0
	for k: String in GameDB.TALENT_INT_KEYS:
		agg[k] = 0
	return agg

## 已购节点效果聚合：全部可加键求和（roll_cd_pct 负值=缩短，同 buffs.json 约定）；
## 白名单外键忽略（fail-closed，数据面已由 T2 校验兜底）。
func aggregate() -> Dictionary:
	var agg := neutral_effects()
	for id in purchased:
		var eff: Dictionary = GameDB.get_talent(id).get("effects", {})
		for k: String in eff:
			if not agg.has(k):
				continue
			if GameDB.TALENT_INT_KEYS.has(k):
				agg[k] = int(agg[k]) + int(eff[k])
			else:
				agg[k] = float(agg[k]) + float(eff[k])
	return agg

# ---- 落地 ----

## 购得效果全量落地到玩家（幂等：own-delta 重算，重复调用不叠加）。
## Player 侧 9 键 + rig 侧 3 键直写公开字段；talent_ 前缀 5 键经 meta 暴露
## （effects_of 读取，消费方接线表见类头）。rig 为空时 rig 键只进 meta——
## 接线卡应在 rig 就绪后调用（player._ready 解析 tscn 子节点后）。
func apply_to_player(p: Player) -> void:
	var agg := aggregate()
	if _p_last.is_empty():
		_p_last = {"hp_max": 0, "shield_max": 0, "energy_max": 0, "move_speed_pct": 0.0,
			"crit_pct": 0.0, "crit_dmg_pct": 0.0, "status_rate_pct": 0.0,
			"shield_delay_reduction_ticks": 0, "roll_cd_pct": 0.0}
	# 可加键：剥上次自身贡献，保留期间外部写入，再按当前已购重加。
	p.hp_max = p.hp_max - int(_p_last["hp_max"]) + int(agg["hp_max"])
	p.shield_max = p.shield_max - int(_p_last["shield_max"]) + int(agg["shield_max"])
	p.energy_max = p.energy_max - int(_p_last["energy_max"]) + int(agg["energy_max"])
	p.crit_bonus = p.crit_bonus - float(_p_last["crit_pct"]) + float(agg["crit_pct"])
	p.crit_damage_bonus = p.crit_damage_bonus - float(_p_last["crit_dmg_pct"]) \
		+ float(agg["crit_dmg_pct"])
	p.status_rate_bonus = p.status_rate_bonus - float(_p_last["status_rate_pct"]) \
		+ float(agg["status_rate_pct"])
	p.shield_delay_reduction_ticks = p.shield_delay_reduction_ticks \
		- int(_p_last["shield_delay_reduction_ticks"]) \
		+ int(agg["shield_delay_reduction_ticks"])
	p.roll_cd_pct = p.roll_cd_pct - float(_p_last["roll_cd_pct"]) + float(agg["roll_cd_pct"])
	# 移速：乘法 own-delta（同 BuffManager 口径，与加法键一样可逆）。
	var old_move_mult := 1.0 + float(_p_last["move_speed_pct"])
	p.move_speed = (p.move_speed / old_move_mult) * (1.0 + float(agg["move_speed_pct"]))
	_p_last = {"hp_max": int(agg["hp_max"]), "shield_max": int(agg["shield_max"]),
		"energy_max": int(agg["energy_max"]), "move_speed_pct": float(agg["move_speed_pct"]),
		"crit_pct": float(agg["crit_pct"]), "crit_dmg_pct": float(agg["crit_dmg_pct"]),
		"status_rate_pct": float(agg["status_rate_pct"]),
		"shield_delay_reduction_ticks": int(agg["shield_delay_reduction_ticks"]),
		"roll_cd_pct": float(agg["roll_cd_pct"])}
	# talent_ 前缀键：meta 全量聚合（未 apply 时 effects_of 回落中性默认）。
	p.set_meta("talent_effects", agg.duplicate())
	if p.weapon_rig != null:
		_apply_to_rig(p.weapon_rig, agg)

## rig 侧三复用键（攻速/弹速=乘法 own-delta，附魔概率=加法 own-delta）。
func _apply_to_rig(rig: WeaponRig, agg: Dictionary) -> void:
	if _rig_last.is_empty():
		_rig_last = {"atk_speed_pct": 0.0, "bullet_speed_pct": 0.0,
			"element_proc_chance": 0.0}
	rig.rate_mult = rig.rate_mult / (1.0 + float(_rig_last["atk_speed_pct"])) \
		* (1.0 + float(agg["atk_speed_pct"]))
	rig.bullet_speed_mult = rig.bullet_speed_mult / (1.0 + float(_rig_last["bullet_speed_pct"])) \
		* (1.0 + float(agg["bullet_speed_pct"]))
	rig.enchant_proc_chance = rig.enchant_proc_chance \
		- float(_rig_last["element_proc_chance"]) + float(agg["element_proc_chance"])
	_rig_last = {"atk_speed_pct": float(agg["atk_speed_pct"]),
		"bullet_speed_pct": float(agg["bullet_speed_pct"]),
		"element_proc_chance": float(agg["element_proc_chance"])}

## 消费方只读出口：读 apply_to_player 落地的 talent_effects meta；
## 未 apply / 未购任何节点 → 中性默认（float 0.0 / int 0）。
static func effects_of(p: Player) -> Dictionary:
	var saved: Variant = p.get_meta("talent_effects", null)
	if typeof(saved) == TYPE_DICTIONARY:
		return saved
	return neutral_effects()

# ---- 消费方接线表（附录 I.4；本卡交付聚合值 + effects_of 读取，接线落在各自所有权卡）----
# talent_dmg_pct          → WeaponRig 伤害乘区（同 rate_mult 模式，_fire_slot/melee 落弹时乘）
# talent_hurt_iframe_pct  → Player.take_hit_ctx 受击无敌帧（HURT_IFRAME_TICKS × (1+v)）
# talent_gem_gain_pct     → M2-T31 蓝晶结算（RunState settle → SaveSystem.add_gems 乘区）
# talent_coin_gain_pct    → Pickup coin on_collect 金币计数乘区（T31 结算复核）
# talent_pickup_radius_pct→ Pickup 磁吸范围（MAGNET_RANGE_PX × (1+v)）
