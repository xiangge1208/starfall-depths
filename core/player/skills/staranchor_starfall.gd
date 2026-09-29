class_name StaranchorStarfall
extends SkillBase
## 星辰·晷 主动技「星陨」+ 被动「蓄能」（M5-T9，附录 L §3 第 20 行；heroes.json id=staranchor）。
##
## 被动蓄能（passive_id=charge_up）：同向持续瞄准 1s（60t）后伤害 +30%，转向超阈重置。
## - 方向采样 = player.facing（生产 player_driver 每拍把 current_aim 写入 facing，
##   桌面/手柄/触屏同源；无头测试直写 facing）；
## - 「同向」口径（议定披露）：锚点制——以本轮连击首拍方向为锚，与锚夹角 ≤ 阈值
##   持续累计；超阈即重置（锚点改写为当前方向、累计清零、退出蓄能）。阈值 15°
##   议定值（附录 L 未给；防瞄准微抖误重置，Balance Bot 校准点）；
## - 伤害侧写：tick 每拍续写 player.skill_dmg_bonus 共享窗（frame+1 滚动，血怒/
##   渐强同款；已有更强窗存活不自我降档），停写 1 拍自然过期。出口口径 = 玩家伤害
##   出口（scaled_damage）——星陨本体 40 伤为规格定值不走出口（不受蓄能放大，披露）。
##
## 主动星陨（CD 780t/25 蓝，heroes 行经 setup 覆写）：引导 0.8s（48t）→ 落点前摇
## 0.5s（30t）地面预警（§7.5 ≥0.35s 预警规范；FirerainZone 红圈同族自绘，fx 卡可
## 替换）→ 准星处 90px 星陨 40 伤（敌 AoE，take_hit 玩家归因）。
## - 落点 = 施放拍 player.pos + facing × 200px（「准星处」的方向化落点，议定值同
##   alchemist 掷程先例；引导期间落点锁定不追踪——附录 L 未述，披露）；
## - 引导不可打断（规格未述打断语义——按不可打断实现并披露：链期无取消读点；
##   移动不受限）；cast 过门（CD/蓝）后链条固定 78t；
## - 强化（data["upgraded"]，HeroApplier 按存档注入，附录 L 强化行）：星陨落点留
##   2s（120t）星火地面——每 0.5s（30t）1 伤 + SHOCK 电积累（alchemist 毒池同构：
##   take_hit ctx element=SHOCK → StatusComponent 既有通道；「第二次共鸣挂点」=
##   感电激活态参与共鸣）；地面半径同星陨 90px（议定：星火即落点地面）。
##
## 遥测：charge_up_enter / starfall_cast / starfall_impact（Telemetry 既有清单无撞名）。
## sfx：starfall（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "星陨"
const CHANNEL_TICKS := 48              # 引导 0.8s（附录 L §3）
const WARN_TICKS := 30                 # 落点前摇 0.5s（§7.5 预警规范）
const IMPACT_DAMAGE := 40              # 星陨 40 伤（附录 L §3 逐字）
const IMPACT_RADIUS_PX := 90.0         # 90px（附录 L §3 逐字）
const STARFALL_RANGE_PX := 200.0       # 议定值（「准星处」方向化落点；alchemist 掷程先例）
const CHARGE_SUSTAIN_TICKS := 60       # 同向持续瞄准 1s
const CHARGE_DMG_PCT := 0.30           # 伤害 +30%
const CHARGE_RESET_RAD := 0.2617994    # 议定阈值 15°（Balance Bot 校准点）
const EMBER_DURATION_TICKS := 120      # 强化：星火地面 2s
const EMBER_TICK_DAMAGE := 1           # 毒池同构：1 伤/tick
const EMBER_TICK_INTERVAL_TICKS := 30  # 0.5s

var upgraded := false
var _anchor_dir := Vector2.ZERO        # 蓄能连击锚点方向（ZERO = 未起锚）
var _aim_acc := 0                      # 同向累计拍
var _charged := false                  # 蓄能激活态
var _impact_at := -1                   # 星陨落点结算帧（<0 = 无链）
var _land_at := Vector2.ZERO           # 锁定落点
var _telegraph: CometTelegraph = null  # 预警圈引用（impact 释放）
var _ember_center := Vector2.ZERO
var _ember_until := -1                 # <0 = 无星火地面
var _ember_next_at := -1

func _init() -> void:
	cooldown_ticks = 780               # 13s（数据行覆写）
	energy_cost = 25

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（m5-t7 先例）
	upgraded = bool(data.get("upgraded", false))

## 施放生效：锁定落点 → 起 78t 链（引导 48t + 预警 30t）。无 player/combat 过门 no-op。
func _activate(frame: int) -> void:
	if player == null:
		return
	AudioMgr.play("starfall")
	var dir := player.facing
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_land_at = player.global_position + dir.normalized() * STARFALL_RANGE_PX
	_cancel_pending_chain()
	_impact_at = frame + CHANNEL_TICKS + WARN_TICKS
	Telemetry.log_row(["starfall_cast", frame, _impact_at, 1 if upgraded else 0], "staranchor")

## 防御性清链（CD 门控下重施不可达；测试重放兜底——同 bard _rollback 幂等守卫先例）。
func _cancel_pending_chain() -> void:
	_impact_at = -1
	_telegraph = null

## 星陨链是否在途（测试/HUD 查询用）。
func starfall_pending() -> bool:
	return _impact_at >= 0

## 蓄能是否激活（测试/HUD 查询用）。
func charge_active() -> bool:
	return _charged

