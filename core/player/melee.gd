class_name Melee
extends Node
## 近战挥击 + 反弹窗口（GDD §7.4）。挥击 9 ticks；窗口 [3,9]，7 帧 ≈0.12s。

const SWING_TICKS := 9
const PARRY_FROM := 3
const PARRY_TO := 9

## m5-t8 行云强化（武僧·岳，附录 L）：满「势」反弹窗口 ×2 —— 本次挥击反弹上界
## （默认基线 PARRY_TO；窗口开启拍经玩家 meta 单点读数改写，MonkQuake.META_PARRY_EXTRA）。
var _parry_to := PARRY_TO

## M5-A2 手刀（空手攻击，对标复盘 #2 借鉴元气骑士）：空槽时的保底挥击——虚拟
## 武器行走与真实近战**完全同一条**挥击/反弹路径（GDD §7.4 反弹窗口/挥砍区
## 无敌判定单一事实源）。不入武器表（GameDB），id "hand_blade" 仅供遥测/成就
## 类目特判（AchievementSystem.notify_weapon_used）。
const HAND_BLADE := {
	"id": "hand_blade", "name": "手刀", "is_melee": true, "category": "melee",
	"damage": 1, "rate": 3.0, "range": 26.0, "arc_deg": 90.0,
	"energy_cost": 0, "element": "none",
}

signal melee_swung(weapon: Dictionary, aim: Vector2)

var rig: WeaponRig
var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var _swing_left := 0
var _swing_tick := -1
var _hit_done := false
var _next_frame := 0
var _active_row: Dictionary = {}    # 本次挥击的行（真实行或 HAND_BLADE）——_physics_process 读此而非 rig.current()（空槽挥击期间行必须稳定）

func _test_init() -> void:
	pass

func try_attack(frame: int) -> bool:
	var w := rig.current()
	if w.is_empty():
		w = HAND_BLADE                    # M5-A2：空槽=手刀
	elif not w["is_melee"]:
		return false
	_active_row = w
	if _swing_left > 0 or frame < _next_frame:
		return false
	var player := get_parent() as Player
	_next_frame = frame + maxi(1, int(round(TimeConst.FPS \
		/ rig.effective_attack_rate(w, player, frame, true))))
	_swing_left = SWING_TICKS
	_swing_tick = 0
	_hit_done = false
	AudioMgr.play("melee_swing")         # m2-t5：挥击起始音
	melee_swung.emit(w, player.facing if player != null else Vector2.RIGHT)
	return true

func is_parry_tick(tick: int) -> bool:
	return tick >= PARRY_FROM and tick <= _parry_to

