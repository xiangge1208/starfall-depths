class_name EngineerTurret
extends SkillBase
## 工程师·铆 主动技「自动炮台」（M2-T8 计划卡 + GDD §6）。
## CD 720t（12s，GDD §6；heroes 行 skill_cd 经 setup 覆写）、0 耗蓝。
## 施放 → 在玩家当前位置部署 TurretSummon（索敌/开火/超时详见 core/summons/turret.gd），
## combat/玩家引用注入取自 player.combat（RoomCombat/FloorScene 已按房间注入的同一引用）。
## 库存上限（GDD §6「与被动共用库存上限 2」）：heroes 行 summon_cap 附加键
## （HeroApplier meta "hero" 接缝读出，缺省 2）；满编时最旧炮台提前退场（树序 FIFO），
## 新炮台照常部署——总数恒 ≤ 上限。
## 被动「备件」（开局/每层补 1 台，passive_id=spare_parts）为后续卡接线，本卡不实现。

const DEFAULT_SUMMON_CAP := 2   # GDD §6 库存上限（heroes 行 summon_cap 可覆写）

var _cap := DEFAULT_SUMMON_CAP
var upgraded := false

func _init() -> void:
	cooldown_ticks = 720        # 12s（GDD §6；数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	super._load(data)           # SkillBase 无字段装载；保留钩子链（同影袭/狂潮先例）
	upgraded = bool(data.get("upgraded", false))
	# 上限读英雄行 summon_cap（HeroApplier 落 meta 在挂技能之前，时序见 hero_applier.apply）；
	# 无 meta（纯逻辑测试/未装配角色）用缺省。下限 1：0 上限会让「部署后立即顶替」语义退化。
	if player != null and player.has_meta("hero"):
		_cap = maxi(1, int((player.get_meta("hero") as Dictionary).get(
			"summon_cap", DEFAULT_SUMMON_CAP)))
	else:
		_cap = DEFAULT_SUMMON_CAP

func summon_cap() -> int:
	return _cap

func _activate(frame: int) -> void:
	if player == null or not player.is_inside_tree():
		return
	_retire_over_cap()
	_deploy(frame)

## 存活召唤物（"summons" 组；跨技能/被动共享的上限计数口径）。
## 剔除已失效与已排定退场（queue_free 尚未落地）的实例。
func living_summons() -> Array[SummonBase]:
	var out: Array[SummonBase] = []
	if player == null or not player.is_inside_tree():
		return out
	for node in player.get_tree().get_nodes_in_group("summons"):
		var s := node as SummonBase
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			out.append(s)
	return out

## 满编顶替：退掉最旧（组序 = 部署序）直至腾出一个名额。
func _retire_over_cap() -> void:
	var living := living_summons()
	while living.size() >= _cap and not living.is_empty():
		(living.pop_front() as SummonBase).despawn("replaced")

## 部署：挂玩家父节点（房间/楼层根，坐标同层）；无父兜底随玩家（生产不可达，纯逻辑环境）。
func _deploy(frame: int) -> void:
	var turret := TurretSummon.new()
	var host := player.get_parent()
	if host != null:
		host.add_child(turret)
		turret.global_position = player.global_position
	else:
		player.add_child(turret)
		turret.position = Vector2.ZERO
	turret.setup(TurretSummon.default_row(upgraded))
	turret.combat = player.combat
	turret.player = player
	turret.add_to_group("summons")
	turret.begin(frame)
	if player.combat != null:
		player.combat.register_body(turret, turret.combat_faction())