## 蓄能同向累计拍（测试/HUD 查询用）。
func charge_acc() -> int:
	return _aim_acc

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：
## 蓄能方向采样 → 星陨链（预警圈铺放/落点结算）→ 星火地面节拍（毒池同构 while 追帧）。
func tick(frame: int) -> void:
	_tick_charge(frame)
	_tick_starfall(frame)
	_tick_ember(frame)

## 蓄能：方向采样（锚点制，见头注）+ 激活期续写伤害共享窗（不自我降档）。
func _tick_charge(frame: int) -> void:
	if player == null:
		return
	var dir := player.facing
	if _anchor_dir == Vector2.ZERO:
		_anchor_dir = dir              # 首拍起锚（本拍即第 1 拍同向瞄准）
		_aim_acc = 1
	elif absf(angle_difference(_anchor_dir.angle(), dir.angle())) > CHARGE_RESET_RAD:
		_anchor_dir = dir              # 转向超阈：重置（锚改写 + 清累计 + 退蓄能）
		_aim_acc = 1
		_charged = false
	else:
		_aim_acc += 1
		if not _charged and _aim_acc >= CHARGE_SUSTAIN_TICKS:
			_charged = true
			Telemetry.log_row(["charge_up_enter", frame], "staranchor")
	if not _charged:
		return
	var current := player.skill_dmg_bonus_pct \
		if frame < player.skill_dmg_bonus_until else 0.0
	if current >= CHARGE_DMG_PCT:
		return                          # 已有更强窗存活：不自我降档（渐强先例）
	player.skill_dmg_bonus_pct = CHARGE_DMG_PCT
	player.skill_dmg_bonus_until = frame + 1   # 滚动 1 拍窗：停写即过期，无残留

## 星陨链：引导期满铺预警圈（§7.5）→ 落点拍结算 90px 40 伤 + 强化星火地面。
func _tick_starfall(frame: int) -> void:
	if _impact_at < 0:
		return
	var combat = player.combat if player != null else null
	if frame >= _impact_at - WARN_TICKS and _telegraph == null \
			and combat != null and combat.has_method("add_child"):
		_telegraph = CometTelegraph.new()
		_telegraph.setup(IMPACT_RADIUS_PX, WARN_TICKS)
		combat.add_child(_telegraph)
		_telegraph.global_position = _land_at
	if frame < _impact_at:
		return
	_impact_at = -1
	var victims := 0
	if combat != null and combat.has_method("bodies_in_radius"):
		for body in combat.bodies_in_radius(_land_at, IMPACT_RADIUS_PX,
				Projectile.Faction.ENEMY):
			if body.get("state") == EnemyBase.State.DEAD:
				continue
			victims += 1
			body.take_hit({
				"amount": IMPACT_DAMAGE, "is_crit": false, "element": Elements.Id.NONE,
				"from": _land_at, "frame": frame, "source_type": "skill",
				"source_id": "staranchor_starfall", "source_name": SKILL_NAME,
				"attack_name": "星陨", "player_damage": true,
			})
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null
	if upgraded:
		_ember_center = _land_at
		_ember_until = frame + EMBER_DURATION_TICKS
		_ember_next_at = frame + EMBER_TICK_INTERVAL_TICKS
	Telemetry.log_row(["starfall_impact", frame, victims, 1 if upgraded else 0], "staranchor")

## 星火地面（强化）：每 0.5s 1 伤 + SHOCK 积累（毒池同构 while 追帧；无 combat
## 节拍照推结算跳过——alchemist 先例）。
func _tick_ember(frame: int) -> void:
	if _ember_until < 0 or frame > _ember_until:
		return
	var combat = player.combat if player != null else null
	while frame >= _ember_next_at and _ember_next_at <= _ember_until:
		_ember_next_at += EMBER_TICK_INTERVAL_TICKS
		if combat == null or not combat.has_method("bodies_in_radius"):
			continue
		for body in combat.bodies_in_radius(_ember_center, IMPACT_RADIUS_PX,
				Projectile.Faction.ENEMY):
			if body.get("state") == EnemyBase.State.DEAD:
				continue
			body.take_hit({
				"amount": EMBER_TICK_DAMAGE, "is_crit": false,
				"element": Elements.Id.SHOCK, "from": _ember_center, "frame": frame,
				"source_type": "skill", "source_id": "staranchor_starfall",
				"source_name": SKILL_NAME, "attack_name": "星火",
				"player_damage": true,
			})

## 星火地面是否在窗（测试/HUD 查询用；末拍含）。
func ember_active(frame: int) -> bool:
	return frame <= _ember_until

## 生产自驱（life_tide 习语）。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())


## 星陨落点预警圈（§7.5 地面红纹；FirerainZone 同族自绘——纯表现节点，逻辑全在
## 技能 tick 链，节点缺席不影响结算；宿主 = 房间 CombatSystem，随房退场）。
class CometTelegraph:
	extends Node2D
	const WARN_COLOR := Color(0.55, 0.75, 1.0, 0.30)   # 星辰主题冷色（敌火雨红圈同构）
	const WARN_EDGE := Color(0.7, 0.85, 1.0, 0.8)

	var _radius := 90.0
	var _left := 0

	func setup(radius: float, ticks: int) -> void:
		_radius = radius
		_left = maxi(0, ticks)
		queue_redraw()

	## 帧注入接缝（宿主 _physics_process 自驱；测试可直驱）。
	func tick() -> void:
		if _left <= 0:
			return
		_left -= 1
		queue_redraw()

	func _physics_process(_delta: float) -> void:
		tick()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, _radius, WARN_COLOR)
		var edge := WARN_EDGE if _left > 9 else Color(0.9, 0.95, 1.0, 1.0)
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 24, edge, 1.5)
