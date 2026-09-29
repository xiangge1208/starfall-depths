class_name BulwarkShield
extends SkillBase
## 铁卫·锚 主动技「架设」+ 被动「固守」（附录 L §3，M5 T6；heroes.json id=bulwark）。
##
## 被动固守（passive_id=entrench 门控）：静止 1.5s（90t）获受伤 -25%（移动即失效）。
## 移动检测在技能内自测位移（本卡禁碰 player.gd 移动缝）：tick 逐拍比对 player
## .global_position，位移（含翻滚/击退/拉拽的任何位置变化）即清零计时并停写减伤窗；
## 满计时开窗（incoming_dr_pct/until 通用减伤窗，take_hit_ctx 与狂潮/潮汐同口径
## ×0.75 向下取整 min 1，滚动 +2t 续窗同 life_tide 前瞻先例，停写 ≤2 拍自然过期）。
##
## 主动架设：CD 720t（12s，数据行 skill_cd 覆写）/0 蓝，在玩家面朝前方 26px 架设
## 钢盾（HP 30，议定半径 14px；无存活时限，被摧毁/被替换/随房退场为止——工事不跨房
## 披露：盾挂房间 CombatSystem 节点下，换房随房释放）。
## 「挡双方弹幕」通道（C-5 可破坏物复用，零改 CombatSystem）：CombatSystem 命中判定
## 为「弹幕 × 异阵营体」，故双阵营各注册一个判定体共摊同一 HP——盾本体注册 ENEMY
## 阵营（接我方弹/近战/我方 AoE），同位 catcher 子体注册 PLAYER 阵营（接敌方弹），
## 二者 take_hit 同扣盾 HP（C-5 固定伤害制：ctx.amount 直扣，无二次乘区）。
## 敌我弹皆可摧毁=规格逐字（含自己人的火力）。物理不阻挡移动（纯弹幕屏障，披露：
## 规格只述「挡弹幕」，防玩家自困）。
## 强化（data["upgraded"]，HeroApplier 按存档注入）：钢盾碎裂（被摧毁，含替换路径）
## 迸射 3 块碎片（120° 均布确定性出射），各 10 伤走玩家弹结算通道（DamageCalc 全局
## 口径——基础值 10，暴击乘区与其他玩家弹一致）。
##
## 语义披露：①视觉表现本卡不落（逻辑层，T3/T4 同先例，fx 后续卡）；②碎片出射角
## 不随面朝旋转（i×120° 确定性，便于回放/测试）。
## 帧注入直驱（tick(frame)）可无头测；生产 _physics_process 自驱（life_tide 习语）。
##
## 遥测：steel_shield_cast / steel_shield_shatter / entrench_active（激活沿一次，
## Telemetry 既有清单无撞名）。
## sfx：steel_shield（施放拍）；盾碎裂复用既有 props 键 destroy（C-5 同源）。

const SKILL_NAME := "架设"          # 技能中文名（heroes 行 skill_name 同值）
const SHIELD_HP := 30               # 附录 L §3 逐字
const SHIELD_RADIUS_PX := 14.0      # 判定体半径（议定值；C-5 pillar 8px 掩体放大档）
const SHIELD_OFFSET_PX := 26.0      # 前方架设偏移（议定值）
const SHARD_COUNT := 3              # 强化：碎裂迸射 3 块
const SHARD_DMG := 10               # 各 10 伤（基础值，玩家弹结算通道）
const SHARD_SPEED_PX := 180.0
const SHARD_LIFE_SECONDS := 0.5
const SHARD_RADIUS_PX := 3.0
# ---- 固守 ----
const STATION_TICKS := 90           # 1.5s（GDD §6 拍口径 TimeConst.FPS=60）
const ENTRENCH_DR_PCT := 0.25       # 受伤 -25%（附录 L §3 逐字）
const GUARD_LOOKAHEAD_TICKS := 2    # 减伤窗续期前瞻（life_tide 同款：覆盖同拍受击）

var upgraded := false
var shield: SteelShield = null      # 场上钢盾唯一引用（null = 无）
var _still_acc := 0                # 固守：静止累计拍
var _last_pos := Vector2.ZERO      # 固守：上一拍位置（位移自测）
var _last_pos_set := false
var _entrenched := false

func _init() -> void:
	cooldown_ticks = 720               # 12s（数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 钢盾是否在位（测试/HUD 查询用）。
func shield_alive() -> bool:
	return shield != null and is_instance_valid(shield) and not shield.is_done()

## 固守是否生效（计时满且窗在续写；测试/HUD 查询用）。
func entrenched() -> bool:
	return _entrenched

## 架设生效：先替换旧盾（摧毁全路径——替换即碎裂语义统一），再于面前铺新盾。
## 无 combat（裸测/无房）静默 no-op（占位语义：cast 过门不产生实体）。
func _activate(frame: int) -> void:
	if player == null:
		return
	AudioMgr.play("steel_shield")
	if player.combat == null:
		return
	if shield_alive():
		shield.destroy()
	var s := SteelShield.new()
	s.setup(self, SHIELD_HP, SHIELD_RADIUS_PX)
	player.combat.add_child(s)
	s.global_position = player.global_position \
		+ (player.facing.normalized() * SHIELD_OFFSET_PX if player.facing != Vector2.ZERO \
			else Vector2.ZERO)
	s.register_combat(player.combat)
	shield = s
	Telemetry.log_row(["steel_shield_cast", frame, 1 if upgraded else 0])

