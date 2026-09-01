class_name WeaponRig
extends Node
## 双武器位射击（GDD §8.1）。数值全部来自 GameDB 行。

const SWITCH_LOCK_TICKS := 15      # 0.25s

var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var slots: Array[Dictionary] = []
var slot := 0
## 正式局注入 RunState 后，武器槽与 T15 聚合字段同源更新；测试/训练房可保持 null。
var run_state: Node = null
var dual_wield_until := -1         # m1-t2 狂潮：frame < 此值时双武器齐射且免蓝（技能写入）
var crit_boost_until := -1         # m1-t5 影袭：必暴状态窗（功能侧掷签在 CombatSystem.forced_crit_until）
var speed_boost_until := -1        # m1-t5 影袭：frame < 此值时弹速 ×1.2（技能写入）
var _next_fire_frame := 0
var _switch_until := 0
var _muzzle := Vector2(8, 0)       # 兼容旧测试/默认；正式射击以武器行 muzzle 为准
# 局内永久增益（BuffManager 写入，正式射击路径消费）。
var enchant_element: int = Elements.Id.NONE  # 附魔元素（Elements.Id）
var enchant_proc_chance: float = 0.0          # 永久附魔在有效命中时的触发概率
var bonus_projectiles: int = 0               # 追加弹丸数（散弹扩张）
var crit_detonate_pct: float = 0.0           # 暴击强制共鸣概率（暴虐回响）
var rate_mult: float = 1.0                   # 攻速倍率（迅捷扳机）
var bullet_speed_mult: float = 1.0           # 弹速倍率（弹速强化）
var temporary_enchant_element: int = Elements.Id.NONE
var temporary_enchant_until := -1

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
	_sync_run_state()

func current() -> Dictionary:
	return slots[slot] if slot < slots.size() else {}

func switch_slot(frame: int) -> void:
	if slots.size() < 2:
		return
	slot = (slot + 1) % 2
	_sync_run_state()
	_switch_until = frame + SWITCH_LOCK_TICKS
	_next_fire_frame = frame

## 清空指定槽的权威入口。设施不得再直接写 slots，否则 RunState 聚合会滞后。
func clear_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var removed: Dictionary = slots[index]
	slots[index] = {}
	_sync_run_state()
	return removed

func bind_run_state(state: Node) -> void:
	run_state = state
	_sync_run_state()

func _sync_run_state() -> void:
	if run_state == null:
		return
	run_state.set("selected_slot", slot)
	for i in slots.size():
		var id := "" if slots[i].is_empty() else String(slots[i].get("id", ""))
		if run_state.has_method("record_weapon"):
			run_state.call("record_weapon", i, id)

func try_fire(aim: Vector2, frame: int) -> bool:
	var w := current()
	if w.is_empty() or w["is_melee"]:
		return false
	if frame < _next_fire_frame or frame < _switch_until:
		return false
	var player := get_parent() as Player
	var dual := frame < dual_wield_until              # 狂潮双持窗（GDD §6）
	var energy_free := frame < player.energy_free_until
	var cost := 0 if dual or energy_free else int(w["energy_cost"])
	if cost > player.energy:
		return false                     # 空蓝禁远程（GDD §7.2）；双持期双武器免蓝
	player.energy -= cost
	var effective_rate := effective_attack_rate(w, player, frame)
	_next_fire_frame = frame + maxi(1, int(round(TimeConst.FPS / effective_rate)))
	_fire_slot(w, aim, false, frame)
	if dual:
		# 副手齐射：镜像枪口（同 aim），副手空/近战则跳过；蓝耗已整体豁免
		var alt := (slot + 1) % 2
		if alt < slots.size():
			var aw: Dictionary = slots[alt]
			if not aw.is_empty() and not aw["is_melee"]:
				_fire_slot(aw, aim, true, frame)
	AudioMgr.play("shoot_player")         # m2-t5：开火成功音（双持齐射仍只一声）
	return true

