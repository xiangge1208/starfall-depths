class_name WeaponRig
extends Node
## 双武器位射击（GDD §8.1）。数值全部来自 GameDB 行。

const SWITCH_LOCK_TICKS := 15      # 0.25s

var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var slots: Array[Dictionary] = []
var slot := 0
var dual_wield_until := -1         # m1-t2 狂潮：frame < 此值时双武器齐射且免蓝（技能写入）
var crit_boost_until := -1         # m1-t5 影袭：必暴状态窗（功能侧掷签在 CombatSystem.forced_crit_until）
var speed_boost_until := -1        # m1-t5 影袭：frame < 此值时弹速 ×1.2（技能写入）
var _next_fire_frame := 0
var _switch_until := 0
var _muzzle := Vector2(8, 0)       # 相对玩家，朝向时旋转
# m1-t9 增益接缝（共享基建，声明仅供 BuffManager 写入；默认中性值，射击路径消费属后续任务）
var enchant_element: int = Elements.Id.NONE  # 附魔元素（Elements.Id）
var bonus_projectiles: int = 0               # 追加弹丸数（散弹扩张）
var crit_detonate_pct: float = 0.0           # 暴击强制共鸣概率（暴虐回响）
var rate_mult: float = 1.0                   # 攻速倍率（迅捷扳机）
var bullet_speed_mult: float = 1.0           # 弹速倍率（弹速强化）

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
	var dual := frame < dual_wield_until              # 狂潮双持窗（GDD §6）
	var cost := 0 if dual else int(w["energy_cost"])
	if cost > player.energy:
		return false                     # 空蓝禁远程（GDD §7.2）；双持期双武器免蓝
	player.energy -= cost
	_next_fire_frame = frame + maxi(1, int(round(TimeConst.FPS / float(w["rate"]))))
	_fire_slot(w, aim, false, frame)
	if dual:
		# 副手齐射：镜像枪口（同 aim），副手空/近战则跳过；蓝耗已整体豁免
		var alt := (slot + 1) % 2
		if alt < slots.size():
			var aw: Dictionary = slots[alt]
			if not aw.is_empty() and not aw["is_melee"]:
				_fire_slot(aw, aim, true, frame)
	return true

## 单侧齐射：mirrored 时枪口取反（副手位于朝向另一舷），弹道角与主手同源。
## 影袭速度窗（m1-t5）：frame < speed_boost_until 时弹速 ×1.2。
func _fire_slot(w: Dictionary, aim: Vector2, mirrored: bool, frame: int) -> void:
	var player := get_parent() as Player
	var n := int(w["projectiles"])
	var spread := float(w["spread_deg"])
	var side := -1.0 if mirrored else 1.0
	var origin: Vector2 = player.global_position + side * _muzzle.rotated(aim.angle())
	var speed := float(w["bullet_speed"])
	if frame < speed_boost_until:
		speed *= 1.2
	for i in n:
		var ang := aim.angle() + deg_to_rad(_fan_offset(n, i, spread)) + deg_to_rad(_jitter(spread))
		_spawn({
			"pos": origin, "vel": Vector2.RIGHT.rotated(ang) * speed,
			"damage": int(w["damage"]), "faction": Projectile.Faction.PLAYER,
			"element": Elements.from_name(w["element"]), "pierce": int(w["pierce"]),
			"bounce": int(w["bounce"]), "life_seconds": 1.2, "radius": 3.0,
		})

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
