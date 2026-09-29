class_name ClericSanctuary
extends SkillBase
## 圣职·烛 主动技「圣环」+ 被动「圣佑」（附录 L §3，M5 T8；heroes.json id=cleric）。
##
## 被动圣佑（passive_id=aegis_blessing 门控）：护盾破碎瞬间 1.5s 无敌（每房 1 次）。
## - 挂点 = EventBus.shield_broken（player.take_hit_ctx 护盾 >0→0 破碎拍广播，
##   坚守被动同源信号；订阅于 setup——bard 弦受击重置同款方法引用，free 时自动断连）；
## - 无敌 = Player.apply_iframes(90t, 破碎拍)（取 max 不缩短既有窗公共缝，影袭/复活
##   图腾同款）——破碎当拍来伤已落地（打破盾的那一击），无敌保护其后 1.5s 内来伤；
## - 「每房 1 次」守卫：消费记号 + 房间更替检测——player.combat 每房重注入（FloorScene
##   ._wire_room_combat 契约，房间各自 CombatSystem 实例），触发点先比对实例键，键变
##   即重置预算。零逐拍轮询（检测内联在破碎回调，零热路径开销）。披露：①商店房不重
##   注入 combat → 穿过商店不重置（保守方向）；②重访已进房（同实例回注）不重置
##   ——严格于「每房首入一次」口径。
##
## 主动圣环：CD 720t（12s，数据行覆写）/15 蓝，在施放位置生成 3s（180t，末拍含）
## 静止圣环（半径 110px 议定值，本卡任务卡议定；life_tide 法阵静止同款）：
## - 环内玩家受伤 -25%：复用 m5-t6 通用减伤窗（player.incoming_dr_pct/until，
##   take_hit_ctx ×0.75 向下取整 min 1 与狂潮/潮汐同口径）——life_tide 升级版减伤窗
##   同款续写语义：tick 每拍判玩家在环内才续写（+2t 前瞻覆盖同拍受击），离环/停写
##   ≤2t 自然过期。技能实例态（非场景节点）跨房存活至到期——法阵先例同款；
## - 触敌 2 伤/0.5s：30t 节拍（while 追帧，alchemist 毒池同口径）对环内敌结算
##   （固定 2 伤，不走玩家乘区——技能 AoE 先例同口径；已死体跳过）；
## - 强化（data["upgraded"]，附录 L 强化行「圣环结束时回 1 HP」）：环到期（末拍后
##   首个 tick）经 heal() 单一收口回 1 HP——灾厄 heal_disable 灾厄下静默失效（返回
##   false 不补偿）；hp<=0（已死）不回（不做无复活语义的起死回生，披露）。
##
## 共享窗披露：固守（m5-t6）与本技能写同一 incoming_dr 窗且同为 0.25——单玩家恒单
## 技能节点（HeroApplier 换装），两者生产上互斥，无叠写冲突。
## 遥测：aegis_trigger / sanctuary_cast（帧,时长,强化）/ sanctuary_heal（帧,回复量）
## ——Telemetry 既有清单无撞名。
## sfx：cleric_sanctuary（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。
## 视觉表现本卡不落（逻辑层先例同上）。

const SKILL_NAME := "圣环"              # 技能中文名（heroes 行 skill_name 同值）
const RING_RADIUS_PX := 110.0           # 议定值（本卡任务卡议定；life_tide 法阵先例）
const RING_DURATION_TICKS := 180        # 3s（附录 L §3；末拍含——第 6 个 0.5s 节拍在窗内）
const RING_DR_PCT := 0.25               # 环内受伤 -25%（附录 L §3 逐字）
const RING_TICK_DAMAGE := 2             # 触敌 2 伤（附录 L §3 逐字）
const RING_TICK_INTERVAL_TICKS := 30    # 0.5s
const RING_END_HEAL := 1                # 强化：圣环结束回 1 HP（附录 L 强化行）
const AEGIS_IFRAME_TICKS := 90          # 圣佑：1.5s 无敌（附录 L §3 逐字）
const GUARD_LOOKAHEAD_TICKS := 2        # 减伤窗续期前瞻（life_tide 同款）