## 单侧齐射：mirrored 时枪口取反（副手位于朝向另一舷），弹道角与主手同源。
## 影袭速度窗（m1-t5）：frame < speed_boost_until 时弹速 ×1.2。
func _fire_slot(w: Dictionary, aim: Vector2, mirrored: bool, frame: int) -> void:
	var player := get_parent() as Player
	var base_n := int(w["projectiles"])
	# 「散弹扩张」只强化原本就是多弹丸的武器，单发枪不凭空变双发。
	var n := base_n + (bonus_projectiles if base_n > 1 else 0)
	var spread := float(w["spread_deg"])
	var side := -1.0 if mirrored else 1.0
	var muzzle := Vector2(float(w.get("muzzle", _muzzle.x)), 0.0)
	var origin: Vector2 = player.global_position + side * muzzle.rotated(aim.angle())
	Fx.spawn_muzzle_flash(origin, aim.angle(), String(w.get("category", "")))   # J3 枪口焰（M3 J-C，池化）
	var speed := float(w["bullet_speed"]) * bullet_speed_mult
	if frame < speed_boost_until:
		speed *= 1.2
	for i in n:
		var ang := aim.angle() + deg_to_rad(_fan_offset(n, i, spread)) + deg_to_rad(_jitter(spread))
		var element_profile := element_hit_profile(w, frame)
		_spawn({
			"pos": origin, "vel": Vector2.RIGHT.rotated(ang) * speed,
			"damage": talent_scaled_damage(int(w["damage"]), player),
			"faction": Projectile.Faction.PLAYER,
			"element": element_profile["element"], "pierce": int(w["pierce"]),
			"enchant_element": element_profile["proc_element"],
			"enchant_proc_chance": element_profile["proc_chance"],
			"bounce": int(w["bounce"]), "life_seconds": float(w.get("bullet_life", 1.2)),
			"radius": float(w.get("bullet_radius", 3.0)),
			"crit_detonate_pct": crit_detonate_pct,
			"source_type": "weapon", "source_id": String(w.get("id", "")),
			"source_name": String(w.get("name", w.get("id", ""))), "attack_name": "射击",
		})

## m2-t35 天赋伤害乘区（talent_dmg_pct，附录 I.4「同 rate_mult 模式」）：远程落弹伤害
## ×(1+pct)，四舍五入取整。meta 缺省（未 apply/未购）= 原伤害。
## 披露：近战路径（core/player/melee.gd 直读 w["damage"]）不在本卡文件所有权内 → 未接。
func talent_scaled_damage(base_damage: int, player: Player) -> int:
	return int(round(float(base_damage) * (1.0 + player.talent_effect_value("talent_dmg_pct"))))

func _spawn(cfg: Dictionary) -> void:
	combat.spawn_projectile(cfg)         # 测试以子类覆写 _spawn 捕获参数


## 远程与近战共享攻速结算：永久 Buff 与战神像临时倍率相乘。
func effective_attack_rate(w: Dictionary, player: Player, frame: int) -> float:
	var temporary := 1.0 + (player.atk_speed_boost_pct \
		if frame < player.atk_speed_boost_until else 0.0)
	return float(w["rate"]) * rate_mult * temporary


## 远程与近战共享元素契约：
## - 武器原生元素始终是主元素；永久 Buff 是命中时额外 proc；
## - 星髓像为独立 100% 临时覆盖，激活时只使用临时元素且不掷永久 Buff。
func element_hit_profile(w: Dictionary, frame: int) -> Dictionary:
	if frame < temporary_enchant_until and temporary_enchant_element != Elements.Id.NONE:
		return {"element": temporary_enchant_element,
			"proc_element": Elements.Id.NONE, "proc_chance": 0.0}
	return {"element": Elements.from_name(String(w.get("element", "none"))),
		"proc_element": enchant_element, "proc_chance": enchant_proc_chance}

func _fan_offset(n: int, i: int, spread_deg: float) -> float:
	if n <= 1:
		return 0.0
	var step := spread_deg / float(n - 1)
	return -spread_deg / 2.0 + step * i

func _jitter(spread_deg: float) -> float:
	if combat_rng == null or spread_deg <= 0.0:
		return 0.0
	return combat_rng.randf_range(-spread_deg / 4.0, spread_deg / 4.0)
