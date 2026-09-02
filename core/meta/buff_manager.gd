class_name BuffManager
extends RefCounted
## 局内增益管理（m1-t9 + m2-t12，每局实例）：持有已取列表，按稀有度权重三选一抽取，
## 并把已取效果聚合落地到 Player / WeaponRig 的公开字段与 buff_* meta。
## 数据源：GameDB.buffs（buffs.json，附录 C 全表 36 条 = 白15 + 绿11 + 蓝10）。
## m2-t12 新键无既有公开字段的，经 set_meta("buff_<key>") 落地（绝对值幂等重写）。
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare"]
const RARITY_WEIGHTS := {"common": 55, "uncommon": 30, "rare": 15}
# 唯一增益（附录 C 标注「唯一」）：pick 后永久移出可抽池
const UNIQUE_IDS: Array[String] = ["extra_projectiles", "crit_detonate", "phoenix"]
# 效果键白名单与中性默认值（与 GameDB.BUFF_*_KEYS 一致；float 用 0.0，int 用 0）。
# FLAG_KEYS 为 0/1 语义 flag（免疫系/视界系/不死鸟）：聚合取 max——
# 重复拾取（anti_* 为白卡可重复）不叠加，结果恒 0/1（评审 Major 修复 ②）。
const EFFECT_DEFAULTS := {
	"move_speed_pct": 0.0, "crit_pct": 0.0, "crit_dmg_pct": 0.0,
	"atk_speed_pct": 0.0, "bullet_speed_pct": 0.0, "status_rate_pct": 0.0,
	"roll_cd_pct": 0.0, "crit_detonate_pct": 0.0,
	"element_proc_chance": 0.0,
	"hp_max": 0, "shield_max": 0, "energy_max": 0,
	"shield_delay_reduction_ticks": 0, "element_enchant": 0, "extra_projectiles": 0,
	# m2-t12 新增键（附录 C 全量键位对齐；符号约定：负值 = 减少，同 roll_cd_pct）
	"dmg_vs_statused_pct": 0.0, "resonance_radius_pct": 0.0,
	"resonance_duration_ticks": 0,
	"vengeance_pct": 0.0, "vengeance_ticks": 0,
	"anti_fire": 0, "anti_ice": 0, "anti_poison": 0,
	"hurt_iframe_bonus_ticks": 0, "bullet_dmg_taken_pct": 0.0,
	"thorns_contact_dmg": 0, "roll_distance_pct": 0.0, "phoenix_flag": 0,
	"wealth_pct": 0.0, "drink_effect_pct": 0.0, "pickup_radius_pct": 0.0,
	"kill_energy_chance": 0.0, "kill_energy_amount": 0,
	"heart_sense_pct": 0.0,
	"passive_energy_interval_ticks": 0, "passive_energy_amount": 0,
	"haggle_pct": 0.0,
	"element_vision": 0, "telegraph_bonus_ticks": 0, "resonance_vision": 0,
}
# 0/1 flag 键（与 GameDB.BUFF_FLAG_KEYS 镜像）：聚合取 max，恒 0/1
const FLAG_KEYS: Array[String] = [
	"anti_fire", "anti_ice", "anti_poison", "phoenix_flag",
	"element_vision", "resonance_vision",
]
# 落地到 player meta 的键（身体/防御/资源/功能侧）——消费端 m4-c3 起全量接线：
# anti_fire→HazardMagma/magma_tyrant；anti_ice/anti_poison→player.take_hit；
# hurt_iframe_bonus/bullet_dmg_taken/thorns/roll_distance/phoenix/kill_energy/
# passive_energy→player；wealth/pickup_radius/haggle→pickup/shop_logic；
# drink_effect→drink_machine；heart_sense→room_combat 掉落 roll；
# element_vision/telegraph_bonus_ticks/resonance_vision→enemy_base 视界展示层。
const PLAYER_META_KEYS: Array[String] = [
	"anti_fire", "anti_ice", "anti_poison",
	"hurt_iframe_bonus_ticks", "bullet_dmg_taken_pct", "thorns_contact_dmg",
	"roll_distance_pct", "phoenix_flag",
	"wealth_pct", "drink_effect_pct", "pickup_radius_pct",
	"kill_energy_chance", "kill_energy_amount", "heart_sense_pct",
	"passive_energy_interval_ticks", "passive_energy_amount",
	"haggle_pct", "element_vision", "telegraph_bonus_ticks", "resonance_vision",
]
# 落地到 rig meta 的键（输出放大侧；M1 WeaponRig 已是输出聚合点 rate_mult/crit_detonate_pct）
# ——消费端 m4-c3 起接线：dmg_vs_statused_pct/vengeance_pct→CombatSystem 全局乘区；
# resonance_radius_pct/resonance_duration_ticks→CombatSystem 燎原毒火云（Resonance 读数）；
# vengeance_ticks→Player 受击开窗。
const RIG_META_KEYS: Array[String] = [
	"dmg_vs_statused_pct", "resonance_radius_pct", "resonance_duration_ticks",
	"vengeance_pct", "vengeance_ticks",
]