var upgraded := false
# ---- 圣佑（每房预算） ----
var _aegis_used := false                # 当前房圣佑已消费
var _room_combat_key := 0               # 上次消费判定所见的 combat 实例键（0 = 无）
# ---- 圣环 ----
var _ring_center := Vector2.ZERO
var _ring_until := -1                   # 环结束帧（含）；<0 = 无环
var _next_tick_at := -1                 # 下次触敌节拍帧

func _init() -> void:
	cooldown_ticks = 720               # 12s（数据行覆写）
	energy_cost = 15

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（影袭先例）
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.shield_broken.is_connected(_on_shield_broken):
		EventBus.shield_broken.connect(_on_shield_broken)   # 破碎拍挂钩；free 时自动断连

# ================================================================ 被动：圣佑

## 护盾破碎拍（EventBus.shield_broken，坚守同源信号）：每房 1 次 → 1.5s 无敌。
## 房间更替检测内联在触发点（零逐拍轮询；语义见头注披露 ①②）。
func _on_shield_broken() -> void:
	if player == null or player.passive_id != "aegis_blessing":
		return
	var key := player.combat.get_instance_id() if player.combat != null else 0
	if key != _room_combat_key:
		_room_combat_key = key
		_aegis_used = false            # 新战斗上下文：预算重置
	if _aegis_used:
		return
	_aegis_used = true
	player.apply_iframes(AEGIS_IFRAME_TICKS, Engine.get_physics_frames())
	Telemetry.log_row(["aegis_trigger", Engine.get_physics_frames()], "cleric")

# ================================================================ 主动：圣环

## 环是否在窗内（测试/HUD 查询用；末拍含）。
func ring_active(frame: int) -> bool:
	return _ring_until >= 0 and frame <= _ring_until

func _activate(frame: int) -> void:
	if player == null:
		return
	_ring_center = player.global_position   # 静止环锚点（life_tide 法阵同款）
	_ring_until = frame + RING_DURATION_TICKS
	_next_tick_at = frame + RING_TICK_INTERVAL_TICKS
	AudioMgr.play("cleric_sanctuary")
	Telemetry.log_row(["sanctuary_cast", frame, RING_DURATION_TICKS,
		1 if upgraded else 0], "cleric")

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：到期收尾（强化回血）→
## 环内减伤窗续写 → 触敌节拍结算。无环帧零开销直接返回。
func tick(frame: int) -> void:
	if _ring_until < 0:
		return
	if frame > _ring_until:
		_expire_ring(frame)
		return
	if _player_inside():
		player.incoming_dr_pct = RING_DR_PCT
		player.incoming_dr_until = frame + GUARD_LOOKAHEAD_TICKS
	var combat = player.combat if player != null else null
	while frame >= _next_tick_at and _next_tick_at <= _ring_until:
		_next_tick_at += RING_TICK_INTERVAL_TICKS
		if combat == null or not combat.has_method("bodies_in_radius"):
			continue                  # 脑层/纯逻辑环境无战斗体：节拍推进、结算跳过
		for body in combat.bodies_in_radius(_ring_center, RING_RADIUS_PX,
				Projectile.Faction.ENEMY):
			if body.get("state") == EnemyBase.State.DEAD:
				continue
			body.take_hit({
				"amount": RING_TICK_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
				"from": _ring_center, "frame": frame, "source_type": "skill",
				"source_id": "cleric_sanctuary", "source_name": SKILL_NAME,
				"attack_name": "圣环", "player_damage": true,
			})

## 到期收尾：强化「圣环结束时回 1 HP」（heal 单一收口；灾厄禁疗静默、已死不回）。
func _expire_ring(frame: int) -> void:
	_ring_until = -1
	if not upgraded or player == null or player.hp <= 0:
		return
	if player.heal(RING_END_HEAL):
		Telemetry.log_row(["sanctuary_heal", frame, RING_END_HEAL], "cleric")

func _player_inside() -> bool:
	return player != null and player.global_position.distance_to(_ring_center) <= RING_RADIUS_PX

## 生产自驱（life_tide/alchemist 习语）；无头测试直接调 tick(frame) 注入帧。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