func _physics_process(_delta: float) -> void:
	if _swing_left <= 0:
		return
	_swing_tick += 1
	_swing_left -= 1
	var player := get_parent() as Player
	var w := _active_row                # M5-A2：空槽挥击期间读启动时行（虚拟行稳定）
	var range_px := float(w.get("range", 40))
	var arc := float(w.get("arc_deg", 90.0))
	# m5-t8 行云强化缝（单点读数）：反弹窗开启拍读 meta 定格本挥击反弹上界（满势 ×2：
	# 3..16t ≈ 0.24s）并补足挥击处理长度；meta 缺省 0 = 基线 3..9t 零漂移。窗口开启后
	# 中途耗势不缩窗（已定格，语义见 MonkQuake 头注）。
	if _swing_tick == PARRY_FROM:
		var parry_extra := int(player.get_meta(MonkQuake.META_PARRY_EXTRA, 0)) \
			if player != null else 0
		_parry_to = PARRY_TO + parry_extra
		if _parry_to > PARRY_TO:
			_swing_left = maxi(_swing_left, _parry_to - _swing_tick)
	if is_parry_tick(_swing_tick):
		for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			# 披露（m4-c2）：反弹伤害镜像武器行原值（GDD §7.4 反弹窗口防御机制），
			# 不走挥击伤害出口聚合点（祝福/天赋乘区不放大反弹面）。
			combat.reflect(p, int(w["damage"]))
			AudioMgr.play_once("reflect")   # m4p-w2a：反弹生效拍（play_once 同帧多弹一声）
	else:
		for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			combat.block(p)
	if not _hit_done:
		_hit_done = true
		# m4-c2：基础伤害走玩家伤害出口聚合点（祝福叠层/天赋乘区，与远程同一口径）。
		# m5-c 配件乘区顺序（与远程 _fire_slot 同两段口径）：近战 muzzle 槽无效
		#（无枪口，exclude_muzzle=true）；mag/stock 生效——配件 dmg_pct 先 round
		# 整数化 → player.scaled_damage（天赋/祝福）。披露：双子弹匣的 dmg_pct
		# -0.20 惩罚对近战照收（mag 槽生效）；projectiles_flat/energy_pct 近战无
		# 消费面 = no-op；roll_boost（stock）经 rig._physics_process 轮询触发。
		var eff := rig._attachment_effects(w, true)
		var att_base := maxi(0, int(round(float(int(w["damage"])) * (1.0 + float(eff["dmg_pct"])))))
		var base_damage := player.scaled_damage(att_base)
		# m5-t8 行云势层乘区缝（单点读数）：meta 由 MonkQuake 随层变化续写（1+0.08×层），
		# 位置 = 玩家出口聚合点之后、暴击掷签之前（祝福同段位）；round + min 1 收口。
		# meta 缺省 1.0 = 非武僧零漂移。
		var momentum_mult := float(player.get_meta(MonkQuake.META_MOMENTUM_MULT, 1.0)) \
			if player != null else 1.0
		if momentum_mult != 1.0:
			base_damage = maxi(1, int(round(float(base_damage) * momentum_mult)))
		# m5-t8 行云上报缝（单点，has_method 门控——"Skill" 未挂 MonkQuake 时零副作用）：
		# 近战命中逐目标喂「势」（口径同相邻 Fx.on_combo_hit），MonkQuake.note_melee_hit 消费。
		var flow_skill := player.get_node_or_null("Skill") if player != null else null
		var flow_ready := flow_skill != null and flow_skill.has_method("note_melee_hit")
		# 暴击本地 roll；combat_rng 未注入（纯逻辑测试）时跳过 roll 用平伤。
		var roll: Dictionary = {"amount": base_damage, "is_crit": false}
		if combat_rng != null:
			var base_crit := float(player.get_meta("crit_base", 0.05))
			roll = DamageCalc.compute(base_damage, combat_rng,
				player.effective_crit_chance(base_crit), player.effective_crit_multiplier())
		var element_profile := rig.element_hit_profile(w, Engine.get_physics_frames())
		for body in combat.bodies_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			Fx.on_combo_hit()   # J5：近战命中上报连击（每目标一次，口径同弹幕）
			if flow_ready:
				flow_skill.note_melee_hit()   # m5-t8 行云：近战命中积「势」
			var proc_element := ElementProc.roll_element(int(element_profile["proc_element"]),
				float(element_profile["proc_chance"]), combat_rng)
			var force_resonance := bool(roll["is_crit"]) \
				and ElementProc.roll_chance(rig.crit_detonate_pct, combat_rng)
			if bool(roll["is_crit"]):
				EventBus.player_crit_landed.emit(roll["amount"], body.global_position)
			body.take_hit({
				"amount": roll["amount"], "is_crit": roll["is_crit"],
				"element": int(element_profile["element"]), "proc_element": proc_element,
				"force_resonance": force_resonance,
				"status_rate_mult": player.effective_status_rate_multiplier(),
				"from": player.global_position,
				"frame": Engine.get_physics_frames(), "source_type": "melee",
				"source_id": String(w.get("id", "")), "source_name": String(w.get("name", "")),
				"attack_name": "近战挥击", "player_damage": true,
			})
			# m4-c2 掠影（刺客被动）：本拍挥击直接击杀（take_hit 后 state==DEAD）→ 上报
			# Player（返蓝+翻滚免冷却窗；被动门控在 Player，非法师/未击杀零副作用）。
			# 披露：击杀归属=挥击直击终结（敌方 status/反伤等间接链不在此路径）。
			if body.get("state") == EnemyBase.State.DEAD:
				player.on_melee_kill(Engine.get_physics_frames())
