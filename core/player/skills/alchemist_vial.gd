class_name AlchemistVial
extends SkillBase
## 炼金·汞 主动技「投瓶」+ 被动「侵蚀」（M5-T3，附录 L §3 第 13 行）。
##
## 主动（CD 480t/0 蓝，heroes 行经 setup 覆写）：朝当前瞄准方向抛物掷瓶，落点
## （player.pos + facing × THROW_RANGE_PX）生成 3s（180t）毒池——池内敌人每 0.5s
## （30t）1 伤并推进毒积累（take_hit ctx element=POISON → StatusComponent
## apply_hit_context 既有通道，毒触发/共鸣/DoT 全走存量语义）。强化版（Appendix L
## 强化行「投瓶随机元素（火/毒/电轮转）——共鸣发动机强化」）：逐次投瓶按
## 火→毒→电轮转换池元素（确定性轮转，不掷 RNG——同种子复现纪律），伤害/积累
## 随元素（FIRE 燃烧 / POISON 中毒 / SHOCK 感电触发全走存量状态语义）。
##
## 被动「侵蚀」（passive_id=erosion）：元素状态积累 +20%，与同名增益叠乘——叠乘
## 口径（头注钉死）：同名增益「状态侵蚀」status_erode（buffs.json，effects
## status_rate_pct=+0.25）走玩家侧加法桶（BuffManager → status_rate_bonus →
## effective_status_rate_multiplier），随 ctx.status_rate_mult 到达状态系统；被动
## ×1.2 在状态系统侧统一漏斗（StatusComponent.apply_hit_context）乘入——合成口径
## (1 + Σ增益) × 1.2（例：持状态侵蚀 1.25 × 1.2 = 1.5，非 1 + 0.25 + 0.2 加法合流）。
## 唯一读点 = StatusComponent.attacker_stack_scale_hook（status_system 侧，远程弹/
## 近战/毒池全部命中契约共用漏斗）；钩子由本技能装配期注入（绑定实例，释放即失效
## 回落恒等 1.0，非炼金零漂移）。
##
## 落点/半径议定值披露（附录 L 未给，同 life_tide 60px AoE 议定先例；Balance Bot
## 校准点）：掷程 200px、池半径 60px。池为技能实例状态（CD 480t > 时长 180t，重投
## 必不重叠）；驱动 = 技能节点自身 _physics_process（life_tide 习语），测试可注入
## 任意帧直驱 tick(frame)。视觉表现本卡不落（逻辑层，fx 后续卡）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "投瓶"
const POOL_RADIUS_PX := 60.0           # 议定值（LifeTide 60px AoE 先例）
const POOL_DURATION_TICKS := 180       # 3s
const POOL_TICK_DAMAGE := 1            # 附录 L §3：1 伤/0.5s
const POOL_TICK_INTERVAL_TICKS := 30   # 0.5s
const THROW_RANGE_PX := 200.0          # 议定值（附录 L 未给掷程）
const EROSION_STACK_MULT := 1.2        # 侵蚀：元素积累 ×1.2（与同名增益叠乘，见头注）
## 强化轮转序（附录 L「火/毒/电轮转」；下标随投瓶递增对 3 取模）。
const ROTATION: Array[int] = [Elements.Id.FIRE, Elements.Id.POISON, Elements.Id.SHOCK]

var upgraded := false
var _pool_center := Vector2.ZERO
var _pool_until := -1                 # <0 = 无池
var _pool_element := Elements.Id.NONE
var _next_tick_at := -1
var _rotation_idx := 0                # 强化轮转游标（跨投瓶持久，单局语义）

func _init() -> void:
	cooldown_ticks = 480        # 8s（附录 L §3；数据行覆写）
	energy_cost = 0

func _load(data: Dictionary) -> void:
	super._load(data)           # SkillBase 无字段装载；保留钩子链（同影袭/狂潮先例）
	upgraded = bool(data.get("upgraded", false))
	# 侵蚀乘区钩子（装配期一次性注册；绑定本实例——实例释放 is_valid()=false，
	# 状态侧漏斗自动回落恒等，跨局/跨角色无残留）。
	StatusComponent.attacker_stack_scale_hook = Callable(self, "_erosion_stack_scale")

func _erosion_stack_scale() -> float:
	return EROSION_STACK_MULT

func _activate(frame: int) -> void:
	if player == null:
		return
	var dir := player.facing
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_pool_center = player.global_position + dir.normalized() * THROW_RANGE_PX
	_pool_until = frame + POOL_DURATION_TICKS
	_pool_element = _next_element()
	_next_tick_at = frame + POOL_TICK_INTERVAL_TICKS
	AudioMgr.play("vial_throw")      # m5-t3：掷瓶拍（cast 过门后到此才响）
	Telemetry.log_row(["vial_throw", frame, Elements.NAMES[_pool_element],
		1 if upgraded else 0], "alchemist")

## 本次投瓶元素：非强化恒毒（附录 L §3 酸瓶毒池）；强化按 火→毒→电 轮转推进游标。
func _next_element() -> int:
	if not upgraded:
		return Elements.Id.POISON
	var e := ROTATION[_rotation_idx % ROTATION.size()]
	_rotation_idx += 1
	return e

## 池是否在窗内（测试/HUD 查询用；末拍含）。
func pool_active(frame: int) -> bool:
	return frame <= _pool_until

## 每拍推进：池节拍结算（while 追帧，同 blaze cloud 口径）。无池/窗闭零开销直接返回。
func tick(frame: int) -> void:
	if _pool_until < 0 or frame > _pool_until:
		return
	var combat = player.combat if player != null else null
	while frame >= _next_tick_at and _next_tick_at <= _pool_until:
		_next_tick_at += POOL_TICK_INTERVAL_TICKS
		if combat == null or not combat.has_method("bodies_in_radius"):
			continue              # 脑层/纯逻辑环境无战斗体：节拍推进、结算跳过
		for body in combat.bodies_in_radius(_pool_center, POOL_RADIUS_PX,
				Projectile.Faction.ENEMY):
			if body.get("state") == EnemyBase.State.DEAD:
				continue
			# element=池元素 → StatusComponent.apply_hit_context 推进对应积累
			#（侵蚀被动 ×1.2 经同一漏斗生效）；伤害/触发归因玩家侧。
			body.take_hit({
				"amount": POOL_TICK_DAMAGE, "is_crit": false, "element": _pool_element,
				"from": _pool_center, "frame": frame, "source_type": "skill",
				"source_id": "alchemist_vial", "source_name": SKILL_NAME,
				"attack_name": "元素池",
				"player_damage": true,
			})

## 生产自驱（同 life_tide/summon_base 习语）；无头测试直接调 tick(frame) 注入帧。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