var picked: Array[String] = []
var _p_base := {}    # 首次 apply_to_player 时记录数值上限/移速基线（幂等重算用）
var _p_last := {}    # 上次由本 manager 写入的增量；饮料等外部变化在重算时保留
var _rig_base := {}  # 首次 apply_to_rig 时记录的 rig 基线（幂等重算用）

## 可抽池：全部 buff id 减去「已被 pick 的唯一项」；普通增益可重复出现（叠加）。
func available_pool() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameDB.buffs:
		if UNIQUE_IDS.has(id) and picked.has(id):
			continue
		out.append(id)
	out.sort()   # 确定性顺序，保证同 seed 结果可复现
	return out

## 三选一：从可抽池按稀有度权重（白55/绿30/蓝15）先抽稀有度、再同稀有度等概率取一，
## 单次三选内不重复；池不足 3 时返回剩余全部，池空返回 []。
func roll_three(rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	for i in 3:
		var candidates: Array[String] = []
		for id in available_pool():
			if not out.has(id):
				candidates.append(id)
		if candidates.is_empty():
			break
		out.append(_draw_one(rng, candidates))
	return out

## 单抽：先按权重抽稀有度（仅统计候选中存在的稀有度），再在该稀有度内等概率取一。
func _draw_one(rng: RandomNumberGenerator, candidates: Array[String]) -> String:
	var by_rarity := {}
	var weights := {}
	var total := 0
	for r in RARITY_ORDER:
		var bucket: Array[String] = []
		for id in candidates:
			if GameDB.buffs[id]["rarity"] == r:
				bucket.append(id)
		if bucket.is_empty():
			continue
		by_rarity[r] = bucket
		weights[r] = int(RARITY_WEIGHTS[r])
		total += int(RARITY_WEIGHTS[r])
	var roll := rng.randi_range(1, total)
	var acc := 0
	var chosen := RARITY_ORDER[0]
	for r in RARITY_ORDER:
		if not weights.has(r):
			continue
		acc += int(weights[r])
		if roll <= acc:
			chosen = r
			break
	var bucket: Array = by_rarity[chosen]
	return bucket[rng.randi_range(0, bucket.size() - 1)]

## 选中：append 到已取列表（普通项可重复＝可叠加）；未知 id 与唯一项二次 pick 拒绝。
## 唯一项的正常防重复由 roll_three 的可抽池移除保证，此处为第二道 fail-closed 防线。
func pick(id: String) -> void:
	if GameDB.get_buff(id).is_empty():
		push_error("BuffManager: unknown buff %s" % id)
		return
	if UNIQUE_IDS.has(id) and picked.has(id):
		push_error("BuffManager: unique buff %s already picked" % id)
		return
	picked.append(id)

## 聚合已取效果：可加键求和；element_enchant 取最后选中者（同类附魔后取覆盖前取）；
## FLAG_KEYS 取 max（0/1 语义，重复拾取不叠加，评审 Major 修复 ②）。
func aggregate() -> Dictionary:
	var agg := {}
	for k: String in EFFECT_DEFAULTS:
		agg[k] = EFFECT_DEFAULTS[k]
	for id in picked:
		var eff: Dictionary = GameDB.get_buff(id).get("effects", {})
		for k: String in eff:
			if not agg.has(k):
				continue                     # 白名单外键忽略（fail-closed）
			if k == "element_enchant":
				agg[k] = int(eff[k])         # 后取覆盖前取
			elif k == "element_proc_chance":
				agg[k] = float(eff[k])       # 与最后一条附魔成对覆盖
			elif FLAG_KEYS.has(k):
				agg[k] = maxi(int(agg[k]), int(eff[k]))   # flag 恒 0/1
			elif typeof(EFFECT_DEFAULTS[k]) == TYPE_FLOAT:
				agg[k] = float(agg[k]) + float(eff[k])
			else:
				agg[k] = int(agg[k]) + int(eff[k])
	return agg

## 落地到玩家（幂等：首次记录基线，之后按已取列表重算）。
## 覆盖 hp_max / shield_max / energy_max / move_speed；其余键经 aggregate() 暴露，
## 由后续任务接线（crit/状态/翻滚/盾延时暂无公开可写字段）。
## m2-t12：新增键以绝对值写入 buff_* meta（幂等重写，不叠加）。
## m4-c3：player meta 消费端全量接线（各键读点见 PLAYER_META_KEYS 注）。
func apply_to_player(p: Player) -> void:
	if _p_base.is_empty():
		_p_base = {"hp_max": p.hp_max, "shield_max": p.shield_max,
			"energy_max": p.energy_max, "move_speed": p.move_speed}
		_p_last = {"hp_max": 0, "shield_max": 0, "energy_max": 0, "move_speed_pct": 0.0}
	var agg := aggregate()
	# 移除上次本 manager 的贡献，保留期间饮料/事件写入，再按当前 picked 重加。
	p.hp_max = p.hp_max - int(_p_last["hp_max"]) + int(agg["hp_max"])
	p.shield_max = p.shield_max - int(_p_last["shield_max"]) + int(agg["shield_max"])
	p.energy_max = p.energy_max - int(_p_last["energy_max"]) + int(agg["energy_max"])
	var old_mult := 1.0 + float(_p_last["move_speed_pct"])
	p.move_speed = (p.move_speed / old_mult) * (1.0 + float(agg["move_speed_pct"]))
	_p_last = {"hp_max": int(agg["hp_max"]), "shield_max": int(agg["shield_max"]),
		"energy_max": int(agg["energy_max"]), "move_speed_pct": float(agg["move_speed_pct"])}
	p.crit_bonus = float(agg["crit_pct"]) + float(p.get_meta("drink_crit_bonus", 0.0))
	p.crit_damage_bonus = float(agg["crit_dmg_pct"])
	p.status_rate_bonus = float(agg["status_rate_pct"]) \
		+ float(p.get_meta("drink_status_rate_bonus", 0.0))
	p.shield_delay_reduction_ticks = int(agg["shield_delay_reduction_ticks"]) \
		+ int(p.get_meta("drink_shield_delay_reduction_ticks", 0))
	p.roll_cd_pct = float(agg["roll_cd_pct"])
	p.roll_cd_reduction_ticks = int(p.get_meta("drink_roll_cd_reduction_ticks", 0))
	for k: String in PLAYER_META_KEYS:
		p.set_meta("buff_" + k, agg[k])

## 落地到武器架（幂等，同 apply_to_player 基线策略）。
## 写 5 个共享字段：rate_mult / bullet_speed_mult / enchant_element /
## bonus_projectiles / crit_detonate_pct（字段为本任务在 weapon_rig.gd 声明）。
## m2-t12：输出放大侧新键（猎杀者/共鸣增幅/复仇者）以绝对值写入 rig buff_* meta。
## m4-c3：rig meta 消费端接线（CombatSystem hunter/vengeance 乘区 + resonance_amp
## 燎原毒火云读数；avenger 开窗读点在 Player.take_hit_ctx）。
func apply_to_rig(rig: WeaponRig) -> void:
	if _rig_base.is_empty():
		_rig_base = {"enchant_element": rig.enchant_element,
			"enchant_proc_chance": rig.enchant_proc_chance,
			"bonus_projectiles": rig.bonus_projectiles,
			"crit_detonate_pct": rig.crit_detonate_pct,
			"rate_mult": rig.rate_mult, "bullet_speed_mult": rig.bullet_speed_mult}
	var agg := aggregate()
	rig.rate_mult = float(_rig_base["rate_mult"]) * (1.0 + float(agg["atk_speed_pct"]))
	rig.bullet_speed_mult = float(_rig_base["bullet_speed_mult"]) \
		* (1.0 + float(agg["bullet_speed_pct"]))
	rig.bonus_projectiles = int(_rig_base["bonus_projectiles"]) + int(agg["extra_projectiles"])
	rig.crit_detonate_pct = float(_rig_base["crit_detonate_pct"]) + float(agg["crit_detonate_pct"])
	if int(agg["element_enchant"]) != Elements.Id.NONE:
		rig.enchant_element = int(agg["element_enchant"])
		rig.enchant_proc_chance = float(agg["element_proc_chance"])
	else:
		rig.enchant_element = int(_rig_base["enchant_element"])
		rig.enchant_proc_chance = float(_rig_base["enchant_proc_chance"])
	for k: String in RIG_META_KEYS:
		rig.set_meta("buff_" + k, agg[k])
