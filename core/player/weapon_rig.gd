class_name WeaponRig
extends Node
## 双武器位射击（GDD §8.1）。数值全部来自 GameDB 行。

const SWITCH_LOCK_TICKS := 15      # 0.25s

var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var slots: Array[Dictionary] = []
var slot := 0
var _next_fire_frame := 0
var _switch_until := 0
var _muzzle := Vector2(8, 0)       # 相对玩家，朝向时旋转

func _test_init() -> void:
	slots = [{}, {}]

func equip(weapon_id: String) -> void:
	var w := GameDB.get_weapon(weapon_id)
	if w.is_empty():
		push_error("WeaponRig: unknown weapon %s" % weapon_id)
		return
	if slots.size() < 2:
		slots.resize(2)
	# 填第一个空槽；两槽满则替换当前槽并保留另一槽
	#（brief 代码原为 `slots[slot] = w`，与自身 test_switch_lock 及控制器决议矛盾，按决议修正）。
	var target := slot
	for i in slots.size():
		if slots[i].is_empty():
			target = i
			break
	slots[target] = w

func current() -> Dictionary:
	return slots[slot] if slot < slots.size() else {}

func switch_slot(frame: int) -> void:
	if slots.size() < 2:
		return
	slot = (slot + 1) % 2
	_switch_until = frame + SWITCH_LOCK_TICKS
	_next_fire_frame = frame

func try_fire(aim: Vector2, frame: int) -> bool:
	var w := current()
	if w.is_empty() or w["is_melee"]:
		return false
	if frame < _next_fire_frame or frame < _switch_until:
		return false
	var player := get_parent() as Player
	var cost := int(w["energy_cost"])
	if cost > player.energy:
		return false                     # 空蓝禁远程（GDD §7.2）
	player.energy -= cost
	_next_fire_frame = frame + maxi(1, int(round(TimeConst.FPS / float(w["rate"]))))
	var n := int(w["projectiles"])
	var spread := float(w["spread_deg"])
	var origin: Vector2 = player.global_position + (_muzzle.rotated(aim.angle()))
	for i in n:
		var ang := aim.angle() + deg_to_rad(_fan_offset(n, i, spread)) + deg_to_rad(_jitter(spread))
		_spawn({
			"pos": origin, "vel": Vector2.RIGHT.rotated(ang) * float(w["bullet_speed"]),
			"damage": int(w["damage"]), "faction": Projectile.Faction.PLAYER,
			"element": Elements.from_name(w["element"]), "pierce": int(w["pierce"]),
			"bounce": int(w["bounce"]), "life_seconds": 1.2, "radius": 3.0,
		})
	return true

func _spawn(cfg: Dictionary) -> void:
	combat.spawn_projectile(cfg)         # 测试以子类覆写 _spawn 捕获参数

func _fan_offset(n: int, i: int, spread_deg: float) -> float:
	if n <= 1:
		return 0.0
	var step := spread_deg / float(n - 1)
	return -spread_deg / 2.0 + step * i

func _jitter(spread_deg: float) -> float:
	if combat_rng == null or spread_deg <= 0.0:
		return 0.0
	return combat_rng.randf_range(-spread_deg / 4.0, spread_deg / 4.0)