## 盾碎裂回调（SteelShield.destroy 统一入口，含替换路径）：强化迸 3 碎片各 10 伤。
func _on_shield_destroyed(pos: Vector2) -> void:
	shield = null
	var cs := player.combat if player != null else null
	var shard_count := 0
	if upgraded and cs != null and is_instance_valid(cs):
		for i in SHARD_COUNT:
			var dir := Vector2.from_angle(TAU * float(i) / float(SHARD_COUNT))
			cs.spawn_projectile({
				"pos": pos, "vel": dir * SHARD_SPEED_PX, "damage": SHARD_DMG,
				"faction": Projectile.Faction.PLAYER, "element": Elements.Id.NONE,
				"pierce": 0, "bounce": 0, "life_seconds": SHARD_LIFE_SECONDS,
				"radius": SHARD_RADIUS_PX, "source_type": "skill",
				"source_id": "bulwark_shield", "source_name": "钢盾", "attack_name": "碎片迸射",
			})
			shard_count += 1
	Telemetry.log_row(["steel_shield_shatter", Engine.get_physics_frames(), shard_count])

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：固守位移自测 + 减伤窗续写。
func tick(frame: int) -> void:
	if player == null or player.passive_id != "entrench":
		return
	var pos := player.global_position
	if _last_pos_set and pos != _last_pos:
		_still_acc = 0                 # 移动即失效：计时清零 + 停写（窗 ≤2t 自然过期）
		_entrenched = false
	else:
		_still_acc += 1
	_last_pos = pos
	_last_pos_set = true
	if not _entrenched and _still_acc >= STATION_TICKS:
		_entrenched = true
		Telemetry.log_row(["entrench_active", frame])
	if _entrenched:
		player.incoming_dr_pct = ENTRENCH_DR_PCT
		player.incoming_dr_until = frame + GUARD_LOOKAHEAD_TICKS

## 生产自驱（life_tide 习语）。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())


## 钢盾实体（C-5 可破坏物通道复用：register_body + 固定伤害 take_hit 契约，
## 同 DestructibleProp 先例独立实现）：本体接我方侧伤害（ENEMY 阵营），
## catcher 子体接敌方弹（PLAYER 阵营），同一 HP。无物理阻挡、无存活时限。
class SteelShield:
	extends Node2D
	var hp := 30
	var radius := 14.0
	var upgraded := false
	var combat: CombatSystem = null
	var catcher: ShieldCatcher = null
	var _skill: Node = null           # BulwarkShield（碎裂回调；duck 引用防循环类型）
	var _done := false                # 破坏幂等门（destroy 恰一次）

	func setup(skill: Node, hp_value: int, radius_value: float) -> void:
		_skill = skill
		hp = maxi(hp_value, 1)
		radius = radius_value
		upgraded = bool(skill.get("upgraded"))
		catcher = ShieldCatcher.new()
		catcher.shield = self
		add_child(catcher)

	## 进战斗流（C-5 attach 同缝）：本体 ENEMY 阵营 + catcher PLAYER 阵营（挡双方弹幕）。
	## 须在入树且 global_position 定位后调用。
	func register_combat(system: CombatSystem) -> void:
		combat = system
		if combat == null:
			return
		combat.register_body(self, Projectile.Faction.ENEMY)
		combat.register_body(catcher, Projectile.Faction.PLAYER)

	## CombatSystem 战斗体半径契约（同 EnemyBase/DestructibleProp 口径）。
	func combat_radius() -> float:
		return radius

	## 伤害入口（C-5 固定伤害制）：amount 直扣，归零即碎裂。已碎再击零副作用（幂等）。
	func take_hit(ctx: Dictionary) -> void:
		if _done:
			return
		hp = maxi(hp - absi(int(ctx.get("amount", 0))), 0)
		if hp == 0:
			destroy()

	func is_done() -> bool:
		return _done

	## 碎裂：幂等门内注销双判定体（哈希不泄漏）→ 碎片回调（强化）→ 退场
	## （catcher 为子节点随释放）。
	func destroy() -> void:
		if _done:
			return
		_done = true
		hp = 0
		AudioMgr.play_once("destroy")   # C-5 同源破碎拍（幂等门内恰一次）
		if combat != null and is_instance_valid(combat):
			combat.unregister_body(self)
			if catcher != null:
				combat.unregister_body(catcher)
			combat = null
		if _skill != null and is_instance_valid(_skill):
			_skill.call("_on_shield_destroyed", global_position)
		queue_free()


## 钢盾敌方弹受击体（同位转发体）：PLAYER 阵营注册——敌方弹命中判定按「异阵营体」，
## 弹打盾即碎弹扣盾 HP，不再飞向玩家。
class ShieldCatcher:
	extends Node2D
	var shield: SteelShield = null

	func combat_radius() -> float:
		return shield.radius if shield != null else 14.0

	## 转发本体统一结算（幂等门在本体）。
	func take_hit(ctx: Dictionary) -> void:
		if shield != null:
			shield.take_hit(ctx)
