class_name HeroApplier
extends RefCounted
## 角色装配（m1-t11）：把 GameDB.heroes 行落到 Player —— 面板字段、初始武器、
## 技能脚本换装 + setup 数据注入、被动开关、meta 接缝。纯静态工具，无实例状态。
##
## 接缝披露：暴击基础值经 player meta 暂存（"crit_base" = hero.crit_chance），
## 完整英雄行存 "hero"；房间层（T10 战斗接线 / T23 局流程）负责读出并注入
## CombatSystem.crit_chance —— 本任务只落数据，不接线。

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
	# 初始武器按行内顺序装备：第一把占槽 0，其余填下一空槽（WeaponRig.equip 契约）
	if player.weapon_rig != null:
		for wid: Variant in hero["start_weapons"]:
			player.weapon_rig.equip(String(wid))
	# meta 接缝：房间层读 meta 注入 CombatSystem.crit_chance（T10/T23 接线，本任务只落数据）
	player.set_meta("hero", hero)
	player.set_meta("crit_base", float(hero["crit_chance"]))
	_mount_skill(hero, player)

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
	# T2 setup 契约键：id / cooldown_ticks / energy_cost / upgraded；另带 has_defiance 供技能侧读取
	skill.setup(player, {
		"id": path.get_file().get_basename(),
		"cooldown_ticks": int(hero["skill_cd"]),
		"energy_cost": int(hero["skill_energy"]),
		"upgraded": bool(hero["upgraded"]),
		"has_defiance": bool(hero["has_defiance"]),
	})
