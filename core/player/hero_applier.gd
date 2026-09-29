class_name HeroApplier
extends RefCounted
## 角色装配（m1-t11）：把 GameDB.heroes 行落到 Player —— 面板字段、初始武器、
## 技能脚本换装 + setup 数据注入、被动开关、meta 接缝。纯静态工具，无实例状态。
##
## 接缝披露：暴击基础值经 player meta 暂存（"crit_base" = hero.crit_chance），
## 完整英雄行存 "hero"；房间层（T10 战斗接线 / T23 局流程）负责读出并注入
## CombatSystem.crit_chance —— 本任务只落数据，不接线。

## m5-h 皮肤表（每英雄 1 套换色外观；纯 modulate 着色，零数值/零碰撞面）。
## 简化披露：运行期 tint 而非 palette swap（spritegen 参数表扩皮肤配置属 T2 美术
## 管线，Appendix L 会话持有）——色调经 32 色 DB16 调色板取样，视觉差异可辨。
const SKINS := {
	"vanguard": {"id": "nightfrost", "name": "夜霜", "tint": Color(0.72, 0.82, 1.0)},
	"ranger": {"id": "crimson", "name": "赤羽", "tint": Color(1.0, 0.72, 0.66)},
	"mage": {"id": "azure", "name": "苍蓝", "tint": Color(0.66, 0.78, 1.0)},
	"assassin": {"id": "inkjade", "name": "墨玉", "tint": Color(0.72, 0.9, 0.8)},
	"engineer": {"id": "verdigris", "name": "铜绿", "tint": Color(0.72, 0.95, 0.78)},
	"guardian": {"id": "gild", "name": "金穗", "tint": Color(1.0, 0.9, 0.66)},
}

static func apply(hero: Dictionary, player: Player) -> void:
	player.hp_max = int(hero["hp"])
	player.shield_max = int(hero["shield"])
	player.energy_max = int(hero["energy"])
	player.move_speed = float(hero["speed"])
	# 装配即开局满值：当前值对齐新上限（避免跨角色残留旧默认，如 8hp 残留到 6hp 角色）
	player.hp = player.hp_max
	player.shield = player.shield_max
	player.energy = player.energy_max
	player.has_defiance = bool(hero["has_defiance"])
	# m4-c2：被动 id 注入（消费门控读点：combat_system 回响乘区 / run_root 层入口
	# blessing+spare_parts / player.on_melee_kill 掠影）。
	player.passive_id = String(hero.get("passive_id", ""))
	# 装配晚于 combat 注入的次序（training_room 装配序）兜底回填——常规次序由
	# player.combat setter 在房间注入时回写（player.gd m4-c2 注）。
	if player.combat != null:
		player.combat.hero_passive_id = player.passive_id
	# 初始武器按行内顺序装备：第一把占槽 0，其余填下一空槽（WeaponRig.equip 契约）
	if player.weapon_rig != null:
		for wid: Variant in hero["start_weapons"]:
			player.weapon_rig.equip(String(wid))
		_zero_starter_energy_cost(player.weapon_rig, hero["start_weapons"])
	# meta 接缝：房间层读 meta 注入 CombatSystem.crit_chance（T10/T23 接线，本任务只落数据）
	player.set_meta("hero", hero)
	player.set_meta("crit_base", float(hero["crit_chance"]))
	# m5-h 皮肤着色：存档选择 → SKINS tint → 玩家体 Sprite（默认/未知 id 恒白色）。
	var hid := String(hero.get("id", ""))
	var spr := player.get_node_or_null("Sprite") as Sprite2D
	if spr != null:
		var skin: Dictionary = SKINS.get(hid, {})
		var tint := Color.WHITE
		if not skin.is_empty() and SaveSystem.skin_of(hid) == String(skin["id"]):
			tint = skin["tint"]
		spr.modulate = tint
	_mount_skill(hero, player)

## M5-S1 GDD §7.2「初始武器 0 耗蓝」实例级保证：蓝量无被动回复，初始武器若按表值
## 耗蓝会在数秒内打空、远程禁射（附录 L 的 14 名新角色绑定了绿装初始武器，表值
## 1~4 蓝/发——圣职·烛 6s、狂战士·烈 10s 空蓝，bot 冒烟 0 房即死实证）。equip 已
## deep-copy 成武器实例，只改实例不改 GameDB 共享行——同名武器作为掉落/商店获取时
## 仍按表值耗蓝（稀有度权衡不变）。现役 6 人中 5 人初始武器表值本就 0，守护者·萄的
## 星辉杖（GDD「弱化版」）一并落回规格。
## 共享入口：HeroApplier 初始装配 + run_root 重开恢复路径（同一口径单一事实源）。
## 前置：槽内须为 equip/duplicate 产出的武器实例（绝不能是 GameDB 共享行）。
## 已知口径：按 id 识别——局内另拾同名初始武器同样 0 耗蓝（初始武器均为白/绿低档，
## 可接受）。
static func _zero_starter_energy_cost(rig: WeaponRig, start_weapons: Array) -> void:
	for i in rig.slots.size():
		var w: Dictionary = rig.slots[i]
		if not w.is_empty() and start_weapons.has(String(w.get("id", ""))):
			w["energy_cost"] = 0
			w["starter"] = true

## 技能换装：player.tscn 恒挂的 Skill 节点（skill_base.gd 占位，T2）按英雄行换成具体技能脚本。
## set_script 为干净换装：技能均为无导出属性/无编辑器状态的纯 Node 脚本（enemy-style
## caveats 不适用）；子类 _init 里的默认 CD 不依赖 set_script 重跑 —— schema 必填键
## skill_cd/skill_energy 经 setup data 覆写，数值以数据行为准。
static func _mount_skill(hero: Dictionary, player: Player) -> void:
	var skill := player.get_node_or_null("Skill")
	if skill == null:
		push_error("HeroApplier: player has no Skill node")
		return
	var path := String(hero["skill_script"])
	var script: Script = load(path)
	if script == null:
		push_error("HeroApplier: cannot load skill script %s" % path)
		return
	skill.set_script(script)
	# T2 setup 契约键：id / cooldown_ticks / energy_cost / upgraded；另带 has_defiance 供技能侧读取。
	# m5-d：upgraded 运行态覆盖——heroes 行字段为纸面锚点（恒 false），实际以存档
	# skill_upgrades 名录为准（1500 蓝晶购买，Appendix L 裁定：购买流关闭、强化保留）。
	skill.setup(player, {
		"id": path.get_file().get_basename(),
		"cooldown_ticks": int(hero["skill_cd"]),
		"energy_cost": int(hero["skill_energy"]),
		"upgraded": bool(hero["upgraded"]) or SaveSystem.skill_upgraded(String(hero["id"])),
		"has_defiance": bool(hero["has_defiance"]),
	})
