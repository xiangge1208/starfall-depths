class_name HunterMark
extends SkillBase
## 猎手·隼 主动技「猎印」+ 被动「弱点洞察」（M5-T7，附录 L §3 第 8 行；heroes.json id=hunter）。
##
## 被动弱点洞察（passive_id=deadeye_insight）：对同一敌人第 3 发连续命中必暴击
## （每敌 3s 冷则）。实现口径与游侠影袭 forced_crit 完全同构——暴击率置 1（GDD §7.1
## 暴击唯一随机乘区不做第二掷签，cc=1.0 时 DamageCalc 恒暴），读点在
## CombatSystem 命中结算掷签前的 note_player_hit 缝（combat 仅转发，计数状态全在
## 本技能节点——技能按角色注入，非隼不挂本脚本天然零漂移）：
## - 逐敌计数（instance_id 键）：{count, last, locked_until}；
## - 两处 3s 语义（规格「每敌 3s 冷却」+ 任务卡「3s 无命中后清零」的落地拆分）：
##   a) 断连清零：相邻两发间隔 > 180t（3s）→ 计数归零重计（含边界：恰 180t 不断）；
##   b) 触发冷却：第 3 发必暴后该敌锁定 180t，期间命中不计数（冷却过后自然从 1 重计
##      ——锁定末拍 last 已逾 180t 旧值，a 条同样兜底）。
## - 换敌互不影响（逐敌独立键）；敌死后键残留由 >64 键惰性修剪兜底（Stale 清理）。
## 口径披露：「发」= 玩家阵营弹命中（combat 命中结算缝）——近战挥击（melee.gd 直击
## 路径不经此缝）与召唤物弹均计入我方命中（单人局「我方第 3 发」通算，不按弹源过滤）。
##
## 主动猎印（CD 600t/10 蓝，heroes 行经 setup 覆写）：标记最近敌 5s（300t）——
## - 受伤 +25%：hit_damage_mult 缝（combat 命中结算掷签后乘入，GDD §7.1 全局乘区
##   口径向下取整 min 1）；作用域同 hunter/vengeance/echo 既有全局乘区先例 = 玩家阵营
##   弹命中路径（近战/AoE 直击不放大——scope 先例披露）；
## - 死亡爆：被标记敌 die()（died 信号，EnemyBase 唯一死亡路径）时以死点为心 30 伤
##   AoE（半径 90px 议定值，附录 L 未给——starfall 90px AoE 先例；Balance Bot 校准点）；
## - 强化（data["upgraded"]）：可同时存在 2 个标记（上限 2，选敌口径「最近未标记者」
##   ——全场皆已标记时回落「最近者」刷新）。上限经 append+trim 统一收口：基础版
##   cap=1 天然「重施替换」语义。数据行 CD 600t > 标记 300t，常规节奏双印不并存，
##   槽位语义由测试以注入短 CD 钉死（数据行数值不动，约束 13）。
## 无目标可标（射程内无敌）→ 施放照常过门（CD/蓝不退——框架无退回缝，同既定惯例）。
## 射程 480px 议定值（附录 L 未给；Balance Bot 校准点）。
##
## 遥测：deadeye_crit / hunter_mark_cast / mark_burst（Telemetry 既有清单无撞名）。
## sfx：hunter_mark（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

const SKILL_NAME := "猎印"            # 技能中文名（heroes 行 skill_name 同值）
const MARK_DURATION_TICKS := 300      # 5s（附录 L §3）
const MARK_DMG_TAKEN_MULT := 1.25     # 受伤 +25%（全局乘区口径）
const BURST_DAMAGE := 30              # 死亡爆 30 AoE（附录 L §3）
const BURST_RADIUS_PX := 90.0         # 议定值（附录 L 未给半径；starfall AoE 先例）
const MARK_RANGE_PX := 480.0          # 议定值（附录 L 未给射程；全房索敌量级）
const DEADEYE_REQUIRED_HITS := 3      # 第 3 发连续命中
const DEADEYE_STALE_TICKS := 180      # 3s：断连清零 / 触发后冷却（附录 L「每敌 3s 冷却」）
const DEADEYE_PRUNE_AT := 64          # 逐敌计数表惰性修剪阈值（跨房残留兜底）
const MARK_SLOTS_BASE := 1
const MARK_SLOTS_UPGRADED := 2        # 强化：可同时存在 2 个（附录 L 强化行）

var upgraded := false
var _marks: Array[Dictionary] = []    # {node: EnemyBase, until: int}（append+trim 收口）
var _deadeye: Dictionary = {}         # 敌 instance_id -> {count: int, last: int, locked: int}

func _init() -> void:
	cooldown_ticks = 600               # 10s（数据行覆写）
	energy_cost = 10

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（同影袭先例）
	upgraded = bool(data.get("upgraded", false))

# ================================================================ 主动：猎印

func _activate(frame: int) -> void:
	if player == null:
		return
	var target := _pick_mark_target()
	if target == null:
		return                          # 射程内无敌：过门 no-op（披露见头注）
	_marks.append({"node": target, "until": frame + MARK_DURATION_TICKS})
	while _marks.size() > _mark_slots():
		_drop_mark(_marks.pop_front())  # 基础版 cap=1 → 重施替换；强化 cap=2
	if not target.died.is_connected(_on_marked_died):
		target.died.connect(_on_marked_died)   # 唯一死亡路径钩（free 时自动断连）
	AudioMgr.play("hunter_mark")
	Telemetry.log_row(["hunter_mark_cast", frame, String(target.row.get("id", "")),
		_marks.size()], "hunter")

