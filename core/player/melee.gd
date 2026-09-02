class_name Melee
extends Node
## 近战挥击 + 反弹窗口（GDD §7.4）。挥击 9 ticks；窗口 [3,9]，7 帧 ≈0.12s。

const SWING_TICKS := 9
const PARRY_FROM := 3
const PARRY_TO := 9

var rig: WeaponRig
var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var _swing_left := 0
var _swing_tick := -1
var _hit_done := false
var _next_frame := 0

func _test_init() -> void:
	pass

func try_attack(frame: int) -> bool:
	var w := rig.current()
	if w.is_empty() or not w["is_melee"]:
		return false
	if _swing_left > 0 or frame < _next_frame:
		return false
	var player := get_parent() as Player
	_next_frame = frame + maxi(1, int(round(TimeConst.FPS \
		/ rig.effective_attack_rate(w, player, frame))))
	_swing_left = SWING_TICKS
	_swing_tick = 0
	_hit_done = false
	AudioMgr.play("melee_swing")         # m2-t5：挥击起始音
	return true

func is_parry_tick(tick: int) -> bool:
	return tick >= PARRY_FROM and tick <= PARRY_TO

func _physics_process(_delta: float) -> void:
	if _swing_left <= 0:
		return
	_swing_tick += 1
	_swing_left -= 1
	var player := get_parent() as Player
	var w := rig.current()
	var range_px := float(w.get("range", 40))
	var arc := float(w.get("arc_deg", 90.0))
	if is_parry_tick(_swing_tick):
		for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			# 披露（m4-c2）：反弹伤害镜像武器行原值（GDD §7.4 反弹窗口防御机制），
			# 不走挥击伤害出口聚合点（祝福/天赋乘区不放大反弹面）。
			combat.reflect(p, int(w["damage"]))
	else:
		for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			combat.block(p)
	if not _hit_done:
		_hit_done = true
		# m4-c2：基础伤害走玩家伤害出口聚合点（祝福叠层/天赋乘区，与远程同一口径）。
		var base_damage := player.scaled_damage(int(w["damage"]))
		# 暴击本地 roll；combat_rng 未注入（纯逻辑测试）时跳过 roll 用平伤。
		var roll: Dictionary = {"amount": base_damage, "is_crit": false}
		if combat_rng != null:
			var base_crit := float(player.get_meta("crit_base", 0.05))
			roll = DamageCalc.compute(base_damage, combat_rng,
				player.effective_crit_chance(base_crit), player.effective_crit_multiplier())
		var element_profile := rig.element_hit_profile(w, Engine.get_physics_frames())
		for body in combat.bodies_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			Fx.on_combo_hit()   # J5：近战命中上报连击（每目标一次，口径同弹幕）
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
