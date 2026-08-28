class_name Melee
extends Node
## 近战挥击 + 反弹窗口（GDD §7.4）。挥击 9 ticks；窗口 [3,10]。

const SWING_TICKS := 9
const PARRY_FROM := 3
const PARRY_TO := 10

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
	_next_frame = frame + maxi(1, int(round(TimeConst.FPS / float(w["rate"]))))
	_swing_left = SWING_TICKS
	_swing_tick = 0
	_hit_done = false
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
			combat.reflect(p, int(w["damage"]))
	else:
		for p in combat.projectiles_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			combat.block(p)
	if not _hit_done:
		_hit_done = true
		# 控制器决议：暴击本地 roll；combat_rng 未注入（纯逻辑测试）时跳过 roll 用平伤。
		var roll: Dictionary = {"amount": int(w["damage"]), "is_crit": false}
		if combat_rng != null:
			roll = DamageCalc.compute(int(w["damage"]), combat_rng, 0.05)
		for body in combat.bodies_in_arc(player.global_position, player.facing.angle(), range_px, arc, Projectile.Faction.ENEMY):
			body.take_hit({"amount": roll["amount"], "is_crit": roll["is_crit"], "element": Elements.from_name(w["element"]), "from": player.global_position})