## 选敌：强化版优先「最近未标记者」（双印语义），全场皆已标记/基础版回落「最近者」。
func _pick_mark_target() -> EnemyBase:
	var combat = player.combat
	if combat == null or not combat.has_method("bodies_in_radius"):
		return null                     # 脑层/纯逻辑环境无战斗体：无目标可标
	var best: EnemyBase = null
	var best_unmarked: EnemyBase = null
	for body in combat.bodies_in_radius(player.global_position, MARK_RANGE_PX,
			Projectile.Faction.ENEMY):
		var e := body as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD or e.is_queued_for_deletion():
			continue
		if best == null:
			best = e                    # bodies_in_radius 距离升序 → 首个即最近
		if best_unmarked == null and not _is_marked(e):
			best_unmarked = e
		if best != null and best_unmarked != null:
			break
	return best_unmarked if best_unmarked != null else best

func _mark_slots() -> int:
	return MARK_SLOTS_UPGRADED if upgraded else MARK_SLOTS_BASE

## 摘除一具标记（替换/过期路径）：断 died 钩——被替换的未标记敌不得再触发死亡爆。
func _drop_mark(m: Dictionary) -> void:
	var e := m.get("node") as EnemyBase
	if e != null and is_instance_valid(e) and e.died.is_connected(_on_marked_died):
		e.died.disconnect(_on_marked_died)

func _is_marked(e: EnemyBase) -> bool:
	for m in _marks:
		if m["node"] == e:
			return true
	return false

## 标记读点缝（combat 命中结算转发）：目标在标记窗内 → 受伤 ×1.25，否则 1.0。
## frame 注入口径与 combat 命中拍一致（测试可注入；末拍不含，同窗语义）。
func hit_damage_mult(target: Node2D, frame: int) -> float:
	for m in _marks:
		var e := m["node"] as EnemyBase
		if e != null and e == target and not e.is_queued_for_deletion() \
				and e.state != EnemyBase.State.DEAD and frame < int(m["until"]):
			return MARK_DMG_TAKEN_MULT
	return 1.0

## 每拍推进：标记到期摘除（died 路径由信号即时摘，此处只管自然过期）+ 计数表修剪。
func tick(frame: int) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[i]
		var e := m["node"] as EnemyBase
		if e == null or not is_instance_valid(e) or frame >= int(m["until"]):
			_marks.remove_at(i)
			_drop_mark(m)
	if _deadeye.size() > DEADEYE_PRUNE_AT:
		for key: int in _deadeye.keys():
			var entry: Dictionary = _deadeye[key]
			if frame - int(entry["last"]) > DEADEYE_STALE_TICKS:
				_deadeye.erase(key)

## 死亡爆：被标记敌 die()（died 信号）→ 死点 30 伤 AoE（§7.3 bodies_in_radius 习语，
## 同 turret 导弹/坚守先例；已死体跳过——含标记体自身）。即时摘标防重入。
func _on_marked_died(enemy: EnemyBase) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		if _marks[i]["node"] == enemy:
			_marks.remove_at(i)
	var frame := Engine.get_physics_frames()
	var at := enemy.global_position
	var combat = player.combat if player != null else null
	if combat == null or not combat.has_method("bodies_in_radius"):
		return                          # 脑层环境无战斗体：无从结算 AoE
	var victims := 0
	for body in combat.bodies_in_radius(at, BURST_RADIUS_PX, Projectile.Faction.ENEMY):
		if body.get("state") == EnemyBase.State.DEAD:
			continue
		victims += 1
		body.take_hit({
			"amount": BURST_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
			"from": at, "frame": frame, "source_type": "skill", "source_id": "hunter_mark",
			"source_name": SKILL_NAME, "attack_name": "猎印爆裂", "player_damage": true,
		})
	Telemetry.log_row(["mark_burst", frame, victims], "hunter")

# ================================================================ 被动：弱点洞察

## 命中计数缝（combat 掷签前转发）：记录一发命中并返回是否「同敌第 3 连发」
## （true → combat 暴击率置 1，影袭 forced_crit 同口径）。返回值语义外，无副作用外溢。
func note_player_hit(target: Node2D, frame: int) -> bool:
	var key := target.get_instance_id()
	var entry: Dictionary = _deadeye.get(key, {"count": 0, "last": -1, "locked": -1})
	if frame < int(entry["locked"]):
		return false                    # 触发冷却：该敌不计数（披露见头注 b 条）
	if int(entry["last"]) >= 0 and frame - int(entry["last"]) > DEADEYE_STALE_TICKS:
		entry["count"] = 0              # 断连清零：>3s 无命中重计（恰 180t 不断）
	entry["count"] = int(entry["count"]) + 1
	entry["last"] = frame
	if int(entry["count"]) >= DEADEYE_REQUIRED_HITS:
		entry["count"] = 0
		entry["locked"] = frame + DEADEYE_STALE_TICKS
		_deadeye[key] = entry
		Telemetry.log_row(["deadeye_crit", frame], "hunter")
		return true
	_deadeye[key] = entry
	return false

## 计数窗状态查询（测试/HUD 用）：该敌当前连发数。
func deadeye_count(target: Node2D) -> int:
	var entry: Dictionary = _deadeye.get(target.get_instance_id(), {})
	return int(entry.get("count", 0))

## 标记查询（测试/HUD 用）：目标当前是否在标记窗内（口径同 hit_damage_mult）。
func is_target_marked(target: Node2D, frame: int) -> bool:
	return hit_damage_mult(target, frame) > 1.0

## 生产自驱（life_tide/alchemist 习语）；无头测试直接调 tick(frame) 注入帧。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
